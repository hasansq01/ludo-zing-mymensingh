#!/usr/bin/env node
// Dev mock of the admin API (server/ADMIN_API.md) + static server for the console. No dependencies.
//
//   node server/admin/dev/mock-server.mjs            → http://localhost:8790/admin  (password: dev)
//   PORT=9000 node server/admin/dev/mock-server.mjs
//   MOCK_DISABLED=1 …   every /admin/api call answers 503 admin_disabled (no ADMIN_PASSWORD)
//   MOCK_LATENCY=400 …  extra latency per API call (ms), to see skeletons
//
// Data is fake and in memory (seeded, so it's the same on every start). Three rooms play live matches whose
// state advances on a timer, so the room page's board animates; a fourth is paused (a match in progress with
// nobody connected: its bots wait, like the real Room DO).

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
    return { color, id: m.id, name: m.name, avatar: m.avatar, frame: m.frame, bot: false, online: m.online, pid: m.pid, left: false, ghost: m.ghost || undefined };
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
  m.players = seats.map((s) => ({ pid: s.ghost ? null : s.pid, name: s.name, color: s.color, bot: false, ghost: s.ghost || undefined }));
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

// one paused room: a match in progress, everyone disconnected (all seats bots now; nothing moves until someone is back)
{
  const r = addRoom("playing", NOW0 - 33 * 60e3, 2);
  const L = liveFromRoom(r, true);
  for (const m of L.members) m.online = false;
  for (const st of L.match.seats) { st.online = false; st.bot = true; L.match.state.players[st.color] = "cpu"; }
  L.match.deadline = 0;
  r.online = 0;
  r.updated_at = NOW0 - 4 * 60e3;
}

const anyOnline = (L) => L.members.some((m) => m.online);

setInterval(() => {
  const now = Date.now();
  for (const L of live.values()) {
    if (L.match && L.status === "playing" && L.match.deadline && now >= L.match.deadline && anyOnline(L)) step(L);
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

// ---------- v2: accounts, ledger, claims, leaderboards, quick match (ADMIN_API.md "v2") ----------
const B32 = "abcdefghijklmnopqrstuvwxyz234567";
const ACC_RE = /^acc_[a-z2-7]{16}$/;
const LEDGER_REASONS = ["daily", "spin", "free", "buy", "achievement", "claim", "match"];
const levelOf = (xp) => 1 + Math.floor(Math.sqrt(Math.max(0, xp) / 40));

const accounts = [];
const accById = new Map();
const ledgerOf = new Map();
const claimsOf = new Map();
const grantsOf = new Map();
const devicesOf = new Map();
let ledgerId = 1;

for (let k = 0; k < 52; k++) {
  const p = players[k];
  const id = "acc_" + randStr(16, B32);
  const created = p.first_seen;
  const linked = k % 3 === 0;
  const acc = {
    id, created_at: created, last_seen: p.last_seen, google_player_id: linked ? "g" + ri(1e8, 9e8) + ri(1e8, 9e8) : null,
    google_name: linked ? p.name + " Google" : null, public_id: "LZM-" + randStr(4, "ABCDEFGHJKLMNPQRSTUVWXYZ23456789") + "-" + randStr(4, "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"),
    name: p.name, avatar: p.avatar, frame: p.frame, plate: "", badge: "", coins: 0, xp: 0, online_wins: 0, completed_matches: 0,
    stats: { wins: ri(0, 20), games: ri(0, 60), coinsEarned: ri(5000, 90000) }, owned: { rooms: ["classic"], dice_owned: ["bone"], scenes: [], av_owned: [p.avatar || "pawn-red"] },
    equipped: { room: "classic", dice: "bone", scene: "" }, rewards: { daily: ri(0, 6), last_spin: created, last_free: created }, achievements: { claimed: [] },
    banned: 0, ban_reason: null, ban_source: null, note: null, merged_into: null, imported: k % 7 === 0 ? 1 : 0, version: ri(3, 140),
    _xpWeek: 0, _winsWeek: 0,
  };
  accounts.push(acc);
  accById.set(id, acc);
  devicesOf.set(id, [{ pid: p.pid, account_id: id, first_seen: created, last_seen: p.last_seen }]);
  if (k % 5 === 0 && players[52 + k / 5]) {
    const q = players[52 + k / 5];
    devicesOf.get(id).push({ pid: q.pid, account_id: id, first_seen: q.first_seen, last_seen: q.last_seen });
  }
  // ledger: the first 5,000, then a mix; sum = coins
  const rows = [{ id: ledgerId++, account_id: id, at: created, delta_coins: 5000, delta_xp: 0, reason: "start", ref: null, balance_after: 5000 }];
  let bal = 5000;
  let xp = 0;
  const n = ri(8, k % 4 === 0 ? 70 : 34);
  for (let i = 0; i < n; i++) {
    const reason = pick(LEDGER_REASONS);
    let dc = reason === "buy" ? -ri(2, 40) * 50 : reason === "match" ? ri(1, 8) * 50 : reason === "spin" ? ri(1, 10) * 100 : reason === "achievement" ? ri(2, 10) * 100 : ri(1, 5) * 100;
    if (bal + dc < 0) dc = 100;
    const dx = reason === "match" ? ri(20, 120) : reason === "achievement" ? ri(30, 90) : reason === "daily" ? 10 : 0;
    bal += dc; xp += dx;
    const at = created + Math.floor(((i + 1) / (n + 1)) * Math.max(3600e3, acc.last_seen - created));
    rows.push({ id: ledgerId++, account_id: id, at, delta_coins: dc, delta_xp: dx, reason, ref: reason === "match" ? "m" + ri(1000, 9999) : reason === "buy" ? pick(["dice:gold", "room:night", "avatar:robot"]) : reason === "achievement" ? pick(["first_win", "ten_games", "streak_3"]) : null, balance_after: bal });
  }
  acc.coins = bal; acc.xp = xp; acc.level = levelOf(xp);
  acc.online_wins = ri(0, 30); acc.completed_matches = k % 9 === 4 ? ri(0, 2) : ri(3, 80);
  acc._xpWeek = Math.floor(xp * rnd() * 0.3); acc._winsWeek = Math.floor(acc.online_wins * rnd() * 0.4);
  ledgerOf.set(id, rows);
  const grants = rows.filter((r) => r.reason === "match").slice(-20).map((r, i) => ({ match_id: "ln_" + r.ref + "_" + i, account_id: id, at: r.at, game: i % 4 ? "ludo" : "sl", outcome: pick(["win", "finish", "finish", "loss"]), coins: r.delta_coins, xp: r.delta_xp }));
  grantsOf.set(id, grants);
  const claims = [];
  const nc = ri(2, k % 6 === 0 ? 24 : 9);
  for (let i = 0; i < nc; i++) {
    const limited = k % 6 === 0 && i % 4 === 1 ? 1 : 0;
    const at = acc.last_seen - i * ri(5, 90) * 60e3;
    claims.push({ id: "clm_" + randStr(10), at, game: pick(["ludo", "sl"]), mode: pick(["online", "cpu", "pass"]), coins: limited ? 0 : ri(1, 6) * 50, xp: limited ? 0 : ri(10, 80), granted: limited ? 0 : 1, limited, reason: limited ? "daily limit" : null, payload: { outcome: pick(["win", "finish"]), players: ri(2, 4), turns: ri(60, 300), seed: randStr(6) } });
  }
  claimsOf.set(id, claims);
}
// moderation states: account 12 banned from the Accounts page, account 40's mirrors a pid ban
const accOfPid = new Map();
for (const [id, ds] of devicesOf) for (const d of ds) accOfPid.set(d.pid, accounts.find((a) => a.id === id));
Object.assign(accounts[12], { banned: 1, ban_reason: "Abusive name, 3 reports", ban_source: "admin_account" });
Object.assign(accounts[40], { banned: 1, ban_reason: "XSS attempt in the display name", ban_source: "pid:" + players[40].pid });
accounts[3].note = "Tester from the Mymensingh club. Reports bugs on WhatsApp.";
const pidBanSource = new Map([[players[12].pid, "admin_account"], [players[40].pid, "admin_pid"]]);
for (const p of players) { /* players.ban_source lives in this map */ if (p.banned && !pidBanSource.has(p.pid)) pidBanSource.set(p.pid, "admin_pid"); }
pidBanSource.set(players[12].pid, "account:" + accounts[12].id);

// ghosts show in the console only: a couple of past matches, one live seat
{
  let g = 0;
  for (const m of matches) {
    if (m.players.filter((x) => !x.bot).length >= 2 && ++g % 6 === 0) {
      const last = m.players.filter((x) => !x.bot).slice(-1)[0];
      last.ghost = true; last.pid = null; last.account_id = null;
      m.quick = 1; m.ghosts = 1; m.game = "ludo";
    }
  }
  const L = live.get(liveRooms[1].code);
  if (L) {
    const mem = L.members[1];
    mem.ghost = true; mem.pid = "";
    const seat = L.match.seats.find((s) => s.id === mem.id);
    seat.ghost = true; seat.pid = "";
    const row = L.match._row.players.find((x) => x.color === seat.color);
    row.ghost = true; row.pid = null;
    L.room.quick = 1;
  }
}

// quick_stats: 90 days, games ludo / sl, sizes 2 and 4
const quickRows = [];
for (let d = 0; d < 90; d++) {
  const day = new Date(Math.floor((NOW0 - d * DAY) / DAY) * DAY).toISOString().slice(0, 10);
  for (const game of ["ludo", "sl"]) for (const size of [2, 4]) {
    if (game === "sl" && size === 4 && d % 3) continue;
    const scale = (game === "ludo" ? 1 : 0.5) * (size === 2 ? 1 : 0.6) * (d === 0 ? 0.5 : 1) * (d > 60 ? 0.3 : 1);
    const queued = Math.round(ri(8, 60) * scale);
    if (!queued) continue;
    const matched = Math.max(0, queued - ri(0, Math.max(1, Math.round(queued * 0.25))));
    const ghost_filled = Math.round(matched * ri(15, 60) / 100 * (size === 4 ? 1.2 : 0.8));
    const finished = Math.round((matched + ghost_filled) / size * 0.8);
    const human_wins = Math.round(finished * ri(40, 70) / 100);
    quickRows.push({ day, game, size, queued, matched, ghost_filled, wait_ms_total: matched * ri(4000, 22000), human_wins, ghost_wins: finished - human_wins });
  }
}
const quickShape = (r) => {
  const seats = r.matched + r.ghost_filled;
  const fin = r.human_wins + r.ghost_wins;
  return { day: r.day, game: r.game, size: r.size, queued: r.queued, matched: r.matched, ghost_filled: r.ghost_filled,
    ghost_fill_rate: seats > 0 ? r.ghost_filled / seats : null, avg_wait_ms: r.matched > 0 ? Math.round(r.wait_ms_total / r.matched) : null,
    human_wins: r.human_wins, ghost_wins: r.ghost_wins, human_win_rate: fin > 0 ? r.human_wins / fin : null };
};
function quickReport(days) {
  const from = new Date(Math.floor((Date.now() - (days - 1) * DAY) / DAY) * DAY).toISOString().slice(0, 10);
  const rowsIn = quickRows.filter((r) => r.day >= from);
  const tot = new Map();
  for (const r of rowsIn) {
    const k = r.game + ":" + r.size;
    const t = tot.get(k) || { day: "total", game: r.game, size: r.size, queued: 0, matched: 0, ghost_filled: 0, wait_ms_total: 0, human_wins: 0, ghost_wins: 0 };
    for (const f of ["queued", "matched", "ghost_filled", "wait_ms_total", "human_wins", "ghost_wins"]) t[f] += r[f];
    tot.set(k, t);
  }
  return { days, from, rows: rowsIn.map(quickShape), totals: [...tot.values()].map(quickShape) };
}

const isoWeek = (t) => {
  const d = new Date(t);
  d.setUTCHours(0, 0, 0, 0);
  d.setUTCDate(d.getUTCDate() + 4 - (d.getUTCDay() || 7));
  const y = d.getUTCFullYear();
  const w = Math.ceil(((d - Date.UTC(y, 0, 1)) / DAY + 1) / 7);
  return y + "-W" + String(w).padStart(2, "0");
};
const accountOut = (a) => { const { _xpWeek, _winsWeek, ...r } = a; return { ...r, level: levelOf(a.xp), linked: a.google_player_id !== null }; };
function addLedger(a, delta, reason, ref) {
  a.coins += delta;
  const row = { id: ledgerId++, account_id: a.id, at: Date.now(), delta_coins: delta, delta_xp: 0, reason, ref, balance_after: a.coins };
  ledgerOf.get(a.id).push(row);
  a.version++;
}

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

const isPaused = (r) => r.status === "playing" && !(r.online > 0);
const pub = (r) => { const { _members, ...rest } = r; return { ...rest, paused: isPaused(r) }; };
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
    paused: L.status === "playing" && !anyOnline(L),
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
      rooms_playing: lv.filter((L) => L.status === "playing" && anyOnline(L)).length,
      rooms_paused: lv.filter((L) => L.status === "playing" && !anyOnline(L)).length,
      members_online: lv.reduce((a, L) => a + L.members.filter((m) => m.online).length, 0),
    },
    today: { rooms: t.rooms, matches: t.matches, players_active: t.players_active, new_players: players.filter((p) => p.first_seen >= todayStart).length },
    days,
    recent_events: events.filter((e) => e.level !== "info").sort((a, b) => b.at - a.at).slice(0, 10),
    maintenance: config.maintenance,
    accounts: {
      total: accounts.length, linked: accounts.filter((a) => a.google_player_id).length, guests: accounts.filter((a) => !a.google_player_id).length,
      banned: accounts.filter((a) => a.banned).length, new_today: accounts.filter((a) => a.created_at >= todayStart).length,
      coins_in_circulation: accounts.reduce((t, a) => t + a.coins, 0),
      claims_limited_today: [...claimsOf.values()].flat().filter((c) => c.limited && c.at >= todayStart).length + 2,
    },
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
        const okStatus = (r) => !st || (st === "paused" ? isPaused(r) : st === "playing" ? r.status === "playing" && !isPaused(r) : r.status === st);
        let list = rooms.filter((r) => okStatus(r) && (!qq || r.code.toLowerCase().startsWith(qq) || (r.host_name || "").toLowerCase().includes(qq)));
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
        return send(res, 200, { player: { ...p, account_id: accOfPid.get(p.pid)?.id ?? null, ban_source: p.banned ? pidBanSource.get(p.pid) ?? null : null }, matches: ms });
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
        p.banned = 1; p.ban_reason = reason || null; pidBanSource.set(p.pid, "admin_pid");
        const pa = accOfPid.get(p.pid);
        if (pa && !pa.banned) Object.assign(pa, { banned: 1, ban_reason: reason || null, ban_source: "pid:" + p.pid });
        let kicked = false; let room = null;
        for (const L of live.values()) { const mem = L.members.find((x) => x.pid === p.pid); if (mem) { expel(L, mem.id); kicked = true; room = L.room.code; } }
        addAudit(Date.now(), ip, "player.ban", p.pid, { reason, kicked, room });
        return send(res, 200, { ok: true, kicked, player: p, account_id: pa?.id ?? null, account_banned: pa ? Boolean(pa.banned) : null });
      }
      if (sub[2] === "unban" && m === "POST") {
        p.banned = 0; p.ban_reason = null; pidBanSource.delete(p.pid);
        const ua = accOfPid.get(p.pid);
        if (ua && ua.banned && ua.ban_source === "pid:" + p.pid) Object.assign(ua, { banned: 0, ban_reason: null, ban_source: null });
        addAudit(Date.now(), ip, "player.unban", p.pid);
        return send(res, 200, { ok: true, player: p, account_id: ua?.id ?? null, account_banned: ua ? Boolean(ua.banned) : null });
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
    case "accounts": {
      if (!sub[1]) {
        const qq = q("q").toLowerCase();
        const list = accounts.filter((a) => (!q("banned") || (q("banned") === "1") === Boolean(a.banned)) && (!q("linked") || (q("linked") === "1") === Boolean(a.google_player_id))
          && (!qq || a.name.toLowerCase().includes(qq) || a.id.startsWith(qq) || a.google_player_id === q("q") || a.public_id === q("q").toUpperCase()
            || devicesOf.get(a.id).some((d) => d.pid.toLowerCase().startsWith(qq))))
          .sort((a, b) => b.last_seen - a.last_seen).map(accountOut);
        return send(res, 200, paginate(list, url));
      }
      const acc = ACC_RE.test(sub[1]) ? accById.get(sub[1]) : null;
      if (!acc) return fail(res, 404, "not_found");
      if (!sub[2] && m === "GET") {
        const devs = devicesOf.get(acc.id);
        const pids = new Set(devs.map((d) => d.pid));
        const ms = matches.filter((x) => x.players.some((pp) => pp.pid && pids.has(pp.pid))).sort((a, b) => b.started_at - a.started_at).slice(0, 20).map(matchOut);
        return send(res, 200, {
          now: Date.now(), account: accountOut(acc), devices: devs.slice().sort((a, b) => b.last_seen - a.last_seen),
          ledger: ledgerOf.get(acc.id).slice().reverse().slice(0, 50), claims: claimsOf.get(acc.id).slice(0, 50),
          grants: grantsOf.get(acc.id).slice().reverse().slice(0, 20), matches: ms,
        });
      }
      if (!sub[2] && m === "PATCH") {
        const body = await readBody(req);
        if (!body || !("note" in body) || (body.note !== null && typeof body.note !== "string") || (body.note || "").length > 500) return fail(res, 400, "bad_request", "note: string or null, at most 500 characters");
        acc.note = body.note || null;
        addAudit(Date.now(), ip, "account.note", acc.id, { note: acc.note });
        return send(res, 200, { ok: true, account: accountOut(acc) });
      }
      if (sub[2] === "coins" && m === "POST") {
        const body = await readBody(req);
        const d = body?.delta;
        const reason = typeof body?.reason === "string" ? body.reason.trim() : "";
        if (typeof d !== "number" || !Number.isInteger(d) || d === 0 || Math.abs(d) > 1e6) return fail(res, 400, "bad_request", "delta: a non-zero integer, at most 1000000 either way");
        if (reason.length < 3 || reason.length > 200) return fail(res, 400, "bad_request", "reason: 3-200 characters");
        if (acc.coins + d < 0) return send(res, 409, { error: "coins", msg: `the balance would go below 0 (it is ${acc.coins})`, coins: acc.coins });
        addLedger(acc, d, "admin", reason);
        addAudit(Date.now(), ip, "account.coins", acc.id, { delta: d, reason, balance: acc.coins });
        return send(res, 200, { ok: true, coins: acc.coins, account: accountOut(acc) });
      }
      if ((sub[2] === "ban" || sub[2] === "unban") && m === "POST") {
        const body = await readBody(req);
        const devs = devicesOf.get(acc.id).map((d) => byPid.get(d.pid)).filter(Boolean);
        if (sub[2] === "ban") {
          const reason = typeof body?.reason === "string" ? body.reason.trim() : "";
          if (reason.length < 3 || reason.length > 200) return fail(res, 400, "bad_request", "reason: 3-200 characters");
          Object.assign(acc, { banned: 1, ban_reason: reason, ban_source: "admin_account" });
          let kicked = 0;
          for (const p of devs) {
            if (!p.banned) { p.banned = 1; p.ban_reason = reason; pidBanSource.set(p.pid, "account:" + acc.id); }
            for (const L of live.values()) { const mem = L.members.find((x) => x.pid === p.pid); if (mem) { expel(L, mem.id); kicked++; } }
          }
          addAudit(Date.now(), ip, "account.ban", acc.id, { reason, kicked });
          return send(res, 200, { ok: true, kicked, account: accountOut(acc) });
        }
        Object.assign(acc, { banned: 0, ban_reason: null, ban_source: null });
        for (const p of players) if (p.banned && pidBanSource.get(p.pid) === "account:" + acc.id) { p.banned = 0; p.ban_reason = null; pidBanSource.delete(p.pid); }
        const still = devs.filter((p) => p.banned).map((p) => p.pid);
        addAudit(Date.now(), ip, "account.unban", acc.id, still.length ? { still_banned_pids: still } : undefined);
        return send(res, 200, { ok: true, account: accountOut(acc), still_banned_pids: still });
      }
      return fail(res, 405, "method");
    }
    case "leaderboards": {
      const board = q("board") === "wins" ? "wins" : "xp";
      const period = q("period") === "week" ? "week" : "all";
      const wk = q("week");
      if (wk && (period !== "week" || !/^\d{4}-W\d{2}$/.test(wk))) return fail(res, 400, "bad_request", "week: YYYY-Www, with period=week");
      const limit = Number(q("limit") || 50);
      if (!Number.isInteger(limit) || limit < 1 || limit > 200) return fail(res, 400, "bad_request", "limit: 1-200");
      const cur = isoWeek(Date.now());
      const weekKey = period === "week" ? wk || cur : null;
      const past = weekKey && weekKey !== cur;
      const val = (a) => (board === "xp" ? (period === "all" ? a.xp : past ? Math.floor(a._xpWeek * 0.7) : a._xpWeek) : period === "all" ? a.online_wins : past ? Math.floor(a._winsWeek * 0.7) : a._winsWeek);
      const pool = accounts.filter((a) => !a.banned && !a.merged_into && a.completed_matches >= 3 && val(a) > 0).sort((a, b) => val(b) - val(a) || a.id.localeCompare(b.id));
      const top = pool.slice(0, limit).map((a, i) => ({ rank: i + 1, account_id: a.id, name: a.name, avatar: a.avatar, frame: a.frame, level: levelOf(a.xp), value: val(a), updated_at: a.last_seen }));
      return send(res, 200, { board, period, week: weekKey, total: pool.length, top });
    }
    case "quick": {
      const d = q("days");
      const days = d === "" ? 14 : Number(d);
      if (!Number.isInteger(days) || days < 1 || days > 90) return fail(res, 400, "bad_request", "days: 1-90");
      return send(res, 200, quickReport(days));
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
