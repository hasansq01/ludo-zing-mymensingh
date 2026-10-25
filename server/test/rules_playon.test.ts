// Play on after the first finish (Ludo and Snakes & Ladders): the TS twin of godot/tests/test_play_on.gd. Places in
// finish order ("finished" events), finished sides skipped by the turn order, the end conditions (fewer than two
// sides left; no person left unfinished), the rest ranked by progress, endGame (the {k: "end"} action), Teams (the
// team finishes together, Free Hand until then) and states saved before play on.
import { describe, expect, it } from "vitest";
import * as Ludo from "../src/rules/ludo";
import type { LudoEvent } from "../src/rules/ludo";
import * as SL from "../src/rules/sl";
import { base, play, state } from "./rules_helpers";

const HOME = () => [56, 56, 56, 56];
const NEAR = () => [56, 56, 56, 55];
const types = (ev: { type: string }[]) => ev.map((e) => e.type);
const ofType = <T extends { type: string }>(ev: T[], t: string) => ev.find((e) => e.type === t);
const vs = () => ({ players: ["human", "cpu", "cpu", "cpu"], names: ["You", "Mocha", "Biscotti", "Espresso"], finished: [] as number[] });

describe("Ludo: play on", () => {
  it("4 players: places 1, 2, 3, the last ranked by progress", () => {
    const t = base(); t[0] = NEAR(); t[1] = NEAR(); t[2] = NEAR(); t[3][0] = 12;
    const s = state(t, [], { finished: [] });
    Ludo.applyRoll(s, 1);
    let ev: LudoEvent[] = Ludo.move(s, 3);
    expect(types(ev)).toEqual(["move", "home", "finished", "turn"]);
    expect(ofType(ev, "finished")).toEqual({ type: "finished", c: 0, place: 1 });
    expect([s.phase, s.turn, s.winner, s.finished]).toEqual(["roll", 1, -1, [0]]);
    expect([Ludo.sideDone(s, 0), Ludo.sideDone(s, 1), Ludo.sideDone(s, 3)]).toEqual([true, false, false]);
    Ludo.applyRoll(s, 1);
    ev = Ludo.move(s, 3);
    expect([ofType(ev, "finished"), s.turn]).toEqual([{ type: "finished", c: 1, place: 2 }, 2]);
    Ludo.applyRoll(s, 1);
    ev = Ludo.move(s, 3);
    expect(types(ev)).toEqual(["move", "home", "finished", "game_over"]);
    expect([s.phase, s.finished, s.winner]).toEqual(["over", [0, 1, 2, 3], 0]);
    expect(ofType(ev, "game_over")).toEqual({ type: "game_over", winner: 0, team: [0], order: [0, 1, 2, 3] });
    const st = Ludo.standings(s);
    expect(st.map((e) => e.place)).toEqual([1, 2, 3, 4]);
    expect([st[2].finished, st[3].finished, st[3].color]).toEqual([true, false, 3]);
    expect(Ludo.applyRoll(s, 6)).toEqual([]);
  });

  it("the turn order skips finished sides; three 6s and extra turns as before", () => {
    const t = base(); t[0] = HOME(); t[1][0] = 3;
    const s = state(t, [], { finished: [0], turn: 3 });
    const ev = Ludo.applyRoll(s, 2);
    expect([s.turn, ev.at(-1)]).toEqual([1, { type: "turn", c: 1, again: false }]);
    expect([Ludo.nextActive(s, 3), Ludo.nextActive(s, 2)]).toEqual([1, 3]);
    s.turn = 3; s.sixes = 2;
    expect(types(Ludo.applyRoll(s, 6))).toEqual(["rolled", "three_sixes", "turn"]);
    expect(s.turn).toBe(1);
    s.turn = 3; s.sixes = 0;
    Ludo.applyRoll(s, 6);
    Ludo.move(s, Ludo.autoMoveToken(s));
    expect([s.turn, s.phase]).toEqual([3, "roll"]);
  });

  it("finishing with a 6 hands the turn on", () => {
    const t = base(); t[0] = [56, 56, 56, 50]; t[1][0] = 2;
    const s = state(t, [], { finished: [] });
    Ludo.applyRoll(s, 6);
    const ev = Ludo.move(s, 3);
    expect(ofType(ev, "finished")).toEqual({ type: "finished", c: 0, place: 1 });
    expect([s.turn, s.sixes, ev.at(-1), s.tok[1][0]]).toEqual([1, 0, { type: "turn", c: 1, again: false }, 2]);
  });

  it("3 players: the second finisher ends it", () => {
    const t = base(); t[0] = NEAR(); t[2] = NEAR(); t[1][0] = 20;
    const s = state(t, [], { players: ["human", "human", "human", "off"], finished: [] });
    play(s, 1);
    expect([s.phase, s.turn]).toEqual(["roll", 1]);
    s.turn = 2;
    play(s, 1);
    expect([s.phase, s.finished, s.winner]).toEqual(["over", [0, 2, 1], 0]);
  });

  it("no person left unfinished ends the game (vs Computer and mixed tables)", () => {
    let t = base(); t[1] = NEAR(); t[0] = NEAR(); t[2][0] = 30; t[3][0] = 40;
    let s = state(t, [], { ...vs(), turn: 1 });
    play(s, 1);
    expect([s.phase, s.finished, s.turn]).toEqual(["roll", [1], 2]);
    s.players[0] = "cpu"; // a mode switch alone never ends a game
    expect(s.phase).toBe("roll");
    s.players[0] = "human";
    s.turn = 0;
    Ludo.applyRoll(s, 1);
    const ev = Ludo.move(s, 3);
    expect(types(ev).slice(-2)).toEqual(["finished", "game_over"]);
    expect([s.phase, s.finished, s.winner]).toEqual(["over", [1, 0, 3, 2], 1]);
    expect([Ludo.winReward(s), Ludo.playReward(s)]).toEqual([0, Ludo.PLAY_REWARD]);
    const st = Ludo.standings(s);
    expect([st[1].color, st[1].place, st[1].finished]).toEqual([0, 2, true]);

    t = base(); t[0] = NEAR(); t[1][0] = 10;
    s = state(t, [], vs());
    play(s, 1);
    expect([s.phase, s.winner, (s.finished ?? []).length, Ludo.winReward(s)]).toEqual(["over", 0, 4, Ludo.WIN_REWARD]);

    t = base(); t[0] = NEAR(); t[2] = NEAR(); t[1][0] = 5; t[3][0] = 9;
    s = state(t, [], { players: ["human", "cpu", "human", "cpu"], finished: [] });
    play(s, 1);
    expect([s.phase, s.finished]).toEqual(["roll", [0]]);
    s.turn = 2;
    play(s, 1);
    expect([s.phase, s.finished]).toEqual(["over", [0, 2, 3, 1]]);

    t = base(); t[0] = NEAR();
    s = state(t, [], { players: ["cpu", "cpu", "cpu", "cpu"], finished: [] });
    play(s, 1);
    expect([s.phase, s.winner]).toEqual(["over", 0]);
  });

  it("Teams: Free Hand until the partner is home, then the team finishes together", () => {
    const t = base(); t[0] = NEAR(); t[2] = [56, 56, 56, 50]; t[1][0] = 5; t[3][0] = 30;
    const s = state(t, [], { teams: true, finished: [] });
    Ludo.applyRoll(s, 1);
    let ev = Ludo.move(s, 3);
    expect(types(ev)).toEqual(["move", "home", "all_home", "turn"]);
    expect([s.phase, s.finished, Ludo.sideDone(s, 0), Ludo.nextActive(s, 3)]).toEqual(["roll", [0], false, 0]);
    ev = Ludo.applyRoll(s, 6);
    expect(types(ev)).toContain("free_hand");
    expect([s.phase, Ludo.moverOf(s, 0)]).toEqual(["choose", 2]);
    ev = Ludo.move(s, 3);
    expect(ofType(ev, "finished")).toEqual({ type: "finished", c: 2, place: 1, team: [0, 2] });
    expect([s.phase, ev.at(-1)?.type, s.finished, Ludo.winners(s)]).toEqual(["over", "game_over", [0, 2, 3, 1], [2, 0]]);
    expect(Ludo.standings(s).map((e) => e.place)).toEqual([1, 1, 2, 2]);
  });

  it("endGame ({k: end}) and states from before play on", () => {
    let t = base(); t[0] = HOME(); t[1][0] = 40; t[2][0] = 12; t[3] = [56, 56, -1, -1];
    let s = state(t, [], { finished: [0], turn: 1, phase: "choose", dice: 3, pick: "single" });
    const ev = Ludo.applyAction(s, { k: "end" });
    expect([types(ev), s.finished, s.winner, s.phase, s.pick, s.pending]).toEqual([["game_over"], [0, 3, 1, 2], 0, "over", "", {}]);
    expect(Ludo.endGame(s)).toEqual([]);
    t = base(); t[1][0] = 50; t[3][0] = 2;
    s = state(t, [], { teams: true, finished: [] });
    Ludo.endGame(s);
    expect([s.winner, Ludo.winners(s), (s.finished ?? []).length]).toEqual([1, [1, 3], 4]);
    s = state(base()); // no finished key: a game saved before finish order existed
    Ludo.applyRoll(s, 2);
    expect([s.finished, s.turn, s.phase]).toEqual([[], 1, "roll"]);
    s = state(base(), [], { finished: [1.0], turn: 0 });
    Ludo.applyRoll(s, 2);
    expect([s.turn, s.finished]).toEqual([2, [1]]);
    t = base(); t[0] = NEAR(); t[1] = NEAR();
    s = state(t, [], { players: ["human", "human", "off", "off"], finished: [] });
    play(s, 1);
    expect([s.phase, s.finished, s.winner]).toEqual(["over", [0, 1], 0]);
  });
});

describe("S&L: play on", () => {
  it("places in finish order, the rest by square", () => {
    const g = SL.newGame("local", 3);
    expect(g.finished).toEqual([]);
    g.players[0].pos = 97; g.players[1].pos = 99; g.players[2].pos = 50;
    let ev = SL.applyRoll(g, 3);
    expect(types(ev)).toEqual(["rolled", "move", "finished", "turn"]);
    expect(ofType(ev, "finished")).toEqual({ type: "finished", turn: 0, c: 0, place: 1 });
    expect([g.turn, g.phase]).toEqual([1, "roll"]);
    ev = SL.applyRoll(g, 1);
    expect(types(ev).slice(-2)).toEqual(["finished", "win"]);
    expect([g.phase, g.winner, g.finished, ev.at(-1)]).toEqual(["over", 0, [0, 1, 2], { type: "win", turn: 0, order: [0, 1, 2] }]);
    const st = SL.standings(g);
    expect([st.map((e) => e.idx), st[1].finished, st[2].finished]).toEqual([[0, 1, 2], true, false]);
  });

  it("finished players are skipped; a 6 onto 100 hands the turn on", () => {
    const g = SL.newGame("local", 4);
    g.finished = [0]; g.players[0].pos = 100; g.turn = 3;
    SL.applyRoll(g, 2);
    expect(g.turn).toBe(1);
    g.turn = 3; g.players[3].pos = 94;
    const ev = SL.applyRoll(g, 6);
    expect([ofType(ev, "finished"), g.turn, g.sixes, ev.at(-1)]).toEqual([
      { type: "finished", turn: 3, c: 3, place: 2 }, 1, 0, { type: "turn", turn: 1, again: false },
    ]);
  });

  it("vs Computer: you play on after a computer's finish; your finish ends it", () => {
    let g = SL.newGame("cpu", 3);
    g.players[1].pos = 97; g.players[0].pos = 98; g.players[2].pos = 40; g.turn = 1;
    SL.applyRoll(g, 3);
    expect([g.phase, g.finished, g.turn]).toEqual(["roll", [1], 2]);
    g.turn = 0;
    SL.applyRoll(g, 2);
    expect([g.phase, g.winner, g.finished]).toEqual(["over", 1, [1, 0, 2]]);
    expect([SL.claimWinReward(SL.cloneSlState(g)), SL.claimPlayReward(SL.cloneSlState(g))]).toEqual([0, SL.PLAY_REWARD]);
    g = SL.newGame("cpu", 3);
    g.players[0].pos = 98;
    SL.applyRoll(g, 2);
    expect([g.phase, g.winner, (g.finished ?? []).length]).toEqual(["over", 0, 3]);
  });

  it("endGame and old states", () => {
    let g = SL.newGame("local", 3);
    g.players[1].pos = 60; g.players[2].pos = 60;
    expect(SL.applySlAction(g, { k: "end" }).length).toBe(1);
    expect([g.finished, g.winner, g.phase]).toEqual([[1, 2, 0], 1, "over"]);
    expect(SL.endGame(g)).toEqual([]);
    g = SL.newGame("local", 2);
    delete g.finished;
    g.phase = "over"; g.winner = 1; g.players[1].pos = 100;
    expect(SL.standings(g)[0].idx).toBe(1);
    g = SL.newGame("local", 3);
    g.finished = [0.0];
    SL.applyRoll(g, 2);
    expect([g.finished, g.turn]).toEqual([[0], 1]);
  });
});
