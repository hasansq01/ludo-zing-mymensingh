// POST /v1/auth/guest rate limit (policy, lead 2026-10-24): at most 20 new guest accounts per client IP per hour
// and 60 per day (generous: carrier-grade NAT); over -> 429 {error: "rate"}. Opening an existing pid's account is
// never limited. IPv6 counts per /64. Only an HMAC of the IP is stored.
import { describe, expect, it } from "vitest";
import { GUEST_LIMITS, ipBucket } from "../src/accounts";
import { T0, guest, newPid, rows, v1 } from "./acc_helpers";

const HOUR = 3600;

function create(ip: string | null, now: number, pid = newPid("rate")) {
  return v1("auth/guest", { body: { pid }, now, headers: ip ? { "CF-Connecting-IP": ip } : {} });
}

async function createN(ip: string, now: number, n: number): Promise<string[]> {
  const pids: string[] = [];
  for (let k = 0; k < n; k++) {
    const pid = newPid("rate");
    const r = await create(ip, now + k, pid);
    expect(r.status, `${ip} #${k}: ${JSON.stringify(r.body)}`).toBe(200);
    expect(r.body.created).toBe(true);
    pids.push(pid);
  }
  return pids;
}

describe("guest account creation per IP", () => {
  it("20 per hour, 60 per day; existing pids are never limited", async () => {
    expect(GUEST_LIMITS).toEqual({ per_hour: 20, per_day: 60 });
    const ip = "198.51.100.7";
    const first = await createN(ip, T0, 20);
    const over = await create(ip, T0 + 30);
    expect(over.status).toBe(429);
    expect(over.body).toEqual({ error: "rate" });
    // the device that was refused, and one that already has an account, can still open accounts
    const back = await create(ip, T0 + 40, first[0]);
    expect(back.status).toBe(200);
    expect(back.body.created).toBe(false);
    // another IP is not affected
    expect((await create("198.51.100.8", T0 + 50)).status).toBe(200);
    // an hour later: another 20, twice, reaching the day's 60
    await createN(ip, T0 + HOUR + 1, 20);
    expect((await create(ip, T0 + HOUR + 100)).status).toBe(429);
    await createN(ip, T0 + 2 * HOUR + 1, 20);
    // a fresh hour, but the day is full
    const day = await create(ip, T0 + 3 * HOUR + 1);
    expect(day.status).toBe(429);
    expect(day.body).toEqual({ error: "rate" });
    // 24 h after the first ones, they no longer count
    expect((await create(ip, T0 + 24 * HOUR + 30)).status).toBe(200);
    // the stored key is not the IP
    const stored = await rows<{ ip: string }>("SELECT DISTINCT ip FROM guest_creations");
    expect(stored.length).toBeGreaterThanOrEqual(2);
    for (const r of stored) expect(r.ip).not.toContain("198.51");
  });

  it("IPv6 addresses count per /64; requests without CF-Connecting-IP are not limited", async () => {
    await createN("2001:db8:1:2::10", T0, 10);
    await createN("2001:0db8:0001:0002:ffff:0:0:1", T0 + 20, 10);
    expect((await create("2001:db8:1:2:abcd::99", T0 + 40)).status).toBe(429);
    expect((await create("2001:db8:1:3::10", T0 + 41)).status).toBe(200);
    // local tools / tests (Cloudflare always sets the header)
    for (let k = 0; k < 25; k++) await guest({ now: T0 + 100 + k });
  });

  it("ipBucket: IPv4 as is, IPv6 by its first 64 bits", () => {
    expect(ipBucket("203.0.113.9")).toBe("203.0.113.9");
    expect(ipBucket("2001:db8:1:2::10")).toBe("2001:db8:1:2::/64");
    expect(ipBucket("2001:0db8:0001:0002:ffff:0:0:1")).toBe("2001:db8:1:2::/64");
    expect(ipBucket("::1")).toBe("0:0:0:0::/64");
    expect(ipBucket("fe80::1:2:3:4")).toBe("fe80:0:0:0::/64");
    expect(ipBucket("2001:db8::")).toBe("2001:db8:0:0::/64");
  });
});
