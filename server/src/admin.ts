// The admin console's JSON API: /admin/api/* (ADMIN_API.md is the contract). Auth: one password (secret
// ADMIN_PASSWORD) -> an HMAC-signed session cookie; X-Admin: 1 on every write (CSRF); every write is audited.
import { ACCOUNT_RE, type AccountRow, type Step, adminAccountOut, getAccount, guardedInsert, mutate } from "./accounts";
import { DAY_OFFSET_MIN } from "./econ/rules";
import { econDayStartMs } from "./wallet";
import * as D from "./db";
import { BOARDS, PERIODS, type Board, type PeriodArg, countScores, periodKey, topScores } from "./leaderboard";
import * as P from "./push";
import { isCode, type AdminSnapshot, type Env, type Room } from "./room";
import { usageReport, type UsageEnv } from "./usage";

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

// "paused" = playing with nobody online; "playing" then means online > 0 (D.RoomFilter)
const ROOM_STATUSES = ["lobby", "playing", "paused", "over", "closed"] as const satisfies readonly D.RoomFilter[];
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
    const [a, b, d, e, ...rest] = path;
    if (a === "login" && path.length === 1) return req.method === "POST" ? await login(c, password) : fail(405, "method");
    if (a === "logout" && path.length === 1) return req.method === "POST" ? await logout(c, password) : fail(405, "method");
    const authed = await validSession(req, password, c.now);
    if (a === "me" && path.length === 1) {
      if (req.method !== "GET") return fail(405, "method");
      return authed ? json({ ok: true }) : fail(401, "unauthorized", "log in first");
    }
    if (!authed) return fail(401, "unauthorized", "log in first");
    if (rest.length || (e !== undefined && !(a === "push" && b === "campaigns"))) return fail(404, "not_found");
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
      case "economy":
        if (b !== undefined) break;
        return m === "GET" ? await economy(c) : fail(405, "method");
      case "usage":
        if (b !== undefined) break;
        if (m !== "GET") return fail(405, "method");
        {
          const u = await usageReport(env as Env & UsageEnv, c.now);
          return json(u.body, u.status);
        }
      case "config":
        if (b !== undefined) break;
        if (m === "GET") return json(await D.readConfig(env.DB));
        if (m === "PUT") return await configPut(c);
        return fail(405, "method");
      case "audit":
        if (b !== undefined) break;
        return m === "GET" ? page(await D.listAudit(env.DB, pageArgs(url))) : fail(405, "method");
      // ----- v2 (ONLINE_V2.md §6) -----
      case "accounts":
        if (b === undefined) return m === "GET" ? await accounts(c) : fail(405, "method");
        if (d === undefined) {
          if (m === "GET") return await accountDetail(c, b);
          if (m === "PATCH") return await accountPatch(c, b);
          return fail(405, "method");
        }
        if (d === "coins") return m === "POST" ? await accountCoins(c, b) : fail(405, "method");
        if (d === "gems") return m === "POST" ? await accountGems(c, b) : fail(405, "method");
        if (d === "ban" || d === "unban") return m === "POST" ? await accountBan(c, b, d === "ban") : fail(405, "method");
        if (d === "erase") return m === "POST" ? await accountErase(c, b) : fail(405, "method");
        break;
      case "leaderboards":
        if (b !== undefined) break;
        return m === "GET" ? await leaderboards(c) : fail(405, "method");
      case "quick":
        if (b !== undefined) break;
        return m === "GET" ? await quick(c) : fail(405, "method");
      // ----- notifications (NOTIFICATIONS.md "N-SRV") -----
      case "push":
        if (b === undefined) return m === "GET" ? await pushOverview(c) : fail(405, "method");
        if (d !== undefined && b !== "campaigns") break;
        if (b === "preview") return m === "POST" ? await pushPreview(c) : fail(405, "method");
        if (b === "test") return m === "POST" ? await pushTest(c) : fail(405, "method");
        if (b === "campaigns" && d === undefined) return m === "POST" ? await pushCampaign(c) : fail(405, "method");
        if (b === "campaigns" && e === "cancel") return m === "POST" ? await pushCancel(c, d!) : fail(405, "method");
        break;
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

/** The DO's snapshot plus `paused` (a match in progress, nobody connected); null when the room is gone. */
async function liveSnapshot(env: Env, code: string) {
  try {
    const s = (await stub(env, code).adminSnapshot()) as AdminSnapshot | null;
    return s ? { ...s, paused: s.status === "playing" && !s.members.some((m) => m.online) } : null;
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
  const dev = await deviceOf(c.env.DB, pid);
  return json({ player, account_id: dev?.account_id ?? null, matches: ms.items.map(D.matchOut) });
}

async function deviceOf(db: D1Database, pid: string): Promise<{ account_id: string } | null> {
  return db.prepare("SELECT account_id FROM devices WHERE pid = ?").bind(pid).first<{ account_id: string }>();
}

/**
 * POST /admin/api/players/:pid/ban {reason} / unban. Ban sources (ADMIN_API.md "Ban sources"): the pid ban is
 * "admin_pid"; it bans the device's account too ("pid:<pid>") unless that account is banned already. Unbanning the pid
 * lifts the account ban only when this pid's ban caused it (another device of the account still banned on the
 * Players page takes the cause over instead).
 */
async function playerBan(c: Ctx, raw: string, ban: boolean): Promise<Response> {
  const pid = pidOf(raw);
  if (!pid) return fail(404, "not_found");
  const o = await body(c.req);
  const reason = ban ? optString(o, "reason", 200, 3)! : null;
  const db = c.env.DB;
  const dev = await deviceOf(db, pid);
  if (!(await D.setBan(db, pid, ban, reason, ban ? "admin_pid" : null))) {
    // a v2 device that never joined a friend room has no players row yet: create it to hold the pid ban
    if (!dev) return fail(404, "not_found");
    await ensurePlayerRows(db, [pid]);
    await D.setBan(db, pid, ban, reason, ban ? "admin_pid" : null);
  }
  let accountBanned: boolean | null = null;
  if (dev) {
    const acc = await db.prepare("SELECT banned, ban_source FROM accounts WHERE id = ?").bind(dev.account_id).first<{ banned: number; ban_source: string | null }>();
    if (acc && ban && !acc.banned) {
      await setAccountBan(db, dev.account_id, true, reason, `pid:${pid}`);
    } else if (acc && !ban && acc.banned && acc.ban_source === `pid:${pid}`) {
      const other = await db
        .prepare(
          `SELECT p.pid, p.ban_reason FROM devices d JOIN players p ON p.pid = d.pid
           WHERE d.account_id = ? AND d.pid != ? AND p.banned = 1 AND p.ban_source = 'admin_pid' LIMIT 1`,
        )
        .bind(dev.account_id, pid)
        .first<{ pid: string; ban_reason: string | null }>();
      if (other) await setAccountBan(db, dev.account_id, true, other.ban_reason, `pid:${other.pid}`);
      else await setAccountBan(db, dev.account_id, false, null, null);
    }
    accountBanned = ((await db.prepare("SELECT banned FROM accounts WHERE id = ?").bind(dev.account_id).first<{ banned: number }>())?.banned ?? 0) === 1;
  }
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
  const account_id = dev?.account_id ?? null;
  await audit(
    c,
    ban ? "player.ban" : "player.unban",
    pid,
    ban ? { reason, kicked, room, account_id: account_id ?? undefined, account_banned: accountBanned ?? undefined } : dev ? { account_id, account_banned: accountBanned } : undefined,
  );
  return json(ban ? { ok: true, kicked, player, account_id, account_banned: accountBanned } : { ok: true, player, account_id, account_banned: accountBanned });
}

/** players rows for v2 devices that never joined a friend room (they hold the pid bans). */
async function ensurePlayerRows(db: D1Database, pids: string[]): Promise<void> {
  if (!pids.length) return;
  await db.batch(
    pids.map((pid) =>
      db.prepare("INSERT OR IGNORE INTO players (pid, first_seen, last_seen) SELECT pid, first_seen, last_seen FROM devices WHERE pid = ?").bind(pid),
    ),
  );
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

// ----- v2: accounts -----

const ADJUST_MAX = 1_000_000;

/** source: "admin_account" | "pid:<pid>" (null when lifting). */
async function setAccountBan(db: D1Database, id: string, ban: boolean, reason: string | null, source: string | null): Promise<boolean> {
  const r = await db
    .prepare("UPDATE accounts SET banned = ?, ban_reason = ?, ban_source = ? WHERE id = ?")
    .bind(ban ? 1 : 0, ban ? reason : null, ban ? source : null, id)
    .run();
  return r.meta.changes > 0;
}

function accountId(raw: string): string | null {
  const id = decode(raw);
  return ACCOUNT_RE.test(id) ? id : null;
}

function flag(u: URL, k: string): boolean | undefined {
  const v = oneOf(u, k, ["0", "1"] as const);
  return v === undefined ? undefined : v === "1";
}

async function accounts(c: Ctx): Promise<Response> {
  const q = param(c.url, "q");
  const p = await D.listAccounts(c.env.DB, { q, banned: flag(c.url, "banned"), linked: flag(c.url, "linked"), ...pageArgs(c.url) });
  return page(p, (r) => adminAccountOut(r as unknown as AccountRow));
}

async function accountDetail(c: Ctx, raw: string): Promise<Response> {
  const id = accountId(raw);
  if (!id) return fail(404, "not_found");
  const db = c.env.DB;
  const row = await getAccount(db, id);
  if (!row) return fail(404, "not_found");
  const [devices, ledger, claims, grants] = await db.batch([
    db.prepare("SELECT * FROM devices WHERE account_id = ? ORDER BY last_seen DESC LIMIT 50").bind(id),
    db.prepare("SELECT * FROM ledger WHERE account_id = ? ORDER BY id DESC LIMIT 50").bind(id),
    db.prepare("SELECT id, at, game, mode, coins, xp, granted, limited, reason, payload FROM claims WHERE account_id = ? ORDER BY at DESC LIMIT 50").bind(id),
    db.prepare("SELECT * FROM match_grants WHERE account_id = ? ORDER BY at DESC LIMIT 20").bind(id),
  ]);
  const devs = devices.results as Array<{ pid: string }>;
  const ms = await D.matchesForAccount(db, id, devs.map((d) => d.pid), 20);
  const claimRows = (claims.results as Array<Record<string, unknown>>).map((r) => ({ ...r, payload: parseJsonText(r.payload) }));
  return json({
    now: c.now,
    account: adminAccountOut(row),
    devices: devs,
    ledger: ledger.results,
    claims: claimRows,
    grants: grants.results,
    matches: ms.map(D.matchOut),
  });
}

function parseJsonText(v: unknown): unknown {
  if (typeof v !== "string") return v ?? null;
  try {
    return JSON.parse(v);
  } catch {
    return v;
  }
}

/** POST /admin/api/accounts/:id/coins {delta, reason}: a ledger row (reason "admin", ref = the reason), audited. */
async function accountCoins(c: Ctx, raw: string): Promise<Response> {
  const id = accountId(raw);
  if (!id) return fail(404, "not_found");
  const o = await body(c.req);
  const delta = o.delta;
  if (typeof delta !== "number" || !Number.isInteger(delta) || delta === 0 || Math.abs(delta) > ADJUST_MAX) {
    throw new BadRequest(`delta: a non-zero integer, at most ${ADJUST_MAX} either way`);
  }
  const reason = optString(o, "reason", 200, 3)!;
  const r = await mutate(c.env, id, c.now, (_row, p): Step<{ ok: boolean; coins: number }> => {
    const coins = Math.trunc(p.coins) + delta;
    if (coins < 0) return { result: { ok: false, coins: Math.trunc(p.coins) } };
    const np = structuredClone(p);
    np.coins = coins; // a correction, not coins earned (stats.coinsEarned unchanged)
    return { result: { ok: true, coins }, write: { profile: np, ledger: { coins: delta, xp: 0, reason: "admin", ref: reason } } };
  });
  if (!r) return fail(404, "not_found");
  if (!r.ok) return json({ error: "coins", msg: `the balance would go below 0 (it is ${r.coins})`, coins: r.coins }, 409);
  await audit(c, "account.coins", id, { delta, reason, balance: r.coins });
  return json({ ok: true, coins: r.coins, account: adminAccountOut((await getAccount(c.env.DB, id))!) });
}

/**
 * POST /admin/api/accounts/:id/gems {delta, reason}: like /coins, for gems. The ledger row (reason "admin", ref = the
 * reason, delta_gems / gems_after) is written through mutate's `set` + guarded `extra`, so it lands in the same batch
 * as the balance change and only when it applied.
 */
async function accountGems(c: Ctx, raw: string): Promise<Response> {
  const id = accountId(raw);
  if (!id) return fail(404, "not_found");
  const o = await body(c.req);
  const delta = o.delta;
  if (typeof delta !== "number" || !Number.isInteger(delta) || delta === 0 || Math.abs(delta) > ADJUST_MAX) {
    throw new BadRequest(`delta: a non-zero integer, at most ${ADJUST_MAX} either way`);
  }
  const reason = optString(o, "reason", 200, 3)!;
  const db = c.env.DB;
  const r = await mutate(c.env, id, c.now, (row, _p): Step<{ ok: boolean; gems: number }> => {
    const have = Math.trunc((row as AccountRow & { gems?: number }).gems ?? 0);
    const gems = have + delta;
    if (gems < 0) return { result: { ok: false, gems: have } };
    return {
      result: { ok: true, gems },
      write: {
        set: { gems },
        extra: (g) => [
          guardedInsert(
            db, g, "ledger",
            ["account_id", "at", "delta_coins", "delta_xp", "reason", "ref", "balance_after", "delta_gems", "gems_after"],
            [id, c.now, 0, 0, "admin", reason, Math.trunc(row.coins), delta, gems],
          ),
        ],
      },
    };
  });
  if (!r) return fail(404, "not_found");
  if (!r.ok) return json({ error: "gems", msg: `the balance would go below 0 (it is ${r.gems})`, gems: r.gems }, 409);
  await audit(c, "account.gems", id, { delta, reason, balance: r.gems });
  return json({ ok: true, gems: r.gems, account: adminAccountOut((await getAccount(db, id))!) });
}

const DELETED_NAME = "Deleted player";

/**
 * POST /admin/api/accounts/:id/erase {confirm, reason}: the Google Play account-deletion request. `confirm` must be the
 * account's public_id ("LZM-XXXX-XXXX", any case) or its id. One D1 batch, with the audit row (`account.erase`: id and
 * reason only, no personal data). It covers the account and any retired account merged into it (accounts.merged_into).
 * Table by table (every table of migrations/*.sql with an account_id / pid / player name):
 *   DELETED  accounts, devices, players (per-pid rows: name, avatar, ban), push_tokens, push_opens, scores, claims
 *            (payload), broke_bonus, weekly_prizes, ad_rewards still `pending`, events (by pid), player_days (by pid)
 *   SCRUBBED matches.players[].name -> "Deleted player" where pid / account_id matches; rooms.host_name likewise
 *            (host_pid matches). pids and account ids stay in the match JSON (pseudonymous).
 *   KEPT     ledger, entries, match_grants, rerolls, purchases, ad_rewards not pending (granted / expired / rejected):
 *            they hold only the account id and amounts, and are needed for refunds, voided purchases and accounting.
 *   NOT PER-PERSON  config, admin_log (our own audit rows), login_attempts, guest_creations (HMAC of the IP),
 *            quick_stats, table_matches, push_campaigns, push_events: no account or pid.
 * Refused with 409 `busy` while an entry (coin table) is `held` / `playing`. The session dies because getAccount is null
 * (checkSession); the pid's next POST /v1/auth/guest finds no device and creates a fresh account. Erasing also drops the
 * players row, so a pid ban on it ends with it.
 */
async function accountErase(c: Ctx, raw: string): Promise<Response> {
  const id = accountId(raw);
  if (!id) return fail(404, "not_found");
  const o = await body(c.req);
  const confirm = optString(o, "confirm", 64, 1)!;
  const reason = optString(o, "reason", 200, 3)!;
  const db = c.env.DB;
  const row = await getAccount(db, id);
  if (!row) return fail(404, "not_found");
  if (confirm !== id && !(row.public_id && confirm.toUpperCase() === row.public_id.toUpperCase())) {
    throw new BadRequest("confirm: must be the account's Player ID (LZM-XXXX-XXXX) or its id");
  }
  const merged = ((await db.prepare("SELECT id FROM accounts WHERE merged_into = ?").bind(id).all<{ id: string }>()).results).map((r) => r.id);
  const ids = [id, ...merged];
  const IN = `(${ids.map(() => "?").join(", ")})`;
  const open = await db.prepare(`SELECT COUNT(*) AS n FROM entries WHERE account_id IN ${IN} AND status IN ('held', 'playing')`).bind(...ids).first<{ n: number }>();
  if ((open?.n ?? 0) > 0) return json({ error: "busy", msg: "the account has a coin-table entry that is still held / playing; try again after the match" }, 409);

  const PIDS = `(SELECT pid FROM devices WHERE account_id IN ${IN})`;
  const del = (table: string, col: string, ext = "") => db.prepare(`DELETE FROM ${table} WHERE ${col} IN ${IN}${ext}`).bind(...ids);
  const delPid = (table: string) => db.prepare(`DELETE FROM ${table} WHERE pid IN ${PIDS}`).bind(...ids);
  const mine = `(json_extract(j.value, '$.account_id') IN ${IN} OR json_extract(j.value, '$.pid') IN ${PIDS})`;
  const stmts = [
    // scrub first: they read `devices`, which is deleted below
    db
      .prepare(
        `UPDATE matches SET players = (
           SELECT json_group_array(json(v)) FROM (
             SELECT CASE WHEN ${mine} THEN json_set(j.value, '$.name', ?) ELSE json(j.value) END AS v
             FROM json_each(matches.players) AS j ORDER BY j.key))
         WHERE EXISTS (SELECT 1 FROM json_each(matches.players) AS j WHERE ${mine})`,
      )
      .bind(...ids, ...ids, DELETED_NAME, ...ids, ...ids),
    db.prepare(`UPDATE rooms SET host_name = ? WHERE host_pid IN ${PIDS}`).bind(DELETED_NAME, ...ids),
    delPid("events"),
    delPid("player_days"),
    delPid("players"),
    del("push_tokens", "account_id"),
    del("push_opens", "account_id"),
    del("scores", "account_id"),
    del("claims", "account_id"),
    del("broke_bonus", "account_id"),
    del("weekly_prizes", "account_id"),
    del("ad_rewards", "account_id", " AND status = 'pending'"),
    del("devices", "account_id"),
    del("accounts", "id"),
    D.addAudit(db, { ip: c.ip, action: "account.erase", target: id, detail: { reason, merged_accounts: merged.length } }, c.now),
  ];
  const res = await db.batch(stmts);
  const n = (i: number) => res[i].meta.changes;
  return json({
    ok: true,
    erased: { accounts: n(13), devices: n(12), players: n(4), claims: n(8), scores: n(7), push_tokens: n(5) },
    scrubbed: { matches: n(0), rooms: n(1) },
  });
}

// ---------- economy ----------

const ECON_DAY_MS = 86_400_000;
const ECON_OFFSET_MS = DAY_OFFSET_MIN * 60_000;
const dayName = (n: number): string => new Date(n * ECON_DAY_MS).toISOString().slice(0, 10);

/** First ledger id with at >= from (ledger has no index on `at`; ids grow with time, so bisect: ~log2(n) point reads). */
async function ledgerStartId(db: D1Database, from: number): Promise<number> {
  const top = await db.prepare("SELECT MAX(id) AS m FROM ledger").first<{ m: number | null }>();
  let lo = 1;
  let hi = (top?.m ?? 0) + 1; // answer in [lo, hi]; hi = "none"
  while (lo < hi) {
    const mid = Math.floor((lo + hi) / 2);
    const r = await db.prepare("SELECT at FROM ledger WHERE id >= ? ORDER BY id LIMIT 1").bind(mid).first<{ at: number }>();
    if (!r || r.at >= from) hi = mid;
    else lo = mid + 1;
  }
  return lo;
}

/**
 * GET /admin/api/economy?days=14 (1-60): per Bangladesh economy day over the last N days, from ledger, table_matches,
 * entries, rerolls, ad_rewards and purchases (ADMIN_API.md "Economy"). A handful of grouped queries on time ranges.
 */
async function economy(c: Ctx): Promise<Response> {
  const asked = Math.trunc(Number(param(c.url, "days") ?? "14"));
  const days = Number.isNaN(asked) ? 14 : Math.min(60, Math.max(1, asked));
  const todayStart = econDayStartMs(c.now);
  const from = todayStart - (days - 1) * ECON_DAY_MS;
  const to = todayStart + ECON_DAY_MS;
  const todayN = Math.floor((todayStart + ECON_OFFSET_MS) / ECON_DAY_MS);
  const firstN = todayN - (days - 1);
  const db = c.env.DB;
  const D = `((at + ${ECON_OFFSET_MS}) / ${ECON_DAY_MS})`;
  const startId = await ledgerStartId(db, from);
  const [led, tm, en, rr, ad, pu, circ] = await db.batch([
    db.prepare(
      `SELECT ${D} AS d, reason,
         COALESCE(SUM(CASE WHEN delta_coins > 0 THEN delta_coins END), 0) AS coins_created,
         COALESCE(SUM(CASE WHEN delta_coins < 0 THEN -delta_coins END), 0) AS coins_spent,
         COALESCE(SUM(CASE WHEN delta_gems > 0 THEN delta_gems END), 0) AS gems_created,
         COALESCE(SUM(CASE WHEN delta_gems < 0 THEN -delta_gems END), 0) AS gems_spent
       FROM ledger WHERE id >= ? AND at >= ? AND at < ? GROUP BY d, reason`,
    ).bind(startId, from, to),
    db.prepare(
      `SELECT ${D} AS d, tier, COUNT(*) AS matches, SUM(pot) AS pot, SUM(fee) AS fee, SUM(paid_humans) AS paid_humans,
         SUM(winner_ghost) AS ghost_wins
       FROM table_matches WHERE at >= ? AND at < ? GROUP BY d, tier`,
    ).bind(from, to),
    db.prepare(
      `SELECT ${D} AS d, tier, COUNT(*) AS entries, SUM(amount) AS coins_in, SUM(payout) AS payouts
       FROM entries WHERE status IN ('playing', 'settled', 'forfeit') AND at >= ? AND at < ? GROUP BY d, tier`,
    ).bind(from, to),
    db.prepare(
      `SELECT ${D} AS d, paid, COUNT(*) AS n FROM rerolls WHERE at >= ? AND at < ? GROUP BY d, paid`,
    ).bind(from, to),
    db.prepare(
      `SELECT ((granted_at + ${ECON_OFFSET_MS}) / ${ECON_DAY_MS}) AS d, kind, COUNT(*) AS n
       FROM ad_rewards WHERE status = 'granted' AND granted_at >= ? AND granted_at < ? GROUP BY d, kind`,
    ).bind(from, to),
    db.prepare(
      `SELECT ${D} AS d, COUNT(*) AS n, COALESCE(SUM(CASE WHEN status = 'granted' THEN gems END), 0) AS gems,
         COALESCE(SUM(status = 'voided'), 0) AS voided
       FROM purchases WHERE at >= ? AND at < ? GROUP BY d`,
    ).bind(from, to),
    db.prepare("SELECT COALESCE(SUM(coins), 0) AS coins, COALESCE(SUM(gems), 0) AS gems FROM accounts WHERE merged_into IS NULL"),
  ]);
  type R = Record<string, number | string>;
  const num = (v: unknown): number => Math.trunc(Number(v) || 0);
  const inRange = (r: R): boolean => num(r.d) >= firstN && num(r.d) <= todayN;
  const dayList = Array.from({ length: days }, (_, i) => dayName(firstN + i));
  const perDay = new Map(dayList.map((d) => [d, { day: d, coins_created: 0, coins_spent: 0, gems_created: 0, gems_spent: 0, fees: 0 }]));
  const byReason = new Map<string, { reason: string; coins_created: number; coins_spent: number; gems_created: number; gems_spent: number }>();
  const ledger = (led.results as R[]).filter(inRange).map((r) => {
    const o = { day: dayName(num(r.d)), reason: String(r.reason), coins_created: num(r.coins_created), coins_spent: num(r.coins_spent), gems_created: num(r.gems_created), gems_spent: num(r.gems_spent) };
    const pd = perDay.get(o.day)!;
    pd.coins_created += o.coins_created; pd.coins_spent += o.coins_spent; pd.gems_created += o.gems_created; pd.gems_spent += o.gems_spent;
    const t = byReason.get(o.reason) ?? { reason: o.reason, coins_created: 0, coins_spent: 0, gems_created: 0, gems_spent: 0 };
    t.coins_created += o.coins_created; t.coins_spent += o.coins_spent; t.gems_created += o.gems_created; t.gems_spent += o.gems_spent;
    byReason.set(o.reason, t);
    return o;
  });
  const tierRow = (tier: string) => ({ tier, matches: 0, pot: 0, fee: 0, paid_humans: 0, ghost_wins: 0, ghost_win_rate: null as number | null, entries: 0, coins_in: 0, payouts: 0 });
  type Tier = ReturnType<typeof tierRow>;
  const rate = <T extends Tier>(t: T): T => { t.ghost_win_rate = t.matches > 0 ? t.ghost_wins / t.matches : null; return t; };
  const tierTotals = new Map<string, Tier>();
  const tables = new Map<string, Tier & { day: string }>();
  const cell = (r: R): Tier & { day: string } => {
    const day = dayName(num(r.d));
    const k = day + "|" + r.tier;
    if (!tables.has(k)) tables.set(k, { day, ...tierRow(String(r.tier)) });
    return tables.get(k)!;
  };
  const total = (tier: string): Tier => {
    if (!tierTotals.has(tier)) tierTotals.set(tier, tierRow(tier));
    return tierTotals.get(tier)!;
  };
  for (const r of (tm.results as R[]).filter(inRange)) {
    for (const t of [cell(r), total(String(r.tier))]) {
      t.matches += num(r.matches); t.pot += num(r.pot); t.fee += num(r.fee); t.paid_humans += num(r.paid_humans); t.ghost_wins += num(r.ghost_wins);
    }
    perDay.get(dayName(num(r.d)))!.fees += num(r.fee);
  }
  for (const r of (en.results as R[]).filter(inRange)) {
    for (const t of [cell(r), total(String(r.tier))]) { t.entries += num(r.entries); t.coins_in += num(r.coins_in); t.payouts += num(r.payouts); }
  }
  const rerollRows = (rr.results as R[]).filter(inRange).map((r) => ({ day: dayName(num(r.d)), paid: String(r.paid), n: num(r.n) }));
  const adRows = (ad.results as R[]).filter(inRange).map((r) => ({ day: dayName(num(r.d)), kind: String(r.kind), granted: num(r.n) }));
  const purRows = (pu.results as R[]).filter(inRange).map((r) => ({ day: dayName(num(r.d)), count: num(r.n), gems: num(r.gems), voided: num(r.voided) }));
  const sumBy = <T,>(rows: T[], f: (r: T) => number) => rows.reduce((a, r) => a + f(r), 0);
  const adTotals: Record<string, number> = {};
  for (const r of adRows) adTotals[r.kind] = (adTotals[r.kind] ?? 0) + r.granted;
  const pd = [...perDay.values()];
  const cc = (circ.results as R[])[0] ?? {};
  return json({
    now: c.now,
    days,
    from: dayList[0],
    to: dayList[days - 1],
    per_day: pd,
    ledger,
    tables: [...tables.values()].map(rate).sort((a, b) => (a.day < b.day ? -1 : a.day > b.day ? 1 : a.tier < b.tier ? -1 : 1)),
    rerolls: rerollRows,
    ads: adRows,
    purchases: purRows,
    totals: {
      coins_created: sumBy(pd, (r) => r.coins_created),
      coins_spent: sumBy(pd, (r) => r.coins_spent),
      gems_created: sumBy(pd, (r) => r.gems_created),
      gems_spent: sumBy(pd, (r) => r.gems_spent),
      fees: sumBy(pd, (r) => r.fees),
      by_reason: [...byReason.values()].sort((a, b) => a.reason.localeCompare(b.reason)),
      tables: [...tierTotals.values()].map(rate).sort((a, b) => a.tier.localeCompare(b.tier)),
      rerolls: { free: sumBy(rerollRows.filter((r) => r.paid === "free"), (r) => r.n), gems: sumBy(rerollRows.filter((r) => r.paid === "gems"), (r) => r.n) },
      ads: adTotals,
      purchases: { count: sumBy(purRows, (r) => r.count), gems: sumBy(purRows, (r) => r.gems), voided: sumBy(purRows, (r) => r.voided) },
    },
    coins_in_circulation: num(cc.coins),
    gems_in_circulation: num(cc.gems),
  });
}

/**
 * POST /admin/api/accounts/:id/ban {reason} / unban. Ban: the account ("admin_account") and the pids of its devices
 * that are not banned yet ("account:<id>"), each kicked from its latest room. Unban: the account, and the pid bans
 * this account's ban caused (pid bans made on the Players page stay: `still_banned_pids`).
 */
async function accountBan(c: Ctx, raw: string, ban: boolean): Promise<Response> {
  const id = accountId(raw);
  if (!id) return fail(404, "not_found");
  const o = await body(c.req);
  const reason = ban ? optString(o, "reason", 200, 3)! : null;
  const db = c.env.DB;
  if (!(await setAccountBan(db, id, ban, reason, "admin_account"))) return fail(404, "not_found");
  const devs = (await db.prepare("SELECT pid FROM devices WHERE account_id = ?").bind(id).all<{ pid: string }>()).results.map((r) => r.pid);
  const src = `account:${id}`;
  if (ban) {
    await ensurePlayerRows(db, devs);
    if (devs.length) {
      await db.batch(
        devs.map((pid) =>
          db.prepare("UPDATE players SET banned = 1, ban_reason = ?, ban_source = ? WHERE pid = ? AND banned = 0").bind(reason, src, pid),
        ),
      );
    }
  } else {
    // lift the pid bans this account's ban caused (also of devices that moved to another account since)
    await db.prepare("UPDATE players SET banned = 0, ban_reason = NULL, ban_source = NULL WHERE banned = 1 AND ban_source = ?").bind(src).run();
  }
  const { results } = await db
    .prepare("SELECT d.pid, p.last_room, COALESCE(p.banned, 0) AS banned FROM devices d LEFT JOIN players p ON p.pid = d.pid WHERE d.account_id = ?")
    .bind(id)
    .all<{ pid: string; last_room: string | null; banned: number }>();
  let kicked = 0;
  for (const r of results) {
    if (!r.last_room || !isCode(r.last_room)) continue;
    try {
      if (ban) kicked += (await stub(c.env, r.last_room).adminBan(r.pid, reason ?? "")) ? 1 : 0;
      else if (!r.banned) await stub(c.env, r.last_room).adminUnban(r.pid);
    } catch (e) {
      console.error("account ban kick failed:", e);
    }
  }
  const stillBanned = results.filter((r) => r.banned === 1).map((r) => r.pid);
  await audit(c, ban ? "account.ban" : "account.unban", id, ban ? { reason, kicked } : stillBanned.length ? { still_banned_pids: stillBanned } : undefined);
  const account = adminAccountOut((await getAccount(db, id))!);
  return json(ban ? { ok: true, kicked, account } : { ok: true, account, still_banned_pids: stillBanned });
}

async function accountPatch(c: Ctx, raw: string): Promise<Response> {
  const id = accountId(raw);
  if (!id) return fail(404, "not_found");
  const o = await body(c.req);
  if (!("note" in o)) throw new BadRequest("note: string or null");
  const note = optString(o, "note", 500);
  const r = await c.env.DB.prepare("UPDATE accounts SET note = ? WHERE id = ?").bind(note || null, id).run();
  if (r.meta.changes === 0) return fail(404, "not_found");
  await audit(c, "account.note", id, { note: note || null });
  return json({ ok: true, account: adminAccountOut((await getAccount(c.env.DB, id))!) });
}

// ----- v2: leaderboards, quick match -----

async function leaderboards(c: Ctx): Promise<Response> {
  const board = (oneOf(c.url, "board", BOARDS) ?? "xp") as Board;
  const period = (oneOf(c.url, "period", PERIODS) ?? "all") as PeriodArg;
  const week = param(c.url, "week", 8);
  if (week !== undefined && (period !== "week" || !/^\d{4}-W\d{2}$/.test(week))) throw new BadRequest("week: YYYY-Www, with period=week");
  const l = c.url.searchParams.get("limit");
  let limit = 50;
  if (l !== null && l !== "") {
    if (!/^\d{1,3}$/.test(l) || Number(l) < 1 || Number(l) > 200) throw new BadRequest("limit: 1-200");
    limit = Number(l);
  }
  const key = periodKey(period, c.now, week);
  const [top, total] = await Promise.all([topScores(c.env.DB, board, key, limit), countScores(c.env.DB, board, key)]);
  return json({ board, period: key === "all" ? "all" : "week", week: key === "all" ? null : key.slice(5), total, top });
}

async function quick(c: Ctx): Promise<Response> {
  const d = c.url.searchParams.get("days");
  let days = 14;
  if (d !== null && d !== "") {
    if (!/^\d{1,2}$/.test(d) || Number(d) < 1 || Number(d) > 90) throw new BadRequest("days: 1-90");
    days = Number(d);
  }
  return json(await D.quickReport(c.env.DB, days, c.now));
}

// ----- notifications (NOTIFICATIONS.md "N-SRV") -----

/** At most this many campaigns in any 24 h (canceled ones don't count), and test sends per hour. */
export const PUSH_LIMITS = { campaignsPerDay: 4, testsPerHour: 20 };
const HOUR_MS = 3_600_000;
const DAY_MS = 86_400_000;
/** A campaign may be scheduled at most this far ahead. */
const SCHEDULE_MAX_MS = 30 * DAY_MS;

function pushOff(): Response {
  return fail(409, "push_off", "Push is not configured: set the FCM_SERVICE_ACCOUNT secret (tools/cf.sh secret put FCM_SERVICE_ACCOUNT).");
}

async function pushUsage(c: Ctx): Promise<{ campaigns: number; tests: number }> {
  const db = c.env.DB;
  const [camps, tests] = await db.batch([
    db.prepare("SELECT COUNT(*) AS n FROM push_campaigns WHERE created_at >= ? AND status != 'canceled'").bind(c.now - DAY_MS),
    db.prepare("SELECT COUNT(*) AS n FROM admin_log WHERE action = 'push.test' AND at >= ?").bind(c.now - HOUR_MS),
  ]);
  return { campaigns: (camps.results[0] as { n: number }).n, tests: (tests.results[0] as { n: number }).n };
}

/** GET /admin/api/push: whether push is on, device counts, the event-push counters (14 UTC days), the latest campaigns. */
async function pushOverview(c: Ctx): Promise<Response> {
  const db = c.env.DB;
  const [tokens, events, campaigns] = await db.batch([
    db.prepare("SELECT COUNT(*) AS total, COALESCE(SUM(prefs_offers = 1), 0) AS offers, COALESCE(SUM(prefs_game = 1), 0) AS game FROM push_tokens"),
    db.prepare("SELECT day, kind, sent, failed FROM push_events WHERE day >= ? ORDER BY day, kind").bind(D.utcDay(c.now - 13 * DAY_MS)),
    db.prepare("SELECT * FROM push_campaigns ORDER BY created_at DESC, id DESC LIMIT 50"),
  ]);
  const used = await pushUsage(c);
  return json({
    now: c.now,
    configured: P.pushConfigured(c.env),
    project_id: P.pushProject(c.env),
    tokens: tokens.results[0],
    events: events.results,
    campaigns: (campaigns.results as unknown as P.CampaignRow[]).map(P.campaignOut),
    limits: {
      campaigns_per_day: PUSH_LIMITS.campaignsPerDay,
      campaigns_left: Math.max(0, PUSH_LIMITS.campaignsPerDay - used.campaigns),
      tests_per_hour: PUSH_LIMITS.testsPerHour,
      tests_left: Math.max(0, PUSH_LIMITS.testsPerHour - used.tests),
    },
  });
}

function audienceOf(o: Record<string, unknown>): P.Audience {
  const a = P.parseAudience(o.audience);
  if (typeof a === "string") throw new BadRequest(a);
  return a;
}

/** title 1-60, body 1-180, link (a deep link, default "home"). */
function pushContent(o: Record<string, unknown>): { title: string; body: string; link: string } {
  const title = optString(o, "title", 60, 1)!;
  const text = optString(o, "body", 180, 1)!;
  const link = optString(o, "link", 80) || "home";
  if (!P.isLink(link)) throw new BadRequest("link: home, daily, spin, free, shop, shop:<kind>:<id>, room:<CODE> or leaderboard");
  return { title, body: text, link };
}

/** POST /admin/api/push/preview {audience} -> {targeted}: the devices it reaches now (nothing is sent). */
async function pushPreview(c: Ctx): Promise<Response> {
  const aud = audienceOf(await body(c.req));
  return json({ targeted: await P.countAudience(c.env.DB, aud, c.now) });
}

/** POST /admin/api/push/test {title, body, link?, account_id} -> {sent, failed, tokens}: to every device of the account, now. */
async function pushTest(c: Ctx): Promise<Response> {
  const o = await body(c.req);
  const content = pushContent(o);
  const id = typeof o.account_id === "string" ? accountId(o.account_id) : null;
  if (!id) throw new BadRequest("account_id: an account id");
  if (!P.pushConfigured(c.env)) return pushOff();
  if ((await pushUsage(c)).tests >= PUSH_LIMITS.testsPerHour) {
    return fail(429, "rate_limited", `at most ${PUSH_LIMITS.testsPerHour} test sends per hour`);
  }
  if (!(await getAccount(c.env.DB, id))) return fail(404, "not_found", "no such account");
  const r = await P.pushAccount(c.env, id, { kind: "test", ...content, channel: "offers", tag: "test", ttl_s: P.EVENT_TTL_S, priority: "high" }, { pref: null, count: false });
  await audit(c, "push.test", id, { title: content.title, sent: r.sent, failed: r.failed });
  return json(r);
}

/**
 * POST /admin/api/push/campaigns {title, body, link?, audience, run_at?} -> the campaign. run_at (unix seconds or
 * epoch ms) in the future: status "scheduled", else "sending" and queued now. The Pusher sends it.
 */
async function pushCampaign(c: Ctx): Promise<Response> {
  const o = await body(c.req);
  const content = pushContent(o);
  const aud = audienceOf(o);
  let runAt: number | null = null;
  if (o.run_at !== undefined && o.run_at !== null) {
    const v = o.run_at;
    if (typeof v !== "number" || !Number.isInteger(v) || v < 0) throw new BadRequest("run_at: unix seconds or epoch ms");
    runAt = v < 1e11 ? v * 1000 : v;
    if (runAt > c.now + SCHEDULE_MAX_MS) throw new BadRequest("run_at: at most 30 days ahead");
    if (runAt <= c.now) runAt = null;
  }
  if (!P.pushConfigured(c.env)) return pushOff();
  if ((await pushUsage(c)).campaigns >= PUSH_LIMITS.campaignsPerDay) {
    return fail(429, "rate_limited", `at most ${PUSH_LIMITS.campaignsPerDay} campaigns per day`);
  }
  const db = c.env.DB;
  const id = P.newCampaignId();
  const targeted = await P.countAudience(db, aud, c.now);
  const row = await db
    .prepare(
      `INSERT INTO push_campaigns (id, title, body, link, audience, status, run_at, created_by, created_at, targeted)
       VALUES (?, ?, ?, ?, ?, ?, ?, 'admin', ?, ?) RETURNING *`,
    )
    .bind(id, content.title, content.body, content.link, JSON.stringify(aud), runAt ? "scheduled" : "sending", runAt, c.now, targeted)
    .first<P.CampaignRow>();
  try {
    await P.pusher(c.env).enqueueCampaign(id, runAt ?? c.now);
  } catch (e) {
    await db.prepare("UPDATE push_campaigns SET status = 'failed' WHERE id = ?").bind(id).run();
    throw e;
  }
  await audit(c, "push.campaign", id, { title: content.title, audience: aud, run_at: runAt, targeted });
  return json(P.campaignOut(row!));
}

/** POST /admin/api/push/campaigns/:id/cancel: a scheduled campaign only (409 bad_state otherwise). */
async function pushCancel(c: Ctx, raw: string): Promise<Response> {
  const id = decode(raw);
  if (!P.CAMPAIGN_RE.test(id)) return fail(404, "not_found");
  const db = c.env.DB;
  const r = await db.prepare("UPDATE push_campaigns SET status = 'canceled' WHERE id = ? AND status = 'scheduled'").bind(id).run();
  const row = await db.prepare("SELECT * FROM push_campaigns WHERE id = ?").bind(id).first<P.CampaignRow>();
  if (!row) return fail(404, "not_found");
  if (r.meta.changes === 0) return fail(409, "bad_state", `only a scheduled campaign can be canceled (this one is ${row.status})`);
  try {
    await P.pusher(c.env).cancelCampaign(id);
  } catch (e) {
    console.error("pusher cancel failed:", e); // its start finds the campaign canceled and drops it
  }
  await audit(c, "push.cancel", id, { title: row.title });
  return json(P.campaignOut(row));
}
