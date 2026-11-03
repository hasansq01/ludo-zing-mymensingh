// Paused rooms (ADMIN_API.md): a match in progress (status playing) with nobody connected (online = 0). The Room
// pauses its bots then; the console shows such rooms as "Paused" and does not count them as playing.
import { beforeAll, describe, expect, it } from "vitest";
import { DB, api, eventually, login, row, type Json } from "./admin_helpers";
import { Client, lobbyOf, startAll } from "./room_client";

let cookie = "";
beforeAll(async () => {
  cookie = await login();
});

const get = (path: string, status = 200) => api(cookie, path, {}, status);
const roomRow = (code: string) => row("SELECT * FROM rooms WHERE code = ?", code);
const codesOf = async (path: string) => ((await get(path)).items as Json[]).map((r) => r.code as string);

/** A rooms row written straight to D1 (no Room DO exists for it); the host name is "Seed <code>". */
async function seedRoom(code: string, status: string, members: number, online: number): Promise<void> {
  const now = Date.now();
  await DB.prepare(
    `INSERT INTO rooms (code, created_at, updated_at, host_pid, host_name, status, members, online, settings, closed_reason)
     VALUES (?, ?, ?, NULL, ?, ?, ?, ?, '{"teams":false,"pair_ask":false}', NULL)`,
  )
    .bind(code, now, now, `Seed ${code}`, status, members, online)
    .run();
}

describe("paused rooms in D1 reads", () => {
  it("overview: rooms_playing counts only rooms with someone online, rooms_paused the rest", async () => {
    const before = (await get("overview")).live;
    expect(before).toHaveProperty("rooms_paused");
    await seedRoom("PAWS22", "playing", 2, 0);
    await seedRoom("PAWS23", "playing", 3, 0);
    await seedRoom("PLAY22", "playing", 2, 1);
    await seedRoom("LOBY22", "lobby", 2, 0); // members offline within the grace: still a lobby
    const o = (await get("overview")).live;
    expect(o.rooms_playing - before.rooms_playing).toBe(1);
    expect(o.rooms_paused - before.rooms_paused).toBe(2);
    expect(o.rooms_lobby - before.rooms_lobby).toBe(1);
    expect(o.members_online - before.members_online).toBe(1);
  });

  it("list: status=paused / status=playing split on online, rows carry paused", async () => {
    await seedRoom("PAWS32", "playing", 2, 0);
    await seedRoom("PLAY32", "playing", 4, 3);
    await seedRoom("LOBY32", "lobby", 1, 0);
    await seedRoom("OVER32", "over", 2, 0);
    const paused = await codesOf("rooms?status=paused&q=");
    expect(paused).toContain("PAWS32");
    for (const c of ["PLAY32", "LOBY32", "OVER32"]) expect(paused).not.toContain(c);
    const playing = await codesOf("rooms?status=playing");
    expect(playing).toContain("PLAY32");
    expect(playing).not.toContain("PAWS32");
    expect(await codesOf("rooms?status=lobby")).toContain("LOBY32");
    expect(await codesOf("rooms?status=over")).toContain("OVER32");
    // q combines with the paused filter
    expect(await codesOf("rooms?status=paused&q=paws32")).toEqual(["PAWS32"]);

    const all = (await get("rooms?q=32")).items as Json[];
    const flag = Object.fromEntries(all.map((r) => [r.code, r.paused]));
    expect(flag).toMatchObject({ PAWS32: true, PLAY32: false, LOBY32: false, OVER32: false });
    expect(all.find((r) => r.code === "PAWS32")).toMatchObject({ status: "playing", online: 0 });

    // pagination works under the paused filter
    await seedRoom("PAWS33", "playing", 2, 0);
    await seedRoom("PAWS34", "playing", 2, 0);
    const p1 = await get("rooms?status=paused&limit=1");
    expect(p1.items.length).toBe(1);
    expect(p1.next).toBeTruthy();
    const p2 = await get(`rooms?status=paused&limit=1&cursor=${encodeURIComponent(p1.next)}`);
    expect(p2.items[0].code).not.toBe(p1.items[0].code);
    expect(p2.items[0].paused).toBe(true);
  });

  it("detail of a row whose room is gone: room.paused from the row, live null", async () => {
    await seedRoom("PAWS42", "playing", 2, 0);
    const d = await get("rooms/PAWS42");
    expect(d.live).toBeNull();
    expect(d.room).toMatchObject({ code: "PAWS42", status: "playing", paused: true });
  });
});

describe("paused rooms: the live room keeps rooms.online accurate", () => {
  it("online reaches 0 at once when the last socket closes mid-match (no debounce), and > 0 again on reconnect", async () => {
    const { code, cs } = await lobbyOf(2);
    const [red, yel] = cs;
    await startAll(cs);
    await red.wait("turn");
    await eventually(async () => (await roomRow(code))?.status === "playing", 5000, "playing row");
    const d0 = await get(`rooms/${code}`);
    expect(d0.live.paused).toBe(false);
    expect(await codesOf("rooms?status=playing")).toContain(code);

    // the first close falls inside the 5 s debounce of the start write; the last one must not wait for it
    red.close();
    yel.close();
    const t0 = Date.now();
    const r = await eventually(async () => {
      const x = await roomRow(code);
      return x && x.online === 0 ? x : null;
    }, 3000, "online 0 without the debounce");
    expect(Date.now() - t0).toBeLessThan(3000);
    expect(r).toMatchObject({ status: "playing", members: 2, online: 0 });

    const d1 = await get(`rooms/${code}`);
    expect(d1.room.paused).toBe(true);
    expect(d1.live).toMatchObject({ status: "playing", paused: true });
    expect(d1.live.members.every((m: Json) => !m.online)).toBe(true);
    expect(await codesOf("rooms?status=paused")).toContain(code);
    expect(await codesOf("rooms?status=playing")).not.toContain(code);
    const o = await get("overview");
    expect(o.live.rooms_paused).toBeGreaterThanOrEqual(1);

    // a reconnect within the grace: the row shows someone online again at once
    const back = await Client.join(code, { token: yel.token, name: "P2" });
    await back.wait("sync");
    const r2 = await eventually(async () => {
      const x = await roomRow(code);
      return x && x.online === 1 ? x : null;
    }, 3000, "online 1 without the debounce");
    expect(r2.status).toBe("playing");
    const d2 = await get(`rooms/${code}`);
    expect(d2.room.paused).toBe(false);
    expect(d2.live.paused).toBe(false);
    expect(await codesOf("rooms?status=playing")).toContain(code);
    expect(await codesOf("rooms?status=paused")).not.toContain(code);
    back.close();
  });

  it("a lobby everyone left (still within the grace) stays a lobby, not paused", async () => {
    const { code, cs } = await lobbyOf(2);
    for (const c of cs) c.close();
    await eventually(async () => (await roomRow(code))?.online === 0, 3000, "online 0");
    const d = await get(`rooms/${code}`);
    expect(d.room).toMatchObject({ status: "lobby", paused: false });
    expect(d.live).toMatchObject({ status: "lobby", paused: false });
    expect(await codesOf("rooms?status=paused")).not.toContain(code);
    expect(await codesOf("rooms?status=lobby")).toContain(code);
  });
});
