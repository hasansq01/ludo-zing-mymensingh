// Ghost / bot steps in one wake-up (Room.chain(), CHAIN in src/room.ts): a ghost's roll and its move (and chained
// steps: a 6, the next ghost's turn) are played by one alarm invocation that waits in-request, instead of one alarm
// per step. Measured here: alarm() invocations per ghost turn with and without chaining (TestHooks.chain = false is
// the old behaviour), the roll -> move gaps people see (same human-like windows and "thinking" pauses as before),
// and the interruptions: a person leaving, an admin close, an eviction and a second alarm during the wait.
import { evictDurableObject, runDurableObjectAlarm, runInDurableObject } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { GHOST_TIMING } from "../src/ghosts";
import { CHAIN, TIMING, type AdminSnapshot, type TestHooks } from "../src/room";
import { applyAction, type LudoState } from "../src/rules/ludo";
import { rows } from "./admin_helpers";
import { Client, NEAR_GOAL, finishAll, lobbyOf, sleep, startAll, stubFor, type Msg } from "./room_client";
import { guest, joinMatched, mmHooks, queueAll, resetSpies, type Guest } from "./quick_client";

beforeEach(() => resetSpies());
afterEach(() => resetSpies());

/** Every pawn out on the board: nearly every roll leads to a choice (a move step after the roll). */
const MID = [0, 1, 2, 3].map(() => [1, 6, 11, 20]);

interface Quick {
  code: string;
  cs: Client[];
  ghosts: Set<number>;
}

/** A started quick Ludo match: `humans` guests (autoplay, instant) and ghosts for the rest. */
async function quick(size: number, humans: number, room: TestHooks): Promise<Quick> {
  await mmHooks("ludo", size, { wait: 100, room: { emoteChance: 0, tok: MID, ...room } });
  const gs: Guest[] = [];
  for (let k = 0; k < humans; k++) gs.push(await guest());
  const { matched } = await queueAll("ludo", size, gs);
  const code = matched[0].code;
  const snap = (await stubFor(code).adminSnapshot()) as unknown as AdminSnapshot;
  const ghosts = new Set(snap.members.filter((m) => m.ghost).map((m) => m.color));
  const cs: Client[] = [];
  for (let k = 0; k < humans; k++) cs.push(await joinMatched(code, matched[k].token, gs[k], `Human${k + 1}`));
  await Promise.all(cs.map((c) => c.wait("start")));
  for (const c of cs) {
    c.autoplay = true;
    c.playTurn(c.state.turn);
  }
  return { code, cs, ghosts };
}

interface Steps {
  /** Ghost roll actions (one per ghost turn; a 6 is a new turn). */
  rolls: number;
  /** Every ghost action (rolls, moves, pair answers). */
  steps: number;
  /** turn announcement -> the ghost's roll (ms). */
  rollGaps: number[];
  /** the ghost's roll -> its move (ms). */
  moveGaps: number[];
}

/** The ghost steps a client saw (its log, replayed from start), up to log entry `upto`. */
function ghostSteps(c: Client, ghosts: Set<number>, upto = c.log.length): Steps {
  const out: Steps = { rolls: 0, steps: 0, rollGaps: [], moveGaps: [] };
  const k0 = c.log.findIndex((m) => m.t === "start");
  const s = JSON.parse(JSON.stringify(c.log[k0].state)) as LudoState;
  let turnAt = -1;
  let turnPhase = "";
  let roll: { c: number; at: number } | null = null;
  for (let k = k0 + 1; k < upto; k++) {
    const m = c.log[k];
    if (m.t === "turn") {
      turnAt = c.at[k];
      turnPhase = s.phase;
    }
    if (m.t !== "act") continue;
    const a = m.a;
    if (ghosts.has(a.c) && a.k !== "mode") {
      out.steps++;
      if (a.k === "roll") {
        out.rolls++;
        if (turnAt >= 0 && turnPhase === "roll") out.rollGaps.push(c.at[k] - turnAt);
      } else if (a.k === "move" && roll && roll.c === a.c) out.moveGaps.push(c.at[k] - roll.at);
    }
    roll = a.k === "roll" ? { c: a.c, at: c.at[k] } : null;
    applyAction(s, a);
  }
  return out;
}

const mean = (xs: number[]) => xs.reduce((x, y) => x + y, 0) / Math.max(1, xs.length);
const fmt = (xs: number[]) =>
  xs.length ? `n ${xs.length}, min ${Math.min(...xs)}, mean ${mean(xs).toFixed(1)}, max ${Math.max(...xs)} ms` : "n 0";

/** Plays a quick match for `ms`, then reads the alarm counters and the ghost steps seen so far; everyone leaves. */
async function measure(size: number, chain: boolean, scale: number, ms: number) {
  const q = await quick(size, 1, { timeScale: scale, chain });
  await sleep(ms);
  const upto = q.cs[0].log.length;
  const stats = await stubFor(q.code).testStats();
  const steps = ghostSteps(q.cs[0], q.ghosts, upto);
  expect(q.cs[0].hashMismatches + q.cs[0].orderErrors).toBe(0);
  q.cs[0].send({ t: "leave" });
  await q.cs[0].waitClosed();
  return { stats, steps };
}

/** Waits until a ghost rolls into a choice whose planned move is due within CHAIN.step (the chained wait). */
async function ghostRolledIntoChoice(c: Client, code: string, ghosts: Set<number>, scale: number): Promise<Msg> {
  for (;;) {
    const m = await c.waitFor((x) => x.t === "act" && x.a.k === "roll" && ghosts.has(x.a.c), 10_000);
    if (c.n !== m.n + 1 || c.state.phase !== "choose" || c.state.turn !== m.a.c) continue;
    const due = await runInDurableObject(stubFor(code), (_i, st) => (st.storage.kv.get("room") as { match: { due: number } }).match.due);
    if (due - Date.now() <= CHAIN.step * scale - 20 * scale) return m;
  }
}

/** The ghost acts that followed the roll at index n (until the next roll). */
function after(c: Client, n: number): Msg[] {
  return c.log.filter((m) => m.t === "act" && m.n > n);
}

describe("alarms per ghost turn", { retry: 2 }, () => {
  it("about 2 alarms per ghost turn without chaining, about 1 with it (and fewer with several ghosts)", async () => {
    const scale = 0.05;
    const res: Record<string, Awaited<ReturnType<typeof measure>>> = {};
    for (const size of [2, 4]) {
      for (const chain of [false, true]) res[`${size}:${chain}`] = await measure(size, chain, scale, 6000);
    }
    const lines = Object.entries(res).map(([k, { stats, steps }]) => {
      const [size, chain] = k.split(":");
      return (
        `${size} seats, chain ${chain.padEnd(5)}: ghost turns ${steps.rolls}, ghost steps ${steps.steps}, alarms ${stats.alarms}` +
        ` (${(stats.alarms / steps.rolls).toFixed(2)} per ghost turn, ${(stats.alarms / steps.steps).toFixed(2)} per step),` +
        ` chained passes ${stats.chained}, longest in-request wait ${stats.longest} ms` +
        `\n    roll gaps ${fmt(steps.rollGaps)}\n    roll->move gaps ${fmt(steps.moveGaps)}`
      );
    });
    console.log(`ghost alarms (time scale ${scale}):\n  ${lines.join("\n  ")}`);
    for (const size of [2, 4]) {
      const off = res[`${size}:false`];
      const on = res[`${size}:true`];
      expect(off.steps.rolls).toBeGreaterThanOrEqual(10);
      expect(on.steps.rolls).toBeGreaterThanOrEqual(10);
      // before: one alarm per ghost step (roll, then move): ~2 per ghost turn
      expect(off.stats.chained).toBe(0);
      expect(off.stats.alarms / off.steps.steps).toBeGreaterThan(0.9);
      expect(off.stats.alarms / off.steps.rolls).toBeGreaterThan(1.6);
      // after: one per ghost turn at most (a "thinking" pause still takes its own alarm)
      expect(on.stats.chained).toBeGreaterThan(0);
      expect(on.stats.alarms / on.steps.rolls).toBeLessThanOrEqual(size === 2 ? 1.25 : 1.0);
      expect(on.stats.longest).toBeLessThanOrEqual(CHAIN.total * scale + 50);
      // the gaps people see did not change
      expect(Math.abs(mean(on.steps.moveGaps) - mean(off.steps.moveGaps))).toBeLessThan(0.3 * mean(off.steps.moveGaps));
    }
  }, 90_000);
});

describe("ghost timing with chaining", { retry: 2 }, () => {
  it("roll and roll->move gaps stay in the human-like windows, thinking pauses included (statistics)", async () => {
    const scale = 0.04;
    const q = await quick(4, 1, { timeScale: scale });
    await sleep(25_000);
    const upto = q.cs[0].log.length;
    const stats = await stubFor(q.code).testStats();
    const g = ghostSteps(q.cs[0], q.ghosts, upto);
    q.cs[0].send({ t: "leave" });
    await q.cs[0].waitClosed();
    const thinkCut = 3750 * scale; // choose <= 3.5 s, thinking >= 4 s
    const thinks = g.moveGaps.filter((x) => x > thinkCut);
    const chooses = g.moveGaps.filter((x) => x <= thinkCut);
    console.log(
      `ghost timing (scale ${scale}, chained passes ${stats.chained}, alarms ${stats.alarms}, ghost turns ${g.rolls}):\n` +
        `  roll gaps        ${fmt(g.rollGaps)} (window ${GHOST_TIMING.roll.map((x) => x * scale).join("-")})\n` +
        `  roll->move gaps  ${fmt(chooses)} (window ${GHOST_TIMING.choose.map((x) => x * scale).join("-")})\n` +
        `  thinking pauses  ${fmt(thinks)} (window ${GHOST_TIMING.think.map((x) => x * scale).join("-")}),` +
        ` ${((100 * thinks.length) / Math.max(1, g.moveGaps.length)).toFixed(1)}% of moves`,
    );
    expect(stats.chained).toBeGreaterThan(0);
    expect(g.rollGaps.length).toBeGreaterThanOrEqual(80);
    expect(g.moveGaps.length).toBeGreaterThanOrEqual(70);
    const tol = 60; // event-loop latency under parallel test files (timers never fire early)
    for (const x of g.rollGaps) {
      expect(x).toBeGreaterThanOrEqual(GHOST_TIMING.roll[0] * scale - 2);
      expect(x).toBeLessThanOrEqual(GHOST_TIMING.roll[1] * scale + tol);
    }
    for (const x of g.moveGaps) {
      expect(x).toBeGreaterThanOrEqual(GHOST_TIMING.choose[0] * scale - 2);
      expect(x).toBeLessThanOrEqual(GHOST_TIMING.think[1] * scale + tol);
    }
    // the distributions: uniform roll 0.8-2.6 s (mean 1.7 s), choose 1-3.5 s (mean 2.25 s), 8% thinking 4-6 s
    expect(mean(g.rollGaps)).toBeGreaterThan(1700 * scale * 0.85);
    expect(mean(g.rollGaps)).toBeLessThan(1700 * scale * 1.15 + 3);
    expect(mean(chooses)).toBeGreaterThan(2250 * scale * 0.85);
    expect(mean(chooses)).toBeLessThan(2250 * scale * 1.15 + 3);
    expect(thinks.length).toBeGreaterThanOrEqual(1);
    expect(thinks.length / g.moveGaps.length).toBeLessThan(0.2);
  }, 60_000);
});

describe("interruptions during the in-request wait", () => {
  it("a person leaving while a ghost's move is pending: the wait is dropped, the alarm plays the move once, on time", async () => {
    const scale = 0.2;
    const q = await quick(4, 2, { timeScale: scale });
    const [a, b] = q.cs;
    const roll = await ghostRolledIntoChoice(a, q.code, q.ghosts, scale);
    const before = await stubFor(q.code).testStats();
    b.send({ t: "leave" }); // n changes ({k: "mode", mode: "cpu"} for b's seat) while the alarm handler waits
    const move = await a.waitFor((m) => m.t === "act" && m.a.c === roll.a.c && m.a.k !== "roll", 5000);
    const afterStats = await stubFor(q.code).testStats();
    expect(move.a.k).toBe("move");
    expect(after(a, roll.n).filter((m) => m.n < move.n).map((m) => m.a.k)).toEqual(["mode"]);
    expect(afterStats.alarms).toBeGreaterThan(before.alarms); // played by the (backup) alarm, not the dropped wait
    const gap = a.at[a.log.indexOf(move)] - a.at[a.log.indexOf(roll)];
    expect(gap).toBeGreaterThanOrEqual(GHOST_TIMING.choose[0] * scale - 2);
    expect(gap).toBeLessThanOrEqual(CHAIN.step * scale + 100);
    await sleep(500);
    expect(a.log.filter((m) => m.t === "act" && m.n === move.n).length).toBe(1);
    expect(a.hashMismatches + a.orderErrors).toBe(0);
    a.send({ t: "leave" });
    await a.waitClosed();
  }, 30_000);

  it("an admin close while a ghost's move is pending: nothing more is played, the handler ends cleanly", async () => {
    const scale = 0.2;
    const q = await quick(2, 1, { timeScale: scale });
    const [a] = q.cs;
    const roll = await ghostRolledIntoChoice(a, q.code, q.ghosts, scale);
    expect(await stubFor(q.code).adminClose("test")).toBe(true);
    expect(await a.waitClosed()).toBe(4004);
    await sleep(CHAIN.step * scale + 300);
    expect(after(a, roll.n)).toEqual([]);
    expect(await rows("SELECT * FROM events WHERE code = ? AND kind = 'exception'", q.code)).toEqual([]);
    expect(await stubFor(q.code).info()).toBeNull();
  }, 30_000);

  it("an eviction mid-wait: the alarm armed at the planned time still plays the move (once)", async () => {
    const scale = 0.2;
    const q = await quick(2, 1, { timeScale: scale });
    const [a] = q.cs;
    const roll = await ghostRolledIntoChoice(a, q.code, q.ghosts, scale);
    const { due, alarm } = await runInDurableObject(stubFor(q.code), async (_i, st) => ({
      due: (st.storage.kv.get("room") as { match: { due: number } }).match.due,
      alarm: await st.storage.getAlarm(),
    }));
    expect(alarm).toBe(Math.ceil(due)); // the backup
    await evictDurableObject(stubFor(q.code));
    const move = await a.waitFor((m) => m.t === "act" && m.a.c === roll.a.c && m.a.k !== "roll", 5000);
    expect(move).toMatchObject({ n: roll.n + 1, a: { k: "move" } });
    const gap = a.at[a.log.indexOf(move)] - a.at[a.log.indexOf(roll)];
    expect(gap).toBeGreaterThanOrEqual(GHOST_TIMING.choose[0] * scale - 2);
    await sleep(400);
    expect(a.log.filter((m) => m.t === "act" && m.n === move.n).length).toBe(1);
    expect(a.hashMismatches + a.orderErrors).toBe(0);
    a.send({ t: "leave" });
    await a.waitClosed();
  }, 30_000);

  it("a second alarm running during the wait never plays a step twice", async () => {
    const scale = 0.2;
    const q = await quick(2, 1, { timeScale: scale });
    const [a] = q.cs;
    const roll = await ghostRolledIntoChoice(a, q.code, q.ghosts, scale);
    expect(await runDurableObjectAlarm(stubFor(q.code))).toBe(true); // concurrent with the waiting handler
    const move = await a.waitFor((m) => m.t === "act" && m.a.c === roll.a.c && m.a.k !== "roll", 5000);
    expect(move).toMatchObject({ n: roll.n + 1, a: { k: "move" } });
    const gap = a.at[a.log.indexOf(move)] - a.at[a.log.indexOf(roll)];
    expect(gap).toBeGreaterThanOrEqual(GHOST_TIMING.choose[0] * scale - 2);
    await sleep(600);
    for (let n = roll.n; n < a.n; n++) expect(a.log.filter((m) => m.t === "act" && m.n === n).length).toBe(1);
    expect(a.hashMismatches + a.orderErrors).toBe(0);
    a.send({ t: "leave" });
    await a.waitClosed();
  }, 30_000);
});

describe("chaining elsewhere", () => {
  it("friend-room bots (a seat that left) chain too, with their usual timing", async () => {
    const scale = 0.05;
    const { code, cs } = await lobbyOf(2, { timeScale: scale, tok: NEAR_GOAL });
    const [red, yel] = cs;
    await startAll(cs);
    red.autoplay = true;
    red.playTurn(red.state.turn);
    yel.send({ t: "leave" }); // yellow (colour 2) is a bot for good
    await finishAll([red], 25_000);
    const stats = await stubFor(code).testStats();
    const botSteps = red.log.filter((m) => m.t === "act" && m.a.c === 2 && m.a.k !== "mode").length;
    expect(botSteps).toBeGreaterThan(4);
    expect(stats.chained).toBeGreaterThan(0);
    expect(stats.alarms).toBeLessThan(botSteps);
    // bot step gaps (turn -> act) stay in TIMING's windows
    let turnAt = -1;
    for (let k = 0; k < red.log.length; k++) {
      const m = red.log[k];
      if (m.t === "turn") turnAt = m.c === 2 ? red.at[k] : -1;
      else if (m.t === "act" && m.a.c === 2 && m.a.k !== "mode" && turnAt >= 0) {
        const gap = red.at[k] - turnAt;
        expect(gap).toBeGreaterThanOrEqual(Math.min(TIMING.botRollMin, TIMING.botStepMin) * scale - 2);
        expect(gap).toBeLessThanOrEqual(Math.max(TIMING.botRollMax, TIMING.botStepMax) * scale + 60);
        turnAt = -1;
      }
    }
  }, 30_000);

  it("ghost emotes planned during a wait are still sent at their planned time", async () => {
    const scale = 0.1;
    const q = await quick(4, 1, { timeScale: scale, emoteChance: 1 });
    const [a] = q.cs;
    const planned = new Map<string, number>(); // "c:id:at" -> at
    const until = Date.now() + 6000;
    while (Date.now() < until) {
      const ge = await runInDurableObject(stubFor(q.code), (_i, st) => {
        const r = st.storage.kv.get("room") as { match?: { gemotes?: Array<{ at: number; c: number; id: string }> } } | undefined;
        return r?.match?.gemotes ?? [];
      });
      for (const e of ge) planned.set(`${e.c}:${e.id}:${e.at}`, e.at);
      await sleep(5);
    }
    const stats = await stubFor(q.code).testStats();
    a.send({ t: "leave" });
    await a.waitClosed();
    const got = a.log.map((m, k) => ({ m, at: a.at[k] })).filter((x) => x.m.t === "emote" && q.ghosts.has(x.m.c));
    expect(stats.chained).toBeGreaterThan(0);
    expect(got.length).toBeGreaterThan(0);
    let matched = 0;
    for (const { m, at } of got) {
      const cands = [...planned.entries()].filter(([k, t]) => k.startsWith(`${m.c}:${m.id}:`) && t <= at + 2).map(([, t]) => at - t);
      if (!cands.length) continue; // planned and sent between two polls
      matched++;
      expect(Math.min(...cands), JSON.stringify(m)).toBeLessThanOrEqual(40);
    }
    expect(matched).toBeGreaterThan(0);
  }, 30_000);
});
