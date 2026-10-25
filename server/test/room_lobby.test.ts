// Room endpoints, hello / identity, lobby, settings, start preconditions, limits.
import { SELF } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import { CODE_ALPHABET } from "../src/room";
import { Client, createRoom, lobbyOf, newPid, roomInfo, stubFor } from "./room_client";

describe("endpoints", () => {
  it("POST /v1/rooms reserves a fresh code", async () => {
    const a = await createRoom();
    const b = await createRoom();
    expect(a).toMatch(new RegExp(`^[${CODE_ALPHABET}]{6}$`));
    expect(a).not.toBe(b);
    const info = await roomInfo(a);
    expect(info.status).toBe(200);
    expect(info.body).toEqual({ code: a, open: true, members: 0, started: false });
  });

  it("init refuses a code already in use", async () => {
    const code = await createRoom();
    expect(await stubFor(code).init(code)).toBe(false);
  });

  it("unknown or malformed codes are 404, also for the socket", async () => {
    expect((await roomInfo("ZZZZZZ")).status).toBe(404);
    expect((await roomInfo("K7QX2O")).status).toBe(404); // O is not in the alphabet
    expect((await roomInfo("abc")).status).toBe(404);
    const r = await SELF.fetch("https://x/v1/rooms/ZZZZZZ/ws", { headers: { Upgrade: "websocket" } });
    expect(r.status).toBe(404);
    expect(r.webSocket).toBeNull();
  });

  it("lower-case codes work; a plain GET on /ws asks for an upgrade", async () => {
    const code = await createRoom();
    expect((await roomInfo(code.toLowerCase())).status).toBe(200);
    expect((await SELF.fetch(`https://x/v1/rooms/${code}/ws`)).status).toBe(426);
  });

  it("other routes and methods", async () => {
    expect((await SELF.fetch("https://x/")).status).toBe(404);
    expect((await SELF.fetch("https://x/v1/rooms")).status).toBe(405);
    expect((await SELF.fetch("https://x/v1/health", { method: "POST" })).status).toBe(405);
  });

  it("test hooks: the Room accepts them only because TEST_MODE is set here", async () => {
    // (wrangler.jsonc has no TEST_MODE, so a deployed Room throws "test hooks are disabled")
    const code = await createRoom();
    await expect(stubFor(code).testHooks({ dice: [6] })).resolves.toBeUndefined();
  });
});

describe("hello and lobby", () => {
  it("welcome, then lobby with members in join order and their colours", async () => {
    const code = await createRoom();
    const a = await Client.join(code, { name: "  Alice  " });
    const w = a.log.find((m) => m.t === "welcome")!;
    expect(w).toMatchObject({ code, host: w.id, id: w.id });
    expect(typeof w.token).toBe("string");
    const l1 = await a.wait("lobby");
    expect(l1).toMatchObject({ code, host: w.id, max: 4, settings: { teams: false, pair_ask: false, game: "ludo" } });
    expect(l1.members).toEqual([{ id: w.id, name: "Alice", avatar: "a1", frame: "f1", level: 1, online: true, color: 0 }]);

    const b = await Client.join(code, { name: "Bob" });
    const l2 = await a.waitFor((m) => m.t === "lobby" && m.members.length === 2);
    expect(l2.members.map((m: { name: string; color: number }) => [m.name, m.color])).toEqual([
      ["Alice", 0],
      ["Bob", 2],
    ]);
    expect(l2.host).toBe(w.id);
    const c = await Client.join(code, { name: "Cy" });
    const l3 = await c.waitFor((m) => m.t === "lobby" && m.members.length === 3);
    expect(l3.members.map((m: { color: number }) => m.color)).toEqual([0, 1, 2]);
    expect((await roomInfo(code)).body).toMatchObject({ members: 3, open: true, started: false });
    b.close();
  });

  it("names are trimmed and cut to 16; empty becomes Player; bad avatar ids are dropped", async () => {
    const code = await createRoom();
    const a = await Client.open(code);
    a.send({ t: "hello", v: 1, pid: newPid(), name: "   ", avatar: "x".repeat(40), frame: "<b>" });
    const l = await a.wait("lobby");
    expect(l.members[0]).toMatchObject({ name: "Player", avatar: "", frame: "" });
    const b = await Client.open(code);
    b.send({ t: "hello", v: 1, pid: newPid(), name: " ABCDEFGHIJKLMNOPQRSTUVWXYZ ", avatar: "a", frame: "f" });
    const l2 = await b.waitFor((m) => m.t === "lobby" && m.members.length === 2);
    expect(l2.members[1].name).toBe("ABCDEFGHIJKLMNOP");
  });

  it("wrong version, missing pid, messages before hello", async () => {
    const code = await createRoom();
    const a = await Client.open(code);
    a.send({ t: "start" });
    expect(await a.wait("error")).toMatchObject({ code: "bad_message" });
    a.send({ t: "hello", v: 2, pid: newPid(), name: "x" });
    expect(await a.wait("error")).toMatchObject({ code: "version" });
    expect(await a.waitClosed()).toBe(4000);

    const b = await Client.open(code);
    b.send({ t: "hello", v: 1, pid: "short", name: "x" });
    expect(await b.wait("error")).toMatchObject({ code: "bad_message" });
    await b.waitClosed();
  });

  it("bad JSON, binary-ish junk, oversized messages and unknown types are bad_message", async () => {
    const { cs } = await lobbyOf(1);
    const a = cs[0];
    a.ws.send("{nope");
    expect(await a.wait("error")).toMatchObject({ code: "bad_message" });
    a.ws.send("[1,2]");
    expect(await a.wait("error")).toMatchObject({ code: "bad_message" });
    a.send({ t: "ping", pad: "x".repeat(5000) });
    expect(await a.wait("error")).toMatchObject({ code: "bad_message" });
    a.send({ t: "dance" });
    expect(await a.wait("error")).toMatchObject({ code: "bad_message" });
    a.send({ t: "hello", v: 1, pid: a.pid });
    expect(await a.wait("error")).toMatchObject({ code: "bad_message" });
    a.send({ t: "ping", v: 1 });
    const p = await a.wait("pong");
    expect(typeof p.now).toBe("number");
  });

  it("rate limit: over 20 messages a second answers rate (once) and drops the rest", async () => {
    const { cs } = await lobbyOf(1, { ratePerSec: undefined });
    const a = cs[0];
    a.skip();
    for (let k = 0; k < 30; k++) a.send({ t: "ping", v: 1 });
    await a.wait("error");
    await new Promise((r) => setTimeout(r, 100));
    expect(a.all("error").filter((m) => m.code === "rate").length).toBe(1);
    // (the hello may share the same one-second window)
    expect(a.all("pong").length).toBeGreaterThanOrEqual(18);
    expect(a.all("pong").length).toBeLessThanOrEqual(20);
  });

  it("the room is full at 4", async () => {
    const { code } = await lobbyOf(4);
    expect((await roomInfo(code)).body).toMatchObject({ members: 4, open: false });
    const e = await Client.open(code);
    e.hello();
    expect(await e.wait("error")).toMatchObject({ code: "full" });
    await e.waitClosed();
  });

  it("settings: host only, booleans only, broadcast in lobby", async () => {
    const { cs } = await lobbyOf(2);
    const [h, g] = cs;
    g.send({ t: "settings", teams: true });
    expect(await g.wait("error")).toMatchObject({ code: "not_host" });
    h.send({ t: "settings", teams: "yes" });
    expect(await h.wait("error")).toMatchObject({ code: "bad_message" });
    h.send({ t: "settings", pair_ask: true });
    const l = await g.waitFor((m) => m.t === "lobby" && m.settings.pair_ask === true);
    expect(l.settings).toEqual({ teams: false, pair_ask: true, game: "ludo" });
    h.send({ t: "settings", teams: true });
    expect((await g.waitFor((m) => m.t === "lobby" && m.settings.teams)).settings).toEqual({ teams: true, pair_ask: true, game: "ludo" });
  });

  it("start: host only, needs 2, teams need exactly 4", async () => {
    const { cs } = await lobbyOf(1);
    cs[0].send({ t: "start" });
    expect(await cs[0].wait("error")).toMatchObject({ code: "too_few" });

    const r3 = await lobbyOf(3);
    r3.cs[1].send({ t: "start" });
    expect(await r3.cs[1].wait("error")).toMatchObject({ code: "not_host" });
    r3.cs[0].send({ t: "settings", teams: true });
    await r3.cs[0].waitFor((m) => m.t === "lobby" && m.settings.teams);
    r3.cs[0].send({ t: "start" });
    expect(await r3.cs[0].wait("error")).toMatchObject({ code: "teams_need_4" });
  });

  it("start: seats, colours, state with member names and the hash", async () => {
    const { code, cs } = await lobbyOf(3);
    cs[0].send({ t: "start" });
    const ss = await Promise.all(cs.map((c) => c.wait("start")));
    const st = ss[0];
    expect(st.n).toBe(0);
    expect(st.seats.map((s: { color: number; name: string }) => [s.color, s.name])).toEqual([
      [0, "P1"],
      [1, "P2"],
      [2, "P3"],
    ]);
    expect(st.seats.every((s: { bot: boolean; online: boolean }) => !s.bot && s.online)).toBe(true);
    expect(st.state.players).toEqual(["human", "human", "human", "off"]);
    expect(st.state.names).toEqual(["P1", "P2", "P3", ""]);
    expect(st.state.phase).toBe("roll");
    expect(st.h).toMatch(/^[0-9a-f]{8}$/);
    const turn = await cs[0].wait("turn");
    expect(turn.c).toBe(0);
    expect(turn.deadline - turn.now).toBeGreaterThan(14_000);
    expect(turn.deadline - turn.now).toBeLessThanOrEqual(15_000);
    expect((await roomInfo(code)).body).toMatchObject({ started: true, open: false });

    // late joiners are refused while the match runs
    const late = await Client.open(code);
    late.hello();
    expect(await late.wait("error")).toMatchObject({ code: "started" });
  });

  it("two players sit at Red and Yellow; teams with 4 sets state.teams", async () => {
    const r2 = await lobbyOf(2);
    r2.cs[0].send({ t: "start" });
    const s2 = await r2.cs[1].wait("start");
    expect(s2.state.players).toEqual(["human", "off", "human", "off"]);
    expect(s2.seats.map((s: { color: number }) => s.color)).toEqual([0, 2]);

    const r4 = await lobbyOf(4);
    r4.cs[0].send({ t: "settings", teams: true });
    await r4.cs[3].waitFor((m) => m.t === "lobby" && m.settings.teams);
    r4.cs[0].send({ t: "start" });
    const s4 = await r4.cs[3].wait("start");
    expect(s4.state.teams).toBe(true);
    expect(s4.state.players).toEqual(["human", "human", "human", "human"]);
  });

  it("the host leaving the lobby passes host to the next member", async () => {
    const { code, cs } = await lobbyOf(3);
    const [h, b, c] = cs;
    h.send({ t: "leave" });
    expect(await h.waitClosed()).toBe(4002);
    const l = await b.waitFor((m) => m.t === "lobby" && m.members.length === 2);
    expect(l.host).toBe(b.id);
    expect(l.members.map((m: { id: number; color: number }) => [m.id, m.color])).toEqual([
      [b.id, 0],
      [c.id, 2],
    ]);
    // the new host can start
    b.send({ t: "start" });
    await c.wait("start");
    expect((await roomInfo(code)).body.started).toBe(true);
  });

  it("the same pid (or token) takes back the same member; the old socket is replaced", async () => {
    const { code, cs } = await lobbyOf(2);
    const [, b] = cs;
    const again = await Client.join(code, { pid: b.pid, name: "Bobby" });
    expect(again.id).toBe(b.id);
    expect(again.token).toBe(b.token);
    expect(await b.waitClosed()).toBe(4001);
    const l = await again.wait("lobby");
    expect(l.members.length).toBe(2);
    expect(l.members[1].name).toBe("Bobby");
    const viaToken = await Client.join(code, { token: b.token });
    expect(viaToken.id).toBe(b.id);
  });

  it("a member offline for longer than the grace is dropped from the lobby", async () => {
    const { code, cs } = await lobbyOf(2, { timeScale: 0.01 });
    cs[1].close();
    const l = await cs[0].waitFor((m) => m.t === "lobby" && m.members.length === 1, 3000);
    expect(l.members[0].id).toBe(cs[0].id);
    expect((await roomInfo(code)).body.members).toBe(1);
  });

  it("a member whose app went to the background keeps the lobby seat longer (sharing the invite)", async () => {
    const { code, cs } = await lobbyOf(2, { timeScale: 0.01 }); // grace 200 ms, lobbyAway 3 s
    cs[1].send({ t: "away", on: true });
    cs[1].send({ t: "ping", sync: true }); // (a pong after it on the same socket: the room has handled the away)
    await cs[1].waitFor((m) => m.t === "pong");
    cs[1].close();
    await new Promise((r) => setTimeout(r, 1000)); // 5 plain graces later
    expect((await roomInfo(code)).body.members).toBe(2);
    const l = await cs[0].waitFor((m) => m.t === "lobby" && m.members.length === 1, 6000);
    expect(l.members[0].id).toBe(cs[0].id);
  });

  it("an empty room is deleted after the empty-room timeout", async () => {
    const { code, cs } = await lobbyOf(1, { timeScale: 0.0005 }); // 10 min -> 300 ms
    cs[0].close();
    await cs[0].waitClosed();
    const deadline = Date.now() + 5000;
    while ((await roomInfo(code)).status !== 404) {
      if (Date.now() > deadline) throw new Error("room not deleted");
      await new Promise((r) => setTimeout(r, 50));
    }
  });
});
