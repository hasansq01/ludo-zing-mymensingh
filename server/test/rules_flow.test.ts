// Port of the rules parts of godot/tests/test_ludo_flow.gd: three 6s, stuck rolls, units(), automatic pairing and the
// "Ask before pairing" house rule, new games, rewards and JSON round trips. (LudoMatch.result_copy is client-only.)
import { expect, it } from "vitest";
import * as Ludo from "../src/rules/ludo";
import type { LudoEvent } from "../src/rules/ludo";
import { base, play, prog, state } from "./rules_helpers";

const has = (ev: LudoEvent[], f: (e: LudoEvent) => boolean) => ev.some(f);
const stuck = (ev: LudoEvent[], reason: string) => has(ev, (e) => e.type === "stuck" && e.reason === reason);
const vs = { players: ["human", "cpu", "cpu", "cpu"], names: ["You", "Mocha", "Biscotti", "Espresso"] };

it("three 6s and stuck rolls", () => {
  let t = base(); t[0][0] = 10;
  let s = state(t);
  play(s, 6, 0); play(s, 6, 0);
  expect([s.turn, s.sixes, s.tok[0][0]]).toEqual([0, 2, 22]);
  let ev = Ludo.applyRoll(s, 6);
  expect([s.turn, s.sixes, s.tok[0][0]]).toEqual([1, 0, 22]);
  expect(has(ev, (e) => e.type === "three_sixes")).toBe(true);
  s = state(base());
  ev = Ludo.applyRoll(s, 4);
  expect(s.turn).toBe(1);
  expect(stuck(ev, "No move this time.")).toBe(true);
  t = base(); t[0] = [56, 56, 56, 54]; s = state(t);
  ev = Ludo.applyRoll(s, 6);
  expect([s.turn, s.phase, s.sixes]).toEqual([0, "roll", 1]);
  expect(stuck(ev, "No move. Roll again.")).toBe(true);
  t = base(); t[0][0] = 10; t[3][0] = prog(3, 12); t[3][1] = prog(3, 12);
  s = state(t, [{ c: 3, a: 0, b: 1 }]);
  ev = Ludo.applyRoll(s, 4);
  expect(s.turn).toBe(1);
  expect(stuck(ev, "Blocked by Blue's pair.")).toBe(true);
  t = base(); t[1][0] = 10; t[0][0] = prog(0, 25); t[0][1] = prog(0, 25);
  s = state(t, [{ c: 0, a: 0, b: 1 }], { ...vs, turn: 1 });
  expect(stuck(Ludo.applyRoll(s, 4), "Blocked by your pair.")).toBe(true);
  t = base(); t[1][0] = 10; t[0][0] = prog(0, 25); t[0][1] = prog(0, 25); t[1][1] = 56; t[1][2] = 56; t[1][3] = 56;
  s = state(t, [{ c: 0, a: 0, b: 1 }], { ...vs, turn: 1 });
  ev = Ludo.applyRoll(s, 6);
  expect(s.turn).toBe(1);
  expect(stuck(ev, "Blocked by your pair. Roll again.")).toBe(true);
  t = base(); t[0][0] = prog(0, 30); t[0][1] = prog(0, 30);
  s = state(t, [{ c: 0, a: 0, b: 1 }]);
  expect(Ludo.stuckReason(s, 0, 5)).toBe("A pair needs an even roll.");
  expect(["No move this time.", Ludo.stuckReason(s, 0, 5), Ludo.stuckReason(state(base()), 0, 6)].every((x) => !x.includes("token"))).toBe(true);
});

it("every legal unit may be tapped (units, unit_for_token, auto_move_token)", () => {
  let t = base(); t[0][0] = 10; t[0][1] = 10; t[0][2] = 20; t[0][3] = 30;
  let s = state(t, [{ c: 0, a: 0, b: 1 }]);
  const ev = Ludo.applyRoll(s, 4);
  expect(s.phase).toBe("choose");
  expect(ev).toEqual([
    { type: "rolled", c: 0, v: 4 },
    { type: "choose", c: 0, mover: 0, movable: [0, 2, 3] },
  ]);
  let us = Ludo.units(s);
  expect(us).toEqual([
    { mover: 0, tokens: [0, 1], token: 0, pair: true, from: 10, to: 12 },
    { mover: 0, tokens: [2], token: 2, pair: false, from: 20, to: 24 },
    { mover: 0, tokens: [3], token: 3, pair: false, from: 30, to: 34 },
  ]);
  expect(Ludo.unitForToken(s, 1)?.tokens).toEqual([0, 1]);
  expect(Ludo.unitForToken(s, 0)?.token).toBe(0);
  expect(Ludo.unitForToken(s, 3)?.tokens).toEqual([3]);
  expect(Ludo.autoMoveToken(s)).toBe(-1);
  Ludo.move(s, 1);
  expect(s.tok[0]).toEqual([12, 12, 20, 30]);
  t = base(); t[0][0] = 10; t[0][1] = 10; t[0][2] = 20;
  s = state(t, [{ c: 0, a: 0, b: 1 }]);
  Ludo.applyRoll(s, 3);
  us = Ludo.units(s);
  expect(us.map((u) => u.tokens)).toEqual([[2]]);
  expect(Ludo.unitForToken(s, 0)).toBeNull();
  expect(Ludo.unitForToken(s, 1)).toBeNull();
  expect(Ludo.move(s, 0)).toEqual([]);
  expect(s.tok[0].slice(0, 2)).toEqual([10, 10]);
  expect(Ludo.autoMoveToken(s)).toBe(2);
  t = base(); t[0][0] = 10; t[0][1] = 10; t[0][2] = 20; t[0][3] = 30;
  s = state(t, [{ c: 0, a: 0, b: 1 }]);
  Ludo.applyRoll(s, 4);
  expect(Ludo.choosePick(s, "single")).toBe(true);
  expect(Ludo.units(s).length).toBe(2);
  expect(Ludo.move(s, 0)).toEqual([]);
  expect(Ludo.choosePick(s, "triple")).toBe(false);
  Ludo.move(s, 3);
  expect([s.tok[0][3], s.pick]).toEqual([34, ""]);
  t = base(); t[0][0] = 15; t[0][1] = 15; t[0][2] = 30; s = state(t);
  Ludo.applyRoll(s, 3);
  expect([Ludo.autoMoveToken(s), Ludo.units(s).length]).toEqual([-1, 3]);
  t = base(); t[0][0] = 15; t[0][1] = 15; s = state(t);
  Ludo.applyRoll(s, 3);
  expect([Ludo.autoMoveToken(s), Ludo.units(s).length]).toEqual([0, 2]);
  t = base(); t[1][0] = 10; t[1][1] = 10; t[1][2] = 20;
  s = state(t, [{ c: 1, a: 0, b: 1 }], { players: ["human", "cpu", "cpu", "cpu"], turn: 1 });
  Ludo.applyRoll(s, 4);
  expect(s.phase).toBe("choose");
  s = state(base());
  expect(Ludo.units(s)).toEqual([]);
  expect(Ludo.unitForToken(s, 0)).toBeNull();
});

it("pairing: automatic by default, asked with the house rule", () => {
  let t = base(); t[0][0] = 10; t[0][1] = 12;
  let s = state(t);
  play(s, 2, 0);
  expect([s.pairs, s.phase, s.turn]).toEqual([[{ c: 0, a: 0, b: 1 }], "roll", 1]);
  t = base(); t[0][0] = 6; t[0][1] = 8; s = state(t);
  play(s, 2, 0);
  expect([s.pairs, s.tok[0][0], s.phase]).toEqual([[], 8, "roll"]);
  t = base(); t[0][0] = 6; t[0][1] = 12; s = state(t);
  Ludo.applyRoll(s, 6);
  let ev = Ludo.move(s, 0);
  expect(has(ev, (e) => e.type === "pair_formed" && e.human)).toBe(true);
  expect([s.turn, s.phase]).toEqual([0, "roll"]);
  expect(has(ev, (e) => e.type === "pair_offer")).toBe(false);

  t = base(); t[0][0] = 10; t[0][1] = 12; s = state(t, [], { pair_ask: true });
  play(s, 2, 0);
  expect([s.phase, s.pending, s.turn]).toEqual(["pair_ask", { c: 0, i: 0, to: 12, extra: false, partner: 1 }, 0]);
  expect(Ludo.applyRoll(s, 3)).toEqual([]);
  ev = Ludo.answerPair(s, true);
  expect(ev).toEqual([
    { type: "pair_formed", c: 0, a: 0, b: 1, human: true },
    { type: "turn", c: 1, again: false },
  ]);
  expect([s.pairs, s.turn, s.phase, s.pending]).toEqual([[{ c: 0, a: 0, b: 1 }], 1, "roll", {}]);
  t = base(); t[0][0] = 10; t[0][1] = 12; s = state(t, [], { pair_ask: true });
  play(s, 2, 0); Ludo.answerPair(s, false);
  expect([s.pairs, s.turn]).toEqual([[], 1]);
  t = base(); t[0][0] = 6; t[0][1] = 12; s = state(t, [], { pair_ask: true });
  play(s, 6, 0);
  expect(s.phase).toBe("pair_ask");
  Ludo.answerPair(s, true);
  expect([s.turn, s.phase, s.pairs.length]).toEqual([0, "roll", 1]);
  t = base(); t[0][0] = 6; t[0][1] = 8; s = state(t, [], { pair_ask: true });
  play(s, 2, 0);
  expect(s.phase, "asked on a star square too").toBe("pair_ask");
  t = base(); t[1][0] = 10; t[1][1] = 12;
  s = state(t, [], { players: ["human", "cpu", "cpu", "cpu"], turn: 1, pair_ask: true });
  Ludo.applyRoll(s, 2); Ludo.move(s, 0);
  expect([s.pairs.length, s.phase]).toEqual([1, "roll"]);
  s = Ludo.newGame(["human", "cpu", "off", "off"], false, { pair_ask: true });
  expect(s.pair_ask).toBe(true);
  expect(Ludo.newGame(["human", "cpu", "off", "off"]).pair_ask).toBe(false);
  const cpu = { players: ["cpu", "human", "cpu", "cpu"] };
  t = base(); t[0][0] = 10; t[0][1] = 12; s = state(t, [], cpu);
  Ludo.applyRoll(s, 2); Ludo.move(s, 0);
  expect([s.pairs.length, s.phase]).toEqual([1, "roll"]);
  t = base(); t[0][0] = 6; t[0][1] = 8; s = state(t, [], cpu);
  Ludo.applyRoll(s, 2); Ludo.move(s, 0);
  expect([s.pairs, s.tok[0][0]]).toEqual([[], 8]);
});

it("new games, rewards, JSON", () => {
  let s = Ludo.newGame(["off", "human", "cpu", "off"]);
  expect([s.turn, s.names, s.view]).toEqual([1, ["", "You", "Mocha", ""], 1]);
  expect(Ludo.newGame(["human", "human", "off", "off"]).names).toEqual(["Red", "Green", "", ""]);
  expect(Ludo.newGame(["cpu", "cpu", "cpu", "cpu"]).names).toEqual(["Mocha", "Biscotti", "Espresso", "Blue"]);
  let t = base(); t[0] = [56, 56, 56, 55];
  s = state(t, [], { players: ["human", "cpu", "off", "off"], names: ["You", "Mocha", "", ""] });
  play(s, 1);
  expect([s.phase, Ludo.winReward(s), Ludo.playReward(s)]).toEqual(["over", Ludo.WIN_REWARD, 0]);
  t = base(); t[1] = [56, 56, 56, 55];
  s = state(t, [], { players: ["human", "cpu", "off", "off"], names: ["You", "Mocha", "", ""], turn: 1 });
  play(s, 1);
  expect([s.phase, s.winner, Ludo.winReward(s), Ludo.playReward(s)]).toEqual(["over", 1, 0, Ludo.PLAY_REWARD]);
  t = base(); t[0] = [56, 56, 56, 55]; s = state(t);
  play(s, 1);
  expect([s.phase, Ludo.winReward(s), Ludo.playReward(s)]).toEqual(["roll", 0, 0]); // Pass & Play: the others play on
  Ludo.endGame(s);
  expect([s.phase, s.winner, Ludo.winReward(s), Ludo.playReward(s)]).toEqual(["over", 0, 0, 0]);
  expect(Ludo.playReward(Ludo.newGame(["human", "cpu", "off", "off"]))).toBe(0);
  s = Ludo.newGame(["human", "cpu", "cpu", "cpu"], true);
  const rt = JSON.parse(JSON.stringify(s));
  expect(rt).toEqual(s);
});

it("refused actions change nothing", () => {
  const s = Ludo.newGame(["human", "human", "off", "off"]);
  const before = JSON.stringify(s);
  expect(Ludo.move(s, 0)).toEqual([]);
  expect(Ludo.answerPair(s, true)).toEqual([]);
  Ludo.applyRoll(s, 6);
  const chosen = JSON.stringify(s);
  expect(Ludo.applyRoll(s, 6)).toEqual([]);
  for (const i of [-1, 4, 1.5, NaN]) expect(Ludo.move(s, i)).toEqual([]);
  expect(JSON.stringify(s)).toBe(chosen);
  expect(before).not.toBe(chosen);
});
