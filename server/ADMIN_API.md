# Ludo Zing admin console: contract v1

A small "Nakama Console"-style admin for the Cloudflare room server. Served by the same Worker:

- `GET /admin` (and `/admin/*`): the console web app (static files in `server/admin/`, Workers static assets).
  Every request reaches the Worker first (`run_worker_first: true`); it strips `/admin` and asks the `ASSETS`
  binding, so `admin/js/app.js` is `/admin/js/app.js`, `/admin` and `/admin/` are `admin/index.html`, an
  extensionless path that is not a file also gets `index.html`, and nothing in `admin/` is reachable outside
  `/admin`. Everything in `server/admin/` is public except what `admin/.assetsignore` lists (`dev/`).
  Console files and API responses carry `Content-Security-Policy: default-src 'self'; script-src 'self';
  style-src 'self'; img-src 'self' data:; font-src 'self'; connect-src 'self'; frame-ancestors 'none';
  base-uri 'none'; form-action 'self'`, `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer` (set by
  the Worker; no `_headers` file); API responses are `Cache-Control: no-store`, HTML `no-cache`.
- `/admin/api/*`: JSON API, session cookie required (except `login`).
- Data: Cloudflare **D1** database `ludo-zing-admin` (binding `DB`), migrations in `server/migrations/`.
  Room Durable Objects write to D1 only on key events (never per game action) to stay inside the free plan
  (100k row writes / 5M reads per day).

## Auth

- Secret `ADMIN_PASSWORD` (set by the owner: `tools/cf.sh secret put ADMIN_PASSWORD`; locally `.dev.vars`).
  If it is not set, every `/admin/api/*` call answers `503 {"error":"admin_disabled"}` and the console shows how to
  set it.
- `POST /admin/api/login {password}` → `204` + cookie `lz_admin=<exp>.<hmac>` (`exp` in epoch seconds;
  HMAC-SHA256 over `exp`, base64url, with the key SHA-256("lz-admin-session-v1:" + ADMIN_PASSWORD);
  `HttpOnly; Secure; SameSite=Strict; Path=/admin; Max-Age=43200`). Wrong password → `401 bad_password`.
  Login rate limit: 5 **failed** attempts per IP (`CF-Connecting-IP`) per 10 min → `429 rate_limited`, even with
  the right password (failures are rows in D1 table `login_attempts`). Changing the password invalidates all
  sessions. (`Secure` cookies work on `http://localhost`, not on a LAN IP over plain http.)
- `POST /admin/api/logout` → `204`, clears the cookie. `GET /admin/api/me` → `{ok: true}` or `401`.
- Every state-changing admin call (POST/PUT/PATCH/DELETE, `login` and `logout` included) must send header
  `X-Admin: 1` (CSRF guard; checked before the session, else `403 csrf`) and is written to `admin_log` (actions:
  `login`, `logout`, `room.close`, `room.kick`, `player.ban`, `player.unban`, `player.note`, `config.update`;
  `detail` is JSON).

## D1 schema (migrations/0001_init.sql)

```
players(pid TEXT PRIMARY KEY, name TEXT, avatar TEXT, frame TEXT, first_seen INTEGER, last_seen INTEGER,
        rooms INTEGER DEFAULT 0, matches INTEGER DEFAULT 0, wins INTEGER DEFAULT 0,
        banned INTEGER DEFAULT 0, ban_reason TEXT, note TEXT,
        last_room TEXT /* code of the latest join: where a ban kicks them */)
rooms(code TEXT PRIMARY KEY, created_at INTEGER, updated_at INTEGER, host_pid TEXT, host_name TEXT,
      status TEXT,            -- lobby | playing | over | closed
      members INTEGER, online INTEGER, settings TEXT /* json {teams, pair_ask} */, closed_reason TEXT)
matches(id INTEGER PRIMARY KEY AUTOINCREMENT, code TEXT, started_at INTEGER, ended_at INTEGER,
        players TEXT /* json [{pid, name, color, bot}] */, teams INTEGER, pair_ask INTEGER,
        winner INTEGER, finished TEXT /* json [colours] */, actions INTEGER,
        result TEXT /* playing | over | abandoned | closed */)
events(id INTEGER PRIMARY KEY AUTOINCREMENT, at INTEGER, level TEXT /* info | warn | error */, kind TEXT,
       code TEXT, pid TEXT, msg TEXT)
config(key TEXT PRIMARY KEY, value TEXT)
admin_log(id INTEGER PRIMARY KEY AUTOINCREMENT, at INTEGER, ip TEXT, action TEXT, target TEXT, detail TEXT)
login_attempts(ip TEXT, at INTEGER)                 -- failed logins only
player_days(day TEXT /* YYYY-MM-DD UTC */, pid TEXT, PRIMARY KEY (day, pid))   -- overview players_active
```
Indexes on rooms(status, updated_at), rooms(created_at), matches(started_at), matches(code, started_at),
events(at), players(last_seen), players(first_seen), login_attempts(ip, at).
Times are epoch ms. Events, login_attempts and player_days older than 30 days are pruned by a daily Cron Trigger
(03:17 UTC; v2 additions under "Cron" below), which also checks rooms rows still marked live (lobby / playing /
over) 2 h after their last update: a row whose Durable Object is gone is closed (`closed_reason` `gone`, a playing
match → `abandoned`).

## What the Room DO writes

- create (`init`) → rooms insert (status lobby). Every rooms write is an upsert of the whole row.
- member joins / leaves / goes offline or online, host or settings change → rooms.members/online/host/settings
  update (debounced: at most one write per room per 5 s, plus a final one; a status change, and `online` reaching 0
  or leaving 0, are written at once, so a paused room shows as paused right away and the last disconnect's write
  never waits on an in-memory timer).
- hello → players upsert (name, avatar, frame, last_seen, last_room; rooms+1 on the first join of a room) and a
  `player_days` row for today. A reconnect within 60 s of the last upsert of that pid is not written again.
- start → matches insert (result playing; `players` = every seat, `bot: false`), rooms.status = playing. A match is
  identified by (code, started_at).
- over → matches update (ended_at, winner, finished, actions = number of actions, result over),
  players.matches+1 and last_seen for every seat, wins+1 for the winning colour(s) (teams: both partners) unless
  that seat left the match; rooms.status = over.
- room deleted by cleanup → rooms.status = closed, `closed_reason` `stale` (2 h without action) or `empty`
  (10 min without a connection); a match still playing → result abandoned. Admin close: `closed_reason` = the
  given reason, a playing match → result closed.
- errors worth seeing → events: `error` kind `exception` (a handler threw; message + stack), `storage` (a storage
  write / setAlarm failed), `worker` (the Worker's router threw); `warn` kind `banned` (a banned pid's hello was
  refused). At most 20 events per room object per minute.
- D1 failures never break gameplay: writes are fire-and-forget (`ctx.waitUntil`), in order per room, logged to
  console on failure. The two D1 reads on the gameplay path (ban check on hello, turn timers on start) time out
  after 2 s and fail open (not banned / default timers).

## Enforcement (read by the server)

- `config.maintenance = "1"`: `POST /v1/rooms` → `503 {"error":"maintenance","msg": <motd or default>}`; existing
  rooms keep working. The game shows the message.
- `config.maintenance` is read through a per-isolate cache (10 s for `POST /v1/rooms`, 60 s for `/v1/config`);
  an admin PUT clears the cache of the isolate that served it.
- Banned pid: `hello` → `error {code: "banned", msg}` and the socket closes (4003). Checked against D1 on hello
  (one read; the DO caches per pid for 60 s). A ban also reaches the room in `players.last_room`: that member gets
  `error banned` + close 4003 and is removed (in a match their seat becomes a bot for good). Unban clears that
  room's cache; another room may keep refusing the pid for up to 60 s.
- Turn timers: `config.turn_roll_s`, `turn_choose_s`, `turn_pair_s` (integers, 5–120) override the defaults
  (15 / 20 / 10) for matches started after the change.
- Public `GET /v1/config` → `{"motd": "", "maintenance": false}` (cached 60 s) so the game can show a message of
  the day on Home.

## Paused rooms

A room is **paused** when `status = 'playing'` and `online = 0`: a match is in progress but nobody is connected.
The Room pauses its bots then (the match continues when someone reconnects) and deletes itself after 10 min with
nobody connected (`closed_reason` `empty`; any room: 2 h without an action, `stale`). The admin API reports such
rooms as paused, not as playing. It is derived, never stored: the D1 `status` stays `playing`. A lobby or an `over`
room with nobody online stays `lobby` / `over` (offline lobby members are dropped after the 20 s grace).

## Admin API

All list endpoints take `limit` (default 50, max 200) and `cursor` (opaque string from the previous page's
`next`), return `{items: [...], next: string | null}`. Rows are the D1 columns as named in the schema, with the JSON
text columns parsed (`rooms.settings` → object, `matches.players` / `matches.finished` → arrays); 0/1 flags stay
integers. Day boundaries (`today`, `days`) are UTC.

| method | path | result |
|---|---|---|
| GET | `/admin/api/overview` | `{now, live: {rooms_lobby, rooms_playing (someone online), rooms_paused (playing, nobody online), members_online}, today: {rooms, matches, players_active, new_players}, days: [{day: "YYYY-MM-DD", rooms, matches, players_active}] (last 14 days, oldest first), recent_events: [event] (last 10 warn/error), maintenance: bool}` |
| GET | `/admin/api/rooms?status=&q=` | rooms rows (q: code prefix, case-insensitive, or host name substring), newest (created_at) first. `status`: `lobby`, `playing` (online > 0 only), `paused` (playing with online = 0), `over`, `closed`. Each row has a computed `paused: bool` |
| GET | `/admin/api/rooms/:code` | `{now, room: row \| null, live: snapshot \| null, matches: [match] (last 20)}`; `room.paused` is the row's flag (as in the list), `live.paused` the live one (status playing and no member online; prefer it when `live` is set); `live` comes from the DO: `{code, status, host, created, touched, sockets, members: [{id, pid, name, avatar, frame, online, color}], settings, match: {n, state, seats: [{color, id, name, avatar, frame, bot, online, pid, left}], deadline, started_at} \| null, paused}` (null if the DO no longer exists; `match` is kept after over); 404 if neither exists |
| POST | `/admin/api/rooms/:code/close` `{reason}` (required, 3–140 chars) | closes every socket (`error not_found` + 4004), deletes the DO's storage, rooms.status = closed → `{ok: true, live: bool}` (live: a room was running) |
| POST | `/admin/api/rooms/:code/kick` `{member_id}` | that member gets `error {code: "kicked"}` and is removed (in a match: the seat becomes a bot for good), socket closed (4002) → `{ok: true}`; 404 if no such member. `member_id` = `live.members[].id`; `members[].color` −1 = no colour; `match.deadline` 0 = none |
| GET | `/admin/api/players?q=&banned=1` | players rows (q: name substring, case-insensitive, or pid prefix; banned=0/1), last_seen desc |
| GET | `/admin/api/players/:pid` | `{player: row, matches: [match] (last 20)}` |
| POST | `/admin/api/players/:pid/ban` `{reason}` (required, 3–200 chars) / `.../unban` | updates players → `{ok: true, kicked: bool, player}` (unban: `{ok: true, player}`); ban also kicks them from the room of their latest join if they are still in it (best effort); 404 for an unknown pid |
| PATCH | `/admin/api/players/:pid` `{note}` (string ≤ 500, or null / "" to clear) | updates the note → `{ok: true, player}` |
| GET | `/admin/api/matches?code=&pid=&result=` | matches rows, newest (id) first |
| GET | `/admin/api/events?level=&kind=` | events rows, newest first |
| GET | `/admin/api/config` | `{maintenance: bool, motd: string, turn_roll_s, turn_choose_s, turn_pair_s}` (unset → defaults false, "", 15, 20, 10) |
| PUT | `/admin/api/config` | same shape (partial ok) → the full config; validated (maintenance bool, motd string ≤ 140 chars, turn_* integers 5–120, unknown fields rejected) |
| GET | `/admin/api/audit` | admin_log rows, newest first |

Errors: `{error: "<code>", msg?}`: 400 `bad_request` (bad input, bad limit / cursor / filter value), 401
`unauthorized` (no session) / `bad_password`, 403 `csrf` (missing X-Admin), 404 `not_found`, 405 `method`,
429 `rate_limited`, 503 `admin_disabled`.

## v2: accounts, economy, leaderboards, quick match (ONLINE_V2.md §6)

Same rules as v1: session cookie, `X-Admin: 1` on writes (else `403 csrf`), every write audited in `admin_log`
(new actions: `account.coins`, `account.ban`, `account.unban`, `account.note`), list endpoints take
`limit` / `cursor` and return `{items, next}`, errors as above.

### D1 schema v2 (migrations/0002_accounts.sql, 0003_policy.sql)

```
accounts(id TEXT PRIMARY KEY /* "acc_" + 16 base32 */, created_at, last_seen, google_player_id TEXT UNIQUE NULL,
         google_name, public_id /* the game's LZM-XXXX-XXXX */, name, avatar, frame, plate, badge,
         coins, xp, online_wins, stats JSON, owned JSON {rooms, dice_owned, scenes, av_owned},
         equipped JSON {room, dice, scene}, rewards JSON {daily, last_spin, last_free}, achievements JSON {claimed},
         banned, ban_reason, note, merged_into NULL /* retired by a Google "keep here" */, imported,
         version /* +1 per write */, rev /* write token: optimistic concurrency */)
devices(pid TEXT PRIMARY KEY, account_id, first_seen, last_seen)        -- device id -> account
ledger(id, account_id, at, delta_coins, delta_xp, reason, ref, balance_after)
   -- reason: start (the first 5,000) | import | buy | daily | spin | free | achievement | claim | match | admin
claims(id /* client id */, account_id, at, game, mode, payload JSON, coins, xp, granted, limited, reason, result JSON,
       PRIMARY KEY (account_id, id))
scores(account_id, board /* xp | wins */, period /* all | week:YYYY-Www */, value, updated_at, PK (account_id, board, period))
match_grants(match_id, account_id, at, game, outcome, coins, xp, PK (match_id, account_id))
quick_stats(day /* UTC */, game, size, queued, matched, ghost_filled, wait_ms_total, human_wins, ghost_wins,
            PK (day, game, size))
rooms   + game TEXT DEFAULT 'ludo', public INTEGER DEFAULT 0, quick INTEGER DEFAULT 0
matches + game TEXT DEFAULT 'ludo', quick INTEGER DEFAULT 0, ghosts INTEGER DEFAULT 0, human_won INTEGER
-- 0003_policy.sql
accounts + completed_matches INTEGER DEFAULT 0 /* online win / finish + granted claims; leaderboards need 3 */,
           ban_source TEXT /* admin_account | pid:<pid> */
players  + ban_source TEXT /* admin_pid | account:<account id> */
guest_creations(ip /* HMAC of the client IP, IPv6 per /64 */, at)   -- the guest rate limit; pruned after a day
```
`players` stays the per-pid table of the rooms (the Players page works as before); `devices` links a pid to its
account. Sum of an account's `ledger.delta_coins` = its coins.

### Bans

- An account ban (`accounts.banned`) refuses its sessions (`403 banned` on every `/v1` account call, `null` from
  `verifySession`), guest auth from its devices, and a room `hello` from any of its pids (`D.readBan` checks the pid
  and the pid's account).
- **Ban sources** (policy, lead 2026-10-24): a ban records what caused it, and an unban lifts only the bans it
  caused. `accounts.ban_source`: `admin_account` (Accounts page) or `pid:<pid>` (that device's ban);
  `players.ban_source`: `admin_pid` (Players page) or `account:<account id>` (that account's ban). Account bans from
  before migration 0003 are backfilled as `pid:<pid>` when a device of the account has a pid ban with the same
  reason, else `admin_account`; existing pid bans as `admin_pid`.
- `POST /admin/api/players/:pid/ban` (source `admin_pid`, also over an account-caused pid ban) also bans the pid's
  account with source `pid:<pid>`, unless the account is already banned (then the account ban, its reason and
  source stay). A device without a `players` row gets one. `.../unban` lifts the pid ban, and the account ban only
  when its source is `pid:<this pid>`; if another device of the account still has an `admin_pid` ban, that one
  becomes the account ban's source (and reason) instead. The responses gain `account_id` (null when none) and
  `account_banned` (the account's state after; null without an account); `GET /admin/api/players/:pid` gains
  `account_id`.
- `POST /admin/api/accounts/:id/ban` (source `admin_account`, also over a pid-caused account ban) also bans every
  device pid of the account that is not banned yet (source `account:<id>`, same reason). `.../unban` lifts the
  account ban and every pid ban with source `account:<id>`; pid bans from the Players page stay and are listed in
  `still_banned_pids` (also in the audit detail).

### Endpoints

| method | path | result |
|---|---|---|
| GET | `/admin/api/accounts?q=&banned=0\|1&linked=0\|1` | account rows, `last_seen` desc. `q`: name substring, account id prefix, device pid prefix, exact Google player id or `LZM-` id. Rows: the columns with the JSON ones parsed, plus `level` and `linked` (no `rev`) |
| GET | `/admin/api/accounts/:id` | `{now, account, devices: [row], ledger: [row] (last 50), claims: [row with payload parsed] (last 50), grants: [match_grants row] (last 20), matches: [match] (last 20, by its pids or players[].account_id)}` |
| POST | `/admin/api/accounts/:id/coins` `{delta, reason}` | delta: non-zero integer, \|delta\| ≤ 1,000,000; reason 3–200 chars. Ledger row reason `admin`, `ref` = the reason (not counted as coins earned) → `{ok: true, coins, account}`; `409 {error: "coins", coins}` if the balance would go below 0 |
| POST | `/admin/api/accounts/:id/ban` `{reason}` (3–200) / `.../unban` | → `{ok: true, kicked: n, account}` (unban: `{ok: true, account, still_banned_pids: [pid]}`); kicks its devices from the room of their latest join (best effort); bans / lifts device pid bans per "Ban sources" |
| PATCH | `/admin/api/accounts/:id` `{note}` (≤ 500, null / "" clears) | → `{ok: true, account}` |
| GET | `/admin/api/leaderboards?board=xp\|wins&period=all\|week&week=YYYY-Www&limit=` | `{board, period, week (null for all), total, top: [{rank, account_id, name, avatar, frame, level, value, updated_at}]}`; `week` picks a past week (period=week only; weeks older than 26 are pruned); limit 1–200 (default 50). The same population as the public board: banned / merged accounts and accounts with fewer than 3 `completed_matches` are left out (also of `total`) |
| GET | `/admin/api/quick?days=14` | days 1–90 → `{days, from, rows: [{day, game, size, queued, matched, ghost_filled, ghost_fill_rate, avg_wait_ms, human_wins, ghost_wins, human_win_rate}] (newest first), totals: [same, day "total", per game + size]}`. `ghost_fill_rate` = ghost seats / (matched humans + ghost seats); `avg_wait_ms` = wait_ms_total / matched; `human_win_rate` = human_wins / (human_wins + ghost_wins); null when the divisor is 0 |
| GET | `/admin/api/overview` | v1 fields plus `accounts: {total, linked, guests, banned, new_today (UTC), coins_in_circulation, claims_limited_today (Bangladesh day)}` (merged accounts not counted) |

`account_id` in paths must look like `acc_` + 16 of `[a-z2-7]`, else `404`. Account rows carry the new columns
`completed_matches` and `ban_source`.

### Cron (v2)

The daily cron (`src/cron.ts`) also deletes `scores` rows of weeks more than 26 weeks before the current one
(`period < "week:<the week 26 weeks back>"`; `all` rows stay) and `guest_creations` rows older than a day. Its room
check covers rows in lobby / playing / over not updated for 2 h: a gone Durable Object → row closed `gone` (as in
v1); a lobby / playing room that exists but whose `adminSnapshot` shows nobody online (no socket, no human member
online; ghosts don't count) → closed through the Room's `adminClose("stale-sweep")` (`closed_reason`
`stale-sweep`; the Room records a match still playing as `closed`); a room with someone online, or in `over`
(its own alarm deletes it), is left alone. Returns `{pruned: {events, login_attempts, player_days,
guest_creations, scores}, reconciled, swept, weekly}` (`weekly`: the weekly-result pushes queued on a Monday,
Bangladesh time, else `null`; see "Notifications"). It also deletes `push_events` rows older than 30 days.

## Notifications (NOTIFICATIONS.md "N-SRV")

Push notifications through Firebase Cloud Messaging. Secret `FCM_SERVICE_ACCOUNT` (the Firebase project's
service-account JSON, whole: `tools/cf.sh secret put FCM_SERVICE_ACCOUNT`); unset (or not a service-account JSON)
= push off: `GET` answers with `configured: false`, preview works, campaign and test sends answer
`409 {error: "push_off"}`. Same rules as v1 (session cookie, `X-Admin: 1` on writes, audited: actions
`push.campaign`, `push.test`, `push.cancel`). Bulk sends go through the `Pusher` Durable Object (a queue drained by
its alarm, at most 40 sends per invocation); a campaign's status and counters are updated as it goes.

### D1 schema (migrations/0004_push.sql)

```
push_tokens(token TEXT PRIMARY KEY /* FCM registration token */, account_id, platform /* android */,
            prefs_game, prefs_offers /* 0 | 1: the game's Game alerts / News & offers toggles */,
            tz_offset_min NULL, created_at, updated_at)         -- an account keeps its 5 latest tokens
push_campaigns(id TEXT PRIMARY KEY /* cmp_ + 12 base32 */, title, body, link, audience JSON,
               status /* draft | scheduled | sending | sent | canceled | failed */, run_at NULL, created_by,
               created_at, sent_at NULL, targeted, sent, failed, opened)
push_opens(cid, account_id, at, PRIMARY KEY (cid, account_id))   -- POST /v1/push/opened, once per account
push_events(day /* UTC */, kind /* turn | joined | rematch | weekly */, sent, failed, PRIMARY KEY (day, kind))
```
Times are epoch ms (as everywhere in D1).

### Endpoints

| method | path | result |
|---|---|---|
| GET | `/admin/api/push` | `{now, configured, project_id (null when off), tokens: {total, offers, game} (devices; offers / game: with that toggle on), events: [{day, kind, sent, failed}] (event pushes, the last 14 UTC days, oldest first, days without pushes left out), campaigns: [campaign] (the latest 50, newest first), limits: {campaigns_per_day: 4, campaigns_left, tests_per_hour: 20, tests_left}}` |
| POST | `/admin/api/push/campaigns` `{title (1–60), body (1–180), link?, audience, run_at?}` | → the campaign. `run_at` (unix seconds, or epoch ms; at most 30 days ahead) in the future → `status: "scheduled"`, sent then; absent / past → `"sending"`, queued now. `targeted` is the estimate at creation (the preview count), replaced by the devices actually sent to. `429 rate_limited` past 4 campaigns in the last 24 h (canceled ones don't count) |
| POST | `/admin/api/push/preview` `{audience}` | → `{targeted}`: the devices the audience reaches now (nothing sent) |
| POST | `/admin/api/push/test` `{title, body, link?, account_id}` | sends to every device of that account now (whatever its toggles; channel `offers`, `kind: "test"`, no `cid`) → `{sent, failed, tokens}`; `404` unknown account; `429 rate_limited` past 20 test sends in the last hour (counted in `admin_log`) |
| POST | `/admin/api/push/campaigns/:id/cancel` | a scheduled campaign → the campaign with `status: "canceled"`; any other status → `409 {error: "bad_state"}`; unknown id → 404 |

`campaign` = the `push_campaigns` row with `audience` parsed: `{id, title, body, link, audience, status, run_at,
created_by: "admin", created_at, sent_at, targeted, sent, failed, opened}` (times epoch ms).

- `link`: one of `home` (default), `daily`, `spin`, `free`, `shop`, `shop:<kind>:<id>`, `room:<CODE>`,
  `leaderboard`; anything else → 400.
- `audience`: `{kind: "all"}`: one send to the FCM topic `promos` (every device with News & offers on subscribes to
  it); `targeted` = devices with offers on, `sent` = `targeted` when FCM accepted it (else `failed` = `targeted`,
  status `failed`). `{kind: "segment", inactive_days?, new_days?, level_min?, level_max?}` (integers; days 1–365,
  levels 1–500, `level_min ≤ level_max`; no filters = every device with offers on): one send per device with
  `prefs_offers` of accounts that are not banned or merged and match **all** given filters: `inactive_days` — last
  seen (or, never seen, created) more than N days ago; `new_days` — created within the last N days; `level_min` /
  `level_max` — the level from the account's XP. Unknown filters → 400.
- Delivery: `sent` / `failed` per device as FCM answers; a token FCM calls unregistered (or not a valid registration
  token, or of another sender) is deleted and counted failed; FCM busy / unreachable is retried after 1 and 2 min,
  then counted failed. Status `sent` when the queue is done (`failed` if nothing was delivered and something
  failed). `opened` = accounts that opened it (`POST /v1/push/opened {cid}` from the game, once per account).

## Usage (Cloudflare free-plan allowances)

`GET /admin/api/usage` (session required) reads the Cloudflare GraphQL Analytics API
(`https://api.cloudflare.com/client/v4/graphql`, `src/usage.ts`) and returns today's (UTC day; every daily
allowance resets at 00:00 UTC) use against the Workers Free limits. The limits are per **account**, so totals cover
every Worker / Durable Object / D1 database of the account; `mine` is this Worker's share. The limits table
(`FREE_LIMITS`) cites the Cloudflare doc pages and the date they were checked. Secret `CF_API_TOKEN` = an API token
with **Account > Account Analytics > Read** on the account (`tools/cf.sh secret put CF_API_TOKEN`); optional var
`CF_ACCOUNT_ID` overrides the built-in account id. Cached 5 minutes per isolate; all HTTP goes through
`setCloudflareFetcher` (tests).

- No token: `200 {configured: false, now, reset_at, account_id, worker, metrics: [{id, label, group, unit, period,
  limit, note}], info, setup: {secret, permission, steps: [string]}}`.
- Configured: `200 {configured: true, now, cached_at, stale, reset_at (ISO, next 00:00 UTC), account_id, worker,
  metrics: [{id, label, group: workers|do|d1, unit: count|gbs|bytes, period: day|total, used, limit, left, percent
  (0–100, 1 decimal), level: ok|warning (≥70)|danger (≥90), note, mine? (workers_requests, do_requests)}],
  hourly: {hours: [ISO hour, today 00:00 UTC … now], <daily metric id>: [number per hour]},
  daily: [{day, <daily metric id>…}] (last 7 UTC days, oldest first),
  estimate: {games_left: int | null, basis: "today" | "7d" | null, matches, limiting: metric id, per_game: {id: cost}},
  do_requests_by_type, info: [{label, value}] (per-request limits, not daily), sampling}`.
  Metric ids: `workers_requests`, `do_requests`, `do_duration` (GB-s), `do_rows_read`, `do_rows_written`,
  `do_storage` (total, no reset), `d1_rows_read`, `d1_rows_written`, `d1_storage` (largest database vs 500 MB; also
  `total_bytes`, `databases`). Durable Object requests count incoming WebSocket messages 20 to 1.
  `estimate` = games left before the tightest metric runs out, at the per-match cost seen so far (today's numbers if
  ≥ 5 matches started today, else the last 7 days) from D1 `matches`; a rough guess, other traffic is in the cost.
- Cloudflare refused / unreachable: `200` with the last good body and `stale: true, error_msg` if it is from today,
  else `502 {error: "cloudflare_failed", msg}`.
