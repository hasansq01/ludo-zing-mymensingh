// Ghost skill and identities, measured without a server: seeded 1v1 Ludo games (fake dice) between a human-like
// policy (the "normal" AI) and a ghost (ghostPick). The ghost's mistake rate is tuned so the human wins 45-55%.
import { describe, expect, it } from "vitest";
import { FEMALE_NAMES, FREE_AVATARS, GHOST_MISTAKE, GHOST_TIMING, MALE_NAMES, ghostDelay, ghostPick, makeGhosts } from "../src/ghosts";
import { answerPair, applyRoll, move, movables, newGame, pickAi } from "../src/rules/ludo";
import { Mulberry32 } from "../src/rules/rng";

/** Human win rate over n seeded games (the human plays Red in even games, Yellow in odd ones). */
function humanWinRate(n: number, mistake: number, seed = 1): number {
  let wins = 0;
  for (let g = 0; g < n; g++) {
    const dice = new Mulberry32(seed * 100_000 + g);
    const hr = new Mulberry32(seed * 200_000 + g);
    const gr = new Mulberry32(seed * 300_000 + g);
    const s = newGame(["human", "off", "human", "off"]);
    const human = g % 2 === 0 ? 0 : 2;
    for (let steps = 0; s.phase !== "over" && steps < 5000; steps++) {
      if (s.phase === "roll") applyRoll(s, dice.randiRange(1, 6));
      else if (s.phase === "choose") move(s, s.turn === human ? pickAi(s, movables(s), hr, "normal") : ghostPick(s, gr, mistake));
      else if (s.phase === "pair_ask") answerPair(s, true);
    }
    expect(s.phase).toBe("over");
    if (s.winner === human) wins++;
  }
  return wins / n;
}

describe("ghost skill", () => {
  it("a human playing the normal AI wins 45-55% of 1v1 games against a ghost", () => {
    const n = 3000;
    const rate = humanWinRate(n, GHOST_MISTAKE);
    console.log(`ghost mistake ${GHOST_MISTAKE}: human win rate ${(rate * 100).toFixed(1)}% over ${n} seeded games`);
    expect(rate).toBeGreaterThanOrEqual(0.45);
    expect(rate).toBeLessThanOrEqual(0.55);
  }, 60_000);

  it("the brief's 20% random moves would make ghosts too weak (outside the band)", () => {
    const rate = humanWinRate(1500, 0.2, 2);
    expect(rate).toBeGreaterThan(0.55);
  }, 60_000);

  it("ghostPick always returns a legal move (or -1 when there is none)", () => {
    const rng = new Mulberry32(7);
    const dice = new Mulberry32(8);
    for (let g = 0; g < 50; g++) {
      const s = newGame(["human", "human", "human", "human"]);
      for (let steps = 0; s.phase !== "over" && steps < 4000; steps++) {
        if (s.phase === "roll") applyRoll(s, dice.randiRange(1, 6));
        else if (s.phase === "choose") {
          const i = ghostPick(s, rng, 0.5);
          expect(movables(s)).toContain(i);
          move(s, i);
        } else if (s.phase === "pair_ask") answerPair(s, rng.randf() < 0.5);
      }
    }
  });
});

describe("ghost identities and timing", () => {
  it("~150 common names, male and female, no duplicates", () => {
    const all = [...MALE_NAMES, ...FEMALE_NAMES];
    expect(all.length).toBeGreaterThanOrEqual(150);
    expect(new Set(all.map((x) => x.toLowerCase())).size).toBe(all.length);
    expect(all.every((x) => /^[A-Z][a-z-]{1,15}$/.test(x))).toBe(true);
  });

  it("free avatars only, unique names that never equal a human's, levels within 3 of a human's", () => {
    expect(FREE_AVATARS.length).toBeGreaterThanOrEqual(5);
    const rng = new Mulberry32(42);
    for (let k = 0; k < 500; k++) {
      const humans = [{ name: MALE_NAMES[k % MALE_NAMES.length], level: 1 + (k % 30) }];
      const gs = makeGhosts(3, humans, rng);
      const names = [...humans.map((h) => h.name), ...gs.map((g) => g.name)].map((x) => x.toLowerCase());
      expect(new Set(names).size).toBe(4);
      for (const g of gs) {
        expect(FREE_AVATARS).toContain(g.avatar);
        expect(g.frame).toBe("classic");
        expect(Math.abs(g.level - humans[0].level)).toBeLessThanOrEqual(3);
        expect(g.level).toBeGreaterThanOrEqual(1);
      }
    }
  });

  it("delays: roll 0.8-2.6 s, choose 1-3.5 s with ~8% 4-6 s, pair 0.8-2 s", () => {
    const rng = new Mulberry32(3);
    let think = 0;
    const n = 5000;
    for (let k = 0; k < n; k++) {
      const r = ghostDelay("roll", rng);
      expect(r).toBeGreaterThanOrEqual(GHOST_TIMING.roll[0]);
      expect(r).toBeLessThanOrEqual(GHOST_TIMING.roll[1]);
      const p = ghostDelay("pair_ask", rng);
      expect(p).toBeGreaterThanOrEqual(800);
      expect(p).toBeLessThanOrEqual(2000);
      const c = ghostDelay("choose", rng);
      expect(c).toBeGreaterThanOrEqual(1000);
      expect(c).toBeLessThanOrEqual(6000);
      if (c >= 4000) think++;
      else expect(c).toBeLessThanOrEqual(3500);
    }
    expect(think / n).toBeGreaterThan(0.05);
    expect(think / n).toBeLessThan(0.11);
  });
});
