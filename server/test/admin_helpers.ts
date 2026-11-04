// Helpers for the admin tests: API calls through SELF with a session cookie, D1 queries, polling for the Room's
// fire-and-forget D1 writes.
import { SELF, env } from "cloudflare:test";
import { expect } from "vitest";
import type { Env } from "../src/room";

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export type Json = Record<string, any>;

export const PASSWORD = "test-admin-password"; // vitest.config.ts miniflare bindings
export const DB = (env as unknown as Env).DB;

export interface CallOpts {
  method?: string;
  body?: unknown;
  cookie?: string | null;
  xadmin?: boolean;
  ip?: string;
}

export async function call(path: string, o: CallOpts = {}): Promise<Response> {
  const method = o.method ?? (o.body !== undefined ? "POST" : "GET");
  const headers: Record<string, string> = { "CF-Connecting-IP": o.ip ?? "203.0.113.1" };
  if (o.cookie) headers.Cookie = `lz_admin=${o.cookie}`;
  if (o.xadmin ?? method !== "GET") headers["X-Admin"] = "1";
  if (o.body !== undefined) headers["Content-Type"] = "application/json";
  return SELF.fetch(`https://x/admin/api/${path}`, {
    method,
    headers,
    body: o.body === undefined ? undefined : JSON.stringify(o.body),
  });
}

/** Logs in and returns the cookie value. */
export async function login(ip = "203.0.113.1"): Promise<string> {
  const r = await call("login", { body: { password: PASSWORD }, ip });
  expect(r.status).toBe(204);
  const sc = r.headers.get("Set-Cookie") ?? "";
  const m = /^lz_admin=([^;]+);/.exec(sc);
  expect(m).not.toBeNull();
  return m![1];
}

/** An authenticated call that expects `status` and returns the JSON body ({} for 204). */
export async function api(cookie: string, path: string, o: Omit<CallOpts, "cookie"> = {}, status = 200): Promise<Json> {
  const r = await call(path, { ...o, cookie });
  const text = await r.text();
  expect(r.status, `${o.method ?? "GET"} ${path}: ${text}`).toBe(status);
  return text ? JSON.parse(text) : ({} as Json);
}

export async function rows<T = Json>(sql: string, ...params: unknown[]): Promise<T[]> {
  return (await DB.prepare(sql).bind(...params).all<T>()).results;
}

export async function row<T = Json>(sql: string, ...params: unknown[]): Promise<T | null> {
  return DB.prepare(sql).bind(...params).first<T>();
}

/** Polls fn until it returns a truthy value (the Room writes D1 in the background). */
export async function eventually<T>(
  fn: () => Promise<T>,
  timeoutMs = 8000,
  what = "condition",
): Promise<Exclude<NonNullable<T>, false>> {
  const deadline = Date.now() + timeoutMs;
  let last: unknown;
  for (;;) {
    try {
      const v = await fn();
      if (v) return v as Exclude<NonNullable<T>, false>;
    } catch (e) {
      last = e;
    }
    if (Date.now() > deadline) throw new Error(`timed out waiting for ${what}${last ? `: ${String(last)}` : ""}`);
    await new Promise((res) => setTimeout(res, 50));
  }
}
