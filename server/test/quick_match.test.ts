// Quick match end to end: the Matchmaker queue (FIFO grouping, ghost fill after the wait, human-only tables),
// pre-registered quick rooms (auto-start, closed to strangers, no lobby, no rematch), full matches with ghosts,
// grants, stats, cancel, one entry per account, bans, maintenance, sessions, eviction / resume.
import { evictDurableObject, runInDurableObject } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import type { AdminSnapshot } from "../src/room";
import { DB, eventually, row } from "./admin_helpers";
import { Client, NEAR_GOAL, finishAll, newPid, sleep, stubFor, type Msg } from "./room_client";
import { QuickClient, guest, joinMatched, mmHooks, mmStub, queueAll, quickStats, resetSpies, spyGrants, type Guest } from "./quick_client";

beforeEach(() => resetSpies());
afterEach(() => resetSpies());

const snapshot = async (code: string) => (await stubFor(code).adminSnapshot()) as unknown as AdminSnapshot | null;

/** Queues the guests, joins every matched room and waits for every start. */
async function matchAndJoin(game: string, size: number, gs: Guest[]) {
  const { qs, matched } = await queueAll(game, size, gs);
  const cs: Client[] = [];
  for (let k = 0; k < gs.length; k++) cs.push(await joinMatched(matched[k].code, matched[k].token, gs[k], `Human${k + 1}`));
  const starts = await Promise.all(cs.map((c) => c.wait("start", 8000)));
  return { qs, matched, cs, starts };
}

describe("queue: grouping", () => {
  it("2 players, 1 human: queued, then matched after the wait with a ghost; the room starts at once", async () => {
    await mmHooks("ludo", 2, { wait: 300, room: { tok: NEAR_GOAL, timeScale: 0.05 } });
    const g = await guest();
    const t0 = Date.now();
    const q = await QuickClient.queue("ludo", 2, g, "Rakibul");
    const queued = await q.wait("queued");
    expect(queued).toMatchObject({ t: "queued", position: 1 });
    expect(queued.eta_s).toBeGreaterThanOrEqual(1);
    const m = await q.wait("matched");
    expect(Date.now() - t0).toBeGreaterThanOrEqual(250);
    expect(m.code).toMatch(/^[23456789ABCDEFGHJKMNPQRSTUVWXYZ]{6}$/);
    expect(typeof m.token).toBe("string");
    // the server leaves the close to the client (a close right behind `matched` can drop that frame in some clients)
    await expect(q.waitClosed(400)).rejects.toThrow("socket did not close");
    q.close();

    const c = await joinMatched(m.code, m.token, g, "Rakibul");
    const st = await c.wait("start");
    expect(st.game).toBe("ludo");
    expect(st.seats.length).toBe(2);
    expect(st.state.players).toEqual(["human", "off", "human", "off"]);
    const snap = (await snapshot(m.code))!;
    expect(snap.quick).toBe(true);
    expect(snap.members.filter((x) => x.ghost).length).toBe(1);
    expect(snap.members.find((x) => !x.ghost)!.account).toBe(g.account);
    c.autoplay = true;
    c.playTurn(c.state.turn);
    const [over] = await finishAll([c], 25_000);
    expect([0, 2]).toContain(over.winner);
    expect(c.all("lobby")).toEqual([]); // quick rooms never send a lobby
  });

  it("2 players, 2 humans: matched together at once, no ghosts", async () => {
    await mmHooks("ludo", 2, { wait: 5000 });
    const gs = [await guest(), await guest()];
    const t0 = Date.now();
    const { matched, cs, starts } = await matchAndJoin("ludo", 2, gs);
    expect(Date.now() - t0).toBeLessThan(4000);
    expect(matched[0].code).toBe(matched[1].code);
    expect(starts[0].seats.map((s: Msg) => s.name).sort()).toEqual(["Human1", "Human2"]);
    const snap = (await snapshot(matched[0].code))!;
    expect(snap.members.some((x) => x.ghost)).toBe(false);
    for (const c of cs) c.close();
  });

  for (const humans of [1, 2, 3, 4]) {
    it(`4 players, ${humans} human(s): ${4 - humans} ghost(s)`, async () => {
      await mmHooks("ludo", 4, { wait: humans === 4 ? 5000 : 400 });
      const gs: Guest[] = [];
      for (let k = 0; k < humans; k++) gs.push(await guest());
      const { matched, starts, cs } = await matchAndJoin("ludo", 4, gs);
      expect(new Set(matched.map((m) => m.code)).size).toBe(1);
      expect(starts[0].seats.length).toBe(4);
      expect(starts[0].state.players).toEqual(["human", "human", "human", "human"]);
      const snap = (await snapshot(matched[0].code))!;
      expect(snap.members.filter((x) => x.ghost).length).toBe(4 - humans);
      expect(snap.members.filter((x) => !x.ghost).map((x) => x.account).sort()).toEqual(gs.map((g) => g.account).sort());
      for (const c of cs) c.close();
    });
  }

  it("FIFO: with 3 waiting for a 2-table, the first two are matched, the third waits for its own turn", async () => {
    await mmHooks("ludo", 2, { wait: 600 });
    const gs = [await guest(), await guest(), await guest()];
    const qs: QuickClient[] = [];
    for (const g of gs) {
      qs.push(await QuickClient.queue("ludo", 2, g));
      await sleep(30);
    }
    const [m0, m1] = await Promise.all([qs[0].wait("matched"), qs[1].wait("matched")]);
    expect(m0.code).toBe(m1.code);
    const third = await qs[2].wait("matched", 3000);
    expect(third.code).not.toBe(m0.code);
    const snap = (await snapshot(third.code))!;
    expect(snap.members.filter((x) => x.ghost).length).toBe(1);
  });
});

describe("queue: cancel, close, one entry per account", () => {
  it("cancel leaves the queue: cancelled + close, nobody is matched with it", async () => {
    await mmHooks("ludo", 2, { wait: 400 });
    const a = await guest();
    const qa = await QuickClient.queue("ludo", 2, a);
    await qa.wait("queued");
    qa.send({ t: "cancel" });
    expect(await qa.wait("cancelled")).toEqual({ t: "cancelled" });
    expect(await qa.waitClosed()).toBe(1000);
    // the next person waits alone (ghost-filled), not paired with the cancelled one
    const b = await guest();
    const qb = await QuickClient.queue("ludo", 2, b);
    expect((await qb.wait("queued")).position).toBe(1);
    const m = await qb.wait("matched");
    const snap = (await snapshot(m.code))!;
    expect(snap.members.filter((x) => !x.ghost).map((x) => x.account)).toEqual([b.account]);
  });

  it("closing the socket cancels; positions move up", async () => {
    await mmHooks("ludo", 4, { wait: 2000 });
    const gs = [await guest(), await guest(), await guest()];
    const qs: QuickClient[] = [];
    for (const g of gs) {
      const q = await QuickClient.queue("ludo", 4, g);
      await q.wait("queued");
      qs.push(q);
    }
    expect(qs[2].log.find((m) => m.t === "queued")!.position).toBe(3);
    qs[0].close();
    expect((await qs[2].waitFor((m) => m.t === "queued" && m.position === 2)).position).toBe(2);
    expect((await qs[1].waitFor((m) => m.t === "queued" && m.position === 1)).position).toBe(1);
    const [m1, m2] = await Promise.all([qs[1].wait("matched", 5000), qs[2].wait("matched", 5000)]);
    expect(m1.code).toBe(m2.code);
    const snap = (await snapshot(m1.code))!;
    expect(snap.members.filter((x) => !x.ghost).map((x) => x.account).sort()).toEqual([gs[1].account, gs[2].account].sort());
  });

  it("the same account queuing again replaces its older connection (keeps its place)", async () => {
    await mmHooks("ludo", 4, { wait: 800 });
    const a = await guest();
    const b = await guest();
    const qa = await QuickClient.queue("ludo", 4, a);
    await qa.wait("queued");
    const qb = await QuickClient.queue("ludo", 4, b);
    await qb.wait("queued");
    const qa2 = await QuickClient.queue("ludo", 4, a);
    expect(await qa.waitFor((m) => m.t === "error")).toMatchObject({ code: "replaced" });
    expect(await qa.waitClosed()).toBe(4001);
    expect((await qa2.wait("queued")).position).toBe(1);
    const [m1, m2] = await Promise.all([qa2.wait("matched"), qb.wait("matched")]);
    expect(m1.code).toBe(m2.code);
    const snap = (await snapshot(m1.code))!;
    expect(snap.members.filter((x) => !x.ghost).length).toBe(2);
  });
});

describe("queue: refusals", () => {
  it("no session, a bad session: error session + close 4000", async () => {
    const q = await QuickClient.open("ludo", 2);
    q.send({ t: "hello", v: 1, pid: newPid() });
    expect(await q.wait("error")).toMatchObject({ code: "session" });
    expect(await q.waitClosed()).toBe(4000);
    const q2 = await QuickClient.open("ludo", 2);
    q2.send({ t: "hello", v: 1, pid: newPid(), session: "acc_aaaaaaaaaaaaaaaa.9999999999.forgedforgedforgedforged" });
    expect(await q2.wait("error")).toMatchObject({ code: "session" });
    expect(await q2.waitClosed()).toBe(4000);
  });

  it("the session may come in the query string", async () => {
    await mmHooks("sl", 2, { wait: 200 });
    const g = await guest();
    const q = await QuickClient.open("sl", 2, `&session=${encodeURIComponent(g.session)}`);
    q.send({ t: "hello", v: 1, pid: g.pid });
    expect((await q.wait("matched")).code).toBeTruthy();
  });

  it("a banned account is refused: error banned + close 4003", async () => {
    const g = await guest();
    await DB.prepare("UPDATE accounts SET banned = 1, ban_reason = 'cheating' WHERE id = ?").bind(g.account).run();
    const q = await QuickClient.queue("ludo", 2, g);
    const e = await q.wait("error");
    expect(e.code).toBe("banned");
    expect(e.msg).toMatch(/cheating/);
    expect(await q.waitClosed()).toBe(4003);
  });

  it("maintenance refuses new queue entries", async () => {
    await DB.prepare("INSERT INTO config (key, value) VALUES ('maintenance', '1'), ('motd', 'Back soon') ON CONFLICT(key) DO UPDATE SET value = excluded.value").run();
    try {
      const g = await guest();
      const q = await QuickClient.queue("ludo", 2, g);
      expect(await q.wait("error")).toMatchObject({ code: "maintenance", msg: "Back soon" });
      expect(await q.waitClosed()).toBe(4000);
    } finally {
      await DB.prepare("DELETE FROM config WHERE key IN ('maintenance', 'motd')").run();
    }
  });

  it("bad routes: wrong game / size 400, no upgrade 426, other paths 404", async () => {
    const { SELF } = await import("cloudflare:test");
    const up = { headers: { Upgrade: "websocket" } };
    expect((await SELF.fetch("https://x/v1/quick/ws?game=chess&players=2", up)).status).toBe(400);
    expect((await SELF.fetch("https://x/v1/quick/ws?game=ludo&players=3", up)).status).toBe(400);
    expect((await SELF.fetch("https://x/v1/quick/ws?game=ludo&players=2")).status).toBe(426);
    expect((await SELF.fetch("https://x/v1/quick/nope", up)).status).toBe(404);
  });

  it("other messages: hello first, unknown types", async () => {
    const q = await QuickClient.open("ludo", 2);
    q.send({ t: "cancel" });
    expect(await q.wait("error")).toMatchObject({ code: "bad_message" });
    q.send({ t: "ping" });
    expect((await q.wait("pong")).now).toBeGreaterThan(0);
    q.close();
  });
});

describe("quick rooms", () => {
  it("closed to strangers, no settings, no rematch, auto-start when someone never connects", async () => {
    await mmHooks("ludo", 2, { wait: 5000, room: { timeScale: 0.05, tok: NEAR_GOAL } });
    const gs = [await guest(), await guest()];
    const { matched } = await queueAll("ludo", 2, gs);
    const code = matched[0].code;
    // a stranger
    const s = await Client.open(code);
    s.hello();
    expect(await s.wait("error")).toMatchObject({ code: "full" });
    // only the first human connects: the match starts at the auto-start time (10 s scaled)
    const t0 = Date.now();
    const c = await joinMatched(code, matched[0].token, gs[0], "Human1");
    expect(c.id).toBeGreaterThan(0);
    const st = await c.wait("start", 3000);
    expect(Date.now() - t0).toBeGreaterThanOrEqual(300);
    const other = st.seats.find((x: Msg) => x.id !== c.id);
    expect(other.online).toBe(false);
    c.send({ t: "settings", teams: true });
    expect(await c.waitFor((m) => m.t === "error")).toMatchObject({ code: "bad_action" });
    // the absent human's seat becomes a (labelled) bot after the grace
    await c.waitFor((m) => m.t === "act" && m.a.k === "mode" && m.a.c === other.color && m.a.mode === "cpu", 3000);
    c.autoplay = true;
    c.playTurn(c.state.turn);
    await finishAll([c], 25_000);
    c.send({ t: "start" });
    expect(await c.waitFor((m) => m.t === "error")).toMatchObject({ code: "bad_action" });
    expect(c.all("lobby")).toEqual([]);
  });

  it("nobody connects: the room is deleted at the auto-start time", async () => {
    await mmHooks("ludo", 2, { wait: 100, room: { timeScale: 0.02 } });
    const g = await guest();
    const { matched } = await queueAll("ludo", 2, [g]);
    await eventually(async () => (await snapshot(matched[0].code)) === null, 3000, "room deleted");
  });

  it("all humans leave: the match is abandoned at once, nothing is granted", async () => {
    const grants = spyGrants();
    await mmHooks("ludo", 4, { wait: 200 });
    const gs = [await guest(), await guest()];
    const { matched, cs } = await matchAndJoin("ludo", 4, gs);
    const code = matched[0].code;
    cs[0].send({ t: "leave" });
    await cs[1].waitFor((m) => m.t === "act" && m.a.k === "mode" && m.a.mode === "cpu");
    expect(await snapshot(code)).not.toBeNull();
    cs[1].send({ t: "leave" });
    await eventually(async () => (await snapshot(code)) === null, 3000, "room gone");
    const mrow = await eventually(() => row("SELECT * FROM matches WHERE code = ? AND result = 'abandoned'", code), 5000, "abandoned row");
    expect(mrow).toMatchObject({ quick: 1, ghosts: 2, game: "ludo" });
    await sleep(100);
    expect(grants).toEqual([]);
  });
});

describe("grants and stats", () => {
  it("over: grantOnlineMatch for the humans only (win / finish), quick stats, matches row", async () => {
    const grants = spyGrants();
    await mmHooks("ludo", 4, { wait: 200, room: { tok: NEAR_GOAL, timeScale: 0.05 } });
    const gs = [await guest(), await guest()];
    const { matched, cs } = await matchAndJoin("ludo", 4, gs);
    const code = matched[0].code;
    const snap = (await snapshot(code))!;
    const ghostColors = new Set(snap.members.filter((x) => x.ghost).map((x) => x.color));
    for (const c of cs) {
      c.autoplay = true;
      c.playTurn(c.state.turn);
    }
    const [over] = await finishAll(cs, 25_000);
    await eventually(async () => grants.length === 1, 5000, "grant");
    const g = grants[0];
    expect(g.game).toBe("ludo");
    expect(g.match_id).toMatch(new RegExp(`^${code}-\\d+$`));
    expect(g.results.map((r) => r.account_id).sort()).toEqual(gs.map((x) => x.account).sort());
    const winnerGhost = ghostColors.has(over.winner);
    for (const r of g.results) {
      const c = cs[gs.findIndex((x) => x.account === r.account_id)];
      expect(r.outcome).toBe(c.color === over.winner ? "win" : "finish");
    }
    // the real grant ran: one match_grants row per human
    const rows = await eventually(async () => {
      const x = (await DB.prepare("SELECT * FROM match_grants WHERE match_id = ?").bind(g.match_id).all()).results;
      return x.length === 2 ? x : null;
    }, 5000, "match_grants");
    expect(rows.length).toBe(2);

    const stats = quickStats();
    expect(stats.find((s) => s.queued)).toMatchObject({ game: "ludo", size: 4, queued: 1 });
    const mstat = stats.find((s) => s.matched);
    expect(mstat).toMatchObject({ game: "ludo", size: 4, matched: 2, ghost_filled: 2 });
    expect(mstat!.wait_ms).toBeGreaterThanOrEqual(0);
    await eventually(async () => stats.some((s) => s.human_wins || s.ghost_wins), 3000, "win stat");
    expect(stats.find((s) => s.human_wins || s.ghost_wins)).toEqual(
      winnerGhost ? { game: "ludo", size: 4, ghost_wins: 1 } : { game: "ludo", size: 4, human_wins: 1 },
    );
    const mrow = await eventually(() => row("SELECT * FROM matches WHERE code = ? AND result = 'over'", code), 5000, "match row");
    expect(mrow).toMatchObject({ game: "ludo", quick: 1, ghosts: 2, human_won: winnerGhost ? 0 : 1 });
    const players = JSON.parse(mrow.players as string);
    expect(players.filter((p: Msg) => p.ghost).length).toBe(2);
    const qrow = await eventually(() => row("SELECT * FROM quick_stats WHERE game = 'ludo' AND size = 4"), 5000, "quick_stats row");
    expect(qrow.matched).toBeGreaterThanOrEqual(2);
  });
});

describe("matchmaker eviction", () => {
  it("an evicted matchmaker resumes the queue from the sockets and its alarm", async () => {
    await mmHooks("sl", 4, { wait: 600 });
    const a = await guest();
    const b = await guest();
    const qa = await QuickClient.queue("sl", 4, a);
    await qa.wait("queued");
    await evictDurableObject(mmStub("sl", 4));
    const qb = await QuickClient.queue("sl", 4, b);
    expect((await qb.wait("queued")).position).toBe(2);
    await evictDurableObject(mmStub("sl", 4));
    const [ma, mb] = await Promise.all([qa.wait("matched", 4000), qb.wait("matched", 4000)]);
    expect(ma.code).toBe(mb.code);
    const snap = (await snapshot(ma.code))!;
    expect(snap.game).toBe("sl");
    expect(snap.members.filter((x) => x.ghost).length).toBe(2);
    // the queue's state is in storage + attachments only
    const meta = await runInDurableObject(mmStub("sl", 4), (_i, st) => st.storage.kv.get("meta"));
    expect(meta).toMatchObject({ game: "sl", size: 4 });
  });

  it("a fresh instance on the same storage groups from the attachments (alarm run by hand)", async () => {
    await mmHooks("ludo", 2, { wait: 150 });
    const a = await guest();
    const qa = await QuickClient.queue("ludo", 2, a);
    await qa.wait("queued");
    const { Matchmaker } = await import("../src/matchmaker");
    await sleep(200);
    await runInDurableObject(mmStub("ludo", 2), async (_inst, state) => {
      const fresh = new Matchmaker(state, (await import("./room_client")).E);
      await fresh.alarm();
    });
    expect((await qa.wait("matched", 3000)).code).toBeTruthy();
  });
});
