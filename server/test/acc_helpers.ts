// Helpers for the accounts / wallet / leaderboard tests: /v1 calls through SELF with a session and a test clock
// (X-Test-Now, honoured only under TEST_MODE), guest accounts, direct D1 reads.
import { SELF, env } from "cloudflare:test";
import { expect } from "vitest";
import type { AccEnv } from "../src/accounts";

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export type Json = Record<string, any>;

export const ENV = env as unknown as AccEnv;
export const DB = ENV.DB;

/** Wednesday 2026-10-21 06:00 UTC = 12:00 in Bangladesh (ISO week 2026-W43). Unix seconds. */
export const T0 = Date.UTC(2026, 9, 21, 6, 0, 0) / 1000;
export const DAY = 86400;

let seq = 0;
export function newPid(tag = "acc"): string {
  const r = crypto.getRandomValues(new Uint8Array(6));
  return `${tag}${(seq++).toString(36)}x${Array.from(r, (b) => b.toString(16).padStart(2, "0")).join("")}`.padEnd(20, "0").slice(0, 40);
}

export interface V1Opts {
  method?: string;
  body?: unknown;
  session?: string | null;
  /** Unix seconds (X-Test-Now). */
  now?: number;
  headers?: Record<string, string>;
}

export interface V1Res {
  status: number;
  body: Json;
  headers: Headers;
}

export async function v1(path: string, o: V1Opts = {}): Promise<V1Res> {
  const method = o.method ?? (o.body !== undefined ? "POST" : "GET");
  const headers: Record<string, string> = { ...(o.headers ?? {}) };
  if (o.session) headers.Authorization = `Bearer ${o.session}`;
  if (o.now !== undefined) headers["X-Test-Now"] = String(Math.floor(o.now));
  if (o.body !== undefined) headers["Content-Type"] = "application/json";
  const r = await SELF.fetch(`https://x/v1/${path}`, { method, headers, body: o.body === undefined ? undefined : JSON.stringify(o.body) });
  const text = await r.text();
  let body: Json = {};
  try {
    body = text ? JSON.parse(text) : {};
  } catch {
    body = { raw: text };
  }
  return { status: r.status, body, headers: r.headers };
}

/** v1() that expects `status`. */
export async function ok(path: string, o: V1Opts = {}, status = 200): Promise<Json> {
  const r = await v1(path, o);
  expect(r.status, `${o.method ?? (o.body !== undefined ? "POST" : "GET")} ${path}: ${JSON.stringify(r.body)}`).toBe(status);
  return r.body;
}

export interface Guest {
  pid: string;
  session: string;
  id: string;
  profile: Json;
  body: Json;
}

export async function guest(o: { pid?: string; import?: unknown; now?: number } = {}): Promise<Guest> {
  const pid = o.pid ?? newPid();
  const body: Json = { pid };
  if (o.import !== undefined) body.import = o.import;
  const b = await ok("auth/guest", { body, now: o.now ?? T0 });
  return { pid, session: b.session, id: b.account.id, profile: b.profile, body: b };
}

export async function rows<T = Json>(sql: string, ...params: unknown[]): Promise<T[]> {
  return (await DB.prepare(sql).bind(...params).all<T>()).results;
}

export async function row<T = Json>(sql: string, ...params: unknown[]): Promise<T | null> {
  return DB.prepare(sql).bind(...params).first<T>();
}

/** Sets account columns directly (test setup only). */
export async function setAccount(id: string, cols: Record<string, string | number | null>): Promise<void> {
  const k = Object.keys(cols);
  await DB.prepare(`UPDATE accounts SET ${k.map((c) => `${c} = ?`).join(", ")}, version = version + 1 WHERE id = ?`)
    .bind(...k.map((c) => cols[c]), id)
    .run();
}

/** Sum of the account's ledger deltas (coins) = its balance (the "start" row holds the first 5,000). */
export async function ledgerSum(id: string): Promise<number> {
  return (await row<{ s: number }>("SELECT COALESCE(SUM(delta_coins), 0) AS s FROM ledger WHERE account_id = ?", id))!.s;
}

let claimSeq = 0;
export function claimId(): string {
  return `claim${Date.now().toString(36)}${(claimSeq++).toString(36)}${crypto.getRandomValues(new Uint32Array(1))[0].toString(36)}`;
}

/** A Ludo vs Computer claim (4 seats, you + 3 computers). */
export function ludoClaim(result: "win" | "loss", over: Json = {}): Json {
  return { id: claimId(), game: "ludo", mode: "cpu", result, players: ["human", "cpu", "cpu", "cpu"], duration_s: 300, ...over };
}
