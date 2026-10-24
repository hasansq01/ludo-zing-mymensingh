// Port of godot/tests/test_pair_rules.gd: pair forming, movement, blocking, capture, start squares, regressions.
import { expect, it } from "vitest";
import * as Ludo from "../src/rules/ludo";
import { base, prog, state } from "./rules_helpers";

const cpu = { players: ["human", "cpu", "cpu", "cpu"], names: ["You", "Mocha", "Biscotti", "Espresso"] };
const bAt = (a: number) => prog(3, a);

it("formation", () => {
  let t = base(); t[0][0] = 10; t[0][1] = 10;
  expect(Ludo.pairPartner(state(t, [], cpu), 0, 1)).toBe(0);
  t = base(); t[0][0] = 0; t[0][1] = 0;
  expect(Ludo.pairPartner(state(t, [], cpu), 0, 1), "own start square").toBe(-1);
  t = base(); t[0][0] = 13; t[0][1] = 13;
  expect(Ludo.pairPartner(state(t, [], cpu), 0, 1), "opponent start square").toBe(-1);
  t = base(); t[0][0] = 10; t[0][1] = 12;
  expect(Ludo.pairPartner(state(t, [], cpu), 0, 1), "passing over").toBe(-1);
  t = base(); t[0][0] = 10; t[0][1] = 10; t[0][2] = 10;
  expect(Ludo.pairPartner(state(t, [{ c: 0, a: 0, b: 1 }], cpu), 0, 2), "already paired").toBe(-1);
  t = base(); t[0][0] = 53; t[0][1] = 53;
  expect(Ludo.pairPartner(state(t, [], cpu), 0, 1), "home column").toBe(-1);
});

it("pair movement", () => {
  let t = base(); t[0][0] = 10; t[0][1] = 10;
  let s = state(t, [{ c: 0, a: 0, b: 1 }], cpu);
  expect([2, 4, 6].map((d) => Ludo.dest(s, 0, 0, d))).toEqual([11, 12, 13]);
  expect([1, 3, 5].every((d) => Ludo.dest(s, 0, 0, d) === Ludo.NO_MOVE)).toBe(true);
  expect(Ludo.dest(s, 0, 1, 4)).toBe(Ludo.dest(s, 0, 0, 4));
  t = base(); t[0][0] = 10; t[0][1] = 10; t[0][2] = 5;
  s = state(t, [{ c: 0, a: 0, b: 1 }], { ...cpu, dice: 3 });
  expect(Ludo.movables(s)).toEqual([2]);
});

it("blocking", () => {
  let t = base(); t[0][0] = 10; t[0][1] = 10; t[3][0] = bAt(7);
  let s = state(t, [{ c: 0, a: 0, b: 1 }], { ...cpu, turn: 3 });
  expect(Ludo.dest(s, 3, 0, 5), "single cannot jump an opponent pair").toBe(Ludo.NO_MOVE);
  expect(Ludo.dest(s, 3, 0, 3), "single may land on the pair square").toBe(bAt(10));
  t[3][0] = bAt(10);
  expect(Ludo.dest(s, 3, 0, 1)).toBe(bAt(11));
  expect([2, 3, 4, 5, 6].every((d) => Ludo.dest(s, 3, 0, d) === Ludo.NO_MOVE)).toBe(true);
  t = base(); t[0][0] = 10; t[0][1] = 10; t[3][0] = bAt(9); t[3][1] = bAt(9);
  s = state(t, [{ c: 0, a: 0, b: 1 }, { c: 3, a: 0, b: 1 }], { ...cpu, turn: 3 });
  expect([Ludo.dest(s, 3, 0, 4), Ludo.dest(s, 3, 0, 6)], "a pair passes an opponent pair").toEqual([bAt(11), bAt(12)]);
  t[3][0] = bAt(10); t[3][1] = bAt(10);
  expect(Ludo.dest(s, 3, 0, 2)).toBe(bAt(11));
  expect(Ludo.dest(s, 3, 0, 1)).toBe(Ludo.NO_MOVE);
});

it("capture", () => {
  let t = base(); t[0][0] = 10; t[0][1] = 10; t[3][0] = bAt(7);
  let s = state(t, [{ c: 0, a: 0, b: 1 }], { ...cpu, turn: 3 });
  expect(Ludo.victimsAt(s, 3, bAt(10), false)).toEqual([]);
  t = base(); t[0][0] = 10; t[0][1] = 10; t[3][0] = bAt(9); t[3][1] = bAt(9);
  s = state(t, [{ c: 0, a: 0, b: 1 }, { c: 3, a: 0, b: 1 }], { ...cpu, turn: 3 });
  expect(Ludo.victimsAt(s, 3, bAt(10), true)).toEqual([[0, 0], [0, 1]]);
  t = base(); t[0][0] = 8; t[0][1] = 8; t[3][0] = bAt(6); t[3][1] = bAt(6);
  s = state(t, [{ c: 0, a: 0, b: 1 }, { c: 3, a: 0, b: 1 }], { ...cpu, turn: 3 });
  expect(Ludo.victimsAt(s, 3, bAt(8), true), "safe square").toEqual([]);
  t = base(); t[0][2] = 10; t[0][3] = 10; t[3][0] = bAt(7);
  s = state(t, [], { ...cpu, turn: 3 });
  expect(Ludo.victimsAt(s, 3, bAt(10), false).length).toBe(1);
});

it("start squares and regressions", () => {
  expect([0, 13, 26, 39].every((p) => Ludo.onStartSquare(0, p))).toBe(true);
  expect([10, 8, 21].every((p) => !Ludo.onStartSquare(0, p))).toBe(true);
  let t = base(); t[0][3] = 50;
  let s = state(t, [], cpu);
  expect(Ludo.dest(s, 0, 0, 6)).toBe(0);
  expect(Ludo.dest(s, 0, 0, 5)).toBe(Ludo.NO_MOVE);
  expect(Ludo.dest(s, 0, 3, 6)).toBe(56);
  s.tok[0][3] = 53;
  expect(Ludo.dest(s, 0, 3, 4)).toBe(Ludo.NO_MOVE);
  t = base(); t[0][0] = 20; t[0][1] = 20;
  s = state(t, [{ c: 0, a: 0, b: 1 }], cpu);
  expect(Ludo.stuckReason(s, 0, 3)).toBe("A pair needs an even roll.");
});
