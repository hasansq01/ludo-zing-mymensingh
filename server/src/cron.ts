// The daily Cron Trigger (wrangler.jsonc "triggers"): D1 pruning and rooms-row reconciliation. Kept out of
// index.ts because a Worker's main module may only export handlers and Durable Object classes.
import * as D from "./db";
import type { Env } from "./room";

/** The daily cron: prune old rows; rooms rows still "live" whose room is gone (a lost final write) are closed. */
export async function cron(env: Env, now = Date.now()): Promise<{ pruned: Awaited<ReturnType<typeof D.prune>>; reconciled: number }> {
  const pruned = await D.prune(env.DB, now);
  let reconciled = 0;
  for (const code of await D.staleLiveRooms(env.DB, now - 3 * 60 * 60_000)) {
    try {
      if (!(await env.ROOMS.get(env.ROOMS.idFromName(code)).info())) {
        await D.closeRoomRow(env.DB, code, "gone", now, "abandoned");
        reconciled++;
      }
    } catch (e) {
      console.error(`reconcile ${code} failed:`, e);
    }
  }
  console.log(`cron: pruned ${JSON.stringify(pruned)}, closed ${reconciled} vanished rooms`);
  return { pruned, reconciled };
}

