// Snakes & Ladders friend rooms: the host picks the game in the lobby; start / sync carry `game: "sl"`; the only
// action is roll; bots and timeouts roll; over carries the S&L standings.
import { describe, expect, it } from "vitest";
import { newGame } from "../src/rules/sl";
import { slStateHash } from "../src/rules/sl_hash";
import { Client, finishAll, lobbyOf, type Msg } from "./room_client";

async function slLobby(k: number, hooks = {}) {
  const r = await lobbyOf(k, hooks);
  r.cs[0].send({ t: "settings", game: "sl" });
  await Promise.all(r.cs.map((c) => c.waitFor((m) => m.t === "lobby" && m.settings.game === "sl")));
  return r;
}

const isMode = (c: number, mode: string) => (m: Msg) => m.t === "act" && m.a.k === "mode" && m.a.c === c && m.a.mode === mode;

describe("S&L friend rooms", () => {
  it("settings {game}: host only, validated; lobby colours are Red, Green, Yellow", async () => {
    const { cs } = await lobbyOf(3);
    cs[1].send({ t: "settings", game: "sl" });
    expect(await cs[1].wait("error")).toMatchObject({ code: "not_host" });
    cs[0].send({ t: "settings", game: "chess" });
    expect(await cs[0].wait("error")).toMatchObject({ code: "bad_message" });
    cs[0].send({ t: "settings", game: "sl" });
    const l = await cs[2].waitFor((m) => m.t === "lobby" && m.settings.game === "sl");
    expect(l.members.map((m: Msg) => m.color)).toEqual([0, 1, 2]);
    cs[0].send({ t: "settings", game: "ludo" });
    const l2 = await cs[2].waitFor((m) => m.t === "lobby" && m.settings.game === "ludo");
    expect(l2.members.map((m: Msg) => m.color)).toEqual([0, 1, 2]);
  });

  it("start: game sl, the S&L state with the members' names, its hash", async () => {
    const { cs } = await slLobby(2);
    cs[0].send({ t: "start" });
    const [st] = await Promise.all(cs.map((c) => c.wait("start")));
    expect(st.game).toBe("sl");
    expect(st.seats.map((s: Msg) => [s.color, s.name, s.bot])).toEqual([
      [0, "P1", false],
      [1, "P2", false],
    ]);
    expect(st.state.mode).toBe("online");
    expect(st.state.players.map((p: Msg) => [p.c, p.name, p.cpu, p.you, p.pos])).toEqual([
      [0, "P1", false, false, 0],
      [1, "P2", false, false, 0],
    ]);
    const fresh = newGame("local", 2);
    expect(st.h).toBe(slStateHash(fresh)); // names / mode are not hashed
    const t = await cs[0].wait("turn");
    expect(t).toMatchObject({ c: 0 });
    expect(t.deadline - t.now).toBe(15_000);
  });

  it("teams are ignored for S&L (3 players can start)", async () => {
    const { cs } = await lobbyOf(3);
    cs[0].send({ t: "settings", teams: true, game: "sl" });
    await cs[0].waitFor((m) => m.t === "lobby" && m.settings.game === "sl");
    cs[0].send({ t: "start" });
    const st = await cs[0].wait("start");
    expect(st.state.players.length).toBe(3);
  });

  it("only roll: move / pair are bad_action; wrong player, stale n", async () => {
    const { cs } = await slLobby(2, { dice: [3, 6, 2] });
    const [red, grn] = cs;
    red.send({ t: "start" });
    await Promise.all(cs.map((c) => c.wait("start")));
    const err = async (c: Client, msg: Msg, code: string) => {
      c.send(msg);
      expect(await c.wait("error")).toMatchObject({ code });
    };
    await err(red, { t: "move", n: 0, i: 0 }, "bad_action");
    await err(red, { t: "pair", n: 0, yes: true }, "bad_action");
    await err(grn, { t: "roll", n: 0 }, "not_your_turn");
    await err(red, { t: "roll", n: 3 }, "stale");
    red.send({ t: "roll", n: 0 });
    expect(await grn.wait("act")).toMatchObject({ n: 0, a: { k: "roll", c: 0, v: 3 } });
    expect(grn.state.players[0].pos).toBe(3);
    expect((await grn.wait("turn")).c).toBe(1);
    grn.send({ t: "roll", n: 1 });
    expect(await red.waitFor((m) => m.t === "act" && m.n === 1)).toMatchObject({ a: { k: "roll", c: 1, v: 6 } });
    expect((await red.waitFor((m) => m.t === "turn" && m.c === 1)).c).toBe(1); // a 6: Green again
    grn.send({ t: "roll", n: 2 });
    await red.waitFor((m) => m.t === "act" && m.n === 2);
    expect(red.state.players[1].pos).toBe(8);
    red.send({ t: "sync_req" });
    const s = await red.wait("sync");
    expect(s).toMatchObject({ game: "sl", n: 3 });
    expect(s.h).toBe(slStateHash(red.state));
    expect(red.hashMismatches + grn.hashMismatches).toBe(0);
  });

  it("2 players, natural dice, full game to over; standings; rematch", async () => {
    const { cs } = await slLobby(2);
    for (const c of cs) c.autoplay = true;
    cs[0].send({ t: "start" });
    await Promise.all(cs.map((c) => c.wait("start")));
    const [over] = await finishAll(cs, 28_000);
    expect([0, 1]).toContain(over.winner);
    expect(over.finished[0]).toBe(over.winner); // (two players: the second is ranked when the first is home)
    expect([...over.finished].sort()).toEqual([0, 1]);
    expect(over.standings[0]).toMatchObject({ color: over.winner, place: 1, finished: true, pos: 100 });
    expect(over.standings.map((s: Msg) => s.name).sort()).toEqual(["P1", "P2"]);
    expect(cs[0].state.players.find((p: Msg) => p.c === over.winner).pos).toBe(100);
    const l = await cs[0].waitFor((m) => m.t === "lobby");
    expect(l).toMatchObject({ status: "over", settings: { game: "sl" } });
    cs[0].send({ t: "start" });
    const again = await cs[1].wait("start");
    expect(again).toMatchObject({ n: 0, game: "sl" });
    await finishAll(cs, 28_000);
  }, 30_000);

  it("4 players; a disconnected player's bot rolls (mode cpu), back with the token", async () => {
    const { code, cs } = await slLobby(4, { timeScale: 0.02, slPos: [30, 30, 30, 30] });
    const [a, b, c, d] = cs;
    for (const x of [a, b, c]) x.autoplay = true;
    a.send({ t: "start" });
    await Promise.all(cs.map((x) => x.wait("start")));
    a.playTurn(0);
    d.close();
    await a.waitFor(isMode(3, "cpu"), 3000);
    expect(a.state.players[3].cpu).toBe(true);
    const back = await Client.join(code, { token: d.token });
    back.autoplay = true;
    const s = await back.wait("sync");
    expect(s.game).toBe("sl");
    await back.waitFor(isMode(3, "human"));
    expect(back.state.players[3].cpu).toBe(false);
    await finishAll([a, b, c, back], 28_000);
  }, 30_000);

  it("timeouts roll for a human; two in a row make a bot", async () => {
    const { cs } = await slLobby(2, { timeScale: 0.01, slPos: [0, 0] });
    const [red, grn] = cs;
    grn.autoplay = true;
    red.send({ t: "start" });
    await Promise.all(cs.map((x) => x.wait("start")));
    const first = await grn.waitFor((m) => m.t === "act" && m.a.c === 0, 3000);
    expect(first.a.k).toBe("roll");
    await grn.waitFor(isMode(0, "cpu"), 5000);
    red.send({ t: "back" });
    await grn.waitFor(isMode(0, "human"), 3000);
  });
});
