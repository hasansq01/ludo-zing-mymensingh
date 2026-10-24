# Ludo Zing online rooms: protocol v1

Friend rooms for **Ludo** (Snakes & Ladders online comes later). One Cloudflare Durable Object (`Room`) per room
code. The server is **authoritative**: it rolls the dice, validates every action with its TypeScript port of
`LudoRules` (`server/src/rules/`), runs bots for absent players, and keeps the match in its SQLite storage.

Clients are **deterministic replicas**. Every client keeps its own `LudoRules` state (GDScript) and applies the
server's actions, in order, with the same rules functions it uses offline (`apply_roll`, `move`, `answer_pair`), so all
the existing animations and HUD messages work unchanged. After every action the server sends the hash of its state;
a client whose own hash differs asks for a full snapshot (`sync_req`) and replaces its state.

## Transport

- `POST /v1/rooms` → `200 {"code": "K7QX2M"}`: reserves a fresh room code (6 chars from
  `23456789ABCDEFGHJKMNPQRSTUVWXYZ`, no 0/O/1/I/L). The creator then connects like everyone else and becomes host.
- `GET /v1/rooms/<CODE>` → `200 {"code", "open": bool, "members": n, "started": bool}` or `404`.
- `GET /v1/rooms/<CODE>/ws` with `Upgrade: websocket` → the room socket. Unknown code → `404` (no upgrade).
- `GET /v1/health` → `{"ok": true}`.
- `GET /v1/config` → `{"motd": "", "maintenance": false}` (`Cache-Control: public, max-age=60`): a message of the
  day for Home, and whether online play is in maintenance (set in the admin console, `ADMIN_API.md`).
- Maintenance: `POST /v1/rooms` → `503 {"error": "maintenance", "msg": "<motd or a default text>"}`; show `msg`.
  Rooms that already exist keep working (joining by code still works).
- Hosts: production `wss://ludo-zing-rooms.flipfold.workers.dev`; local dev `ws://<mac-ip>:8787` (`npm run dev` in
  `server/`); the Android emulator reaches the Mac at `ws://10.0.2.2:8787`.
- Every message is one JSON object with a `"t"` (type) field. Text frames only. Max 4 KB per client message.

## Identity

- Each client has a random **player id** (`pid`, 16+ chars, generated once and kept on the device) and per-room
  **token** issued by the server in `welcome`. Reconnecting with the token (same room) takes back the same seat.
- Names are trimmed, 1–16 characters (default "Player"); avatar and frame are catalog ids (strings ≤ 32 chars).

## Client → server

| t | fields | when |
|---|---|---|
| `hello` | `v: 1, pid, name, avatar, frame, token?` | first message on every connection |
| `settings` | `teams?: bool, pair_ask?: bool` | host, lobby only |
| `start` | – | host, lobby (or after `over` for a rematch); needs ≥ 2 members (teams: exactly 4) |
| `roll` | `n` | your turn, phase `roll` |
| `move` | `n, i` (token index 0–3, as `LudoRules.move`) | your turn, phase `choose` |
| `pair` | `n, yes` | your turn, phase `pair_ask` |
| `back` | – | you were turned into a bot (timeouts) and tapped "I'm back" |
| `sync_req` | – | your hash didn't match, or after a reconnect hiccup |
| `leave` | – | leave the room (lobby: frees the seat; in a match: a bot takes the seat for good) |
| `ping` | – | keep-alive every 20 s |

`n` is the index of the action this request would become (the client's `n` = number of actions applied so far).
A request with a stale `n` is ignored with `error {code: "stale"}` (protects against double taps and races).

## Server → client

| t | fields |
|---|---|
| `welcome` | `token, id` (your member id), `code`, `host` (member id) |
| `lobby` | `code, host, members: [{id, name, avatar, frame, online, color}], settings: {teams, pair_ask}, max: 4` |
| `start` | `n: 0, seats, state, h` |
| `act` | `n, a, h` (one action, see below; `n` = its index, `h` = server state hash after applying it) |
| `sync` | `n, seats, state, h` (full snapshot; replaces the client state) |
| `turn` | `c, deadline, now` (colour to act, epoch ms deadline for the current step, server clock) |
| `presence` | `id, online` |
| `over` | `finished: [colours in finishing order], winner` (colour, or −1) |
| `error` | `code, msg` |
| `pong` | `now` |

`seats`: `[{color, id, name, avatar, frame, bot: bool, online: bool}]` for the playing colours. `state` is the full
LudoRules state (JSON) with `players[c]` = `"human"` (a member), `"cpu"` (a bot) or `"off"`, and `names[c]` = the
member's name. Clients replace their own seat's display name with "You" locally (presentation only; never hashed).

### Actions (`a`)

| k | fields | client applies |
|---|---|---|
| `roll` | `c, v` | `LudoRules.apply_roll(s, v)` |
| `move` | `c, i` | `LudoRules.move(s, i)` |
| `pair` | `c, yes` | `LudoRules.answer_pair(s, yes)` |
| `mode` | `c, mode: "cpu" \| "human"` | `s.players[c] = mode` (a bot takes over / the player is back) |

The server only ever sends legal actions. Bots and timeouts produce ordinary `roll` / `move` / `pair` actions, so a
client never runs AI for online matches.

### Colours

Members are seated in join order. At `start` the playing colours are: 2 players → Red, Yellow (0, 2: opposite
corners); 3 → Red, Green, Yellow (0, 1, 2); 4 → all. Teams needs 4 (Red + Yellow vs Green + Blue).

## State hash

FNV-1a 32-bit over the UTF-8 bytes of this string, written as 8 lowercase hex digits:

```
tok(16 ints, colour-major, comma-joined) | pairs("c.a.b" in array order, comma-joined) | turn | dice | sixes |
phase | winner | free(4 chars "0"/"1") | finished(comma-joined) | players(comma-joined) | pending
```

joined with `|` and no spaces, where `pending` is `""` when empty or `"c.i.to.extra(0/1).partner"` (partner −1 if
absent). Example for a fresh 2-player game:
`-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1||0|0|0|roll|-1|0000||human,off,human,off|`
`names`, `view`, `teams`, `pair_ask` and `pick` are not hashed. Implementations: `server/src/rules/hash.ts`,
`godot/scripts/net/state_hash.gd` (identical outputs are tested on shared fixtures).

## Timers, bots and presence

- Turn deadlines: `roll` 15 s, `choose` 20 s, `pair_ask` 10 s by default; the admin console can set each to
  5–120 s (read at every match start, so a change applies from the next match). Clients should always use the
  `turn.deadline` they receive, never a built-in duration (bots act after 0.8–1.4 s; a roll by a bot, then
  its move after ~1 s so clients can animate).
- A timeout auto-acts for that human: roll; move = `auto_move_token` or the easy AI choice; pair = yes. Two
  timeouts in a row → `mode cpu` for that colour until the player sends `back` (any later `roll`/`move` from them
  counts as `back` too).
- Disconnect: `presence {online: false}`; after a 20 s grace the colour becomes a bot (`mode cpu`); reconnecting
  with the token sends `sync` and `mode human`.
- The host leaving the lobby passes host to the next member. An empty room (no sockets) is deleted after 10 min;
  any room is deleted 2 h after its last action (Durable Object alarm).

## Errors (`error.code`)

`version` (unsupported v), `not_found`, `full` (4 members), `started` (match in progress and you have no seat),
`not_host`, `not_your_turn`, `bad_action` (illegal for the rules), `stale`, `too_few`, `teams_need_4`, `rate`
(over 20 messages/s), `bad_message`, `banned` (your pid is banned from online play; `msg` says so, with the
reason; the socket then closes with 4003: on hello, or while you are in a room when the ban happens), `kicked` (an
admin removed you from the room; the socket then closes with 4002).

## Server behaviour details (as implemented in `server/src/room.ts`)

Clarifications of the tables above; nothing here changes a message the client sends.

- **Codes** in URLs are case-insensitive. Wrong method → `405`; `/ws` without `Upgrade: websocket` → `426`; more
  than 16 sockets on one room → `503`. A reserved code nobody joins expires after the 10 min empty-room timeout.
- **hello**: `pid` must be 16–64 chars of `[A-Za-z0-9_-]` (else `bad_message` and close). A matching `token` **or**
  the same `pid` reclaims the member (and seat); the member's older socket is closed with code `4001`. Names have
  control characters removed and are cut to 16 characters (never rejected; empty → "Player"); an avatar / frame
  that is not ≤ 32 chars of `[A-Za-z0-9_.:-]` becomes `""`.
- **Close codes**: `4000` after a fatal error (`version`, `full`, `started`, bad hello, `not_found`), `4001`
  replaced by a newer connection of the same member, `4002` after your own `leave` (or an admin kick, preceded by
  `error {code: "kicked"}`), `4003` banned (preceded by `error {code: "banned"}`; don't auto-reconnect), `4004` the
  room was deleted (stale / empty cleanup or closed by an admin; preceded by `error {code: "not_found"}`).
- **hello and bans**: the server checks the pid against the ban list (one D1 read, cached 60 s) before answering
  `welcome`; messages sent before `welcome` wait for it and keep their order.
- **Message order on connect**: `welcome`, then in the lobby (or after `over`) `lobby` to everyone; in a match
  `presence {online: true}` to the others, `sync` + `turn` to you, and `act mode human` if a bot had your seat.
  After `over`, a reconnecting client gets `sync` + `over` + `lobby`.
- **After every action** the server sends `act`, then `turn` (unless the game is over). `turn` is sent for bot
  steps too; its `deadline` is when the bot will act. While nobody is connected, bots pause (no `turn`) and resume
  when someone reconnects.
- `act.a.c` is `state.turn` (the roller, also under Free Hand). For `move`, `i` is the unit's lead token (`units()`
  `token`); a client may send either pawn of a pair.
- **Validation order**: shape (`n` must be an integer, else `bad_message`) → `stale` → `not_your_turn` → phase /
  legality (`bad_action`). A `move` whose `i` is not 0–3 or not movable is `bad_action`. `settings` / `start`
  during a match are `bad_action`. A `back` when your seat is not a bot is ignored. A `pair` (like `roll` / `move`)
  from a player whose seat is a bot counts as `back`: the server emits `act mode human` first, then the action.
- Timeouts act with `auto_move_token`, else the **easy** AI; bots play the **normal** AI.
- **`lobby`** also carries `status` (`"lobby" | "playing" | "over"`); a member's `color` is the colour they would
  get if the host started now. It is also sent during a match when the host changes (the host left).
- **Lobby disconnects**: the member stays (`online: false`) for the 20 s grace, then is dropped (`lobby` sent); a
  later hello joins as a new member at the end of the order.
- **`over`** also carries `standings: [{color, place, finished, progress}]` (`LudoRules.standings`), and is
  followed by `lobby` (`status: "over"`). The room is then back under lobby rules: people may join (up to 4) or
  leave, the host may change settings, and the host's `start` begins a rematch with the current members in join
  order (a new `start`, `n: 0`). Members still offline after the game are dropped after the grace.
- **`leave` in a match**: the others get `presence {online: false}` and `act mode cpu`; the bot keeps that colour
  for the rest of the match, and the old token no longer works (`started`).
- **Rate limit**: a fixed 1 s window per socket, `ping` included; the first message over 20 gets `error rate`, the
  rest of that window is dropped silently.
- **Storage / timers**: one storage value per room (members, settings, match state, `n`, deadlines, strikes, bot
  RNG) and one Durable Object alarm set to the earliest of: turn deadline / bot action, disconnect graces, empty-room
  (10 min) and stale-room (2 h since the last action or lobby change) cleanup. Sockets use the hibernation API, so
  an idle room is evicted from memory and resumes from storage on the next message.
- **Tests only**: the Room has test hooks (fixed dice, starting token positions, a time scale, a rate limit) that
  work only when the `TEST_MODE` binding is `"1"`, which only `vitest.config.ts` sets; no route reaches them.

## Rules module API (`server/src/rules/ludo.ts`)

A line-for-line port of `godot/scripts/core/ludo_rules.gd` with the same names in camelCase and the same state
shape and event objects: `newGame(players, teams, opts)`, `applyRoll(s, v)`, `move(s, i)`, `answerPair(s, yes)`,
`movables(s)`, `units(s)`, `autoMoveToken(s)`, `pickAi(s, mv, rng, level)`, `winners(s)`, `standings(s)`, plus the
helpers. `stateHash(s)` lives in `hash.ts`. Parity with GDScript is tested by replaying traces recorded from the
GDScript rules (`godot/dev/net_parity_dump.gd` → `server/test/fixtures/ludo_traces.json`).
