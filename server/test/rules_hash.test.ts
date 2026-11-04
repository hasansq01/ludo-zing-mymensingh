// State hash (PROTOCOL.md "State hash"). GDScript vs TS on every recorded step is in rules_parity.test.ts; the same
// fresh-game value is checked by godot/tests/test_state_hash.gd.
import { expect, it } from "vitest";
import * as Ludo from "../src/rules/ludo";
import { fnv1a32, stateHash, stateHashInput } from "../src/rules/hash";
import { base, state } from "./rules_helpers";

const FRESH_2P = "-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1||0|0|0|roll|-1|0000||human,off,human,off|";

it("FNV-1a 32 reference values", () => {
  expect(fnv1a32("")).toBe("811c9dc5");
  expect(fnv1a32("a")).toBe("e40c292c");
  expect(fnv1a32("foobar")).toBe("bf9cf968");
  expect(fnv1a32("é")).toBe(fnv1a32("é")); // UTF-8 bytes
  expect(fnv1a32("é")).not.toBe(fnv1a32("e"));
});

it("the PROTOCOL.md example: a fresh 2-player game", () => {
  const s = Ludo.newGame(["human", "off", "human", "off"]);
  expect(stateHashInput(s)).toBe(FRESH_2P);
  expect(stateHash(s)).toBe("86cf2abe");
  expect(stateHash(s)).toMatch(/^[0-9a-f]{8}$/);
});

it("pairs, free, finished and pending are in the string; names, view, teams, pair_ask, pick are not", () => {
  const t = base(); t[0][0] = 10; t[0][1] = 10; t[2] = [56, 56, 56, 56];
  const s = state(t, [{ c: 0, a: 0, b: 1 }], {
    players: ["human", "cpu", "human", "off"], free: [false, false, true, false], finished: [2],
    phase: "pair_ask", pending: { c: 0, i: 2, to: 12, extra: true, partner: 3 }, turn: 0, dice: 4, sixes: 1,
  });
  expect(stateHashInput(s)).toBe(
    "10,10,-1,-1,-1,-1,-1,-1,56,56,56,56,-1,-1,-1,-1|0.0.1|0|4|1|pair_ask|-1|0010|2|human,cpu,human,off|0.2.12.1.3",
  );
  const h = stateHash(s);
  const other = { ...s, names: ["A", "B", "C", "D"], view: 2, teams: true, pair_ask: true, pick: "pair" };
  expect(stateHash(other)).toBe(h);
  expect(stateHash({ ...s, pending: { c: 0, i: 2, to: 12, extra: false } })).not.toBe(h);
  expect(stateHashInput({ ...s, pending: { c: 0, i: 2, to: 12, extra: false } }).endsWith("|0.2.12.0.-1")).toBe(true);
  expect(stateHash({ ...s, players: ["cpu", "cpu", "human", "off"] })).not.toBe(h);
  expect(stateHash({ ...s, pending: {} })).not.toBe(h);
  const noFinished = { ...s };
  delete noFinished.finished;
  expect(stateHashInput(noFinished)).toContain("|0010||human");
});
