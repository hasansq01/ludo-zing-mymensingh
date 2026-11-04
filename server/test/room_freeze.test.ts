// Nobody connected (owner decision 2026-10-31): a running match freezes the moment no person has an open socket (no
// ghost / bot / timeout step, no alarm but the freeze's deadline), resumes where it was when someone is back within
// TIMING.abandonAfter, and a quick match nobody came back to is ended and settled by progress (settle.ts): places
// from progress, normal payouts and the house bonus, the anti-gaming refund, leavers' forfeit, ghosts never paid, the
// result for people coming back later. A friend room still ends as abandoned (no rewards) after the empty timeout.
import { runInDurableObject } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { QUICK, TIMING, type TestHooks } from "../src/room";
import { GOAL } from "../src/rules/ludo";
import { eventually, row, rows } from "./admin_helpers";
import { Client, E, NEAR_GOAL, finishAll, lobbyOf, roomInfo, sleep, startAll, stubFor, type Msg } from "./room_client";
import { QuickClient, guest, joinMatched, resetSpies, spyGrants, type Guest } from "./quick_client";

beforeEach(() => resetSpies());
afterEach(() => resetSpies());

const SCALE = 0.01; // abandonAfter 2 min -> 1.2 s, grace 20 s -> 200 ms
const BASE = [-1, -1, -1, -1];

function mm(game: string, size: number, table: string) {
  return E.MATCHMAKER.get(E.MATCHMAKER.idFromName(table === "practice" ? `${game}:${size}` : `${game}:${size}:${table}`));
}

interface Table {
  code: string;
  gs: Guest[];
  cs: Client[];
  matched: Msg[];
}

/** A started coin-table quick match with `humans` guests (each connected and started) and ghosts for the rest. */
async function tableMatch(game: "ludo" | "sl", size: number, humans: number, room: TestHooks = {}, table = "t100"): Promise<Table> {
  await mm(game, size, table).testHooks({ wait: 100, room: { ratePerSec: 1000, timeScale: SCALE, autoStartMs: 5000, emoteChance: 0, ...room } } as never);
  const gs: Guest[] = [];
  for (let k = 0; k < humans; k++) gs.push(await guest());
  const qs: QuickClient[] = [];
  for (const g of gs) {
    const q = await QuickClient.open(game, size, `&table=${table}`);
    q.send({ t: "hello", v: 1, session: g.session, pid: g.pid, name: `Human${qs.length + 1}`, avatar: "pawn-red", frame: "classic" });
    await q.waitFor((m) => m.t === "queued" || m.t === "matched");
    qs.push(q);
  }
  const matched = await Promise.all(qs.map((q) => q.matched(8000)));
  for (const q of qs) q.close();
  const code = matched[0].code;
  const cs: Client[] = [];
  for (let k = 0; k < humans; k++) cs.push(await joinMatched(code, matched[k].token, gs[k], `Human${k + 1}`));
  // "start" goes out once; a seat that joins a moment later (a busy test run) gets the running match instead
  await Promise.all(cs.map((c) => c.waitFor((m) => m.t === "start" || m.t === "sync", 8000)));
  return { code, gs, cs, matched };
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type Inner = any;

/** The room as stored (match: n, due, frozenAt, state, ...). */
async function stored(code: string): Promise<Inner> {
  return runInDurableObject(stubFor(code), (_i, st) => st.storage.kv.get("room"));
}

/** Changes the live match (test only: the instance's room, then commit like a handler). */
async function edit(code: string, f: (m: Inner) => void): Promise<void> {
  const run = runInDurableObject as unknown as (stub: unknown, cb: (inst: Inner) => void) => Promise<void>;
  await run(stubFor(code), (inst) => {
    f(inst.room.match);
    inst.commit();
  });
}

async function alarmAt(code: string): Promise<number | null> {
  return runInDurableObject(stubFor(code), (_i, st) => st.storage.getAlarm());
}

const coinsOf = async (id: string) => (await row<{ coins: number }>("SELECT coins FROM accounts WHERE id = ?", id))!.coins;

async function settledEntry(account: string): Promise<Msg> {
  return eventually(async () => {
    const e = await row<Msg>("SELECT * FROM entries WHERE account_id = ?", account);
    return e && e.status !== "playing" && e.status !== "held" ? e : null;
  }, 8000, "entry closed");
}

async function frozen(code: string): Promise<Inner> {
  return eventually(async () => {
    const r = await stored(code);
    return r?.match?.frozenAt ? r.match : null;
  }, 5000, "frozen");
}

/** Seat colours: the humans' (in join order) and the ghosts'. */
async function colours(code: string): Promise<{ ghosts: number[] }> {
  const r = await stored(code);
  return { ghosts: r.match.seats.filter((s: Inner) => s.ghost).map((s: Inner) => s.color) };
}

describe("freeze", () => {
  it("nobody connected: no ghost steps, no alarm runs; the only alarm is the freeze's deadline", async () => {
    const t = await tableMatch("ludo", 4, 1, { tok: [0, 1, 2, 3].map(() => [1, 6, 11, 20]) });
    await sleep(150); // ghosts play while the person is here
    t.cs[0].close();
    const m0 = await frozen(t.code);
    const s0 = await stubFor(t.code).testStats();
    expect(m0.due).toBe(0);
    expect(m0.gemotes ?? []).toEqual([]);
    expect(await alarmAt(t.code)).toBe(Math.ceil(m0.frozenAt + TIMING.abandonAfter * SCALE));
    await sleep(700); // ~40 ghost steps' worth of time (they take 10-60 ms at this scale)
    const r1 = await stored(t.code);
    expect(r1.match.n).toBe(m0.n);
    expect(r1.status).toBe("playing");
    const s1 = await stubFor(t.code).testStats();
    expect(s1.alarms).toBe(s0.alarms); // nothing woke the room
    expect(s1.chained).toBe(s0.chained);
  });

  it("back within the deadline: the match resumes where it was and plays on to a normal end", async () => {
    const t = await tableMatch("ludo", 2, 1, { tok: NEAR_GOAL });
    t.cs[0].close();
    const m0 = await frozen(t.code);
    await sleep(500);
    expect((await stored(t.code)).match.n).toBe(m0.n);
    const back = await joinMatched(t.code, t.matched[0].token, t.gs[0], "Human1");
    back.autoplay = true;
    const sync = await back.wait("sync");
    expect(sync.n).toBe(m0.n);
    await back.wait("turn"); // re-planned with a fresh deadline
    expect((await stored(t.code)).match.frozenAt ?? 0).toBe(0);
    back.playTurn(back.state.turn);
    const [over] = await finishAll([back], 20_000);
    expect(over.ended).toBeUndefined();
    const e = await settledEntry(t.gs[0].account);
    expect(e.status).toBe("settled");
  });

  it("the graces of people still away stand still while frozen, then run on after the thaw", async () => {
    const t = await tableMatch("ludo", 4, 2, { tok: [0, 1, 2, 3].map(() => [1, 6, 11, 20]) });
    const [a, b] = t.cs;
    const bColour = b.color;
    b.close();
    await sleep(40); // b's grace (200 ms) is running
    a.close();
    await frozen(t.code);
    await sleep(600); // 3 graces long
    expect((await stored(t.code)).match.state.players[bColour]).toBe("human"); // not a bot yet
    const back = await joinMatched(t.code, t.matched[0].token, t.gs[0], "Human1");
    back.autoplay = true;
    const s = await back.wait("sync");
    expect(s.state.players[bColour]).toBe("human");
    // b's grace had ~160 ms left: it ends after the thaw
    await back.waitFor((m) => m.t === "act" && m.a.k === "mode" && m.a.c === bColour && m.a.mode === "cpu", 3000);
    back.send({ t: "leave" });
  });
});

/** Freezes the match (every person disconnected), sets the positions, and waits for the settlement. */
async function settleWith(t: Table, set: (m: Inner, ghosts: number[]) => void): Promise<void> {
  for (const c of t.cs) c.close();
  await frozen(t.code);
  const { ghosts } = await colours(t.code);
  await edit(t.code, (m) => set(m, ghosts));
  await eventually(async () => (await stored(t.code))?.status === "over", 6000, "ended");
}

/** A person back after the end: `sync` + `over` (with `ended`). */
async function comeBack(t: Table, k = 0): Promise<Msg> {
  const c = await joinMatched(t.code, t.matched[k].token, t.gs[k], `Human${k + 1}`);
  await c.wait("sync");
  const over = await c.wait("over");
  c.close();
  return over;
}

function ludoTok(m: Inner, tok: Record<number, number[]>): void {
  for (const [c, v] of Object.entries(tok)) m.state.tok[Number(c)] = v;
  m.state.pairs = [];
  m.state.finished = [];
}

describe("settlement by progress (nobody came back)", () => {
  it("Ludo 4 seats: a clear leader (more pawns home) is paid 1st + the bonus; ghosts are ranked but never paid", async () => {
    const t = await tableMatch("ludo", 4, 1);
    const me = t.cs[0].color;
    let order: number[] = [];
    await settleWith(t, (m, gh) => {
      ludoTok(m, { [me]: [GOAL, GOAL, 10, 10], [gh[0]]: [GOAL, 40, 40, 40], [gh[1]]: [30, 30, 30, 30], [gh[2]]: [-1, -1, -1, 5] });
      order = [me, ...gh];
    });
    const e = await settledEntry(t.gs[0].account);
    expect(e).toMatchObject({ status: "settled", place: 0, payout: 228 });
    expect(await coinsOf(t.gs[0].account)).toBe(2400 + 228 + 76);
    expect(await rows("SELECT reason, delta_coins FROM ledger WHERE account_id = ? AND reason IN ('payout', 'table_bonus') ORDER BY id", t.gs[0].account)).toEqual([
      { reason: "payout", delta_coins: 228 },
      { reason: "table_bonus", delta_coins: 76 },
    ]);
    expect(await row("SELECT outcome, coins, xp FROM match_grants WHERE account_id = ?", t.gs[0].account)).toEqual({ outcome: "win", coins: 228, xp: 100 });
    const over = await comeBack(t);
    expect(over.ended).toBe("away");
    expect(over.finished).toEqual(order);
    expect(over.winner).toBe(me);
    expect(over.table).toEqual({
      tier: "t100",
      entry: 100,
      payouts: { [me]: 228, [order[1]]: 114, [order[2]]: 38, [order[3]]: 0 },
      bonus: { [me]: 76 },
      refunds: {},
    });
    expect(await row("SELECT paid_humans, winner_ghost, fee FROM table_matches WHERE match_id = ?", e.match_id)).toEqual({ paid_humans: 228, winner_ghost: 0, fee: 20 });
    expect(await row("SELECT result FROM matches WHERE code = ?", t.code)).toEqual({ result: "over" });
    // kept longer than a normal end (QUICK.endedKeep), closed to play: the next alarm is its deletion
    const r = await stored(t.code);
    const at = (await alarmAt(t.code))!;
    expect(at).toBeGreaterThan(r.quick.overAt + QUICK.overKeep * SCALE);
    expect(at).toBeLessThanOrEqual(Math.ceil(r.quick.overAt + QUICK.endedKeep * SCALE));
  });

  it("anti-gaming: 1st by progress without a clear lead (6 steps) -> the entry back, no prize, no bonus", async () => {
    const t = await tableMatch("ludo", 4, 1);
    const me = t.cs[0].color;
    await settleWith(t, (m, gh) => ludoTok(m, { [me]: [20, 20, 20, 20], [gh[0]]: [18, 18, 18, 20], [gh[1]]: [5, 5, 5, 5], [gh[2]]: BASE }));
    const e = await settledEntry(t.gs[0].account);
    expect(e).toMatchObject({ status: "refunded", place: 0, payout: 0 });
    expect(await coinsOf(t.gs[0].account)).toBe(2500);
    expect(await rows("SELECT reason, delta_coins FROM ledger WHERE account_id = ? AND reason IN ('payout', 'table_bonus', 'entry_refund') ORDER BY id", t.gs[0].account)).toEqual([
      { reason: "payout", delta_coins: 0 },
      { reason: "entry_refund", delta_coins: 100 },
    ]);
    expect(await row("SELECT outcome, coins FROM match_grants WHERE account_id = ?", t.gs[0].account)).toEqual({ outcome: "finish", coins: 0 });
    const over = await comeBack(t);
    expect(over.table.refunds).toEqual({ [me]: 100 });
    expect(over.table.payouts[me]).toBe(0);
    expect(over.table.bonus).toEqual({});
    expect(await row("SELECT paid_humans FROM table_matches WHERE match_id = ?", e.match_id)).toEqual({ paid_humans: 0 });
  });

  it("a clear distance lead (20 steps, no pawn home) is paid", async () => {
    const t = await tableMatch("ludo", 2, 1);
    const me = t.cs[0].color;
    await settleWith(t, (m, gh) => ludoTok(m, { [me]: [29, 29, 29, 29], [gh[0]]: [24, 24, 24, 24] }));
    expect(await settledEntry(t.gs[0].account)).toMatchObject({ status: "settled", place: 0, payout: 190 });
    expect(await coinsOf(t.gs[0].account)).toBe(2400 + 190 + 38);
  });

  it("2nd by progress: the 2nd share (114), no bonus for anyone; the ghost's 1st prize stays with the house", async () => {
    const t = await tableMatch("ludo", 4, 1);
    const me = t.cs[0].color;
    await settleWith(t, (m, gh) => ludoTok(m, { [gh[0]]: [GOAL, 50, 50, 50], [me]: [40, 40, 40, 40], [gh[1]]: [10, 10, 10, 10], [gh[2]]: BASE }));
    expect(await settledEntry(t.gs[0].account)).toMatchObject({ status: "settled", place: 1, payout: 114 });
    expect(await coinsOf(t.gs[0].account)).toBe(2514);
    expect(await rows("SELECT 1 FROM ledger WHERE account_id = ? AND reason IN ('table_bonus', 'entry_refund')", t.gs[0].account)).toEqual([]);
    const over = await comeBack(t);
    expect(over.winner).not.toBe(me);
    expect(Object.keys(over.table.bonus)).toEqual([String(over.winner)]); // shown like anyone's, never paid
  });

  it("S&L 2 seats, behind: the entry is lost (disconnecting never gets it back), even after the room is gone", async () => {
    const t = await tableMatch("sl", 2, 1);
    const me = t.cs[0].color;
    await settleWith(t, (m, gh) => {
      for (const p of m.state.players) p.pos = p.c === me ? 30 : 60;
      m.state.finished = [];
      void gh;
    });
    expect(await settledEntry(t.gs[0].account)).toMatchObject({ status: "settled", place: 1, payout: 0 });
    expect(await coinsOf(t.gs[0].account)).toBe(2400);
    const over = await comeBack(t);
    expect(over.ended).toBe("away");
    expect(over.table.refunds).toEqual({});
    // the room deletes itself (QUICK.endedKeep 10 min -> 6 s): nothing is refunded on the way out
    await eventually(async () => (await roomInfo(t.code)).status === 404, 9000, "room gone");
    expect(await coinsOf(t.gs[0].account)).toBe(2400);
    expect((await row<Msg>("SELECT status FROM entries WHERE account_id = ?", t.gs[0].account))!.status).toBe("settled");
  }, 20_000);

  it("S&L: 1st by 19 squares is not clear (refund); by 20 it is (paid)", async () => {
    const t = await tableMatch("sl", 2, 1);
    const me = t.cs[0].color;
    await settleWith(t, (m) => {
      for (const p of m.state.players) p.pos = p.c === me ? 70 : 51;
      m.state.finished = [];
    });
    expect(await settledEntry(t.gs[0].account)).toMatchObject({ status: "refunded" });
    expect(await coinsOf(t.gs[0].account)).toBe(2500);

    const u = await tableMatch("sl", 2, 1);
    const me2 = u.cs[0].color;
    await settleWith(u, (m) => {
      for (const p of m.state.players) p.pos = p.c === me2 ? 70 : 50;
      m.state.finished = [];
    });
    expect(await settledEntry(u.gs[0].account)).toMatchObject({ status: "settled", place: 0, payout: 190 });
    expect(await coinsOf(u.gs[0].account)).toBe(2400 + 190 + 38);
  });

  it("an explicit leaver forfeits; the disconnected person is judged against the next seat behind them", async () => {
    const t = await tableMatch("ludo", 4, 2);
    const [a, b] = t.cs;
    const aColour = a.color;
    const bColour = b.color;
    a.send({ t: "leave" });
    await a.waitClosed();
    await settleWith({ ...t, cs: [b] }, (m, gh) =>
      // the leaver (bot-played) is far ahead; b is 1st of the paid places with a clear lead over the ghosts
      ludoTok(m, { [aColour]: [GOAL, GOAL, GOAL, 50], [bColour]: [GOAL, 30, 30, 30], [gh[0]]: [40, 40, 40, 40], [gh[1]]: [10, 10, 10, 10] }),
    );
    expect(await settledEntry(t.gs[0].account)).toMatchObject({ status: "forfeit", payout: 0 });
    expect(await coinsOf(t.gs[0].account)).toBe(2400);
    expect(await settledEntry(t.gs[1].account)).toMatchObject({ status: "settled", place: 0, payout: 228 });
    expect(await coinsOf(t.gs[1].account)).toBe(2400 + 228 + 76);
    const over = await comeBack(t, 1);
    expect(over.finished[0]).toBe(aColour); // the leaver keeps its rank in the order...
    expect(over.table.payouts[aColour]).toBe(0); // ... but no money
  });

  it("every person left: abandoned as before (forfeit), nothing is settled by progress", async () => {
    const grants = spyGrants();
    const t = await tableMatch("ludo", 2, 1);
    t.cs[0].send({ t: "leave" });
    expect(await settledEntry(t.gs[0].account)).toMatchObject({ status: "forfeit" });
    await sleep(300);
    expect(grants).toEqual([]);
    expect(await coinsOf(t.gs[0].account)).toBe(2400);
  });
});

describe("friend rooms", () => {
  it("freeze while nobody is connected, then end as abandoned after the empty timeout (no rewards)", async () => {
    const grants = spyGrants();
    const { code, cs } = await lobbyOf(2, { timeScale: 0.002 }); // empty 10 min -> 1.2 s
    await startAll(cs);
    for (const c of cs) c.close();
    const m0 = await frozen(code);
    const s0 = await stubFor(code).testStats();
    await sleep(400);
    expect((await stored(code)).match.n).toBe(m0.n);
    expect((await stubFor(code).testStats()).alarms).toBe(s0.alarms);
    await eventually(async () => (await roomInfo(code)).status === 404, 5000, "room gone");
    const m = await eventually(() => row<Msg>("SELECT result FROM matches WHERE code = ?", code), 5000, "match row");
    expect(m.result).toBe("abandoned");
    expect(grants).toEqual([]);
  });
});
