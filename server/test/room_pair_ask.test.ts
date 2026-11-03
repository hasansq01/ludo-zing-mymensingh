// "Ask before pairing" online (PROTOCOL.md "Ask before pairing"): in friend and quick rooms alike each person's own
// choice (hello.pair_ask) is dealt to their colour as state.pair_ask_by; the host has no room rule for it (an old
// client's settings.pair_ask is ignored). An asked player gets the `pair_ask` phase and answers with `pair {yes}`;
// nobody asked pairs by itself off safe squares. No answer before the pair timer: the server answers what would have
// happened unasked (defaultPairAnswer). Ghosts are asked and answer after a short delay, yes or no (ghostPairOdds).
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { GHOST_PAIR, GHOST_TIMING, ghostPairOdds, ghostPairYes } from "../src/ghosts";
import * as R from "../src/rules/ludo";
import { Mulberry32 } from "../src/rules/rng";
import { Client, lobbyOf, startAll, type Msg } from "./room_client";
import { guest, joinMatched, mmHooks, queueAll, resetSpies, type Guest } from "./quick_client";

beforeEach(() => resetSpies());
afterEach(() => resetSpies());

// Red and Yellow: a pawn on progress 10 and one on 7 (both off the safe squares). The first roll (Red) is a 3: the
// pawn on 7 lands on its partner on 10.
const TOK = [
  [10, 7, -1, -1],
  [-1, -1, -1, -1],
  [10, 7, -1, -1],
  [-1, -1, -1, -1],
];

// As TOK, plus a pair on progress 37 for both colours: it stands just ahead of the other colour's pawn on 10, so with
// a 3 the only legal move is 7 -> 10 (a single can't pass a pair; a pair needs an even roll). Lets a ghost's move be
// known whichever colour it was seated on.
const TOK_ONE_MOVE = [
  [10, 7, 37, 37],
  [-1, -1, -1, -1],
  [10, 7, 37, 37],
  [-1, -1, -1, -1],
];
const PAIRS_ONE_MOVE = [
  { c: 0, a: 2, b: 3 },
  { c: 2, a: 2, b: 3 },
];

/** Red rolls (dice hook: 3) and moves the pawn on 7 onto the one on 10; returns the move's act. */
async function redLandsOnPartner(red: Client): Promise<Msg> {
  await red.waitFor((m) => m.t === "turn" && m.c === 0);
  red.send({ t: "roll", n: red.n });
  const roll = await red.waitFor((m) => m.t === "act" && m.a.k === "roll");
  expect(roll.a.v).toBe(3);
  expect(red.state.phase).toBe("choose");
  red.send({ t: "move", n: red.n, i: 1 });
  return red.waitFor((m) => m.t === "act" && m.a.k === "move");
}

describe("friend rooms: each person's own choice", () => {
  it("Red's setting on, Yellow's off: Red is asked (a turn deadline), answers no, the pawns stay single", async () => {
    const { cs } = await lobbyOf(2, { tok: TOK, dice: [3] }, [true, false]);
    const [red, yel] = cs;
    const st = await startAll(cs);
    expect(st[0].state.pair_ask).toBe(false);
    expect(st[0].state.pair_ask_by).toEqual([true, false, false, false]);
    await redLandsOnPartner(red);
    expect(red.state.phase).toBe("pair_ask");
    expect(red.state.pending).toMatchObject({ c: 0, i: 1, partner: 0 });
    const turn = await red.waitFor((m) => m.t === "turn" && m.c === 0);
    expect(turn.deadline).toBeGreaterThan(turn.now); // the pair prompt's own timer
    yel.send({ t: "pair", n: yel.n, yes: true });
    expect(await yel.wait("error")).toMatchObject({ code: "not_your_turn" });
    red.send({ t: "pair", n: red.n, yes: false });
    const a = await red.waitFor((m) => m.t === "act" && m.a.k === "pair");
    expect(a.a).toEqual({ k: "pair", c: 0, yes: false });
    expect(red.state.pairs).toEqual([]);
    expect(red.state.tok[0]).toEqual([10, 10, -1, -1]);
    for (const c of cs) expect(c.hashMismatches).toBe(0);
  });

  it("answered yes: the pair forms", async () => {
    const { cs } = await lobbyOf(2, { tok: TOK, dice: [3] }, [true, true]);
    const [red] = cs;
    await startAll(cs);
    await redLandsOnPartner(red);
    red.send({ t: "pair", n: red.n, yes: true });
    await red.waitFor((m) => m.t === "act" && m.a.k === "pair");
    expect(red.state.pairs).toEqual([{ c: 0, a: 0, b: 1 }]);
  });

  it("the host's (old) settings.pair_ask changes nothing: a guest who turned it on is still asked", async () => {
    // Red (host) off, Yellow on; the host's old client turns the room rule "on" and then "off": both ignored
    const { cs } = await lobbyOf(2, { tok: [TOK[0], TOK[1], [7, 4, -1, -1], TOK[3]], dice: [3, 3] }, [false, true]);
    const [red, yel] = cs;
    red.send({ t: "settings", pair_ask: true });
    const l = await yel.waitFor((m) => m.t === "lobby");
    expect(l.settings).toEqual({ teams: false, game: "ludo" });
    red.send({ t: "settings", pair_ask: false });
    await yel.waitFor((m) => m.t === "lobby");
    const st = await startAll(cs);
    expect(st[0].state.pair_ask_by).toEqual([false, false, true, false]);
    // Red (off): pairs by itself
    await redLandsOnPartner(red);
    expect(red.state.phase).toBe("roll");
    expect(red.state.pairs).toEqual([{ c: 0, a: 0, b: 1 }]);
    // Yellow (on): 4 -> 7 lands on its pawn on 7, and is asked
    await yel.waitFor((m) => m.t === "turn" && m.c === 2);
    yel.send({ t: "roll", n: yel.n });
    await yel.waitFor((m) => m.t === "act" && m.a.k === "roll");
    yel.send({ t: "move", n: yel.n, i: 1 });
    await yel.waitFor((m) => m.t === "act" && m.a.k === "move");
    expect(yel.state.phase).toBe("pair_ask");
    for (const c of cs) expect(c.hashMismatches).toBe(0);
  });

  it("not sent (clients before it): off, pairs form by themselves as before", async () => {
    const { cs } = await lobbyOf(2, { tok: TOK, dice: [3] });
    const st = await startAll(cs);
    expect(st[0].state.pair_ask_by).toEqual([false, false, false, false]);
    await redLandsOnPartner(cs[0]);
    expect(cs[0].state.phase).toBe("roll");
    expect(cs[0].state.pairs).toEqual([{ c: 0, a: 0, b: 1 }]);
    expect(cs[0].all("act").some((m) => m.a.k === "pair")).toBe(false);
  });

  it("no answer: the pair timer answers what would have happened unasked (here: pair up) and play goes on", async () => {
    const { cs } = await lobbyOf(2, { tok: TOK, dice: [3], timeScale: 0.05 }, [true, true]);
    const [red] = cs;
    await startAll(cs);
    await redLandsOnPartner(red);
    expect(red.state.phase).toBe("pair_ask");
    const t0 = Date.now();
    const a = await red.waitFor((m) => m.t === "act" && m.a.k === "pair", 4000);
    expect(Date.now() - t0).toBeGreaterThanOrEqual(300); // 10 s x 0.05, not at once
    expect(a.a).toEqual({ k: "pair", c: 0, yes: true });
    expect(red.state.pairs).toEqual([{ c: 0, a: 0, b: 1 }]);
    for (const c of cs) expect(c.hashMismatches).toBe(0);
  });

  it("no answer on a safe square: the timer keeps them single (unasked, they wouldn't pair there)", async () => {
    // Red: pawns on 8 (a star square) and 5; a 3 lands 5 -> 8
    const { cs } = await lobbyOf(2, { tok: [[8, 5, -1, -1], TOK[1], TOK[2], TOK[3]], dice: [3], timeScale: 0.05 }, [true, true]);
    const [red] = cs;
    await startAll(cs);
    await red.waitFor((m) => m.t === "turn" && m.c === 0);
    red.send({ t: "roll", n: red.n });
    await red.waitFor((m) => m.t === "act" && m.a.k === "roll");
    red.send({ t: "move", n: red.n, i: 1 });
    await red.waitFor((m) => m.t === "act" && m.a.k === "move");
    expect(red.state.phase).toBe("pair_ask"); // asked anywhere, safe squares too
    const a = await red.waitFor((m) => m.t === "act" && m.a.k === "pair", 4000);
    expect(a.a).toEqual({ k: "pair", c: 0, yes: false });
    expect(red.state.pairs).toEqual([]);
  });
});

describe("quick rooms: each person's own choice", () => {
  /** A 2-human quick match (no ghosts); pairAsk per guest (undefined: not sent). Returns the clients, Red first. */
  async function quick2(asks: Array<boolean | undefined>, room: Record<string, unknown> = {}) {
    await mmHooks("ludo", 2, { wait: 5000, room: { tok: TOK, dice: [3], ...room } });
    const gs: Guest[] = [await guest(), await guest()];
    const { matched } = await queueAll("ludo", 2, gs);
    const cs: Client[] = [];
    for (let k = 0; k < 2; k++) cs.push(await joinMatched(matched[k].code, matched[k].token, gs[k], `Human${k + 1}`, asks[k]));
    const starts = await Promise.all(cs.map((c) => c.wait("start", 8000)));
    const colorOf = (k: number) => starts[k].seats.find((st: Msg) => st.id === cs[k].id).color as number;
    const red = colorOf(0) === 0 ? 0 : 1; // seats are shuffled in quick rooms
    return { cs, starts, red: cs[red], yel: cs[1 - red], redAsk: asks[red], yelAsk: asks[1 - red] };
  }

  it("the colour of a person who turned it on is asked; the other's pawns pair by themselves", async () => {
    const q = await quick2([true, false]);
    const by = q.starts[0].state.pair_ask_by as boolean[];
    expect(q.starts[0].state.pair_ask).toBe(false);
    expect(by[0]).toBe(q.redAsk === true);
    expect(by[2]).toBe(q.yelAsk === true);
    expect(by[1]).toBe(false);
    expect(by[3]).toBe(false);
    await redLandsOnPartner(q.red);
    if (q.redAsk) {
      expect(q.red.state.phase).toBe("pair_ask");
      q.red.send({ t: "pair", n: q.red.n, yes: false });
      await q.red.waitFor((m) => m.t === "act" && m.a.k === "pair");
      expect(q.red.state.pairs).toEqual([]);
    } else {
      expect(q.red.state.phase).toBe("roll");
      expect(q.red.state.pairs).toEqual([{ c: 0, a: 0, b: 1 }]);
    }
    for (const c of q.cs) expect(c.hashMismatches).toBe(0);
    for (const c of q.cs) c.close();
  });

  it("both on: Red is asked", async () => {
    const q = await quick2([true, true]);
    expect(q.starts[0].state.pair_ask_by).toEqual([true, false, true, false]);
    await redLandsOnPartner(q.red);
    expect(q.red.state.phase).toBe("pair_ask");
    await q.yel.waitFor((m) => m.t === "act" && m.a.k === "move");
    expect(q.yel.state.phase).toBe("pair_ask"); // the other replica agrees (the prompt is Red's alone)
    q.red.send({ t: "pair", n: q.red.n, yes: true });
    await q.yel.waitFor((m) => m.t === "act" && m.a.k === "pair");
    expect(q.yel.state.pairs).toEqual([{ c: 0, a: 0, b: 1 }]);
    for (const c of q.cs) expect(c.hashMismatches).toBe(0);
    for (const c of q.cs) c.close();
  });

  it("not sent (clients before it): off, pairs form by themselves as before", async () => {
    const q = await quick2([undefined, undefined]);
    expect(q.starts[0].state.pair_ask_by).toEqual([false, false, false, false]);
    await redLandsOnPartner(q.red);
    expect(q.red.state.phase).toBe("roll");
    expect(q.red.state.pairs).toEqual([{ c: 0, a: 0, b: 1 }]);
    for (const c of q.cs) c.close();
  });
});

describe("ghosts answer like people", () => {
  it("a ghost is asked, waits a human-like moment, then answers; the person's replica follows", async () => {
    const SCALE = 0.05;
    await mmHooks("ludo", 2, { wait: 200, room: { tok: TOK_ONE_MOVE, pairs: PAIRS_ONE_MOVE, dice: [3, 3], timeScale: SCALE } });
    const g = await guest();
    const { matched } = await queueAll("ludo", 2, [g]);
    const c = await joinMatched(matched[0].code, matched[0].token, g, "Solo", false);
    const st = await c.wait("start", 8000);
    const mine = st.seats.find((x: Msg) => x.id === c.id).color as number;
    const ghost = 2 - mine;
    expect(st.state.pair_ask_by[mine]).toBe(false);
    expect(st.state.pair_ask_by[ghost]).toBe(true); // ghosts are asked
    expect(st.state.pairs).toEqual(PAIRS_ONE_MOVE);
    // play my turn when it comes (my setting is off: my landing pairs by itself)
    c.policy = { pick: () => 0 };
    c.autoplay = true;
    c.playTurn(c.state.turn);
    const offerAt = await (async () => {
      for (;;) {
        await c.waitFor((m) => m.t === "act" && m.a.k === "move" && m.a.c === ghost, 8000);
        if (c.state.phase === "pair_ask") return Date.now();
      }
    })();
    const ans = await c.waitFor((m) => m.t === "act" && m.a.k === "pair", 8000);
    expect(ans.a.c).toBe(ghost);
    expect(typeof ans.a.yes).toBe("boolean");
    expect(Date.now() - offerAt).toBeGreaterThanOrEqual(GHOST_TIMING.pair[0] * SCALE * 0.8);
    expect(c.state.pairs.some((q: R.Pair) => q.c === ghost && q.a === 0 && q.b === 1)).toBe(ans.a.yes);
    expect(c.hashMismatches).toBe(0);
    c.autoplay = false;
    c.close();
  });

  it("ghostPairOdds: likely yes under threat, mostly no on a safe square or near home; both answers happen", () => {
    const s = R.newGame(["human", "off", "human", "off"], false, { pair_ask_by: [true, false, true, false] });
    const ask = (c: number, to: number) => {
      s.phase = "pair_ask";
      s.pending = { c, i: 1, to, extra: false, partner: 0 };
    };
    s.tok[0] = [10, 10, -1, -1];
    s.tok[2] = [-1, -1, -1, -1];
    ask(0, 10);
    expect(ghostPairOdds(s)).toBe(GHOST_PAIR.calm);
    s.tok[2] = [32, -1, -1, -1]; // Yellow's single on abs 6: 4 squares behind Red's 10
    expect(ghostPairOdds(s)).toBe(GHOST_PAIR.threat);
    s.tok[0] = [8, 8, -1, -1];
    ask(0, 8); // a star square
    expect(ghostPairOdds(s)).toBe(GHOST_PAIR.safe);
    s.tok[0] = [46, 46, -1, -1];
    ask(0, 46);
    expect(ghostPairOdds(s)).toBe(GHOST_PAIR.home);
    expect(GHOST_PAIR.threat).toBeGreaterThan(GHOST_PAIR.calm);
    expect(GHOST_PAIR.calm).toBeGreaterThan(GHOST_PAIR.safe);
    // sometimes yes, sometimes no, near the odds
    s.tok[0] = [10, 10, -1, -1];
    s.tok[2] = [-1, -1, -1, -1];
    ask(0, 10);
    const rng = new Mulberry32(7);
    let yes = 0;
    for (let k = 0; k < 2000; k++) if (ghostPairYes(s, rng)) yes++;
    expect(yes / 2000).toBeGreaterThan(GHOST_PAIR.calm - 0.05);
    expect(yes / 2000).toBeLessThan(GHOST_PAIR.calm + 0.05);
  });

  it("defaultPairAnswer: yes off the safe squares, no on them, false outside the question", () => {
    const s = R.newGame(["human", "off", "human", "off"], false, { pair_ask_by: [true, false, true, false] });
    expect(R.defaultPairAnswer(s)).toBe(false);
    s.phase = "pair_ask";
    s.pending = { c: 0, i: 1, to: 10, extra: false, partner: 0 };
    expect(R.defaultPairAnswer(s)).toBe(true);
    s.pending = { c: 2, i: 1, to: 8, extra: false, partner: 0 }; // Yellow 8 = abs 34, a star
    expect(R.defaultPairAnswer(s)).toBe(false);
  });
});
