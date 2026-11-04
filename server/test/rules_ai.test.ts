// The bots (pickAi levels), after godot/tests/test_bot_levels.gd: every pick is legal, the levels choose sensibly
// in telling positions, and in seeded self-play hard beats easy. Plus the seeded PRNG.
import { expect, it } from "vitest";
import * as Ludo from "../src/rules/ludo";
import { Mulberry32 } from "../src/rules/rng";
import { base, prog, state } from "./rules_helpers";

const cpu = { players: ["cpu", "cpu", "cpu", "cpu"], names: ["A", "B", "C", "D"] };

it("Mulberry32 is seeded, in [0, 1) and spreads", () => {
  const a = new Mulberry32(42);
  const b = new Mulberry32(42);
  const xs = Array.from({ length: 1000 }, () => a.randf());
  expect(xs).toEqual(Array.from({ length: 1000 }, () => b.randf()));
  expect(xs.every((x) => x >= 0 && x < 1)).toBe(true);
  const mean = xs.reduce((p, x) => p + x, 0) / xs.length;
  expect(mean).toBeGreaterThan(0.45);
  expect(mean).toBeLessThan(0.55);
  const d = new Mulberry32(7);
  const seen = new Set(Array.from({ length: 600 }, () => d.randiRange(1, 6)));
  expect([...seen].sort()).toEqual([1, 2, 3, 4, 5, 6]);
  const e = new Mulberry32(1);
  e.randf();
  const f = new Mulberry32(0);
  f.state = e.state;
  expect(f.randf()).toBe(e.randf());
});

it("levels and the no-move case", () => {
  expect(Ludo.LEVELS).toEqual(["easy", "normal", "hard"]);
  const s = state(base(), [], { ...cpu, dice: 4 });
  const rng = new Mulberry32(1);
  for (const l of Ludo.LEVELS) expect(Ludo.pickAi(s, [], rng, l)).toBe(-1);
});

it("telling positions", () => {
  const rng = new Mulberry32(3);
  let t = base(); t[0][0] = 10; t[0][1] = 30; t[1][0] = prog(1, 14);
  let s = state(t, [], { ...cpu, dice: 4, phase: "choose" });
  let mv = Ludo.movables(s);
  expect(Ludo.pickAi(s, mv, rng, "normal"), "normal takes the capture").toBe(0);
  expect(Ludo.pickAi(s, mv, rng, "hard"), "hard takes the capture").toBe(0);

  t = base(); t[0][0] = 52; t[0][1] = 10; t[0][2] = 20; t[0][3] = 30;
  s = state(t, [], { ...cpu, dice: 4, phase: "choose" });
  mv = Ludo.movables(s);
  let fin = 0;
  for (let k = 0; k < 400; k++) if (Ludo.pickAi(s, mv, rng, "easy") === 0) fin++;
  expect(fin).toBeGreaterThan(200);
  expect(fin).toBeLessThan(340);
  expect(Ludo.pickAi(s, mv, rng, "normal")).toBe(0);
  expect(Ludo.pickAi(s, mv, rng, "hard")).toBe(0);

  t = base(); t[0][0] = 10; t[0][1] = 20; t[0][2] = 30; t[0][3] = 40;
  s = state(t, [], { ...cpu, dice: 3, phase: "choose" });
  mv = Ludo.movables(s);
  const seen = new Set<number>();
  for (let k = 0; k < 200; k++) seen.add(Ludo.pickAi(s, mv, rng, "easy"));
  expect(seen.size).toBe(4);

  t = base(); t[0][0] = 20; t[0][1] = 5; t[1][0] = prog(1, 23); t[1][1] = prog(1, 23);
  s = state(t, [], { ...cpu, dice: 4, phase: "choose" });
  expect(Ludo.pickAi(s, Ludo.movables(s), rng, "hard"), "hard stays out of reach").toBe(1);

  t = base(); t[0][0] = 30; t[0][1] = 8; t[1][0] = prog(1, 28);
  s = state(t, [], { ...cpu, dice: 5, phase: "choose" });
  expect(Ludo.pickAi(s, Ludo.movables(s), rng, "hard"), "hard runs from a threat").toBe(0);
  const t2 = base(); t2[0][1] = 8; t2[1][0] = prog(1, 6);
  expect(Ludo.risk(s, 0)).toBeGreaterThan(0);
  expect(Ludo.risk(state(t2, [], cpu), 0)).toBe(0);

  t = base(); t[0][0] = 20; t[0][1] = 24; t[0][2] = 40; t[1][0] = prog(1, 21); t[1][1] = prog(1, 22);
  s = state(t, [], { ...cpu, dice: 4, phase: "choose" });
  const before = JSON.stringify(s);
  expect(Ludo.pickAi(s, Ludo.movables(s), rng, "hard"), "hard pairs up to protect a pawn").toBe(0);
  expect(JSON.stringify(s), "thinking never changes the state").toBe(before);
  const after = Ludo.cloneState(s);
  Ludo.move(after, 0);
  expect(after.pairs.length).toBe(1);
  expect(Ludo.risk(after, 0)).toBeLessThan(Ludo.risk(s, 0));
});

/** One all-computer 4-player game; levels[c] plays colour c. Returns the winner (-1 on an illegal pick). */
function game(levels: string[], rng: Mulberry32): number {
  const s = Ludo.newGame(["cpu", "cpu", "cpu", "cpu"]);
  let rolls = 0;
  while (s.phase !== "over" && rolls < 20000) {
    rolls++;
    Ludo.applyRoll(s, rng.randiRange(1, 6));
    if (s.phase === "choose") {
      const mv = Ludo.movables(s);
      const i = Ludo.pickAi(s, mv, rng, levels[s.turn]);
      if (!mv.includes(i) || Ludo.move(s, i).length === 0) return -1;
    }
  }
  return s.winner;
}

it("seeded self-play: always legal, and hard beats easy", () => {
  const rng = new Mulberry32(2024);
  let hardWins = 0;
  const N = 60;
  for (let g = 0; g < N; g++) {
    // hard on two seats, easy on the other two (rotated so seat order doesn't decide)
    const levels = g % 2 ? ["hard", "easy", "hard", "easy"] : ["easy", "hard", "easy", "hard"];
    const w = game(levels, rng);
    expect(w).toBeGreaterThanOrEqual(0);
    if (levels[w] === "hard") hardWins++;
  }
  expect(hardWins / N).toBeGreaterThan(0.6);
});
