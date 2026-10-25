// sweepStale(): the daily cron's clean-up of rooms nobody is connected to (ghosts don't count).
import { describe, expect, it } from "vitest";
import { eventually, row } from "./admin_helpers";
import { Client, lobbyOf, sleep, startAll, stubFor } from "./room_client";
import { guest, joinMatched, mmHooks, queueAll } from "./quick_client";

describe("sweepStale", () => {
  it("gone for an unknown room, live while someone is connected", async () => {
    expect(await stubFor("ZZZZZZ").sweepStale()).toBe("gone");
    const { code, cs } = await lobbyOf(2);
    expect(await stubFor(code).sweepStale()).toBe("live");
    for (const c of cs) c.close();
  });

  it("a friend match with nobody connected is deleted and recorded as abandoned", async () => {
    const { code, cs } = await lobbyOf(2);
    await startAll(cs);
    for (const c of cs) c.close();
    await sleep(100);
    expect(await stubFor(code).sweepStale()).toBe("swept");
    expect(await stubFor(code).info()).toBeNull();
    const m = await eventually(() => row("SELECT * FROM matches WHERE code = ?", code), 5000, "match row");
    expect(m.result).toBe("abandoned");
    const r = await eventually(() => row("SELECT * FROM rooms WHERE code = ? AND status = 'closed'", code), 5000, "room row");
    expect(r.closed_reason).toBe("stale-sweep");
  });

  it("a quick match whose people all disconnected is swept (its ghosts don't keep it alive)", async () => {
    await mmHooks("ludo", 4, { wait: 100 });
    const g = await guest();
    const { matched } = await queueAll("ludo", 4, [g]);
    const c: Client = await joinMatched(matched[0].code, matched[0].token, g);
    await c.wait("start");
    c.close();
    await sleep(100);
    expect(await stubFor(matched[0].code).sweepStale()).toBe("swept");
    const m = await eventually(() => row("SELECT * FROM matches WHERE code = ?", matched[0].code), 5000, "match row");
    expect(m).toMatchObject({ result: "abandoned", quick: 1, ghosts: 3 });
  });
});
