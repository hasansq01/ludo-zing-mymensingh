// The Room Durable Object: one per room code. Server-authoritative Ludo and Snakes & Ladders over hibernatable
// WebSockets (PROTOCOL.md is the spec). Everything the room needs to resume after hibernation or eviction lives in one
// storage value ("room"), written synchronously with the SQLite-backed KV API after every change; per-socket
// identity lives in the socket attachment. A single alarm covers every timer (turn deadline / bot or ghost action,
// disconnect grace, quick-room auto-start, grant retries, empty-room and stale-room cleanup): schedule() always sets
// it to the earliest due event. Ghost / bot steps due soon after an alarm run in that same wake-up (chain()), with the
// alarm kept armed as the backup.
//
// Two kinds of rooms: friend rooms (POST /v1/rooms, a lobby, a host, rematches) and quick rooms (created by the
// Matchmaker, src/matchmaker.ts: every seat pre-registered, auto-start, no lobby, no rematch). Quick rooms may hold
// ghosts: seats the server plays itself that look exactly like people (src/ghosts.ts). Whether a seat is a ghost is
// stored here only (Member.ghost / Seat.ghost) and is never part of any client message; the admin console sees it.
//
// Play on (PROTOCOL.md "Play on after the first finish"): a match runs past the first finish until the rules end it
// (fewer than two sides left, or no "human" seat left unfinished). The room ends it early with an explicit
// {k: "end"} act (the rules' endGame, which clients apply too) once no real person (a seated, not-left, non-ghost
// member) is left unfinished while one is still there to see the result: quick matches never make people watch
// ghosts. Each seat's grant outcome is fixed when its side is ranked (Match.ranked / Match.away).
import { reservedName } from "./econ";
import { DurableObject } from "cloudflare:workers";
import * as R from "./rules_shim";
import * as SL from "./rules/sl";
import { slStateHash } from "./rules/sl_hash";
import * as D from "./db";
import { accounts, quickStat, type GameKind, type OnlineMatchGrant, type OnlineOutcome } from "./accounts_shim";
import { forfeitEntry, refundEntry, refundReroll, rerollBalance, spendReroll } from "./economy";
import { ECON_V1, tablePayouts } from "./econ/rules";
import { ghostDelay, ghostEmoteReply, ghostPack, ghostPairYes, ghostPersonas, ghostPick, makeGhosts, newGhostMemory, packOfEmote, progressLead, type GhostMemory, type GhostSituation, type GhostTrigger, type Persona } from "./ghosts";
import type { Matchmaker } from "./matchmaker";
import { EVENT_TTL_S, pushAccount, pushConfigured, type PushKind } from "./push";
import type { Pusher } from "./pusher";

export interface Env {
  ROOMS: DurableObjectNamespace<Room>;
  /** Quick-match queues: one Matchmaker per "game:size" (src/matchmaker.ts). */
  MATCHMAKER: DurableObjectNamespace<Matchmaker>;
  /** The push queue (src/pusher.ts; one instance, "pusher"). */
  PUSHER: DurableObjectNamespace<Pusher>;
  /** D1 "ludo-zing-admin" (ADMIN_API.md): rooms / players / matches / events / config. */
  DB: D1Database;
  /** The admin console's static files (server/admin/, served at /admin). */
  ASSETS?: Fetcher;
  /** Admin console password (a secret; locally .dev.vars). Unset: the admin API answers 503. */
  ADMIN_PASSWORD?: string;
  /** Session HMAC key (accounts, ONLINE_V2.md §1; a secret). */
  SESSION_KEY?: string;
  GOOGLE_WEB_CLIENT_ID?: string;
  GOOGLE_WEB_CLIENT_SECRET?: string;
  /** The Firebase service-account JSON (push notifications, NOTIFICATIONS.md; a secret). Unset: push is off. */
  FCM_SERVICE_ACCOUNT?: string;
  /** "1" only under vitest (vitest.config.ts miniflare bindings). Never set in wrangler.jsonc. */
  TEST_MODE?: string;
}

export type { GameKind };

// ---------- constants ----------

export const CODE_ALPHABET = "23456789ABCDEFGHJKMNPQRSTUVWXYZ";
export const CODE_LEN = 6;

export const TIMING = {
  roll: 15_000,
  choose: 20_000,
  pair_ask: 10_000,
  botRollMin: 800,
  botRollMax: 1400,
  botStepMin: 900, // a bot's move / pair answer after its roll (~1 s, so clients can animate the dice)
  botStepMax: 1100,
  grace: 20_000, // disconnect grace: match -> the seat becomes a bot; lobby -> the member is dropped
  lobbyAway: 300_000, // lobby grace when the app said it went to the background (sharing the invite, a call)
  empty: 10 * 60_000, // no connected member for this long -> the room is deleted
  stale: 2 * 60 * 60_000, // no action (or lobby change) for this long -> the room is deleted
};

/**
 * Server-played steps in one wake-up (fewer Durable Object requests; see chain()). After an alarm, while the next step
 * is a ghost's or a bot's and due within `step`, the alarm handler stays awake until then and runs the alarm logic
 * again instead of returning and being woken by another alarm; at most `total` of such waiting per alarm (and
 * `passes` passes), then the alarm takes over again. A ghost "thinking" (4-6 s) is beyond `step`: its alarm plays it.
 */
export const CHAIN = { step: 4_000, total: 8_000, passes: 12 };

/** Quick rooms (ONLINE_V2.md §3). */
export const QUICK = {
  autoStart: 10_000, // start this long after creation even if not every human connected
  overKeep: 2 * 60_000, // a finished quick room is deleted this long after `over`
};

/** Online reward grants (accounts.grantOnlineMatch) are retried this often, this many times. */
const GRANT = { retryMs: 30_000, tries: 5 };

export const LIMITS = { maxMembers: 4, maxMsgBytes: 4096, ratePerSec: 20, maxSockets: 16 };

/** Event pushes (NOTIFICATIONS.md): at most one per member and kind per `everyMs` (a turn push also once per turn). */
export const PUSH = { everyMs: 3 * 60_000 };

/** Ludo playing colours by member count, in join order (PROTOCOL.md "Colours"). */
const SEAT_COLORS: Record<number, number[]> = { 1: [0], 2: [0, 2], 3: [0, 1, 2], 4: [0, 1, 2, 3] };

/** Playing colours for k members: Ludo uses opposite corners for 2; Snakes & Ladders Red, Green, Yellow, Blue. */
export function seatColors(game: GameKind, k: number): number[] {
  if (game === "sl") return [0, 1, 2, 3].slice(0, Math.max(1, k));
  return SEAT_COLORS[Math.max(1, Math.min(4, k))];
}

/** Close codes the server uses after a fatal error or a replaced / closed session. */
export const CLOSE = { fatal: 4000, replaced: 4001, left: 4002, banned: 4003, closed: 4004 };

/** D1 telemetry knobs (ADMIN_API.md "What the Room DO writes"). */
const TELEMETRY = {
  roomDebounce: 5_000, // at most one rooms-row write per room per 5 s (status changes are written at once)
  playerRepeat: 60_000, // a member reconnecting within this of the last players upsert is not written again
  banCache: 60_000, // a pid's ban flag (and an identity lookup) is re-read after this
  readTimeout: 2_000, // a D1 read on the gameplay path (ban check, turn timers) gives up after this
  eventsPerMin: 20, // events written per room object per minute, at most
};

// ---------- persisted shapes ----------

type Status = "lobby" | "playing" | "over";
// The rules states are the GDScript dictionary shapes (snake_case keys); the rules modules own their types.
type LudoState = R.LudoState;
type SlState = SL.SlState;
type AnyState = LudoState | SlState;
type Action = R.Action | SL.SlAction;

interface Member {
  id: number;
  pid: string;
  token: string;
  name: string;
  avatar: string;
  frame: string;
  /** Epoch ms when the disconnect grace runs out (0 = none). */
  graceAt: number;
  /** The account (sessions, ONLINE_V2.md §1); null / missing = none known. */
  account?: string | null;
  /** The account's level (public profile); missing = unknown (shown as 1). */
  level?: number;
  /** Quick rooms: a seat the server plays (never sent to clients). */
  ghost?: boolean;
  /** Ghosts only: the one paid emote pack this ghost "owns" besides starter (never sent). */
  emotePack?: string;
  /** Ghosts only: the hidden emote personality (chosen at seat time, never sent). */
  persona?: Persona;
  /** Ghosts only: what the ghost remembers about the chat (spam heat, conversations, recent emotes); never sent. */
  emo?: GhostMemory;
  /** Event pushes sent to this member (epoch ms per kind) and the turn of the last turn push; never sent. */
  pushed?: { turn?: number; joined?: number; rematch?: number; turnKey?: string };
  /** Quick rooms at a coin table: this person's entry (ECONOMY_V1.md §3); never sent. */
  entry?: string;
  /** Re-roll means (free re-rolls, gems), read at match start and after each use; missing: unknown (no offer). */
  rr?: { free: number; gems: number };
}

interface Seat {
  color: number;
  id: number;
  /** The member's pid (admin stats only; never sent to clients). Missing in matches stored before v1.1. */
  pid?: string;
  name: string;
  avatar: string;
  frame: string;
  /** The member left the match: a bot plays this colour for good. */
  left: boolean;
  account?: string | null;
  level?: number;
  /** Never sent to clients (see the file comment). */
  ghost?: boolean;
  /** Coin tables: the member's entry id (never sent). */
  entry?: string;
}

interface Match {
  /** Missing in matches stored before S&L: Ludo. */
  game?: GameKind;
  seats: Seat[];
  state: AnyState;
  /** Number of actions applied so far (= the index the next action gets). */
  n: number;
  /** Epoch ms of the current step's deadline (human), planned action (bot, ghost); 0 = nothing pending. */
  due: number;
  /** The deadline clients are shown (`turn.deadline`): due, except for a ghost (a human's deadline). */
  shown?: number;
  /** Timeouts in a row per colour. */
  strikes: number[];
  /** Bot / ghost RNG (Mulberry32) state, so bot choices continue across wake-ups. */
  rng: number;
  /** Epoch ms of the start (with the code, identifies the D1 matches row and the grant's match id). */
  startedAt?: number;
  /** Human turn deadlines for this match (ms), from D1 config at start; missing -> TIMING. */
  timers?: TurnTimers;
  /**
   * Colours whose side has been ranked (finished, or ranked at the end), in that order, and those of them that were
   * away then (the seat had left, or a bot played it): their grant is "left". Missing in matches stored before play
   * on (the outcome is then read at `over`, as before).
   */
  ranked?: number[];
  away?: number[];
  /** Ghost emotes planned (alarm-driven, stored so they survive hibernation); never touches state, n or the hash. */
  gemotes?: Array<{ at: number; c: number; id: string }>;
  /** The open re-roll offer after a bad roll (ECONOMY_V1.md §4). Cleared by the next action. */
  rr?: RerollOffer;
  /** Colours that used their re-roll in this match. */
  rrUsed?: number[];
}

interface RerollOffer {
  /** The colour that rolled. */
  c: number;
  /** The action index of the bad roll (the state goes back to it) and m.n after it (the offer is for that state). */
  bn: number;
  n: number;
  /** The state before the bad roll. */
  before: AnyState;
  /** Epoch ms: the offer closes; the next player can't act before. */
  until: number;
  /** A ghost decided to re-roll at this time. */
  ghostAt?: number;
  /** A person's payment is in flight (the hold lasts until it's answered). */
  paying?: boolean;
}

interface TurnTimers {
  roll: number;
  choose: number;
  pair_ask: number;
}

interface Settings {
  teams: boolean;
  pair_ask: boolean;
  /** Missing in rooms stored before S&L: Ludo. */
  game?: GameKind;
}

interface QuickInfo {
  size: number;
  /** The coin table (ECONOMY_V1.md §3); missing: practice (rooms made before Economy v1 too). */
  table?: { tier: string; entry: number };
  /** Epoch ms: start then even if not every human is connected. */
  startBy: number;
  timers?: TurnTimers;
  /** Epoch ms of `over` (0 = not over). */
  overAt: number;
}

interface PendingGrant {
  g: OnlineMatchGrant;
  tries: number;
  next: number;
}

interface RoomData {
  v: 1;
  code: string;
  created: number;
  status: Status;
  host: number; // member id, -1 when the room has no members (always -1 in quick rooms)
  nextId: number;
  members: Member[]; // join order (quick rooms: seat order)
  settings: Settings;
  match: Match | null;
  touched: number; // last action / lobby change (stale cleanup)
  emptySince: number; // 0 while somebody is connected
  alarmAt: number; // the alarm currently set (0 = none)
  /** Quick rooms only. */
  quick?: QuickInfo;
  /** Online reward grants not yet confirmed by the accounts module. */
  grants?: PendingGrant[];
  /** Signature of the rooms-row fields last queued for D1, and the status they had (see commit()). */
  dbSig?: string;
  dbStatus?: Status;
  /** Whether the rows last queued for D1 had nobody online (see commit()). */
  dbIdle?: boolean;
}

/** Test-only knobs. Honoured only when env.TEST_MODE === "1" (vitest); set through testHooks() via RPC. */
export interface TestHooks {
  /** Dice values used, in order, before falling back to random rolls. */
  dice?: number[];
  /** Ludo: token progress per colour applied to the state at `start` (to make games short). */
  tok?: number[][];
  /** S&L: starting square per player (turn order) applied at `start`. */
  slPos?: number[];
  /** Multiplies every duration in TIMING / QUICK / ghost delays (e.g. 0.01 makes a 20 s grace 200 ms). */
  timeScale?: number;
  /** Replaces LIMITS.ratePerSec (test clients play far faster than people tap). */
  ratePerSec?: number;
  /** Replaces the ghosts' 25% chance of reacting to an event (1 = always, 0 = never). */
  emoteChance?: number;
  /** false: every ghost / bot step waits for an alarm of its own (no chain(); the old behaviour, for measurements). */
  chain?: boolean;
  /** Replaces ECON_V1.ghost_reroll_chance (1 = a ghost always re-rolls a bad roll, 0 = never). */
  rerollChance?: number;
}

/**
 * Test-only counters (TEST_MODE, in memory): alarm() invocations, the alarm passes chain() ran in-request, and the
 * longest in-request wait of one alarm (ms).
 */
export interface TestStats {
  alarms: number;
  chained: number;
  longest: number;
}

/** What the Matchmaker hands a new quick room. */
export interface QuickSpec {
  game: GameKind;
  size: number;
  /** The coin table (ECONOMY_V1.md §3); missing: practice. */
  table?: { tier: string; entry: number };
  humans: Array<{ account_id: string; pid: string; name: string; avatar: string; frame: string; level: number; entry_id?: string }>;
  /** Tests only (TEST_MODE). */
  hooks?: TestHooks;
}

interface Att {
  /** Member id; -1 before hello, -2 for a socket the server is closing (replaced / left). */
  mid: number;
  /** The client said its app is in the background ({t: "away", on: true}); pushes only. */
  away?: boolean;
}

interface Identity {
  account: string | null;
  ban: string | null;
  level: number | null;
}

// ---------- the two games behind one interface ----------

interface GameOps {
  hash(s: AnyState): string;
  apply(s: AnyState, a: Action): unknown[];
  /** The colour whose turn it is. */
  turnColor(s: AnyState): number;
  /** Colour c is played by a (labelled) bot. */
  isCpu(s: AnyState, c: number): boolean;
  phase(s: AnyState): string;
  winners(s: AnyState): number[];
  /** The finish order (colours); at `over` the full final order. */
  finished(s: AnyState): number[];
  /** Colours whose side has its place now (Ludo Teams: only at the end, the team finishing ends the game). */
  ranked(s: AnyState): number[];
  /** Playing colours whose side has not finished yet. */
  unfinished(s: AnyState): number[];
  winner(s: AnyState): number;
  standings(s: AnyState): unknown[];
}

const LUDO: GameOps = {
  hash: (s) => R.stateHash(s as LudoState),
  apply: (s, a) => R.applyAction(s as LudoState, a as R.Action),
  turnColor: (s) => (s as LudoState).turn,
  isCpu: (s, c) => (s as LudoState).players[c] === "cpu",
  phase: (s) => (s as LudoState).phase,
  winners: (s) => R.winners(s as LudoState),
  finished: (s) => [...((s as LudoState).finished ?? [])],
  ranked: (s) => {
    const ls = s as LudoState;
    return ls.phase === "over" || !ls.teams ? [...(ls.finished ?? [])] : [];
  },
  unfinished: (s) => {
    const ls = s as LudoState;
    if (ls.phase === "over") return [];
    return [0, 1, 2, 3].filter((c) => ls.players[c] !== "off" && !R.sideDone(ls, c));
  },
  winner: (s) => (s as LudoState).winner,
  standings: (s) => R.standings(s as LudoState),
};

function slWinnerColor(g: SlState): number {
  return g.winner >= 0 && g.players[g.winner] ? g.players[g.winner].c : -1;
}

/** The S&L finish order as colours (the rules keep player indices). */
function slFinishedColors(g: SlState): number[] {
  return SL.finishedOf(g)
    .filter((k) => g.players[k])
    .map((k) => g.players[k].c);
}

const SNAKES: GameOps = {
  hash: (s) => slStateHash(s as SlState),
  apply: (s, a) => SL.applySlAction(s as SlState, a as SL.SlAction),
  turnColor: (s) => SL.turnColor(s as SlState),
  isCpu: (s, c) => (s as SlState).players.some((p) => p.c === c && p.cpu),
  phase: (s) => (s as SlState).phase,
  winners: (s) => (slWinnerColor(s as SlState) >= 0 ? [slWinnerColor(s as SlState)] : []),
  finished: (s) => slFinishedColors(s as SlState),
  ranked: (s) => slFinishedColors(s as SlState),
  unfinished: (s) => {
    const g = s as SlState;
    if (g.phase === "over") return [];
    const fin = SL.finishedOf(g);
    return g.players.filter((_p, k) => !fin.includes(k)).map((p) => p.c);
  },
  winner: (s) => slWinnerColor(s as SlState),
  standings: (s) => SL.standings(s as SlState),
};

function opsFor(game: GameKind | undefined): GameOps {
  return game === "sl" ? SNAKES : LUDO;
}

export function isGame(x: unknown): x is GameKind {
  return x === "ludo" || x === "sl";
}

// ---------- helpers ----------

function randomBytes(n: number): Uint8Array {
  const b = new Uint8Array(n);
  crypto.getRandomValues(b);
  return b;
}

/** A uniform int in [0, n) from crypto randomness (rejection sampling, n <= 256). */
function cryptoInt(n: number): number {
  const lim = 256 - (256 % n);
  for (;;) {
    const b = randomBytes(1)[0];
    if (b < lim) return b % n;
  }
}

export function randomCode(): string {
  let s = "";
  for (let k = 0; k < CODE_LEN; k++) s += CODE_ALPHABET[cryptoInt(CODE_ALPHABET.length)];
  return s;
}

export function isCode(s: string): boolean {
  return s.length === CODE_LEN && [...s].every((ch) => CODE_ALPHABET.includes(ch));
}

function randomToken(): string {
  return [...randomBytes(18)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function randomSeed(): number {
  return new DataView(randomBytes(4).buffer).getUint32(0);
}

function rollDie(): number {
  return cryptoInt(6) + 1;
}

/** Names: control characters stripped, trimmed, at most 16 characters (code points); empty -> "Player". */
export function cleanName(x: unknown): string {
  if (typeof x !== "string") return "Player";
  // eslint-disable-next-line no-control-regex
  const t = x.replace(/[\u0000-\u001f\u007f-\u009f\u2028\u2029]/g, "").trim();
  const cut = Array.from(t).slice(0, 16).join("").trim();
  return cut && !reservedName(cut) ? cut : "Player";
}


/** Catalog ids (avatar, frame): strings of at most 32 safe characters, else "". */
export function cleanId(x: unknown): string {
  return typeof x === "string" && x.length <= 32 && /^[A-Za-z0-9_.:-]*$/.test(x) ? x : "";
}

export const PID_RE = /^[A-Za-z0-9_-]{16,64}$/;

/** A session token as sent in hello (opaque here; accounts.verifySession checks it). */
export function isSessionShape(x: unknown): x is string {
  return typeof x === "string" && x.length > 0 && x.length <= 512;
}

/**
 * A roll that a re-roll can undo (ECONOMY_V1.md §4): Ludo, the roll ended the turn without a move (need a 6, or stuck
 * on a non-6); Snakes & Ladders, it ended on a snake.
 */
export function badRoll(game: GameKind, ev: Array<{ type: string; v?: number; snake?: boolean }>): boolean {
  if (game === "sl") return ev.some((e) => e.type === "move" && e.snake === true);
  if (ev.some((e) => e.type === "three_sixes")) return false;
  if (ev.some((e) => e.type === "need_six")) return true;
  const rolled = ev.find((e) => e.type === "rolled");
  return ev.some((e) => e.type === "stuck") && rolled?.v !== 6;
}

function isInt(x: unknown, lo: number, hi: number): x is number {
  return typeof x === "number" && Number.isInteger(x) && x >= lo && x <= hi;
}

// ---------- the Durable Object ----------

export class Room extends DurableObject<Env> {
  private room: RoomData | null;
  private hooks: TestHooks = {};
  private stats: TestStats = { alarms: 0, chained: 0, longest: 0 };
  private rate = new WeakMap<WebSocket, { start: number; count: number; warned: boolean }>();
  /** Per-socket message queue: a message waits for the previous one's async part (ban check, timers read). */
  private queue = new WeakMap<WebSocket, Promise<void>>();
  // D1 telemetry (in memory only: lost on eviction, which at worst costs one extra or one missed write)
  private dbChain: Promise<void> = Promise.resolve();
  private roomWriteAt = 0;
  private roomTimer = false;
  private roomDirty = false;
  private playerSeenAt = new Map<string, number>();
  private banCache = new Map<string, { at: number; banned: boolean; reason: string }>();
  private idCache = new Map<string, { at: number; id: Identity }>();
  private eventWindow = { start: 0, count: 0 };
  private reported = new WeakSet<object>();
  private granting = false;
  // emotes (in memory: a miss after eviction only means one extra D1 read / a looser window)
  private emoSets = new Map<number, string[]>();
  private emoSent = new Map<number, number[]>();
  private emoLocked = new Map<string, number>();
  private emoWindow = new WeakMap<WebSocket, { start: number; count: number }>();

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair('{"t":"ping"}', '{"t":"pong"}')); // keep-alives never wake the DO
    this.room = ctx.storage.kv.get<RoomData>("room") ?? null;
    if (env.TEST_MODE === "1") this.hooks = ctx.storage.kv.get<TestHooks>("hooks") ?? {};
  }

  private get game(): GameKind {
    return this.room?.match?.game ?? this.room?.settings.game ?? "ludo";
  }

  private get ops(): GameOps {
    return opsFor(this.game);
  }

  // ----- RPC from the Worker -----

  /** Reserves this room (POST /v1/rooms). False when the code is already in use. */
  async init(code: string): Promise<boolean> {
    if (this.room) return false;
    const now = Date.now();
    this.room = {
      v: 1,
      code,
      created: now,
      status: "lobby",
      host: -1,
      nextId: 1,
      members: [],
      settings: { teams: false, pair_ask: false, game: "ludo" },
      match: null,
      touched: now,
      emptySince: now, // nobody connected yet: a code nobody joins is dropped after TIMING.empty
      alarmAt: 0,
    };
    this.commit();
    return true;
  }

  /**
   * Creates this room as a quick room (Matchmaker): the humans are pre-registered (seated even though the room is
   * closed to strangers), the other seats get ghosts, seats are shuffled. Returns each human's room token (by
   * account), or null when the code is already in use.
   */
  async initQuick(code: string, spec: QuickSpec): Promise<{ tokens: Record<string, string> } | null> {
    if (this.room) return null;
    if (this.env.TEST_MODE === "1" && spec.hooks) {
      this.hooks = { ...spec.hooks, dice: spec.hooks.dice ? [...spec.hooks.dice] : undefined };
      this.ctx.storage.kv.put("hooks", this.hooks);
    }
    const timers = await this.turnTimers();
    if (this.room) return null;
    const now = Date.now();
    const size = Math.max(2, Math.min(4, spec.size));
    const humans = spec.humans.slice(0, size);
    const g = new R.Mulberry32(randomSeed());
    const ghosts = makeGhosts(size - humans.length, humans, g);
    const personas = ghostPersonas(ghosts.length, g);
    const entries: Array<Omit<Member, "id">> = [
      ...humans.map((h) => ({
        pid: h.pid,
        token: randomToken(),
        name: cleanName(h.name),
        avatar: cleanId(h.avatar),
        frame: cleanId(h.frame),
        graceAt: 0,
        account: h.account_id,
        level: Math.max(1, Math.trunc(h.level) || 1),
        ...(h.entry_id ? { entry: h.entry_id } : {}),
      })),
      ...ghosts.map((gh, k) => ({ pid: "", token: "", name: gh.name, avatar: gh.avatar, frame: gh.frame, graceAt: 0, account: null, level: gh.level, ghost: true, emotePack: ghostPack(g), persona: personas[k], emo: newGhostMemory() })),
    ];
    for (let k = entries.length - 1; k > 0; k--) {
      const j = cryptoInt(k + 1);
      [entries[k], entries[j]] = [entries[j], entries[k]];
    }
    const members: Member[] = entries.map((e, j) => ({ id: j + 1, ...e }));
    this.room = {
      v: 1,
      code,
      created: now,
      status: "lobby",
      host: -1,
      nextId: members.length + 1,
      members,
      settings: { teams: false, pair_ask: false, game: spec.game },
      match: null,
      touched: now,
      emptySince: now,
      alarmAt: 0,
      quick: { size, startBy: now + this.ms(QUICK.autoStart), timers, overAt: 0, table: spec.table ?? { tier: "practice", entry: 0 } },
    };
    this.commit();
    const tokens: Record<string, string> = {};
    for (const m of members) if (!m.ghost && m.account) tokens[m.account] = m.token;
    return { tokens };
  }

  /** GET /v1/rooms/<CODE>; null when the room doesn't exist. */
  async info(): Promise<{ code: string; open: boolean; members: number; started: boolean } | null> {
    const r = this.room;
    if (!r) return null;
    return {
      code: r.code,
      open: !r.quick && r.status !== "playing" && r.members.length < LIMITS.maxMembers,
      members: r.members.length,
      started: r.status === "playing",
    };
  }

  /** Tests only: throws unless env.TEST_MODE is "1" (it is never set in wrangler.jsonc, and no route calls this). */
  async testHooks(h: TestHooks): Promise<void> {
    if (this.env.TEST_MODE !== "1") throw new Error("test hooks are disabled");
    this.hooks = { ...h, dice: h.dice ? [...h.dice] : undefined };
    this.ctx.storage.kv.put("hooks", this.hooks);
    this.commit(); // re-plan the alarm with the new time scale
  }

  /** Tests only: the alarm counters (TestStats). */
  async testStats(): Promise<TestStats> {
    if (this.env.TEST_MODE !== "1") throw new Error("test hooks are disabled");
    return { ...this.stats };
  }

  // ----- RPC from the admin API (src/admin.ts; no public route reaches these) -----

  /** The live room for the console; null when the room doesn't exist. The console is the only place ghosts show. */
  async adminSnapshot(): Promise<AdminSnapshot | null> {
    const r = this.room;
    if (!r) return null;
    const m = r.match;
    const colors = seatColors(this.game, r.members.length);
    const seatsOut = m ? this.seatsOut() : [];
    return {
      code: r.code,
      status: r.status,
      host: r.host,
      created: r.created,
      touched: r.touched,
      sockets: this.sockets().length,
      game: this.game,
      quick: !!r.quick,
      members: r.members.map((mm, j) => ({
        id: mm.id,
        pid: mm.pid,
        name: mm.name,
        avatar: mm.avatar,
        frame: mm.frame,
        online: this.memberOnline(mm),
        color:
          r.status === "playing" && m ? (m.seats.find((st) => st.id === mm.id && !st.left)?.color ?? -1) : colors[j],
        account: mm.account ?? undefined,
        level: mm.level,
        ghost: mm.ghost ? true : undefined,
        persona: mm.ghost ? mm.persona : undefined,
      })),
      settings: { teams: r.settings.teams, pair_ask: r.settings.pair_ask },
      match: m
        ? {
            n: m.n,
            game: m.game ?? "ludo",
            state: m.state,
            seats: m.seats.map((st, k) => ({
              ...seatsOut[k],
              pid: this.seatPid(st),
              left: st.left,
              account: st.account ?? undefined,
              ghost: st.ghost ? true : undefined,
            })),
            deadline: r.status === "playing" ? Math.round(m.shown || m.due) : 0,
            started_at: m.startedAt ?? 0,
          }
        : null,
    };
  }

  /**
   * The daily cron's sweep of rooms rows that look stale: re-runs the timers (as the alarm would), then deletes the
   * room if no person is connected (ghosts don't count), recording a running match as "abandoned" (reason
   * "stale-sweep"). "gone": no such room (or the timers deleted it); "live": someone is connected; "swept": deleted.
   */
  async sweepStale(): Promise<"gone" | "live" | "swept"> {
    if (!this.room) return "gone";
    await this.onAlarm();
    const r = this.room;
    if (!r) return "gone";
    if (r.members.some((m) => !m.ghost && this.online(m.id))) return "live";
    await this.destroy("stale-sweep", "abandoned");
    return "swept";
  }

  /** Admin close: every socket gets error not_found + close 4004, the storage is deleted. False if no room. */
  async adminClose(reason: string): Promise<boolean> {
    if (!this.room) return false;
    await this.destroy(reason || "admin", "closed");
    return true;
  }

  /** Admin kick of one member (lobby: removed; match: the seat is a bot for good). False if no such member. */
  async adminKick(memberId: number): Promise<boolean> {
    const mem = this.room?.members.find((m) => m.id === memberId);
    if (!mem || mem.ghost) return false;
    this.expel(mem, CLOSE.left, "kicked", "you were removed from the room");
    this.commit();
    await this.settle();
    return true;
  }

  /** A pid was banned: remember it (no rejoin) and remove that member if present. True if they were here. */
  async adminBan(pid: string, reason: string): Promise<boolean> {
    this.banCache.set(pid, { at: Date.now(), banned: true, reason });
    this.idCache.clear();
    const mem = pid ? this.room?.members.find((m) => m.pid === pid && !m.ghost) : undefined;
    if (!mem) return false;
    this.expel(mem, CLOSE.banned, "banned", banMsg(reason));
    this.commit();
    await this.settle();
    return true;
  }

  /** A pid was unbanned: forget the cached flag. */
  async adminUnban(pid: string): Promise<void> {
    this.banCache.delete(pid);
    this.idCache.clear();
  }

  /** An account was banned: remove that member if present. True if they were here. */
  async adminBanAccount(account: string, reason: string): Promise<boolean> {
    this.idCache.clear();
    const mem = account ? this.room?.members.find((m) => m.account === account && !m.ghost) : undefined;
    if (!mem) return false;
    this.expel(mem, CLOSE.banned, "banned", banMsg(reason));
    this.commit();
    await this.settle();
    return true;
  }

  /** An account was unbanned: forget cached identities. */
  async adminUnbanAccount(_account: string): Promise<void> {
    this.idCache.clear();
  }

  // ----- WebSocket upgrade -----

  async fetch(req: Request): Promise<Response> {
    if (!this.room) return Response.json({ error: "not_found" }, { status: 404 });
    if (req.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
      return new Response("expected a websocket upgrade", { status: 426 });
    }
    if (this.ctx.getWebSockets().length >= LIMITS.maxSockets) {
      return Response.json({ error: "busy" }, { status: 503 });
    }
    const pair = new WebSocketPair();
    const [client, server] = [pair[0], pair[1]];
    this.ctx.acceptWebSocket(server);
    server.serializeAttachment({ mid: -1 } satisfies Att);
    return new Response(null, { status: 101, webSocket: client });
  }

  // ----- hibernatable WebSocket handlers -----

  async webSocketMessage(ws: WebSocket, data: string | ArrayBuffer): Promise<void> {
    // Messages of one socket are handled in order. Most handling is synchronous (the queue is then a no-op); a hello
    // (ban / session check) or a start (turn timers) awaits a D1 read, and that socket's next messages wait for it.
    const prev = this.queue.get(ws);
    const run = (prev ? prev.then(() => this.onMessage(ws, data)) : this.onMessage(ws, data)).catch((e) => {
      this.crashed("message", e);
      throw e;
    });
    const tail = run.catch(() => {});
    this.queue.set(ws, tail);
    try {
      await run;
    } finally {
      if (this.queue.get(ws) === tail) this.queue.delete(ws);
    }
  }

  private async onMessage(ws: WebSocket, data: string | ArrayBuffer): Promise<void> {
    const r = this.room;
    if (!r) {
      this.fatal(ws, "not_found", "this room no longer exists");
      return;
    }
    if (!this.allow(ws)) return;
    if (typeof data !== "string") return this.error(ws, "bad_message", "text frames only");
    if (data.length > LIMITS.maxMsgBytes || new TextEncoder().encode(data).length > LIMITS.maxMsgBytes) {
      return this.error(ws, "bad_message", "message too large");
    }
    let msg: Record<string, unknown>;
    try {
      msg = JSON.parse(data);
    } catch {
      return this.error(ws, "bad_message", "not JSON");
    }
    if (!msg || typeof msg !== "object" || Array.isArray(msg) || typeof msg.t !== "string") {
      return this.error(ws, "bad_message", "expected an object with a string t");
    }
    if (msg.t === "ping") /* other ping shapes (the exact one is auto-answered) */ return this.send(ws, { t: "pong", now: Date.now() });
    if (msg.t === "emote") this.refundEmote(ws);

    const att = this.att(ws);
    if (att.mid === -2) return;
    if (msg.t === "away" && att.mid < 0) return; // nobody to mark yet
    if (att.mid < 0) {
      if (msg.t !== "hello") return this.error(ws, "bad_message", "say hello first");
      let who: Identity = { account: null, ban: null, level: null };
      if (msg.v === 1 && typeof msg.pid === "string" && PID_RE.test(msg.pid)) {
        who = await this.identify(msg.pid, msg.session);
        if (ws.readyState !== 1 || this.att(ws).mid !== -1) return; // closed (or replaced) meanwhile
        if (!this.room) return this.fatal(ws, "not_found", "this room no longer exists");
        if (who.ban) {
          this.event("warn", "banned", `banned player refused: ${who.ban}`.slice(0, 200), msg.pid);
          this.error(ws, "banned", banMsg(who.ban));
          this.closeWith(ws, CLOSE.banned, "banned");
          return;
        }
      }
      this.hello(ws, msg, who);
      this.commit();
      return;
    }
    let mem = r.members.find((m) => m.id === att.mid);
    if (!mem) {
      if (msg.t === "away") return; // ignored for unknown members (NOTIFICATIONS.md)
      // removed while this socket stayed open (left from another socket, dropped from the lobby)
      this.fatal(ws, "not_found", "you are no longer in this room");
      return;
    }
    switch (msg.t) {
      case "hello":
        return this.error(ws, "bad_message", "already said hello");
      case "settings":
        this.settings(ws, mem, msg);
        break;
      case "start": {
        let timers: TurnTimers | undefined;
        if (this.startError(mem) === null) {
          timers = await this.turnTimers(); // read at every match start: config changes apply to the next match
          const rr = this.room;
          mem = rr?.members.find((m) => m.id === att.mid);
          if (!rr || !mem) return;
        }
        this.start(ws, mem, timers);
        break;
      }
      case "roll":
      case "move":
      case "pair":
        this.play(ws, mem, msg);
        break;
      case "back":
        this.back(mem);
        break;
      case "reroll":
        await this.reroll(ws, mem, msg);
        break;
      case "sync_req":
        this.sendSnapshot(ws);
        break;
      case "emote":
        await this.emote(ws, mem, msg);
        return; // emotes never touch the match: nothing to commit or settle
      case "away":
        if (typeof msg.on !== "boolean") return this.error(ws, "bad_message", "on: bool");
        ws.serializeAttachment({ ...att, away: msg.on } satisfies Att);
        return; // only decides event pushes: nothing to commit
      case "leave":
        this.leave(ws, mem);
        break;
      default:
        return this.error(ws, "bad_message", `unknown type ${String(msg.t).slice(0, 20)}`);
    }
    this.commit();
    await this.settle();
  }

  async webSocketClose(ws: WebSocket, code: number, _reason: string, _clean: boolean): Promise<void> {
    try {
      this.dropped(ws);
    } catch (e) {
      this.crashed("close", e);
      throw e;
    }
    try {
      ws.close(code === 1005 || code === 1006 ? 1000 : code, "bye");
    } catch {
      /* already closed */
    }
  }

  async webSocketError(ws: WebSocket, _err: unknown): Promise<void> {
    try {
      this.dropped(ws);
    } catch (e) {
      this.crashed("socket_error", e);
      throw e;
    }
  }

  // ----- the alarm: every timer -----

  async alarm(): Promise<void> {
    try {
      this.stats.alarms++;
      await this.onAlarm();
      await this.chain();
    } catch (e) {
      this.crashed("alarm", e);
      throw e;
    }
  }

  private async onAlarm(): Promise<void> {
    const r = this.room;
    if (!r) return;
    r.alarmAt = 0;
    const now = Date.now();
    if (now >= r.touched + this.ms(TIMING.stale)) {
      await this.destroy("stale", "abandoned");
      return;
    }
    if (r.emptySince && now >= r.emptySince + this.ms(TIMING.empty)) {
      await this.destroy("empty", "abandoned");
      return;
    }
    const q = r.quick;
    if (q && r.status === "lobby" && now >= q.startBy) {
      if (!this.startQuick()) {
        await this.destroy("no_show", "abandoned"); // nobody came
        return;
      }
    }
    if (q && r.status === "over" && q.overAt && now >= q.overAt + this.ms(QUICK.overKeep)) {
      await this.destroy("done", "over");
      return;
    }
    for (const mem of [...r.members]) {
      if (!mem.graceAt) continue;
      if (this.online(mem.id)) mem.graceAt = 0;
      else if (mem.graceAt <= now) this.graceOver(mem);
    }
    const m = r.match;
    if (r.status === "playing" && m?.rr?.ghostAt && m.rr.ghostAt <= now && m.n === m.rr.n) this.doReroll(m, m.rr, "free");
    if (r.status === "playing" && m?.rr?.paying && m.due && m.due <= now) m.due = now + 300; // wait for the payment
    else if (r.status === "playing" && m && m.due && m.due <= now) this.step();
    this.flushGhostEmotes(now);
    if (r.grants?.some((g) => g.next <= now)) this.ctx.waitUntil(this.runGrants());
    this.commit();
    await this.settle();
  }

  /**
   * After an alarm pass: while the next step is server-played (a ghost, or a bot) and due soon (CHAIN), wait for it
   * in this request and run the alarm pass again, instead of a second alarm (a ghost's roll and its move in one
   * wake-up; a 6 or the next ghost's turn chained too). Nothing visible changes: planStep() drew the delay exactly as
   * before and announced the turn; the pass plays the step as the alarm would (same rules, same persisted RNG), at the
   * same time. Ghost emotes and other timers due on the way are handled by the passes (the wake-up is the alarm's
   * time, the earliest of them). Safety: commit() keeps the alarm armed at the planned time throughout, so after an
   * eviction mid-wait the alarm plays the step as before, and once the waited pass played it the alarm finds nothing
   * due. The wait is dropped (the alarm takes over) when anything moved meanwhile: the room or match object, the
   * status, the action count n (a mode change, {k: "end"}, ...) or the step's planned time (re-planned).
   */
  private async chain(): Promise<void> {
    if (this.env.TEST_MODE === "1" && this.hooks.chain === false) return;
    const start = Date.now();
    for (let pass = 0; pass < CHAIN.passes; pass++) {
      const r = this.room;
      const m = r?.match;
      if (!r || r.status !== "playing" || !m || !m.due) return;
      const O = this.ops;
      const c = O.turnColor(m.state);
      if (!O.isCpu(m.state, c) && !this.seatOfColor(c)?.ghost) return; // a person's deadline: the alarm's
      const now = Date.now();
      const toStep = m.due - now;
      if (toStep > this.ms(CHAIN.step) || now + toStep - start > this.ms(CHAIN.total)) return;
      const { n, due } = m;
      const wake = r.alarmAt > 0 ? Math.min(r.alarmAt, due) : due;
      await new Promise((res) => setTimeout(res, Math.max(1, wake - now)));
      if (this.room !== r || r.status !== "playing" || r.match !== m || m.n !== n || m.due !== due) return;
      this.stats.chained++;
      this.stats.longest = Math.max(this.stats.longest, Date.now() - start);
      await this.onAlarm();
    }
  }

  // ---------- connection handling ----------

  private hello(ws: WebSocket, msg: Record<string, unknown>, who: Identity): void {
    const r = this.room!;
    if (msg.v !== 1) return this.fatal(ws, "version", "unsupported protocol version");
    if (typeof msg.pid !== "string" || !PID_RE.test(msg.pid)) {
      return this.fatal(ws, "bad_message", "pid must be 16-64 characters of [A-Za-z0-9_-]");
    }
    const pid = msg.pid;
    const name = cleanName(msg.name);
    const avatar = cleanId(msg.avatar);
    const frame = cleanId(msg.frame);
    const token = typeof msg.token === "string" ? msg.token : "";
    const humans = r.members.filter((m) => !m.ghost);
    let mem =
      (token && humans.find((m) => m.token === token)) ||
      (who.account && humans.find((m) => m.account === who.account)) ||
      humans.find((m) => m.pid === pid);
    const now = Date.now();
    const fresh = !mem;
    if (mem) {
      // the same member again: this socket replaces any older one
      for (const other of this.socketsOf(mem.id)) {
        if (other === ws) continue;
        other.serializeAttachment({ mid: -2 } satisfies Att);
        try {
          other.close(CLOSE.replaced, "replaced");
        } catch {
          /* gone */
        }
      }
      if (!r.quick) {
        // quick rooms keep the identity sent to the queue (ghost names were chosen not to clash with it)
        mem.name = name;
        mem.avatar = avatar;
        mem.frame = frame;
      }
      if (who.account && !mem.account) mem.account = who.account;
      if (who.level !== null) mem.level = who.level;
      mem.graceAt = 0;
      this.playerSeen(mem, r.quick ? !this.playerSeenAt.has(mem.pid) : false);
    } else {
      if (r.quick) return this.fatal(ws, "full", "the room is full");
      if (r.status === "playing") return this.fatal(ws, "started", "the match is in progress");
      if (r.members.length >= LIMITS.maxMembers) return this.fatal(ws, "full", "the room is full");
      mem = { id: r.nextId++, pid, token: randomToken(), name, avatar, frame, graceAt: 0, account: who.account };
      if (who.level !== null) mem.level = who.level;
      r.members.push(mem);
      if (r.host < 0) r.host = mem.id;
      r.touched = now;
      this.playerSeen(mem, true);
    }
    this.emoSets.delete(mem.id); // the account's packs are read again (a reconnect, or another account taking the seat)
    ws.serializeAttachment({ mid: mem.id } satisfies Att);
    r.emptySince = 0;
    this.send(ws, { t: "welcome", token: mem.token, id: mem.id, code: r.code, host: r.host });

    const m = r.match;
    if (r.status === "playing" && m) {
      const seat = m.seats.find((st) => st.id === mem.id && !st.left);
      this.broadcast({ t: "presence", id: mem.id, online: true }, ws);
      this.sendSnapshot(ws);
      const s = m.state;
      if (seat && this.ops.isCpu(s, seat.color)) {
        m.strikes[seat.color] = 0;
        this.act({ k: "mode", c: seat.color, mode: "human" });
        if (this.ops.turnColor(s) === seat.color || !m.due) this.planStep();
      } else if (!m.due) {
        this.planStep(); // bots were paused while nobody was online
      }
    } else if (r.quick) {
      if (r.status === "over" && m) this.sendSnapshot(ws);
      else if (r.status === "lobby" && humans.every((h) => this.online(h.id))) this.startQuick();
    } else {
      if (r.status === "over" && m) this.sendSnapshot(ws);
      this.broadcast(this.lobbyMsg());
      const host = r.members.find((h) => h.id === r.host);
      if (fresh && host && host !== mem) this.pushTo(host, "joined", "Friend joined", `${mem.name} joined your room ${r.code}`);
    }
  }

  /** A socket closed or errored. */
  private dropped(ws: WebSocket): void {
    const r = this.room;
    if (!r) return;
    const att = this.att(ws);
    if (att.mid < 0) return;
    const wentAway = att.away === true; // the app said it went to the background, then the phone closed the socket
    try {
      ws.serializeAttachment({ mid: -2 } satisfies Att);
    } catch {
      /* closed */
    }
    const mem = r.members.find((m) => m.id === att.mid);
    if (mem && !this.online(mem.id, ws)) {
      const now = Date.now();
      if (r.status === "playing") {
        mem.graceAt = now + this.ms(TIMING.grace);
        this.broadcast({ t: "presence", id: mem.id, online: false }, ws);
      } else if (!r.quick) {
        mem.graceAt = now + this.ms(wentAway ? TIMING.lobbyAway : TIMING.grace);
        this.broadcast(this.lobbyMsg(), ws);
      }
    }
    if (this.sockets(ws).length === 0) r.emptySince = Date.now();
    this.commit();
  }

  /** The disconnect grace ran out for an offline member. */
  private graceOver(mem: Member): void {
    const r = this.room!;
    mem.graceAt = 0;
    const m = r.match;
    if (r.status === "playing" && m) {
      const seat = m.seats.find((st) => st.id === mem.id && !st.left);
      // (a seat whose side has finished never plays again: no bot needed)
      if (seat && !seat.ghost && !this.ops.isCpu(m.state, seat.color) && !this.ops.ranked(m.state).includes(seat.color)) {
        this.act({ k: "mode", c: seat.color, mode: "cpu" });
        if (this.ops.turnColor(m.state) === seat.color) this.planStep();
      }
    } else if (!r.quick) {
      this.removeMember(mem);
      this.broadcast(this.lobbyMsg());
    }
  }

  private removeMember(mem: Member): void {
    const r = this.room!;
    r.members = r.members.filter((m) => m !== mem);
    if (r.host === mem.id) r.host = r.quick ? -1 : r.members.length ? r.members[0].id : -1;
    r.touched = Date.now();
  }

  private leave(_ws: WebSocket, mem: Member): void {
    this.expel(mem, CLOSE.left);
  }

  /**
   * Removes a member for good (their own leave, an admin kick, a ban): their sockets get `error {code, msg}` (if
   * given) and close with closeCode; in a match a bot plays the seat for the rest of it.
   */
  private expel(mem: Member, closeCode: number, code?: string, msg?: string): void {
    const r = this.room!;
    const m = r.match;
    const hostWas = r.host;
    if (r.quick && r.status === "lobby" && mem.entry) {
      // left a coin-table room before its match started: the entry goes back
      const id = mem.entry;
      this.ctx.waitUntil(refundEntry(this.env as never, id, "left_lobby").then(() => undefined, (e) => console.error("entry refund failed:", e)));
    }
    this.removeMember(mem);
    for (const sock of this.socketsOf(mem.id)) {
      if (code) this.send(sock, { t: "error", code, msg: msg ?? code });
      this.closeWith(sock, closeCode, code ?? "left");
    }
    if (r.status === "playing" && m) {
      const seat = m.seats.find((st) => st.id === mem.id && !st.left);
      this.broadcast({ t: "presence", id: mem.id, online: false });
      if (seat) {
        seat.left = true;
        if (!this.ops.isCpu(m.state, seat.color) && !this.ops.ranked(m.state).includes(seat.color)) {
          this.act({ k: "mode", c: seat.color, mode: "cpu" });
          if (this.ops.turnColor(m.state) === seat.color) this.planStep();
        }
      }
      if (this.onlyBotsLeft()) {
        this.act({ k: "end" }); // the last person still playing left: the finished ones get their result now
        this.finish();
      }
      if (hostWas !== r.host && !r.quick) this.broadcast(this.lobbyMsg()); // tells everyone who the new host is
    } else if (!r.quick) {
      this.broadcast(this.lobbyMsg());
    }
    if (this.sockets().length === 0 && !r.emptySince) r.emptySince = Date.now();
  }

  /**
   * After a handler: a quick match whose humans have all left is abandoned at once (the ghosts would only play for
   * nobody; nothing is granted, the matches row says abandoned).
   */
  private async settle(): Promise<void> {
    const r = this.room;
    if (!r?.quick || r.status !== "playing" || !r.match) return;
    const humans = r.match.seats.filter((st) => !st.ghost);
    if (humans.length && humans.every((st) => st.left)) await this.destroy("abandoned", "abandoned");
  }

  // ---------- lobby ----------

  private settings(ws: WebSocket, mem: Member, msg: Record<string, unknown>): void {
    const r = this.room!;
    if (r.quick) return this.error(ws, "bad_action", "quick matches have no settings");
    if (r.host !== mem.id) return this.error(ws, "not_host", "only the host changes settings");
    if (r.status === "playing") return this.error(ws, "bad_action", "the match is in progress");
    if (msg.teams !== undefined && typeof msg.teams !== "boolean") return this.error(ws, "bad_message", "teams: bool");
    if (msg.pair_ask !== undefined && typeof msg.pair_ask !== "boolean") {
      return this.error(ws, "bad_message", "pair_ask: bool");
    }
    if (msg.game !== undefined && !isGame(msg.game)) return this.error(ws, "bad_message", 'game: "ludo" | "sl"');
    if (typeof msg.teams === "boolean") r.settings.teams = msg.teams;
    if (typeof msg.pair_ask === "boolean") r.settings.pair_ask = msg.pair_ask;
    if (isGame(msg.game)) r.settings.game = msg.game;
    r.touched = Date.now();
    this.broadcast(this.lobbyMsg());
  }

  /** Why mem can't start the match now ([code, msg]), or null. */
  private startError(mem: Member): [string, string] | null {
    const r = this.room!;
    if (r.quick) return ["bad_action", "quick matches have no rematch: queue again"];
    if (r.host !== mem.id) return ["not_host", "only the host starts the match"];
    if (r.status === "playing") return ["bad_action", "the match is in progress"];
    const k = r.members.length;
    if (k < 2) return ["too_few", "at least 2 players are needed"];
    if ((r.settings.game ?? "ludo") === "ludo" && r.settings.teams && k !== 4) {
      return ["teams_need_4", "teams need exactly 4 players"];
    }
    return null;
  }

  private start(ws: WebSocket, mem: Member, timers?: TurnTimers): void {
    const err = this.startError(mem);
    if (err) return this.error(ws, err[0], err[1]);
    this.startMatch(timers);
  }

  /** A quick room starts (every human connected, or the auto-start time). False when no human is connected. */
  private startQuick(): boolean {
    const r = this.room!;
    if (r.status !== "lobby" || !r.quick) return true;
    const humans = r.members.filter((m) => !m.ghost);
    if (!humans.some((h) => this.online(h.id))) return false;
    this.startMatch(r.quick.timers);
    // humans who never connected: their seat becomes a bot after the grace, as for a disconnect
    const now = Date.now();
    for (const h of humans) if (!this.online(h.id)) h.graceAt = now + this.ms(TIMING.grace);
    return true;
  }

  /** Seats the members (join / seat order), deals the new state and broadcasts `start`. */
  private startMatch(timers?: TurnTimers): void {
    const r = this.room!;
    const game: GameKind = r.settings.game ?? "ludo";
    const k = r.members.length;
    const colors = seatColors(game, k);
    const seats: Seat[] = r.members.map((mm, j) => {
      const st: Seat = {
        color: colors[j],
        id: mm.id,
        pid: mm.pid,
        name: mm.name,
        avatar: mm.avatar,
        frame: mm.frame,
        left: false,
        account: mm.account ?? null,
      };
      if (mm.level !== undefined) st.level = mm.level;
      if (mm.ghost) st.ghost = true;
      if (mm.entry) st.entry = mm.entry;
      return st;
    });
    let s: AnyState;
    if (game === "sl") {
      const g = SL.newGame("local", k, 0, { need_one: false });
      g.mode = "online";
      seats.forEach((st, j) => {
        const p = g.players[j];
        p.c = st.color;
        p.name = st.name;
        p.you = false;
        p.cpu = false;
        const pos = this.hooks.slPos?.[j];
        if (this.env.TEST_MODE === "1" && typeof pos === "number") p.pos = pos;
      });
      s = g;
    } else {
      const players = ["off", "off", "off", "off"];
      for (const c of colors) players[c] = "human";
      const g = R.newGame(players, r.settings.teams, { pair_ask: r.settings.pair_ask });
      for (let c = 0; c < 4; c++) g.names[c] = "";
      for (const st of seats) g.names[st.color] = st.name;
      if (this.hooks.tok) {
        for (const st of seats) if (this.hooks.tok[st.color]) g.tok[st.color] = [...this.hooks.tok[st.color]];
      }
      s = g;
    }
    const now = Date.now();
    const m: Match = {
      game,
      seats,
      state: s,
      n: 0,
      due: 0,
      shown: 0,
      strikes: [0, 0, 0, 0],
      rng: randomSeed(),
      startedAt: now,
      timers,
    };
    r.match = m;
    r.status = "playing";
    r.touched = now;
    const ghosts = seats.filter((st) => st.ghost).length;
    const row = {
      code: r.code,
      started_at: now,
      players: seats.map((st) => {
        const p: D.MatchPlayer & { ghost?: boolean } = { pid: st.pid ?? "", name: st.name, color: st.color, bot: false };
        if (st.ghost) p.ghost = true;
        return p;
      }),
      teams: game === "ludo" && r.settings.teams,
      pair_ask: game === "ludo" && r.settings.pair_ask,
      // matches.game / quick / ghosts (migration 0002; db.ts ignores them until it writes those columns)
      game,
      quick: !!r.quick,
      ghosts,
    };
    this.db("match start", [D.insertMatch(this.env.DB, row)]);
    this.broadcast({ t: "start", n: 0, game, seats: this.seatsOut(), state: s, h: this.ops.hash(s) });
    this.ctx.waitUntil(this.loadRerollMeans());
    // members offline at the start keep their grace; it now turns their seat into a bot
    this.planStep();
  }

  // ---------- match ----------

  private play(ws: WebSocket, mem: Member, msg: Record<string, unknown>): void {
    const r = this.room!;
    const m = r.match;
    if (r.status !== "playing" || !m) return this.error(ws, "bad_action", "no match in progress");
    if (!isInt(msg.n, 0, Number.MAX_SAFE_INTEGER)) return this.error(ws, "bad_message", "n: int");
    if (msg.n !== m.n) return this.error(ws, "stale", `expected n ${m.n}`);
    const O = this.ops;
    const s = m.state;
    const seat = m.seats.find((st) => st.id === mem.id && !st.left);
    if (!seat || seat.color !== O.turnColor(s)) return this.error(ws, "not_your_turn", "it is not your turn");
    const c = seat.color;
    const hold = this.holding(m);
    if (hold && hold.c !== c) return this.error(ws, "hold", "wait: the last player may roll again", { until: hold.until });
    let a: Action;
    if ((m.game ?? "ludo") === "sl") {
      if (msg.t !== "roll") return this.error(ws, "bad_action", "snakes & ladders only has roll");
      if (s.phase !== "roll") return this.error(ws, "bad_action", `phase is ${s.phase}`);
      a = { k: "roll", c, v: this.dice() };
    } else {
      const ls = s as LudoState;
      if (msg.t === "roll") {
        if (ls.phase !== "roll") return this.error(ws, "bad_action", `phase is ${ls.phase}`);
        a = { k: "roll", c, v: this.dice() };
      } else if (msg.t === "move") {
        if (ls.phase !== "choose") return this.error(ws, "bad_action", `phase is ${ls.phase}`);
        if (!isInt(msg.i, 0, 3)) return this.error(ws, "bad_action", "i: token index 0-3");
        const i = msg.i;
        const u = R.units(ls).find((uu) => uu.tokens.includes(i));
        if (!u) return this.error(ws, "bad_action", "that pawn can't move");
        a = { k: "move", c, i: u.token };
      } else {
        if (ls.phase !== "pair_ask") return this.error(ws, "bad_action", `phase is ${ls.phase}`);
        if (typeof msg.yes !== "boolean") return this.error(ws, "bad_message", "yes: bool");
        a = { k: "pair", c, yes: msg.yes };
      }
    }
    m.strikes[c] = 0;
    if (O.isCpu(s, c)) this.act({ k: "mode", c, mode: "human" }); // acting yourself counts as "back"
    this.act(a);
    this.afterActs();
  }

  private back(mem: Member): void {
    const r = this.room!;
    const m = r.match;
    if (r.status !== "playing" || !m) return;
    const seat = m.seats.find((st) => st.id === mem.id && !st.left);
    if (!seat || !this.ops.isCpu(m.state, seat.color)) return;
    m.strikes[seat.color] = 0;
    this.act({ k: "mode", c: seat.color, mode: "human" });
    if (this.ops.turnColor(m.state) === seat.color) this.planStep();
  }

  private seatOfColor(c: number): Seat | undefined {
    return this.room?.match?.seats.find((st) => st.color === c);
  }

  /** The current step is due: a timeout for a human, a ghost's or a bot's action. */
  private step(): void {
    const m = this.room!.match!;
    const O = this.ops;
    const s = m.state;
    const c = O.turnColor(s);
    if (this.seatOfColor(c)?.ghost && !O.isCpu(s, c)) {
      this.ghostAct(c); // ghosts never time out and play on like people (no pause when nobody watches)
    } else if (!O.isCpu(s, c)) {
      m.strikes[c]++;
      this.autoAct(c, "easy", true);
      if (O.phase(s) !== "over" && m.strikes[c] >= 2 && !O.isCpu(s, c)) {
        this.act({ k: "mode", c, mode: "cpu" });
      }
    } else {
      if (!this.anyOnline()) {
        m.due = 0; // nobody is watching: pause the bots until somebody reconnects
        m.shown = 0;
        return;
      }
      this.autoAct(c, "normal", false);
    }
    this.afterActs();
  }

  private rng(): { g: R.Mulberry32; done: () => void } {
    const m = this.room!.match!;
    const g = new R.Mulberry32(0);
    g.state = m.rng;
    return { g, done: () => void (m.rng = g.state) };
  }

  private autoAct(c: number, level: string, timeout: boolean): void {
    const m = this.room!.match!;
    if ((m.game ?? "ludo") === "sl") {
      const a = SL.botAction(m.state as SlState, this.dice());
      if (a) this.act(a);
      return;
    }
    const s = m.state as LudoState;
    if (s.phase === "roll") {
      this.act({ k: "roll", c, v: this.dice() });
    } else if (s.phase === "choose") {
      let i = timeout ? R.autoMoveToken(s) : -1;
      if (i < 0) {
        const { g, done } = this.rng();
        i = R.pickAi(s, R.movables(s), g, level);
        done();
      }
      this.act({ k: "move", c, i });
    } else if (s.phase === "pair_ask") {
      this.act({ k: "pair", c, yes: true });
    }
  }

  /** A ghost's step: the same actions a person's requests become. */
  private ghostAct(c: number): void {
    const m = this.room!.match!;
    if ((m.game ?? "ludo") === "sl") {
      if (m.state.phase === "roll") this.act({ k: "roll", c, v: this.dice() });
      return;
    }
    const s = m.state as LudoState;
    if (s.phase === "roll") {
      this.act({ k: "roll", c, v: this.dice() });
    } else if (s.phase === "choose") {
      const { g, done } = this.rng();
      const i = ghostPick(s, g);
      done();
      if (i >= 0) this.act({ k: "move", c, i });
    } else if (s.phase === "pair_ask") {
      const { g, done } = this.rng();
      const yes = ghostPairYes(g);
      done();
      this.act({ k: "pair", c, yes });
    }
  }

  /** Applies one action to the match and broadcasts it. */
  private act(a: Action): void {
    const r = this.room!;
    const m = r.match!;
    const s = m.state;
    delete m.rr; // any action closes an open re-roll offer
    const before = a.k === "roll" && this.rerollEligible(m, a.c) ? structuredClone(s) : null;
    const ev = this.ops.apply(s, a);
    const n = m.n++;
    r.touched = Date.now();
    this.noteRanked(m);
    this.broadcast({ t: "act", n, a, h: this.ops.hash(s) });
    if (before && s.phase !== "over" && badRoll(m.game ?? "ludo", ev as Array<{ type: string; v?: number; snake?: boolean }>)) this.offerReroll(m, (a as { c: number }).c, n, before);
    if (r.quick) this.ghostReact(m, ev);
  }

  // ---------- re-rolls (ECONOMY_V1.md §4) ----------

  /** Can colour c's seat get a re-roll offer if this roll goes badly? */
  private rerollEligible(m: Match, c: number): boolean {
    if (m.rrUsed?.includes(c)) return false;
    if (this.ops.isCpu(m.state, c)) return false;
    const st = m.seats.find((x) => x.color === c);
    if (!st || st.left) return false;
    if (st.ghost) return true;
    if (!st.account) return false;
    const mem = this.room!.members.find((x) => x.id === st.id);
    const rr = mem?.rr;
    return !!rr && (rr.free > 0 || rr.gems >= ECON_V1.reroll_gems);
  }

  /** Opens the offer: holds the turn ECON_V1.reroll_window_ms; a ghost may decide to take it. */
  private offerReroll(m: Match, c: number, bn: number, before: AnyState): void {
    const now = Date.now();
    const until = now + this.ms(ECON_V1.reroll_window_ms);
    const offer: RerollOffer = { c, bn, n: m.n, before, until };
    const st = m.seats.find((x) => x.color === c)!;
    if (st.ghost) {
      // (tests: off unless a test asks, so scripted dice stay in order)
      const chance = this.env.TEST_MODE === "1" ? (this.hooks.rerollChance ?? 0) : ECON_V1.ghost_reroll_chance;
      if (Math.random() >= chance) return; // most bad rolls a ghost just takes (no hold either: nothing to wait for)
      offer.ghostAt = now + this.ms(1200 + Math.random() * 1000);
      m.rr = offer;
      this.broadcast({ t: "hold", c, until });
      return;
    }
    m.rr = offer;
    const mem = this.room!.members.find((x) => x.id === st.id);
    if (mem) for (const ws of this.socketsOf(mem.id)) this.send(ws, { t: "reroll_offer", n: m.n, until, now, free: mem.rr?.free ?? 0, gems: mem.rr?.gems ?? 0, cost: ECON_V1.reroll_gems });
    this.broadcast({ t: "hold", c, until });
  }

  /** The open offer, if it still holds the turn (paying keeps it open past `until`). */
  private holding(m: Match, now = Date.now()): RerollOffer | null {
    const o = m.rr;
    return o && (o.paying || now < o.until) ? o : null;
  }

  /** {t: "reroll", n}: the player pays and rolls again. */
  private async reroll(ws: WebSocket, mem: Member, msg: Record<string, unknown>): Promise<void> {
    const r = this.room!;
    const m = r.match;
    if (r.status !== "playing" || !m) return this.error(ws, "reroll_closed", "no match in progress");
    const seat = m.seats.find((st) => st.id === mem.id && !st.left);
    const o = m.rr;
    if (!seat || !o || o.c !== seat.color || o.ghostAt !== undefined) return this.error(ws, "reroll_closed", "no re-roll offer for you");
    if (m.rrUsed?.includes(seat.color)) return this.error(ws, "reroll_used", "you already rolled again this match");
    if (msg.n !== m.n || o.n !== m.n) return this.error(ws, "reroll_closed", "the game moved on");
    if (o.paying) return; // a double tap
    if (Date.now() > o.until + 500) return this.error(ws, "reroll_closed", "too late");
    if (!mem.account) return this.error(ws, "reroll_closed", "sign in to roll again");
    const matchId = `${r.code}-${m.startedAt ?? 0}`;
    o.paying = true;
    this.commit();
    let pay: Awaited<ReturnType<typeof spendReroll>>;
    try {
      pay = await withTimeout(spendReroll(this.env as never, mem.account, matchId), 8_000);
    } catch (e) {
      console.error("spendReroll failed:", e);
      pay = { ok: false, error: "unknown" };
    }
    const r2 = this.room;
    const still = r2 === r && r.status === "playing" && r.match === m && m.rr === o && m.n === o.n;
    o.paying = false;
    if (!still) {
      if (pay.ok) this.ctx.waitUntil(refundReroll(this.env as never, mem.account, matchId).catch((e) => console.error("refundReroll failed:", e)));
      return this.error(ws, "reroll_closed", "the game moved on");
    }
    if (!pay.ok) {
      delete m.rr; // the hold ends: the next player goes on
      this.planStep();
      if (pay.error === "reroll_used") (m.rrUsed ??= []).push(seat.color);
      return this.error(ws, pay.error === "unknown" ? "reroll_closed" : pay.error, pay.error === "gems" ? `a re-roll costs ${ECON_V1.reroll_gems} gems` : "can't roll again now");
    }
    mem.rr = { free: pay.free, gems: pay.gems };
    this.doReroll(m, o, pay.paid);
  }

  /** Puts the state back to before the bad roll and rolls again (a fresh server roll). */
  private doReroll(m: Match, o: RerollOffer, paid: "free" | "gems"): void {
    const r = this.room!;
    delete m.rr;
    (m.rrUsed ??= []).push(o.c);
    m.state = o.before;
    m.n = o.bn;
    const O = this.ops;
    this.broadcast({ t: "rerolled", c: o.c, paid });
    this.broadcast({ t: "sync", n: m.n, game: m.game ?? "ludo", seats: this.seatsOut(), state: m.state, h: O.hash(m.state) });
    this.act({ k: "roll", c: o.c, v: this.dice() } as Action);
    r.touched = Date.now();
    this.afterActs();
  }

  /** Re-roll means for the people in a match (read once at the start; best effort). */
  private async loadRerollMeans(): Promise<void> {
    const r = this.room;
    const m = r?.match;
    if (!r || !m) return;
    for (const mem of r.members) {
      if (mem.ghost || !mem.account || mem.rr) continue;
      try {
        const b = await withTimeout(rerollBalance(this.env as never, mem.account), 5_000);
        if (b && this.room === r) mem.rr = b;
      } catch (e) {
        console.error("rerollBalance failed:", e);
      }
    }
    if (this.room === r) this.commit();
  }

  /** Records the sides ranked by the last action, and which of their seats were away then (their grant: "left"). */
  private noteRanked(m: Match): void {
    const O = opsFor(m.game);
    const ranked = (m.ranked ??= []);
    for (const c of O.ranked(m.state)) {
      if (ranked.includes(c)) continue;
      ranked.push(c);
      const st = m.seats.find((x) => x.color === c);
      if (st && (st.left || O.isCpu(m.state, c))) (m.away ??= []).push(c);
    }
  }

  /**
   * Play on: no real person (seated, not left, not a ghost) is left unfinished, while there is someone the result
   * is for: a person still seated, or one whose side already finished (left afterwards: the place is kept). The
   * match is then ended with {k: "end"} (the rest ranked by progress). Nobody finished and everyone left: false
   * (settle() abandons a quick match; a friend room waits for the empty-room timer, as before).
   */
  private onlyBotsLeft(): boolean {
    const r = this.room!;
    const m = r.match;
    if (r.status !== "playing" || !m || m.state.phase === "over") return false;
    const open = new Set(this.ops.unfinished(m.state));
    if (m.seats.some((st) => !st.ghost && !st.left && open.has(st.color))) return false;
    const ranked = m.ranked ?? [];
    return m.seats.some((st) => !st.ghost && (!st.left || ranked.includes(st.color)));
  }

  private afterActs(): void {
    const r = this.room!;
    const m = r.match!;
    if (m.state.phase !== "over" && this.onlyBotsLeft()) this.act({ k: "end" });
    if (m.state.phase === "over") this.finish();
    else this.planStep();
  }

  /**
   * Sets the deadline (human), the action time (bot, ghost) for the current step and announces it. A ghost's turn is
   * announced with a human's deadline (the configured turn timer), whatever its planned action time.
   */
  private planStep(): void {
    const r = this.room!;
    const m = r.match!;
    const O = this.ops;
    const s = m.state;
    if (r.status !== "playing" || s.phase === "over") {
      m.due = 0;
      m.shown = 0;
      return;
    }
    const now = Date.now();
    const c = O.turnColor(s);
    const phase = O.phase(s);
    const timers = (m.timers ?? TIMING) as unknown as Record<string, number>;
    const humanMs = this.ms(timers[phase] ?? TIMING.roll);
    if (O.isCpu(s, c)) {
      if (!this.anyOnline()) {
        m.due = 0;
        m.shown = 0;
        return;
      }
      const [lo, hi] = phase === "roll" ? [TIMING.botRollMin, TIMING.botRollMax] : [TIMING.botStepMin, TIMING.botStepMax];
      m.due = now + this.ms(lo + Math.random() * (hi - lo));
      m.shown = m.due;
    } else if (this.seatOfColor(c)?.ghost) {
      m.due = now + this.ms(ghostDelay(phase, { randf: Math.random }));
      m.shown = now + humanMs;
    } else {
      m.due = now + humanMs;
      m.shown = m.due;
    }
    // a re-roll offer holds the turn: the next player's clock starts when it closes
    const hold = this.holding(m, now);
    if (hold && hold.c !== c) {
      const shift = Math.max(0, hold.until - now);
      m.due += shift;
      m.shown = (m.shown || m.due) + shift;
    }
    this.broadcast({ t: "turn", c, deadline: Math.round(m.shown), now });
    if (phase === "roll" && !O.isCpu(s, c) && !r.quick) this.pushTurn(m, c);
  }

  private overMsg(m: Match): Record<string, unknown> {
    const O = opsFor(m.game);
    const r = this.room!;
    const msg: Record<string, unknown> = { t: "over", finished: O.finished(m.state), winner: O.winner(m.state), standings: O.standings(m.state), match_id: `${r.code}-${m.startedAt ?? 0}` };
    const t = r.quick?.table;
    if (r.quick && t) {
      // the coin table's result (ECONOMY_V1.md §3): coins paid per colour (seats that left get none)
      const paid = this.paidOrder(m);
      const { pay } = tablePayouts(t.entry, r.quick.size, paid.length);
      const payouts: Record<string, number> = {};
      for (const st of m.seats) payouts[String(st.color)] = 0;
      if (t.entry > 0) paid.forEach((st, k) => (payouts[String(st.color)] = pay[k] ?? 0));
      msg.table = { tier: t.tier, entry: t.entry, payouts };
    }
    return msg;
  }

  /** Quick matches: the seats in final order without the ones that left (the coin table's paid places). */
  private paidOrder(m: Match): Seat[] {
    const O = opsFor(m.game);
    const order = [...O.finished(m.state)];
    for (const st of m.seats) if (!order.includes(st.color)) order.push(st.color);
    const out: Seat[] = [];
    for (const c of order) {
      const st = m.seats.find((x) => x.color === c);
      if (st && !st.left) out.push(st);
    }
    return out;
  }

  private finish(): void {
    const r = this.room!;
    const m = r.match!;
    r.status = "over";
    m.due = 0;
    m.shown = 0;
    this.matchOver();
    this.broadcast(this.overMsg(m));
    const now = Date.now();
    if (r.quick) {
      r.quick.overAt = now; // no lobby, no rematch: the room is deleted a little later
      return;
    }
    // back to lobby rules: members still offline are dropped after the grace
    for (const mem of r.members) if (!this.online(mem.id) && !mem.graceAt) mem.graceAt = now + this.ms(TIMING.grace);
    this.broadcast(this.lobbyMsg());
    for (const mem of r.members) {
      const by = this.presentName(mem);
      if (by) this.pushTo(mem, "rematch", "Rematch?", `${by} wants a rematch in room ${r.code}`);
    }
  }

  private dice(): number {
    const q = this.hooks.dice;
    if (this.env.TEST_MODE === "1" && q && q.length) {
      const v = q.shift()!;
      this.ctx.storage.kv.put("hooks", this.hooks);
      return v;
    }
    return rollDie();
  }

  // ---------- messages ----------

  private lobbyMsg(): Record<string, unknown> {
    const r = this.room!;
    const colors = seatColors(r.settings.game ?? "ludo", r.members.length);
    return {
      t: "lobby",
      code: r.code,
      host: r.host,
      members: r.members.map((m, j) => ({
        id: m.id,
        name: m.name,
        avatar: m.avatar,
        frame: m.frame,
        level: m.level ?? 1,
        online: this.memberOnline(m),
        color: colors[j],
      })),
      settings: { teams: r.settings.teams, pair_ask: r.settings.pair_ask, game: r.settings.game ?? "ludo" },
      max: LIMITS.maxMembers,
      status: r.status,
    };
  }

  /** The seats as clients see them. Ghost seats are built exactly like the others (same keys, bot false, online). */
  private seatsOut(): Array<Record<string, unknown>> {
    const m = this.room!.match!;
    const O = opsFor(m.game);
    return m.seats.map((st) => ({
      color: st.color,
      id: st.id,
      name: st.name,
      avatar: st.avatar,
      frame: st.frame,
      level: st.level ?? 1,
      bot: O.isCpu(m.state, st.color),
      online: st.ghost ? true : !st.left && this.online(st.id),
    }));
  }

  /** sync (+ turn while playing) for one socket; lobby when there is no match. */
  private sendSnapshot(ws: WebSocket): void {
    const r = this.room!;
    const m = r.match;
    if (!m) {
      if (!r.quick) this.send(ws, this.lobbyMsg());
      return;
    }
    const O = opsFor(m.game);
    this.send(ws, { t: "sync", n: m.n, game: m.game ?? "ludo", seats: this.seatsOut(), state: m.state, h: O.hash(m.state) });
    if (r.status === "playing" && m.due) {
      this.send(ws, { t: "turn", c: O.turnColor(m.state), deadline: Math.round(m.shown || m.due), now: Date.now() });
    } else if (r.status === "over") {
      this.send(ws, this.overMsg(m));
    }
  }

  private send(ws: WebSocket, msg: unknown): void {
    try {
      ws.send(JSON.stringify(msg));
    } catch {
      /* closing */
    }
  }

  private broadcast(msg: unknown, except?: WebSocket): void {
    const text = JSON.stringify(msg);
    for (const ws of this.sockets(except)) {
      try {
        ws.send(text);
      } catch {
        /* closing */
      }
    }
  }

  private error(ws: WebSocket, code: string, msg: string, extra?: Record<string, unknown>): void {
    this.send(ws, { t: "error", code, msg, ...extra });
  }

  /** An error that ends the connection. */
  private fatal(ws: WebSocket, code: string, msg: string): void {
    this.error(ws, code, msg);
    try {
      ws.serializeAttachment({ mid: -2 } satisfies Att);
      ws.close(CLOSE.fatal, code);
    } catch {
      /* gone */
    }
  }

  // ---------- sockets ----------

  private att(ws: WebSocket): Att {
    try {
      return (ws.deserializeAttachment() as Att | null) ?? { mid: -1 };
    } catch {
      return { mid: -2 };
    }
  }

  /** Open sockets that said hello. */
  private sockets(except?: WebSocket): WebSocket[] {
    return this.ctx.getWebSockets().filter((ws) => ws !== except && ws.readyState === 1 && this.att(ws).mid >= 0);
  }

  private socketsOf(mid: number): WebSocket[] {
    return this.ctx.getWebSockets().filter((ws) => this.att(ws).mid === mid);
  }

  private online(mid: number, except?: WebSocket): boolean {
    return this.sockets(except).some((ws) => this.att(ws).mid === mid);
  }

  /** What clients are told about a member's presence: ghosts are always online. */
  private memberOnline(mem: Member): boolean {
    return mem.ghost ? true : this.online(mem.id);
  }

  private anyOnline(): boolean {
    return this.sockets().length > 0;
  }

  // ---------- event pushes (NOTIFICATIONS.md; never part of the match) ----------

  /** Away for pushes: no open socket, or every open one said `away`. */
  private away(mem: Member): boolean {
    return !this.sockets().some((ws) => {
      const a = this.att(ws);
      return a.mid === mem.id && !a.away;
    });
  }

  /** The name of a person here (not away) other than `to`, the host first; null when nobody is. */
  private presentName(to: Member): string | null {
    const r = this.room!;
    const here = r.members.filter((x) => x !== to && !x.ghost && !this.away(x));
    return (here.find((x) => x.id === r.host) ?? here[0])?.name ?? null;
  }

  /** "It's your turn" for the member seated at colour c (a person, not a bot, holds it) when away and someone waits. */
  private pushTurn(m: Match, c: number): void {
    const st = this.seatOfColor(c);
    const mem = st && !st.left && !st.ghost ? this.room!.members.find((x) => x.id === st.id) : undefined;
    if (!mem) return;
    const by = this.presentName(mem);
    if (by) this.pushTo(mem, "turn", "It's your turn", `${by} is waiting for you in room ${this.room!.code}`, `${m.startedAt ?? 0}:${m.n}`);
  }

  /**
   * An event push to an away member of a friend room with an account (Game alerts on, NOTIFICATIONS.md), sent in the
   * background: never to ghosts or in quick rooms, at most once per member and kind per PUSH.everyMs, a turn push
   * once per turn. Only `mem.pushed` changes (saved with the handler's commit); push off: nothing at all.
   */
  private pushTo(mem: Member, kind: PushKind & keyof NonNullable<Member["pushed"]>, title: string, body: string, turnKey?: string): void {
    const r = this.room!;
    if (r.quick || mem.ghost || !mem.account || !pushConfigured(this.env) || !this.away(mem)) return;
    const now = Date.now();
    const p = (mem.pushed ??= {});
    if (turnKey !== undefined && p.turnKey === turnKey) return;
    if (now - (p[kind] ?? 0) < PUSH.everyMs) return;
    p[kind] = now;
    if (turnKey !== undefined) p.turnKey = turnKey;
    const note = { kind, title, body, link: `room:${r.code}`, channel: "game", tag: `room:${r.code}`, ttl_s: EVENT_TTL_S } as const;
    this.ctx.waitUntil(
      pushAccount(this.env, mem.account, note, { pref: "game", count: true }).catch((e) => console.error(`${kind} push failed:`, e)),
    );
  }

  // ---------- emotes (EMOTES.md; never part of the match) ----------

  /**
   * Emotes have their own limiter, so a spammed picker must not eat the 20 msg/s budget that rolls and moves need:
   * the first 5 emote messages per second are refunded to the general limit, the rest count as ordinary messages.
   */
  private refundEmote(ws: WebSocket): void {
    const now = Date.now();
    let e = this.emoWindow.get(ws);
    if (!e || now - e.start >= 1000) {
      e = { start: now, count: 0 };
      this.emoWindow.set(ws, e);
    }
    e.count++;
    const w = this.rate.get(ws);
    if (e.count <= 5 && w && w.count > 0) w.count--;
  }

  /** `{t:"emote", id}` from a member: validate, rate limit (1 / 2 s, 6 / 30 s), ownership, relay to the others. */
  private async emote(ws: WebSocket, mem: Member, msg: Record<string, unknown>): Promise<void> {
    const r = this.room!;
    const id = msg.id;
    const pack = packOfEmote(id);
    if (!pack) return this.error(ws, "bad_message", "unknown emote");
    const now = Date.now();
    const sent = (this.emoSent.get(mem.id) ?? []).filter((t) => now - t < this.ms(30_000));
    if ((sent.length && now - sent[sent.length - 1] < this.ms(2000)) || sent.length >= 6) {
      this.emoSent.set(mem.id, sent);
      return this.error(ws, "emote_rate", "too many emotes");
    }
    if (pack !== "starter") {
      const key = `${mem.id}:${pack}`;
      if ((this.emoLocked.get(key) ?? 0) > now) return this.error(ws, "emote_locked", "you do not own that emote pack");
      let sets = this.emoSets.get(mem.id);
      if (!sets?.includes(pack)) {
        sets = await this.readEmoteSets(mem);
        if (ws.readyState !== 1 || !this.room) return;
        if (sets.includes(pack)) this.emoSets.set(mem.id, sets);
      }
      if (!sets.includes(pack)) {
        this.emoLocked.set(key, Date.now() + this.ms(2000));
        if (this.emoLocked.size > 256) this.emoLocked.delete(this.emoLocked.keys().next().value!);
        return this.error(ws, "emote_locked", "you do not own that emote pack");
      }
    }
    const at = Date.now();
    sent.push(at);
    this.emoSent.set(mem.id, sent);
    const m = r.match;
    const seat = m && r.status !== "lobby" ? m.seats.find((st) => st.id === mem.id && !st.left) : undefined;
    this.broadcast(seat ? { t: "emote", c: seat.color, id } : { t: "emote", c: -1, member: mem.id, id }, ws);
    if (r.quick && m && r.status === "playing" && seat) {
      this.ghostReply(m, id as string, seat.color);
      this.commit(); // persists the plan and points the alarm at it
    }
  }

  /** The packs the member's account owns (fails to starter only); never throws. */
  private async readEmoteSets(mem: Member): Promise<string[]> {
    if (!mem.account || !this.env.DB) return ["starter"];
    try {
      return await withTimeout(D.readEmoteSets(this.env.DB, mem.account), TELEMETRY.readTimeout);
    } catch (e) {
      console.error("emote ownership read failed (denying):", e);
      return ["starter"];
    }
  }

  /** Ghost reactions to the events of one action (their capture, being captured, a 6, finishing; the opening hi). */
  private ghostReact(m: Match, ev: unknown[]): void {
    const hits: Array<{ c: number; kind: "capture" | "captured" | "six" | "finish" }> = [];
    const colourOf = (turn: number): number => (m.state as SlState).players?.[turn]?.c ?? -1;
    for (const e of ev as Array<Record<string, unknown>>) {
      switch (e.type) {
        case "rolled":
          if (e.v === 6) hits.push({ c: typeof e.c === "number" ? e.c : colourOf(e.turn as number), kind: "six" });
          break;
        case "capture":
          hits.push({ c: e.c as number, kind: "capture" });
          for (const v of (e.victims as number[][]) ?? []) hits.push({ c: v[0], kind: "captured" });
          break;
        case "finished":
          hits.push({ c: typeof e.c === "number" ? e.c : colourOf(e.turn as number), kind: "finish" });
          break;
        case "move":
          if (e.snake === true) hits.push({ c: colourOf(e.turn as number), kind: "captured" });
          break;
      }
    }
    const seen = new Set<string>();
    for (const h of hits) {
      const key = `${h.c}:${h.kind}`;
      if (!seen.has(key)) {
        seen.add(key);
        this.planGhostEmote(m, h.c, { kind: h.kind });
      }
    }
    // early in the match a chatty ghost may open with a hi (decided once per ghost)
    if (m.n <= 3) for (const st of m.seats) if (st.ghost && !st.left) this.planGhostEmote(m, st.color, { kind: "open" });
  }

  /** A human emoted: at most one ghost may answer. */
  private ghostReply(m: Match, id: string, from: number): void {
    const gs = m.seats.filter((st) => st.ghost && !st.left);
    for (let k = gs.length - 1; k > 0; k--) {
      const j = Math.floor(Math.random() * (k + 1));
      [gs[k], gs[j]] = [gs[j], gs[k]];
    }
    for (const st of gs) if (this.planGhostEmote(m, st.color, { kind: "emote", id, from, human: true })) return;
  }

  /** A ghost's emote went out: another ghost may (rarely, once per pair) react to it. */
  private ghostsHear(m: Match, from: number, id: string): void {
    const gs = m.seats.filter((st) => st.ghost && !st.left && st.color !== from);
    for (const st of gs) if (this.planGhostEmote(m, st.color, { kind: "emote", id, from, human: false })) return;
  }

  /**
   * Asks the ghost on colour c what to do about `trigger` (pure policy in ghosts.ts), and plans its emote (alarm-driven,
   * stored so it survives hibernation); true when one was planned.
   */
  private planGhostEmote(m: Match, c: number, trigger: GhostTrigger): boolean {
    const r = this.room!;
    const st = m.seats.find((x) => x.color === c && x.ghost && !x.left);
    const mem = st && r.members.find((x) => x.id === st.id);
    if (!st || !mem?.ghost) return false;
    const now = Date.now();
    const sit: GhostSituation = {
      now,
      scale: this.ms(1),
      lead: progressLead(m.state, c, m.seats.filter((x) => !x.left).map((x) => x.color)),
      ownTurn: r.status === "playing" && opsFor(m.game).turnColor(m.state) === c,
      chance: this.env.TEST_MODE === "1" ? this.hooks.emoteChance : undefined,
    };
    const out = ghostEmoteReply(sit, mem.persona ?? "friendly", (mem.emo ??= newGhostMemory()), trigger, { randf: Math.random }, mem.emotePack ?? "");
    if (!out) return false;
    (m.gemotes ??= []).push({ at: now + out.delayMs, c, id: out.id });
    return true;
  }

  /** Sends the ghost emotes that are due (same shape as a person's); drops them when the room is back in the lobby. */
  private flushGhostEmotes(now: number): void {
    const r = this.room;
    const m = r?.match;
    if (!r || !m?.gemotes?.length) return;
    const due = m.gemotes.filter((e) => e.at <= now);
    if (!due.length && r.status !== "lobby") return;
    m.gemotes = m.gemotes.filter((e) => e.at > now);
    if (r.status === "lobby") m.gemotes = [];
    if (!this.anyOnline()) return;
    for (const e of due) {
      if (r.status === "lobby") continue;
      this.broadcast({ t: "emote", c: e.c, id: e.id });
      this.ghostsHear(m, e.c, e.id);
    }
  }

  /** 20 messages per second per socket; over that: one rate error per window, the rest dropped. */
  private allow(ws: WebSocket): boolean {
    const now = Date.now();
    let w = this.rate.get(ws);
    if (!w || now - w.start >= 1000) {
      w = { start: now, count: 0, warned: false };
      this.rate.set(ws, w);
    }
    w.count++;
    const limit = this.env.TEST_MODE === "1" ? (this.hooks.ratePerSec ?? LIMITS.ratePerSec) : LIMITS.ratePerSec;
    if (w.count <= limit) return true;
    if (!w.warned) {
      w.warned = true;
      this.error(ws, "rate", "too many messages");
    }
    return false;
  }

  // ---------- persistence and timers ----------

  private ms(t: number): number {
    const k = this.env.TEST_MODE === "1" ? (this.hooks.timeScale ?? 1) : 1;
    return t * k;
  }

  /** Points the alarm at the earliest due event and saves the room; queues the D1 rooms row if it changed. */
  private commit(): void {
    const r = this.room;
    if (!r) return;
    const due: number[] = [r.touched + this.ms(TIMING.stale)];
    if (r.emptySince) due.push(r.emptySince + this.ms(TIMING.empty));
    if (r.status === "playing" && r.match?.due) due.push(r.match.due);
    if (r.status === "playing" && r.match?.rr?.ghostAt) due.push(r.match.rr.ghostAt);
    for (const mem of r.members) if (mem.graceAt) due.push(mem.graceAt);
    if (r.match?.gemotes?.length && r.status !== "lobby") for (const e of r.match.gemotes) due.push(e.at);
    if (r.quick && r.status === "lobby") due.push(r.quick.startBy);
    if (r.quick && r.status === "over" && r.quick.overAt) due.push(r.quick.overAt + this.ms(QUICK.overKeep));
    for (const g of r.grants ?? []) due.push(g.next);
    const next = Math.ceil(Math.min(...due));
    if (next !== r.alarmAt) {
      r.alarmAt = next;
      this.ctx.storage.setAlarm(next).catch((e) => this.storageFailed("setAlarm", e));
    }
    const sig = this.roomSig();
    if (sig !== r.dbSig) {
      // Written at once (not debounced): a status change, and the online count reaching 0 or leaving 0. The console
      // shows a playing room with online = 0 as paused, and a debounce timer would not survive an eviction
      // (dbSig is already advanced), which could leave the row saying online > 0 for good.
      const idle = !r.members.some((m) => !m.ghost && this.online(m.id));
      const immediate = r.dbStatus !== r.status || r.dbIdle !== idle;
      r.dbSig = sig;
      r.dbStatus = r.status;
      r.dbIdle = idle;
      this.roomChanged(immediate);
    }
    try {
      this.ctx.storage.kv.put("room", r);
    } catch (e) {
      this.storageFailed("put", e);
      throw e;
    }
  }

  private async destroy(reason: string, result: D.MatchResult): Promise<void> {
    const r = this.room;
    if (r) {
      const now = Date.now();
      const stmts: D1PreparedStatement[] = [];
      const m = r.match;
      if (r.status === "playing" && m) stmts.push(this.endMatchStmt(m, result, now));
      stmts.push(D.upsertRoom(this.env.DB, { ...this.roomState(), status: "closed", online: 0, closed_reason: reason }, now));
      this.roomDirty = false;
      this.db("room closed", stmts);
    }
    for (const ws of this.ctx.getWebSockets()) {
      try {
        ws.serializeAttachment({ mid: -2 } satisfies Att);
        this.send(ws, { t: "error", code: "not_found", msg: "the room was closed" });
        ws.close(CLOSE.closed, "room closed");
      } catch {
        /* gone */
      }
    }
    const pending = r?.grants?.length ? r.grants : null;
    if (r) this.closeEntries(r, reason);
    this.room = null;
    this.hooks = {};
    await this.ctx.storage.deleteAlarm();
    await this.ctx.storage.deleteAll();
    if (pending) for (const g of pending) this.ctx.waitUntil(this.grantOnce(g.g).catch(() => undefined)); // last try
    // the room is gone anyway: give its last D1 writes a moment instead of leaving them to waitUntil alone
    await Promise.race([this.dbChain, new Promise((res) => setTimeout(res, 3000))]);
  }

  /**
   * A coin-table room closing before `over` (no-show, everyone left, stale, an admin close): entries of seats that
   * left are forfeit when every person left (the match was abandoned), every other open entry is refunded. Entries
   * already settled by the match grant are left alone (refund / forfeit only touch open entries).
   */
  private closeEntries(r: RoomData, reason: string): void {
    if (!r.quick?.table?.entry || r.status === "over") return;
    const matchId = r.match ? `${r.code}-${r.match.startedAt ?? 0}` : r.code;
    const seen = new Set<string>();
    const env = this.env as never;
    for (const st of r.match?.seats ?? []) {
      if (!st.entry || seen.has(st.entry)) continue;
      seen.add(st.entry);
      const id = st.entry;
      this.ctx.waitUntil((reason === "abandoned" && st.left ? forfeitEntry(env, id, matchId) : refundEntry(env, id, reason).then(() => undefined)).catch((e) => console.error("entry close failed:", e)));
    }
    for (const mem of r.members) {
      if (!mem.entry || seen.has(mem.entry)) continue;
      seen.add(mem.entry);
      this.ctx.waitUntil(refundEntry(env, mem.entry, reason).then(() => undefined, (e) => console.error("entry refund failed:", e)));
    }
  }

  // ---------- online rewards (accounts.grantOnlineMatch) ----------

  /**
   * win / finish / left for one seat at `over`: the first side wins, every other side that finished or was ranked at
   * the end finishes; "left" only when the seat was away (it had left, or a bot played it) when its side was ranked
   * (a player who finished and then left keeps their outcome). Matches stored before play on: away at `over`.
   */
  private outcome(m: Match, st: Seat, won: Set<number>): OnlineOutcome {
    const away = m.ranked ? (m.away ?? []).includes(st.color) : st.left || opsFor(m.game).isCpu(m.state, st.color);
    if (away) return "left";
    return won.has(st.color) ? "win" : "finish";
  }

  private async grantOnce(g: OnlineMatchGrant): Promise<void> {
    await withTimeout(Promise.resolve(accounts(this.env).grantOnlineMatch(this.env, g)), 10_000);
  }

  /** Sends every pending grant that is due; failures are retried from the alarm (GRANT.tries in all). */
  private async runGrants(): Promise<void> {
    if (this.granting) return;
    this.granting = true;
    try {
      for (;;) {
        const r = this.room;
        const p = r?.grants?.find((x) => x.next <= Date.now());
        if (!r || !p) return;
        try {
          await this.grantOnce(p.g);
          if (this.room === r) r.grants = (r.grants ?? []).filter((x) => x !== p);
        } catch (e) {
          p.tries++;
          console.error("grantOnlineMatch failed:", e);
          if (p.tries >= GRANT.tries) {
            this.event("error", "grant", `grant ${p.g.match_id} gave up: ${String(e)}`.slice(0, 500));
            if (this.room === r) r.grants = (r.grants ?? []).filter((x) => x !== p);
          } else {
            p.next = Date.now() + this.ms(GRANT.retryMs * p.tries);
          }
        }
        if (this.room === r) {
          if (!r.grants?.length) delete r.grants;
          this.commit();
        }
      }
    } finally {
      this.granting = false;
    }
  }

  // ---------- D1 telemetry (ADMIN_API.md). Never blocks or breaks gameplay. ----------

  /** Runs statements as one D1 batch after the room's earlier writes (in order), fire-and-forget. */
  private db(label: string, stmts: D1PreparedStatement[]): void {
    if (!this.env.DB || !stmts.length) return;
    const p = this.dbChain.then(
      () => this.env.DB.batch(stmts).then(() => undefined),
      () => undefined,
    );
    this.dbChain = p.catch((e) => console.error(`D1 write failed (${label}):`, e));
    this.ctx.waitUntil(this.dbChain);
  }

  /** The rooms row as it is now. */
  private roomState(): D.RoomState {
    const r = this.room!;
    const host = r.members.find((m) => m.id === r.host);
    const st = {
      code: r.code,
      created_at: r.created,
      host_pid: host?.pid ?? null,
      host_name: host?.name ?? null,
      status: r.status,
      members: r.members.length,
      online: r.members.filter((m) => !m.ghost && this.online(m.id)).length,
      settings: { teams: r.settings.teams, pair_ask: r.settings.pair_ask },
      closed_reason: null,
      // rooms.game / public / quick (migration 0002; db.ts ignores them until it writes those columns)
      game: r.settings.game ?? "ludo",
      public: !!r.quick,
      quick: !!r.quick,
    };
    return st;
  }

  /** What the rooms row shows, as a string: a change queues a (debounced) write. */
  private roomSig(): string {
    const r = this.room!;
    const ms = r.members.map((m) => `${m.id}${!m.ghost && this.online(m.id) ? "+" : "-"}`).join(",");
    return `${r.status}|${r.host}|${ms}|${r.settings.teams ? 1 : 0}${r.settings.pair_ask ? 1 : 0}|${r.settings.game ?? "ludo"}`;
  }

  /** A status change is written at once; anything else at most once per TELEMETRY.roomDebounce (plus a final one). */
  private roomChanged(immediate: boolean): void {
    const wait = this.roomWriteAt + this.ms(TELEMETRY.roomDebounce) - Date.now();
    if (immediate || wait <= 0) return this.writeRoom();
    this.roomDirty = true;
    if (this.roomTimer) return;
    this.roomTimer = true;
    this.ctx.waitUntil(
      new Promise((res) => setTimeout(res, wait)).then(() => {
        this.roomTimer = false;
        if (this.roomDirty && this.room) this.writeRoom();
      }),
    );
  }

  private writeRoom(): void {
    const now = Date.now();
    this.roomDirty = false;
    this.roomWriteAt = now;
    this.db("room", [D.upsertRoom(this.env.DB, this.roomState(), now)]);
  }

  /** players upsert on hello (rooms+1 on the first join of this room); a quick reconnect is not written again. */
  private playerSeen(mem: Member, firstJoin: boolean): void {
    if (mem.ghost || !mem.pid) return;
    const now = Date.now();
    const last = this.playerSeenAt.get(mem.pid);
    if (!firstJoin && last !== undefined && now - last < TELEMETRY.playerRepeat) return;
    this.playerSeenAt.set(mem.pid, now);
    const p = { pid: mem.pid, name: mem.name, avatar: mem.avatar, frame: mem.frame, room: this.room!.code };
    this.db("player", D.playerSeen(this.env.DB, p, now, firstJoin));
  }

  private seatPid(st: Seat): string {
    if (st.ghost) return "";
    return st.pid ?? this.room?.members.find((m) => m.id === st.id)?.pid ?? "";
  }

  private endMatchStmt(m: Match, result: D.MatchResult, now: number): D1PreparedStatement {
    const O = opsFor(m.game);
    const s = m.state;
    const done = result === "over";
    const win = done ? O.winner(s) : -1;
    const winSeat = win >= 0 ? m.seats.find((st) => st.color === win) : undefined;
    const row = {
      code: this.room!.code,
      started_at: m.startedAt ?? 0,
      ended_at: now,
      winner: done ? win : null,
      finished: O.finished(s),
      actions: m.n,
      result,
      // matches.human_won (migration 0002): quick matches only, null while unknown
      human_won: this.room?.quick && done && winSeat ? !winSeat.ghost : null,
    };
    return D.endMatch(this.env.DB, row);
  }

  /** over: the matches row, players stats, online rewards for the humans, quick-match stats. */
  private matchOver(): void {
    const r = this.room!;
    const m = r.match!;
    const O = opsFor(m.game);
    const now = Date.now();
    const won = new Set<number>(O.winners(m.state));
    const stmts = [this.endMatchStmt(m, "over", now)];
    for (const st of m.seats) {
      if (st.ghost) continue;
      const pid = this.seatPid(st);
      if (pid) stmts.push(D.playerResult(this.env.DB, pid, won.has(st.color) && this.outcome(m, st, won) === "win", now));
    }
    this.db("match over", stmts);

    // quick match: the coin table's places (ECONOMY_V1.md §3): the final order without the seats that left
    const q = r.quick;
    const paidOrder: Seat[] = q ? this.paidOrder(m) : [];
    const results = m.seats
      .filter((st) => !st.ghost && st.account)
      .map((st) => {
        const res: OnlineMatchGrant["results"][number] = { account_id: st.account as string, outcome: this.outcome(m, st, won) };
        if (q) {
          res.place = st.left ? -1 : paidOrder.indexOf(st);
          if (st.entry) res.entry_id = st.entry;
        }
        return res;
      });
    if (results.length) {
      const g: OnlineMatchGrant = { match_id: `${r.code}-${m.startedAt ?? 0}`, game: m.game ?? "ludo", results };
      if (q) {
        const t = q.table ?? { tier: "practice", entry: 0 };
        const ghosts = m.seats.filter((st) => st.ghost).length;
        g.table = { tier: t.tier, entry: t.entry, size: q.size, humans: m.seats.length - ghosts, ghosts, winner_ghost: !!paidOrder[0]?.ghost };
      }
      (r.grants ??= []).push({ g, tries: 0, next: now });
      this.ctx.waitUntil(this.runGrants());
    }
    if (r.quick) {
      const win = O.winner(m.state);
      const ws = m.seats.find((st) => st.color === win);
      const stat = ws?.ghost ? { ghost_wins: 1 } : { human_wins: 1 };
      this.ctx.waitUntil(quickStat(this.env, { game: m.game ?? "ludo", size: r.quick.size, ...stat }));
    }
  }

  /**
   * Who is saying hello: the account (session, else the pid's account), the level, and whether they are banned
   * (the pid's legacy ban, the pid's account, the session's account). Cached TELEMETRY.banCache. Fails open.
   */
  private async identify(pid: string, session: unknown): Promise<Identity> {
    const ban = await this.banOf(pid);
    if (ban) return { account: null, ban, level: null };
    const sess = isSessionShape(session) ? session : "";
    const key = `${pid}|${sess}`;
    const now = Date.now();
    const c = this.idCache.get(key);
    if (c && now - c.at < TELEMETRY.banCache) return c.id;
    const A = accounts(this.env);
    const id: Identity = { account: null, ban: null, level: null };
    try {
      if (sess) {
        const v = await withTimeout(A.verifySession(this.env, sess), TELEMETRY.readTimeout);
        if (v?.account_id) {
          id.account = v.account_id;
          if (v.banned) id.ban = v.ban_reason || "banned";
        }
      }
      const pa = await withTimeout(A.accountForPid(this.env, pid), TELEMETRY.readTimeout);
      if (pa) {
        id.account ??= pa.account_id;
        if (pa.banned) id.ban ??= pa.ban_reason || "banned";
      }
      if (id.account && !id.ban) {
        const prof = await withTimeout(A.getPublicProfile(this.env, id.account), TELEMETRY.readTimeout);
        if (prof && Number.isFinite(prof.level)) id.level = Math.max(1, Math.trunc(prof.level));
      }
    } catch (e) {
      console.error("account lookup failed (allowing):", e);
    }
    this.idCache.set(key, { at: Date.now(), id });
    if (this.idCache.size > 256) this.idCache.delete(this.idCache.keys().next().value!);
    return id;
  }

  /** The ban reason for pid ("" reason -> still banned: returns a non-empty default), or null. Fails open. */
  private async banOf(pid: string): Promise<string | null> {
    const now = Date.now();
    const c = this.banCache.get(pid);
    if (c && now - c.at < TELEMETRY.banCache) return c.banned ? c.reason || "banned" : null;
    if (!this.env.DB) return null;
    try {
      const b = await withTimeout(D.readBan(this.env.DB, pid), TELEMETRY.readTimeout);
      const banned = !!b?.banned;
      this.banCache.set(pid, { at: Date.now(), banned, reason: b?.reason ?? "" });
      if (this.banCache.size > 256) this.banCache.delete(this.banCache.keys().next().value!);
      return banned ? b!.reason || "banned" : null;
    } catch (e) {
      console.error("ban check failed (allowing):", e);
      return null;
    }
  }

  /** Human turn deadlines from D1 config (read at every match start); defaults when unset or unreadable. */
  private async turnTimers(): Promise<TurnTimers | undefined> {
    if (!this.env.DB) return undefined;
    try {
      const c = await withTimeout(D.readConfig(this.env.DB), TELEMETRY.readTimeout);
      return { roll: c.turn_roll_s * 1000, choose: c.turn_choose_s * 1000, pair_ask: c.turn_pair_s * 1000 };
    } catch (e) {
      console.error("config read failed (default timers):", e);
      return undefined;
    }
  }

  /** An events row (rate-limited per room object). */
  private event(level: D.EventLevel, kind: string, msg: string, pid?: string): void {
    const now = Date.now();
    const w = this.eventWindow;
    if (now - w.start >= 60_000) {
      w.start = now;
      w.count = 0;
    }
    if (++w.count > TELEMETRY.eventsPerMin) return;
    this.db("event", [D.addEvent(this.env.DB, { level, kind, code: this.room?.code ?? null, pid: pid ?? null, msg }, now)]);
  }

  /** An exception escaped a handler: one error event (then the runtime sees the rethrown error as before). */
  private crashed(where: string, e: unknown): void {
    console.error(`room ${where} handler failed:`, e);
    if (typeof e === "object" && e !== null) {
      if (this.reported.has(e)) return;
      this.reported.add(e);
    }
    const msg = e instanceof Error ? `${e.name}: ${e.message}\n${e.stack ?? ""}` : String(e);
    this.event("error", "exception", `${where}: ${msg}`.slice(0, 1000));
  }

  private storageFailed(op: string, e: unknown): void {
    console.error(`room storage ${op} failed:`, e);
    if (typeof e === "object" && e !== null) this.reported.add(e);
    this.event("error", "storage", `${op}: ${e instanceof Error ? e.message : String(e)}`.slice(0, 1000));
  }

  private closeWith(ws: WebSocket, code: number, reason: string): void {
    try {
      ws.serializeAttachment({ mid: -2 } satisfies Att);
      ws.close(code, reason);
    } catch {
      /* gone */
    }
  }
}

/** The live room as the admin console sees it (ADMIN_API.md: GET /admin/api/rooms/:code `live`). */
export interface AdminSnapshot {
  code: string;
  status: Status;
  host: number;
  created: number;
  touched: number;
  sockets: number;
  /** "ludo" | "sl". */
  game: GameKind;
  /** A quick-match room (Matchmaker): no host, no lobby, may hold ghosts. */
  quick: boolean;
  /** `account`, `level` and `ghost: true` are present only when known / true. */
  members: Array<{
    id: number;
    pid: string;
    name: string;
    avatar: string;
    frame: string;
    online: boolean;
    color: number;
    account?: string;
    level?: number;
    ghost?: boolean;
    /** Ghosts only: the hidden emote personality (admin console only). */
    persona?: string;
  }>;
  settings: { teams: boolean; pair_ask: boolean };
  match: {
    n: number;
    game: GameKind;
    state: AnyState;
    seats: Array<Record<string, unknown>>;
    deadline: number;
    started_at: number;
  } | null;
}

function banMsg(reason: string): string {
  return reason && reason !== "banned" ? `You are banned from online play: ${reason}` : "You are banned from online play.";
}

export function withTimeout<T>(p: Promise<T>, ms: number): Promise<T> {
  return new Promise<T>((res, rej) => {
    const t = setTimeout(() => rej(new Error(`timed out after ${ms} ms`)), ms);
    p.then(
      (v) => {
        clearTimeout(t);
        res(v);
      },
      (e) => {
        clearTimeout(t);
        rej(e);
      },
    );
  });
}
