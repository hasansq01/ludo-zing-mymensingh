// S&L parity with the GDScript rules: replays every game recorded by godot/dev/net_parity_dump_sl.gd with the TS
// port and checks, after every action, the events (deep equal), the full state (deep equal) and the state hash (TS
// slStateHash vs the GDScript SLStateHash.of recorded in the trace). Regenerate the fixture from the repo root with
//   godot --headless --path godot -s res://dev/net_parity_dump_sl.gd
import { describe, expect, it } from "vitest";
import tracesJson from "./fixtures/sl_traces.json?raw";
import * as SL from "../src/rules/sl";
import type { SlAction, SlState } from "../src/rules/sl";
import { slStateHash } from "../src/rules/sl_hash";
import { deepEqual } from "./rules_helpers";

type PlayerRow = [number, Record<string, unknown>, number[]?];
type Step = [string, number, number | string, number, string, Record<string, unknown>];
interface Game {
  seed: number;
  args: { mode: string; n: number; color: number; opts: { need_one: boolean } };
  s0: SlState;
  h0: string;
  steps: Step[];
  end?: { standings: unknown[]; win_reward: number; play_reward: number; replay: boolean[] };
}
interface Traces {
  version: number;
  games: Game[];
  ev: unknown[][];
}

const T = JSON.parse(tracesJson) as Traces;

function toAction(st: Step): SlAction {
  const [k, c, val] = st;
  switch (k) {
    case "roll":
      return { k, c, v: val as number };
    case "mode":
      return { k, c, mode: val as "cpu" | "human" };
    case "end":
      return { k };
  }
  throw new Error(`unknown action ${k}`);
}

/** Applies one step's state diff (players: changed players only, with appended rolls) to the expected state. */
function applyDiff(exp: Record<string, unknown>, diff: Record<string, unknown>): void {
  for (const [k, v] of Object.entries(diff)) {
    if (k === "players") {
      for (const [i, fields, added] of v as PlayerRow[]) {
        const p = (exp.players as Record<string, unknown>[])[i];
        Object.assign(p, structuredClone(fields));
        if (added) (p.rolls as number[]).push(...added);
      }
    } else {
      exp[k] = structuredClone(v);
    }
  }
}

function fail(where: string, got: unknown, want: unknown): never {
  expect(got, where).toEqual(want); // a readable diff
  throw new Error(where);
}

describe("S&L GDScript parity traces", () => {
  it("fixture is present and covers the interesting cases", () => {
    expect(T.version).toBe(1);
    expect(T.games.length).toBeGreaterThanOrEqual(200);
    const types = new Set<string>();
    for (const evs of T.ev) for (const e of evs) types.add((e as { type: string }).type);
    expect([...types].sort()).toEqual(["finished", "move", "over", "rolled", "three_sixes", "turn", "wait", "win"]);
    const evs = T.ev.flat() as { type: string; ladder?: boolean; snake?: boolean; again?: boolean }[];
    expect(evs.some((e) => e.type === "move" && e.ladder)).toBe(true);
    expect(evs.some((e) => e.type === "move" && e.snake)).toBe(true);
    expect(evs.some((e) => e.type === "turn" && e.again)).toBe(true);
    const kinds = new Set(T.games.flatMap((g) => g.steps.map((s) => s[0])));
    expect([...kinds].sort()).toEqual(["end", "mode", "roll"]);
    // play on: several players home in one game, a finish the game goes on after, "end" mid-game and after the end
    const finishes = (g: Game) => g.steps.flatMap((st) => T.ev[st[3]] as { type: string }[]).filter((e) => e.type === "finished").length;
    expect(T.games.filter((g) => finishes(g) >= 3).length).toBeGreaterThanOrEqual(10);
    expect(T.games.some((g) => g.steps.some((st) => {
      const l = T.ev[st[3]] as { type: string }[];
      return l.some((e) => e.type === "finished") && l.at(-1)?.type === "turn";
    }))).toBe(true);
    expect(T.games.some((g) => g.steps.some((st) => st[0] === "end" && T.ev[st[3]].length > 0))).toBe(true);
    expect(T.games.some((g) => g.steps.some((st) => st[0] === "end" && T.ev[st[3]].length === 0))).toBe(true);
    expect(new Set(T.games.map((g) => g.args.n))).toEqual(new Set([2, 3, 4]));
    expect(new Set(T.games.map((g) => g.args.mode))).toEqual(new Set(["cpu", "local"]));
    expect(new Set(T.games.map((g) => g.args.opts.need_one))).toEqual(new Set([true, false]));
    expect(T.games.some((g) => g.end && g.end.win_reward > 0)).toBe(true);
    expect(T.games.some((g) => g.end && g.end.play_reward > 0)).toBe(true);
    // refused rolls after the end
    expect(T.games.some((g) => g.steps.some((s) => s[0] === "roll" && T.ev[s[3]].length === 0))).toBe(true);
  });

  let steps = 0;
  for (const g of T.games) {
    const { mode, n, color, opts } = g.args;
    it(`game ${g.seed} (${mode} ${n}${opts.need_one ? " need_one" : ""}, ${g.steps.length} steps)`, () => {
      const s = SL.newGame(mode, n, color, opts);
      if (!deepEqual(s, g.s0)) fail("new_game", s, g.s0);
      expect(slStateHash(s)).toBe(g.h0);
      const exp = structuredClone(g.s0) as unknown as Record<string, unknown>;
      for (let k = 0; k < g.steps.length; k++) {
        const st = g.steps[k];
        const a = toAction(st);
        if (a.k === "roll" && s.phase === "roll" && SL.turnColor(s) !== a.c) fail(`step ${k}: roll colour`, a.c, SL.turnColor(s));
        const ev = SL.applySlAction(s, a);
        const where = `game ${g.seed} step ${k} ${JSON.stringify(a)}`;
        if (!deepEqual(ev, T.ev[st[3]])) fail(`${where}: events`, ev, T.ev[st[3]]);
        applyDiff(exp, st[5]);
        if (!deepEqual(s, exp)) fail(`${where}: state`, s, exp);
        const h = slStateHash(s);
        if (h !== st[4]) fail(`${where}: hash`, h, st[4]);
        if (slStateHash(SL.cloneSlState(s)) !== h) fail(`${where}: hash after JSON`, slStateHash(SL.cloneSlState(s)), h);
        steps++;
      }
      if (g.end) {
        expect(s.phase).toBe("over");
        expect(SL.botAction(s, 3)).toBeNull();
        expect(SL.standings(s)).toEqual(g.end.standings);
        expect(s.players.map((p) => SL.replayReaches100(p.rolls, SL.needsOne(s)))).toEqual(g.end.replay);
        const w = SL.cloneSlState(s);
        expect(SL.claimWinReward(w)).toBe(g.end.win_reward);
        expect(SL.claimWinReward(w)).toBe(0); // paid once
        const pl = SL.cloneSlState(s);
        expect(SL.claimPlayReward(pl)).toBe(g.end.play_reward);
        expect(SL.claimPlayReward(pl)).toBe(0);
      }
    });
  }

  it("replayed every recorded step", () => {
    expect(steps).toBe(T.games.reduce((n, g) => n + g.steps.length, 0));
  });
});
