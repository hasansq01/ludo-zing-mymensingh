// POST /v1/claims (offline matches): what the offline game pays, idempotency by client id, the limits of the
// Economy decisions (too short and the hourly cap pay 0; 6,000 coins and 3,000 XP per Bangladesh day pay the
// remainder), S&L wins verified by replaying the rolls, and concurrency.
import { describe, expect, it } from "vitest";
import { land, replayReaches100 } from "../src/rules/sl";
import { DAY, T0, type Json, claimId, guest, ledgerSum, ludoClaim, ok, row, rows, v1 } from "./acc_helpers";
import { DB } from "./acc_helpers";

/** Bangladesh day start of T0 (2026-10-21 00:00 BD = 2026-10-20 18:00 UTC), ms. */
const DAY_START_MS = (T0 - 12 * 3600) * 1000;

/** Rolls that take one pawn from square 0 to exactly 100 (never three 6s in a row). */
function winningRolls(): number[] {
  for (;;) {
    const rolls: number[] = [];
    let pos = 0;
    let sixes = 0;
    while (pos !== 100 && rolls.length < 400) {
      let v = 1 + Math.floor(Math.random() * 6);
      if (v === 6 && sixes === 2) v = 5;
      if (pos + v > 100) v = 100 - pos <= 6 && 100 - pos >= 1 ? 100 - pos : v;
      sixes = v === 6 ? sixes + 1 : 0;
      rolls.push(v);
      pos = land(pos, v).to;
    }
    if (pos === 100 && replayReaches100(rolls)) return rolls;
  }
}

/** Earlier claims of the account (test setup): `coins` / `xp` already paid today, or `n` granted claims at `at`. */
async function seedClaims(account: string, list: { at: number; coins?: number; xp?: number; granted?: number }[]): Promise<void> {
  await DB.batch(
    list.map((c) =>
      DB.prepare("INSERT INTO claims (id, account_id, at, game, coins, xp, granted, limited) VALUES (?, ?, ?, 'ludo', ?, ?, ?, 0)").bind(
        claimId(),
        account,
        c.at,
        c.coins ?? 0,
        c.xp ?? 0,
        c.granted ?? 1,
      ),
    ),
  );
}

describe("claims", () => {
  it("pays a Ludo win vs Computer like the offline game (200 coins, 100 XP, wins / streak)", async () => {
    const a = await guest();
    const c = ludoClaim("win", { pairs: 2, xp: 99999 });
    const r = await ok("claims", { session: a.session, body: c, now: T0 });
    expect(r).toMatchObject({ ok: true, id: c.id, limited: false, granted: true, coins: 200, xp: 100 });
    expect(r.profile).toMatchObject({ coins: 2700, xp: 100 });
    expect(r.profile.stats).toMatchObject({ played: 1, wins: 1, streak: 1, bestStreak: 1, pairsFormed: 2, coinsEarned: 200 });
    expect(await rows("SELECT reason, ref, delta_coins, delta_xp FROM ledger WHERE account_id = ? AND reason = 'claim'", a.id)).toEqual([
      { reason: "claim", ref: c.id, delta_coins: 200, delta_xp: 100 },
    ]);
    const loss = await ok("claims", { session: a.session, body: ludoClaim("loss"), now: T0 + 400 });
    expect(loss).toMatchObject({ coins: 20, xp: 40 });
    expect(loss.profile.stats).toMatchObject({ played: 2, wins: 1, losses: 1, streak: 0 });
    const pp = await ok("claims", { session: a.session, body: { id: claimId(), game: "ludo", mode: "pp", result: "win", players: 3, duration_s: 600 }, now: T0 + 800 });
    expect(pp).toMatchObject({ coins: 0, xp: 30 });
    expect(pp.profile.stats.ppGames).toBe(1);
  });

  it("is idempotent by client id (a retry returns the first answer, pays nothing more)", async () => {
    const a = await guest();
    const c = ludoClaim("win");
    const first = await ok("claims", { session: a.session, body: c, now: T0 });
    const again = await ok("claims", { session: a.session, body: { ...c, result: "loss" }, now: T0 + 5 });
    expect(again).toMatchObject({ duplicate: true, id: c.id, coins: 200, xp: 100, limited: false });
    expect(again.profile.coins).toBe(first.profile.coins);
    expect(await rows("SELECT id FROM claims WHERE account_id = ?", a.id)).toHaveLength(1);
    // the same id from another account is a separate claim
    const b = await guest();
    expect((await ok("claims", { session: b.session, body: c, now: T0 })).duplicate).toBeUndefined();
  });

  it("parallel retries of one claim pay once", async () => {
    const a = await guest();
    const c = ludoClaim("win");
    const rs = await Promise.all([0, 1, 2, 3].map(() => v1("claims", { session: a.session, body: c, now: T0 })));
    for (const r of rs) expect(r.status, JSON.stringify(r.body)).toBe(200);
    expect(rs.filter((r) => r.body.duplicate)).toHaveLength(3);
    expect((await ok("me", { session: a.session })).profile.coins).toBe(2700);
    expect(await ledgerSum(a.id)).toBe(2700);
  });

  it("too short and malformed claims", async () => {
    const a = await guest();
    const short = await ok("claims", { session: a.session, body: ludoClaim("win", { duration_s: 59 }), now: T0 });
    expect(short).toMatchObject({ limited: true, granted: false, reason: "too_short", coins: 0, xp: 0, would: { coins: 200, xp: 100 } });
    expect(short.profile.stats.played).toBe(0);
    const sl = await ok("claims", { session: a.session, body: { id: claimId(), game: "sl", mode: "cpu", result: "loss", duration_s: 29 }, now: T0 });
    expect(sl.reason).toBe("too_short");
    expect((await row("SELECT limited, granted, reason FROM claims WHERE account_id = ? AND id = ?", a.id, short.id))).toEqual({ limited: 1, granted: 0, reason: "too_short" });
    for (const bad of [
      { game: "chess", duration_s: 100 },
      { game: "ludo", mode: "cpu", result: "win", players: ["human"], duration_s: 100 },
      { game: "ludo", mode: "cpu", result: "win", players: 4, duration_s: -1 },
      { game: "sl", mode: "online", result: "win", duration_s: 100 },
    ]) {
      const r = await v1("claims", { session: a.session, body: { id: claimId(), ...bad }, now: T0 });
      expect(r.status, JSON.stringify(bad)).toBe(400);
      expect(r.body.error).toBe("invalid");
    }
    for (const id of [undefined, "short", "x".repeat(65), "bad id!!"]) {
      expect((await v1("claims", { session: a.session, body: { ...ludoClaim("win"), id } })).status).toBe(400);
    }
    expect((await ok("me", { session: a.session })).profile.coins).toBe(2500);
  });

  it("S&L: a win vs Computer pays 100 only when its rolls replay to 100; a loss pays 10; no XP", async () => {
    const a = await guest();
    const base = { game: "sl", mode: "cpu", players: 2, duration_s: 120 };
    const noRolls = await ok("claims", { session: a.session, body: { id: claimId(), ...base, result: "win" }, now: T0 });
    expect(noRolls).toMatchObject({ limited: true, granted: false, reason: "replay", coins: 0, would: { coins: 100, xp: 0 } });
    const bad = await ok("claims", { session: a.session, body: { id: claimId(), ...base, result: "win", rolls: [6, 6, 6, 6, 6] }, now: T0 });
    expect(bad.reason).toBe("replay");
    const good = await ok("claims", { session: a.session, body: { id: claimId(), ...base, result: "win", rolls: winningRolls() }, now: T0 });
    expect(good).toMatchObject({ limited: false, granted: true, coins: 100, xp: 0 });
    expect(good.profile.stats).toMatchObject({ slPlayed: 1, slWins: 1 });
    const loss = await ok("claims", { session: a.session, body: { id: claimId(), ...base, result: "loss" }, now: T0 });
    expect(loss).toMatchObject({ coins: 10, granted: true });
    const local = await ok("claims", { session: a.session, body: { id: claimId(), game: "sl", mode: "local", result: "win", duration_s: 60 }, now: T0 });
    expect(local).toMatchObject({ coins: 0, xp: 0, granted: true, limited: false });
    expect(local.profile.stats.slPlayed).toBe(3);
  });
});

describe("claim limits", () => {
  it("the daily coin cap pays the remainder, then nothing; XP is capped at 3,000 a day", async () => {
    const a = await guest();
    await seedClaims(a.id, [{ at: DAY_START_MS + 1000, coins: 5820, xp: 2940, granted: 1 }]);
    const p1 = await ok("claims", { session: a.session, body: ludoClaim("win"), now: T0 });
    expect(p1).toMatchObject({ granted: true, limited: true, reason: "daily_coins", coins: 180, xp: 60, would: { coins: 200, xp: 100 } });
    expect(p1.profile).toMatchObject({ coins: 2680, xp: 60 });
    expect(p1.profile.stats).toMatchObject({ wins: 1, coinsEarned: 180 });
    const p2 = await ok("claims", { session: a.session, body: ludoClaim("win"), now: T0 + 1 });
    expect(p2).toMatchObject({ granted: false, limited: true, reason: "daily_coins", coins: 0, xp: 0 });
    expect(p2.profile.stats.wins).toBe(1);
    // the next Bangladesh day the caps start again
    const p3 = await ok("claims", { session: a.session, body: ludoClaim("win"), now: T0 + 12 * 3600 });
    expect(p3).toMatchObject({ granted: true, limited: false, coins: 200, xp: 100 });
    expect(await ledgerSum(a.id)).toBe(2500 + 180 + 200);
  });

  it("XP alone hits the cap: a Pass & Play claim pays the XP remainder", async () => {
    const a = await guest();
    await seedClaims(a.id, [{ at: DAY_START_MS + 5, coins: 0, xp: 2990 }]);
    const r = await ok("claims", { session: a.session, body: { id: claimId(), game: "ludo", mode: "pp", result: "win", players: 2, duration_s: 100 }, now: T0 });
    expect(r).toMatchObject({ granted: true, limited: true, reason: "daily_xp", coins: 0, xp: 10, would: { coins: 0, xp: 30 } });
    const s = await ok("claims", { session: a.session, body: ludoClaim("loss"), now: T0 + 1 });
    expect(s).toMatchObject({ granted: true, limited: true, reason: "daily_xp", coins: 20, xp: 0 });
  });

  it("claims from yesterday (Bangladesh day) do not count", async () => {
    const a = await guest();
    await seedClaims(a.id, [{ at: DAY_START_MS - 1000, coins: 6000, xp: 3000 }]);
    expect(await ok("claims", { session: a.session, body: ludoClaim("win"), now: T0 })).toMatchObject({ limited: false, coins: 200 });
  });

  it("more than 20 granted claims in an hour pay 0 (limited claims don't count)", async () => {
    const a = await guest();
    const at = T0 * 1000 - 30 * 60_000;
    await seedClaims(a.id, [
      ...Array.from({ length: 20 }, () => ({ at, coins: 0, xp: 0, granted: 1 })),
      ...Array.from({ length: 5 }, () => ({ at, granted: 0 })),
    ]);
    const r = await ok("claims", { session: a.session, body: ludoClaim("win"), now: T0 });
    expect(r).toMatchObject({ limited: true, granted: false, reason: "hourly", coins: 0 });
    // 31 minutes later those 20 are more than an hour old
    expect(await ok("claims", { session: a.session, body: ludoClaim("win"), now: T0 + 31 * 60 })).toMatchObject({ limited: false, coins: 200 });
  });

  it("parallel claims can't pass the hourly cap together", async () => {
    const a = await guest();
    await seedClaims(a.id, Array.from({ length: 19 }, () => ({ at: T0 * 1000 - 60_000 })));
    const rs = await Promise.all([0, 1, 2, 3].map(() => v1("claims", { session: a.session, body: ludoClaim("win"), now: T0 })));
    const bodies: Json[] = rs.map((r) => r.body);
    expect(bodies.filter((b) => b.granted)).toHaveLength(1);
    expect(bodies.filter((b) => b.reason === "hourly")).toHaveLength(3);
    expect((await ok("me", { session: a.session })).profile.coins).toBe(2700);
  });

  it("claims are refused for a banned account and without a session", async () => {
    const a = await guest();
    expect((await v1("claims", { body: ludoClaim("win") })).status).toBe(401);
    await DB.prepare("UPDATE accounts SET banned = 1 WHERE id = ?").bind(a.id).run();
    expect((await v1("claims", { session: a.session, body: ludoClaim("win") })).status).toBe(403);
  });

  it("granted claims (also cut ones) count as completed matches; claims paying nothing don't", async () => {
    const a = await guest();
    const done = async () => (await row<{ n: number }>("SELECT completed_matches AS n FROM accounts WHERE id = ?", a.id))!.n;
    await ok("claims", { session: a.session, body: ludoClaim("win"), now: T0 });
    await ok("claims", { session: a.session, body: ludoClaim("win", { duration_s: 10 }), now: T0 + 1 }); // too short
    expect(await done()).toBe(1);
    await seedClaims(a.id, [{ at: DAY_START_MS + 1000, coins: 5790, xp: 0 }]); // 5,990 coins today
    expect(await ok("claims", { session: a.session, body: ludoClaim("loss"), now: T0 + 2 })).toMatchObject({ granted: true, limited: true, coins: 10, xp: 40 });
    expect(await ok("claims", { session: a.session, body: ludoClaim("win"), now: T0 + 3 })).toMatchObject({ granted: true, limited: true, coins: 0, xp: 100 });
    expect(await done()).toBe(3);
    await seedClaims(a.id, [{ at: DAY_START_MS + 2000, coins: 0, xp: 2760 }]); // 3,000 XP today
    expect(await ok("claims", { session: a.session, body: ludoClaim("win"), now: T0 + 4 })).toMatchObject({ granted: false, reason: "daily_coins" });
    expect(await done()).toBe(3);
    expect((await ok("me", { session: a.session })).account.completed_matches).toBe(3);
  });

  it("the week's XP board counts claim XP (capped)", async () => {
    const a = await guest();
    await ok("claims", { session: a.session, body: ludoClaim("win"), now: T0 });
    expect(await row("SELECT value FROM scores WHERE account_id = ? AND board = 'xp' AND period = 'week:2026-W43'", a.id)).toEqual({ value: 100 });
    await ok("claims", { session: a.session, body: ludoClaim("win"), now: T0 + 7 * DAY });
    expect(await row("SELECT value FROM scores WHERE account_id = ? AND board = 'xp' AND period = 'week:2026-W44'", a.id)).toEqual({ value: 100 });
    expect(await row("SELECT value FROM scores WHERE account_id = ? AND board = 'xp' AND period = 'all'", a.id)).toEqual({ value: 200 });
  });
});
