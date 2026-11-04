// Emotes (EMOTES.md "Online relay"): relay to the others, pack ownership from the account, rate limits, the lobby
// form, no effect on the match, and the quick-match ghosts' reactions.
import { evictDurableObject, runInDurableObject } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { DB } from "./admin_helpers";
import { Client, NEAR_GOAL, createRoom, sleep, startAll, stubFor, type Msg } from "./room_client";
import { QuickClient, guest, joinMatched, mmHooks, queueAll, resetSpies, type Guest } from "./quick_client";
import { GHOST_DELAY_MAX, GHOST_EMOTE, packOfEmote } from "../src/ghosts";

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
    // Timing-robust: a slower scale (2 s -> 500 ms, 30 s -> 7.5 s) and sends spaced twice the gap apart, so that no
    // CPU-load jitter can push two sends inside one gap, or the 7th send out of the first send's window.
    const K = 0.25;
    const { a, b } = await pair({ timeScale: K });
    const spacing = 2000 * K * 2; // 1 s: >= 500 ms gap with 500 ms of margin; 6 sends span 5 s of the 7.5 s window
    for (let k = 0; k < 6; k++) {
      a.send({ t: "emote", id: "happy" });
      await b.waitFor(() => emotes(b).length >= k + 1, 3000);
      if (k < 5) await sleep(spacing);
    }
    expect(emotes(b).length).toBe(6);
    expect(a.log.filter((m) => m.t === "error")).toEqual([]);
    a.send({ t: "emote", id: "happy" }); // ~5 s after the first: still inside its 7.5 s window
    expect((await a.wait("error")).code).toBe("emote_rate");
    expect(emotes(b).length).toBe(6);
    await sleep(30_000 * K); // far past the first send's window (>= 5 s of margin even when the sends ran late)
    a.send({ t: "emote", id: "happy" });
    await b.waitFor(() => emotes(b).length === 7, 3000);
  }, 40_000);

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
  async function quickRoom(chance: number): Promise<{ g: Guest; c: Client; ghostColor: number; code: string }> {
    await mmHooks("ludo", 2, { wait: 100, room: { timeScale: 0.1, emoteChance: chance, tok: NEAR_GOAL } });
    const g = await guest();
    const { matched } = await queueAll("ludo", 2, [g], ["Rahim"]);
    const snap = (await stubFor(matched[0].code).adminSnapshot()) as unknown as { members: Array<{ ghost?: boolean; color: number }> };
    const ghostColor = snap.members.find((m) => m.ghost)!.color;
    const c = await joinMatched(matched[0].code, matched[0].token, g, "Rahim");
    await c.wait("start");
    return { g, c, ghostColor, code: matched[0].code };
  }

  /** Sends `id` until the ghost on `color` emotes (it can be busy with its own pace); returns it and the send time. */
  async function chatUntilGhost(c: Client, color: number, id: string, tries = 10): Promise<{ m: Msg; dt: number }> {
    for (let k = 0; k < tries; k++) {
      const seen = c.log.length;
      const t0 = Date.now();
      c.send({ t: "emote", id });
      try {
        const m = await c.waitFor((x) => x.t === "emote" && x.c === color && c.log.indexOf(x) >= seen, 1400);
        return { m, dt: Date.now() - t0 };
      } catch {
        await sleep(2000 * 0.1 + 80);
      }
    }
    throw new Error("the ghost never answered");
  }

  it("answers a human's emote after 0.8-2.5 s (scaled), in a human's shape", async () => {
    const { c, ghostColor } = await quickRoom(1);
    const { m, dt } = await chatUntilGhost(c, ghostColor, "love");
    expect(Object.keys(m)).toEqual(["t", "c", "id"]);
    expect(packOfEmote(m.id)).not.toBe("");
    expect(dt).toBeGreaterThanOrEqual(GHOST_EMOTE.delay[0] * 0.1 - 25);
    expect(dt).toBeLessThanOrEqual(GHOST_DELAY_MAX * 0.1 + 400); // 1-3.5 s, up to 5.5 s more on its own turn
    c.send({ t: "leave" });
  });

  it("obeys the humans' limits (1 per 2 s, 6 per 30 s, scaled) and never repeats back to back, even when every event triggers", { retry: 2, timeout: 30_000 }, async () => {
    const { c, ghostColor } = await quickRoom(1);
    c.autoplay = true;
    c.playTurn(c.state.turn);
    await c.wait("over", 28_000);
    await sleep(GHOST_DELAY_MAX * 0.1 + 300); // the last planned emotes still go out
    const at = c.log.map((m, k) => ({ m, t: c.at[k] })).filter((x) => x.m.t === "emote" && x.m.c === ghostColor).map((x) => x.t);
    expect(at.length).toBeGreaterThan(0);
    // receipt times: delivery jitter under load can bunch two frames together, so allow JITTER (the exact limits are
    // checked deterministically on ghostEmoteReply in ghost_emote.test.ts)
    const JITTER = 160;
    for (let k = 1; k < at.length; k++) expect(at[k] - at[k - 1]).toBeGreaterThanOrEqual(GHOST_EMOTE.minGap * 0.1 - JITTER);
    for (let k = 6; k < at.length; k++) expect(at[k] - at[k - 6]).toBeGreaterThanOrEqual(GHOST_EMOTE.window * 0.1 - JITTER);
    const ids = c.log.filter((m) => m.t === "emote" && m.c === ghostColor).map((m) => m.id);
    for (let k = 1; k < ids.length; k++) expect(ids[k]).not.toBe(ids[k - 1]);
  });

  it("chance 0 means silence", async () => {
    const { c, ghostColor } = await quickRoom(0);
    c.send({ t: "emote", id: "love" });
    await sleep(600);
    expect(emotes(c).filter((m) => m.c === ghostColor)).toEqual([]);
    c.send({ t: "leave" });
  });

  it("the persona and the chat memory live in the room's storage: an evicted room keeps both and keeps the plan", async () => {
    const { c, ghostColor, code } = await quickRoom(1);
    const members = (): Promise<Array<{ ghost?: boolean; persona?: string; emo?: { last: string[]; sent: number[] } }>> =>
      runInDurableObject(stubFor(code), (inst) => JSON.parse(JSON.stringify((inst as unknown as { room: { members: never[] } }).room.members)));
    const before = (await members()).find((m) => m.ghost)!;
    expect(["chatty", "quiet", "cheeky", "friendly", "sore"]).toContain(before.persona);
    c.send({ t: "emote", id: "love" });
    // evicted while the reply is still only planned: the plan (alarm) survives
    await sleep(60);
    await evictDurableObject(stubFor(code));
    let first: Msg;
    try {
      first = await c.waitFor((x) => x.t === "emote" && x.c === ghostColor, 1500);
    } catch {
      first = (await chatUntilGhost(c, ghostColor, "love")).m; // it was busy with its own pace: ask again
    }
    const mid = (await members()).find((m) => m.ghost)!;
    expect(mid.persona).toBe(before.persona);
    expect(mid.emo!.last).toContain(first.id);
    await evictDurableObject(stubFor(code));
    const after = (await members()).find((m) => m.ghost)!;
    expect(after.persona).toBe(before.persona);
    expect(after.emo!.last).toContain(first.id); // memory survived a second eviction
    await chatUntilGhost(c, ghostColor, "love");
    const ids = c.log.filter((x) => x.t === "emote" && x.c === ghostColor).map((x) => x.id);
    expect(ids.length).toBeGreaterThanOrEqual(2);
    for (let k = 1; k < ids.length; k++) expect(ids[k]).not.toBe(ids[k - 1]); // never the same twice running, across evictions
    c.send({ t: "leave" });
  }, 20_000);
});
