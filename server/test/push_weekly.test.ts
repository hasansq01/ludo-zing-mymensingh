// The weekly-result pushes (NOTIFICATIONS.md "Weekly result"): the daily cron on Monday (Bangladesh time) queues one
// push per device (Game alerts on) of last week's XP top 100 in the Pusher, once per week; other days and push off:
// nothing.
import { runInDurableObject } from "cloudflare:test";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { cron } from "../src/cron";
import { isMondayBd, setPushServiceAccount, weeklyPushes } from "../src/push";
import { eventually, rows } from "./admin_helpers";
import { PENV, fcmToken, installFakeFcm, pusherStub, uninstallFakeFcm, type FakeFcm } from "./push_helpers";

const DB = PENV.DB;
/** Monday 2026-10-26 03:17 UTC = 09:17 in Bangladesh (the cron's time); last week = 2026-W43. */
const MONDAY = Date.UTC(2026, 9, 26, 3, 17);
const WEEK = "week:2026-W43";
let fcm: FakeFcm;

beforeAll(async () => {
  fcm = await installFakeFcm();
});
afterAll(() => uninstallFakeFcm());
beforeEach(async () => {
  fcm.reset();
  setPushServiceAccount(fcm.serviceAccount);
  await DB.batch([DB.prepare("DELETE FROM scores"), DB.prepare("DELETE FROM push_tokens"), DB.prepare("DELETE FROM push_events"), DB.prepare("DELETE FROM accounts WHERE id LIKE 'acc_w%'")]);
  await runInDurableObject(pusherStub(), async (_i, st) => {
    st.storage.sql.exec("DELETE FROM jobs");
    st.storage.sql.exec("DELETE FROM batches");
    await st.storage.deleteAlarm();
  });
  await pusherStub().testHooks({ paceMs: 20 });
});

let seq = 0;
/** A listed account (3 completed matches) with last week's XP and its devices. */
async function player(xp: number, devices: Array<{ game?: boolean }> = [{}], o: { matches?: number; period?: string } = {}) {
  seq++;
  const id = `acc_w${String(seq).padStart(15, "a").replace(/[0-9]/g, (d) => "abcdefghij"[Number(d)])}`;
  await DB.prepare("INSERT INTO accounts (id, created_at, last_seen, completed_matches) VALUES (?, 0, 0, ?)").bind(id, o.matches ?? 3).run();
  await DB.prepare("INSERT INTO scores (account_id, board, period, value, updated_at) VALUES (?, 'xp', ?, ?, ?)").bind(id, o.period ?? WEEK, xp, seq).run();
  const tokens: string[] = [];
  for (const d of devices) {
    const t = fcmToken("wk");
    tokens.push(t);
    await DB.prepare("INSERT INTO push_tokens (token, account_id, prefs_game, created_at, updated_at) VALUES (?, ?, ?, 0, 0)").bind(t, id, d.game === false ? 0 : 1).run();
  }
  return { id, tokens };
}

describe("weekly result", () => {
  it("Monday: one push per device of last week's top accounts, with the rank; queued once per week", async () => {
    const first = await player(900, [{}, {}]);
    const second = await player(500);
    const third = await player(300, [{ game: false }]); // Game alerts off
    await player(800, [{}], { matches: 1 }); // not listed (fewer than 3 matches)
    await player(999, [{}], { period: "week:2026-W44" }); // this week, not last
    const res = await cron(PENV, MONDAY);
    expect(res.weekly).toBe(3);
    await eventually(async () => fcm.delivered.length === 3, 8000, "weekly sends");
    const byToken = new Map(fcm.delivered.map((m) => [m.token, m]));
    expect(byToken.get(first.tokens[0])).toEqual({
      token: first.tokens[0],
      notification: { title: "Weekly results are in", body: "You finished #1 on last week's board!" },
      data: { link: "leaderboard", kind: "weekly" },
      android: { priority: "high", ttl: "86400s", collapse_key: "weekly", notification: { channel_id: "game", tag: "weekly" } },
    });
    expect(byToken.has(first.tokens[1])).toBe(true);
    expect(byToken.get(second.tokens[0])!.notification.body).toBe("You finished #2 on last week's board!"); // the 800 is not listed
    expect(byToken.has(third.tokens[0])).toBe(false);
    await eventually(async () => (await rows("SELECT * FROM push_events WHERE kind = 'weekly' AND sent = 3")).length === 1, 8000, "counters");
    // the same Monday again (a retried cron): nothing new
    expect((await cron(PENV, MONDAY + 3600_000)).weekly).toBe(0);
    expect((await pusherStub().pending()).jobs).toBe(0);
  });

  it("not on other days, not with push off", async () => {
    await player(100);
    for (let d = 1; d < 7; d++) {
      expect(isMondayBd(MONDAY + d * 86_400_000)).toBe(false);
      expect(await weeklyPushes(PENV, MONDAY + d * 86_400_000)).toBeNull();
    }
    // Sunday 18:00 UTC is already Monday in Bangladesh; Monday 17:59 UTC still is, 18:00 is Tuesday
    expect(isMondayBd(Date.UTC(2026, 9, 25, 18, 0))).toBe(true);
    expect(isMondayBd(Date.UTC(2026, 9, 25, 17, 59))).toBe(false);
    expect(isMondayBd(Date.UTC(2026, 9, 26, 17, 59))).toBe(true);
    setPushServiceAccount(null);
    expect((await cron(PENV, MONDAY)).weekly).toBeNull();
    expect(fcm.sends).toHaveLength(0);
  });

  it("an empty board queues nothing", async () => {
    expect(await weeklyPushes(PENV, MONDAY)).toBe(0);
  });
});
