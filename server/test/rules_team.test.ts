// Port of godot/tests/test_team_rules.gd: Pair Mode (teams) setup, partners, Free Hand and team wins.
import { expect, it } from "vitest";
import * as Ludo from "../src/rules/ludo";
import type { LudoState } from "../src/rules/ludo";
import { base, play, prog, state } from "./rules_helpers";

const HOME = () => [56, 56, 56, 56];
const team = (tok: number[][], extra: Partial<LudoState> = {}) => state(tok, [], { teams: true, ...extra });

it("setup", () => {
  let s = Ludo.newGame(["human", "cpu", "cpu", "cpu"], true);
  expect([s.teams, s.free]).toEqual([true, [false, false, false, false]]);
  expect([0, 1, 2, 3].map(Ludo.mateOf)).toEqual([2, 3, 0, 1]);
  expect(Ludo.newGame(["human", "off", "human", "off"], true).teams).toBe(false);
  expect(Ludo.newGame(["human", "human", "human", "off"], true).teams).toBe(false);
  expect(Ludo.newGame(["human", "cpu", "cpu", "cpu"], false).teams).toBe(false);
  s = Ludo.newGame(["human", "cpu", "cpu", "cpu"], true);
  s.free[0] = true;
  expect(Ludo.newGame(["human", "cpu", "cpu", "cpu"], true).free.every((f) => !f)).toBe(true);
});

it("captures and blocking between partners", () => {
  let t = base(); t[0][0] = 10; t[2][0] = prog(2, 14);
  let s = team(t);
  expect(Ludo.victimsAt(s, 0, 14, false)).toEqual([]);
  expect(!Ludo.foe(s, 0, 2) && Ludo.foe(s, 0, 1) && Ludo.foe(s, 0, 3)).toBe(true);
  t = base(); t[0][0] = 10; t[1][0] = prog(1, 14);
  expect(Ludo.victimsAt(team(t), 0, 14, false)).toEqual([[1, 0]]);
  t = base(); t[0][0] = 10; t[2][0] = prog(2, 14);
  expect(Ludo.victimsAt(team(t, { teams: false }), 0, 14, false)).toEqual([[2, 0]]);
  t = base(); t[0][0] = 10; t[2][0] = prog(2, 12); t[2][1] = prog(2, 12);
  s = team(t, { pairs: [{ c: 2, a: 0, b: 1 }] });
  expect(Ludo.dest(s, 0, 0, 4)).toBe(14);
  expect(Ludo.victimsAt(s, 0, 12, false)).toEqual([]);
  s = team(t, { teams: false, pairs: [{ c: 2, a: 0, b: 1 }] });
  expect(Ludo.dest(s, 0, 0, 4)).toBe(Ludo.NO_MOVE);
});

it("Free Hand gating", () => {
  let t = base(); t[0] = HOME(); t[2][0] = 10;
  let s = team(t, { dice: 4 });
  expect(Ludo.waitingSix(s, 0) && Ludo.movables(s).length === 0).toBe(true);
  s.free[0] = true;
  expect(Ludo.moverOf(s, 0)).toBe(2);
  expect(Ludo.movables(s)).toEqual([0]);
  t = base(); t[0][0] = 10; s = team(t);
  expect(Ludo.moverOf(s, 0) === 0 && !Ludo.waitingSix(s, 0)).toBe(true);
});

it("Free Hand flow", () => {
  let t = base(); t[0] = HOME(); t[2][0] = 10; t[2][1] = 20;
  let s = team(t);
  play(s, 3);
  expect([s.free[0], s.turn, s.tok[2][0]]).toEqual([false, 1, 10]);
  t = base(); t[0] = HOME(); t[2] = [10, 56, 56, 56];
  s = team(t);
  play(s, 6);
  expect([s.free[0], s.tok[2][0], s.turn]).toEqual([true, 16, 0]);
  play(s, 4);
  expect([s.tok[2][0], s.turn]).toEqual([20, 1]);
  t = base(); t[0] = HOME(); t[2][0] = 12; t[1][0] = prog(1, 41);
  s = team(t, { free: [true, false, false, false] });
  play(s, 3);
  expect([s.tok[2][0], s.tok[1][0], s.turn]).toEqual([15, -1, 0]);
  t = base(); t[0] = HOME(); t[2] = [56, 56, 56, 54];
  s = team(t, { free: [true, false, false, false] });
  play(s, 5);
  expect(s.tok[2][3]).toBe(54);
  expect(s.phase).not.toBe("over");
});

it("wins", () => {
  let t = base(); t[0] = [56, 56, 56, 55]; t[2][0] = 10;
  let s = team(t);
  play(s, 1);
  expect([s.tok[0][3], s.phase, s.winner, s.turn, Ludo.waitingSix(s, 0)]).toEqual([56, "roll", -1, 0, true]);
  t = base(); t[0] = HOME(); t[2] = [56, 56, 56, 55];
  s = team(t, { free: [true, false, false, false] });
  play(s, 1);
  expect(s.phase).toBe("over");
  expect([0, 2]).toContain(s.winner);
  expect(Ludo.teamName(s, s.winner)).toBe("Red + Yellow");
  expect(Ludo.winners(s).length).toBe(2);
  t = base(); t[0] = HOME(); t[2] = [56, 56, 56, 55];
  s = team(t, { turn: 2 });
  play(s, 1);
  expect(s.phase).toBe("over");
  expect([0, 2]).toContain(s.winner);
  t = base(); t[0] = [56, 56, 56, 55];
  s = team(t, { teams: false });
  play(s, 1);
  expect([s.phase, s.winner]).toEqual(["over", 0]);
});

it("computer players follow the same rules", () => {
  const cpus = { players: ["human", "cpu", "human", "cpu"], names: ["Red", "Mocha", "Yellow", "Espresso"], turn: 1 };
  let t = base(); t[1] = HOME(); t[3][0] = 10;
  let s = team(t, cpus);
  play(s, 2);
  expect([s.free[1], s.tok[3][0]]).toEqual([false, 10]);
  t = base(); t[1] = HOME(); t[3][0] = 10;
  s = team(t, { ...cpus, free: [false, true, false, false] });
  play(s, 2);
  expect(s.tok[3][0]).toBe(12);
});
