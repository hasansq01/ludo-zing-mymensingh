// The Matchmaker Durable Object: one quick-match queue per game and table size (idFromName("ludo:4"), "sl:2", ...).
// ONLINE_V2.md §3, PROTOCOL.md "Quick match".
//
// People connect (GET /v1/quick/ws, src/quick.ts), say hello with their session and wait. Waiting people are grouped
// first come, first served: a full table of people is matched at once; otherwise, once the oldest has waited their
// randomised 4-9 s (3-5 s when nobody had queued for a while), everyone waiting is seated together and the empty seats
// get ghosts (src/ghosts.ts). The Matchmaker creates the room (Room.initQuick: the humans are pre-registered, the room
// is closed to anyone else), tells each person `matched {code, token}` and closes their socket; they then connect to
// the room like any friend room.
//
// Hibernation-friendly: the queue lives in the sockets' attachments (each waiting socket carries its entry: account,
// identity, when it queued, its wait), the few counters in one storage value, and one alarm is set to the next due
// event. An evicted object resumes from those on the next message or alarm.
import { DurableObject } from "cloudflare:workers";
import * as D from "./db";
import { accounts, quickStat, type GameKind } from "./accounts_shim";
import { coinTable } from "./econ";
import { holdEntry, refundEntry, seatEntries } from "./economy";
import {
  CLOSE,
  PID_RE,
  cleanId,
  cleanName,
  isGame,
  isSessionShape,
  pawnFor,
  randomCode,
  withTimeout,
  type Env,
  type QuickSpec,
  type TestHooks,
} from "./room";

export const QUICK_SIZES = [2, 4] as const;

export const MM = {
  waitMin: 4_000, // the oldest waiting person waits this long (uniform in [min, max]) before ghosts fill the table
  waitMax: 9_000,
  idleAfter: 120_000, // nobody queued for this long before you: a shorter wait
  idleWaitMin: 3_000,
  idleWaitMax: 5_000,
  helloTimeout: 10_000, // a socket that hasn't said hello by then is closed
  maxSockets: 1_000,
  ratePerSec: 10,
  maxMsgBytes: 4_096,
  readTimeout: 2_000,
};

type Stage = "new" | "queued" | "matching" | "done";

interface MmAtt {
  st: Stage;
  opened: number;
  /** A session from the query string (?session=), used when the hello has none. */
  qs?: string;
  acc?: string;
  pid?: string;
  name?: string;
  avatar?: string;
  frame?: string;
  /** Pawn skin, one the account owns ("" = Classic). */
  pawn?: string;
  level?: number;
  since?: number;
  seq?: number;
  /** This entry's wait (ms) before ghosts may fill its table. */
  wait?: number;
  /** The position last sent (1-based), to send `queued` only on changes. */
  pos?: number;
  /** Coin tables: the entry held for this queue entry (ECONOMY_V1.md §3); refunded unless it reaches a room. */
  ent?: string;
}

interface Meta {
  game: GameKind;
  size: number;
  /** The coin table (ECONOMY_V1.md §3); missing in queues created before Economy v1: practice. */
  table?: string;
  /** Epoch ms since the queue has been empty (0 while someone waits). */
  emptySince: number;
  seq: number;
  alarmAt: number;
}

/** Test-only knobs (TEST_MODE "1"): set through testHooks() via RPC. */
export interface MmHooks {
  /** Multiplies every duration in MM (the waits, the hello timeout). */
  timeScale?: number;
  /** A fixed wait (ms, before the time scale) instead of the random one. */
  wait?: number;
  /** Test hooks every room this matchmaker creates gets (dice, short games, time scale). */
  room?: TestHooks;
}

interface Entry {
  ws: WebSocket;
  att: MmAtt;
}

export class Matchmaker extends DurableObject<Env> {
  private meta: Meta | null;
  private hooks: MmHooks = {};
  private chain: Promise<void> = Promise.resolve();
  private rate = new WeakMap<WebSocket, { start: number; count: number }>();
  private queue = new WeakMap<WebSocket, Promise<void>>();

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair('{"t":"ping"}', '{"t":"pong"}')); // keep-alives never wake the DO
    this.meta = ctx.storage.kv.get<Meta>("meta") ?? null;
    if (env.TEST_MODE === "1") this.hooks = ctx.storage.kv.get<MmHooks>("hooks") ?? {};
  }

  // ----- RPC -----

  /** Tests only. */
  async testHooks(h: MmHooks): Promise<void> {
    if (this.env.TEST_MODE !== "1") throw new Error("test hooks are disabled");
    this.hooks = { ...h };
    this.ctx.storage.kv.put("hooks", this.hooks);
  }

  /** For the admin console: how many people wait and for how long. */
  async adminStatus(): Promise<{ game: string; size: number; queued: number; oldest_wait_ms: number; sockets: number }> {
    const q = this.waiting();
    const now = Date.now();
    return {
      game: this.meta?.game ?? "",
      size: this.meta?.size ?? 0,
      queued: q.length,
      oldest_wait_ms: q.length ? now - (q[0].att.since ?? now) : 0,
      sockets: this.ctx.getWebSockets().length,
    };
  }

  // ----- the socket -----

  async fetch(req: Request): Promise<Response> {
    if (req.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
      return new Response("expected a websocket upgrade", { status: 426 });
    }
    const url = new URL(req.url);
    const game = url.searchParams.get("game") ?? "ludo";
    const size = Number(url.searchParams.get("players") ?? "2");
    const table = url.searchParams.get("table") ?? "practice";
    if (!isGame(game) || !(QUICK_SIZES as readonly number[]).includes(size) || !coinTable(table)) {
      return Response.json({ error: "bad_request" }, { status: 400 });
    }
    if (!this.meta) {
      this.meta = { game, size, table, emptySince: Date.now(), seq: 0, alarmAt: 0 };
      this.save();
    } else if (this.meta.game !== game || this.meta.size !== size || (this.meta.table ?? "practice") !== table) {
      return Response.json({ error: "bad_request" }, { status: 400 });
    }
    if (this.ctx.getWebSockets().length >= MM.maxSockets) return Response.json({ error: "busy" }, { status: 503 });
    const pair = new WebSocketPair();
    const [client, server] = [pair[0], pair[1]];
    this.ctx.acceptWebSocket(server);
    const qs = url.searchParams.get("session");
    const att: MmAtt = { st: "new", opened: Date.now() };
    if (isSessionShape(qs)) att.qs = qs;
    server.serializeAttachment(att);
    this.schedule();
    return new Response(null, { status: 101, webSocket: client });
  }

  async webSocketMessage(ws: WebSocket, data: string | ArrayBuffer): Promise<void> {
    const prev = this.queue.get(ws);
    const run = prev ? prev.then(() => this.onMessage(ws, data)) : this.onMessage(ws, data);
    const tail = run.catch((e) => console.error("matchmaker message failed:", e));
    this.queue.set(ws, tail);
    try {
      await run;
    } finally {
      if (this.queue.get(ws) === tail) this.queue.delete(ws);
    }
  }

  async webSocketClose(ws: WebSocket, code: number): Promise<void> {
    this.gone(ws);
    try {
      ws.close(code === 1005 || code === 1006 ? 1000 : code, "bye");
    } catch {
      /* closed */
    }
  }

  async webSocketError(ws: WebSocket): Promise<void> {
    this.gone(ws);
  }

  async alarm(): Promise<void> {
    if (this.meta) this.meta.alarmAt = 0;
    await this.tick();
  }

  // ----- messages -----

  private async onMessage(ws: WebSocket, data: string | ArrayBuffer): Promise<void> {
    if (!this.allow(ws)) return;
    if (typeof data !== "string" || data.length > MM.maxMsgBytes) return this.error(ws, "bad_message", "text frames only, at most 4 KB");
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
    if (!att) return;
    if (att.st === "new") {
      if (msg.t !== "hello") return this.error(ws, "bad_message", "say hello first");
      return this.hello(ws, att, msg);
    }
    if (att.st !== "queued") return; // matching / done: nothing more to say
    if (msg.t === "cancel") {
      this.finishSocket(ws, { t: "cancelled" }, 1000, "cancelled");
      await this.tick();
      return;
    }
    if (msg.t === "hello") return this.error(ws, "bad_message", "already said hello");
    return this.error(ws, "bad_message", `unknown type ${String(msg.t).slice(0, 20)}`);
  }

  private async hello(ws: WebSocket, att: MmAtt, msg: Record<string, unknown>): Promise<void> {
    if (msg.v !== 1) return this.fatal(ws, "version", "unsupported protocol version");
    if (typeof msg.pid !== "string" || !PID_RE.test(msg.pid)) {
      return this.fatal(ws, "bad_message", "pid must be 16-64 characters of [A-Za-z0-9_-]");
    }
    const pid = msg.pid;
    const session = isSessionShape(msg.session) ? msg.session : att.qs;
    if (!session) return this.fatal(ws, "session", "quick match needs a session (POST /v1/auth/guest)");
    att.st = "matching"; // (busy: a second hello while this one is checked is ignored)
    ws.serializeAttachment(att);

    const env = this.env;
    const A = accounts(env);
    let account: string | null = null;
    let ban: string | null = null;
    let level = 1;
    let prof: { name: string; avatar: string; frame: string; pawn?: string; pawns?: string[] } | null = null;
    let maintenance: string | null = null;
    try {
      const cfg = await withTimeout(D.readConfig(env.DB), MM.readTimeout);
      if (cfg.maintenance) maintenance = cfg.motd || "Online play is down for maintenance. Please try again later.";
    } catch (e) {
      console.error("config read failed (allowing):", e);
    }
    if (!maintenance) {
      try {
        const v = await withTimeout(A.verifySession(env, session), MM.readTimeout);
        if (v?.account_id) {
          account = v.account_id;
          if (v.banned) ban = v.ban_reason || "banned";
        }
      } catch (e) {
        console.error("verifySession failed:", e);
      }
      if (account && !ban) {
        try {
          const legacy = await withTimeout(D.readBan(env.DB, pid), MM.readTimeout);
          if (legacy?.banned) ban = legacy.reason || "banned";
          const pa = await withTimeout(A.accountForPid(env, pid), MM.readTimeout);
          if (pa?.banned) ban = pa.ban_reason || "banned";
        } catch (e) {
          console.error("ban check failed (allowing):", e);
        }
      }
      if (account && !ban) {
        try {
          const p = await withTimeout(A.getPublicProfile(env, account), MM.readTimeout);
          if (p) {
            prof = p;
            if (Number.isFinite(p.level)) level = Math.max(1, Math.trunc(p.level));
          }
        } catch (e) {
          console.error("profile read failed:", e);
        }
      }
    }
    if (ws.readyState !== 1) return;
    if (maintenance) return this.fatal(ws, "maintenance", maintenance);
    if (!account) return this.fatal(ws, "session", "your session is not valid: sign in again");
    if (ban) {
      this.error(ws, "banned", ban !== "banned" ? `You are banned from online play: ${ban}` : "You are banned from online play.");
      this.closeWith(ws, CLOSE.banned, "banned");
      return;
    }

    // one queue entry per account: a newer connection takes the older one's place (and keeps its position)
    const now = Date.now();
    let since = now;
    let seq = -1;
    let wait = -1;
    let ent: string | undefined;
    for (const other of this.ctx.getWebSockets()) {
      if (other === ws) continue;
      const oa = this.att(other);
      if (!oa || oa.acc !== account) continue;
      if (oa.st === "matching") return this.fatal(ws, "busy", "you are being matched on another connection");
      if (oa.st !== "queued") continue;
      since = oa.since ?? now;
      seq = oa.seq ?? -1;
      wait = oa.wait ?? -1;
      ent = oa.ent; // the newer connection takes over the entry already paid
      delete oa.ent;
      other.serializeAttachment(oa);
      this.finishSocket(other, { t: "error", code: "replaced", msg: "you queued again on another connection" }, CLOSE.replaced, "replaced");
    }
    const meta = this.meta!;
    const t = coinTable(meta.table ?? "practice");
    if (t && t.entry > 0 && !ent) {
      // a coin table: the entry is taken now and given back if this person leaves the queue
      let h: Awaited<ReturnType<typeof holdEntry>>;
      try {
        h = await holdEntry(env as never, { account_id: account, game: meta.game, size: meta.size, tier: t.id });
      } catch (e) {
        console.error("holdEntry failed:", e);
        return this.fatal(ws, "busy", "could not take the entry: try again");
      }
      if (!h.ok) {
        if (h.error === "coins") {
          this.send(ws, { t: "error", code: "coins", msg: "not enough coins for this table", short: h.short });
          return this.closeWith(ws, CLOSE.fatal, "coins");
        }
        if (h.error === "locked") {
          this.send(ws, { t: "error", code: "locked", msg: `this table opens at level ${h.level}`, level: h.level });
          return this.closeWith(ws, CLOSE.fatal, "locked");
        }
        return this.fatal(ws, "session", "your account can't play this table");
      }
      ent = h.entry_id;
      if (ws.readyState !== 1) {
        // gone while paying: give it back
        this.ctx.waitUntil(refundEntry(env as never, ent, "gone").then(() => undefined));
        return;
      }
    }
    const fresh = seq < 0;
    if (fresh) {
      seq = meta.seq++;
      const idle = this.waiting().length === 0 && meta.emptySince > 0 && now - meta.emptySince >= this.ms(MM.idleAfter);
      wait = this.hooks.wait !== undefined && this.env.TEST_MODE === "1" ? this.hooks.wait : idle ? span(MM.idleWaitMin, MM.idleWaitMax) : span(MM.waitMin, MM.waitMax);
      wait = this.ms(wait);
    }
    const entry: MmAtt = {
      st: "queued",
      opened: att.opened,
      acc: account,
      pid,
      name: cleanName(msg.name ?? prof?.name),
      avatar: cleanId(msg.avatar ?? prof?.avatar ?? ""),
      frame: cleanId(msg.frame ?? prof?.frame ?? ""),
      pawn: pawnFor(msg.pawn ?? prof?.pawn, prof?.pawns), // only a skin the account owns
      level,
      since,
      seq,
      wait,
    };
    if (ent) entry.ent = ent;
    ws.serializeAttachment(entry);
    meta.emptySince = 0;
    this.save();
    if (fresh) this.ctx.waitUntil(quickStat(env, { game: meta.game, size: meta.size, queued: 1 }));
    await this.tick();
  }

  // ----- the queue -----

  /** Waiting entries, first come first served. */
  private waiting(): Entry[] {
    const out: Entry[] = [];
    for (const ws of this.ctx.getWebSockets()) {
      const att = this.att(ws);
      if (att?.st === "queued" && ws.readyState === 1) out.push({ ws, att });
    }
    out.sort((a, b) => (a.att.since! - b.att.since!) || (a.att.seq! - b.att.seq!));
    return out;
  }

  /** Runs one grouping pass after the previous one (passes await room creation). */
  private tick(): Promise<void> {
    const p = this.chain.then(() => this.tickNow());
    this.chain = p.catch((e) => console.error("matchmaker tick failed:", e));
    return this.chain;
  }

  private async tickNow(): Promise<void> {
    const meta = this.meta;
    if (!meta) return;
    const now = Date.now();
    // sockets that never said hello
    for (const ws of this.ctx.getWebSockets()) {
      const att = this.att(ws);
      if (att?.st === "new" && now >= att.opened + this.ms(MM.helloTimeout)) this.fatal(ws, "bad_message", "say hello first");
    }
    let q = this.waiting();
    while (q.length >= meta.size) await this.group(q.splice(0, meta.size), 0);
    if (q.length && now >= q[0].att.since! + q[0].att.wait!) await this.group(q, meta.size - q.length);
    q = this.waiting();
    if (!q.length && !meta.emptySince) meta.emptySince = Date.now();
    this.sendPositions(q);
    this.schedule();
  }

  /** `queued {position, eta_s}` to every waiting entry whose position changed (always after its hello). */
  private sendPositions(q: Entry[]): void {
    const meta = this.meta!;
    const now = Date.now();
    q.forEach((e, k) => {
      const pos = k + 1;
      if (e.att.pos === pos) return;
      // the first table fills at the oldest entry's deadline; later entries wait for their own
      const head = k < meta.size ? q[0].att : e.att;
      const eta = Math.max(1, Math.ceil((head.since! + head.wait! - now) / 1000) + 1);
      e.att.pos = pos;
      e.ws.serializeAttachment(e.att);
      this.send(e.ws, { t: "queued", position: pos, eta_s: eta });
    });
  }

  /** Seats these entries (and `ghosts` ghosts) in a new quick room and tells them where to go. */
  private async group(entries: Entry[], ghosts: number): Promise<void> {
    const meta = this.meta!;
    for (const e of entries) {
      e.att.st = "matching";
      e.ws.serializeAttachment(e.att);
    }
    const t = coinTable(meta.table ?? "practice")!;
    const spec: QuickSpec = {
      game: meta.game,
      size: meta.size,
      table: { tier: t.id, entry: t.entry },
      humans: entries.map((e) => ({
        account_id: e.att.acc!,
        pid: e.att.pid!,
        name: e.att.name ?? "Player",
        avatar: e.att.avatar ?? "",
        frame: e.att.frame ?? "",
        pawn: e.att.pawn ?? "",
        level: e.att.level ?? 1,
        entry_id: e.att.ent,
      })),
    };
    if (this.env.TEST_MODE === "1" && this.hooks.room) spec.hooks = this.hooks.room;
    let code = "";
    let res: { tokens: Record<string, string> } | null = null;
    for (let attempt = 0; attempt < 8 && !res; attempt++) {
      code = randomCode();
      try {
        res = await this.env.ROOMS.get(this.env.ROOMS.idFromName(code)).initQuick(code, spec);
      } catch (e) {
        console.error("initQuick failed:", e);
        break;
      }
    }
    if (!res) {
      // could not create a room: everyone goes back to the queue (same place) and is retried with the next pass
      for (const e of entries) {
        if (e.ws.readyState !== 1) continue;
        e.att.st = "queued";
        e.att.wait = Date.now() - e.att.since! + 2_000; // retry in 2 s
        e.ws.serializeAttachment(e.att);
      }
      return;
    }
    const now = Date.now();
    let waited = 0;
    const ents: string[] = [];
    for (const e of entries) {
      waited += now - e.att.since!;
      if (e.att.ent) ents.push(e.att.ent);
      delete e.att.ent; // the room owns the entry now (it refunds it if the match never happens)
      this.matchedSocket(e.ws, { t: "matched", code, token: res.tokens[e.att.acc!] ?? "" });
    }
    if (ents.length) this.ctx.waitUntil(seatEntries(this.env as never, ents, code).catch((e) => console.error("seatEntries failed:", e)));
    this.ctx.waitUntil(
      quickStat(this.env, { game: meta.game, size: meta.size, matched: entries.length, ghost_filled: ghosts, wait_ms: waited }),
    );
  }

  private gone(ws: WebSocket): void {
    const att = this.att(ws);
    if (!att || att.st === "done") return;
    const wasQueued = att.st === "queued";
    this.release(att);
    att.st = "done";
    try {
      ws.serializeAttachment(att);
    } catch {
      /* closed */
    }
    if (wasQueued) this.ctx.waitUntil(this.tick()); // cancel on close; positions move up
  }

  // ----- timers and storage -----

  private schedule(): void {
    const meta = this.meta;
    if (!meta) return;
    const due: number[] = [];
    for (const ws of this.ctx.getWebSockets()) {
      const att = this.att(ws);
      if (att?.st === "new") due.push(att.opened + this.ms(MM.helloTimeout));
    }
    const q = this.waiting();
    if (q.length) due.push(q[0].att.since! + q[0].att.wait!);
    const next = due.length ? Math.ceil(Math.min(...due)) : 0;
    if (next && next !== meta.alarmAt) {
      meta.alarmAt = next;
      this.ctx.storage.setAlarm(next).catch((e) => console.error("setAlarm failed:", e));
    }
    this.save();
  }

  private save(): void {
    if (this.meta) this.ctx.storage.kv.put("meta", this.meta);
  }

  private ms(t: number): number {
    return t * (this.env.TEST_MODE === "1" ? (this.hooks.timeScale ?? 1) : 1);
  }

  // ----- sockets -----

  private att(ws: WebSocket): MmAtt | null {
    try {
      return (ws.deserializeAttachment() as MmAtt | null) ?? null;
    } catch {
      return null;
    }
  }

  private allow(ws: WebSocket): boolean {
    const now = Date.now();
    let w = this.rate.get(ws);
    if (!w || now - w.start >= 1000) {
      w = { start: now, count: 0 };
      this.rate.set(ws, w);
    }
    return ++w.count <= MM.ratePerSec;
  }

  private send(ws: WebSocket, msg: unknown): void {
    try {
      ws.send(JSON.stringify(msg));
    } catch {
      /* closing */
    }
  }

  private error(ws: WebSocket, code: string, msg: string): void {
    this.send(ws, { t: "error", code, msg });
  }

  private fatal(ws: WebSocket, code: string, msg: string): void {
    this.error(ws, code, msg);
    this.closeWith(ws, CLOSE.fatal, code);
  }

  /** Sends a last message, marks the socket done and closes it. */
  private finishSocket(ws: WebSocket, last: unknown, code: number, reason: string): void {
    this.send(ws, last);
    this.closeWith(ws, code, reason);
  }

  /** `matched` is the last message, but the client closes the socket: a close right behind a frame can make some
   *  WebSocket clients (Godot's WebSocketPeer over wss) drop that frame. The socket is marked done (later messages
   *  are ignored) and costs nothing while it hibernates until the client closes it. */
  private matchedSocket(ws: WebSocket, last: unknown): void {
    this.send(ws, last);
    const att = this.att(ws) ?? { st: "done" as Stage, opened: 0 };
    att.st = "done";
    try {
      ws.serializeAttachment(att);
    } catch {
      /* gone */
    }
  }

  /** Gives back the coin-table entry of a queue entry that won't reach a room (cancel, close, replaced, error). */
  private release(att: MmAtt): void {
    if (!att.ent) return;
    const id = att.ent;
    delete att.ent;
    this.ctx.waitUntil(refundEntry(this.env as never, id, "queue").then(() => undefined, (e) => console.error("refundEntry failed:", e)));
  }

  private closeWith(ws: WebSocket, code: number, reason: string): void {
    const att = this.att(ws) ?? { st: "done" as Stage, opened: 0 };
    this.release(att);
    att.st = "done";
    try {
      ws.serializeAttachment(att);
      ws.close(code, reason);
    } catch {
      /* gone */
    }
  }
}

function span(lo: number, hi: number): number {
  return lo + Math.random() * (hi - lo);
}
