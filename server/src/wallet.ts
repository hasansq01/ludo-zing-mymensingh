// The server wallet (ONLINE_V2.md §2): shop, daily reward / spin / free coins, achievements and offline match claims.
// The rules are src/econ (pure functions, parity-tested against the game, with the Economy decisions of ONLINE_V2.md
// in econ/rules.ts: Bangladesh days, claim caps paying the remainder, the daily XP cap, S&L wins verified by replaying
// the rolls). This file adds the I/O: every change goes through accounts.ts mutate (optimistic concurrency + ledger
// row + scores in one D1 batch).
import {
  type ClaimInput,
  type ClaimTotals,
  type LimitReason,
  type Profile,
  achProgress,
  buy,
  claimAch,
  claimDaily,
  claimFree,
  claimMatch,
  dailyState,
  dayKey,
  dayStart,
  equip,
  freeLeftSec,
  canSpin,
  nextDayAt,
  rollSpin,
  spin,
  FREE_AMOUNT,
  CATALOG,
  ECON_V1,
} from "./econ";
import { type AccEnv, type Authed, type Step, BadRequest, authedJson, guardedInsert, isUnique, json, mutate, readBody } from "./accounts";

/** The economy day ("YYYY-MM-DD", Bangladesh) of an epoch-ms time. */
export function econDay(nowMs: number): string {
  return dayKey(Math.floor(nowMs / 1000));
}

/** Epoch ms when the economy day of `nowMs` started. */
export function econDayStartMs(nowMs: number): number {
  return dayStart(econDay(nowMs)) * 1000;
}

const ITEM_RE = /^[A-Za-z0-9_.:-]{0,32}$/;

function itemArgs(o: Record<string, unknown>): { kind: string; id: string } {
  if (typeof o.kind !== "string" || !/^[a-z]{1,12}$/.test(o.kind)) throw new BadRequest("kind: string");
  if (typeof o.id !== "string" || !ITEM_RE.test(o.id)) throw new BadRequest("id: an item id");
  return { kind: o.kind, id: o.id };
}

function gone(): Response {
  return json({ error: "unauthorized" }, 401);
}

// ---------- shop ----------

/**
 * POST /v1/shop/buy {kind, id, currency?: "coins" | "gems"} -> {ok, profile, price, currency, item} | 404 unknown |
 * 409 owned / locked / coins / gems (+short).
 */
export async function shopBuy(req: Request, env: AccEnv, a: Authed, now: number): Promise<Response> {
  const body = await readBody(req);
  const { kind, id } = itemArgs(body);
  const currency = body.currency ?? "coins";
  if (currency !== "coins" && currency !== "gems") throw new BadRequest('currency: "coins" | "gems"');
  const r = await mutate(env, a.row.id, now, (_row, p): Step<Response> => {
    const b = buy(p, kind, id, currency);
    if (!b.ok) {
      const body: Record<string, unknown> = { error: b.error };
      if (b.short !== undefined) body.short = b.short;
      return { result: authedJson(a, body, b.error === "unknown" ? 404 : 409) };
    }
    return {
      result: authedJson(a, { ok: true, profile: b.profile, price: b.price, currency, item: { kind, id } }),
      write: { profile: b.profile, ledger: { coins: b.delta.coins, xp: 0, gems: b.delta.gems ?? 0, reason: "buy", ref: `${kind}:${id}` } },
    };
  });
  return r ?? gone();
}

/** POST /v1/shop/equip {kind, id} (room, dice, emotes, scene, avatar / char, frame, plate, badge) -> {ok, profile} | 404 | 409 locked. */
export async function shopEquip(req: Request, env: AccEnv, a: Authed, now: number): Promise<Response> {
  const { kind, id } = itemArgs(await readBody(req));
  const r = await mutate(env, a.row.id, now, (_row, p): Step<Response> => {
    const e = equip(p, kind, id);
    if (!e.ok) return { result: authedJson(a, { error: e.error }, e.error === "unknown" ? 404 : 409) };
    return { result: authedJson(a, { ok: true, profile: e.profile }), write: e.changed ? { profile: e.profile } : undefined };
  });
  return r ?? gone();
}

// ---------- rewards ----------

/** GET /v1/rewards -> {today, daily: {state, next_at?}, spin: {available, next_at}, free: {available, next_at, amount}}. */
export async function rewardsState(a: Authed, profile: Profile, now: number): Promise<Response> {
  const nowS = Math.floor(now / 1000);
  const today = econDay(now);
  const d = dailyState(profile, today);
  const next = nextDayAt(today);
  const left = freeLeftSec(profile, nowS);
  return authedJson(a, {
    today,
    now: nowS,
    daily: { state: d.state, next_at: d.state.claimable ? nowS : next },
    spin: { available: canSpin(profile, today), next_at: canSpin(profile, today) ? nowS : next, prizes: CATALOG.rewards.prizes },
    free: { available: left === 0, next_at: nowS + left, amount: FREE_AMOUNT },
  });
}

/** POST /v1/rewards/daily -> {ok, profile, coins, dice, char, day, cycle, next_at} | 409 {error: "claimed", next_at}. */
export async function rewardDaily(env: AccEnv, a: Authed, now: number): Promise<Response> {
  const nowS = Math.floor(now / 1000);
  const today = econDay(now);
  const next = nextDayAt(today);
  const r = await mutate(env, a.row.id, now, (_row, p): Step<Response> => {
    const c = claimDaily(p, today, nowS);
    if (!c.ok) return { result: authedJson(a, { error: "claimed", next_at: next, day: c.day, cycle: c.cycle }, 409) };
    const { ok, profile, coins, dice, char, day, cycle } = c;
    return {
      result: authedJson(a, { ok, profile, coins, dice, char, day, cycle, next_at: next }),
      write: { profile, ledger: { coins: c.delta.coins, xp: 0, reason: "daily", ref: `${today}:c${cycle}:d${day}${dice ? `:${dice}` : ""}${char ? `:${char}` : ""}` } },
    };
  });
  return r ?? gone();
}

/** POST /v1/rewards/spin -> {ok, profile, index, prize, next_at} | 409 {error: "spun", next_at}. The server draws the segment. */
export async function rewardSpin(env: AccEnv, a: Authed, now: number): Promise<Response> {
  const today = econDay(now);
  const next = nextDayAt(today);
  const roll = rollSpin(); // once per request: a retry after a concurrent write does not re-draw
  const r = await mutate(env, a.row.id, now, (_row, p): Step<Response> => {
    const s = spin(p, today, roll);
    if (!s.ok) return { result: authedJson(a, { error: "spun", next_at: next }, 409) };
    return {
      result: authedJson(a, { ok: true, profile: s.profile, index: s.index, prize: s.prize, next_at: next }),
      write: { profile: s.profile, ledger: { coins: s.prize, xp: 0, reason: "spin", ref: `${today}:${s.index}` } },
    };
  });
  return r ?? gone();
}

/** POST /v1/rewards/free -> {ok, profile, coins, next_at} | 409 {error: "cooldown", next_at}. */
export async function rewardFree(env: AccEnv, a: Authed, now: number): Promise<Response> {
  const nowS = Math.floor(now / 1000);
  const r = await mutate(env, a.row.id, now, (_row, p): Step<Response> => {
    const f = claimFree(p, nowS);
    if (!f.ok) return { result: authedJson(a, { error: "cooldown", next_at: f.next_at }, 409) };
    return {
      result: authedJson(a, { ok: true, profile: f.profile, coins: f.coins, next_at: f.next_at }),
      write: { profile: f.profile, ledger: { coins: f.coins, xp: 0, reason: "free", ref: String(nowS) } },
    };
  });
  return r ?? gone();
}

// ---------- achievements ----------

/** POST /v1/achievements/claim {id} -> {ok, profile, coins} | 404 unknown | 409 not_done / claimed. */
export async function achievementClaim(req: Request, env: AccEnv, a: Authed, now: number): Promise<Response> {
  const o = await readBody(req);
  if (typeof o.id !== "string" || !/^[a-z0-9_-]{1,32}$/.test(o.id)) throw new BadRequest("id: an achievement id");
  const id = o.id;
  const r = await mutate(env, a.row.id, now, (_row, p): Step<Response> => {
    const c = claimAch(p, id);
    if (!c.ok) return { result: authedJson(a, { error: c.error }, c.error === "unknown" ? 404 : 409) };
    // Economy v1: every achievement also pays ECON_V1.achievement_gems (server-only, on top of the catalog coins)
    const gems = ECON_V1.achievement_gems;
    const profile = { ...c.profile, gems: c.profile.gems + gems };
    return {
      result: authedJson(a, { ok: true, profile, coins: c.coins, gems, progress: achProgress(id, profile) }),
      write: { profile, ledger: { coins: c.coins, xp: 0, gems, reason: "achievement", ref: id } },
    };
  });
  return r ?? gone();
}

// ---------- offline match claims ----------

export const CLAIM_ID_RE = /^[A-Za-z0-9_-]{8,64}$/;

export type ClaimReason = LimitReason;

export interface ClaimOutcome {
  ok: true;
  id: string;
  /** Something was cut (partial: granted, but less than the claim was worth) or nothing was paid. */
  limited: boolean;
  /** The claim was applied (coins / XP / stats). */
  granted: boolean;
  reason?: ClaimReason;
  coins: number;
  xp: number;
  /** What the claim was worth before the limits (when limited). */
  would?: { coins: number; xp: number };
}

/**
 * POST /v1/claims {id, game, mode, result, players, duration_s, placing?, moves?, pairs?, xp?, rolls?, need_one?}
 * (placing, when sent, decides the reward: 1 = the win reward, any other place the play reward; else result)
 * -> {ok, id, limited, granted, reason?, coins, xp, would?, profile}. Idempotent by `id` (a retry returns the first
 * answer with `duplicate: true` and the current profile). Rules: econ claimMatch / claimLimit (what the offline
 * game pays; the 60 s / 30 s minimum, an S&L win vs Computer needs `rolls` that replay to square 100, ≤ 20 granted
 * claims per rolling hour, each else paying 0; then the per-day caps of 6,000 coins and 3,000 XP (Bangladesh day),
 * which pay the remainder). A granted claim counts as a completed match. Malformed: 400 {error: "invalid", detail}.
 */
export async function postClaim(req: Request, env: AccEnv, a: Authed, now: number): Promise<Response> {
  const o = await readBody(req);
  const id = o.id;
  if (typeof id !== "string" || !CLAIM_ID_RE.test(id)) throw new BadRequest("id: 8-64 characters of [A-Za-z0-9_-]");
  const db = env.DB;
  const accountId = a.row.id;

  const replay = async (): Promise<Response | null> => {
    const prev = await db
      .prepare("SELECT result FROM claims WHERE account_id = ? AND id = ?")
      .bind(accountId, id)
      .first<{ result: string }>();
    if (!prev) return null;
    const cur = await mutate(env, accountId, now, (_r, p) => ({ result: p }));
    return authedJson(a, { ...(JSON.parse(prev.result) as object), duplicate: true, profile: cur });
  };
  const again = await replay();
  if (again) return again;

  const c = o as unknown as ClaimInput;
  const nowS = Math.floor(now / 1000);
  const dayStartMs = econDayStartMs(now);
  const hourAgo = now - 3600_000;
  const payload = JSON.stringify(o).slice(0, 8000);

  try {
    const r = await mutate(env, accountId, now, async (_row, p): Promise<Step<Response>> => {
      // the account's claims today and in the last hour (claims.at is epoch ms); limited claims hold 0 coins / XP
      const totals = (await db
        .prepare(
          `SELECT COALESCE(SUM(CASE WHEN at >= ?1 THEN coins END), 0) AS coins_today,
                  COALESCE(SUM(CASE WHEN at >= ?1 THEN xp END), 0) AS xp_today,
                  COALESCE(SUM(CASE WHEN at > ?2 AND granted = 1 THEN 1 END), 0) AS last_hour
           FROM claims WHERE account_id = ?3 AND at >= MIN(?1, ?2)`,
        )
        .bind(dayStartMs, hourAgo, accountId)
        .first<ClaimTotals>())!;
      const m = claimMatch(p, c, totals, nowS);
      if (!m.ok) return { result: authedJson(a, { error: "invalid", detail: m.detail }, 400) };
      const out: ClaimOutcome = { ok: true, id, limited: m.limited, granted: m.granted, coins: m.coins, xp: m.xp };
      if (m.limited) Object.assign(out, { reason: m.reason, would: m.would });
      const profile: Profile | undefined = m.granted ? m.profile : undefined;
      return {
        result: authedJson(a, { ...out, profile: profile ?? p }),
        write: {
          profile,
          ledger: { coins: out.coins, xp: out.xp, reason: "claim", ref: id },
          matches: out.granted ? 1 : 0,
          extra: (g) => [
            guardedInsert(
              db,
              g,
              "claims",
              ["id", "account_id", "at", "game", "mode", "payload", "coins", "xp", "granted", "limited", "reason", "result"],
              [id, accountId, now, String(c.game), c.mode === undefined ? null : String(c.mode).slice(0, 16), payload, out.coins, out.xp, out.granted ? 1 : 0, out.limited ? 1 : 0, out.reason ?? null, JSON.stringify(out)],
            ),
          ],
        },
      };
    });
    return r ?? gone();
  } catch (e) {
    if (isUnique(e)) {
      const dup = await replay(); // the same claim id arrived twice at once
      if (dup) return dup;
    }
    throw e;
  }
}
