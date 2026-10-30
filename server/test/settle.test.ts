// Settlement by progress (src/settle.ts; owner 2026-10-31): the score and order of a match ended because nobody was
// connected (Ludo individual and Teams, S&L), the anti-gaming "clear lead" rule at its exact boundaries, and the grant
// side of coin tables (accounts.ts grantOne): the new payouts, the house bonus on its own ledger row, the entry refund,
// leavers' forfeit, ghosts never paid, idempotent retries, and the sum rule (pot payouts <= the pot).
import { describe, expect, it } from "vitest";
import { grantOnlineMatch } from "../src/accounts";
import { ECON_V1, tablePayouts } from "../src/econ/rules";
import { newGame as ludoGame, standings, endGame, GOAL, type LudoState } from "../src/rules/ludo";
import { newGame as slGame, endGame as slEnd, type SlState } from "../src/rules/sl";
import { applyOrder, clearLead, ludoScore, rankByProgress, slScore } from "../src/settle";
import { DB, ENV, guest, ledgerSum, ok, row, rows, setAccount, type Json } from "./acc_helpers";

function ludo(tok: number[][], opts: { teams?: boolean; finished?: number[]; players?: string[] } = {}): LudoState {
  const s = ludoGame(opts.players ?? ["human", "human", "human", "human"], opts.teams ?? false);
  s.tok = tok.map((t) => [...t]);
  s.finished = opts.finished ?? [];
  return s;
}

function sl(pos: number[], finished: number[] = []): SlState {
  const g = slGame("local", pos.length, 0, { need_one: false });
  g.mode = "online";
  pos.forEach((p, k) => {
    g.players[k].c = k;
    g.players[k].pos = p;
    g.players[k].cpu = false;
  });
  g.finished = finished;
  return g;
}

const BASE = [-1, -1, -1, -1];

describe("progress score", () => {
  it("Ludo: pawns home, and the distance: min(p, GOAL) + 1 per pawn (0 in base)", () => {
    const s = ludo([[GOAL, GOAL, 10, -1], BASE, [0, 0, 0, 0], [55, 55, 55, 55]]);
    expect(ludoScore(s, 0)).toEqual({ home: 2, dist: 57 + 57 + 11 + 0 });
    expect(ludoScore(s, 1)).toEqual({ home: 0, dist: 0 });
    expect(ludoScore(s, 2)).toEqual({ home: 0, dist: 4 }); // just out of base: 1 step each
    expect(ludoScore(s, 3)).toEqual({ home: 0, dist: 224 });
  });

  it("S&L: the square", () => {
    const g = sl([37, 0, 99]);
    expect([0, 1, 2].map((c) => slScore(g, c))).toEqual([
      { home: 0, dist: 37 },
      { home: 0, dist: 0 },
      { home: 0, dist: 99 },
    ]);
  });
});

describe("rankByProgress", () => {
  it("Ludo individual: finished sides keep their places first, then pawns home beat distance", () => {
    // green finished; blue has 1 pawn home but less distance than yellow (no pawn home): blue is ahead of yellow
    const s = ludo([[50, 50, 50, 50], [GOAL, GOAL, GOAL, GOAL], [55, 55, 55, 55], [GOAL, -1, -1, -1]], { finished: [1] });
    const rk = rankByProgress("ludo", s);
    expect(rk.order).toEqual([1, 3, 2, 0]);
    expect(rk.byProgress).toEqual([3, 2, 0]);
    expect(rk.scores[3]).toEqual({ home: 1, dist: 57 });
    // (the rules' own standings rank by distance only: yellow 224 > red 204 > blue 57)
    const t = structuredClone(s);
    endGame(t);
    expect(t.finished).toEqual([1, 2, 0, 3]);
    applyOrder("ludo", t, rk.order);
    expect(standings(t).map((x) => x.color)).toEqual([1, 3, 2, 0]);
    expect(t.winner).toBe(1);
  });

  it("Ludo individual: ties go to the lower colour; 2 players use only the playing colours", () => {
    const s = ludo([[10, 10, -1, -1], BASE, [9, 11, -1, -1], BASE], { players: ["human", "off", "human", "off"] });
    expect(rankByProgress("ludo", s).order).toEqual([0, 2]);
  });

  it("Ludo Teams: a team's score is both colours'; within a team the finished member first, then its own score", () => {
    // Red + Yellow: 1 + 0 home; Green + Blue: 0 + 0 home but far more distance -> Red/Yellow first (pawns home)
    const s = ludo([[GOAL, -1, -1, -1], [50, 50, 50, 50], [20, 20, -1, -1], [50, 50, 50, 50]], { teams: true });
    const rk = rankByProgress("ludo", s);
    expect(rk.order).toEqual([0, 2, 1, 3]);
    expect(rk.scores[0]).toEqual({ home: 1, dist: 57 + 42 });
    expect(rk.scores[2]).toEqual(rk.scores[0]);
    expect(rk.scores[1]).toEqual({ home: 0, dist: 408 });
    expect(rk.byProgress).toEqual([0, 2, 1, 3]);
    // all four of Yellow's pawns home (finished individually) but Red not: Yellow first within the team
    const s2 = ludo([[10, -1, -1, -1], BASE, [GOAL, GOAL, GOAL, GOAL], BASE], { teams: true, finished: [2] });
    expect(rankByProgress("ludo", s2).order).toEqual([2, 0, 1, 3]);
    endGame(s2);
    applyOrder("ludo", s2, [2, 0, 1, 3]);
    expect(standings(s2).map((x) => [x.color, x.place])).toEqual([
      [2, 1],
      [0, 1],
      [1, 2],
      [3, 2],
    ]);
  });

  it("S&L: finished players first (finish order), then by square", () => {
    const g = sl([100, 40, 72, 72], [0]);
    const rk = rankByProgress("sl", g);
    expect(rk.order).toEqual([0, 2, 3, 1]);
    expect(rk.byProgress).toEqual([2, 3, 1]);
    const t = structuredClone(g);
    slEnd(t);
    applyOrder("sl", t, rk.order);
    expect(t.finished).toEqual([0, 2, 3, 1]);
    expect(t.winner).toBe(0);
  });
});

describe("clearLead (the anti-gaming rule)", () => {
  it("Ludo: more pawns home is clear; else the distance lead must exceed 25% of one pawn's track (57): 15+ steps", () => {
    expect(ECON_V1.away_lead).toEqual({ ludo_track_pct: 25, sl_squares: 20 });
    expect(clearLead("ludo", { home: 1, dist: 60 }, { home: 0, dist: 200 })).toBe(true);
    expect(clearLead("ludo", { home: 0, dist: 115 }, { home: 0, dist: 100 })).toBe(true); // 15 > 14.25
    expect(clearLead("ludo", { home: 0, dist: 114 }, { home: 0, dist: 100 })).toBe(false); // 14
    expect(clearLead("ludo", { home: 2, dist: 130 }, { home: 2, dist: 130 })).toBe(false); // a tie
    expect(clearLead("ludo", { home: 0, dist: 1 }, undefined)).toBe(true); // nobody behind
  });

  it("S&L: a lead of 20 squares or more", () => {
    expect(clearLead("sl", { home: 0, dist: 70 }, { home: 0, dist: 50 })).toBe(true);
    expect(clearLead("sl", { home: 0, dist: 69 }, { home: 0, dist: 50 })).toBe(false);
  });
});

// ---------- grants (accounts.ts) ----------

let seq = 0;
function entryId(): string {
  const abc = "abcdefghijklmnopqrstuvwxyz234567";
  let s = "ent_";
  let n = ++seq + Math.floor(Math.random() * 1e9);
  for (let k = 0; k < 16; k++) {
    s += abc[n & 31];
    n = Math.floor(n / 32) + k * 7;
  }
  return s;
}

/** A guest that paid `entry` for a seat: coins 2500 - entry, an `entry` ledger row, an entry row `playing`. */
async function seated(entry = 100, size = 4) {
  const g = await guest();
  const id = entryId();
  await setAccount(g.id, { coins: 2500 - entry });
  await DB.batch([
    DB.prepare("INSERT INTO ledger (account_id, at, delta_coins, delta_xp, reason, ref, balance_after) VALUES (?, ?, ?, 0, 'entry', ?, ?)").bind(g.id, Date.now(), -entry, id, 2500 - entry),
    DB.prepare("INSERT INTO entries (id, account_id, at, game, size, tier, amount, status) VALUES (?, ?, ?, 'ludo', ?, 't100', ?, 'playing')").bind(id, g.id, Date.now(), size, entry),
  ]);
  return { ...g, entry: id };
}

const coinsOf = async (id: string) => (await row<{ coins: number }>("SELECT coins FROM accounts WHERE id = ?", id))!.coins;
const entryOf = (id: string) => row<Json>("SELECT status, place, payout, match_id FROM entries WHERE id = ?", id);

describe("coin-table grants", () => {
  it("4 players, every seat a person: 228 + bonus 76 / 114 / 38 / 0; pot payouts <= the pot; idempotent", async () => {
    const ps = await Promise.all([0, 1, 2, 3].map(() => seated()));
    const match_id = `set-4p-${ps[0].id}`;
    const g = {
      match_id,
      game: "ludo" as const,
      results: ps.map((p, k) => ({ account_id: p.id, outcome: (k === 0 ? "win" : "finish") as "win" | "finish", place: k, entry_id: p.entry })),
      table: { tier: "t100", entry: 100, size: 4, humans: 4, ghosts: 0 },
    };
    await grantOnlineMatch(ENV, g);
    await grantOnlineMatch(ENV, g); // a retry pays nothing more (bonus included)
    expect(await Promise.all(ps.map((p) => coinsOf(p.id)))).toEqual([2400 + 228 + 76, 2400 + 114, 2400 + 38, 2400]);
    expect((await Promise.all(ps.map((p) => entryOf(p.entry)))).map((e) => [e!.status, e!.place, e!.payout])).toEqual([
      ["settled", 0, 228],
      ["settled", 1, 114],
      ["settled", 2, 38],
      ["settled", 3, 0],
    ]);
    expect(await rows("SELECT reason, delta_coins, ref, balance_after FROM ledger WHERE account_id = ? AND reason IN ('payout', 'table_bonus') ORDER BY id", ps[0].id)).toEqual([
      { reason: "payout", delta_coins: 228, ref: match_id, balance_after: 2628 },
      { reason: "table_bonus", delta_coins: 76, ref: match_id, balance_after: 2704 },
    ]);
    for (const p of ps) expect(await ledgerSum(p.id)).toBe(await coinsOf(p.id));
    expect((await rows("SELECT 1 FROM ledger WHERE reason = 'table_bonus' AND ref = ?", match_id)).length).toBe(1);
    // the sum rule: what the pot paid (bonus aside) never exceeds what went in
    const paid = (await rows<{ payout: number }>("SELECT payout FROM entries WHERE match_id = ?", match_id)).reduce((a, r) => a + r.payout, 0);
    expect(paid).toBe(380);
    expect(paid).toBeLessThanOrEqual(400);
    expect(await row("SELECT pot, fee, paid_humans, winner_ghost FROM table_matches WHERE match_id = ?", match_id)).toEqual({ pot: 400, fee: 20, paid_humans: 380, winner_ghost: 0 });
    // the bonus counts as earned coins
    expect((await ok("me", { session: ps[0].session })).profile.stats.coinsEarned).toBe(304);
  });

  it("a ghost won: nobody gets the bonus; 2nd gets its normal share; a leaver forfeits", async () => {
    const [a, b] = await Promise.all([seated(), seated()]);
    const match_id = `set-ghost-${a.id}`;
    await grantOnlineMatch(ENV, {
      match_id,
      game: "ludo",
      results: [
        { account_id: a.id, outcome: "finish", place: 1, entry_id: a.entry },
        { account_id: b.id, outcome: "left", place: -1, entry_id: b.entry },
      ],
      table: { tier: "t100", entry: 100, size: 4, humans: 2, ghosts: 2, winner_ghost: true },
    });
    expect(await coinsOf(a.id)).toBe(2514);
    expect(await coinsOf(b.id)).toBe(2400);
    expect((await entryOf(b.entry))!.status).toBe("forfeit");
    expect(await rows("SELECT 1 FROM ledger WHERE reason = 'table_bonus' AND ref = ?", match_id)).toEqual([]);
    expect(await row("SELECT paid_humans, winner_ghost FROM table_matches WHERE match_id = ?", match_id)).toEqual({ paid_humans: 114, winner_ghost: 1 });
  });

  it("refund (settlement by progress, no clear lead): the entry comes back, no prize, no bonus, outcome finish", async () => {
    const p = await seated();
    const match_id = `set-refund-${p.id}`;
    const g = {
      match_id,
      game: "ludo" as const,
      results: [{ account_id: p.id, outcome: "finish" as const, place: 0, entry_id: p.entry, refund: true }],
      table: { tier: "t100", entry: 100, size: 2, humans: 1, ghosts: 1 },
    };
    await grantOnlineMatch(ENV, g);
    await grantOnlineMatch(ENV, g);
    expect(await coinsOf(p.id)).toBe(2500);
    expect(await entryOf(p.entry)).toMatchObject({ status: "refunded", place: 0, payout: 0, match_id });
    expect(await rows("SELECT reason, delta_coins, delta_xp, ref FROM ledger WHERE account_id = ? AND reason != 'start' ORDER BY id", p.id)).toEqual([
      { reason: "entry", delta_coins: -100, delta_xp: 0, ref: p.entry },
      { reason: "payout", delta_coins: 0, delta_xp: 40, ref: match_id },
      { reason: "entry_refund", delta_coins: 100, delta_xp: 0, ref: `${p.entry}:away` },
    ]);
    expect(await ledgerSum(p.id)).toBe(2500);
    expect(await row("SELECT outcome, coins, xp FROM match_grants WHERE match_id = ?", match_id)).toEqual({ outcome: "finish", coins: 0, xp: 40 });
    expect(await row("SELECT paid_humans, fee FROM table_matches WHERE match_id = ?", match_id)).toEqual({ paid_humans: 0, fee: 10 });
    // a refund is not "earned", and can't be doubled with an ad (no settled payout)
    expect((await ok("me", { session: p.session })).profile.stats.coinsEarned ?? 0).toBe(0);
  });

  it("an entry already closed (refunded elsewhere) pays nothing: no payout, no bonus", async () => {
    const p = await seated(100, 2);
    await DB.prepare("UPDATE entries SET status = 'refunded' WHERE id = ?").bind(p.entry).run();
    await grantOnlineMatch(ENV, {
      match_id: `set-closed-${p.id}`,
      game: "ludo",
      results: [{ account_id: p.id, outcome: "win", place: 0, entry_id: p.entry }],
      table: { tier: "t100", entry: 100, size: 2, humans: 1, ghosts: 1 },
    });
    expect(await coinsOf(p.id)).toBe(2400);
    expect(await rows("SELECT 1 FROM ledger WHERE account_id = ? AND reason = 'table_bonus'", p.id)).toEqual([]);
  });

  it("parallel grants of the same match pay the bonus once", async () => {
    const p = await seated(100, 2);
    const g = {
      match_id: `set-par-${p.id}`,
      game: "ludo" as const,
      results: [{ account_id: p.id, outcome: "win" as const, place: 0, entry_id: p.entry }],
      table: { tier: "t100", entry: 100, size: 2, humans: 1, ghosts: 1 },
    };
    await Promise.all([0, 1, 2, 3].map(() => grantOnlineMatch(ENV, g).catch(() => undefined)));
    expect(await coinsOf(p.id)).toBe(2400 + 190 + 38);
    expect(await ledgerSum(p.id)).toBe(2628);
  });

  it("the practice table: no entry, no bonus; friend rooms: the new rewards", async () => {
    const p = await guest();
    await grantOnlineMatch(ENV, {
      match_id: `set-prac-${p.id}`,
      game: "ludo",
      results: [{ account_id: p.id, outcome: "win", place: 0 }],
      table: { tier: "practice", entry: 0, size: 2, humans: 1, ghosts: 1 },
    });
    expect(await coinsOf(p.id)).toBe(2550);
    await grantOnlineMatch(ENV, { match_id: `set-friend-${p.id}`, game: "sl", results: [{ account_id: p.id, outcome: "win" }] });
    expect(await coinsOf(p.id)).toBe(2750);
    expect(tablePayouts(0, 2, 2).bonus).toBe(0);
  });
});
