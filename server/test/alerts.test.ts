// Alerts (ADMIN_API.md "Alerts", src/alerts.ts): the usage steps (70 / 90 / 100 %, the lower ones silent), the pace
// projection, server errors, push failing, Cloudflare unreadable twice in a row, the morning summary, once-only keys,
// the push to the alert accounts (one each, or one for many), the 15-minute cron dispatch and the admin endpoints.
// Cloudflare and FCM are fakes.
import { createExecutionContext, createScheduledController, env, waitOnExecutionContext } from "cloudflare:test";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import worker from "../src/index";
import { ALERT_CRON, bdTime, checkAlerts, errorsAlert, paceAlerts, usageAlerts } from "../src/alerts";
import { ERRORS_QUERY, FREE_LIMITS, WORKER_NAME, setCloudflareFetcher, usageSnapshot } from "../src/usage";
import type { Env } from "../src/room";
import { api, call, login, row, rows } from "./admin_helpers";
import { fcmToken, installFakeFcm, uninstallFakeFcm, type FakeFcm, type Json } from "./push_helpers";

const MIN = 60_000;
const HOUR = 60 * MIN;
const DAY = 24 * HOUR;
const TODAY = Date.parse("2026-11-03T00:00:00Z");
const NOON = TODAY + 12 * HOUR + 20 * MIN; // 18:20 Bangladesh
const iso = (t: number) => new Date(t).toISOString();
const OWNER = "acc_ownerownerowner2";
const BASE = env as unknown as Env;
const E = { ...BASE, CF_API_TOKEN: "tok_test", ALERT_ACCOUNTS: OWNER } as Env & { CF_API_TOKEN: string };
const DB = BASE.DB;

let fcm: FakeFcm;
let cookie: string;

/** `n` hours of `v` requests. */
const flat = (n: number, v: number): number[] => Array(n).fill(v);
/** Busy in the morning, then quiet: no pace alert at NOON. */
const morning = (total: number): number[] => [...flat(4, total / 4), ...flat(9, 0)];

/** A fake Cloudflare: Workers requests `series[k]` in hour k of today, nothing else; `errors` in the last hour. */
function fakeCloudflare(o: { series?: number[]; errors?: number; requests?: number; down?: boolean; doRows?: Json[] }) {
  const calls: string[] = [];
  setCloudflareFetcher(async (_url, init) => {
    const b = JSON.parse(String(init?.body));
    calls.push(b.query === ERRORS_QUERY ? "errors" : "usage");
    if (o.down) return Response.json({}, { status: 503 });
    if (b.query === ERRORS_QUERY) {
      return Response.json({ data: { viewer: { accounts: [{
        workers: [{ sum: { requests: o.requests ?? 1000, errors: o.errors ?? 0 } }],
        durableObjects: o.doRows ?? [{ sum: { requests: 0, errors: 0 } }],
      }] } } });
    }
    const workers: Json[] = [];
    (o.series ?? []).forEach((v, k) => {
      workers.push({ sum: { requests: v }, dimensions: { datetimeHour: iso(TODAY + k * HOUR), scriptName: WORKER_NAME } });
    });
    return Response.json({ data: { viewer: { accounts: [{ workers, doInvocations: [], doPeriodic: [], doStorage: [], d1: [], d1Storage: [] }] } } });
  });
  return calls;
}

async function device(acc: string): Promise<string> {
  const token = fcmToken("al");
  await DB.prepare("INSERT INTO push_tokens (token, account_id, created_at, updated_at) VALUES (?, ?, ?, ?)").bind(token, acc, Date.now(), Date.now()).run();
  return token;
}

beforeAll(async () => {
  fcm = await installFakeFcm();
  cookie = await login();
});
afterAll(() => {
  uninstallFakeFcm();
  setCloudflareFetcher(null);
});
beforeEach(async () => {
  fcm.reset();
  await DB.batch([
    DB.prepare("DELETE FROM alerts"),
    DB.prepare("DELETE FROM alert_state"),
    DB.prepare("DELETE FROM push_tokens"),
    DB.prepare("DELETE FROM push_events"),
    DB.prepare("DELETE FROM events"),
    DB.prepare("DELETE FROM accounts WHERE id = ?").bind(OWNER),
    DB.prepare("INSERT INTO accounts (id, name, created_at, last_seen) VALUES (?, 'Owner', ?, ?)").bind(OWNER, TODAY - 30 * DAY, NOON),
    // yesterday's summary already sent (TODAY's, and the real clock's for the API / cron tests): only the summary test wants one
    ...[TODAY, Date.now()].map((t) =>
      DB.prepare("INSERT OR IGNORE INTO alerts (key, at, level, kind, title, body, read_at) VALUES (?, 0, 'info', 'summary', 'S', 'B', 0)")
        .bind(`summary:${iso(Math.floor(t / DAY) * DAY - DAY).slice(0, 10)}`)),
  ]);
  await device(OWNER);
});

const metric = (id: string, used: number) => {
  const L = FREE_LIMITS[id as keyof typeof FREE_LIMITS];
  return { id, label: L.label, group: L.group, unit: L.unit, period: L.period, used, limit: L.limit, left: L.limit - used, percent: (used / L.limit) * 100, level: "ok", note: "" };
};

describe("alert rules", () => {
  it("bdTime: Bangladesh time, 12-hour clock", () => {
    expect(bdTime(TODAY)).toBe("6:00 AM");
    expect(bdTime(TODAY + 10 * HOUR + 30 * MIN)).toBe("4:30 PM");
    expect(bdTime(TODAY + 18 * HOUR)).toBe("12:00 AM");
    expect(bdTime(TODAY + 6 * HOUR + 5 * MIN)).toBe("12:05 PM");
  });

  it("usage steps: 70 warning; 95 raises 70 silently and 90 as danger; 100 'Out'; under 70 nothing", () => {
    expect(usageAlerts([metric("workers_requests", 69_999)] as never, NOON)).toEqual([]);
    const a = usageAlerts([metric("workers_requests", 72_000)] as never, NOON);
    expect(a).toHaveLength(1);
    expect(a[0]).toMatchObject({ key: "usage:workers_requests:70:2026-11-03", level: "warning", silent: false, title: "Workers requests at 72% of today's free limit" });
    expect(a[0].body).toContain("72,000 of 100,000 used today. It resets at 6:00 AM Bangladesh time (in 11h 40m).");
    const b = usageAlerts([metric("workers_requests", 95_500)] as never, NOON);
    expect(b.map((x) => [x.key, x.level, x.silent])).toEqual([
      ["usage:workers_requests:70:2026-11-03", "warning", true],
      ["usage:workers_requests:90:2026-11-03", "danger", false],
    ]);
    expect(b[1].title).toBe("Almost out: Workers requests at 95%");
    const c = usageAlerts([metric("d1_rows_written", 100_000)] as never, NOON);
    expect(c.filter((x) => !x.silent).map((x) => x.title)).toEqual(["Out: D1 rows written used up for today"]);
  });

  it("storage (no reset): a monthly key and its own text", () => {
    const a = usageAlerts([metric("d1_storage", 360_000_000)] as never, NOON);
    expect(a[0]).toMatchObject({ key: "usage:d1_storage:70:2026-11", level: "warning" });
    expect(a[0].body).toContain("360.0 MB of 500.0 MB stored. This one does not reset");
  });

  it("pace: the last 3 complete hours' rate runs out before the reset (not in the first 3 hours, not under 25%)", () => {
    // 12 hours of 3,000 then 3 hours of 8,000: 60,000 at 15:20 UTC; 8,000 an hour runs out in 5 hours (20:20 UTC = 2:20 AM)
    const now = TODAY + 15 * HOUR + 20 * MIN;
    const series = [...Array(12).fill(3000), 8000, 8000, 8000, 1000];
    const body = { metrics: [metric("workers_requests", 61_000)], hourly: { workers_requests: series } } as never;
    const p = paceAlerts(body, now);
    expect(p).toHaveLength(1);
    expect(p[0]).toMatchObject({ key: "pace:workers_requests:2026-11-03", level: "warning", title: "Workers requests will run out today" });
    expect(p[0].body).toContain("runs out around 2:12 AM Bangladesh time, before the reset at 6:00 AM. Now at 61%");
    // a slow pace: fine
    expect(paceAlerts({ metrics: [metric("workers_requests", 61_000)], hourly: { workers_requests: [...Array(15).fill(1000), 0] } } as never, now)).toEqual([]);
    // too early in the day, or too little used
    expect(paceAlerts({ metrics: [metric("workers_requests", 40_000)], hourly: { workers_requests: [20000, 20000, 0] } } as never, TODAY + 2 * HOUR + 5 * MIN)).toEqual([]);
    expect(paceAlerts({ metrics: [metric("workers_requests", 20_000)], hourly: { workers_requests: series } } as never, now)).toEqual([]);
  });

  it("errors: at least 20 and 2% of requests; one key per 6 hours", () => {
    expect(errorsAlert(1000, 19, NOON)).toBeNull();
    expect(errorsAlert(10_000, 150, NOON)).toBeNull();
    const a = errorsAlert(1000, 40, NOON)!;
    expect(a).toMatchObject({ key: "server:errors:2026-11-03:2", level: "danger", title: "Server errors: 40 in the last hour" });
    expect(a.body).toContain("(4.0% of 1,000 requests)");
  });
});

describe("checkAlerts", () => {
  it("70%: one push to the owner's device, stored with its result; the next check raises nothing new", async () => {
    fakeCloudflare({ series: morning(78_000) });
    const r = await checkAlerts(E, NOON);
    expect(r).toMatchObject({ usage: "ok", errors_check: "ok", raised: ["usage:workers_requests:70:2026-11-03"], pushed: { sent: 1, failed: 0 } });
    expect(r.top).toEqual({ id: "workers_requests", percent: 78 });
    expect(fcm.delivered).toHaveLength(1);
    const m = fcm.delivered[0];
    expect(m.notification.title).toBe("Workers requests at 78% of today's free limit");
    expect(m.data).toMatchObject({ kind: "alert", link: "home" });
    expect(m.android).toMatchObject({ priority: "high", notification: { channel_id: "game", tag: "alert-workers_requests" } });
    expect(await row("SELECT level, kind, sent, failed, read_at FROM alerts WHERE kind != 'summary'")).toEqual({ level: "warning", kind: "usage", sent: 1, failed: 0, read_at: null });

    const again = await checkAlerts(E, NOON + 15 * MIN);
    expect(again.raised).toEqual([]);
    expect(fcm.delivered).toHaveLength(1);
    const st = await row<Json>("SELECT value FROM alert_state WHERE key = 'last_check'");
    expect(JSON.parse(st!.value)).toMatchObject({ at: NOON + 15 * MIN, raised: [] });
  });

  it("a jump to 95%: the 90 step pushed, the 70 step stored as read (not in the banner)", async () => {
    fakeCloudflare({ series: morning(95_200) });
    const r = await checkAlerts(E, NOON);
    expect(r.raised).toEqual(["usage:workers_requests:90:2026-11-03"]);
    expect(fcm.delivered.map((d) => d.notification.title)).toEqual(["Almost out: Workers requests at 95%"]);
    const all = await rows<Json>("SELECT key, read_at IS NOT NULL AS read FROM alerts WHERE kind != 'summary' ORDER BY key");
    expect(all).toEqual([
      { key: "usage:workers_requests:70:2026-11-03", read: 1 },
      { key: "usage:workers_requests:90:2026-11-03", read: 0 },
    ]);
  });

  it("Cloudflare unreadable: nothing the first time, a warning the second, once a day; a good read resets the count", async () => {
    fakeCloudflare({ down: true });
    const a = await checkAlerts(E, NOON);
    expect(a.usage).toContain("Cloudflare");
    expect(a.raised).toEqual([]);
    const b = await checkAlerts(E, NOON + 15 * MIN);
    expect(b.raised).toEqual(["server:usage_read:2026-11-03"]);
    expect(fcm.delivered[0].notification.title).toBe("Can't check the server's free limits");
    expect((await checkAlerts(E, NOON + 30 * MIN)).raised).toEqual([]);
    fakeCloudflare({ series: flat(13, 10) });
    await checkAlerts(E, NOON + 45 * MIN);
    expect((await row<Json>("SELECT value FROM alert_state WHERE key = 'usage_fails'"))!.value).toBe("0");
  });

  it("no token: usage not checked (said so), the D1 checks still run", async () => {
    const r = await checkAlerts({ ...E, CF_API_TOKEN: undefined } as never, NOON);
    expect(r).toMatchObject({ usage: "CF_API_TOKEN is not set", errors_check: "skipped", top: null });
  });

  it("server errors: Cloudflare's count plus the logged Worker errors", async () => {
    fakeCloudflare({ series: flat(13, 10), requests: 500, errors: 8 });
    const stmts = [];
    for (let k = 0; k < 14; k++) stmts.push(DB.prepare("INSERT INTO events (at, level, kind, msg) VALUES (?, 'error', 'worker', 'boom')").bind(NOON - 10 * MIN));
    stmts.push(DB.prepare("INSERT INTO events (at, level, kind, msg) VALUES (?, 'error', 'worker', 'old')").bind(NOON - 2 * HOUR));
    await DB.batch(stmts);
    const r = await checkAlerts(E, NOON);
    expect(r.raised).toEqual(["server:errors:2026-11-03:2"]);
    expect(fcm.delivered[0].notification.title).toBe("Server errors: 22 in the last hour");
  });

  it("push failing today: more failed than sent, at least 20", async () => {
    fakeCloudflare({ series: flat(13, 10) });
    await DB.prepare("INSERT INTO push_events (day, kind, sent, failed) VALUES ('2026-11-03', 'turn', 5, 25)").run();
    expect((await checkAlerts(E, NOON)).raised).toEqual(["server:push:2026-11-03"]);
  });

  it("a phone disconnecting and a cancelled alarm are not server errors; a crash and an unknown status are", async () => {
    const dropped = (status: string, errors: number): Json => ({ dimensions: { status }, sum: { requests: errors, errors } });
    fakeCloudflare({ series: flat(13, 10), requests: 300, errors: 0, doRows: [dropped("clientDisconnected", 40), dropped("canceled", 60)] });
    let r = await checkAlerts(E, NOON);
    expect(r.raised.filter((k) => k.startsWith("server:errors"))).toEqual([]);
    expect(r.errors_by_status).toEqual({ clientDisconnected: 40, canceled: 60 });
    fakeCloudflare({ series: flat(13, 10), requests: 300, errors: 0, doRows: [dropped("canceled", 60), dropped("scriptThrewException", 15), dropped("somethingNew", 15)] });
    r = await checkAlerts(E, NOON);
    expect(r.raised.filter((k) => k.startsWith("server:errors")).length).toBe(1);
  });

  it("many new alerts at once: one push that lists them, every row gets its result", async () => {
    fakeCloudflare({ series: morning(78_000), requests: 100, errors: 50 });
    await DB.prepare("INSERT INTO push_events (day, kind, sent, failed) VALUES ('2026-11-03', 'turn', 0, 30)").run();
    const r = await checkAlerts(E, NOON);
    expect(r.raised).toHaveLength(3);
    expect(fcm.delivered).toHaveLength(1);
    const n = fcm.delivered[0].notification;
    expect(n.title).toBe("3 server alerts");
    expect(n.body.split(" · ")[0]).toBe("Server errors: 50 in the last hour"); // danger first
    expect(await rows("SELECT sent FROM alerts WHERE kind != 'summary'")).toEqual([{ sent: 1 }, { sent: 1 }, { sent: 1 }]);
  });

  it("the summary: from 03:00 UTC once, about yesterday; not before", async () => {
    fakeCloudflare({ series: flat(3, 10) });
    const y = TODAY - DAY;
    await DB.batch([
      DB.prepare("DELETE FROM alerts"),
      DB.prepare("DELETE FROM matches"),
      DB.prepare("DELETE FROM crash_reports"),
      DB.prepare("INSERT INTO accounts (id, created_at, last_seen) VALUES ('acc_newnewnewnewnew2', ?, ?)").bind(y + HOUR, TODAY + HOUR),
      DB.prepare("INSERT INTO matches (code, started_at, result) VALUES ('AAAAAA', ?, 'over'), ('BBBBBB', ?, 'over'), ('CCCCCC', ?, 'over')").bind(y + 2 * HOUR, y + 3 * HOUR, TODAY + HOUR),
      DB.prepare("INSERT INTO crash_reports (id, received_at, pid, sid, reason, payload, gpu, model) VALUES ('crs_1', ?, 'p1', 's1', 'x', '{}', 'Mali-G57 MC2', 'Infinix X6886'), ('crs_2', ?, 'p1', 's2', 'x', '{}', 'Mali-G57 MC2', 'Infinix X6886')").bind(y + HOUR, y + 2 * HOUR),
      // not players' crashes: Google's pre-launch robot, an emulator, a graphics-test report
      DB.prepare("INSERT INTO crash_reports (id, received_at, pid, sid, reason, payload, gpu, model) VALUES ('crs_3', ?, 'r1', 's1', 'crash_native', '{}', 'Google SwiftShader', 'OnePlus8Pro'), ('crs_4', ?, 'e1', 's1', 'unclean', '{}', 'Android Emulator OpenGL ES Translator (Apple M3 Pro)', 'sdk_gphone64_arm64'), ('crs_5', ?, 'p2', 's1', 'probe', '{}', 'Mali-G68 MC4', 'OPPO CPH2251')").bind(y + HOUR, y + HOUR, y + HOUR),
    ]);
    expect((await checkAlerts(E, TODAY + 2 * HOUR + 50 * MIN)).raised).toEqual([]);
    const r = await checkAlerts(E, TODAY + 3 * HOUR + 5 * MIN);
    expect(r.raised).toEqual(["summary:2026-11-02"]);
    const n = fcm.delivered[0];
    expect(n.notification.title).toBe("Ludo Zing yesterday");
    expect(n.notification.body).toBe(
      "2 players in the last 24 hours, 1 new account, 2 online matches, 2 crashes on 1 player's phone (+2 on Google's test robots / emulators). Highest free limit yesterday: Workers requests at 0%.",
    );
    expect(n.android.ttl).toBe("86400s");
    expect((await row<Json>("SELECT level, read_at FROM alerts"))).toEqual({ level: "info", read_at: null });
    expect((await checkAlerts(E, TODAY + 3 * HOUR + 20 * MIN)).raised).toEqual([]);
    await DB.prepare("DELETE FROM accounts WHERE id = 'acc_newnewnewnewnew2'").run();
  });

  it("no alert accounts: stored, not pushed", async () => {
    fakeCloudflare({ series: morning(78_000) });
    const r = await checkAlerts({ ...E, ALERT_ACCOUNTS: "" } as never, NOON);
    expect(r.raised).toHaveLength(1);
    expect(r.pushed).toEqual({ sent: 0, failed: 0 });
    expect(fcm.sends).toHaveLength(0);
  });

  it("the snapshot reads no matches (no estimate)", async () => {
    fakeCloudflare({ series: flat(2, 10) });
    expect((await usageSnapshot(E, NOON)).estimate).toBeNull();
  });
});

describe("the 15-minute cron", () => {
  it("runs the check (the daily cron does not)", async () => {
    fakeCloudflare({ series: flat(2, 10) });
    const ctx = createExecutionContext();
    await worker.scheduled(createScheduledController({ cron: ALERT_CRON, scheduledTime: Date.now() }), BASE, ctx);
    await waitOnExecutionContext(ctx);
    const st = await row<Json>("SELECT value FROM alert_state WHERE key = 'last_check'");
    expect(JSON.parse(st!.value).usage).toBe("CF_API_TOKEN is not set"); // the test env has no token
  });
});

describe("/admin/api/alerts", () => {
  it("needs a session", async () => {
    expect((await call("alerts")).status).toBe(401);
    expect((await call("alerts/test", { body: {} })).status).toBe(401);
  });

  it("lists newest first with paging and the status: unread, last check, the accounts and their devices", async () => {
    fakeCloudflare({ series: morning(78_000) });
    await checkAlerts(E, NOON);
    await DB.prepare("INSERT INTO alerts (key, at, level, kind, title, body) VALUES ('summary:x', ?, 'info', 'summary', 'S', 'B')").bind(NOON + 1).run();
    await DB.prepare("DELETE FROM alerts WHERE key LIKE 'summary:2%'").run();
    const p1 = await api(cookie, "alerts?limit=1");
    expect(p1.items.map((a: Json) => a.key)).toEqual(["summary:x"]);
    const p2 = await api(cookie, `alerts?limit=1&cursor=${p1.next}`);
    expect(p2.items.map((a: Json) => a.key)).toEqual(["usage:workers_requests:70:2026-11-03"]);
    expect(p2.next).toBeNull();
    expect(p1.status).toMatchObject({ unread: 1, unread_danger: 0, every_min: 15, steps: [70, 90, 100], push_configured: true });
    expect(p1.status.last_check.raised).toEqual(["usage:workers_requests:70:2026-11-03"]);
    // the test env's ALERT_ACCOUNTS (wrangler.jsonc) names the real owner, absent here
    expect(p1.status.accounts).toEqual([{ id: "acc_trk4hyeypeu26juq", name: null, devices: 0, missing: true }]);
    expect((await call("alerts?cursor=abc", { cookie })).status).toBe(400);
  });

  it("read: marks every alert read", async () => {
    await DB.prepare("INSERT INTO alerts (key, at, level, kind, title, body) VALUES ('a', 1, 'danger', 'server', 'T', 'B'), ('b', 2, 'warning', 'usage', 'T', 'B')").run();
    expect(await api(cookie, "alerts/read", { body: {} })).toEqual({ read: 2 });
    expect((await api(cookie, "alerts")).status.unread).toBe(0);
  });

  it("test: a push to the alert accounts, audited, at most 5 an hour", async () => {
    const r = await api(cookie, "alerts/test", { body: {} });
    expect(r).toEqual({ sent: 0, failed: 0, accounts: 1 }); // the owner of wrangler.jsonc has no device in the test D1
    expect(await row<Json>("SELECT action FROM admin_log WHERE action = 'alerts.test' ORDER BY id DESC LIMIT 1")).toEqual({ action: "alerts.test" });
    for (let k = 0; k < 4; k++) await api(cookie, "alerts/test", { body: {} });
    expect((await call("alerts/test", { cookie, body: {} })).status).toBe(429);
  });

  it("check: runs it now", async () => {
    const r = await api(cookie, "alerts/check", { body: {} });
    expect(r).toMatchObject({ usage: "CF_API_TOKEN is not set", raised: [] });
    expect((await call("alerts/check", { cookie })).status).toBe(405);
  });
});
