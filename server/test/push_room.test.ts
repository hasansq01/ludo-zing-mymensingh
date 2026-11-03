// Event pushes from friend rooms (NOTIFICATIONS.md "Event pushes"): the {t: "away"} message, "It's your turn" /
// "Friend joined" / "Rematch?" to away members with an account (Game alerts on), their throttles, and never: for
// members who are here, when nobody is waiting, in quick rooms, with push off. The match itself never changes (the
// test clients replay every act and check its hash).
import { runInDurableObject } from "cloudflare:test";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { randomCode } from "../src/room";
import { setPushServiceAccount } from "../src/push";
import { eventually, rows } from "./admin_helpers";
import { guest, joinMatched, type Guest } from "./quick_client";
import { Client, NEAR_GOAL, createRoom, finishAll, sleep, startAll, stubFor, type Msg } from "./room_client";
import { fcmToken, installFakeFcm, register, uninstallFakeFcm, type FakeFcm } from "./push_helpers";

let fcm: FakeFcm;
beforeAll(async () => {
  fcm = await installFakeFcm();
});
afterAll(() => uninstallFakeFcm());
beforeEach(() => {
  fcm.reset();
  setPushServiceAccount(fcm.serviceAccount);
});

/** No 6s: every roll passes the turn (all pawns stay in the yard). */
const PASS = Array.from({ length: 60 }, (_, k) => [2, 3, 4, 5][k % 4]);

interface P {
  g: Guest;
  c: Client;
  token: string;
}

/** A friend room of guests with devices (first = host), all in the lobby. */
async function room(names: string[], hooks: Record<string, unknown> = {}, prefs: Array<{ game?: boolean }> = []): Promise<{ code: string; ps: P[] }> {
  const code = await createRoom({ ratePerSec: 1000, dice: [...PASS], ...hooks });
  const ps: P[] = [];
  for (const [k, name] of names.entries()) {
    const g = await guest();
    const token = fcmToken(name);
    await register(g.session, token, prefs[k] ?? {});
    const c = await Client.join(code, { pid: g.pid, session: g.session, name });
    await c.waitFor((m) => m.t === "lobby" && m.members.length === k + 1);
    ps.push({ g, c, token });
  }
  return { code, ps };
}

const to = (token: string) => fcm.delivered.filter((m) => m.token === token);
const pushedTo = (token: string, kind: string, n = 1) => eventually(async () => to(token).filter((m) => m.data.kind === kind).length >= n, 5000, `${kind} push`);

/** The player whose turn it is rolls (a pass with the PASS dice) and everyone sees the act. */
async function pass(ps: P[], who: P): Promise<void> {
  who.c.send({ t: "roll", n: who.c.n });
  await Promise.all(ps.map((p) => p.c.waitFor((m) => m.t === "act" && m.a.k === "roll")));
}

/** Sends {t: "away", on} and waits until the room has handled it (a pong after it on the same socket). */
async function away(c: Client, on: boolean): Promise<void> {
  c.send({ t: "away", on });
  c.send({ t: "ping", sync: true });
  await c.waitFor((m) => m.t === "pong");
}

/** Makes the member's last push of `kind` look `ms` older (the 3 min throttle). */
async function age(code: string, memberId: number, kind: string, ms: number): Promise<void> {
  await runInDurableObject(stubFor(code), (inst) => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const mem = (inst as any).room.members.find((x: Msg) => x.id === memberId);
    mem.pushed[kind] -= ms;
  });
}

describe("away", () => {
  it("is ignored before hello, needs a bool, and answers nothing", async () => {
    const code = await createRoom({ ratePerSec: 1000 });
    const c = await Client.open(code);
    c.send({ t: "away", on: true }); // before hello: ignored
    c.hello();
    await c.wait("welcome");
    await c.wait("lobby");
    c.send({ t: "away", on: "yes" });
    expect((await c.wait("error")).code).toBe("bad_message");
    await away(c, true);
    await away(c, false);
    expect(c.log.filter((m) => m.t === "error")).toHaveLength(1);
    expect(c.log.filter((m) => m.t === "lobby")).toHaveLength(1); // presence is unchanged for the others
    c.close();
  });
});

describe("It's your turn", () => {
  it("goes to an away member when their turn starts: once per 3 minutes; the match is untouched", async () => {
    const { code, ps } = await room(["Ann", "Bob"]);
    const [a, b] = ps;
    await startAll(ps.map((p) => p.c));
    await away(b.c, true);
    await pass(ps, a); // -> Bob's turn
    await pushedTo(b.token, "turn");
    expect(to(b.token)[0]).toEqual({
      token: b.token,
      notification: { title: "It's your turn", body: `Ann is waiting for you in room ${code}` },
      data: { link: `room:${code}`, kind: "turn" },
      android: { priority: "high", ttl: "1800s", collapse_key: `room:${code}`, notification: { channel_id: "game", tag: `room:${code}` } },
    });
    expect(to(a.token)).toEqual([]);
    await pass(ps, b);
    await pass(ps, a); // Bob's turn again, within 3 min: no push
    await sleep(150);
    expect(to(b.token)).toHaveLength(1);
    await age(code, b.c.id, "turn", 3 * 60_000);
    await pass(ps, b);
    await pass(ps, a);
    await pushedTo(b.token, "turn", 2);
    await eventually(async () => (await rows<{ sent: number }>("SELECT sent FROM push_events WHERE kind = 'turn'"))[0]?.sent === 2, 5000, "counter");
    for (const p of ps) {
      expect(p.c.hashMismatches).toBe(0);
      expect(p.c.orderErrors).toBe(0);
    }
    expect(a.c.n).toBe(5);
    for (const p of ps) p.c.close();
  });

  it("goes to a member with no open socket (the disconnect grace), not to one who is back", async () => {
    const { code, ps } = await room(["Ann", "Bob"]);
    const [a, b] = ps;
    await startAll(ps.map((p) => p.c));
    await away(b.c, true);
    await away(b.c, false); // back
    await pass(ps, a);
    await sleep(150);
    expect(to(b.token)).toEqual([]);
    await pass(ps, b);
    b.c.close();
    await a.c.waitFor((m) => m.t === "presence" && m.online === false);
    a.c.send({ t: "roll", n: a.c.n });
    await a.c.waitFor((m) => m.t === "act" && m.a.k === "roll");
    await pushedTo(b.token, "turn");
    expect(to(b.token)[0].notification.body).toBe(`Ann is waiting for you in room ${code}`);
    a.c.close();
  });

  it("nobody is waiting (everyone away): no push", async () => {
    const { ps } = await room(["Ann", "Bob"]);
    const [a, b] = ps;
    await startAll(ps.map((p) => p.c));
    await away(a.c, true);
    await away(b.c, true);
    await pass(ps, a);
    await sleep(200);
    expect(fcm.sends).toEqual([]);
    for (const p of ps) p.c.close();
  });

  it("Game alerts off on the device: nothing sent", async () => {
    const { ps } = await room(["Ann", "Bob"], {}, [{}, { game: false }]);
    const [a, b] = ps;
    await startAll(ps.map((p) => p.c));
    await away(b.c, true);
    await pass(ps, a);
    await sleep(200);
    expect(fcm.sends).toEqual([]);
    for (const p of ps) p.c.close();
  });

  it("push off: nothing sent and nothing recorded on the member", async () => {
    setPushServiceAccount(null);
    const { code, ps } = await room(["Ann", "Bob"]);
    const [a, b] = ps;
    await startAll(ps.map((p) => p.c));
    await away(b.c, true);
    await pass(ps, a);
    await sleep(200);
    expect(fcm.sends).toEqual([]);
    const pushed = await runInDurableObject(stubFor(code), (inst) =>
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      (inst as any).room.members.map((m: Msg) => m.pushed ?? null),
    );
    expect(pushed).toEqual([null, null]);
    for (const p of ps) p.c.close();
  });
});

describe("Friend joined", () => {
  it("goes to the host when someone joins while the host is away (throttled), not when the host is here", async () => {
    const { code, ps } = await room(["Ann"]);
    const [host] = ps;
    const join = async (name: string) => {
      const c = await Client.join(code, { name });
      await host.c.waitFor((m) => m.t === "lobby" && m.members.some((x: Msg) => x.name === name));
      return c;
    };
    const c1 = await join("Cat");
    await sleep(150);
    expect(fcm.sends).toEqual([]); // the host is here
    await away(host.c, true);
    const c2 = await join("Dan");
    await pushedTo(host.token, "joined");
    expect(to(host.token)[0]).toMatchObject({
      notification: { title: "Friend joined", body: `Dan joined your room ${code}` },
      data: { link: `room:${code}`, kind: "joined" },
      android: { priority: "high", collapse_key: `room:${code}` },
    });
    const c3 = await join("Eve"); // within 3 min: no second push
    await sleep(150);
    expect(to(host.token)).toHaveLength(1);
    for (const c of [host.c, c1, c2, c3]) c.close();
  });
});

describe("Rematch?", () => {
  it("goes to away members when the match ends (back to the lobby)", async () => {
    const { code, ps } = await room(["Ann", "Bob"], { tok: NEAR_GOAL, dice: undefined });
    const [a, b] = ps;
    for (const p of ps) p.c.autoplay = true;
    await startAll(ps.map((p) => p.c));
    a.c.playTurn(a.c.state.turn);
    await away(b.c, true); // (still plays: the test client ignores its own away)
    await finishAll(ps.map((p) => p.c));
    await pushedTo(b.token, "rematch");
    expect(to(b.token).find((m) => m.data.kind === "rematch")).toMatchObject({
      notification: { title: "Rematch?", body: `Ann wants a rematch in room ${code}` },
      data: { link: `room:${code}`, kind: "rematch" },
    });
    expect(to(a.token)).toEqual([]);
    for (const p of ps) p.c.close();
  });
});

describe("never in quick rooms", () => {
  it("an away human in a quick match gets no turn push", async () => {
    const code = randomCode();
    const [g1, g2] = [await guest(), await guest()];
    const [t1, t2] = [fcmToken("q1"), fcmToken("q2")];
    await register(g1.session, t1);
    await register(g2.session, t2);
    const human = (g: Guest, name: string) => ({ account_id: g.account, pid: g.pid, name, avatar: "pawn-red", frame: "classic", level: 1 });
    const res = await stubFor(code).initQuick(code, { game: "ludo", size: 2, humans: [human(g1, "Q1"), human(g2, "Q2")], hooks: { ratePerSec: 1000, dice: [...PASS] } });
    const c1 = await joinMatched(code, res!.tokens[g1.account], g1, "Q1");
    const c2 = await joinMatched(code, res!.tokens[g2.account], g2, "Q2");
    await Promise.all([c1.wait("start"), c2.wait("start")]);
    const first = c1.state.turn === c1.color ? c1 : c2;
    const other = first === c1 ? c2 : c1;
    await away(other, true);
    first.send({ t: "roll", n: first.n });
    await other.waitFor((m) => m.t === "turn" && m.c === other.color);
    await sleep(200);
    expect(fcm.sends).toEqual([]);
    c1.close();
    c2.close();
  });
});

describe("nothing without accounts", () => {
  it("a member without an account gets nothing", async () => {
    const code = await createRoom({ ratePerSec: 1000, dice: [...PASS] });
    const a = await Client.join(code, { name: "Ann" });
    const b = await Client.join(code, { name: "Bob" });
    await a.waitFor((m) => m.t === "lobby" && m.members.length === 2);
    await startAll([a, b]);
    await away(b, true);
    a.send({ t: "roll", n: a.n });
    await b.waitFor((m) => m.t === "turn" && m.c === b.color);
    await sleep(200);
    expect(fcm.sends).toEqual([]);
    a.close();
    b.close();
  });
});
