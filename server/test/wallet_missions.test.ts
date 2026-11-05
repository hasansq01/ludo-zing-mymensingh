// Daily missions and the Lucky Draw's server rules.
import { describe, expect, it } from "vitest";
import { CHEST, CHEST_ID, ECON_V1, PRIZES, canSpin, claimMission, extraSpins, missionsToday, missionState, spin } from "../src/econ";
import { T0, guest, ok, v1 } from "./acc_helpers";

const prof = (o: Record<string, unknown> = {}): never => ({ coins: 0, gems: 0, stats: { played: 0, slPlayed: 0, wins: 0, slWins: 0, coinsEarned: 0 }, daily: {}, last_spin: "", ...o }) as never;

describe("missions: the rules", () => {
  it("three a day: one from each tier, the same all day", () => {
    const a = missionsToday("2026-11-06");
    expect(a).toHaveLength(3);
    expect(missionsToday("2026-11-06")).toEqual(a);
    const seen = new Set<string>();
    for (let d = 1; d <= 28; d++) seen.add(missionsToday(`2026-11-${String(d).padStart(2, "0")}`).map((m) => m.id).join());
    expect(seen.size).toBeGreaterThan(1);
  });

  it("only what happens after the day began counts; each pays once; the chest needs all three", () => {
    const day = "2026-11-06";
    const before = prof({ stats: { played: 40, slPlayed: 40, wins: 40, slWins: 40, coinsEarned: 90000 } });
    const { state } = missionState(before, day);
    const started = { ...(before as object), missions: state } as never;
    const first = missionsToday(day)[0];
    expect(claimMission(started, day, first.id)).toEqual({ ok: false, error: "not_done" });
    expect(claimMission(started, day, CHEST_ID)).toEqual({ ok: false, error: "not_done" });
    expect(claimMission(started, day, "nonsense")).toEqual({ ok: false, error: "unknown" });
    const after = structuredClone(started) as { stats: Record<string, number> };
    for (const k of ["played", "slPlayed", "wins", "slWins"]) after.stats[k] += 5;
    after.stats.coinsEarned += 5000;
    let p = after as never;
    for (const m of missionsToday(day)) {
      const c = claimMission(p, day, m.id);
      expect(c).toMatchObject({ ok: true, coins: m.coins, gems: 0 });
      if (c.ok) p = c.profile as never;
      expect(claimMission(p, day, m.id)).toEqual({ ok: false, error: "claimed" });
    }
    const chest = claimMission(p, day, CHEST_ID);
    expect(chest).toMatchObject({ ok: true, coins: CHEST.coins, gems: CHEST.gems });
    if (chest.ok) expect(claimMission(chest.profile, day, CHEST_ID)).toEqual({ ok: false, error: "claimed" });
  });

  it("a new day starts over", () => {
    const { state } = missionState(prof(), "2026-11-06");
    const p = prof({ missions: { ...state, claimed: ["play1"] } });
    expect(missionState(p, "2026-11-06").fresh).toBe(false);
    expect(missionState(p, "2026-11-07")).toMatchObject({ fresh: true, state: { claimed: [] } });
  });
});

describe("Lucky Draw: the rules", () => {
  it("one free a day, then only the draws won by video", () => {
    const day = "2026-11-06";
    const a = spin(prof(), day, 0);
    expect(a.ok).toBe(true);
    if (!a.ok) return;
    expect(canSpin(a.profile, day)).toBe(false);
    expect(spin(a.profile, day, 0)).toMatchObject({ ok: false, error: "spun" });
    const earned = { ...(a.profile as object), extra_spins: 2 } as never;
    expect(canSpin(earned, day)).toBe(true);
    const b = spin(earned, day, 1);
    expect(b.ok && extraSpins(b.profile)).toBe(1);
  });

  it("the free one of a new day leaves the earned ones alone", () => {
    const r = spin(prof({ last_spin: "2026-11-05", extra_spins: 2 }), "2026-11-06", 0);
    expect(r.ok && extraSpins(r.profile)).toBe(2);
  });
});

describe("missions and draws: the endpoints", () => {
  it("GET /v1/missions starts the day, claims refuse until done", async () => {
    const g = await guest();
    const m = await ok("missions", { method: "GET", session: g.session, now: T0 });
    expect(m.missions).toHaveLength(3);
    expect(m.chest).toMatchObject({ coins: CHEST.coins, gems: CHEST.gems, ready: false, claimed: false });
    expect(m.missions.every((x: { value: number }) => x.value === 0)).toBe(true);
    const r = await v1("missions/claim", { session: g.session, body: { id: m.missions[0].id }, now: T0 + 1 });
    expect(r.status).toBe(409);
    expect(r.body.error).toBe("not_done");
  });

  it("a spin answers the prize; the jackpot wedge is the highest prize and pays gems", async () => {
    const g = await guest();
    const s = await ok("rewards/spin", { session: g.session, body: {}, now: T0 });
    expect(PRIZES).toContain(s.prize);
    expect(s.gems).toBe(s.prize === Math.max(...PRIZES) ? ECON_V1.jackpot_gems : 0);
    expect(s.draws_left).toBe(0);
  });
});
