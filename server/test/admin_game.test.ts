// What the Room writes to D1 during real games, and what the server enforces from D1 (maintenance, bans, turn
// timers, /v1/config), the daily cron and the console's static files.
import { SELF } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import { cron } from "../src/cron";
import type { Env } from "../src/room";
import { DB, api, eventually, login, row, rows, type Json } from "./admin_helpers";
import { Client, createRoom, finishAll, lobbyOf, NEAR_GOAL, newPid, roomInfo, startAll, E } from "./room_client";

const roomRow = (code: string) => row("SELECT * FROM rooms WHERE code = ?", code);
const matchRows = (code: string) => rows("SELECT * FROM matches WHERE code = ? ORDER BY id", code);

describe("instrumentation", () => {
  it("a full 2-player game writes the rooms, matches and players rows", async () => {
    const { code, cs } = await lobbyOf(2, { tok: NEAR_GOAL });
    const [red, yel] = cs;
    // create + 2 joins: the row shows both members online, red as host
    await eventually(async () => {
      const r = await roomRow(code);
      return r && r.members === 2 && r.online === 2 ? r : null;
    }, 8000, "lobby row");
    const r0 = (await roomRow(code))!;
    expect(r0).toMatchObject({ status: "lobby", host_pid: red.pid, host_name: "P1", closed_reason: null });
    expect(JSON.parse(r0.settings)).toEqual({ teams: false, pair_ask: false });
    for (const c of cs) {
      const p = await eventually(() => row("SELECT * FROM players WHERE pid = ?", c.pid), 5000, "player row");
      expect(p).toMatchObject({ name: c.name, avatar: "a1", frame: "f1", rooms: 1, matches: 0, wins: 0, banned: 0, last_room: code });
      expect(p.first_seen).toBeGreaterThan(0);
    }

    await startAll(cs);
    await red.wait("turn");
    const playing = await eventually(async () => {
      const ms = await matchRows(code);
      return ms.length === 1 ? ms[0] : null;
    }, 5000, "match row");
    expect(playing.result).toBe("playing");
    expect(JSON.parse(playing.players)).toEqual([
      { pid: red.pid, name: "P1", color: 0, bot: false },
      { pid: yel.pid, name: "P2", color: 2, bot: false },
    ]);
    expect(playing).toMatchObject({ teams: 0, pair_ask: 0 });
    expect((await roomRow(code))!.status).toBe("playing");

    for (const c of cs) c.autoplay = true;
    red.playTurn(0); // its first turn already came
    const [over] = await finishAll(cs);
    const m = await eventually(async () => {
      const ms = await matchRows(code);
      return ms[0]?.result === "over" ? ms[0] : null;
    }, 5000, "match over");
    expect(m.winner).toBe(over.winner);
    expect(JSON.parse(m.finished)).toEqual(over.finished);
    expect(m.actions).toBe(red.n);
    expect(m.ended_at).toBeGreaterThanOrEqual(m.started_at);
    expect((await roomRow(code))!.status).toBe("over");
    const winner = over.winner === 0 ? red : yel;
    for (const c of cs) {
      const p = await eventually(async () => {
        const x = await row("SELECT * FROM players WHERE pid = ?", c.pid);
        return x && x.matches === 1 ? x : null;
      }, 5000, "player stats");
      expect(p.wins).toBe(c === winner ? 1 : 0);
    }
    // activity for today's overview
    expect((await rows("SELECT * FROM player_days WHERE pid IN (?, ?)", red.pid, yel.pid)).length).toBe(2);
  });

  it("member changes are debounced, the final state is written", async () => {
    const { code, cs } = await lobbyOf(3);
    cs[2].send({ t: "leave" });
    await cs[0].waitFor((m) => m.t === "lobby" && m.members.length === 2);
    cs[1].close();
    await cs[0].waitFor((m) => m.t === "lobby" && m.members.some((x: Json) => !x.online));
    const r = await eventually(async () => {
      const x = await roomRow(code);
      return x && x.members === 2 && x.online === 1 ? x : null;
    }, 8000, "debounced final row");
    expect(r.status).toBe("lobby");
  });

  it("a room deleted by cleanup with a match still playing: match abandoned, room closed", async () => {
    // empty timeout 10 min x 0.001 = 600 ms; everyone leaves mid-match
    const { code, cs } = await lobbyOf(2, { timeScale: 0.001 });
    await startAll(cs);
    await eventually(async () => (await matchRows(code)).length === 1, 5000, "match row");
    for (const c of cs) c.close();
    const r = await eventually(async () => {
      const x = await roomRow(code);
      return x?.status === "closed" ? x : null;
    }, 8000, "closed row");
    expect(r.closed_reason).toBe("empty");
    expect(r.online).toBe(0);
    const [m] = await matchRows(code);
    expect(m.result).toBe("abandoned");
    expect(m.ended_at).toBeGreaterThan(0);
    expect((await roomInfo(code)).status).toBe(404);
  });

  it("a reserved code nobody joins is closed by the empty timeout", async () => {
    const code = await createRoom({ timeScale: 0.001 });
    const r0 = await eventually(() => roomRow(code), 5000, "created row");
    expect(r0).toMatchObject({ members: 0, online: 0, host_pid: null });
    const r = await eventually(async () => {
      const x = await roomRow(code);
      return x?.status === "closed" ? x : null;
    }, 8000, "closed row");
    expect(r.closed_reason).toBe("empty");
  });
});

describe("enforcement", () => {
  it("maintenance blocks POST /v1/rooms (503 + motd) but not existing rooms; /v1/config shows it", async () => {
    const cookie = await login();
    const { code } = await lobbyOf(1);
    expect(await (await SELF.fetch("https://x/v1/config")).json()).toEqual({ motd: "", maintenance: false });

    await api(cookie, "config", { method: "PUT", body: { maintenance: true, motd: "Back at 6 pm" } });
    const r = await SELF.fetch("https://x/v1/rooms", { method: "POST" });
    expect(r.status).toBe(503);
    expect(await r.json()).toEqual({ error: "maintenance", msg: "Back at 6 pm" });
    const cfg = await SELF.fetch("https://x/v1/config");
    expect(cfg.headers.get("Cache-Control")).toBe("public, max-age=60");
    expect(await cfg.json()).toEqual({ motd: "Back at 6 pm", maintenance: true });
    // the existing room still works
    const c = await Client.join(code, { name: "Late" });
    await c.waitFor((m) => m.t === "lobby" && m.members.length === 2);

    await api(cookie, "config", { method: "PUT", body: { motd: "" } });
    const r2 = await SELF.fetch("https://x/v1/rooms", { method: "POST" });
    expect(await r2.json()).toMatchObject({ error: "maintenance", msg: expect.stringMatching(/maintenance/) });

    await api(cookie, "config", { method: "PUT", body: { maintenance: false } });
    expect((await SELF.fetch("https://x/v1/rooms", { method: "POST" })).status).toBe(200);
    expect(await (await SELF.fetch("https://x/v1/config")).json()).toEqual({ motd: "", maintenance: false });
  });

  it("a banned pid's hello gets error banned and close 4003 (and a warn event)", async () => {
    const pid = newPid();
    await DB.prepare("INSERT INTO players (pid, name, first_seen, last_seen, banned, ban_reason) VALUES (?, 'Cheat', 1, 1, 1, 'cheating')")
      .bind(pid)
      .run();
    const code = await createRoom();
    const c = await Client.open(code, pid);
    c.hello();
    const e = await c.wait("error");
    expect(e).toMatchObject({ code: "banned" });
    expect(e.msg).toContain("cheating");
    expect(await c.waitClosed()).toBe(4003);
    expect(c.all("welcome")).toEqual([]);
    expect((await roomInfo(code)).body.members).toBe(0);
    await eventually(() => row("SELECT * FROM events WHERE kind = 'banned' AND pid = ? AND level = 'warn'", pid), 5000, "event");
    // other players are fine
    await Client.join(code);
  });

  it("messages a client sends right after hello wait for the ban check (order kept)", async () => {
    const code = await createRoom({ ratePerSec: 1000 });
    const c = await Client.open(code);
    c.hello();
    c.send({ t: "sync_req" });
    await c.wait("welcome");
    expect(c.all("error")).toEqual([]);
    await c.waitFor((m) => m.t === "lobby");
  });

  it("turn timers from config apply to matches started after the change", async () => {
    const cookie = await login();
    await api(cookie, "config", { method: "PUT", body: { turn_roll_s: 7, turn_choose_s: 9, turn_pair_s: 5 } });
    const { cs } = await lobbyOf(2, { dice: [3] });
    const [red] = cs;
    await startAll(cs);
    const t = await red.wait("turn");
    expect(t.deadline - t.now).toBeGreaterThanOrEqual(6900);
    expect(t.deadline - t.now).toBeLessThanOrEqual(7100);
    red.send({ t: "roll", n: 0 }); // a 3 with every pawn at base: no move, Yellow's turn to roll
    const t2 = await red.waitFor((m) => m.t === "turn" && m.c === 2);
    expect(t2.deadline - t2.now).toBeLessThanOrEqual(7100);

    await api(cookie, "config", { method: "PUT", body: { turn_roll_s: 15, turn_choose_s: 20, turn_pair_s: 10 } });
    const { cs: cs2 } = await lobbyOf(2);
    await startAll(cs2);
    const t3 = await cs2[0].wait("turn");
    expect(t3.deadline - t3.now).toBeGreaterThanOrEqual(14_900);
  });
});

describe("cron", () => {
  it("prunes events / login attempts older than 30 days and closes rows of vanished rooms", async () => {
    const now = Date.now();
    const old = now - 31 * 86_400_000;
    await DB.batch([
      DB.prepare("INSERT INTO events (at, level, kind, msg) VALUES (?, 'error', 'cron_old', 'x')").bind(old),
      DB.prepare("INSERT INTO events (at, level, kind, msg) VALUES (?, 'error', 'cron_new', 'x')").bind(now),
      DB.prepare("INSERT INTO login_attempts (ip, at) VALUES ('cron-ip', ?)").bind(old),
      DB.prepare("INSERT INTO login_attempts (ip, at) VALUES ('cron-ip', ?)").bind(now),
      DB.prepare("INSERT INTO rooms (code, created_at, updated_at, status, members, online, settings) VALUES ('ZZZZZZ', ?, ?, 'playing', 2, 2, '{}')").bind(old, old),
      DB.prepare("INSERT INTO matches (code, started_at, players, result) VALUES ('ZZZZZZ', ?, '[]', 'playing')").bind(old),
    ]);
    const res = await cron(E as Env, now);
    expect(res.pruned.events).toBeGreaterThanOrEqual(1);
    expect(res.pruned.login_attempts).toBeGreaterThanOrEqual(1);
    expect(res.reconciled).toBeGreaterThanOrEqual(1);
    expect((await rows("SELECT kind FROM events WHERE kind LIKE 'cron_%'")).map((x) => x.kind)).toEqual(["cron_new"]);
    expect((await rows("SELECT at FROM login_attempts WHERE ip = 'cron-ip'")).length).toBe(1);
    expect(await roomRow("ZZZZZZ")).toMatchObject({ status: "closed", closed_reason: "gone" });
    expect((await matchRows("ZZZZZZ"))[0].result).toBe("abandoned");
  });
});

describe("console files", () => {
  it("/admin and /admin/ serve index.html; files under /admin/; nothing at the root", async () => {
    for (const p of ["/admin", "/admin/"]) {
      const r = await SELF.fetch(`https://x${p}`);
      expect(r.status, p).toBe(200);
      expect(r.headers.get("Content-Type")).toContain("text/html");
      expect(r.headers.get("X-Frame-Options")).toBe("DENY");
      expect(r.headers.get("Content-Security-Policy")).toBe(
        "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; font-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'",
      );
      expect(r.headers.get("Referrer-Policy")).toBe("no-referrer");
      expect(await r.text()).toContain("<html");
    }
    const app = await SELF.fetch("https://x/admin/js/app.js");
    expect(app.status).toBe(200);
    expect(app.headers.get("Content-Type")).toContain("javascript");
    expect(app.headers.get("Content-Security-Policy")).toContain("script-src 'self'");
    await app.text();
    const fav = await SELF.fetch("https://x/admin/favicon.svg");
    expect(fav.status).toBe(200);
    await fav.arrayBuffer();
    expect((await SELF.fetch("https://x/index.html")).status).toBe(404);
    expect((await SELF.fetch("https://x/favicon.svg")).status).toBe(404);
    expect((await SELF.fetch("https://x/admin/nope.js")).status).toBe(404);
    expect((await SELF.fetch("https://x/admin", { method: "POST" })).status).toBe(405);
  });
});
