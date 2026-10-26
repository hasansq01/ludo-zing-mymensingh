// POST /v1/auth/guest: guest accounts per device, the one-time capped import, PATCH /v1/me, bans of pids.
import { describe, expect, it } from "vitest";
import { accountForPid, getPublicProfile } from "../src/accounts";
import { ENV, T0, guest, ledgerSum, newPid, ok, row, rows, v1 } from "./acc_helpers";

describe("guest accounts", () => {
  it("creates an account for a new pid and returns the same one for that pid later", async () => {
    const pid = newPid();
    const a = await guest({ pid });
    expect(a.body.created).toBe(true);
    expect(a.body.account).toMatchObject({ id: a.id, guest: true, imported: false });
    expect(a.profile).toMatchObject({ coins: 2500, xp: 0, name: "You", room: "night", dice: "classic" });
    expect(a.profile.id).toMatch(/^LZM-/);
    const b = await guest({ pid });
    expect(b.body.created).toBe(false);
    expect(b.id).toBe(a.id);
    expect(b.profile.id).toBe(a.profile.id);
    expect(await rows("SELECT * FROM devices WHERE pid = ?", pid)).toHaveLength(1);
    const led = await rows("SELECT reason, delta_coins, balance_after FROM ledger WHERE account_id = ?", a.id);
    expect(led).toEqual([{ reason: "start", delta_coins: 2500, balance_after: 2500 }]);
    expect(await accountForPid(ENV, pid)).toEqual({ account_id: a.id, banned: false });
    expect(await accountForPid(ENV, newPid())).toBeNull();
  });

  it("parallel first calls for one pid end with one account", async () => {
    const pid = newPid();
    const rs = await Promise.all([0, 1, 2, 3].map(() => v1("auth/guest", { body: { pid }, now: T0 })));
    for (const r of rs) expect(r.status).toBe(200);
    expect(new Set(rs.map((r) => r.body.account.id)).size).toBe(1);
    const d = await row<{ account_id: string }>("SELECT account_id FROM devices WHERE pid = ?", pid);
    expect(d!.account_id).toBe(rs[0].body.account.id);
  });

  it("validates the pid", async () => {
    for (const pid of [undefined, "", "short", "x".repeat(65), "bad pid with spaces!!", 12345678901234567]) {
      expect((await v1("auth/guest", { body: { pid } })).status).toBe(400);
    }
    expect((await v1("auth/guest", { method: "GET" })).status).toBe(405);
    expect((await v1("auth/guest", { body: [] as unknown })).status).toBe(400);
  });

  it("a banned pid cannot create or open a guest account", async () => {
    const pid = newPid();
    await ENV.DB.prepare("INSERT INTO players (pid, name, first_seen, last_seen, banned, ban_reason) VALUES (?, 'B', 1, 1, 1, 'spam')").bind(pid).run();
    const r = await v1("auth/guest", { body: { pid } });
    expect(r.status).toBe(403);
    expect(r.body.error).toBe("banned");
    expect(r.body.msg).toContain("spam");
    expect(await row("SELECT * FROM devices WHERE pid = ?", pid)).toBeNull();
  });
});

describe("the one-time import", () => {
  const local = {
    name: "  Shihab  ",
    id: "LZM-ABCD-EFGH",
    coins: 999_999,
    xp: 12_345,
    stats: { wins: 7, played: 30, streak: 2, bestStreak: 4, coinsEarned: 20_000 },
    rooms: ["night", "cafe", "dream", "no-such-room"],
    room: "dream",
    dice_owned: ["classic", "crema"],
    dice: "crema",
    av_owned: ["ch-rafi"],
    avatar: "ch-rafi",
    claimed: ["first", "veteran", "streak"],
    last_spin: "2099-01-01",
  };

  it("is applied on the first call, capped and checked, with a ledger row and the XP score", async () => {
    const g = await guest({ import: local });
    const p = g.profile;
    expect(g.body.account.imported).toBe(true);
    expect(g.body.import.ok).toBe(true);
    expect(p).toMatchObject({ name: "Shihab", id: "LZM-ABCD-EFGH", coins: 50_000, xp: 12_345, room: "dream", dice: "crema", avatar: "ch-rafi" });
    expect(p.rooms).toEqual(["night", "cafe", "dream"]);
    expect(p.claimed).toEqual(["first", "veteran", "streak"]);
    expect(p.last_spin).toBe("2026-10-21"); // a future spin day becomes today
    expect(g.body.import.notes).toEqual(expect.arrayContaining(["coins: 999999 -> 50000", 'rooms: dropped "no-such-room"']));
    const led = await rows<{ reason: string; delta_coins: number; delta_xp: number }>(
      "SELECT reason, delta_coins, delta_xp FROM ledger WHERE account_id = ? ORDER BY id",
      g.id,
    );
    expect(led).toEqual([
      { reason: "start", delta_coins: 2500, delta_xp: 0 },
      { reason: "import", delta_coins: 47_500, delta_xp: 12_345 },
    ]);
    expect(await ledgerSum(g.id)).toBe(50_000);
    expect(await row("SELECT value FROM scores WHERE account_id = ? AND board = 'xp' AND period = 'all'", g.id)).toEqual({ value: 12_345 });
    // imported XP is not "this week's" XP
    expect(await row("SELECT value FROM scores WHERE account_id = ? AND board = 'xp' AND period LIKE 'week:%'", g.id)).toBeNull();
    expect(await getPublicProfile(ENV, g.id)).toEqual({ name: "Shihab", avatar: "ch-rafi", frame: "classic", level: 21 });
  });

  it("caps XP at 200,000 and happens once per account", async () => {
    const pid = newPid();
    const g = await guest({ pid, import: { coins: 10, xp: 5_000_000 } });
    expect(g.profile).toMatchObject({ coins: 10, xp: 200_000 });
    const again = await guest({ pid, import: { coins: 40_000 } });
    expect(again.body.import).toEqual({ ok: false, error: "already" });
    expect(again.profile.coins).toBe(10);
  });

  it("a later import works only while the account is untouched", async () => {
    const pid = newPid();
    const g = await guest({ pid });
    // untouched: accepted
    const imp = await guest({ pid, import: { coins: 7000 } });
    expect(imp.body.import.ok).toBe(true);
    expect(imp.profile.coins).toBe(7000);

    const pid2 = newPid();
    const h = await guest({ pid: pid2 });
    await ok("shop/buy", { session: h.session, body: { kind: "dice", id: "crema" } });
    const late = await guest({ pid: pid2, import: { coins: 40_000 } });
    expect(late.body.import).toEqual({ ok: false, error: "already" });
    expect(late.profile.coins).toBe(1500);
    expect(g.id).not.toBe(h.id);
  });

  it("an import that is not an object is refused, the account is still created", async () => {
    const g = await guest({ import: "lots of coins" });
    expect(g.body.import).toEqual({ ok: false, error: "invalid" });
    expect(g.body.account.imported).toBe(false);
    expect(g.profile.coins).toBe(2500);
  });
});

describe("PATCH /v1/me", () => {
  it("sets the name and owned / unlocked items only", async () => {
    const g = await guest();
    const s = { session: g.session, method: "PATCH" };
    const r = await ok("me", { ...s, body: { name: "  Rafi   Khan  ", avatar: "pawn-blue", frame: "classic" } });
    expect(r.profile).toMatchObject({ name: "Rafi Khan", avatar: "pawn-blue" });
    expect((await ok("me", { session: g.session })).profile.name).toBe("Rafi Khan");
    expect((await v1("me", { ...s, body: { avatar: "ch-rafi" } })).body).toEqual({ error: "locked", field: "avatar" }); // paid character not bought
    expect((await v1("me", { ...s, body: { frame: "gold" } })).status).toBe(409); // level 5
    expect((await v1("me", { ...s, body: { badge: "first" } })).status).toBe(409);
    expect((await v1("me", { ...s, body: { avatar: "nope" } })).status).toBe(404);
    expect((await v1("me", { ...s, body: { badge: "" } })).status).toBe(200);
    for (const bad of [{ name: "" }, { name: "   " }, { name: 5 }, { coins: 1_000_000 }, { avatar: 3 }]) {
      expect((await v1("me", { ...s, body: bad })).status, JSON.stringify(bad)).toBe(400);
    }
    expect((await v1("me", { session: g.session, method: "DELETE" })).status).toBe(405);
  });

  it("refuses the name \"You\" (what every client calls its own player)", async () => {
    const g = await guest();
    const s = { session: g.session, method: "PATCH" };
    await ok("me", { ...s, body: { name: "Rafi" } });
    for (const name of ["You", " you ", "YOU"]) {
      const r = await v1("me", { ...s, body: { name } });
      expect(r.status, name).toBe(409);
      expect(r.body).toEqual({ error: "reserved", field: "name" });
    }
    expect((await ok("me", { session: g.session })).profile.name).toBe("Rafi");
    expect((await ok("me", { ...s, body: { name: "Younus" } })).profile.name).toBe("Younus"); // only the word itself
  });
});
