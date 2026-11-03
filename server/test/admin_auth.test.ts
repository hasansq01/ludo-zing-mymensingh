// Admin auth: disabled without a password, login, rate limit, the session cookie, CSRF header, logout, routing.
import { createExecutionContext, env, waitOnExecutionContext } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import worker from "../src/index";
import type { Env } from "../src/room";
import { api, call, login, PASSWORD, rows } from "./admin_helpers";

async function direct(e: Env, path: string, init: RequestInit = {}): Promise<Response> {
  const ctx = createExecutionContext();
  const r = await worker.fetch(new Request(`https://x/admin/api/${path}`, init), e, ctx);
  await waitOnExecutionContext(ctx);
  return r;
}

async function forge(password: string, exp: number): Promise<string> {
  const enc = new TextEncoder();
  const raw = await crypto.subtle.digest("SHA-256", enc.encode(`lz-admin-session-v1:${password}`));
  const key = await crypto.subtle.importKey("raw", raw, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", key, enc.encode(String(exp)));
  const b64 = btoa(String.fromCharCode(...new Uint8Array(sig))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  return `${exp}.${b64}`;
}

describe("admin auth", () => {
  it("without ADMIN_PASSWORD every admin call answers 503 admin_disabled", async () => {
    const e = { ...(env as unknown as Env), ADMIN_PASSWORD: undefined };
    for (const [path, init] of [
      ["me", {}],
      ["overview", {}],
      ["login", { method: "POST", headers: { "X-Admin": "1" }, body: JSON.stringify({ password: "x" }) }],
    ] as const) {
      const r = await direct(e, path, init);
      expect(r.status).toBe(503);
      expect(await r.json()).toMatchObject({ error: "admin_disabled" });
    }
  });

  it("no session: 401 on me and on every endpoint", async () => {
    for (const p of ["me", "overview", "rooms", "players", "matches", "events", "config", "audit"]) {
      const r = await call(p);
      expect(r.status, p).toBe(401);
      expect(await r.json()).toMatchObject({ error: "unauthorized" });
    }
  });

  it("wrong password 401; a correct one sets the session cookie; me works with it", async () => {
    const bad = await call("login", { body: { password: "nope" }, ip: "198.51.100.1" });
    expect(bad.status).toBe(401);
    expect(await bad.json()).toMatchObject({ error: "bad_password" });

    const r = await call("login", { body: { password: PASSWORD }, ip: "198.51.100.1" });
    expect(r.status).toBe(204);
    const sc = r.headers.get("Set-Cookie")!;
    expect(sc).toMatch(/^lz_admin=\d+\.[A-Za-z0-9_-]+;/);
    for (const attr of ["HttpOnly", "Secure", "SameSite=Strict", "Path=/admin", "Max-Age=43200"]) expect(sc).toContain(attr);
    const cookie = /^lz_admin=([^;]+)/.exec(sc)![1];
    expect(await api(cookie, "me")).toEqual({ ok: true });
  });

  it("bad login bodies are 400", async () => {
    for (const body of [{}, { password: 5 }, { password: "" }]) {
      const r = await call("login", { body, ip: "198.51.100.2" });
      expect(r.status).toBe(400);
    }
    const r = await call("login", { method: "POST", ip: "198.51.100.2", body: undefined });
    expect(r.status).toBe(400);
  });

  it("5 failed logins from one IP in 10 minutes -> 429, even with the right password; other IPs unaffected", async () => {
    const ip = "198.51.100.77";
    for (let k = 0; k < 5; k++) expect((await call("login", { body: { password: `bad${k}` }, ip })).status).toBe(401);
    const r = await call("login", { body: { password: PASSWORD }, ip });
    expect(r.status).toBe(429);
    expect(await r.json()).toMatchObject({ error: "rate_limited" });
    expect((await rows("SELECT * FROM login_attempts WHERE ip = ?", ip)).length).toBe(5);
    await login("198.51.100.78");
  });

  it("a tampered, expired or other-password cookie is 401", async () => {
    const cookie = await login();
    const [exp, sig] = cookie.split(".");
    const flip = (s: string) => (s[0] === "A" ? "B" : "A") + s.slice(1);
    for (const bad of [
      `${exp}.${flip(sig)}`,
      `${Number(exp) + 1000}.${sig}`,
      `${exp}`,
      "garbage",
      await forge(PASSWORD, Math.floor(Date.now() / 1000) - 10), // correctly signed but expired
      await forge("another-password", Number(exp)), // signed with a different (old) password
    ]) {
      const r = await call("me", { cookie: bad });
      expect(r.status, bad).toBe(401);
    }
    // a forged cookie with the real password and a future exp is (by construction) valid
    expect(await api(await forge(PASSWORD, Number(exp)), "me")).toEqual({ ok: true });
    // changing the password invalidates every session
    const e = { ...(env as unknown as Env), ADMIN_PASSWORD: "changed-password" };
    const r = await direct(e, "me", { headers: { Cookie: `lz_admin=${cookie}` } });
    expect(r.status).toBe(401);
  });

  it("writes without X-Admin: 1 are 403 (login included); reads don't need it", async () => {
    const cookie = await login();
    for (const [path, method] of [
      ["config", "PUT"],
      ["players/abcdefghijklmnop/ban", "POST"],
      ["players/abcdefghijklmnop", "PATCH"],
      ["rooms/ABCDEF/close", "POST"],
      ["logout", "POST"],
      ["login", "POST"],
    ]) {
      const r = await call(path, { method, cookie, xadmin: false, body: {} });
      expect(r.status, `${method} ${path}`).toBe(403);
      expect(await r.json()).toMatchObject({ error: "csrf" });
    }
    expect((await call("config", { cookie, xadmin: false })).status).toBe(200);
  });

  it("logout clears the cookie; login and logout are audited", async () => {
    const cookie = await login("192.0.2.44");
    const r = await call("logout", { method: "POST", cookie, ip: "192.0.2.44" });
    expect(r.status).toBe(204);
    expect(r.headers.get("Set-Cookie")).toMatch(/^lz_admin=; .*Max-Age=0/);
    const log = await rows("SELECT action FROM admin_log WHERE ip = ? ORDER BY id", "192.0.2.44");
    expect(log.map((x) => x.action)).toEqual(["login", "logout"]);
  });

  it("unknown endpoints 404, wrong methods 405", async () => {
    const cookie = await login();
    expect((await call("nope", { cookie })).status).toBe(404);
    expect((await call("rooms/ABCDEF/nope", { cookie, method: "POST", body: {} })).status).toBe(404);
    expect((await call("overview/x", { cookie })).status).toBe(404);
    expect((await call("overview", { cookie, method: "POST", body: {} })).status).toBe(405);
    expect((await call("rooms", { cookie, method: "DELETE" })).status).toBe(405);
    expect((await call("me", { method: "POST", body: {} })).status).toBe(405);
  });
});
