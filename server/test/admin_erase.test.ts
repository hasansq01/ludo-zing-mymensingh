// Admin "Erase account" (ADMIN_API.md "Erase account"): rows deleted / kept per table, the session and pid afterwards,
// confirm / unknown / busy refusals, the audit row, names scrubbed in matches.
import { beforeAll, describe, expect, it } from "vitest";
import { api, call, login } from "./admin_helpers";
import { DB, guest, ok, row, rows, v1 } from "./acc_helpers";

let cookie = "";
beforeAll(async () => {
  cookie = await login();
});
const erase = (id: string, body: unknown, status = 200) => api(cookie, `accounts/${id}/erase`, { method: "POST", body }, status);
const count = async (sql: string, ...p: unknown[]) => (await row<{ n: number }>(sql, ...p))!.n;

/** A guest with a row in every table that holds its id or pid. */
async function seed() {
  const g = await guest();
  const pub = (await row<{ public_id: string | null }>("SELECT public_id FROM accounts WHERE id = ?", g.id))!.public_id;
  const other = await guest();
  const id = g.id;
  const now = Date.now();
  const st = [
    DB.prepare("INSERT INTO players (pid, name, first_seen, last_seen, banned, ban_reason) VALUES (?, 'Rina', ?, ?, 1, 'x')").bind(g.pid, now, now),
    DB.prepare("INSERT INTO events (at, level, kind, pid, msg) VALUES (?, 'info', 'join', ?, 'Rina joined')").bind(now, g.pid),
    DB.prepare("INSERT INTO player_days (day, pid) VALUES ('2026-10-20', ?)").bind(g.pid),
    DB.prepare("INSERT INTO push_tokens (token, account_id, created_at, updated_at) VALUES (?, ?, ?, ?)").bind("tok" + id, id, now, now),
    DB.prepare("INSERT INTO push_opens (cid, account_id, at) VALUES ('cmp_x', ?, ?)").bind(id, now),
    DB.prepare("INSERT INTO scores (account_id, board, period, value) VALUES (?, 'xp', 'all', 5)").bind(id),
    DB.prepare("INSERT INTO claims (id, account_id, at, payload) VALUES ('c1', ?, ?, '{}')").bind(id, now),
    DB.prepare("INSERT INTO broke_bonus (account_id, day, at, coins) VALUES (?, '2026-10-20', ?, 100)").bind(id, now),
    DB.prepare("INSERT INTO weekly_prizes (period, board, account_id, rank, gems, at) VALUES ('week:2026-W42', 'xp', ?, 1, 50, ?)").bind(id, now),
    DB.prepare("INSERT INTO ad_rewards (nonce, account_id, kind, created_at, status) VALUES (?, ?, 'gems', ?, 'pending')").bind("n1" + id, id, now),
    DB.prepare("INSERT INTO ad_rewards (nonce, account_id, kind, created_at, status, amount) VALUES (?, ?, 'gems', ?, 'granted', 5)").bind("n2" + id, id, now),
    DB.prepare("INSERT INTO match_grants (match_id, account_id, at, outcome) VALUES ('m1', ?, ?, 'win')").bind(id, now),
    DB.prepare("INSERT INTO rerolls (match_id, account_id, at, paid) VALUES ('m1', ?, ?, 'free')").bind(id, now),
    DB.prepare("INSERT INTO purchases (token, account_id, product_id, at, gems) VALUES (?, ?, 'gems_100', ?, 100)").bind("pt" + id, id, now),
    DB.prepare("INSERT INTO entries (id, account_id, at, game, size, tier, amount, status) VALUES (?, ?, ?, 'ludo', 2, 't100', 100, 'settled')").bind("ent_" + id, id, now),
    DB.prepare("INSERT INTO rooms (code, host_pid, host_name, status) VALUES (?, ?, 'Rina', 'closed')").bind("E" + id.slice(4, 9).toUpperCase(), g.pid),
    DB.prepare("INSERT INTO matches (code, started_at, players, result) VALUES ('ERASE1', ?, ?, 'over')").bind(
      now,
      JSON.stringify([
        { pid: g.pid, name: "Rina", color: "red" },
        { pid: "someoneelse000000000", name: "Karim", color: "blue", account_id: other.id },
        { pid: "pidless000000000000", name: "Rina2", color: "green", account_id: id },
        { pid: other.pid, name: "Keep Me", color: "yellow" },
      ]),
    ),
  ];
  await DB.batch(st);
  return { g, pub, other };
}

describe("erase account", () => {
  it("deletes the personal rows, keeps the pseudonymous ones, scrubs names, audits, kills the session", async () => {
    const { g, pub, other } = await seed();
    const id = g.id;
    const r = await erase(id, { confirm: pub ?? id, reason: "Deletion request by email" });
    expect(r).toMatchObject({ ok: true, erased: { accounts: 1, devices: 1, players: 1 } });

    const gone: Array<[string, string]> = [
      ["accounts", "id"], ["devices", "account_id"], ["push_tokens", "account_id"], ["push_opens", "account_id"], ["scores", "account_id"],
      ["claims", "account_id"], ["broke_bonus", "account_id"], ["weekly_prizes", "account_id"],
    ];
    for (const [t, c] of gone) expect(await count(`SELECT COUNT(*) AS n FROM ${t} WHERE ${c} = ?`, id), t).toBe(0);
    for (const t of ["players", "events", "player_days", "devices"]) expect(await count(`SELECT COUNT(*) AS n FROM ${t} WHERE pid = ?`, g.pid), t).toBe(0);
    expect(await rows("SELECT status FROM ad_rewards WHERE account_id = ?", id)).toEqual([{ status: "granted" }]);
    for (const t of ["ledger", "entries", "match_grants", "rerolls", "purchases"]) {
      expect(await count(`SELECT COUNT(*) AS n FROM ${t} WHERE account_id = ?`, id), t).toBeGreaterThan(0);
    }

    // another account is untouched
    expect(await count("SELECT COUNT(*) AS n FROM accounts WHERE id = ?", other.id)).toBe(1);
    expect(await count("SELECT COUNT(*) AS n FROM devices WHERE pid = ?", other.pid)).toBe(1);

    const m = (await row<{ players: string }>("SELECT players FROM matches WHERE code = 'ERASE1'"))!;
    expect(JSON.parse(m.players)).toEqual([
      { pid: g.pid, name: "Deleted player", color: "red" },
      { pid: "someoneelse000000000", name: "Karim", color: "blue", account_id: other.id },
      { pid: "pidless000000000000", name: "Deleted player", color: "green", account_id: id },
      { pid: other.pid, name: "Keep Me", color: "yellow" },
    ]);
    expect((await row<{ host_name: string }>("SELECT host_name FROM rooms WHERE host_pid = ?", g.pid))!.host_name).toBe("Deleted player");

    const log = await rows<{ target: string; detail: string }>("SELECT target, detail FROM admin_log WHERE action = 'account.erase' AND target = ?", id);
    expect(log).toHaveLength(1);
    expect(JSON.parse(log[0].detail)).toEqual({ reason: "Deletion request by email", merged_accounts: 0 });

    // the session is dead
    expect((await v1("me", { session: g.session })).status).toBe(401);
    await api(cookie, `accounts/${id}`, {}, 404);
  });

  it("gives the old pid a fresh account on the next guest sign-in", async () => {
    const g = await guest();
    await erase(g.id, { confirm: g.id, reason: "Deletion request" });
    const b = await ok("auth/guest", { body: { pid: g.pid } });
    expect(b.created).toBe(true);
    expect(b.account.id).not.toBe(g.id);
    expect((await v1("me", { session: b.session })).status).toBe(200);
    expect(await count("SELECT COUNT(*) AS n FROM devices WHERE pid = ? AND account_id = ?", g.pid, b.account.id)).toBe(1);
  });

  it("accepts the public id in any case", async () => {
    const { g, pub } = await seed();
    if (!pub) return;
    await erase(g.id, { confirm: ` ${pub.toLowerCase()} `, reason: "Deletion request" });
    expect(await count("SELECT COUNT(*) AS n FROM accounts WHERE id = ?", g.id)).toBe(0);
  });

  it("refuses a wrong or missing confirm (400) and short reason, deleting nothing", async () => {
    const g = await guest();
    await erase(g.id, { confirm: "LZM-NOPE-NOPE", reason: "Deletion request" }, 400);
    await erase(g.id, { reason: "Deletion request" }, 400);
    await erase(g.id, { confirm: g.id }, 400);
    await erase(g.id, { confirm: g.id, reason: "ab" }, 400);
    expect(await count("SELECT COUNT(*) AS n FROM accounts WHERE id = ?", g.id)).toBe(1);
    expect((await v1("me", { session: g.session })).status).toBe(200);
  });

  it("404 for an unknown or malformed id; needs the session, CSRF header and POST", async () => {
    await erase("acc_nosuchaccount234", { confirm: "acc_nosuchaccount234", reason: "Deletion request" }, 404);
    await erase("nope", { confirm: "nope", reason: "Deletion request" }, 404);
    const g = await guest();
    const body = { confirm: g.id, reason: "Deletion request" };
    expect((await call(`accounts/${g.id}/erase`, { body })).status).toBe(401);
    expect((await call(`accounts/${g.id}/erase`, { cookie, body, xadmin: false })).status).toBe(403);
    expect((await call(`accounts/${g.id}/erase`, { cookie })).status).toBe(405);
  });

  it("409 busy while a coin-table entry is held or playing", async () => {
    for (const status of ["held", "playing"]) {
      const g = await guest();
      await DB.prepare("INSERT INTO entries (id, account_id, at, game, size, tier, amount, status) VALUES (?, ?, ?, 'ludo', 2, 't100', 100, ?)")
        .bind(`ent_${status}${g.id}`, g.id, Date.now(), status)
        .run();
      const r = await erase(g.id, { confirm: g.id, reason: "Deletion request" }, 409);
      expect(r.error).toBe("busy");
      expect(await count("SELECT COUNT(*) AS n FROM accounts WHERE id = ?", g.id)).toBe(1);
      await DB.prepare("UPDATE entries SET status = 'refunded' WHERE account_id = ?").bind(g.id).run();
      await erase(g.id, { confirm: g.id, reason: "Deletion request" });
    }
  });

  it("also erases accounts merged into it", async () => {
    const a = await guest();
    const b = await guest();
    await DB.prepare("UPDATE accounts SET merged_into = ? WHERE id = ?").bind(a.id, b.id).run();
    const r = await erase(a.id, { confirm: a.id, reason: "Deletion request" });
    expect(r.erased.accounts).toBe(2);
    expect(await count("SELECT COUNT(*) AS n FROM devices WHERE pid IN (?, ?)", a.pid, b.pid)).toBe(0);
    expect(JSON.parse((await row<{ detail: string }>("SELECT detail FROM admin_log WHERE action = 'account.erase' AND target = ?", a.id))!.detail).merged_accounts).toBe(1);
  });
});
