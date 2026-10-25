// Player sessions (ONLINE_V2.md §1): signature, tampering, expiry, refresh, and the Room-facing verifySession.
import { createExecutionContext, env, waitOnExecutionContext } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import { makeSession, parseSession, verifySession, SESSION_TTL_S } from "../src/accounts";
import worker from "../src/index";
import { DAY, ENV, T0, guest, ok, setAccount, v1 } from "./acc_helpers";

describe("sessions", () => {
  it("a guest session opens /v1/me; no, malformed or tampered sessions get 401", async () => {
    const g = await guest();
    expect(g.session).toMatch(/^acc_[a-z2-7]{16}\.\d+\.[A-Za-z0-9_-]+$/);
    const me = await ok("me", { session: g.session, now: T0 });
    expect(me.account.id).toBe(g.id);
    expect(me.profile.coins).toBe(5000);

    expect((await v1("me", { now: T0 })).status).toBe(401);
    expect((await v1("me", { session: "garbage", now: T0 })).status).toBe(401);
    const [acc, exp, sig] = g.session.split(".");
    // another signature
    const flipped = sig.slice(0, -2) + (sig.endsWith("AA") ? "BB" : "AA");
    expect((await v1("me", { session: `${acc}.${exp}.${flipped}`, now: T0 })).status).toBe(401);
    // a longer expiry with the old signature
    expect((await v1("me", { session: `${acc}.${Number(exp) + 1000}.${sig}`, now: T0 })).status).toBe(401);
    // another account's id with this signature
    const other = await guest();
    expect((await v1("me", { session: `${other.id}.${exp}.${sig}`, now: T0 })).status).toBe(401);
    // the Bearer scheme is required
    const r = await v1("me", { headers: { Authorization: g.session }, now: T0 });
    expect(r.status).toBe(401);
  });

  it("expires after 30 days", async () => {
    const g = await guest({ now: T0 });
    expect((await v1("me", { session: g.session, now: T0 + SESSION_TTL_S - 10 })).status).toBe(200);
    expect((await v1("me", { session: g.session, now: T0 + SESSION_TTL_S })).status).toBe(401);
    expect((await v1("me", { session: g.session, now: T0 + 40 * DAY })).status).toBe(401);
  });

  it("is refreshed on use when less than 7 days are left (X-Session header and me.session)", async () => {
    const g = await guest({ now: T0 });
    const early = await v1("me", { session: g.session, now: T0 + DAY });
    expect(early.headers.get("X-Session")).toBeNull();
    expect(early.body.session).toBe(g.session);

    const late = await v1("me", { session: g.session, now: T0 + 24 * DAY });
    const fresh = late.headers.get("X-Session");
    expect(fresh).toBeTruthy();
    expect(late.body.session).toBe(fresh);
    expect(fresh).not.toBe(g.session);
    // the new one lives 30 days from the refresh; the old one still dies at its own expiry
    expect((await v1("me", { session: fresh!, now: T0 + 50 * DAY })).status).toBe(200);
    expect((await v1("me", { session: g.session, now: T0 + 31 * DAY })).status).toBe(401);
    // other authed endpoints carry the header too
    const r = await v1("rewards", { session: g.session, now: T0 + 25 * DAY });
    expect(r.status).toBe(200);
    expect(r.headers.get("X-Session")).toBeTruthy();
  });

  it("a different SESSION_KEY rejects the session", async () => {
    const tok = await makeSession(ENV, "acc_aaaaaaaaaaaaaaaa", T0 * 1000);
    expect(await parseSession(ENV, tok, T0 * 1000)).toEqual({ account_id: "acc_aaaaaaaaaaaaaaaa", exp: T0 + SESSION_TTL_S });
    expect(await parseSession({ SESSION_KEY: "another key" }, tok, T0 * 1000)).toBeNull();
    expect(await parseSession({}, tok, T0 * 1000)).toBeNull();
  });

  it("without SESSION_KEY the account endpoints answer 503 accounts_disabled", async () => {
    const e = { ...(env as object), SESSION_KEY: undefined };
    for (const [path, method] of [["/v1/auth/guest", "POST"], ["/v1/me", "GET"], ["/v1/shop/buy", "POST"]] as const) {
      const ctx = createExecutionContext();
      const r = await worker.fetch(new Request(`https://x${path}`, { method, body: method === "POST" ? JSON.stringify({ pid: "x".repeat(20) }) : undefined }), e as never, ctx);
      await waitOnExecutionContext(ctx);
      expect(r.status, path).toBe(503);
      expect(((await r.json()) as { error: string }).error).toBe("accounts_disabled");
    }
  });
});

describe("verifySession (Room / quick match)", () => {
  it("valid -> {account_id}; tampered, unknown, banned, merged -> null", async () => {
    const g = await guest();
    expect(await verifySession(ENV, g.session)).toEqual({ account_id: g.id });
    expect(await verifySession(ENV, g.session + "x")).toBeNull();
    expect(await verifySession(ENV, "")).toBeNull();
    expect(await verifySession(ENV, await makeSession(ENV, "acc_zzzzzzzzzzzzzzzz"))).toBeNull(); // no such account
    await setAccount(g.id, { banned: 1, ban_reason: "cheating" });
    expect(await verifySession(ENV, g.session)).toBeNull();
    const r = await v1("me", { session: g.session });
    expect(r.status).toBe(403);
    expect(r.body).toMatchObject({ error: "banned" });
    expect(r.body.msg).toContain("cheating");

    const h = await guest();
    await setAccount(h.id, { merged_into: g.id });
    expect(await verifySession(ENV, h.session)).toBeNull();
  });
});
