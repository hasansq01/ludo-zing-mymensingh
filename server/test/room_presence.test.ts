// Presence and timers: reconnect, disconnect grace -> bot, timeouts -> bot, back, leave, hibernation / eviction,
// paused bots, stale-room cleanup. Timers run for real with a test time scale (TestHooks.timeScale).
import { evictDurableObject, runInDurableObject } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import { Client, finishAll, lobbyOf, NEAR_GOAL, roomInfo, sleep, startAll, stubFor, type Msg } from "./room_client";

const isMode = (c: number, mode: string) => (m: Msg) => m.t === "act" && m.a.k === "mode" && m.a.c === c && m.a.mode === mode;

describe("reconnect", () => {
  it("reconnecting with the token within the grace restores the seat and sends sync", async () => {
    const { code, cs } = await lobbyOf(2, { dice: [6, 6, 2] });
    const [red, yel] = cs;
    await startAll(cs);
    red.send({ t: "roll", n: 0 });
    await yel.wait("act");
    red.close();
    expect(await yel.wait("presence")).toEqual({ t: "presence", id: red.id, online: false });

    const back = await Client.join(code, { token: red.token, name: "P1" });
    expect(back.id).toBe(red.id);
    const s = await back.wait("sync");
    expect(s.n).toBe(1);
    expect(s.state.phase).toBe("choose");
    expect(s.seats.find((x: Msg) => x.id === red.id)).toMatchObject({ color: 0, online: true, bot: false });
    const t = await back.wait("turn");
    expect(t.c).toBe(0);
    expect(await yel.wait("presence")).toEqual({ t: "presence", id: red.id, online: true });
    // and plays on with the same n
    back.send({ t: "move", n: 1, i: 0 });
    expect(await yel.wait("act")).toMatchObject({ n: 1, a: { k: "move", c: 0, i: 0 } });
    expect(back.hashMismatches + yel.hashMismatches).toBe(0);
    expect(back.all("act").some((m) => m.a.k === "mode")).toBe(false);
  });

  it("after the grace a bot takes the seat; reconnecting gets sync then mode human", async () => {
    const { code, cs } = await lobbyOf(2, { timeScale: 0.01 });
    const [red, yel] = cs;
    yel.autoplay = true;
    await startAll(cs);
    red.close();
    await yel.waitFor(isMode(0, "cpu"), 3000);
    await yel.waitFor((m) => m.t === "act" && m.a.c === 0 && m.a.k !== "mode", 3000); // the bot plays Red

    const back = await Client.join(code, { token: red.token });
    back.autoplay = true;
    const s = await back.wait("sync");
    expect(s.state.players[0]).toBe("cpu");
    const mh = await back.waitFor(isMode(0, "human"));
    expect(mh.n).toBe(s.n);
    expect(back.state!.players[0]).toBe("human");
    await finishAll([back, yel]);
  });

  it("a disconnected player's bot finishes the game", async () => {
    const { cs } = await lobbyOf(2, { timeScale: 0.01 });
    const [red, yel] = cs;
    yel.autoplay = true;
    await startAll(cs);
    red.close();
    await yel.waitFor(isMode(0, "cpu"), 3000);
    const [over] = await finishAll([yel], 25_000);
    expect([0, 2]).toContain(over.winner);
    expect(yel.state!.players).toEqual(["cpu", "off", "human", "off"]);
  });
});

describe("timeouts", () => {
  it("a timeout auto-acts; two in a row make a bot; back (or a roll) brings the player back", async () => {
    const { cs } = await lobbyOf(2, { timeScale: 0.02, tok: NEAR_GOAL });
    const [red, yel] = cs;
    yel.autoplay = true;
    await startAll(cs);
    // Red never acts: the first timeout rolls for Red, the second (roll or move) makes Red a bot
    const first = await red.waitFor((m) => m.t === "act" && m.a.c === 0, 3000);
    expect(first.a.k).toBe("roll");
    await red.waitFor(isMode(0, "cpu"), 3000);
    expect(red.state!.players[0]).toBe("cpu");
    // the bot keeps playing Red
    await red.waitFor((m) => m.t === "act" && m.a.c === 0 && m.a.k !== "mode", 3000);

    red.send({ t: "back" });
    await yel.waitFor(isMode(0, "human"), 3000);
    expect(yel.state!.players[0]).toBe("human");
    red.autoplay = true;
    if (red.state!.turn === 0 && red.state!.players[0] === "human") red.playTurn(0);
    await finishAll(cs);
  });

  it("any roll from a player turned into a bot counts as back", async () => {
    const { cs } = await lobbyOf(2, { timeScale: 0.05 }); // bots wait 40-70 ms, humans 750 ms to roll
    const [red, yel] = cs;
    yel.autoplay = true;
    await startAll(cs);
    await red.waitFor(isMode(0, "cpu"), 5000);
    // on Red's next turn, roll before the bot does
    for (;;) {
      const t = await red.waitFor((m) => m.t === "turn", 5000);
      if (t.c === 0 && red.state!.phase === "roll") break;
    }
    const n = red.n;
    red.send({ t: "roll", n });
    const mh = await red.waitFor((m) => m.t === "act" && m.n === n, 2000);
    expect(mh.a).toEqual({ k: "mode", c: 0, mode: "human" });
    const roll = await red.waitFor((m) => m.t === "act" && m.n === n + 1, 2000);
    expect(roll.a).toMatchObject({ k: "roll", c: 0 });
  });
});

describe("leave and host", () => {
  it("leaving a match: a bot plays the seat for good, host passes, the token no longer works", async () => {
    const { code, cs } = await lobbyOf(3, { timeScale: 0.01, tok: NEAR_GOAL });
    const [red, grn, yel] = cs;
    grn.autoplay = true;
    yel.autoplay = true;
    await startAll(cs);
    red.send({ t: "leave" });
    expect(await red.waitClosed()).toBe(4002);
    expect(await grn.wait("presence")).toEqual({ t: "presence", id: red.id, online: false });
    await grn.waitFor(isMode(0, "cpu"));
    const l = await grn.wait("lobby");
    expect(l.host).toBe(grn.id);
    expect(l.members.map((m: Msg) => m.id)).toEqual([grn.id, yel.id]);

    const again = await Client.open(code, red.pid);
    again.hello(red.token);
    expect(await again.wait("error")).toMatchObject({ code: "started" });

    await finishAll([grn, yel]);
    // the new host can start the rematch with the two remaining members
    grn.send({ t: "start" });
    const st = await yel.wait("start");
    expect(st.seats.map((s: Msg) => s.id)).toEqual([grn.id, yel.id]);
    expect(st.state.players).toEqual(["human", "off", "human", "off"]);
  });
});

describe("hibernation and cleanup", () => {
  it("an evicted room resumes from storage with hibernated sockets", async () => {
    const { code, cs } = await lobbyOf(2, { dice: [6, 4, 3] });
    const [red, yel] = cs;
    await startAll(cs);
    red.send({ t: "roll", n: 0 });
    await yel.wait("act");
    await evictDurableObject(stubFor(code));
    expect((await roomInfo(code)).body).toMatchObject({ started: true, members: 2 });
    red.send({ t: "move", n: 1, i: 0 });
    expect(await yel.wait("act")).toMatchObject({ n: 1, a: { k: "move", c: 0, i: 0 } });
    red.send({ t: "roll", n: 2 });
    expect(await yel.wait("act")).toMatchObject({ n: 2, a: { k: "roll", c: 0, v: 4 } }); // hooks survived too
    red.send({ t: "sync_req" });
    const s = await red.wait("sync");
    expect(s.seats.every((x: Msg) => x.online)).toBe(true);
    expect(red.hashMismatches + yel.hashMismatches).toBe(0);
  });

  it("the match freezes while nobody is connected (no step, no grace runs) and resumes where it was", async () => {
    const { code, cs } = await lobbyOf(2, { timeScale: 0.01 });
    const [red, yel] = cs;
    await startAll(cs);
    red.close();
    yel.close();
    await sleep(600); // 3 graces (200 ms) long: nothing runs while frozen
    type M = { n: number; due: number; frozenAt?: number; state: { players: string[] } };
    const nOf = () => runInDurableObject(stubFor(code), (_i, st) => (st.storage.kv.get("room") as { match: M }).match);
    const a = await nOf();
    expect(a.frozenAt).toBeGreaterThan(0);
    expect(a.due).toBe(0);
    await sleep(300);
    const b = await nOf();
    expect(b.n).toBe(a.n);
    expect(b.due).toBe(0);
    expect(b.state.players[2]).toBe("human"); // yellow's grace stood still while frozen: no bot took the seat

    const back = await Client.join(code, { token: yel.token });
    back.autoplay = true;
    await back.wait("sync");
    expect((await nOf()).frozenAt ?? 0).toBe(0);
    await back.waitFor((m) => m.t === "turn"); // re-planned: the turn goes on
    const [over] = await finishAll([back], 25_000);
    expect([0, 2]).toContain(over.winner);
    expect(back.log.some((m) => isMode(2, "cpu")(m))).toBe(false);
  });

  it("a room with no action for the stale timeout is deleted, connected or not", async () => {
    const { code, cs } = await lobbyOf(2, { timeScale: 0.0002 }); // 2 h -> 1.44 s (room for both joins on a busy run)
    const e = await cs[0].waitFor((m) => m.t === "error" && m.code === "not_found", 5000);
    expect(e.msg).toMatch(/closed/);
    expect(await cs[0].waitClosed()).toBe(4004);
    expect((await roomInfo(code)).status).toBe(404);
  });
});
