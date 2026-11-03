#!/usr/bin/env node
// Seeds the LOCAL D1 database (the one `npx wrangler dev` uses, in .wrangler/state) with realistic data for the admin
// console: 14 days of synthetic history (rooms, matches, players, activity, a banned player, events), then real
// games played by tools/sim.mjs against the running local server, and optionally rooms kept live until Ctrl-C.
// It only ever runs wrangler with --local; it never touches the deployed database.
//
//   npx wrangler dev --port 8787          # terminal 1 (server/.dev.vars holds ADMIN_PASSWORD)
//   node tools/seed-local.mjs [--url http://localhost:8787] [--games 4] [--live] [--no-history] [--wipe]
//
//   --games N      sim games to play against the server (default 4; 0 = none)
//   --live         afterwards keep a lobby (2 members) and a match (idle players, bots take over) open until Ctrl-C
//   --no-history   skip the synthetic history
//   --wipe         empty every local admin table first
import { spawn, spawnSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const serverDir = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const DB_NAME = "ludo-zing-admin";

const args = process.argv.slice(2);
const flag = (n) => args.includes(`--${n}`);
function opt(name, def) {
  const k = args.indexOf(`--${name}`);
  return k >= 0 && args[k + 1] !== undefined && !args[k + 1].startsWith("--") ? args[k + 1] : def;
}
const HTTP = String(opt("url", "http://localhost:8787")).replace(/\/$/, "");
const WS = HTTP.replace(/^http/, "ws");
const GAMES = Number(opt("games", 4));
const LIVE = flag("live");
const HISTORY = !flag("no-history");
const WIPE = flag("wipe");

// ---------- wrangler (always --local) ----------

function wrangler(...a) {
  if (a.includes("--remote")) throw new Error("refusing to run against the remote database");
  const r = spawnSync("npx", ["wrangler", ...a, "--local"], {
    cwd: serverDir,
    encoding: "utf8",
    env: { ...process.env, CI: "1" }, // no confirmation prompts
  });
  if (r.status !== 0) {
    process.stderr.write(r.stdout + r.stderr);
    throw new Error(`wrangler ${a.slice(0, 3).join(" ")} failed`);
  }
  return r.stdout;
}

function execSql(sql) {
  const dir = mkdtempSync(join(tmpdir(), "lz-seed-"));
  const file = join(dir, "seed.sql");
  try {
    writeFileSync(file, sql);
    wrangler("d1", "execute", DB_NAME, "--file", file);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

// ---------- synthetic history ----------

const NAMES = ["Rafi", "Nusrat", "Tanvir", "Mitu", "Sakib", "Ayesha", "Imran", "Farzana", "Jamil", "Sumaiya", "Arif",
  "Lamia", "Hasan", "Tania", "Rubel", "Shathi", "Kamal", "Popy", "Nayeem", "Rima", "Player", "Zing King"];
const AVATARS = ["avatar_01", "avatar_02", "avatar_03", "avatar_04", "avatar_05", "avatar_06"];
const FRAMES = ["", "frame_gold", "frame_leaf", ""];
const ALPHABET = "23456789ABCDEFGHJKMNPQRSTUVWXYZ";
const DAY = 86_400_000;

const rnd = (n) => Math.floor(Math.random() * n);
const pick = (a) => a[rnd(a.length)];
const q = (v) => (v === null || v === undefined ? "NULL" : typeof v === "number" ? String(v) : `'${String(v).replace(/'/g, "''")}'`);
const code = () => Array.from({ length: 6 }, () => pick(ALPHABET)).join("");
const pid = () => "seed" + Math.random().toString(36).slice(2, 12) + Math.random().toString(36).slice(2, 12);
const SEATS = { 2: [0, 2], 3: [0, 1, 2], 4: [0, 1, 2, 3] };

function history() {
  const now = Date.now();
  const today = Math.floor(now / DAY) * DAY;
  const pool = Array.from({ length: 24 }, () => ({
    pid: pid(), name: pick(NAMES), avatar: pick(AVATARS), frame: pick(FRAMES),
    first: Infinity, last: 0, rooms: 0, matches: 0, wins: 0, days: new Set(),
  }));
  const out = [];
  for (let d = 13; d >= 0; d--) {
    const dayStart = today - d * DAY;
    const n = d === 0 ? 3 : 3 + rnd(10);
    for (let k = 0; k < n; k++) {
      const created = Math.min(dayStart + rnd(DAY), now - 60 * 60_000);
      const size = 2 + rnd(3);
      const teams = size === 4 && Math.random() < 0.3;
      const pairAsk = Math.random() < 0.3;
      const members = [...pool].sort(() => Math.random() - 0.5).slice(0, size);
      const c = code();
      const started = created + 60_000 + rnd(4 * 60_000);
      const ended = started + 5 * 60_000 + rnd(20 * 60_000);
      const roll = Math.random();
      const result = roll < 0.8 ? "over" : roll < 0.92 ? "abandoned" : "closed";
      const colors = SEATS[size];
      const finished = result === "over" ? [...colors].sort(() => Math.random() - 0.5).slice(0, teams ? 2 : size - 1) : [];
      const winner = result === "over" ? finished[0] : null;
      const winners = winner === null ? [] : teams ? [winner, (winner + 2) % 4] : [winner];
      const players = members.map((m, j) => ({ pid: m.pid, name: m.name, color: colors[j], bot: result === "abandoned" && j > 0 }));
      for (const [j, m] of members.entries()) {
        m.first = Math.min(m.first, created);
        m.last = Math.max(m.last, ended);
        m.rooms++;
        m.days.add(new Date(created).toISOString().slice(0, 10));
        if (result === "over") {
          m.matches++;
          if (winners.includes(colors[j])) m.wins++;
        }
      }
      const reason = result === "closed" ? "admin: seeded close" : result === "abandoned" ? "empty" : pick(["stale", "empty"]);
      out.push(
        `INSERT INTO rooms (code, created_at, updated_at, host_pid, host_name, status, members, online, settings, closed_reason) VALUES (` +
          [c, created, ended + 10 * 60_000, members[0].pid, members[0].name, "closed", size, 0, JSON.stringify({ teams, pair_ask: pairAsk }), reason].map(q).join(", ") +
          ") ON CONFLICT(code) DO NOTHING;",
        `INSERT INTO matches (code, started_at, ended_at, players, teams, pair_ask, winner, finished, actions, result) VALUES (` +
          [c, started, ended, JSON.stringify(players), teams ? 1 : 0, pairAsk ? 1 : 0, winner, JSON.stringify(finished), 80 + rnd(320), result].map(q).join(", ") +
          ");",
      );
    }
  }
  const banned = pool[0];
  for (const m of pool) {
    if (!m.rooms) continue;
    const isBanned = m === banned;
    out.push(
      `INSERT OR IGNORE INTO players (pid, name, avatar, frame, first_seen, last_seen, rooms, matches, wins, banned, ban_reason, note) VALUES (` +
        [m.pid, m.name, m.avatar, m.frame, m.first, m.last, m.rooms, m.matches, m.wins, isBanned ? 1 : 0,
          isBanned ? "Seeded: abusive name" : null, isBanned ? "seed data" : null].map(q).join(", ") + ");",
    );
    for (const day of m.days) out.push(`INSERT OR IGNORE INTO player_days (day, pid) VALUES (${q(day)}, ${q(m.pid)});`);
  }
  const ev = [
    ["warn", "banned", banned.pid, "banned pid refused: Seeded: abusive name"],
    ["error", "exception", null, "message: TypeError: Cannot read properties of undefined (reading 'turn')\n    at Room.step (room.ts)"],
    ["error", "storage", null, "put: storage operation exceeded timeout"],
    ["warn", "banned", banned.pid, "banned pid refused: Seeded: abusive name"],
    ["error", "worker", null, "POST /v1/rooms: Error: D1_ERROR: network connection lost"],
    ["info", "seed", null, "seed-local.mjs ran"],
  ];
  for (const [i, [level, kind, p, msg]] of ev.entries()) {
    out.push(
      `INSERT INTO events (at, level, kind, code, pid, msg) VALUES (` +
        [now - (ev.length - i) * 3 * 60 * 60_000, level, kind, code(), p, msg].map(q).join(", ") + ");",
    );
  }
  return out.join("\n");
}

// ---------- games against the local server ----------

async function serverUp() {
  try {
    const r = await fetch(`${HTTP}/v1/health`);
    return r.ok;
  } catch {
    return false;
  }
}

function sim(extra) {
  return new Promise((res) => {
    const p = spawn(process.execPath, [join(serverDir, "tools/sim.mjs"), "--url", WS, "--delay", "40", "--quiet", "--timeout", "300000", ...extra], {
      cwd: serverDir,
      stdio: ["ignore", "pipe", "pipe"],
    });
    let out = "";
    p.stdout.on("data", (b) => (out += b));
    p.stderr.on("data", (b) => (out += b));
    p.on("close", (code) => res({ code, out, extra }));
  });
}

const SIM_SETS = [
  ["--players", "2"],
  ["--players", "3", "--pair-ask"],
  ["--players", "4"],
  ["--players", "4", "--teams"],
  ["--players", "2", "--pair-ask"],
  ["--players", "3"],
];

// ---------- live rooms (--live) ----------

function client(code, name) {
  return new Promise((res, rej) => {
    const ws = new WebSocket(`${WS}/v1/rooms/${code}/ws`);
    const c = { ws, name, msgs: [] };
    ws.onopen = () => ws.send(JSON.stringify({ t: "hello", v: 1, pid: pid(), name, avatar: pick(AVATARS), frame: "" }));
    ws.onerror = () => rej(new Error("ws error"));
    ws.onmessage = (ev) => {
      const m = JSON.parse(ev.data);
      c.msgs.push(m);
      if (m.t === "welcome") res(c);
    };
  });
}

async function newRoom() {
  const r = await fetch(`${HTTP}/v1/rooms`, { method: "POST" });
  if (!r.ok) throw new Error(`POST /v1/rooms: ${r.status} ${await r.text()}`);
  return (await r.json()).code;
}

async function live() {
  const lobby = await newRoom();
  const a = [await client(lobby, "Rafi"), await client(lobby, "Mitu")];
  const match = await newRoom();
  const b = [await client(match, "Sakib"), await client(match, "Ayesha"), await client(match, "Nayeem")];
  b[0].ws.send(JSON.stringify({ t: "start" }));
  console.log(`live: lobby ${lobby} (2 members), match ${match} (3 idle players: timeouts, then bots play it out)`);
  console.log("Ctrl-C to close them.");
  const ping = setInterval(() => [...a, ...b].forEach((c) => c.ws.readyState === 1 && c.ws.send('{"t":"ping"}')), 20_000);
  await new Promise((res) => process.on("SIGINT", res));
  clearInterval(ping);
  [...a, ...b].forEach((c) => c.ws.close(1000, "bye"));
}

// ---------- main ----------

async function main() {
  console.log("applying migrations to the local D1 database...");
  wrangler("d1", "migrations", "apply", DB_NAME);
  if (WIPE) {
    console.log("wiping local admin tables...");
    execSql(["players", "rooms", "matches", "events", "config", "admin_log", "login_attempts", "player_days"].map((t) => `DELETE FROM ${t};`).join("\n"));
  }
  if (HISTORY) {
    console.log("writing 14 days of synthetic history...");
    execSql(history());
  }
  if (GAMES > 0 || LIVE) {
    if (!(await serverUp())) {
      console.error(`no server at ${HTTP}: start \`npx wrangler dev --port 8787\` in server/ and run this again (or pass --games 0).`);
      process.exit(1);
    }
  }
  if (GAMES > 0) {
    console.log(`playing ${GAMES} sim games against ${WS} (in parallel; a few minutes)...`);
    const runs = await Promise.all(Array.from({ length: GAMES }, (_, k) => sim(SIM_SETS[k % SIM_SETS.length])));
    for (const r of runs) {
      const line = r.out.split("\n").find((l) => l.startsWith("RESULT")) ?? `exit ${r.code}`;
      const room = r.out.split("\n").find((l) => l.startsWith("room"))?.trim() ?? "";
      console.log(`  sim ${r.extra.join(" ").padEnd(24)} ${room.padEnd(20)} ${line}`);
      if (r.code !== 0) console.log(r.out.split("\n").slice(-12).join("\n"));
    }
  }
  console.log(`done. Console: ${HTTP}/admin (password: ADMIN_PASSWORD from server/.dev.vars)`);
  if (LIVE) await live();
}

main().catch((e) => {
  console.error(e);
  process.exit(2);
});
