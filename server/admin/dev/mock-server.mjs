#!/usr/bin/env node
// Dev mock of the admin API (server/ADMIN_API.md) + static server for the console. No dependencies.
//
//   node server/admin/dev/mock-server.mjs            → http://localhost:8790/admin  (password: dev)
//   PORT=9000 node server/admin/dev/mock-server.mjs
//   MOCK_DISABLED=1 …   every /admin/api call answers 503 admin_disabled (no ADMIN_PASSWORD)
//   MOCK_LATENCY=400 …  extra latency per API call (ms), to see skeletons
//
// Data is fake and in memory (seeded, so it's the same on every start). Three rooms play live matches whose
// state advances on a timer, so the room page's board animates.

import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { fileURLToPath } from "node:url";

const ADMIN_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const PORT = Number(process.env.PORT || 8790);
const PASSWORD = "dev";
const DISABLED = process.env.MOCK_DISABLED === "1";
const LATENCY = Number(process.env.MOCK_LATENCY || 120);
const DAY = 86400e3;

// ---------- seeded RNG ----------
let seed = 20261024;
const rnd = () => ((seed = (seed * 1664525 + 1013904223) >>> 0) / 4294967296);
const ri = (a, b) => a + Math.floor(rnd() * (b - a + 1));
const pick = (arr) => arr[Math.floor(rnd() * arr.length)];
const ALNUM = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-";
const CODE_ALPHA = "23456789ABCDEFGHJKMNPQRSTUVWXYZ";
const randStr = (n, al = ALNUM) => Array.from({ length: n }, () => al[Math.floor(rnd() * al.length)]).join("");

const NOW0 = Date.now();

// ---------- players ----------
const NAMES = ["Rafi", "Nusrat", "Tanvir", "Mim", "Sakib", "Ayesha", "Fahim", "Jannat", "Rakib", "Tasnim", "Arif", "Sumaiya",
  "Imran", "Farhana", "Shuvo", "Puja", "Nayeem", "Riya", "Hasan", "Lamia", "Sabbir", "Mehjabin", "Tamim", "Anika", "Rasel",
  "Sadia", "Joy", "Nabila", "Ovi", "Tisha", "Rumi", "Priya", "Shanto", "Bristy", "Asif", "Tuli", "Zubair", "Moumita", "Kowshik",
  "Ludo King 👑", "<img src=x onerror=alert(1)>", "Zara & Co", "\"quoted\"", "মাহি", "Player", "ThisNameIs16Char", "Mocha fan",
  "Dhaka Dice", "Brahmaputra", "Gold Rush", "x", "Nabil", "Ishrat", "Fardin", "Raisa", "Shamim", "Keya", "Turjo", "Hridoy", "Oishee", "Sami", "Labib", "Raha"];
const AVATARS = ["pawn-red", "pawn-green", "pawn-yellow", "pawn-blue", "latte", "dice", "robot", "crown", "char-mymensingh-boat", ""];
const players = NAMES.map((name, k) => {
  const first = NOW0 - ri(0, 40) * DAY - ri(0, DAY);
  const last = Math.min(NOW0 - ri(0, 5) * 3600e3 * (k % 4 ? 3 : 0.1), first + ri(0, 40) * DAY);
  return {
    pid: randStr(ri(18, 24)), name, avatar: pick(AVATARS), frame: pick(["", "gold", "rose", "night"]),
    first_seen: first, last_seen: Math.max(first, last), rooms: 0, matches: 0, wins: 0,
    banned: 0, ban_reason: null, note: null,
  };
});
players[40].banned = 1; players[40].ban_reason = "XSS attempt in the display name";
players[12].banned = 1; players[12].ban_reason = "Abusive name, 3 reports";
players[3].note = "Tester from the Mymensingh club. Reports bugs on WhatsApp.";
const byPid = new Map(players.map((p) => [p.pid, p]));

// ---------- rooms + matches ----------
const rooms = [];
const matches = [];
let matchId = 1;
const newCode = () => { let c; do c = randStr(6, CODE_ALPHA); while (rooms.some((r) => r.code === c)); return c; };
const SEAT_COLORS = { 1: [0], 2: [0, 2], 3: [0, 1, 2], 4: [0, 1, 2, 3] };

function pickPlayers(n) {
  const pool = players.filter((p) => !p.banned);
  const out = [];
  while (out.length < n) { const p = pick(pool); if (!out.includes(p)) out.push(p); }
  return out;
}

function addMatch(code, members, startedAt, opts = {}) {
  const n = members.length;
  const cols = SEAT_COLORS[n];
  const teams = n === 4 && rnd() < 0.2 ? 1 : 0;
  const ps = cols.map((color, k) => {
    const m = members[k];
    const bot = !m || (opts.botChance && rnd() < opts.botChance);
    return bot ? { pid: null, name: ["Mocha", "Biscotti", "Espresso"][k % 3], color, bot: true } : { pid: m.pid, name: m.name, color, bot: false };
  });
  const result = opts.result || (rnd() < 0.86 ? "over" : rnd() < 0.6 ? "abandoned" : "closed");
  const dur = ri(4, 26) * 60e3 + ri(0, 59e3);
  const order = cols.slice().sort(() => rnd() - 0.5);
  const m = {
    id: matchId++, code, started_at: startedAt, ended_at: result === "playing" ? null : startedAt + dur, players: ps, teams,
    pair_ask: rnd() < 0.3 ? 1 : 0, winner: result === "over" ? order[0] : -1, finished: result === "over" ? order.slice(0, Math.max(1, n - 1)) : null,
    actions: result === "playing" ? 0 : ri(70, 420), result,
  };
  matches.push(m);
  if (result === "over") {
    for (const p of ps) {
      if (p.bot) continue;
      const pl = byPid.get(p.pid);
      pl.matches++;
      if (p.color === m.winner || (teams && (m.winner + 2) % 4 === p.color)) pl.wins++;
    }
  }
  return m;
}

function addRoom(status, createdAt, nMembers) {
  const mem = pickPlayers(nMembers);
  for (const p of mem) p.rooms++;
  const r = {
    code: newCode(), created_at: createdAt, updated_at: Math.min(Date.now(), createdAt + ri(1, 40) * 60e3), host_pid: mem[0].pid, host_name: mem[0].name,
    status, members: status === "closed" ? 0 : nMembers, online: status === "closed" ? 0 : status === "over" ? ri(0, nMembers) : nMembers,
    settings: { teams: nMembers === 4 && rnd() < 0.25, pair_ask: rnd() < 0.3 }, closed_reason: null, _members: mem,
  };
  if (status === "closed") r.closed_reason = pick(["empty for 10 min", "stale (2 h since the last action)", "empty for 10 min", "admin: spam room"]);
  rooms.push(r);
  return r;
}

// history: 14 days, more on recent days / weekends
for (let d = 15; d >= 0; d--) {
  const dayStart = Math.floor((NOW0 - d * DAY) / DAY) * DAY;
  const span = d === 0 ? NOW0 - dayStart - 600e3 : DAY;
  const count = d === 0 ? ri(5, 8) : ri(3, 9) + (d < 6 ? 3 : 0);
  for (let k = 0; k < count; k++) {
    const created = dayStart + Math.floor(rnd() * span);
    const n = ri(2, 4);
    const r = addRoom(rnd() < 0.55 ? "closed" : "over", created, n);
    const games = ri(1, 3);
    let t = created + ri(1, 5) * 60e3;
    for (let g = 0; g < games; g++) {
      const m = addMatch(r.code, r._members, t, { botChance: 0.08 });
      t = (m.ended_at || t) + ri(1, 4) * 60e3;
      if (m.result !== "over") break;
    }
    r.updated_at = Math.min(NOW0, t);
    if (r.status === "closed") { r.updated_at += 600e3; const last = matches[matches.length - 1]; if (last.result === "playing") last.result = "abandoned"; }
  }
}
// lobbies
for (let k = 0; k < 3; k++) addRoom("lobby", NOW0 - ri(1, 9) * 60e3, ri(1, 3));

// ---------- live matches (simplified rules, enough to animate the board) ----------
const OFF = [0, 13, 26, 39];
const SAFE = new Set([0, 13, 26, 39, 8, 21, 34, 47]);
const live = new Map(); // code -> {room, members, settings, host, match|null, status}

function liveFromRoom(r, withMatch) {
  const members = r._members.map((p, j) => ({ id: j + 1, pid: p.pid, name: p.name, avatar: p.avatar, frame: p.frame, online: true, color: SEAT_COLORS[r._members.length][j] }));
  const L = { room: r, members, settings: { ...r.settings }, host: 1, status: r.status, match: null, nextId: members.length + 1 };
  if (withMatch) startMatch(L, true);
  live.set(r.code, L);
  return L;
}

function startMatch(L, scramble) {
  const cols = SEAT_COLORS[Math.min(4, L.members.length)];
  const pl = ["off", "off", "off", "off"];
  const names = ["", "", "", ""];
  const seats = cols.map((color, k) => {
    const m = L.members[k];
    pl[color] = "human";
    names[color] = m.name;
    return { color, id: m.id, name: m.name, avatar: m.avatar, frame: m.frame, bot: false, online: m.online, pid: m.pid, left: false };
  });
  const tok = [[-1, -1, -1, -1], [-1, -1, -1, -1], [-1, -1, -1, -1], [-1, -1, -1, -1]];
  if (scramble) {
    for (const c of cols) for (let i = 0; i < 4; i++) {
      const x = rnd();
      tok[c][i] = x < 0.35 ? -1 : x < 0.85 ? ri(0, 50) : x < 0.95 ? ri(51, 55) : 56;
    }
    // a stack, to show the count badge
    tok[cols[0]][1] = tok[cols[0]][2] = 8;
  }
  const state = {
    players: pl, names, view: cols[0], tok, pairs: [], turn: cols[0], dice: 0, sixes: 0, phase: "roll", pick: "", winner: -1,
    teams: Boolean(L.settings.teams && cols.length === 4), free: [false, false, false, false], pending: {}, pair_ask: Boolean(L.settings.pair_ask), finished: [],
  };
  const m = addMatch(L.room.code, L.members, Date.now() - (scramble ? ri(3, 12) * 60e3 : 0), { result: "playing" });
  m.players = seats.map((s) => ({ pid: s.pid, name: s.name, color: s.color, bot: false }));
  m.teams = state.teams ? 1 : 0;
  L.match = { n: scramble ? ri(40, 180) : 0, state, seats, deadline: Date.now() + 2500, started_at: m.started_at, _row: m };
  L.status = "playing";
  L.room.status = "playing";
}

function nextTurn(s, c) {
  for (let k = 1; k <= 4; k++) {
    const n = (c + k) % 4;
    if (s.players[n] !== "off" && !s.finished.includes(n)) return n;
  }
  return c;
}

function stepDelay(L, c) {
  const seat = L.match.seats.find((x) => x.color === c);
  return seat?.bot ? 900 + rnd() * 700 : 1600 + rnd() * 4200;
}

function step(L) {
  const M = L.match;
  const s = M.state;
  const c = s.turn;
  M.n++;
  if (s.phase === "over") return;
  if (s.phase === "roll") {
    s.dice = rnd() < 0.22 ? 6 : ri(1, 5);
    s.sixes = s.dice === 6 ? s.sixes + 1 : 0;
    const mov = s.tok[c].map((p, i) => ((p === -1 && s.dice === 6) || (p >= 0 && p + s.dice <= 56) ? i : -1)).filter((i) => i >= 0);
    if (!mov.length || s.sixes >= 3) {
      s.sixes = 0;
      s.turn = nextTurn(s, c);
      s.phase = "roll";
    } else s.phase = "choose";
  } else if (s.phase === "choose") {
    const mov = s.tok[c].map((p, i) => ((p === -1 && s.dice === 6) || (p >= 0 && p + s.dice <= 56) ? i : -1)).filter((i) => i >= 0);
    const i = mov.sort((a, b) => s.tok[c][b] - s.tok[c][a])[rnd() < 0.7 ? 0 : mov.length - 1];
    const p = s.tok[c][i] === -1 ? 0 : s.tok[c][i] + s.dice;
    s.tok[c][i] = p;
    let again = s.dice === 6;
    if (p <= 50) {
      const abs = (OFF[c] + p) % 52;
      if (!SAFE.has(abs)) {
        for (let o = 0; o < 4; o++) {
          if (o === c || (s.teams && (o + 2) % 4 === c)) continue;
          for (let j = 0; j < 4; j++) {
            const q = s.tok[o][j];
            if (q >= 0 && q <= 50 && (OFF[o] + q) % 52 === abs) { s.tok[o][j] = -1; again = true; }
          }
        }
      }
    }
    if (p === 56) {
      again = true;
      if (s.tok[c].every((x) => x === 56)) {
        s.finished.push(c);
        const active = s.players.filter((x) => x !== "off").length;
        if (s.finished.length >= active - 1) {
          s.phase = "over";
          s.winner = s.finished[0];
          finishMatch(L);
          return;
        }
        again = false;
      }
    }
    s.phase = "roll";
    if (!again) { s.turn = nextTurn(s, c); s.sixes = 0; }
  }
  M.deadline = Date.now() + stepDelay(L, s.turn);
  L.room.updated_at = Date.now();
}

function finishMatch(L) {
  const M = L.match;
  const row = M._row;
  row.ended_at = Date.now();
  row.result = "over";
  row.actions = M.n;
  row.winner = M.state.winner;
  row.finished = M.state.finished.slice();
  for (const p of row.players) {
    if (p.bot) continue;
    const pl = byPid.get(p.pid);
    if (!pl) continue;
    pl.matches++;
    if (p.color === row.winner) pl.wins++;
  }
  M.deadline = 0;
  L.status = "over";
  L.room.status = "over";
  setTimeout(() => { if (live.get(L.room.code) === L && L.members.length >= 2) startMatch(L, true); }, 12000);
}

const liveRooms = [addRoom("playing", NOW0 - 25 * 60e3, 4), addRoom("playing", NOW0 - 12 * 60e3, 2), addRoom("playing", NOW0 - 40 * 60e3, 3)];
liveRooms[0].settings.teams = false;
for (const r of liveRooms) liveFromRoom(r, true);
for (const r of rooms.filter((x) => x.status === "lobby")) liveFromRoom(r, false);
for (const r of rooms.filter((x) => x.status === "over" && NOW0 - x.updated_at < 3600e3)) liveFromRoom(r, false);
// one live member offline, one seat a bot
{
  const L = live.get(liveRooms[0].code);
  L.members[3].online = false;
  L.match.seats[3].online = false;
  L.match.seats[2].bot = true;
  L.match.state.players[L.match.seats[2].color] = "cpu";
}

setInterval(() => {
  const now = Date.now();
  for (const L of live.values()) {
    if (L.match && L.status === "playing" && L.match.deadline && now >= L.match.deadline) step(L);
  }
}, 200);

// ---------- events, config, audit ----------
const events = [];
let eventId = 1;
function addEvent(at, level, kind, msg, code = null, pid = null) { events.push({ id: eventId++, at, level, kind, code, pid, msg }); }
const EV = [
  ["error", "handler_exception", "TypeError: Cannot read properties of undefined (reading 'tok')\n    at Room.onMove (room.ts:812:21)\n    at Room.webSocketMessage (room.ts:640:9)"],
  ["error", "storage_failed", "storage.put failed: Durable Object storage operation exceeded timeout"],
  ["warn", "d1_write_failed", "D1_ERROR: database is locked (rooms update, retry dropped)"],
  ["warn", "rejected_ban", "hello from a banned pid; socket closed 4003"],
  ["warn", "rate", "socket over 20 messages/s; dropped the rest of the window"],
  ["info", "room_closed", "room deleted after 10 min empty"],
  ["info", "bot_takeover", "two timeouts in a row: seat 2 is a bot"],
  ["warn", "hash_mismatch", "client asked for sync_req 3 times in 10 s"],
  ["error", "alarm_failed", "alarm handler threw: <script>alert('xss')</script> (message escaped?)"],
];
for (let k = 0; k < 120; k++) {
  const [level, kind, msg] = pick(EV);
  const r = pick(rooms);
  addEvent(NOW0 - Math.floor(rnd() * 14 * DAY), level, kind, msg, rnd() < 0.8 ? r.code : null, rnd() < 0.5 ? pick(players).pid : null);
}
events.sort((a, b) => a.at - b.at).forEach((e, i) => (e.id = i + 1));
eventId = events.length + 1;

const config = { maintenance: false, motd: "Eid tournament this Friday at 8 pm. Invite your friends!", turn_roll_s: 15, turn_choose_s: 20, turn_pair_s: 10 };
const audit = [];
let auditId = 1;
function addAudit(at, ip, action, target, detail) { audit.push({ id: auditId++, at, ip, action, target, detail: detail === undefined ? null : JSON.stringify(detail) }); }
addAudit(NOW0 - 3 * DAY, "203.0.113.7", "login", null);
addAudit(NOW0 - 3 * DAY + 60e3, "203.0.113.7", "player.ban", players[12].pid, { reason: players[12].ban_reason, kicked: false });
addAudit(NOW0 - 2 * DAY, "203.0.113.7", "config.update", null, { motd: config.motd });
addAudit(NOW0 - 1 * DAY, "198.51.100.23", "login", null);
addAudit(NOW0 - 1 * DAY + 90e3, "198.51.100.23", "room.close", rooms[5].code, { reason: "admin: spam room", live: true });
addAudit(NOW0 - 1 * DAY + 95e3, "198.51.100.23", "player.ban", players[40].pid, { reason: players[40].ban_reason, kicked: true, room: rooms[6].code });
addAudit(NOW0 - 20 * 3600e3, "198.51.100.23", "player.note", players[3].pid, { note: players[3].note });
addAudit(NOW0 - 5 * 3600e3, "198.51.100.23", "logout", null);

// ---------- http helpers ----------
const sessions = new Set();
const loginAttempts = new Map(); // ip -> [ts]

function send(res, status, body, headers = {}) {
  const h = { "Cache-Control": "no-store", ...headers };
  if (body === null || body === undefined) { res.writeHead(status, h); res.end(); return; }
  h["Content-Type"] = "application/json; charset=utf-8";
  res.writeHead(status, h);
  res.end(JSON.stringify(body));
}
const fail = (res, status, error, msg) => send(res, status, msg ? { error, msg } : { error });

function readBody(req) {
  return new Promise((resolve) => {
    let data = "";
    req.on("data", (c) => { data += c; if (data.length > 1e5) req.destroy(); });
    req.on("end", () => { try { resolve(data ? JSON.parse(data) : {}); } catch { resolve(null); } });
  });
}

function cookieSession(req) {
  const m = /(?:^|;\s*)lz_admin=([^;]+)/.exec(req.headers.cookie || "");
  return m && sessions.has(m[1]) ? m[1] : null;
}

function paginate(list, url) {
  const limit = Math.min(200, Math.max(1, Number(url.searchParams.get("limit")) || 50));
  const off = Number(url.searchParams.get("cursor") ? Buffer.from(url.searchParams.get("cursor"), "base64url").toString() : 0) || 0;
  const items = list.slice(off, off + limit);
  const next = off + limit < list.length ? Buffer.from(String(off + limit)).toString("base64url") : null;
  return { items, next };
}

const pub = (r) => { const { _members, ...rest } = r; return rest; };
const matchOut = (m) => ({ ...m });

function snapshot(L) {
  if (!L) return null;
  const M = L.match;
  return {
    code: L.room.code, status: L.status, host: L.host, created: L.room.created_at, touched: L.room.updated_at,
    sockets: L.members.filter((m) => m.online).length,
    members: L.members.map((m) => ({ ...m, color: M && L.status === "playing" ? (M.seats.find((s) => s.id === m.id && !s.left)?.color ?? -1) : m.color })),
    settings: { ...L.settings },
    match: M ? { n: M.n, state: M.state, seats: M.seats, deadline: L.status === "playing" ? Math.round(M.deadline) : 0, started_at: M.started_at } : null,
  };
}

function overview() {
  const now = Date.now();
  const days = [];
  for (let d = 13; d >= 0; d--) {
    const start = Math.floor((now - d * DAY) / DAY) * DAY;
    const end = start + DAY;
    const ms = matches.filter((m) => m.started_at >= start && m.started_at < end);
    const act = new Set();
    for (const m of ms) for (const p of m.players) if (!p.bot) act.add(p.pid);
    days.push({ day: new Date(start).toISOString().slice(0, 10), rooms: rooms.filter((r) => r.created_at >= start && r.created_at < end).length, matches: ms.length, players_active: act.size });
  }
  const todayStart = Math.floor(now / DAY) * DAY;
  const t = days[days.length - 1];
  const lv = [...live.values()];
  return {
    now,
    live: {
      rooms_lobby: lv.filter((L) => L.status === "lobby").length,
      rooms_playing: lv.filter((L) => L.status === "playing").length,
      members_online: lv.reduce((a, L) => a + L.members.filter((m) => m.online).length, 0),
    },
    today: { rooms: t.rooms, matches: t.matches, players_active: t.players_active, new_players: players.filter((p) => p.first_seen >= todayStart).length },
    days,
    recent_events: events.filter((e) => e.level !== "info").sort((a, b) => b.at - a.at).slice(0, 10),
    maintenance: config.maintenance,
  };
}

function expel(L, memberId) {
  const k = L.members.findIndex((m) => m.id === memberId);
  if (k < 0) return false;
  const [mem] = L.members.splice(k, 1);
  if (L.match && L.status === "playing") {
    const seat = L.match.seats.find((s) => s.id === mem.id);
    if (seat) { seat.bot = true; seat.left = true; seat.online = false; L.match.state.players[seat.color] = "cpu"; }
  }
  if (L.host === mem.id && L.members.length) L.host = L.members[0].id;
  L.room.members = L.members.length;
  L.room.online = L.members.filter((m) => m.online).length;
  L.room.updated_at = Date.now();
  return true;
}

// ---------- API ----------
async function api(req, res, url) {
  if (LATENCY) await new Promise((r) => setTimeout(r, LATENCY + Math.random() * LATENCY));
  if (DISABLED) return fail(res, 503, "admin_disabled", "set ADMIN_PASSWORD");
  const ip = req.socket.remoteAddress || "127.0.0.1";
  const sub = url.pathname.slice("/admin/api/".length).split("/").filter(Boolean).map(decodeURIComponent);
  const m = req.method;
  const write = m !== "GET" && m !== "HEAD";

  if (sub[0] === "login" && m === "POST") {
    const now = Date.now();
    const att = (loginAttempts.get(ip) || []).filter((t) => now - t < 600e3);
    if (att.length >= 5) return fail(res, 429, "rate", "too many attempts");
    const body = await readBody(req);
    if (!body || body.password !== PASSWORD) {
      att.push(now);
      loginAttempts.set(ip, att);
      return fail(res, 401, "unauthorized", "wrong password");
    }
    loginAttempts.delete(ip);
    const tok = Math.floor(now / 1000 + 43200) + "." + crypto.randomBytes(16).toString("hex");
    sessions.add(tok);
    addAudit(now, ip, "login", null);
    return send(res, 204, null, { "Set-Cookie": `lz_admin=${tok}; HttpOnly; SameSite=Strict; Path=/admin; Max-Age=43200` });
  }
  const sess = cookieSession(req);
  if (sub[0] === "logout" && m === "POST") {
    if (sess) { sessions.delete(sess); addAudit(Date.now(), ip, "logout", null); }
    return send(res, 204, null, { "Set-Cookie": "lz_admin=; HttpOnly; SameSite=Strict; Path=/admin; Max-Age=0" });
  }
  if (!sess) return fail(res, 401, "unauthorized", "log in first");
  if (write && req.headers["x-admin"] !== "1") return fail(res, 403, "forbidden", "missing X-Admin header");
  const q = (k) => url.searchParams.get(k) || "";

  switch (sub[0]) {
    case "me": return send(res, 200, { ok: true });
    case "overview": return send(res, 200, overview());
    case "rooms": {
      for (const L of live.values()) { L.room.members = L.members.length; L.room.online = L.members.filter((x) => x.online).length; }
      if (!sub[1]) {
        const st = q("status");
        const qq = q("q").toLowerCase();
        let list = rooms.filter((r) => (!st || r.status === st) && (!qq || r.code.toLowerCase().startsWith(qq) || (r.host_name || "").toLowerCase().includes(qq)));
        list = list.sort((a, b) => b.created_at - a.created_at).map(pub);
        return send(res, 200, paginate(list, url));
      }
      const code = sub[1].toUpperCase();
      const r = rooms.find((x) => x.code === code);
      const L = live.get(code);
      if (!r && !L) return fail(res, 404, "not_found");
      if (!sub[2] && m === "GET") {
        const ms = matches.filter((x) => x.code === code).sort((a, b) => b.started_at - a.started_at).slice(0, 20).map(matchOut);
        return send(res, 200, { room: r ? pub(r) : null, live: snapshot(L), matches: ms, now: Date.now() });
      }
      if (sub[2] === "close" && m === "POST") {
        const body = await readBody(req);
        const reason = String(body?.reason || "").slice(0, 200);
        if (L?.match?._row && L.match._row.result === "playing") { L.match._row.result = "closed"; L.match._row.ended_at = Date.now(); L.match._row.actions = L.match.n; }
        live.delete(code);
        if (r) Object.assign(r, { status: "closed", members: 0, online: 0, closed_reason: "admin: " + (reason || "closed"), updated_at: Date.now() });
        addAudit(Date.now(), ip, "room.close", code, { reason, live: Boolean(L) });
        addEvent(Date.now(), "info", "room_closed", "closed by admin: " + reason, code);
        return send(res, 200, { ok: true, live: Boolean(L) });
      }
      if (sub[2] === "kick" && m === "POST") {
        const body = await readBody(req);
        const id = Number(body?.member_id);
        if (!Number.isInteger(id)) return fail(res, 400, "bad_input", "member_id must be an integer");
        if (!L || !expel(L, id)) return fail(res, 404, "not_found", "no such member");
        addAudit(Date.now(), ip, "room.kick", code, { member_id: id });
        return send(res, 200, { ok: true });
      }
      return fail(res, 405, "method");
    }
    case "players": {
      if (!sub[1]) {
        const qq = q("q").toLowerCase();
        const list = players.filter((p) => (!q("banned") || p.banned) && (!qq || p.name.toLowerCase().includes(qq) || p.pid.toLowerCase().startsWith(qq)))
          .sort((a, b) => b.last_seen - a.last_seen);
        return send(res, 200, paginate(list, url));
      }
      const p = byPid.get(sub[1]);
      if (!p) return fail(res, 404, "not_found");
      if (!sub[2] && m === "GET") {
        const ms = matches.filter((x) => x.players.some((pp) => pp.pid === p.pid)).sort((a, b) => b.started_at - a.started_at).slice(0, 20).map(matchOut);
        return send(res, 200, { player: p, matches: ms });
      }
      if (!sub[2] && m === "PATCH") {
        const body = await readBody(req);
        if (!body || typeof body.note !== "string" || body.note.length > 1000) return fail(res, 400, "bad_input", "note must be a string ≤ 1000 chars");
        p.note = body.note || null;
        addAudit(Date.now(), ip, "player.note", p.pid, { note: p.note });
        return send(res, 200, { ok: true, player: p });
      }
      if (sub[2] === "ban" && m === "POST") {
        const body = await readBody(req);
        const reason = String(body?.reason || "").slice(0, 200);
        p.banned = 1; p.ban_reason = reason || null;
        let kicked = false; let room = null;
        for (const L of live.values()) { const mem = L.members.find((x) => x.pid === p.pid); if (mem) { expel(L, mem.id); kicked = true; room = L.room.code; } }
        addAudit(Date.now(), ip, "player.ban", p.pid, { reason, kicked, room });
        return send(res, 200, { ok: true, kicked, player: p });
      }
      if (sub[2] === "unban" && m === "POST") {
        p.banned = 0; p.ban_reason = null;
        addAudit(Date.now(), ip, "player.unban", p.pid);
        return send(res, 200, { ok: true, player: p });
      }
      return fail(res, 405, "method");
    }
    case "matches": {
      const code = q("code").toUpperCase(); const pid = q("pid"); const result = q("result");
      const list = matches.filter((x) => (!code || x.code === code) && (!pid || x.players.some((pp) => pp.pid === pid)) && (!result || x.result === result))
        .sort((a, b) => b.started_at - a.started_at).map(matchOut);
      return send(res, 200, paginate(list, url));
    }
    case "events": {
      const level = q("level"); const kind = q("kind");
      const list = events.filter((e) => (!level || e.level === level) && (!kind || e.kind === kind)).sort((a, b) => b.at - a.at);
      return send(res, 200, paginate(list, url));
    }
    case "config": {
      if (m === "GET") return send(res, 200, config);
      if (m === "PUT") {
        const body = await readBody(req);
        if (!body || typeof body !== "object") return fail(res, 400, "bad_input");
        const patch = {};
        if ("maintenance" in body) patch.maintenance = Boolean(body.maintenance);
        if ("motd" in body) {
          if (typeof body.motd !== "string" || body.motd.length > 140) return fail(res, 400, "bad_input", "motd must be ≤ 140 characters");
          patch.motd = body.motd;
        }
        for (const k of ["turn_roll_s", "turn_choose_s", "turn_pair_s"]) {
          if (!(k in body)) continue;
          const v = body[k];
          if (!Number.isInteger(v) || v < 5 || v > 120) return fail(res, 400, "bad_input", k + " must be an integer 5–120");
          patch[k] = v;
        }
        Object.assign(config, patch);
        if (Object.keys(patch).length) addAudit(Date.now(), ip, "config.update", null, patch);
        return send(res, 200, config);
      }
      return fail(res, 405, "method");
    }
    case "audit": return send(res, 200, paginate(audit.slice().sort((a, b) => b.at - a.at), url));
    default: return fail(res, 404, "not_found");
  }
}

// ---------- static ----------
const MIME = { ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8", ".mjs": "text/javascript; charset=utf-8", ".css": "text/css; charset=utf-8", ".svg": "image/svg+xml", ".woff2": "font/woff2", ".png": "image/png", ".json": "application/json" };
// frame-ancestors is 'self' only so the dev page can be framed at tablet width for checks; the Worker should send 'none'.
const CSP = "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; font-src 'self'; connect-src 'self'; frame-ancestors 'self'; base-uri 'none'; form-action 'self'";

function serveStatic(req, res, url) {
  let rel = url.pathname === "/admin" || url.pathname === "/admin/" ? "index.html" : url.pathname.slice("/admin/".length);
  let file;
  try { file = path.resolve(ADMIN_DIR, decodeURIComponent(rel)); } catch { return fail(res, 400, "bad_path"); }
  if (!file.startsWith(ADMIN_DIR + path.sep) || rel.startsWith("dev/")) return fail(res, 404, "not_found");
  fs.stat(file, (err, st) => {
    if (err || !st.isFile()) { res.writeHead(404, { "Content-Type": "text/plain" }); res.end("not found"); return; }
    res.writeHead(200, {
      "Content-Type": MIME[path.extname(file)] || "application/octet-stream",
      "Cache-Control": "no-cache",
      "Content-Security-Policy": CSP,
      "X-Content-Type-Options": "nosniff",
      "Referrer-Policy": "same-origin",
    });
    fs.createReadStream(file).pipe(res);
  });
}

http.createServer((req, res) => {
  const url = new URL(req.url, "http://localhost");
  if (url.pathname.startsWith("/admin/api/")) {
    api(req, res, url).catch((e) => { console.error(e); fail(res, 500, "internal"); });
    return;
  }
  if (url.pathname === "/" ) { res.writeHead(302, { Location: "/admin/" }); res.end(); return; }
  if (url.pathname === "/admin" || url.pathname.startsWith("/admin/")) return serveStatic(req, res, url);
  res.writeHead(404); res.end("not found");
}).listen(PORT, () => {
  console.log(`Ludo Zing admin mock: http://localhost:${PORT}/admin  (password "${PASSWORD}")${DISABLED ? "  [admin disabled]" : ""}`);
  console.log(`live rooms: ${liveRooms.map((r) => r.code).join(", ")}`);
});
