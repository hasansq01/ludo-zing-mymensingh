// Parity with the GDScript rules: replays every game recorded by godot/dev/net_parity_dump.gd with the TS port and
// checks, after every action, the events (deep equal), the full state (deep equal) and the state hash (TS stateHash
// vs the GDScript StateHash.of recorded in the trace). Regenerate the fixture from the repo root with
//   godot --headless --path godot -s res://dev/net_parity_dump.gd
import { describe, expect, it } from "vitest";
import tracesJson from "./fixtures/ludo_traces.json?raw";
import * as Ludo from "../src/rules/ludo";
import type { Action, LudoState } from "../src/rules/ludo";
import { stateHash } from "../src/rules/hash";
import { Mulberry32 } from "../src/rules/rng";
import { deepEqual } from "./rules_helpers";

type Step = [string, number, number | boolean | string, number, string, Record<string, unknown>, Extra?];
interface Extra {
  auto: number;
  units: unknown[];
}
interface Game {
  seed: number;
  args: { players: string[]; teams: boolean; opts: { pair_ask?: boolean } };
  levels: string[];
  s0: LudoState;
  h0: string;
  steps: Step[];
  end?: { standings: unknown[]; winners: number[]; win_reward: number; play_reward: number };
}
interface Traces {
  version: number;
  games: Game[];
  ev: unknown[][];
}

const T = JSON.parse(tracesJson) as Traces;

function toAction(st: Step): Action {
  const [k, c, val] = st;
  switch (k) {
    case "roll":
      return { k, c, v: val as number };
    case "move":
      return { k, c, i: val as number };
    case "pair":
      return { k, c, yes: val as boolean };
    case "mode":
      return { k, c, mode: val as "cpu" | "human" };
  }
  throw new Error(`unknown action ${k}`);
}

/** Applies one step's state diff (tok: changed rows only) to the expected state. */
function applyDiff(exp: Record<string, unknown>, diff: Record<string, unknown>): void {
  for (const [k, v] of Object.entries(diff)) {
    if (k === "tok") {
      for (const [c, row] of v as [number, number[]][]) (exp.tok as number[][])[c] = structuredClone(row);
    } else {
      exp[k] = structuredClone(v);
    }
  }
}

function fail(where: string, got: unknown, want: unknown): never {
  expect(got, where).toEqual(want); // a readable diff
  throw new Error(where);
}

describe("GDScript parity traces", () => {
  it("fixture is present and covers the interesting cases", () => {
    expect(T.version).toBe(1);
    expect(T.games.length).toBeGreaterThanOrEqual(100);
    const types = new Set<string>();
    for (const evs of T.ev) for (const e of evs) types.add((e as { type: string }).type);
    for (const t of ["rolled", "three_sixes", "need_six", "free_hand", "stuck", "choose", "move", "capture", "split",
      "pair_offer", "pair_formed", "home", "finished", "turn", "game_over"]) {
      expect(types.has(t), t).toBe(true);
    }
    const kinds = new Set(T.games.flatMap((g) => g.steps.map((s) => s[0])));
    expect([...kinds].sort()).toEqual(["mode", "move", "pair", "roll"]);
    expect(T.games.some((g) => g.args.teams && g.end)).toBe(true);
    expect(new Set(T.games.map((g) => g.args.players.filter((p) => p !== "off").length))).toEqual(new Set([2, 3, 4]));
  });

  for (const g of T.games) {
    const seats = g.args.players.map((p) => p[0]).join("");
    it(`game ${g.seed} (${seats}${g.args.teams ? " teams" : ""}${g.args.opts.pair_ask ? " ask" : ""}, ${g.steps.length} steps)`, () => {
      const s = Ludo.newGame(g.args.players, g.args.teams, g.args.opts);
      if (!deepEqual(s, g.s0)) fail("new_game", s, g.s0);
      expect(stateHash(s)).toBe(g.h0);
      const exp = structuredClone(g.s0) as unknown as Record<string, unknown>;
      const rng = new Mulberry32(g.seed);
      for (let n = 0; n < g.steps.length; n++) {
        const st = g.steps[n];
        const a = toAction(st);
        const ev = Ludo.applyAction(s, a);
        const where = `game ${g.seed} step ${n} ${JSON.stringify(a)}`;
        if (!deepEqual(ev, T.ev[st[3]])) fail(`${where}: events`, ev, T.ev[st[3]]);
        applyDiff(exp, st[5]);
        if (!deepEqual(s, exp)) fail(`${where}: state`, s, exp);
        const h = stateHash(s);
        if (h !== st[4]) fail(`${where}: hash`, h, st[4]);
        const extra = st[6];
        if (extra) {
          if (Ludo.autoMoveToken(s) !== extra.auto) fail(`${where}: auto_move_token`, Ludo.autoMoveToken(s), extra.auto);
          if (!deepEqual(Ludo.units(s), extra.units)) fail(`${where}: units`, Ludo.units(s), extra.units);
        }
        if (s.phase === "choose" && n % 3 === 0) {
          // the bots: every level picks a legal unit and thinking never changes the state
          const mv = Ludo.movables(s);
          for (const level of Ludo.LEVELS) {
            const i = Ludo.pickAi(s, mv, rng, level);
            if (!mv.includes(i)) fail(`${where}: pickAi ${level}`, i, mv);
          }
          if (stateHash(s) !== h || !deepEqual(s, exp)) fail(`${where}: pickAi changed the state`, s, exp);
        }
      }
      if (g.end) {
        expect(s.phase).toBe("over");
        expect(Ludo.standings(s)).toEqual(g.end.standings);
        expect(Ludo.winners(s)).toEqual(g.end.winners);
        expect(Ludo.winReward(s)).toBe(g.end.win_reward);
        expect(Ludo.playReward(s)).toBe(g.end.play_reward);
      }
    });
  }
});
