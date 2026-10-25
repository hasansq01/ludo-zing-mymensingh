// S&L state hash (PROTOCOL.md "S&L state hash"). GDScript vs TS on every recorded step is in
// rules_sl_parity.test.ts; the same strings / values are checked by godot/tests/test_sl_state_hash.gd.
import { expect, it } from "vitest";
import * as SL from "../src/rules/sl";
import { slStateHash, slStateHashInput } from "../src/rules/sl_hash";
import { Mulberry32 } from "../src/rules/rng";

const FRESH_LOCAL_2P = "0|roll|0|-1|0|0.0.0.0.0.,1.0.0.0.0.|";

it("the PROTOCOL.md example: a fresh 2-player Pass & Play game", () => {
  const s = SL.newGame("local", 2);
  expect(slStateHashInput(s)).toBe(FRESH_LOCAL_2P);
  expect(slStateHash(s)).toBe("edd54d53");
});

it("every hashed field is in the string; mode, paid, name and you are not", () => {
  const s = SL.newGame("cpu", 3, 2, { need_one: true });
  s.players[0].pos = 42; s.players[0].ladders = 2; s.players[0].snakes = 1; s.players[0].rolls = [1, 3, 6, 6, 2];
  s.players[2].cpu = false; s.players[1].pos = 7; s.players[1].rolls = [4, 3];
  s.turn = 1; s.sixes = 2; s.phase = "over"; s.winner = 0;
  const want = "1|over|2|0|1|2.42.0.2.1.13662,3.7.1.0.0.43,0.0.0.0.0.|";
  expect(slStateHashInput(s)).toBe(want);
  const h = slStateHash(s);
  expect(h).toBe("a78c39c4");
  const other = SL.cloneSlState(s);
  other.mode = "local"; other.paid = true; other.players[0].name = "Shihab"; other.players[0].you = false;
  expect(slStateHash(other)).toBe(h);
  const noOpt = SL.cloneSlState(s);
  delete noOpt.need_one;
  expect(slStateHashInput(noOpt)).toBe("1|over|2|0|0|2.42.0.2.1.13662,3.7.1.0.0.43,0.0.0.0.0.|");
  const fin = SL.cloneSlState(s);
  fin.finished = [0, 2, 1];
  expect(slStateHashInput(fin)).toBe("1|over|2|0|1|2.42.0.2.1.13662,3.7.1.0.0.43,0.0.0.0.0.|0,2,1");
  const noFin = SL.cloneSlState(s);
  delete noFin.finished;
  expect(slStateHash(noFin)).toBe(h); // (a state from before play on: no finished field hashes as none)
  for (const f of [
    (x: SL.SlState) => (x.players[2].cpu = true),
    (x: SL.SlState) => x.players[1].rolls.push(1),
    (x: SL.SlState) => (x.players[0].snakes = 0),
    (x: SL.SlState) => (x.sixes = 0),
    (x: SL.SlState) => (x.turn = 2),
    (x: SL.SlState) => (x.finished = [0]),
  ]) {
    const t = SL.cloneSlState(s);
    f(t);
    expect(slStateHash(t)).not.toBe(h);
  }
});

it("a real game: the hash follows the play and survives JSON", () => {
  const s = SL.newGame("local", 4, 0, { need_one: true });
  const rng = new Mulberry32(5);
  let last = slStateHash(s);
  let changed = 0;
  let steps = 0;
  while (s.phase === "roll" && steps < 2000) {
    SL.applyRoll(s, rng.randiRange(1, 6));
    const now = slStateHash(s);
    expect(now).toMatch(/^[0-9a-f]{8}$/);
    expect(slStateHash(JSON.parse(JSON.stringify(s)))).toBe(now);
    changed += now !== last ? 1 : 0;
    last = now;
    steps++;
  }
  expect(changed).toBe(steps); // every roll is recorded, so every roll changes the hash
});
