// Port of godot/tests/test_pair_capture_split.gd: pair capture rules and the automatic split in the home lane.
import { describe, expect, it } from "vitest";
import * as Ludo from "../src/rules/ludo";
import { base, play, prog, state } from "./rules_helpers";

const R = 0;
const B = 3;
const NAMES = ["Red", "Green", "Yellow", "Blue"];
const bAt = (a: number) => prog(B, a);

it("capture rules (static)", () => {
  let t = base(); t[R][0] = 10; t[R][1] = 10; t[B][0] = bAt(12);
  expect(Ludo.victimsAt(state(t, [{ c: R, a: 0, b: 1 }]), R, 12, true)).toEqual([]);
  t = base(); t[R][0] = 10; t[B][0] = bAt(12); t[B][1] = bAt(12);
  expect(Ludo.victimsAt(state(t, [{ c: B, a: 0, b: 1 }]), R, 12, false)).toEqual([]);
  t = base(); t[R][0] = 10; t[R][1] = 10; t[B][0] = bAt(12); t[B][1] = bAt(12); t[B][2] = bAt(12);
  const s = state(t, [{ c: R, a: 0, b: 1 }, { c: B, a: 0, b: 1 }]);
  expect(Ludo.victimsAt(s, R, 12, true)).toEqual([[3, 0], [3, 1]]);
  expect(Ludo.victimsAt(s, R, 12, false)).toEqual([[3, 2]]);
});

it("capture rules (real moves)", () => {
  let t = base(); t[R][0] = 10; t[R][1] = 10; t[B][0] = bAt(12);
  let s = state(t, [{ c: R, a: 0, b: 1 }]);
  play(s, 4);
  expect([s.tok[R][0], s.tok[R][1], s.tok[B][0], s.pairs.length]).toEqual([12, 12, bAt(12), 1]);
  expect(s.turn).not.toBe(R);

  t = base(); t[R][0] = 10; t[B][0] = bAt(12); t[B][1] = bAt(12);
  s = state(t, [{ c: B, a: 0, b: 1 }]);
  play(s, 2);
  expect([s.tok[R][0], s.tok[B][0], s.tok[B][1]]).toEqual([12, bAt(12), bAt(12)]);
  expect(s.pairs.some((q) => q.c === B)).toBe(true);

  t = base(); t[R][0] = 10; t[R][1] = 10; t[B][0] = bAt(12); t[B][1] = bAt(12);
  s = state(t, [{ c: R, a: 0, b: 1 }, { c: B, a: 0, b: 1 }]);
  play(s, 4);
  expect([s.tok[B][0], s.tok[B][1], s.turn]).toEqual([-1, -1, R]);
  expect(s.pairs.some((q) => q.c === B)).toBe(false);

  t = base(); t[R][0] = 10; t[B][0] = bAt(12);
  s = state(t);
  play(s, 2);
  expect([s.tok[B][0], s.turn]).toEqual([-1, R]);

  t = base(); t[R][0] = 6; t[R][1] = 6; t[B][0] = bAt(8);
  s = state(t, [{ c: R, a: 0, b: 1 }]);
  play(s, 4);
  expect([s.tok[B][0], s.tok[R][0]]).toEqual([bAt(8), 8]);
});

describe("automatic split on every home-lane cell, all four colours", () => {
  const cases = [[50, 2, 51], [50, 4, 52], [50, 6, 53], [52, 4, 54], [53, 4, 55], [49, 4, 51], [48, 6, 51]];
  for (let c = 0; c < 4; c++) {
    for (const [from, d, to] of cases) {
      it(`${NAMES[c]}: pair at ${from} +${d} splits on ${to}`, () => {
        const t = base(); t[c][0] = from; t[c][1] = from; t[c][2] = 56; t[c][3] = 56;
        const other = (c + 1) % 4;
        t[other][0] = 20;
        const s = state(t, [{ c, a: 0, b: 1 }], { turn: c });
        expect(Ludo.dest(s, c, 0, d)).toBe(to);
        play(s, d);
        expect(s.tok[c]).toEqual([to, to, 56, 56]);
        expect(s.pairs).toEqual([]);
        expect(s.tok[other][0]).toBe(20);
        expect(s.turn).toBe(d === 6 ? c : (c + 1) % 4);
        s.turn = c; s.phase = "roll"; s.sixes = 0;
        play(s, 1, 0);
        expect([s.tok[c][0], s.tok[c][1], s.pairs.length]).toEqual([to + 1, to, 0]);
        if (to + 2 <= 56) {
          s.turn = c; s.phase = "roll"; s.sixes = 0;
          play(s, 1, 1);
          expect([s.tok[c][0], s.tok[c][1], s.pairs.length]).toEqual([to + 1, to + 1, 0]);
        }
      });
    }
  }
});

it("unchanged pair behaviour elsewhere", () => {
  let t = base(); t[R][0] = 10; t[R][1] = 10;
  let s = state(t, [{ c: R, a: 0, b: 1 }]);
  play(s, 4);
  expect([s.tok[R][0], s.pairs.length]).toEqual([12, 1]);
  t = base(); t[R][0] = 11; t[R][1] = 11;
  s = state(t, [{ c: R, a: 0, b: 1 }]);
  const ev = Ludo.move((Ludo.applyRoll(s, 4), s), 0);
  expect([s.tok[R][0], s.tok[R][1], s.pairs.length]).toEqual([13, 13, 0]);
  expect(ev).toContainEqual({ type: "split", c: R, tokens: [0, 1], where: "start" });
  t = base(); t[R][0] = 48; t[R][1] = 48; t[R][2] = 50;
  expect(Ludo.dest(state(t, [{ c: R, a: 0, b: 1 }]), R, 0, 6)).toBe(51);
  t = base(); t[R][0] = 54; t[R][1] = 54;
  s = state(t, [{ c: R, a: 0, b: 1 }]);
  play(s, 4);
  expect([s.tok[R][0], s.tok[R][1], s.pairs.length]).toEqual([56, 56, 0]);
  t = base(); t[0][0] = 10; t[0][1] = 10; t[2][0] = prog(2, 12);
  expect(Ludo.victimsAt(state(t, [{ c: 0, a: 0, b: 1 }], { teams: true }), 0, 12, true)).toEqual([]);
});
