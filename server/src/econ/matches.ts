// Match rewards. Offline matches (vs Computer, Pass & Play) are reported as claims and pay what the game pays today
// (LudoMatch._game_over / SLMatch._win: LudoRules.win_reward / play_reward, SnakesLaddersRules.claim_*_reward,
// Save.record_ludo / record_sl, Save.add_coins), within the claim limits of rules.ts (S&L wins verified by replaying
// their rolls, as SLMatch does before paying). Online matches pay ONLINE_REWARDS, granted by the Room at `over`.
import { MATCH } from "./catalog";
import { CLAIM_LIMITS, ONLINE_REWARDS } from "./rules";
import { type Dict, clone, getInt, isDict } from "./gd";
import { type Delta, type Profile, type Stats, addCoins } from "./profile";
import { dayKey } from "./rewards";
import { replayReaches100 } from "../rules/sl";

export type Seat = "human" | "cpu" | "off";
export type Game = "ludo" | "sl";

export interface MatchResult {
  profile: Profile;
  delta: Delta;
  coins: number;
  xp: number;
}

function stats(p: Profile): Stats {
  const st: Dict = isDict(p.stats) ? p.stats : {};
  p.stats = st as Stats;
  return st as Stats;
}

function bump(st: Stats, k: string, n = 1): void {
  st[k] = getInt(st, k, 0) + n;
}

/**
 * The coins a finished offline Ludo game pays: LudoRules.win_reward (beating the computer as its only human
 * opponent; with teams, your side winning) or play_reward (losing such a game). Pass & Play pays no coins.
 * `won`: a human seat's side won (LudoMatch's human_won).
 */
export function ludoCoins(players: readonly string[], won: boolean): number {
  const humans = players.filter((x) => x === "human").length;
  if (!players.includes("cpu") || humans !== 1) return 0;
  return won ? MATCH.ludo.win : MATCH.ludo.play;
}

/** A finished offline Ludo game: Save.record_ludo(players, won) then Save.add_coins(ludoCoins). */
export function applyLudoResult(profile: Profile, players: readonly string[], won: boolean, pairs = 0): MatchResult {
  const p = clone(profile);
  const st = stats(p);
  const humans = players.filter((x) => x === "human").length;
  let xp = 0;
  if (humans === 1 && players.includes("cpu")) {
    bump(st, "played");
    if (won) {
      bump(st, "wins");
      bump(st, "streak");
      st.bestStreak = Math.max(getInt(st, "bestStreak", 0), getInt(st, "streak", 0));
      xp = MATCH.ludo.xp_win;
    } else {
      bump(st, "losses");
      st.streak = 0;
      xp = MATCH.ludo.xp_loss;
    }
  } else if (humans > 1) {
    bump(st, "ppGames");
    xp = MATCH.ludo.xp_pp;
  }
  if (pairs > 0) bump(st, "pairsFormed", pairs);    // the game counts these as they happen (LudoMatch "pair_formed")
  p.xp = getInt(p, "xp", 0) + xp;
  const coins = ludoCoins(players, won);
  if (coins > 0) addCoins(p, coins);
  return { profile: p, delta: { coins, xp }, coins, xp };
}

/**
 * A finished offline Snakes & Ladders game (SLMatch._win): vs Computer pays REWARD for your win, PLAY_REWARD for a
 * loss; Pass & Play ("local") pays nothing. Save.record_sl: slPlayed, and slWins for a paid win. No XP (the game
 * gives none for S&L).
 */
export function applySlResult(profile: Profile, mode: string, won: boolean): MatchResult {
  const p = clone(profile);
  const st = stats(p);
  const vsCpu = mode === "cpu";
  const coins = vsCpu ? (won ? MATCH.sl.win : MATCH.sl.play) : 0;
  bump(st, "slPlayed");
  if (vsCpu && won) bump(st, "slWins");
  const xp = vsCpu ? (won ? MATCH.sl.xp_win : MATCH.sl.xp_loss) : MATCH.sl.xp_pp;
  if (xp) p.xp = getInt(p, "xp", 0) + xp;
  if (coins > 0) addCoins(p, coins);
  return { profile: p, delta: { coins, xp }, coins, xp };
}


// ---------- claims (POST /v1/claims) ----------

/** The claim body. `xp` (the client's own figure) is informational: the server computes the grant. */
export interface ClaimInput {
  game: Game;
  /** Ludo: "cpu" | "pp" (only used with a numeric `players`); S&L: "cpu" | "local" ("pp" accepted). */
  mode?: string;
  /** "win": your side won (vs Computer); anything else is a loss. Ignored for Pass & Play, and when `placing` is sent. */
  result: string;
  /** Ludo: the four seats ("human" | "cpu" | "off"), or a player count with `mode`. S&L: optional count. */
  players?: unknown;
  /**
   * Your (your team's) final place, 1-based (play on: the game goes on after the first finish). When sent it decides:
   * 1 = the win reward, any other place the play / finish reward. Missing (older clients): `result` decides.
   */
  placing?: unknown;
  duration_s: number;
  moves?: number;
  /** Ludo: pairs you formed (stats.pairsFormed), at most CLAIM_LIMITS.pairs_per_claim. */
  pairs?: number;
  /**
   * S&L vs Computer: your dice values in order (SLMatch records them). A win is paid only when they replay from
   * square 0 to exactly 100 (SnakesLaddersRules.replay_reaches_100); at most CLAIM_LIMITS.max_rolls.
   */
  rolls?: unknown;
  /** S&L: the "need a 1 to start" rule was on (replayed with it). */
  need_one?: unknown;
  xp?: number;
}

/** An earlier claim of the same account (the endpoint keeps them). `at` in unix seconds; xp optional (0). */
export interface ClaimRecord {
  at: number;
  coins: number;
  xp?: number;
  granted: boolean;
}

/** What the account's earlier claims add up to at `now` (the endpoint reads these with one query). */
export interface ClaimTotals {
  /** Coins / XP paid by claims since the start of today (DAY_OFFSET_MIN day). */
  coins_today: number;
  xp_today: number;
  /** Granted claims in the last 3600 s. */
  last_hour: number;
}

/**
 * too_short, replay (an S&L win whose rolls don't reach 100) and hourly grant nothing; daily_coins / daily_xp mean
 * the day's cap was reached: the remainder is paid (granted), or nothing once both remainders are 0.
 */
export type LimitReason = "too_short" | "replay" | "hourly" | "daily_coins" | "daily_xp";

export type ClaimResult =
  | (MatchResult & { ok: true; limited: false; granted: true })
  | (MatchResult & { ok: true; limited: true; granted: boolean; reason: LimitReason; would: { coins: number; xp: number } })
  | { ok: false; error: "invalid"; detail: string };

const SEATS = new Set(["human", "cpu", "off"]);

/** The seats of a Ludo claim, or a reason it is malformed. */
export function claimSeats(c: ClaimInput): string[] | string {
  if (Array.isArray(c.players)) {
    if (c.players.length !== 4 || !c.players.every((x) => typeof x === "string" && SEATS.has(x))) return "players";
    const seats = c.players as string[];
    if (seats.filter((x) => x !== "off").length < 2 || !seats.includes("human")) return "players";
    return seats;
  }
  if (typeof c.players === "number" && Number.isInteger(c.players) && c.players >= 2 && c.players <= 4) {
    const n = c.players;
    if (c.mode === "cpu") return ["human", ...Array(n - 1).fill("cpu"), ...Array(4 - n).fill("off")];
    if (c.mode === "pp") return [...Array(n).fill("human"), ...Array(4 - n).fill("off")];
    return "mode";
  }
  return "players";
}

/** ClaimTotals from a list of earlier claims (unix seconds). */
export function claimTotals(history: readonly ClaimRecord[], now: number): ClaimTotals {
  const today = dayKey(now);
  let coins = 0;
  let xp = 0;
  let hour = 0;
  for (const h of history) {
    if (h.granted && h.at > now - 3600 && h.at <= now) hour++;
    if (dayKey(h.at) === today) {
      coins += h.coins;
      xp += h.xp ?? 0;
    }
  }
  return { coins_today: coins, xp_today: xp, last_hour: hour };
}

/**
 * Whether the claim is for a win: `placing` 1 when the client sends a placing (any other place is a loss), else
 * `result` "win". A placing that is not a whole number 1-4 is malformed (claimMatch refuses it).
 */
export function claimWon(c: ClaimInput): boolean {
  if (c.placing !== undefined && c.placing !== null) return c.placing === 1;
  return c.result === "win";
}

function placingOk(c: ClaimInput): boolean {
  const p = c.placing;
  return p === undefined || p === null || (typeof p === "number" && Number.isInteger(p) && p >= 1 && p <= 4);
}

/** An S&L win vs Computer whose rolls replay to square 100 (other claims need no rolls). */
export function rollsVerified(c: ClaimInput): boolean {
  if (c.game !== "sl" || !claimWon(c) || c.mode !== "cpu") return true;
  if (!Array.isArray(c.rolls) || c.rolls.length > CLAIM_LIMITS.max_rolls) return false;
  return replayReaches100(c.rolls, c.need_one === true);
}

/** What a claim worth `worth` is paid now: the reason it is cut (null: in full) and the coins / XP granted. */
export interface ClaimCut {
  reason: LimitReason | null;
  granted: boolean;
  coins: number;
  xp: number;
}

/**
 * The limits, in order: too short, unverified S&L win, 20 granted claims in the last hour (each grants nothing), then
 * the day's 6,000 coins / 3,000 XP, which pay the remainder (`history`: the account's earlier claims, or their totals).
 */
export function claimLimit(
  c: ClaimInput,
  worth: { coins: number; xp: number },
  history: readonly ClaimRecord[] | ClaimTotals,
  now: number,
): ClaimCut {
  const none = (reason: LimitReason): ClaimCut => ({ reason, granted: false, coins: 0, xp: 0 });
  const min = CLAIM_LIMITS.min_duration_s[c.game] ?? 0;
  if (!(c.duration_s >= min)) return none("too_short");
  if (!rollsVerified(c)) return none("replay");
  const t = Array.isArray(history) ? claimTotals(history, now) : (history as ClaimTotals);
  if (t.last_hour >= CLAIM_LIMITS.per_hour) return none("hourly");
  const coins = Math.min(worth.coins, Math.max(0, CLAIM_LIMITS.coins_per_day - t.coins_today));
  const xp = Math.min(worth.xp, Math.max(0, CLAIM_LIMITS.xp_per_day - t.xp_today));
  if (coins === worth.coins && xp === worth.xp) return { reason: null, granted: true, coins, xp };
  const reason: LimitReason = coins < worth.coins ? "daily_coins" : "daily_xp";
  if (coins === 0 && xp === 0) return none(reason);
  return { reason, granted: true, coins, xp };
}

/**
 * An offline match claim: validates it, computes the game's grant and applies the limits (claimLimit). A claim that
 * grants nothing leaves the profile as it is (no coins, XP or stats) and is still recorded by the endpoint; a claim
 * cut to the daily caps applies in full except the coins / XP over the cap (its stats count).
 */
export function claimMatch(profile: Profile, c: ClaimInput, history: readonly ClaimRecord[] | ClaimTotals, now: number): ClaimResult {
  if (!isDict(c)) return { ok: false, error: "invalid", detail: "body" };
  if (c.game !== "ludo" && c.game !== "sl") return { ok: false, error: "invalid", detail: "game" };
  if (typeof c.duration_s !== "number" || !Number.isFinite(c.duration_s) || c.duration_s < 0) {
    return { ok: false, error: "invalid", detail: "duration_s" };
  }
  if (!placingOk(c)) return { ok: false, error: "invalid", detail: "placing" };
  const won = claimWon(c);
  let res: MatchResult;
  if (c.game === "ludo") {
    const seats = claimSeats(c);
    if (typeof seats === "string") return { ok: false, error: "invalid", detail: seats };
    const pairs = c.pairs === undefined ? 0 : c.pairs;
    if (typeof pairs !== "number" || !Number.isInteger(pairs) || pairs < 0) return { ok: false, error: "invalid", detail: "pairs" };
    res = applyLudoResult(profile, seats, won, Math.min(pairs, CLAIM_LIMITS.pairs_per_claim));
  } else {
    const mode = c.mode === "pp" ? "local" : c.mode;
    if (mode !== "cpu" && mode !== "local") return { ok: false, error: "invalid", detail: "mode" };
    if (c.players !== undefined && !(typeof c.players === "number" && Number.isInteger(c.players) && c.players >= 2 && c.players <= 4)) {
      return { ok: false, error: "invalid", detail: "players" };
    }
    res = applySlResult(profile, mode, won);
  }
  const would = { coins: res.coins, xp: res.xp };
  const cut = claimLimit(c, would, history, now);
  if (cut.reason === null) return { ...res, ok: true, limited: false, granted: true };
  if (!cut.granted) {
    return { ok: true, limited: true, granted: false, reason: cut.reason, profile, delta: { coins: 0, xp: 0 }, coins: 0, xp: 0, would };
  }
  const p = res.profile;
  const overCoins = res.coins - cut.coins;
  if (overCoins > 0) {
    p.coins = getInt(p, "coins", 0) - overCoins;
    const st = stats(p);
    st.coinsEarned = getInt(st, "coinsEarned", 0) - overCoins;
  }
  p.xp = getInt(p, "xp", 0) - (res.xp - cut.xp);
  return { ok: true, limited: true, granted: true, reason: cut.reason, profile: p, delta: { coins: cut.coins, xp: cut.xp }, coins: cut.coins, xp: cut.xp, would };
}


// ---------- online matches ----------

/** win: your side won; finish: played to the end without winning; left: left before the end. */
export type OnlineOutcome = "win" | "finish" | "left";

export function onlineReward(game: Game, outcome: OnlineOutcome): { coins: number; xp: number } {
  const r = ONLINE_REWARDS[game][outcome];
  return { coins: r.coins, xp: r.xp };
}

/** The Room's grant at `over` (once per account per match: the caller's job). Coins and XP; no stats. */
export function applyOnlineResult(profile: Profile, game: Game, outcome: OnlineOutcome): MatchResult {
  const { coins, xp } = onlineReward(game, outcome);
  const p = clone(profile);
  p.xp = getInt(p, "xp", 0) + xp;
  if (coins > 0) addCoins(p, coins);
  return { profile: p, delta: { coins, xp }, coins, xp };
}
