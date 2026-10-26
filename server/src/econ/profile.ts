// The player's profile: its shape and defaults (Save._ensure), level math (Save.level_info), ownership and unlocks
// (Catalog.owns_*, SLScenes.owns_scene, Collection.is_unlocked / equipped). Pure functions, no I/O.
import {
  CATALOG,
  DEFAULT_AVATAR,
  DEFAULT_FRAME,
  DEFAULT_PLATE,
  DEFAULT_ROOM,
  DEFAULT_SCENE,
  DEFAULTS,
  FREE_DICE,
  FREE_EMOTES,
  FREE_ROOMS,
  STAT_KEYS,
  achievement,
  avatarItem,
  item,
} from "./catalog";
import { type Dict, clone, getInt, isArray, isDict, list, str, stripEdges } from "./gd";

export interface Stats {
  played: number;
  wins: number;
  losses: number;
  streak: number;
  bestStreak: number;
  coinsEarned: number;
  pairsFormed: number;
  ppGames: number;
  slPlayed: number;
  slWins: number;
  [k: string]: unknown;
}

/** The profile as the game saves it (user://save.json `profile`). Unknown keys are kept, as the game keeps them. */
export interface Profile {
  name: string;
  id: string;
  coins: number;
  /** Premium currency, >= 0. */
  gems: number;
  /** Free re-rolls, 0..9. */
  rerolls: number;
  xp: number;
  stats: Stats;
  /** Owned rooms (the free ones always). */
  rooms: unknown[];
  room: string;
  dice_owned: unknown[];
  dice: string;
  /** Owned emote packs (Starter always) and the equipped pack. */
  emote_sets: unknown[];
  emote_set: string;
  /** Owned Snakes & Ladders scenes; the game adds the field on the first scene purchase (Jungle is implied). */
  scenes?: unknown;
  scene?: unknown;
  /** Rewards.daily_data: {cycle, streak, last, last_at, auto_on, history}. */
  daily: Dict;
  /** The day key of the last spin. */
  last_spin: string;
  /** Unix seconds of the last Free Coins claim. */
  last_free: number;
  avatar: string;
  /** Bought characters (and characters from the daily calendar). */
  av_owned: unknown[];
  frame: string;
  plate: string;
  badge: string;
  /** Claimed achievements. */
  claimed: unknown[];
  [k: string]: unknown;
}

/** What a change did, for the ledger row ({delta_coins, delta_xp}). */
export interface Delta {
  coins: number;
  xp: number;
  /** Gems (negative when spent). */
  gems?: number;
  /** Items added to the profile. */
  items?: { kind: string; id: string }[];
}

export const ZERO: Delta = Object.freeze({ coins: 0, xp: 0 }) as Delta;

const ID_ABC = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

/** A new player ID like the game's: "LZM-XXXX-XXXX" (32 letters and digits, no I / O / 0 / 1). */
export function newPlayerId(): string {
  const r = new Uint32Array(8);
  crypto.getRandomValues(r);
  let s = "";
  for (const v of r) s += ID_ABC[v % ID_ABC.length];
  return `LZM-${s.slice(0, 4)}-${s.slice(4, 8)}`;
}

export function isPlayerId(v: unknown): v is string {
  return typeof v === "string" && /^LZM-[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}$/.test(v);
}

/**
 * Save._ensure: fills only missing or wrongly typed fields, never overwrites saved ones. `raw` is not changed.
 * The ID is kept when there is one (any value, as the game), else `newId()`.
 * One difference: Godot stops with a script error on int(null) / int([]) for coins, xp, last_free and stats; the
 * port uses the default there.
 */
/** Save.as_int: a number (floats truncate), or a string holding a whole number; anything else the default. */
function asInt(d: Dict, key: string, dflt: number): number {
  const v = d[key];
  if (typeof v === "number") return Number.isFinite(v) ? Math.trunc(v) : dflt;
  if (typeof v === "string" && /^\s*[+-]?\d+\s*$/.test(v)) return Number(v.trim());
  return dflt;
}

export function normalizeProfile(raw: unknown, newId: () => string = newPlayerId): Profile {
  const p: Dict = isDict(raw) ? clone(raw) : {};
  if (typeof p.name !== "string" || stripEdges(p.name) === "") p.name = DEFAULTS.name;
  if (!("id" in p)) p.id = newId();
  p.coins = Math.max(0, asInt(p, "coins", DEFAULTS.coins));
  p.gems = Math.max(0, asInt(p, "gems", 0));
  p.rerolls = Math.min(9, Math.max(0, asInt(p, "rerolls", 0)));
  p.xp = Math.max(0, asInt(p, "xp", 0));
  const st: Dict = isDict(p.stats) ? p.stats : {};
  for (const k of STAT_KEYS) st[k] = Math.max(0, asInt(st, k, 0));
  p.stats = st;
  const rooms = isArray(p.rooms) ? p.rooms : [];
  for (const free of FREE_ROOMS) if (!rooms.includes(free)) rooms.push(free);
  p.rooms = rooms;
  if (typeof p.room !== "string" || !rooms.includes(p.room)) p.room = DEFAULT_ROOM;
  const dice = isArray(p.dice_owned) ? p.dice_owned : [];
  if (!dice.includes(FREE_DICE)) dice.unshift(FREE_DICE);
  p.dice_owned = dice;
  if (typeof p.dice !== "string" || !dice.includes(p.dice)) p.dice = FREE_DICE;
  const emo = isArray(p.emote_sets) ? p.emote_sets : [];
  if (!emo.includes(FREE_EMOTES)) emo.unshift(FREE_EMOTES);
  p.emote_sets = emo;
  if (typeof p.emote_set !== "string" || !emo.includes(p.emote_set)) p.emote_set = FREE_EMOTES;
  if (!isDict(p.daily)) p.daily = {};
  if (typeof p.last_spin !== "string") p.last_spin = "";
  p.last_free = Math.max(0, asInt(p, "last_free", 0));
  if (typeof p.avatar !== "string" || p.avatar === "") p.avatar = DEFAULT_AVATAR;
  if (!isArray(p.av_owned)) p.av_owned = [];
  if (typeof p.frame !== "string" || p.frame === "") p.frame = DEFAULT_FRAME;
  if (typeof p.plate !== "string" || p.plate === "") p.plate = DEFAULT_PLATE;
  if (typeof p.badge !== "string") p.badge = "";
  if (!isArray(p.claimed)) p.claimed = [];
  return p as Profile;
}

/** A brand-new profile for a new account (the game's fresh profile plus the scenes fields). */
export function newProfile(id: string = newPlayerId()): Profile {
  const p = normalizeProfile({ id });
  p.scenes = [DEFAULT_SCENE];
  p.scene = DEFAULT_SCENE;
  return p;
}


// ---------- level ----------

export interface LevelInfo {
  level: number;
  /** XP into the current level. */
  into: number;
  /** XP the current level needs to reach the next. */
  need: number;
}

/** Save.level_info: level n needs 100 + 50·(n−1) XP to reach n+1. */
export function levelInfo(xp: number): LevelInfo {
  const { base, step } = CATALOG.level;
  let level = 1;
  let need = base;
  let x = Math.trunc(xp);
  while (x >= need) {
    x -= need;
    level += 1;
    need = base + (level - 1) * step;
  }
  return { level, into: x, need };
}

/** Collection.level. */
export function levelOf(p: Dict): number {
  return levelInfo(Math.max(0, getInt(p, "xp", 0))).level;
}


// ---------- what the player has ----------

export function coinsOf(p: Dict): number {
  return getInt(p, "coins", 0);
}

/** Collection.stat. */
export function stat(name: string, p: Dict): number {
  return isDict(p.stats) ? getInt(p.stats, name, 0) : 0;
}

/** Catalog.owns_room. */
export function ownsRoom(p: Dict, id: string): boolean {
  if (!item("room", id)) return false;
  return FREE_ROOMS.includes(id) || list(p, "rooms").includes(id);
}

/** Catalog.owns_dice. */
export function ownsDice(p: Dict, id: string): boolean {
  if (!item("dice", id)) return false;
  return id === FREE_DICE || list(p, "dice_owned").includes(id);
}

/** Catalog.owns_emotes. */
export function ownsEmotes(p: Dict, id: string): boolean {
  if (!item("emotes", id)) return false;
  return id === FREE_EMOTES || list(p, "emote_sets").includes(id);
}

/** SLScenes.owned_ids: Jungle first, then the saved scenes that exist (once each). */
export function sceneIds(p: Dict): string[] {
  const out = [DEFAULT_SCENE];
  const v = p.scenes;
  if (isArray(v)) {
    for (const x of v) {
      const id = str(x);
      if (item("scene", id) && !out.includes(id)) out.push(id);
    }
  }
  return out;
}

/** SLScenes.owns_scene. */
export function ownsScene(p: Dict, id: string): boolean {
  if (!item("scene", id)) return false;
  return id === DEFAULT_SCENE || sceneIds(p).includes(id);
}

/** Collection.ach_done. */
export function achDone(id: string, p: Dict): boolean {
  const a = achievement(id);
  return a !== undefined && stat(a.stat, p) >= a.goal;
}

/** Collection.item for the collection kinds ("avatar" | "char" | "frame" | "plate" | "badge"). */
function collectionItem(kind: string, id: string) {
  switch (kind) {
    case "avatar":
    case "char":
      return avatarItem(id);
    case "frame":
      return item("frame", id);
    case "plate":
      return item("plate", id);
  }
  return undefined;
}

/**
 * Collection.is_unlocked: a paid character once bought; otherwise free, or its level / achievement reached.
 * Badges: "" (none) or a done achievement. Unknown ids and other kinds: false.
 */
export function isUnlocked(kind: string, id: string, p: Dict): boolean {
  if (kind === "badge") return id === "" || achDone(id, p);
  const it = collectionItem(kind, id);
  if (!it) return false;
  if (it.price > 0) return list(p, "av_owned").includes(id);
  const u = it.unlock;
  if (!u) return true;
  if (u.level !== undefined) return levelOf(p) >= u.level;
  return achDone(String(u.ach), p);
}

/** Collection.equipped: what is in use, falling back to the default when the saved one is unknown or locked. */
export function equipped(kind: string, p: Dict): string {
  switch (kind) {
    case "avatar":
    case "char": {
      const id = str(p.avatar, DEFAULT_AVATAR);
      return isUnlocked("avatar", id, p) ? id : DEFAULT_AVATAR;
    }
    case "frame": {
      const id = str(p.frame, DEFAULT_FRAME);
      return isUnlocked("frame", id, p) ? id : DEFAULT_FRAME;
    }
    case "plate": {
      const id = str(p.plate, DEFAULT_PLATE);
      return isUnlocked("plate", id, p) ? id : DEFAULT_PLATE;
    }
    case "badge": {
      const id = str(p.badge, "");
      return isUnlocked("badge", id, p) ? id : "";
    }
    case "room": {
      const id = str(p.room);
      return ownsRoom(p, id) ? id : DEFAULT_ROOM;
    }
    case "dice": {
      const id = str(p.dice);
      return ownsDice(p, id) ? id : FREE_DICE;
    }
    case "emotes": {
      const id = str(p.emote_set);
      return ownsEmotes(p, id) ? id : FREE_EMOTES;
    }
    case "scene": {
      const id = str(p.scene, DEFAULT_SCENE);
      return ownsScene(p, id) ? id : DEFAULT_SCENE;
    }
  }
  return "";
}

/** Rewards._add_coins / Save.add_coins: coins, and stats.coinsEarned for a gain. */
export function addCoins(p: Profile, n: number): void {
  p.coins = getInt(p, "coins", 0) + n;
  if (n > 0) {
    const st: Dict = isDict(p.stats) ? p.stats : {};
    st.coinsEarned = getInt(st, "coinsEarned", 0) + n;
    p.stats = st as Stats;
  }
}
