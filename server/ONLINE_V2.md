# Ludo Zing online v2: accounts, server economy, quick match, leaderboards, S&L online

Status: design (2026-10-24). Builds on PROTOCOL.md (friend rooms) and ADMIN_API.md (console). Everything stays on
the Cloudflare free plan (Workers, Durable Objects with SQLite, D1).

Product decisions (owner, 2026-10-24):
- Quick match fills empty seats with **bots that look like real players** (human names and avatars, human-like
  timing). **No disclosure.** Bots never chat or claim anything beyond a name and avatar.
- **Accounts:** Google Play Games Services v2 sign-in on Android (the owner has a Play Console account; the app
  will be created there). Every install starts as a guest account; signing in links it to the Google identity.
- **Server-authoritative coins:** shop purchases, daily reward, spin and free coins go through the server; offline
  match wins (vs computer / pass & play) are reported as claims and accepted within limits; online match rewards are
  granted by the server at `over`.

## 1. Identity and sessions

- Device id `pid` (exists today, `Save.prefs.net_pid`).
- `POST /v1/auth/guest {pid, import?}` → `{account, session, profile}`. Creates the guest account for a new pid,
  or returns the existing one. `import` (first call only, once per account): the local profile from before v2
  (coins, xp, stats, owned, equipped, name, avatar…) is accepted once, capped (coins ≤ 50,000, xp ≤ 200,000;
  owned items must exist in the catalog), recorded in the ledger as `import`.
- `session`: `<account_id>.<exp>.<hmac>` (HMAC-SHA256 with secret `SESSION_KEY`; 30 days; refreshed on use when
  < 7 days left). Sent as `Authorization: Bearer <session>` on HTTP and as `session` in the room `hello`.
- `POST /v1/auth/google {server_auth_code}` (Bearer guest session) → exchanges the Play Games server auth code with
  Google (`https://oauth2.googleapis.com/token`, web client id/secret = secrets `GOOGLE_WEB_CLIENT_ID`,
  `GOOGLE_WEB_CLIENT_SECRET`), reads the Play Games player id (`GET https://games.googleapis.com/games/v1/players/me`
  with the access token) and links it:
  - Google id unknown → it becomes this account's Google id → `{account, session, profile, linked: true}`.
  - Google id already linked to another account → `409 {conflict: {here: summary, there: summary}}`; the client asks
    which progress to keep, then `POST /v1/auth/google/resolve {server_auth_code, keep: "here" | "there"}`.
    "there": this device switches to that account (the guest account is left as is). "here": the Google id moves to
    this account and the other account is marked merged/retired.
  - This account is already linked to another Google id → `409 {error: "other_google", conflict: {here, there | null},
    ticket}` (never a silent switch); the client asks, then resolve with `keep: "switch"` or `"stay"` (Policy b).
  - Summary = `{name, avatar, level, coins, wins, last_seen}`.
- Bans move from pid to account (a banned account can't play online; a banned pid can't create guest accounts).
- `GET /v1/me` → `{account, profile}`; `PATCH /v1/me {name?, avatar?, frame?, plate?, badge?}` (owned items only).

## 2. Server economy (wallet)

- The catalog (prices, unlocks) is generated from the GDScript catalog into `server/src/catalog.json` by a dev script
  (`godot/dev/export_catalog.gd`) and checked by a test (parity with `Catalog`/`Collection`).
- `POST /v1/shop/buy {kind, id}` → new profile or `{error: "coins" | "owned" | "locked" | "unknown"}`.
- `POST /v1/rewards/daily` / `/v1/rewards/spin` / `/v1/rewards/free` → the reward computed by the server (server
  clock, server RNG, same tables as `Rewards` in GDScript) + new profile; cooldown errors carry `next_at`.
- `POST /v1/claims {game, mode, result, placing, players, duration_s, moves, xp}` for offline matches →
  server grants coins/xp per the same rules as offline today (`LudoRules.win_reward/play_reward`, S&L equivalents),
  by **placing** (play on, 2026-10-25: a game goes on after the first finish): `placing` 1 (your side finished first)
  = the win reward, any other place (finished later, or ranked by progress at the end) = the play / finish reward;
  `result` ("win" | "loss") still decides for clients that send no `placing`; a placing outside 1-4 is `invalid`.
  S&L vs Computer wins (placing 1) are still verified by replaying the rolls.
  with limits: duration ≥ 60 s (Ludo) / 30 s (S&L), ≤ 20 claims per hour, ≤ 6,000 coins per day from claims;
  over-limit claims are recorded but grant 0 (`limited: true`). Claims carry a client id so retries are idempotent.
- Online matches (friend rooms and quick match): the Room DO grants at `over` (win 150, finish 20, XP 100/40),
  once per account per match.
- Every change is a ledger row `{account, at, delta_coins, delta_xp, reason, ref}`.
- Offline-first client: the local profile is a cache. Purchases, daily, spin and free need a connection ("Connect to
  claim"); claims queue offline and sync on reconnect; the server profile wins on sync.

## 3. Quick match

- `GET /v1/quick/ws?game=ludo|sl&players=2|4&session=…` → a **Matchmaker** Durable Object (one per game+size).
  Messages: server → `{t: "queued", position, eta_s}`, `{t: "matched", code, token}`; client → `{t: "cancel"}`.
- Pairing: humans waiting for the same game+size are matched FIFO. After a short wait (randomised **4–9 s**, shorter
  when the queue is empty for long) the remaining seats are filled with **disguised bots** and the room starts.
- The room is a normal Room DO with `public: true`, `quick: true`, auto-start (no lobby screen: the client goes
  straight from "Finding players…" to the match), no rematch (Play again re-queues).
- **Disguised bots:**
  - In the rules state their seat is `players[c] = "human"`, so every client sees them as people (no Bot tag, no
    `mode` acts). The Room drives those seats itself (`seat.ghost = true`, never sent to clients).
  - Names and avatars come from a pool of common Bangladeshi first names plus a free avatar; levels look plausible
    (1–25, tied to the human's level).
  - Timing: roll after 0.8–2.6 s, pick a pawn after 1.0–3.5 s, pair answer after 0.8–2 s, with occasional longer
    "thinking"; never time out.
  - Skill: "normal" AI with some random mistakes, so they don't always win (target: a human wins about 45–55% of
    1v1 quick matches against ghosts).
  - Presence always online. They stay to the end even if the humans leave (then the room just finishes or is cleaned up).
- Rewards: online rules (see 2). Leaderboards count human wins only; ghosts are excluded from stats and the
  console marks them (the console sees `ghost`, clients never do).
- Friend rooms are unchanged (bots there stay labelled, as today).

## 4. Leaderboards

- D1 `scores(account, board, period, value, updated_at)` for boards `xp` (total XP) and `wins` (online wins: friend
  rooms + quick match), periods `all` and `week:<ISO week>`.
- `GET /v1/leaderboard?board=xp|wins&period=all|week` → `{top: [{rank, name, avatar, level, value}], me: {rank, value}}`
  (top 50; cached 30 s).
- Also submitted to Play Games leaderboards from the client when signed in (optional, ids in config).
- In-game: a Leaderboard sheet (from Profile and Home), Weekly / All time tabs, You row pinned.

## 5. Snakes & Ladders online

- TypeScript port of `snakes_ladders_rules.gd` in `server/src/rules/sl.ts` with GDScript-recorded parity traces (as
  for Ludo), `stateHash` for S&L.
- Rooms get `game: "ludo" | "sl"` (friend rooms: the host picks; quick match: by queue). S&L actions: `roll`,
  `mode`. Bots and ghosts work the same.
- Client: `SLMatch` online mode mirroring Ludo's (requests not local moves, act queue, hash check, sync), Friends
  sheet game picker, Home "Play with friends" enabled for S&L.

## 6. Admin console additions

- Accounts page (replaces/extends Players): guest vs Google-linked, coins, XP, level, devices (pids), ledger tab,
  **Adjust coins** (reason required, audited), ban/unban account.
- Leaderboards page (both boards, both periods).
- Quick match: queue sizes, matches today, average wait, ghost fill rate, human win rate vs ghosts.
- Room/match pages show ghosts (console only).

## 7. Play Games Services (Android)

- A Godot Android v2 plugin (Kotlin AAR, `com.google.android.gms:play-services-games-v2`) in
  `godot/android/plugins/play_games/` with a GDScript wrapper `godot/scripts/net/play_games.gd`: `is_available()`,
  `sign_in()` (automatic at launch, manual button as fallback), `server_auth_code(web_client_id)`,
  `submit_score(board_id, value)`, `show_leaderboards()`. A no-op stub on desktop/emulator without Play services.
- Needs from the Play Console (owner + lead): the app created, Play Games Services project, OAuth consent screen,
  Android OAuth client(s) for package `com.flipfold.ludozing` with the SHA-1 of the upload key and of the Play app
  signing key (and the debug key for testing), a Web OAuth client for the server auth code, leaderboards created.

## 8. Notifications (backlog, requested 2026-10-24; after sections 1–7)

- **Local notifications (on-device, no server):** daily reward ready, free coins ready, spin ready, "come back"
  nudges after 1 / 3 / 7 days away (capped, quiet hours 22:00–09:00 local). Android WorkManager/AlarmManager via our
  own Godot Android plugin (same approach as Play Games); Android 13+ POST_NOTIFICATIONS runtime permission asked at a
  good moment (after the first win), never at launch. Settings: a Notifications switch (+ per-type toggles).
- **Push notifications (Firebase Cloud Messaging, free):** a Firebase project + `google-services.json`; the plugin
  registers an FCM token and sends it to the server (`POST /v1/push/token`, stored per account/device in D1).
  Event pushes from the server: "It's your turn" in a friend game when the app is in the background, "Your friend
  joined room CODE", "Rematch?", weekly leaderboard result. The Worker sends via the FCM HTTP v1 API using a service
  account (OAuth JWT signed with WebCrypto RS256; key as a Worker secret).
- **Admin promos:** a Notifications page in the console: compose title + body (+ optional deep link: shop item,
  daily reward), audience (everyone via an FCM topic, or segments from D1: inactive N days, new players, level
  ranges), test-send to yourself, schedule (Cron/alarm), and delivery stats (sent / failed / opened via a tracking
  param). Rate limits and an audit entry per send.

## Economy decisions (lead, 2026-10-24, after the econ port — server/src/econ/README.md)

1. Day boundary for daily / spin / free: **Bangladesh midnight** (`DAY_OFFSET_MIN = 360`, UTC+6) — the players are
   in Bangladesh; the offline game used the device day.
2. Online rewards: **Ludo** win 150 coins + 100 XP, finish 20 + 40 XP; **Snakes & Ladders** win 100 + 60 XP, finish
   10 + 25 XP (S&L offline pays half of Ludo and no XP; online S&L gives XP so it counts for the XP board).
   Left early: 0.
3. The 6,000-coins-per-day claim cap pays the **partial remainder** (not 0); the 20-per-hour cap and too-short
   matches still grant 0.
4. Offline claims also cap **XP at 3,000 per day** (online XP is uncapped: those matches are server-run).
5. S&L win claims carry `rolls`; the server replays them (`replayReaches100`) before paying a win.
6. Import keeps the daily streak and owned items as the econ README describes (one-time, capped).

All six are in `src/econ` (`rules.ts`: `DAY_OFFSET_MIN`, `ONLINE_REWARDS`, `CLAIM_LIMITS`; `matches.ts`:
`claimLimit` / `claimMatch`; `rewards.ts`: `dayKey`, `nextDayAt`, `isoWeek`). The endpoints call econ directly.

## Policy decisions (lead, 2026-10-24)

a. **Guest accounts per IP:** at most 20 new guest accounts per client IP per hour and 60 per day (generous:
   Bangladeshi mobile networks use carrier-grade NAT). Over → `429 {error: "rate"}`. IPv6 counts per /64; only an
   HMAC of the IP is stored (`guest_creations`, pruned after a day). `POST /v1/auth/guest` for a pid that already
   has an account is never limited. **Leaderboards** list only accounts with ≥ 3 completed matches (online matches
   played to the end, i.e. win / finish, + granted offline claims: `accounts.completed_matches`); the caller still
   gets their own rank (`me.listed: false` until then).
b. **Switching Google accounts:** a device whose account is linked to Google id A that signs in with Google id B gets
   `409 {error: "other_google", conflict: {here, there (null when B has no account)}, ticket}` and must resolve
   explicitly: `keep: "switch"` (to B's account, created when new) or `"stay"`.
c. **Ban sources:** unbanning a pid lifts its account's ban only when that pid's ban caused it
   (`accounts.ban_source` = `admin_account` | `pid:<pid>`); an account unban lifts the device pid bans it caused
   (`players.ban_source` = `admin_pid` | `account:<id>`). Details in ADMIN_API.md "Bans".
d. **Cron:** weekly score rows older than 26 weeks are pruned; rooms whose D1 row says lobby / playing 2 h after its
   last update are checked: gone → row closed, nobody online → the Room is closed (`adminClose("stale-sweep")`).

## Accounts / wallet / leaderboard HTTP API as implemented (src/accounts.ts, wallet.ts, leaderboard.ts)

Clarifications of §1, §2, §4; the admin side is in ADMIN_API.md "v2".

**Common.** JSON in and out, `Cache-Control: no-store`, bodies ≤ 32 KB. Authed calls send
`Authorization: Bearer <session>`; without a valid one → `401 {error: "unauthorized"}`; a banned account →
`403 {error: "banned", msg}`; no `SESSION_KEY` secret → `503 {error: "accounts_disabled"}`. Bad input →
`400 {error: "bad_request", msg}`. A write that kept colliding with other writes of the same account (8 tries) →
`503 {error: "busy"}` (retry). `profile` is always the whole profile in the game's save shape (`Save.profile`: name,
id, coins, xp, stats, rooms, room, dice_owned, dice, scenes, scene, daily, last_spin, last_free, avatar, av_owned,
frame, plate, badge, claimed); the client replaces its cache with it. `account` = `{id, guest, google_name,
created_at, imported, online_wins, completed_matches, version}`.

**Sessions.** `<account_id>.<exp>.<hmac>`, exp in unix seconds, 30 days. When fewer than 7 days are left, any authed
response carries a fresh one in the `X-Session` header (and `GET /v1/me` always returns the current one in `session`).
A session of a merged-away (`keep: "here"` on the other device) or banned account stops working.

| method | path | body → result |
|---|---|---|
| POST | `/v1/auth/guest` | `{pid, import?}` → `{account, session, profile, created, import?: {ok: true, notes} \| {ok: false, error: "invalid" \| "already"}}`. `import` is accepted on the account's first call, or later only while nothing has changed it (version 0). A banned pid or its banned account → 403. A new account past 20 per hour / 60 per day for the client IP → `429 {error: "rate"}` (Policy a; an existing pid is never limited) |
| GET | `/v1/me` | → `{account, profile, session}` |
| PATCH | `/v1/me` | `{name?, avatar?, frame?, plate?, badge?}` → `{ok, profile}`; `404 {error: "unknown", field}` / `409 {error: "locked", field}`; name 1–16 chars after trimming |
| POST | `/v1/auth/google` | `{server_auth_code, pid?}` → `{account, session, profile, linked: true}`; this (guest) account and a Google id on another account → `409 {error: "conflict", conflict: {here, there}, ticket}`; this account already linked to another Google player → `409 {error: "other_google", conflict: {here, there: summary \| null (no account yet)}, ticket}` (Policy b: no silent switch). Google refused the code → `401 {error: "google_rejected"}`, Google unreachable → `502 {error: "google_failed"}`, secrets unset → `503 {error: "google_not_configured"}`, the Google account is banned → 403 |
| POST | `/v1/auth/google/resolve` | `{keep, ticket \| server_auth_code, pid?}` (`ticket` from the 409, valid 10 min: a server auth code can be exchanged only once, so the client should send the ticket). After `conflict`: `keep: "there"` (or `"switch"`) → `{account, session, profile, switched: true, created: false}`; `"here"` → `{…, linked: true, merged: <other account id>}`. After `other_google`: `"switch"` (or `"there"`) → the Google player's account, created when new: `{…, switched: true, created}`; `"here"` → `409 {error: "already_linked"}`. `"stay"` (either case) changes nothing → `{account, session, profile, stayed: true}`. `pid` (this device) is moved to the chosen account so a later guest auth opens it. `400 {error: "bad_ticket"}`; a banned target → 403 |
| POST | `/v1/shop/buy` | `{kind, id}` → `{ok, profile, price, item}`; `404 unknown`, `409 owned \| locked \| coins (+short)` |
| POST | `/v1/shop/equip` | `{kind, id}` (room, dice, scene, avatar / char, frame, plate, badge; badge "" = none) → `{ok, profile}`; `404 unknown`, `409 locked` |
| GET | `/v1/rewards` | → `{today, now, daily: {state, next_at}, spin: {available, next_at, prizes}, free: {available, next_at, amount}}` (`state` = econ `dailyState`: the 7 tiles with status) |
| POST | `/v1/rewards/daily` | → `{ok, profile, coins, dice, char, day, cycle, next_at}`; `409 {error: "claimed", next_at, day, cycle}` |
| POST | `/v1/rewards/spin` | → `{ok, profile, index, prize, next_at}` (the server draws `index`); `409 {error: "spun", next_at}` |
| POST | `/v1/rewards/free` | → `{ok, profile, coins, next_at}`; `409 {error: "cooldown", next_at}` |
| POST | `/v1/achievements/claim` | `{id}` → `{ok, profile, coins, progress}`; `404 unknown`, `409 not_done \| claimed` |
| POST | `/v1/claims` | `{id (8–64 [A-Za-z0-9_-], unique per account), game, mode, result, players, duration_s, pairs?, rolls? (S&L), need_one?}` → `{ok, id, limited, granted, reason?, coins, xp, would?, profile}`; a retry with the same id → the first answer + `duplicate: true` + the current profile; malformed → `400 {error: "invalid", detail}` |
| GET | `/v1/leaderboard` | `?board=xp\|wins&period=all\|week` → `{board, period, week?, min_matches: 3, top: [{rank, name, avatar, frame, level, value}], me: {rank, value, listed} \| null}` (session optional; `me.rank` null while the value is 0; `listed: false` while the account has fewer than `min_matches` completed matches: it is not in `top`, but `rank` is still its place among the listed accounts) |

`next_at` values are unix seconds. Days (daily, spin, claim caps) start at midnight Bangladesh time; leaderboard
weeks are ISO weeks starting Monday 00:00 Bangladesh time.

**Claims in detail.** `granted`: the claim was applied (coins / XP / stats). `limited`: something was cut or nothing
was paid; `reason`: `too_short` (< 60 s Ludo / 30 s S&L), `hourly` (20 granted claims in the last 3,600 s),
`replay` (an S&L win vs Computer whose `rolls` don't replay to square 100), all three paying nothing; `daily_coins` /
`daily_xp` (the 6,000 coins / 3,000 XP of today's claims reached): the remainder is paid and the claim counts as
granted (its stats apply), unless the remainder of both is 0 (then nothing). `would` = what the claim was worth.
Limited claims are recorded too (admin sees them).

**Leaderboard scores.** `xp/all` = total XP (import included), `xp/week` = XP gained that week (claims, online
matches), `wins` = online match wins (granted by the Room via `grantOnlineMatch`). Ties share a rank; among equal
values the one that got there first is listed first. Banned and merged accounts and accounts with fewer than 3
completed matches (`completed_matches`: online win / finish + granted claims) are left out. The top list is cached
30 s (Cache API); `me` is always live. Weekly rows older than 26 weeks are pruned by the daily cron.

**For the Room / quick match** (`src/accounts.ts`): `verifySession(env, token) → {account_id} | null`,
`accountForPid(env, pid) → {account_id, banned} | null` (banned: the account or the pid),
`getPublicProfile(env, account_id) → {name, avatar, frame, level}` (defaults for an unknown id),
`grantOnlineMatch(env, {match_id, game, results: [{account_id, outcome}]})` (idempotent per match_id + account;
unknown / banned / merged accounts skipped; throws after trying everyone if a write failed, so it can be retried).
Amounts: econ `ONLINE_REWARDS` (Ludo 150 + 100 XP / 20 + 40 XP, S&L 100 + 60 XP / 10 + 25 XP, left 0); win and
finish count as a completed match (leaderboard eligibility), left doesn't.
`db.ts`: `recordQuickStat(env, {day?, game, size, queued?, matched?, ghost_filled?, wait_ms?, human_wins?,
ghost_wins?})`, `insertMatch(…, {game?, quick?, ghosts?})`, `endMatch(…, {human_won?})`,
`upsertRoom` with `RoomState.game? / public? / quick?`.

**Secrets.** `SESSION_KEY` (required for accounts), `GOOGLE_WEB_CLIENT_ID` / `GOOGLE_WEB_CLIENT_SECRET` (the Web OAuth
client of §7; optional). Locally in `server/.dev.vars`; deployed with `tools/cf.sh secret put …`.

**Economy values vs src/econ.** Aligned: the Economy decisions live in `src/econ` (`DAY_OFFSET_MIN = 360`,
`ONLINE_REWARDS` with the S&L table, `claimLimit` paying the partial remainder of the 6,000 coins / 3,000 XP per day,
S&L win claims replayed from `rolls`); `wallet.ts`, `accounts.ts`, `leaderboard.ts` and `db.ts` call econ directly
(`src/wallet_rules.ts` is gone). The offline functions the parity tests replay take the day key / clock / roll as
arguments, so the server values don't touch them.
