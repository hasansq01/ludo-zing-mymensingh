// Snakes & Ladders rules: a line-for-line port of godot/scripts/core/snakes_ladders_rules.gd (class
// SnakesLaddersRules).
//
// The state shape (snake_case keys) and the event objects ("type" strings and field names) are exactly the
// GDScript ones, because clients replay the server's actions with the GDScript rules and compare state hashes
// (sl_hash.ts). Parity is tested by replaying traces recorded from the GDScript rules (test/rules_sl_parity.test.ts,
// recorded by godot/dev/net_parity_dump_sl.gd).
//
// GDScript -> TS notes:
// - land() returns the same dictionary shapes: the flag keys (wait / over / ladder / snake) are present (true) or
//   absent, never false; `via` only on a ladder / snake.
// - replay_reaches_100 accepts ints and whole-number floats (JSON); in JS both are numbers, so the check is
//   "a finite whole number in 1-6" (a boolean or string fails, as in GDScript).
// - g.players[g.winner] with winner -1 would read the last player in GDScript (negative index); Array.at() keeps
//   that (it never happens in play: phase "over" always has a winner).
// - sort_custom with a total order (winner first, then square, then index) is Array.sort.
//
// State: { mode ("cpu" | "local"), turn, phase ("roll" | "over"), sixes, winner, paid,
//   players [{c, name, you, cpu, pos, rolls, ladders, snakes}], need_one, finished }
// Play on (see the GDScript header): a player reaching 100 gets their place (s.finished: player indices in finish
// order, event "finished") and sits out; the game is over ("win" {turn: winner, order}) when fewer than two players
// are left or none of them is a person (cpu false); the rest are ranked by square. endGame() is the {k: "end"}.
// pos 0 is off the board; squares run 1-100. Entering the board: by default any roll v from square 0 moves to
// square v (ladders and snakes apply). The house rule need_one ("Need a 1 to start") brings back the web version's
// rule: off the board only a 1 enters, on square 1.

export const LADDERS: Readonly<Record<number, number>> = { 4: 14, 9: 31, 21: 42, 28: 84, 36: 44, 51: 67, 71: 91 };
export const SNAKES: Readonly<Record<number, number>> = {
  16: 6, 47: 26, 49: 11, 56: 53, 62: 19, 64: 60, 87: 24, 93: 73, 95: 75, 98: 78,
};
export const REWARD = 100; // coins for beating the computer
export const PLAY_REWARD = 10; // coins for finishing a game you lost against the computer (participation)
export const COLOR_NAMES = ["Red", "Green", "Yellow", "Blue"] as const;
export const CPU_NAMES = ["Mocha", "Biscotti", "Espresso"] as const;

export type SlMode = "cpu" | "local";

export interface SlPlayer {
  c: number;
  name: string;
  you: boolean;
  cpu: boolean;
  pos: number;
  rolls: number[];
  ladders: number;
  snakes: number;
}

export interface SlState {
  mode: string;
  turn: number;
  phase: string;
  sixes: number;
  winner: number;
  paid: boolean;
  players: SlPlayer[];
  need_one?: boolean;
  /** Player indices in finish order (missing in states saved before play on). */
  finished?: number[];
}

/** What land() says about one roll (the GDScript dictionary: flag keys present only when true). */
export interface Landing {
  to: number;
  steps: number;
  via?: number;
  wait?: true;
  over?: true;
  ladder?: true;
  snake?: true;
}

export type SlEvent =
  | { type: "rolled"; turn: number; v: number }
  | { type: "three_sixes"; turn: number }
  | { type: "wait" | "over"; turn: number; v: number; need: number }
  | { type: "move"; turn: number; from: number; to: number; steps: number; via: number; ladder: boolean; snake: boolean }
  | { type: "finished"; turn: number; c: number; place: number }
  | { type: "win"; turn: number; order: number[] }
  | { type: "turn"; turn: number; again: boolean };

export interface SlStanding {
  idx: number;
  color: number;
  name: string;
  place: number;
  finished: boolean;
  pos: number;
  progress: number;
}

export interface SlNewGameOpts {
  need_one?: boolean;
}

const has = (o: object, k: string): boolean => Object.prototype.hasOwnProperty.call(o, k);

/** The rule in one place: where a roll of v from square `from` ends, and what happened on the way. */
export function land(from: number, v: number, needOne = false): Landing {
  if (from === 0 && needOne && v !== 1) return { to: 0, steps: 0, wait: true }; // off the board: only a 1 enters
  const to = from + v;
  if (to > 100) return { to: from, steps: 0, over: true };
  if (has(LADDERS, String(to))) return { to: LADDERS[to], steps: v, via: to, ladder: true };
  if (has(SNAKES, String(to))) return { to: SNAKES[to], steps: v, via: to, snake: true };
  return { to, steps: v };
}

/**
 * Reward check: replays the human's rolls through the rules from square 0, the way applyRoll played them (the third
 * 6 in a row is recorded but ends the turn without moving). Anything that is not a whole number in 1-6 fails.
 */
export function replayReaches100(rolls: readonly unknown[], needOne = false): boolean {
  let pos = 0;
  let sixes = 0;
  for (const v of rolls) {
    if (typeof v !== "number" || Number.isNaN(v) || v !== Math.floor(v)) return false;
    if (v < 1 || v > 6) return false;
    sixes = Math.trunc(v) === 6 ? sixes + 1 : 0;
    if (sixes === 3) {
      // three 6s: the turn is over, the pawn stays
      sixes = 0;
      continue;
    }
    pos = land(pos, Math.trunc(v), needOne).to;
    if (pos === 100) return true;
  }
  return false;
}

/** vs Computer: you play `color`, the computers take the next colours round. Pass & Play: Red, Green, ... */
export function newGame(mode: string, n: number, color = 0, opts: SlNewGameOpts = {}): SlState {
  const players: SlPlayer[] = [];
  for (let k = 0; k < n; k++) {
    const c = mode === "cpu" ? (color + k) % 4 : k;
    players.push({
      c,
      name: mode === "cpu" ? (k === 0 ? "You" : CPU_NAMES[k - 1]) : COLOR_NAMES[c],
      you: mode === "cpu" && k === 0,
      cpu: mode === "cpu" && k > 0,
      pos: 0,
      rolls: [],
      ladders: 0,
      snakes: 0,
    });
  }
  return {
    mode,
    turn: 0,
    phase: "roll",
    sixes: 0,
    winner: -1,
    paid: false,
    players,
    need_one: Boolean(opts.need_one ?? false),
    finished: [],
  };
}

/** The house rule in force for game g (a state saved before the option existed has no field: any roll enters). */
export function needsOne(g: { need_one?: unknown }): boolean {
  return Boolean(g.need_one ?? false);
}

export function current(g: SlState): SlPlayer {
  return g.players[g.turn];
}

/** The dice show v for the player whose turn it is (phase "roll"). [] (and no change) in any other phase. */
export function applyRoll(g: SlState, v: number): SlEvent[] {
  if (g.phase !== "roll") return [];
  const p = current(g);
  const ev: SlEvent[] = [{ type: "rolled", turn: g.turn, v }];
  p.rolls.push(v);
  g.sixes = v === 6 ? g.sixes + 1 : 0;
  if (g.sixes === 3) {
    g.sixes = 0;
    ev.push({ type: "three_sixes", turn: g.turn });
    next(g, ev);
    return ev;
  }
  const r = land(p.pos, v, needsOne(g));
  if (r.wait || r.over) {
    ev.push({ type: r.wait ? "wait" : "over", turn: g.turn, v, need: 100 - p.pos });
    if (v === 6) again(g, ev);
    else next(g, ev);
    return ev;
  }
  const from = p.pos;
  p.pos = r.to;
  ev.push({
    type: "move", turn: g.turn, from, to: r.to, steps: r.steps, via: r.via ?? 0,
    ladder: Boolean(r.ladder), snake: Boolean(r.snake),
  });
  if (r.ladder) p.ladders += 1;
  else if (r.snake) p.snakes += 1;
  if (p.pos === 100) {
    finishedOf(g).push(g.turn);
    ev.push({ type: "finished", turn: g.turn, c: p.c, place: (g.finished as number[]).length });
    let left = 0;
    let person = false;
    for (let k = 0; k < g.players.length; k++) {
      if (!(g.finished as number[]).includes(k)) {
        left += 1;
        person = person || !g.players[k].cpu;
      }
    }
    if (left < 2 || !person) end(g, ev);
    else next(g, ev); // (a 6 onto 100 too: a finished player sits out)
    return ev;
  }
  if (v === 6) again(g, ev);
  else next(g, ev);
  return ev;
}

/**
 * Coins for the finished game, paid once: only you, only against the computer, and only when your recorded rolls
 * really reach 100 under the rules.
 */
export function claimWinReward(g: SlState): number {
  if (g.phase !== "over" || g.paid || g.mode !== "cpu") return 0;
  const p = g.players.at(g.winner) as SlPlayer;
  if (!p.you || !replayReaches100(p.rolls, needsOne(g))) return 0;
  g.paid = true;
  return REWARD;
}

/**
 * Coins for a finished game vs the computer that you lost (participation), paid once (the same `paid` flag as the
 * win reward): 0 for your win, Pass & Play or a game not over.
 */
export function claimPlayReward(g: SlState): number {
  if (g.phase !== "over" || g.paid || g.mode !== "cpu" || Math.trunc(g.winner) < 0) return 0;
  if (g.players[g.winner].you || !g.players.some((p) => Boolean(p.you))) return 0;
  g.paid = true;
  return PLAY_REWARD;
}

/**
 * Placings: the players who reached 100 in finish order, then everyone else by square (ties keep turn order). One
 * entry per player: {idx (index into g.players), color, name, place (1-based), finished (reached 100), pos, progress}.
 */
export function standings(g: SlState): SlStanding[] {
  const order: number[] = [];
  for (let k = 0; k < g.players.length; k++) order.push(k);
  const fin = finishedOf(g);
  const less = (a: number, b: number): boolean => {
    const fa = fin.indexOf(a);
    const fb = fin.indexOf(b);
    if (fa >= 0 !== fb >= 0) return fa >= 0;
    if (fa >= 0) return fa < fb;
    const pa = g.players[a].pos;
    const pb = g.players[b].pos;
    return pa !== pb ? pa > pb : a < b;
  };
  order.sort((a, b) => (less(a, b) ? -1 : less(b, a) ? 1 : 0));
  const out: SlStanding[] = [];
  for (let n = 0; n < order.length; n++) {
    const p = g.players[order[n]];
    out.push({
      idx: order[n], color: p.c, name: p.name, place: n + 1, finished: p.pos >= 100, pos: p.pos,
      progress: Math.min(Math.max(p.pos / 100.0, 0.0), 1.0),
    });
  }
  return out;
}

/** A 6: the same player rolls again (the 6s count carries on). */
function again(g: SlState, ev: SlEvent[]): void {
  g.phase = "roll";
  ev.push({ type: "turn", turn: g.turn, again: true });
}

function next(g: SlState, ev: SlEvent[]): void {
  g.sixes = 0;
  const n = g.players.length;
  const fin = finishedOf(g);
  for (let k = 1; k < n + 1; k++) {
    // the next player still playing (finished players sit out)
    const t = (g.turn + k) % n;
    if (!fin.includes(t)) {
      g.turn = t;
      break;
    }
  }
  g.phase = "roll";
  ev.push({ type: "turn", turn: g.turn, again: false });
}

/** g.finished, made (a state saved before play on: the winner, if any) / normalised to ints (GDScript _finished). */
export function finishedOf(g: SlState): number[] {
  if (!Array.isArray(g.finished)) g.finished = Math.trunc(g.winner ?? -1) >= 0 ? [Math.trunc(g.winner)] : [];
  else if (g.finished.some((x) => typeof x !== "number" || !Number.isInteger(x)))
    g.finished = g.finished.map((x) => Math.trunc(Number(x)));
  return g.finished;
}

/** The end: the rest ranked by square after the finished players, s.finished the full order, winner the first. */
function end(g: SlState, ev: SlEvent[]): void {
  const order = standings(g).map((e) => e.idx);
  g.finished = order;
  g.winner = order[0];
  g.phase = "over";
  ev.push({ type: "win", turn: g.winner, order: [...order] });
}

/** Ends the game now (the server's {k: "end"}): the players still on the board ranked by square. [] when over. */
export function endGame(g: SlState): SlEvent[] {
  if (g.phase === "over") return [];
  const ev: SlEvent[] = [];
  end(g, ev);
  return ev;
}

// ---------- extras for the server (not in the GDScript class) ----------

/** A deep copy of a state (GDScript g.duplicate(true)). */
export function cloneSlState(g: SlState): SlState {
  return JSON.parse(JSON.stringify(g)) as SlState;
}

/** The colour whose turn it is (the `c` of a roll action). */
export function turnColor(g: SlState): number {
  return current(g).c;
}

/** The index into g.players of colour c, or -1. */
export function playerIndex(g: SlState, c: number): number {
  return g.players.findIndex((p) => p.c === c);
}

/**
 * The S&L protocol actions (PROTOCOL.md "S&L actions"): `roll` (the dice show v for the player whose turn it is)
 * and `mode` (a bot takes over colour c / the player is back: sets that player's `cpu` flag).
 */
export type SlAction =
  | { k: "roll"; c: number; v: number }
  | { k: "mode"; c: number; mode: "cpu" | "human" }
  | { k: "end" };

/**
 * Applies one protocol action the way a client does. Returns the rules' events ([] for "mode", and [] for a roll
 * the rules refuse: phase "over"). The roll's colour `c` is not checked here (the server checks it is turnColor(s)
 * before calling). A "mode" for a colour with no player changes nothing.
 *
 * GDScript twin of "mode" (clients): `for p in s.players: if int(p.c) == c: p.cpu = mode == "cpu"`.
 */
export function applySlAction(s: SlState, a: SlAction): SlEvent[] {
  switch (a.k) {
    case "roll":
      return applyRoll(s, a.v);
    case "mode":
      for (const p of s.players) if (p.c === a.c) p.cpu = a.mode === "cpu";
      return [];
    case "end":
      return endGame(s);
  }
}

/**
 * S&L has no choices: a bot (or a timeout) only ever rolls. The server rolls the dice itself, so the bot's action
 * for the current turn is always {k: "roll", c: turnColor(s), v}; null when the game is over.
 */
export function botAction(s: SlState, v: number): SlAction | null {
  if (s.phase !== "roll") return null;
  return { k: "roll", c: turnColor(s), v };
}
