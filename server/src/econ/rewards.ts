// The reward rules (Rewards in godot/scripts/core/rewards.gd): the Daily Reward calendar, the Daily Spin and Free
// Coins, as pure functions over a profile. The server passes its own clock (`now`, unix seconds) and day key
// (`today`, from dayKey(now)); the game uses the device's clock and local day. The spin takes its segment as an
// argument (rollSpin() draws one with the server RNG), so tests can replay the game's rolls.
import { CATALOG, REWARDS, item } from "./catalog";
import { DAY_OFFSET_MIN } from "./rules";
import { type Dict, clamp, clone, getInt, isArray, isDict, isGdInt, stringToInt } from "./gd";
import { type Delta, type Profile, addCoins } from "./profile";


// ---------- days ----------

function isLeap(y: number): boolean {
  return y % 4 === 0 && (y % 100 !== 0 || y % 400 === 0);
}

const MONTH_DAYS = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];

/** Days since 1970-01-01 of a proleptic Gregorian date (H. Hinnant's days_from_civil). */
function daysFromCivil(y: number, m: number, d: number): number {
  y -= m <= 2 ? 1 : 0;
  const era = Math.floor(y / 400);
  const yoe = y - era * 400;
  const doy = Math.floor((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + d - 1;
  const doe = yoe * 365 + Math.floor(yoe / 4) - Math.floor(yoe / 100) + doy;
  return era * 146097 + doe - 719468;
}

function civilFromDays(z: number): [number, number, number] {
  z += 719468;
  const era = Math.floor(z / 146097);
  const doe = z - era * 146097;
  const yoe = Math.floor((doe - Math.floor(doe / 1460) + Math.floor(doe / 36524) - Math.floor(doe / 146096)) / 365);
  const doy = doe - (365 * yoe + Math.floor(yoe / 4) - Math.floor(yoe / 100));
  const mp = Math.floor((5 * doy + 2) / 153);
  const d = doy - Math.floor((153 * mp + 2) / 5) + 1;
  const m = mp + (mp < 10 ? 3 : -9);
  return [yoe + era * 400 + (m <= 2 ? 1 : 0), m, d];
}

function pad(n: number, w: number): string {
  const s = String(Math.abs(n)).padStart(w, "0");
  return n < 0 ? `-${s}` : s;
}

function keyOfDays(days: number): string {
  const [y, m, d] = civilFromDays(days);
  return `${pad(y, 4)}-${pad(m, 2)}-${pad(d, 2)}`;
}

const INT_RE = /^[+-]?\d+$/;

/** Rewards.is_day_key: "YYYY-MM-DD"-shaped (the parts only need to be integers). */
export function isDayKey(v: unknown): v is string {
  if (typeof v !== "string" || v.length !== 10) return false;
  return v[4] === "-" && v[7] === "-" && INT_RE.test(v.slice(0, 4)) && INT_RE.test(v.slice(5, 7)) && INT_RE.test(v.slice(8, 10));
}

/**
 * Rewards.day_num: days since 1970 for a day key, -1 for a damaged key. An impossible date (month 13, Feb 30)
 * gives 0, as Godot's Time.get_unix_time_from_datetime_dict does (after an error).
 */
export function dayNum(key: string): number {
  if (!isDayKey(key)) return -1;
  const y = stringToInt(key.slice(0, 4));
  const m = stringToInt(key.slice(5, 7));
  const d = stringToInt(key.slice(8, 10));
  if (m < 1 || m > 12 || d < 1) return 0;
  const dim = m === 2 && isLeap(y) ? 29 : MONTH_DAYS[m - 1];
  if (d > dim) return 0;
  return daysFromCivil(y, m, d);
}

/** Rewards.add_days. */
export function addDays(key: string, days: number): string {
  return keyOfDays(dayNum(key) + days);
}

/**
 * The server's day key for a unix time: the calendar day at UTC + offsetMin (default DAY_OFFSET_MIN = 360, Bangladesh).
 * The game uses the device's local day instead (README: "Days").
 */
export function dayKey(unix: number, offsetMin: number = DAY_OFFSET_MIN): string {
  return keyOfDays(Math.floor((Math.floor(unix) + offsetMin * 60) / 86400));
}

/** Unix seconds when the day `key` starts (in the same offset). */
export function dayStart(key: string, offsetMin: number = DAY_OFFSET_MIN): number {
  return dayNum(key) * 86400 - offsetMin * 60;
}

/** Unix seconds when the day after `key` starts: when the calendar and the wheel open again. */
export function nextDayAt(key: string, offsetMin: number = DAY_OFFSET_MIN): number {
  return dayStart(addDays(key, 1), offsetMin);
}

/**
 * The ISO 8601 week ("2026-W43") of the server day of a unix time: weeks start on Monday 00:00 at UTC + offsetMin
 * (Bangladesh by default), so a week starts on Sunday 18:00 UTC. The leaderboard's weekly period.
 */
export function isoWeek(unix: number, offsetMin: number = DAY_OFFSET_MIN): string {
  const days = Math.floor((Math.floor(unix) + offsetMin * 60) / 86400); // days since 1970-01-01 (a Thursday)
  const dow = (((days + 3) % 7) + 7) % 7; // 0 = Monday
  const thursday = days - dow + 3; // the ISO year is the year of the week's Thursday
  const year = civilFromDays(thursday)[0];
  const week = Math.floor((thursday - daysFromCivil(year, 1, 1)) / 7) + 1;
  return `${pad(year, 4)}-W${pad(week, 2)}`;
}

/** The leaderboard period of the week of a unix time: "week:2026-W43". */
export function weekPeriod(unix: number, offsetMin: number = DAY_OFFSET_MIN): string {
  return `week:${isoWeek(unix, offsetMin)}`;
}


// ---------- daily reward ----------

export interface DailyData {
  cycle: number;
  streak: number;
  last: string;
  last_at: number;
  auto_on: string;
  history: unknown[];
}

export interface Grant {
  coins: number;
  dice: string;
  char: string;
}

export interface DailyTile {
  day: number;
  reward: Dict;
  grant: Grant;
  status: "claimed" | "today" | "locked";
}

export interface DailyState {
  key: string;
  claimable: boolean;
  cycle: number;
  /** Tiles already claimed in this cycle. */
  claimed: number;
  /** Index of today's tile, -1 when nothing is claimable. */
  today: number;
  /** 1-7: the day claimable now, or the last one claimed. */
  day: number;
  streak: number;
  /** A run was broken. */
  missed: boolean;
  rewards: DailyTile[];
}

export function cycleRewards(cycle: number): Dict[] {
  const n = REWARDS.daily_cycles.length;
  return REWARDS.daily_cycles[((cycle % n) + n) % n] as Dict[];
}

/** Rewards.daily_data: the saved calendar state, repaired (written back into p.daily). */
export function dailyData(p: Profile): DailyData {
  const d: Dict = isDict(p.daily) ? p.daily : {};
  const { cycle, streak, last_at } = d;
  const hist = isArray(d.history) ? d.history : [];
  const fixed: DailyData = {
    cycle: isGdInt(cycle) && Math.trunc(cycle) >= 0 ? Math.trunc(cycle) : 0,
    streak: isGdInt(streak) && Math.trunc(streak) >= 0 && Math.trunc(streak) <= 7 ? Math.trunc(streak) : 0,
    last: isDayKey(d.last) ? d.last : "",
    last_at: isGdInt(last_at) && Math.trunc(last_at) > 0 ? Math.trunc(last_at) : 0,
    auto_on: typeof d.auto_on === "string" ? d.auto_on : "",
    history: hist.slice(-REWARDS.history_max),
  };
  p.daily = fixed as unknown as Dict;
  return fixed;
}

/** Rewards.grant_of: what reward r gives p now (owned dice and owned characters turn into their `or` coins). */
export function grantOf(p: Profile, r: Dict): Grant {
  const g: Grant = { coins: getInt(r, "coins", 0), dice: "", char: "" };
  if ("dice" in r) {
    const owned = isArray(p.dice_owned) ? p.dice_owned : [];
    if (typeof r.dice === "string" && item("dice", r.dice) && !owned.includes(r.dice)) g.dice = r.dice;
    else g.coins += getInt(r, "or", 0);
  }
  if ("char" in r) {
    const have = isArray(p.av_owned) ? p.av_owned : [];
    const c = String(r.char);
    if (!have.includes(r.char) && item("char", c)) g.char = c;
    else g.coins += getInt(r, "or", 0);
  }
  return g;
}

/** Rewards._granted: what a claimed day gave (its history entry, else the reward itself). */
function granted(d: DailyData, cycle: number, k: number, r: Dict): Grant {
  const hist = d.history;
  for (let i = hist.length - 1; i >= 0; i--) {
    const e = hist[i];
    if (isDict(e) && getInt(e, "day", 0) === k + 1 && getInt(e, "cycle", -1) === cycle) {
      const it = typeof e.item === "string" ? e.item : "";
      const isChar = it.startsWith("ch-");
      return { coins: getInt(e, "coins", 0), dice: isChar ? "" : it, char: isChar ? it : "" };
    }
  }
  const g: Grant = { coins: getInt(r, "coins", 0), dice: "dice" in r ? String(r.dice) : "", char: "" };
  if ("char" in r) g.coins += getInt(r, "or", 0);
  return g;
}

/** Rewards.daily_state (without the labels). Repairs p.daily in place, as the game does. */
export function dailyStateMut(p: Profile, today: string): DailyState {
  const d = dailyData(p);
  const gap = d.last !== "" ? dayNum(today) - dayNum(d.last) : 1 << 30;
  let st: Omit<DailyState, "rewards">;
  if (gap <= 0) {
    st = { key: today, streak: d.streak, missed: false, claimable: false, cycle: d.cycle, claimed: d.streak, today: -1, day: Math.max(1, d.streak) };
  } else {
    let cycle = d.cycle;
    let start = d.streak;
    if (gap === 1 && d.streak === 7) {
      cycle += 1;
      start = 0;
    } else if (gap > 1) {
      start = 0;
    }
    if (gap > 1 && d.streak === 7) cycle += 1;
    st = {
      key: today, streak: d.streak, claimable: true, cycle, claimed: start, today: start, day: start + 1,
      missed: gap > 1 && d.last !== "" && d.streak > 0 && d.streak < 7,
    };
  }
  const rewards = cycleRewards(st.cycle);
  const list: DailyTile[] = [];
  for (let k = 0; k < 7; k++) {
    const g = k >= st.claimed ? grantOf(p, rewards[k]) : granted(d, st.cycle, k, rewards[k]);
    list.push({ day: k + 1, reward: rewards[k], grant: g, status: k < st.claimed ? "claimed" : k === st.today ? "today" : "locked" });
  }
  return { ...st, rewards: list };
}

/** The calendar for GET-style reads: the state and the repaired profile (p is not changed). */
export function dailyState(profile: Profile, today: string): { state: DailyState; profile: Profile; next_at?: number } {
  const p = clone(profile);
  const state = dailyStateMut(p, today);
  return state.claimable ? { state, profile: p } : { state, profile: p, next_at: nextDayAt(today) };
}

export type DailyClaim =
  | { ok: true; profile: Profile; delta: Delta; coins: number; dice: string; char: string; day: number; cycle: number }
  | { ok: false; error: "claimed"; next_at: number; day: number; cycle: number; profile: Profile };

/** Rewards.claim_daily: today's reward (coins / dice / character), once per day. POST /v1/rewards/daily. */
export function claimDaily(profile: Profile, today: string, now: number): DailyClaim {
  const p = clone(profile);
  const st = dailyStateMut(p, today);
  if (!st.claimable) return { ok: false, error: "claimed", next_at: nextDayAt(today), day: st.day, cycle: st.cycle, profile: p };
  const g = st.rewards[st.today].grant;
  const d = p.daily as unknown as DailyData;
  const itemId = g.dice !== "" ? g.dice : g.char !== "" ? g.char : null;
  const hist = d.history;
  hist.push({ on: st.key, at: now, cycle: st.cycle, day: st.today + 1, coins: g.coins, item: itemId });
  d.history = hist.slice(-REWARDS.history_max);
  d.cycle = st.cycle;
  d.streak = st.today + 1;
  d.last = st.key;
  d.last_at = now;
  addCoins(p, g.coins);
  const items: { kind: string; id: string }[] = [];
  if (g.dice !== "") {
    const owned = isArray(p.dice_owned) ? p.dice_owned : [CATALOG.defaults.dice];
    owned.push(g.dice);
    p.dice_owned = owned;
    items.push({ kind: "dice", id: g.dice });
  }
  if (g.char !== "") {
    const have = isArray(p.av_owned) ? p.av_owned : [];
    have.push(g.char);
    p.av_owned = have;
    items.push({ kind: "char", id: g.char });
  }
  const delta: Delta = { coins: g.coins, xp: 0 };
  if (items.length) delta.items = items;
  return { ok: true, profile: p, delta, coins: g.coins, dice: g.dice, char: g.char, day: st.today + 1, cycle: st.cycle };
}


// ---------- daily spin ----------

export const PRIZES: readonly number[] = REWARDS.prizes;

/** Rewards.can_spin. */
export function canSpin(p: Profile, today: string): boolean {
  return String(p.last_spin ?? "") !== today;
}

/**
 * A wheel segment from the server RNG: uniform over the 8 segments, as rng.randi_range(0, 7) in the game
 * (100 is on two segments, so it comes up 2 times in 8). 2^32 is a multiple of 8, so `% 8` has no bias.
 */
export function rollSpin(): number {
  const r = new Uint32Array(1);
  crypto.getRandomValues(r);
  return r[0] % PRIZES.length;
}

export type SpinResult =
  | { ok: true; profile: Profile; delta: Delta; index: number; prize: number }
  | { ok: false; error: "spun"; next_at: number };

/** Rewards.spin with the segment given: once per day. POST /v1/rewards/spin (roll = rollSpin()). */
export function spin(profile: Profile, today: string, roll: number): SpinResult {
  if (!Number.isInteger(roll) || roll < 0 || roll >= PRIZES.length) throw new RangeError(`spin roll ${roll}`);
  if (!canSpin(profile, today)) return { ok: false, error: "spun", next_at: nextDayAt(today) };
  const p = clone(profile);
  p.last_spin = today;
  addCoins(p, PRIZES[roll]);
  return { ok: true, profile: p, delta: { coins: PRIZES[roll], xp: 0 }, index: roll, prize: PRIZES[roll] };
}


// ---------- free coins ----------

export const FREE_EVERY_SEC = REWARDS.free_every_sec;
export const FREE_AMOUNT = REWARDS.free_amount;

/** Rewards.free_left_sec: seconds until Free Coins can be claimed again (a clock moved back waits at most one period). */
export function freeLeftSec(p: Profile, now: number): number {
  const last = getInt(p, "last_free", 0);
  if (last <= 0) return 0;
  return clamp(FREE_EVERY_SEC - (now - last), 0, FREE_EVERY_SEC);
}

export type FreeResult =
  | { ok: true; profile: Profile; delta: Delta; coins: number; next_at: number }
  | { ok: false; error: "cooldown"; next_at: number };

/** Rewards.claim_free: FREE_AMOUNT every FREE_EVERY_SEC. POST /v1/rewards/free. */
export function claimFree(profile: Profile, now: number): FreeResult {
  const left = freeLeftSec(profile, now);
  if (left > 0) return { ok: false, error: "cooldown", next_at: now + left };
  const p = clone(profile);
  p.last_free = now;
  addCoins(p, FREE_AMOUNT);
  return { ok: true, profile: p, delta: { coins: FREE_AMOUNT, xp: 0 }, coins: FREE_AMOUNT, next_at: now + FREE_EVERY_SEC };
}
