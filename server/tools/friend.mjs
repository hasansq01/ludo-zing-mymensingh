// A scripted friend for manual testing: joins an existing room by code (from the phone / emulator) and plays its
// own turns with a replica of the TypeScript rules, checking the server hash after every action.
//   node tools/friend.mjs CODE [--url wss://ludo-zing-rooms.flipfold.workers.dev] [--name Robo] [--host-start]
//                              [--delay 600] [--drop-at N --rejoin-after 25000]
// --host-start: if this friend is host (it joined an empty room first, or the host left), it starts the match once
// --start-at N members (default 2) are in.
// Plays Ludo or Snakes & Ladders, whichever the host picked (start / sync carry `game`).
// Exits 0 at `over` with no hash mismatches, 1 otherwise.
import { build } from "esbuild";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const serverDir = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const args = process.argv.slice(2);
const opt = (name, def) => {
  const k = args.indexOf(`--${name}`);
  if (k < 0) return def;
  const v = args[k + 1];
  return v === undefined || v.startsWith("--") ? true : v;
};
const CODE = (args.find((a) => !a.startsWith("--") && /^[A-Za-z0-9]{6}$/.test(a)) ?? "").toUpperCase();
if (!CODE) {
  console.error("usage: node tools/friend.mjs CODE [--url ...] [--name ...]");
  process.exit(2);
}
const URL_ = String(opt("url", "wss://ludo-zing-rooms.flipfold.workers.dev"));
const NAME = String(opt("name", "Robo"));
const DELAY = Number(opt("delay", 600));
const DROP_AT = Number(opt("drop-at", -1));
const REJOIN_AFTER = Number(opt("rejoin-after", 25_000));
const HOST_START = Boolean(opt("host-start", false));
const START_AT = Number(opt("start-at", 2));      // --host-start waits for this many members

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

const t0 = Date.now();
const log = (s) => console.log(`[${((Date.now() - t0) / 1000).toFixed(1).padStart(6)}s] ${s}`);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const COLORS = ["Red", "Green", "Yellow", "Blue"];
const pid = "friend-" + Math.random().toString(36).slice(2) + Math.random().toString(36).slice(2);

let ws, token, id = -1, state = null, n = 0, seats = [], dropped = false, over = null, game = "ludo";
const hash = () => (game === "sl" ? R.slStateHash(state) : R.stateHash(state));
const stats = { acts: 0, mismatches: 0, syncs: 0, errors: {} };
const color = () => seats.find((s) => s.id === id)?.color ?? -1;
const send = (o) => ws?.readyState === WebSocket.OPEN && ws.send(JSON.stringify(o));

function connect() {
  ws = new WebSocket(`${URL_}/v1/rooms/${CODE}/ws`);
  ws.onopen = () => send({ t: "hello", v: 1, pid, name: NAME, avatar: "", frame: "", token });
  ws.onclose = (e) => { if (!dropped && !over) { log(`socket closed ${e.code} ${e.reason}`); process.exit(1); } };
  ws.onmessage = (ev) => onMessage(JSON.parse(ev.data));
}

async function play(c) {
  if (!state || dropped || c !== color()) return;
  if (game === "sl") {
    const me = state.players.find((p) => p.c === c);
    if (!me || me.cpu || R.slTurnColor(state) !== c) return;
    const at = n;
    await sleep(DELAY);
    if (n === at && state.phase === "roll") send({ t: "roll", n });
    return;
  }
  if (state.players[c] !== "human") return;
  const at = n;
  await sleep(DELAY);
  if (n !== at || state.turn !== c) return;
  if (state.phase === "roll") send({ t: "roll", n });
  else if (state.phase === "choose") send({ t: "move", n, i: R.pickAi(state, R.movables(state), null, "normal") });
  else if (state.phase === "pair_ask") send({ t: "pair", n, yes: true });
}

function onMessage(m) {
  switch (m.t) {
    case "welcome":
      token = m.token;
      id = m.id;
      log(`joined ${CODE} as ${NAME} (member ${id})`);
      break;
    case "lobby":
      log(`lobby (${m.status ?? "lobby"}): ${m.members.map((x) => `${x.name}${x.id === m.host ? "*" : ""}`).join(", ")}`);
      if (HOST_START && m.host === id && m.members.length >= START_AT && (m.status ?? "lobby") !== "playing") send({ t: "start" });
      break;
    case "start":
    case "sync":
      game = m.game ?? "ludo";
      state = structuredClone(m.state);
      n = m.n;
      seats = m.seats;
      if (m.t === "sync") stats.syncs++;
      if (hash() !== m.h) stats.mismatches++;
      log(`${m.t}: ${seats.map((s) => `${COLORS[s.color]}=${s.name}`).join(", ")}; I am ${COLORS[color()]}`);
      break;
    case "act":
      if (!state) break;
      if (m.n !== n) { send({ t: "sync_req" }); break; }
      const ev = game === "sl" ? R.applySlAction(state, m.a) : R.applyAction(state, m.a);
      n = m.n + 1;
      for (const e of ev) if (e.type === "finished") log(`${COLORS[e.c]} finished, place ${e.place} (the others play on)`);
      if (m.a.k === "end") log("the server ended the match ({k: end}): the rest ranked by progress");
      stats.acts++;
      if (hash() !== m.h) { stats.mismatches++; log(`HASH MISMATCH at ${m.n}`); send({ t: "sync_req" }); }
      if (m.a.k === "roll" && m.a.c === color()) log(`I rolled ${m.a.v}`);
      if (m.a.k === "mode") log(`${COLORS[m.a.c]} is now ${m.a.mode === "cpu" ? "a bot" : "human again"}`);
      if (n === DROP_AT && !dropped) {
        dropped = true;
        log(`dropping for ${REJOIN_AFTER} ms`);
        ws.close(1000, "friend drop");
        setTimeout(() => { dropped = false; connect(); }, REJOIN_AFTER);
      }
      break;
    case "turn":
      play(m.c);
      break;
    case "over":
      over = m;
      log(`over: winner ${COLORS[m.winner] ?? "-"}, finished ${m.finished.map((c) => COLORS[c]).join(", ")}`);
      log(`acts ${stats.acts}, mismatches ${stats.mismatches}, syncs ${stats.syncs}, errors ${JSON.stringify(stats.errors)}`);
      ws.close(1000, "done");
      process.exit(stats.mismatches ? 1 : 0);
    case "error":
      stats.errors[m.code] = (stats.errors[m.code] ?? 0) + 1;
      if (m.code !== "stale") log(`error ${m.code}: ${m.msg}`);
      if (["not_found", "full", "started", "version"].includes(m.code)) process.exit(1);
      break;
  }
}

connect();
