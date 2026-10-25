// Port of godot/tests/test_sl_rewards.gd: the win reward vs the three-sixes rule. The third 6 in a row is recorded
// in the player's rolls but never moves the pawn, so the reward replay must skip it too.
import { expect, it } from "vitest";
import * as SL from "../src/rules/sl";
import type { SlState } from "../src/rules/sl";
import { Mulberry32 } from "../src/rules/rng";

/** Plays a vs-Computer game to the end with seeded dice; returns the final state. */
function play(seed: number, n: number, needOne = false): SlState {
  const rng = new Mulberry32(seed);
  const g = SL.newGame("cpu", n, 0, { need_one: needOne });
  for (let k = 0; k < 5000; k++) {
    if (g.phase === "over") break;
    SL.applyRoll(g, rng.randiRange(1, 6));
  }
  return g;
}

/** Every roll replayed as a move (the old, wrong replay). */
function naive(rolls: number[]): number {
  let pos = 0;
  for (const v of rolls) {
    pos = SL.land(pos, Math.trunc(v)).to;
    if (pos === 100) return 100;
  }
  return pos;
}

function hasThreeSixes(rolls: number[]): boolean {
  let run = 0;
  for (const v of rolls) {
    run = v === 6 ? run + 1 : 0;
    if (run === 3) return true;
  }
  return false;
}

// 6, 6, (6: no move) -> 12; 2 -> 14; 1 -> 15; 5 -> 20; 1 -> 21 > 42; 6 -> 48; 3 -> 51 > 67; 4 -> 71 > 91; 6 -> 97; 3 -> 100
const PATH = [6, 6, 6, 2, 1, 5, 1, 6, 3, 4, 6, 3];

it("the replay mirrors the rule", () => {
  expect(SL.replayReaches100([6, 6, 6])).toBe(false);
  expect(SL.land(SL.land(0, 6).to, 6).to).toBe(12);
  expect(SL.replayReaches100(PATH)).toBe(true);
  expect(naive(PATH)).not.toBe(100);
  const r = [6, 6, 5, 1, 6, 3, 4, 6, 3, 3];
  expect(SL.replayReaches100(r)).toBe(naive(r) === 100);
});

it("the same win played through applyRoll pays", () => {
  const g = SL.newGame("cpu", 2);
  const me = g.players[0];
  for (const v of PATH) {
    while (g.turn !== 0 && g.phase === "roll") SL.applyRoll(g, 1); // the computer creeps along by 1s
    SL.applyRoll(g, v);
  }
  expect(g.phase === "over" && g.winner === 0 && me.pos === 100).toBe(true);
  expect(SL.claimWinReward(g)).toBe(100);
  const rt = JSON.parse(JSON.stringify({ rolls: me.rolls })) as { rolls: number[] };
  expect(SL.replayReaches100(rt.rolls)).toBe(true);
});

for (const needOne of [false, true]) {
  it(`[need_one ${needOne}] seeded games: every one of your wins is paid, some had three 6s`, () => {
    let wins = 0;
    let unpaid = 0;
    let withThree = 0;
    for (let s = 0; s < 400; s++) {
      const g = play(1000 + s, 2 + (s % 3), needOne);
      if (g.phase !== "over" || !g.players[g.winner].you) continue;
      wins += 1;
      if (hasThreeSixes(g.players[0].rolls)) withThree += 1;
      if (SL.claimWinReward(g) !== 100) unpaid += 1;
    }
    expect(withThree).toBeGreaterThan(0);
    expect(wins).toBeGreaterThan(0);
    expect(unpaid).toBe(0);
  });
}
