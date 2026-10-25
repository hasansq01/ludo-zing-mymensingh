// Leaderboards (ONLINE_V2.md §4): D1 `scores(account_id, board, period, value, updated_at)`.
//   board xp:   total XP (period "all") / XP gained this week ("week:YYYY-Www")
//   board wins: online match wins (friend rooms + quick match), all time / this week
// Weeks are ISO weeks in Bangladesh time (econ isoWeek, the same day rule as the economy).
// Scores are written in the same D1 batch as the change that causes them (accounts.ts mutate), so they never drift.
import { isoWeek, levelInfo, weekPeriod } from "./econ";

export const BOARDS = ["xp", "wins"] as const;
export type Board = (typeof BOARDS)[number];
export const PERIODS = ["all", "week"] as const;
export type PeriodArg = (typeof PERIODS)[number];
export const TOP_N = 50;
export const CACHE_S = 30;
/** Policy (lead, 2026-10-24): an account is listed once it has this many completed matches (accounts.completed_matches). */
export const MIN_MATCHES = 3;
/** Weekly score rows older than this many weeks are pruned by the daily cron. */
export const KEEP_WEEKS = 26;

/** A condition (SQL + params) that is true only when the batch's account write applied (accounts.ts Guard). */
export interface Guard {
  sql: string;
  params: unknown[];
}

const ALWAYS: Guard = { sql: "1", params: [] };

/**
 * The score rows a change touches: `xp` (the new total, when XP changed), `xpWeek` (XP to add to this week's board),
 * `wins` (online wins to add).
 */
export function scoreStmts(
  db: D1Database,
  g: Guard | null,
  accountId: string,
  ch: { xp?: number; xpWeek?: number; wins?: number },
  now: number,
): D1PreparedStatement[] {
  const guard = g ?? ALWAYS;
  const out: D1PreparedStatement[] = [];
  const set = (board: Board, period: string, value: number) =>
    out.push(
      db
        .prepare(
          `INSERT INTO scores (account_id, board, period, value, updated_at) SELECT ?, ?, ?, ?, ? WHERE ${guard.sql}
           ON CONFLICT (account_id, board, period) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at`,
        )
        .bind(accountId, board, period, value, now, ...guard.params),
    );
  const add = (board: Board, period: string, n: number) =>
    out.push(
      db
        .prepare(
          `INSERT INTO scores (account_id, board, period, value, updated_at) SELECT ?, ?, ?, ?, ? WHERE ${guard.sql}
           ON CONFLICT (account_id, board, period) DO UPDATE SET value = scores.value + excluded.value, updated_at = excluded.updated_at`,
        )
        .bind(accountId, board, period, n, now, ...guard.params),
    );
  const week = weekPeriod(Math.floor(now / 1000));
  if (ch.xp !== undefined) set("xp", "all", ch.xp);
  if (ch.xpWeek) add("xp", week, ch.xpWeek);
  if (ch.wins) {
    add("wins", "all", ch.wins);
    add("wins", week, ch.wins);
  }
  return out;
}

/** "all" or "week" (the current week; admin may name another: "2026-W42") -> scores.period. */
export function periodKey(p: PeriodArg, now: number, week?: string): string {
  if (p === "all") return "all";
  return `week:${week ?? isoWeek(Math.floor(now / 1000))}`;
}

export interface TopRow {
  rank: number;
  account_id: string;
  name: string;
  avatar: string;
  frame: string;
  level: number;
  value: number;
  updated_at: number;
}

/** Accounts that are listed: not banned, not merged away, at least MIN_MATCHES completed matches (a constant). */
const LIVE = `a.banned = 0 AND a.merged_into IS NULL AND a.completed_matches >= ${MIN_MATCHES}`;

/**
 * The top N of a board (banned and merged accounts and accounts with fewer than MIN_MATCHES completed matches left
 * out). Ties share a rank (1, 2, 2, 4), earlier first.
 */
export async function topScores(db: D1Database, board: Board, period: string, limit = TOP_N): Promise<TopRow[]> {
  const { results } = await db
    .prepare(
      `SELECT s.account_id, s.value, s.updated_at, a.name, a.avatar, a.frame, a.xp
       FROM scores s JOIN accounts a ON a.id = s.account_id
       WHERE s.board = ? AND s.period = ? AND s.value > 0 AND ${LIVE}
       ORDER BY s.value DESC, s.updated_at ASC, s.account_id ASC LIMIT ?`,
    )
    .bind(board, period, limit)
    .all<{ account_id: string; value: number; updated_at: number; name: string | null; avatar: string | null; frame: string | null; xp: number }>();
  const out: TopRow[] = [];
  results.forEach((r, i) => {
    const prev = out[i - 1];
    out.push({
      rank: prev && prev.value === r.value ? prev.rank : i + 1,
      account_id: r.account_id,
      name: r.name || "Player",
      avatar: r.avatar ?? "",
      frame: r.frame ?? "",
      level: levelInfo(Math.max(0, r.xp)).level,
      value: r.value,
      updated_at: r.updated_at,
    });
  });
  return out;
}

export interface MyRank {
  /** 1 + listed accounts strictly ahead (also for an account that is not listed yet); null while the value is 0. */
  rank: number | null;
  value: number;
  /** The account appears in the top list's population (it has MIN_MATCHES completed matches, not banned). */
  listed: boolean;
}

/** An account's value and rank among the listed accounts (its own rank even when it is not listed itself). */
export async function rankOf(db: D1Database, board: Board, period: string, accountId: string): Promise<MyRank> {
  const r = await db
    .prepare(
      `SELECT a0.completed_matches AS done, a0.banned AS banned, a0.merged_into AS merged, s.value AS value,
         (SELECT COUNT(*) FROM scores t JOIN accounts a ON a.id = t.account_id
          WHERE t.board = ?2 AND t.period = ?3 AND t.value > s.value AND ${LIVE}) AS ahead
       FROM accounts a0 LEFT JOIN scores s ON s.account_id = a0.id AND s.board = ?2 AND s.period = ?3
       WHERE a0.id = ?1`,
    )
    .bind(accountId, board, period)
    .first<{ done: number; banned: number; merged: string | null; value: number | null; ahead: number }>();
  const listed = !!r && r.done >= MIN_MATCHES && r.banned === 0 && r.merged === null;
  const value = r?.value ?? 0;
  if (!r || value <= 0) return { rank: null, value, listed };
  return { rank: r.ahead + 1, value, listed };
}

export async function countScores(db: D1Database, board: Board, period: string): Promise<number> {
  const r = await db
    .prepare(`SELECT COUNT(*) AS n FROM scores s JOIN accounts a ON a.id = s.account_id WHERE s.board = ? AND s.period = ? AND s.value > 0 AND ${LIVE}`)
    .bind(board, period)
    .first<{ n: number }>();
  return r?.n ?? 0;
}

function publicRow(r: TopRow) {
  return { rank: r.rank, name: r.name, avatar: r.avatar, frame: r.frame, level: r.level, value: r.value };
}

/**
 * GET /v1/leaderboard?board=xp|wins&period=all|week -> {board, period, week?, min_matches, top: [{rank, name, avatar,
 * frame, level, value}], me: {rank, value, listed} | null}. Only accounts with MIN_MATCHES completed matches are
 * listed; `me` still has the caller's rank among them (listed: false until then). The top list is cached 30 s (Cache
 * API, per board + period); `me` is read per request (null without a session). `nocache=1` skips the cache, only
 * under TEST_MODE.
 */
export async function handleLeaderboard(
  db: D1Database,
  ctx: ExecutionContext,
  url: URL,
  accountId: string | null,
  now: number,
  testMode: boolean,
): Promise<Response> {
  const board = url.searchParams.get("board") ?? "xp";
  const period = url.searchParams.get("period") ?? "all";
  if (!(BOARDS as readonly string[]).includes(board) || !(PERIODS as readonly string[]).includes(period)) {
    return Response.json({ error: "bad_request", msg: "board: xp | wins, period: all | week" }, { status: 400, headers: { "Cache-Control": "no-store" } });
  }
  const key = periodKey(period as PeriodArg, now);
  const cacheKey = new Request(`https://leaderboard.cache.ludo-zing/${board}/${key}`);
  const skipCache = testMode && url.searchParams.get("nocache") === "1";
  const cache = (globalThis as unknown as { caches?: { default?: Cache } }).caches?.default;
  let top: unknown[] | null = null;
  if (cache && !skipCache) {
    const hit = await cache.match(cacheKey).catch(() => undefined);
    if (hit) top = ((await hit.json().catch(() => null)) as { top?: unknown[] } | null)?.top ?? null;
  }
  if (!top) {
    top = (await topScores(db, board as Board, key)).map(publicRow);
    if (cache && !skipCache) {
      const res = Response.json({ top }, { headers: { "Cache-Control": `public, max-age=${CACHE_S}` } });
      ctx.waitUntil(cache.put(cacheKey, res).catch(() => {}));
    }
  }
  const me = accountId ? await rankOf(db, board as Board, key, accountId) : null;
  const body: Record<string, unknown> = { board, period, min_matches: MIN_MATCHES, top, me };
  if (period === "week") body.week = key.slice(5);
  return Response.json(body, { headers: { "Cache-Control": "no-store" } });
}
