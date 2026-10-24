// D1 (binding DB, database "ludo-zing-admin"): every SQL statement the Worker and the Room DO run lives here.
// Schema: migrations/0001_init.sql. Contract: ADMIN_API.md. Times are epoch ms.

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
  note: string | null;
  last_room: string | null;
}

export type RoomStatus = "lobby" | "playing" | "over" | "closed";

export interface RoomRow {
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
}

/**
 * Inserts or updates the room's row (every write carries the whole row, so a lost write is repaired by the next).
 * `fresh` (room init) also resets created_at: a code can be reused after its room was deleted.
 */
export function upsertRoom(db: D1Database, r: RoomState, now: number, fresh = false): D1PreparedStatement {
  return db
    .prepare(
      `INSERT INTO rooms (code, created_at, updated_at, host_pid, host_name, status, members, online, settings, closed_reason)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)
       ON CONFLICT(code) DO UPDATE SET
         ${fresh ? "created_at = excluded.created_at," : ""}
         updated_at = excluded.updated_at, host_pid = excluded.host_pid, host_name = excluded.host_name,
         status = excluded.status, members = excluded.members, online = excluded.online,
         settings = excluded.settings, closed_reason = excluded.closed_reason`,
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

/** The ban flag for one pid (null when the player has never been seen). */
export async function readBan(db: D1Database, pid: string): Promise<{ banned: boolean; reason: string } | null> {
  const row = await db.prepare("SELECT banned, ban_reason FROM players WHERE pid = ?").bind(pid).first<{ banned: number; ban_reason: string | null }>();
  return row ? { banned: row.banned === 1, reason: row.ban_reason ?? "" } : null;
}

export function insertMatch(
  db: D1Database,
  m: { code: string; started_at: number; players: MatchPlayer[]; teams: boolean; pair_ask: boolean },
): D1PreparedStatement {
  return db
    .prepare(
      `INSERT INTO matches (code, started_at, players, teams, pair_ask, actions, result)
       VALUES (?, ?, ?, ?, ?, 0, 'playing')`,
    )
    .bind(m.code, m.started_at, JSON.stringify(m.players), m.teams ? 1 : 0, m.pair_ask ? 1 : 0);
}

/** Ends the match identified by (code, started_at). Only a match still `playing` changes. */
export function endMatch(
  db: D1Database,
  m: { code: string; started_at: number; ended_at: number; winner: number | null; finished: number[]; actions: number; result: MatchResult },
): D1PreparedStatement {
  return db
    .prepare(
      `UPDATE matches SET ended_at = ?, winner = ?, finished = ?, actions = ?, result = ?
       WHERE code = ? AND started_at = ? AND result = 'playing'`,
    )
    .bind(m.ended_at, m.winner, JSON.stringify(m.finished), m.actions, m.result, m.code, m.started_at);
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

/** Rows as the admin API returns them: JSON text columns parsed. */
export function roomOut(r: RoomRow): Record<string, unknown> {
  return { ...r, settings: parseJson(r.settings, { teams: false, pair_ask: false }) };
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
  o: { status?: string; q?: string; limit: number; cursor?: string | null },
): Promise<Page<RoomRow>> {
  const where: string[] = [];
  const params: unknown[] = [];
  if (o.status) {
    where.push("status = ?");
    params.push(o.status);
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

export async function setBan(db: D1Database, pid: string, banned: boolean, reason: string | null): Promise<boolean> {
  const r = await db.prepare("UPDATE players SET banned = ?, ban_reason = ? WHERE pid = ?").bind(banned ? 1 : 0, banned ? reason : null, pid).run();
  return r.meta.changes > 0;
}

export async function setNote(db: D1Database, pid: string, note: string | null): Promise<boolean> {
  const r = await db.prepare("UPDATE players SET note = ? WHERE pid = ?").bind(note, pid).run();
  return r.meta.changes > 0;
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
  const [live, rooms, matches, active, fresh, events, cfg] = await db.batch([
    db.prepare(
      `SELECT
         COALESCE(SUM(status = 'lobby'), 0) AS rooms_lobby,
         COALESCE(SUM(status = 'playing'), 0) AS rooms_playing,
         COALESCE(SUM(online), 0) AS members_online
       FROM rooms WHERE status IN ('lobby', 'playing', 'over')`,
    ),
    db.prepare(`SELECT ${dayExpr("created_at")} AS day, COUNT(*) AS n FROM rooms WHERE created_at >= ? GROUP BY day`).bind(from),
    db.prepare(`SELECT ${dayExpr("started_at")} AS day, COUNT(*) AS n FROM matches WHERE started_at >= ? GROUP BY day`).bind(from),
    db.prepare("SELECT day, COUNT(*) AS n FROM player_days WHERE day >= ? GROUP BY day").bind(utcDay(from)),
    db.prepare("SELECT COUNT(*) AS n FROM players WHERE first_seen >= ?").bind(today),
    db.prepare("SELECT * FROM events WHERE level IN ('warn', 'error') ORDER BY id DESC LIMIT 10"),
    db.prepare("SELECT value FROM config WHERE key = 'maintenance'"),
  ]);
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
    live: { rooms_lobby: l.rooms_lobby ?? 0, rooms_playing: l.rooms_playing ?? 0, members_online: l.members_online ?? 0 },
    today: {
      rooms: t.rooms,
      matches: t.matches,
      players_active: t.players_active,
      new_players: (fresh.results[0] as { n: number } | undefined)?.n ?? 0,
    },
    days,
    recent_events: events.results,
    maintenance: (cfg.results[0] as { value: string } | undefined)?.value === "1",
  };
}

// ---------- cron ----------

export const RETENTION_MS = 30 * DAY;

export async function prune(db: D1Database, now: number): Promise<{ events: number; login_attempts: number; player_days: number }> {
  const cut = now - RETENTION_MS;
  const [e, l, p] = await db.batch([
    db.prepare("DELETE FROM events WHERE at < ?").bind(cut),
    db.prepare("DELETE FROM login_attempts WHERE at < ?").bind(cut),
    db.prepare("DELETE FROM player_days WHERE day < ?").bind(utcDay(cut)),
  ]);
  return { events: e.meta.changes, login_attempts: l.meta.changes, player_days: p.meta.changes };
}

/** Rooms rows still marked live but untouched for a while (their DO may be gone: the cron double-checks). */
export async function staleLiveRooms(db: D1Database, before: number, limit = 100): Promise<string[]> {
  const { results } = await db
    .prepare("SELECT code FROM rooms WHERE status IN ('lobby', 'playing', 'over') AND updated_at < ? LIMIT ?")
    .bind(before, limit)
    .all<{ code: string }>();
  return results.map((r) => r.code);
}
