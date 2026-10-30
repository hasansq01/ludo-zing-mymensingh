// Admin API v2 (ADMIN_API.md "v2"): accounts list / detail / coins / ban / note, pid bans reaching accounts (and
// the ban sources that decide what an unban lifts), leaderboards, the quick-match report, overview additions; auth,
// CSRF and audit as in v1.
import { SELF } from "cloudflare:test";
import { beforeAll, describe, expect, it } from "vitest";
import { grantOnlineMatch } from "../src/accounts";
import * as D from "../src/db";
import { api, call, login } from "./admin_helpers";
import { Client } from "./room_client";
import { DB, ENV, T0, guest, ledgerSum, ludoClaim, newPid, ok, row, rows, setAccount, v1 } from "./acc_helpers";

let cookie = "";
beforeAll(async () => {
  cookie = await login();
});

const get = (path: string, status = 200) => api(cookie, path, {}, status);
const post = (path: string, body: unknown, status = 200) => api(cookie, path, { method: "POST", body }, status);

describe("auth", () => {
  it("v2 endpoints need the session; writes need X-Admin", async () => {
    const a = await guest();
    for (const p of ["accounts", `accounts/${a.id}`, "leaderboards", "quick"]) {
      expect((await call(p)).status, p).toBe(401);
    }
    expect((await call(`accounts/${a.id}/coins`, { cookie, body: { delta: 5, reason: "test" }, xadmin: false })).status).toBe(403);
    expect((await call(`accounts/${a.id}/ban`, { body: { reason: "test" } })).status).toBe(401);
    expect((await call("accounts", { cookie, method: "POST", body: {} })).status).toBe(405);
    expect((await call(`accounts/${a.id}/x`, { cookie })).status).toBe(404);
  });
});

describe("accounts", () => {
  it("lists with q / banned / linked filters and pages with a cursor", async () => {
    const tag = `Admv2${Date.now().toString(36)}`;
    const made = [];
    for (let k = 0; k < 5; k++) {
      const g = await guest();
      await setAccount(g.id, { name: `${tag} ${k}`, last_seen: 1_000_000 + k });
      made.push(g);
    }
    await setAccount(made[1].id, { banned: 1 });
    await setAccount(made[2].id, { google_player_id: `gp-${tag}`, google_name: "G" });
    const all = await get(`accounts?q=${tag}`);
    expect(all.items.map((x: { id: string }) => x.id)).toEqual(made.map((g) => g.id).reverse());
    expect(all.items[0]).toMatchObject({ coins: 2500, level: 1, linked: false, stats: { wins: 0 } });
    expect(all.items[0]).not.toHaveProperty("rev");
    expect((await get(`accounts?q=${tag}&banned=1`)).items.map((x: { id: string }) => x.id)).toEqual([made[1].id]);
    expect((await get(`accounts?q=${tag}&linked=1`)).items.map((x: { id: string }) => x.id)).toEqual([made[2].id]);
    expect((await get(`accounts?q=${tag}&linked=0`)).items).toHaveLength(4);
    // by id prefix, pid prefix, Google id
    expect((await get(`accounts?q=${made[3].id}`)).items[0].id).toBe(made[3].id);
    expect((await get(`accounts?q=${made[4].pid}`)).items[0].id).toBe(made[4].id);
    expect((await get(`accounts?q=gp-${tag}`)).items[0].id).toBe(made[2].id);
    // pages
    const p1 = await get(`accounts?q=${tag}&limit=2`);
    const p2 = await get(`accounts?q=${tag}&limit=2&cursor=${encodeURIComponent(p1.next)}`);
    const p3 = await get(`accounts?q=${tag}&limit=2&cursor=${encodeURIComponent(p2.next)}`);
    expect([...p1.items, ...p2.items, ...p3.items].map((x: { id: string }) => x.id)).toEqual(made.map((g) => g.id).reverse());
    expect(p3.next).toBeNull();
    await get("accounts?banned=2", 400);
    await get("accounts?cursor=zzz", 400);
  });

  it("detail: profile, devices, ledger, claims, grants, matches", async () => {
    const g = await guest();
    await ok("claims", { session: g.session, body: ludoClaim("win"), now: T0 });
    await grantOnlineMatch(ENV, { match_id: `adm-${g.id}`, game: "ludo", results: [{ account_id: g.id, outcome: "finish" }] });
    await D.insertMatch(DB, { code: "ADMV2X", started_at: Date.now(), players: [{ pid: g.pid, name: "x", color: 0, bot: false }], teams: false, pair_ask: false }).run();
    const d = await get(`accounts/${g.id}`);
    expect(d.account).toMatchObject({ id: g.id, coins: 2750, xp: 140, linked: false });
    expect(d.devices.map((x: { pid: string }) => x.pid)).toEqual([g.pid]);
    expect(d.ledger.map((l: { reason: string }) => l.reason)).toEqual(["match", "level", "claim", "start"]);
    expect(d.claims[0]).toMatchObject({ coins: 200, xp: 100, granted: 1, limited: 0, payload: { game: "ludo", result: "win" } });
    expect(d.grants[0]).toMatchObject({ outcome: "finish", coins: 50 });
    expect(d.matches[0]).toMatchObject({ code: "ADMV2X" });
    await get("accounts/acc_nosuchaccount234", 404);
    await get("accounts/bad", 404);
  });

  it("adjusts coins with a reason: ledger row 'admin', audited; can't go below 0", async () => {
    const g = await guest();
    const r = await post(`accounts/${g.id}/coins`, { delta: 750, reason: "lost purchase refund" });
    expect(r).toMatchObject({ ok: true, coins: 3250, account: { coins: 3250 } });
    expect((await ok("me", { session: g.session })).profile).toMatchObject({ coins: 3250, stats: { coinsEarned: 0 } });
    await post(`accounts/${g.id}/coins`, { delta: -750, reason: "oops" });
    const over = await call(`accounts/${g.id}/coins`, { cookie, body: { delta: -6000, reason: "too much" } });
    expect(over.status).toBe(409);
    expect(((await over.json()) as { error: string }).error).toBe("coins");
    expect(await rows("SELECT delta_coins, ref, balance_after FROM ledger WHERE account_id = ? AND reason = 'admin' ORDER BY id", g.id)).toEqual([
      { delta_coins: 750, ref: "lost purchase refund", balance_after: 3250 },
      { delta_coins: -750, ref: "oops", balance_after: 2500 },
    ]);
    expect(await ledgerSum(g.id)).toBe(2500);
    const log = await rows<{ detail: string }>("SELECT detail FROM admin_log WHERE action = 'account.coins' AND target = ? ORDER BY id", g.id);
    expect(log.map((l) => JSON.parse(l.detail))).toEqual([
      { delta: 750, reason: "lost purchase refund", balance: 3250 },
      { delta: -750, reason: "oops", balance: 2500 },
    ]);
    for (const bad of [{ delta: 0, reason: "abc" }, { delta: 1.5, reason: "abc" }, { delta: "5", reason: "abc" }, { delta: 2_000_000, reason: "abc" }, { delta: 5 }, { delta: 5, reason: "ab" }]) {
      await post(`accounts/${g.id}/coins`, bad, 400);
    }
    await post("accounts/acc_nosuchaccount234/coins", { delta: 5, reason: "abc" }, 404);
  });

  it("ban / unban an account: sessions, guest auth and its pids are refused; audited", async () => {
    const g = await guest();
    const r = await post(`accounts/${g.id}/ban`, { reason: "chargeback" });
    expect(r).toMatchObject({ ok: true, kicked: 0, account: { banned: 1, ban_reason: "chargeback" } });
    expect((await v1("me", { session: g.session })).status).toBe(403);
    expect((await v1("auth/guest", { body: { pid: g.pid } })).status).toBe(403);
    expect(await D.readBan(DB, g.pid)).toEqual({ banned: true, reason: "chargeback" }); // the room's hello check
    await post(`accounts/${g.id}/ban`, {}, 400);
    const u = await post(`accounts/${g.id}/unban`, {});
    expect(u).toMatchObject({ ok: true, account: { banned: 0, ban_reason: null } });
    expect((await v1("me", { session: g.session })).status).toBe(200);
    expect(await D.readBan(DB, g.pid)).toEqual({ banned: false, reason: "" });
    const log = await rows<{ action: string }>("SELECT action FROM admin_log WHERE target = ? ORDER BY id", g.id);
    expect(log.map((l) => l.action)).toEqual(["account.ban", "account.unban"]);
    await post("accounts/acc_nosuchaccount234/ban", { reason: "abc" }, 404);
  });

  it("a banned account's device is refused by a room's hello (old clients that send only pid)", async () => {
    const g = await guest();
    await post(`accounts/${g.id}/ban`, { reason: "account ban reaches rooms" });
    const { code } = (await (await SELF.fetch("https://x/v1/rooms", { method: "POST" })).json()) as { code: string };
    const c = await Client.open(code, g.pid, "Banned");
    c.hello();
    const m = await c.waitFor((x) => x.t === "error" || x.t === "welcome");
    expect(m).toMatchObject({ t: "error", code: "banned" });
    c.close();
  });

  it("a pid ban (Players page) also bans that device's account, and unban lifts both", async () => {
    const g = await guest();
    // a v2 device that never joined a friend room has no players row: the ban creates it
    const r = await post(`players/${g.pid}/ban`, { reason: "abusive" });
    expect(r).toMatchObject({ ok: true, account_id: g.id, player: { pid: g.pid, banned: 1 } });
    expect(await row("SELECT banned, ban_reason FROM accounts WHERE id = ?", g.id)).toEqual({ banned: 1, ban_reason: "abusive" });
    expect((await v1("me", { session: g.session })).status).toBe(403);
    const d = await get(`players/${g.pid}`);
    expect(d.account_id).toBe(g.id);
    await post(`players/${g.pid}/unban`, {});
    expect(await row("SELECT banned FROM accounts WHERE id = ?", g.id)).toEqual({ banned: 0 });
    expect((await v1("me", { session: g.session })).status).toBe(200);
    await post(`players/${newPid()}/ban`, { reason: "nobody" }, 404);
  });

  it("ban sources: a pid's unban lifts the account ban only when that pid's ban caused it", async () => {
    const g = await guest();
    await post(`players/${g.pid}/ban`, { reason: "spam" });
    expect(await row("SELECT banned, ban_source FROM accounts WHERE id = ?", g.id)).toEqual({ banned: 1, ban_source: `pid:${g.pid}` });
    expect(await row("SELECT banned, ban_source FROM players WHERE pid = ?", g.pid)).toEqual({ banned: 1, ban_source: "admin_pid" });
    // the console bans the account itself too: from now on the account ban is its own
    await post(`accounts/${g.id}/ban`, { reason: "chargeback" });
    expect(await row("SELECT banned, ban_reason, ban_source FROM accounts WHERE id = ?", g.id)).toEqual({ banned: 1, ban_reason: "chargeback", ban_source: "admin_account" });
    const u = await post(`players/${g.pid}/unban`, {});
    expect(u).toMatchObject({ ok: true, account_id: g.id, account_banned: true });
    expect((await row("SELECT banned FROM accounts WHERE id = ?", g.id))!.banned).toBe(1);
    expect((await v1("me", { session: g.session })).status).toBe(403);
  });

  it("ban sources: with two banned devices, unbanning one hands the account ban to the other", async () => {
    const g = await guest();
    const pid2 = newPid();
    await DB.prepare("INSERT INTO devices (pid, account_id, first_seen, last_seen) VALUES (?, ?, ?, ?)").bind(pid2, g.id, Date.now(), Date.now()).run();
    await post(`players/${g.pid}/ban`, { reason: "first device" });
    const b2 = await post(`players/${pid2}/ban`, { reason: "second device" });
    expect(b2).toMatchObject({ account_id: g.id, account_banned: true });
    // already banned: the second pid ban doesn't take the account ban over
    expect(await row("SELECT ban_reason, ban_source FROM accounts WHERE id = ?", g.id)).toEqual({ ban_reason: "first device", ban_source: `pid:${g.pid}` });
    expect(await post(`players/${g.pid}/unban`, {})).toMatchObject({ account_banned: true });
    expect(await row("SELECT banned, ban_reason, ban_source FROM accounts WHERE id = ?", g.id)).toEqual({ banned: 1, ban_reason: "second device", ban_source: `pid:${pid2}` });
    expect(await post(`players/${pid2}/unban`, {})).toMatchObject({ account_banned: false });
    expect(await row("SELECT banned, ban_source FROM accounts WHERE id = ?", g.id)).toEqual({ banned: 0, ban_source: null });
    expect((await v1("me", { session: g.session })).status).toBe(200);
  });

  it("ban sources: an account ban bans its devices' pids; its unban lifts only those (Players-page bans stay)", async () => {
    const g = await guest();
    const pid2 = newPid();
    await DB.prepare("INSERT INTO devices (pid, account_id, first_seen, last_seen) VALUES (?, ?, ?, ?)").bind(pid2, g.id, Date.now(), Date.now()).run();
    await post(`accounts/${g.id}/ban`, { reason: "fraud" });
    expect(await rows("SELECT pid, banned, ban_reason, ban_source FROM players WHERE pid IN (?, ?) ORDER BY pid = ?", g.pid, pid2, pid2)).toEqual([
      { pid: g.pid, banned: 1, ban_reason: "fraud", ban_source: `account:${g.id}` },
      { pid: pid2, banned: 1, ban_reason: "fraud", ban_source: `account:${g.id}` },
    ]);
    // the console also bans the second device on its own
    await post(`players/${pid2}/ban`, { reason: "device itself" });
    expect(await row("SELECT ban_source FROM players WHERE pid = ?", pid2)).toEqual({ ban_source: "admin_pid" });
    const u = await post(`accounts/${g.id}/unban`, {});
    expect(u).toMatchObject({ ok: true, account: { banned: 0, ban_source: null }, still_banned_pids: [pid2] });
    expect(await D.readBan(DB, g.pid)).toEqual({ banned: false, reason: "" });
    expect(await D.readBan(DB, pid2)).toEqual({ banned: true, reason: "device itself" });
    expect((await v1("me", { session: g.session })).status).toBe(200);
    const log = await row<{ detail: string }>("SELECT detail FROM admin_log WHERE action = 'account.unban' AND target = ? ORDER BY id DESC", g.id);
    expect(JSON.parse(log!.detail)).toEqual({ still_banned_pids: [pid2] });
  });

  it("PATCH note", async () => {
    const g = await guest();
    const r = await api(cookie, `accounts/${g.id}`, { method: "PATCH", body: { note: " VIP tester " } });
    expect(r.account.note).toBe("VIP tester");
    expect((await api(cookie, `accounts/${g.id}`, { method: "PATCH", body: { note: null } })).account.note).toBeNull();
    await api(cookie, `accounts/${g.id}`, { method: "PATCH", body: {} }, 400);
    await api(cookie, `accounts/${g.id}`, { method: "PATCH", body: { note: "x".repeat(501) } }, 400);
    await api(cookie, "accounts/acc_nosuchaccount234", { method: "PATCH", body: { note: "x" } }, 404);
    expect((await rows("SELECT * FROM admin_log WHERE action = 'account.note' AND target = ?", g.id)).length).toBe(2);
  });
});

describe("leaderboards, quick match, overview", () => {
  it("leaderboards: top with account ids and the total", async () => {
    const [a, b] = await Promise.all([guest(), guest()]);
    for (const x of [a, b]) await setAccount(x.id, { completed_matches: 2 }); // the match below is their 3rd: listed
    await grantOnlineMatch(ENV, { match_id: `admlb-${a.id}`, game: "ludo", results: [{ account_id: a.id, outcome: "win" }, { account_id: b.id, outcome: "finish" }] });
    const r = await get("leaderboards?board=wins&period=all");
    expect(r).toMatchObject({ board: "wins", period: "all", week: null });
    expect(r.top.find((x: { account_id: string }) => x.account_id === a.id)).toMatchObject({ value: 1 });
    expect(r.total).toBeGreaterThanOrEqual(1);
    const w = await get("leaderboards?board=xp&period=week");
    expect(w.week).toMatch(/^\d{4}-W\d{2}$/);
    expect(w.top.find((x: { account_id: string }) => x.account_id === a.id)).toMatchObject({ value: 100 });
    expect((await get("leaderboards?board=xp&period=week&week=2020-W01")).top).toEqual([]);
    await get("leaderboards?board=coins", 400);
    await get("leaderboards?period=all&week=2020-W01", 400);
    await get("leaderboards?limit=500", 400);
  });

  it("quick: per day / game / size with rates, plus totals", async () => {
    const today = D.utcDay(Date.now());
    await D.recordQuickStat(ENV, { game: "ludo", size: 2, queued: 10, matched: 8, ghost_filled: 4, wait_ms: 40_000, human_wins: 3, ghost_wins: 1 });
    const r = await get("quick?days=7");
    expect(r.days).toBe(7);
    const day = r.rows.find((x: { day: string; game: string; size: number }) => x.day === today && x.game === "ludo" && x.size === 2);
    expect(day).toMatchObject({ queued: 10, matched: 8, ghost_filled: 4, ghost_fill_rate: 4 / 12, avg_wait_ms: 5000, human_win_rate: 0.75 });
    expect(r.totals.find((x: { game: string; size: number }) => x.game === "ludo" && x.size === 2)).toMatchObject({ day: "total", queued: 10 });
    await get("quick?days=0", 400);
    await get("quick?days=91", 400);
    expect((await get("quick")).days).toBe(14);
  });

  it("overview: accounts, Google-linked, coins in circulation, claims limited today", async () => {
    const before = (await get("overview")).accounts;
    const g = await guest({ now: Math.floor(Date.now() / 1000) });
    await setAccount(g.id, { google_player_id: `gp-ov-${g.id}` });
    await ok("claims", { session: g.session, body: ludoClaim("win", { duration_s: 5 }) });
    const after = (await get("overview")).accounts;
    expect(after.total).toBe(before.total + 1);
    expect(after.linked).toBe(before.linked + 1);
    expect(after.coins_in_circulation).toBe(before.coins_in_circulation + 2500);
    expect(after.claims_limited_today).toBe(before.claims_limited_today + 1);
    expect(after.new_today).toBe(before.new_today + 1);
  });
});
