// Accounts and sessions (ONLINE_V2.md §1): guest accounts per device id (pid), Google Play Games linking, the
// profile stored in D1 `accounts`, and the one write path every economy change goes through (mutate: optimistic
// concurrency on accounts.version, the ledger / scores / claims rows batched with it).
//
// Interface for the Room / quick match (W2-QM): verifySession, accountForPid, getPublicProfile, grantOnlineMatch.
import * as D from "./db";
import {
  DEFAULT_AVATAR,
  DEFAULT_FRAME,
  ECON_V1,
  ONLINE_REWARDS,
  addCoins,
  tablePayouts,
  type Profile,
  applyOnlineResult,
  cleanName,
  dayKey,
  reservedName,
  equip,
  equipped,
  importProfile,
  levelInfo,
  newProfile,
  normalizeProfile,
} from "./econ";
import { entryOpen, entrySettleStmt } from "./economy";
import { type GoogleEnv, type GooglePlayer, googleConfigured, playerFromAuthCode } from "./google";
import { type Guard, scoreStmts } from "./leaderboard";
import type { Env } from "./room";

export interface AccEnv extends Env, GoogleEnv {
  /** HMAC key of the player sessions (a secret; locally .dev.vars; tests: a vitest binding). Unset: accounts are off. */
  SESSION_KEY?: string;
}

// ---------- rows ----------

export interface AccountRow {
  id: string;
  created_at: number;
  last_seen: number | null;
  google_player_id: string | null;
  google_name: string | null;
  public_id: string | null;
  name: string | null;
  avatar: string | null;
  frame: string | null;
  plate: string | null;
  badge: string | null;
  coins: number;
  /** Economy v1 (migration 0005): premium currency and free re-rolls held. */
  gems: number;
  rerolls: number;
  xp: number;
  online_wins: number;
  stats: string | null;
  owned: string | null;
  equipped: string | null;
  rewards: string | null;
  achievements: string | null;
  banned: number;
  ban_reason: string | null;
  /** Why the account is banned: "admin_account" (the console's account ban) or "pid:<pid>" (that device's ban). */
  ban_source: string | null;
  note: string | null;
  merged_into: string | null;
  imported: number;
  /** Completed matches: online matches played to the end + granted offline claims (leaderboards need 3). */
  completed_matches: number;
  version: number;
  rev: string | null;
}

export const PID_RE = /^[A-Za-z0-9_-]{16,64}$/;
export const ACCOUNT_RE = /^acc_[a-z2-7]{16}$/;

function parseJson(s: unknown, fallback: unknown): unknown {
  if (typeof s !== "string") return fallback;
  try {
    return JSON.parse(s);
  } catch {
    return fallback;
  }
}

function obj(s: unknown): Record<string, unknown> {
  const v = parseJson(s, {});
  return v && typeof v === "object" && !Array.isArray(v) ? (v as Record<string, unknown>) : {};
}

/** The stored columns -> the game's profile shape (normalized as Save._ensure does). */
export function rowToProfile(r: AccountRow): Profile {
  const owned = obj(r.owned);
  const eq = obj(r.equipped);
  const rw = obj(r.rewards);
  const ach = obj(r.achievements);
  const raw: Record<string, unknown> = {
    name: r.name,
    id: r.public_id,
    coins: r.coins,
    gems: r.gems,
    rerolls: r.rerolls,
    xp: r.xp,
    stats: obj(r.stats),
    rooms: owned.rooms,
    room: eq.room,
    dice_owned: owned.dice_owned,
    dice: eq.dice,
    emote_sets: owned.emote_sets,
    emote_set: eq.emote_set,
    scenes: owned.scenes,
    scene: eq.scene,
    daily: rw.daily,
    last_spin: rw.last_spin,
    last_free: rw.last_free,
    avatar: r.avatar,
    av_owned: owned.av_owned,
    frame: r.frame,
    plate: r.plate,
    badge: r.badge,
    claimed: ach.claimed,
  };
  for (const k of Object.keys(raw)) if (raw[k] === undefined || raw[k] === null) delete raw[k];
  return normalizeProfile(raw);
}

/** The profile -> the accounts columns it is stored in. */
export function profileColumns(p: Profile): Record<string, string | number | null> {
  const owned: Record<string, unknown> = { rooms: p.rooms, dice_owned: p.dice_owned, av_owned: p.av_owned, emote_sets: p.emote_sets };
  if (p.scenes !== undefined) owned.scenes = p.scenes;
  const eq: Record<string, unknown> = { room: p.room, dice: p.dice, emote_set: p.emote_set };
  if (p.scene !== undefined) eq.scene = p.scene;
  return {
    public_id: typeof p.id === "string" ? p.id : String(p.id ?? ""),
    name: p.name,
    avatar: p.avatar,
    frame: p.frame,
    plate: p.plate,
    badge: p.badge,
    coins: Math.trunc(p.coins),
    gems: Math.trunc(p.gems ?? 0),
    rerolls: Math.trunc(p.rerolls ?? 0),
    xp: Math.trunc(p.xp),
    stats: JSON.stringify(p.stats),
    owned: JSON.stringify(owned),
    equipped: JSON.stringify(eq),
    rewards: JSON.stringify({ daily: p.daily, last_spin: p.last_spin, last_free: p.last_free }),
    achievements: JSON.stringify({ claimed: p.claimed }),
  };
}

/** What the game gets as `account`. */
export function accountOut(r: AccountRow): Record<string, unknown> {
  return {
    id: r.id,
    guest: r.google_player_id === null,
    google_name: r.google_name,
    created_at: r.created_at,
    imported: r.imported === 1,
    online_wins: r.online_wins,
    completed_matches: r.completed_matches ?? 0,
    version: r.version,
  };
}

/** The admin console's view of an account row (JSON columns parsed, level computed). */
export function adminAccountOut(r: AccountRow): Record<string, unknown> {
  const { rev: _rev, ...rest } = r;
  return {
    ...rest,
    stats: obj(r.stats),
    owned: obj(r.owned),
    equipped: obj(r.equipped),
    rewards: obj(r.rewards),
    achievements: obj(r.achievements),
    level: levelInfo(Math.max(0, r.xp)).level,
    linked: r.google_player_id !== null,
  };
}

/** The conflict summary of ONLINE_V2.md §1. */
export function summary(r: AccountRow): Record<string, unknown> {
  const st = obj(r.stats);
  const wins = (typeof st.wins === "number" ? Math.trunc(st.wins) : 0) + r.online_wins;
  return { name: r.name ?? "Player", avatar: r.avatar ?? DEFAULT_AVATAR, level: levelInfo(Math.max(0, r.xp)).level, coins: r.coins, wins, last_seen: r.last_seen };
}

export async function getAccount(db: D1Database, id: string): Promise<AccountRow | null> {
  return db.prepare("SELECT * FROM accounts WHERE id = ?").bind(id).first<AccountRow>();
}

const ID_ABC = "abcdefghijklmnopqrstuvwxyz234567";

export function newAccountId(): string {
  const r = new Uint8Array(16);
  crypto.getRandomValues(r);
  let s = "acc_";
  for (const v of r) s += ID_ABC[v & 31];
  return s;
}

function newRev(): string {
  const r = new Uint8Array(12);
  crypto.getRandomValues(r);
  return Array.from(r, (b) => b.toString(16).padStart(2, "0")).join("");
}

export function isUnique(e: unknown): boolean {
  return /UNIQUE constraint failed|PRIMARY KEY/i.test(String(e instanceof Error ? e.message : e));
}

// ---------- the write path ----------

export interface LedgerEntry {
  coins: number;
  xp: number;
  /** Gems of this change (Economy v1); missing = 0. */
  gems?: number;
  reason: string;
  ref?: string | null;
}

export interface Write {
  /** The new profile (omitted: unchanged; the version still moves, which serializes concurrent requests). */
  profile?: Profile;
  ledger?: LedgerEntry;
  /** Online wins to add (accounts.online_wins and the wins board). */
  wins?: number;
  /** Completed matches to add (accounts.completed_matches: online matches finished + granted claims). */
  matches?: number;
  /** XP of this change that counts for the weekly XP board (default: ledger.xp when positive). */
  xpWeek?: number;
  /** Other account columns to set (constant names only). */
  set?: Record<string, string | number | null>;
  /** Statements to run in the same batch, guarded so they apply only when this write did. */
  extra?: (g: Guard) => D1PreparedStatement[];
  /** No level-up gems for this write (the one-time import: XP from the device isn't earned here). */
  noLevelGems?: boolean;
}

export interface Step<T> {
  result: T;
  write?: Write;
}

/** Thrown when an account kept changing under a write (8 tries). */
export class Busy extends Error {}

/** A guarded INSERT: `INSERT INTO t (cols) SELECT ?... WHERE <guard>`. */
export function guardedInsert(db: D1Database, g: Guard, table: string, cols: string[], vals: unknown[]): D1PreparedStatement {
  return db
    .prepare(`INSERT INTO ${table} (${cols.join(", ")}) SELECT ${cols.map(() => "?").join(", ")} WHERE ${g.sql}`)
    .bind(...vals, ...g.params);
}

export function ledgerStmt(db: D1Database, g: Guard, accountId: string, l: LedgerEntry, balance: number, now: number, gemsAfter: number | null = null): D1PreparedStatement {
  return guardedInsert(
    db,
    g,
    "ledger",
    ["account_id", "at", "delta_coins", "delta_xp", "delta_gems", "reason", "ref", "balance_after", "gems_after"],
    [accountId, now, Math.trunc(l.coins), Math.trunc(l.xp), Math.trunc(l.gems ?? 0), l.reason, l.ref ?? null, balance, gemsAfter],
  );
}

/** Gems for reaching a new level (ECONOMY_V1.md §0): ECON_V1.level_gems per level gained. */
export function levelGems(xpBefore: number, xpAfter: number): { gems: number; level: number } {
  const a = levelInfo(Math.max(0, xpBefore)).level;
  const b = levelInfo(Math.max(0, xpAfter)).level;
  return { gems: b > a ? (b - a) * ECON_V1.level_gems : 0, level: b };
}

/**
 * Reads the account, lets `fn` compute the change, and writes it in one D1 batch:
 *   UPDATE accounts ... version = version + 1, rev = <new> WHERE id = ? AND version = <read>
 *   + the ledger row, the score rows and `extra`, each guarded by "the account now has rev <new>".
 * If another request wrote the account in between, the UPDATE changes nothing, the guarded rows are not inserted,
 * and the whole step runs again on a fresh read. So two parallel purchases can never spend the same coins.
 * Returns null for an unknown account. Errors from `extra` (e.g. a UNIQUE conflict) roll the batch back and propagate.
 */
export async function mutate<T>(
  env: { DB: D1Database },
  accountId: string,
  now: number,
  fn: (row: AccountRow, profile: Profile) => Step<T> | Promise<Step<T>>,
  tries = 8,
): Promise<T | null> {
  const db = env.DB;
  for (let attempt = 0; attempt < tries; attempt++) {
    const row = await getAccount(db, accountId);
    if (!row) return null;
    const step = await fn(row, rowToProfile(row));
    const w = step.write;
    if (!w) return step.result;
    // a write that raises the level adds the level-up gems (its own ledger row below)
    const lv = w.profile && !w.noLevelGems ? levelGems(row.xp, Math.trunc(w.profile.xp)) : { gems: 0, level: 0 };
    if (lv.gems > 0) w.profile = { ...w.profile!, gems: Math.trunc(w.profile!.gems ?? 0) + lv.gems };
    const rev = newRev();
    const g: Guard = { sql: "EXISTS (SELECT 1 FROM accounts WHERE id = ? AND rev = ?)", params: [accountId, rev] };
    const cols: Record<string, string | number | null> = { ...(w.profile ? profileColumns(w.profile) : {}), ...(w.set ?? {}) };
    const names = Object.keys(cols);
    const sets = names.map((k) => `${k} = ?`);
    const vals: unknown[] = names.map((k) => cols[k]);
    sets.push("online_wins = online_wins + ?", "completed_matches = completed_matches + ?", "version = version + 1", "rev = ?");
    vals.push(w.wins ?? 0, w.matches ?? 0, rev);
    const stmts: D1PreparedStatement[] = [
      db.prepare(`UPDATE accounts SET ${sets.join(", ")} WHERE id = ? AND version = ?`).bind(...vals, accountId, row.version),
    ];
    const coins = w.profile ? Math.trunc(w.profile.coins) : row.coins;
    const xp = w.profile ? Math.trunc(w.profile.xp) : row.xp;
    const gems = w.profile ? Math.trunc(w.profile.gems ?? 0) : row.gems;
    if (w.ledger && (w.ledger.coins !== 0 || w.ledger.xp !== 0 || (w.ledger.gems ?? 0) !== 0)) {
      stmts.push(ledgerStmt(db, g, accountId, w.ledger, coins, now, gems - lv.gems));
    }
    if (lv.gems > 0) stmts.push(ledgerStmt(db, g, accountId, { coins: 0, xp: 0, gems: lv.gems, reason: "level", ref: String(lv.level) }, coins, now, gems));
    const xpWeek = w.xpWeek ?? (w.ledger && w.ledger.xp > 0 ? w.ledger.xp : 0);
    stmts.push(...scoreStmts(db, g, accountId, { xp: xp !== row.xp ? xp : undefined, xpWeek, wins: w.wins }, now));
    if (w.extra) stmts.push(...w.extra(g));
    const res = await db.batch(stmts);
    if (res[0].meta.changes > 0) return lv.gems > 0 ? ((await withLevelGems(step.result, w.profile!)) as T) : step.result;
    await new Promise((r) => setTimeout(r, 2 + Math.random() * 10 * (attempt + 1)));
  }
  throw new Busy(`account ${accountId} busy`);
}

/**
 * A step's answer was built from its profile before mutate added the level-up gems: a JSON Response carrying that
 * profile gets the final gems (anything else is returned as it is).
 */
async function withLevelGems<T>(result: T, final: Profile): Promise<T> {
  if (!(result instanceof Response)) return result;
  if (!(result.headers.get("Content-Type") ?? "").includes("application/json")) return result;
  const body = (await result.clone().json().catch(() => null)) as Record<string, unknown> | null;
  const prof = body?.profile as Record<string, unknown> | undefined;
  if (!prof || typeof prof !== "object") return result;
  prof.gems = Math.trunc(final.gems ?? 0);
  return new Response(JSON.stringify(body), { status: result.status, headers: result.headers }) as T;
}

// ---------- sessions ----------

export const SESSION_TTL_S = 30 * 86400;
export const SESSION_REFRESH_S = 7 * 86400;
const TICKET_TTL_S = 10 * 60;

const enc = new TextEncoder();
const keyCache = new Map<string, Promise<CryptoKey>>();

function hmacKey(secret: string, purpose: string): Promise<CryptoKey> {
  const k = `${purpose}\u0000${secret}`;
  let p = keyCache.get(k);
  if (!p) {
    p = crypto.subtle
      .digest("SHA-256", enc.encode(`lz-${purpose}-v1:${secret}`))
      .then((raw) => crypto.subtle.importKey("raw", raw, { name: "HMAC", hash: "SHA-256" }, false, ["sign", "verify"]));
    keyCache.set(k, p);
  }
  return p;
}

function b64url(buf: ArrayBuffer | Uint8Array): string {
  const a = buf instanceof Uint8Array ? buf : new Uint8Array(buf);
  return btoa(String.fromCharCode(...a)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function unb64url(s: string): Uint8Array | null {
  try {
    const bin = atob(s.replace(/-/g, "+").replace(/_/g, "/"));
    return Uint8Array.from(bin, (c) => c.charCodeAt(0));
  } catch {
    return null;
  }
}

async function sign(secret: string, purpose: string, msg: string): Promise<string> {
  return b64url(await crypto.subtle.sign("HMAC", await hmacKey(secret, purpose), enc.encode(msg)));
}

async function verifySig(secret: string, purpose: string, msg: string, sig: string): Promise<boolean> {
  const raw = unb64url(sig);
  if (!raw) return false;
  return crypto.subtle.verify("HMAC", await hmacKey(secret, purpose), raw, enc.encode(msg));
}

/** `<account_id>.<exp>.<hmac>` (exp: unix seconds; HMAC-SHA256 over "<account_id>.<exp>"). */
export async function makeSession(env: { SESSION_KEY?: string }, accountId: string, nowMs = Date.now()): Promise<string> {
  if (!env.SESSION_KEY) throw new Error("SESSION_KEY is not set");
  const exp = Math.floor(nowMs / 1000) + SESSION_TTL_S;
  const msg = `${accountId}.${exp}`;
  return `${msg}.${await sign(env.SESSION_KEY, "session", msg)}`;
}

/** Signature and expiry only (no D1). */
export async function parseSession(env: { SESSION_KEY?: string }, token: unknown, nowMs = Date.now()): Promise<{ account_id: string; exp: number } | null> {
  if (!env.SESSION_KEY || typeof token !== "string" || token.length > 200) return null;
  const m = /^(acc_[a-z2-7]{16})\.(\d{1,12})\.([A-Za-z0-9_-]{20,100})$/.exec(token);
  if (!m) return null;
  const exp = Number(m[2]);
  if (exp * 1000 <= nowMs) return null;
  if (!(await verifySig(env.SESSION_KEY, "session", `${m[1]}.${m[2]}`, m[3]))) return null;
  return { account_id: m[1], exp };
}

export type SessionCheck =
  | { ok: true; row: AccountRow; exp: number }
  | { ok: false; error: "unauthorized" | "banned"; reason?: string };

/** A session that is signed, not expired, of an account that exists, is not merged away and is not banned. */
export async function checkSession(env: AccEnv, token: unknown, nowMs = Date.now()): Promise<SessionCheck> {
  const s = await parseSession(env, token, nowMs);
  if (!s) return { ok: false, error: "unauthorized" };
  const row = await getAccount(env.DB, s.account_id);
  if (!row || row.merged_into) return { ok: false, error: "unauthorized" };
  if (row.banned) return { ok: false, error: "banned", reason: row.ban_reason ?? "" };
  return { ok: true, row, exp: s.exp };
}

/**
 * For the Room's hello (`session` field) and the quick-match socket: the account of a valid session, or null
 * (bad signature, expired, unknown or merged account, banned account).
 */
export async function verifySession(env: AccEnv, token: string): Promise<{ account_id: string } | null> {
  try {
    const c = await checkSession(env, token);
    return c.ok ? { account_id: c.row.id } : null;
  } catch (e) {
    console.error("verifySession failed:", e);
    return null;
  }
}

/** The device's account (following a merge), for old clients that send only `pid`. banned: the account or the pid. */
export async function accountForPid(env: AccEnv, pid: string): Promise<{ account_id: string; banned: boolean } | null> {
  if (typeof pid !== "string" || !PID_RE.test(pid)) return null;
  const r = await env.DB.prepare(
    `SELECT a.id, a.banned, a.merged_into, COALESCE((SELECT banned FROM players WHERE pid = d.pid), 0) AS pid_banned
     FROM devices d JOIN accounts a ON a.id = d.account_id WHERE d.pid = ?`,
  )
    .bind(pid)
    .first<{ id: string; banned: number; merged_into: string | null; pid_banned: number }>();
  if (!r) return null;
  if (r.merged_into) {
    const t = await getAccount(env.DB, r.merged_into);
    if (!t) return null;
    return { account_id: t.id, banned: t.banned === 1 || r.pid_banned === 1 };
  }
  return { account_id: r.id, banned: r.banned === 1 || r.pid_banned === 1 };
}

/** What other players see (rooms, leaderboards). Unknown accounts get the defaults. */
export async function getPublicProfile(env: AccEnv, accountId: string): Promise<{ name: string; avatar: string; frame: string; level: number }> {
  const row = ACCOUNT_RE.test(accountId) ? await getAccount(env.DB, accountId) : null;
  if (!row) return { name: "Player", avatar: DEFAULT_AVATAR, frame: DEFAULT_FRAME, level: 1 };
  const p = rowToProfile(row);
  return { name: p.name, avatar: equipped("avatar", p), frame: equipped("frame", p), level: levelInfo(Math.max(0, p.xp)).level };
}

/**
 * Online match rewards at `over` (ONLINE_V2.md §2, Economy decision 2: econ ONLINE_REWARDS): win / finish / left
 * per account, once per account per match (match_grants), with a ledger row (reason "match", ref = match_id), the
 * leaderboards (XP; wins: online wins) and completed_matches (win / finish). Idempotent: calling it again for the same match grants nothing new. Unknown, merged and banned
 * accounts are skipped. Every account is tried; if any write failed it throws afterwards (safe to retry).
 */
export async function grantOnlineMatch(env: AccEnv, m: MatchGrant): Promise<void> {
  const table = ONLINE_REWARDS[m.game];
  if (!table || typeof m.match_id !== "string" || !m.match_id) throw new Error("grantOnlineMatch: bad match");
  const now = Date.now();
  const errors: unknown[] = [];
  const seen = new Set<string>();
  if (m.table && m.table.entry > 0) {
    // the Economy page's row for this coin-table match (once)
    const t = m.table;
    const { pot, pool, pay } = tablePayouts(t.entry, t.size, t.size);
    const paidHumans = m.results.reduce((n, r) => n + (r.place !== undefined && r.place >= 0 && r.entry_id ? (pay[r.place] ?? 0) : 0), 0);
    await env.DB.prepare(
      `INSERT OR IGNORE INTO table_matches (match_id, at, game, size, tier, entry, humans, ghosts, pot, fee, paid_humans, winner_ghost)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    )
      .bind(m.match_id, now, m.game, t.size, t.tier, t.entry, t.humans, t.ghosts, pot, pot - pool, paidHumans, t.winner_ghost ? 1 : 0)
      .run();
  }
  for (const r of m.results) {
    if (seen.has(r.account_id) || !ACCOUNT_RE.test(r.account_id) || !(r.outcome in table)) continue;
    seen.add(r.account_id);
    try {
      await grantOne(env, m, r, now);
    } catch (e) {
      console.error(`grantOnlineMatch ${m.match_id} ${r.account_id} failed:`, e);
      errors.push(e);
    }
  }
  if (errors.length) throw new AggregateError(errors, `grantOnlineMatch ${m.match_id}: ${errors.length} failed`);
}

/** The grant of one online match (Room -> accounts_shim -> grantOnlineMatch). */
export interface MatchGrant {
  match_id: string;
  game: "ludo" | "sl";
  results: MatchGrantResult[];
  /** Quick match: the coin table (entry 0 = practice). Missing: a friend room (ONLINE_REWARDS coins). */
  table?: { tier: string; entry: number; size: number; humans: number; ghosts: number; winner_ghost?: boolean };
}

export interface MatchGrantResult {
  account_id: string;
  outcome: "win" | "finish" | "left";
  /** Coin tables: the paid place (0 = 1st) among the seats that didn't leave; -1 = left (forfeit). */
  place?: number;
  /** Coin tables: this person's entry (ECONOMY_V1.md §3). */
  entry_id?: string;
}

/**
 * One account's grant: XP (and online stats) by outcome as before; coins: friend rooms ONLINE_REWARDS, practice
 * ECON_V1.practice, coin tables the payout of `place` (ledger `payout`) with the entry settled (or forfeit) in the
 * same batch. Once per match (match_grants).
 */
async function grantOne(env: AccEnv, m: MatchGrant, r: MatchGrantResult, now: number) {
  const db = env.DB;
  const matchId = m.match_id;
  const game = m.game;
  const accountId = r.account_id;
  const outcome = r.outcome;
  const done = await db.prepare("SELECT 1 AS x FROM match_grants WHERE match_id = ? AND account_id = ?").bind(matchId, accountId).first();
  if (done) return;
  const t = m.table;
  const paid = !!t && t.entry > 0;
  let coins: number = ONLINE_REWARDS[game][outcome].coins;
  if (t && !paid) coins = outcome === "left" ? 0 : (ECON_V1.practice[game]?.[outcome] ?? 0);
  if (paid) coins = r.place !== undefined && r.place >= 0 ? (tablePayouts(t.entry, t.size, t.size).pay[r.place] ?? 0) : 0;
  const xp = ONLINE_REWARDS[game][outcome].xp;
  try {
    await mutate(env, accountId, now, async (row, p) => {
      if (row.merged_into || row.banned) return { result: undefined };
      // a coin table pays only against an open entry (settled once, whatever retries do)
      const entry = paid && r.entry_id ? await entryOpen(db, r.entry_id) : null;
      const payout = paid ? (entry && entry.account_id === accountId ? coins : 0) : coins;
      const g0 = applyOnlineResult(p, game, outcome);
      const prof = structuredClone(g0.profile);
      // applyOnlineResult paid ONLINE_REWARDS coins: replace them with this match's coins
      prof.coins = Math.trunc(p.coins);
      prof.stats = structuredClone(p.stats);
      if (payout > 0) addCoins(prof, payout);
      return {
        result: undefined,
        write: {
          profile: prof,
          ledger: { coins: payout, xp, reason: paid ? "payout" : "match", ref: matchId },
          wins: outcome === "win" ? 1 : 0,
          matches: outcome === "left" ? 0 : 1,
          extra: (g) => [
            guardedInsert(db, g, "match_grants", ["match_id", "account_id", "at", "game", "outcome", "coins", "xp"], [matchId, accountId, now, game, outcome, payout, xp]),
            ...(entry ? [entrySettleStmt(db, g, entry.id, matchId, r.place ?? -1, payout, now)] : []),
          ],
        },
      };
    });
  } catch (e) {
    if (isUnique(e)) return; // granted by a concurrent call
    throw e;
  }
}

// ---------- HTTP helpers (shared by the /v1 endpoints) ----------

export const MAX_BODY = 32 * 1024;

export class BadRequest extends Error {}

export function json(body: unknown, status = 200, headers: Record<string, string> = {}): Response {
  return Response.json(body, { status, headers: { "Cache-Control": "no-store", ...headers } });
}

export async function readBody(req: Request): Promise<Record<string, unknown>> {
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

/** The server clock (epoch ms). Under TEST_MODE a request may set it with `X-Test-Now: <unix seconds>`. */
export function clock(req: Request, env: { TEST_MODE?: string }): number {
  if (env.TEST_MODE === "1") {
    const h = req.headers.get("X-Test-Now");
    if (h && /^\d{1,12}$/.test(h)) return Number(h) * 1000;
  }
  return Date.now();
}

export interface Authed {
  row: AccountRow;
  /** A fresh session when the current one has less than 7 days left (also sent as the X-Session header). */
  refresh: string | null;
  session: string;
}

function bearer(req: Request): string | null {
  const h = req.headers.get("Authorization");
  const m = h ? /^Bearer\s+(\S+)$/i.exec(h) : null;
  return m ? m[1] : null;
}

export function disabled(): Response {
  return json({ error: "accounts_disabled", msg: "Accounts are off: set the SESSION_KEY secret." }, 503);
}

/** The request's account (Authorization: Bearer <session>), or the error response (401 / 403 banned / 503). */
export async function authenticate(req: Request, env: AccEnv, now: number): Promise<Authed | Response> {
  if (!env.SESSION_KEY) return disabled();
  const token = bearer(req);
  const c = await checkSession(env, token, now);
  if (!c.ok) {
    return c.error === "banned" ? json({ error: "banned", msg: banMsg(c.reason) }, 403) : json({ error: "unauthorized" }, 401);
  }
  const refresh = c.exp - Math.floor(now / 1000) < SESSION_REFRESH_S ? await makeSession(env, c.row.id, now) : null;
  return { row: c.row, refresh, session: refresh ?? token! };
}

/** Optional auth (leaderboards): the account id of a valid session, else null. */
export async function optionalAccount(req: Request, env: AccEnv, now: number): Promise<string | null> {
  const t = bearer(req);
  if (!t || !env.SESSION_KEY) return null;
  const c = await checkSession(env, t, now);
  return c.ok ? c.row.id : null;
}

function banMsg(reason?: string | null): string {
  return reason ? `You are banned from online play: ${reason}` : "You are banned from online play.";
}

/** A JSON response for an authed request (adds X-Session when the session was refreshed). */
export function authedJson(a: Authed, body: unknown, status = 200): Response {
  return json(body, status, a.refresh ? { "X-Session": a.refresh } : {});
}

// ---------- POST /v1/auth/guest ----------

interface DeviceAccount {
  row: AccountRow;
}

async function deviceAccount(db: D1Database, pid: string): Promise<DeviceAccount | null> {
  const d = await db.prepare("SELECT account_id FROM devices WHERE pid = ?").bind(pid).first<{ account_id: string }>();
  if (!d) return null;
  let row = await getAccount(db, d.account_id);
  if (row?.merged_into) {
    const t = await getAccount(db, row.merged_into);
    if (t) {
      await db.prepare("UPDATE devices SET account_id = ? WHERE pid = ?").bind(t.id, pid).run();
      row = t;
    }
  }
  return row ? { row } : null;
}

/** Ledger rows and score rows of a brand-new account (unguarded: they go in the account's INSERT batch). */
function newAccountStmts(db: D1Database, id: string, p: Profile, now: number, importDelta: { coins: number; xp: number } | null): D1PreparedStatement[] {
  const base = newProfile();
  const always: Guard = { sql: "1", params: [] };
  const out = [ledgerStmt(db, always, id, { coins: base.coins, xp: 0, reason: "start" }, base.coins, now)];
  if (importDelta && (importDelta.coins !== 0 || importDelta.xp !== 0)) {
    out.push(ledgerStmt(db, always, id, { coins: importDelta.coins, xp: importDelta.xp, reason: "import" }, Math.trunc(p.coins), now));
  }
  if (p.xp > 0) out.push(...scoreStmts(db, null, id, { xp: Math.trunc(p.xp) }, now));
  return out;
}

function insertAccount(db: D1Database, id: string, p: Profile, now: number, extra: Record<string, string | number | null>): D1PreparedStatement {
  const cols: Record<string, string | number | null> = { id, created_at: now, last_seen: now, ...profileColumns(p), ...extra, version: 0, rev: newRev() };
  const names = Object.keys(cols);
  return db.prepare(`INSERT INTO accounts (${names.join(", ")}) VALUES (${names.map(() => "?").join(", ")})`).bind(...names.map((k) => cols[k]));
}

type ImportOut = { ok: true; notes: string[] } | { ok: false; error: "invalid" | "already" };

/**
 * Policy (lead, 2026-10-24): new guest accounts per client IP. Generous, because Bangladeshi mobile networks put many
 * players behind one carrier-grade NAT address. Opening an existing pid's account is never limited.
 */
export const GUEST_LIMITS = { per_hour: 20, per_day: 60 } as const;

/**
 * The key guest_creations stores for a request: an HMAC of CF-Connecting-IP (Cloudflare always sets it; a request
 * without it, i.e. local tools and tests, is not limited).
 */
async function ipKey(env: AccEnv, req: Request): Promise<string | null> {
  const ip = req.headers.get("CF-Connecting-IP")?.trim().toLowerCase();
  if (!ip || !env.SESSION_KEY) return null;
  return (await sign(env.SESSION_KEY, "ip", ipBucket(ip))).slice(0, 22);
}

/** IPv4 as is; IPv6 by its /64 (one subscriber's prefix: a device can pick any address in it). */
export function ipBucket(ip: string): string {
  if (!ip.includes(":")) return ip;
  const [head, tail] = ip.split("::", 2);
  const a = head ? head.split(":") : [];
  const b = tail !== undefined && tail !== "" ? tail.split(":") : [];
  const groups = tail === undefined ? a : [...a, ...Array(Math.max(0, 8 - a.length - b.length)).fill("0"), ...b];
  return `${groups
    .slice(0, 4)
    .map((g) => (g.replace(/^0+(?=.)/, "") || "0"))
    .join(":")}::/64`;
}

/** True when the IP may create another guest account now. */
async function guestAllowed(db: D1Database, key: string, now: number): Promise<boolean> {
  const r = await db
    .prepare("SELECT COUNT(*) AS day, COALESCE(SUM(at > ?), 0) AS hour FROM guest_creations WHERE ip = ? AND at > ?")
    .bind(now - 3600_000, key, now - 86400_000)
    .first<{ day: number; hour: number }>();
  return !r || (r.hour < GUEST_LIMITS.per_hour && r.day < GUEST_LIMITS.per_day);
}

/**
 * POST /v1/auth/guest {pid, import?} -> {account, session, profile, created, import?}. A banned pid (or its banned
 * account) gets 403 banned. `import` (the local pre-v2 profile) is applied once, while the account is untouched.
 * A new account past GUEST_LIMITS for the client IP -> 429 {error: "rate"} (an existing pid is never limited).
 */
export async function authGuest(req: Request, env: AccEnv, now: number): Promise<Response> {
  if (!env.SESSION_KEY) return disabled();
  const o = await readBody(req);
  const pid = o.pid;
  if (typeof pid !== "string" || !PID_RE.test(pid)) throw new BadRequest("pid: 16-64 characters of [A-Za-z0-9_-]");
  const db = env.DB;
  const ban = await D.readBan(db, pid);
  if (ban?.banned) return json({ error: "banned", msg: banMsg(ban.reason) }, 403);
  const nowS = Math.floor(now / 1000);
  const today = dayKey(nowS);

  for (let attempt = 0; attempt < 3; attempt++) {
    const found = await deviceAccount(db, pid);
    if (found) {
      let row = found.row;
      if (row.banned) return json({ error: "banned", msg: banMsg(row.ban_reason) }, 403);
      let imp: ImportOut | undefined;
      if (o.import !== undefined) {
        imp = await mutate(env, row.id, now, (r, p): Step<ImportOut> => {
          if (r.imported || r.version !== 0) return { result: { ok: false, error: "already" } };
          const res = importProfile(o.import, p, today, nowS);
          if (!res.ok) return { result: { ok: false, error: "invalid" } };
          return {
            result: { ok: true, notes: res.notes },
            write: {
              profile: res.profile,
              set: { imported: 1 },
              ledger: { coins: res.delta.coins, xp: res.delta.xp, reason: "import" },
              xpWeek: 0,
              noLevelGems: true,
            },
          };
        }) ?? undefined;
        row = (await getAccount(db, row.id)) ?? row;
      }
      await db.batch([
        db.prepare("UPDATE devices SET last_seen = ? WHERE pid = ?").bind(now, pid),
        db.prepare("UPDATE accounts SET last_seen = ? WHERE id = ?").bind(now, row.id),
      ]);
      const body: Record<string, unknown> = { account: accountOut(row), session: await makeSession(env, row.id, now), profile: rowToProfile(row), created: false };
      if (imp) body.import = imp;
      return json(body);
    }

    // a new guest account for this device
    const ip = await ipKey(env, req);
    if (ip && !(await guestAllowed(db, ip, now))) return json({ error: "rate" }, 429);
    const id = newAccountId();
    let p = newProfile();
    let imp: ImportOut | undefined;
    let importDelta: { coins: number; xp: number } | null = null;
    if (o.import !== undefined) {
      const res = importProfile(o.import, p, today, nowS);
      if (res.ok) {
        p = res.profile;
        importDelta = res.delta;
        imp = { ok: true, notes: res.notes };
      } else imp = { ok: false, error: "invalid" };
    }
    try {
      await db.batch([
        insertAccount(db, id, p, now, { imported: importDelta ? 1 : 0 }),
        db.prepare("INSERT INTO devices (pid, account_id, first_seen, last_seen) VALUES (?, ?, ?, ?)").bind(pid, id, now, now),
        ...newAccountStmts(db, id, p, now, importDelta),
        ...(ip ? [db.prepare("INSERT INTO guest_creations (ip, at) VALUES (?, ?)").bind(ip, now)] : []),
      ]);
    } catch (e) {
      if (isUnique(e)) continue; // a parallel request created this device's account first
      throw e;
    }
    const row = (await getAccount(db, id))!;
    const body: Record<string, unknown> = { account: accountOut(row), session: await makeSession(env, id, now), profile: rowToProfile(row), created: true };
    if (imp) body.import = imp;
    return json(body);
  }
  return json({ error: "busy" }, 503);
}

// ---------- GET / PATCH /v1/me ----------

export async function getMe(a: Authed): Promise<Response> {
  return authedJson(a, { account: accountOut(a.row), profile: rowToProfile(a.row), session: a.session });
}

const ME_KINDS = ["avatar", "frame", "plate", "badge"] as const;

/** PATCH /v1/me {name?, avatar?, frame?, plate?, badge?}: owned / unlocked items only (badge "" = none). */
export async function patchMe(req: Request, env: AccEnv, a: Authed, now: number): Promise<Response> {
  const o = await readBody(req);
  for (const k of Object.keys(o)) if (k !== "name" && !(ME_KINDS as readonly string[]).includes(k)) throw new BadRequest(`unknown field ${k.slice(0, 40)}`);
  let name: string | undefined;
  if (o.name !== undefined) {
    if (typeof o.name !== "string") throw new BadRequest("name: string");
    if (reservedName(o.name)) return authedJson(a, { error: "reserved", field: "name" }, 409);
    name = cleanName(o.name.replace(/[\u0000-\u001f\u007f]/g, " "));
    if (!name) throw new BadRequest("name: 1-16 characters");
  }
  for (const k of ME_KINDS) if (o[k] !== undefined && (typeof o[k] !== "string" || (o[k] as string).length > 32)) throw new BadRequest(`${k}: an item id`);
  const r = await mutate(env, a.row.id, now, (_row, p): Step<Response> => {
    let q = p;
    for (const k of ME_KINDS) {
      if (o[k] === undefined) continue;
      const e = equip(q, k, o[k] as string);
      if (!e.ok) return { result: authedJson(a, { error: e.error, field: k }, e.error === "unknown" ? 404 : 409) };
      q = e.profile;
    }
    if (name !== undefined && name !== q.name) q = { ...structuredClone(q), name };
    if (q === p) return { result: authedJson(a, { ok: true, profile: p }) };
    return { result: authedJson(a, { ok: true, profile: q }), write: { profile: q } };
  });
  return r ?? json({ error: "unauthorized" }, 401);
}

// ---------- Google Play Games: POST /v1/auth/google, /v1/auth/google/resolve ----------

/** A short-lived signed proof that this account's session presented this Google player (for /resolve). */
async function makeTicket(env: AccEnv, accountId: string, g: GooglePlayer, nowMs: number): Promise<string> {
  const exp = Math.floor(nowMs / 1000) + TICKET_TTL_S;
  const msg = `${accountId}.${b64url(enc.encode(g.id))}.${b64url(enc.encode(g.name))}.${exp}`;
  return `${msg}.${await sign(env.SESSION_KEY!, "glink", msg)}`;
}

async function readTicket(env: AccEnv, accountId: string, t: unknown, nowMs: number): Promise<GooglePlayer | null> {
  if (typeof t !== "string" || t.length > 600) return null;
  const parts = t.split(".");
  if (parts.length !== 5) return null;
  const [acc, gid, gname, exp, sig] = parts;
  if (acc !== accountId || !/^\d{1,12}$/.test(exp) || Number(exp) * 1000 <= nowMs) return null;
  if (!(await verifySig(env.SESSION_KEY!, "glink", parts.slice(0, 4).join("."), sig))) return null;
  const dec = (s: string) => {
    const b = unb64url(s);
    return b ? new TextDecoder().decode(b) : null;
  };
  const id = dec(gid);
  const name = dec(gname);
  return id ? { id, name: name ?? "" } : null;
}

async function accountByGoogle(db: D1Database, gid: string): Promise<AccountRow | null> {
  return db.prepare("SELECT * FROM accounts WHERE google_player_id = ?").bind(gid).first<AccountRow>();
}

/** Points the device at `accountId` when it currently belongs to `fromId` (pid optional in the Google calls). */
function repointStmt(db: D1Database, pid: unknown, fromId: string, toId: string, now: number): D1PreparedStatement | null {
  if (typeof pid !== "string" || !PID_RE.test(pid)) return null;
  return db.prepare("UPDATE devices SET account_id = ?, last_seen = ? WHERE pid = ? AND account_id = ?").bind(toId, now, pid, fromId);
}

async function sessionBody(env: AccEnv, row: AccountRow, now: number, extra: Record<string, unknown>): Promise<Record<string, unknown>> {
  return { account: accountOut(row), session: await makeSession(env, row.id, now), profile: rowToProfile(row), ...extra };
}

async function googlePlayer(env: AccEnv, o: Record<string, unknown>): Promise<GooglePlayer | Response> {
  const code = o.server_auth_code;
  if (typeof code !== "string" || code.length < 1 || code.length > 2048) throw new BadRequest("server_auth_code: string");
  const g = await playerFromAuthCode(env, code);
  if (!g.ok) {
    console.error("google:", g.detail);
    return json({ error: g.error }, g.error === "google_rejected" ? 401 : 502);
  }
  return g.player;
}

function googleOff(): Response {
  return json({ error: "google_not_configured" }, 503);
}

/** Links Google player `g` to the session's account, or reports the conflict. */
async function link(env: AccEnv, a: Authed, g: GooglePlayer, pid: unknown, now: number): Promise<Response> {
  const db = env.DB;
  const here = a.row;
  for (let attempt = 0; attempt < 3; attempt++) {
    const there = await accountByGoogle(db, g.id);
    if (there && there.banned) return json({ error: "banned", msg: banMsg(there.ban_reason) }, 403);
    if (there && there.id === here.id) {
      await db.prepare("UPDATE accounts SET google_name = ?, last_seen = ? WHERE id = ?").bind(g.name, now, here.id).run();
      return json(await sessionBody(env, (await getAccount(db, here.id))!, now, { linked: true }));
    }
    if (here.google_player_id !== null) {
      // this account belongs to another Google player: never switch silently, ask (resolve "switch" | "stay")
      return json(
        {
          error: "other_google",
          conflict: { here: summary(here), there: there ? summary(there) : null },
          ticket: await makeTicket(env, here.id, g, now),
        },
        409,
      );
    }
    if (!there) {
      try {
        const r = await db
          .prepare("UPDATE accounts SET google_player_id = ?, google_name = ?, last_seen = ?, version = version + 1 WHERE id = ? AND google_player_id IS NULL")
          .bind(g.id, g.name, now, here.id)
          .run();
        if (r.meta.changes === 0) return json({ error: "conflict_retry" }, 409);
      } catch (e) {
        if (isUnique(e)) continue; // linked to another account a moment ago: report the conflict
        throw e;
      }
      return json(await sessionBody(env, (await getAccount(db, here.id))!, now, { linked: true }));
    }
    return json(
      { error: "conflict", conflict: { here: summary(here), there: summary(there) }, ticket: await makeTicket(env, here.id, g, now) },
      409,
    );
  }
  return json({ error: "busy" }, 503);
}

/**
 * The device leaves account `here` for Google player g's account `there` (created, linked to g, when g is new):
 * {account, session, profile, switched: true, created}. The account left behind is not changed.
 */
async function switchTo(env: AccEnv, here: AccountRow, g: GooglePlayer, there: AccountRow | null, pid: unknown, now: number): Promise<Response> {
  const db = env.DB;
  let target = there;
  let created = false;
  if (!target) {
    const id = newAccountId();
    const p = newProfile();
    try {
      await db.batch([insertAccount(db, id, p, now, { google_player_id: g.id, google_name: g.name }), ...newAccountStmts(db, id, p, now, null)]);
      created = true;
      target = await getAccount(db, id);
    } catch (e) {
      if (!isUnique(e)) throw e;
      target = await accountByGoogle(db, g.id); // created by a parallel request a moment ago
    }
    if (!target) return json({ error: "conflict_retry" }, 409);
  } else {
    await db.prepare("UPDATE accounts SET last_seen = ? WHERE id = ?").bind(now, target.id).run();
  }
  if (target.banned) return json({ error: "banned", msg: banMsg(target.ban_reason) }, 403);
  const s = repointStmt(db, pid, here.id, target.id, now);
  if (s) await s.run();
  return json(await sessionBody(env, (await getAccount(db, target.id)) ?? target, now, { switched: true, created }));
}

/** POST /v1/auth/google {server_auth_code, pid?} (Bearer guest session). */
export async function authGoogle(req: Request, env: AccEnv, now: number): Promise<Response> {
  if (!googleConfigured(env)) return googleOff();
  const a = await authenticate(req, env, now);
  if (a instanceof Response) return a;
  const o = await readBody(req);
  const g = await googlePlayer(env, o);
  if (g instanceof Response) return g;
  return link(env, a, g, o.pid, now);
}

/**
 * POST /v1/auth/google/resolve {keep, ticket | server_auth_code, pid?}. `ticket` comes with the 409 (valid 10 min; a
 * server auth code can only be exchanged once, so prefer it).
 * After 409 "conflict" (this account is a guest, the Google player has another account):
 *   there (or switch): the device switches to the Google player's account (this guest account is left as is).
 *   here:  the Google id moves to this account; the other account is retired (merged_into = this one) and its
 *          devices now open this account.
 * After 409 "other_google" (this account is linked to another Google player):
 *   switch (or there): the device switches to the new Google player's account, created when it is new.
 *   stay:  nothing changes (the device keeps this account). "here" -> 409 already_linked.
 * `stay` is accepted after either 409 and changes nothing: {account, session, profile, stayed: true}.
 */
export async function authGoogleResolve(req: Request, env: AccEnv, now: number): Promise<Response> {
  if (!googleConfigured(env)) return googleOff();
  const a = await authenticate(req, env, now);
  if (a instanceof Response) return a;
  const o = await readBody(req);
  const keep = o.keep;
  if (keep !== "here" && keep !== "there" && keep !== "switch" && keep !== "stay") throw new BadRequest("keep: here | there | switch | stay");
  let g: GooglePlayer | null = null;
  if (o.ticket !== undefined) {
    g = await readTicket(env, a.row.id, o.ticket, now);
    if (!g) return json({ error: "bad_ticket" }, 400);
  } else {
    const r = await googlePlayer(env, o);
    if (r instanceof Response) return r;
    g = r;
  }
  const db = env.DB;
  const here = a.row;
  if (keep === "stay") {
    await db.prepare("UPDATE accounts SET last_seen = ? WHERE id = ?").bind(now, here.id).run();
    return json(await sessionBody(env, here, now, { stayed: true }));
  }
  const there = await accountByGoogle(db, g.id);
  if (there && there.id === here.id) return link(env, a, g, o.pid, now); // nothing to resolve any more
  if (there?.banned) return json({ error: "banned", msg: banMsg(there.ban_reason) }, 403);
  if (here.google_player_id !== null) {
    if (keep === "here") return json({ error: "already_linked" }, 409);
    return switchTo(env, here, g, there, o.pid, now);
  }
  if (!there) return link(env, a, g, o.pid, now); // the Google player has no account (any more): link it here
  if (keep === "there" || keep === "switch") return switchTo(env, here, g, there, o.pid, now);
  const tok = newRev();
  const res = await db.batch([
    db
      .prepare(
        `UPDATE accounts SET google_player_id = NULL, merged_into = ?, version = version + 1, rev = ?
         WHERE id = ? AND google_player_id = ? AND EXISTS (SELECT 1 FROM accounts WHERE id = ? AND google_player_id IS NULL AND merged_into IS NULL)`,
      )
      .bind(here.id, tok, there.id, g.id, here.id),
    db
      .prepare(
        `UPDATE accounts SET google_player_id = ?, google_name = ?, last_seen = ?, version = version + 1
         WHERE id = ? AND google_player_id IS NULL AND EXISTS (SELECT 1 FROM accounts WHERE id = ? AND rev = ?)`,
      )
      .bind(g.id, g.name, now, here.id, there.id, tok),
    db.prepare("UPDATE devices SET account_id = ? WHERE account_id = ? AND EXISTS (SELECT 1 FROM accounts WHERE id = ? AND rev = ?)").bind(here.id, there.id, there.id, tok),
  ]);
  if (res[0].meta.changes === 0 || res[1].meta.changes === 0) return json({ error: "conflict_retry" }, 409);
  return json(await sessionBody(env, (await getAccount(db, here.id))!, now, { linked: true, merged: there.id }));
}
