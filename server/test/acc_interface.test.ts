// The functions the Room / quick match call (accounts.ts) and the db.ts helpers they write with: grantOnlineMatch
// (Economy decision 2, idempotent), getPublicProfile, accountForPid, recordQuickStat, the v2 match / room columns.
import { describe, expect, it } from "vitest";
import { accountForPid, getPublicProfile, grantOnlineMatch } from "../src/accounts";
import * as D from "../src/db";
import { DB, ENV, guest, ledgerSum, ok, row, rows, setAccount } from "./acc_helpers";

describe("grantOnlineMatch", () => {
  it("Ludo: win 150 + 100 XP, finish 20 + 40 XP, left 0; once per account per match", async () => {
    const [w, f, l] = await Promise.all([guest(), guest(), guest()]);
    const m = { match_id: `m-ludo-${w.id}`, game: "ludo" as const, results: [
      { account_id: w.id, outcome: "win" as const },
      { account_id: f.id, outcome: "finish" as const },
      { account_id: l.id, outcome: "left" as const },
    ] };
    await grantOnlineMatch(ENV, m);
    await grantOnlineMatch(ENV, m); // again: nothing new
    const pw = (await ok("me", { session: w.session })).profile;
    const pf = (await ok("me", { session: f.session })).profile;
    const pl = (await ok("me", { session: l.session })).profile;
    expect([pw.coins, pw.xp, pw.stats.coinsEarned]).toEqual([5150, 100, 150]);
    expect([pf.coins, pf.xp]).toEqual([5020, 40]);
    expect([pl.coins, pl.xp]).toEqual([5000, 0]);
    expect(pw.stats.wins).toBe(0); // online results don't touch the offline stats
    expect(await rows("SELECT reason, ref, delta_coins, delta_xp FROM ledger WHERE account_id = ? AND reason = 'match'", w.id)).toEqual([
      { reason: "match", ref: m.match_id, delta_coins: 150, delta_xp: 100 },
    ]);
    expect(await rows("SELECT account_id, outcome, coins, xp FROM match_grants WHERE match_id = ? ORDER BY coins DESC", m.match_id)).toEqual([
      { account_id: w.id, outcome: "win", coins: 150, xp: 100 },
      { account_id: f.id, outcome: "finish", coins: 20, xp: 40 },
      { account_id: l.id, outcome: "left", coins: 0, xp: 0 },
    ]);
    expect((await row<{ online_wins: number }>("SELECT online_wins FROM accounts WHERE id = ?", w.id))!.online_wins).toBe(1);
    expect(await ledgerSum(w.id)).toBe(5150);
    expect((await ok("me", { session: w.session })).account.online_wins).toBe(1);
  });

  it("Snakes & Ladders: win 100 + 60 XP, finish 10 + 25 XP", async () => {
    const [w, f] = await Promise.all([guest(), guest()]);
    await grantOnlineMatch(ENV, { match_id: `m-sl-${w.id}`, game: "sl", results: [{ account_id: w.id, outcome: "win" }, { account_id: f.id, outcome: "finish" }] });
    expect((await ok("me", { session: w.session })).profile).toMatchObject({ coins: 5100, xp: 60 });
    expect((await ok("me", { session: f.session })).profile).toMatchObject({ coins: 5010, xp: 25 });
  });

  it("parallel calls for the same match grant once; other matches still grant", async () => {
    const a = await guest();
    const m = { match_id: `m-par-${a.id}`, game: "ludo" as const, results: [{ account_id: a.id, outcome: "win" as const }] };
    await Promise.all([0, 1, 2, 3].map(() => grantOnlineMatch(ENV, m)));
    expect((await ok("me", { session: a.session })).profile.coins).toBe(5150);
    await grantOnlineMatch(ENV, { ...m, match_id: `${m.match_id}-2` });
    expect((await ok("me", { session: a.session })).profile.coins).toBe(5300);
  });

  it("skips unknown, banned and merged accounts and duplicates in one call", async () => {
    const [a, b, c] = await Promise.all([guest(), guest(), guest()]);
    await setAccount(b.id, { banned: 1 });
    await setAccount(c.id, { merged_into: a.id });
    await grantOnlineMatch(ENV, {
      match_id: `m-skip-${a.id}`,
      game: "ludo",
      results: [
        { account_id: a.id, outcome: "win" },
        { account_id: a.id, outcome: "win" },
        { account_id: b.id, outcome: "win" },
        { account_id: c.id, outcome: "win" },
        { account_id: "acc_nosuchaccount234", outcome: "win" },
        { account_id: "not an id", outcome: "win" },
      ],
    });
    expect((await ok("me", { session: a.session })).profile.coins).toBe(5150);
    expect((await row<{ coins: number }>("SELECT coins FROM accounts WHERE id = ?", b.id))!.coins).toBe(5000);
    expect((await row<{ coins: number }>("SELECT coins FROM accounts WHERE id = ?", c.id))!.coins).toBe(5000);
    await expect(grantOnlineMatch(ENV, { match_id: "", game: "ludo", results: [] })).rejects.toThrow();
  });
});

describe("profile lookups", () => {
  it("getPublicProfile / accountForPid", async () => {
    const g = await guest();
    await ok("me", { session: g.session, method: "PATCH", body: { name: "Nadia", avatar: "pawn-green" } });
    expect(await getPublicProfile(ENV, g.id)).toEqual({ name: "Nadia", avatar: "pawn-green", frame: "classic", level: 1 });
    expect(await getPublicProfile(ENV, "acc_nosuchaccount234")).toEqual({ name: "Player", avatar: "pawn-red", frame: "classic", level: 1 });
    expect(await accountForPid(ENV, g.pid)).toEqual({ account_id: g.id, banned: false });
    expect(await accountForPid(ENV, "bad")).toBeNull();
    await DB.prepare("INSERT INTO players (pid, banned) VALUES (?, 1)").bind(g.pid).run();
    expect(await accountForPid(ENV, g.pid)).toEqual({ account_id: g.id, banned: true });
  });
});

describe("db helpers for quick match", () => {
  it("recordQuickStat adds to the day's row", async () => {
    await D.recordQuickStat(ENV, { day: "2026-10-01", game: "ludo", size: 2, queued: 3, matched: 2, ghost_filled: 1, wait_ms: 9000 });
    await D.recordQuickStat(ENV, { day: "2026-10-01", game: "ludo", size: 2, queued: 1, human_wins: 1 });
    await D.recordQuickStat(ENV, { day: "2026-10-01", game: "sl", size: 4, ghost_wins: 1, wait_ms_total: 5 });
    expect(await rows("SELECT * FROM quick_stats WHERE day = '2026-10-01' ORDER BY game")).toEqual([
      { day: "2026-10-01", game: "ludo", size: 2, queued: 4, matched: 2, ghost_filled: 1, wait_ms_total: 9000, human_wins: 1, ghost_wins: 0 },
      { day: "2026-10-01", game: "sl", size: 4, queued: 0, matched: 0, ghost_filled: 0, wait_ms_total: 5, human_wins: 0, ghost_wins: 1 },
    ]);
  });

  it("insertMatch / endMatch / upsertRoom: the v2 columns are optional", async () => {
    const t = Date.now();
    await D.insertMatch(DB, { code: "QQQQQ2", started_at: t, players: [], teams: false, pair_ask: false }).run();
    await D.insertMatch(DB, { code: "QQQQQ3", started_at: t, players: [], teams: false, pair_ask: false, game: "sl", quick: true, ghosts: 2 }).run();
    expect(await row("SELECT game, quick, ghosts, human_won FROM matches WHERE code = 'QQQQQ2'")).toEqual({ game: "ludo", quick: 0, ghosts: 0, human_won: null });
    expect(await row("SELECT game, quick, ghosts FROM matches WHERE code = 'QQQQQ3'")).toEqual({ game: "sl", quick: 1, ghosts: 2 });
    const end = { started_at: t, ended_at: t + 1, winner: 0, finished: [0], actions: 9, result: "over" as const };
    await D.endMatch(DB, { ...end, code: "QQQQQ2" }).run();
    await D.endMatch(DB, { ...end, code: "QQQQQ3", human_won: false }).run();
    expect((await row("SELECT human_won, result FROM matches WHERE code = 'QQQQQ2'"))).toEqual({ human_won: null, result: "over" });
    expect((await row("SELECT human_won FROM matches WHERE code = 'QQQQQ3'"))!.human_won).toBe(0);
    const room = { code: "QQQQQ4", created_at: t, host_pid: null, host_name: null, status: "lobby" as const, members: 0, online: 0, settings: { teams: false, pair_ask: false }, closed_reason: null };
    await D.upsertRoom(DB, room, t, true).run();
    expect(await row("SELECT game, public, quick FROM rooms WHERE code = 'QQQQQ4'")).toEqual({ game: "ludo", public: 0, quick: 0 });
    await D.upsertRoom(DB, { ...room, game: "sl", public: true, quick: true }, t + 1).run();
    expect(await row("SELECT game, public, quick FROM rooms WHERE code = 'QQQQQ4'")).toEqual({ game: "sl", public: 1, quick: 1 });
  });
});
