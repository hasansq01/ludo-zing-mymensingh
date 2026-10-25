// Achievements (Collection.ACH, ach_progress, claim_ach, claimable_count): a stat reaching a goal pays its coins
// once (profile.claimed); the coins count as coins earned.
import { CATALOG, achievement } from "./catalog";
import { clone, list } from "./gd";
import { type Delta, type Profile, addCoins, stat } from "./profile";

export interface AchProgress {
  /** The stat, capped at the goal. */
  value: number;
  goal: number;
  done: boolean;
  claimed: boolean;
  /** 0..1 */
  pct: number;
}

/** Collection.ach_progress (undefined for an unknown id). */
export function achProgress(id: string, p: Profile): AchProgress | undefined {
  const a = achievement(id);
  if (!a) return undefined;
  const v = Math.min(a.goal, stat(a.stat, p));
  return { value: v, goal: a.goal, done: v >= a.goal, claimed: list(p, "claimed").includes(id), pct: v / a.goal };
}

/** Collection.claimable_count: done but not claimed yet. */
export function claimableCount(p: Profile): number {
  let n = 0;
  for (const a of CATALOG.achievements) {
    const pr = achProgress(a.id, p)!;
    if (pr.done && !pr.claimed) n++;
  }
  return n;
}

export type AchClaim =
  | { ok: true; profile: Profile; delta: Delta; coins: number }
  | { ok: false; error: "unknown" | "not_done" | "claimed" };

/** Collection.claim_ach: pays a finished, unclaimed achievement once. */
export function claimAch(profile: Profile, id: string): AchClaim {
  const pr = achProgress(id, profile);
  if (!pr) return { ok: false, error: "unknown" };
  if (!pr.done) return { ok: false, error: "not_done" };
  if (pr.claimed) return { ok: false, error: "claimed" };
  const reward = achievement(id)!.reward;
  const p = clone(profile);
  const cl = list(p, "claimed");
  cl.push(id);
  p.claimed = cl;
  addCoins(p, reward);
  return { ok: true, profile: p, delta: { coins: reward, xp: 0 }, coins: reward };
}
