// Push notifications (NOTIFICATIONS.md "N-SRV"): the FCM HTTP v1 sender (an OAuth access token from a JWT signed
// RS256 with the service account's key, WebCrypto), the device tokens in D1 `push_tokens`, the /v1/push/* endpoints,
// the event pushes a Room sends inline, the weekly-result pushes of the daily cron and the D1 side of the admin's
// campaigns (the queue that sends them is the Pusher Durable Object, src/pusher.ts).
// Push is off until the FCM_SERVICE_ACCOUNT secret is set: every send is then a no-op and the endpoints still answer.
// Every HTTP call goes through `pushFetch`, which tests replace with setPushFetcher() (a fake FCM).
import * as A from "./accounts";
import * as D from "./db";
import { CATALOG, DAY_OFFSET_MIN, isoWeek } from "./econ";
import { topScores } from "./leaderboard";
import type { Env } from "./room";

export const TOKEN_URL = "https://oauth2.googleapis.com/token";
export const FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging";

export function sendUrl(projectId: string): string {
  return `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;
}

export type Fetcher = (input: string, init?: RequestInit) => Promise<Response>;

let pushFetch: Fetcher = (input, init) => fetch(input, init);

/** Tests: route Google's OAuth and FCM endpoints to a fake. `null` restores the real fetch. */
export function setPushFetcher(f: Fetcher | null): void {
  pushFetch = f ?? ((input, init) => fetch(input, init));
}

export interface PushEnv {
  DB: D1Database;
  /** The Firebase project's service-account JSON, whole (a secret). Unset: push is off. */
  FCM_SERVICE_ACCOUNT?: string;
  TEST_MODE?: string;
}

// ---------- the service account ----------

interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
  private_key_id: string;
}

/** undefined: env.FCM_SERVICE_ACCOUNT; a string or null: that instead (tests). */
let accountOverride: string | null | undefined;
let parsed: { raw: string; sa: ServiceAccount | null } | null = null;

/** Tests: use this service-account JSON instead of the secret (null: push off; undefined: back to the secret). */
export function setPushServiceAccount(json: string | null | undefined): void {
  accountOverride = json;
  parsed = null;
  tokenCache = null;
}

function serviceAccount(env: { FCM_SERVICE_ACCOUNT?: string }): ServiceAccount | null {
  const raw = accountOverride !== undefined ? accountOverride : env.FCM_SERVICE_ACCOUNT;
  if (!raw) return null;
  if (parsed?.raw === raw) return parsed.sa;
  let sa: ServiceAccount | null = null;
  try {
    const j = JSON.parse(raw) as Record<string, unknown>;
    if (
      typeof j.project_id === "string" &&
      /^[a-z0-9-]{1,64}$/.test(j.project_id) &&
      typeof j.client_email === "string" &&
      j.client_email.includes("@") &&
      typeof j.private_key === "string" &&
      j.private_key.includes("PRIVATE KEY")
    ) {
      sa = {
        project_id: j.project_id,
        client_email: j.client_email,
        private_key: j.private_key,
        private_key_id: typeof j.private_key_id === "string" ? j.private_key_id : "",
      };
    }
  } catch {
    /* not JSON */
  }
  if (!sa) console.error("FCM_SERVICE_ACCOUNT is not a service-account JSON (project_id, client_email, private_key): push is off");
  parsed = { raw, sa };
  return sa;
}

/** Push is on: FCM_SERVICE_ACCOUNT holds a usable service-account JSON. */
export function pushConfigured(env: { FCM_SERVICE_ACCOUNT?: string }): boolean {
  return serviceAccount(env) !== null;
}

/** The Firebase project id (admin display), or null when push is off. */
export function pushProject(env: { FCM_SERVICE_ACCOUNT?: string }): string | null {
  return serviceAccount(env)?.project_id ?? null;
}

// ---------- OAuth: JWT (RS256) -> access token ----------

const enc = new TextEncoder();
/** The access token is renewed this long before it expires. */
const TOKEN_MARGIN_MS = 5 * 60_000;
const TIMEOUT_MS = 8000;

let tokenCache: { key: string; p: Promise<{ token: string; exp: number } | null> } | null = null;
const keyCache = new Map<string, Promise<CryptoKey>>();

function b64url(data: ArrayBuffer | Uint8Array | string): string {
  const a = typeof data === "string" ? enc.encode(data) : data instanceof Uint8Array ? data : new Uint8Array(data);
  let s = "";
  for (const b of a) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** The PKCS8 key of the PEM "-----BEGIN PRIVATE KEY-----" block. */
function signingKey(pem: string): Promise<CryptoKey> {
  let p = keyCache.get(pem);
  if (!p) {
    const b64 = pem.replace(/-----[A-Z ]+-----/g, "").replace(/\s+/g, "");
    const der = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
    p = crypto.subtle.importKey("pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
    p.catch(() => keyCache.delete(pem));
    keyCache.set(pem, p);
  }
  return p;
}

/** The signed JWT Google's token endpoint exchanges for an access token (valid 1 h). */
async function assertion(sa: ServiceAccount, nowMs: number): Promise<string> {
  const iat = Math.floor(nowMs / 1000);
  const head = b64url(JSON.stringify({ alg: "RS256", typ: "JWT", kid: sa.private_key_id || undefined }));
  const claims = b64url(JSON.stringify({ iss: sa.client_email, scope: FCM_SCOPE, aud: TOKEN_URL, iat, exp: iat + 3600 }));
  const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", await signingKey(sa.private_key), enc.encode(`${head}.${claims}`));
  return `${head}.${claims}.${b64url(sig)}`;
}

async function call(url: string, init: RequestInit): Promise<Response> {
  const ac = new AbortController();
  const t = setTimeout(() => ac.abort(), TIMEOUT_MS);
  try {
    return await pushFetch(url, { ...init, signal: ac.signal });
  } finally {
    clearTimeout(t);
  }
}

async function fetchToken(sa: ServiceAccount): Promise<{ token: string; exp: number } | null> {
  try {
    const now = Date.now();
    const res = await call(TOKEN_URL, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: await assertion(sa, now) }).toString(),
    });
    const j = (await res.json().catch(() => null)) as { access_token?: unknown; expires_in?: unknown; error?: unknown } | null;
    if (!res.ok || typeof j?.access_token !== "string" || !j.access_token) {
      console.error(`FCM access token refused: ${res.status} ${typeof j?.error === "string" ? j.error : ""}`);
      return null;
    }
    const ttl = typeof j.expires_in === "number" && j.expires_in > 0 ? j.expires_in : 3600;
    return { token: j.access_token, exp: now + ttl * 1000 };
  } catch (e) {
    console.error("FCM access token failed:", e);
    return null;
  }
}

/** The cached access token (in memory, per isolate, until 5 min before it expires); `renew` forces a new one. */
async function accessToken(sa: ServiceAccount, renew = false): Promise<string | null> {
  const key = `${sa.project_id}\u0000${sa.client_email}\u0000${sa.private_key_id}`;
  const c = tokenCache;
  if (!renew && c && c.key === key) {
    const v = await c.p;
    if (v && v.exp - TOKEN_MARGIN_MS > Date.now()) return v.token;
    if (tokenCache !== c) return accessToken(sa); // someone else is renewing it
  }
  const p = fetchToken(sa);
  tokenCache = { key, p };
  const v = await p;
  if (!v && tokenCache?.p === p) tokenCache = null;
  return v?.token ?? null;
}

// ---------- sending ----------

export type PushKind = "turn" | "joined" | "rematch" | "weekly" | "promo" | "test";
/** Android channel (NOTIFICATIONS.md "Ids and texts"): game alerts are high priority, offers normal. */
export type Channel = "game" | "offers";

export interface Note {
  kind: PushKind;
  title: string;
  body: string;
  /** Deep link (NOTIFICATIONS.md): home, daily, spin, free, shop[:kind:id], room:<CODE>, leaderboard. */
  link: string;
  /** Campaign id (open stats). */
  cid?: string;
  channel: Channel;
  /** collapse_key and notification tag: a phone shows the latest push of a tag only. */
  tag?: string;
  /** FCM delivery priority; default by channel (game high, offers normal: Android may hold those while dozing). */
  priority?: "high" | "normal";
  ttl_s: number;
}

export type Target = { token: string } | { topic: string };

/** sent; dead: the token is gone (deleted from D1); retry: FCM / the network failed for now; failed: refused. */
export type SendResult = "sent" | "dead" | "retry" | "failed";

/** The topic every device with News & offers on subscribes to (the "everyone" audience). */
export const PROMO_TOPIC = "promos";
export const EVENT_TTL_S = 30 * 60;
export const DAY_TTL_S = 86400;

/** The FCM v1 request body. */
export function fcmMessage(t: Target, n: Note): Record<string, unknown> {
  const data: Record<string, string> = { link: n.link, kind: n.kind };
  if (n.cid) data.cid = n.cid;
  const android: Record<string, unknown> = {
    priority: n.priority ?? (n.channel === "game" ? "high" : "normal"),
    ttl: `${n.ttl_s}s`,
    notification: n.tag ? { channel_id: n.channel, tag: n.tag } : { channel_id: n.channel },
  };
  if (n.tag) android.collapse_key = n.tag;
  return { message: { ...t, notification: { title: n.title, body: n.body }, data, android } };
}

interface FcmError {
  error?: { code?: number; status?: string; message?: string; details?: Array<{ errorCode?: string }> };
}

/**
 * What an FCM error means. UNREGISTERED / SENDER_ID_MISMATCH and INVALID_ARGUMENT about the registration token: the
 * token is dead (an INVALID_ARGUMENT about anything else is our message: failed, the token is kept). 429 / 5xx:
 * retry later.
 */
export function classify(status: number, body: unknown, toToken: boolean): SendResult {
  const e = (body as FcmError | null)?.error;
  const code = e?.details?.find((d) => typeof d?.errorCode === "string")?.errorCode ?? e?.status ?? "";
  if (toToken && (code === "UNREGISTERED" || code === "SENDER_ID_MISMATCH")) return "dead";
  if (toToken && code === "INVALID_ARGUMENT" && /registration token/i.test(e?.message ?? "")) return "dead";
  if (status === 429 || status >= 500 || code === "UNAVAILABLE" || code === "INTERNAL" || code === "QUOTA_EXCEEDED") return "retry";
  return "failed";
}

/** One FCM send (1 subrequest; +1 when the access token is fetched or renewed). Never throws. */
export async function send(env: { FCM_SERVICE_ACCOUNT?: string }, t: Target, n: Note): Promise<SendResult> {
  const sa = serviceAccount(env);
  if (!sa) return "failed";
  const body = JSON.stringify(fcmMessage(t, n));
  for (let attempt = 0; attempt < 2; attempt++) {
    const at = await accessToken(sa, attempt > 0);
    if (!at) return "retry";
    let res: Response;
    try {
      res = await call(sendUrl(sa.project_id), {
        method: "POST",
        headers: { Authorization: `Bearer ${at}`, "Content-Type": "application/json" },
        body,
      });
    } catch (e) {
      console.error("FCM send failed:", e);
      return "retry";
    }
    const j = await res.json().catch(() => null);
    if (res.ok) return "sent";
    if (res.status === 401 && attempt === 0) continue; // the access token was refused: a new one, once
    const r = classify(res.status, j, "token" in t);
    if (r === "failed") console.error(`FCM refused a push: ${res.status} ${JSON.stringify(j).slice(0, 300)}`);
    return r;
  }
  return "failed";
}

// ---------- tokens (D1 push_tokens) ----------

/** An account keeps at most this many devices (the most recently updated). */
export const MAX_TOKENS = 5;
const TOKEN_RE = /^[A-Za-z0-9_:.-]{32,1024}$/;

export function dropTokens(db: D1Database, tokens: string[]): D1PreparedStatement[] {
  return tokens.map((t) => db.prepare("DELETE FROM push_tokens WHERE token = ?").bind(t));
}

/** The account's tokens; `pref`: only those with that toggle on. */
export async function accountTokens(db: D1Database, accountId: string, pref: Channel | null): Promise<string[]> {
  const where = pref === "game" ? " AND prefs_game = 1" : pref === "offers" ? " AND prefs_offers = 1" : "";
  const { results } = await db
    .prepare(`SELECT token FROM push_tokens WHERE account_id = ?${where} ORDER BY updated_at DESC LIMIT ${MAX_TOKENS}`)
    .bind(accountId)
    .all<{ token: string }>();
  return results.map((r) => r.token);
}

/** push_events counters (UTC day, kind). */
export function countEvent(db: D1Database, kind: PushKind, sent: number, failed: number, now: number): D1PreparedStatement {
  return db
    .prepare(
      `INSERT INTO push_events (day, kind, sent, failed) VALUES (?, ?, ?, ?)
       ON CONFLICT (day, kind) DO UPDATE SET sent = push_events.sent + excluded.sent, failed = push_events.failed + excluded.failed`,
    )
    .bind(D.utcDay(now), kind, sent, failed);
}

/**
 * A push to every device of an account now (in parallel; dead tokens deleted). `pref`: only the devices with that
 * toggle on (event pushes: "game"); `count`: add the result to push_events. Push off: nothing (no D1 either).
 * Cost: 1 D1 read, 1 send per device (+1 for a new access token), 1 D1 write batch when something was sent.
 */
export async function pushAccount(
  env: PushEnv,
  accountId: string,
  n: Note,
  o: { pref: Channel | null; count: boolean },
): Promise<{ sent: number; failed: number; tokens: number }> {
  if (!pushConfigured(env)) return { sent: 0, failed: 0, tokens: 0 };
  const tokens = await accountTokens(env.DB, accountId, o.pref);
  if (!tokens.length) return { sent: 0, failed: 0, tokens: 0 };
  const rs = await Promise.all(tokens.map((token) => send(env, { token }, n)));
  const dead = tokens.filter((_t, k) => rs[k] === "dead");
  const sent = rs.filter((r) => r === "sent").length;
  const failed = rs.length - sent;
  const stmts = dropTokens(env.DB, dead);
  if (o.count) stmts.push(countEvent(env.DB, n.kind, sent, failed, Date.now()));
  if (stmts.length) await env.DB.batch(stmts);
  return { sent, failed, tokens: tokens.length };
}

// ---------- /v1/push/* ----------

function bool(v: unknown, k: string, dflt: boolean): boolean {
  if (v === undefined || v === null) return dflt;
  if (typeof v !== "boolean") throw new A.BadRequest(`${k}: bool`);
  return v;
}

function tokenOf(o: Record<string, unknown>): string {
  if (typeof o.token !== "string" || !TOKEN_RE.test(o.token)) throw new A.BadRequest("token: an FCM registration token");
  return o.token;
}

/**
 * POST /v1/push/token {token, platform: "android", prefs: {game, offers}, tz_offset_min} -> {ok}. The token moves to
 * this account if another one had it; an account keeps its 5 latest tokens. Stored with push off too.
 */
export async function postToken(req: Request, env: A.AccEnv, a: A.Authed, now: number): Promise<Response> {
  const o = await A.readBody(req);
  const token = tokenOf(o);
  if (o.platform !== undefined && o.platform !== "android") throw new A.BadRequest('platform: "android"');
  const prefs = o.prefs ?? {};
  if (!prefs || typeof prefs !== "object" || Array.isArray(prefs)) throw new A.BadRequest("prefs: {game, offers}");
  const p = prefs as Record<string, unknown>;
  const game = bool(p.game, "prefs.game", true);
  const offers = bool(p.offers, "prefs.offers", true);
  const tz = o.tz_offset_min;
  if (tz !== undefined && tz !== null && (typeof tz !== "number" || !Number.isInteger(tz) || tz < -840 || tz > 840)) {
    throw new A.BadRequest("tz_offset_min: integer -840..840");
  }
  const id = a.row.id;
  const db = env.DB;
  await db.batch([
    db
      .prepare(
        `INSERT INTO push_tokens (token, account_id, platform, prefs_game, prefs_offers, tz_offset_min, created_at, updated_at)
         VALUES (?, ?, 'android', ?, ?, ?, ?, ?)
         ON CONFLICT (token) DO UPDATE SET account_id = excluded.account_id, platform = excluded.platform,
           prefs_game = excluded.prefs_game, prefs_offers = excluded.prefs_offers, tz_offset_min = excluded.tz_offset_min,
           updated_at = excluded.updated_at`,
      )
      .bind(token, id, game ? 1 : 0, offers ? 1 : 0, typeof tz === "number" ? tz : null, now, now),
    db
      .prepare(
        `DELETE FROM push_tokens WHERE account_id = ?1 AND token NOT IN
           (SELECT token FROM push_tokens WHERE account_id = ?1 ORDER BY updated_at DESC, created_at DESC, token LIMIT ${MAX_TOKENS})`,
      )
      .bind(id),
  ]);
  return A.authedJson(a, { ok: true });
}

/** DELETE /v1/push/token {token} -> {ok} (sign-out / account switch; only this account's token). */
export async function deleteToken(req: Request, env: A.AccEnv, a: A.Authed): Promise<Response> {
  const token = tokenOf(await A.readBody(req));
  await env.DB.prepare("DELETE FROM push_tokens WHERE token = ? AND account_id = ?").bind(token, a.row.id).run();
  return A.authedJson(a, { ok: true });
}

export const CAMPAIGN_RE = /^cmp_[a-z2-7]{12}$/;

/** A deep link the game routes (NOTIFICATIONS.md "Ids and texts"). */
export function isLink(s: string): boolean {
  return /^(home|daily|spin|free|shop|leaderboard|shop:[a-z_]{1,16}:[A-Za-z0-9_.-]{1,48}|room:[23456789ABCDEFGHJKMNPQRSTUVWXYZ]{6})$/.test(s);
}

/**
 * POST /v1/push/opened {cid} -> {ok}: a campaign push was opened. Counted once per account (push_opens) and only with a
 * valid session (pushes only reach devices of accounts); an unknown campaign or no session counts nothing.
 */
export async function postOpened(req: Request, env: A.AccEnv, now: number): Promise<Response> {
  const o = await A.readBody(req);
  if (typeof o.cid !== "string" || !CAMPAIGN_RE.test(o.cid)) throw new A.BadRequest("cid: a campaign id");
  const account = await A.optionalAccount(req, env, now);
  if (account) {
    const db = env.DB;
    // a recount, not +1: a repeated open changes nothing
    await db.batch([
      db
        .prepare("INSERT OR IGNORE INTO push_opens (cid, account_id, at) SELECT ?1, ?2, ?3 WHERE EXISTS (SELECT 1 FROM push_campaigns WHERE id = ?1)")
        .bind(o.cid, account, now),
      db.prepare("UPDATE push_campaigns SET opened = (SELECT COUNT(*) FROM push_opens WHERE cid = ?1) WHERE id = ?1").bind(o.cid),
    ]);
  }
  return A.json({ ok: true });
}

// ---------- campaigns (admin) ----------

export type Audience =
  | { kind: "all" }
  | { kind: "segment"; inactive_days?: number; new_days?: number; level_min?: number; level_max?: number };

const SEGMENT_KEYS = ["inactive_days", "new_days", "level_min", "level_max"] as const;
export const LEVEL_MAX = 500;
const DAY_MS = 86_400_000;

/** A validated audience, or the reason it is not one. */
export function parseAudience(v: unknown): Audience | string {
  if (!v || typeof v !== "object" || Array.isArray(v)) return 'audience: {kind: "all"} or {kind: "segment", ...}';
  const o = v as Record<string, unknown>;
  if (o.kind === "all") {
    if (Object.keys(o).length > 1) return 'audience: "all" takes no filters';
    return { kind: "all" };
  }
  if (o.kind !== "segment") return 'audience.kind: "all" | "segment"';
  const out: Audience = { kind: "segment" };
  for (const [k, x] of Object.entries(o)) {
    if (k === "kind" || x === undefined || x === null) continue;
    if (!(SEGMENT_KEYS as readonly string[]).includes(k)) return `audience: unknown filter ${k.slice(0, 40)}`;
    const max = k.startsWith("level") ? LEVEL_MAX : 365;
    if (typeof x !== "number" || !Number.isInteger(x) || x < 1 || x > max) return `audience.${k}: integer 1-${max}`;
    out[k as (typeof SEGMENT_KEYS)[number]] = x;
  }
  if (out.level_min !== undefined && out.level_max !== undefined && out.level_min > out.level_max) return "audience: level_min > level_max";
  return out;
}

/** The total XP at which `level` starts (econ levelInfo: level n needs base + step·(n−1) XP to reach n+1). */
export function levelXp(level: number): number {
  const { base, step } = CATALOG.level;
  const k = Math.max(0, level - 1);
  return k * base + (step * k * (k - 1)) / 2;
}

/** Tokens with News & offers on of live accounts (not banned, not merged) matching every filter of the audience. */
function audienceWhere(aud: Audience, now: number): { sql: string; params: unknown[] } {
  const w = ["t.prefs_offers = 1", "a.banned = 0", "a.merged_into IS NULL"];
  const params: unknown[] = [];
  if (aud.kind === "segment") {
    if (aud.inactive_days !== undefined) {
      w.push("COALESCE(a.last_seen, a.created_at) < ?");
      params.push(now - aud.inactive_days * DAY_MS);
    }
    if (aud.new_days !== undefined) {
      w.push("a.created_at >= ?");
      params.push(now - aud.new_days * DAY_MS);
    }
    if (aud.level_min !== undefined) {
      w.push("a.xp >= ?");
      params.push(levelXp(aud.level_min));
    }
    if (aud.level_max !== undefined) {
      w.push("a.xp < ?");
      params.push(levelXp(aud.level_max + 1));
    }
  }
  return { sql: w.join(" AND "), params };
}

/** How many devices the audience reaches now ("all": the devices subscribed to the promos topic). */
export async function countAudience(db: D1Database, aud: Audience, now: number): Promise<number> {
  const { sql, params } = audienceWhere(aud, now);
  const r = await db
    .prepare(`SELECT COUNT(*) AS n FROM push_tokens t JOIN accounts a ON a.id = t.account_id WHERE ${sql}`)
    .bind(...params)
    .first<{ n: number }>();
  return r?.n ?? 0;
}

/** The next page of a segment's tokens after `after` (token order: a stable cursor while the queue expands it). */
export async function audiencePage(db: D1Database, aud: Audience, now: number, after: string, limit: number): Promise<string[]> {
  const { sql, params } = audienceWhere(aud, now);
  const { results } = await db
    .prepare(`SELECT t.token FROM push_tokens t JOIN accounts a ON a.id = t.account_id WHERE ${sql} AND t.token > ? ORDER BY t.token LIMIT ?`)
    .bind(...params, after, limit)
    .all<{ token: string }>();
  return results.map((r) => r.token);
}

export interface CampaignRow {
  id: string;
  title: string;
  body: string;
  link: string;
  audience: string;
  status: "draft" | "scheduled" | "sending" | "sent" | "canceled" | "failed";
  run_at: number | null;
  created_by: string | null;
  created_at: number;
  sent_at: number | null;
  targeted: number;
  sent: number;
  failed: number;
  opened: number;
}

export function campaignOut(r: CampaignRow): Record<string, unknown> {
  let audience: unknown = null;
  try {
    audience = JSON.parse(r.audience);
  } catch {
    /* keep null */
  }
  return { ...r, audience };
}

export function campaignNote(c: Pick<CampaignRow, "id" | "title" | "body" | "link">): Note {
  return { kind: "promo", title: c.title, body: c.body, link: c.link, cid: c.id, channel: "offers", tag: c.id, ttl_s: DAY_TTL_S };
}

const ID_ABC = "abcdefghijklmnopqrstuvwxyz234567";

export function newCampaignId(): string {
  const r = crypto.getRandomValues(new Uint8Array(12));
  let s = "cmp_";
  for (const v of r) s += ID_ABC[v & 31];
  return s;
}

// ---------- the queue (Pusher DO) ----------

export function pusher(env: Env) {
  return env.PUSHER.get(env.PUSHER.idFromName("pusher"));
}

// ---------- weekly result (daily cron) ----------

export const WEEKLY_TOP = 100;

/** Monday in Bangladesh time (econ DAY_OFFSET_MIN days). */
export function isMondayBd(nowMs: number): boolean {
  const days = Math.floor((Math.floor(nowMs / 1000) + DAY_OFFSET_MIN * 60) / 86400);
  return (((days + 3) % 7) + 7) % 7 === 0;
}

/**
 * The daily cron on Monday (Bangladesh time): one push per device (Game alerts on) of the accounts on last week's XP
 * board top 100, queued in the Pusher (once per week: the batch key). The number queued; null when push is off or it
 * is not Monday.
 */
export async function weeklyPushes(env: Env, now: number): Promise<number | null> {
  if (!pushConfigured(env) || !isMondayBd(now)) return null;
  const week = isoWeek(Math.floor(now / 1000) - 7 * 86400);
  const top = await topScores(env.DB, "xp", `week:${week}`, WEEKLY_TOP);
  if (!top.length) return 0;
  const rank = new Map(top.map((t) => [t.account_id, t.rank]));
  const { results } = await env.DB.prepare(
    `SELECT token, account_id FROM push_tokens WHERE prefs_game = 1 AND account_id IN (${top.map(() => "?").join(", ")}) ORDER BY account_id, token`,
  )
    .bind(...top.map((t) => t.account_id))
    .all<{ token: string; account_id: string }>();
  const jobs = results.map((r) => ({
    key: `weekly:${week}:${r.token}`,
    token: r.token,
    note: {
      kind: "weekly",
      title: "Weekly results are in",
      body: `You finished #${rank.get(r.account_id)} on last week's board!`,
      link: "leaderboard",
      channel: "game",
      tag: "weekly",
      ttl_s: DAY_TTL_S,
    } satisfies Note,
  }));
  return pusher(env).enqueueBatch(`weekly:${week}`, jobs);
}

/** Deletes push_events rows older than the D1 retention (30 days); the number deleted. */
export async function prunePush(db: D1Database, now: number): Promise<number> {
  const r = await db.prepare("DELETE FROM push_events WHERE day < ?").bind(D.utcDay(now - D.RETENTION_MS)).run();
  return r.meta.changes ?? 0;
}
