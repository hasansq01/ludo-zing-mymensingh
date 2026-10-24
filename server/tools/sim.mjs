#!/usr/bin/env node
// End-to-end room simulation against a running server (default: `npx wrangler dev --port 8787` in server/).
// Creates a room, connects N clients, starts a match and plays it to `over`. Every client keeps a deterministic
// replica (the server's TypeScript rules, bundled on the fly with esbuild) and checks the server hash after every
// action, exactly as the Godot client does. Optionally one client drops mid-game (a bot takes over after the 20 s
// grace) and rejoins with its token later.
//
//   node tools/sim.mjs [--url ws://localhost:8787] [--players 2] [--teams] [--pair-ask] [--delay 120]
//                      [--drop <client#> --drop-at <actions> --rejoin-after <ms>] [--quiet]
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
const TEAMS = Boolean(opt("teams", false));
const PAIR_ASK = Boolean(opt("pair-ask", false));
const DELAY = Number(opt("delay", 120)); // ms before each of our actions (stays under the 20 msg/s rate limit)
const DROP = opt("drop", null) === null ? -1 : Number(opt("drop"));
const DROP_AT = Number(opt("drop-at", 20));
const REJOIN_AFTER = Number(opt("rejoin-after", 25_000));
const QUIET = Boolean(opt("quiet", false));
const TIMEOUT = Number(opt("timeout", 15 * 60_000));

if (!(PLAYERS >= 2 && PLAYERS <= 4)) throw new Error("--players 2..4");
if (TEAMS && PLAYERS !== 4) throw new Error("--teams needs --players 4");

// ---------- the rules, bundled from src/rules ----------
const bundle = await build({
  stdin: {
    contents: 'export * from "./src/rules/ludo.ts"; export { stateHash } from "./src/rules/hash.ts";',
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
const t0 = Date.now();
const log = (...a) => QUIET || console.log(`[${((Date.now() - t0) / 1000).toFixed(1).padStart(6)}s]`, ...a);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const pid = () => "sim-" + Math.random().toString(36).slice(2) + Math.random().toString(36).slice(2);

// ---------- a client ----------
class SimClient {
  constructor(no, code) {
    this.no = no;
    this.code = code;
    this.pid = pid();
    this.name = `Sim${no + 1}`;
    this.token = undefined;
    this.id = -1;
    this.state = null;
    this.n = 0;
    this.seats = [];
    this.stats = { acts: 0, mismatches: 0, orderErrors: 0, errors: {}, syncs: 0 };
    this.over = null;
    this.dropped = false;
    this.listeners = [];
    this.history = [];
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
        ws.send(JSON.stringify({ t: "hello", v: 1, pid: this.pid, name: this.name, avatar: "", frame: "", token: this.token }));
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
        this.state = structuredClone(m.state);
        this.n = m.n;
        this.seats = m.seats;
        if (m.t === "sync") this.stats.syncs++;
        if (R.stateHash(this.state) !== m.h) this.stats.mismatches++;
        break;
      case "act": {
        if (!this.state) break;
        if (m.n !== this.n) {
          this.stats.orderErrors++;
          this.send({ t: "sync_req" });
          break;
        }
        R.applyAction(this.state, m.a);
        this.n = m.n + 1;
        this.stats.acts++;
        if (R.stateHash(this.state) !== m.h) {
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

  async maybePlay(c) {
    const s = this.state;
    if (!s || this.dropped || c !== this.color || s.players[c] !== "human") return;
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
  if (TEAMS || PAIR_ASK) {
    cs[0].send({ t: "settings", teams: TEAMS, pair_ask: PAIR_ASK });
    await cs[0].waitFor((m) => m.t === "lobby" && m.settings.teams === TEAMS && m.settings.pair_ask === PAIR_ASK);
  }
  const info = await (await fetch(`${HTTP}/v1/rooms/${code}`)).json();
  log(`lobby full: ${JSON.stringify(info)}`);
  const started = cs.map((c) => c.waitFor((m) => m.t === "start"));
  cs[0].send({ t: "start" });
  const [st] = await Promise.all(started);
  log(`start: ${st.seats.map((s) => `${COLORS[s.color]}=${s.name}`).join(", ")}${TEAMS ? " (teams)" : ""}`);

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
  const hashes = new Set(cs.filter((c) => c.over).map((c) => R.stateHash(c.state)));
  console.log("\n=== summary ===");
  console.log(`room        ${code}`);
  console.log(`actions     ${ref.n}`);
  console.log(`duration    ${((Date.now() - t0) / 1000).toFixed(1)} s`);
  console.log(`winner      ${over.winner >= 0 ? COLORS[over.winner] : "-"}${TEAMS ? ` (team ${R.winners(ref.state).map((c) => COLORS[c]).join(" + ")})` : ""}`);
  console.log(`finished    ${over.finished.map((c) => COLORS[c]).join(", ")}`);
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

main().catch((e) => {
  console.error(e);
  process.exit(2);
});
