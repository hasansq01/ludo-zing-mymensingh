// Economy v1 (ECONOMY_V1.md): coin-table entries (held at queue time, moved to the room, settled with the match grant,
// refunded when a match never happens), re-roll payments, the gems -> coins exchange, the coin-table list and the
// daily broke bonus. Every coin / gem change goes through accounts.ts mutate (one D1 batch with its ledger row), and
// every entry status change too: an entry belongs to one account, so the account's version check serializes them
// (a refund racing a settlement re-reads the entry and finds it already done).
import { type AccEnv, type Authed, type Step, BadRequest, authedJson, guardedInsert, json, mutate, readBody } from "./accounts";
import { ECON_V1, addCoins, coinTable, levelInfo, type Profile } from "./econ";
import { econDay } from "./wallet";
import { isoWeek, nextDayAt } from "./econ";
import { topScores } from "./leaderboard";
import { isMondayBd } from "./push";

export type EntryStatus = "held" | "playing" | "settled" | "forfeit" | "refunded";

export interface EntryRow {
  id: string;
  account_id: string;
  at: number;
  game: string;
  size: number;
  tier: string;
  amount: number;
  status: EntryStatus;
  room: string | null;
  match_id: string | null;
  place: number | null;
  payout: number;
  settled_at: number | null;
}

const ABC = "abcdefghijklmnopqrstuvwxyz234567";

export function newEntryId(): string {
  const r = new Uint8Array(16);
  crypto.getRandomValues(r);
  let s = "ent_";
  for (const v of r) s += ABC[v & 31];
  return s;
}

export const ENTRY_RE = /^ent_[a-z2-7]{16}$/;

async function getEntry(db: D1Database, id: string): Promise<EntryRow | null> {
  return db.prepare("SELECT * FROM entries WHERE id = ?").bind(id).first<EntryRow>();
}

function level(p: Profile): number {
  return levelInfo(Math.max(0, Math.trunc(p.xp))).level;
}

// ---------- entries ----------

export type HoldResult =
  | { ok: true; entry_id: string; amount: number }
  | { ok: false; error: "unknown" | "locked" | "coins" | "banned"; short?: number; level?: number };

/**
 * Takes a coin table's entry at queue time (Matchmaker hello): checks the level, pays the entry (ledger `entry`,
 * ref = the entry id) and inserts the `held` entry row in the same batch. The practice table and unknown accounts
 * never get here (entry 0 needs no row).
 */
export async function holdEntry(env: AccEnv, o: { account_id: string; game: string; size: number; tier: string }, now = Date.now()): Promise<HoldResult> {
  const t = coinTable(o.tier);
  if (!t || t.entry <= 0) return { ok: false, error: "unknown" };
  const id = newEntryId();
  const r = await mutate(env, o.account_id, now, (row, p): Step<HoldResult> => {
    if (row.banned || row.merged_into) return { result: { ok: false, error: "banned" } };
    if (level(p) < t.level) return { result: { ok: false, error: "locked", level: t.level } };
    if (p.coins < t.entry) return { result: { ok: false, error: "coins", short: t.entry - p.coins } };
    const q = { ...p, coins: p.coins - t.entry };
    return {
      result: { ok: true, entry_id: id, amount: t.entry },
      write: {
        profile: q,
        ledger: { coins: -t.entry, xp: 0, reason: "entry", ref: id },
        extra: (g) => [
          guardedInsert(env.DB, g, "entries", ["id", "account_id", "at", "game", "size", "tier", "amount", "status"], [id, o.account_id, now, o.game, o.size, o.tier, t.entry, "held"]),
        ],
      },
    };
  });
  return r ?? { ok: false, error: "unknown" };
}

/**
 * Gives an entry's coins back (left the queue, match abandoned before it started, no-show, room destroyed, cron
 * sweep). Only from `held` / `playing`; anything else is a no-op. Returns whether coins went back.
 */
export async function refundEntry(env: AccEnv, entryId: string, why: string, now = Date.now()): Promise<boolean> {
  if (!ENTRY_RE.test(entryId)) return false;
  const e0 = await getEntry(env.DB, entryId);
  if (!e0) return false;
  const r = await mutate(env, e0.account_id, now, async (_row, p): Promise<Step<boolean>> => {
    const e = await getEntry(env.DB, entryId);
    if (!e || (e.status !== "held" && e.status !== "playing")) return { result: false };
    return {
      result: true,
      write: {
        profile: { ...p, coins: p.coins + e.amount },
        ledger: { coins: e.amount, xp: 0, reason: "entry_refund", ref: `${entryId}:${why}`.slice(0, 80) },
        extra: (g) => [
          env.DB.prepare(`UPDATE entries SET status = 'refunded', settled_at = ? WHERE id = ? AND status IN ('held', 'playing') AND ${g.sql}`).bind(now, entryId, ...g.params),
        ],
      },
    };
  });
  return r ?? false;
}

/** The matched entries move to their room (`held` -> `playing`). No coins move, so no account write is needed. */
export async function seatEntries(env: AccEnv, entryIds: string[], room: string): Promise<void> {
  const ids = entryIds.filter((id) => ENTRY_RE.test(id));
  if (!ids.length) return;
  await env.DB.batch(ids.map((id) => env.DB.prepare("UPDATE entries SET status = 'playing', room = ? WHERE id = ? AND status = 'held'").bind(room, id)));
}

/**
 * The entries of a finished or abandoned match: `settle` each with its payout (place = index in the paid order,
 * -1 = forfeit). Called from the match grant (accounts.ts grantOne) inside its mutate: returns the statements to
 * batch and the coins to add. Only `playing` / `held` entries change.
 */
export function entrySettleStmt(db: D1Database, g: { sql: string; params: unknown[] }, entryId: string, matchId: string, place: number, payout: number, now: number): D1PreparedStatement {
  const status = place < 0 ? "forfeit" : "settled";
  return db
    .prepare(`UPDATE entries SET status = ?, match_id = ?, place = ?, payout = ?, settled_at = ? WHERE id = ? AND status IN ('held', 'playing') AND ${g.sql}`)
    .bind(status, matchId, place < 0 ? null : place, payout, now, entryId, ...g.params);
}

export async function entryOpen(db: D1Database, entryId: string): Promise<EntryRow | null> {
  const e = await getEntry(db, entryId);
  return e && (e.status === "held" || e.status === "playing") ? e : null;
}

/** Forfeits an entry (every person left an abandoned match): no coins move, the entry is closed. */
export async function forfeitEntry(env: AccEnv, entryId: string, matchId: string, now = Date.now()): Promise<void> {
  if (!ENTRY_RE.test(entryId)) return;
  const e0 = await getEntry(env.DB, entryId);
  if (!e0) return;
  await mutate(env, e0.account_id, now, async (): Promise<Step<void>> => {
    const e = await entryOpen(env.DB, entryId);
    if (!e) return { result: undefined };
    return { result: undefined, write: { extra: (g) => [entrySettleStmt(env.DB, g, entryId, matchId, -1, 0, now)] } };
  });
}

/** Cron: entries still held / playing after ECON_V1.entry_sweep_ms are refunded (a lost Matchmaker or Room). */
export async function sweepEntries(env: AccEnv, now = Date.now()): Promise<number> {
  const rows = await env.DB.prepare("SELECT id FROM entries WHERE status IN ('held', 'playing') AND at < ? LIMIT 50")
    .bind(now - ECON_V1.entry_sweep_ms)
    .all<{ id: string }>();
  let n = 0;
  for (const r of rows.results ?? []) if (await refundEntry(env, r.id, "sweep", now).catch(() => false)) n++;
  return n;
}

// ---------- re-rolls ----------

export type RerollPay = { ok: true; paid: "free" | "gems"; free: number; gems: number } | { ok: false; error: "reroll_used" | "gems" | "unknown" };

/**
 * Pays a re-roll for `match_id` (a free re-roll if any, else ECON_V1.reroll_gems gems) and records it (rerolls row,
 * once per match: a second one is `reroll_used`).
 */
export async function spendReroll(env: AccEnv, accountId: string, matchId: string, now = Date.now()): Promise<RerollPay> {
  const r = await mutate(env, accountId, now, async (row, p): Promise<Step<RerollPay>> => {
    if (row.banned || row.merged_into) return { result: { ok: false, error: "unknown" } };
    const used = await env.DB.prepare("SELECT 1 AS x FROM rerolls WHERE match_id = ? AND account_id = ?").bind(matchId, accountId).first();
    if (used) return { result: { ok: false, error: "reroll_used" } };
    let paid: "free" | "gems";
    const q = { ...p };
    if (p.rerolls > 0) {
      paid = "free";
      q.rerolls = p.rerolls - 1;
    } else if (p.gems >= ECON_V1.reroll_gems) {
      paid = "gems";
      q.gems = p.gems - ECON_V1.reroll_gems;
    } else return { result: { ok: false, error: "gems" } };
    return {
      result: { ok: true, paid, free: q.rerolls, gems: q.gems },
      write: {
        profile: q,
        ledger: paid === "gems" ? { coins: 0, xp: 0, gems: -ECON_V1.reroll_gems, reason: "reroll", ref: matchId } : undefined,
        extra: (g) => [guardedInsert(env.DB, g, "rerolls", ["match_id", "account_id", "at", "paid"], [matchId, accountId, now, paid])],
      },
    };
  });
  return r ?? { ok: false, error: "unknown" };
}

/** Undoes a paid re-roll that couldn't be used (the match moved on while paying). */
export async function refundReroll(env: AccEnv, accountId: string, matchId: string, now = Date.now()): Promise<void> {
  await mutate(env, accountId, now, async (_row, p): Promise<Step<void>> => {
    const r = await env.DB.prepare("SELECT paid FROM rerolls WHERE match_id = ? AND account_id = ?").bind(matchId, accountId).first<{ paid: string }>();
    if (!r) return { result: undefined };
    const q = { ...p };
    if (r.paid === "free") q.rerolls = Math.min(ECON_V1.reroll_free_max, p.rerolls + 1);
    else q.gems = p.gems + ECON_V1.reroll_gems;
    return {
      result: undefined,
      write: {
        profile: q,
        ledger: r.paid === "gems" ? { coins: 0, xp: 0, gems: ECON_V1.reroll_gems, reason: "reroll", ref: `${matchId}:refund` } : undefined,
        extra: (g) => [env.DB.prepare(`DELETE FROM rerolls WHERE match_id = ? AND account_id = ? AND ${g.sql}`).bind(matchId, accountId, ...g.params)],
      },
    };
  });
}

/** What the Room caches at match start to decide whether to offer a re-roll window. */
export async function rerollBalance(env: AccEnv, accountId: string): Promise<{ free: number; gems: number } | null> {
  const r = await env.DB.prepare("SELECT rerolls, gems FROM accounts WHERE id = ?").bind(accountId).first<{ rerolls: number; gems: number }>();
  return r ? { free: r.rerolls, gems: r.gems } : null;
}

// ---------- HTTP: exchange, tables, broke ----------

/** POST /v1/gems/exchange {pack: 0 | 1 | 2} -> {ok, profile, gems, coins} | 409 {error: "gems", short}. */
export async function gemsExchange(req: Request, env: AccEnv, a: Authed, now: number): Promise<Response> {
  const o = await readBody(req);
  const pack = ECON_V1.exchange[typeof o.pack === "number" && Number.isInteger(o.pack) ? o.pack : -1];
  if (!pack) throw new BadRequest(`pack: 0..${ECON_V1.exchange.length - 1}`);
  const r = await mutate(env, a.row.id, now, (_row, p): Step<Response> => {
    if (p.gems < pack.gems) return { result: authedJson(a, { error: "gems", short: pack.gems - p.gems }, 409) };
    const q = { ...p, gems: p.gems - pack.gems, coins: p.coins + pack.coins };
    return {
      result: authedJson(a, { ok: true, profile: q, gems: pack.gems, coins: pack.coins }),
      write: { profile: q, ledger: { coins: pack.coins, xp: 0, gems: -pack.gems, reason: "exchange", ref: `${pack.gems}` } },
    };
  });
  return r ?? json({ error: "unauthorized" }, 401);
}

async function brokeClaimedToday(db: D1Database, accountId: string, day: string): Promise<boolean> {
  return !!(await db.prepare("SELECT 1 AS x FROM broke_bonus WHERE account_id = ? AND day = ?").bind(accountId, day).first());
}

/** GET /v1/tables -> the coin tables with unlocked / affordable, the fee, and the broke bonus state. */
export async function tablesState(env: AccEnv, a: Authed, p: Profile, now: number): Promise<Response> {
  const lv = level(p);
  const broke = p.coins < ECON_V1.broke_below;
  const day = econDay(now);
  const claimed = broke ? await brokeClaimedToday(env.DB, a.row.id, day) : false;
  return authedJson(a, {
    tables: ECON_V1.tables.map((t) => ({ id: t.id, entry: t.entry, level: t.level, unlocked: lv >= t.level, affordable: p.coins >= t.entry })),
    fee_pct: ECON_V1.fee_pct,
    level: lv,
    broke,
    broke_bonus: { available: broke && !claimed, next_at: claimed ? nextDayAt(day) : Math.floor(now / 1000), amount: ECON_V1.broke_bonus },
  });
}

/** POST /v1/rewards/broke -> {ok, profile, coins} | 409 not_broke | 409 claimed (+next_at). */
export async function rewardBroke(env: AccEnv, a: Authed, now: number): Promise<Response> {
  const day = econDay(now);
  const amount = ECON_V1.broke_bonus;
  const r = await mutate(env, a.row.id, now, async (_row, p): Promise<Step<Response>> => {
    if (p.coins >= ECON_V1.broke_below) return { result: authedJson(a, { error: "not_broke" }, 409) };
    if (await brokeClaimedToday(env.DB, a.row.id, day)) return { result: authedJson(a, { error: "claimed", next_at: nextDayAt(day) }, 409) };
    const q = structuredClone(p);
    addCoins(q, amount);
    return {
      result: authedJson(a, { ok: true, profile: q, coins: amount, next_at: nextDayAt(day) }),
      write: {
        profile: q,
        ledger: { coins: amount, xp: 0, reason: "broke", ref: day },
        extra: (g) => [guardedInsert(env.DB, g, "broke_bonus", ["account_id", "day", "at", "coins"], [a.row.id, day, now, amount])],
      },
    };
  });
  return r ?? json({ error: "unauthorized" }, 401);
}

// ---------- weekly gem prizes ----------

/**
 * Monday cron (Bangladesh time): last week's XP and wins boards pay gems by rank (ECON_V1.weekly_gems; ties share a
 * rank and its prize), once per week, board and account (weekly_prizes). Returns the prizes paid, or null on
 * another day.
 */
export async function weeklyPrizes(env: AccEnv, now = Date.now(), force = false): Promise<number | null> {
  if (!force && !isMondayBd(now)) return null;
  const week = isoWeek(Math.floor(now / 1000) - 7 * 86400);
  const period = `week:${week}`;
  let n = 0;
  for (const board of ["xp", "wins"] as const) {
    const top = await topScores(env.DB, board, period, ECON_V1.weekly_gems.length);
    for (const t of top) {
      const gems = ECON_V1.weekly_gems[Math.min(t.rank, ECON_V1.weekly_gems.length) - 1] ?? 0;
      if (gems <= 0) continue;
      try {
        const paid = await mutate(env, t.account_id, now, async (row, p): Promise<Step<boolean>> => {
          if (row.banned || row.merged_into) return { result: false };
          const done = await env.DB.prepare("SELECT 1 AS x FROM weekly_prizes WHERE period = ? AND board = ? AND account_id = ?").bind(period, board, t.account_id).first();
          if (done) return { result: false };
          return {
            result: true,
            write: {
              profile: { ...p, gems: p.gems + gems },
              ledger: { coins: 0, xp: 0, gems, reason: "weekly", ref: `${board}:${week}:#${t.rank}` },
              extra: (g) => [guardedInsert(env.DB, g, "weekly_prizes", ["period", "board", "account_id", "rank", "gems", "at"], [period, board, t.account_id, t.rank, gems, now])],
            },
          };
        });
        if (paid) n++;
      } catch (e) {
        console.error(`weekly prize ${board} ${t.account_id} failed:`, e);
      }
    }
  }
  return n;
}
