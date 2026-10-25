// Ludo rules: a line-for-line port of godot/scripts/core/ludo_rules.gd (class LudoRules).
//
// The state shape (snake_case keys) and the event objects ("type" strings and field names) are exactly the
// GDScript ones, because clients replay the server's actions with the GDScript rules and compare state hashes.
// Parity is tested by replaying traces recorded from the GDScript rules (test/rules_parity.test.ts).
//
// GDScript -> TS notes:
// - helpers that return {} for "none" in GDScript (pair_of, opp_pair_at, _blocker, unit_for_token) return null here;
//   they never end up in the state or in events. s.pending is {} (empty object) when no question is open, as in
//   GDScript.
// - int division (d / 2 on ints) is Math.trunc; mini / maxi are Math.min / Math.max; Array.find is indexOf;
//   find_custom is findIndex; sort_custom (comparators here are total orders) is Array.sort.
// - move() rejects a token index outside 0-3 (GDScript would index from the end for -1; the server validates first).
//
// State: { players[4] ("human" | "cpu" | "off"), names[4], view, tok[4][4], pairs [{c, a, b}], turn, dice, sixes,
//   phase, pick ("" | "single" | "pair"), winner, teams, free[4], pending, pair_ask, finished [colours] }
// Progress per token: -1 base, 0-50 track, 51-55 home column, 56 (GOAL) finished.
// Colours: 0 red, 1 green, 2 yellow, 3 blue.
//
// Play on after the first finish (see the GDScript header): a finished side gets its place ("finished" event) and is
// skipped; the game is over when fewer than two sides are unfinished or no unfinished side has a "human" seat; the
// unfinished sides are then ranked by progress and s.finished is the full order. endGame() (the {k: "end"} action)
// ends a game early the same way.

import { mathRandom, type Rng } from "./rng";

export const OFF = [0, 13, 26, 39] as const;
export const STARS = [8, 21, 34, 47] as const;
export const SAFE = [0, 13, 26, 39, 8, 21, 34, 47] as const;
export const GOAL = 56;
export const NO_MOVE = -1;
export const COLOR_NAMES = ["Red", "Green", "Yellow", "Blue"] as const;
export const CPU_NAMES = ["Mocha", "Biscotti", "Espresso"] as const;
export const WIN_REWARD = 200;
export const PLAY_REWARD = 20;
export const LEVELS = ["easy", "normal", "hard"] as const;
export const RISK_W = 4.0;

export type Seat = "human" | "cpu" | "off";
export type Phase = "roll" | "choose" | "pair_ask" | "over" | "pick";
export type Level = "easy" | "normal" | "hard";

export interface Pair {
  c: number;
  a: number;
  b: number;
}

/** s.pending while phase is "pair_ask" (move() fills it); {} otherwise. */
export interface Pending {
  c: number;
  i: number;
  to: number;
  extra: boolean;
  partner?: number;
}

export interface LudoState {
  players: string[];
  names: string[];
  view: number;
  tok: number[][];
  pairs: Pair[];
  turn: number;
  dice: number;
  sixes: number;
  phase: string;
  pick: string;
  winner: number;
  teams: boolean;
  free: boolean[];
  pending: Pending | Record<string, never>;
  pair_ask?: boolean;
  finished?: number[];
}

export type LudoEvent =
  | { type: "rolled"; c: number; v: number }
  | { type: "three_sixes"; c: number }
  | { type: "need_six"; c: number; v: number }
  | { type: "free_hand"; c: number; mate: number }
  | { type: "stuck"; c: number; mover: number; reason: string }
  | { type: "choose"; c: number; mover: number; movable: number[] }
  | { type: "move"; c: number; roller: number; tokens: number[]; from: number; to: number; pair: boolean }
  | { type: "capture"; c: number; victims: number[][] }
  | { type: "split"; c: number; tokens: number[]; where: "lane" | "start" }
  | { type: "pair_offer"; c: number; a: number; b: number }
  | { type: "pair_formed"; c: number; a: number; b: number; human: boolean }
  | { type: "home"; c: number }
  | { type: "all_home"; c: number }
  | { type: "finished"; c: number; place: number; team?: number[] }
  | { type: "turn"; c: number; again: boolean }
  | { type: "game_over"; winner: number; team: number[]; order: number[] };

export interface Unit {
  mover: number;
  tokens: number[];
  token: number;
  pair: boolean;
  from: number;
  to: number;
}

export interface Standing {
  color: number;
  place: number;
  finished: boolean;
  progress: number;
}

export interface NewGameOpts {
  pair_ask?: boolean;
}

function isEmpty(d: object): boolean {
  return Object.keys(d).length === 0;
}

// ---------- setup ----------

/** opts: {pair_ask} - the "Ask before pairing" house rule (default false). */
export function newGame(players: string[], teams = false, opts: NewGameOpts = {}): LudoState {
  teams = teams && players.every((p) => p !== "off"); // Pair Mode needs all four seats
  const humans = players.filter((p) => p === "human").length;
  const names: string[] = [];
  let cpuNo = 0;
  for (let c = 0; c < 4; c++) {
    if (players[c] === "off") {
      names.push("");
    } else if (players[c] === "cpu") {
      names.push(cpuNo < CPU_NAMES.length ? CPU_NAMES[cpuNo] : COLOR_NAMES[c]);
      cpuNo += 1;
    } else {
      names.push(humans === 1 ? "You" : COLOR_NAMES[c]);
    }
  }
  const h = players.indexOf("human");
  return {
    players: [...players],
    names,
    view: h >= 0 ? h : 0,
    tok: [
      [-1, -1, -1, -1],
      [-1, -1, -1, -1],
      [-1, -1, -1, -1],
      [-1, -1, -1, -1],
    ],
    pairs: [],
    turn: players.findIndex((p) => p !== "off"),
    dice: 0,
    sixes: 0,
    phase: "roll",
    pick: "",
    winner: -1,
    teams,
    free: [false, false, false, false],
    pending: {},
    pair_ask: Boolean(opts.pair_ask ?? false),
    finished: [],
  };
}

// ---------- board helpers ----------

export function absIndex(c: number, p: number): number {
  return (OFF[c] + p) % 52;
}

export function active(s: LudoState, c: number): boolean {
  return s.players[c] !== "off";
}

export function isHuman(s: LudoState, c: number): boolean {
  return s.players[c] === "human";
}

export function pname(s: LudoState, c: number): string {
  return s.names[c] !== "" ? s.names[c] : COLOR_NAMES[c];
}

/** Colour c is "you": the only human at the table (vs Computer). Never true in Pass & Play. */
export function isYou(s: LudoState, c: number): boolean {
  return c >= 0 && c < 4 && s.players[c] === "human" && s.players.filter((p) => p === "human").length === 1;
}

export function subject(s: LudoState, c: number): string {
  return isYou(s, c) ? "You" : pname(s, c);
}

export function object(s: LudoState, c: number): string {
  return isYou(s, c) ? "you" : pname(s, c);
}

export function poss(s: LudoState, c: number, cap = true): string {
  if (isYou(s, c)) return cap ? "Your" : "your";
  return pname(s, c) + "'s";
}

export function verb(s: LudoState, c: number, base: string, third: string): string {
  return isYou(s, c) ? base : third;
}

/** The next colour that plays after c: active and its side not finished yet (play on: finished sides sit out). */
export function nextActive(s: LudoState, c: number): number {
  for (let k = 1; k < 5; k++) {
    const n = (c + k) % 4;
    if (active(s, n) && !sideDone(s, n)) return n;
  }
  return c;
}

/** Colour c's side has finished: individual, c is in s.finished; Teams, c and its partner both all home. */
export function sideDone(s: LudoState, c: number): boolean {
  if (teamOn(s)) return allHome(s, c) && allHome(s, mateOf(c));
  return finishedOf(s).includes(c);
}

// ---------- Team (Pair Mode) games: Red + Yellow, Green + Blue ----------

export function teamOn(s: LudoState): boolean {
  return Boolean(s.teams);
}

export function mateOf(c: number): number {
  return (c + 2) % 4;
}

export function allHome(s: LudoState, c: number): boolean {
  return s.tok[c].every((p) => p >= GOAL);
}

/** Whose pawns c can capture / is blocked by. */
export function foe(s: LudoState, c: number, o: number): boolean {
  return o !== c && active(s, o) && !(teamOn(s) && o === mateOf(c));
}

/** Finished, Free Hand not started yet. */
export function waitingSix(s: LudoState, c: number): boolean {
  return teamOn(s) && allHome(s, c) && !s.free[c];
}

/** Whose pawns c's roll moves. */
export function moverOf(s: LudoState, c: number): number {
  return teamOn(s) && allHome(s, c) ? mateOf(c) : c;
}

export function teamName(s: LudoState, c: number): string {
  const m = mateOf(c);
  if (isYou(s, c) || isYou(s, m)) return "Your team";
  return `${pname(s, Math.min(c, m))} + ${pname(s, Math.max(c, m))}`;
}

export function teamLabel(_s: LudoState, c: number): string {
  const m = mateOf(c);
  return `${COLOR_NAMES[Math.min(c, m)]} + ${COLOR_NAMES[Math.max(c, m)]}`;
}

// ---------- Pairs: two same-colour tokens joined on one main-track square ----------

/** The pair token i of colour c belongs to, or null when it is a single (GDScript: {}). */
export function pairOf(s: LudoState, c: number, i: number): Pair | null {
  for (const q of s.pairs) {
    if (q.c === c && (q.a === i || q.b === i)) return q;
  }
  return null;
}

export function unitOf(s: LudoState, c: number, i: number): number[] {
  const q = pairOf(s, c, i);
  return q === null ? [i] : [q.a, q.b];
}

/** An opponent pair standing on main-track square absSq, or null. */
export function oppPairAt(s: LudoState, c: number, absSq: number): Pair | null {
  for (const q of s.pairs) {
    if (!foe(s, c, q.c)) continue;
    const p = s.tok[q.c][q.a];
    if (p >= 0 && p <= 50 && absIndex(q.c, p) === absSq) return q;
  }
  return null;
}

/** Any colour's Home Base cell. */
export function onStartSquare(c: number, p: number): boolean {
  return p >= 0 && p <= 50 && (OFF as readonly number[]).includes(absIndex(c, p));
}

function removePair(s: LudoState, c: number, i: number): void {
  s.pairs = s.pairs.filter((q) => !(q.c === c && (q.a === i || q.b === i)));
}

// ---------- moves ----------

/** Where token i (or the pair it belongs to) lands with roll d, or NO_MOVE when the move is illegal. */
export function dest(s: LudoState, c: number, i: number, d: number): number {
  const p = s.tok[c][i];
  const pair = pairOf(s, c, i) !== null;
  if (p >= GOAL) return NO_MOVE;
  if (p < 0) return d === 6 ? 0 : NO_MOVE;
  if (pair && d % 2) return NO_MOVE; // pairs use even rolls only…
  const to = p + (pair ? Math.trunc(d / 2) : d); // …and move half the roll
  if (to > GOAL) return NO_MOVE;
  if (!pair && blocker(s, c, i, d) !== null) return NO_MOVE;
  return to;
}

/** The opponent pair that stops single token i (on the board) moving d squares, or null. */
export function blocker(s: LudoState, c: number, i: number, d: number): Pair | null {
  const p = s.tok[c][i];
  if (p < 0) return null;
  if (p <= 50 && d !== 1) {
    const here = oppPairAt(s, c, absIndex(c, p));
    if (here !== null) return here;
  }
  for (let q = p + 1; q < p + d; q++) {
    if (q > 50) break;
    const on = oppPairAt(s, c, absIndex(c, q));
    if (on !== null) return on;
  }
  return null;
}

export function canMove(s: LudoState, c: number, i: number, d: number): boolean {
  return dest(s, c, i, d) !== NO_MOVE;
}

/** One entry per movable unit of the player whose turn it is; a pair is listed once, by its first token. */
export function movables(s: LudoState): number[] {
  if (waitingSix(s, s.turn)) return [];
  const c = moverOf(s, s.turn);
  const out: number[] = [];
  for (let i = 0; i < 4; i++) {
    const q = pairOf(s, c, i);
    if ((q === null || q.a === i) && canMove(s, c, i, s.dice)) out.push(i);
  }
  return out;
}

/** Tokens sent home by a landing on progress `to`, as [[colour, token], ...]. */
export function victimsAt(s: LudoState, c: number, to: number, isPair: boolean): number[][] {
  if (to > 50) return [];
  const a = absIndex(c, to);
  if ((SAFE as readonly number[]).includes(a)) return [];
  if (isPair) {
    const q = oppPairAt(s, c, a);
    return q === null ? [] : [
      [q.c, q.a],
      [q.c, q.b],
    ];
  }
  for (let o = 0; o < 4; o++) {
    if (!foe(s, c, o)) continue;
    for (let j = 0; j < 4; j++) {
      const p = s.tok[o][j];
      if (p >= 0 && p <= 50 && absIndex(o, p) === a && pairOf(s, o, j) === null) return [[o, j]];
    }
  }
  return [];
}

/** A loose token of the same colour already on the main-track square token i just landed on (-1 if none). */
export function pairPartner(s: LudoState, c: number, i: number): number {
  const p = s.tok[c][i];
  if (p < 0 || p > 50 || onStartSquare(c, p) || pairOf(s, c, i) !== null) return -1;
  for (let k = 0; k < 4; k++) {
    if (k !== i && s.tok[c][k] === p && pairOf(s, c, k) === null) return k;
  }
  return -1;
}

/** Why a roll left nothing to move (colour c's pawns, roll d). */
export function stuckReason(s: LudoState, c: number, d: number): string {
  const again = d === 6 ? " Roll again." : "";
  let pairOdd = false;
  for (let i = 0; i < 4; i++) {
    const p = s.tok[c][i];
    if (p < 0 || p >= GOAL) continue;
    if (pairOf(s, c, i) !== null) {
      pairOdd = pairOdd || d % 2 === 1;
      continue;
    }
    if (p + d > GOAL) continue;
    const q = blocker(s, c, i, d);
    if (q !== null) return `Blocked by ${poss(s, q.c, false)} pair.${again}`;
  }
  if (pairOdd) return "A pair needs an even roll.";
  return d === 6 ? "No move. Roll again." : "No move this time.";
}

// ---------- turn flow ----------

/** The dice show v for the player whose turn it is (phase "roll"). */
export function applyRoll(s: LudoState, v: number): LudoEvent[] {
  if (s.phase !== "roll") return [];
  const c = s.turn;
  const ev: LudoEvent[] = [{ type: "rolled", c, v }];
  s.dice = v;
  s.sixes = v === 6 ? s.sixes + 1 : 0;
  if (s.sixes === 3) {
    s.sixes = 0;
    ev.push({ type: "three_sixes", c });
    nextTurn(s, ev);
    return ev;
  }
  if (waitingSix(s, c)) {
    if (v !== 6) {
      ev.push({ type: "need_six", c, v });
      nextTurn(s, ev);
      return ev;
    }
    s.free[c] = true;
    ev.push({ type: "free_hand", c, mate: mateOf(c) });
  }
  const mc = moverOf(s, c);
  const mv = movables(s);
  if (mv.length === 0) {
    ev.push({ type: "stuck", c, mover: mc, reason: stuckReason(s, mc, v) });
    if (v === 6) beginTurn(s, ev);
    else nextTurn(s, ev);
    return ev;
  }
  s.phase = "choose";
  ev.push({ type: "choose", c, mover: mc, movable: mv });
  return ev;
}

/** Legacy Single / Pair step: a human narrows this turn's choice to one kind of unit. */
export function choosePick(s: LudoState, kind: string): boolean {
  if (!isHuman(s, s.turn) || !(kind === "single" || kind === "pair")) return false;
  if (s.phase !== "pick" && s.phase !== "choose") return false;
  if (picked(s, kind).length === 0) return false;
  s.pick = kind;
  s.phase = "choose";
  return true;
}

/** The movable units of one kind ("single" or "pair"). */
export function picked(s: LudoState, kind: string): number[] {
  const c = moverOf(s, s.turn);
  return movables(s).filter((i) => (pairOf(s, c, i) !== null) === (kind === "pair"));
}

/** Every legal unit for this roll: {mover, tokens, token, pair, from, to}. */
export function units(s: LudoState): Unit[] {
  const c = moverOf(s, s.turn);
  const d = s.dice;
  const out: Unit[] = [];
  for (const i of legal(s)) {
    const q = pairOf(s, c, i);
    out.push({ mover: c, tokens: unitOf(s, c, i), token: i, pair: q !== null, from: s.tok[c][i], to: dest(s, c, i, d) });
  }
  return out;
}

/** The legal unit pawn i belongs to, or null (GDScript: {}) when that pawn can't move. */
export function unitForToken(s: LudoState, i: number): Unit | null {
  for (const u of units(s)) {
    if (u.tokens.includes(i)) return u;
  }
  return null;
}

/** The movable units this turn (the legacy Single / Pair choice narrows them). */
export function legal(s: LudoState): number[] {
  return s.pick !== "" ? picked(s, s.pick) : movables(s);
}

/** The token a human's move goes to without a tap, or -1 when the player has to choose. */
export function autoMoveToken(s: LudoState): number {
  if (s.phase !== "choose") return -1;
  const c = moverOf(s, s.turn);
  const mv = legal(s);
  if (mv.length === 0) return -1;
  if (mv.length === 1 || mv.every((i) => s.tok[c][i] < 0)) return mv[0];
  const firstPair = pairOf(s, c, mv[0]) !== null;
  const firstFrom = s.tok[c][mv[0]];
  if (mv.every((i) => s.tok[c][i] === firstFrom && (pairOf(s, c, i) !== null) === firstPair)) return mv[0];
  return -1;
}

/** Move token i (or its whole pair) by the dice (phase "choose"). Returns no events when the move isn't allowed. */
export function move(s: LudoState, i: number): LudoEvent[] {
  if (s.phase !== "choose") return [];
  if (!Number.isInteger(i) || i < 0 || i > 3) return [];
  const roller = s.turn;
  const c = moverOf(s, roller);
  const d = s.dice;
  if (waitingSix(s, roller)) return [];
  const pair = pairOf(s, c, i);
  const isPair = pair !== null;
  if (pair !== null) i = pair.a;
  if (s.pick !== "" && (s.pick === "pair") !== isPair) return [];
  const to = dest(s, c, i, d);
  if (to === NO_MOVE) return [];
  s.pick = "";
  const unit = unitOf(s, c, i);
  const from = s.tok[c][i];
  for (const j of unit) s.tok[c][j] = to;
  const ev: LudoEvent[] = [{ type: "move", c, roller, tokens: unit, from, to, pair: isPair }];
  if (isPair && to >= GOAL) removePair(s, c, i);

  let extra = d === 6;
  const victims = victimsAt(s, c, to, isPair);
  if (victims.length > 0) {
    extra = true;
    for (const v of victims) {
      removePair(s, v[0], v[1]);
      s.tok[v[0]][v[1]] = -1;
    }
    ev.push({ type: "capture", c, victims });
  }

  if (isPair && ((to > 50 && to < GOAL) || (to <= 50 && onStartSquare(c, to)))) {
    removePair(s, c, i);
    ev.push({ type: "split", c, tokens: unit, where: to > 50 ? "lane" : "start" });
  }

  const pend: Pending = { c, i, to, extra };
  const partner = pairPartner(s, c, i);
  if (partner >= 0) {
    if (isHuman(s, roller) && Boolean(s.pair_ask ?? false)) {
      pend.partner = partner;
      s.pending = pend;
      s.phase = "pair_ask";
      ev.push({ type: "pair_offer", c, a: i, b: partner });
      return ev;
    }
    if (!(SAFE as readonly number[]).includes(absIndex(c, to))) formPair(s, c, i, partner, ev);
  }
  finishMove(s, pend, ev);
  return ev;
}

/** Human only: the answer to "make a pair?" (phase "pair_ask"). */
export function answerPair(s: LudoState, yes: boolean): LudoEvent[] {
  if (s.phase !== "pair_ask") return [];
  const pend = s.pending as Pending;
  s.pending = {};
  const ev: LudoEvent[] = [];
  if (yes) formPair(s, pend.c, pend.i, pend.partner as number, ev);
  finishMove(s, pend, ev);
  return ev;
}

function formPair(s: LudoState, c: number, i: number, partner: number, ev: LudoEvent[]): void {
  if (pairOf(s, c, i) !== null || pairOf(s, c, partner) !== null) return;
  s.pairs.push({ c, a: Math.min(i, partner), b: Math.max(i, partner) });
  ev.push({ type: "pair_formed", c, a: Math.min(i, partner), b: Math.max(i, partner), human: isHuman(s, s.turn) });
}

function finishMove(s: LudoState, pend: Pending, ev: LudoEvent[]): void {
  const c = pend.c;
  const to = pend.to;
  let extra = pend.extra;
  if (to === GOAL) {
    extra = true;
    ev.push({ type: "home", c });
    if (allHome(s, c)) {
      markFinished(s, c); // (Teams: each colour's own order; standings() lists partners by it)
      if (!teamOn(s) || allHome(s, mateOf(c))) {
        sideFinished(s, c, ev); // a colour (Teams: both partners, the team together) has its place
        if (s.phase === "over") return;
      } else {
        ev.push({ type: "all_home", c }); // Teams: four home, the partner still playing (Free Hand next)
      }
    }
  }
  if (extra && !sideDone(s, s.turn)) beginTurn(s, ev);
  else nextTurn(s, ev); // (a side that just finished hands the turn on, extra or not)
}

function beginTurn(s: LudoState, ev: LudoEvent[]): void {
  s.phase = "roll";
  s.pick = "";
  ev.push({ type: "turn", c: s.turn, again: true });
}

function nextTurn(s: LudoState, ev: LudoEvent[]): void {
  s.sixes = 0;
  s.turn = nextActive(s, s.turn);
  s.phase = "roll";
  s.pick = "";
  ev.push({ type: "turn", c: s.turn, again: false });
}

/** Colour c's side just finished (c: the colour whose pawn came home last): its place, then is the game over? */
function sideFinished(s: LudoState, c: number, ev: LudoEvent[]): void {
  let place = 0;
  for (const side of sides(s)) if (sideDone(s, side[0])) place += 1;
  const e: Extract<LudoEvent, { type: "finished" }> = { type: "finished", c, place };
  if (teamOn(s)) e.team = [Math.min(c, mateOf(c)), Math.max(c, mateOf(c))];
  ev.push(e);
  let left = 0;
  let human = false;
  for (const side of sides(s)) {
    if (sideDone(s, side[0])) continue;
    left += 1;
    for (const k of side) human = human || isHuman(s, k);
  }
  if (left < 2 || !human) gameOver(s, place === 1 ? c : -1, ev);
}

/** The sides of the game, each a list of colours: [[c], ...] for the active colours; Teams [[0, 2], [1, 3]]. */
function sides(s: LudoState): number[][] {
  if (teamOn(s)) {
    return [
      [0, 2],
      [1, 3],
    ];
  }
  const out: number[][] = [];
  for (let c = 0; c < 4; c++) if (active(s, c)) out.push([c]);
  return out;
}

/** The end: unfinished sides ranked by progress (standings()), s.finished the full order, s.winner the first finisher. */
function gameOver(s: LudoState, w: number, ev: LudoEvent[]): void {
  if (w < 0 && !teamOn(s) && finishedOf(s).length > 0) w = (s.finished as number[])[0];
  s.winner = w;
  const order = standings(s).map((e) => e.color);
  if (w < 0) {
    w = order[0];
    s.winner = w;
  }
  s.finished = order;
  s.phase = "over";
  s.pick = "";
  s.pending = {};
  ev.push({ type: "game_over", winner: w, team: winners(s), order: [...order] });
}

/** Ends the game now (the server's {k: "end"}): unfinished sides ranked by progress. [] when already over. */
export function endGame(s: LudoState): LudoEvent[] {
  if (s.phase === "over") return [];
  const ev: LudoEvent[] = [];
  gameOver(s, -1, ev);
  return ev;
}

/** s.finished, created / normalised to ints when missing or loaded as floats (GDScript _finished). */
function finishedOf(s: LudoState): number[] {
  if (!Array.isArray(s.finished)) s.finished = [];
  else if (s.finished.some((x) => typeof x !== "number" || !Number.isInteger(x)))
    s.finished = s.finished.map((x) => Math.trunc(Number(x)));
  return s.finished;
}

function markFinished(s: LudoState, c: number): void {
  if (!finishedOf(s).includes(c)) (s.finished as number[]).push(c);
}

// ---------- results ----------

/** The winning colours: the winner, plus the partner in Pair Mode. */
export function winners(s: LudoState): number[] {
  if (s.winner < 0) return [];
  return teamOn(s) ? [s.winner, mateOf(s.winner)] : [s.winner];
}

export function winReward(s: LudoState): number {
  if (s.phase !== "over" || !s.players.includes("cpu")) return 0;
  return winners(s).some((k) => isYou(s, k)) ? WIN_REWARD : 0;
}

export function playReward(s: LudoState): number {
  if (s.phase !== "over" || !s.players.includes("cpu") || winReward(s) > 0) return 0;
  for (let k = 0; k < 4; k++) {
    if (active(s, k) && isYou(s, k)) return PLAY_REWARD;
  }
  return 0;
}

/** How far colour c has come, 0 (all at base) to 1 (all four home). */
export function progress(s: LudoState, c: number): number {
  let n = 0;
  for (const p of s.tok[c]) n += Math.max(0, Math.min(Math.trunc(p), GOAL) + 1);
  return n / (4.0 * (GOAL + 1));
}

function sortBy<T>(arr: T[], less: (a: T, b: T) => boolean): void {
  arr.sort((a, b) => (less(a, b) ? -1 : less(b, a) ? 1 : 0));
}

/** Placings for every active colour: {color, place (1-based), finished, progress (0-1)}. */
export function standings(s: LudoState): Standing[] {
  const fin = finishedOf(s);
  const cols: number[] = [];
  for (let c = 0; c < 4; c++) if (active(s, c)) cols.push(c);
  const byFinish = (a: number, b: number): boolean => {
    const fa = fin.indexOf(a);
    const fb = fin.indexOf(b);
    if (fa >= 0 !== fb >= 0) return fa >= 0;
    if (fa >= 0) return fa < fb;
    const pa = progress(s, a);
    const pb = progress(s, b);
    return pa !== pb ? pa > pb : a < b;
  };
  sortBy(cols, byFinish);
  const out: Standing[] = [];
  if (!teamOn(s)) {
    for (let n = 0; n < cols.length; n++) {
      out.push({ color: cols[n], place: n + 1, finished: allHome(s, cols[n]), progress: progress(s, cols[n]) });
    }
    return out;
  }
  const teams_ = [
    [0, 2],
    [1, 3],
  ];
  const score = (t: number[]): number => {
    if (s.winner >= 0 && t.includes(s.winner)) return 1000.0;
    return progress(s, t[0]) + progress(s, t[1]);
  };
  sortBy(teams_, (a, b) => (score(a) !== score(b) ? score(a) > score(b) : a[0] < b[0]));
  for (let n = 0; n < teams_.length; n++) {
    const members = [...teams_[n]];
    sortBy(members, byFinish);
    for (const c of members) out.push({ color: c, place: n + 1, finished: allHome(s, c), progress: progress(s, c) });
  }
  return out;
}

// ---------- computer player: score each legal move ----------
//   "easy":   a random legal move (half the time it takes a move that finishes a pawn; it never dodges danger).
//   "normal": scores every move (finish, leave base, capture, safety, running from a threat) plus a little jitter.
//   "hard":   the same move values plus a one-turn risk lookahead on a copy of the state.

export function threatAt(s: LudoState, c: number, absSq: number): boolean {
  return threatsAt(s, c, absSq) > 0;
}

/** How many opponent single pawns stand 1-6 squares behind main-track square absSq (0 on safe squares). */
export function threatsAt(s: LudoState, c: number, absSq: number): number {
  if ((SAFE as readonly number[]).includes(absSq)) return 0;
  let n = 0;
  for (let o = 0; o < 4; o++) {
    if (!foe(s, c, o)) continue;
    for (let j = 0; j < 4; j++) {
      const p = s.tok[o][j];
      if (p < 0 || p > 50 || pairOf(s, o, j) !== null) continue;
      const d = (absSq - absIndex(o, p) + 52) % 52;
      if (d >= 1 && d <= 6) n += 1;
    }
  }
  return n;
}

/** The computer's move: one of mv (from movables()), by level "easy" / "normal" / "hard" (anything else: normal). */
export function pickAi(s: LudoState, mv: number[], rng: Rng | null = null, level: string = "normal"): number {
  if (mv.length === 0) return -1;
  const r = rng ?? mathRandom;
  if (level === "easy") return pickEasy(s, mv, r);
  const hard = level === "hard";
  const c = moverOf(s, s.turn);
  let best = mv[0];
  let bestScore = -Infinity;
  for (const i of mv) {
    const sc = (hard && mv.length > 1 ? scoreHard(s, c, i) : score(s, c, i, s.dice)) + r.randf() * 4;
    if (sc > bestScore) {
      bestScore = sc;
      best = i;
    }
  }
  return best;
}

function pickEasy(s: LudoState, mv: number[], rng: Rng): number {
  const c = moverOf(s, s.turn);
  const d = s.dice;
  const fin = mv.filter((i) => dest(s, c, i, d) === GOAL);
  if (fin.length > 0 && rng.randf() < 0.5) return fin[0];
  return mv[Math.min(Math.trunc(rng.randf() * mv.length), mv.length - 1)];
}

/** Normal: the web version's move scores. */
export function score(s: LudoState, c: number, i: number, d: number): number {
  const p = s.tok[c][i];
  const to = dest(s, c, i, d);
  const pair = pairOf(s, c, i) !== null;
  let sc = to * 0.4;
  if (to === GOAL) sc += pair ? 160 : 100;
  if (p < 0) sc += 60;
  if (p <= 50 && to > 50) sc += 45;
  if (to <= 50) {
    const a = absIndex(c, to);
    const hits = victimsAt(s, c, to, pair).length;
    if (hits) sc += hits === 2 ? 120 : 80;
    else if ((SAFE as readonly number[]).includes(a)) sc += 18;
    if (!pair && threatAt(s, c, a)) sc -= 30;
  }
  if (!pair && p >= 0 && p <= 50 && threatAt(s, c, absIndex(c, p))) sc += 25;
  return sc;
}

/** Hard: the move values without the one-square threat checks, plus the change in expected loss over the move. */
export function scoreHard(s: LudoState, c: number, i: number): number {
  const d = s.dice;
  const p = s.tok[c][i];
  const to = dest(s, c, i, d);
  const pair = pairOf(s, c, i) !== null;
  let sc = to * 0.4;
  if (to === GOAL) sc += pair ? 160 : 100;
  if (p < 0) sc += 60;
  if (p <= 50 && to > 50) sc += 45;
  if (to <= 50) {
    const victims = victimsAt(s, c, to, pair);
    if (victims.length) sc += (victims.length === 2 ? 120 : 80) + Math.trunc(s.tok[victims[0][0]][victims[0][1]]) * 0.5;
    else if ((SAFE as readonly number[]).includes(absIndex(c, to))) sc += 10;
  }
  const after = cloneState(s);
  move(after, i);
  return sc + (risk(s, c) - risk(after, c)) * RISK_W;
}

/** Chance that a pawn k squares ahead of an enemy single is hit with its next roll. */
export function hitP(k: number): number {
  if (k >= 1 && k <= 6) return 1.0 / 6.0;
  if (k >= 7 && k <= 12) return 1.0 / 36.0;
  return 0.0;
}

/** Expected loss for colour c next turn. */
export function risk(s: LudoState, c: number): number {
  let total = 0.0;
  for (let i = 0; i < 4; i++) {
    const p = s.tok[c][i];
    if (p < 0 || p > 50) continue;
    const a = absIndex(c, p);
    if ((SAFE as readonly number[]).includes(a)) continue;
    const q = pairOf(s, c, i);
    if (q !== null && q.a !== i) continue; // count a pair once
    let safeP = 1.0;
    for (let o = 0; o < 4; o++) {
      if (!foe(s, c, o)) continue;
      for (let j = 0; j < 4; j++) {
        const op = s.tok[o][j];
        if (op < 0 || op > 50) continue;
        const oq = pairOf(s, o, j);
        if ((q === null) !== (oq === null) || (oq !== null && oq.a !== j)) continue;
        const k = (a - absIndex(o, op) + 52) % 52;
        if (op + k > 50) continue; // that pawn turns into its home column first
        const hp = oq === null ? hitP(k) : k >= 1 && k <= 3 ? 1.0 / 6.0 : 0.0;
        safeP *= 1.0 - hp;
      }
    }
    total += (1.0 - safeP) * (p + 12) * (q === null ? 1 : 2);
  }
  return total;
}

// ---------- extras for the server (not in the GDScript class) ----------

/** A deep copy of a state (GDScript s.duplicate(true)). */
export function cloneState(s: LudoState): LudoState {
  return JSON.parse(JSON.stringify(s)) as LudoState;
}

/** The protocol action objects (PROTOCOL.md "Actions"). */
export type Action =
  | { k: "roll"; c: number; v: number }
  | { k: "move"; c: number; i: number }
  | { k: "pair"; c: number; yes: boolean }
  | { k: "mode"; c: number; mode: "cpu" | "human" }
  | { k: "end" };

/**
 * Applies one protocol action the way a client does. Returns the rules' events ([] for "mode", and [] when the rules
 * refuse the action: a refused roll / move / pair / end leaves the state unchanged). The colour `c` is not checked
 * here (the server checks it is s.turn before calling). "end" (no colour): endGame, the server ending a match early.
 */
export function applyAction(s: LudoState, a: Action): LudoEvent[] {
  switch (a.k) {
    case "roll":
      return applyRoll(s, a.v);
    case "move":
      return move(s, a.i);
    case "pair":
      return answerPair(s, a.yes);
    case "mode":
      s.players[a.c] = a.mode;
      return [];
    case "end":
      return endGame(s);
  }
}
