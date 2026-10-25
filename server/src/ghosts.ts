// Quick-match ghosts: seats the server fills when not enough people queue (ONLINE_V2.md §3, owner decision: no
// disclosure). To every client a ghost is an ordinary person: players[c] = "human" in the rules state, a common
// Bangladeshi first name, a free avatar, a plausible level, online, never a bot. Only the Room knows (seat.ghost,
// stored server-side, never in a message) and the admin console sees it (adminSnapshot).
//
// This module is pure (no I/O): identities, human-like delays and the move policy. room.ts drives the seats.
import data from "./econ/catalog.json";
import { GOAL, dest, movables, moverOf, pickAi, type LudoState } from "./rules/ludo";
import type { Rng } from "./rules/rng";

// ---------- identities ----------

/** Common Bangladeshi first names (the spellings people type in games). */
export const MALE_NAMES = [
  "Rahim", "Karim", "Hasan", "Hossain", "Rafiq", "Jamal", "Kamal", "Sohel", "Sumon", "Shakil",
  "Rasel", "Rubel", "Masud", "Mamun", "Faruk", "Habib", "Hridoy", "Imran", "Jahid", "Jewel",
  "Kawsar", "Liton", "Mahbub", "Mehedi", "Milon", "Mizan", "Monir", "Nayeem", "Nazmul", "Noman",
  "Parvez", "Polash", "Rakib", "Rana", "Rashed", "Razib", "Riyad", "Robin", "Saiful", "Sajib",
  "Sajid", "Salman", "Shafiq", "Shahin", "Shamim", "Shanto", "Sharif", "Shihab", "Shuvo", "Siam",
  "Sohag", "Sujon", "Tamim", "Tanvir", "Tarek", "Touhid", "Wasim", "Yasin", "Zahid", "Zubair",
  "Arif", "Asif", "Ashik", "Babu", "Biplob", "Emon", "Fahim", "Faisal", "Hasib", "Ibrahim",
  "Jubayer", "Mahfuz", "Nahid", "Rifat", "Sabbir", "Sakib", "Tuhin", "Anik", "Apu", "Rony",
] as const;

export const FEMALE_NAMES = [
  "Ayesha", "Fatema", "Nusrat", "Sadia", "Sumaiya", "Tania", "Farhana", "Jannat", "Sharmin", "Nasrin",
  "Rumana", "Shirin", "Rima", "Riya", "Mim", "Mitu", "Lima", "Lipi", "Munni", "Moushumi",
  "Nadia", "Nabila", "Nafisa", "Nishat", "Papiya", "Popy", "Priya", "Rabeya", "Rehana", "Ruma",
  "Sabina", "Salma", "Sanjida", "Shamima", "Shathi", "Shila", "Shompa", "Sonia", "Sultana", "Sumi",
  "Tahmina", "Tamanna", "Tanjila", "Tasnim", "Tisha", "Urmi", "Afroza", "Anika", "Antara", "Bristy",
  "Dola", "Eva", "Fariha", "Faria", "Habiba", "Israt", "Jesmin", "Jui", "Keya", "Laboni",
  "Lamia", "Maliha", "Marjia", "Mahmuda", "Mehjabin", "Mukta", "Nipa", "Orin", "Prova", "Raisa",
  "Rokeya", "Samia", "Sinthia", "Sraboni", "Sumona",
] as const;

interface CatalogItemLite {
  kind: string;
  id: string;
  free: boolean;
}

/** Free avatars and characters from the catalog (what a new player can pick without coins or unlocks). */
export const FREE_AVATARS: readonly string[] = (data.items as CatalogItemLite[])
  .filter((it) => (it.kind === "avatar" || it.kind === "char") && it.free)
  .map((it) => it.id);

/** The avatar every new profile starts with (most people keep it). */
export const DEFAULT_AVATAR: string = data.defaults.avatar;

/** Characters that read as one gender (a ghost's avatar should not contradict its name). */
const FEMALE_CHARS = new Set(["ch-nadia", "ch-riya", "ch-tania", "ch-mim", "ch-sumaiya", "ch-priya", "ch-lamia", "ch-fariha", "ch-nusrat", "ch-ayesha"]);

export interface GhostIdentity {
  name: string;
  avatar: string;
  frame: string;
  level: number;
}

export interface HumanLite {
  name: string;
  level: number;
}

function pick<T>(arr: readonly T[], rng: Rng): T {
  return arr[Math.min(Math.floor(rng.randf() * arr.length), arr.length - 1)];
}

function intIn(lo: number, hi: number, rng: Rng): number {
  return lo + Math.min(Math.floor(rng.randf() * (hi - lo + 1)), hi - lo);
}

const norm = (s: string) => s.trim().toLowerCase();

/**
 * n ghost identities for a room with these humans: names unique in the room and never a human's name
 * (case-insensitive), a free avatar that fits the name, the default frame, a level within ±3 of a human's.
 */
export function makeGhosts(n: number, humans: readonly HumanLite[], rng: Rng): GhostIdentity[] {
  const taken = new Set(humans.map((h) => norm(h.name)));
  const levels = humans.map((h) => Math.max(1, Math.trunc(h.level) || 1));
  if (!levels.length) levels.push(intIn(2, 12, rng));
  const out: GhostIdentity[] = [];
  for (let k = 0; k < n; k++) {
    const female = rng.randf() < 0.4;
    const pool = (female ? FEMALE_NAMES : MALE_NAMES).filter((x) => !taken.has(norm(x)));
    const name = pool.length ? pick(pool, rng) : `Player${intIn(10, 99, rng)}`;
    taken.add(norm(name));
    const fits = FREE_AVATARS.filter((a) => !a.startsWith("ch-") || FEMALE_CHARS.has(a) === female);
    // most people keep the default avatar
    const avatar = rng.randf() < 0.35 ? DEFAULT_AVATAR : pick(fits.length ? fits : FREE_AVATARS, rng);
    const base = pick(levels, rng);
    const level = Math.max(1, base + intIn(-3, 3, rng));
    out.push({ name, avatar, frame: "classic", level });
  }
  return out;
}

// ---------- timing ----------

/** Human-like delays (ms) before a ghost acts, by phase (task brief: roll 0.8-2.6 s, choose 1-3.5 s + ~8% 4-6 s). */
export const GHOST_TIMING = {
  roll: [800, 2600],
  choose: [1000, 3500],
  think: [4000, 6000],
  thinkChance: 0.08,
  pair: [800, 2000],
} as const;

export function ghostDelay(phase: string, rng: Rng): number {
  const span = ([lo, hi]: readonly [number, number]) => lo + rng.randf() * (hi - lo);
  if (phase === "choose") {
    return rng.randf() < GHOST_TIMING.thinkChance ? span(GHOST_TIMING.think) : span(GHOST_TIMING.choose);
  }
  if (phase === "pair_ask") return span(GHOST_TIMING.pair);
  return span(GHOST_TIMING.roll);
}

// ---------- skill ----------

/**
 * Chance that a ghost plays a random legal move instead of the "normal" AI's choice. Tuned with
 * test/quick_ghost_skill.test.ts so that a player using the normal AI wins 45-55% of 1v1 games against a ghost.
 * Measured (seeded games, fake dice): 0 -> 50.3%, 0.03 -> 51.8%, 0.05 -> 52.4% (20,000 games each), 0.1 -> 54.9%,
 * 0.2 -> 60.7%, 0.3 -> 67.4% (4,000 games). The brief's ~20% would make ghosts too easy; 3% keeps the human near 52%.
 */
export const GHOST_MISTAKE = 0.03;

/** The ghost's move (a token from movables(s)): normal AI, or (mistake rate) a random legal move. -1 if none. */
export function ghostPick(s: LudoState, rng: Rng, mistake = GHOST_MISTAKE): number {
  const mv = movables(s);
  if (!mv.length) return -1;
  if (mv.length > 1 && rng.randf() < mistake) {
    // a person's slip: any legal move, but nobody skips bringing a pawn home
    const c = moverOf(s, s.turn);
    const home = mv.filter((i) => dest(s, c, i, s.dice) === GOAL);
    if (home.length && rng.randf() < 0.7) return home[0];
    return pick(mv, rng);
  }
  return pickAi(s, mv, rng, "normal");
}

/** Pair answers: people mostly say yes. */
export function ghostPairYes(rng: Rng): boolean {
  return rng.randf() < 0.85;
}

// ---------- emotes (EMOTES.md) ----------

/** The emote packs in manifest order (ids of the 24 emotes; `starter` is free and always owned). */
export const EMOTE_PACKS: Readonly<Record<string, readonly string[]>> = {
  starter: ["happy", "laugh", "cool", "angry", "love", "party"],
  pawns: ["champ", "sleepy", "sob", "gasp", "confused", "hi"],
  friends: ["cry", "wow", "facepalm", "cheer", "think", "tease"],
  game: ["dice", "crown", "highfive", "flag", "sad", "peek"],
};
export const PAID_PACKS: readonly string[] = ["pawns", "friends", "game"];

/** The pack that contains emote `id`, or "" when it is not one of the 24. */
export function packOfEmote(id: unknown): string {
  if (typeof id !== "string") return "";
  for (const [p, ids] of Object.entries(EMOTE_PACKS)) if (ids.includes(id)) return p;
  return "";
}

/** What made a ghost want to react. */
export type EmoteKind = "capture" | "captured" | "six" | "finish" | "reply";

/** Emotes that fit each moment, best first (a ghost uses the first few it owns, picked at random). */
const MOOD: Record<EmoteKind, readonly string[]> = {
  capture: ["laugh", "cool", "tease", "champ", "party", "highfive", "happy"],
  captured: ["angry", "sob", "cry", "sad", "gasp", "wow", "confused", "facepalm"],
  six: ["party", "cool", "happy", "cheer", "dice", "wow"],
  finish: ["party", "happy", "love", "cheer", "crown", "champ", "highfive"],
  reply: ["happy", "laugh", "love", "hi", "wow", "cheer", "highfive", "tease", "cool"],
};

/** Ghost emote tuning: chance per event, delay (ms) and the minimum gap per ghost (ms). */
export const GHOST_EMOTE = { chance: 0.25, delay: [800, 2500], gap: 8000 } as const;

/** One random paid pack, the second pack a ghost "owns" (besides starter). */
export function ghostPack(rng: Rng): string {
  return pick(PAID_PACKS, rng);
}

/** The emote a ghost owning `pack` (and starter) sends for this moment. */
export function ghostEmote(kind: EmoteKind, pack: string, rng: Rng): string {
  const owned = new Set([...EMOTE_PACKS.starter, ...(EMOTE_PACKS[pack] ?? [])]);
  const fit = MOOD[kind].filter((id) => owned.has(id));
  return pick(fit.length ? fit : EMOTE_PACKS.starter, rng);
}
