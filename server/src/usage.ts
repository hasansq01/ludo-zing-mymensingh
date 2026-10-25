// The admin console's Usage page (GET /admin/api/usage, ADMIN_API.md): today's use of the Cloudflare Workers Free
// allowances, read from the Cloudflare GraphQL Analytics API. Free-plan limits are per ACCOUNT, not per Worker, so the
// totals cover every Worker / Durable Object / D1 database of the account; `mine` is this Worker's share.
// Every HTTP call goes through `cfFetch`, which tests replace with setCloudflareFetcher() (a fake Cloudflare).
import type { Env } from "./room";

export const GRAPHQL_URL = "https://api.cloudflare.com/client/v4/graphql";
export const ACCOUNT_ID = "cd708edb210d36f6f898127f0373d124"; // hrdev.main (tools/cf.sh); env CF_ACCOUNT_ID overrides
export const WORKER_NAME = "ludo-zing-rooms"; // wrangler.jsonc "name"
export const CACHE_MS = 5 * 60_000;
const TIMEOUT_MS = 8000;
const HOUR = 3_600_000;
const DAY = 24 * HOUR;

export type Fetcher = (input: string, init?: RequestInit) => Promise<Response>;

let cfFetch: Fetcher = (input, init) => fetch(input, init);

/** Tests: route the Cloudflare API to a fake. `null` restores the real fetch. */
export function setCloudflareFetcher(f: Fetcher | null): void {
  cfFetch = f ?? ((input, init) => fetch(input, init));
}

/** Secret CF_API_TOKEN: an API token with "Account Analytics: Read". Unset: the endpoint answers configured:false. */
export interface UsageEnv {
  CF_API_TOKEN?: string;
  CF_ACCOUNT_ID?: string;
}

export type MetricId =
  | "workers_requests"
  | "do_requests"
  | "do_duration"
  | "do_rows_read"
  | "do_rows_written"
  | "do_storage"
  | "d1_rows_read"
  | "d1_rows_written"
  | "d1_storage";

export type Unit = "count" | "gbs" | "bytes";

/**
 * Workers Free plan allowances. Checked 2026-10-25 against:
 *  - Workers limits (daily request limit 100,000, resets 00:00 UTC; 10 ms CPU, 50 subrequests per invocation):
 *    https://developers.cloudflare.com/workers/platform/limits/
 *  - Durable Objects pricing (Free: 100,000 requests, 13,000 GB-s duration, 5 M SQLite rows read, 100,000 rows
 *    written per day, reset 00:00 UTC; 5 GB SQLite stored data; incoming WebSocket messages count 20:1):
 *    https://developers.cloudflare.com/durable-objects/platform/pricing/
 *  - D1 pricing (Free: 5 M rows read and 100,000 rows written per day, reset 00:00 UTC, 5 GB total storage):
 *    https://developers.cloudflare.com/d1/platform/pricing/
 *  - D1 limits (Free: 500 MB per database, 10 databases, 50 queries per invocation):
 *    https://developers.cloudflare.com/d1/platform/limits/
 * GB / MB are decimal (10^9 / 10^6 bytes). `period: "total"` limits are not daily: they do not reset.
 */
export const FREE_LIMITS: Record<MetricId, { label: string; group: "workers" | "do" | "d1"; unit: Unit; period: "day" | "total"; limit: number; note: string }> = {
  workers_requests: { label: "Workers requests", group: "workers", unit: "count", period: "day", limit: 100_000, note: "HTTP requests and cron runs that start the Worker, all Workers of the account." },
  do_requests: { label: "Durable Object requests", group: "do", unit: "count", period: "day", limit: 100_000, note: "Fetches, RPC calls and alarms; incoming WebSocket messages count 20 to 1." },
  do_duration: { label: "Durable Object duration", group: "do", unit: "gbs", period: "day", limit: 13_000, note: "GB-seconds of wall-clock time (128 MB per object) while an object is awake and not hibernating." },
  do_rows_read: { label: "Durable Object rows read", group: "do", unit: "count", period: "day", limit: 5_000_000, note: "SQLite rows read by Durable Objects." },
  do_rows_written: { label: "Durable Object rows written", group: "do", unit: "count", period: "day", limit: 100_000, note: "SQLite rows written by Durable Objects (deletes and alarms included)." },
  do_storage: { label: "Durable Object storage", group: "do", unit: "bytes", period: "total", limit: 5_000_000_000, note: "SQLite data stored by Durable Objects, account total. Does not reset." },
  d1_rows_read: { label: "D1 rows read", group: "d1", unit: "count", period: "day", limit: 5_000_000, note: "Rows scanned by D1 queries, all databases of the account." },
  d1_rows_written: { label: "D1 rows written", group: "d1", unit: "count", period: "day", limit: 100_000, note: "Rows changed by D1 writes (an index adds one per write)." },
  d1_storage: { label: "D1 database size", group: "d1", unit: "bytes", period: "total", limit: 500_000_000, note: "Largest D1 database against the 500 MB per-database limit. Does not reset." },
};

/** Per-request limits (not daily): shown as information only. */
export const PER_REQUEST_LIMITS = [
  { label: "Worker CPU time", value: "10 ms per request" },
  { label: "Subrequests per invocation", value: "50" },
  { label: "D1 queries per invocation", value: "50" },
  { label: "D1 total storage (account)", value: "5 GB" },
];

const METRICS = Object.keys(FREE_LIMITS) as MetricId[];
const DAILY = METRICS.filter((m) => FREE_LIMITS[m].period === "day");
type DailyId = Exclude<MetricId, "do_storage" | "d1_storage">;

/** The one GraphQL request: the last 7 UTC days by hour (today's chart and the daily history come from the same rows). */
export const QUERY = `query Usage($accountTag: string!, $start: Time!, $end: Time!, $storageFrom: Date!) {
  viewer {
    accounts(filter: { accountTag: $accountTag }) {
      workers: workersInvocationsAdaptive(limit: 10000, filter: { datetime_geq: $start, datetime_lt: $end }) {
        sum { requests }
        dimensions { datetimeHour scriptName }
      }
      doInvocations: durableObjectsInvocationsAdaptiveGroups(limit: 10000, filter: { datetime_geq: $start, datetime_lt: $end }) {
        sum { requests }
        dimensions { datetimeHour scriptName type }
      }
      doPeriodic: durableObjectsPeriodicGroups(limit: 10000, filter: { datetime_geq: $start, datetime_lt: $end }) {
        sum { duration rowsRead rowsWritten }
        dimensions { datetimeHour }
      }
      doStorage: durableObjectsStorageGroups(limit: 2, filter: { date_geq: $storageFrom }, orderBy: [date_DESC]) {
        max { storedBytes }
        dimensions { date }
      }
      d1: d1AnalyticsAdaptiveGroups(limit: 10000, filter: { datetime_geq: $start, datetime_lt: $end }) {
        sum { rowsRead rowsWritten }
        dimensions { datetimeHour }
      }
      d1Storage: d1StorageAdaptiveGroups(limit: 100, filter: { date_geq: $storageFrom }, orderBy: [date_DESC]) {
        max { databaseSizeBytes }
        dimensions { databaseId date }
      }
    }
  }
}`;

/** Incoming WebSocket messages of hibernating objects are listed as invocations but billed 20 to 1. */
const WS_MESSAGE = /message/i;
const WS_MESSAGE_RATIO = 20;

// ---------- time ----------

export function utcDayStart(now: number): number {
  return Math.floor(now / DAY) * DAY;
}

const dayKey = (ms: number): string => new Date(ms).toISOString().slice(0, 10);

// ---------- Cloudflare ----------

interface Row<S, D> {
  sum?: S;
  max?: S;
  dimensions: D;
}
interface Account {
  workers: Array<Row<{ requests: number }, { datetimeHour: string; scriptName: string }>>;
  doInvocations: Array<Row<{ requests: number }, { datetimeHour: string; scriptName: string; type: string }>>;
  doPeriodic: Array<Row<{ duration: number; rowsRead: number; rowsWritten: number }, { datetimeHour: string }>>;
  doStorage: Array<Row<{ storedBytes: number }, { date: string }>>;
  d1: Array<Row<{ rowsRead: number; rowsWritten: number }, { datetimeHour: string }>>;
  d1Storage: Array<Row<{ databaseSizeBytes: number }, { databaseId: string; date: string }>>;
}

export class CloudflareError extends Error {}

async function graphql(token: string, accountId: string, now: number): Promise<Account> {
  const start = utcDayStart(now) - 6 * DAY;
  const variables = {
    accountTag: accountId,
    start: new Date(start).toISOString(),
    end: new Date(utcDayStart(now) + DAY).toISOString(),
    storageFrom: dayKey(utcDayStart(now) - DAY),
  };
  const ac = new AbortController();
  const t = setTimeout(() => ac.abort(), TIMEOUT_MS);
  let res: Response;
  try {
    res = await cfFetch(GRAPHQL_URL, {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify({ query: QUERY, variables }),
      signal: ac.signal,
    });
  } catch (e) {
    throw new CloudflareError(`Cloudflare did not answer (${e instanceof Error ? e.message : "network"})`);
  } finally {
    clearTimeout(t);
  }
  let body: { data?: { viewer?: { accounts?: Account[] } }; errors?: Array<{ message?: string }> } | null = null;
  try {
    body = await res.json();
  } catch {
    /* not JSON */
  }
  if (!res.ok || body?.errors?.length) {
    const why = body?.errors?.map((e) => e.message).filter(Boolean).join("; ") || `HTTP ${res.status}`;
    throw new CloudflareError(`Cloudflare Analytics API: ${why}`);
  }
  const acc = body?.data?.viewer?.accounts?.[0];
  if (!acc) throw new CloudflareError("Cloudflare Analytics API: no data for this account (check the token's account)");
  return acc;
}

// ---------- aggregation ----------

type Hourly = Record<DailyId, Map<number, number>>;

function add(m: Map<number, number>, hour: string, v: number | undefined): void {
  const t = Date.parse(hour);
  if (!Number.isFinite(t) || !v) return;
  m.set(t, (m.get(t) ?? 0) + v);
}

/** Per-hour sums of every daily metric, plus this Worker's own share of the request counts. */
export function aggregate(a: Account, worker: string): { hourly: Hourly; mine: { workers_requests: Map<number, number>; do_requests: Map<number, number> }; doByType: Record<string, number> } {
  const hourly = Object.fromEntries(DAILY.map((m) => [m, new Map<number, number>()])) as Hourly;
  const mine = { workers_requests: new Map<number, number>(), do_requests: new Map<number, number>() };
  const doByType: Record<string, number> = {};
  for (const r of a.workers ?? []) {
    add(hourly.workers_requests, r.dimensions.datetimeHour, r.sum?.requests);
    if (r.dimensions.scriptName === worker) add(mine.workers_requests, r.dimensions.datetimeHour, r.sum?.requests);
  }
  for (const r of a.doInvocations ?? []) {
    const w = WS_MESSAGE.test(r.dimensions.type ?? "") ? 1 / WS_MESSAGE_RATIO : 1;
    const v = (r.sum?.requests ?? 0) * w;
    add(hourly.do_requests, r.dimensions.datetimeHour, v);
    if (r.dimensions.scriptName === worker) add(mine.do_requests, r.dimensions.datetimeHour, v);
    doByType[r.dimensions.type ?? ""] = (doByType[r.dimensions.type ?? ""] ?? 0) + (r.sum?.requests ?? 0);
  }
  for (const r of a.doPeriodic ?? []) {
    add(hourly.do_duration, r.dimensions.datetimeHour, r.sum?.duration);
    add(hourly.do_rows_read, r.dimensions.datetimeHour, r.sum?.rowsRead);
    add(hourly.do_rows_written, r.dimensions.datetimeHour, r.sum?.rowsWritten);
  }
  for (const r of a.d1 ?? []) {
    add(hourly.d1_rows_read, r.dimensions.datetimeHour, r.sum?.rowsRead);
    add(hourly.d1_rows_written, r.dimensions.datetimeHour, r.sum?.rowsWritten);
  }
  return { hourly, mine, doByType };
}

const round = (v: number, d = 0): number => {
  const k = 10 ** d;
  return Math.round(v * k) / k;
};

export const levelOf = (percent: number): "ok" | "warning" | "danger" => (percent >= 90 ? "danger" : percent >= 70 ? "warning" : "ok");

function metric(id: MetricId, used: number, mine?: number) {
  const L = FREE_LIMITS[id];
  const u = L.unit === "gbs" ? round(used, 2) : Math.ceil(used - 1e-9);
  const percent = Math.min(100, round((used / L.limit) * 100, 1));
  return {
    id, label: L.label, group: L.group, unit: L.unit, period: L.period, used: u, limit: L.limit,
    left: Math.max(0, round(L.limit - used, L.unit === "gbs" ? 2 : 0)), percent, level: levelOf((used / L.limit) * 100), note: L.note,
    ...(mine === undefined ? {} : { mine: L.unit === "gbs" ? round(mine, 2) : Math.ceil(mine - 1e-9) }),
  };
}

/** Today's matches, and the 7 days' (D1 `matches`): the base of the "games left" estimate. */
async function matchCounts(db: D1Database, now: number): Promise<{ today: number; week: number }> {
  const today = utcDayStart(now);
  const r = await db
    .prepare("SELECT COALESCE(SUM(started_at >= ?), 0) AS today, COUNT(*) AS week FROM matches WHERE started_at >= ?")
    .bind(today, today - 6 * DAY)
    .first<{ today: number; week: number }>();
  return { today: r?.today ?? 0, week: r?.week ?? 0 };
}

const ESTIMATE_MIN_TODAY = 5;

/** ~games left today: for each daily metric, what is left over the cost of one game so far; the tightest metric wins. */
export function estimateGames(
  metrics: Array<{ id: MetricId; left: number }>,
  usage: { today: Record<string, number>; week: Record<string, number> },
  matches: { today: number; week: number },
) {
  const useToday = matches.today >= ESTIMATE_MIN_TODAY;
  const n = useToday ? matches.today : matches.week;
  const basis = useToday ? usage.today : usage.week;
  if (n < 1) return { games_left: null, basis: null, matches: n, limiting: null, per_game: {} as Record<string, number> };
  const per_game: Record<string, number> = {};
  let games = Infinity;
  let limiting: string | null = null;
  for (const m of metrics) {
    const cost = (basis[m.id] ?? 0) / n;
    if (cost <= 0) continue;
    per_game[m.id] = round(cost, 2);
    const g = m.left / cost;
    if (g < games) { games = g; limiting = m.id; }
  }
  return {
    games_left: Number.isFinite(games) ? Math.floor(games) : null,
    basis: useToday ? "today" : "7d",
    matches: n,
    limiting,
    per_game,
  };
}

// ---------- report ----------

export function nextReset(now: number): string {
  return new Date(utcDayStart(now) + DAY).toISOString();
}

function limitsOnly() {
  return METRICS.map((id) => {
    const L = FREE_LIMITS[id];
    return { id, label: L.label, group: L.group, unit: L.unit, period: L.period, limit: L.limit, note: L.note };
  });
}

async function build(env: UsageEnv, db: D1Database, now: number) {
  const accountId = env.CF_ACCOUNT_ID || ACCOUNT_ID;
  const [acc, matches] = await Promise.all([graphql(env.CF_API_TOKEN!, accountId, now), matchCounts(db, now)]);
  const { hourly, mine, doByType } = aggregate(acc, WORKER_NAME);

  const today0 = utcDayStart(now);
  const sumFrom = (m: Map<number, number>, from: number) => {
    let s = 0;
    for (const [t, v] of m) if (t >= from && t < today0 + DAY) s += v;
    return s;
  };
  const todayOf = Object.fromEntries(DAILY.map((m) => [m, sumFrom(hourly[m as DailyId], today0)])) as Record<DailyId, number>;
  const weekOf = Object.fromEntries(DAILY.map((m) => [m, sumFrom(hourly[m as DailyId], today0 - 6 * DAY)])) as Record<DailyId, number>;

  const latest = (rows: Array<{ date: string; v: number }>) => (rows.length ? rows.reduce((a, b) => (b.date > a.date ? b : a)).v : 0);
  const doStored = latest((acc.doStorage ?? []).map((r) => ({ date: r.dimensions.date, v: r.max?.storedBytes ?? 0 })));
  const perDb = new Map<string, { date: string; v: number }>();
  for (const r of acc.d1Storage ?? []) {
    const cur = perDb.get(r.dimensions.databaseId);
    if (!cur || r.dimensions.date > cur.date) perDb.set(r.dimensions.databaseId, { date: r.dimensions.date, v: r.max?.databaseSizeBytes ?? 0 });
  }
  const d1Sizes = [...perDb.values()].map((x) => x.v);
  const d1Largest = d1Sizes.length ? Math.max(...d1Sizes) : 0;
  const d1Total = d1Sizes.reduce((a, b) => a + b, 0);

  const list = METRICS.map((id) => {
    if (id === "do_storage") return metric(id, doStored);
    if (id === "d1_storage") return { ...metric(id, d1Largest), total_bytes: d1Total, databases: d1Sizes.length };
    const mm = id === "workers_requests" || id === "do_requests" ? sumFrom(mine[id], today0) : undefined;
    return metric(id, todayOf[id], mm);
  });

  const hours: string[] = [];
  const series = Object.fromEntries(DAILY.map((m) => [m, [] as number[]])) as Record<DailyId, number[]>;
  for (let t = today0; t <= Math.floor(now / HOUR) * HOUR; t += HOUR) {
    hours.push(new Date(t).toISOString());
    for (const m of DAILY) series[m as DailyId].push(round(hourly[m as DailyId].get(t) ?? 0, m === "do_duration" ? 2 : 0));
  }
  const daily = [];
  for (let d = today0 - 6 * DAY; d <= today0; d += DAY) {
    const e: Record<string, string | number> = { day: dayKey(d) };
    for (const m of DAILY) {
      let s = 0;
      for (let t = d; t < d + DAY; t += HOUR) s += hourly[m as DailyId].get(t) ?? 0;
      e[m] = m === "do_duration" ? round(s, 2) : Math.ceil(s - 1e-9);
    }
    daily.push(e);
  }

  const daily_list = list.filter((m) => m.period === "day");
  return {
    configured: true,
    now,
    cached_at: now,
    stale: false,
    reset_at: nextReset(now),
    account_id: accountId,
    worker: WORKER_NAME,
    metrics: list,
    hourly: { hours, ...series },
    daily,
    estimate: estimateGames(daily_list, { today: todayOf, week: weekOf }, matches),
    do_requests_by_type: doByType,
    info: PER_REQUEST_LIMITS,
    sampling: "Cloudflare's adaptive analytics are sampled: the numbers track the real usage closely but can differ slightly from the dashboard's billing figures.",
  };
}

// ---------- cache (per isolate; 5 minutes) ----------

let cached: { at: number; body: Awaited<ReturnType<typeof build>> } | null = null;

export function resetUsageCache(): void {
  cached = null;
}

/** The body of GET /admin/api/usage, or the failure to answer with. */
export async function usageReport(env: Env & UsageEnv, now: number): Promise<{ status: number; body: Record<string, unknown> }> {
  if (!env.CF_API_TOKEN) {
    return {
      status: 200,
      body: {
        configured: false, now, reset_at: nextReset(now), account_id: env.CF_ACCOUNT_ID || ACCOUNT_ID, worker: WORKER_NAME,
        metrics: limitsOnly(), info: PER_REQUEST_LIMITS,
        setup: {
          secret: "CF_API_TOKEN",
          permission: "Account > Account Analytics > Read",
          steps: [
            "Cloudflare dashboard > My Profile > API Tokens > Create Token > Create Custom Token.",
            "Permissions: Account, Account Analytics, Read. Account Resources: Include > the account of this Worker.",
            "Create the token and copy it once.",
            "In server/: tools/cf.sh secret put CF_API_TOKEN (paste the token), then reload this page.",
          ],
        },
      },
    };
  }
  if (cached && now - cached.at < CACHE_MS && now >= cached.at) return { status: 200, body: cached.body };
  try {
    const body = await build(env, env.DB, now);
    cached = { at: now, body };
    return { status: 200, body };
  } catch (e) {
    if (!(e instanceof CloudflareError)) throw e;
    // Cloudflare is down or refused: the last good numbers (marked stale) beat an empty page.
    if (cached && utcDayStart(cached.at) === utcDayStart(now)) return { status: 200, body: { ...cached.body, stale: true, error_msg: e.message } };
    return { status: 502, body: { error: "cloudflare_failed", msg: e.message } };
  }
}
