// Recent players, friends and invites (social.ts, PROTOCOL.md "Recent players, friends and invites"): who played is
// recorded when a match starts (people and ghosts alike, newest 30), friends are one-way, invites reach a person on
// the inviter's lists from the inviter's own friend room (listed, pushed after the answer), and an invite to a ghost
// or to someone with invites off is answered, stored and rate-limited exactly like one a person ignores. Account
// erase removes all of it.
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { SOCIAL, newUid, playedStmts, pruneSocial } from "../src/social";
import { setPushFetcher, setPushServiceAccount } from "../src/push";
import { eventually } from "./admin_helpers";
import { DB, guest as accGuest, ok, row, rows, v1, type Guest, type Json } from "./acc_helpers";
import { api, login } from "./admin_helpers";
import { QuickClient, joinMatched, mmHooks, walk } from "./quick_client";
import { Client, sleep } from "./room_client";
import { fcmToken, installFakeFcm, register, uninstallFakeFcm, type FakeFcm } from "./push_helpers";

/** Unix seconds now (the X-Test-Now clock of the invite calls; the Room stamps recent rows with the real clock). */
const NOW = Math.floor(Date.now() / 1000);
const MIN = 60;
const UID = /^[0-9a-f]{16}$/;

async function guest(): Promise<Guest> {
  return accGuest({ now: NOW });
}

const social = (g: Guest, now = NOW) => ok("social", { session: g.session, now });
const invites = async (g: Guest, now = NOW) => (await ok("social/invites", { session: g.session, now })).invites as Json[];
const invite = (g: Guest, uid: string, code: string, now = NOW) => v1("social/invites", { session: g.session, body: { uid, code }, now });

/** A friend room with these guests in the lobby (first = host). */
async function lobby(gs: Guest[]): Promise<{ code: string; cs: Client[] }> {
  const code = (await ok("rooms", { method: "POST" })).code as string;
  const cs: Client[] = [];
  for (const [k, g] of gs.entries()) {
    const c = await Client.join(code, { pid: g.pid, session: g.session, name: `P${k + 1}` });
    await c.waitFor((m) => m.t === "lobby" && m.members.length === k + 1);
    cs.push(c);
  }
  return { code, cs };
}

/** The guests play a friend-room match (it starts; that's when it counts). */
async function playFriends(gs: Guest[]): Promise<{ code: string; cs: Client[] }> {
  const l = await lobby(gs);
  l.cs[0].send({ t: "start" });
  await Promise.all(l.cs.map((c) => c.wait("start")));
  return l;
}

/** g plays a 2-seat quick match alone: the other seat is a ghost. Returns the room's clients (closed later). */
async function playQuick(g: Guest, game = "ludo"): Promise<{ code: string; c: Client; q: QuickClient }> {
  await mmHooks(game, 2, { wait: 50 });
  const q = await QuickClient.queue(game, 2, { pid: g.pid, account: g.id, session: g.session }, "Me");
  const m = await q.matched(8000);
  const c = await joinMatched(m.code, m.token, { pid: g.pid, account: g.id, session: g.session });
  await c.wait("start", 5000);
  return { code: m.code, c, q };
}

/** g's recent list once it has n people. */
async function recentOf(g: Guest, n: number): Promise<Json[]> {
  return eventually(async () => {
    const r = (await social(g)).recent as Json[];
    return r.length >= n ? r : null;
  }, 8000, `${n} recent players`);
}

/** An answer with its times made relative to `now` (what two invites at the same moment must share). */
function shape(r: { status: number; body: Json }, now = NOW): Json {
  const b = { ...r.body };
  for (const k of ["expires_at", "retry_at", "again_at"]) if (typeof b[k] === "number") b[k] -= now;
  return { status: r.status, body: b };
}

describe("recent players", () => {
  it("a friend-room match puts everyone on everyone's list, with the game and when, newest first", async () => {
    const [a, b, c] = [await guest(), await guest(), await guest()];
    const before = Math.floor(Date.now() / 1000);
    const { cs } = await playFriends([a, b, c]);
    const ra = await recentOf(a, 2);
    expect(ra).toHaveLength(2);
    for (const p of ra) {
      expect(Object.keys(p).sort()).toEqual(["avatar", "frame", "friend", "game", "level", "name", "played_at", "uid"]);
      expect(p.uid).toMatch(UID);
      expect(p.game).toBe("ludo");
      expect(p.friend).toBe(false);
      expect(p.played_at).toBeGreaterThanOrEqual(before - 1);
    }
    const uidB = (await row<{ uid: string }>("SELECT uid FROM accounts WHERE id = ?", b.id))!.uid;
    expect(ra.map((p) => p.uid)).toContain(uidB);
    expect(JSON.stringify(ra)).not.toContain(b.id); // never the account id
    expect((await recentOf(b, 2)).map((p) => p.uid)).not.toContain(uidB); // not yourself
    for (const x of cs) x.close();

    // a second match with only b: b moves to the top (one row per person)
    await sleep(1100);
    const l2 = await playFriends([a, b]);
    const again = await eventually(async () => {
      const r = (await social(a)).recent as Json[];
      return r[0]?.uid === uidB && r[0].played_at > r[1].played_at ? r : null;
    }, 8000, "b first");
    expect(again).toHaveLength(2);
    for (const x of l2.cs) x.close();
  });

  it("a quick match puts its ghost on the list exactly like a person (same fields, same handle)", async () => {
    const a = await guest();
    const b = await guest();
    const f = await playFriends([a, b]);
    const qm = await playQuick(a);
    const list = await recentOf(a, 2);
    expect(new Set(list.map((p) => Object.keys(p).sort().join(","))).size).toBe(1); // a person's row and a ghost's: the same fields
    for (const p of list) {
      expect(p.uid).toMatch(UID);
      expect(typeof p.name).toBe("string");
      expect(typeof p.avatar).toBe("string");
      expect(typeof p.frame).toBe("string");
      expect(Number.isInteger(p.level) && p.level >= 1).toBe(true);
    }
    const w = walk(await social(a));
    expect(w.keys.filter((k) => /ghost|bot|cpu/i.test(k))).toEqual([]);
    expect(w.strings.filter((s) => /ghost/i.test(s))).toEqual([]);
    // the ghost's identity is the one it had at the table
    const seats = qm.c.seats;
    const other = seats.find((s: Json) => s.id !== qm.c.id)!;
    const g = list.find((p) => p.name === other.name)!;
    expect(g).toMatchObject({ name: other.name, avatar: other.avatar, frame: other.frame, level: other.level });
    qm.c.close();
    qm.q.close();
    for (const x of f.cs) x.close();
  });

  it("keeps the newest 30", async () => {
    const a = await guest();
    const ghosts = Array.from({ length: 34 }, (_, k) => ({ ghost: { uid: newUid(), name: `G${k}`, avatar: "pawn-red", frame: "classic", level: 3 } }));
    for (const [k, gh] of ghosts.entries()) await DB.batch(playedStmts(DB, [{ account: a.id }, gh], "sl", 1_000_000 + k, null));
    const list = (await social(a)).recent as Json[];
    expect(list).toHaveLength(SOCIAL.recent);
    expect(list[0].name).toBe("G33");
    expect(list.at(-1)!.name).toBe("G4");
    expect(list[0].game).toBe("sl");
    expect((await row<{ n: number }>("SELECT COUNT(*) AS n FROM recent_players WHERE account_id = ?", a.id))!.n).toBe(30);
  });
});

describe("friends", () => {
  it("add by handle and by room seat, remove; one-way; not yourself; unknown handles 404", async () => {
    const [a, b] = [await guest(), await guest()];
    const { code, cs } = await lobby([a, b]);
    // by seat in the room (the lobby's member id)
    const r1 = await ok("social/friends", { session: a.session, body: { code, member: cs[1].id }, now: NOW });
    expect(r1.ok).toBe(true);
    expect(Object.keys(r1.friend).sort()).toEqual(["avatar", "frame", "level", "name", "uid"]);
    const uidB = r1.friend.uid as string;
    expect(uidB).toMatch(UID);
    const sa = await social(a);
    expect(sa.friends).toHaveLength(1);
    expect(Object.keys(sa.friends[0]).sort()).toEqual(["added_at", "avatar", "frame", "game", "level", "name", "played_at", "uid"]);
    expect(sa.friends[0]).toMatchObject({ uid: uidB, game: null, played_at: null, added_at: NOW });
    expect((await social(b)).friends).toEqual([]); // one-way: b's list is unchanged, b is told nothing
    // idempotent
    await ok("social/friends", { session: a.session, body: { uid: uidB }, now: NOW });
    expect((await social(a)).friends).toHaveLength(1);
    // yourself, unknown, not a member of that room
    const uidA = (await row<{ uid: string }>("SELECT uid FROM accounts WHERE id = ?", a.id))!.uid;
    expect((await v1("social/friends", { session: a.session, body: { uid: uidA } })).status).toBe(400);
    expect((await v1("social/friends", { session: a.session, body: { code, member: cs[0].id } })).status).toBe(404); // own seat: nobody to add
    expect((await v1("social/friends", { session: a.session, body: { uid: "0123456789abcdef" } })).status).toBe(404);
    const c = await guest();
    expect((await v1("social/friends", { session: c.session, body: { code, member: cs[1].id } })).status).toBe(404);
    expect((await v1("social/friends", { session: a.session, body: { uid: "nope" } })).status).toBe(400);
    expect((await v1("social/friends", { body: { uid: uidB } })).status).toBe(401);
    // remove
    await ok("social/friends", { method: "DELETE", session: a.session, body: { uid: uidB } });
    expect((await social(a)).friends).toEqual([]);
    for (const x of cs) x.close();
  });

  it("adds a ghost from the quick match it sat in, like a person; the recent list marks friends", async () => {
    const a = await guest();
    const qm = await playQuick(a);
    const other = qm.c.seats.find((s: Json) => s.id !== qm.c.id)!;
    const r = await ok("social/friends", { session: a.session, body: { code: qm.code, member: other.id }, now: NOW });
    expect(Object.keys(r.friend).sort()).toEqual(["avatar", "frame", "level", "name", "uid"]);
    expect(r.friend).toMatchObject({ name: other.name, avatar: other.avatar, frame: other.frame, level: other.level });
    const recent = await recentOf(a, 1);
    expect(recent[0]).toMatchObject({ uid: r.friend.uid, friend: true });
    expect((await social(a)).friends[0]).toMatchObject({ uid: r.friend.uid, game: "ludo" });
    qm.c.close();
    qm.q.close();
  });

  it("from the leaderboard: rows carry the handle", async () => {
    const a = await guest();
    const b = await guest();
    await DB.prepare("UPDATE accounts SET completed_matches = 5 WHERE id = ?").bind(b.id).run();
    await DB.prepare("INSERT INTO scores (account_id, board, period, value, updated_at) VALUES (?, 'xp', 'all', 99999, 1)").bind(b.id).run();
    const lb = await ok("leaderboard?board=xp&period=all&nocache=1");
    const top = (lb.top as Json[]).find((t) => t.value === 99999)!;
    expect(top.uid).toMatch(UID);
    expect(JSON.stringify(lb)).not.toContain(b.id);
    const r = await ok("social/friends", { session: a.session, body: { uid: top.uid }, now: NOW });
    expect(r.friend.uid).toBe(top.uid);
  });

  it("at most 100", async () => {
    const a = await guest();
    const stmts = Array.from({ length: SOCIAL.friends }, (_, k) => {
      const uid = newUid();
      return [
        DB.prepare("INSERT INTO ghost_people (uid, name, avatar, frame, level, created_at) VALUES (?, ?, 'pawn-red', 'classic', 2, ?)").bind(uid, `F${k}`, Date.now()),
        DB.prepare("INSERT INTO friends (account_id, uid, at) VALUES (?, ?, ?)").bind(a.id, uid, k),
      ];
    }).flat();
    await DB.batch(stmts);
    const b = await guest();
    const uidB = (await row<{ uid: string }>("SELECT uid FROM accounts WHERE id = ?", b.id))!.uid;
    const r = await v1("social/friends", { session: a.session, body: { uid: uidB } });
    expect(r.status).toBe(409);
    expect(r.body).toEqual({ error: "friends_full", max: 100 });
    expect((await social(a)).friends).toHaveLength(100);
  });
});

describe("invites", () => {
  let fcm: FakeFcm;
  // a: the inviter; b: a person who ignores invites (push token); c: invites turned off (push token); ghost: a quick
  // match seat; d: a person a has never played with
  let a: Guest, b: Guest, c: Guest, d: Guest;
  let uid: { b: string; c: string; ghost: string; d: string };
  let tok: { b: string; c: string };
  const opened: Array<{ close(): void }> = [];

  beforeAll(async () => {
    fcm = await installFakeFcm();
    [a, b, c, d] = [await guest(), await guest(), await guest(), await guest()];
    tok = { b: fcmToken("b"), c: fcmToken("c") };
    await register(b.session, tok.b);
    await register(c.session, tok.c);
    await ok("social/prefs", { session: c.session, body: { invites: false } });
    const f = await playFriends([a, b, c]);
    const qm = await playQuick(a);
    opened.push(...f.cs, qm.c, qm.q);
    const list = await recentOf(a, 3);
    const u = async (g: Guest) => (await row<{ uid: string }>("SELECT uid FROM accounts WHERE id = ?", g.id))!.uid;
    const ub = await u(b);
    const uc = await u(c);
    uid = { b: ub, c: uc, ghost: list.find((p) => p.uid !== ub && p.uid !== uc)!.uid, d: await u(d) };
  });
  afterAll(() => {
    for (const x of opened) x.close();
    uninstallFakeFcm();
  });
  beforeEach(() => {
    fcm.reset();
    setPushServiceAccount(fcm.serviceAccount);
    setPushFetcher(fcm.fetch);
  });

  it("reaches a person: listed with who sent it, pushed after the answer, accepted into the room", async () => {
    const { code, cs } = await lobby([a]);
    // FCM is slow: the answer must not wait for it
    setPushFetcher(async (u, i) => {
      await sleep(900);
      return fcm.fetch(u, i);
    });
    const t0 = Date.now();
    const r = await invite(a, uid.b, code);
    const took = Date.now() - t0;
    expect(r.status).toBe(200);
    expect(r.body).toEqual({ ok: true, expires_at: NOW + 600, again_at: NOW + 60 });
    expect(took).toBeLessThan(800);
    const pending = await invites(b);
    expect(pending).toHaveLength(1);
    expect(Object.keys(pending[0]).sort()).toEqual(["code", "expires_at", "from", "game", "id", "sent_at"]);
    expect(pending[0]).toMatchObject({ code, game: "ludo", sent_at: NOW, expires_at: NOW + 600 });
    expect(Object.keys(pending[0].from).sort()).toEqual(["avatar", "frame", "level", "name", "uid"]);
    expect(JSON.stringify(pending)).not.toContain(a.id);
    await eventually(async () => fcm.delivered.some((m) => m.token === tok.b), 5000, "the invite push");
    const msg = fcm.delivered.find((m) => m.token === tok.b)!;
    expect(msg.data).toEqual({ link: `room:${code}`, kind: "invite" });
    expect(msg.notification).toEqual({ title: "Game invite", body: `P1 invited you to play Ludo in room ${code}` });
    expect(msg.android).toMatchObject({ priority: "high", ttl: "600s", collapse_key: `invite:${code}`, notification: { channel_id: "game", tag: `invite:${code}` } });
    // accept -> the room; then b joins as with a code
    const acc = await ok("social/invites/accept", { session: b.session, body: { id: pending[0].id }, now: NOW + 30 });
    expect(acc).toEqual({ ok: true, code, game: "ludo" });
    expect(await invites(b, NOW + 30)).toEqual([]);
    const cb = await Client.join(code, { pid: b.pid, session: b.session, name: "B" });
    await cb.waitFor((m) => m.t === "lobby" && m.members.length === 2);
    for (const x of [...cs, cb]) x.close();
  });

  it("a ghost, a person who ignores it and a person with invites off: the same answers, the same limits", async () => {
    const { code, cs } = await lobby([a]);
    const t = NOW + 1000;
    const first = [await invite(a, uid.ghost, code, t), await invite(a, uid.b, code, t), await invite(a, uid.c, code, t)].map((r) => shape(r, t));
    expect(first[0]).toEqual({ status: 200, body: { ok: true, expires_at: 600, again_at: 60 } });
    expect(first[1]).toEqual(first[0]);
    expect(first[2]).toEqual(first[0]);
    // tapped again a moment later: still fine, the same invite, alike for all three
    const again = [await invite(a, uid.ghost, code, t + 10), await invite(a, uid.b, code, t + 10), await invite(a, uid.c, code, t + 10)].map((r) => shape(r, t));
    expect(again[0]).toEqual({ status: 200, body: { ok: true, expires_at: 600, again_at: 60 } });
    expect(again[1]).toEqual(again[0]);
    expect(again[2]).toEqual(again[0]);
    // after a minute, a reminder is a new invite, for all three
    const later = [await invite(a, uid.ghost, code, t + 61), await invite(a, uid.b, code, t + 61), await invite(a, uid.c, code, t + 61)].map((r) => shape(r, t));
    expect(later[1]).toEqual(later[0]);
    expect(later[2]).toEqual(later[0]);
    expect(later[0]).toEqual({ status: 200, body: { ok: true, expires_at: 661, again_at: 121 } });
    // the person with invites off sees nothing and gets no push; the one who ignores it has it listed
    expect(await invites(c, t + 62)).toEqual([]);
    expect((await invites(b, t + 62)).length).toBeGreaterThan(0);
    await eventually(async () => fcm.delivered.some((m) => m.token === tok.b), 5000, "b's push");
    await sleep(200);
    expect(fcm.delivered.filter((m) => m.token === tok.c)).toEqual([]);
    for (const x of cs) x.close();
  });

  it("only people on the inviter's lists, only from the inviter's own open friend room", async () => {
    const { code, cs } = await lobby([a]);
    const t = NOW + 3000;
    expect((await invite(a, uid.d, code, t)).body).toEqual({ error: "not_found" }); // never played, not a friend
    expect((await invite(a, uid.d, code, t)).status).toBe(404);
    expect((await invite(a, "0123456789abcdef", code, t)).status).toBe(404);
    const other = await lobby([d]);
    expect((await invite(a, uid.b, other.code, t)).body).toEqual({ error: "not_in_room" }); // not a's room
    expect((await invite(a, uid.b, "ZZZZZZ", t)).body).toEqual({ error: "not_in_room" });
    const uidA = (await row<{ uid: string }>("SELECT uid FROM accounts WHERE id = ?", a.id))!.uid;
    expect((await invite(a, uidA, code, t)).status).toBe(400);
    // a friend a never played with can be invited
    await ok("social/friends", { session: a.session, body: { uid: uid.d }, now: t });
    expect((await invite(a, uid.d, code, t)).status).toBe(200);
    await ok("social/friends", { method: "DELETE", session: a.session, body: { uid: uid.d } });
    // a full room, a room whose match started
    const full = await lobby([a, await guest(), await guest(), await guest()]);
    expect((await invite(a, uid.b, full.code, t)).body).toEqual({ error: "room_full" });
    const started = await playFriends([a, await guest()]);
    expect((await invite(a, uid.b, started.code, t)).body).toEqual({ error: "started" });
    for (const x of [...cs, ...other.cs, ...full.cs, ...started.cs]) x.close();
  });

  it("expires after 10 minutes and when the room's match starts; decline ends it", async () => {
    const t = NOW + 5000;
    const r1 = await lobby([a]);
    await invite(a, uid.b, r1.code, t);
    expect(await invites(b, t + 599)).toHaveLength(1);
    expect(await invites(b, t + 600)).toEqual([]);
    expect((await v1("social/invites/accept", { session: b.session, body: { code: r1.code }, now: t + 601 })).status).toBe(410);
    // the match starts: gone at once
    const r2 = await lobby([a]);
    await invite(a, uid.b, r2.code, t + 2000);
    const pending = await invites(b, t + 2001);
    expect(pending).toHaveLength(1);
    const e = await Client.join(r2.code, { name: "E" });
    await e.waitFor((m) => m.t === "lobby" && m.members.length === 2);
    r2.cs[0].send({ t: "start" });
    await r2.cs[0].wait("start");
    await eventually(async () => (await invites(b, t + 2002)).length === 0, 5000, "expired at start");
    const gone = await v1("social/invites/accept", { session: b.session, body: { id: pending[0].id }, now: t + 2003 });
    expect(gone.status).toBe(410);
    expect(gone.body).toEqual({ error: "gone" });
    // decline: off b's list; a can't tell (nothing to read)
    const r3 = await lobby([a]);
    await invite(a, uid.b, r3.code, t + 4000);
    const p3 = await invites(b, t + 4001);
    expect(await ok("social/invites/decline", { session: b.session, body: { id: p3[0].id }, now: t + 4002 })).toEqual({ ok: true });
    expect(await invites(b, t + 4003)).toEqual([]);
    expect((await v1("social/invites/accept", { session: b.session, body: { id: p3[0].id }, now: t + 4004 })).status).toBe(410);
    // the inviter left the room meanwhile: accept says gone
    const r4 = await lobby([a]);
    await invite(a, uid.b, r4.code, t + 6000);
    r4.cs[0].send({ t: "leave" });
    const gone4 = await eventually(async () => {
      const s = await v1("social/invites/accept", { session: b.session, body: { code: r4.code }, now: t + 6001 });
      return s.status === 410 ? s : null;
    }, 5000, "accept refused");
    expect(gone4.body).toEqual({ error: "gone" });
    for (const x of [...r1.cs, ...r2.cs, e, ...r3.cs, ...r4.cs]) x.close();
  });

  it("rate limits: 20 per hour and 60 per day in all", async () => {
    const x = await guest();
    const { code, cs } = await lobby([x]);
    const people = Array.from({ length: 61 }, () => ({ ghost: { uid: newUid(), name: "N", avatar: "pawn-red", frame: "classic", level: 2 } }));
    await DB.batch(people.flatMap((p) => playedStmts(DB, [{ account: x.id }, p], "ludo", Date.now(), null)));
    await DB.batch(people.map((p) => DB.prepare("INSERT OR IGNORE INTO friends (account_id, uid, at) VALUES (?, ?, 1)").bind(x.id, p.ghost.uid)));
    const t = NOW + 10_000;
    for (let k = 0; k < SOCIAL.perHour; k++) expect((await invite(x, people[k].ghost.uid, code, t + k)).status).toBe(200);
    const over = await invite(x, people[20].ghost.uid, code, t + 30);
    expect(over.status).toBe(429);
    expect(over.body).toEqual({ error: "rate", scope: "total", retry_at: t + 3600 });
    // two more hours of 20: the day's 60, then nothing until a day after the first
    for (let h = 1; h <= 2; h++) for (let k = 0; k < 20; k++) expect((await invite(x, people[h * 20 + k].ghost.uid, code, t + h * 3600 + k)).status).toBe(200);
    const day = await invite(x, people[60].ghost.uid, code, t + 3 * 3600);
    expect(day.body).toEqual({ error: "rate", scope: "total", retry_at: t + 86400 });
    for (const y of cs) y.close();
  });

  it("at most 6 invite pushes per person per hour; more are still listed", async () => {
    const t = NOW + 200_000;
    const senders = [] as Guest[];
    for (let k = 0; k < 7; k++) senders.push(await guest());
    const target = await guest();
    const token = fcmToken("t");
    await register(target.session, token);
    const ut = (await row<{ uid: string }>("SELECT uid FROM accounts WHERE id = ?", target.id))!.uid;
    const rooms = [];
    for (const s of senders) {
      await ok("social/friends", { session: s.session, body: { uid: ut }, now: t });
      const l = await lobby([s]);
      rooms.push(l);
      expect((await invite(s, ut, l.code, t + 1)).status).toBe(200);
    }
    await eventually(async () => fcm.delivered.filter((m) => m.token === token).length >= 6, 5000, "6 pushes");
    await sleep(300);
    expect(fcm.delivered.filter((m) => m.token === token)).toHaveLength(6);
    expect(await invites(target, t + 2)).toHaveLength(7);
    for (const l of rooms) for (const y of l.cs) y.close();
  });

  it("invites off: pending ones end, nothing new is listed; on again: listed again", async () => {
    const x = await guest();
    const y = await guest();
    const uy = (await row<{ uid: string }>("SELECT uid FROM accounts WHERE id = ?", y.id))!.uid;
    await ok("social/friends", { session: x.session, body: { uid: uy } });
    const { code, cs } = await lobby([x]);
    const t = NOW + 400_000;
    await invite(x, uy, code, t);
    expect(await invites(y, t + 1)).toHaveLength(1);
    expect(await ok("social/prefs", { session: y.session, body: { invites: false } })).toEqual({ ok: true, prefs: { invites: false } });
    expect(await invites(y, t + 2)).toEqual([]);
    expect((await social(y)).prefs).toEqual({ invites: false });
    expect((await invite(x, uy, code, t + 700)).status).toBe(200);
    expect(await invites(y, t + 701)).toEqual([]);
    await ok("social/prefs", { session: y.session, body: { invites: true } });
    expect((await social(y)).prefs).toEqual({ invites: true });
    expect((await invite(x, uy, code, t + 1400)).status).toBe(200);
    expect(await invites(y, t + 1401)).toHaveLength(1);
    expect((await v1("social/prefs", { session: y.session, body: { invites: "no" } })).status).toBe(400);
    for (const z of cs) z.close();
  });

  it("your exact case: the wrong game, leave, a new room: the new invite goes at once and replaces the old", async () => {
    const t = NOW + 200_000;
    const wrong = await lobby([a]);
    await invite(a, uid.b, wrong.code, t);
    const right = await lobby([a]);
    const r = shape(await invite(a, uid.b, right.code, t + 5), t + 5);
    expect(r).toEqual({ status: 200, body: { ok: true, expires_at: 600, again_at: 60 } });
    const list = await invites(b, t + 6);
    expect(list.map((i: Json) => i.code)).toEqual([right.code]);
    for (const x of [...wrong.cs, ...right.cs]) x.close();
  });

  it("their Not now stops that inviter for 30 minutes, in any room; ignoring never does", async () => {
    const t = NOW + 210_000;
    const r1 = await lobby([a]);
    await invite(a, uid.b, r1.code, t);
    const p = await invites(b, t + 1);
    await ok("social/invites/decline", { session: b.session, body: { id: p[0].id }, now: t + 100 });
    const r2 = await lobby([a]);
    expect(shape(await invite(a, uid.b, r2.code, t + 101), t + 100)).toEqual({ status: 429, body: { error: "rate", scope: "person", declined: true, retry_at: 1800 } });
    expect((await invites(b, t + 102))).toEqual([]);
    const sent = await ok("social/invites/sent", { session: a.session, now: t + 102 });
    expect(sent.sent.find((x: Json) => x.uid === uid.b)).toMatchObject({ status: "declined", retry_at: t + 1900 });
    expect((await invite(a, uid.b, r2.code, t + 1901)).status).toBe(200);
    for (const x of [...r1.cs, ...r2.cs]) x.close();
  });

  it("leaving ends your invites; switching game updates them; the list says where they stand", async () => {
    const t = NOW + 220_000;
    const r1 = await lobby([a]);
    await invite(a, uid.b, r1.code, t);
    expect((await ok("social/invites/sent", { session: a.session, now: t + 1 })).sent.find((x: Json) => x.uid === uid.b)).toMatchObject({ status: "invited", code: r1.code, again_at: t + 60 });
    r1.cs[0].send({ t: "settings", game: "sl" });
    await eventually(async () => (await invites(b, t + 2))[0]?.game === "sl", 5000, "the game follows");
    r1.cs[0].send({ t: "leave" });
    await eventually(async () => (await invites(b, t + 3)).length === 0, 5000, "ended on leave");
    expect((await ok("social/invites/sent", { session: a.session, now: t + 4 })).sent.find((x: Json) => x.uid === uid.b)).toBeUndefined();
    for (const x of r1.cs) x.close();
  });

  it("still no spam: 6 an hour to the same person", async () => {
    const t = NOW + 230_000;
    const r1 = await lobby([a]);
    for (let k = 0; k < 6; k++) expect((await invite(a, uid.ghost, r1.code, t + k * 61)).status).toBe(200);
    expect(shape(await invite(a, uid.ghost, r1.code, t + 400), t)).toEqual({ status: 429, body: { error: "rate", scope: "person", retry_at: 3600 } });
    for (const x of r1.cs) x.close();
  });
});

describe("erase", () => {
  it("erasing an account removes its lists, its invites and it from everyone else's lists", async () => {
    const cookie = await login();
    const [a, b] = [await guest(), await guest()];
    const f = await playFriends([a, b]);
    await recentOf(a, 1);
    await recentOf(b, 1);
    const ub = (await row<{ uid: string }>("SELECT uid FROM accounts WHERE id = ?", b.id))!.uid;
    const ua = (await row<{ uid: string }>("SELECT uid FROM accounts WHERE id = ?", a.id))!.uid;
    await ok("social/friends", { session: a.session, body: { uid: ub } });
    await ok("social/friends", { session: b.session, body: { uid: ua } });
    await ok("social/prefs", { session: b.session, body: { invites: false } });
    const l = await lobby([a]);
    await invite(a, ub, l.code);
    const l2 = await lobby([b]);
    await invite(b, ua, l2.code);
    const r = await api(cookie, `accounts/${b.id}/erase`, { method: "POST", body: { confirm: b.id, reason: "Deletion request" } });
    expect(r.erased).toMatchObject({ accounts: 1, recent_players: 2, friends: 2, invites: 2 });
    for (const [t, col] of [["recent_players", "account_id"], ["friends", "account_id"], ["social_prefs", "account_id"], ["invites", "from_account"], ["invites", "to_account"]]) {
      expect((await rows(`SELECT 1 FROM ${t} WHERE ${col} = ?`, b.id)).length, `${t}.${col}`).toBe(0);
    }
    for (const t of ["recent_players", "friends", "invites"]) {
      const col = t === "invites" ? "to_uid" : "uid";
      expect((await rows(`SELECT 1 FROM ${t} WHERE ${col} = ?`, ub)).length, t).toBe(0);
    }
    const sa = await social(a);
    expect(sa.recent).toEqual([]);
    expect(sa.friends).toEqual([]);
    for (const x of [...f.cs, ...l.cs, ...l2.cs]) x.close();
  });
});

describe("prune (daily cron)", () => {
  it("drops invites after 2 days and ghost rows that no list refers to after 30 days", async () => {
    const a = await guest();
    const now = Date.now();
    const old = now - 31 * 86_400_000;
    const [kept, dropped, fresh] = [newUid(), newUid(), newUid()];
    const ghost = (uid: string, at: number) =>
      DB.prepare("INSERT INTO ghost_people (uid, name, avatar, frame, level, created_at) VALUES (?, 'G', 'pawn-red', 'classic', 2, ?)").bind(uid, at);
    const inv = (id: string, at: number) =>
      DB.prepare("INSERT INTO invites (id, from_account, to_uid, code, game, at, expires_at) VALUES (?, ?, ?, 'K7QX2M', 'ludo', ?, ?)").bind(id, a.id, kept, at, at + 600_000);
    await DB.batch([
      ghost(kept, old),
      ghost(dropped, old),
      ghost(fresh, now),
      DB.prepare("INSERT INTO friends (account_id, uid, at) VALUES (?, ?, ?)").bind(a.id, kept, old),
      inv("inv_aaaaaaaaaaaaaaaa", now - 3 * 86_400_000),
      inv("inv_bbbbbbbbbbbbbbbb", now - 3_600_000),
    ]);
    const r = await pruneSocial(DB, now);
    expect(r.invites).toBeGreaterThanOrEqual(1);
    expect(r.ghosts).toBeGreaterThanOrEqual(1);
    const left = await rows<{ uid: string }>("SELECT uid FROM ghost_people WHERE uid IN (?, ?, ?)", kept, dropped, fresh);
    expect(left.map((x) => x.uid).sort()).toEqual([kept, fresh].sort());
    expect((await rows<{ id: string }>("SELECT id FROM invites WHERE from_account = ?", a.id)).map((x) => x.id)).toEqual(["inv_bbbbbbbbbbbbbbbb"]);
  });
});
