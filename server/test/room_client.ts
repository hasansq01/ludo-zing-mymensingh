// Test client for the Room protocol: a WebSocket through SELF.fetch, a message log with sequential waits, and a
// deterministic replica of the match (the same rules functions a Godot client uses) that checks every `act` hash.
import { SELF, env } from "cloudflare:test";
import { expect } from "vitest";
import type { Env, TestHooks } from "../src/room";
import { applyAction, units, type LudoState } from "../src/rules/ludo";
import { stateHash } from "../src/rules/hash";
import { applySlAction, turnColor, type SlAction, type SlState } from "../src/rules/sl";
import { slStateHash } from "../src/rules/sl_hash";

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export type Msg = Record<string, any>;

export const E = env as unknown as Env;

export function stubFor(code: string) {
  return E.ROOMS.get(E.ROOMS.idFromName(code));
}

export async function createRoom(hooks?: TestHooks): Promise<string> {
  const r = await SELF.fetch("https://x/v1/rooms", { method: "POST" });
  expect(r.status).toBe(200);
  const { code } = (await r.json()) as { code: string };
  if (hooks) await stubFor(code).testHooks(hooks);
  return code;
}

export async function roomInfo(code: string): Promise<{ status: number; body: Msg }> {
  const r = await SELF.fetch(`https://x/v1/rooms/${code}`);
  return { status: r.status, body: (await r.json()) as Msg };
}

let pidNo = 0;
export function newPid(): string {
  pidNo++;
  return `testpid-${String(pidNo).padStart(4, "0")}-${Math.random().toString(36).slice(2, 10)}`;
}

export function sleep(ms: number): Promise<void> {
  return new Promise((res) => setTimeout(res, ms));
}

export interface Policy {
  /** Which unit to move: index into units(s). Default: random. */
  pick?: (s: LudoState) => number;
  pairYes?: boolean;
}

/** The state hash for a game ("ludo" | "sl"). */
export function hashOf(game: string, s: unknown): string {
  return game === "sl" ? slStateHash(s as SlState) : stateHash(s as LudoState);
}

export class Client {
  ws: WebSocket;
  log: Msg[] = [];
  /** Date.now() when each log entry arrived. */
  at: number[] = [];
  private cursor = 0;
  private waiters: Array<() => void> = [];
  closed = false;
  closeCode = 0;

  // identity
  pid: string;
  name: string;
  id = -1;
  token = "";

  /** Sent as `session` in hello when set. */
  session: string | undefined;

  // replica
  game = "ludo";
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  state: any = null;
  n = 0;
  seats: Msg[] = [];
  hashMismatches = 0;
  orderErrors = 0;
  acts = 0;

  /** When true, the client plays its own turns as soon as a `turn` for its colour arrives. */
  autoplay = false;
  policy: Policy = {};
  sent: Msg[] = [];

  private constructor(ws: WebSocket, pid: string, name: string) {
    this.ws = ws;
    this.pid = pid;
    this.name = name;
    ws.addEventListener("message", (ev) => this.onMessage(JSON.parse(ev.data as string)));
    ws.addEventListener("close", (ev) => {
      this.closed = true;
      this.closeCode = ev.code;
      this.wake();
    });
  }

  /** Opens a socket (no hello yet). */
  static async open(code: string, pid = newPid(), name = "Tester"): Promise<Client> {
    const r = await SELF.fetch(`https://x/v1/rooms/${code}/ws`, { headers: { Upgrade: "websocket" } });
    if (r.status !== 101 || !r.webSocket) throw new Error(`upgrade failed: ${r.status}`);
    r.webSocket.accept();
    return new Client(r.webSocket, pid, name);
  }

  /** Opens a socket, says hello and waits for welcome. */
  static async join(code: string, opts: { pid?: string; name?: string; token?: string; session?: string } = {}): Promise<Client> {
    const c = await Client.open(code, opts.pid ?? newPid(), opts.name ?? "Tester");
    c.session = opts.session;
    c.hello(opts.token);
    const w = await c.waitFor((m) => m.t === "welcome" || m.t === "error");
    if (w.t === "error") throw new Error(`join refused: ${w.code}`);
    return c;
  }

  hello(token?: string): void {
    this.send({ t: "hello", v: 1, pid: this.pid, name: this.name, avatar: "a1", frame: "f1", token, session: this.session });
  }

  send(o: Msg): void {
    this.sent.push(o);
    this.ws.send(JSON.stringify(o));
  }

  close(): void {
    try {
      this.ws.close(1000, "bye");
    } catch {
      /* closed */
    }
  }

  get color(): number {
    const st = this.seats.find((s) => s.id === this.id);
    return st ? st.color : -1;
  }

  private wake(): void {
    const w = this.waiters;
    this.waiters = [];
    for (const f of w) f();
  }

  private onMessage(m: Msg): void {
    this.log.push(m);
    this.at.push(Date.now());
    if (m.t === "welcome") {
      this.id = m.id;
      this.token = m.token;
    } else if (m.t === "start" || m.t === "sync") {
      this.game = m.game ?? "ludo";
      this.state = JSON.parse(JSON.stringify(m.state));
      this.n = m.n;
      this.seats = m.seats;
      expect(hashOf(this.game, this.state)).toBe(m.h);
    } else if (m.t === "act" && this.state) {
      if (m.n !== this.n) this.orderErrors++;
      if (this.game === "sl") applySlAction(this.state, m.a as SlAction);
      else applyAction(this.state, m.a);
      this.n = m.n + 1;
      this.acts++;
      if (hashOf(this.game, this.state) !== m.h) this.hashMismatches++;
    } else if (m.t === "turn" && this.autoplay) {
      this.playTurn(m.c);
    }
    this.wake();
  }

  /** Plays one step for colour c if it is ours and a human (not a bot) holds it. */
  playTurn(c: number): void {
    const s = this.state;
    if (this.game === "sl") {
      const me = s?.players?.find((p: { c: number }) => p.c === c);
      if (!s || c !== this.color || turnColor(s) !== c || !me || me.cpu || s.phase !== "roll") return;
      this.send({ t: "roll", n: this.n });
      return;
    }
    if (!s || c !== this.color || s.turn !== c || s.players[c] !== "human") return;
    if (s.phase === "roll") this.send({ t: "roll", n: this.n });
    else if (s.phase === "choose") {
      const us = units(s);
      const k = this.policy.pick ? this.policy.pick(s) : Math.floor(Math.random() * us.length);
      this.send({ t: "move", n: this.n, i: us[k].token });
    } else if (s.phase === "pair_ask") this.send({ t: "pair", n: this.n, yes: this.policy.pairYes ?? true });
  }

  /** The next message (after the previous wait's match) that satisfies pred. */
  async waitFor(pred: (m: Msg) => boolean, timeoutMs = 5000): Promise<Msg> {
    const deadline = Date.now() + timeoutMs;
    for (;;) {
      while (this.cursor < this.log.length) {
        const m = this.log[this.cursor++];
        if (pred(m)) return m;
      }
      if (this.closed) throw new Error(`socket closed (${this.closeCode}) while waiting`);
      const left = deadline - Date.now();
      if (left <= 0) throw new Error(`timed out; last messages: ${JSON.stringify(this.log.slice(-5))}`);
      await new Promise<void>((res) => {
        const t = setTimeout(res, left);
        this.waiters.push(() => {
          clearTimeout(t);
          res();
        });
      });
    }
  }

  /** Waits for a message of type t. */
  wait(t: string, timeoutMs = 5000): Promise<Msg> {
    return this.waitFor((m) => m.t === t, timeoutMs);
  }

  /** Waits until the socket closes. */
  async waitClosed(timeoutMs = 5000): Promise<number> {
    const deadline = Date.now() + timeoutMs;
    while (!this.closed) {
      if (Date.now() > deadline) throw new Error("socket did not close");
      await new Promise<void>((res) => {
        const t = setTimeout(res, 50);
        this.waiters.push(() => {
          clearTimeout(t);
          res();
        });
      });
    }
    return this.closeCode;
  }

  /** Skips everything received so far. */
  skip(): void {
    this.cursor = this.log.length;
  }

  /** All messages of type t received so far. */
  all(t: string): Msg[] {
    return this.log.filter((m) => m.t === t);
  }
}

/** A room with k members (first = host), all welcomed and in the lobby. */
export async function lobbyOf(k: number, hooks: TestHooks = {}): Promise<{ code: string; cs: Client[] }> {
  const code = await createRoom({ ratePerSec: 1000, ...hooks }); // (the rate-limit test passes its own)
  const cs: Client[] = [];
  for (let j = 0; j < k; j++) {
    const c = await Client.join(code, { name: `P${j + 1}` });
    await c.waitFor((m) => m.t === "lobby" && m.members.length === j + 1);
    cs.push(c);
  }
  return { code, cs };
}

/** Starts the match from the host and waits for every client's start. */
export async function startAll(cs: Client[]): Promise<Msg[]> {
  cs[0].send({ t: "start" });
  return Promise.all(cs.map((c) => c.wait("start")));
}

/** Waits for `over` on every client (autoplay assumed), then checks the replicas. */
export async function finishAll(cs: Client[], timeoutMs = 25_000): Promise<Msg[]> {
  const overs = await Promise.all(cs.map((c) => c.wait("over", timeoutMs)));
  for (const c of cs) {
    expect(c.hashMismatches).toBe(0);
    expect(c.orderErrors).toBe(0);
    expect(c.state!.phase).toBe("over");
  }
  return overs;
}

/** Token progress near the end, so a game takes a few dozen actions (home column: no captures, no pairs). */
export const NEAR_GOAL = [
  [52, 53, 54, 55],
  [52, 53, 54, 55],
  [52, 53, 54, 55],
  [52, 53, 54, 55],
];
