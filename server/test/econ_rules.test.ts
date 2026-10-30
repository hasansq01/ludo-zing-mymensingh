// Unit tests for the server economy's own rules (src/econ/): validation, cooldowns, claim limits, online rewards
// and the one-time import. The game's rules themselves are covered by econ_parity.test.ts.
import { describe, expect, it } from "vitest";
import { land, replayReaches100 } from "../src/rules/sl";
import {
  CLAIM_LIMITS,
  DAY_OFFSET_MIN,
  type ClaimInput,
  type ClaimRecord,
  IMPORT_CAPS,
  ONLINE_REWARDS,
  PRIZES,
  type Profile,
  applyOnlineResult,
  buy,
  claimDaily,
  claimFree,
  claimLimit,
  claimMatch,
  claimTotals,
  dailyState,
  dayKey,
  dayStart,
  equip,
  importProfile,
  isPlayerId,
  levelInfo,
  newProfile,
  normalizeProfile,
  nextDayAt,
  rollSpin,
  spin,
} from "../src/econ";

const T0 = Date.UTC(2026, 9, 24, 12, 0, 0) / 1000; // 2026-10-24 12:00 UTC
const DAY = 86400;

function fresh(over: Partial<Profile> = {}): Profile {
  // 5,000 coins: an arbitrary working balance (a new account starts with 2,500)
  return { ...newProfile("LZM-TEST-0001"), coins: 5000, ...over };
}

describe("profile defaults and level", () => {
  it("a new profile matches the game's fresh profile", () => {
    const p = newProfile();
    expect(isPlayerId(p.id)).toBe(true);
    expect(p).toMatchObject({
      name: "You", coins: 2500, gems: 0, rerolls: 0, xp: 0, rooms: ["night", "cafe"], room: "night", dice_owned: ["classic"], dice: "classic",
      scenes: ["jungle"], scene: "jungle", avatar: "pawn-red", frame: "classic", plate: "plain", badge: "", claimed: [],
      av_owned: [], daily: {}, last_spin: "", last_free: 0,
    });
    expect(Object.values(p.stats).every((v) => v === 0)).toBe(true);
  });

  it("levels need 100, 150, 200 … XP", () => {
    expect(levelInfo(0)).toEqual({ level: 1, into: 0, need: 100 });
    expect(levelInfo(100)).toEqual({ level: 2, into: 0, need: 150 });
    expect(levelInfo(249)).toEqual({ level: 2, into: 149, need: 150 });
    expect(levelInfo(250)).toEqual({ level: 3, into: 0, need: 200 });
  });
});

describe("shop", () => {
  it("buys, takes the price once, equips, and leaves the input alone", () => {
    const p = fresh();
    const r = buy(p, "room", "dream");
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.profile.coins).toBe(2000);
    expect(r.profile.room).toBe("dream");
    expect(r.profile.rooms).toEqual(["night", "cafe", "dream"]);
    expect(r.delta).toEqual({ coins: -3000, xp: 0, items: [{ kind: "room", id: "dream" }] });
    expect(p.coins).toBe(5000);
    expect(buy(r.profile, "room", "dream")).toEqual({ ok: false, error: "owned" });
  });

  it("refuses with unknown / owned / coins / locked", () => {
    const p = fresh();
    expect(buy(p, "room", "moon")).toEqual({ ok: false, error: "unknown" });
    expect(buy(p, "hat", "x")).toEqual({ ok: false, error: "unknown" });
    expect(buy(p, "room", "night")).toEqual({ ok: false, error: "owned" });
    expect(buy(p, "dice", "classic")).toEqual({ ok: false, error: "owned" });
    expect(buy(p, "scene", "jungle")).toEqual({ ok: false, error: "owned" });
    expect(buy(p, "char", "ch-arif")).toEqual({ ok: false, error: "owned" });
    expect(buy(p, "char", "ch-rafi")).toEqual({ ok: false, error: "coins", short: 5000 });
    expect(buy(p, "avatar", "crown")).toEqual({ ok: false, error: "locked" });
    expect(buy(fresh({ xp: 1000 }), "avatar", "crown")).toEqual({ ok: false, error: "owned" });
    expect(buy(p, "frame", "nope")).toEqual({ ok: false, error: "unknown" });
    expect(buy(p, "badge", "first")).toEqual({ ok: false, error: "locked" });
  });

  it("a character bought is equipped and owned", () => {
    const r = buy(fresh({ coins: 10000 }), "char", "ch-rafi");
    expect(r.ok && [r.profile.coins, r.profile.avatar, r.profile.av_owned]).toEqual([0, "ch-rafi", ["ch-rafi"]]);
  });

  it("equips only owned / unlocked items", () => {
    const p = fresh();
    expect(equip(p, "room", "cafe")).toMatchObject({ ok: true, changed: true });
    expect(equip(p, "room", "night")).toMatchObject({ ok: true, changed: false });
    expect(equip(p, "room", "dream")).toEqual({ ok: false, error: "locked" });
    expect(equip(p, "frame", "gold")).toEqual({ ok: false, error: "locked" });
    expect(equip(fresh({ xp: 1000 }), "frame", "gold")).toMatchObject({ ok: true, changed: true });
    expect(equip(p, "avatar", "nobody")).toEqual({ ok: false, error: "unknown" });
    expect(equip(p, "badge", "")).toMatchObject({ ok: true });
  });
});

describe("days", () => {
  it("are Bangladesh calendar days (UTC+6) by default; any offset on request", () => {
    expect(DAY_OFFSET_MIN).toBe(360);
    expect(dayKey(T0)).toBe("2026-10-24");
    expect(dayKey(Date.UTC(2026, 9, 24, 17, 59, 59) / 1000)).toBe("2026-10-24"); // 23:59:59 in Dhaka
    expect(dayKey(Date.UTC(2026, 9, 24, 18, 0, 0) / 1000)).toBe("2026-10-25"); // midnight in Dhaka
    expect(dayKey(Date.UTC(2026, 9, 24, 23, 59, 59) / 1000, 0)).toBe("2026-10-24"); // UTC
    expect(dayKey(Date.UTC(2026, 9, 25, 0, 0, 0) / 1000, 0)).toBe("2026-10-25");
    expect(nextDayAt("2026-10-24")).toBe(Date.UTC(2026, 9, 24, 18) / 1000);
    expect(nextDayAt("2026-10-24", 0)).toBe(Date.UTC(2026, 9, 25) / 1000);
    expect(dayStart("2026-10-24")).toBe(Date.UTC(2026, 9, 23, 18) / 1000);
  });
});

describe("daily reward", () => {
  it("runs Day 1 .. 7, once per day, and Day 7 gives its character", () => {
    let p = fresh();
    const got: number[] = [];
    for (let k = 0; k < 7; k++) {
      const today = dayKey(T0 + k * DAY);
      const r = claimDaily(p, today, T0 + k * DAY);
      expect(r.ok).toBe(true);
      if (!r.ok) return;
      got.push(r.day);
      p = r.profile;
      const again = claimDaily(p, today, T0 + k * DAY + 60);
      expect(again).toMatchObject({ ok: false, error: "claimed", next_at: nextDayAt(today) });
    }
    expect(got).toEqual([1, 2, 3, 4, 5, 6, 7]);
    expect(p.av_owned).toEqual(["ch-rafi"]);
    expect(p.dice_owned).toEqual(["classic", "crema"]);
    expect(p.coins).toBe(5000 + 100 + 150 + 200 + 0 + 300 + 400 + 800);
    expect(p.stats.coinsEarned).toBe(1950);
  });

  it("a missed day starts again at Day 1; the state read doesn't change the profile", () => {
    let p = fresh();
    for (let k = 0; k < 3; k++) {
      const r = claimDaily(p, dayKey(T0 + k * DAY), T0 + k * DAY);
      if (r.ok) p = r.profile;
    }
    const s = dailyState(p, dayKey(T0 + 4 * DAY));
    expect(s.state).toMatchObject({ claimable: true, day: 1, missed: true });
    expect(s.profile).not.toBe(p);
    const r = claimDaily(p, dayKey(T0 + 4 * DAY), T0 + 4 * DAY);
    expect(r.ok && r.day).toBe(1);
  });
});

describe("spin and free coins", () => {
  it("spins once per day with the segment given", () => {
    const p = fresh();
    const r = spin(p, "2026-10-24", 5);
    expect(r).toMatchObject({ ok: true, index: 5, prize: 1000, delta: { coins: 1000, xp: 0 } });
    if (!r.ok) return;
    expect(r.profile.coins).toBe(6000);
    expect(spin(r.profile, "2026-10-24", 0)).toEqual({ ok: false, error: "spun", next_at: nextDayAt("2026-10-24") });
    expect(spin(r.profile, "2026-10-25", 0).ok).toBe(true);
    expect(() => spin(p, "2026-10-24", 8)).toThrow(RangeError);
    expect(() => spin(p, "2026-10-24", 1.5)).toThrow(RangeError);
  });

  it("rollSpin draws every segment, nothing else", () => {
    const seen = new Set<number>();
    for (let k = 0; k < 2000; k++) {
      const v = rollSpin();
      expect(Number.isInteger(v) && v >= 0 && v < PRIZES.length).toBe(true);
      seen.add(v);
    }
    expect(seen.size).toBe(PRIZES.length);
  });

  it("free coins: 300 every 4 hours", () => {
    const r = claimFree(fresh(), T0);
    expect(r).toMatchObject({ ok: true, coins: 300, next_at: T0 + 14400 });
    if (!r.ok) return;
    expect(claimFree(r.profile, T0 + 100)).toEqual({ ok: false, error: "cooldown", next_at: T0 + 14400 });
    expect(claimFree(r.profile, T0 + 14400).ok).toBe(true);
  });
});

describe("offline match claims", () => {
  const ludoWin: ClaimInput = { game: "ludo", result: "win", players: ["human", "cpu", "off", "off"], duration_s: 300 };
  const none: ClaimRecord[] = [];

  it("pay what the game pays", () => {
    const r = claimMatch(fresh(), ludoWin, none, T0);
    expect(r).toMatchObject({ ok: true, limited: false, coins: 200, xp: 100 });
    if (!r.ok || r.limited) return;
    expect(r.profile.stats).toMatchObject({ played: 1, wins: 1, streak: 1, bestStreak: 1, coinsEarned: 200 });
    expect(claimMatch(fresh(), { ...ludoWin, result: "loss" }, none, T0)).toMatchObject({ coins: 20, xp: 40 });
    expect(claimMatch(fresh(), { game: "ludo", result: "win", players: 3, mode: "pp", duration_s: 90 }, none, T0)).toMatchObject({ coins: 0, xp: 30 });
    expect(claimMatch(fresh(), { game: "ludo", result: "win", players: 4, mode: "cpu", duration_s: 90 }, none, T0)).toMatchObject({ coins: 200, xp: 100 });
    expect(claimMatch(fresh(), { game: "sl", mode: "cpu", result: "win", duration_s: 40, rolls: winningRolls() }, none, T0)).toMatchObject({ coins: 100, xp: 0 });
    expect(claimMatch(fresh(), { game: "sl", mode: "cpu", result: "loss", duration_s: 40 }, none, T0)).toMatchObject({ coins: 10, xp: 0 });
    expect(claimMatch(fresh(), { game: "sl", mode: "local", result: "win", duration_s: 40 }, none, T0)).toMatchObject({ coins: 0, xp: 0 });
  });

  it("play on: the placing decides (1 = win, any later place = the play reward); result only without one", () => {
    expect(claimMatch(fresh(), { ...ludoWin, result: "loss", placing: 1 }, none, T0)).toMatchObject({ coins: 200, xp: 100 });
    for (const placing of [2, 3, 4]) {
      expect(claimMatch(fresh(), { ...ludoWin, result: "win", placing }, none, T0)).toMatchObject({ coins: 20, xp: 40 });
    }
    const second = claimMatch(fresh(), { ...ludoWin, placing: 2 }, none, T0);
    expect(second.ok && !second.limited && second.profile.stats).toMatchObject({ played: 1, wins: 0, losses: 1, streak: 0 });
    expect(claimMatch(fresh(), { ...ludoWin, placing: null }, none, T0)).toMatchObject({ coins: 200 }); // (null: as missing)
    const sl: ClaimInput = { game: "sl", mode: "cpu", result: "loss", duration_s: 40 };
    expect(claimMatch(fresh(), { ...sl, placing: 2 }, none, T0)).toMatchObject({ coins: 10, limited: false });
    expect(claimMatch(fresh(), { ...sl, placing: 1, rolls: winningRolls() }, none, T0)).toMatchObject({ coins: 100, limited: false });
    expect(claimMatch(fresh(), { ...sl, placing: 1, rolls: [1, 2] }, none, T0)).toMatchObject({ limited: true, reason: "replay", coins: 0 });
    for (const placing of [0, 5, 1.5, "1", true]) {
      expect(claimMatch(fresh(), { ...ludoWin, placing }, none, T0)).toEqual({ ok: false, error: "invalid", detail: "placing" });
    }
  });

  it("ignore the client's xp and cap pairs", () => {
    const r = claimMatch(fresh(), { ...ludoWin, xp: 99999, pairs: 50 }, none, T0);
    expect(r.ok && !r.limited && [r.xp, r.profile.xp, r.profile.stats.pairsFormed]).toEqual([100, 100, CLAIM_LIMITS.pairs_per_claim]);
  });

  it("reject malformed claims", () => {
    const bad: unknown[] = [
      { ...ludoWin, game: "chess" },
      { ...ludoWin, players: ["human", "cpu"] },
      { ...ludoWin, players: ["human", "off", "off", "off"] },
      { ...ludoWin, players: ["cpu", "cpu", "off", "off"] },
      { ...ludoWin, players: ["human", "robot", "off", "off"] },
      { ...ludoWin, players: 3 },
      { ...ludoWin, duration_s: -1 },
      { ...ludoWin, duration_s: "300" },
      { ...ludoWin, pairs: 1.5 },
      { game: "sl", mode: "online", result: "win", duration_s: 40 },
      { game: "sl", mode: "cpu", result: "win", duration_s: 40, players: 9 },
      null,
    ];
    for (const c of bad) expect(claimMatch(fresh(), c as ClaimInput, none, T0), JSON.stringify(c)).toMatchObject({ ok: false, error: "invalid" });
  });

  it("are limited when too short (60 s Ludo, 30 s S&L), granting nothing", () => {
    const p = fresh();
    const r = claimMatch(p, { ...ludoWin, duration_s: 59 }, none, T0);
    expect(r).toMatchObject({ ok: true, limited: true, reason: "too_short", coins: 0, xp: 0, delta: { coins: 0, xp: 0 }, would: { coins: 200, xp: 100 } });
    expect(r.ok && r.profile).toBe(p);
    expect(claimMatch(p, { ...ludoWin, duration_s: 60 }, none, T0)).toMatchObject({ limited: false });
    expect(claimMatch(p, { game: "sl", mode: "cpu", result: "win", duration_s: 29 }, none, T0)).toMatchObject({ limited: true, reason: "too_short" });
    expect(claimMatch(p, { game: "sl", mode: "cpu", result: "win", duration_s: 30, rolls: winningRolls() }, none, T0)).toMatchObject({ limited: false });
  });

  it("are limited after 20 granted claims in an hour", () => {
    const hour: ClaimRecord[] = Array.from({ length: CLAIM_LIMITS.per_hour }, (_, k) => ({ at: T0 - 3599 + k, coins: 20, granted: true }));
    expect(claimMatch(fresh(), ludoWin, hour, T0)).toMatchObject({ limited: true, reason: "hourly" });
    expect(claimMatch(fresh(), ludoWin, hour.slice(1), T0)).toMatchObject({ limited: false });
    const old = hour.map((h) => ({ ...h, at: h.at - 1 })); // the first one is now exactly an hour old
    expect(claimMatch(fresh(), ludoWin, old, T0)).toMatchObject({ limited: false });
    const refused = hour.map((h) => ({ ...h, granted: false }));
    expect(claimMatch(fresh(), ludoWin, refused, T0)).toMatchObject({ limited: false });
  });

  it("pay the remainder of the day's 6,000 coins, then nothing; the next day starts over", () => {
    // T0 is 18:00 in Dhaka: 29 claims since 06:53 the same Bangladesh day
    const today: ClaimRecord[] = Array.from({ length: 29 }, (_, k) => ({ at: T0 - 40000 + k * 1000, coins: 200, granted: true }));
    expect(claimMatch(fresh(), ludoWin, today, T0)).toMatchObject({ limited: false, granted: true, coins: 200 }); // 5,800 + 200 = 6,000
    const more = [...today, { at: T0 - 5000, coins: 20, granted: true }];
    const cut = claimMatch(fresh(), ludoWin, more, T0);
    expect(cut).toMatchObject({ ok: true, limited: true, granted: true, reason: "daily_coins", coins: 180, xp: 100, delta: { coins: 180, xp: 100 }, would: { coins: 200, xp: 100 } });
    if (!cut.ok) return;
    // its stats count; only the coins over the cap are left out (also of coinsEarned)
    expect(cut.profile).toMatchObject({ coins: 5180, xp: 100, stats: { wins: 1, played: 1, coinsEarned: 180 } });
    const full = [...more, { at: T0 - 4000, coins: 180, granted: true }];
    expect(claimMatch(fresh(), ludoWin, full, T0)).toMatchObject({ limited: true, reason: "daily_coins", coins: 0, xp: 100, granted: true });
    // a 0-coin claim (Pass & Play) still gives its XP
    expect(claimMatch(fresh(), { game: "ludo", result: "win", players: 2, mode: "pp", duration_s: 90 }, full, T0)).toMatchObject({ limited: false, xp: 30 });
    const tomorrow = nextDayAt(dayKey(T0)) + 10;
    expect(claimMatch(fresh(), ludoWin, full, tomorrow)).toMatchObject({ limited: false, coins: 200 });
  });

  it("cap claim XP at 3,000 a day; nothing at all once both caps are reached", () => {
    const xpDay: ClaimRecord[] = [{ at: T0 - 100, coins: 0, xp: 2950, granted: true }];
    expect(claimMatch(fresh(), ludoWin, xpDay, T0)).toMatchObject({ limited: true, granted: true, reason: "daily_xp", coins: 200, xp: 50 });
    const both: ClaimRecord[] = [{ at: T0 - 100, coins: 6000, xp: 3000, granted: true }];
    const r = claimMatch(fresh(), ludoWin, both, T0);
    expect(r).toMatchObject({ limited: true, granted: false, reason: "daily_coins", coins: 0, xp: 0, would: { coins: 200, xp: 100 } });
    expect(r.ok && r.profile.stats.played).toBe(0);
    // a claim worth nothing is granted (its stats count) even then
    expect(claimMatch(fresh(), { game: "sl", mode: "local", result: "win", duration_s: 40 }, both, T0)).toMatchObject({ limited: false, granted: true });
  });

  it("take the earlier claims as a list or as totals (the endpoint's query)", () => {
    const list: ClaimRecord[] = [
      { at: T0 - 10, coins: 5900, xp: 100, granted: true },
      { at: T0 - 20, coins: 0, granted: false },
      { at: T0 - 7200, coins: 0, xp: 2000, granted: true }, // more than an hour ago, same day
      { at: T0 - 86400, coins: 6000, xp: 3000, granted: true }, // yesterday
    ];
    const t = claimTotals(list, T0);
    expect(t).toEqual({ coins_today: 5900, xp_today: 2100, last_hour: 1 });
    expect(claimLimit(ludoWin, { coins: 200, xp: 100 }, t, T0)).toEqual({ reason: "daily_coins", granted: true, coins: 100, xp: 100 });
    expect(claimLimit(ludoWin, { coins: 200, xp: 100 }, list, T0)).toEqual(claimLimit(ludoWin, { coins: 200, xp: 100 }, t, T0));
    expect(claimLimit(ludoWin, { coins: 200, xp: 100 }, { coins_today: 0, xp_today: 0, last_hour: 20 }, T0)).toEqual({ reason: "hourly", granted: false, coins: 0, xp: 0 });
  });

  it("pay an S&L win vs Computer only when its rolls replay to square 100", () => {
    const sl: ClaimInput = { game: "sl", mode: "cpu", result: "win", duration_s: 120 };
    const bad = [undefined, "1,2,3", [6, 6, 6, 6], [7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7], Array(CLAIM_LIMITS.max_rolls + 1).fill(1)];
    for (const rolls of bad) {
      expect(claimMatch(fresh(), { ...sl, rolls }, none, T0), JSON.stringify(rolls)?.slice(0, 40)).toMatchObject({
        limited: true, granted: false, reason: "replay", coins: 0, would: { coins: 100, xp: 0 },
      });
    }
    const r = claimMatch(fresh(), { ...sl, rolls: winningRolls() }, none, T0);
    expect(r).toMatchObject({ limited: false, granted: true, coins: 100 });
    expect(r.ok && r.profile.stats).toMatchObject({ slPlayed: 1, slWins: 1 });
    // losses and Pass & Play need no rolls; too short comes first
    expect(claimMatch(fresh(), { ...sl, result: "loss" }, none, T0)).toMatchObject({ limited: false, coins: 10 });
    expect(claimMatch(fresh(), { ...sl, mode: "local" }, none, T0)).toMatchObject({ limited: false, coins: 0 });
    expect(claimMatch(fresh(), { ...sl, duration_s: 10 }, none, T0)).toMatchObject({ reason: "too_short" });
  });
});

/** Rolls that take one pawn from square 0 to exactly 100 (never three 6s in a row). */
function winningRolls(): number[] {
  for (;;) {
    const rolls: number[] = [];
    let pos = 0;
    let sixes = 0;
    while (pos !== 100 && rolls.length < 400) {
      let v = 1 + Math.floor(Math.random() * 6);
      if (v === 6 && sixes === 2) v = 5;
      if (pos + v > 100) v = 100 - pos;
      sixes = v === 6 ? sixes + 1 : 0;
      rolls.push(v);
      pos = land(pos, v).to;
    }
    if (pos === 100 && replayReaches100(rolls)) return rolls;
  }
}

describe("online match rewards", () => {
  it("Ludo: win 300 + 100 XP, finish 50 + 40 XP, left nothing (owner 2026-10-31: was 150 / 20)", () => {
    expect(ONLINE_REWARDS.ludo.win).toEqual({ coins: 300, xp: 100 });
    const w = applyOnlineResult(fresh(), "ludo", "win");
    expect([w.coins, w.xp, w.profile.coins, w.profile.xp, w.profile.stats.coinsEarned]).toEqual([300, 100, 5300, 100, 300]);
    expect(applyOnlineResult(fresh(), "ludo", "finish")).toMatchObject({ coins: 50, xp: 40, delta: { coins: 50, xp: 40 } });
    const l = applyOnlineResult(fresh(), "ludo", "left");
    expect([l.coins, l.xp, l.profile.coins]).toEqual([0, 0, 5000]);
  });

  it("Snakes & Ladders: win 200 + 60 XP, finish 25 + 25 XP, left nothing (was 100 / 10)", () => {
    expect(ONLINE_REWARDS.sl).toEqual({ win: { coins: 200, xp: 60 }, finish: { coins: 25, xp: 25 }, left: { coins: 0, xp: 0 } });
    expect(applyOnlineResult(fresh(), "sl", "win")).toMatchObject({ coins: 200, xp: 60, profile: { coins: 5200, xp: 60 } });
    expect(applyOnlineResult(fresh(), "sl", "finish")).toMatchObject({ coins: 25, xp: 25, delta: { coins: 25, xp: 25 } });
    expect(applyOnlineResult(fresh(), "sl", "left")).toMatchObject({ coins: 0, xp: 0 });
  });
});

describe("import of the local profile", () => {
  const today = "2026-10-24";

  it("caps coins and XP and reports it", () => {
    const base = newProfile("LZM-BASE-0001");
    const r = importProfile({ coins: 999999, xp: 5_000_000 }, base, today, T0);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect([r.profile.coins, r.profile.xp]).toEqual([IMPORT_CAPS.coins, IMPORT_CAPS.xp]);
    expect(r.delta).toEqual({ coins: IMPORT_CAPS.coins - 2500, xp: IMPORT_CAPS.xp });
    expect(r.notes).toEqual(["coins: 999999 -> 50000", "xp: 5000000 -> 200000"]);
    const neg = importProfile({ coins: -50, xp: "lots" }, base, today, T0);
    expect(neg.ok && [neg.profile.coins, neg.profile.xp]).toEqual([0, 0]);
    expect(importProfile([], base, today, T0)).toEqual({ ok: false, error: "invalid" });
    expect(importProfile(null, base, today, T0)).toEqual({ ok: false, error: "invalid" });
  });

  it("keeps only owned items that exist, and equipped items that are owned or unlocked", () => {
    const r = importProfile(
      {
        name: "  Shihab   Shaharia  ", id: "LZM-ABCD-EFGH", coins: 1234, xp: 0,
        rooms: ["dream", "moon", 5, "night"], room: "moon",
        dice_owned: ["gold", "gold"], dice: "gold",
        scenes: ["frost"], scene: "candy",
        av_owned: ["ch-rafi", "ch-arif", "ch-nobody"], avatar: "crown", frame: "royal", plate: "ruby", badge: "first",
        stats: { wins: 1, played: 3, losses: 2, streak: 1, bestStreak: 0 },
        claimed: ["first", "coins", "bogus"],
      },
      newProfile("LZM-BASE-0001"), today, T0,
    );
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    const p = r.profile;
    expect(p.name).toBe("Shihab Shaharia");
    expect(p.id).toBe("LZM-ABCD-EFGH");
    expect(p.rooms).toEqual(["night", "cafe", "dream"]);
    expect(p.room).toBe("night");
    expect(p.dice_owned).toEqual(["classic", "gold"]);
    expect(p.dice).toBe("gold");
    expect(p.scenes).toEqual(["jungle", "frost"]);
    expect(p.scene).toBe("jungle");
    expect(p.av_owned).toEqual(["ch-rafi"]);
    expect([p.avatar, p.frame, p.plate, p.badge]).toEqual(["pawn-red", "classic", "plain", "first"]);
    expect(p.claimed).toEqual(["first"]);
    expect(p.stats.bestStreak).toBe(1);
    expect(r.notes).toContain('rooms: dropped "moon"');
    expect(r.notes).toContain('av_owned: dropped "ch-arif"');
    expect(r.notes).toContain('claimed: dropped "coins"');
  });

  it("never lets a reward be claimed twice because of imported timers", () => {
    const base = newProfile("LZM-BASE-0001");
    const r = importProfile(
      { last_spin: "2026-12-01", last_free: T0 + 99999, daily: { cycle: 1, streak: 3, last: "2026-10-23", history: [{ x: 1 }] } },
      base, today, T0,
    );
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.profile.last_spin).toBe(today);
    expect(r.profile.last_free).toBe(T0);
    expect(r.profile.daily).toEqual({ cycle: 1, streak: 3, last: "2026-10-23", last_at: 0, auto_on: "", history: [] });
    expect(claimFree(r.profile, T0 + 100).ok).toBe(false);
    expect(spin(r.profile, today, 0).ok).toBe(false);
    const d = claimDaily(r.profile, today, T0);
    expect(d.ok && d.day).toBe(4);
    const past = importProfile({ last_spin: "2026-10-23", daily: { streak: 9, last: "2027-01-01" } }, base, today, T0);
    expect(past.ok && [past.profile.last_spin, past.profile.daily]).toEqual(["2026-10-23", { cycle: 0, streak: 0, last: "", last_at: 0, auto_on: "", history: [] }]);
  });
});


describe("emote packs", () => {
  it("a new profile owns and uses the Starter Set", () => {
    const p = newProfile();
    expect(p.emote_sets).toEqual(["starter"]);
    expect(p.emote_set).toBe("starter");
  });

  it("buy pays once, owns and equips; equip needs ownership", () => {
    const p = newProfile();
    p.coins = 10_000;
    const r = buy(p, "emotes", "friends");
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.profile).toMatchObject({ coins: 6000, emote_sets: ["starter", "friends"], emote_set: "friends" });
    expect(buy(r.profile, "emotes", "friends")).toMatchObject({ ok: false, error: "owned" });
    expect(buy(p, "emotes", "starter")).toMatchObject({ ok: false, error: "owned" });
    expect(buy(p, "emotes", "nope")).toMatchObject({ ok: false, error: "unknown" });
    expect(buy(newProfile(), "emotes", "pawns")).toMatchObject({ ok: true });
    const poor = newProfile();
    poor.coins = 100;
    expect(buy(poor, "emotes", "pawns")).toMatchObject({ ok: false, error: "coins", short: 2400 });
    expect(equip(p, "emotes", "game")).toMatchObject({ ok: false, error: "locked" });
    expect(equip(p, "emotes", "nope")).toMatchObject({ ok: false, error: "unknown" });
    const e = equip(r.profile, "emotes", "starter");
    expect(e.ok && e.profile.emote_set).toBe("starter");
  });

  it("normalize repairs damaged emote fields; import keeps only known owned packs", () => {
    expect(normalizeProfile({ emote_sets: "x", emote_set: 4 }, () => "id")).toMatchObject({ emote_sets: ["starter"], emote_set: "starter" });
    expect(normalizeProfile({ emote_sets: ["game"], emote_set: "pawns" }, () => "id")).toMatchObject({ emote_sets: ["starter", "game"], emote_set: "starter" });
    const r = importProfile({ emote_sets: ["game", "bogus", "game"], emote_set: "game" }, newProfile("LZM-BASE-0001"), "2026-10-24", T0);
    expect(r.ok && r.profile).toMatchObject({ emote_sets: ["starter", "game"], emote_set: "game" });
    const bad = importProfile({ emote_sets: [], emote_set: "pawns" }, newProfile("LZM-BASE-0001"), "2026-10-24", T0);
    expect(bad.ok && bad.profile.emote_set).toBe("starter");
  });
});
