// Admin usage page API (ADMIN_API.md "Usage"): the Cloudflare GraphQL query's shape, the aggregation into used / limit /
// left / percent, the UTC day boundary, the 20:1 WebSocket message weight, the games-left estimate, the 5 minute cache,
// the stale fallback, "not configured" and auth. Cloudflare is a fake (setCloudflareFetcher).
import { createExecutionContext, env, waitOnExecutionContext } from "cloudflare:test";
import { afterAll, beforeEach, describe, expect, it } from "vitest";
import worker from "../src/index";
import type { Env } from "../src/room";
import { CACHE_MS, FREE_LIMITS, GRAPHQL_URL, QUERY, WORKER_NAME, estimateGames, resetUsageCache, setCloudflareFetcher, usageReport, type UsageEnv } from "../src/usage";
import { api, call, DB, login, type Json } from "./admin_helpers";

const HOUR = 3_600_000;
const DAY = 24 * HOUR;
const NOW = Date.parse("2026-10-25T14:30:00Z");
const TODAY = Date.parse("2026-10-25T00:00:00Z");
const E = { ...(env as unknown as Env), CF_API_TOKEN: "tok_test" } as Env & UsageEnv;
const iso = (t: number) => new Date(t).toISOString();

interface Call {
  url: string;
  auth: string | null;
  query: string;
  variables: Json;
}

/** A fake Cloudflare: answers the one GraphQL query with rows built from `rows(variables)`. */
function fakeCloudflare(rows: (v: Json) => Json, status = 200, errors?: Array<{ message: string }>) {
  const calls: Call[] = [];
  setCloudflareFetcher(async (url, init) => {
    const b = JSON.parse(String(init?.body));
    calls.push({ url, auth: new Headers(init?.headers).get("Authorization"), query: b.query, variables: b.variables });
    if (errors) return Response.json({ data: null, errors }, { status });
    if (status !== 200) return Response.json({}, { status });
    return Response.json({ data: { viewer: { accounts: [rows(b.variables)] } } });
  });
  return calls;
}

const empty = (): Json => ({ workers: [], doInvocations: [], doPeriodic: [], doStorage: [], d1: [], d1Storage: [] });

/** Usage: yesterday's last hour (must not count today), today 00:00 and 13:00 (UTC). */
function sample(): Json {
  const a = empty();
  const ours = WORKER_NAME;
  a.workers = [
    { sum: { requests: 900 }, dimensions: { datetimeHour: iso(TODAY - HOUR), scriptName: ours } },
    { sum: { requests: 1000 }, dimensions: { datetimeHour: iso(TODAY), scriptName: ours } },
    { sum: { requests: 500 }, dimensions: { datetimeHour: iso(TODAY), scriptName: "other-worker" } },
    { sum: { requests: 2000 }, dimensions: { datetimeHour: iso(TODAY + 13 * HOUR), scriptName: ours } },
  ];
  a.doInvocations = [
    { sum: { requests: 7000 }, dimensions: { datetimeHour: iso(TODAY - HOUR), scriptName: ours, type: "fetch" } },
    { sum: { requests: 4000 }, dimensions: { datetimeHour: iso(TODAY + 13 * HOUR), scriptName: ours, type: "fetch" } },
    { sum: { requests: 1000 }, dimensions: { datetimeHour: iso(TODAY + 13 * HOUR), scriptName: ours, type: "alarm" } },
    // incoming WebSocket messages (hibernation): 20 to 1
    { sum: { requests: 40000 }, dimensions: { datetimeHour: iso(TODAY + 13 * HOUR), scriptName: ours, type: "webSocketMessage" } },
  ];
  a.doPeriodic = [
    { sum: { duration: 100.5, rowsRead: 1000, rowsWritten: 200 }, dimensions: { datetimeHour: iso(TODAY - HOUR) } },
    { sum: { duration: 6500.25, rowsRead: 2_500_000, rowsWritten: 50_000 }, dimensions: { datetimeHour: iso(TODAY + 13 * HOUR) } },
  ];
  a.doStorage = [
    { max: { storedBytes: 1_000_000 }, dimensions: { date: "2026-10-24" } },
    { max: { storedBytes: 2_000_000 }, dimensions: { date: "2026-10-25" } },
  ];
  a.d1 = [
    { sum: { rowsRead: 4_000_000, rowsWritten: 90_000 }, dimensions: { datetimeHour: iso(TODAY + 13 * HOUR) } },
    { sum: { rowsRead: 9, rowsWritten: 9 }, dimensions: { datetimeHour: iso(TODAY - 5 * HOUR) } },
  ];
  a.d1Storage = [
    { max: { databaseSizeBytes: 100_000_000 }, dimensions: { databaseId: "db1", date: "2026-10-24" } },
    { max: { databaseSizeBytes: 450_000_000 }, dimensions: { databaseId: "db1", date: "2026-10-25" } },
    { max: { databaseSizeBytes: 5_000_000 }, dimensions: { databaseId: "db2", date: "2026-10-25" } },
  ];
  return a;
}

const metric = (b: Json, id: string): Json => b.metrics.find((m: Json) => m.id === id);

beforeEach(async () => {
  resetUsageCache();
  await DB.prepare("DELETE FROM matches").run();
});
afterAll(() => setCloudflareFetcher(null));

describe("usage: the Cloudflare query", () => {
  it("one authenticated GraphQL call for the account and the last 7 UTC days", async () => {
    const calls = fakeCloudflare(sample);
    const r = await usageReport(E, NOW);
    expect(r.status).toBe(200);
    expect(calls).toHaveLength(1);
    const c = calls[0];
    expect(c.url).toBe(GRAPHQL_URL);
    expect(c.auth).toBe("Bearer tok_test");
    expect(c.variables).toEqual({
      accountTag: "cd708edb210d36f6f898127f0373d124",
      start: "2026-10-19T00:00:00.000Z",
      end: "2026-10-26T00:00:00.000Z",
      storageFrom: "2026-10-24",
    });
    for (const dataset of [
      "workersInvocationsAdaptive", "durableObjectsInvocationsAdaptiveGroups", "durableObjectsPeriodicGroups",
      "durableObjectsStorageGroups", "d1AnalyticsAdaptiveGroups", "d1StorageAdaptiveGroups",
    ]) expect(c.query).toContain(dataset);
    expect(c.query).toBe(QUERY);
    for (const field of ["requests", "duration", "rowsRead", "rowsWritten", "storedBytes", "databaseSizeBytes", "datetimeHour", "scriptName", "type"]) {
      expect(c.query).toContain(field);
    }
  });

  it("CF_ACCOUNT_ID overrides the built-in account id", async () => {
    const calls = fakeCloudflare(empty);
    await usageReport({ ...E, CF_ACCOUNT_ID: "a".repeat(32) }, NOW);
    expect(calls[0].variables.accountTag).toBe("a".repeat(32));
  });
});

describe("usage: aggregation", () => {
  it("used / limit / left / percent / level per metric, only today's UTC day", async () => {
    fakeCloudflare(sample);
    const b = (await usageReport(E, NOW)).body as Json;
    expect(b.configured).toBe(true);
    expect(b.reset_at).toBe("2026-10-26T00:00:00.000Z");

    // Workers: today 1000 + 500 + 2000 (yesterday's 900 is out); ours 3000
    const w = metric(b, "workers_requests");
    expect(w).toMatchObject({ used: 3500, limit: 100_000, left: 96_500, percent: 3.5, level: "ok", mine: 3000, period: "day", group: "workers" });
    // DO requests: 4000 + 1000 + 40000/20 = 7000
    expect(metric(b, "do_requests")).toMatchObject({ used: 7000, left: 93_000, percent: 7, mine: 7000 });
    expect(metric(b, "do_duration")).toMatchObject({ used: 6500.25, limit: 13_000, left: 6499.75, percent: 50, level: "ok", unit: "gbs" });
    expect(metric(b, "do_rows_read")).toMatchObject({ used: 2_500_000, limit: 5_000_000, percent: 50 });
    expect(metric(b, "do_rows_written")).toMatchObject({ used: 50_000, percent: 50 });
    expect(metric(b, "d1_rows_read")).toMatchObject({ used: 4_000_000, left: 1_000_000, percent: 80, level: "warning" });
    expect(metric(b, "d1_rows_written")).toMatchObject({ used: 90_000, percent: 90, level: "danger" });
    // storage: the latest day's value, not summed over days; D1 = the largest database vs 500 MB
    expect(metric(b, "do_storage")).toMatchObject({ used: 2_000_000, limit: 5_000_000_000, period: "total" });
    expect(metric(b, "d1_storage")).toMatchObject({ used: 450_000_000, limit: 500_000_000, percent: 90, level: "danger", total_bytes: 455_000_000, databases: 2 });
    // every metric has a limit from the one table
    for (const m of b.metrics) expect(m.limit).toBe(FREE_LIMITS[m.id as keyof typeof FREE_LIMITS].limit);
    expect(b.metrics).toHaveLength(Object.keys(FREE_LIMITS).length);
  });

  it("levels switch at 70% and 90% (on the exact ratio, not the rounded percent)", async () => {
    const a = empty();
    a.workers = [
      { sum: { requests: 69_999 }, dimensions: { datetimeHour: iso(TODAY), scriptName: "x" } },
    ];
    a.d1 = [{ sum: { rowsRead: 0, rowsWritten: 90_000 }, dimensions: { datetimeHour: iso(TODAY) } }];
    a.doPeriodic = [{ sum: { duration: 9100, rowsRead: 0, rowsWritten: 0 }, dimensions: { datetimeHour: iso(TODAY) } }];
    fakeCloudflare(() => a);
    const b = (await usageReport(E, NOW)).body as Json;
    expect(metric(b, "workers_requests").level).toBe("ok");
    expect(metric(b, "do_duration")).toMatchObject({ percent: 70, level: "warning" });
    expect(metric(b, "d1_rows_written")).toMatchObject({ percent: 90, level: "danger" });
  });

  it("never reports more than 100% or a negative 'left'", async () => {
    const a = empty();
    a.workers = [{ sum: { requests: 130_000 }, dimensions: { datetimeHour: iso(TODAY), scriptName: "x" } }];
    fakeCloudflare(() => a);
    const m = metric(((await usageReport(E, NOW)).body as Json), "workers_requests");
    expect(m).toMatchObject({ used: 130_000, left: 0, percent: 100, level: "danger" });
  });

  it("hourly: today's hours up to the current one; daily: 7 days, oldest first, hours binned by UTC date", async () => {
    fakeCloudflare(sample);
    const b = (await usageReport(E, NOW)).body as Json;
    expect(b.hourly.hours).toHaveLength(15); // 00:00 … 14:00
    expect(b.hourly.hours[0]).toBe("2026-10-25T00:00:00.000Z");
    expect(b.hourly.workers_requests[0]).toBe(1500);
    expect(b.hourly.workers_requests[13]).toBe(2000);
    expect(b.hourly.do_requests[13]).toBe(7000);
    expect(b.hourly.workers_requests[14]).toBe(0);
    expect(b.daily.map((d: Json) => d.day)).toEqual(["2026-10-19", "2026-10-20", "2026-10-21", "2026-10-22", "2026-10-23", "2026-10-24", "2026-10-25"]);
    // 23:00 UTC on the 24th belongs to the 24th
    expect(b.daily[5]).toMatchObject({ workers_requests: 900, do_requests: 7000, do_duration: 100.5 });
    expect(b.daily[6]).toMatchObject({ workers_requests: 3500, do_requests: 7000 });
  });

  it("the UTC day boundary: just after midnight only the new day counts, reset is the next 00:00", async () => {
    fakeCloudflare(sample);
    const b = (await usageReport(E, TODAY + 60_000)).body as Json; // 00:01 UTC
    expect(b.hourly.hours).toEqual(["2026-10-25T00:00:00.000Z"]);
    expect(metric(b, "workers_requests").used).toBe(3500); // the fake still returns the 13:00 row; the window is the caller's
    resetUsageCache();
    const calls = fakeCloudflare(empty);
    const e = (await usageReport(E, TODAY - 1)).body as Json; // 23:59:59.999 on the 24th
    expect(e.reset_at).toBe("2026-10-25T00:00:00.000Z");
    expect(calls[0].variables.start).toBe("2026-10-18T00:00:00.000Z");
    expect(calls[0].variables.end).toBe("2026-10-25T00:00:00.000Z");
  });
});

describe("usage: games left estimate", () => {
  async function matches(n: number, at: number) {
    for (let i = 0; i < n; i++) await DB.prepare("INSERT INTO matches (code, started_at) VALUES (?, ?)").bind("M" + i, at + i).run();
  }

  it("uses today's cost per match once there are 5 matches today; the tightest metric limits", async () => {
    fakeCloudflare(sample);
    await matches(10, TODAY + HOUR);
    const e = ((await usageReport(E, NOW)).body as Json).estimate;
    // DO requests: 7000 used / 10 matches = 700 per match; 93,000 left -> 132 games. Rows written (D1) 90,000/10 = 9000 per match, 10,000 left -> 1 game.
    expect(e.basis).toBe("today");
    expect(e.matches).toBe(10);
    expect(e.limiting).toBe("d1_rows_written");
    expect(e.games_left).toBe(1);
    expect(e.per_game.do_requests).toBe(700);
  });

  it("falls back to the last 7 days with fewer than 5 matches today; null without matches", async () => {
    fakeCloudflare(sample);
    await matches(2, TODAY + HOUR);
    await matches(6, TODAY - 3 * DAY);
    let e = ((await usageReport(E, NOW)).body as Json).estimate;
    expect(e.basis).toBe("7d");
    expect(e.matches).toBe(8);
    resetUsageCache();
    await DB.prepare("DELETE FROM matches").run();
    e = ((await usageReport(E, NOW)).body as Json).estimate;
    expect(e).toMatchObject({ games_left: null, basis: null, matches: 0 });
  });

  it("estimateGames: skips metrics with no use, floors the result", () => {
    const r = estimateGames(
      [{ id: "do_requests", left: 1000 }, { id: "do_duration", left: 100 }],
      { today: { do_requests: 300, do_duration: 0 }, week: {} },
      { today: 10, week: 10 },
    );
    expect(r.games_left).toBe(33);
    expect(r.limiting).toBe("do_requests");
  });
});

describe("usage: cache and failures", () => {
  it("caches for 5 minutes, then asks Cloudflare again", async () => {
    const calls = fakeCloudflare(sample);
    const a = await usageReport(E, NOW);
    await usageReport(E, NOW + CACHE_MS - 1);
    expect(calls).toHaveLength(1);
    expect((a.body as Json).cached_at).toBe(NOW);
    const b = await usageReport(E, NOW + CACHE_MS);
    expect(calls).toHaveLength(2);
    expect((b.body as Json).cached_at).toBe(NOW + CACHE_MS);
  });

  it("Cloudflare errors: 502 with the message; after a good answer from today, the stale numbers", async () => {
    fakeCloudflare(empty, 200, [{ message: "authentication error" }]);
    let r = await usageReport(E, NOW);
    expect(r.status).toBe(502);
    expect(r.body).toMatchObject({ error: "cloudflare_failed" });
    expect(String(r.body.msg)).toContain("authentication error");

    fakeCloudflare(sample);
    await usageReport(E, NOW);
    fakeCloudflare(empty, 500);
    r = await usageReport(E, NOW + CACHE_MS + 1);
    expect(r.status).toBe(200);
    expect(r.body).toMatchObject({ configured: true, stale: true });
    expect(metric(r.body, "workers_requests").used).toBe(3500);
    // the stale fallback never crosses the UTC day
    r = await usageReport(E, NOW + DAY);
    expect(r.status).toBe(502);
  });

  it("network failure is a 502, not a crash", async () => {
    setCloudflareFetcher(async () => {
      throw new Error("boom");
    });
    const r = await usageReport(E, NOW);
    expect(r.status).toBe(502);
  });
});

describe("usage: the endpoint", () => {
  async function direct(e: Env, path: string, cookie?: string, method = "GET"): Promise<Response> {
    const ctx = createExecutionContext();
    const headers: Record<string, string> = { "CF-Connecting-IP": "203.0.113.9" };
    if (cookie) headers.Cookie = `lz_admin=${cookie}`;
    if (method !== "GET") headers["X-Admin"] = "1";
    const r = await worker.fetch(new Request(`https://x/admin/api/${path}`, { method, headers }), e, ctx);
    await waitOnExecutionContext(ctx);
    return r;
  }

  it("needs a session, GET only", async () => {
    expect((await call("usage")).status).toBe(401);
    const cookie = await login();
    expect((await call("usage", { cookie, method: "POST", xadmin: true })).status).toBe(405);
    expect((await call("usage/x", { cookie })).status).toBe(404);
  });

  it("without CF_API_TOKEN: configured false, the limits, the setup steps; no call to Cloudflare", async () => {
    const calls = fakeCloudflare(sample);
    const cookie = await login();
    const b = await api(cookie, "usage");
    expect(b.configured).toBe(false);
    expect(calls).toHaveLength(0);
    expect(b.metrics).toHaveLength(Object.keys(FREE_LIMITS).length);
    expect(b.metrics[0]).not.toHaveProperty("used");
    expect(b.metrics.find((m: Json) => m.id === "do_requests").limit).toBe(100_000);
    expect(b.setup.secret).toBe("CF_API_TOKEN");
    expect(b.setup.permission).toContain("Account Analytics");
    expect(b.setup.steps.length).toBeGreaterThan(2);
    expect(Date.parse(b.reset_at)).toBeGreaterThan(Date.now());
  });

  it("with the token, through the Worker: admin headers and the report", async () => {
    // rows are placed relative to the window the page asked for (the Worker uses the real clock)
    fakeCloudflare((v) => {
      const a = empty();
      a.workers = [{ sum: { requests: 123 }, dimensions: { datetimeHour: iso(Date.parse(v.end) - HOUR), scriptName: WORKER_NAME } }];
      return a;
    });
    const cookie = await login();
    const r = await direct(E, "usage", cookie);
    expect(r.status).toBe(200);
    expect(r.headers.get("Cache-Control")).toBe("no-store");
    const b = (await r.json()) as Json;
    expect(b.configured).toBe(true);
    expect(Date.parse(b.reset_at)).toBeGreaterThan(Date.now());
    expect(Date.parse(b.reset_at) - Date.now()).toBeLessThanOrEqual(DAY);
    expect(b.info.length).toBeGreaterThan(0);
    expect(direct(E, "usage")).resolves.toHaveProperty("status", 401);
  });
});
