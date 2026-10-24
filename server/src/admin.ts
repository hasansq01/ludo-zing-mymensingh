// The admin console's JSON API: /admin/api/* (ADMIN_API.md is the contract). Auth: one password (secret
// ADMIN_PASSWORD) -> an HMAC-signed session cookie; X-Admin: 1 on every write (CSRF); every write is audited.
import * as D from "./db";
import { isCode, type Env, type Room } from "./room";

const COOKIE = "lz_admin";
const SESSION_S = 12 * 60 * 60; // 43200
const LOGIN_WINDOW_MS = 10 * 60_000;
const LOGIN_MAX_FAILURES = 5;
const MAX_BODY = 8192;
const PID_RE = /^[A-Za-z0-9_-]{16,64}$/;

/** The console's Content-Security-Policy (also sent on API responses). */
export const CSP =
  "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; font-src 'self'; " +
  "connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'";

const NO_STORE = {
  "Cache-Control": "no-store",
  "Content-Security-Policy": CSP,
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "no-referrer",
};

function json(body: unknown, status = 200, headers: Record<string, string> = {}): Response {
  return Response.json(body, { status, headers: { ...NO_STORE, ...headers } });
}

function fail(status: number, error: string, msg?: string): Response {
  return json(msg ? { error, msg } : { error }, status);
}

function noContent(headers: Record<string, string> = {}): Response {
  return new Response(null, { status: 204, headers: { ...NO_STORE, ...headers } });
}

/** Thrown by validators; answered as 400 {error: "bad_request", msg}. */
class BadRequest extends Error {}

// ---------- crypto ----------

const enc = new TextEncoder();

async function sha256(s: string): Promise<ArrayBuffer> {
  return crypto.subtle.digest("SHA-256", enc.encode(s));
}

function b64url(buf: ArrayBuffer): string {
  return btoa(String.fromCharCode(...new Uint8Array(buf))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function unb64url(s: string): Uint8Array | null {
  try {
    const bin = atob(s.replace(/-/g, "+").replace(/_/g, "/"));
    return Uint8Array.from(bin, (c) => c.charCodeAt(0));
  } catch {
    return null;
  }
}

/** The session key: derived from the password, so changing it invalidates every session. */
async function sessionKey(password: string): Promise<CryptoKey> {
  const raw = await sha256(`lz-admin-session-v1:${password}`);
  return crypto.subtle.importKey("raw", raw, { name: "HMAC", hash: "SHA-256" }, false, ["sign", "verify"]);
}

async function passwordOk(given: string, expected: string): Promise<boolean> {
  const [a, b] = await Promise.all([sha256(given), sha256(expected)]);
  return crypto.subtle.timingSafeEqual(a, b);
}

async function makeSession(password: string, now: number): Promise<string> {
  const exp = String(Math.floor(now / 1000) + SESSION_S);
  const sig = await crypto.subtle.sign("HMAC", await sessionKey(password), enc.encode(exp));
  return `${exp}.${b64url(sig)}`;
}

async function validSession(req: Request, password: string, now: number): Promise<boolean> {
  const v = cookie(req, COOKIE);
  const m = v ? /^(\d{1,12})\.([A-Za-z0-9_-]{20,100})$/.exec(v) : null;
  if (!m) return false;
  if (Number(m[1]) * 1000 <= now) return false;
  const sig = unb64url(m[2]);
  if (!sig) return false;
  return crypto.subtle.verify("HMAC", await sessionKey(password), sig, enc.encode(m[1]));
}

function cookie(req: Request, name: string): string | null {
  const h = req.headers.get("Cookie");
  if (!h) return null;
  for (const part of h.split(";")) {
    const k = part.indexOf("=");
    if (k > 0 && part.slice(0, k).trim() === name) return part.slice(k + 1).trim();
  }
  return null;
}

function setCookie(value: string, maxAge: number): string {
  return `${COOKIE}=${value}; HttpOnly; Secure; SameSite=Strict; Path=/admin; Max-Age=${maxAge}`;
}

function clientIp(req: Request): string {
  return req.headers.get("CF-Connecting-IP") ?? "local";
}

// ---------- input ----------

async function body(req: Request): Promise<Record<string, unknown>> {
  const text = await req.text();
  if (text.length > MAX_BODY) throw new BadRequest("body too large");
  if (!text.trim()) return {};
  let v: unknown;
  try {
    v = JSON.parse(text);
  } catch {
    throw new BadRequest("body must be JSON");
  }
  if (!v || typeof v !== "object" || Array.isArray(v)) throw new BadRequest("body must be a JSON object");
  return v as Record<string, unknown>;
}

function optString(o: Record<string, unknown>, k: string, max: number, min = 0): string | undefined {
  const v = o[k];
  if (v === undefined || v === null) {
    if (min > 0) throw new BadRequest(`${k}: required, ${min}-${max} characters`);
    return undefined;
  }
  if (typeof v !== "string") throw new BadRequest(`${k}: string`);
  // eslint-disable-next-line no-control-regex
  const t = v.replace(/[\u0000-\u001f\u007f]/g, " ").trim();
  const n = Array.from(t).length;
  if (n > max || n < min) throw new BadRequest(min > 0 ? `${k}: ${min}-${max} characters` : `${k}: at most ${max} characters`);
  return t;
}

function pageArgs(u: URL): { limit: number; cursor: string | null } {
  const l = u.searchParams.get("limit");
  let limit = 50;
  if (l !== null && l !== "") {
    if (!/^\d{1,3}$/.test(l) || Number(l) < 1 || Number(l) > 200) throw new BadRequest("limit: 1-200");
    limit = Number(l);
  }
  const cursor = u.searchParams.get("cursor") || null;
  if (cursor && cursor.length > 400) throw new BadRequest("bad cursor");
  return { limit, cursor };
}

function param(u: URL, k: string, max = 64): string | undefined {
  const v = u.searchParams.get(k)?.trim();
  if (!v) return undefined;
  if (v.length > max) throw new BadRequest(`${k}: at most ${max} characters`);
  return v;
}

function oneOf<T extends string>(u: URL, k: string, allowed: readonly T[]): T | undefined {
  const v = param(u, k);
  if (v === undefined) return undefined;
  if (!(allowed as readonly string[]).includes(v)) throw new BadRequest(`${k}: one of ${allowed.join(", ")}`);
  return v as T;
}

const ROOM_STATUSES = ["lobby", "playing", "over", "closed"] as const;
const MATCH_RESULTS = ["playing", "over", "abandoned", "closed"] as const;
const LEVELS = ["info", "warn", "error"] as const;

function page<T>(p: D.Page<T>, map?: (x: T) => unknown): Response {
  return json({ items: map ? p.items.map(map) : p.items, next: p.next });
}

// ---------- the API ----------

interface Ctx {
  req: Request;
  env: Env;
  ctx: ExecutionContext;
  url: URL;
  ip: string;
  now: number;
}

function stub(env: Env, code: string): DurableObjectStub<Room> {
  return env.ROOMS.get(env.ROOMS.idFromName(code));
}

async function audit(c: Ctx, action: string, target: string | null, detail?: unknown): Promise<void> {
  try {
    await D.addAudit(c.env.DB, { ip: c.ip, action, target, detail }, c.now).run();
  } catch (e) {
    console.error("admin_log write failed:", e);
  }
}

/** Every /admin/api/* request. `path` is what follows /admin/api/. */
export async function handleAdmin(req: Request, env: Env, ctx: ExecutionContext, path: string[]): Promise<Response> {
  const password = env.ADMIN_PASSWORD;
  if (!password) {
    return fail(
      503,
      "admin_disabled",
      "The admin console is disabled: set the ADMIN_PASSWORD secret (tools/cf.sh secret put ADMIN_PASSWORD; locally server/.dev.vars).",
    );
  }
  const url = new URL(req.url);
  const c: Ctx = { req, env, ctx, url, ip: clientIp(req), now: Date.now() };
  const write = req.method !== "GET" && req.method !== "HEAD";
  if (write && req.headers.get("X-Admin") !== "1") return fail(403, "csrf", "write requests need the header X-Admin: 1");

  try {
    const [a, b, d, ...rest] = path;
    if (a === "login" && path.length === 1) return req.method === "POST" ? await login(c, password) : fail(405, "method");
    if (a === "logout" && path.length === 1) return req.method === "POST" ? await logout(c, password) : fail(405, "method");
    const authed = await validSession(req, password, c.now);
    if (a === "me" && path.length === 1) {
      if (req.method !== "GET") return fail(405, "method");
      return authed ? json({ ok: true }) : fail(401, "unauthorized", "log in first");
    }
    if (!authed) return fail(401, "unauthorized", "log in first");
    if (rest.length) return fail(404, "not_found");
    const m = req.method;
    switch (a) {
      case "overview":
        if (b !== undefined) break;
        return m === "GET" ? json(await D.overview(env.DB, c.now)) : fail(405, "method");
      case "rooms":
        if (b === undefined) return m === "GET" ? await rooms(c) : fail(405, "method");
        if (d === undefined) return m === "GET" ? await roomDetail(c, b) : fail(405, "method");
        if (d === "close") return m === "POST" ? await roomClose(c, b) : fail(405, "method");
        if (d === "kick") return m === "POST" ? await roomKick(c, b) : fail(405, "method");
        break;
      case "players":
        if (b === undefined) return m === "GET" ? await players(c) : fail(405, "method");
        if (d === undefined) {
          if (m === "GET") return await playerDetail(c, b);
          if (m === "PATCH") return await playerPatch(c, b);
          return fail(405, "method");
        }
        if (d === "ban" || d === "unban") return m === "POST" ? await playerBan(c, b, d === "ban") : fail(405, "method");
        break;
      case "matches":
        if (b !== undefined) break;
        return m === "GET" ? await matches(c) : fail(405, "method");
      case "events":
        if (b !== undefined) break;
        return m === "GET" ? await events(c) : fail(405, "method");
      case "config":
        if (b !== undefined) break;
        if (m === "GET") return json(await D.readConfig(env.DB));
        if (m === "PUT") return await configPut(c);
        return fail(405, "method");
      case "audit":
        if (b !== undefined) break;
        return m === "GET" ? page(await D.listAudit(env.DB, pageArgs(url))) : fail(405, "method");
    }
    return fail(404, "not_found");
  } catch (e) {
    if (e instanceof BadRequest) return fail(400, "bad_request", e.message);
    if (e instanceof D.BadCursor) return fail(400, "bad_request", "bad cursor");
    throw e;
  }
}

// ----- auth -----

async function login(c: Ctx, password: string): Promise<Response> {
  const db = c.env.DB;
  const failures = await D.loginFailures(db, c.ip, c.now - LOGIN_WINDOW_MS);
  if (failures >= LOGIN_MAX_FAILURES) {
    return fail(429, "rate_limited", "too many failed logins from this address; try again in 10 minutes");
  }
  const o = await body(c.req);
  if (typeof o.password !== "string" || !o.password || o.password.length > 512) throw new BadRequest("password: string");
  if (!(await passwordOk(o.password, password))) {
    await D.addLoginFailure(db, c.ip, c.now).run();
    return fail(401, "bad_password", "wrong password");
  }
  await audit(c, "login", null);
  return noContent({ "Set-Cookie": setCookie(await makeSession(password, c.now), SESSION_S) });
}

async function logout(c: Ctx, password: string): Promise<Response> {
  if (await validSession(c.req, password, c.now)) await audit(c, "logout", null);
  return noContent({ "Set-Cookie": setCookie("", 0) });
}

// ----- rooms -----

async function rooms(c: Ctx): Promise<Response> {
  const status = oneOf(c.url, "status", ROOM_STATUSES);
  const q = param(c.url, "q");
  return page(await D.listRooms(c.env.DB, { status, q, ...pageArgs(c.url) }), D.roomOut);
}

function decode(s: string): string {
  try {
    return decodeURIComponent(s);
  } catch {
    return "";
  }
}

function roomCode(s: string): string | null {
  const code = decode(s).toUpperCase();
  return isCode(code) ? code : null;
}

async function liveSnapshot(env: Env, code: string) {
  try {
    return await stub(env, code).adminSnapshot();
  } catch (e) {
    console.error("adminSnapshot failed:", e);
    return null;
  }
}

async function roomDetail(c: Ctx, raw: string): Promise<Response> {
  const code = roomCode(raw);
  if (!code) return fail(404, "not_found");
  const [row, live, ms] = await Promise.all([
    D.getRoom(c.env.DB, code),
    liveSnapshot(c.env, code),
    D.listMatches(c.env.DB, { code, limit: 20 }),
  ]);
  if (!row && !live) return fail(404, "not_found");
  return json({ now: Date.now(), room: row ? D.roomOut(row) : null, live, matches: ms.items.map(D.matchOut) });
}

async function roomClose(c: Ctx, raw: string): Promise<Response> {
  const code = roomCode(raw);
  if (!code) return fail(404, "not_found");
  const o = await body(c.req);
  const reason = optString(o, "reason", 140, 3)!;
  const row = await D.getRoom(c.env.DB, code);
  const live = await stub(c.env, code).adminClose(reason);
  if (!row && !live) return fail(404, "not_found");
  // the room writes its own closed row; this also covers a row whose room is already gone
  await D.closeRoomRow(c.env.DB, code, reason, Date.now(), live ? "closed" : "abandoned");
  await audit(c, "room.close", code, { reason, live });
  return json({ ok: true, live });
}

async function roomKick(c: Ctx, raw: string): Promise<Response> {
  const code = roomCode(raw);
  if (!code) return fail(404, "not_found");
  const o = await body(c.req);
  const id = o.member_id;
  if (typeof id !== "number" || !Number.isInteger(id) || id < 1) throw new BadRequest("member_id: positive int");
  const ok = await stub(c.env, code).adminKick(id);
  if (!ok) return fail(404, "not_found", "no such member in a live room");
  await audit(c, "room.kick", code, { member_id: id });
  return json({ ok: true });
}

// ----- players -----

async function players(c: Ctx): Promise<Response> {
  const q = param(c.url, "q");
  const b = oneOf(c.url, "banned", ["0", "1"] as const);
  return page(await D.listPlayers(c.env.DB, { q, banned: b === undefined ? undefined : b === "1", ...pageArgs(c.url) }));
}

function pidOf(raw: string): string | null {
  const pid = decode(raw);
  return PID_RE.test(pid) ? pid : null;
}

async function playerDetail(c: Ctx, raw: string): Promise<Response> {
  const pid = pidOf(raw);
  if (!pid) return fail(404, "not_found");
  const player = await D.getPlayer(c.env.DB, pid);
  if (!player) return fail(404, "not_found");
  const ms = await D.listMatches(c.env.DB, { pid, since: player.first_seen ?? undefined, limit: 20 });
  return json({ player, matches: ms.items.map(D.matchOut) });
}

async function playerBan(c: Ctx, raw: string, ban: boolean): Promise<Response> {
  const pid = pidOf(raw);
  if (!pid) return fail(404, "not_found");
  const o = await body(c.req);
  const reason = ban ? optString(o, "reason", 200, 3)! : null;
  if (!(await D.setBan(c.env.DB, pid, ban, reason))) return fail(404, "not_found");
  const player = await D.getPlayer(c.env.DB, pid);
  // best effort: the room of the player's latest join (players.last_room) kicks them / forgets its cached flag
  let kicked = false;
  const room = player?.last_room;
  if (room && isCode(room)) {
    try {
      if (ban) kicked = await stub(c.env, room).adminBan(pid, reason ?? "");
      else await stub(c.env, room).adminUnban(pid);
    } catch (e) {
      console.error("ban kick failed:", e);
    }
  }
  await audit(c, ban ? "player.ban" : "player.unban", pid, ban ? { reason, kicked, room } : undefined);
  return json(ban ? { ok: true, kicked, player } : { ok: true, player });
}

async function playerPatch(c: Ctx, raw: string): Promise<Response> {
  const pid = pidOf(raw);
  if (!pid) return fail(404, "not_found");
  const o = await body(c.req);
  if (!("note" in o)) throw new BadRequest("note: string or null");
  const note = optString(o, "note", 500);
  if (!(await D.setNote(c.env.DB, pid, note || null))) return fail(404, "not_found");
  await audit(c, "player.note", pid, { note: note || null });
  return json({ ok: true, player: await D.getPlayer(c.env.DB, pid) });
}

// ----- matches, events -----

async function matches(c: Ctx): Promise<Response> {
  const rawCode = param(c.url, "code");
  const code = rawCode === undefined ? undefined : rawCode.toUpperCase();
  if (code !== undefined && !isCode(code)) throw new BadRequest("code: a room code");
  const pid = param(c.url, "pid");
  if (pid !== undefined && !PID_RE.test(pid)) throw new BadRequest("pid: 16-64 characters of [A-Za-z0-9_-]");
  const result = oneOf(c.url, "result", MATCH_RESULTS);
  let since: number | undefined;
  if (pid) since = (await D.getPlayer(c.env.DB, pid))?.first_seen ?? undefined;
  return page(await D.listMatches(c.env.DB, { code, pid, result, since, ...pageArgs(c.url) }), D.matchOut);
}

async function events(c: Ctx): Promise<Response> {
  const level = oneOf(c.url, "level", LEVELS);
  const kind = param(c.url, "kind", 40);
  return page(await D.listEvents(c.env.DB, { level, kind, ...pageArgs(c.url) }));
}

// ----- config -----

async function configPut(c: Ctx): Promise<Response> {
  const o = await body(c.req);
  const patch: Partial<D.GameConfig> = {};
  for (const [k, v] of Object.entries(o)) {
    if (k === "maintenance") {
      if (typeof v !== "boolean") throw new BadRequest("maintenance: bool");
      patch.maintenance = v;
    } else if (k === "motd") {
      patch.motd = optString(o, "motd", D.MOTD_MAX) ?? "";
    } else if ((D.TURN_KEYS as readonly string[]).includes(k)) {
      if (typeof v !== "number" || !Number.isInteger(v) || v < D.TURN_MIN || v > D.TURN_MAX) {
        throw new BadRequest(`${k}: integer ${D.TURN_MIN}-${D.TURN_MAX}`);
      }
      patch[k as (typeof D.TURN_KEYS)[number]] = v;
    } else {
      throw new BadRequest(`unknown field ${k.slice(0, 40)}`);
    }
  }
  await D.writeConfig(c.env.DB, patch);
  D.forgetConfig();
  if (Object.keys(patch).length) await audit(c, "config.update", null, patch);
  return json(await D.readConfig(c.env.DB));
}
