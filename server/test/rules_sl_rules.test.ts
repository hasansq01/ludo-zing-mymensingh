// Port of godot/tests/test_snakes_ladders.gd: board data, the landing rule (both entry rules), the reward replay,
// setup, real turns with forced dice, rewards and standings. (The SLTile checks there test the Godot UI.)
import { describe, expect, it } from "vitest";
import * as SL from "../src/rules/sl";
import type { SlState } from "../src/rules/sl";
import { Mulberry32 } from "../src/rules/rng";

const LA = SL.LADDERS;
const SN = SL.SNAKES;
const keys = (o: Readonly<Record<number, number>>): number[] => Object.keys(o).map(Number);

/** The computers roll until done (test_snakes_ladders.gd roll_until). */
function rollUntil(g: SlState, done: () => boolean, rng: Mulberry32): void {
  for (let k = 0; k < 200; k++) {
    if (done()) return;
    SL.applyRoll(g, rng.randiRange(1, 6));
  }
}

describe("board data and the landing rule", () => {
  it("ladders go up, snakes go down, no overlap", () => {
    expect(keys(LA).every((a) => LA[a] > a) && keys(SN).every((a) => SN[a] < a)).toBe(true);
    expect(keys(LA).every((k) => !(k in SN))).toBe(true);
    expect(100 in SN).toBe(false);
  });

  it("plain move", () => {
    expect(SL.land(10, 2)).toEqual({ to: 12, steps: 2 });
  });

  for (const n1 of [false, true]) {
    it(`[need_one ${n1}] off the board, a 1 enters on square 1 (no ladder there any more)`, () => {
      const r = SL.land(0, 1, n1);
      expect(r.to === 1 && r.steps === 1 && !("ladder" in r)).toBe(true);
    });
  }

  it("removed ladders: no 1 -> 38 and no 80 -> 100", () => {
    expect(1 in LA || 80 in LA).toBe(false);
    expect(Object.values(LA).includes(38) || Object.values(LA).includes(100)).toBe(false);
    expect(keys(LA).length).toBe(7);
    expect(SL.land(77, 3).to).toBe(80);
    expect("ladder" in SL.land(77, 3)).toBe(false);
    expect(SL.land(0, 1).to).toBe(1);
  });

  it("every remaining ladder climbs, every snake slides", () => {
    for (const [f, t] of [[4, 14], [9, 31], [21, 42], [28, 84], [36, 44], [51, 67], [71, 91]]) {
      expect(SL.land(f - 1, 1)).toEqual({ to: t, steps: 1, via: f, ladder: true });
    }
    for (const h of keys(SN)) expect(SL.land(h - 2, 2)).toEqual({ to: SN[h], steps: 2, via: h, snake: true });
  });

  it("need a 1: off the board, 2-6 never enter", () => {
    for (const v of [2, 3, 4, 5, 6]) expect(SL.land(0, v, true)).toEqual({ to: 0, steps: 0, wait: true });
  });

  it("default: off the board, every roll v moves to square v", () => {
    for (const v of [1, 2, 3, 5, 6]) {
      const r = SL.land(0, v);
      expect(r.to === v && r.steps === v && !("wait" in r)).toBe(true);
    }
    expect(SL.land(0, 4)).toEqual({ to: 14, steps: 4, via: 4, ladder: true });
    expect(SL.land(0, 3)).toEqual(SL.land(0, 3, false));
    expect(SL.land(0, 3).to).toBe(3);
  });

  it("on the board", () => {
    for (const v of [1, 2, 3, 5, 6]) expect(SL.land(10, v).to).not.toBe(10);
    expect(SL.land(3, 1).to).toBe(14);
    expect(SL.land(3, 1).ladder).toBe(true);
    expect(SL.land(13, 3).to).toBe(6);
    expect(SL.land(13, 3).snake).toBe(true);
    expect(SL.land(97, 5)).toEqual({ to: 97, steps: 0, over: true });
    expect(SL.land(97, 3).to).toBe(100);
  });
});

describe("reward replay", () => {
  const PATH = [1, 3, 6, 1, 6, 3, 4, 6, 3]; // 1, 4>14, 20, 21>42, 48, 51>67, 71>91, 97, 100
  it("a real path reaches 100; the old 1 -> 38 shortcut and invented rolls do not", () => {
    expect(SL.replayReaches100(PATH)).toBe(true);
    expect(SL.replayReaches100([1, 6, 6, 1, 4, 6, 3])).toBe(false);
    expect(SL.replayReaches100([3])).toBe(false);
    expect(SL.replayReaches100([7, 7])).toBe(false);
    expect(SL.replayReaches100([2.5])).toBe(false);
    expect(SL.replayReaches100([0])).toBe(false);
    expect(SL.replayReaches100(["1", 3] as unknown[])).toBe(false);
    expect(SL.replayReaches100([true, 3] as unknown[])).toBe(false);
    expect(SL.replayReaches100([NaN])).toBe(false);
  });

  it("need a 1", () => {
    expect(SL.replayReaches100([6, 6, 1, 4, 6, 3], true)).toBe(false);
    expect(SL.replayReaches100(PATH, true)).toBe(true);
    const waited = [4, 2, ...PATH];
    expect(SL.replayReaches100(waited, true)).toBe(true);
    expect(SL.replayReaches100(waited)).toBe(false);
  });

  it("any roll: 4 > 14, 20, 21 > 42, 48, 51 > 67, 71 > 91, 97, 100", () => {
    expect(SL.replayReaches100([4, 6, 1, 6, 3, 4, 6, 3])).toBe(true);
    expect(SL.replayReaches100([4, 6, 1, 6, 3, 4, 6, 3], true)).toBe(false);
  });

  it("rolls that came through JSON still count", () => {
    expect(SL.replayReaches100(JSON.parse("[1, 3, 6, 1, 6, 3, 4, 6, 3]"))).toBe(true);
    expect(SL.replayReaches100(JSON.parse("[1.0, 3.0, 6, 1, 6, 3, 4, 6, 3]"), true)).toBe(true);
  });
});

describe("setup", () => {
  it("vs Computer and Pass & Play", () => {
    let g = SL.newGame("cpu", 3, 2);
    expect(g.mode).toBe("cpu");
    expect(g.players.map((p) => p.c)).toEqual([2, 3, 0]);
    expect(g.players.map((p) => p.name)).toEqual(["You", "Mocha", "Biscotti"]);
    expect(g.players.map((p) => [p.you, p.cpu])).toEqual([[true, false], [false, true], [false, true]]);
    g = SL.newGame("local", 4);
    expect(g.mode === "local" && g.players.length === 4).toBe(true);
    expect(g.players.map((p) => p.name)).toEqual(["Red", "Green", "Yellow", "Blue"]);
    expect(g.players.every((p) => !p.you && !p.cpu && p.pos === 0 && p.rolls.length === 0)).toBe(true);
    expect(g).toEqual({
      mode: "local", turn: 0, phase: "roll", sixes: 0, winner: -1, paid: false, players: g.players, need_one: false,
      finished: [],
    });
  });

  it("need_one", () => {
    let g = SL.newGame("local", 4);
    expect(g.need_one === false && !SL.needsOne(g) && SL.newGame("cpu", 2).need_one === false).toBe(true);
    g = SL.newGame("cpu", 2, 1, { need_one: true });
    expect(g.need_one === true && SL.needsOne(g) && g.players[0].c === 1).toBe(true);
    expect(SL.needsOne({})).toBe(false); // a state saved before the option
    const rt = JSON.parse(JSON.stringify(g)) as SlState;
    expect(rt.need_one === true && rt.players.length === 2).toBe(true);
  });
});

describe("turns", () => {
  it("Pass & Play, default entry rule (any roll enters)", () => {
    let g = SL.newGame("local", 2);
    const [q0, q1] = g.players;
    const ev = SL.applyRoll(g, 3);
    expect(q0.pos === 3 && g.turn === 1).toBe(true);
    expect(ev).toEqual([
      { type: "rolled", turn: 0, v: 3 },
      { type: "move", turn: 0, from: 0, to: 3, steps: 3, via: 0, ladder: false, snake: false },
      { type: "turn", turn: 1, again: false },
    ]);
    SL.applyRoll(g, 4);
    expect(q1.pos === 14 && q1.ladders === 1 && g.turn === 0).toBe(true);
    g = SL.newGame("local", 2);
    SL.applyRoll(g, 6);
    expect(g.players[0].pos === 6 && g.turn === 0 && g.sixes === 1).toBe(true);
    g = SL.newGame("local", 2);
    SL.applyRoll(g, 1);
    expect(g.players[0].pos === 1 && g.turn === 1).toBe(true);
  });

  it("Pass & Play, house rule \"Need a 1 to start\"", () => {
    const g = SL.newGame("local", 2, 0, { need_one: true });
    const [p0, p1] = g.players;
    for (const v of [2, 3, 4, 5]) {
      const ev = SL.applyRoll(g, v);
      expect(p0.pos === 0 && g.turn === 1).toBe(true);
      expect(ev[1]).toEqual({ type: "wait", turn: 0, v, need: 100 });
      g.turn = 0;
      g.phase = "roll";
    }
    expect(p0.rolls).toEqual([2, 3, 4, 5]);
    const ev6 = SL.applyRoll(g, 6);
    expect(p0.pos === 0 && g.turn === 0).toBe(true);
    expect(ev6[2]).toEqual({ type: "turn", turn: 0, again: true });
    g.sixes = 0;
    SL.applyRoll(g, 1);
    expect(p0.pos === 1 && p0.ladders === 0 && g.turn === 1).toBe(true);
    p0.pos = 3; p1.pos = 0; g.turn = 0;
    SL.applyRoll(g, 1);
    expect(p0.pos).toBe(14); // after entering, a 1 is an ordinary move (3 -> 4 climbs to 14)
    p1.pos = 2;
    SL.applyRoll(g, 4);
    expect(p1.pos === 6 && g.turn === 0).toBe(true);
    g.turn = 1;
    SL.applyRoll(g, 6);
    expect(p1.pos === 12 && g.turn === 1).toBe(true);
    SL.applyRoll(g, 2);
    expect(p1.pos === 14 && g.turn === 0).toBe(true);
    p0.pos = 13;
    SL.applyRoll(g, 3);
    expect(p0.pos === 6 && p0.snakes === 1).toBe(true);
    p1.pos = 97;
    const evOver = SL.applyRoll(g, 5);
    expect(p1.pos === 97 && g.turn === 0).toBe(true);
    expect(evOver[1]).toEqual({ type: "over", turn: 1, v: 5, need: 3 });
    p0.pos = 40;
    SL.applyRoll(g, 6); SL.applyRoll(g, 6);
    const ev3 = SL.applyRoll(g, 6);
    expect(p0.pos === 52 && g.sixes === 0 && g.turn === 1).toBe(true);
    expect(ev3).toEqual([
      { type: "rolled", turn: 0, v: 6 },
      { type: "three_sixes", turn: 0 },
      { type: "turn", turn: 1, again: false },
    ]);
    const evWin = SL.applyRoll(g, 3);
    expect(g.phase === "over" && g.winner === 1).toBe(true);
    expect(evWin.slice(-2)).toEqual([
      { type: "finished", turn: 1, c: 1, place: 1 },
      { type: "win", turn: 1, order: [1, 0] }, // two players: the second is ranked by square
    ]);
    expect(SL.claimWinReward(g)).toBe(0); // Pass & Play: no coins
    expect(SL.applyRoll(g, 4)).toEqual([]); // the game is over
    expect(p0.rolls.at(-1)).toBe(6);
  });
});

describe("vs Computer: rewards and the computer's turn", () => {
  it("the computer takes its own turn; a real win pays once", () => {
    const rng = new Mulberry32(7);
    const g = SL.newGame("cpu", 2);
    expect(g.players[0].you && g.players[1].cpu).toBe(true);
    SL.applyRoll(g, 2);
    rollUntil(g, () => g.turn === 0, rng);
    expect(g.players[1].rolls.length >= 1 && g.turn === 0 && g.phase === "roll").toBe(true);
    const me = g.players[0];
    me.pos = 97;
    me.rolls = [1, 3, 6, 1, 6, 3, 4, 6];
    SL.applyRoll(g, 3);
    const paid = SL.claimWinReward(g);
    expect(g.phase === "over" && paid === 100 && g.paid && SL.claimWinReward(g) === 0).toBe(true);
    expect(SL.claimPlayReward(g)).toBe(0);
  });

  it("losing pays the participation reward once; Pass & Play pays none", () => {
    const gl = SL.newGame("cpu", 2);
    gl.players[1].pos = 97;
    gl.turn = 1;
    SL.applyRoll(gl, 3);
    expect(gl.phase === "over" && gl.winner === 1 && SL.claimWinReward(gl) === 0).toBe(true);
    expect(SL.claimPlayReward(gl)).toBe(SL.PLAY_REWARD);
    expect(SL.claimPlayReward(gl)).toBe(0);
    const gp = SL.newGame("local", 2);
    gp.players[1].pos = 97;
    gp.turn = 1;
    SL.applyRoll(gp, 3);
    expect(gp.phase === "over" && SL.claimPlayReward(gp) === 0).toBe(true);
  });

  it("the reward replay uses the game's rule", () => {
    let g = SL.newGame("cpu", 2);
    g.players[0].pos = 97;
    g.players[0].rolls = [];
    SL.applyRoll(g, 3);
    expect(g.phase === "over" && SL.claimWinReward(g) === 0 && !g.paid).toBe(true);
    g = SL.newGame("cpu", 2);
    g.players[0].pos = 97;
    g.players[0].rolls = [4, 6, 1, 6, 3, 4, 6];
    SL.applyRoll(g, 3);
    expect(SL.claimWinReward(g)).toBe(100);
    g = SL.newGame("cpu", 2, 0, { need_one: true });
    g.players[0].pos = 97;
    g.players[0].rolls = [4, 6, 1, 6, 3, 4, 6];
    SL.applyRoll(g, 3);
    expect(g.phase === "over" && SL.claimWinReward(g) === 0).toBe(true);
  });
});

describe("standings", () => {
  it("by square, ties in turn order; the winner first", () => {
    const g = SL.newGame("cpu", 4);
    g.players[0].pos = 40; g.players[1].pos = 72; g.players[2].pos = 0; g.players[3].pos = 40;
    let st = SL.standings(g);
    expect(st.map((e) => e.idx)).toEqual([1, 0, 3, 2]);
    expect(st.map((e) => e.place)).toEqual([1, 2, 3, 4]);
    expect(st[0]).toEqual({ idx: 1, color: g.players[1].c, name: "Mocha", place: 1, finished: false, pos: 72, progress: 0.72 });
    g.turn = 2; g.players[2].pos = 97;
    SL.applyRoll(g, 3);
    st = SL.standings(g);
    expect(g.phase).toBe("roll"); // a computer is home first: you play on for 2nd
    expect([g.finished, g.turn]).toEqual([[2], 3]);
    expect(st[0].idx === 2 && st[0].finished && st[0].place === 1 && st[0].progress === 1 && st[1].idx === 1).toBe(true);
    SL.endGame(g);
    expect([g.phase, g.winner, g.finished]).toEqual(["over", 2, [2, 1, 0, 3]]);
  });

  it("3 and 4 players", () => {
    expect(SL.newGame("cpu", 4).players.filter((p) => p.cpu).length).toBe(3);
    const g = SL.newGame("local", 3);
    expect(g.players.length === 3 && g.players.every((p) => !p.cpu)).toBe(true);
  });
});

describe("protocol actions (applySlAction)", () => {
  it("roll is applyRoll; mode sets the colour's cpu flag; a mode for an absent colour changes nothing", () => {
    const g = SL.newGame("local", 3);
    const ev = SL.applySlAction(g, { k: "roll", c: 0, v: 2 });
    expect(ev[1]).toMatchObject({ type: "move", to: 2 });
    expect(SL.turnColor(g)).toBe(1);
    expect(SL.botAction(g, 5)).toEqual({ k: "roll", c: 1, v: 5 });
    expect(SL.applySlAction(g, { k: "mode", c: 2, mode: "cpu" })).toEqual([]);
    expect(g.players.map((p) => p.cpu)).toEqual([false, false, true]);
    const before = SL.cloneSlState(g);
    expect(SL.applySlAction(g, { k: "mode", c: 3, mode: "cpu" })).toEqual([]);
    expect(g).toEqual(before);
    SL.applySlAction(g, { k: "mode", c: 2, mode: "human" });
    expect(g.players[2].cpu).toBe(false);
    expect(SL.playerIndex(g, 2)).toBe(2);
    expect(SL.playerIndex(g, 3)).toBe(-1);
  });

  it("vs Computer as Blue: colours wrap round", () => {
    const g = SL.newGame("cpu", 3, 3);
    expect(g.players.map((p) => p.c)).toEqual([3, 0, 1]);
    SL.applySlAction(g, { k: "mode", c: 0, mode: "human" });
    expect(g.players[1].cpu).toBe(false);
    expect(SL.turnColor(g)).toBe(3);
  });
});
