// Accounts in friend rooms: hello with a session (or only the pid of a guest account), account bans, the level from
// the public profile, and the online rewards at `over` (grantOnlineMatch: win / finish / left, retried on failure).
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import type { AdminSnapshot } from "../src/room";
import { DB, eventually } from "./admin_helpers";
import { Client, NEAR_GOAL, createRoom, finishAll, newPid, startAll, stubFor } from "./room_client";
import { guest, resetSpies, spyGrants } from "./quick_client";

beforeEach(() => resetSpies());
afterEach(() => resetSpies());

const snapshot = async (code: string) => (await stubFor(code).adminSnapshot()) as unknown as AdminSnapshot;

describe("hello with accounts", () => {
  it("a session gives the member its account; a guest's pid alone finds its account too; plain pids have none", async () => {
    const code = await createRoom({ ratePerSec: 1000 });
    const a = await guest();
    const b = await guest();
    const ca = await Client.join(code, { pid: a.pid, session: a.session, name: "A" });
    const cb = await Client.join(code, { pid: b.pid, name: "B" }); // an old client: no session
    const cc = await Client.join(code, { pid: newPid(), name: "C" }); // never called /v1/auth/guest
    const snap = await snapshot(code);
    expect(snap.members.map((m) => m.account)).toEqual([a.account, b.account, undefined]);
    expect(snap.members.map((m) => m.level)).toEqual([1, 1, undefined]);
    const l = await ca.waitFor((m) => m.t === "lobby" && m.members.length === 3);
    expect(l.members.map((m: { level: number }) => m.level)).toEqual([1, 1, 1]);
    for (const c of [ca, cb, cc]) c.close();
  });

  it("the level comes from the account's XP", async () => {
    const a = await guest();
    await DB.prepare("UPDATE accounts SET xp = 1000 WHERE id = ?").bind(a.account).run();
    const code = await createRoom();
    const c = await Client.join(code, { pid: a.pid, session: a.session });
    const l = await c.wait("lobby");
    expect(l.members[0].level).toBeGreaterThan(1);
  });

  it("a banned account is refused with a session and with its pid alone", async () => {
    const a = await guest();
    await DB.prepare("UPDATE accounts SET banned = 1, ban_reason = 'abuse' WHERE id = ?").bind(a.account).run();
    const code = await createRoom();
    for (const session of [a.session, undefined]) {
      const c = await Client.open(code, a.pid);
      c.session = session;
      c.hello();
      const e = await c.wait("error");
      expect(e.code).toBe("banned");
      expect(await c.waitClosed()).toBe(4003);
    }
  });

  it("the same account on a new device takes back its member", async () => {
    const code = await createRoom();
    const a = await guest();
    const c1 = await Client.join(code, { pid: a.pid, session: a.session, name: "A" });
    const c2 = await Client.join(code, { pid: newPid(), session: a.session, name: "A2" });
    expect(c2.id).toBe(c1.id);
    expect(await c1.waitClosed()).toBe(4001);
  });
});

describe("online rewards at over", () => {
  it("win / finish for the players, idempotent ledger rows", async () => {
    const grants = spyGrants();
    const code = await createRoom({ ratePerSec: 1000, tok: NEAR_GOAL });
    const gs = [await guest(), await guest()];
    const cs = [];
    for (const g of gs) cs.push(await Client.join(code, { pid: g.pid, session: g.session }));
    await cs[0].waitFor((m) => m.t === "lobby" && m.members.length === 2);
    for (const c of cs) c.autoplay = true;
    await startAll(cs);
    const [over] = await finishAll(cs);
    await eventually(async () => grants.length === 1, 5000, "grant");
    expect(grants[0].game).toBe("ludo");
    expect(grants[0].match_id).toMatch(new RegExp(`^${code}-\\d+$`));
    expect(grants[0].results).toEqual(
      cs.map((c, k) => ({ account_id: gs[k].account, outcome: c.color === over.winner ? "win" : "finish" })),
    );
    const ledger = await eventually(async () => {
      const r = (await DB.prepare("SELECT account_id, delta_coins FROM ledger WHERE ref = ?").bind(grants[0].match_id).all()).results;
      return r.length === 2 ? r : null;
    }, 5000, "ledger rows");
    expect(ledger.length).toBe(2);
  });

  it("a player who left gets left; S&L matches grant with game sl", async () => {
    const grants = spyGrants();
    const code = await createRoom({ ratePerSec: 1000, timeScale: 0.05, slPos: [90, 90, 90] });
    const gs = [await guest(), await guest(), await guest()];
    const cs = [];
    for (const g of gs) cs.push(await Client.join(code, { pid: g.pid, session: g.session }));
    cs[0].send({ t: "settings", game: "sl" });
    await cs[2].waitFor((m) => m.t === "lobby" && m.members.length === 3 && m.settings.game === "sl");
    await startAll(cs);
    cs[2].send({ t: "leave" });
    for (const c of cs.slice(0, 2)) {
      c.autoplay = true;
      c.playTurn(c.state.players[c.state.turn].c);
    }
    const [over] = await finishAll(cs.slice(0, 2), 25_000);
    await eventually(async () => grants.length === 1, 5000, "grant");
    expect(grants[0].game).toBe("sl");
    const byAcc = Object.fromEntries(grants[0].results.map((r) => [r.account_id, r.outcome]));
    expect(byAcc[gs[2].account]).toBe("left");
    for (const k of [0, 1]) expect(byAcc[gs[k].account]).toBe(over.winner === cs[k].color ? "win" : "finish");
  }, 30_000);

  it("a failed grant is retried from the alarm", async () => {
    const grants = spyGrants({ fail: 2 });
    const code = await createRoom({ ratePerSec: 1000, tok: NEAR_GOAL, timeScale: 0.01 });
    const gs = [await guest(), await guest()];
    const cs = [];
    for (const g of gs) cs.push(await Client.join(code, { pid: g.pid, session: g.session }));
    await cs[0].waitFor((m) => m.t === "lobby" && m.members.length === 2);
    for (const c of cs) c.autoplay = true;
    await startAll(cs);
    await finishAll(cs);
    await eventually(async () => grants.length === 3, 8000, "three tries");
    const id = grants[0].match_id;
    expect(grants.every((g) => g.match_id === id)).toBe(true);
    await eventually(async () => {
      const r = (await DB.prepare("SELECT * FROM match_grants WHERE match_id = ?").bind(id).all()).results;
      return r.length === 2;
    }, 5000, "granted after the retries");
  });
});
