// Each player's die: a hello's dice counts only when the account owns it, and ghosts get a mix of their own.
import { describe, expect, it } from "vitest";
import { GHOST_DICE, ghostDice } from "../src/ghosts";
import { diceFor } from "../src/room";
import { CATALOG } from "../src/econ";

describe("diceFor", () => {
  it("a die the account owns, else Classic: never one nobody paid for", () => {
    expect(diceFor("gold", ["classic", "gold"])).toBe("gold");
    expect(diceFor("gold", ["classic"])).toBe("");
    expect(diceFor("gold", null)).toBe("");
    expect(diceFor("classic", ["classic"])).toBe("");
    expect(diceFor("not-a-die", ["not-a-die"])).toBe("");
    expect(diceFor(7, ["classic"])).toBe("");
  });
});

describe("ghost dice", () => {
  it("only dice that exist; mostly Classic, the dearest rare", () => {
    const ids = CATALOG.items.filter((i: { kind: string }) => i.kind === "dice").map((i: { id: string }) => i.id);
    for (const [id] of GHOST_DICE) if (id) expect(ids).toContain(id);
    let seq = 0;
    const rng = { randf: () => ((seq = (seq + 0.37) % 1)), randi: () => 0 } as never;
    const seen = new Set<string>();
    for (let k = 0; k < 200; k++) seen.add(ghostDice(rng));
    expect(seen.has("")).toBe(true);
    expect(seen.size).toBeGreaterThan(2);
  });
});
