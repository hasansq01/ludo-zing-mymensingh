// POST /v1/rewards/daily|spin|free, GET /v1/rewards and POST /v1/achievements/claim: the server clock with the
// Bangladesh day (UTC+6), cooldowns with next_at, ledger rows, parallel claims.
import { describe, expect, it } from "vitest";
import { PRIZES } from "../src/econ";
import { DAY, T0, guest, ledgerSum, ludoClaim, ok, rows, v1 } from "./acc_helpers";

/** Thursday 00:00 in Bangladesh = Wednesday 18:00 UTC: the economy day after T0's. */
const NEXT_BD_DAY = T0 + 12 * 3600;

describe("daily reward", () => {
  it("pays the calendar once per Bangladesh day and continues the run the next day", async () => {
    const a = await guest();
    const d1 = await ok("rewards/daily", { session: a.session, body: {}, now: T0 });
    expect(d1).toMatchObject({ ok: true, coins: 100, day: 1, cycle: 0, next_at: NEXT_BD_DAY });
    expect(d1.profile.coins).toBe(5100);
    expect(d1.profile.daily).toMatchObject({ streak: 1, last: "2026-10-21" });

    const again = await v1("rewards/daily", { session: a.session, body: {}, now: NEXT_BD_DAY - 60 });
    expect(again.status).toBe(409);
    expect(again.body).toMatchObject({ error: "claimed", next_at: NEXT_BD_DAY });

    // one minute after Bangladesh midnight (18:01 UTC, still Wednesday in UTC) the next day is open
    const d2 = await ok("rewards/daily", { session: a.session, body: {}, now: NEXT_BD_DAY + 60 });
    expect(d2).toMatchObject({ coins: 150, day: 2, next_at: NEXT_BD_DAY + DAY });

    // day 4 is the Crema dice (a run of four days)
    await ok("rewards/daily", { session: a.session, body: {}, now: NEXT_BD_DAY + DAY + 60 });
    const d4 = await ok("rewards/daily", { session: a.session, body: {}, now: NEXT_BD_DAY + 2 * DAY + 60 });
    expect(d4).toMatchObject({ day: 4, dice: "crema", coins: 0 });
    expect(d4.profile.dice_owned).toContain("crema");
    const led = await rows<{ delta_coins: number; ref: string }>("SELECT delta_coins, ref FROM ledger WHERE account_id = ? AND reason = 'daily' ORDER BY id", a.id);
    expect(led.map((l) => l.delta_coins)).toEqual([100, 150, 200]); // the dice day changes no coins: no ledger row
    expect(led[0].ref).toBe("2026-10-21:c0:d1");
    expect(await ledgerSum(a.id)).toBe(5450);
  });

  it("GET /v1/rewards shows the calendar, the wheel and free coins", async () => {
    const a = await guest();
    const s = await ok("rewards", { session: a.session, now: T0 });
    expect(s.today).toBe("2026-10-21");
    expect(s.daily.state).toMatchObject({ claimable: true, day: 1 });
    expect(s.daily.state.rewards).toHaveLength(7);
    expect(s.spin).toMatchObject({ available: true });
    expect(s.free).toMatchObject({ available: true, amount: 300 });
    await ok("rewards/daily", { session: a.session, body: {}, now: T0 });
    await ok("rewards/free", { session: a.session, body: {}, now: T0 });
    const t = await ok("rewards", { session: a.session, now: T0 + 60 });
    expect(t.daily.state.claimable).toBe(false);
    expect(t.daily.next_at).toBe(NEXT_BD_DAY);
    expect(t.free).toMatchObject({ available: false, next_at: T0 + 14400 });
    expect((await v1("rewards", { session: a.session, method: "POST" })).status).toBe(405);
  });

  it("two parallel claims pay once", async () => {
    const a = await guest();
    const rs = await Promise.all([0, 1, 2].map(() => v1("rewards/daily", { session: a.session, body: {}, now: T0 })));
    expect(rs.filter((r) => r.status === 200)).toHaveLength(1);
    expect(rs.filter((r) => r.status === 409)).toHaveLength(2);
    expect((await ok("me", { session: a.session })).profile.coins).toBe(5100);
  });
});

describe("daily spin", () => {
  it("draws a segment on the server, once per day", async () => {
    const a = await guest();
    const s = await ok("rewards/spin", { session: a.session, body: {}, now: T0 });
    expect(PRIZES[s.index]).toBe(s.prize);
    expect(s.profile.coins).toBe(5000 + s.prize);
    expect(s.next_at).toBe(NEXT_BD_DAY);
    expect(await v1("rewards/spin", { session: a.session, body: {}, now: T0 + 3600 })).toMatchObject({ status: 409, body: { error: "spun", next_at: NEXT_BD_DAY } });
    const t = await ok("rewards/spin", { session: a.session, body: {}, now: NEXT_BD_DAY });
    expect(t.profile.coins).toBe(5000 + s.prize + t.prize);
    const led = await rows("SELECT delta_coins FROM ledger WHERE account_id = ? AND reason = 'spin'", a.id);
    expect(led).toEqual([{ delta_coins: s.prize }, { delta_coins: t.prize }]);
  });

  it("parallel spins pay once", async () => {
    const a = await guest();
    const rs = await Promise.all([0, 1, 2, 3].map(() => v1("rewards/spin", { session: a.session, body: {}, now: T0 })));
    expect(rs.filter((r) => r.status === 200)).toHaveLength(1);
    const won = rs.find((r) => r.status === 200)!.body.prize;
    expect((await ok("me", { session: a.session })).profile.coins).toBe(5000 + won);
  });
});

describe("free coins", () => {
  it("300 every 4 hours", async () => {
    const a = await guest();
    const f = await ok("rewards/free", { session: a.session, body: {}, now: T0 });
    expect(f).toMatchObject({ ok: true, coins: 300, next_at: T0 + 14400 });
    expect(await v1("rewards/free", { session: a.session, body: {}, now: T0 + 14399 })).toMatchObject({ status: 409, body: { error: "cooldown", next_at: T0 + 14400 } });
    const g = await ok("rewards/free", { session: a.session, body: {}, now: T0 + 14400 });
    expect(g.profile.coins).toBe(5600);
    expect(await rows("SELECT delta_coins, balance_after FROM ledger WHERE account_id = ? AND reason = 'free' ORDER BY id", a.id)).toEqual([
      { delta_coins: 300, balance_after: 5300 },
      { delta_coins: 300, balance_after: 5600 },
    ]);
  });
});

describe("achievements", () => {
  it("claims a done achievement once", async () => {
    const a = await guest();
    const claim = (id: string) => v1("achievements/claim", { session: a.session, body: { id }, now: T0 });
    expect(await claim("first")).toMatchObject({ status: 409, body: { error: "not_done" } });
    expect(await claim("nope")).toMatchObject({ status: 404, body: { error: "unknown" } });
    expect((await v1("achievements/claim", { session: a.session, body: { id: 3 } })).status).toBe(400);
    await ok("claims", { session: a.session, body: ludoClaim("win"), now: T0 });
    const r = await claim("first");
    expect(r.status).toBe(200);
    expect(r.body).toMatchObject({ ok: true, coins: 200, progress: { done: true, claimed: true } });
    expect(r.body.profile.claimed).toEqual(["first"]);
    expect(r.body.profile.coins).toBe(5000 + 200 + 200);
    expect(await claim("first")).toMatchObject({ status: 409, body: { error: "claimed" } });
    expect(await rows("SELECT delta_coins, ref FROM ledger WHERE account_id = ? AND reason = 'achievement'", a.id)).toEqual([{ delta_coins: 200, ref: "first" }]);
  });
});
