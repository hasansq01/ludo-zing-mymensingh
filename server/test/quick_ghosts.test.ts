// Ghosts never show: every message a client receives (queue and room, Ludo and S&L) is collected and checked for any
// field that would tell a ghost from a person; ghost identities look like people's; ghosts act in human time windows
// and never time out.
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { EMOTE_PACKS, FEMALE_NAMES, FREE_AVATARS, GHOST_TIMING, MALE_NAMES, packOfEmote } from "../src/ghosts";
import type { AdminSnapshot } from "../src/room";
import { Client, NEAR_GOAL, finishAll, stubFor, type Msg } from "./room_client";
import { QuickClient, guest, joinMatched, mmHooks, queueAll, resetSpies, walk, type Guest } from "./quick_client";

beforeEach(() => resetSpies());
afterEach(() => resetSpies());

const POOL = new Set<string>([...MALE_NAMES, ...FEMALE_NAMES]);
const SCALE = 0.05;
const TIMERS = { roll: 15_000 * SCALE, choose: 20_000 * SCALE, pair_ask: 10_000 * SCALE };

interface Played {
  code: string;
  snap: AdminSnapshot;
  qs: QuickClient[];
  cs: Client[];
  ghostColors: Set<number>;
  ghostIds: Set<number>;
}

/** A full quick match with these humans (autoplay), returning everything every client received. */
async function play(game: string, size: number, humans: number, names: string[]): Promise<Played> {
  await mmHooks(game, size, { wait: 150, room: { timeScale: SCALE, emoteChance: 1, rerollChance: 1, ...(game === "ludo" ? { tok: NEAR_GOAL } : { slPos: [80, 80, 80, 80] }) } });
  const gs: Guest[] = [];
  for (let k = 0; k < humans; k++) gs.push(await guest());
  const { qs, matched } = await queueAll(game, size, gs, names);
  const code = matched[0].code;
  const snap = (await stubFor(code).adminSnapshot()) as unknown as AdminSnapshot;
  const cs: Client[] = [];
  for (let k = 0; k < humans; k++) cs.push(await joinMatched(code, matched[k].token, gs[k], names[k]));
  await Promise.all(cs.map((c) => c.wait("start", 5000)));
  for (const c of cs) c.send({ t: "emote", id: "happy" }); // a human's emote (ghosts may answer it)
  for (const c of cs) {
    c.autoplay = true;
    c.playTurn(game === "sl" ? c.state.players[c.state.turn].c : c.state.turn);
  }
  await finishAll(cs, 28_000);
  const ghostIds = new Set(snap.members.filter((m) => m.ghost).map((m) => m.id));
  const ghostColors = new Set(snap.members.filter((m) => m.ghost).map((m) => m.color));
  return { code, snap, qs, cs, ghostColors, ghostIds };
}

/** The leak checks over everything the humans received. */
function audit(p: Played, game: string, humanNames: string[]): void {
  const all: Msg[] = [...p.qs.flatMap((q) => q.log), ...p.cs.flatMap((c) => c.log)];
  // 1. nothing anywhere says ghost
  const w = walk(all);
  expect(w.keys.filter((k) => /ghost/i.test(k))).toEqual([]);
  expect(w.strings.filter((s) => /ghost/i.test(s))).toEqual([]);
  // 2. queue messages: fixed shapes
  for (const q of p.qs) {
    for (const m of q.log) {
      if (m.t === "queued") expect(Object.keys(m).sort()).toEqual(["eta_s", "position", "t"]);
      else if (m.t === "matched") expect(Object.keys(m).sort()).toEqual(["code", "t", "token"]);
      else throw new Error(`unexpected queue message ${JSON.stringify(m)}`);
    }
  }
  const humanNamesLc = humanNames.map((n) => n.toLowerCase());
  for (const c of p.cs) {
    for (let k = 0; k < c.log.length; k++) {
      const m = c.log[k];
      expect(["welcome", "start", "sync", "act", "turn", "presence", "over", "error", "pong", "emote", "hold", "rerolled"]).toContain(m.t);
      // re-rolls (ECONOMY_V1.md §4): a ghost's look exactly like a person's free one
      if (m.t === "hold") expect(Object.keys(m).sort()).toEqual(["c", "t", "until"]);
      if (m.t === "rerolled") expect(Object.keys(m).sort()).toEqual(["c", "paid", "t"]);
      if (m.t === "welcome") expect(m.host).toBe(-1);
      if (m.t === "start" || m.t === "sync") {
        expect(m.game).toBe(game);
        const keys = m.seats.map((s: Msg) => Object.keys(s).sort().join(","));
        expect(new Set(keys).size).toBe(1); // every seat has exactly the same fields
        expect(keys[0]).toBe("avatar,bot,color,frame,id,level,name,online");
        const ghostSeats = m.seats.filter((s: Msg) => p.ghostColors.has(s.color));
        expect(ghostSeats.length).toBe(p.ghostColors.size);
        const names = m.seats.map((s: Msg) => s.name.toLowerCase());
        expect(new Set(names).size).toBe(names.length); // no duplicate names in a room
        for (const s of ghostSeats) {
          expect(s.bot).toBe(false);
          expect(s.online).toBe(true);
          expect(POOL.has(s.name)).toBe(true);
          expect(humanNamesLc).not.toContain(s.name.toLowerCase());
          expect(FREE_AVATARS).toContain(s.avatar);
          expect(s.frame).toBe("classic");
          expect(s.level).toBeGreaterThanOrEqual(1);
          expect(s.level).toBeLessThanOrEqual(4); // new guests are level 1: ghosts within +3
          if (game === "ludo") {
            expect(m.state.players[s.color]).toBe("human");
            expect(m.state.names[s.color]).toBe(s.name);
          } else {
            const pl = m.state.players.find((x: Msg) => x.c === s.color);
            expect(pl).toMatchObject({ cpu: false, you: false, name: s.name });
          }
        }
      }
      if (m.t === "act") {
        expect(Object.keys(m).sort()).toEqual(["a", "h", "n", "t"]);
        if (p.ghostColors.has(m.a.c)) expect(m.a.k).not.toBe("mode");
      }
      if (m.t === "turn") {
        expect(Object.keys(m).sort()).toEqual(["c", "deadline", "now", "t"]);
        // a ghost's turn carries a person's deadline (the configured turn timer), like everyone's; after a hold
        // (a re-roll offer) it starts when the hold ends
        const held = c.log.slice(0, k).reverse().find((x) => x.t === "hold" || x.t === "act");
        // (a hold shifts the next player's clock; the roller's own next turn, after an S&L 6, isn't shifted)
        if (held?.t === "hold" && held.until > m.now && held.c !== m.c) expect(Object.values(TIMERS).some((t) => Math.abs(m.deadline - held.until - t) <= 2)).toBe(true);
        else expect(Object.values(TIMERS)).toContain(m.deadline - m.now);
      }
      if (m.t === "emote") {
        // exactly a person's shape (key order included), a colour in the match, one of the 24 ids
        expect(Object.keys(m)).toEqual(["t", "c", "id"]);
        expect(packOfEmote(m.id)).not.toBe("");
        expect(c.seats.some((x) => x.color === m.c)).toBe(true);
      }
      if (m.t === "presence") expect(p.ghostIds.has(m.id)).toBe(false);
      if (m.t === "over") {
        expect(Object.keys(m).sort()).toEqual(["finished", "match_id", "standings", "t", "table", "winner"]);
        expect(Object.keys(m.table).sort()).toEqual(["bonus", "entry", "payouts", "refunds", "tier"]);
        // the house bonus is shown for 1st place whoever holds it (a ghost's too: ghosts look like people)
        expect(Object.keys(m.table.bonus)).toEqual(m.table.entry > 0 ? [String(m.finished[0])] : []);
        const ks = m.standings.map((s: Msg) => Object.keys(s).sort().join(","));
        expect(new Set(ks).size).toBe(1);
      }
    }
  }
}

describe("no ghost leaks", () => {
  it("Ludo, 4 seats, 1 human + 3 ghosts", async () => {
    const p = await play("ludo", 4, 1, ["Rahim"]);
    expect(p.ghostColors.size).toBe(3);
    audit(p, "ludo", ["Rahim"]);
  }, 30_000);

  it("Ludo, 2 seats, 1 human + 1 ghost (the human's name is in the ghost pool)", async () => {
    const p = await play("ludo", 2, 1, ["Nusrat"]);
    expect(p.ghostColors.size).toBe(1);
    audit(p, "ludo", ["Nusrat"]);
  }, 30_000);

  it("Snakes & Ladders, 4 seats, 2 humans + 2 ghosts", async () => {
    const p = await play("sl", 4, 2, ["Karim", "Mim"]);
    expect(p.ghostColors.size).toBe(2);
    audit(p, "sl", ["Karim", "Mim"]);
  }, 30_000);

  it("ghost emotes (chance 1): human shape, starter + one pack per ghost, 8 s gap, no ghost word", async () => {
    const p = await play("ludo", 4, 1, ["Rahim"]);
    const em = p.cs[0].log.filter((m) => m.t === "emote" && p.ghostColors.has(m.c));
    expect(em.length).toBeGreaterThan(0);
    for (const col of p.ghostColors) {
      const mine = em.filter((m) => m.c === col);
      const packs = new Set(mine.map((m) => packOfEmote(m.id)).filter((x) => x !== "starter"));
      expect(packs.size).toBeLessThanOrEqual(1);
      for (const id of mine.map((m) => m.id)) expect(Object.values(EMOTE_PACKS).flat()).toContain(id);
    }
    // like a person's: never the same emote twice in a row, the humans' pace (1 per 2 s), no more than 6 per 30 s
    for (const col of p.ghostColors) {
      const mine = em.filter((m) => m.c === col);
      for (let k = 1; k < mine.length; k++) expect(mine[k].id).not.toBe(mine[k - 1].id);
      const at = p.cs[0].log.map((m, k) => ({ m, t: p.cs[0].at[k] })).filter((x) => x.m.t === "emote" && x.m.c === col).map((x) => x.t);
      for (let k = 1; k < at.length; k++) expect(at[k] - at[k - 1]).toBeGreaterThanOrEqual(2000 * SCALE - 40);
      for (let k = 6; k < at.length; k++) expect(at[k] - at[k - 6]).toBeGreaterThanOrEqual(30_000 * SCALE - 40);
    }
    audit(p, "ludo", ["Rahim"]);
  }, 30_000);

  it("the 3 ghosts of a 4-seat match have different (hidden) personalities", async () => {
    const p = await play("ludo", 4, 1, ["Rahim"]);
    const ps = (p.snap.members as Array<{ ghost?: boolean; persona?: string }>).filter((m) => m.ghost).map((m) => m.persona);
    expect(ps.length).toBe(3);
    expect(new Set(ps).size).toBe(3);
    // never on the wire: no message key or string carries the persona
    expect(walk(p.cs[0].log).keys.filter((k) => /persona|personality/i.test(k))).toEqual([]);
    expect(JSON.stringify(p.cs[0].log)).not.toMatch(/persona|chatty|cheeky|sore/i);
  }, 30_000);

  it("a reconnect (sync) mid-match shows the ghosts like everyone else", async () => {
    await mmHooks("ludo", 2, { wait: 100, room: { timeScale: SCALE } });
    const g = await guest();
    const { matched } = await queueAll("ludo", 2, [g], ["Shuvo"]);
    const c = await joinMatched(matched[0].code, matched[0].token, g, "Shuvo");
    await c.wait("start");
    c.close();
    const back = await joinMatched(matched[0].code, matched[0].token, g, "Shuvo");
    const s = await back.wait("sync");
    const ghost = s.seats.find((x: Msg) => x.id !== back.id);
    expect(ghost).toMatchObject({ bot: false, online: true });
    expect(walk(back.log).keys.filter((k) => /ghost/i.test(k))).toEqual([]);
    back.send({ t: "leave" });
  });
});

describe("ghost timing", () => {
  it("ghosts act within the human-like windows and never time out", { retry: 2, timeout: 30_000 }, async () => {
    const scale = 0.1;
    await mmHooks("ludo", 4, { wait: 100, room: { timeScale: scale, tok: NEAR_GOAL } });
    const g = await guest();
    const { matched } = await queueAll("ludo", 4, [g]);
    const code = matched[0].code;
    const snap = (await stubFor(code).adminSnapshot()) as unknown as AdminSnapshot;
    const ghostColors = new Set(snap.members.filter((m) => m.ghost).map((m) => m.color));
    const c = await joinMatched(code, matched[0].token, g);
    await c.wait("start");
    c.autoplay = true;
    c.playTurn(c.state.turn);
    await finishAll([c], 28_000);
    // pair each ghost action with the turn announcement before it
    const samples: Array<{ phase: string; ms: number }> = [];
    let lastTurn = -1;
    let phase = "roll";
    const replay = JSON.parse(JSON.stringify(c.log.find((m) => m.t === "start")!.state));
    const { applyAction } = await import("../src/rules/ludo");
    for (let k = 0; k < c.log.length; k++) {
      const m = c.log[k];
      if (m.t === "turn") {
        lastTurn = k;
        phase = replay.phase;
      } else if (m.t === "act") {
        if (ghostColors.has(m.a.c) && m.a.k !== "mode" && lastTurn >= 0) samples.push({ phase, ms: c.at[k] - c.at[lastTurn] });
        applyAction(replay, m.a);
      }
    }
    expect(samples.length).toBeGreaterThanOrEqual(8);
    for (const s of samples) {
      const [lo, hi] = s.phase === "choose" ? [GHOST_TIMING.choose[0], GHOST_TIMING.think[1]] : s.phase === "pair_ask" ? GHOST_TIMING.pair : GHOST_TIMING.roll;
      expect(s.ms, JSON.stringify(s)).toBeGreaterThanOrEqual(lo * scale - 160); // receipt times: delivery jitter under load
      expect(s.ms, JSON.stringify(s)).toBeLessThanOrEqual(hi * scale + 250);
    }
    // never a timeout: no ghost action waited for the turn timer
    expect(samples.every((s) => s.ms < (s.phase === "choose" ? 20_000 : 15_000) * scale)).toBe(true);
    // a ghost's roll and its move share one wake-up (Room.chain(); test/room_ghost_alarm.test.ts measures it)
    const stats = await stubFor(code).testStats();
    expect(stats.chained).toBeGreaterThan(0);
    expect(stats.alarms).toBeLessThan(samples.length);
  });
});
