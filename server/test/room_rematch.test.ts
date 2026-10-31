// Play again in friend rooms (PROTOCOL.md "Play again"): the rematch vote after `over`. Anyone asks (and is a yes),
// everyone else is asked; the next match starts with the yes-sayers once everyone answered or the window ran out
// (2 or more), else the room goes back to its lobby. The window runs on the room's alarm: tests shorten it with
// TestHooks.rematchMs (and the graces with timeScale) instead of waiting 30 s.
import { evictDurableObject } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import type { TestHooks } from "../src/room";
import { Client, finishAll, lobbyOf, NEAR_GOAL, roomInfo, sleep, startAll, stubFor, type Msg } from "./room_client";

/** Where each client's log stood when afterMatch handed it over (fresh() reads what came after). */
const marks = new WeakMap<Client, number>();
const fresh = (c: Client, t: string): Msg[] => c.log.slice(marks.get(c) ?? 0).filter((m) => m.t === t);

/** A friend room of k that has just played a short match to `over` (autoplay off again, logs skipped). */
async function afterMatch(k: number, opts: { teams?: boolean; hooks?: TestHooks; scale?: number } = {}): Promise<{ code: string; cs: Client[] }> {
  const { code, cs } = await lobbyOf(k, { tok: NEAR_GOAL, timeScale: opts.scale });
  if (opts.teams) {
    cs[0].send({ t: "settings", teams: true });
    await cs[k - 1].waitFor((m) => m.t === "lobby" && m.settings.teams);
  }
  for (const c of cs) c.autoplay = true;
  await startAll(cs);
  await finishAll(cs);
  await Promise.all(cs.map((c) => c.waitFor((m) => m.t === "lobby" && m.status === "over")));
  for (const c of cs) {
    c.autoplay = false;
    c.skip();
    marks.set(c, c.log.length);
  }
  if (opts.hooks) await stubFor(code).testHooks({ ratePerSec: 1000, tok: NEAR_GOAL, ...opts.hooks });
  return { code, cs };
}

/** name -> answer in a `rematch` message. */
const votes = (m: Msg): Record<string, string> => Object.fromEntries(m.players.map((p: Msg) => [p.name, p.vote]));
const isVote = (pred: (m: Msg) => boolean = () => true) => (m: Msg) => m.t === "rematch" && pred(m);
const closed = (m: Msg) => m.t === "rematch" && typeof m.result === "string";

describe("Play again: the vote", () => {
  it("anyone may ask; when everyone says yes the next match starts at once with all of them", async () => {
    const { cs } = await afterMatch(3);
    const [a, b, c] = cs;
    b.send({ t: "rematch" }); // not the host
    const opened = await Promise.all(cs.map((x) => x.waitFor(isVote())));
    for (const o of opened) {
      expect(o.by).toBe(b.id);
      expect(votes(o)).toEqual({ P1: "wait", P2: "yes", P3: "wait" });
      expect(o.until - o.now).toBeGreaterThan(29_000);
      expect(o.until - o.now).toBeLessThanOrEqual(30_000);
      expect(o.result).toBeUndefined();
    }
    expect(opened[0].players[1]).toEqual({ id: b.id, name: "P2", avatar: "a1", frame: "f1", vote: "yes" });
    a.send({ t: "rematch" });
    expect(votes(await c.waitFor(isVote((m) => votes(m).P1 === "yes")))).toEqual({ P1: "yes", P2: "yes", P3: "wait" });
    c.send({ t: "rematch" });
    const done = await Promise.all(cs.map((x) => x.waitFor(closed)));
    for (const d of done) {
      expect(d.result).toBe("go");
      expect(d.ffa).toBeUndefined();
      expect(votes(d)).toEqual({ P1: "yes", P2: "yes", P3: "yes" });
    }
    const st = await Promise.all(cs.map((x) => x.wait("start")));
    expect(st[0].n).toBe(0);
    expect(st[0].seats.map((s: Msg) => [s.id, s.color])).toEqual([
      [a.id, 0],
      [b.id, 1],
      [c.id, 2],
    ]);
    for (const x of cs) x.autoplay = true;
    a.playTurn(a.state.turn);
    await finishAll(cs);
  });

  it("Leave on the prompt: out of the room (a no for the others); the match starts with the rest", async () => {
    const { code, cs } = await afterMatch(3);
    const [a, b, c] = cs;
    a.send({ t: "rematch" });
    await b.waitFor(isVote());
    b.send({ t: "leave" });
    expect(await b.waitClosed()).toBe(4002);
    expect(votes(await c.waitFor(isVote((m) => votes(m).P2 === "no")))).toEqual({ P1: "yes", P2: "no", P3: "wait" });
    c.send({ t: "rematch" });
    const d = await a.waitFor(closed);
    expect(d.result).toBe("go");
    expect(votes(d)).toEqual({ P1: "yes", P2: "no", P3: "yes" });
    const st = await c.wait("start");
    expect(st.seats.map((s: Msg) => s.id)).toEqual([a.id, c.id]);
    expect(st.state.players).toEqual(["human", "off", "human", "off"]);
    expect((await roomInfo(code)).body).toMatchObject({ members: 2, started: true });

    // the one who left: no way in while that match runs; after it, a newcomer with the code like anyone
    const early = await Client.open(code, b.pid);
    early.hello();
    expect(await early.wait("error")).toMatchObject({ code: "started" });
    for (const x of [a, c]) x.autoplay = true;
    a.playTurn(a.state.turn);
    await finishAll([a, c]);
    const back = await Client.join(code, { pid: b.pid, name: "P2" });
    expect(back.id).not.toBe(b.id);
    const l = await back.waitFor((m) => m.t === "lobby" && m.members.length === 3);
    expect(l.status).toBe("over");
    expect(l.members.map((m: Msg) => m.id)).toEqual([a.id, c.id, back.id]);
  });

  it("the window runs out: the silent are left out (rematch_out, close 4002), the yes-sayers play", async () => {
    const { code, cs } = await afterMatch(4, { hooks: { rematchMs: 300 } });
    const [a, b, c, d] = cs;
    a.send({ t: "rematch" });
    await b.waitFor(isVote());
    b.send({ t: "rematch" });
    const done = await Promise.all(cs.map((x) => x.waitFor(closed, 4000)));
    for (const x of done) expect(x).toMatchObject({ result: "go" });
    expect(votes(done[0])).toEqual({ P1: "yes", P2: "yes", P3: "wait", P4: "wait" });
    for (const x of [c, d]) {
      expect(await x.wait("error")).toMatchObject({ code: "rematch_out" });
      expect(await x.waitClosed()).toBe(4002);
      expect(fresh(x, "start")).toEqual([]);
    }
    const st = await a.wait("start");
    expect(st.seats.map((s: Msg) => [s.id, s.color])).toEqual([
      [a.id, 0],
      [b.id, 2],
    ]);
    expect((await roomInfo(code)).body).toMatchObject({ members: 2, started: true });
    // the old seat is gone: its token is a stranger's now
    const again = await Client.open(code, c.pid);
    again.hello(c.token);
    expect(await again.wait("error")).toMatchObject({ code: "started" });
  });

  it("fewer than 2 say yes: no match; the one who said yes waits in the lobby (as host) and can start there", async () => {
    const { code, cs } = await afterMatch(3, { hooks: { rematchMs: 300 } });
    const [a, b, c] = cs;
    b.send({ t: "rematch" });
    await a.waitFor(isVote());
    a.send({ t: "leave" }); // the host
    await a.waitClosed();
    const d = await b.waitFor(closed, 4000);
    expect(d.result).toBe("few");
    expect(votes(d)).toEqual({ P1: "no", P2: "yes", P3: "wait" });
    expect(await c.wait("error")).toMatchObject({ code: "rematch_out" });
    expect(await c.waitClosed()).toBe(4002);
    const l = await b.waitFor((m) => m.t === "lobby" && m.status === "lobby");
    expect(l.host).toBe(b.id);
    expect(l.members.map((m: Msg) => m.id)).toEqual([b.id]);
    expect(fresh(b, "start")).toEqual([]);
    expect((await roomInfo(code)).body).toMatchObject({ members: 1, open: true, started: false });
    b.send({ t: "rematch" }); // (back in the lobby: the host starts)
    expect(await b.wait("error")).toMatchObject({ code: "bad_action" });
    const e = await Client.join(code, { name: "P4" });
    await b.waitFor((m) => m.t === "lobby" && m.members.length === 2);
    b.send({ t: "start" });
    const st = await e.wait("start");
    expect(st.seats.map((s: Msg) => s.id)).toEqual([b.id, e.id]);
  });

  it("Play again at the same moment: one vote, everyone a yes, one match", async () => {
    const two = await afterMatch(2);
    for (const x of two.cs) x.send({ t: "rematch" });
    await Promise.all(two.cs.map((x) => x.wait("start")));

    const { cs } = await afterMatch(3);
    for (const x of cs) x.send({ t: "rematch" });
    const done = await Promise.all(cs.map((x) => x.waitFor(closed)));
    expect(done.every((m) => m.result === "go")).toBe(true);
    expect(votes(done[0])).toEqual({ P1: "yes", P2: "yes", P3: "yes" });
    await Promise.all(cs.map((x) => x.wait("start")));
    await sleep(100);
    for (const x of [...cs, ...two.cs]) {
      expect(fresh(x, "start")).toHaveLength(1);
      expect(fresh(x, "error")).toEqual([]);
    }
    expect(new Set(fresh(cs[0], "rematch").map((m) => m.by)).size).toBe(1); // one vote
  });

  it("Teams: all four say yes, teams again; three: free-for-all (the setting turns off, ffa)", async () => {
    const all = await afterMatch(4, { teams: true });
    for (const x of all.cs) x.send({ t: "rematch" });
    const d4 = await all.cs[0].waitFor(closed);
    expect(d4.ffa).toBeUndefined();
    expect((await all.cs[0].wait("start")).state.teams).toBe(true);

    const { cs } = await afterMatch(4, { teams: true });
    const [a, b, c, d] = cs;
    for (const x of [a, b, c]) x.send({ t: "rematch" });
    await d.waitFor(isVote((m) => Object.values(votes(m)).filter((v) => v === "yes").length === 3));
    d.send({ t: "leave" });
    const done = await a.waitFor(closed);
    expect(done).toMatchObject({ result: "go", ffa: true });
    const st = await a.wait("start");
    expect(st.state.teams).toBe(false);
    expect(st.state.players).toEqual(["human", "human", "human", "off"]);
    for (const x of [a, b, c]) x.autoplay = true;
    a.playTurn(a.state.turn);
    await finishAll([a, b, c]);
    expect((await a.waitFor((m) => m.t === "lobby" && m.status === "over")).settings.teams).toBe(false);
  });

  it("offline at the end: back within the window, the answer still counts; never back: a no", async () => {
    // graces 200 ms (timeScale), the window 1.5 s: an offline voter is kept past the grace while the vote runs
    const { code, cs } = await afterMatch(3, { hooks: { timeScale: 0.01, rematchMs: 1500 } });
    const [a, b, c] = cs;
    b.close();
    c.close();
    await a.waitFor((m) => m.t === "lobby" && m.members.filter((x: Msg) => !x.online).length === 2);
    a.send({ t: "rematch" });
    expect(votes(await a.waitFor(isVote()))).toEqual({ P1: "yes", P2: "wait", P3: "wait" });
    await sleep(450); // two graces
    expect((await roomInfo(code)).body.members).toBe(3);
    const back = await Client.join(code, { token: b.token, name: "P2" });
    expect(back.id).toBe(b.id);
    await back.wait("over"); // (sync, over, lobby, then the vote)
    const v = await back.waitFor(isVote());
    expect(votes(v)).toEqual({ P1: "yes", P2: "wait", P3: "wait" });
    back.send({ t: "rematch" });
    const done = await a.waitFor(closed, 4000);
    expect(done.result).toBe("go");
    expect(votes(done)).toEqual({ P1: "yes", P2: "yes", P3: "wait" });
    const st = await back.wait("start");
    expect(st.seats.map((s: Msg) => [s.id, s.online])).toEqual([
      [a.id, true],
      [b.id, true],
    ]);
    expect((await roomInfo(code)).body.members).toBe(2);
  });

  it("someone joining while the others vote is in for the next match (a yes)", async () => {
    const { code, cs } = await afterMatch(2);
    const [a, b] = cs;
    a.send({ t: "rematch" });
    await b.waitFor(isVote());
    const n = await Client.join(code, { name: "New" });
    expect(votes(await n.waitFor(isVote()))).toEqual({ P1: "yes", P2: "wait", New: "yes" });
    expect(votes(await a.waitFor(isVote((m) => m.players.length === 3)))).toEqual({ P1: "yes", P2: "wait", New: "yes" });
    b.send({ t: "leave" });
    expect(await n.waitFor(closed)).toMatchObject({ result: "go" });
    const st = await n.wait("start");
    expect(st.seats.map((s: Msg) => s.id)).toEqual([a.id, n.id]);
  });

  it("a vote survives an eviction: answers still count and the alarm still closes it", async () => {
    // (an eviction waits for the room's D1 debounce timer: a time scale from the start keeps that short)
    const { code, cs } = await afterMatch(3, { scale: 0.01, hooks: { timeScale: 0.01, rematchMs: 2000 } });
    const [a, b, c] = cs;
    a.send({ t: "rematch" });
    await c.waitFor(isVote());
    await evictDurableObject(stubFor(code));
    b.send({ t: "rematch" });
    expect(votes(await a.waitFor(isVote((m) => votes(m).P2 === "yes")))).toEqual({ P1: "yes", P2: "yes", P3: "wait" });
    await evictDurableObject(stubFor(code));
    expect(await a.waitFor(closed, 8000)).toMatchObject({ result: "go" });
    expect(await c.wait("error")).toMatchObject({ code: "rematch_out" });
    expect((await b.wait("start")).seats.map((s: Msg) => s.id)).toEqual([a.id, b.id]);
  });

  it("an older client's start after over is a yes too (no instant rematch); rematch only after over", async () => {
    const { code, cs } = await lobbyOf(2, { tok: NEAR_GOAL });
    const [a, b] = cs;
    a.send({ t: "rematch" });
    expect(await a.wait("error")).toMatchObject({ code: "bad_action" }); // lobby: the host starts
    for (const x of cs) x.autoplay = true;
    await startAll(cs);
    b.send({ t: "rematch" });
    expect(await b.wait("error")).toMatchObject({ code: "bad_action" }); // playing
    await finishAll(cs);
    for (const x of cs) x.autoplay = false;
    a.send({ t: "start" });
    expect(votes(await b.waitFor(isVote()))).toEqual({ P1: "yes", P2: "wait" });
    expect((await roomInfo(code)).body.started).toBe(false);
    b.send({ t: "rematch" });
    await Promise.all(cs.map((x) => x.wait("start")));
  });
});
