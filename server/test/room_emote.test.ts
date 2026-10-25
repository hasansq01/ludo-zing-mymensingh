// Emotes (EMOTES.md "Online relay"): relay to the others, pack ownership from the account, rate limits, the lobby
// form, no effect on the match, and the quick-match ghosts' reactions.
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { DB } from "./admin_helpers";
import { Client, NEAR_GOAL, createRoom, sleep, startAll, stubFor } from "./room_client";
import { QuickClient, guest, joinMatched, mmHooks, queueAll, resetSpies, type Guest } from "./quick_client";
import { GHOST_EMOTE, packOfEmote } from "../src/ghosts";

beforeEach(() => resetSpies());
afterEach(() => resetSpies());

const SCALE = 0.05; // 2 s -> 100 ms, 30 s -> 1.5 s
const GAP = 2000 * SCALE + 40;

async function own(g: Guest, sets: string[]): Promise<void> {
  await DB.prepare("UPDATE accounts SET owned = json_set(coalesce(owned, '{}'), '$.emote_sets', json(?)) WHERE id = ?")
    .bind(JSON.stringify(sets), g.account)
    .run();
}

/** A friend room with two guests (sessions), both in the lobby. */
async function pair(hooks = {}): Promise<{ code: string; a: Client; b: Client; ga: Guest; gb: Guest }> {
  const code = await createRoom({ ratePerSec: 1000, timeScale: SCALE, ...hooks });
  const ga = await guest();
  const gb = await guest();
  const a = await Client.join(code, { pid: ga.pid, session: ga.session, name: "A" });
  const b = await Client.join(code, { pid: gb.pid, session: gb.session, name: "B" });
  await a.waitFor((m) => m.t === "lobby" && m.members.length === 2);
  return { code, a, b, ga, gb };
}

const emotes = (c: Client) => c.log.filter((m) => m.t === "emote");

describe("emote relay", () => {
  it("lobby: others get c = -1 plus member, the sender gets nothing", async () => {
    const { a, b } = await pair();
    a.send({ t: "emote", id: "laugh" });
    const m = await b.wait("emote");
    expect(m).toEqual({ t: "emote", c: -1, member: a.id, id: "laugh" });
    await sleep(150);
    expect(emotes(a)).toEqual([]);
    expect(a.log.filter((x) => x.t === "error")).toEqual([]);
  });

  it("in a match: {t, c, id} with the sender's colour, to everyone but the sender; no state, n or hash effect", async () => {
    const { a, b } = await pair({ tok: NEAR_GOAL });
    const [sa] = await startAll([a, b]);
    const acts = a.acts;
    a.send({ t: "emote", id: "cool" });
    const m = await b.wait("emote");
    expect(Object.keys(m)).toEqual(["t", "c", "id"]);
    expect(m).toEqual({ t: "emote", c: a.color, id: "cool" });
    await sleep(100);
    expect(emotes(a)).toEqual([]);
    // the match is untouched: same n and hash in a fresh snapshot, no action was added
    a.send({ t: "sync_req" });
    const s = await a.wait("sync");
    expect(s.n).toBe(sa.n);
    expect(s.h).toBe(sa.h);
    expect(a.acts).toBe(acts);
    expect(b.acts).toBe(a.acts);
  });

  it("an unknown id is refused", async () => {
    const { a } = await pair();
    a.send({ t: "emote", id: "nope" });
    expect((await a.wait("error")).code).toBe("bad_message");
    a.send({ t: "emote" });
    expect((await a.wait("error")).code).toBe("bad_message");
  });
});

describe("pack ownership", () => {
  it("a locked pack is refused, accepted once the account owns it; starter is always allowed", async () => {
    const { a, b, ga } = await pair();
    a.send({ t: "emote", id: "champ" }); // pawns
    expect((await a.wait("error")).code).toBe("emote_locked");
    await sleep(GAP);
    expect(emotes(b)).toEqual([]);
    await own(ga, ["starter", "pawns"]);
    await sleep(GAP);
    a.send({ t: "emote", id: "champ" });
    expect((await b.wait("emote")).id).toBe("champ");
    await sleep(GAP);
    a.send({ t: "emote", id: "wow" }); // friends: still locked
    expect((await a.waitFor((m) => m.t === "error" && m.code === "emote_locked")).code).toBe("emote_locked");
    await sleep(GAP);
    a.send({ t: "emote", id: "party" }); // starter
    expect((await b.waitFor((m) => m.t === "emote" && m.id === "party")).id).toBe("party");
  });

  it("a member without an account owns only the starter pack", async () => {
    const code = await createRoom({ ratePerSec: 1000, timeScale: SCALE });
    const a = await Client.join(code, { name: "A" });
    a.send({ t: "emote", id: "crown" });
    expect((await a.wait("error")).code).toBe("emote_locked");
  });

  it("the packs are re-read after a reconnect", async () => {
    const { code, a, b, ga } = await pair();
    await own(ga, ["starter", "game"]);
    a.send({ t: "emote", id: "dice" });
    await b.wait("emote");
    await own(ga, ["starter"]); // refunded / removed behind the cache
    await sleep(GAP);
    a.send({ t: "emote", id: "dice" });
    expect((await b.waitFor((m) => m.t === "emote" && m.id === "dice")).id).toBe("dice"); // cached for the match
    a.close();
    await sleep(200);
    const a2 = await Client.join(code, { pid: ga.pid, session: ga.session, name: "A", token: a.token });
    a2.send({ t: "emote", id: "dice" });
    expect((await a2.wait("error")).code).toBe("emote_locked");
  });
});

describe("emote rate limits", () => {
  it("1 per 2 s", async () => {
    const { a, b } = await pair();
    a.send({ t: "emote", id: "happy" });
    a.send({ t: "emote", id: "laugh" });
    expect((await a.wait("error")).code).toBe("emote_rate");
    await b.wait("emote");
    await sleep(GAP);
    a.send({ t: "emote", id: "laugh" });
    expect((await b.waitFor((m) => m.t === "emote" && m.id === "laugh")).id).toBe("laugh");
    expect(emotes(b).length).toBe(2);
  });

  it("6 per 30 s", async () => {
    const { a, b } = await pair();
    for (let k = 0; k < 6; k++) {
      a.send({ t: "emote", id: "happy" });
      await sleep(GAP + 10);
    }
    await b.waitFor(() => emotes(b).length >= 6, 1000).catch(() => {});
    await sleep(50);
    expect(emotes(b).length).toBe(6);
    a.send({ t: "emote", id: "happy" });
    expect((await a.wait("error")).code).toBe("emote_rate");
    expect(emotes(b).length).toBe(6);
    await sleep(1500 + 100); // the window moves on
    a.send({ t: "emote", id: "happy" });
    await b.waitFor((m) => m.t === "emote" && emotes(b).length === 7);
  });

  it("an emote flood does not eat the 20 msg/s budget that gameplay needs", async () => {
    const { a, b } = await pair({ ratePerSec: 20, tok: NEAR_GOAL });
    await startAll([a, b]);
    for (let k = 0; k < 12; k++) a.send({ t: "emote", id: "happy" }); // 1 accepted, 11 emote_rate
    a.send({ t: "sync_req" });
    await a.wait("sync", 2000);
    expect(a.log.filter((m) => m.t === "error" && m.code === "rate")).toEqual([]);
  });
});

describe("ghost reactions", () => {
  async function quickRoom(chance: number): Promise<{ g: Guest; c: Client; ghostColor: number }> {
    await mmHooks("ludo", 2, { wait: 100, room: { timeScale: 0.1, emoteChance: chance, tok: NEAR_GOAL } });
    const g = await guest();
    const { matched } = await queueAll("ludo", 2, [g], ["Rahim"]);
    const snap = (await stubFor(matched[0].code).adminSnapshot()) as unknown as { members: Array<{ ghost?: boolean; color: number }> };
    const ghostColor = snap.members.find((m) => m.ghost)!.color;
    const c = await joinMatched(matched[0].code, matched[0].token, g, "Rahim");
    await c.wait("start");
    return { g, c, ghostColor };
  }

  it("answers a human's emote after 0.8-2.5 s (scaled), in a human's shape", async () => {
    const { c, ghostColor } = await quickRoom(1);
    const t0 = Date.now();
    c.send({ t: "emote", id: "love" });
    const m = await c.waitFor((x) => x.t === "emote" && x.c === ghostColor, 2000);
    const dt = Date.now() - t0;
    expect(Object.keys(m)).toEqual(["t", "c", "id"]);
    expect(packOfEmote(m.id)).not.toBe("");
    expect(dt).toBeGreaterThanOrEqual(GHOST_EMOTE.delay[0] * 0.1 - 25);
    expect(dt).toBeLessThanOrEqual(GHOST_EMOTE.delay[1] * 0.1 + 400);
    c.send({ t: "leave" });
  });

  it("never more than one per 8 s (scaled) per ghost, even when every event triggers", async () => {
    const { c, ghostColor } = await quickRoom(1);
    c.autoplay = true;
    c.playTurn(c.state.turn);
    await c.wait("over", 28_000);
    await sleep(300);
    const at = c.log.map((m, k) => ({ m, t: c.at[k] })).filter((x) => x.m.t === "emote" && x.m.c === ghostColor).map((x) => x.t);
    expect(at.length).toBeGreaterThan(0);
    for (let k = 1; k < at.length; k++) expect(at[k] - at[k - 1]).toBeGreaterThanOrEqual(GHOST_EMOTE.gap * 0.1 - 60);
  }, 30_000);

  it("chance 0 means silence", async () => {
    const { c, ghostColor } = await quickRoom(0);
    c.send({ t: "emote", id: "love" });
    await sleep(600);
    expect(emotes(c).filter((m) => m.c === ghostColor)).toEqual([]);
    c.send({ t: "leave" });
  });
});
