// Parity with the GDScript economy: replays every case recorded by godot/dev/econ_parity_dump.gd (Save, Catalog,
// SLScenes, Collection, Rewards, LudoRules, SnakesLaddersRules run on seeded inputs) with the TS port in
// src/econ/ and checks the results and the profiles after, exactly. Regenerate the fixture from the repo root with
//   godot --headless --path godot -s res://dev/econ_parity_dump.gd
// and the catalog with
//   godot --headless --path godot -s res://dev/export_catalog.gd -- ../server/src/econ/catalog.json
import { describe, expect, it } from "vitest";
import casesJson from "./fixtures/econ_cases.json?raw";
import {
  CATALOG,
  type Profile,
  achProgress,
  addDays,
  applyLudoResult,
  applySlResult,
  buy,
  claimAch,
  claimDaily,
  claimFree,
  claimableCount,
  dailyStateMut,
  dayNum,
  equip,
  equipped,
  freeLeftSec,
  isDayKey,
  isUnlocked,
  levelInfo,
  ludoCoins,
  normalizeProfile,
  spin,
} from "../src/econ";

type Any = any; // eslint-disable-line @typescript-eslint/no-explicit-any
const F: Any = JSON.parse(casesJson);
const NOW = 1_800_000_000;
const clone = <T>(v: T): T => structuredClone(v);

/** The game stamps daily claims with the wall clock: compare only that a stamp is there. */
function mask(p: Any): Any {
  const q = clone(p);
  const d = q?.daily;
  if (d && typeof d === "object" && !Array.isArray(d)) {
    if (typeof d.last_at === "number" && d.last_at > 0) d.last_at = "T";
    if (Array.isArray(d.history)) {
      for (const e of d.history) if (e && typeof e === "object" && typeof e.at === "number" && e.at > 0) e.at = "T";
    }
  }
  return q;
}

describe("econ parity: tables", () => {
  it("catalog.json is what export_catalog.gd builds now", () => {
    expect(CATALOG).toEqual(F.catalog);
  });

  it(`level_info (${F.level.length} xp values)`, () => {
    for (const [xp, level, into, need] of F.level) expect(levelInfo(xp), `xp ${xp}`).toEqual({ level, into, need });
  });

  it(`day keys (${F.days.length})`, () => {
    for (const c of F.days) {
      expect(isDayKey(c.key), c.key).toBe(c.valid);
      expect(dayNum(c.key), c.key).toBe(c.num);
      for (const [d, key] of c.plus) expect(addDays(c.key, d), `${c.key} + ${d}`).toBe(key);
    }
  });
});

describe("econ parity: profile", () => {
  it(`Save._ensure (${F.normalize.length} raw profiles)`, () => {
    for (const c of F.normalize) expect(normalizeProfile(c.in, () => ""), JSON.stringify(c.in)).toEqual(c.out);
  });

  it(`is_unlocked / equipped (${F.unlocked.length})`, () => {
    for (const c of F.unlocked) {
      const what = `${c.kind}:${c.id}`;
      expect(isUnlocked(c.kind, c.id, c.p), what).toBe(c.unlocked);
      expect(equipped(c.kind, c.p), what).toBe(c.equipped);
    }
  });
});

describe("econ parity: shop", () => {
  it(`buy (${F.buy.length})`, () => {
    let paid = 0;
    for (const c of F.buy) {
      const before = clone(c.p);
      const r = buy(c.p as Profile, c.kind, c.id);
      const what = `${c.kind}:${c.id} coins ${c.p.coins}: ${c.err}`;
      expect(c.p, "input untouched").toEqual(before);
      if (c.code === "") {
        expect(r.ok, what).toBe(true);
        if (r.ok) expect(r.profile, what).toEqual(c.out);
        paid++;
      } else {
        expect(r.ok ? "" : r.error, what).toBe(c.code);
        expect(c.p, what).toEqual(c.out);
      }
    }
    expect(paid).toBeGreaterThan(30);
  });

  it(`equip (${F.equip.length})`, () => {
    for (const c of F.equip) {
      const r = equip(c.p as Profile, c.kind, c.id);
      const what = `${c.kind}:${c.id}`;
      expect(r.ok, what).toBe(c.ok);
      expect(r.ok ? r.profile : c.p, what).toEqual(c.out);
    }
  });
});

describe("econ parity: achievements", () => {
  it(`ach_progress / claim_ach (${F.ach.length})`, () => {
    for (const c of F.ach) {
      const pr = achProgress(c.id, c.p);
      expect(pr ?? {}, c.id).toEqual(c.progress);
      expect(claimableCount(c.p)).toBe(c.claimable_count);
      const r = claimAch(c.p as Profile, c.id);
      expect(r.ok ? r.coins : 0, c.id).toBe(c.paid);
      expect(r.ok ? r.profile : c.p, c.id).toEqual(c.out);
    }
  });
});

describe("econ parity: rewards", () => {
  it(`daily calendar runs (${F.daily.length} runs, ${F.daily.reduce((a: number, r: Any) => a + r.steps.length, 0)} days)`, () => {
    for (const [n, run] of F.daily.entries()) {
      let p: Profile = clone(run.p);
      for (const [k, step] of run.steps.entries()) {
        const what = `run ${n} step ${k} ${step.today}`;
        const st = dailyStateMut(clone(p), step.today);
        expect(
          {
            key: st.key, claimable: st.claimable, cycle: st.cycle, claimed: st.claimed, today: st.today, day: st.day,
            streak: st.streak, missed: st.missed, tiles: st.rewards.map((t) => ({ day: t.day, grant: t.grant, status: t.status })),
          },
          what,
        ).toEqual(step.state);
        if (step.claim) {
          const r = claimDaily(p, step.today, NOW);
          if (r.ok) expect({ ok: true, coins: r.coins, dice: r.dice, day: r.day, cycle: r.cycle }, what).toEqual(step.res);
          else expect({ ok: false, coins: 0, dice: "", day: r.day, cycle: r.cycle }, what).toEqual(step.res);
          p = r.profile;
        } else {
          p = clone(p);
          dailyStateMut(p, step.today);
        }
        expect(mask(p), what).toEqual(mask(step.out));
      }
    }
  });

  it(`spin with the game's rolls (${F.spin.length})`, () => {
    for (const c of F.spin) {
      const r = spin(c.p as Profile, c.today, c.roll);
      expect(r.ok ? { ok: true, index: r.index, prize: r.prize } : { ok: false, index: -1, prize: 0 }).toEqual(c.res);
      expect(r.ok ? r.profile : c.p).toEqual(c.out);
    }
  });

  it(`free coins (${F.free.length})`, () => {
    for (const c of F.free) {
      expect(freeLeftSec(c.p, c.now)).toBe(c.left);
      const r = claimFree(c.p as Profile, c.now);
      expect(r.ok ? r.coins : 0).toBe(c.paid);
      expect(r.ok ? r.profile : c.p).toEqual(c.out);
    }
  });
});

describe("econ parity: offline matches", () => {
  it(`Ludo results (${F.ludo.length})`, () => {
    for (const c of F.ludo) {
      const what = `${c.players} teams ${c.teams} winner ${c.winner} won ${c.won}`;
      expect(ludoCoins(c.players, c.won), what).toBe(c.win_reward || c.play_reward);
      expect(applyLudoResult(c.p, c.players, c.won).profile, what).toEqual(c.out);
    }
  });

  it(`Snakes & Ladders results (${F.sl.length})`, () => {
    for (const c of F.sl) {
      const r = applySlResult(c.p, c.mode, c.won);
      expect(r.coins).toBe(c.reward);
      expect(r.profile).toEqual(c.out);
    }
  });
});
