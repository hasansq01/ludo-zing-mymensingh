// The one-time import of the local (pre-v2) profile into a new account (POST /v1/auth/guest {pid, import}).
// Only known fields are taken; numbers are capped, owned items must exist, equipped items must be owned or
// unlocked, reward timers may only make the player wait (never claim twice). Every change is listed in `notes`.
import { DEFAULT_SCENE, FREE_DICE, FREE_EMOTES, FREE_ROOMS, STAT_KEYS, achievement, item } from "./catalog";
import { IMPORT_CAPS } from "./rules";
import { type Dict, clamp, clone, isArray, isDict, isGdInt, stripEdges } from "./gd";
import { type Delta, type Profile, achDone, equipped, isPlayerId } from "./profile";
import { dayNum, isDayKey } from "./rewards";

export interface ImportResult {
  ok: true;
  profile: Profile;
  /** Against `base` (the account's new profile), for the ledger row (reason "import"). */
  delta: Delta;
  /** What was capped, dropped or reset. */
  notes: string[];
}

export type ImportOutcome = ImportResult | { ok: false; error: "invalid" };

function num(v: unknown): number | undefined {
  return typeof v === "number" && Number.isFinite(v) ? Math.trunc(v) : undefined;
}

/** NetClient.wire_name: trimmed, inner runs of spaces collapsed, at most 16 characters. */
/** "You" is what every client calls its own player (tiles, leaderboard rows): nobody may be named that. */
export function reservedName(name: string): boolean {
  return name.trim().toLowerCase() === "you";
}

export function cleanName(v: unknown): string {
  if (typeof v !== "string") return "";
  return stripEdges(v).split(" ").filter((s) => s !== "").join(" ").slice(0, IMPORT_CAPS.name_max);
}

function ownedIds(v: unknown, kind: "room" | "dice" | "emotes" | "scene" | "char", field: string, notes: string[]): string[] {
  const out: string[] = [];
  if (v === undefined) return out;
  if (!isArray(v)) {
    notes.push(`${field}: not a list`);
    return out;
  }
  for (const x of v) {
    const it = typeof x === "string" ? item(kind, x) : undefined;
    if (!it || (kind === "char" && it.price <= 0)) {
      notes.push(`${field}: dropped ${JSON.stringify(x)}`);
      continue;
    }
    if (!out.includes(it.id)) out.push(it.id);
  }
  return out;
}

/**
 * Validates and caps a local profile. `base` is the account's fresh profile (newProfile()), `today` / `now` the
 * server's day key and clock. The result is a complete profile; nothing from `raw` is trusted as is.
 */
export function importProfile(raw: unknown, base: Profile, today: string, now: number): ImportOutcome {
  if (!isDict(raw)) return { ok: false, error: "invalid" };
  const notes: string[] = [];
  const p = clone(base);

  const name = cleanName(raw.name);
  if (name !== "" && !reservedName(name)) p.name = name;
  if (isPlayerId(raw.id)) p.id = raw.id;

  const capNum = (v: unknown, field: string, max: number, dflt: number): number => {
    if (v === undefined) return dflt;
    const n = num(v);
    if (n === undefined) {
      notes.push(`${field}: not a number`);
      return dflt;
    }
    const c = clamp(n, 0, max);
    if (c !== n) notes.push(`${field}: ${n} -> ${c}`);
    return c;
  };
  p.coins = capNum(raw.coins, "coins", IMPORT_CAPS.coins, base.coins);
  p.xp = capNum(raw.xp, "xp", IMPORT_CAPS.xp, base.xp);

  const st = isDict(raw.stats) ? raw.stats : {};
  for (const k of STAT_KEYS) p.stats[k] = capNum(st[k], `stats.${k}`, IMPORT_CAPS.stat, 0);
  if (p.stats.bestStreak < p.stats.streak) p.stats.bestStreak = p.stats.streak;

  // owned items: only ones that exist (characters: only paid ones; the free ones need no entry)
  const rooms = ownedIds(raw.rooms, "room", "rooms", notes);
  p.rooms = [...FREE_ROOMS, ...rooms.filter((r) => !FREE_ROOMS.includes(r))];
  const dice = ownedIds(raw.dice_owned, "dice", "dice_owned", notes);
  p.dice_owned = [FREE_DICE, ...dice.filter((d) => d !== FREE_DICE)];
  const emo = ownedIds(raw.emote_sets, "emotes", "emote_sets", notes);
  p.emote_sets = [FREE_EMOTES, ...emo.filter((e) => e !== FREE_EMOTES)];
  const scenes = ownedIds(raw.scenes, "scene", "scenes", notes);
  p.scenes = [DEFAULT_SCENE, ...scenes.filter((s) => s !== DEFAULT_SCENE)];
  p.av_owned = ownedIds(raw.av_owned, "char", "av_owned", notes);

  // achievements: claimed only when they exist and are done by the imported stats
  const claimed: string[] = [];
  if (isArray(raw.claimed)) {
    for (const x of raw.claimed) {
      if (typeof x === "string" && achievement(x) && achDone(x, p)) {
        if (!claimed.includes(x)) claimed.push(x);
      } else notes.push(`claimed: dropped ${JSON.stringify(x)}`);
    }
  }
  p.claimed = claimed;

  // equipped: owned / unlocked, else the default
  const fields: [string, string][] = [["room", "room"], ["dice", "dice"], ["emotes", "emote_set"], ["scene", "scene"], ["avatar", "avatar"], ["frame", "frame"], ["plate", "plate"], ["badge", "badge"]];
  for (const [kind, field] of fields) {
    const v = raw[field];
    if (v === undefined) continue;
    const q: Dict = { ...p, [field]: typeof v === "string" ? v : "" };
    const use = equipped(kind, q);
    if (use !== v) notes.push(`${field}: ${JSON.stringify(v)} -> ${JSON.stringify(use)}`);
    p[field] = use;
  }

  // reward timers: kept only when they lie in the past (a future one is reset, so nothing is claimable twice today
  // because of it); the daily history is not imported (only the claimed tiles' captions use it)
  const td = dayNum(today);
  if (isDict(raw.daily)) {
    const d = raw.daily;
    const last = isDayKey(d.last) && dayNum(d.last) > 0 && dayNum(d.last) <= td ? d.last : "";
    if (d.last !== undefined && last === "") notes.push("daily.last: reset");
    const cycle = isGdInt(d.cycle) && d.cycle >= 0 ? Math.min(Math.trunc(d.cycle), 9999) : 0;
    const streak = isGdInt(d.streak) && d.streak >= 0 && d.streak <= 7 && last !== "" ? Math.trunc(d.streak) : 0;
    p.daily = { cycle, streak, last, last_at: last !== "" ? Math.min(now, Math.max(0, num(d.last_at) ?? 0)) : 0, auto_on: "", history: [] };
  }
  if (isDayKey(raw.last_spin) && dayNum(raw.last_spin) > 0) {
    if (dayNum(raw.last_spin) <= td) p.last_spin = raw.last_spin;
    else {
      p.last_spin = today;
      notes.push("last_spin: in the future -> today");
    }
  }
  const lf = num(raw.last_free);
  if (lf !== undefined && lf > 0) {
    p.last_free = Math.min(lf, now);
    if (lf > now) notes.push("last_free: in the future -> now");
  }

  const delta: Delta = { coins: p.coins - base.coins, xp: p.xp - base.xp };
  return { ok: true, profile: p, delta, notes };
}
