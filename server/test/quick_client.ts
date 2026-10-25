// Helpers for the quick-match tests: guest accounts (real sessions from POST /v1/auth/guest), a Matchmaker socket
// client, test hooks for the queues, and spies on the accounts / stats interfaces (globalThis, TEST_MODE only).
import { SELF } from "cloudflare:test";
import { expect } from "vitest";
import type { AccountsApi, OnlineMatchGrant, QuickStat } from "../src/accounts_shim";
import type { MmHooks } from "../src/matchmaker";
import { Client, E, newPid, type Msg } from "./room_client";

export interface Guest {
  pid: string;
  account: string;
  session: string;
}

/** A guest account for a fresh pid (the real accounts endpoint). */
export async function guest(pid = newPid()): Promise<Guest> {
  const r = await SELF.fetch("https://x/v1/auth/guest", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ pid }),
  });
  const body = (await r.json()) as Msg;
  expect(r.status, JSON.stringify(body)).toBe(200);
  return { pid, account: body.account.id, session: body.session };
}

export function mmStub(game: string, size: number) {
  return E.MATCHMAKER.get(E.MATCHMAKER.idFromName(`${game}:${size}`));
}

/** Hooks for one queue (the rooms it creates get `room`). Fast clients: rate limit off in rooms. */
export async function mmHooks(game: string, size: number, h: MmHooks): Promise<void> {
  await mmStub(game, size).testHooks({ ...h, room: { ratePerSec: 1000, ...(h.room ?? {}) } });
}

interface TestGlobals {
  __lzAccounts?: Partial<AccountsApi>;
  __lzQuickStats?: QuickStat[];
}
const G = globalThis as unknown as TestGlobals;

/** Records every grantOnlineMatch call (and still runs the real one unless `fail` says otherwise). */
export function spyGrants(opts: { fail?: number } = {}): OnlineMatchGrant[] {
  const calls: OnlineMatchGrant[] = [];
  let fails = opts.fail ?? 0;
  G.__lzAccounts = {
    ...(G.__lzAccounts ?? {}),
    grantOnlineMatch: async (_env, g) => {
      calls.push(JSON.parse(JSON.stringify(g)));
      if (fails > 0) {
        fails--;
        throw new Error("grant failed (test)");
      }
      const real = await import("../src/accounts");
      return real.grantOnlineMatch(_env as never, g);
    },
  };
  return calls;
}

export function resetSpies(): void {
  delete G.__lzAccounts;
  G.__lzQuickStats = [];
}

export function quickStats(): QuickStat[] {
  return (G.__lzQuickStats ??= []);
}

/** A socket on GET /v1/quick/ws. */
export class QuickClient {
  ws: WebSocket;
  log: Msg[] = [];
  private cursor = 0;
  private waiters: Array<() => void> = [];
  closed = false;
  closeCode = 0;

  private constructor(ws: WebSocket) {
    this.ws = ws;
    ws.addEventListener("message", (ev) => {
      this.log.push(JSON.parse(ev.data as string));
      this.wake();
    });
    ws.addEventListener("close", (ev) => {
      this.closed = true;
      this.closeCode = ev.code;
      this.wake();
    });
  }

  static async open(game: string, size: number, query = ""): Promise<QuickClient> {
    const r = await SELF.fetch(`https://x/v1/quick/ws?game=${game}&players=${size}${query}`, { headers: { Upgrade: "websocket" } });
    if (r.status !== 101 || !r.webSocket) throw new Error(`upgrade failed: ${r.status}`);
    r.webSocket.accept();
    return new QuickClient(r.webSocket);
  }

  /** Opens, says hello as g (name etc. optional) and waits for the first queued / error. */
  static async queue(game: string, size: number, g: Guest, name = "Me", extra: Msg = {}): Promise<QuickClient> {
    const q = await QuickClient.open(game, size);
    q.send({ t: "hello", v: 1, session: g.session, pid: g.pid, name, avatar: "pawn-red", frame: "classic", ...extra });
    return q;
  }

  send(o: Msg): void {
    this.ws.send(JSON.stringify(o));
  }

  close(): void {
    try {
      this.ws.close(1000, "bye");
    } catch {
      /* closed */
    }
  }

  private wake(): void {
    const w = this.waiters;
    this.waiters = [];
    for (const f of w) f();
  }

  async waitFor(pred: (m: Msg) => boolean, timeoutMs = 5000): Promise<Msg> {
    const deadline = Date.now() + timeoutMs;
    for (;;) {
      while (this.cursor < this.log.length) {
        const m = this.log[this.cursor++];
        if (pred(m)) return m;
      }
      if (this.closed) throw new Error(`socket closed (${this.closeCode}) while waiting; log ${JSON.stringify(this.log)}`);
      const left = deadline - Date.now();
      if (left <= 0) throw new Error(`timed out; log ${JSON.stringify(this.log)}`);
      await new Promise<void>((res) => {
        const t = setTimeout(res, left);
        this.waiters.push(() => {
          clearTimeout(t);
          res();
        });
      });
    }
  }

  wait(t: string, timeoutMs = 5000): Promise<Msg> {
    return this.waitFor((m) => m.t === t, timeoutMs);
  }

  /** The `matched` message (already received or still to come). */
  async matched(timeoutMs = 5000): Promise<Msg> {
    const m = this.log.find((x) => x.t === "matched");
    return m ?? this.wait("matched", timeoutMs);
  }

  async waitClosed(timeoutMs = 5000): Promise<number> {
    const deadline = Date.now() + timeoutMs;
    while (!this.closed) {
      if (Date.now() > deadline) throw new Error("socket did not close");
      await new Promise((res) => setTimeout(res, 20));
    }
    return this.closeCode;
  }
}

/** The room socket for a matched person (hello with the session, the room token and the queue identity). */
export async function joinMatched(code: string, token: string, g: Guest, name = "Me"): Promise<Client> {
  return Client.join(code, { pid: g.pid, name, token, session: g.session });
}

/** Queues these guests one after the other and returns their `matched` messages. */
export async function queueAll(game: string, size: number, gs: Guest[], names?: string[]): Promise<{ qs: QuickClient[]; matched: Msg[] }> {
  const qs: QuickClient[] = [];
  for (let k = 0; k < gs.length; k++) {
    const q = await QuickClient.queue(game, size, gs[k], names?.[k] ?? `Human${k + 1}`);
    await q.waitFor((m) => m.t === "queued" || m.t === "matched");
    qs.push(q);
  }
  const matched = await Promise.all(qs.map((q) => q.matched(8000)));
  return { qs, matched };
}

/** Every key path (a.b[].c) and every string value in a message tree. */
export function walk(o: unknown, path = "", out: { keys: string[]; strings: string[] } = { keys: [], strings: [] }) {
  if (Array.isArray(o)) o.forEach((x) => walk(x, `${path}[]`, out));
  else if (o && typeof o === "object") {
    for (const [k, v] of Object.entries(o)) {
      out.keys.push(`${path}.${k}`);
      walk(v, `${path}.${k}`, out);
    }
  } else if (typeof o === "string") out.strings.push(o);
  return out;
}
