// Quick-match ghosts: seats the server fills when not enough people queue (ONLINE_V2.md §3, owner decision: no
// disclosure). To every client a ghost is an ordinary person: players[c] = "human" in the rules state, a common
// Bangladeshi first name, a free avatar, a plausible level, online, never a bot. Only the Room knows (seat.ghost,
// stored server-side, never in a message) and the admin console sees it (adminSnapshot).
//
// This module is pure (no I/O): identities, human-like delays and the move policy. room.ts drives the seats.
import data from "./econ/catalog.json";
import { GOAL, SAFE, absIndex, dest, movables, moverOf, pickAi, threatsAt, type LudoState } from "./rules/ludo";
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

/**
 * How often a ghost says yes to "make a pair?", by situation (a person's reasoning: a pair can't be taken by a
 * single and blocks the singles behind it, but it only moves on even rolls, half as far).
 *   threat: an opponent single stands 1-6 squares behind (pairing makes both pawns safe from it, and blocks it)
 *   calm:   on an open square with nobody behind
 *   safe:   on a safe (star / start) square already, where pairing only slows the pawns down
 *   home:   near the home lane (progress 45+), where a pair splits anyway and moves half
 */
export const GHOST_PAIR = { threat: 0.95, calm: 0.7, safe: 0.3, home: 0.25 } as const;

/** The odds GHOST_PAIR gives the open pair question (phase "pair_ask", s.pending); calm when there is none. */
export function ghostPairOdds(s: LudoState, odds: Readonly<Record<keyof typeof GHOST_PAIR, number>> = GHOST_PAIR): number {
  const p = s.pending as { c?: number; to?: number };
  if (p?.c === undefined || p.to === undefined) return odds.calm;
  if (p.to >= 45) return odds.home;
  const sq = absIndex(p.c, p.to);
  if ((SAFE as readonly number[]).includes(sq)) return odds.safe;
  return threatsAt(s, p.c, sq) > 0 ? odds.threat : odds.calm;
}

/** A ghost's answer to the open pair question: yes with ghostPairOdds (one draw from rng). */
export function ghostPairYes(s: LudoState, rng: Rng): boolean {
  return rng.randf() < ghostPairOdds(s);
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

/** One random paid pack, the second pack a ghost "owns" (besides starter). */
export function ghostPack(rng: Rng): string {
  return pick(PAID_PACKS, rng);
}

// ---------- ghost emote behaviour (EMOTES.md "Ghost behaviour") ----------
//
// Everything below is pure and seeded: room.ts only supplies the situation, stores the persona and memory on the
// ghost's Member (so both survive eviction) and sends what `ghostEmoteReply` decides through the alarm.

export type Persona = "chatty" | "quiet" | "cheeky" | "friendly" | "sore";
export const PERSONAS: readonly Persona[] = ["chatty", "quiet", "cheeky", "friendly", "sore"];

/** What a ghost reacts to: a game event of its own, an emote it saw, or the match opening. */
export type GhostTrigger =
  | { kind: "capture" | "captured" | "six" | "finish" | "open" }
  | { kind: "emote"; id: string; from: number; human: boolean };

/** What the room knows right now. `scale` multiplies every duration (test time scaling); `chance` is the test hook. */
export interface GhostSituation {
  now: number;
  scale?: number;
  /** Progress lead of this ghost over the average of the others, in fractions of a full race (-1..1). */
  lead?: number;
  /** It is this ghost's own turn right now. */
  ownTurn?: boolean;
  /** Test hook: 0 = never reply, >= 1 = every random gate passes (pools, no-repeat and gaps still apply). */
  chance?: number;
}

/** Persisted per ghost: everything it remembers about the chat. Plain JSON. */
export interface GhostMemory {
  /** Its last 3 emotes, newest last. */
  last: string[];
  /** Epoch ms of the emotes it sent or has planned (rate limits, own pace). */
  sent: number[];
  /** Spam heat from humans' emotes, when the last one came, and the sulk state. */
  heat: number;
  heatAt: number;
  sulked: boolean;
  quietUntil: number;
  /** Conversations per human colour: replies so far, the planned length, ignore-until. */
  threads: Record<string, { n: number; max: number; at: number; until: number }>;
  /** Colours of other ghosts it has already reacted to (once per match each). */
  reacted: number[];
  /** Epoch ms of its last capture / of being captured (gloat / sulk windows). */
  capAt: number;
  hitAt: number;
  /** The opening greeting was decided (once per match). */
  opened: boolean;
}

export function newGhostMemory(): GhostMemory {
  return { last: [], sent: [], heat: 0, heatAt: 0, sulked: false, quietUntil: 0, threads: {}, reacted: [], capAt: 0, hitAt: 0, opened: false };
}

export interface PersonaDef {
  /** Multiplier on the chance to answer a person's emote. */
  reply: number;
  /** Multipliers on the chance to react to each game event. */
  event: Record<"capture" | "captured" | "six" | "finish", number>;
  /** Own minimum gap between two emotes (ms). */
  gap: number;
  /** Chance of opening with "hi" early in the match. */
  open: number;
  /** Multipliers on single emote ids in every pool. */
  bias: Record<string, number>;
  /** Chance that a sad person it just beat gets a cheeky (not friendly) answer. */
  cheeky: number;
}

export const PERSONA_DEFS: Readonly<Record<Persona, PersonaDef>> = {
  chatty: { reply: 1.4, event: { capture: 1.3, captured: 1.3, six: 1.6, finish: 1.2 }, gap: 4000, open: 0.45, cheeky: 0.45, bias: { hi: 1.5, happy: 1.3, party: 1.3, wow: 1.2, cheer: 1.2 } },
  quiet: { reply: 0.5, event: { capture: 0.5, captured: 0.5, six: 0.3, finish: 0.6 }, gap: 12000, open: 0, cheeky: 0.3, bias: { cool: 1.5, happy: 1.2, hi: 1.2, tease: 0.5, angry: 0.6, party: 0.7 } },
  cheeky: { reply: 1.0, event: { capture: 1.6, captured: 0.9, six: 1.0, finish: 1.2 }, gap: 6000, open: 0, cheeky: 0.85, bias: { tease: 2.4, cool: 1.8, laugh: 1.4, crown: 1.8, champ: 1.4, love: 0.5, hi: 0.7 } },
  friendly: { reply: 1.2, event: { capture: 0.6, captured: 0.7, six: 1.1, finish: 1.3 }, gap: 5000, open: 0.1, cheeky: 0.12, bias: { love: 2, hi: 2, happy: 1.6, highfive: 1.8, cheer: 1.6, tease: 0.3, angry: 0.2, facepalm: 0.6 } },
  sore: { reply: 0.9, event: { capture: 0.8, captured: 1.8, six: 0.7, finish: 0.6 }, gap: 6000, open: 0, cheeky: 0.4, bias: { angry: 2.5, facepalm: 2, cry: 1.6, sob: 1.6, sad: 1.6, flag: 1.5, love: 0.5, happy: 0.6, party: 0.5, cheer: 0.5 } },
};

/** Base chance of reacting to each game event, before the persona multiplier. */
const EVENT_CHANCE = { capture: 0.3, captured: 0.35, six: 0.12, finish: 0.45 } as const;
/** Chance of answering the 1st, 2nd, 3rd person's emote in a spam window (then nothing); x persona.reply. */
const HEAT_CHANCE = [0.6, 0.28, 0.11, 0] as const;
/** Chance (once per match, per other ghost) of reacting to a ghost's emote. */
const GHOST_TO_GHOST = 0.05;

/** Ghost emote timing (ms, before scaling). */
export const GHOST_EMOTE = {
  delay: [1000, 3500],
  /** Extra wait on its own turn: usually a little, sometimes it answers after making its move. */
  ownExtra: [500, 1500],
  afterMove: [3000, 5500],
  afterMoveChance: 0.35,
  open: [3000, 11000],
  /** Humans' limits, which ghosts obey too. */
  minGap: 2000,
  window: 30000,
  maxPerWindow: 6,
  /** Spam: a window with no human emote this long forgets the heat; heat cools by 1 per `cool`. */
  forget: 60000,
  cool: 30000,
  /** How long it sulks after "enough", and how long it ignores a finished conversation. */
  quiet: [45000, 90000],
  ignore: [60000, 120000],
  /** A conversation idle this long starts over. */
  idle: 40000,
  /** "just captured / was captured" windows for gloating and sulking. */
  recent: 15000,
} as const;

/** Longest possible reply delay (ms, unscaled): for tests and the room. */
export const GHOST_DELAY_MAX = GHOST_EMOTE.delay[1] + GHOST_EMOTE.afterMove[1];

type Pool = ReadonlyArray<readonly [string, number]>;
/** Weight of "no reply" is the entry named "-". */
const POOLS: Record<string, Pool> = {
  hi: [["hi", 5], ["love", 1], ["laugh", 1], ["cool", 1], ["happy", 1.5], ["-", 1.2]],
  love: [["love", 4], ["laugh", 1.5], ["happy", 2], ["tease", 0.4], ["cool", 0.5], ["-", 0.8]],
  happy: [["happy", 3], ["laugh", 1.5], ["love", 1], ["cool", 1], ["hi", 1], ["cheer", 1], ["-", 1.5]],
  laugh: [["laugh", 3], ["tease", 1.5], ["cool", 1], ["angry", 0.7], ["facepalm", 1], ["happy", 1], ["-", 1.2]],
  tease: [["laugh", 2], ["angry", 1.6], ["tease", 2], ["cool", 1.3], ["facepalm", 1], ["-", 1]],
  cool: [["cool", 2], ["laugh", 1], ["tease", 1], ["happy", 0.8], ["wow", 0.8], ["highfive", 0.6], ["-", 1.5]],
  angry: [["laugh", 2], ["facepalm", 1.5], ["cool", 1.3], ["confused", 1], ["gasp", 0.7], ["sad", 0.4], ["-", 1.5]],
  party: [["cheer", 2], ["highfive", 1.8], ["party", 2], ["happy", 1], ["laugh", 0.8], ["sad", 0.3], ["-", 1]],
  crown: [["cheer", 2], ["highfive", 1.5], ["party", 1.5], ["wow", 1], ["cool", 1], ["sad", 0.4], ["flag", 0.3], ["-", 1]],
  sleepy: [["laugh", 1.5], ["tease", 1.5], ["confused", 1], ["hi", 1], ["cool", 1], ["-", 2]],
  wow: [["laugh", 2], ["cool", 1.5], ["happy", 1], ["tease", 1], ["wow", 1], ["-", 1.5]],
  confused: [["laugh", 2], ["think", 1.5], ["confused", 1], ["tease", 1], ["hi", 1], ["-", 1.5]],
  facepalm: [["laugh", 2.5], ["tease", 1], ["cool", 1], ["confused", 0.8], ["sad", 0.4], ["-", 1.5]],
  highfive: [["highfive", 3], ["cheer", 2], ["party", 1.5], ["happy", 1.5], ["love", 0.7], ["-", 1]],
  dice: [["dice", 2], ["cool", 1], ["laugh", 1], ["happy", 1], ["-", 2]],
  flag: [["cool", 2], ["tease", 1.5], ["laugh", 1.5], ["champ", 1], ["-", 1.2]],
  think: [["think", 1.5], ["confused", 1], ["laugh", 1], ["cool", 1], ["-", 2]],
  peek: [["peek", 2], ["laugh", 1.5], ["hi", 1.5], ["wow", 1], ["-", 1.5]],
  // the generic fallback, also when an answer is not in an owned pack
  other: [["laugh", 2], ["happy", 2], ["cool", 1.5], ["love", 1], ["hi", 1], ["-", 1.5]],
  // game events
  capture: [["laugh", 3], ["cool", 3], ["tease", 3], ["champ", 2], ["crown", 2], ["party", 1], ["highfive", 1], ["happy", 1], ["-", 2]],
  captured: [["angry", 3], ["sob", 2], ["cry", 2], ["sad", 2], ["gasp", 2], ["wow", 1], ["confused", 1], ["facepalm", 2], ["laugh", 1], ["-", 2]],
  six: [["party", 2], ["cool", 2], ["happy", 2], ["cheer", 2], ["dice", 2], ["wow", 1], ["-", 3]],
  finish: [["party", 2], ["happy", 2], ["love", 1], ["cheer", 2], ["crown", 2], ["champ", 2], ["highfive", 1], ["-", 1]],
  // a sad person: beaten by this ghost (cheeky or friendly answer) or just sad
  sadCheeky: [["cool", 2], ["tease", 2], ["laugh", 2], ["crown", 0.7], ["champ", 0.7], ["-", 1]],
  sadFriendly: [["love", 2], ["hi", 1.5], ["happy", 0.8], ["highfive", 0.5], ["confused", 0.4], ["-", 1.2]],
  // "ok, enough" at the end of spam
  enough: [["facepalm", 3], ["sleepy", 2]],
};
for (const k of ["cry", "sad", "sob"]) POOLS[k] = POOLS.sadFriendly;
POOLS.cheer = POOLS.highfive;
POOLS.champ = POOLS.crown;
POOLS.gasp = POOLS.wow;

const WINNING = new Set(["cool", "tease", "crown", "laugh", "champ", "party"]);
const LOSING = new Set(["cry", "sad", "facepalm", "sob", "flag"]);
const GLOAT = new Set(["tease", "laugh", "cool", "champ", "crown"]);
const SULK = new Set(["angry", "cry", "facepalm", "sob"]);
const SOFT = new Set(["love", "happy", "hi"]);
const SAD_IN = new Set(["cry", "sad", "sob"]);

const span = (r: readonly [number, number] | readonly number[], rng: Rng): number => r[0] + rng.randf() * (r[1] - r[0]);

/** Weighted distribution of `personas` over a match: 1 ghost: random, several: all different (while personas last). */
export function ghostPersonas(n: number, rng: Rng): Persona[] {
  const w: Record<Persona, number> = { chatty: 0.2, quiet: 0.25, cheeky: 0.2, friendly: 0.2, sore: 0.15 };
  const left: Persona[] = [...PERSONAS];
  const out: Persona[] = [];
  for (let k = 0; k < n; k++) {
    if (!left.length) left.push(...PERSONAS);
    const total = left.reduce((a, p) => a + w[p], 0);
    let x = rng.randf() * total;
    let at = 0;
    for (; at < left.length - 1; at++) {
      x -= w[left[at]];
      if (x < 0) break;
    }
    out.push(left.splice(at, 1)[0]);
  }
  return out;
}

/**
 * Progress lead (-1..1) of colour c over the average of the other `colours`, as fractions of a full race.
 * Ludo: sum of token progress over 4 x 56; Snakes & Ladders: square / 100. 0 when unknown.
 */
export function progressLead(state: unknown, c: number, colours: readonly number[]): number {
  const s = state as { tok?: number[][]; players?: Array<{ c: number; pos: number }> };
  const frac = (col: number): number => {
    if (s.tok?.[col]) return s.tok[col].reduce((a, p) => a + Math.max(0, p + 1), 0) / (4 * (GOAL + 1));
    const p = s.players?.find((x) => x.c === col);
    return p ? p.pos / 100 : 0;
  };
  const others = colours.filter((x) => x !== c);
  if (!others.length) return 0;
  return frac(c) - others.reduce((a, x) => a + frac(x), 0) / others.length;
}

/** Index of the spam table for the current heat: 0 = first emote. */
const heatIndex = (heat: number): number => Math.min(HEAT_CHANCE.length - 1, Math.max(0, Math.ceil(heat - 1e-9) - 1));

/** The weighted pool of answers for this trigger, restricted to `owned`, minus the ghost's last 3. */
export function ghostPool(trigger: GhostTrigger, persona: Persona, mem: GhostMemory, sit: GhostSituation, owned: ReadonlySet<string>, rng: Rng): Array<[string, number]> {
  const def = PERSONA_DEFS[persona];
  const k = sit.scale ?? 1;
  const lead = sit.lead ?? 0;
  const winning = lead > 0.08;
  const losing = lead < -0.08;
  const gloat = mem.capAt > 0 && sit.now - mem.capAt < GHOST_EMOTE.recent * k;
  const hit = mem.hitAt > 0 && sit.now - mem.hitAt < GHOST_EMOTE.recent * k;
  let base: Pool;
  if (trigger.kind === "emote") {
    if (SAD_IN.has(trigger.id)) base = gloat ? (rng.randf() < def.cheeky ? POOLS.sadCheeky : POOLS.sadFriendly) : rng.randf() < 0.6 ? POOLS.sadFriendly : POOLS.sadCheeky;
    else base = POOLS[trigger.id] ?? POOLS.other;
  } else if (trigger.kind === "open") base = [["hi", 5], ["happy", 1.5], ["cool", 0.5]];
  else base = POOLS[trigger.kind];
  const weigh = (pool: Pool): Array<[string, number]> => {
    const out: Array<[string, number]> = [];
    for (const [id, w0] of pool) {
      if (id === "-" || !owned.has(id) || mem.last.includes(id)) continue;
      let w = w0 * (def.bias[id] ?? 1);
      if (winning && WINNING.has(id)) w *= 2.2;
      if (winning && LOSING.has(id)) w *= 0.4;
      if (losing && LOSING.has(id)) w *= 2.2;
      if (losing && WINNING.has(id)) w *= 0.4;
      if (gloat && GLOAT.has(id)) w *= 2;
      if (hit && SULK.has(id)) w *= 2.5;
      if (hit && SOFT.has(id)) w *= 0.3;
      out.push([id, w]);
    }
    return out;
  };
  let out = weigh(base);
  if (!out.length) out = weigh(POOLS.other); // fall back within the owned packs
  if (!out.length) return out;
  // "no reply" weight of the base pool, scaled to the (filtered) rest so that it keeps its share
  const none = base.find(([id]) => id === "-")?.[1] ?? 0;
  if (none > 0) {
    const all = base.reduce((a, [id, w]) => a + (id === "-" ? 0 : w), 0);
    const kept = out.reduce((a, [, w]) => a + w, 0);
    out.push(["-", (none / Math.max(all, 1e-9)) * kept]);
  }
  return out;
}

function pickWeighted(items: Array<[string, number]>, rng: Rng): string {
  const total = items.reduce((a, [, w]) => a + w, 0);
  let x = rng.randf() * total;
  for (const [id, w] of items) {
    x -= w;
    if (x < 0) return id;
  }
  return items[items.length - 1][0];
}

/**
 * Decides whether and what a ghost emotes for `trigger`, updating its memory (spam heat, conversations, captures,
 * recents, planned sends). null = nothing. `pack` is the one paid pack it owns besides starter.
 */
export function ghostEmoteReply(sit: GhostSituation, persona: Persona, mem: GhostMemory, trigger: GhostTrigger, rng: Rng, pack = ""): { id: string; delayMs: number } | null {
  const E = GHOST_EMOTE;
  const k = sit.scale ?? 1;
  const now = sit.now;
  const def = PERSONA_DEFS[persona];
  const always = (sit.chance ?? -1) >= 1;
  const gate = (p: number): boolean => always || (sit.chance === undefined ? rng.randf() < p : rng.randf() < p * sit.chance);
  const owned = new Set([...EMOTE_PACKS.starter, ...(EMOTE_PACKS[pack] ?? [])]);
  const reply = (cands: Array<[string, number]>, delayMs: number): { id: string; delayMs: number } | null => {
    const real = cands.filter(([id]) => id !== "-");
    if (!real.length) return null;
    const id = pickWeighted(always ? real : cands, rng); // the test hook leaves out "no reply" too
    if (id === "-") return null;
    const at = now + delayMs;
    // the humans' limits: 1 per 2 s and 6 per 30 s (around the planned time), plus its own pace
    mem.sent = mem.sent.filter((t) => at - t < E.window * k);
    if (mem.sent.length >= E.maxPerWindow) return null;
    if (mem.sent.some((t) => Math.abs(at - t) < Math.max(E.minGap, def.gap) * k)) return null;
    mem.sent.push(at);
    mem.last = [...mem.last, id].slice(-3);
    return { id, delayMs };
  };
  const delay = (own: boolean): number => {
    let d = span(E.delay, rng);
    if (own) d += rng.randf() < E.afterMoveChance ? span(E.afterMove, rng) : span(E.ownExtra, rng);
    return Math.round(d * k);
  };

  switch (trigger.kind) {
    case "capture":
      mem.capAt = now;
      break;
    case "captured":
      mem.hitAt = now;
      break;
    case "open": {
      if (mem.opened) return null;
      mem.opened = true;
      if (sit.chance === 0 || rng.randf() >= def.open) return null; // the greeting is a personality trait: not forced by the test hook
      return reply(ghostPool(trigger, persona, mem, sit, owned, rng), Math.round(span(E.open, rng) * k));
    }
    case "emote": {
      if (!trigger.human) {
        // another ghost: rarely, once per match for each of them
        if (mem.reacted.includes(trigger.from)) return null;
        if (now < mem.quietUntil || !gate(GHOST_TO_GHOST * (persona === "chatty" ? 2 : persona === "quiet" ? 0.3 : 1))) return null;
        mem.reacted.push(trigger.from);
        return reply(ghostPool(trigger, persona, mem, sit, owned, rng), delay(!!sit.ownTurn));
      }
      return humanEmote(trigger);
    }
  }
  // a game event
  if (now < mem.quietUntil) return null;
  if (!gate(EVENT_CHANCE[trigger.kind] * def.event[trigger.kind])) return null;
  return reply(ghostPool(trigger, persona, mem, sit, owned, rng), delay(false));

  function humanEmote(t: Extract<GhostTrigger, { kind: "emote" }>): { id: string; delayMs: number } | null {
    // spam heat: cools by 1 per 30 s, forgotten after 60 s of quiet
    const dt = now - mem.heatAt;
    if (mem.heat === 0 || dt >= E.forget * k) {
      mem.heat = 0;
      mem.sulked = false;
    } else mem.heat = Math.max(0, mem.heat - dt / (E.cool * k));
    mem.heat += 1;
    mem.heatAt = now;
    if (now < mem.quietUntil) return null;
    const idx = heatIndex(mem.heat);
    let enoughMaybe = false;
    if (idx >= HEAT_CHANCE.length - 1 && !mem.sulked && !always) {
      mem.sulked = true;
      mem.quietUntil = now + Math.round(span(E.quiet, rng) * k);
      enoughMaybe = true;
    }
    if (enoughMaybe) {
      // an "ok, enough" now and then, then it goes quiet
      if (rng.randf() < 0.4 * (persona === "sore" ? 1.5 : persona === "quiet" ? 1.2 : persona === "chatty" ? 0.6 : 1)) {
        return reply(weighEnough(), delay(!!sit.ownTurn));
      }
      return null;
    }
    // conversation with this person: ends after 1-3 of its replies, then it ignores the thread for a while
    const key = String(t.from);
    let th: GhostMemory["threads"][string] | undefined = mem.threads[key];
    if (th?.until) {
      if (now < th.until && !always) return null;
      th = undefined; // the ignore time is over: a new conversation
    }
    if (th && now - th.at > E.idle * k) th = undefined;
    if (!th) th = mem.threads[key] = { n: 0, max: 1 + Math.min(2, Math.floor(rng.randf() * 3)), at: now, until: 0 };
    th.at = now;
    const p = always ? 1 : HEAT_CHANCE[idx] * def.reply;
    if (!gate(p)) return null;
    const out = reply(ghostPool(t, persona, mem, sit, owned, rng), delay(!!sit.ownTurn));
    if (out) {
      th.n++;
      if (th.n >= th.max && !always) th.until = now + Math.round(span(E.ignore, rng) * k);
    }
    return out;
  }

  function weighEnough(): Array<[string, number]> {
    return POOLS.enough.filter(([id]) => owned.has(id) && !mem.last.includes(id)).map(([id, w]) => [id, w * (def.bias[id] ?? 1)] as [string, number]);
  }
}
