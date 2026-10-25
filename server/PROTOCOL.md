# Ludo Zing online rooms: protocol v1

Friend rooms and quick match for **Ludo** and **Snakes & Ladders** (see "Game types" and "Quick match"). One
Cloudflare Durable Object (`Room`) per room code, one `Matchmaker` per quick-match queue. The server is
**authoritative**: it rolls the dice, validates every action with its TypeScript ports of `LudoRules` /
`SnakesLaddersRules` (`server/src/rules/`), runs bots for absent players, and keeps the match in its SQLite storage.

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
- **Accounts** (ONLINE_V2.md §1): `hello` may carry `session` (from `POST /v1/auth/guest`). The member then belongs
  to that account (rewards at `over`, bans, level). Without a session (old clients) the server looks up the pid's
  account (`devices`); a pid with no account still plays, but earns nothing. An invalid or expired session is not an
  error in rooms: the pid's account is used instead. The same account on another device takes back its member.
- `level` (seats, lobby members) is the account's level from its XP (1 when unknown).

## Client → server

| t | fields | when |
|---|---|---|
| `hello` | `v: 1, pid, name, avatar, frame, token?, session?` | first message on every connection |
| `settings` | `teams?: bool, pair_ask?: bool, game?: "ludo" \| "sl"` | host, lobby only (friend rooms) |
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
| `lobby` | `code, host, members: [{id, name, avatar, frame, level, online, color}], settings: {teams, pair_ask, game}, max: 4` |
| `start` | `n: 0, game, seats, state, h` |
| `act` | `n, a, h` (one action, see below; `n` = its index, `h` = server state hash after applying it) |
| `sync` | `n, game, seats, state, h` (full snapshot; replaces the client state) |
| `turn` | `c, deadline, now` (colour to act, epoch ms deadline for the current step, server clock) |
| `presence` | `id, online` |
| `over` | `finished: [colours in final order], winner` (colour, or −1); sent once, at the end of the game (see "Play on after the first finish") |
| `error` | `code, msg` |
| `pong` | `now` |

`seats`: `[{color, id, name, avatar, frame, level, bot: bool, online: bool}]` for the playing colours. `state` is the full
LudoRules state (JSON) with `players[c]` = `"human"` (a member), `"cpu"` (a bot) or `"off"`, and `names[c]` = the
member's name. Clients replace their own seat's display name with "You" locally (presentation only; never hashed).

### Actions (`a`)

| k | fields | client applies |
|---|---|---|
| `roll` | `c, v` | `LudoRules.apply_roll(s, v)` |
| `move` | `c, i` | `LudoRules.move(s, i)` |
| `pair` | `c, yes` | `LudoRules.answer_pair(s, yes)` |
| `mode` | `c, mode: "cpu" \| "human"` | `s.players[c] = mode` (a bot takes over / the player is back) |
| `end` | – (no `c`) | `LudoRules.end_game(s)`: the server ends the match early (see "Play on after the first finish") |

The server only ever sends legal actions. Bots and timeouts produce ordinary `roll` / `move` / `pair` actions, so a
client never runs AI for online matches.

### Play on after the first finish

A match does not end when the first side finishes: like real Ludo, the others play on for the next places. The
rules (the same in GDScript and TS, so clients get there from the acts alone):

- A side finishes when a colour has all four pawns home (Teams: when both partners have, the team finishing
  together; Snakes & Ladders: when a player reaches 100). The rules record it in `s.finished` (S&L: player indices)
  and emit `{type: "finished", c, place, team?}` (Ludo; `team` = both colours in Teams) / `{type: "finished", turn,
  c, place}` (S&L). That side is skipped by the turn order from then on (`next_active`); its pawns stay home. A 6 or
  a capture on the finishing move gives no extra roll (the turn passes). In Teams a colour home on its own still
  rolls (Free Hand, `{type: "all_home", c}`), until its partner is home too.
- The game is over when fewer than two sides are unfinished, or when no unfinished side has a `"human"` seat
  (`players[c] == "human"`; S&L `cpu == false`). This is checked when a side finishes (a `mode` act alone never ends
  a game). Then the unfinished sides are ranked by progress (`standings()`), `s.finished` becomes the full order,
  `s.winner` is the first finisher, and one `game_over {winner, team, order}` (S&L `win {turn, order}`) ends the
  event list. `over` follows the act, with that order in `finished`.
- `{k: "end"}` (`end_game` / `endGame`): the server's way to end a match early, ranking the unfinished sides by
  progress exactly as above. The Room sends it after an action when no **real** person is left unfinished (every
  unfinished seat is a quick-match ghost or a seat whose member left) while the result is for someone (a person still
  seated, or one who finished and left since): ghosts are `"human"` in the state, so the rules alone would make you
  watch them. (Nobody finished and every person left: a quick match is abandoned, as before.) It is refused (no events,
  no change) once the game is over.
- Grants (see "Online rewards"): the first side is **win**, every other side that finished or was ranked at the end
  is **finish**; **left** only for a seat that was away (left, or played by a bot) when its side was ranked, so a
  player who finished and then left keeps their outcome. A seat that has finished never becomes a bot (disconnects
  and `leave` send no `mode` act for it).
- Clients show each finish as it happens (the place on that player's tile; your own finish: a card with Keep
  watching / Home, where Home leaves the room and the reward is still granted at `over`).

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

## S&L state hash

For Snakes & Ladders matches (`SnakesLaddersRules` state, see ONLINE_V2.md §5) `act.h` / `start.h` / `sync.h` are
this hash instead: FNV-1a 32-bit (the same function as above) over the UTF-8 bytes of

```
turn | phase | sixes | winner | need_one | players | finished
```

i.e. exactly these seven fields, in this order:

1. `turn`: int (index into `players`)
2. `phase`: the string as is (`roll` / `over`)
3. `sixes`: int
4. `winner`: int (−1 while playing)
5. `need_one`: `"1"` or `"0"` (an absent key is `"0"`)
6. `players`: one entry per player in array (turn) order, comma-joined, each `c.pos.cpu.ladders.snakes.rolls`:
   `c`, `pos`, `ladders`, `snakes` as ints, `cpu` as `"1"` / `"0"`, and `rolls` every recorded roll as one digit,
   concatenated (`""` before the player's first roll)
7. `finished`: the player indices in finish order, as ints, comma-joined (`""` when none, or the key is absent)

joined with `|` and no spaces. Every number goes through `int()` (`Math.trunc`), so a state that came through JSON
hashes the same. `mode`, `paid`, `name` and `you` are not hashed (`you` / `name` are per-client presentation; rewards
are the server's). Example for a fresh 2-player game (`new_game("local", 2)`):
`0|roll|0|-1|0|0.0.0.0.0.,1.0.0.0.0.|` → `edd54d53`.

S&L actions (`a`): `roll {c, v}` → `SnakesLaddersRules.apply_roll(s, v)` (`c` is the colour of
`s.players[s.turn]`); `mode {c, mode: "cpu" | "human"}` → for the player whose `c` is that colour,
`p.cpu = mode == "cpu"` (no player with that colour: no change); `end {}` → `SnakesLaddersRules.end_game(s)`.
Rolling is the only choice, so a bot or a timeout just rolls.

Implementations: `server/src/rules/sl_hash.ts` (`slStateHash`, `slStateHashInput`), `godot/scripts/net/sl_state_hash.gd`
(`SLStateHash.of`, `SLStateHash.input`). The rules port is `server/src/rules/sl.ts` (line-for-line from
`snakes_ladders_rules.gd`, same state and events: `newGame(mode, n, color, opts)`, `land`, `applyRoll`,
`replayReaches100`, `claimWinReward`, `claimPlayReward`, `standings`, plus `applySlAction(s, a)`, `turnColor`,
`botAction`); parity is tested on traces recorded from the GDScript rules (`godot/dev/net_parity_dump_sl.gd` →
`server/test/fixtures/sl_traces.json`, replayed by `server/test/rules_sl_parity.test.ts`).

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

## Game types

A room plays `game: "ludo"` (default) or `"sl"` (Snakes & Ladders). Friend rooms: the host picks it in the lobby with
`settings {game}` (shown in `lobby.settings.game`; it may change between matches). Quick rooms: the queue's game.
`start` and `sync` carry `game`; the client sets up the matching board and replica from it.

What changes for `"sl"`:

- `state` is the `SnakesLaddersRules` state (`new_game("local", k)`, then for player k: `c` = its colour, `name` = the
  member's name, `cpu: false`, `you: false`; `mode: "online"`). Clients set `you` on their own player locally
  (presentation only; not hashed). `h` is the **S&L state hash** (below).
- Colours: members in join order get Red, Green, Yellow, Blue (`0, 1, 2, 3`; also `lobby.members[].color`). Turn
  order is `state.players` order. `teams` / `pair_ask` are ignored (any 2-4 members can start).
- The only request is `roll {n}` (`move` / `pair` → `bad_action`). `turn.c` is the colour of `players[turn]`;
  the deadline is the roll timer. A 6 means the same colour rolls again (another `turn`).
- Actions: `roll {c, v}` and `mode {c, mode}` (see "S&L state hash"). Bots, timeouts and ghosts only roll.
- `over`: `winner` = the winner's colour (the first to 100), `finished` = every colour in final order (play on),
  `standings` = `SnakesLaddersRules.standings` (`[{idx, color, name, place, finished, pos, progress}]`).

## Quick match

`GET /v1/quick/ws?game=ludo|sl&players=2|4` with `Upgrade: websocket` → the queue for that game and table size (one
`Matchmaker` Durable Object each). Wrong game / size → `400`; no upgrade → `426`. JSON text frames as in rooms.

| dir | t | fields |
|---|---|---|
| → | `hello` | `v: 1, session, pid, name?, avatar?, frame?` (first message; `session` may instead be the `?session=` query parameter). name / avatar / frame default to the account's profile; they are what the others see in the match |
| ← | `queued` | `position` (1-based, first come first served), `eta_s` (rough seconds until the match). Sent after hello and whenever your position changes |
| ← | `matched` | `code`, `token`: your seat in room `code`. The last message: the **client** closes this socket (the server leaves it open, because a close right behind a frame can make some clients drop it; later messages are ignored) |
| → | `cancel` | leave the queue; answered by `cancelled`, then close 1000. Closing the socket also leaves the queue |
| ↔ | `ping` / `pong` | as in rooms |
| ← | `error` | `code, msg`: `session` (missing / invalid / expired: get a new one from `POST /v1/auth/guest`, close 4000), `banned` (close 4003), `maintenance` (`msg` = the motd; close 4000), `replaced` (you queued again on another connection, which took your place; close 4001), `busy` (you are being matched on another connection; close 4000), `version`, `bad_message` |

- One queue entry per account. People are matched in arrival order: as soon as `players` people wait they get a
  table together. Otherwise, a few seconds after the first of them queued (randomised 4–9 s; 3–5 s when nobody had
  queued for 2 minutes), everyone waiting is seated together and the empty seats are filled with other players.
- After `matched`: connect to `GET /v1/rooms/<code>/ws` and send the usual `hello` with `token` (from `matched`),
  `session` and `pid`. Your seat was reserved for you: the room is closed to anyone else (`error full`).
- A quick room has **no lobby, no host and no rematch**: no `lobby` message is ever sent, `welcome.host` is `-1`,
  `settings` / `start` → `bad_action`. The match starts (`start`) as soon as every matched person is connected, or
  10 s after the match was made. Someone who never connects is treated like a disconnect (after the 20 s grace a
  bot plays their seat, `mode cpu`). Play again = queue again.
- After `over` the room stays for 2 minutes (reconnects get `sync` + `over`) and is then deleted. If every person
  leaves (`leave`) during the match, the match is abandoned (the room is closed, nothing is granted), unless one of
  them had already finished (play on): then the match ends with `{k: "end"}` and the finished keep their place.
- Everything else in the match (turns, timers, presence, reconnects, `leave`) is as in friend rooms.

## Online rewards

At `over` (friend rooms and quick rooms) the server grants each seat's account once per match (match id
`<code>-<start ms>`): **win** (your side finished first), **finish** (your side finished later, or was ranked by
progress at the end), **left** (you were away, i.e. had left or a bot was playing your seat, when your side was
ranked: 0; finishing and then leaving keeps win / finish). Amounts: ONLINE_V2.md "Economy decisions". The client refreshes its
profile (`GET /v1/me`) after `over`; rewards are not part of any room message.

## Errors (`error.code`)

`version` (unsupported v), `not_found`, `full` (4 members), `started` (match in progress and you have no seat),
`not_host`, `not_your_turn`, `bad_action` (illegal for the rules), `stale`, `too_few`, `teams_need_4`, `rate`
(over 20 messages/s), `bad_message`, `banned` (your pid is banned from online play; `msg` says so, with the
reason; the socket then closes with 4003: on hello, or while you are in a room when the ban happens), `kicked` (an
admin removed you from the room; the socket then closes with 4002). `banned` also covers a banned account (by
session or by the pid's account). In a quick room `full` means you have no seat in it.

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
  After `over`, a reconnecting client gets `sync` + `over` + `lobby`. Quick rooms: never `lobby` (before the start
  only `welcome`; after `over` `sync` + `over`).
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
- **Quick-match seats the server plays** (ONLINE_V2.md §3, owner decision: no disclosure): to clients they are
  ordinary members in every message (`players[c] = "human"`, `bot: false`, `online: true`, a name, a free avatar,
  a level, a `turn.deadline` from the normal turn timer, the same actions as a person's requests). Which seats they
  are is stored in the Room only and shown in the admin console (`adminSnapshot`: `ghost: true` on members / seats;
  matches rows: `ghosts`, `human_won`, `players[].ghost`). Server internals: `src/ghosts.ts`, `src/room.ts`.
- **Accounts on hello**: the legacy pid ban, the session's account (banned → `banned`) and the pid's account are
  checked before `welcome` (cached 60 s); the account's level is read from its profile. Lookups fail open.
- **Rate limit**: a fixed 1 s window per socket, `ping` included; the first message over 20 gets `error rate`, the
  rest of that window is dropped silently.
- **Storage / timers**: one storage value per room (members, settings, match state, `n`, deadlines, strikes, bot
  RNG) and one Durable Object alarm set to the earliest of: turn deadline / bot action, disconnect graces, empty-room
  (10 min) and stale-room (2 h since the last action or lobby change) cleanup. Sockets use the hibernation API, so
  an idle room is evicted from memory and resumes from storage on the next message. Quick rooms add the auto-start
  time, the 2 min after `over`, and grant retries (30 s, 60 s, ... 5 tries) to the alarm. The daily cron calls the
  `sweepStale()` RPC on rooms rows that look stale: a room with no person connected is deleted (a running match is
  recorded as abandoned).
- **Matchmaker storage**: the queue is the waiting sockets' attachments (account, identity, queue time, wait) plus
  one storage value (game, size, empty-since, sequence) and one alarm (the next fill time / hello timeout of 10 s),
  so an evicted queue resumes as it was.
- **Tests only**: the Room has test hooks (fixed dice, starting token positions, a time scale, a rate limit) that
  work only when the `TEST_MODE` binding is `"1"`, which only `vitest.config.ts` sets; no route reaches them.

## Rules module API (`server/src/rules/ludo.ts`)

A line-for-line port of `godot/scripts/core/ludo_rules.gd` with the same names in camelCase and the same state
shape and event objects: `newGame(players, teams, opts)`, `applyRoll(s, v)`, `move(s, i)`, `answerPair(s, yes)`,
`movables(s)`, `units(s)`, `autoMoveToken(s)`, `pickAi(s, mv, rng, level)`, `winners(s)`, `standings(s)`, `endGame(s)`,
`sideDone(s, c)`, `applyAction(s, a)` (all five action kinds), plus the
helpers. `stateHash(s)` lives in `hash.ts`. Parity with GDScript is tested by replaying traces recorded from the
GDScript rules (`godot/dev/net_parity_dump.gd` → `server/test/fixtures/ludo_traces.json`).
