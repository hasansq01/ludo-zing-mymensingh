// The admin's notifications API (ADMIN_API.md "Notifications") and the Pusher queue behind it: the overview, push off,
// campaigns to everyone (one topic send) and to segments (filters, prefs, banned accounts, dead tokens), the 40 sends
// per alarm chunking and its re-arm, scheduling and cancel, retries, preview, test sends, rate limits and audit rows.
import { runDurableObjectAlarm, runInDurableObject } from "cloudflare:test";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { setPushServiceAccount } from "../src/push";
import { SENDS_PER_ALARM } from "../src/pusher";
import { api, call, eventually, login, row, rows } from "./admin_helpers";
import { PENV, PROJECT, fcmToken, installFakeFcm, pusherStub, uninstallFakeFcm, type FakeFcm, type Json } from "./push_helpers";

const DB = PENV.DB;
const DAY = 86_400_000;
let fcm: FakeFcm;
let cookie: string;

beforeAll(async () => {
  fcm = await installFakeFcm();
  cookie = await login();
});
afterAll(() => uninstallFakeFcm());
beforeEach(async () => {
  fcm.reset();
  setPushServiceAccount(fcm.serviceAccount);
  await DB.batch([
    DB.prepare("DELETE FROM push_campaigns"),
    DB.prepare("DELETE FROM push_tokens"),
    DB.prepare("DELETE FROM push_events"),
    DB.prepare("DELETE FROM accounts WHERE id LIKE 'acc_p%'"),
    DB.prepare("DELETE FROM admin_log WHERE action LIKE 'push.%'"),
  ]);
  await runInDurableObject(pusherStub(), async (_i, st) => {
    st.storage.sql.exec("DELETE FROM jobs");
    st.storage.sql.exec("DELETE FROM notes");
    st.storage.sql.exec("DELETE FROM batches");
    await st.storage.deleteAlarm();
  });
  await pusherStub().testHooks({ paceMs: 20 });
});

const ABC = "abcdefghijklmnopqrstuvwxyz234567";
/** An account row (ids "acc_p..." so beforeEach can drop them). */
async function account(o: { xp?: number; created?: number; seen?: number | null; banned?: boolean; merged?: boolean } = {}): Promise<string> {
  const r = crypto.getRandomValues(new Uint8Array(15));
  const id = `acc_p${Array.from(r, (v) => ABC[v & 31]).join("")}`;
  const now = Date.now();
  await DB.prepare("INSERT INTO accounts (id, created_at, last_seen, xp, banned, merged_into) VALUES (?, ?, ?, ?, ?, ?)")
    .bind(id, o.created ?? now - 100 * DAY, o.seen === undefined ? now : o.seen, o.xp ?? 0, o.banned ? 1 : 0, o.merged ? "acc_somewhereelseaa" : null)
    .run();
  return id;
}

/** A device row for an account. */
async function device(acc: string, prefs: { game?: boolean; offers?: boolean } = {}, token = fcmToken()): Promise<string> {
  const now = Date.now();
  await DB.prepare("INSERT INTO push_tokens (token, account_id, prefs_game, prefs_offers, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)")
    .bind(token, acc, prefs.game === false ? 0 : 1, prefs.offers === false ? 0 : 1, now, now)
    .run();
  return token;
}

const campaign = (id: string) => row<Json>("SELECT * FROM push_campaigns WHERE id = ?", id);
const done = (id: string) => eventually(async () => {
  const c = await campaign(id);
  return c && ["sent", "failed"].includes(c.status) ? c : null;
}, 8000, `campaign ${id} done`);

function create(body: Json, status = 200): Promise<Json> {
  return api(cookie, "push/campaigns", { body }, status);
}

describe("GET /admin/api/push", () => {
  it("configured, device counts, event counters (14 UTC days), latest campaigns, limits", async () => {
    const a = await account();
    await device(a);
    await device(a, { offers: false });
    await device(a, { game: false });
    const today = new Date().toISOString().slice(0, 10);
    const old = new Date(Date.now() - 20 * DAY).toISOString().slice(0, 10);
    await DB.prepare("INSERT INTO push_events (day, kind, sent, failed) VALUES (?, 'turn', 5, 1), (?, 'turn', 9, 9)").bind(today, old).run();
    const c = await create({ title: "Hello", body: "World", audience: { kind: "all" } });
    await done(c.id);
    const r = await api(cookie, "push");
    expect(r.configured).toBe(true);
    expect(r.project_id).toBe(PROJECT);
    expect(r.tokens).toEqual({ total: 3, offers: 2, game: 2 });
    expect(r.events).toEqual([{ day: today, kind: "turn", sent: 5, failed: 1 }]);
    expect(r.campaigns).toHaveLength(1);
    expect(r.campaigns[0]).toMatchObject({ id: c.id, title: "Hello", body: "World", link: "home", audience: { kind: "all" }, status: "sent", created_by: "admin" });
    expect(r.limits).toEqual({ campaigns_per_day: 4, campaigns_left: 3, tests_per_hour: 20, tests_left: 20 });
  });

  it("push off: configured false, preview still answers, sends are refused (409 push_off)", async () => {
    setPushServiceAccount(null);
    const a = await account();
    await device(a);
    const r = await api(cookie, "push");
    expect(r.configured).toBe(false);
    expect(r.project_id).toBeNull();
    expect(r.tokens.total).toBe(1);
    expect(await api(cookie, "push/preview", { body: { audience: { kind: "all" } } })).toEqual({ targeted: 1 });
    expect((await create({ title: "t", body: "b", audience: { kind: "all" } }, 409)).error).toBe("push_off");
    expect((await api(cookie, "push/test", { body: { title: "t", body: "b", account_id: a } }, 409)).error).toBe("push_off");
    expect(await rows("SELECT * FROM push_campaigns")).toEqual([]);
    expect(fcm.sends).toHaveLength(0);
  });

  it("needs the admin session and X-Admin on writes", async () => {
    expect((await call("push")).status).toBe(401);
    expect((await call("push/campaigns", { cookie, body: { title: "t", body: "b", audience: { kind: "all" } }, xadmin: false })).status).toBe(403);
    expect((await call("push/campaigns", { cookie })).status).toBe(405);
    expect((await call("push/nope", { cookie })).status).toBe(404);
    expect((await call("push/campaigns/cmp_aaaaaaaaaaaa/cancel/x", { cookie, method: "POST" })).status).toBe(404);
  });
});

describe("campaigns", () => {
  it("everyone: one send to the promos topic, targeted = devices with offers on, audited", async () => {
    for (let k = 0; k < 3; k++) await device(await account());
    await device(await account(), { offers: false });
    await device(await account({ banned: true }));
    const c = await create({ title: "Weekend", body: "Double coins!", link: "shop:dice:gold", audience: { kind: "all" } });
    expect(c).toMatchObject({ status: "sending", targeted: 3, sent: 0, run_at: null, audience: { kind: "all" } });
    expect(c.id).toMatch(/^cmp_[a-z2-7]{12}$/);
    const d = await done(c.id);
    expect(d).toMatchObject({ status: "sent", targeted: 3, sent: 3, failed: 0 });
    expect(d.sent_at).toBeGreaterThan(0);
    expect(fcm.delivered).toEqual([
      {
        topic: "promos",
        notification: { title: "Weekend", body: "Double coins!" },
        data: { link: "shop:dice:gold", kind: "promo", cid: c.id },
        android: { priority: "normal", ttl: "86400s", collapse_key: c.id, notification: { channel_id: "offers", tag: c.id } },
      },
    ]);
    const log = await rows<Json>("SELECT action, target, detail FROM admin_log WHERE action LIKE 'push.%'");
    expect(log).toHaveLength(1);
    expect(log[0]).toMatchObject({ action: "push.campaign", target: c.id });
    expect(JSON.parse(log[0].detail)).toMatchObject({ title: "Weekend", audience: { kind: "all" }, run_at: null, targeted: 3 });
  });

  it("a segment: only matching accounts' devices with offers on; dead tokens are counted failed and deleted", async () => {
    const now = Date.now();
    const yes1 = await device(await account({ seen: now - 10 * DAY }));
    const yes2 = await device(await account({ seen: null, created: now - 30 * DAY })); // never seen: by its creation
    const dead = await device(await account({ seen: now - 9 * DAY }));
    await device(await account({ seen: now - 10 * DAY }), { offers: false });
    await device(await account({ seen: now - 2 * DAY }));
    await device(await account({ seen: now - 10 * DAY, banned: true }));
    await device(await account({ seen: now - 10 * DAY, merged: true }));
    fcm.behaviour.set(dead, "unregistered");
    const c = await create({ title: "We miss you", body: "Your spin is waiting", link: "spin", audience: { kind: "segment", inactive_days: 7 } });
    expect(c.targeted).toBe(3);
    const d = await done(c.id);
    expect(d).toMatchObject({ status: "sent", targeted: 3, sent: 2, failed: 1 });
    expect(fcm.delivered.map((m) => m.token).sort()).toEqual([yes1, yes2].sort());
    expect(fcm.delivered[0]).toMatchObject({ data: { link: "spin", kind: "promo", cid: c.id }, android: { priority: "normal" } });
    expect(await rows("SELECT token FROM push_tokens WHERE token = ?", dead)).toEqual([]);
  });

  it("a segment nobody matches: sent, 0 targeted", async () => {
    await device(await account());
    const c = await create({ title: "t", body: "b", audience: { kind: "segment", level_min: 50 } });
    expect(await done(c.id)).toMatchObject({ status: "sent", targeted: 0, sent: 0, failed: 0 });
    expect(fcm.sends).toHaveLength(0);
  });

  it("a topic send FCM refuses: failed, every targeted device counted failed", async () => {
    await device(await account());
    await device(await account());
    fcm.behaviour.set("topic:promos", "bad_payload");
    const c = await create({ title: "t", body: "b", audience: { kind: "all" } });
    expect(await done(c.id)).toMatchObject({ status: "failed", targeted: 2, sent: 0, failed: 2 });
    expect(fcm.sends).toHaveLength(1);
  });

  it(`sends at most ${SENDS_PER_ALARM} per alarm and re-arms while work is left`, async () => {
    await pusherStub().testHooks({ paceMs: 60_000 }); // the follow-up alarms are run by hand
    const tokens: string[] = [];
    const stmts: D1PreparedStatement[] = [];
    const now = Date.now();
    for (let k = 0; k < 95; k++) {
      const acc = `acc_pchunk${String.fromCharCode(97 + Math.floor(k / 26))}${String.fromCharCode(97 + (k % 26))}aaaa`;
      const t = fcmToken("chunk");
      tokens.push(t);
      stmts.push(DB.prepare("INSERT INTO accounts (id, created_at, last_seen, xp) VALUES (?, ?, ?, 0)").bind(acc, now - DAY, now - 20 * DAY));
      stmts.push(DB.prepare("INSERT INTO push_tokens (token, account_id, created_at, updated_at) VALUES (?, ?, ?, ?)").bind(t, acc, now, now));
    }
    await DB.batch(stmts);
    const c = await create({ title: "Big", body: "Many", audience: { kind: "segment", inactive_days: 10 } });
    expect(c.targeted).toBe(95);
    // the first alarm runs by itself: start + expansion + the first 40
    const p1 = await eventually(async () => {
      const p = await pusherStub().pending();
      return fcm.delivered.length === 40 && p.send === 55 ? p : null;
    }, 8000, "first chunk");
    expect(p1.expand).toBe(0);
    expect(p1.alarm! - Date.now()).toBeGreaterThan(50_000); // re-armed (the test pace)
    expect(await pusherStub().testLast()).toMatchObject({ sends: 40, sent: 40, started: 1, expanded: 95 });
    expect((await campaign(c.id))!).toMatchObject({ status: "sending", targeted: 95, sent: 40 });
    expect(await runDurableObjectAlarm(pusherStub())).toBe(true);
    expect(fcm.delivered).toHaveLength(80);
    expect(await pusherStub().testLast()).toMatchObject({ sends: 40, started: 0, expanded: 0 });
    expect(await runDurableObjectAlarm(pusherStub())).toBe(true);
    expect(fcm.delivered).toHaveLength(95);
    expect(await pusherStub().pending()).toMatchObject({ jobs: 0, next_at: null, alarm: null }); // nothing left: no alarm
    expect(new Set(fcm.delivered.map((m) => m.token))).toEqual(new Set(tokens));
    expect((await campaign(c.id))!).toMatchObject({ status: "sent", targeted: 95, sent: 95, failed: 0 });
  });

  it("a send FCM can't take now is retried (1 min, 2 min), then counted failed", async () => {
    await pusherStub().testHooks({ paceMs: 60_000 });
    const t = await device(await account({ seen: Date.now() - 30 * DAY }));
    fcm.behaviour.set(t, "unavailable");
    const c = await create({ title: "t", body: "b", audience: { kind: "segment", inactive_days: 7 } });
    const p = await eventually(async () => ((await pusherStub().testLast())?.retried === 1 ? pusherStub().pending() : null), 8000, "first try");
    expect(p.send).toBe(1);
    expect(p.next_at! - Date.now()).toBeGreaterThan(50_000);
    expect(p.next_at! - Date.now()).toBeLessThanOrEqual(60_000);
    const due = () => runInDurableObject(pusherStub(), (_i, st) => void st.storage.sql.exec("UPDATE jobs SET run_at = 0"));
    await due();
    await runDurableObjectAlarm(pusherStub());
    expect(await pusherStub().testLast()).toMatchObject({ sends: 1, retried: 1 });
    expect((await campaign(c.id))!.status).toBe("sending");
    await due();
    await runDurableObjectAlarm(pusherStub());
    expect(await pusherStub().testLast()).toMatchObject({ sends: 1, retried: 0, failed: 1 });
    expect(fcm.sends.filter((s) => s.message.token === t)).toHaveLength(3);
    expect((await campaign(c.id))!).toMatchObject({ status: "failed", sent: 0, failed: 1 });
    expect(await rows("SELECT token FROM push_tokens WHERE token = ?", t)).toHaveLength(1); // not dead: kept
  });

  it("validates the content, the link, the audience and run_at", async () => {
    const aud = { kind: "all" };
    for (const body of [
      { body: "b", audience: aud },
      { title: "x".repeat(61), body: "b", audience: aud },
      { title: "t", body: "y".repeat(181), audience: aud },
      { title: "t", body: "", audience: aud },
      { title: "t", body: "b", link: "https://evil.example", audience: aud },
      { title: "t", body: "b", link: "room:abc", audience: aud },
      { title: "t", body: "b" },
      { title: "t", body: "b", audience: { kind: "everyone" } },
      { title: "t", body: "b", audience: { kind: "all", inactive_days: 3 } },
      { title: "t", body: "b", audience: { kind: "segment", age: 3 } },
      { title: "t", body: "b", audience: { kind: "segment", level_min: 9, level_max: 3 } },
      { title: "t", body: "b", audience: { kind: "segment", new_days: 0 } },
      { title: "t", body: "b", audience: aud, run_at: "tomorrow" },
      { title: "t", body: "b", audience: aud, run_at: Math.floor(Date.now() / 1000) + 31 * 86400 },
    ]) {
      const r = await create(body, 400);
      expect(r.error, JSON.stringify(body)).toBe("bad_request");
    }
    expect(await rows("SELECT * FROM push_campaigns")).toEqual([]);
    // the full title / body lengths are fine; every deep link of the contract is accepted
    await device(await account());
    for (const link of ["home", "daily", "spin", "free", "shop", "shop:avatar:robot", "room:K7QX2M"]) {
      await api(cookie, "push/test", { body: { title: "x".repeat(60), body: "y".repeat(180), link, account_id: (await account()) } });
    }
  });
});

describe("scheduling and cancel", () => {
  it("run_at in the future (unix seconds): scheduled, the alarm at that time; cancel drops it", async () => {
    await device(await account());
    const at = Math.floor(Date.now() / 1000) + 3600;
    const c = await create({ title: "Later", body: "b", audience: { kind: "all" }, run_at: at });
    expect(c).toMatchObject({ status: "scheduled", run_at: at * 1000 });
    expect(await pusherStub().pending()).toMatchObject({ jobs: 1, campaign: 1, next_at: at * 1000, alarm: at * 1000 });
    const x = await api(cookie, `push/campaigns/${c.id}/cancel`, { method: "POST" });
    expect(x).toMatchObject({ id: c.id, status: "canceled" });
    expect(await pusherStub().pending()).toMatchObject({ jobs: 0 });
    expect((await api(cookie, `push/campaigns/${c.id}/cancel`, { method: "POST" }, 409)).error).toBe("bad_state");
    await api(cookie, "push/campaigns/cmp_nosuchcampaig/cancel", { method: "POST" }, 404);
    await api(cookie, "push/campaigns/garbage/cancel", { method: "POST" }, 404);
    expect((await rows<Json>("SELECT action FROM admin_log WHERE action LIKE 'push.%' ORDER BY id")).map((r) => r.action)).toEqual(["push.campaign", "push.cancel"]);
    expect(fcm.sends).toHaveLength(0);
  });

  it("a scheduled campaign is sent when its time comes (epoch ms accepted too)", async () => {
    await pusherStub().testHooks({ paceMs: 60_000 });
    const t = await device(await account());
    const at = Date.now() + 3600_000;
    const c = await create({ title: "Later", body: "b", audience: { kind: "segment" }, run_at: at });
    expect(c).toMatchObject({ status: "scheduled", run_at: at, targeted: 1 });
    // an alarm before its time sends nothing
    await runDurableObjectAlarm(pusherStub());
    expect(fcm.sends).toHaveLength(0);
    expect((await pusherStub().pending()).alarm).toBe(at);
    await runInDurableObject(pusherStub(), (_i, st) => void st.storage.sql.exec("UPDATE jobs SET run_at = 0")); // its time
    await runDurableObjectAlarm(pusherStub());
    expect(fcm.delivered.map((m) => m.token)).toEqual([t]);
    expect((await campaign(c.id))!).toMatchObject({ status: "sent", sent: 1 });
    expect((await api(cookie, `push/campaigns/${c.id}/cancel`, { method: "POST" }, 409)).error).toBe("bad_state");
  });

  it("canceled in D1 but still queued (a lost cancel call): the start finds it canceled and sends nothing", async () => {
    await device(await account());
    const c = await create({ title: "t", body: "b", audience: { kind: "all" }, run_at: Math.floor(Date.now() / 1000) + 600 });
    await DB.prepare("UPDATE push_campaigns SET status = 'canceled' WHERE id = ?").bind(c.id).run();
    await runInDurableObject(pusherStub(), (_i, st) => void st.storage.sql.exec("UPDATE jobs SET run_at = 0"));
    await runDurableObjectAlarm(pusherStub());
    expect(fcm.sends).toHaveLength(0);
    expect((await campaign(c.id))!.status).toBe("canceled");
    expect((await pusherStub().pending()).jobs).toBe(0);
  });

  it("push switched off after queueing: the campaign fails, nothing is sent", async () => {
    await device(await account());
    const c = await create({ title: "t", body: "b", audience: { kind: "all" }, run_at: Math.floor(Date.now() / 1000) + 600 });
    setPushServiceAccount(null);
    await runInDurableObject(pusherStub(), (_i, st) => void st.storage.sql.exec("UPDATE jobs SET run_at = 0"));
    await runDurableObjectAlarm(pusherStub());
    expect((await campaign(c.id))!.status).toBe("failed");
    expect(fcm.sends).toHaveLength(0);
  });
});

describe("preview and segment filters", () => {
  it("counts devices with offers on of live accounts matching every filter", async () => {
    const now = Date.now();
    // level 1: 0 XP; level 2 starts at 100; level 3 at 250; level 5 at 700
    await device(await account({ xp: 0, seen: now, created: now - 2 * DAY })); // new, active, L1
    await device(await account({ xp: 120, seen: now - 15 * DAY, created: now - 60 * DAY })); // L2, inactive 15 d
    await device(await account({ xp: 260, seen: now - 40 * DAY, created: now - 90 * DAY })); // L3, inactive 40 d
    await device(await account({ xp: 700, seen: now, created: now - 5 * DAY })); // L5, new
    await device(await account({ xp: 700, seen: now - 40 * DAY }), { offers: false });
    const preview = async (audience: Json) => (await api(cookie, "push/preview", { body: { audience } })).targeted;
    expect(await preview({ kind: "all" })).toBe(4);
    expect(await preview({ kind: "segment" })).toBe(4);
    expect(await preview({ kind: "segment", inactive_days: 7 })).toBe(2);
    expect(await preview({ kind: "segment", inactive_days: 30 })).toBe(1);
    expect(await preview({ kind: "segment", new_days: 7 })).toBe(2);
    expect(await preview({ kind: "segment", level_min: 2 })).toBe(3);
    expect(await preview({ kind: "segment", level_max: 2 })).toBe(2);
    expect(await preview({ kind: "segment", level_min: 2, level_max: 3 })).toBe(2);
    expect(await preview({ kind: "segment", level_min: 3, level_max: 3 })).toBe(1);
    expect(await preview({ kind: "segment", new_days: 7, level_min: 5 })).toBe(1);
    expect(await preview({ kind: "segment", inactive_days: 7, new_days: 7 })).toBe(0);
    expect((await api(cookie, "push/preview", { body: { audience: { kind: "segment", level_max: 0 } } }, 400)).error).toBe("bad_request");
    expect((await api(cookie, "push/preview", { body: {} }, 400)).error).toBe("bad_request");
    expect(fcm.sends).toHaveLength(0);
  });
});

describe("test sends", () => {
  it("go to every device of the account now (toggles ignored), dead ones deleted, audited", async () => {
    const a = await account();
    const t1 = await device(a);
    const t2 = await device(a, { offers: false, game: false });
    const t3 = await device(a);
    fcm.behaviour.set(t3, "unregistered");
    const r = await api(cookie, "push/test", { body: { title: "Test", body: "Hello me", link: "daily", account_id: a } });
    expect(r).toEqual({ sent: 2, failed: 1, tokens: 3 });
    expect(fcm.delivered.map((m) => m.token).sort()).toEqual([t1, t2].sort());
    expect(fcm.delivered[0]).toMatchObject({ notification: { title: "Test", body: "Hello me" }, data: { link: "daily", kind: "test" }, android: { notification: { channel_id: "offers" } } });
    expect(fcm.delivered[0].data.cid).toBeUndefined();
    expect(await rows("SELECT token FROM push_tokens WHERE token = ?", t3)).toEqual([]);
    const log = await rows<Json>("SELECT target, detail FROM admin_log WHERE action = 'push.test'");
    expect(log).toHaveLength(1);
    expect(log[0].target).toBe(a);
    expect(JSON.parse(log[0].detail)).toEqual({ title: "Test", sent: 2, failed: 1 });
    expect(await rows("SELECT * FROM push_events")).toEqual([]); // not an event push
    expect(await api(cookie, "push/test", { body: { title: "T", body: "B", account_id: await account() } })).toEqual({ sent: 0, failed: 0, tokens: 0 });
  });

  it("an unknown account is 404, a malformed id 400", async () => {
    await api(cookie, "push/test", { body: { title: "T", body: "B", account_id: "acc_aaaaaaaaaaaaaaaa" } }, 404);
    await api(cookie, "push/test", { body: { title: "T", body: "B", account_id: "nope" } }, 400);
    await api(cookie, "push/test", { body: { title: "T", body: "B" } }, 400);
  });
});

describe("rate limits", () => {
  it("at most 4 campaigns in 24 h; canceled ones don't count", async () => {
    await device(await account());
    const later = Math.floor(Date.now() / 1000) + 3600;
    const ids: string[] = [];
    for (let k = 0; k < 4; k++) ids.push((await create({ title: `c${k}`, body: "b", audience: { kind: "all" }, run_at: later })).id);
    expect((await create({ title: "c5", body: "b", audience: { kind: "all" } }, 429)).error).toBe("rate_limited");
    expect((await api(cookie, "push")).limits.campaigns_left).toBe(0);
    await api(cookie, `push/campaigns/${ids[0]}/cancel`, { method: "POST" });
    await create({ title: "c5", body: "b", audience: { kind: "all" }, run_at: later });
    await create({ title: "c6", body: "b", audience: { kind: "all" } }, 429);
    // a campaign older than a day no longer counts
    await DB.prepare("UPDATE push_campaigns SET created_at = created_at - ? WHERE id = ?").bind(DAY + 1000, ids[1]).run();
    await create({ title: "c6", body: "b", audience: { kind: "all" }, run_at: later });
  });

  it("at most 20 test sends per hour", async () => {
    const a = await account();
    await device(a);
    const now = Date.now();
    await DB.batch(
      Array.from({ length: 19 }, () => DB.prepare("INSERT INTO admin_log (at, ip, action, target) VALUES (?, 'x', 'push.test', ?)").bind(now - 1000, a)),
    );
    await DB.prepare("INSERT INTO admin_log (at, ip, action, target) VALUES (?, 'x', 'push.test', ?)").bind(now - 3700_000, a).run(); // an hour ago
    await api(cookie, "push/test", { body: { title: "T", body: "B", account_id: a } });
    expect((await api(cookie, "push")).limits.tests_left).toBe(0);
    expect((await api(cookie, "push/test", { body: { title: "T", body: "B", account_id: a } }, 429)).error).toBe("rate_limited");
    expect(fcm.delivered).toHaveLength(1);
  });
});
