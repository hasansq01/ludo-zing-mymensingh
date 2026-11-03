// Shared helpers for the rules tests (ports of godot/tests/test_suite.gd).
import * as Ludo from "../src/rules/ludo";
import type { LudoState } from "../src/rules/ludo";

/** Colours: 0 red (start abs 0), 1 green (13), 2 yellow (26), 3 blue (39). abs = (start + progress) % 52. */
export function prog(c: number, absSq: number): number {
  return (absSq - Ludo.OFF[c] + 52) % 52;
}

export function base(): number[][] {
  return [
    [-1, -1, -1, -1],
    [-1, -1, -1, -1],
    [-1, -1, -1, -1],
    [-1, -1, -1, -1],
  ];
}

/** A Ludo state for a test: four humans unless `extra` says otherwise, Individual mode (no pair_ask / finished keys). */
export function state(tok: number[][], pairs: Ludo.Pair[] = [], extra: Partial<LudoState> = {}): LudoState {
  const s: LudoState = {
    players: ["human", "human", "human", "human"],
    names: ["Red", "Green", "Yellow", "Blue"],
    view: 0,
    tok,
    pairs,
    turn: 0,
    dice: 0,
    sixes: 0,
    phase: "roll",
    winner: -1,
    pick: "",
    teams: false,
    free: [false, false, false, false],
    pending: {},
  };
  return Object.assign(s, extra);
}

/** One real roll the way the game drives it (test_suite.gd play()). */
export function play(s: LudoState, v: number, pick = -1): void {
  Ludo.applyRoll(s, v);
  if (s.phase !== "choose") return;
  if (!Ludo.isHuman(s, s.turn)) {
    Ludo.move(s, Ludo.pickAi(s, Ludo.movables(s)));
    return;
  }
  const a = Ludo.autoMoveToken(s);
  if (a >= 0) Ludo.move(s, a);
  else if (pick >= 0) Ludo.move(s, pick);
}

/** Strict structural equality for JSON-like values (number vs boolean matters, key order does not). */
export function deepEqual(a: unknown, b: unknown): boolean {
  if (a === b) return true;
  if (typeof a !== typeof b || a === null || b === null || typeof a !== "object") return false;
  if (Array.isArray(a) !== Array.isArray(b)) return false;
  if (Array.isArray(a)) {
    const bb = b as unknown[];
    return a.length === bb.length && a.every((x, i) => deepEqual(x, bb[i]));
  }
  const ao = a as Record<string, unknown>;
  const bo = b as Record<string, unknown>;
  const ak = Object.keys(ao);
  if (ak.length !== Object.keys(bo).length) return false;
  return ak.every((k) => Object.prototype.hasOwnProperty.call(bo, k) && deepEqual(ao[k], bo[k]));
}
