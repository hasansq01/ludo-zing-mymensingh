// GET /v1/leaderboard: ordering, ties, the caller's rank, ISO weeks in Bangladesh time (rollover), the wins board
// from online matches, banned / merged accounts left out, only accounts with 3 completed matches listed, the 30 s
// cache.
import { describe, expect, it } from "vitest";
import { grantOnlineMatch } from "../src/accounts";
import { isoWeek, weekPeriod } from "../src/econ";
import { MIN_MATCHES } from "../src/leaderboard";
import { DAY, ENV, T0, type Json, guest, ludoClaim, ok, row, setAccount, v1 } from "./acc_helpers";

const S = (ms: number) => Math.floor(ms / 1000);

/** Gives the account `n` Ludo wins vs Computer (100 XP each) from `now`, 181 s apart (under the hourly claim cap). */
async function wins(session: string, n: number, now: number, result: "win" | "loss" = "win"): Promise<void> {
  for (let k = 0; k < n; k++) {
    const r = await ok("claims", { session, body: ludoClaim(result), now: now + k * 181 });
    expect(r.granted && !r.limited).toBe(true);
  }
}

describe("ISO weeks in Bangladesh time", () => {
  it("weeks start Monday 00:00 in Bangladesh (Sunday 18:00 UTC)", () => {
    const sunday = S(Date.UTC(2026, 9, 25, 17, 59, 59)); // Sunday 23:59:59 BD
    expect(isoWeek(sunday)).toBe("2026-W43");
    expect(isoWeek(sunday + 1)).toBe("2026-W44");
    expect(weekPeriod(T0)).toBe("week:2026-W43");
    expect(isoWeek(S(Date.UTC(2027, 0, 1, 12)))).toBe("2026-W53");
    expect(isoWeek(S(Date.UTC(2027, 0, 3, 17)))).toBe("2026-W53");
    expect(isoWeek(S(Date.UTC(2027, 0, 3, 18)))).toBe("2027-W01");
    expect(isoWeek(S(Date.UTC(2025, 11, 29, 12)))).toBe("2026-W01");
    expect(isoWeek(S(Date.UTC(2024, 11, 31, 12)))).toBe("2025-W01");
    // UTC weeks on request
    expect(isoWeek(S(Date.UTC(2027, 0, 3, 18)), 0)).toBe("2026-W53");
  });
});

describe("leaderboard", () => {
  it("XP all time: top list in order with ranks, ties share a rank, me = my rank", async () => {
    const [a, b, c, d] = await Promise.all([guest(), guest(), guest(), guest()]);
    await setAccount(a.id, { name: "LB Alpha" });
    await wins(a.session, 3, T0);
    await wins(b.session, 3, T0, "loss"); // 3 x 40 XP
    await wins(c.session, 3, T0 + 100); // ties with a, reached later
    const r = await ok("leaderboard?board=xp&period=all&nocache=1", { session: b.session, now: T0 + 2000 });
    expect(r.board).toBe("xp");
    expect(r.period).toBe("all");
    expect(r.min_matches).toBe(MIN_MATCHES);
    const mine = r.top.filter((x: { value: number }) => x.value === 300 || x.value === 120);
    expect(mine.slice(0, 3).map((x: { value: number }) => x.value)).toEqual([300, 300, 120]);
    const ia = r.top.findIndex((x: { name: string }) => x.name === "LB Alpha");
    expect(r.top[ia]).toMatchObject({ value: 300, level: 3, avatar: "pawn-red", frame: "classic" });
    expect(r.top[ia + 1].rank).toBe(r.top[ia].rank); // tie: same rank, a first (reached it earlier)
    expect(r.top[ia + 2].rank).toBe(r.top[ia].rank + 2);
    expect(r.me).toEqual({ rank: r.top[ia].rank + 2, value: 120, listed: true });
    expect(r.top[0]).not.toHaveProperty("account_id");
    // no XP: no rank
    expect((await ok("leaderboard?board=xp&period=all&nocache=1", { session: d.session, now: T0 + 200 })).me).toEqual({ rank: null, value: 0, listed: false });
    // no session: me null
    expect((await ok("leaderboard?board=xp&period=all&nocache=1", { now: T0 })).me).toBeNull();
    // ranks are dense from the top
    expect(r.top[0].rank).toBe(1);
    for (let i = 1; i < r.top.length; i++) expect(r.top[i].value).toBeLessThanOrEqual(r.top[i - 1].value);
  });

  it("the weekly XP board rolls over on Monday (Bangladesh), the all-time board keeps counting", async () => {
    const a = await guest();
    await wins(a.session, 2, T0);
    const w = await ok("leaderboard?board=xp&period=week&nocache=1", { session: a.session, now: T0 + 10 });
    expect(w.week).toBe("2026-W43");
    expect(w.me.value).toBe(200);
    expect(w.me.rank).toBeGreaterThanOrEqual(1);
    const next = await ok("leaderboard?board=xp&period=week&nocache=1", { session: a.session, now: T0 + 5 * DAY });
    expect(next.week).toBe("2026-W44");
    expect(next.me).toEqual({ rank: null, value: 0, listed: false });
    await wins(a.session, 1, T0 + 5 * DAY);
    expect((await ok("leaderboard?board=xp&period=week&nocache=1", { session: a.session, now: T0 + 5 * DAY + 10 })).me).toEqual({ rank: 1, value: 100, listed: true });
    expect((await ok("leaderboard?board=xp&period=all&nocache=1", { session: a.session, now: T0 + 5 * DAY + 10 })).me.value).toBe(300);
  });

  it("the wins board counts online wins (grantOnlineMatch), not offline ones", async () => {
    const [a, b] = await Promise.all([guest(), guest()]);
    await wins(a.session, 2, T0); // offline: not on the wins board
    const now = Date.now();
    await grantOnlineMatch(ENV, { match_id: `lbm1-${a.id}`, game: "ludo", results: [{ account_id: a.id, outcome: "win" }, { account_id: b.id, outcome: "finish" }] });
    await grantOnlineMatch(ENV, { match_id: `lbm2-${a.id}`, game: "sl", results: [{ account_id: b.id, outcome: "win" }, { account_id: a.id, outcome: "left" }] });
    await grantOnlineMatch(ENV, { match_id: `lbm3-${a.id}`, game: "ludo", results: [{ account_id: b.id, outcome: "win" }] });
    const nowS = Math.floor(now / 1000);
    const ra = await ok("leaderboard?board=wins&period=all&nocache=1", { session: a.session, now: nowS });
    const rb = await ok("leaderboard?board=wins&period=week&nocache=1", { session: b.session, now: nowS });
    expect(ra.me.value).toBe(1);
    expect(rb.me.value).toBe(2);
    expect(rb.me.rank).toBeLessThan(ra.me.rank);
  });

  it("banned and merged accounts are left out of the boards and the ranks", async () => {
    const [a, b, c] = await Promise.all([guest(), guest(), guest()]);
    await setAccount(a.id, { name: "LB Banned" });
    await setAccount(b.id, { name: "LB Merged" });
    await wins(a.session, 30, T0 - 10 * DAY); // a lot of XP
    await wins(b.session, 30, T0 - 10 * DAY);
    await wins(c.session, 29, T0 - 10 * DAY);
    const before = await ok("leaderboard?board=xp&period=all&nocache=1", { session: c.session, now: T0 });
    await setAccount(a.id, { banned: 1 });
    await setAccount(b.id, { merged_into: c.id });
    const after = await ok("leaderboard?board=xp&period=all&nocache=1", { session: c.session, now: T0 });
    expect(after.top.map((x: { name: string }) => x.name)).not.toContain("LB Banned");
    expect(after.top.map((x: { name: string }) => x.name)).not.toContain("LB Merged");
    expect(after.me.rank).toBe(before.me.rank - 2);
  });

  it("validates board and period", async () => {
    expect((await v1("leaderboard?board=coins")).status).toBe(400);
    expect((await v1("leaderboard?period=month")).status).toBe(400);
    expect((await v1("leaderboard", { method: "POST" })).status).toBe(405);
    expect((await ok("leaderboard")).board).toBe("xp");
  });

  it("caches the top list for 30 s (me stays live)", async () => {
    const a = await guest();
    await setAccount(a.id, { completed_matches: 2 }); // the online match below is its 3rd
    const p = "leaderboard?board=wins&period=week";
    const nowS = Math.floor(Date.now() / 1000);
    const first = await ok(p, { session: a.session, now: nowS });
    await grantOnlineMatch(ENV, { match_id: `lbcache-${a.id}`, game: "ludo", results: [{ account_id: a.id, outcome: "win" }] });
    await new Promise((r) => setTimeout(r, 100));
    const second = await ok(p, { session: a.session, now: nowS });
    expect(second.top).toEqual(first.top);
    expect(second.me.value).toBe(1);
    const fresh = await ok(`${p}&nocache=1`, { session: a.session, now: nowS });
    expect(fresh.top.length).toBe(first.top.length + 1);
  });

  it("lists only accounts with 3 completed matches; the others still get their own rank", async () => {
    const [a, b] = await Promise.all([guest(), guest()]);
    await setAccount(a.id, { name: "LB Newcomer" });
    await setAccount(b.id, { name: "LB Regular" });
    await wins(b.session, 3, T0 - 20 * DAY);
    // a: one huge online win (its only completed match) and an early leave (not completed)
    await grantOnlineMatch(ENV, { match_id: `lbmin1-${a.id}`, game: "ludo", results: [{ account_id: a.id, outcome: "win" }] });
    await grantOnlineMatch(ENV, { match_id: `lbmin2-${a.id}`, game: "sl", results: [{ account_id: a.id, outcome: "left" }] });
    await wins(a.session, 1, T0 - 20 * DAY); // 2 completed
    expect(await row("SELECT completed_matches FROM accounts WHERE id = ?", a.id)).toEqual({ completed_matches: 2 });
    const xpOf = async (s: string) => ok("leaderboard?board=xp&period=all&nocache=1", { session: s, now: T0 });
    let r = await xpOf(a.session);
    const names = (x: Json) => x.top.map((t: { name: string }) => t.name);
    expect(names(r)).not.toContain("LB Newcomer");
    expect(names(r)).toContain("LB Regular");
    // its own rank counts only listed accounts ahead of it: 200 XP (online win 100 + claim 100) is behind b's 300
    const ib = r.top.findIndex((t: { name: string }) => t.name === "LB Regular");
    const ahead = r.top.filter((t: { value: number }) => t.value > 200).length;
    expect(r.top[ib].value).toBe(300);
    expect(r.me).toEqual({ rank: ahead + 1, value: 200, listed: false });
    // the wins board too
    const w = await ok("leaderboard?board=wins&period=all&nocache=1", { session: a.session, now: S(Date.now()) });
    expect(w.me).toMatchObject({ value: 1, listed: false });
    expect(w.top.map((t: { name: string }) => t.name)).not.toContain("LB Newcomer");
    // the 3rd completed match lists it
    await wins(a.session, 1, T0 - 19 * DAY, "loss");
    r = await xpOf(a.session);
    expect(names(r)).toContain("LB Newcomer");
    expect(r.me).toMatchObject({ value: 240, listed: true });
    expect(r.top.find((t: { name: string }) => t.name === "LB Newcomer").rank).toBe(r.me.rank);
  });
});
