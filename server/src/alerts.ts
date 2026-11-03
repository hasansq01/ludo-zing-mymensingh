// Alerts (ADMIN_API.md "Alerts"): a check every 15 minutes (wrangler.jsonc "triggers") that warns the owner before
// the server runs into a Cloudflare free-plan limit, when the server itself has trouble, and once a morning with
// yesterday's numbers. Every alert is a row in D1 `alerts` (the console's Alerts page, and its banner until read) and a
// push to every device of the accounts in ALERT_ACCOUNTS (a var: account ids, comma separated). An alert's `key` makes
// it once only: the same metric at the same step on the same UTC day is never pushed twice.
//
// What it watches:
//  - each daily free-plan allowance (usage.ts FREE_LIMITS) at 70 / 90 / 100 % of today (the storage ones: per month);
//  - the pace: at the rate of the last 3 hours, an allowance runs out before the 00:00 UTC reset;
//  - Cloudflare's usage can't be read (twice in a row): the warnings above are blind;
//  - server errors in the last hour (Cloudflare's count for the Worker and its Durable Objects, plus the Worker errors
//    the fetch handler logged in D1 `events`);
//  - push sending failing today (D1 push_events);
//  - from 03:00 UTC (09:00 Bangladesh), once: yesterday's summary.
import * as D from "./db";
import * as P from "./push";
import type { Env } from "./room";
import { CloudflareError, FREE_LIMITS, cloudflareErrors, usageSnapshot, utcDayStart, type MetricId, type UsageBody, type UsageEnv } from "./usage";

export const ALERT_CRON = "*/15 * * * *";

const MIN = 60_000;
const HOUR = 60 * MIN;
const DAY = 24 * HOUR;
/** Bangladesh (UTC+6, no DST): the times in the texts. */
const BD_OFFSET_MS = 6 * HOUR;

/** % of an allowance that raise an alert; 70 is a warning, 90 and 100 are danger. */
export const STEPS = [70, 90, 100] as const;
/** Pace: only once this much of the day's allowance is used and this many hours of the day have passed. */
export const PACE_MIN_PERCENT = 25;
export const PACE_MIN_HOURS = 3;
/** Failed Cloudflare reads in a row before "Can't check the limits". */
export const USAGE_FAILS = 2;
/** Server errors in the last hour: at least this many, and at least this share of the requests. */
export const ERRORS_MIN = 20;
export const ERRORS_SHARE = 0.02;
/** Push failing: at least this many failed today, and more failed than sent. */
export const PUSH_FAILED_MIN = 20;
/** The summary goes out at the first check from this UTC hour (09:00 Bangladesh). */
export const SUMMARY_HOUR_UTC = 3;
/** More new alerts than this in one check: one push that lists them. */
const PUSH_SINGLY = 2;
export const KEEP_DAYS = 90;

export type Level = "info" | "warning" | "danger";
export type Kind = "usage" | "pace" | "server" | "summary" | "test";

export interface AlertEnv {
  /** Account ids (comma or space separated) whose devices get the alert pushes. Unset: alerts are only listed. */
  ALERT_ACCOUNTS?: string;
}

type AEnv = Env & UsageEnv & AlertEnv;

export interface NewAlert {
  key: string;
  level: Level;
  kind: Kind;
  title: string;
  body: string;
  /** The notification tag: a phone shows only the latest push of a tag. */
  tag: string;
}

export interface CheckResult {
  at: number;
  /** "ok", or why Cloudflare's usage could not be read. */
  usage: string;
  /** "ok", "skipped" (no token), or why the error count could not be read. */
  errors_check: string;
  /** The highest daily allowance now: {id, percent}. */
  top: { id: string; percent: number } | null;
  /** Keys of the alerts raised by this check (already raised ones are not). */
  raised: string[];
  pushed: { sent: number; failed: number };
}

export function alertAccounts(env: AlertEnv): string[] {
  return (env.ALERT_ACCOUNTS ?? "").split(/[\s,]+/).filter((s) => /^acc_[a-z2-7]{16}$/.test(s));
}

// ---------- text helpers ----------

const fmt = (n: number): string => Math.round(n).toLocaleString("en-US");

function amount(id: MetricId, v: number): string {
  const u = FREE_LIMITS[id].unit;
  if (u === "bytes") return v >= 1e9 ? `${(v / 1e9).toFixed(2)} GB` : `${(v / 1e6).toFixed(1)} MB`;
  if (u === "gbs") return `${fmt(v)} GB-s`;
  return fmt(v);
}

/** "4:30 PM" in Bangladesh time. */
export function bdTime(ms: number): string {
  const d = new Date(ms + BD_OFFSET_MS);
  const h = d.getUTCHours();
  const m = String(d.getUTCMinutes()).padStart(2, "0");
  return `${h % 12 === 0 ? 12 : h % 12}:${m} ${h < 12 ? "AM" : "PM"}`;
}

function inTime(ms: number): string {
  const m = Math.max(0, Math.round(ms / MIN));
  return m >= 60 ? `${Math.floor(m / 60)}h ${String(m % 60).padStart(2, "0")}m` : `${m} min`;
}

const dayKey = (ms: number): string => new Date(ms).toISOString().slice(0, 10);
const monthKey = (ms: number): string => new Date(ms).toISOString().slice(0, 7);

// ---------- the rules (pure: tested on their own) ----------

type Metric = UsageBody["metrics"][number];

/**
 * Usage alerts: every step a metric has reached (each its own key, so a later check doesn't raise a lower one), the
 * text of the highest only; the lower ones are raised silently (`silent`).
 */
export function usageAlerts(metrics: Metric[], now: number): Array<NewAlert & { silent: boolean }> {
  const out: Array<NewAlert & { silent: boolean }> = [];
  const reset = utcDayStart(now) + DAY;
  for (const m of metrics) {
    if (!("used" in m)) continue;
    const id = m.id as MetricId;
    const pct = (m.used / m.limit) * 100;
    const reached = STEPS.filter((s) => pct >= s);
    if (!reached.length) continue;
    const period = m.period === "day" ? dayKey(now) : monthKey(now);
    const top = reached[reached.length - 1];
    for (const s of reached) {
      const shown = Math.min(100, Math.floor(pct));
      const used = `${amount(id, m.used)} of ${amount(id, m.limit)}`;
      let title: string;
      let body: string;
      if (m.period === "day") {
        const when = `the reset at ${bdTime(reset)} Bangladesh time (in ${inTime(reset - now)})`;
        if (s === 100) {
          title = `Out: ${m.label} used up for today`;
          body = `${used} used. Online play can fail until ${when}. The Workers Paid plan ($5 a month) lifts these limits.`;
        } else if (s === 90) {
          title = `Almost out: ${m.label} at ${shown}%`;
          body = `${used} used today. At 100% online play can fail until ${when}.`;
        } else {
          title = `${m.label} at ${shown}% of today's free limit`;
          body = `${used} used today. It resets at ${bdTime(reset)} Bangladesh time (in ${inTime(reset - now)}).`;
        }
      } else {
        title = s === 100 ? `Out: ${m.label} is full` : `${m.label} at ${shown}% of the free limit`;
        body = `${used} stored. This one does not reset: old data has to be deleted, or the plan upgraded.`;
      }
      out.push({
        key: `usage:${id}:${s}:${period}`, level: s >= 90 ? "danger" : "warning", kind: "usage",
        title, body, tag: `alert-${id}`, silent: s !== top,
      });
    }
  }
  return out;
}

/**
 * Pace alerts: at the rate of the last 3 complete hours (the current hour is partial), a daily allowance runs out
 * before the reset. Once a day per metric; not before PACE_MIN_HOURS into the day nor under PACE_MIN_PERCENT used.
 */
export function paceAlerts(body: Pick<UsageBody, "metrics" | "hourly">, now: number): NewAlert[] {
  const day0 = utcDayStart(now);
  const reset = day0 + DAY;
  if (now - day0 < PACE_MIN_HOURS * HOUR) return [];
  const out: NewAlert[] = [];
  for (const m of body.metrics) {
    if (!("used" in m) || m.period !== "day") continue;
    const id = m.id as MetricId;
    const pct = (m.used / m.limit) * 100;
    if (pct < PACE_MIN_PERCENT || pct >= 100) continue;
    const series = ((body.hourly as Record<string, unknown>)[id] as number[] | undefined) ?? [];
    const complete = series.slice(0, -1).slice(-3); // the last entry is the hour now running
    if (!complete.length) continue;
    const perHour = complete.reduce((a, b) => a + b, 0) / complete.length;
    if (perHour <= 0) continue;
    const runsOut = now + ((m.limit - m.used) / perHour) * HOUR;
    if (runsOut >= reset) continue;
    out.push({
      key: `pace:${id}:${dayKey(now)}`, level: "warning", kind: "pace",
      title: `${m.label} will run out today`,
      body: `At the pace of the last ${complete.length === 1 ? "hour" : `${complete.length} hours`} it runs out around ${bdTime(runsOut)} Bangladesh time, before the reset at ${bdTime(reset)}. Now at ${Math.floor(pct)}%.`,
      tag: `alert-${id}`,
    });
  }
  return out;
}

export function errorsAlert(requests: number, errors: number, now: number): NewAlert | null {
  if (errors < ERRORS_MIN || errors < requests * ERRORS_SHARE) return null;
  const share = requests > 0 ? ` (${((errors / requests) * 100).toFixed(1)}% of ${fmt(requests)} requests)` : "";
  const window = `${dayKey(now)}:${Math.floor(new Date(now).getUTCHours() / 6)}`; // at most one push per 6 hours
  return {
    key: `server:errors:${window}`, level: "danger", kind: "server",
    title: `Server errors: ${fmt(errors)} in the last hour`,
    body: `${fmt(errors)} failed${share}. Look at Events on the admin console and the Worker's logs on Cloudflare.`,
    tag: "alert-errors",
  };
}

// ---------- D1 ----------

async function getState(db: D1Database, key: string): Promise<string | null> {
  const r = await db.prepare("SELECT value FROM alert_state WHERE key = ?").bind(key).first<{ value: string }>();
  return r?.value ?? null;
}

function setState(db: D1Database, key: string, value: string, now: number): D1PreparedStatement {
  return db
    .prepare("INSERT INTO alert_state (key, value, at) VALUES (?, ?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value, at = excluded.at")
    .bind(key, value, now);
}

/** Inserts the alerts whose key is new; returns those (the others were raised before). */
/** `read`: stored as already read (the lower steps passed on the way to a higher one: not in the banner). */
async function raise(db: D1Database, list: NewAlert[], now: number, read = false): Promise<Array<NewAlert & { id: number }>> {
  if (!list.length) return [];
  const rs = await db.batch(
    list.map((a) =>
      db.prepare("INSERT OR IGNORE INTO alerts (key, at, level, kind, title, body, read_at) VALUES (?, ?, ?, ?, ?, ?, ?) RETURNING id")
        .bind(a.key, now, a.level, a.kind, a.title, a.body, read ? now : null),
    ),
  );
  const out: Array<NewAlert & { id: number }> = [];
  rs.forEach((r, k) => {
    const id = (r.results?.[0] as { id?: number } | undefined)?.id;
    if (id !== undefined) out.push({ ...list[k], id });
  });
  return out;
}

/** Pushes `list` to the alert accounts (one push each, or one for all when there are many) and stores the results. */
async function deliver(env: AEnv, list: Array<NewAlert & { id: number }>): Promise<{ sent: number; failed: number }> {
  const total = { sent: 0, failed: 0 };
  const accounts = alertAccounts(env);
  if (!list.length || !accounts.length || !P.pushConfigured(env)) return total;
  const order = { danger: 0, warning: 1, info: 2 };
  const sorted = [...list].sort((a, b) => order[a.level] - order[b.level]);
  const notes: Array<{ ids: number[]; note: P.Note }> =
    sorted.length <= PUSH_SINGLY
      ? sorted.map((a) => ({ ids: [a.id], note: note(a.title, a.body, a.tag, a.kind === "summary") }))
      : [{
          ids: sorted.map((a) => a.id),
          note: note(`${sorted.length} server alerts`, sorted.map((a) => a.title).join(" · ").slice(0, 400), "alert-many", false),
        }];
  const stmts: D1PreparedStatement[] = [];
  for (const { ids, note: n } of notes) {
    let sent = 0;
    let failed = 0;
    for (const acc of accounts) {
      const r = await P.pushAccount(env, acc, n, { pref: null, count: false });
      sent += r.sent;
      failed += r.failed;
    }
    total.sent += sent;
    total.failed += failed;
    for (const id of ids) stmts.push(env.DB.prepare("UPDATE alerts SET sent = ?, failed = ? WHERE id = ?").bind(sent, failed, id));
  }
  if (stmts.length) await env.DB.batch(stmts);
  return total;
}

function note(title: string, body: string, tag: string, summary: boolean): P.Note {
  return {
    kind: "alert", title: title.slice(0, 120), body: body.slice(0, 400), link: "home", channel: "game", tag,
    ttl_s: summary ? P.DAY_TTL_S : 6 * 3600, priority: "high",
  };
}

// ---------- the summary ----------

/** Yesterday (UTC day, 06:00 to 06:00 Bangladesh time): players, new accounts, online matches, crashes, the peak use. */
export async function summaryAlert(db: D1Database, usage: UsageBody | null, now: number): Promise<NewAlert> {
  const to = utcDayStart(now);
  const from = to - DAY;
  const r = await db
    .prepare(
      `SELECT
         (SELECT COUNT(*) FROM accounts WHERE last_seen >= ?) AS active,
         (SELECT COUNT(*) FROM accounts WHERE created_at >= ? AND created_at < ?) AS fresh,
         (SELECT COUNT(*) FROM matches WHERE started_at >= ? AND started_at < ?) AS matches,
         (SELECT COUNT(*) FROM crash_reports WHERE received_at >= ? AND received_at < ?) AS crashes,
         (SELECT COUNT(DISTINCT pid) FROM crash_reports WHERE received_at >= ? AND received_at < ?) AS crash_devices`,
    )
    .bind(now - DAY, from, to, from, to, from, to, from, to)
    .first<{ active: number; fresh: number; matches: number; crashes: number; crash_devices: number }>();
  const n = r ?? { active: 0, fresh: 0, matches: 0, crashes: 0, crash_devices: 0 };
  const plural = (k: number, one: string, many = one + "s") => `${fmt(k)} ${k === 1 ? one : many}`;
  const parts = [
    `${plural(n.active, "player")} in the last 24 hours`,
    `${plural(n.fresh, "new account")}`,
    `${plural(n.matches, "online match", "online matches")}`,
    n.crashes ? `${plural(n.crashes, "crash report")} from ${plural(n.crash_devices, "phone")}` : "no crash reports",
  ];
  let peak = "";
  const y = usage?.daily.find((d) => d.day === dayKey(from));
  if (y) {
    let best: { label: string; pct: number } | null = null;
    for (const [id, L] of Object.entries(FREE_LIMITS)) {
      if (L.period !== "day") continue;
      const pct = (Number(y[id]) / L.limit) * 100;
      if (!best || pct > best.pct) best = { label: L.label, pct };
    }
    if (best) peak = ` Highest free limit yesterday: ${best.label} at ${best.pct < 1 && best.pct > 0 ? "<1" : Math.round(best.pct)}%.`;
  }
  return {
    key: `summary:${dayKey(from)}`, level: "info", kind: "summary",
    title: "Ludo Zing yesterday",
    body: `${parts.join(", ")}.${peak}`,
    tag: "alert-summary",
  };
}

// ---------- the check ----------

/** One run of the 15-minute check (also POST /admin/api/alerts/check). Never throws for Cloudflare / push trouble. */
export async function checkAlerts(env: AEnv, now = Date.now()): Promise<CheckResult> {
  const db = env.DB;
  const list: NewAlert[] = [];
  const silent: NewAlert[] = [];
  let usage: UsageBody | null = null;
  let usageMsg = "ok";
  let errorsMsg = "skipped";
  let top: CheckResult["top"] = null;

  if (!env.CF_API_TOKEN) {
    usageMsg = "CF_API_TOKEN is not set";
  } else {
    try {
      usage = await usageSnapshot(env, now);
    } catch (e) {
      if (!(e instanceof CloudflareError)) throw e;
      usageMsg = e.message;
    }
  }
  const fails = usage ? 0 : Number((await getState(db, "usage_fails")) ?? 0) + 1;
  if (usage) {
    for (const a of usageAlerts(usage.metrics, now)) (a.silent ? silent : list).push(a);
    list.push(...paceAlerts(usage, now));
    for (const m of usage.metrics) {
      if (m.period === "day" && "percent" in m && (!top || m.percent > top.percent)) top = { id: m.id, percent: m.percent };
    }
  } else if (fails >= USAGE_FAILS) {
    list.push({
      key: `server:usage_read:${dayKey(now)}`, level: "warning", kind: "server",
      title: "Can't check the server's free limits",
      body: `Reading Cloudflare's usage failed ${fails} times in a row (${usageMsg}). Until it works there are no warnings before a limit runs out.`,
      tag: "alert-usage-read",
    });
  }

  // server errors: Cloudflare's count (best effort) + the Worker errors logged in D1 events
  const logged = await db
    .prepare("SELECT COUNT(*) AS n FROM events WHERE at >= ? AND level = 'error'")
    .bind(now - HOUR)
    .first<{ n: number }>();
  let requests = 0;
  let errors = logged?.n ?? 0;
  if (env.CF_API_TOKEN) {
    try {
      const cf = await cloudflareErrors(env, now);
      requests = cf.requests;
      errors += cf.errors;
      errorsMsg = "ok";
    } catch (e) {
      if (!(e instanceof CloudflareError)) throw e;
      errorsMsg = e.message;
    }
  }
  const ea = errorsAlert(requests, errors, now);
  if (ea) list.push(ea);

  // push failing today
  const pe = await db
    .prepare("SELECT COALESCE(SUM(sent), 0) AS sent, COALESCE(SUM(failed), 0) AS failed FROM push_events WHERE day = ?")
    .bind(D.utcDay(now))
    .first<{ sent: number; failed: number }>();
  if (pe && pe.failed >= PUSH_FAILED_MIN && pe.failed > pe.sent) {
    list.push({
      key: `server:push:${dayKey(now)}`, level: "warning", kind: "server",
      title: "Push notifications are failing",
      body: `${fmt(pe.failed)} of ${fmt(pe.sent + pe.failed)} pushes failed today. Check the Firebase service account (FCM_SERVICE_ACCOUNT) and the Notifications page.`,
      tag: "alert-push",
    });
  }

  // yesterday's summary, from 09:00 Bangladesh time
  if (now - utcDayStart(now) >= SUMMARY_HOUR_UTC * HOUR) {
    const key = `summary:${dayKey(utcDayStart(now) - DAY)}`;
    const had = await db.prepare("SELECT 1 AS x FROM alerts WHERE key = ?").bind(key).first();
    if (!had) list.push(await summaryAlert(db, usage, now));
  }

  await raise(db, silent, now, true);
  const fresh = await raise(db, list, now);
  const pushed = await deliver(env, fresh).catch((e) => (console.error("alert push failed:", e), { sent: 0, failed: 0 }));
  const result: CheckResult = { at: now, usage: usageMsg, errors_check: errorsMsg, top, raised: fresh.map((a) => a.key), pushed };
  await db.batch([setState(db, "usage_fails", String(fails), now), setState(db, "last_check", JSON.stringify(result), now)]);
  if (fresh.length) console.log(`alerts: raised ${result.raised.join(", ")}; pushed ${pushed.sent} (${pushed.failed} failed)`);
  return result;
}

/** A test alert to the alert accounts (POST /admin/api/alerts/test). */
export async function testAlert(env: AEnv, now = Date.now()): Promise<{ sent: number; failed: number; accounts: number }> {
  const a: NewAlert = {
    key: `test:${now}`, level: "info", kind: "test",
    title: "Test alert", body: "Server alerts reach this phone. Nothing is wrong.", tag: "alert-test",
  };
  const fresh = await raise(env.DB, [a], now);
  const r = await deliver(env, fresh);
  return { ...r, accounts: alertAccounts(env).length };
}

// ---------- the console (GET /admin/api/alerts, POST /admin/api/alerts/read) ----------

export interface AlertRow {
  id: number;
  key: string;
  at: number;
  level: Level;
  kind: Kind;
  title: string;
  body: string;
  sent: number;
  failed: number;
  read_at: number | null;
}

/** Newest first, `limit` (1-200) after `before` (an id). */
export async function listAlerts(db: D1Database, limit: number, before: number | null): Promise<{ items: AlertRow[]; next: string | null }> {
  const { results } = await db
    .prepare(`SELECT * FROM alerts ${before ? "WHERE id < ?" : ""} ORDER BY id DESC LIMIT ?`)
    .bind(...(before ? [before, limit + 1] : [limit + 1]))
    .all<AlertRow>();
  const items = results.slice(0, limit);
  return { items, next: results.length > limit ? String(items[items.length - 1].id) : null };
}

/** Unread warnings / dangers (the console's banner) and the check's state. */
export async function alertStatus(env: AEnv): Promise<Record<string, unknown>> {
  const db = env.DB;
  const ids = alertAccounts(env);
  const [unread, last, accs] = await db.batch([
    db.prepare("SELECT COUNT(*) AS n, COALESCE(SUM(level = 'danger'), 0) AS danger FROM alerts WHERE read_at IS NULL AND level != 'info'"),
    db.prepare("SELECT value, at FROM alert_state WHERE key = 'last_check'"),
    db.prepare(
      `SELECT a.id, a.name, (SELECT COUNT(*) FROM push_tokens t WHERE t.account_id = a.id) AS devices FROM accounts a
       WHERE a.id IN (${ids.map(() => "?").join(", ") || "NULL"})`,
    ).bind(...ids),
  ]);
  const u = unread.results[0] as { n: number; danger: number };
  const l = last.results[0] as { value: string } | undefined;
  const found = accs.results as Array<{ id: string; name: string; devices: number }>;
  return {
    unread: u.n,
    unread_danger: u.danger,
    last_check: l ? JSON.parse(l.value) : null,
    every_min: 15,
    steps: STEPS,
    push_configured: P.pushConfigured(env),
    accounts: ids.map((id) => found.find((a) => a.id === id) ?? { id, name: null, devices: 0, missing: true }),
  };
}

export async function markRead(db: D1Database, now: number): Promise<number> {
  const r = await db.prepare("UPDATE alerts SET read_at = ? WHERE read_at IS NULL").bind(now).run();
  return r.meta.changes ?? 0;
}

export async function pruneAlerts(db: D1Database, now: number): Promise<number> {
  const r = await db.prepare("DELETE FROM alerts WHERE at < ?").bind(now - KEEP_DAYS * DAY).run();
  return r.meta.changes ?? 0;
}
