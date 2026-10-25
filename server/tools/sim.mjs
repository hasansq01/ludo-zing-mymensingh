#!/usr/bin/env node
// End-to-end room simulation against a running server (default: `npx wrangler dev --port 8787` in server/).
// Creates a room, connects N clients, starts a match and plays it to `over`. Every client keeps a deterministic
// replica (the server's TypeScript rules, bundled on the fly with esbuild) and checks the server hash after every
// action, exactly as the Godot client does. Optionally one client drops mid-game (a bot takes over after the 20 s
// grace) and rejoins with its token later.
//
//   node tools/sim.mjs [--url ws://localhost:8787] [--game ludo|sl] [--players 2] [--teams] [--pair-ask]
//                      [--delay 120] [--drop <client#> --drop-at <actions> --rejoin-after <ms>] [--quiet]
//   node tools/sim.mjs --quick <humans> [--game ludo|sl] [--players 2|4] [--stagger 1500] ...
//
// --game sl plays Snakes & Ladders (the host sends settings {game: "sl"}).
// --quick N: N simulated people get guest sessions (POST /v1/auth/guest), queue on /v1/quick/ws (one every
// --stagger ms), and play the quick match(es) they are put in. Reports each one's wait, the room, the seats that are
// not one of ours (ghosts: clients can't tell, by design) and the winner. Needs the accounts (SESSION_KEY set).
//
// Exit code 0 when the game reached `over` with no hash mismatch, no unexpected error and no order error.
import { build } from "esbuild";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const serverDir = resolve(dirname(fileURLToPath(import.meta.url)), "..");

// ---------- args ----------
const args = process.argv.slice(2);
function opt(name, def) {
  const k = args.indexOf(`--${name}`);
  if (k < 0) return def;
  const v = args[k + 1];
  return v === undefined || v.startsWith("--") ? true : v;
}
const WS = String(opt("url", "ws://localhost:8787")).replace(/\/$/, "");
const HTTP = WS.replace(/^ws/, "http");
const PLAYERS = Number(opt("players", 2));
const GAME = String(opt("game", "ludo"));
const QUICK = opt("quick", null) === null ? 0 : Number(opt("quick"));
const STAGGER = Number(opt("stagger", 1500));
const TEAMS = Boolean(opt("teams", false));
const PAIR_ASK = Boolean(opt("pair-ask", false));
const DELAY = Number(opt("delay", 120)); // ms before each of our actions (stays under the 20 msg/s rate limit)
const DROP = opt("drop", null) === null ? -1 : Number(opt("drop"));
const DROP_AT = Number(opt("drop-at", 20));
const REJOIN_AFTER = Number(opt("rejoin-after", 25_000));
const QUIET = Boolean(opt("quiet", false));
const TIMEOUT = Number(opt("timeout", 15 * 60_000));

if (!(PLAYERS >= 2 && PLAYERS <= 4)) throw new Error("--players 2..4");
if (GAME !== "ludo" && GAME !== "sl") throw new Error("--game ludo|sl");
if (QUICK && !(PLAYERS === 2 || PLAYERS === 4)) throw new Error("--quick needs --players 2 or 4");
if (TEAMS && PLAYERS !== 4) throw new Error("--teams needs --players 4");

// ---------- the rules, bundled from src/rules ----------
const bundle = await build({
  stdin: {
    contents:
      'export * from "./src/rules/ludo.ts"; export { stateHash } from "./src/rules/hash.ts";' +
      'export { applySlAction, turnColor as slTurnColor } from "./src/rules/sl.ts"; export { slStateHash } from "./src/rules/sl_hash.ts";',
    resolveDir: serverDir,
    loader: "ts",
  },
  bundle: true,
  format: "esm",
  platform: "neutral",
  write: false,
  logLevel: "silent",
});
const R = await import("data:text/javascript;base64," + Buffer.from(bundle.outputFiles[0].text).toString("base64"));

const COLORS = ["Red", "Green", "Yellow", "Blue"];
const ordinal = (n) => `${n}${["th", "st", "nd", "rd"][n % 100 >= 11 && n % 100 <= 13 ? 0 : Math.min(n % 10, 4) % 4] ?? "th"}`;
const t0 = Date.now();
const log = (...a) => QUIET || console.log(`[${((Date.now() - t0) / 1000).toFixed(1).padStart(6)}s]`, ...a);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const pid = () => "sim-" + Math.random().toString(36).slice(2) + Math.random().toString(36).slice(2);

// ---------- a client ----------
class SimClient {
  constructor(no, code, opts = {}) {
    this.no = no;
    this.code = code;
    this.pid = opts.pid ?? pid();
    this.session = opts.session;
    this.name = opts.name ?? `Sim${no + 1}`;
    this.token = opts.token;
    this.game = "ludo";
    this.id = -1;
    this.state = null;
    this.n = 0;
    this.seats = [];
    this.stats = { acts: 0, mismatches: 0, orderErrors: 0, errors: {}, syncs: 0 };
    this.over = null;
    this.dropped = false;
    this.listeners = [];
    this.history = [];
    this.finishes = []; // play on: {c, place, n} for every side that finished, in order
  }

  get color() {
    const s = this.seats.find((x) => x.id === this.id);
    return s ? s.color : -1;
  }

  connect() {
    return new Promise((res, rej) => {
      const ws = new WebSocket(`${WS}/v1/rooms/${this.code}/ws`);
      this.ws = ws;
      ws.onopen = () => {
        ws.send(
          JSON.stringify({ t: "hello", v: 1, pid: this.pid, name: this.name, avatar: "", frame: "", token: this.token, session: this.session }),
        );
      };
      ws.onerror = (e) => rej(new Error(`ws error ${e.message ?? ""}`));
      ws.onclose = (e) => {
        if (!this.dropped && !this.over) log(`${this.name}: socket closed ${e.code} ${e.reason}`);
      };
      ws.onmessage = (ev) => {
        const m = JSON.parse(ev.data);
        if (m.t === "welcome") {
          this.id = m.id;
          this.token = m.token;
          res();
        }
        this.onMessage(m);
      };
    });
  }

  send(o) {
    if (this.ws?.readyState === WebSocket.OPEN) this.ws.send(JSON.stringify(o));
  }

  /** The next message matching pred (with past: also the latest one already received). */
  waitFor(pred, ms = 30_000, past = false) {
    if (past) {
      const m = this.history.findLast(pred);
      if (m) return Promise.resolve(m);
    }
    return new Promise((res, rej) => {
      const t = setTimeout(() => rej(new Error(`${this.name}: timed out waiting`)), ms);
      this.listeners.push((m) => {
        if (!pred(m)) return false;
        clearTimeout(t);
        res(m);
        return true;
      });
    });
  }

  onMessage(m) {
    this.history.push(m);
    if (this.history.length > 200) this.history.shift();
    this.listeners = this.listeners.filter((f) => !f(m));
    switch (m.t) {
      case "start":
      case "sync":
        this.game = m.game ?? "ludo";
        this.state = structuredClone(m.state);
        this.n = m.n;
        this.seats = m.seats;
        if (m.t === "sync") this.stats.syncs++;
        if (this.hash() !== m.h) this.stats.mismatches++;
        break;
      case "act": {
        if (!this.state) break;
        if (m.n !== this.n) {
          this.stats.orderErrors++;
          this.send({ t: "sync_req" });
          break;
        }
        const ev = this.game === "sl" ? R.applySlAction(this.state, m.a) : R.applyAction(this.state, m.a);
        this.n = m.n + 1;
        this.stats.acts++;
        // play on: every side's finish (the match goes on until the places are decided)
        for (const e of ev) {
          if (e.type !== "finished") continue;
          this.finishes.push({ c: e.c, place: e.place, n: m.n });
          if (this.no === 0) log(`${COLORS[e.c]}${e.team ? ` + ${COLORS[(e.c + 2) % 4]}` : ""} finished ${ordinal(e.place)} (act ${m.n})`);
        }
        if (m.a.k === "end" && this.no === 0) log(`the server ended the match ({k: "end"}): the rest ranked by progress`);
        if (this.hash() !== m.h) {
          this.stats.mismatches++;
          this.send({ t: "sync_req" });
        }
        if (m.a.k === "mode") log(`${COLORS[m.a.c]} is now ${m.a.mode === "cpu" ? "a bot" : "human again"}`);
        if (this.no === DROP && !this.dropped && this.n >= DROP_AT && this.n < DROP_AT + 1 && !this.over) this.drop();
        break;
      }
      case "turn":
        this.maybePlay(m.c);
        break;
      case "over":
        this.over = m;
        break;
      case "error":
        this.stats.errors[m.code] = (this.stats.errors[m.code] ?? 0) + 1;
        if (m.code !== "stale") log(`${this.name}: error ${m.code} ${m.msg}`);
        break;
    }
  }

  hash() {
    return this.game === "sl" ? R.slStateHash(this.state) : R.stateHash(this.state);
  }

  async maybePlay(c) {
    const s = this.state;
    if (!s || this.dropped || c !== this.color) return;
    if (this.game === "sl") {
      const me = s.players.find((p) => p.c === c);
      if (!me || me.cpu || R.slTurnColor(s) !== c) return;
      const n = this.n;
      await sleep(DELAY);
      if (this.n === n && this.state.phase === "roll") this.send({ t: "roll", n });
      return;
    }
    if (s.players[c] !== "human") return;
    const n = this.n;
    await sleep(DELAY);
    if (this.n !== n || this.state.turn !== c) return;
    if (s.phase === "roll") this.send({ t: "roll", n });
    else if (s.phase === "choose") {
      const us = R.units(s);
      // half the time the bot's choice, else a random unit
      const i = Math.random() < 0.5 ? R.pickAi(s, R.movables(s), null, "normal") : us[Math.floor(Math.random() * us.length)].token;
      this.send({ t: "move", n, i });
    } else if (s.phase === "pair_ask") this.send({ t: "pair", n, yes: Math.random() < 0.7 });
  }

  drop() {
    this.dropped = true;
    log(`${this.name} (${COLORS[this.color]}) drops; rejoins in ${REJOIN_AFTER} ms`);
    this.ws.close(1000, "sim drop");
    setTimeout(async () => {
      if (this.over) return;
      this.dropped = false;
      await this.connect();
      log(`${this.name} rejoined with its token`);
    }, REJOIN_AFTER);
  }
}

// ---------- run ----------
async function main() {
  const res = await fetch(`${HTTP}/v1/rooms`, { method: "POST" });
  if (!res.ok) throw new Error(`POST /v1/rooms: ${res.status}`);
  const { code } = await res.json();
  log(`room ${code} at ${WS}`);

  const cs = [];
  for (let k = 0; k < PLAYERS; k++) {
    const c = new SimClient(k, code);
    await c.connect();
    cs.push(c);
  }
  await cs[0].waitFor((m) => m.t === "lobby" && m.members.length === PLAYERS, 30_000, true);
  if (GAME === "sl") {
    cs[0].send({ t: "settings", game: "sl" });
    await cs[0].waitFor((m) => m.t === "lobby" && m.settings.game === "sl", 10_000, true);
  }
  if (TEAMS || PAIR_ASK) {
    cs[0].send({ t: "settings", teams: TEAMS, pair_ask: PAIR_ASK });
    await cs[0].waitFor((m) => m.t === "lobby" && m.settings.teams === TEAMS && m.settings.pair_ask === PAIR_ASK);
  }
  const info = await (await fetch(`${HTTP}/v1/rooms/${code}`)).json();
  log(`lobby full: ${JSON.stringify(info)}`);
  const started = cs.map((c) => c.waitFor((m) => m.t === "start"));
  cs[0].send({ t: "start" });
  const [st] = await Promise.all(started);
  log(`start (${st.game ?? "ludo"}): ${st.seats.map((s) => `${COLORS[s.color]}=${s.name}`).join(", ")}${TEAMS ? " (teams)" : ""}`);

  const overs = await Promise.race([
    // (a client that dropped may still be away when the game ends)
    Promise.all(cs.filter((c) => c.no !== DROP).map((c) => c.waitFor((m) => m.t === "over", TIMEOUT))),
    sleep(TIMEOUT).then(() => {
      throw new Error("game did not finish");
    }),
  ]);
  const over = overs[0];
  for (const c of cs) c.ws.close(1000, "done");

  const ref = cs.find((c) => !c.dropped) ?? cs[0];
  const hashes = new Set(cs.filter((c) => c.over).map((c) => c.hash()));
  console.log("\n=== summary ===");
  console.log(`room        ${code}`);
  console.log(`actions     ${ref.n}`);
  console.log(`duration    ${((Date.now() - t0) / 1000).toFixed(1)} s`);
  console.log(`game        ${ref.game}`);
  console.log(`winner      ${over.winner >= 0 ? COLORS[over.winner] : "-"}${TEAMS ? ` (team ${R.winners(ref.state).map((c) => COLORS[c]).join(" + ")})` : ""}`);
  console.log(`finished    ${over.finished.map((c) => COLORS[c]).join(", ")}`);
  console.log(`finishes   ${ref.finishes.length} before over: ${ref.finishes.map((f) => `${COLORS[f.c]} ${ordinal(f.place)} @${f.n}`).join(", ") || "-"} (over after act ${ref.n - 1})`);
  console.log(`standings   ${over.standings.map((s) => `${s.place}. ${COLORS[s.color]}`).join("  ")}`);
  console.log(`final hash  ${[...hashes].join(" ")} (${hashes.size === 1 ? "all replicas agree" : "REPLICAS DIFFER"})`);
  let bad = hashes.size !== 1;
  for (const c of cs) {
    const errs = Object.entries(c.stats.errors).map(([k, v]) => `${k}x${v}`).join(" ") || "none";
    console.log(
      `${c.name.padEnd(6)} ${COLORS[c.color].padEnd(6)} acts ${String(c.stats.acts).padStart(4)}  mismatches ${c.stats.mismatches}  order ${c.stats.orderErrors}  syncs ${c.stats.syncs}  errors ${errs}`,
    );
    const unexpected = Object.keys(c.stats.errors).filter((k) => k !== "stale");
    if (c.stats.mismatches || c.stats.orderErrors || unexpected.length) bad = true;
  }
  console.log(bad ? "RESULT: FAIL" : "RESULT: OK");
  process.exit(bad ? 1 : 0);
}

// ---------- quick match ----------

/** A guest session for a fresh pid. */
async function guestSession() {
  const p = pid();
  const res = await fetch(`${HTTP}/v1/auth/guest`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ pid: p }) });
  if (!res.ok) throw new Error(`POST /v1/auth/guest: ${res.status} ${await res.text()} (quick match needs accounts: SESSION_KEY)`);
  const b = await res.json();
  return { pid: p, session: b.session, account: b.account.id };
}

/** Queues once; resolves with {code, token, waitMs, positions}. */
function queueOnce(no, g) {
  return new Promise((res, rej) => {
    const t = Date.now();
    const positions = [];
    const ws = new WebSocket(`${WS}/v1/quick/ws?game=${GAME}&players=${PLAYERS}`);
    ws.onopen = () => ws.send(JSON.stringify({ t: "hello", v: 1, session: g.session, pid: g.pid, name: `Sim${no + 1}`, avatar: "pawn-red", frame: "classic" }));
    ws.onerror = (e) => rej(new Error(`queue ws error ${e.message ?? ""}`));
    ws.onmessage = (ev) => {
      const m = JSON.parse(ev.data);
      if (m.t === "queued") {
        positions.push(m.position);
        log(`Sim${no + 1}: queued, position ${m.position}, eta ${m.eta_s} s`);
      } else if (m.t === "matched") res({ code: m.code, token: m.token, waitMs: Date.now() - t, positions });
      else if (m.t === "error") rej(new Error(`Sim${no + 1}: queue error ${m.code} ${m.msg}`));
    };
  });
}

async function quickMain() {
  log(`quick match: ${QUICK} people, ${GAME} for ${PLAYERS}, one every ${STAGGER} ms, at ${WS}`);
  const guests = [];
  for (let k = 0; k < QUICK; k++) guests.push(await guestSession());
  const results = [];
  const runs = guests.map(async (g, k) => {
    await sleep(k * STAGGER);
    const q = await queueOnce(k, g);
    log(`Sim${k + 1}: matched into ${q.code} after ${(q.waitMs / 1000).toFixed(1)} s`);
    const c = new SimClient(k, q.code, { pid: g.pid, session: g.session, token: q.token, name: `Sim${k + 1}` });
    await c.connect();
    const st = await c.waitFor((m) => m.t === "start", 30_000, true);
    const over = await c.waitFor((m) => m.t === "over", TIMEOUT, true);
    c.ws.close(1000, "done");
    results.push({ k, c, q, st, over });
  });
  await Promise.all(runs);
  console.log("\n=== quick match summary ===");
  let bad = false;
  const rooms = new Map();
  for (const r of results.sort((a, b) => a.k - b.k)) {
    if (!rooms.has(r.q.code)) rooms.set(r.q.code, []);
    rooms.get(r.q.code).push(r);
  }
  for (const [code, rs] of rooms) {
    const st = rs[0].st;
    const ours = new Set(rs.map((r) => r.c.id));
    const others = st.seats.filter((s) => !ours.has(s.id));
    const over = rs[0].over;
    const winSeat = st.seats.find((s) => s.color === over.winner);
    console.log(`room ${code} (${st.game}): ${st.seats.map((s) => `${COLORS[s.color]}=${s.name} L${s.level}`).join(", ")}`);
    console.log(`  ours ${rs.map((r) => `Sim${r.k + 1}`).join(", ")}; other seats ${others.length} (ghosts, unless other people queued): ${others.map((s) => s.name).join(", ") || "-"}`);
    console.log(`  waits ${rs.map((r) => `${(r.q.waitMs / 1000).toFixed(1)} s`).join(", ")}`);
    console.log(`  winner ${winSeat ? `${COLORS[winSeat.color]} ${winSeat.name}${ours.has(winSeat.id) ? " (one of ours)" : ""}` : "-"}`);
    const hashes = new Set(rs.map((r) => r.c.hash()));
    if (hashes.size !== 1) bad = true;
    for (const r of rs) {
      const unexpected = Object.keys(r.c.stats.errors).filter((x) => x !== "stale");
      if (r.c.stats.mismatches || r.c.stats.orderErrors || unexpected.length) bad = true;
    }
  }
  const waits = results.map((r) => r.q.waitMs);
  console.log(`waits       min ${(Math.min(...waits) / 1000).toFixed(1)} s, max ${(Math.max(...waits) / 1000).toFixed(1)} s, mean ${(waits.reduce((a, b) => a + b, 0) / waits.length / 1000).toFixed(1)} s`);
  console.log(bad ? "RESULT: FAIL" : "RESULT: OK");
  process.exit(bad ? 1 : 0);
}

(QUICK ? quickMain() : main()).catch((e) => {
  console.error(e);
  process.exit(2);
});
