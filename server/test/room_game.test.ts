// Full matches driven by test clients (deterministic replicas with hash checks), validation, sync, rematch.
import { describe, expect, it } from "vitest";
import { stateHash } from "../src/rules/hash";
import { Client, finishAll, lobbyOf, NEAR_GOAL, startAll } from "./room_client";

function sameReplicas(cs: Client[]): void {
  const h = stateHash(cs[0].state!);
  for (const c of cs) {
    expect(stateHash(c.state!)).toBe(h);
    expect(c.n).toBe(cs[0].n);
  }
}

describe("full games", () => {
  it("2 players, natural dice, to over (replicas match after every action)", async () => {
    const { cs } = await lobbyOf(2);
    for (const c of cs) c.autoplay = true;
    await startAll(cs);
    const overs = await finishAll(cs);
    expect([0, 2]).toContain(overs[0].winner);
    expect(overs[0].finished[0]).toBe(overs[0].winner);
    expect(overs[0].standings.map((s: { color: number }) => s.color).sort()).toEqual([0, 2]);
    expect(overs[1]).toEqual(overs[0]);
    sameReplicas(cs);
    expect(cs[0].acts).toBeGreaterThan(40);
    // over is followed by the lobby (rematch screen)
    const l = await cs[0].waitFor((m) => m.t === "lobby");
    expect(l.status).toBe("over");
  });

  it("2 players who both turned on Ask before pairing, random answers, to over", async () => {
    const { cs } = await lobbyOf(2, {}, [true, true]);
    for (const c of cs) {
      c.autoplay = true;
      c.policy = { pairYes: Math.random() < 0.5 };
    }
    const st = await startAll(cs);
    expect(st[0].state.pair_ask_by).toEqual([true, false, true, false]);
    await finishAll(cs);
    sameReplicas(cs);
  });

  it("4 players (near the goal) to over", async () => {
    const { cs } = await lobbyOf(4, { tok: NEAR_GOAL });
    for (const c of cs) c.autoplay = true;
    const st = await startAll(cs);
    expect(st[0].state.tok).toEqual(NEAR_GOAL);
    const overs = await finishAll(cs);
    expect([0, 1, 2, 3]).toContain(overs[0].winner);
    sameReplicas(cs);
  });

  it("4 players in teams (near the goal) to over", async () => {
    const { cs } = await lobbyOf(4, { tok: NEAR_GOAL });
    cs[0].send({ t: "settings", teams: true });
    await cs[3].waitFor((m) => m.t === "lobby" && m.settings.teams);
    for (const c of cs) c.autoplay = true;
    await startAll(cs);
    const overs = await finishAll(cs);
    expect(overs[0].finished.length).toBeGreaterThanOrEqual(2); // both partners
    sameReplicas(cs);
  });

  it("4 players, natural dice, to over", async () => {
    const { cs } = await lobbyOf(4);
    for (const c of cs) c.autoplay = true;
    await startAll(cs);
    await finishAll(cs, 28_000);
    sameReplicas(cs);
  }, 30_000);

  it("rematch: the host starts again after over", async () => {
    const { cs } = await lobbyOf(2, { tok: NEAR_GOAL });
    for (const c of cs) c.autoplay = true;
    await startAll(cs);
    await finishAll(cs);
    cs[1].send({ t: "start" });
    expect(await cs[1].wait("error")).toMatchObject({ code: "not_host" });
    cs[0].send({ t: "start" });
    const again = await Promise.all(cs.map((c) => c.wait("start")));
    expect(again[0].n).toBe(0);
    expect(again[0].state.phase).toBe("roll");
    await finishAll(cs);
    sameReplicas(cs);
  });
});

describe("validation", () => {
  it("wrong player, wrong phase, illegal pawn and stale n change nothing", async () => {
    // Red: one pawn at base, one on the track, one home. Dice: Red rolls 2.
    const tok = [
      [-1, 10, 56, -1],
      [-1, -1, -1, -1],
      [-1, -1, -1, -1],
      [-1, -1, -1, -1],
    ];
    const { cs } = await lobbyOf(2, { tok, dice: [2, 1, 1] });
    const [red, yel] = cs;
    await startAll(cs);
    await red.wait("turn");
    const err = async (c: Client, msg: Record<string, unknown>, code: string) => {
      c.send(msg);
      expect(await c.wait("error")).toMatchObject({ code });
    };
    await err(yel, { t: "roll", n: 0 }, "not_your_turn");
    await err(red, { t: "move", n: 0, i: 1 }, "bad_action"); // phase is roll
    await err(red, { t: "pair", n: 0, yes: true }, "bad_action");
    await err(red, { t: "roll", n: 5 }, "stale");
    await err(red, { t: "roll" }, "bad_message");
    expect(red.acts).toBe(0);

    red.send({ t: "roll", n: 0 });
    red.send({ t: "roll", n: 0 }); // a double tap
    const a = await red.wait("act");
    expect(a).toMatchObject({ n: 0, a: { k: "roll", c: 0, v: 2 } });
    expect(await red.wait("error")).toMatchObject({ code: "stale" });
    expect(red.state!.phase).toBe("choose");

    await err(red, { t: "move", n: 1, i: 0 }, "bad_action"); // at base, needs a 6
    await err(red, { t: "move", n: 1, i: 2 }, "bad_action"); // already home
    await err(red, { t: "move", n: 1, i: 9 }, "bad_action");
    await err(red, { t: "move", n: 1, i: "1" }, "bad_action");
    await err(yel, { t: "move", n: 1, i: 1 }, "not_your_turn");
    await err(red, { t: "roll", n: 1 }, "bad_action");
    expect(red.acts).toBe(1);

    red.send({ t: "move", n: 1, i: 1 });
    const mv = await yel.wait("act");
    expect(mv).toMatchObject({ n: 1, a: { k: "move", c: 0, i: 1 } });
    expect(yel.state!.tok[0]).toEqual([-1, 12, 56, -1]);
    expect(yel.state!.turn).toBe(2);
    expect(yel.hashMismatches + red.hashMismatches).toBe(0);
  });

  it("settings and start are refused during a match", async () => {
    const { cs } = await lobbyOf(2);
    await startAll(cs);
    cs[0].send({ t: "settings", teams: true });
    expect(await cs[0].wait("error")).toMatchObject({ code: "bad_action" });
    cs[0].send({ t: "start" });
    expect(await cs[0].wait("error")).toMatchObject({ code: "bad_action" });
  });

  it("sync_req returns the full state with the same hash as the replica", async () => {
    const { cs } = await lobbyOf(2, { dice: [6, 6, 3] });
    const [red] = cs;
    await startAll(cs);
    red.send({ t: "roll", n: 0 });
    await red.wait("act");
    red.send({ t: "move", n: 1, i: 0 });
    await red.wait("act");
    red.send({ t: "sync_req" });
    const s = await red.wait("sync");
    expect(s.n).toBe(2);
    expect(s.h).toBe(stateHash(red.state!));
    expect(s.seats.length).toBe(2);
    const t = await red.wait("turn");
    expect(t.c).toBe(0); // a 6: Red rolls again
  });
});
