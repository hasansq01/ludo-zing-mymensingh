// The daily Cron Trigger (wrangler.jsonc "triggers"): D1 pruning, rooms-row reconciliation and, on Mondays, the
// weekly-result pushes (NOTIFICATIONS.md). Kept out of index.ts because a Worker's main module may only export
// handlers and Durable Object classes.
import * as D from "./db";
import { isoWeek } from "./econ";
import { KEEP_WEEKS } from "./leaderboard";
import { prunePush, weeklyPushes } from "./push";
import { sweepEntries, weeklyPrizes } from "./economy";
import { voidRefunded } from "./iap";
import type { AdminSnapshot, Env } from "./room";

/** A rooms row still "live" (lobby / playing / over) but not updated for this long is checked against its Room. */
export const STALE_ROOM_MS = 2 * 60 * 60_000;

export interface CronResult {
  pruned: Awaited<ReturnType<typeof D.prune>>;
  /** Rows whose Room is gone (a lost final write): closed "gone". */
  reconciled: number;
  /** Lobby / playing rooms that still exist but have nobody connected: closed by the Room ("stale-sweep"). */
  swept: number;
  /** Weekly-result pushes queued (Monday, Bangladesh time; null: another day, push off, or the queueing failed). */
  weekly: number | null;
  /** Economy v1: stuck coin-table entries refunded, refunded gem purchases voided, weekly gem prizes paid (Monday). */
  entries?: number;
  voided?: number;
  prizes?: number | null;
}

/**
 * The daily cron: prune old rows (weekly leaderboard rows after KEEP_WEEKS weeks); then every rooms row in lobby /
 * playing / over untouched for 2 h: a Room that is gone gets its row closed ("gone", its match "abandoned"); a lobby
 * or playing Room is asked to sweepStale(): it deletes itself when no person is connected (ghosts don't count), with
 * reason "stale-sweep" (the Room writes its own closed row). A Room with someone online is left alone. On Monday
 * (Bangladesh time) the weekly-result pushes are queued in the Pusher (push.ts weeklyPushes); push_events rows are
 * pruned after 30 days.
 */
export async function cron(env: Env, now = Date.now()): Promise<CronResult> {
  const oldestWeek = isoWeek(Math.floor(now / 1000) - KEEP_WEEKS * 7 * 86400);
  const pruned = await D.prune(env.DB, now, oldestWeek);
  let reconciled = 0;
  let swept = 0;
  for (const { code, status } of await D.staleRooms(env.DB, ["lobby", "playing", "over"], now - STALE_ROOM_MS)) {
    try {
      const room = env.ROOMS.get(env.ROOMS.idFromName(code));
      const snap = (await room.adminSnapshot()) as AdminSnapshot | null;
      if (!snap) {
        await D.closeRoomRow(env.DB, code, "gone", now, "abandoned");
        reconciled++;
        continue;
      }
      if (status === "over") continue; // a finished room: its own alarm deletes it
      // the Room re-runs its timers and deletes itself when no person is connected (a running match: "abandoned")
      const r = await room.sweepStale();
      if (r === "live") continue;
      if (r === "swept") swept++;
      await D.closeRoomRow(env.DB, code, "stale-sweep", now, "abandoned"); // in case the Room's own write was lost
    } catch (e) {
      console.error(`reconcile ${code} failed:`, e);
    }
  }
  const weekly = await weeklyPushes(env, now).catch((e) => {
    console.error("weekly pushes failed:", e);
    return null;
  });
  const pushEvents = await prunePush(env.DB, now).catch(() => 0);
  const entries = await sweepEntries(env as never, now).catch((e) => (console.error("entry sweep failed:", e), 0));
  const voided = await voidRefunded(env as never, now).catch((e) => (console.error("voided purchases failed:", e), 0));
  const prizes = await weeklyPrizes(env as never, now).catch((e) => (console.error("weekly prizes failed:", e), null));
  console.log(
    `cron: pruned ${JSON.stringify(pruned)} (incl. ${pruned.crash_reports} crash reports) + ${pushEvents} push_events, closed ${reconciled} vanished rooms, swept ${swept} stale rooms, queued ${weekly ?? "no"} weekly pushes, refunded ${entries} entries, voided ${voided} purchases, paid ${prizes ?? "no"} weekly prizes`,
  );
  return { pruned, reconciled, swept, weekly, entries, voided, prizes };
}
