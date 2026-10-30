// D1 (binding DB, database "ludo-zing-admin"): the SQL of the friend rooms, the admin console and quick-match stats.
// The accounts / economy / leaderboard SQL (ONLINE_V2.md) lives next to its logic in accounts.ts, wallet.ts and
// leaderboard.ts. Schema: migrations/0001_init.sql, 0002_accounts.sql, 0003_policy.sql. Contract: ADMIN_API.md. Times are epoch ms.

import { dayKey, dayStart } from "./econ";

// ---------- row shapes ----------

export interface PlayerRow {
  pid: string;
  name: string | null;
  avatar: string | null;
  frame: string | null;
  first_seen: number | null;
  last_seen: number | null;
  rooms: number;
  matches: number;
  wins: number;
  banned: number;
  ban_reason: string | null;
  /** v2: "admin_pid" | "account:<id>" (why the pid is banned). */
  ban_source?: string | null;
  note: string | null;
  last_room: string | null;
}

export type RoomStatus = "lobby" | "playing" | "over" | "closed";

/**
 * The admin console's room status filter: a RoomStatus, or "paused" = a match in progress (status playing) with
 * nobody connected (online = 0). The Room pauses its bots then; "playing" in a filter means online > 0.
 */
export type RoomFilter = RoomStatus | "paused";

/** SQL for one RoomFilter (constant strings; the status value is bound). */
function roomFilterSql(f: RoomFilter): { sql: string; params: unknown[] } {
  if (f === "paused") return { sql: "status = 'playing' AND online = 0", params: [] };
  if (f === "playing") return { sql: "status = 'playing' AND online > 0", params: [] };
  return { sql: "status = ?", params: [f] };
}

/** A paused room: a match in progress with nobody connected (bots wait; cleanup deletes it after 10 min empty). */
export function isPaused(r: { status: string; online: number }): boolean {
  return r.status === "playing" && !(Number(r.online) > 0);
}

export interface RoomRow {
  /** v2 (0002): game "ludo" | "sl", public / quick flags. */
  game?: string | null;
  public?: number | null;
  quick?: number | null;
  code: string;
  created_at: number;
  updated_at: number;
  host_pid: string | null;
  host_name: string | null;
  status: RoomStatus;
  members: number;
  online: number;
  settings: string; // json {teams, pair_ask}
  closed_reason: string | null;
}

export type MatchResult = "playing" | "over" | "abandoned" | "closed";

export interface MatchPlayer {
  pid: string;
  name: string;
  color: number;
  bot: boolean;
}

export interface MatchRow {
  id: number;
  code: string;
  started_at: number;
  ended_at: number | null;
  players: string; // json MatchPlayer[]
  teams: number;
  pair_ask: number;
  winner: number | null;
  finished: string | null; // json colours
  actions: number | null;
  result: MatchResult;
  /** v2 (0002): "ludo" | "sl", quick match flag, ghost seats, a human won (null: unknown / not a quick match). */
  game?: string | null;
  quick?: number | null;
  ghosts?: number | null;
  human_won?: number | null;
}

export type EventLevel = "info" | "warn" | "error";

export interface EventRow {
  id: number;
  at: number;
  level: EventLevel;
  kind: string;
  code: string | null;
  pid: string | null;
  msg: string | null;
}

export interface AuditRow {
  id: number;
  at: number;
  ip: string | null;
  action: string;
  target: string | null;
  detail: string | null;
}

// ---------- config ----------

export interface GameConfig {
  maintenance: boolean;
  motd: string;
  turn_roll_s: number;
  turn_choose_s: number;
  turn_pair_s: number;
}

export const CONFIG_DEFAULTS: GameConfig = {
  maintenance: false,
  motd: "",
  turn_roll_s: 15,
  turn_choose_s: 20,
  turn_pair_s: 10,
};

export const TURN_KEYS = ["turn_roll_s", "turn_choose_s", "turn_pair_s"] as const;
export const TURN_MIN = 5;
export const TURN_MAX = 120;
export const MOTD_MAX = 140;

function turnValue(raw: string | undefined, def: number): number {
  if (raw === undefined || !/^\d{1,3}$/.test(raw)) return def;
  const v = Number(raw);
  return v >= TURN_MIN && v <= TURN_MAX ? v : def;
}

/** The config table's key/value rows -> typed config (bad or missing values fall back to the defaults). */
export function parseConfig(rows: Record<string, string>): GameConfig {
  return {
    maintenance: rows.maintenance === "1",
    motd: typeof rows.motd === "string" ? rows.motd : "",
    turn_roll_s: turnValue(rows.turn_roll_s, CONFIG_DEFAULTS.turn_roll_s),
    turn_choose_s: turnValue(rows.turn_choose_s, CONFIG_DEFAULTS.turn_choose_s),
    turn_pair_s: turnValue(rows.turn_pair_s, CONFIG_DEFAULTS.turn_pair_s),
  };
}

export async function readConfig(db: D1Database): Promise<GameConfig> {
  const { results } = await db.prepare("SELECT key, value FROM config").all<{ key: string; value: string }>();
  const rows: Record<string, string> = {};
  for (const r of results) rows[r.key] = r.value;
  return parseConfig(rows);
}

// Per-isolate cache (POST /v1/rooms maintenance check, GET /v1/config). An admin PUT clears this isolate's copy;
// other isolates pick the change up within maxAge.
let configCache: { at: number; v: GameConfig } | null = null;

export async function cachedConfig(db: D1Database, maxAgeMs: number): Promise<GameConfig> {
  const now = Date.now();
  if (configCache && now - configCache.at < maxAgeMs) return configCache.v;
  const v = await readConfig(db);
  configCache = { at: now, v };
  return v;
}

export function forgetConfig(): void {
  configCache = null;
}

/** Writes the given (already validated) config fields. */
export async function writeConfig(db: D1Database, patch: Partial<GameConfig>): Promise<void> {
  const stmts: D1PreparedStatement[] = [];
  const put = (k: string, v: string) =>
    stmts.push(db.prepare("INSERT INTO config (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value").bind(k, v));
  if (patch.maintenance !== undefined) put("maintenance", patch.maintenance ? "1" : "0");
  if (patch.motd !== undefined) put("motd", patch.motd);
  for (const k of TURN_KEYS) if (patch[k] !== undefined) put(k, String(patch[k]));
  if (stmts.length) await db.batch(stmts);
}

// ---------- what the Room DO writes ----------

export interface RoomState {
  code: string;
  created_at: number;
  host_pid: string | null;
  host_name: string | null;
  status: RoomStatus;
  members: number;
  online: number;
  settings: { teams: boolean; pair_ask: boolean };
  closed_reason: string | null;
  /** v2 (optional; omitted = a Ludo friend room): "ludo" | "sl", listed publicly, a quick-match room. */
  game?: "ludo" | "sl";
  public?: boolean;
  quick?: boolean;
}

/**
 * Inserts or updates the room's row (every write carries the whole row, so a lost write is repaired by the next).
 * `fresh` (room init) also resets created_at: a code can be reused after its room was deleted.
 */
export function upsertRoom(db: D1Database, r: RoomState, now: number, fresh = false): D1PreparedStatement {
  return db
    .prepare(
      `INSERT INTO rooms (code, created_at, updated_at, host_pid, host_name, status, members, online, settings, closed_reason,
                          game, public, quick)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13)
       ON CONFLICT(code) DO UPDATE SET
         ${fresh ? "created_at = excluded.created_at," : ""}
         updated_at = excluded.updated_at, host_pid = excluded.host_pid, host_name = excluded.host_name,
         status = excluded.status, members = excluded.members, online = excluded.online,
         settings = excluded.settings, closed_reason = excluded.closed_reason,
         game = excluded.game, public = excluded.public, quick = excluded.quick`,
    )
    .bind(
      r.code,
      r.created_at,
      now,
      r.host_pid,
      r.host_name,
      r.status,
      r.members,
      r.online,
      JSON.stringify(r.settings),
      r.closed_reason,
      r.game ?? "ludo",
      r.public ? 1 : 0,
      r.quick ? 1 : 0,
    );
}

export function utcDay(ms: number): string {
  return new Date(ms).toISOString().slice(0, 10);
}

/** A member joined (firstJoin) or came back: players upsert + today's activity row. */
export function playerSeen(
  db: D1Database,
  p: { pid: string; name: string; avatar: string; frame: string; room: string },
  now: number,
  firstJoin: boolean,
): D1PreparedStatement[] {
  return [
    db
      .prepare(
        `INSERT INTO players (pid, name, avatar, frame, first_seen, last_seen, rooms, last_room)
         VALUES (?1, ?2, ?3, ?4, ?5, ?5, ?6, ?7)
         ON CONFLICT(pid) DO UPDATE SET name = excluded.name, avatar = excluded.avatar, frame = excluded.frame,
           last_seen = excluded.last_seen, rooms = players.rooms + excluded.rooms, last_room = excluded.last_room`,
      )
      .bind(p.pid, p.name, p.avatar, p.frame, now, firstJoin ? 1 : 0, p.room),
    db.prepare("INSERT OR IGNORE INTO player_days (day, pid) VALUES (?, ?)").bind(utcDay(now), p.pid),
  ];
}

/**
 * The ban flag for one pid: the pid's own ban (players) or the ban of the account the device belongs to (v2, devices
 * -> accounts). Null when the pid has never been seen (no players row, no device).
 */
export async function readBan(db: D1Database, pid: string): Promise<{ banned: boolean; reason: string } | null> {
  const row = await db
    .prepare(
      `SELECT p.pid AS p, p.banned AS pb, p.ban_reason AS pr, d.pid AS d, a.banned AS ab, a.ban_reason AS ar
       FROM (SELECT ? AS pid) x
       LEFT JOIN players p ON p.pid = x.pid
       LEFT JOIN devices d ON d.pid = x.pid
       LEFT JOIN accounts a ON a.id = d.account_id`,
    )
    .bind(pid)
    .first<{ p: string | null; pb: number | null; pr: string | null; d: string | null; ab: number | null; ar: string | null }>();
  if (!row || (row.p === null && row.d === null)) return null;
  if (row.pb === 1) return { banned: true, reason: row.pr ?? "" };
  if (row.ab === 1) return { banned: true, reason: row.ar ?? "" };
  return { banned: false, reason: "" };
}

/**
 * A match started. v2 fields are optional (omitted: a Ludo friend-room match): `game`, `quick`, `ghosts` (the number
 * of ghost seats). `players` may carry extra per-seat fields (e.g. account_id, ghost: the console sees them).
 */
export function insertMatch(
  db: D1Database,
  m: {
    code: string;
    started_at: number;
    players: MatchPlayer[];
    teams: boolean;
    pair_ask: boolean;
    game?: "ludo" | "sl";
    quick?: boolean;
    ghosts?: number;
  },
): D1PreparedStatement {
  return db
    .prepare(
      `INSERT INTO matches (code, started_at, players, teams, pair_ask, actions, result, game, quick, ghosts)
       VALUES (?, ?, ?, ?, ?, 0, 'playing', ?, ?, ?)`,
    )
    .bind(
      m.code,
      m.started_at,
      JSON.stringify(m.players),
      m.teams ? 1 : 0,
      m.pair_ask ? 1 : 0,
      m.game ?? "ludo",
      m.quick ? 1 : 0,
      Math.max(0, Math.trunc(m.ghosts ?? 0)),
    );
}

/** Ends the match identified by (code, started_at). Only a match still `playing` changes. */
/** Ends the match identified by (code, started_at). Only a match still `playing` changes. `human_won` (v2, optional):
 * whether a human (not a ghost) won; omitted keeps the column as it is. */
export function endMatch(
  db: D1Database,
  m: {
    code: string;
    started_at: number;
    ended_at: number;
    winner: number | null;
    finished: number[];
    actions: number;
    result: MatchResult;
    human_won?: boolean | null;
  },
): D1PreparedStatement {
  const hw = m.human_won === undefined || m.human_won === null ? null : m.human_won ? 1 : 0;
  return db
    .prepare(
      `UPDATE matches SET ended_at = ?, winner = ?, finished = ?, actions = ?, result = ?, human_won = COALESCE(?, human_won)
       WHERE code = ? AND started_at = ? AND result = 'playing'`,
    )
    .bind(m.ended_at, m.winner, JSON.stringify(m.finished), m.actions, m.result, hw, m.code, m.started_at);
}

// ---------- quick match stats (quick_stats, 0002) ----------

/**
 * One quick-match stats increment for (day, game, size); missing counters add 0. day: UTC "YYYY-MM-DD" (default:
 * today). queued: humans who joined the queue; matched: humans placed in a match; ghost_filled: ghost seats created;
 * wait_ms (or wait_ms_total): the matched humans' waits, summed; human_wins / ghost_wins: finished quick matches with
 * ghosts won by a human / by a ghost.
 */
export interface QuickStatInc {
  day?: string;
  game: string;
  size: number;
  queued?: number;
  matched?: number;
  ghost_filled?: number;
  wait_ms?: number;
  wait_ms_total?: number;
  human_wins?: number;
  ghost_wins?: number;
}

function inc(v: unknown): number {
  return typeof v === "number" && Number.isFinite(v) && v > 0 ? Math.trunc(v) : 0;
}

export function quickStatStmt(db: D1Database, s: QuickStatInc, now = Date.now()): D1PreparedStatement {
  const game = s.game === "sl" ? "sl" : "ludo";
  const size = Math.trunc(Number(s.size)) || 0;
  const day = typeof s.day === "string" && /^\d{4}-\d{2}-\d{2}$/.test(s.day) ? s.day : utcDay(now);
  return db
    .prepare(
      `INSERT INTO quick_stats (day, game, size, queued, matched, ghost_filled, wait_ms_total, human_wins, ghost_wins)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT (day, game, size) DO UPDATE SET
         queued = queued + excluded.queued, matched = matched + excluded.matched,
         ghost_filled = ghost_filled + excluded.ghost_filled, wait_ms_total = wait_ms_total + excluded.wait_ms_total,
         human_wins = human_wins + excluded.human_wins, ghost_wins = ghost_wins + excluded.ghost_wins`,
    )
    .bind(day, game, size, inc(s.queued), inc(s.matched), inc(s.ghost_filled), inc(s.wait_ms ?? s.wait_ms_total), inc(s.human_wins), inc(s.ghost_wins));
}

/** quickStatStmt, run (the Matchmaker / Room call this fire-and-forget). */
export async function recordQuickStat(env: { DB: D1Database }, s: QuickStatInc): Promise<void> {
  await quickStatStmt(env.DB, s).run();
}

export interface QuickDay {
  day: string;
  game: string;
  size: number;
  queued: number;
  matched: number;
  ghost_filled: number;
  /** ghost_filled / (matched + ghost_filled): the share of seats that were ghosts (null without seats). */
  ghost_fill_rate: number | null;
  /** wait_ms_total / matched (null when nobody was matched). */
  avg_wait_ms: number | null;
  human_wins: number;
  ghost_wins: number;
  /** human_wins / (human_wins + ghost_wins) (null without finished ghost matches). */
  human_win_rate: number | null;
}

/** The admin quick-match report: the last `days` UTC days (today included), newest first, per game and size. */
export async function quickReport(db: D1Database, days: number, now: number): Promise<{ days: number; from: string; rows: QuickDay[]; totals: QuickDay[] }> {
  const from = utcDay(now - (days - 1) * DAY);
  const { results } = await db
    .prepare("SELECT * FROM quick_stats WHERE day >= ? ORDER BY day DESC, game, size")
    .bind(from)
    .all<{ day: string; game: string; size: number; queued: number; matched: number; ghost_filled: number; wait_ms_total: number; human_wins: number; ghost_wins: number }>();
  const shape = (r: { day: string; game: string; size: number; queued: number; matched: number; ghost_filled: number; wait_ms_total: number; human_wins: number; ghost_wins: number }): QuickDay => {
    const seats = r.matched + r.ghost_filled;
    const fin = r.human_wins + r.ghost_wins;
    return {
      day: r.day,
      game: r.game,
      size: r.size,
      queued: r.queued,
      matched: r.matched,
      ghost_filled: r.ghost_filled,
      ghost_fill_rate: seats > 0 ? r.ghost_filled / seats : null,
      avg_wait_ms: r.matched > 0 ? Math.round(r.wait_ms_total / r.matched) : null,
      human_wins: r.human_wins,
      ghost_wins: r.ghost_wins,
      human_win_rate: fin > 0 ? r.human_wins / fin : null,
    };
  };
  const tot = new Map<string, { day: string; game: string; size: number; queued: number; matched: number; ghost_filled: number; wait_ms_total: number; human_wins: number; ghost_wins: number }>();
  for (const r of results) {
    const k = `${r.game}:${r.size}`;
    const t = tot.get(k) ?? { day: "total", game: r.game, size: r.size, queued: 0, matched: 0, ghost_filled: 0, wait_ms_total: 0, human_wins: 0, ghost_wins: 0 };
    t.queued += r.queued;
    t.matched += r.matched;
    t.ghost_filled += r.ghost_filled;
    t.wait_ms_total += r.wait_ms_total;
    t.human_wins += r.human_wins;
    t.ghost_wins += r.ghost_wins;
    tot.set(k, t);
  }
  return { days, from, rows: results.map(shape), totals: [...tot.values()].map(shape) };
}

/** Over: one more match for a human seat, plus a win for the winners. */
export function playerResult(db: D1Database, pid: string, won: boolean, now: number): D1PreparedStatement {
  return db
    .prepare("UPDATE players SET matches = matches + 1, wins = wins + ?, last_seen = MAX(COALESCE(last_seen, 0), ?) WHERE pid = ?")
    .bind(won ? 1 : 0, now, pid);
}

export function addEvent(
  db: D1Database,
  e: { level: EventLevel; kind: string; code?: string | null; pid?: string | null; msg?: string | null },
  now = Date.now(),
): D1PreparedStatement {
  return db
    .prepare("INSERT INTO events (at, level, kind, code, pid, msg) VALUES (?, ?, ?, ?, ?, ?)")
    .bind(now, e.level, e.kind.slice(0, 40), e.code ?? null, e.pid ?? null, e.msg ? e.msg.slice(0, 1000) : null);
}

// ---------- admin: auth helpers ----------

export async function loginFailures(db: D1Database, ip: string, since: number): Promise<number> {
  const row = await db.prepare("SELECT COUNT(*) AS n FROM login_attempts WHERE ip = ? AND at > ?").bind(ip, since).first<{ n: number }>();
  return row?.n ?? 0;
}

export function addLoginFailure(db: D1Database, ip: string, now: number): D1PreparedStatement {
  return db.prepare("INSERT INTO login_attempts (ip, at) VALUES (?, ?)").bind(ip, now);
}

export function addAudit(
  db: D1Database,
  a: { ip: string; action: string; target?: string | null; detail?: unknown },
  now = Date.now(),
): D1PreparedStatement {
  const detail = a.detail === undefined ? null : JSON.stringify(a.detail).slice(0, 2000);
  return db.prepare("INSERT INTO admin_log (at, ip, action, target, detail) VALUES (?, ?, ?, ?, ?)").bind(now, a.ip, a.action, a.target ?? null, detail);
}

// ---------- admin: reads ----------

function parseJson(s: unknown, fallback: unknown): unknown {
  if (typeof s !== "string") return fallback;
  try {
    return JSON.parse(s);
  } catch {
    return fallback;
  }
}

/** Rows as the admin API returns them: JSON text columns parsed, plus the computed `paused` flag. */
export function roomOut(r: RoomRow): Record<string, unknown> {
  return { ...r, settings: parseJson(r.settings, { teams: false, pair_ask: false }), paused: isPaused(r) };
}

export function matchOut(m: MatchRow): Record<string, unknown> {
  return { ...m, players: parseJson(m.players, []), finished: parseJson(m.finished, null) };
}

export interface Page<T> {
  items: T[];
  next: string | null;
}

export class BadCursor extends Error {}

function encodeCursor(v: unknown[]): string {
  return btoa(JSON.stringify(v)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function decodeCursor(s: string, n: number): Array<string | number> {
  try {
    const v = JSON.parse(atob(s.replace(/-/g, "+").replace(/_/g, "/")));
    if (Array.isArray(v) && v.length === n && v.every((x) => typeof x === "string" || typeof x === "number")) return v;
  } catch {
    /* fall through */
  }
  throw new BadCursor("bad cursor");
}

/**
 * Keyset pagination, newest first: ORDER BY <key...> DESC. `keys` are constant column names (never user input).
 * The cursor is the last row's key values.
 */
async function pageQuery<T extends Record<string, unknown>>(
  db: D1Database,
  q: { from: string; where: string[]; params: unknown[]; keys: string[]; limit: number; cursor?: string | null },
): Promise<Page<T>> {
  const where = [...q.where];
  const params = [...q.params];
  if (q.cursor) {
    const c = decodeCursor(q.cursor, q.keys.length);
    // (k1, k2) < (c1, c2)  ==  k1 < c1 OR (k1 = c1 AND k2 < c2)
    const ors: string[] = [];
    for (let i = 0; i < q.keys.length; i++) {
      const eqs = q.keys.slice(0, i).map((k) => `${k} = ?`);
      ors.push(`(${[...eqs, `${q.keys[i]} < ?`].join(" AND ")})`);
      params.push(...c.slice(0, i + 1));
    }
    where.push(`(${ors.join(" OR ")})`);
  }
  const sql =
    `SELECT * FROM ${q.from}` +
    (where.length ? ` WHERE ${where.join(" AND ")}` : "") +
    ` ORDER BY ${q.keys.map((k) => `${k} DESC`).join(", ")} LIMIT ?`;
  params.push(q.limit + 1);
  const { results } = await db.prepare(sql).bind(...params).all<T>();
  const more = results.length > q.limit;
  const items = more ? results.slice(0, q.limit) : results;
  const last = items[items.length - 1];
  return { items, next: more && last ? encodeCursor(q.keys.map((k) => last[k] as string | number)) : null };
}

/** LIKE pattern with %, _ and \ escaped (use with ESCAPE '\'). */
function likeEscape(s: string): string {
  return s.replace(/[\\%_]/g, (ch) => "\\" + ch);
}

export async function listRooms(
  db: D1Database,
  o: { status?: RoomFilter; q?: string; limit: number; cursor?: string | null },
): Promise<Page<RoomRow>> {
  const where: string[] = [];
  const params: unknown[] = [];
  if (o.status) {
    const f = roomFilterSql(o.status);
    where.push(f.sql);
    params.push(...f.params);
  }
  if (o.q) {
    where.push("(code LIKE ? ESCAPE '\\' OR host_name LIKE ? ESCAPE '\\')");
    params.push(likeEscape(o.q.toUpperCase()) + "%", "%" + likeEscape(o.q) + "%");
  }
  return pageQuery<RoomRow & Record<string, unknown>>(db, { from: "rooms", where, params, keys: ["created_at", "code"], ...o });
}

export async function getRoom(db: D1Database, code: string): Promise<RoomRow | null> {
  return db.prepare("SELECT * FROM rooms WHERE code = ?").bind(code).first<RoomRow>();
}

/** Marks a room row closed (and its match still `playing` as `result`). */
export async function closeRoomRow(db: D1Database, code: string, reason: string, now: number, result: MatchResult): Promise<void> {
  await db.batch([
    db.prepare("UPDATE rooms SET status = 'closed', closed_reason = ?, online = 0, updated_at = ? WHERE code = ? AND status != 'closed'").bind(reason, now, code),
    db.prepare("UPDATE matches SET result = ?, ended_at = ? WHERE code = ? AND result = 'playing'").bind(result, now, code),
  ]);
}

export async function listPlayers(
  db: D1Database,
  o: { q?: string; banned?: boolean; limit: number; cursor?: string | null },
): Promise<Page<PlayerRow>> {
  const where: string[] = [];
  const params: unknown[] = [];
  if (o.q) {
    where.push("(name LIKE ? ESCAPE '\\' OR pid LIKE ? ESCAPE '\\')");
    params.push("%" + likeEscape(o.q) + "%", likeEscape(o.q) + "%");
  }
  if (o.banned !== undefined) {
    where.push("banned = ?");
    params.push(o.banned ? 1 : 0);
  }
  return pageQuery<PlayerRow & Record<string, unknown>>(db, { from: "players", where, params, keys: ["last_seen", "pid"], ...o });
}

export async function getPlayer(db: D1Database, pid: string): Promise<PlayerRow | null> {
  return db.prepare("SELECT * FROM players WHERE pid = ?").bind(pid).first<PlayerRow>();
}

/** source (v2, migration 0003): "admin_pid" (Players page) | "account:<id>" (an account ban reached the device). */
export async function setBan(db: D1Database, pid: string, banned: boolean, reason: string | null, source: string | null = banned ? "admin_pid" : null): Promise<boolean> {
  const r = await db
    .prepare("UPDATE players SET banned = ?, ban_reason = ?, ban_source = ? WHERE pid = ?")
    .bind(banned ? 1 : 0, banned ? reason : null, banned ? source : null, pid)
    .run();
  return r.meta.changes > 0;
}

export async function setNote(db: D1Database, pid: string, note: string | null): Promise<boolean> {
  const r = await db.prepare("UPDATE players SET note = ? WHERE pid = ?").bind(note, pid).run();
  return r.meta.changes > 0;
}

// ---------- admin: accounts (v2) ----------

export async function listAccounts(
  db: D1Database,
  o: { q?: string; banned?: boolean; linked?: boolean; limit: number; cursor?: string | null },
): Promise<Page<Record<string, unknown>>> {
  const where: string[] = [];
  const params: unknown[] = [];
  if (o.q) {
    where.push(
      `(name LIKE ? ESCAPE '\\' OR id LIKE ? ESCAPE '\\' OR google_player_id = ? OR public_id = ?
        OR EXISTS (SELECT 1 FROM devices d WHERE d.account_id = accounts.id AND d.pid LIKE ? ESCAPE '\\'))`,
    );
    params.push("%" + likeEscape(o.q) + "%", likeEscape(o.q) + "%", o.q, o.q.toUpperCase(), likeEscape(o.q) + "%");
  }
  if (o.banned !== undefined) {
    where.push("banned = ?");
    params.push(o.banned ? 1 : 0);
  }
  if (o.linked !== undefined) where.push(o.linked ? "google_player_id IS NOT NULL" : "google_player_id IS NULL");
  return pageQuery<Record<string, unknown>>(db, { from: "accounts", where, params, keys: ["last_seen", "id"], ...o });
}

/** The last matches any of these pids played (players[].pid) or this account played (players[].account_id). */
export async function matchesForAccount(db: D1Database, accountId: string, pids: string[], limit = 20): Promise<MatchRow[]> {
  const ps = pids.slice(0, 10);
  const cond = [
    "json_extract(j.value, '$.account_id') = ?",
    ...(ps.length ? [`json_extract(j.value, '$.pid') IN (${ps.map(() => "?").join(", ")})`] : []),
  ].join(" OR ");
  const { results } = await db
    .prepare(`SELECT * FROM matches WHERE EXISTS (SELECT 1 FROM json_each(matches.players) AS j WHERE ${cond}) ORDER BY id DESC LIMIT ?`)
    .bind(accountId, ...ps, limit)
    .all<MatchRow>();
  return results;
}

const HAS_PID = "EXISTS (SELECT 1 FROM json_each(matches.players) AS j WHERE json_extract(j.value, '$.pid') = ?)";

export async function listMatches(
  db: D1Database,
  o: { code?: string; pid?: string; result?: string; since?: number; limit: number; cursor?: string | null },
): Promise<Page<MatchRow>> {
  const where: string[] = [];
  const params: unknown[] = [];
  if (o.code) {
    where.push("code = ?");
    params.push(o.code);
  }
  if (o.pid) {
    where.push(HAS_PID);
    params.push(o.pid);
  }
  if (o.result) {
    where.push("result = ?");
    params.push(o.result);
  }
  if (o.since) {
    // bounds the json_each scan for a pid filter (a player's matches start after their first_seen)
    where.push("started_at >= ?");
    params.push(o.since);
  }
  return pageQuery<MatchRow & Record<string, unknown>>(db, { from: "matches", where, params, keys: ["id"], ...o });
}

export async function listEvents(
  db: D1Database,
  o: { level?: string; kind?: string; limit: number; cursor?: string | null },
): Promise<Page<EventRow>> {
  const where: string[] = [];
  const params: unknown[] = [];
  if (o.level) {
    where.push("level = ?");
    params.push(o.level);
  }
  if (o.kind) {
    where.push("kind = ?");
    params.push(o.kind);
  }
  return pageQuery<EventRow & Record<string, unknown>>(db, { from: "events", where, params, keys: ["id"], ...o });
}

export async function listAudit(db: D1Database, o: { limit: number; cursor?: string | null }): Promise<Page<AuditRow>> {
  return pageQuery<AuditRow & Record<string, unknown>>(db, { from: "admin_log", where: [], params: [], keys: ["id"], ...o });
}

const DAY = 86_400_000;

export async function overview(db: D1Database, now: number): Promise<Record<string, unknown>> {
  const today = Math.floor(now / DAY) * DAY;
  const from = today - 13 * DAY;
  const dayExpr = (col: string) => `strftime('%Y-%m-%d', ${col} / 1000, 'unixepoch')`;
  const [live, rooms, matches, active, fresh, events, cfg, acc, lim] = await db.batch([
    db.prepare(
      `SELECT
         COALESCE(SUM(status = 'lobby'), 0) AS rooms_lobby,
         COALESCE(SUM(status = 'playing' AND online > 0), 0) AS rooms_playing,
         COALESCE(SUM(status = 'playing' AND online = 0), 0) AS rooms_paused,
         COALESCE(SUM(online), 0) AS members_online
       FROM rooms WHERE status IN ('lobby', 'playing', 'over')`,
    ),
    db.prepare(`SELECT ${dayExpr("created_at")} AS day, COUNT(*) AS n FROM rooms WHERE created_at >= ? GROUP BY day`).bind(from),
    db.prepare(`SELECT ${dayExpr("started_at")} AS day, COUNT(*) AS n FROM matches WHERE started_at >= ? GROUP BY day`).bind(from),
    db.prepare("SELECT day, COUNT(*) AS n FROM player_days WHERE day >= ? GROUP BY day").bind(utcDay(from)),
    db.prepare("SELECT COUNT(*) AS n FROM players WHERE first_seen >= ?").bind(today),
    db.prepare("SELECT * FROM events WHERE level IN ('warn', 'error') ORDER BY id DESC LIMIT 10"),
    db.prepare("SELECT value FROM config WHERE key = 'maintenance'"),
    db.prepare(
      `SELECT COUNT(*) AS total, COALESCE(SUM(google_player_id IS NOT NULL), 0) AS linked,
         COALESCE(SUM(coins), 0) AS coins, COALESCE(SUM(created_at >= ?), 0) AS new_today, COALESCE(SUM(banned = 1), 0) AS banned
       FROM accounts WHERE merged_into IS NULL`,
    ).bind(today),
    db.prepare("SELECT COUNT(*) AS n FROM claims WHERE at >= ? AND limited = 1").bind(dayStart(dayKey(Math.floor(now / 1000))) * 1000),
  ]);
  const a = (acc.results[0] ?? {}) as Record<string, number>;
  const byDay = (res: D1Result) => new Map((res.results as Array<{ day: string; n: number }>).map((r) => [r.day, r.n]));
  const R = byDay(rooms);
  const M = byDay(matches);
  const A = byDay(active);
  const days = [];
  for (let t = from; t <= today; t += DAY) {
    const day = utcDay(t);
    days.push({ day, rooms: R.get(day) ?? 0, matches: M.get(day) ?? 0, players_active: A.get(day) ?? 0 });
  }
  const t = days[days.length - 1];
  const l = (live.results[0] ?? {}) as Record<string, number>;
  return {
    now,
    live: {
      rooms_lobby: l.rooms_lobby ?? 0,
      rooms_playing: l.rooms_playing ?? 0,
      rooms_paused: l.rooms_paused ?? 0,
      members_online: l.members_online ?? 0,
    },
    today: {
      rooms: t.rooms,
      matches: t.matches,
      players_active: t.players_active,
      new_players: (fresh.results[0] as { n: number } | undefined)?.n ?? 0,
    },
    days,
    recent_events: events.results,
    maintenance: (cfg.results[0] as { value: string } | undefined)?.value === "1",
    // v2: accounts (merged-away accounts not counted); claims_limited_today counts the economy (Bangladesh) day
    accounts: {
      total: a.total ?? 0,
      linked: a.linked ?? 0,
      guests: (a.total ?? 0) - (a.linked ?? 0),
      banned: a.banned ?? 0,
      new_today: a.new_today ?? 0,
      coins_in_circulation: a.coins ?? 0,
      claims_limited_today: (lim.results[0] as { n: number } | undefined)?.n ?? 0,
    },
  };
}

// ---------- cron ----------

export const RETENTION_MS = 30 * DAY;

/** Guest-creation rows (the per-IP rate limit, accounts.ts GUEST_LIMITS) are kept a day. */
export const GUEST_CREATIONS_MS = DAY;
/** Crash reports (diag.ts) are kept this long; their IP HMAC (the per-IP rate limit) only a day, like guest_creations. */
export const CRASH_REPORTS_MS = 90 * DAY;

/**
 * The daily prune: events, login attempts and player_days after 30 days, guest_creations after a day, weekly
 * leaderboard rows of weeks before `oldestWeek` ("YYYY-Www": the cron passes the week 26 weeks back).
 */
export async function prune(
  db: D1Database,
  now: number,
  oldestWeek?: string,
): Promise<{ events: number; login_attempts: number; player_days: number; guest_creations: number; scores: number; crash_reports: number }> {
  const cut = now - RETENTION_MS;
  const stmts = [
    db.prepare("DELETE FROM events WHERE at < ?").bind(cut),
    db.prepare("DELETE FROM login_attempts WHERE at < ?").bind(cut),
    db.prepare("DELETE FROM player_days WHERE day < ?").bind(utcDay(cut)),
    db.prepare("DELETE FROM guest_creations WHERE at < ?").bind(now - GUEST_CREATIONS_MS),
    db.prepare("DELETE FROM crash_reports WHERE received_at < ?").bind(now - CRASH_REPORTS_MS),
    db.prepare("UPDATE crash_reports SET ip = NULL WHERE ip IS NOT NULL AND received_at < ?").bind(now - GUEST_CREATIONS_MS),
  ];
  // "week:2026-W05" < "week:2026-W43" < "week:2027-W01": the keys sort by time
  if (oldestWeek) stmts.push(db.prepare("DELETE FROM scores WHERE period >= 'week:' AND period < ?").bind(`week:${oldestWeek}`));
  const [e, l, p, g, cr, , w] = await db.batch(stmts);
  return {
    events: e.meta.changes,
    login_attempts: l.meta.changes,
    player_days: p.meta.changes,
    guest_creations: g.meta.changes,
    scores: w?.meta.changes ?? 0,
    crash_reports: cr.meta.changes,
  };
}

/** Rooms rows in one of `statuses` untouched since `before` (their DO may be gone or stuck: the cron checks). */
export async function staleRooms(db: D1Database, statuses: readonly RoomStatus[], before: number, limit = 100): Promise<{ code: string; status: RoomStatus }[]> {
  if (!statuses.length) return [];
  const { results } = await db
    .prepare(`SELECT code, status FROM rooms WHERE status IN (${statuses.map(() => "?").join(", ")}) AND updated_at < ? ORDER BY updated_at LIMIT ?`)
    .bind(...statuses, before, limit)
    .all<{ code: string; status: RoomStatus }>();
  return results;
}

/**
 * The emote packs an account owns (EMOTES.md): `emote_sets` in the account's `owned` JSON (next to rooms, scenes ...),
 * "starter" always included. Unknown account or unreadable JSON -> just starter. Read-only.
 */
export async function readEmoteSets(db: D1Database, accountId: string): Promise<string[]> {
  const row = await db.prepare("SELECT owned FROM accounts WHERE id = ?").bind(accountId).first<{ owned: string | null }>();
  const out = new Set<string>(["starter"]);
  try {
    const owned = row?.owned ? JSON.parse(row.owned) : null;
    const sets = owned && typeof owned === "object" ? (owned as Record<string, unknown>).emote_sets : null;
    if (Array.isArray(sets)) for (const s of sets) if (typeof s === "string") out.add(s);
  } catch {
    /* bad JSON: starter only */
  }
  return [...out];
}
