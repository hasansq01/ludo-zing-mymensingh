// Admin economy (ADMIN_API.md "Economy"): gems grant / remove (ledger row, 409 below 0, audit) and
// GET /admin/api/economy (per Bangladesh day aggregates on seeded rows, totals, circulation, days clamping).
import { beforeAll, describe, expect, it } from "vitest";
import { econDayStartMs } from "../src/wallet";
import { api, call, login } from "./admin_helpers";
import { DB, guest, rows, setAccount } from "./acc_helpers";

let cookie = "";
beforeAll(async () => {
  cookie = await login();
});

const get = (path: string, status = 200) => api(cookie, path, {}, status);
const post = (path: string, body: unknown, status = 200) => api(cookie, path, { method: "POST", body }, status);

describe("gems", () => {
  it("grants and removes gems: ledger row 'admin' with delta_gems, 409 below 0, audited", async () => {
    const g = await guest();
    const r = await post(`accounts/${g.id}/gems`, { delta: 50, reason: "compensation" });
    expect(r).toMatchObject({ ok: true, gems: 50, account: { gems: 50 } });
    await post(`accounts/${g.id}/gems`, { delta: -20, reason: "oops" });
    const over = await call(`accounts/${g.id}/gems`, { cookie, body: { delta: -31, reason: "too much" } });
    expect(over.status).toBe(409);
    expect(await over.json()).toMatchObject({ error: "gems", gems: 30 });
    expect(await rows("SELECT delta_coins, delta_gems, gems_after, ref FROM ledger WHERE account_id = ? AND reason = 'admin' ORDER BY id", g.id)).toEqual([
      { delta_coins: 0, delta_gems: 50, gems_after: 50, ref: "compensation" },
      { delta_coins: 0, delta_gems: -20, gems_after: 30, ref: "oops" },
    ]);
    const sum = await rows<{ s: number }>("SELECT SUM(delta_gems) AS s FROM ledger WHERE account_id = ?", g.id);
    expect(sum[0].s).toBe(30);
    const log = await rows<{ detail: string }>("SELECT detail FROM admin_log WHERE action = 'account.gems' AND target = ? ORDER BY id", g.id);
    expect(log.map((l) => JSON.parse(l.detail))).toEqual([
      { delta: 50, reason: "compensation", balance: 50 },
      { delta: -20, reason: "oops", balance: 30 },
    ]);
    const d = await get(`accounts/${g.id}`);
    expect(d.account).toMatchObject({ gems: 30, rerolls: 0, coins: expect.any(Number) });
    expect(d.ledger[0]).toMatchObject({ delta_gems: -20, gems_after: 30 });
  });

  it("validates the body, the id, the method and the session", async () => {
    const g = await guest();
    for (const bad of [{ delta: 0, reason: "abc" }, { delta: 1.5, reason: "abc" }, { delta: "5", reason: "abc" }, { delta: 2_000_000, reason: "abc" }, { delta: 5 }, { delta: 5, reason: "ab" }]) {
      await post(`accounts/${g.id}/gems`, bad, 400);
    }
    await post("accounts/acc_nosuchaccount234/gems", { delta: 5, reason: "abc" }, 404);
    expect((await call(`accounts/${g.id}/gems`, { cookie })).status).toBe(405);
    expect((await call(`accounts/${g.id}/gems`, { body: { delta: 5, reason: "abc" } })).status).toBe(401);
    expect((await call(`accounts/${g.id}/gems`, { cookie, body: { delta: 5, reason: "abc" }, xadmin: false })).status).toBe(403);
  });
});

const HOUR = 3_600_000;
const DAY = 24 * HOUR;

describe("economy report", () => {
  it("needs the session and GET", async () => {
    expect((await call("economy")).status).toBe(401);
    expect((await call("economy", { cookie, method: "POST", body: {} })).status).toBe(405);
  });

  it("aggregates seeded rows per Bangladesh day, with totals and circulation", async () => {
    const today = econDayStartMs(Date.now());
    const g = await guest(); // its start ledger row counts too, so take the baseline after creating it
    await setAccount(g.id, { gems: 7 });
    const bg = (await get("economy?days=7")).totals; // plus whatever other tests put in the window
    const bt = (await get("economy?days=1")).totals;
    const d1 = today - DAY; // yesterday (BD)
    const old = today - 40 * DAY;
    const led = (at: number, reason: string, dc: number, dg: number) =>
      DB.prepare("INSERT INTO ledger (account_id, at, delta_coins, delta_xp, reason, ref, balance_after, delta_gems, gems_after) VALUES ('acc_econ', ?, ?, 0, ?, NULL, 0, ?, 0)").bind(at, dc, reason, dg).run();
    await led(old, "payout", 9999, 0); // outside every window we ask for below
    await led(d1 + HOUR, "payout", 900, 0);
    await led(d1 + 2 * HOUR, "entry", -1000, 0);
    await led(d1 + 3 * HOUR, "level", 0, 5);
    await led(today + HOUR, "reroll", 0, -5);
    await led(today + 2 * HOUR, "payout", 450, 0);
    await led(today + 3 * HOUR, "entry", -500, 0);
    // table matches: yesterday t100 x2 (one won by a ghost), today t500 x1
    const tm = (id: string, at: number, tier: string, entry: number, size: number, fee: number, paid: number, ghost: number) =>
      DB.prepare("INSERT INTO table_matches (match_id, at, game, size, tier, entry, humans, ghosts, pot, fee, paid_humans, winner_ghost) VALUES (?, ?, 'ludo', ?, ?, ?, 1, ?, ?, ?, ?, ?)")
        .bind(id, at, size, tier, entry, size - 1, entry * size, fee, paid, ghost).run();
    await tm("e1", d1 + HOUR, "t100", 100, 2, 20, 180, 0);
    await tm("e2", d1 + 2 * HOUR, "t100", 100, 2, 20, 0, 1);
    await tm("e3", today + HOUR, "t500", 500, 2, 100, 900, 0);
    await tm("eold", old, "t100", 100, 2, 20, 180, 0);
    const en = (id: string, at: number, tier: string, amount: number, status: string, payout: number) =>
      DB.prepare("INSERT INTO entries (id, account_id, at, game, size, tier, amount, status, payout) VALUES (?, 'acc_econ', ?, 'ludo', 2, ?, ?, ?, ?)").bind(id, at, tier, amount, status, payout).run();
    await en("ent_1", d1 + HOUR, "t100", 100, "settled", 180);
    await en("ent_2", d1 + 2 * HOUR, "t100", 100, "settled", 0);
    await en("ent_3", d1 + 2 * HOUR, "t100", 100, "refunded", 0); // refunded: not a coin in
    await en("ent_4", today + HOUR, "t500", 500, "playing", 0);
    const rr = (m: string, at: number, paid: string) => DB.prepare("INSERT INTO rerolls (match_id, account_id, at, paid) VALUES (?, 'acc_econ', ?, ?)").bind(m, at, paid).run();
    await rr("m1", d1 + HOUR, "free");
    await rr("m2", today + HOUR, "gems");
    await rr("m3", today + 2 * HOUR, "gems");
    const ad = (n: string, kind: string, at: number, status: string) =>
      DB.prepare("INSERT INTO ad_rewards (nonce, account_id, kind, created_at, status, granted_at, amount) VALUES (?, 'acc_econ', ?, ?, ?, ?, 1)").bind(n, kind, at, status, status === "granted" ? at : null).run();
    await ad("n1", "reroll", d1 + HOUR, "granted");
    await ad("n2", "gems", today + HOUR, "granted");
    await ad("n3", "gems", today + 2 * HOUR, "pending"); // not granted: not counted
    await ad("n4", "reroll", today + 3 * HOUR, "granted");
    const pu = (t: string, at: number, gems: number, status: string) =>
      DB.prepare("INSERT INTO purchases (token, account_id, product_id, at, gems, status) VALUES (?, 'acc_econ', 'gems_80', ?, ?, ?)").bind(t, at, gems, status).run();
    await pu("t1", d1 + HOUR, 80, "granted");
    await pu("t2", today + HOUR, 220, "granted");
    await pu("t3", today + 2 * HOUR, 80, "voided");

    const e = await get("economy?days=7");
    expect(e).toMatchObject({ days: 7 });
    expect(e.per_day).toHaveLength(7);
    expect(e.per_day.map((p: { day: string }) => p.day)).toEqual([...e.per_day.map((p: { day: string }) => p.day)].sort());
    const [yest, tod] = e.per_day.slice(-2);
    expect(yest).toMatchObject({ coins_created: 900, coins_spent: 1000, gems_created: 5, gems_spent: 0, fees: 40 });
    expect(tod).toMatchObject({ coins_created: bt.coins_created + 450, coins_spent: bt.coins_spent + 500, gems_created: bt.gems_created, gems_spent: bt.gems_spent + 5, fees: 100 });
    expect(e.per_day[0]).toMatchObject({ coins_created: 0, fees: 0 });
    expect(e.to).toBe(tod.day);
    expect(e.totals).toMatchObject({ coins_created: bg.coins_created + 1350, coins_spent: bg.coins_spent + 1500, gems_created: bg.gems_created + 5, gems_spent: bg.gems_spent + 5, fees: 140 });
    expect(e.totals.by_reason).toEqual(
      expect.arrayContaining([
        { reason: "payout", coins_created: 1350, coins_spent: 0, gems_created: 0, gems_spent: 0 },
        { reason: "entry", coins_created: 0, coins_spent: 1500, gems_created: 0, gems_spent: 0 },
      ]),
    );
    expect(e.ledger.filter((r: { day: string }) => r.day === yest.day)).toHaveLength(3);
    expect(e.totals.tables).toEqual([
      { tier: "t100", matches: 2, pot: 400, fee: 40, paid_humans: 180, ghost_wins: 1, ghost_win_rate: 0.5, entries: 2, coins_in: 200, payouts: 180 },
      { tier: "t500", matches: 1, pot: 1000, fee: 100, paid_humans: 900, ghost_wins: 0, ghost_win_rate: 0, entries: 1, coins_in: 500, payouts: 0 },
    ]);
    expect(e.tables.filter((t: { day: string }) => t.day === yest.day)).toHaveLength(1);
    expect(e.totals.rerolls).toEqual({ free: 1, gems: 2 });
    expect(e.totals.ads).toEqual({ reroll: 2, gems: 1 });
    expect(e.totals.purchases).toEqual({ count: 3, gems: 300, voided: 1 });
    expect(e.purchases.find((p: { day: string }) => p.day === tod.day)).toEqual({ day: tod.day, count: 2, gems: 220, voided: 1 });
    expect(e.gems_in_circulation).toBeGreaterThanOrEqual(7);
    expect(e.coins_in_circulation).toBeGreaterThan(0);

    // a window that includes the old rows
    const wide = await get("economy?days=60");
    expect(wide.totals.coins_created).toBe(bg.coins_created + 1350 + 9999);
    expect(wide.totals.tables.find((t: { tier: string }) => t.tier === "t100").matches).toBe(3);
    // a 1-day window: only today
    const one = await get("economy?days=1");
    expect(one.per_day).toHaveLength(1);
    expect(one.totals).toMatchObject({ coins_created: bt.coins_created + 450, fees: 100 });
  });

  it("clamps days to 1-60 (default 14)", async () => {
    expect((await get("economy")).days).toBe(14);
    expect((await get("economy?days=0")).days).toBe(1);
    expect((await get("economy?days=-5")).days).toBe(1);
    expect((await get("economy?days=500")).days).toBe(60);
    expect((await get("economy?days=abc")).days).toBe(14);
    expect((await get("economy?days=500")).per_day).toHaveLength(60);
  });
});
