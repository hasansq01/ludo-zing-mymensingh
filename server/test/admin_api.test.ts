// Every admin endpoint: happy paths, filters, cursor pagination and validation (ADMIN_API.md "Admin API").
import { beforeAll, describe, expect, it } from "vitest";
import { DB, api, call, eventually, login, row, rows, type Json } from "./admin_helpers";
import { Client, finishAll, lobbyOf, NEAR_GOAL, newPid, roomInfo, startAll, type Msg } from "./room_client";

let cookie = "";
beforeAll(async () => {
  cookie = await login();
});

const get = (path: string, status = 200) => api(cookie, path, {}, status);
const post = (path: string, body: unknown, status = 200) => api(cookie, path, { method: "POST", body }, status);
const isMode = (c: number, mode: string) => (m: Msg) => m.t === "act" && m.a.k === "mode" && m.a.c === c && m.a.mode === mode;

async function seedPlayers(prefix: string, n: number, extra: Partial<Json> = {}): Promise<string[]> {
  const pids: string[] = [];
  const stmts = [];
  for (let k = 0; k < n; k++) {
    const pid = `${prefix}${String(k).padStart(4, "0")}xxxxxxxx`;
    pids.push(pid);
    stmts.push(
      DB.prepare("INSERT INTO players (pid, name, first_seen, last_seen, banned) VALUES (?, ?, ?, ?, ?)").bind(
        pid,
        extra.name ?? `Seed ${prefix} ${k}`,
        1000 + k,
        2000 + k,
        extra.banned ?? 0,
      ),
    );
  }
  await DB.batch(stmts);
  return pids;
}

/** Collects every page of a list endpoint with the given page size. */
async function allPages(path: string, limit: number): Promise<Json[]> {
  const out: Json[] = [];
  let cursor: string | null = null;
  for (let k = 0; k < 50; k++) {
    const sep = path.includes("?") ? "&" : "?";
    const p: Json = await get(`${path}${sep}limit=${limit}${cursor ? `&cursor=${encodeURIComponent(cursor)}` : ""}`);
    expect(p.items.length).toBeLessThanOrEqual(limit);
    out.push(...p.items);
    cursor = p.next;
    if (!cursor) return out;
  }
  throw new Error("too many pages");
}

describe("lists: pagination and validation", () => {
  it("limit / cursor walk every row exactly once, newest first", async () => {
    await seedPlayers("pagetest", 7);
    const all = await allPages("players?q=pagetest", 3);
    expect(all.length).toBe(7);
    expect(all.map((p) => p.last_seen)).toEqual([...all.map((p) => p.last_seen)].sort((a, b) => b - a));
    expect(new Set(all.map((p) => p.pid)).size).toBe(7);
    const first = await get("players?q=pagetest");
    expect(first.items.length).toBe(7);
    expect(first.next).toBeNull();
  });

  it("bad limit / cursor / filters are 400", async () => {
    for (const p of [
      "players?limit=0",
      "players?limit=201",
      "players?limit=abc",
      "players?cursor=notacursor",
      "players?banned=yes",
      "rooms?status=gone",
      "matches?result=won",
      "matches?code=lower1",
      "matches?pid=short",
      "events?level=fatal",
      `rooms?q=${"x".repeat(65)}`,
    ]) {
      const r = await get(p, 400);
      expect(r.error, p).toBe("bad_request");
    }
    expect((await get("players?limit=200")).items).toBeInstanceOf(Array);
  });
});

describe("overview", () => {
  it("live counts, today, 14 days oldest first, recent warn/error events, maintenance", async () => {
    const { cs } = await lobbyOf(2);
    await DB.prepare("INSERT INTO events (at, level, kind, msg) VALUES (?, 'error', 'overview_test', 'boom')").bind(Date.now()).run();
    const o = await eventually(async () => {
      const x = await get("overview");
      return x.live.members_online >= 2 ? x : null;
    }, 8000, "live members");
    expect(o.now).toBeGreaterThan(0);
    expect(o.live.rooms_lobby).toBeGreaterThanOrEqual(1);
    expect(o.today.rooms).toBeGreaterThanOrEqual(1);
    expect(o.today.players_active).toBeGreaterThanOrEqual(2);
    expect(o.today.new_players).toBeGreaterThanOrEqual(2);
    expect(o.days.length).toBe(14);
    const today = new Date().toISOString().slice(0, 10);
    expect(o.days[13].day).toBe(today);
    expect(o.days[0].day < o.days[13].day).toBe(true);
    expect(o.days[13]).toMatchObject({ rooms: o.today.rooms, matches: o.today.matches, players_active: o.today.players_active });
    expect(o.recent_events[0]).toMatchObject({ kind: "overview_test", level: "error" });
    expect(o.recent_events.length).toBeLessThanOrEqual(10);
    expect(o.maintenance).toBe(false);
    for (const c of cs) c.close();
  });
});

describe("rooms", () => {
  it("list (status, q), detail with the live snapshot and matches", async () => {
    const { code, cs } = await lobbyOf(2);
    await eventually(() => row("SELECT * FROM rooms WHERE code = ? AND members = 2", code), 8000, "row");
    const byCode = await get(`rooms?q=${code.toLowerCase()}`);
    expect(byCode.items.map((r: Json) => r.code)).toEqual([code]);
    expect(byCode.items[0].settings).toEqual({ teams: false, pair_ask: false });
    const byHost = await get("rooms?q=P1&status=lobby");
    expect(byHost.items.some((r: Json) => r.code === code)).toBe(true);
    expect((await get("rooms?status=closed")).items.some((r: Json) => r.code === code)).toBe(false);

    const t0 = Date.now();
    const d = await get(`rooms/${code}`);
    expect(d.now).toBeGreaterThanOrEqual(t0);
    expect(d.now).toBeLessThanOrEqual(Date.now());
    expect(d.room).toMatchObject({ code, status: "lobby", members: 2 });
    expect(d.live).toMatchObject({ code, status: "lobby", host: cs[0].id, settings: { teams: false, pair_ask: false }, match: null });
    expect(d.live.members).toEqual([
      { id: cs[0].id, pid: cs[0].pid, name: "P1", avatar: "a1", frame: "f1", online: true, color: 0 },
      { id: cs[1].id, pid: cs[1].pid, name: "P2", avatar: "a1", frame: "f1", online: true, color: 2 },
    ]);
    expect(d.matches).toEqual([]);

    await startAll(cs);
    await cs[0].wait("turn");
    const d2 = await get(`rooms/${code.toLowerCase()}`);
    expect(d2.live.status).toBe("playing");
    expect(d2.live.match).toMatchObject({ n: 0 });
    expect(d2.live.match.deadline).toBeGreaterThan(Date.now());
    expect(d2.live.match.seats.map((s: Json) => [s.color, s.pid])).toEqual([
      [0, cs[0].pid],
      [2, cs[1].pid],
    ]);
    expect(d2.live.match.state.phase).toBe("roll");
    await eventually(async () => (await get(`rooms/${code}`)).matches.length === 1, 5000, "match in detail");
    const d3 = await get(`rooms/${code}`);
    expect(d3.matches[0]).toMatchObject({ code, result: "playing" });
    expect(d3.matches[0].players.length).toBe(2);
  });

  it("unknown or malformed codes are 404", async () => {
    await get("rooms/ABCDEF", 404); // valid shape, never created
    await get("rooms/abc", 404);
    await post("rooms/ABCDEF/close", { reason: "test close" }, 404);
    await post("rooms/ABCDEF/kick", { member_id: 1 }, 404);
  });

  it("close: error not_found + 4004 to everyone, storage gone, row closed with the reason, match closed", async () => {
    const { code, cs } = await lobbyOf(2);
    await startAll(cs);
    await eventually(() => row("SELECT * FROM matches WHERE code = ?", code), 5000, "match row");
    const r = await post(`rooms/${code}/close`, { reason: "abuse report" });
    expect(r).toEqual({ ok: true, live: true });
    for (const c of cs) {
      expect(await c.waitFor((m) => m.t === "error" && m.code === "not_found")).toBeTruthy();
      expect(await c.waitClosed()).toBe(4004);
    }
    expect((await roomInfo(code)).status).toBe(404);
    expect(await row("SELECT status, closed_reason FROM rooms WHERE code = ?", code)).toEqual({ status: "closed", closed_reason: "abuse report" });
    expect((await row("SELECT result FROM matches WHERE code = ?", code))!.result).toBe("closed");
    const d = await get(`rooms/${code}`);
    expect(d.live).toBeNull();
    expect(d.room.status).toBe("closed");
    // closing it again: the row exists, nothing live
    expect(await post(`rooms/${code}/close`, { reason: "again" })).toEqual({ ok: true, live: false });
    for (const bad of [{}, { reason: 5 }, { reason: "ab" }, { reason: "  ab  " }, { reason: "x".repeat(141) }]) {
      await post(`rooms/${code}/close`, bad, 400);
    }
    await post(`rooms/${code}/close`, { reason: "x".repeat(140) });
    const audit = await rows("SELECT * FROM admin_log WHERE action = 'room.close' AND target = ?", code);
    expect(JSON.parse(audit[0].detail)).toEqual({ reason: "abuse report", live: true });
  });

  it("kick in the lobby: error kicked + 4002, removed from the lobby", async () => {
    const { code, cs } = await lobbyOf(3);
    const [a, b] = cs;
    a.skip();
    expect(await post(`rooms/${code}/kick`, { member_id: b.id })).toEqual({ ok: true });
    expect(await b.waitFor((m) => m.t === "error")).toMatchObject({ code: "kicked" });
    expect(await b.waitClosed()).toBe(4002);
    const l = await a.waitFor((m) => m.t === "lobby" && m.members.length === 2);
    expect(l.members.map((m: Json) => m.id)).not.toContain(b.id);
    await post(`rooms/${code}/kick`, { member_id: b.id }, 404);
    for (const bad of [{}, { member_id: "1" }, { member_id: 0 }, { member_id: 1.5 }]) await post(`rooms/${code}/kick`, bad, 400);
  });

  it("kick in a match: the seat becomes a bot for good", async () => {
    const { code, cs } = await lobbyOf(2, { timeScale: 0.01, tok: NEAR_GOAL });
    const [red, yel] = cs;
    yel.autoplay = true;
    await startAll(cs);
    await post(`rooms/${code}/kick`, { member_id: red.id });
    expect(await red.waitClosed()).toBe(4002);
    await yel.waitFor(isMode(0, "cpu"));
    const again = await Client.open(code, red.pid);
    again.hello(red.token);
    expect(await again.wait("error")).toMatchObject({ code: "started" });
    await finishAll([yel]);
  });
});

describe("players", () => {
  it("list with q (name or pid prefix) and banned; detail with recent matches", async () => {
    const { cs } = await lobbyOf(2, { tok: NEAR_GOAL });
    for (const c of cs) c.autoplay = true;
    await startAll(cs);
    await finishAll(cs);
    const pid = cs[0].pid;
    await eventually(() => row("SELECT * FROM players WHERE pid = ? AND matches = 1", pid), 5000, "stats");

    expect((await get(`players?q=${pid.slice(0, 14)}`)).items.map((p: Json) => p.pid)).toContain(pid);
    await seedPlayers("bannedlist", 2, { banned: 1, name: "Zed Banned" });
    const banned = await get("players?banned=1");
    expect(banned.items.length).toBeGreaterThanOrEqual(2);
    expect(banned.items.every((p: Json) => p.banned === 1)).toBe(true);
    expect((await get("players?q=zed%20ban")).items.length).toBe(2); // name match is case-insensitive
    expect((await get("players?banned=0")).items.every((p: Json) => p.banned === 0)).toBe(true);
    expect((await get("players?q=100%25")).items).toEqual([]); // % is literal

    const d = await get(`players/${pid}`);
    expect(d.player).toMatchObject({ pid, name: "P1", matches: 1 });
    expect(d.matches.length).toBe(1);
    expect(d.matches[0].players.map((p: Json) => p.pid)).toContain(pid);
    expect(d.matches[0].result).toBe("over");
    await get(`players/${newPid()}`, 404);
    await get("players/bad", 404);
  });

  it("PATCH note", async () => {
    const [pid] = await seedPlayers("notetest", 1);
    const r = await api(cookie, `players/${pid}`, { method: "PATCH", body: { note: "  friend of the owner " } });
    expect(r.player.note).toBe("friend of the owner");
    const r2 = await api(cookie, `players/${pid}`, { method: "PATCH", body: { note: null } });
    expect(r2.player.note).toBeNull();
    await api(cookie, `players/${pid}`, { method: "PATCH", body: {} }, 400);
    await api(cookie, `players/${pid}`, { method: "PATCH", body: { note: 3 } }, 400);
    await api(cookie, `players/${pid}`, { method: "PATCH", body: { note: "x".repeat(501) } }, 400);
    await api(cookie, `players/${pid}`, { method: "PATCH", body: { note: "x".repeat(500) } });
    await api(cookie, `players/${newPid()}`, { method: "PATCH", body: { note: "x" } }, 404);
    expect((await rows("SELECT * FROM admin_log WHERE action = 'player.note' AND target = ?", pid)).length).toBe(3);
  });

  it("ban kicks the player from their live room (error banned + 4003), hello is refused; unban lets them back", async () => {
    const { code, cs } = await lobbyOf(2);
    const [a, b] = cs;
    await eventually(() => row("SELECT * FROM players WHERE pid = ? AND last_room = ?", b.pid, code), 5000, "player row");
    const r = await post(`players/${b.pid}/ban`, { reason: "spam" });
    expect(r).toMatchObject({ ok: true, kicked: true, player: { banned: 1, ban_reason: "spam" } });
    expect(await b.waitFor((m) => m.t === "error")).toMatchObject({ code: "banned" });
    expect(await b.waitClosed()).toBe(4003);
    await a.waitFor((m) => m.t === "lobby" && m.members.length === 1);

    const again = await Client.open(code, b.pid);
    again.hello();
    expect(await again.wait("error")).toMatchObject({ code: "banned" });
    expect(await again.waitClosed()).toBe(4003);

    const u = await post(`players/${b.pid}/unban`, {});
    expect(u).toMatchObject({ ok: true, player: { banned: 0, ban_reason: null } });
    const back = await Client.join(code, { pid: b.pid, name: "P2" });
    await back.waitFor((m) => m.t === "lobby" && m.members.length === 2);
    const log = await rows("SELECT action FROM admin_log WHERE target = ? ORDER BY id", b.pid);
    expect(log.map((x) => x.action)).toEqual(["player.ban", "player.unban"]);

    await post(`players/${newPid()}/ban`, { reason: "spam" }, 404);
    for (const bad of [{}, { reason: ["x"] }, { reason: "ab" }, { reason: "x".repeat(201) }]) await post(`players/${b.pid}/ban`, bad, 400);
    expect((await row("SELECT banned FROM players WHERE pid = ?", b.pid))!.banned).toBe(0);
  });
});

describe("matches, events, audit", () => {
  it("matches filters: code, pid, result", async () => {
    const { code, cs } = await lobbyOf(2, { tok: NEAR_GOAL });
    for (const c of cs) c.autoplay = true;
    await startAll(cs);
    await finishAll(cs);
    await eventually(() => row("SELECT * FROM matches WHERE code = ? AND result = 'over'", code), 5000, "over row");
    const byCode = await get(`matches?code=${code}`);
    expect(byCode.items.length).toBe(1);
    expect(byCode.items[0]).toMatchObject({ code, result: "over" });
    expect(Array.isArray(byCode.items[0].finished)).toBe(true);
    expect((await get(`matches?pid=${cs[1].pid}`)).items.map((m: Json) => m.code)).toEqual([code]);
    expect((await get(`matches?code=${code}&result=abandoned`)).items).toEqual([]);
    expect((await get("matches?result=over")).items.every((m: Json) => m.result === "over")).toBe(true);
    const all = await get("matches");
    const ids = all.items.map((m: Json) => m.id);
    expect(ids).toEqual([...ids].sort((x: number, y: number) => y - x));
  });

  it("events filters: level, kind", async () => {
    const now = Date.now();
    await DB.batch(
      ["info", "warn", "error"].map((lvl) =>
        DB.prepare("INSERT INTO events (at, level, kind, code, msg) VALUES (?, ?, 'evtest', 'ABCDEF', 'm')").bind(now, lvl),
      ),
    );
    const all = await get("events?kind=evtest");
    expect(all.items.map((e: Json) => e.level)).toEqual(["error", "warn", "info"]);
    expect((await get("events?kind=evtest&level=warn")).items.length).toBe(1);
    expect((await get("events?level=error")).items.every((e: Json) => e.level === "error")).toBe(true);
  });

  it("API responses carry no-store, the CSP, nosniff and no-referrer", async () => {
    const r = await call("overview", { cookie });
    expect(r.headers.get("Cache-Control")).toBe("no-store");
    expect(r.headers.get("Content-Security-Policy")).toContain("frame-ancestors 'none'");
    expect(r.headers.get("X-Content-Type-Options")).toBe("nosniff");
    expect(r.headers.get("Referrer-Policy")).toBe("no-referrer");
    await r.arrayBuffer();
  });

  it("audit lists admin writes newest first", async () => {
    const p = await get("audit?limit=5");
    expect(p.items.length).toBeGreaterThan(0);
    expect(p.items[0]).toHaveProperty("action");
    expect(p.items[0]).toHaveProperty("ip");
    const ids = p.items.map((x: Json) => x.id);
    expect(ids).toEqual([...ids].sort((x: number, y: number) => y - x));
  });
});

describe("config", () => {
  it("GET defaults, PUT partial updates, validation, audit", async () => {
    expect(await get("config")).toEqual({ maintenance: false, motd: "", turn_roll_s: 15, turn_choose_s: 20, turn_pair_s: 10 });
    const r = await api(cookie, "config", { method: "PUT", body: { motd: "Eid Mubarak!", turn_roll_s: 30 } });
    expect(r).toEqual({ maintenance: false, motd: "Eid Mubarak!", turn_roll_s: 30, turn_choose_s: 20, turn_pair_s: 10 });
    expect(await api(cookie, "config", { method: "PUT", body: {} })).toEqual(r);
    for (const bad of [
      { motd: "x".repeat(141) },
      { motd: 5 },
      { maintenance: "1" },
      { turn_roll_s: 4 },
      { turn_choose_s: 121 },
      { turn_pair_s: 7.5 },
      { other: 1 },
    ]) {
      expect((await api(cookie, "config", { method: "PUT", body: bad }, 400)).error).toBe("bad_request");
    }
    expect(await get("config")).toEqual(r);
    const a = await rows("SELECT detail FROM admin_log WHERE action = 'config.update' ORDER BY id DESC LIMIT 1");
    expect(JSON.parse(a[0].detail)).toEqual({ motd: "Eid Mubarak!", turn_roll_s: 30 });
    expect((await call("config", { cookie, method: "PUT", body: "not json" as unknown as Json })).status).toBe(400);
    await api(cookie, "config", { method: "PUT", body: { motd: "", turn_roll_s: 15 } });
  });
});
