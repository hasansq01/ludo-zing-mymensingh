// Play on in rooms (PROTOCOL.md "Play on after the first finish"): `over` only at the end of the game, the
// `finished` events in between, grants by placing (the first side wins, every other ranked side finishes, "left"
// only for a seat that left before its side was ranked), and the server's {k: "end"} once no real person is left
// unfinished (the others left, or only quick-match ghosts are still playing).
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { randomCode, type AdminSnapshot } from "../src/room";
import { eventually } from "./admin_helpers";
import { Client, createRoom, finishAll, startAll, stubFor, type Msg } from "./room_client";
import { guest, joinMatched, resetSpies, spyGrants, type Guest } from "./quick_client";

beforeEach(() => resetSpies());
afterEach(() => resetSpies());

const NEAR = [56, 56, 56, 55]; // one pawn a 1 away from home
const BASE = [-1, -1, -1, -1];

/** Every `finished` event the client's replica produced, in order (re-derived from the acts it received). */
function finishedActs(c: Client): Msg[] {
  return c.log.filter((m) => m.t === "act");
}

/** A friend room of guests (sessions, so grants are made), all in the lobby. */
async function guestsRoom(k: number, hooks: Record<string, unknown>): Promise<{ code: string; cs: Client[]; gs: Guest[] }> {
  const code = await createRoom({ ratePerSec: 1000, ...hooks });
  const gs: Guest[] = [];
  const cs: Client[] = [];
  for (let j = 0; j < k; j++) {
    const g = await guest();
    gs.push(g);
    const c = await Client.join(code, { pid: g.pid, session: g.session, name: `P${j + 1}` });
    await c.waitFor((m) => m.t === "lobby" && m.members.length === j + 1);
    cs.push(c);
  }
  return { code, cs, gs };
}

const outcomes = (grant: { results: { account_id: string; outcome: string }[] }) =>
  Object.fromEntries(grant.results.map((r) => [r.account_id, r.outcome]));

/** Plays colour c's roll and (when it has to choose) its only move, then waits for the act. */
async function rollAndMove(c: Client): Promise<void> {
  c.skip();
  c.send({ t: "roll", n: c.n });
  await c.waitFor((m) => m.t === "act" && m.a.k === "roll");
  if (c.state.phase === "choose") {
    c.send({ t: "move", n: c.n, i: 3 });
    await c.waitFor((m) => m.t === "act" && m.a.k === "move");
  }
}

describe("Ludo play on", () => {
  it("4 players: three finishes before over; over carries the full order; grants by placing", async () => {
    const grants = spyGrants();
    const { cs, gs } = await guestsRoom(4, { tok: [NEAR, NEAR, NEAR, [20, -1, -1, -1]], dice: [1, 1, 1] });
    await startAll(cs);
    const [red, grn, yel, blu] = cs;
    await rollAndMove(red);
    expect([red.state.phase, red.state.finished, red.state.turn]).toEqual(["roll", [0], 1]);
    expect(red.all("over")).toEqual([]);
    const t1 = await blu.waitFor((m) => m.t === "turn" && m.c === 1);
    expect(t1.c).toBe(1);
    await rollAndMove(grn);
    expect([grn.state.phase, grn.state.finished, grn.state.turn]).toEqual(["roll", [0, 1], 2]);
    expect(cs.every((c) => c.all("over").length === 0)).toBe(true);
    await rollAndMove(yel);
    const overs = await finishAll(cs);
    expect(overs[0]).toMatchObject({ winner: 0, finished: [0, 1, 2, 3] });
    expect(overs[0].standings.map((e: Msg) => [e.color, e.place, e.finished])).toEqual([
      [0, 1, true], [1, 2, true], [2, 3, true], [3, 4, false],
    ]);
    expect(finishedActs(blu).length).toBe(6); // 3 rolls + 3 moves: nobody acted after the third finish
    await eventually(async () => grants.length === 1, 5000, "grant");
    expect(grants[0].results.map((r) => r.outcome)).toEqual(["win", "finish", "finish", "finish"]);
    expect(grants[0].results.map((r) => r.account_id)).toEqual(gs.map((g) => g.account));
  });

  it("a player who finished and then left keeps the win; one who left before finishing gets left", async () => {
    const grants = spyGrants();
    const { cs, gs } = await guestsRoom(3, { tok: [NEAR, NEAR, BASE], dice: [1, 1], timeScale: 0.02 });
    await startAll(cs);
    const [red, grn, yel] = cs;
    await rollAndMove(red); // Red 1st
    red.send({ t: "leave" });
    await red.waitClosed();
    grn.send({ t: "leave" }); // Green leaves before finishing: its bot rolls the 1 and comes home 2nd
    await grn.waitClosed();
    const [over] = await finishAll([yel]);
    expect(over).toMatchObject({ winner: 0, finished: [0, 1, 2] });
    await eventually(async () => grants.length === 1, 5000, "grant");
    const by = outcomes(grants[0]);
    expect([by[gs[0].account], by[gs[1].account], by[gs[2].account]]).toEqual(["win", "left", "finish"]);
  });

  it("everyone still playing leaves: the server ends the match with {k: end}", async () => {
    const grants = spyGrants();
    const { cs, gs } = await guestsRoom(3, { tok: [NEAR, BASE, BASE], dice: [1] });
    await startAll(cs);
    const [red, grn, yel] = cs;
    await rollAndMove(red);
    grn.send({ t: "leave" });
    await grn.waitClosed();
    expect(red.all("over")).toEqual([]); // Yellow is still playing
    yel.send({ t: "leave" });
    const [over] = await finishAll([red]);
    const acts = red.all("act");
    expect(acts.at(-1)?.a).toEqual({ k: "end" });
    expect(over).toMatchObject({ winner: 0 });
    expect(over.finished[0]).toBe(0);
    expect(over.finished.length).toBe(3);
    await eventually(async () => grants.length === 1, 5000, "grant");
    const by = outcomes(grants[0]);
    expect([by[gs[0].account], by[gs[1].account], by[gs[2].account]]).toEqual(["win", "left", "left"]);
  });

  it("the finisher left, then everyone else: the match still ends and the finisher keeps the win", async () => {
    const grants = spyGrants();
    const { cs, gs } = await guestsRoom(3, { tok: [NEAR, BASE, BASE], dice: [1] });
    await startAll(cs);
    const [red, grn, yel] = cs;
    await rollAndMove(red);
    red.send({ t: "leave" });
    await red.waitClosed();
    grn.send({ t: "leave" });
    await grn.waitClosed();
    expect(yel.all("over")).toEqual([]);
    yel.send({ t: "leave" });
    await yel.waitClosed();
    await eventually(async () => grants.length === 1, 5000, "grant");
    const by = outcomes(grants[0]);
    expect([by[gs[0].account], by[gs[1].account], by[gs[2].account]]).toEqual(["win", "left", "left"]);
  });
});

describe("quick match: only ghosts left unfinished", () => {
  it("the human's finish is followed by {k: end}: the ghosts are ranked by progress", async () => {
    const grants = spyGrants();
    const code = randomCode();
    const g = await guest();
    const hooks = { ratePerSec: 1000, timeScale: 0.02, tok: [NEAR, NEAR, NEAR, NEAR] };
    const spec = { game: "ludo" as const, size: 4, humans: [{ account_id: g.account, pid: g.pid, name: "Me", avatar: "pawn-red", frame: "classic", level: 1 }], hooks };
    const res = await stubFor(code).initQuick(code, spec);
    expect(res).not.toBeNull();
    const snap = (await stubFor(code).adminSnapshot()) as unknown as AdminSnapshot;
    const me = snap.members.find((m) => !m.ghost)!;
    const h = me.color;
    // the ghosts before you roll 2s (55 + 2 overshoots: no move), you roll the 1 that brings you home first
    await stubFor(code).testHooks({ ...hooks, dice: [...Array(h).fill(2), 1] });
    const c = await joinMatched(code, res!.tokens[g.account], g);
    c.autoplay = true;
    await c.wait("start");
    c.playTurn(c.state.turn);
    const [over] = await finishAll([c]);
    const acts = c.all("act");
    expect(acts.at(-1)?.a).toEqual({ k: "end" });
    expect(acts.at(-2)?.a).toMatchObject({ k: "move", c: h });
    expect(over.winner).toBe(h);
    expect(over.finished.length).toBe(4);
    expect(over.standings.filter((e: Msg) => e.finished).map((e: Msg) => e.color)).toEqual([h]);
    await eventually(async () => grants.length === 1, 5000, "grant");
    expect(grants[0].results).toEqual([{ account_id: g.account, outcome: "win" }]);
  });
});

describe("S&L play on", () => {
  it("3 players: two reach 100 before over; the order in over", async () => {
    const { cs } = await guestsRoom(3, { slPos: [97, 98, 50], dice: [3, 2] });
    cs[0].send({ t: "settings", game: "sl" });
    await cs[2].waitFor((m) => m.t === "lobby" && m.settings.game === "sl");
    await startAll(cs);
    const [red, grn] = cs;
    red.send({ t: "roll", n: red.n });
    await red.waitFor((m) => m.t === "act" && m.a.k === "roll");
    expect([red.state.phase, red.state.finished, red.state.turn]).toEqual(["roll", [0], 1]);
    grn.send({ t: "roll", n: grn.n });
    const [over] = await finishAll(cs);
    expect(over).toMatchObject({ winner: 0, finished: [0, 1, 2] });
    expect(over.standings.map((e: Msg) => [e.color, e.place, e.finished])).toEqual([[0, 1, true], [1, 2, true], [2, 3, false]]);
  });
});
