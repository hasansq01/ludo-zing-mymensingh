// Re-rolls (ECONOMY_V1.md §4): what counts as a bad roll, the offer and the hold, paying with gems or a free re-roll,
// the state put back and rolled again, once per match, no offer without the means, the window running out, ghosts.
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { badRoll } from "../src/room";
import { randomCode } from "../src/room";
import { DB, eventually, row, rows } from "./admin_helpers";
import { Client, createRoom, sleep, stubFor, type Msg } from "./room_client";
import { guest, joinMatched, resetSpies, type Guest } from "./quick_client";

beforeEach(() => resetSpies());
afterEach(() => resetSpies());

async function setAcc(account: string, cols: Record<string, number>) {
  const k = Object.keys(cols);
  await DB.prepare(`UPDATE accounts SET ${k.map((c) => `${c} = ?`).join(", ")} WHERE id = ?`).bind(...k.map((c) => cols[c]), account).run();
}

async function acc(account: string) {
  return (await row<{ gems: number; rerolls: number }>("SELECT gems, rerolls FROM accounts WHERE id = ?", account))!;
}

/** A 2-player Ludo friend room of two guest accounts, started; red (colour 0) rolls first. */
async function duo(dice: number[], means: { gems?: number; rerolls?: number } = {}, timeScale = 1) {
  const code = await createRoom({ ratePerSec: 1000, dice, timeScale });
  const a = await guest();
  const b = await guest();
  await setAcc(a.account, { gems: means.gems ?? 0, rerolls: means.rerolls ?? 0 });
  const ca = await Client.join(code, { pid: a.pid, session: a.session, name: "Ana" });
  const cb = await Client.join(code, { pid: b.pid, session: b.session, name: "Bo" });
  ca.send({ t: "start" });
  await Promise.all([ca.wait("start"), cb.wait("start")]);
  await sleep(300); // the room reads the re-roll means after the start
  expect(ca.color).toBe(0);
  expect(ca.state.turn).toBe(0);
  return { code, a, b, ca, cb };
}

describe("bad rolls", () => {
  it("Ludo: needing a 6, or stuck on a non-6; S&L: ending on a snake", () => {
    expect(badRoll("ludo", [{ type: "rolled", v: 3 }, { type: "need_six", v: 3 }, { type: "turn" }])).toBe(true);
    expect(badRoll("ludo", [{ type: "rolled", v: 4 }, { type: "stuck" }, { type: "turn" }])).toBe(true);
    expect(badRoll("ludo", [{ type: "rolled", v: 6 }, { type: "stuck" }, { type: "turn" }])).toBe(false);
    expect(badRoll("ludo", [{ type: "rolled", v: 6 }, { type: "three_sixes" }, { type: "turn" }])).toBe(false);
    expect(badRoll("ludo", [{ type: "rolled", v: 5 }, { type: "choose" }])).toBe(false);
    expect(badRoll("sl", [{ type: "rolled", v: 2 }, { type: "move", snake: true }])).toBe(true);
    expect(badRoll("sl", [{ type: "rolled", v: 2 }, { type: "move", snake: false }])).toBe(false);
  });
});

describe("a person's re-roll", () => {
  it("a 2 at the start: offer + hold; the other player waits; 5 gems pay; the state goes back and a new roll follows", async () => {
    const { a, ca, cb } = await duo([2, 6], { gems: 12 });
    ca.send({ t: "roll", n: 0 });
    const offer = await ca.wait("reroll_offer");
    expect(offer).toMatchObject({ n: 1, free: 0, gems: 12, cost: 5 });
    const hold = await cb.wait("hold");
    expect(hold).toMatchObject({ c: 0 });
    expect(cb.all("reroll_offer")).toEqual([]); // only the roller gets the offer
    expect(cb.state.turn).toBe(2); // the bad roll passed the turn
    cb.send({ t: "roll", n: 1 });
    expect(await cb.wait("error")).toMatchObject({ code: "hold" });

    ca.send({ t: "reroll", n: 1 });
    for (const c of [ca, cb]) {
      expect(await c.wait("rerolled")).toMatchObject({ c: 0, paid: "gems" });
      const sync = await c.wait("sync");
      expect(sync.n).toBe(0);
      const act = await c.wait("act");
      expect(act).toMatchObject({ n: 0, a: { k: "roll", c: 0, v: 6 } });
      expect(c.hashMismatches).toBe(0);
      expect(c.state.phase).toBe("choose"); // the 6 brings a pawn out: red's turn goes on
    }
    expect(await acc(a.account)).toEqual({ gems: 7, rerolls: 0 });
    const rr = await rows<Msg>("SELECT paid FROM rerolls WHERE account_id = ?", a.account);
    expect(rr).toEqual([{ paid: "gems" }]);
    const led = await row<Msg>("SELECT delta_gems, reason FROM ledger WHERE account_id = ? AND reason = 'reroll'", a.account);
    expect(led).toEqual({ delta_gems: -5, reason: "reroll" });
    for (const c of [ca, cb]) c.close();
  });

  it("a free re-roll is used before gems; once per match: the next bad roll gets no offer", async () => {
    const { a, ca, cb } = await duo([3, 2, 4, 1], { gems: 20, rerolls: 1 });
    ca.send({ t: "roll", n: 0 });
    await ca.wait("reroll_offer");
    ca.send({ t: "reroll", n: 1 });
    expect(await ca.wait("rerolled")).toMatchObject({ paid: "free" });
    await ca.waitFor((m) => m.t === "act" && m.a.k === "roll" && m.a.v === 2);
    expect(await acc(a.account)).toEqual({ gems: 20, rerolls: 0 });
    // the 2 also needed a 6: no second offer, Bo plays at once
    await cb.waitFor((m) => m.t === "turn" && m.c === 2);
    cb.send({ t: "roll", n: cb.n });
    await cb.waitFor((m) => m.t === "act" && m.a.c === 2);
    expect(ca.all("reroll_offer").length).toBe(1);
    for (const c of [ca, cb]) c.close();
  });

  it("without gems or free re-rolls there is no offer and no hold", async () => {
    const { ca, cb } = await duo([2, 3], { gems: 4 });
    ca.send({ t: "roll", n: 0 });
    await cb.waitFor((m) => m.t === "turn" && m.c === 2);
    cb.send({ t: "roll", n: 1 });
    await cb.waitFor((m) => m.t === "act" && m.a.c === 2);
    expect(ca.all("reroll_offer")).toEqual([]);
    expect(cb.all("hold")).toEqual([]);
    for (const c of [ca, cb]) c.close();
  });

  it("the window runs out: the next player goes on; a late reroll is refused and costs nothing", async () => {
    const { a, ca, cb } = await duo([2, 3], { gems: 10 }, 0.1); // a 300 ms window
    ca.send({ t: "roll", n: 0 });
    const offer = await ca.wait("reroll_offer");
    await sleep(Math.max(0, offer.until - offer.now) + 50);
    cb.send({ t: "roll", n: 1 });
    await cb.waitFor((m) => m.t === "act" && m.a.c === 2);
    ca.send({ t: "reroll", n: 1 });
    expect(await ca.wait("error")).toMatchObject({ code: "reroll_closed" });
    expect(await acc(a.account)).toEqual({ gems: 10, rerolls: 0 });
    for (const c of [ca, cb]) c.close();
  });

  it("the next player's clock starts after the hold (turn deadline shifted)", async () => {
    const { ca, cb } = await duo([2], { gems: 10 });
    ca.send({ t: "roll", n: 0 });
    const hold = await cb.wait("hold");
    const turn = await cb.waitFor((m) => m.t === "turn" && m.c === 2);
    expect(turn.deadline).toBeGreaterThanOrEqual(hold.until);
    for (const c of [ca, cb]) c.close();
  });

  it("a stale n or no offer: reroll_closed", async () => {
    const { ca, cb } = await duo([5], { gems: 10 });
    ca.send({ t: "reroll", n: 0 });
    expect(await ca.wait("error")).toMatchObject({ code: "reroll_closed" });
    for (const c of [ca, cb]) c.close();
  });
});

describe("ghosts", () => {
  it("a ghost that rolls badly sometimes rolls again (forced here): hold, rerolled (free), a new roll", async () => {
    const code = randomCode();
    const g: Guest = await guest();
    const hooks = { ratePerSec: 1000, timeScale: 0.2, rerollChance: 1, dice: [2, 2, 2, 5, 5, 5] };
    const spec = { game: "ludo" as const, size: 2, humans: [{ account_id: g.account, pid: g.pid, name: "Me", avatar: "pawn-red", frame: "classic", level: 1 }], hooks };
    const res = await stubFor(code).initQuick(code, spec);
    const c = await joinMatched(code, res!.tokens[g.account], g);
    c.autoplay = true;
    await c.wait("start");
    c.playTurn(c.state.turn);
    const ghost = c.seats.find((s: Msg) => s.id !== c.id)!.color;
    const rr = await c.waitFor((m) => m.t === "rerolled", 10_000);
    expect(rr).toEqual({ t: "rerolled", c: ghost, paid: "free" });
    expect(c.all("hold").some((h) => h.c === ghost)).toBe(true);
    await c.wait("sync");
    await c.waitFor((m) => m.t === "act" && m.a.k === "roll" && m.a.c === ghost);
    expect(c.hashMismatches).toBe(0);
    await eventually(async () => c.all("rerolled").length === 1 && c.acts > 3, 8000, "play goes on");
    expect(await rows("SELECT * FROM rerolls WHERE match_id LIKE ?", `${code}-%`)).toEqual([]); // ghosts pay nothing
    c.close();
  });
});
