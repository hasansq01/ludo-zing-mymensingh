// Daily missions: three small goals a day, counted from the profile's own stats (which only the server moves: match
// claims and online matches), so they can't be faked. Each pays its coins once; all three open a chest. The day's three
// come from the day's key: one easy, one middling, one harder, the same for everybody.
// State: p.missions = {day, base: {stat: value when the day began}, claimed: [ids and "chest"]}, started on the first
// read of the day.
import { addCoins, type Profile } from "./profile";

export const CHEST_ID = "chest";
export const CHEST = { coins: 300, gems: 3 };

type Stat = "games" | "played" | "slPlayed" | "wins" | "coinsEarned";
interface Mission {
  id: string;
  stat: Stat;
  goal: number;
  coins: number;
}

export const MISSION_POOL: readonly (readonly Mission[])[] = [
  [
    { id: "play1", stat: "games", goal: 1, coins: 100 },
    { id: "ludo1", stat: "played", goal: 1, coins: 120 },
    { id: "sl1", stat: "slPlayed", goal: 1, coins: 120 },
  ],
  [
    { id: "play3", stat: "games", goal: 3, coins: 200 },
    { id: "earn500", stat: "coinsEarned", goal: 500, coins: 150 },
  ],
  [
    { id: "win1", stat: "wins", goal: 1, coins: 200 },
    { id: "win2", stat: "wins", goal: 2, coins: 350 },
  ],
];

interface MissionState {
  day: string;
  base: Record<string, number>;
  claimed: string[];
}

function statOf(p: Profile, s: Stat): number {
  const st = (p.stats ?? {}) as unknown as Record<string, unknown>;
  const n = (k: string): number => {
    const v = st[k];
    return typeof v === "number" && Number.isFinite(v) ? Math.trunc(v) : 0;
  };
  switch (s) {
    case "games":
      return n("played") + n("slPlayed");
    case "wins":
      return n("wins") + n("slWins");
    default:
      return n(s);
  }
}

/** The day's three missions. */
export function missionsToday(today: string): Mission[] {
  let h = 0;
  for (const c of today) h = (h * 31 + c.charCodeAt(0)) >>> 0;
  return MISSION_POOL.map((tier, k) => tier[(h >>> (k * 3)) % tier.length]);
}

function isState(v: unknown, today: string): v is MissionState {
  if (typeof v !== "object" || v === null) return false;
  const m = v as Partial<MissionState>;
  return m.day === today && typeof m.base === "object" && m.base !== null && Array.isArray(m.claimed);
}

/** Today's state; `fresh` when it had to be started (the caller saves it). */
export function missionState(p: Profile, today: string): { state: MissionState; fresh: boolean } {
  const cur = (p as unknown as { missions?: unknown }).missions;
  if (isState(cur, today)) return { state: cur, fresh: false };
  const base: Record<string, number> = {};
  for (const m of missionsToday(today)) base[m.stat] = statOf(p, m.stat);
  return { state: { day: today, base, claimed: [] }, fresh: true };
}

export interface MissionView {
  id: string;
  goal: number;
  value: number;
  coins: number;
  done: boolean;
  claimed: boolean;
}

/** What GET /v1/missions answers. */
export function missionsView(p: Profile, today: string, state: MissionState): { missions: MissionView[]; chest: { coins: number; gems: number; ready: boolean; claimed: boolean } } {
  const missions = missionsToday(today).map((m) => {
    const value = Math.max(0, Math.min(m.goal, statOf(p, m.stat) - (state.base[m.stat] ?? 0)));
    return { id: m.id, goal: m.goal, value, coins: m.coins, done: value >= m.goal, claimed: state.claimed.includes(m.id) };
  });
  return { missions, chest: { ...CHEST, ready: missions.every((m) => m.claimed), claimed: state.claimed.includes(CHEST_ID) } };
}

export type MissionClaim =
  | { ok: true; profile: Profile; coins: number; gems: number }
  | { ok: false; error: "unknown" | "not_done" | "claimed" };

/** Claims a finished mission, or the chest once all three are claimed. */
export function claimMission(profile: Profile, today: string, id: string): MissionClaim {
  const { state } = missionState(profile, today);
  const view = missionsView(profile, today, state);
  if (state.claimed.includes(id)) return { ok: false, error: "claimed" };
  let coins = 0;
  let gems = 0;
  if (id === CHEST_ID) {
    if (!view.chest.ready) return { ok: false, error: "not_done" };
    coins = CHEST.coins;
    gems = CHEST.gems;
  } else {
    const m = view.missions.find((x) => x.id === id);
    if (!m) return { ok: false, error: "unknown" };
    if (!m.done) return { ok: false, error: "not_done" };
    coins = m.coins;
  }
  const p = structuredClone(profile);
  (p as unknown as { missions: MissionState }).missions = { ...state, claimed: [...state.claimed, id] };
  addCoins(p, coins);
  p.gems += gems;
  return { ok: true, profile: p, coins, gems };
}
