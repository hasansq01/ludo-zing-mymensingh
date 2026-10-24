// The Room Durable Object: one per room code. Server-authoritative Ludo over hibernatable WebSockets
// (PROTOCOL.md is the spec). Everything the room needs to resume after hibernation or eviction lives in one
// storage value ("room"), written synchronously with the SQLite-backed KV API after every change; per-socket
// identity lives in the socket attachment. A single alarm covers every timer (turn deadline / bot action,
// disconnect grace, empty-room and stale-room cleanup): schedule() always sets it to the earliest due event.
import { DurableObject } from "cloudflare:workers";
import * as R from "./rules_shim";
import * as D from "./db";

export interface Env {
  ROOMS: DurableObjectNamespace<Room>;
  /** D1 "ludo-zing-admin" (ADMIN_API.md): rooms / players / matches / events / config. */
  DB: D1Database;
  /** The admin console's static files (server/admin/, served at /admin). */
  ASSETS?: Fetcher;
  /** Admin console password (a secret; locally .dev.vars). Unset: the admin API answers 503. */
  ADMIN_PASSWORD?: string;
  /** "1" only under vitest (vitest.config.ts miniflare bindings). Never set in wrangler.jsonc. */
  TEST_MODE?: string;
}

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
  empty: 10 * 60_000, // no connected member for this long -> the room is deleted
  stale: 2 * 60 * 60_000, // no action (or lobby change) for this long -> the room is deleted
};

export const LIMITS = { maxMembers: 4, maxMsgBytes: 4096, ratePerSec: 20, maxSockets: 16 };

/** Playing colours by member count, in join order (PROTOCOL.md "Colours"). */
const SEAT_COLORS: Record<number, number[]> = { 1: [0], 2: [0, 2], 3: [0, 1, 2], 4: [0, 1, 2, 3] };

/** Close codes the server uses after a fatal error or a replaced / closed session. */
export const CLOSE = { fatal: 4000, replaced: 4001, left: 4002, banned: 4003, closed: 4004 };

/** D1 telemetry knobs (ADMIN_API.md "What the Room DO writes"). */
const TELEMETRY = {
  roomDebounce: 5_000, // at most one rooms-row write per room per 5 s (status changes are written at once)
  playerRepeat: 60_000, // a member reconnecting within this of the last players upsert is not written again
  banCache: 60_000, // a pid's ban flag is re-read from D1 after this
  readTimeout: 2_000, // a D1 read on the gameplay path (ban check, turn timers) gives up after this
  eventsPerMin: 20, // events written per room object per minute, at most
};

// ---------- persisted shapes ----------

type Status = "lobby" | "playing" | "over";
// The rules state is the GDScript LudoRules dictionary shape (snake_case keys); the rules module owns its type.
type LudoState = R.LudoState;
type Action = R.Action;

interface Member {
  id: number;
  pid: string;
  token: string;
  name: string;
  avatar: string;
  frame: string;
  /** Epoch ms when the disconnect grace runs out (0 = none). */
  graceAt: number;
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
}

interface Match {
  seats: Seat[];
  state: LudoState;
  /** Number of actions applied so far (= the index the next action gets). */
  n: number;
  /** Epoch ms of the current step's deadline (human) or planned action (bot); 0 = nothing pending. */
  due: number;
  /** Timeouts in a row per colour. */
  strikes: number[];
  /** Bot RNG (Mulberry32) state, so bot choices continue across wake-ups. */
  rng: number;
  /** Epoch ms of the start (with the code, identifies the D1 matches row). */
  startedAt?: number;
  /** Human turn deadlines for this match (ms), from D1 config at start; missing -> TIMING. */
  timers?: TurnTimers;
}

interface TurnTimers {
  roll: number;
  choose: number;
  pair_ask: number;
}

interface Settings {
  teams: boolean;
  pair_ask: boolean;
}

interface RoomData {
  v: 1;
  code: string;
  created: number;
  status: Status;
  host: number; // member id, -1 when the room has no members
  nextId: number;
  members: Member[]; // join order
  settings: Settings;
  match: Match | null;
  touched: number; // last action / lobby change (stale cleanup)
  emptySince: number; // 0 while somebody is connected
  alarmAt: number; // the alarm currently set (0 = none)
  /** Signature of the rooms-row fields last queued for D1, and the status they had (see commit()). */
  dbSig?: string;
  dbStatus?: Status;
}

/** Test-only knobs. Honoured only when env.TEST_MODE === "1" (vitest); set through testHooks() via RPC. */
export interface TestHooks {
  /** Dice values used, in order, before falling back to random rolls. */
  dice?: number[];
  /** Token progress per colour applied to the state at `start` (to make games short). */
  tok?: number[][];
  /** Multiplies every duration in TIMING (e.g. 0.01 makes a 20 s grace 200 ms). */
  timeScale?: number;
  /** Replaces LIMITS.ratePerSec (test clients play far faster than people tap). */
  ratePerSec?: number;
}

interface Att {
  /** Member id; -1 before hello, -2 for a socket the server is closing (replaced / left). */
  mid: number;
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

function rollDie(): number {
  return cryptoInt(6) + 1;
}

/** Names: control characters stripped, trimmed, at most 16 characters (code points); empty -> "Player". */
export function cleanName(x: unknown): string {
  if (typeof x !== "string") return "Player";
  // eslint-disable-next-line no-control-regex
  const t = x.replace(/[\u0000-\u001f\u007f-\u009f\u2028\u2029]/g, "").trim();
  const cut = Array.from(t).slice(0, 16).join("").trim();
  return cut || "Player";
}

/** Catalog ids (avatar, frame): strings of at most 32 safe characters, else "". */
function cleanId(x: unknown): string {
  return typeof x === "string" && x.length <= 32 && /^[A-Za-z0-9_.:-]*$/.test(x) ? x : "";
}

const PID_RE = /^[A-Za-z0-9_-]{16,64}$/;

function isInt(x: unknown, lo: number, hi: number): x is number {
  return typeof x === "number" && Number.isInteger(x) && x >= lo && x <= hi;
}

// ---------- the Durable Object ----------

export class Room extends DurableObject<Env> {
  private room: RoomData | null;
  private hooks: TestHooks = {};
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
  private eventWindow = { start: 0, count: 0 };
  private reported = new WeakSet<object>();

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.room = ctx.storage.kv.get<RoomData>("room") ?? null;
    if (env.TEST_MODE === "1") this.hooks = ctx.storage.kv.get<TestHooks>("hooks") ?? {};
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
      settings: { teams: false, pair_ask: false },
      match: null,
      touched: now,
      emptySince: now, // nobody connected yet: a code nobody joins is dropped after TIMING.empty
      alarmAt: 0,
    };
    this.commit();
    return true;
  }

  /** GET /v1/rooms/<CODE>; null when the room doesn't exist. */
  async info(): Promise<{ code: string; open: boolean; members: number; started: boolean } | null> {
    const r = this.room;
    if (!r) return null;
    return {
      code: r.code,
      open: r.status !== "playing" && r.members.length < LIMITS.maxMembers,
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

  // ----- RPC from the admin API (src/admin.ts; no public route reaches these) -----

  /** The live room for the console; null when the room doesn't exist. */
  async adminSnapshot(): Promise<AdminSnapshot | null> {
    const r = this.room;
    if (!r) return null;
    const m = r.match;
    const colors = SEAT_COLORS[Math.max(1, r.members.length)];
    return {
      code: r.code,
      status: r.status,
      host: r.host,
      created: r.created,
      touched: r.touched,
      sockets: this.sockets().length,
      members: r.members.map((mm, j) => ({
        id: mm.id,
        pid: mm.pid,
        name: mm.name,
        avatar: mm.avatar,
        frame: mm.frame,
        online: this.online(mm.id),
        color:
          r.status === "playing" && m ? (m.seats.find((st) => st.id === mm.id && !st.left)?.color ?? -1) : colors[j],
      })),
      settings: { ...r.settings },
      match: m
        ? {
            n: m.n,
            state: m.state,
            seats: m.seats.map((st, k) => ({ ...this.seatsOut()[k], pid: this.seatPid(st), left: st.left })),
            deadline: r.status === "playing" ? Math.round(m.due) : 0,
            started_at: m.startedAt ?? 0,
          }
        : null,
    };
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
    if (!mem) return false;
    this.expel(mem, CLOSE.left, "kicked", "you were removed from the room");
    this.commit();
    return true;
  }

  /** A pid was banned: remember it (no rejoin) and remove that member if present. True if they were here. */
  async adminBan(pid: string, reason: string): Promise<boolean> {
    this.banCache.set(pid, { at: Date.now(), banned: true, reason });
    const mem = this.room?.members.find((m) => m.pid === pid);
    if (!mem) return false;
    this.expel(mem, CLOSE.banned, "banned", banMsg(reason));
    this.commit();
    return true;
  }

  /** A pid was unbanned: forget the cached flag. */
  async adminUnban(pid: string): Promise<void> {
    this.banCache.delete(pid);
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
    // (ban check) or a start (turn timers) awaits one D1 read, and that socket's next messages wait for it.
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
    if (msg.t === "ping") return this.send(ws, { t: "pong", now: Date.now() });

    const att = this.att(ws);
    if (att.mid === -2) return;
    if (att.mid < 0) {
      if (msg.t !== "hello") return this.error(ws, "bad_message", "say hello first");
      if (msg.v === 1 && typeof msg.pid === "string" && PID_RE.test(msg.pid)) {
        const ban = await this.banOf(msg.pid);
        if (ws.readyState !== 1 || this.att(ws).mid !== -1) return; // closed (or replaced) meanwhile
        if (!this.room) return this.fatal(ws, "not_found", "this room no longer exists");
        if (ban) {
          this.event("warn", "banned", `banned pid refused: ${ban}`.slice(0, 200), msg.pid);
          this.error(ws, "banned", banMsg(ban));
          this.closeWith(ws, CLOSE.banned, "banned");
          return;
        }
      }
      this.hello(ws, msg);
      this.commit();
      return;
    }
    let mem = r.members.find((m) => m.id === att.mid);
    if (!mem) {
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
      case "sync_req":
        this.sendSnapshot(ws);
        break;
      case "leave":
        this.leave(ws, mem);
        break;
      default:
        return this.error(ws, "bad_message", `unknown type ${String(msg.t).slice(0, 20)}`);
    }
    this.commit();
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
      await this.onAlarm();
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
    for (const mem of [...r.members]) {
      if (!mem.graceAt) continue;
      if (this.online(mem.id)) mem.graceAt = 0;
      else if (mem.graceAt <= now) this.graceOver(mem);
    }
    const m = r.match;
    if (r.status === "playing" && m && m.due && m.due <= now) this.step();
    this.commit();
  }

  // ---------- connection handling ----------

  private hello(ws: WebSocket, msg: Record<string, unknown>): void {
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
    let mem = (token && r.members.find((m) => m.token === token)) || r.members.find((m) => m.pid === pid);
    const now = Date.now();
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
      mem.name = name;
      mem.avatar = avatar;
      mem.frame = frame;
      mem.graceAt = 0;
      this.playerSeen(mem, false);
    } else {
      if (r.status === "playing") return this.fatal(ws, "started", "the match is in progress");
      if (r.members.length >= LIMITS.maxMembers) return this.fatal(ws, "full", "the room is full");
      mem = { id: r.nextId++, pid, token: randomToken(), name, avatar, frame, graceAt: 0 };
      r.members.push(mem);
      if (r.host < 0) r.host = mem.id;
      r.touched = now;
      this.playerSeen(mem, true);
    }
    ws.serializeAttachment({ mid: mem.id } satisfies Att);
    r.emptySince = 0;
    this.send(ws, { t: "welcome", token: mem.token, id: mem.id, code: r.code, host: r.host });

    const m = r.match;
    if (r.status === "playing" && m) {
      const seat = m.seats.find((st) => st.id === mem.id && !st.left);
      this.broadcast({ t: "presence", id: mem.id, online: true }, ws);
      this.sendSnapshot(ws);
      const s = m.state;
      if (seat && s.players[seat.color] === "cpu") {
        m.strikes[seat.color] = 0;
        this.act({ k: "mode", c: seat.color, mode: "human" });
        if (s.turn === seat.color || !m.due) this.planStep();
      } else if (!m.due) {
        this.planStep(); // bots were paused while nobody was online
      }
    } else {
      if (r.status === "over" && m) this.sendSnapshot(ws);
      this.broadcast(this.lobbyMsg());
    }
  }

  /** A socket closed or errored. */
  private dropped(ws: WebSocket): void {
    const r = this.room;
    if (!r) return;
    const att = this.att(ws);
    if (att.mid < 0) return;
    try {
      ws.serializeAttachment({ mid: -2 } satisfies Att);
    } catch {
      /* closed */
    }
    const mem = r.members.find((m) => m.id === att.mid);
    if (mem && !this.online(mem.id, ws)) {
      const now = Date.now();
      mem.graceAt = now + this.ms(TIMING.grace);
      if (r.status === "playing") this.broadcast({ t: "presence", id: mem.id, online: false }, ws);
      else this.broadcast(this.lobbyMsg(), ws);
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
      if (seat && m.state.players[seat.color] === "human") {
        this.act({ k: "mode", c: seat.color, mode: "cpu" });
        if (m.state.turn === seat.color) this.planStep();
      }
    } else {
      this.removeMember(mem);
      this.broadcast(this.lobbyMsg());
    }
  }

  private removeMember(mem: Member): void {
    const r = this.room!;
    r.members = r.members.filter((m) => m !== mem);
    if (r.host === mem.id) r.host = r.members.length ? r.members[0].id : -1;
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
        if (m.state.players[seat.color] !== "cpu") {
          this.act({ k: "mode", c: seat.color, mode: "cpu" });
          if (m.state.turn === seat.color) this.planStep();
        }
      }
      if (hostWas !== r.host) this.broadcast(this.lobbyMsg()); // tells everyone who the new host is
    } else {
      this.broadcast(this.lobbyMsg());
    }
    if (this.sockets().length === 0 && !r.emptySince) r.emptySince = Date.now();
  }

  // ---------- lobby ----------

  private settings(ws: WebSocket, mem: Member, msg: Record<string, unknown>): void {
    const r = this.room!;
    if (r.host !== mem.id) return this.error(ws, "not_host", "only the host changes settings");
    if (r.status === "playing") return this.error(ws, "bad_action", "the match is in progress");
    if (msg.teams !== undefined && typeof msg.teams !== "boolean") return this.error(ws, "bad_message", "teams: bool");
    if (msg.pair_ask !== undefined && typeof msg.pair_ask !== "boolean") {
      return this.error(ws, "bad_message", "pair_ask: bool");
    }
    if (typeof msg.teams === "boolean") r.settings.teams = msg.teams;
    if (typeof msg.pair_ask === "boolean") r.settings.pair_ask = msg.pair_ask;
    r.touched = Date.now();
    this.broadcast(this.lobbyMsg());
  }

  /** Why mem can't start the match now ([code, msg]), or null. */
  private startError(mem: Member): [string, string] | null {
    const r = this.room!;
    if (r.host !== mem.id) return ["not_host", "only the host starts the match"];
    if (r.status === "playing") return ["bad_action", "the match is in progress"];
    const k = r.members.length;
    if (k < 2) return ["too_few", "at least 2 players are needed"];
    if (r.settings.teams && k !== 4) return ["teams_need_4", "teams need exactly 4 players"];
    return null;
  }

  private start(ws: WebSocket, mem: Member, timers?: TurnTimers): void {
    const r = this.room!;
    const err = this.startError(mem);
    if (err) return this.error(ws, err[0], err[1]);
    const k = r.members.length;
    const colors = SEAT_COLORS[k];
    const players = ["off", "off", "off", "off"];
    for (const c of colors) players[c] = "human";
    const s = R.newGame(players, r.settings.teams, { pair_ask: r.settings.pair_ask });
    const seats: Seat[] = r.members.map((mm, j) => ({
      color: colors[j],
      id: mm.id,
      pid: mm.pid,
      name: mm.name,
      avatar: mm.avatar,
      frame: mm.frame,
      left: false,
    }));
    for (let c = 0; c < 4; c++) s.names[c] = "";
    for (const st of seats) s.names[st.color] = st.name;
    if (this.hooks.tok) {
      for (const st of seats) if (this.hooks.tok[st.color]) s.tok[st.color] = [...this.hooks.tok[st.color]];
    }
    const seedBytes = randomBytes(4);
    const now = Date.now();
    const m: Match = {
      seats,
      state: s,
      n: 0,
      due: 0,
      strikes: [0, 0, 0, 0],
      rng: new DataView(seedBytes.buffer).getUint32(0),
      startedAt: now,
      timers,
    };
    r.match = m;
    r.status = "playing";
    r.touched = now;
    this.db("match start", [
      D.insertMatch(this.env.DB, {
        code: r.code,
        started_at: now,
        players: seats.map((st) => ({ pid: st.pid ?? "", name: st.name, color: st.color, bot: false })),
        teams: r.settings.teams,
        pair_ask: r.settings.pair_ask,
      }),
    ]);
    this.broadcast({ t: "start", n: 0, seats: this.seatsOut(), state: s, h: R.stateHash(s) });
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
    const s = m.state;
    const seat = m.seats.find((st) => st.id === mem.id && !st.left);
    if (!seat || seat.color !== s.turn) return this.error(ws, "not_your_turn", "it is not your turn");
    const c = seat.color;
    let a: Action;
    if (msg.t === "roll") {
      if (s.phase !== "roll") return this.error(ws, "bad_action", `phase is ${s.phase}`);
      a = { k: "roll", c, v: this.dice() };
    } else if (msg.t === "move") {
      if (s.phase !== "choose") return this.error(ws, "bad_action", `phase is ${s.phase}`);
      if (!isInt(msg.i, 0, 3)) return this.error(ws, "bad_action", "i: token index 0-3");
      const i = msg.i;
      const u = R.units(s).find((uu) => uu.tokens.includes(i));
      if (!u) return this.error(ws, "bad_action", "that pawn can't move");
      a = { k: "move", c, i: u.token };
    } else {
      if (s.phase !== "pair_ask") return this.error(ws, "bad_action", `phase is ${s.phase}`);
      if (typeof msg.yes !== "boolean") return this.error(ws, "bad_message", "yes: bool");
      a = { k: "pair", c, yes: msg.yes };
    }
    m.strikes[c] = 0;
    if (s.players[c] === "cpu") this.act({ k: "mode", c, mode: "human" }); // acting yourself counts as "back"
    this.act(a);
    this.afterActs();
  }

  private back(mem: Member): void {
    const r = this.room!;
    const m = r.match;
    if (r.status !== "playing" || !m) return;
    const seat = m.seats.find((st) => st.id === mem.id && !st.left);
    if (!seat || m.state.players[seat.color] !== "cpu") return;
    m.strikes[seat.color] = 0;
    this.act({ k: "mode", c: seat.color, mode: "human" });
    if (m.state.turn === seat.color) this.planStep();
  }

  /** The current step is due: a timeout for a human, or a bot's action. */
  private step(): void {
    const m = this.room!.match!;
    const s = m.state;
    const c: number = s.turn;
    if (s.players[c] === "human") {
      m.strikes[c]++;
      this.autoAct(c, "easy", true);
      if (s.phase !== "over" && m.strikes[c] >= 2 && s.players[c] === "human") {
        this.act({ k: "mode", c, mode: "cpu" });
      }
    } else {
      if (!this.anyOnline()) {
        m.due = 0; // nobody is watching: pause the bots until somebody reconnects
        return;
      }
      this.autoAct(c, "normal", false);
    }
    this.afterActs();
  }

  private autoAct(c: number, level: string, timeout: boolean): void {
    const m = this.room!.match!;
    const s = m.state;
    if (s.phase === "roll") {
      this.act({ k: "roll", c, v: this.dice() });
    } else if (s.phase === "choose") {
      let i = timeout ? R.autoMoveToken(s) : -1;
      if (i < 0) {
        const g = new R.Mulberry32(0);
        g.state = m.rng;
        i = R.pickAi(s, R.movables(s), g, level);
        m.rng = g.state;
      }
      this.act({ k: "move", c, i });
    } else if (s.phase === "pair_ask") {
      this.act({ k: "pair", c, yes: true });
    }
  }

  /** Applies one action to the match and broadcasts it. */
  private act(a: Action): void {
    const r = this.room!;
    const m = r.match!;
    const s = m.state;
    R.applyAction(s, a);
    const n = m.n++;
    r.touched = Date.now();
    this.broadcast({ t: "act", n, a, h: R.stateHash(s) });
  }

  private afterActs(): void {
    const r = this.room!;
    const m = r.match!;
    if (m.state.phase === "over") this.finish();
    else this.planStep();
  }

  /** Sets the deadline (human) or the action time (bot) for the current step and announces it. */
  private planStep(): void {
    const r = this.room!;
    const m = r.match!;
    const s = m.state;
    if (r.status !== "playing" || s.phase === "over") {
      m.due = 0;
      return;
    }
    const now = Date.now();
    const c: number = s.turn;
    if (s.players[c] === "cpu") {
      if (!this.anyOnline()) {
        m.due = 0;
        return;
      }
      const [lo, hi] =
        s.phase === "roll" ? [TIMING.botRollMin, TIMING.botRollMax] : [TIMING.botStepMin, TIMING.botStepMax];
      m.due = now + this.ms(lo + Math.random() * (hi - lo));
    } else {
      const timers = (m.timers ?? TIMING) as unknown as Record<string, number>;
      const t = timers[s.phase] ?? TIMING.roll;
      m.due = now + this.ms(t);
    }
    this.broadcast({ t: "turn", c, deadline: Math.round(m.due), now });
  }

  private finish(): void {
    const r = this.room!;
    const m = r.match!;
    const s = m.state;
    r.status = "over";
    m.due = 0;
    this.matchOver();
    this.broadcast({
      t: "over",
      finished: [...(s.finished ?? [])],
      winner: s.winner,
      standings: R.standings(s),
    });
    // back to lobby rules: members still offline are dropped after the grace
    const now = Date.now();
    for (const mem of r.members) if (!this.online(mem.id) && !mem.graceAt) mem.graceAt = now + this.ms(TIMING.grace);
    this.broadcast(this.lobbyMsg());
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
    const colors = SEAT_COLORS[Math.max(1, r.members.length)];
    return {
      t: "lobby",
      code: r.code,
      host: r.host,
      members: r.members.map((m, j) => ({
        id: m.id,
        name: m.name,
        avatar: m.avatar,
        frame: m.frame,
        online: this.online(m.id),
        color: colors[j],
      })),
      settings: { ...r.settings },
      max: LIMITS.maxMembers,
      status: r.status,
    };
  }

  private seatsOut(): Array<Record<string, unknown>> {
    const m = this.room!.match!;
    return m.seats.map((st) => ({
      color: st.color,
      id: st.id,
      name: st.name,
      avatar: st.avatar,
      frame: st.frame,
      bot: m.state.players[st.color] === "cpu",
      online: !st.left && this.online(st.id),
    }));
  }

  /** sync (+ turn while playing) for one socket; lobby when there is no match. */
  private sendSnapshot(ws: WebSocket): void {
    const r = this.room!;
    const m = r.match;
    if (!m) return this.send(ws, this.lobbyMsg());
    this.send(ws, { t: "sync", n: m.n, seats: this.seatsOut(), state: m.state, h: R.stateHash(m.state) });
    if (r.status === "playing" && m.due) {
      this.send(ws, { t: "turn", c: m.state.turn, deadline: Math.round(m.due), now: Date.now() });
    } else if (r.status === "over") {
      this.send(ws, { t: "over", finished: [...(m.state.finished ?? [])], winner: m.state.winner, standings: R.standings(m.state) });
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

  private error(ws: WebSocket, code: string, msg: string): void {
    this.send(ws, { t: "error", code, msg });
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

  private anyOnline(): boolean {
    return this.sockets().length > 0;
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
    for (const mem of r.members) if (mem.graceAt) due.push(mem.graceAt);
    const next = Math.ceil(Math.min(...due));
    if (next !== r.alarmAt) {
      r.alarmAt = next;
      this.ctx.storage.setAlarm(next).catch((e) => this.storageFailed("setAlarm", e));
    }
    const sig = this.roomSig();
    if (sig !== r.dbSig) {
      const statusChanged = r.dbStatus !== r.status;
      r.dbSig = sig;
      r.dbStatus = r.status;
      this.roomChanged(statusChanged);
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
    this.room = null;
    this.hooks = {};
    await this.ctx.storage.deleteAlarm();
    await this.ctx.storage.deleteAll();
    // the room is gone anyway: give its last D1 writes a moment instead of leaving them to waitUntil alone
    await Promise.race([this.dbChain, new Promise((res) => setTimeout(res, 3000))]);
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
    return {
      code: r.code,
      created_at: r.created,
      host_pid: host?.pid ?? null,
      host_name: host?.name ?? null,
      status: r.status,
      members: r.members.length,
      online: r.members.filter((m) => this.online(m.id)).length,
      settings: { ...r.settings },
      closed_reason: null,
    };
  }

  /** What the rooms row shows, as a string: a change queues a (debounced) write. */
  private roomSig(): string {
    const r = this.room!;
    const ms = r.members.map((m) => `${m.id}${this.online(m.id) ? "+" : "-"}`).join(",");
    return `${r.status}|${r.host}|${ms}|${r.settings.teams ? 1 : 0}${r.settings.pair_ask ? 1 : 0}`;
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
    const now = Date.now();
    const last = this.playerSeenAt.get(mem.pid);
    if (!firstJoin && last !== undefined && now - last < TELEMETRY.playerRepeat) return;
    this.playerSeenAt.set(mem.pid, now);
    const p = { pid: mem.pid, name: mem.name, avatar: mem.avatar, frame: mem.frame, room: this.room!.code };
    this.db("player", D.playerSeen(this.env.DB, p, now, firstJoin));
  }

  private seatPid(st: Seat): string {
    return st.pid ?? this.room?.members.find((m) => m.id === st.id)?.pid ?? "";
  }

  private endMatchStmt(m: Match, result: D.MatchResult, now: number): D1PreparedStatement {
    const s = m.state;
    return D.endMatch(this.env.DB, {
      code: this.room!.code,
      started_at: m.startedAt ?? 0,
      ended_at: now,
      winner: result === "over" ? s.winner : null,
      finished: [...(s.finished ?? [])],
      actions: m.n,
      result,
    });
  }

  /** over: the matches row, matches+1 for every seat's player, wins+1 for the winners who stayed. */
  private matchOver(): void {
    const r = this.room!;
    const m = r.match!;
    const now = Date.now();
    const won = new Set<number>(R.winners(m.state));
    const stmts = [this.endMatchStmt(m, "over", now)];
    for (const st of m.seats) {
      const pid = this.seatPid(st);
      if (pid) stmts.push(D.playerResult(this.env.DB, pid, won.has(st.color) && !st.left, now));
    }
    this.db("match over", stmts);
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
  members: Array<{ id: number; pid: string; name: string; avatar: string; frame: string; online: boolean; color: number }>;
  settings: Settings;
  match: { n: number; state: LudoState; seats: Array<Record<string, unknown>>; deadline: number; started_at: number } | null;
}

function banMsg(reason: string): string {
  return reason && reason !== "banned" ? `You are banned from online play: ${reason}` : "You are banned from online play.";
}

function withTimeout<T>(p: Promise<T>, ms: number): Promise<T> {
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
