// Port of godot/tests/test_ludo_standings.gd: "You" helpers, team labels, finish order and standings().
import { expect, it } from "vitest";
import * as Ludo from "../src/rules/ludo";
import { base, play, state } from "./rules_helpers";

const HOME = () => [56, 56, 56, 56];
const vs = { players: ["human", "cpu", "cpu", "cpu"], names: ["You", "Mocha", "Biscotti", "Espresso"] };

it("is_you and grammar helpers", () => {
  let s = Ludo.newGame(["human", "cpu", "cpu", "cpu"]);
  expect([Ludo.isYou(s, 0), Ludo.isYou(s, 1), Ludo.isYou(s, 3)]).toEqual([true, false, false]);
  s = Ludo.newGame(["cpu", "off", "human", "cpu"]);
  expect([Ludo.isYou(s, 2), Ludo.isYou(s, 0), Ludo.isYou(s, 1)]).toEqual([true, false, false]);
  s = Ludo.newGame(["human", "human", "off", "off"]);
  expect([Ludo.isYou(s, 0), Ludo.isYou(s, 1)]).toEqual([false, false]);
  s = Ludo.newGame(["human", "cpu", "off", "off"]);
  s.names[0] = "Shihab";
  expect(Ludo.isYou(s, 0)).toBe(true);
  expect([Ludo.isYou(s, -1), Ludo.isYou(s, 4)]).toEqual([false, false]);
  s = Ludo.newGame(["human", "cpu", "cpu", "off"]);
  expect([Ludo.subject(s, 0), Ludo.subject(s, 1)]).toEqual(["You", "Mocha"]);
  expect([Ludo.object(s, 0), Ludo.object(s, 2)]).toEqual(["you", "Biscotti"]);
  expect([Ludo.poss(s, 0), Ludo.poss(s, 0, false), Ludo.poss(s, 1), Ludo.poss(s, 1, false)]).toEqual(["Your", "your", "Mocha's", "Mocha's"]);
  expect([Ludo.verb(s, 0, "roll", "rolls"), Ludo.verb(s, 1, "roll", "rolls")]).toEqual(["roll", "rolls"]);
  s = Ludo.newGame(["human", "human", "off", "off"]);
  expect([Ludo.subject(s, 1), Ludo.verb(s, 1, "go", "goes"), Ludo.poss(s, 0)]).toEqual(["Green", "goes", "Red's"]);
});

it("team names", () => {
  let s = Ludo.newGame(["human", "cpu", "cpu", "cpu"], true);
  expect([Ludo.teamLabel(s, 0), Ludo.teamLabel(s, 2), Ludo.teamLabel(s, 3)]).toEqual(["Red + Yellow", "Red + Yellow", "Green + Blue"]);
  expect([Ludo.teamName(s, 2), Ludo.teamName(s, 1)]).toEqual(["Your team", "Mocha + Espresso"]);
  s = Ludo.newGame(["human", "human", "human", "human"], true);
  expect(Ludo.teamName(s, 3)).toBe("Green + Blue");
});

it("win reward uses is_you; progress", () => {
  let t = base(); t[0] = [56, 56, 56, 55];
  let s = state(t, [], { players: ["human", "cpu", "off", "off"], names: ["Shihab", "Mocha", "", ""] });
  play(s, 1);
  expect([s.phase, Ludo.winReward(s)]).toEqual(["over", Ludo.WIN_REWARD]);
  expect(Ludo.progress(state(base()), 0)).toBe(0);
  t = base(); t[0] = HOME();
  expect(Ludo.progress(state(t), 0)).toBeCloseTo(1.0);
  t = base(); t[0] = [56, 56, -1, -1];
  expect(Ludo.progress(state(t), 0)).toBeCloseTo(0.5);
});

it("finish order and standings (Individual)", () => {
  expect(Ludo.newGame(["human", "cpu", "cpu", "cpu"]).finished).toEqual([]);
  let t = base(); t[1] = [56, 56, 56, 55]; t[0][0] = 30; t[2][0] = 10; t[3][0] = 40;
  let s = state(t, [], { ...vs, turn: 1, finished: [] });
  play(s, 1);
  expect([s.phase, s.finished]).toEqual(["over", [1]]);
  let st = Ludo.standings(s);
  expect(st.map((e) => e.color)).toEqual([1, 3, 0, 2]);
  expect(st.map((e) => e.place)).toEqual([1, 2, 3, 4]);
  expect([st[0].finished, st[1].finished]).toEqual([true, false]);
  expect(st.every((e) => e.progress >= 0 && e.progress <= 1)).toBe(true);
  expect(st[0].progress).toBeCloseTo(1.0);
  t = base(); t[0][0] = 20; t[1][0] = 20;
  st = Ludo.standings(state(t, [], { players: ["human", "off", "human", "off"] }));
  expect(st.map((e) => e.color)).toEqual([0, 2]);
  s = state(base());
  expect(Ludo.standings(s).length).toBe(4);
  t = base(); t[0] = [56, 56, 56, 55];
  s = state(t);
  play(s, 1);
  expect(s.finished).toEqual([0]);
});

it("finish order and standings (Teams)", () => {
  let t = base(); t[0] = [56, 56, 56, 55]; t[2][0] = 10; t[1][0] = 5; t[3][0] = 30;
  let s = state(t, [], { teams: true, finished: [] });
  const ev = Ludo.move((Ludo.applyRoll(s, 1), s), 3);
  expect(ev.map((e) => e.type)).toEqual(["move", "home", "finished", "turn"]);
  expect([s.finished, s.phase, s.winner]).toEqual([[0], "roll", -1]);
  let st = Ludo.standings(s);
  expect(st.map((e) => e.color)).toEqual([0, 2, 3, 1]);
  expect(st.map((e) => e.place)).toEqual([1, 1, 2, 2]);
  s.tok[2] = [56, 56, 56, 55]; s.turn = 2; s.phase = "roll"; s.sixes = 0;
  play(s, 1);
  expect([s.phase, s.finished]).toEqual(["over", [0, 2]]);
  st = Ludo.standings(s);
  expect([st[0].place, st[1].place, st[0].finished, st[1].finished, st[2].place]).toEqual([1, 1, true, true, 2]);
  t = base(); t[0] = HOME(); t[2] = [56, 56, 56, 55];
  s = state(t, [], { teams: true, finished: [], free: [true, false, false, false] });
  play(s, 1);
  expect(s.phase).toBe("over");
  expect([...(s.finished ?? [])].sort()).toEqual([0, 2]);
  expect(s.finished).toEqual([0, 2]); // Yellow wins; Red (home earlier, not recorded) goes in before it
  t = base(); t[1][0] = 50; t[3][0] = 2;
  st = Ludo.standings(state(t, [], { teams: true, finished: [] }));
  expect([st[0].color, st[0].place, st[2].place]).toEqual([1, 1, 2]);
});

it("JSON round trip with the new fields", () => {
  const s = Ludo.newGame(["human", "cpu", "cpu", "cpu"], false, { pair_ask: true });
  s.finished = [2];
  const rt = JSON.parse(JSON.stringify(s));
  expect([rt.pair_ask, rt.finished]).toEqual([true, [2]]);
  expect(Ludo.standings(rt).length).toBe(4);
  expect(Ludo.standings(rt)[0].color).toBe(2);
});
