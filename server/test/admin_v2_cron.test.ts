// The daily cron's v2 work (src/cron.ts): weekly leaderboard rows pruned after 26 weeks, guest-creation rows after a
// day, and the sweep of rooms whose D1 row still says lobby / playing 2 h after its last update (gone: row closed;
// nobody online: the Room is closed through adminClose "stale-sweep"; someone online: left alone).
import { describe, expect, it } from "vitest";
import { cron } from "../src/cron";
import type { Env } from "../src/room";
import { DB, eventually, row, rows } from "./admin_helpers";
import { Client, E, createRoom, roomInfo } from "./room_client";

/** Wednesday 2026-10-21 12:00 in Bangladesh: week 2026-W43; 26 weeks back is 2026-W17. */
const NOW = Date.UTC(2026, 9, 21, 6, 0, 0);
const HOUR = 3600_000;

async function score(account: string, period: string): Promise<void> {
  await DB.prepare("INSERT INTO scores (account_id, board, period, value, updated_at) VALUES (?, 'xp', ?, 10, 0)").bind(account, period).run();
}

/** Makes the room's D1 row look untouched since `at` (after the Room's own first write landed). */
async function ageRow(code: string, status: string, at: number): Promise<void> {
  await eventually(() => row("SELECT code FROM rooms WHERE code = ?", code), 5000, "rooms row");
  await DB.prepare("UPDATE rooms SET status = ?, updated_at = ? WHERE code = ?").bind(status, at, code).run();
}

describe("cron: pruning", () => {
  it("drops weekly scores older than 26 weeks (all-time rows stay) and guest-creation rows older than a day", async () => {
    const acc = "acc_cronprune";
    for (const p of ["all", "week:2025-W52", "week:2026-W16", "week:2026-W17", "week:2026-W43"]) await score(acc, p);
    await DB.batch([
      DB.prepare("INSERT INTO guest_creations (ip, at) VALUES ('cron-ip-old', ?)").bind(Date.now() - 25 * HOUR),
      DB.prepare("INSERT INTO guest_creations (ip, at) VALUES ('cron-ip-new', ?)").bind(Date.now() - HOUR),
    ]);
    const res = await cron(E as Env, NOW);
    expect(res.pruned.scores).toBe(2);
    expect((await rows<{ period: string }>("SELECT period FROM scores WHERE account_id = ? ORDER BY period", acc)).map((r) => r.period)).toEqual([
      "all",
      "week:2026-W17",
      "week:2026-W43",
    ]);
    // guest_creations are pruned against the real clock of the rows (now - 1 day)
    const res2 = await cron(E as Env);
    expect(res2.pruned.guest_creations).toBeGreaterThanOrEqual(1);
    expect((await rows<{ ip: string }>("SELECT ip FROM guest_creations WHERE ip LIKE 'cron-ip-%'")).map((r) => r.ip)).toEqual(["cron-ip-new"]);
  });
});

describe("cron: stale rooms", () => {
  it("closes a lobby room nobody is in after 2 h without updates (stale-sweep)", async () => {
    const code = await createRoom();
    expect((await roomInfo(code)).status).toBe(200);
    await ageRow(code, "lobby", Date.now() - 2 * HOUR - 60_000);
    const res = await cron(E as Env);
    expect(res.swept).toBeGreaterThanOrEqual(1);
    expect((await roomInfo(code)).status).toBe(404);
    expect(await row("SELECT status, closed_reason FROM rooms WHERE code = ?", code)).toEqual({ status: "closed", closed_reason: "stale-sweep" });
  });

  it("leaves a room with someone connected alone, and rows updated less than 2 h ago", async () => {
    const code = await createRoom();
    const c = await Client.join(code, { name: "Still here" });
    await c.waitFor((m) => m.t === "lobby");
    await ageRow(code, "lobby", Date.now() - 3 * HOUR);
    const fresh = await createRoom();
    await ageRow(fresh, "lobby", Date.now() - HOUR);
    await cron(E as Env);
    expect((await roomInfo(code)).status).toBe(200);
    expect((await roomInfo(fresh)).status).toBe(200);
    expect((await row("SELECT status FROM rooms WHERE code = ?", code))!.status).toBe("lobby");
    c.close();
  });

  it("a row whose room is gone is closed 'gone' (its match abandoned); an 'over' room that exists is left to its alarm", async () => {
    const t = Date.now() - 2 * HOUR - 1000;
    await DB.batch([
      DB.prepare("INSERT INTO rooms (code, created_at, updated_at, status, members, online, settings) VALUES ('CRNGNE', ?, ?, 'lobby', 1, 1, '{}')").bind(t, t),
      DB.prepare("INSERT INTO matches (code, started_at, players, result) VALUES ('CRNGNE', ?, '[]', 'playing')").bind(t),
    ]);
    const over = await createRoom();
    await ageRow(over, "over", t);
    const res = await cron(E as Env);
    expect(res.reconciled).toBeGreaterThanOrEqual(1);
    expect(await row("SELECT status, closed_reason FROM rooms WHERE code = 'CRNGNE'")).toEqual({ status: "closed", closed_reason: "gone" });
    expect((await row("SELECT result FROM matches WHERE code = 'CRNGNE'"))!.result).toBe("abandoned");
    expect((await roomInfo(over)).status).toBe(200);
  });
});
