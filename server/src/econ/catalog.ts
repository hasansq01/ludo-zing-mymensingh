// The economy's tables, generated from the GDScript sources by godot/dev/export_catalog.gd into catalog.json
// (regenerate from the repo root: godot --headless --path godot -s res://dev/export_catalog.gd -- ../server/src/econ/catalog.json).
// Server-only rules that have no GDScript counterpart (online rewards, claim limits, import caps) live in rules.ts.
import data from "./catalog.json";

export type ItemKind = "dice" | "emotes" | "room" | "scene" | "char" | "avatar" | "frame" | "plate" | "badge";
export const ITEM_KINDS: readonly ItemKind[] = ["dice", "emotes", "room", "scene", "char", "avatar", "frame", "plate", "badge"];

export interface Unlock {
  level?: number;
  ach?: string;
}

export interface CatalogItem {
  kind: ItemKind;
  id: string;
  name: string;
  /** Coins; 0 for free and unlock-only items. */
  price: number;
  /** Gem price, ceil(price / 100); only on items the Shop sells (buy: true). */
  gems?: number;
  /** Sold for coins in the Shop (rooms, dice, scenes, characters with a price). */
  buy: boolean;
  /** Owned / usable by everyone from the start. */
  free: boolean;
  /** The fallback of its kind. */
  default: boolean;
  /** Unlocked by level or by an achievement (avatars, frames, plates, badges). */
  unlock: Unlock | null;
}

export interface Achievement {
  id: string;
  name: string;
  stat: string;
  goal: number;
  reward: number;
}

export interface DailyReward {
  coins?: number;
  dice?: string;
  char?: string;
  or?: number;
}

export interface CatalogData {
  version: number;
  source: string;
  items: CatalogItem[];
  achievements: Achievement[];
  defaults: {
    name: string;
    coins: number;
    xp: number;
    stats: string[];
    rooms: string[];
    room: string;
    dice_owned: string[];
    dice: string;
    emote_sets: string[];
    emote_set: string;
    scenes: string[];
    scene: string;
    avatar: string;
    frame: string;
    plate: string;
    badge: string;
    bot_levels: string[];
  };
  level: { base: number; step: number };
  rewards: {
    daily_cycles: DailyReward[][];
    history_max: number;
    prizes: number[];
    free_every_sec: number;
    free_amount: number;
  };
  match: {
    ludo: MatchTable;
    sl: MatchTable;
    online_today: { coins_win: number; coins_finish: number; xp_win: number; xp_finish: number };
  };
}

export interface MatchTable {
  /** Coins for beating the computer. */
  win: number;
  /** Coins for finishing a game lost against the computer. */
  play: number;
  xp_win: number;
  xp_loss: number;
  /** Pass & Play. */
  xp_pp: number;
}

export const CATALOG = data as CatalogData;

const byKind = new Map<string, CatalogItem>();
for (const it of CATALOG.items) byKind.set(`${it.kind}:${it.id}`, it);

/** The catalogue entry, or undefined. */
export function item(kind: string, id: string): CatalogItem | undefined {
  return byKind.get(`${kind}:${id}`);
}

export function items(kind: ItemKind): CatalogItem[] {
  return CATALOG.items.filter((it) => it.kind === kind);
}

export function ids(kind: ItemKind): string[] {
  return items(kind).map((it) => it.id);
}

/** Collection.avatar(id): an original avatar or a character. */
export function avatarItem(id: string): CatalogItem | undefined {
  return item("avatar", id) ?? item("char", id);
}

export function achievement(id: string): Achievement | undefined {
  return CATALOG.achievements.find((a) => a.id === id);
}

export const DEFAULTS = CATALOG.defaults;
export const STAT_KEYS = CATALOG.defaults.stats;
export const FREE_ROOMS = CATALOG.defaults.rooms;
export const FREE_DICE = CATALOG.defaults.dice;
export const FREE_EMOTES = CATALOG.defaults.emote_set;
export const DEFAULT_ROOM = CATALOG.defaults.room;
export const DEFAULT_SCENE = CATALOG.defaults.scene;
export const DEFAULT_AVATAR = CATALOG.defaults.avatar;
export const DEFAULT_FRAME = CATALOG.defaults.frame;
export const DEFAULT_PLATE = CATALOG.defaults.plate;
export const REWARDS = CATALOG.rewards;
export const MATCH = CATALOG.match;
