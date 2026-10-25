# Notifications: shared contract (2026-10-25)

ONLINE_V2.md §8, built in four parts that meet at the interfaces below: N-PLUG (Android plugin + GDScript wrapper),
N-GAME (game side), N-SRV (server push core), N-ADMIN (console page). Everything works with push switched off:
until a Firebase project exists (owner step, "Setup" at the end), local notifications run, the server stores
nothing new and sends nothing, and the console page says "Push not configured".

## Ids and texts
Android notification channels (created by the plugin, names shown in the system settings):
| channel id | name | used by |
|---|---|---|
| `rewards` | Rewards | local: daily reward / spin / free coins ready |
| `reminders` | Reminders | local: come-back nudges |
| `game` | Game alerts | push: your turn, friend joined, rematch, weekly result |
| `offers` | News & offers | push: admin promos |

Deep links (`link`, a string, in both local and push data; unknown → just open the home screen):
`home`, `daily`, `spin`, `free`, `shop`, `shop:<kind>:<id>`, `room:<CODE>` (rejoin / open that friend room),
`leaderboard`. A campaign push also carries `cid` (campaign id, for the open stats).

Game copy uses "Ludo Zing" (never "Ludo King"), short and friendly, English.

## N-PLUG: Android plugin `NotificationsPlugin` (Kotlin AAR, `godot/android/plugins/notifications/`)
Same build setup as `godot/android/plugins/play_games/` (AGP 8.6.1, Kotlin 2.1.21, Java 17, compileSdk 36, minSdk 24,
`compileOnly org.godotengine:godot:4.7.2.stable`), its own `godot/addons/notifications/` editor + export plugin
(AARs in `addons/notifications/bin/`, Maven deps added by the export plugin, manifest additions in the AAR manifest).
Engine singleton name `NotificationsPlugin`.

Local (no Firebase): AlarmManager (inexact `setAndAllowWhileIdle`, no exact-alarm permission) → a BroadcastReceiver
posts the notification; scheduled items persist in SharedPreferences and are re-armed by a `BOOT_COMPLETED` receiver
(and dropped once past). Small icon: a white monochrome silhouette drawable in the AAR (not the launcher icon).
Tapping opens the game's launcher activity with the extras `lz_link` and (push) `lz_cid`, `lz_source`
(`local` | `push`).

Methods (all safe to call any time; results via signals, never thrown):
- `permission_state() -> String`: `granted` | `denied` (asked and refused or permanently blocked) | `ask` (may ask)
  | `unsupported`. Below Android 13 always `granted` unless the app's notifications are off in settings (`denied`).
- `request_permission()` → signal `permission_result(granted: bool)` (Android 13+ POST_NOTIFICATIONS dialog; below
  13 answers at once with the current state).
- `schedule(id: String, at_unix: int, channel: String, title: String, body: String, link: String)` (replaces the
  same id), `cancel(id: String)`, `cancel_all()` (local only), `scheduled() -> Array` of ids.
- `take_launch_data() -> Dictionary`: `{link, cid, source}` of the notification that opened the app (cold start or
  `onNewIntent`), once, then `{}`. Also signal `opened(data: Dictionary)` when tapped while the game is running.
- Push (FCM, initialised manually with `FirebaseOptions`, no google-services.json / Gradle plugin):
  `push_init(project_id, app_id, api_key, sender_id)` → signal `push_token(token: String)` (also on refresh) or
  `push_failed(code: String)`; `push_subscribe(topic)`, `push_unsubscribe(topic)`; `push_delete_token()`.
  A push arriving while the game is in the foreground → signal `push_received(data: Dictionary)` (`title`, `body`,
  `link`, `cid`, `kind`) and no system notification; in the background the system shows it (FCM notification
  message, channel from `android.notification.channel_id`).

GDScript wrapper `godot/scripts/net/notifier.gd`, `class_name Notifier extends Node`, same style as `play_games.gd`:
a safe stub without the plugin (desktop, headless, tests: `is_available()` false, `permission_state()` "unsupported",
schedule calls recorded in `stub_scheduled` for tests); constructor takes an optional fake singleton. Project
settings `ludo_zing/push/project_id`, `.../app_id`, `.../api_key`, `.../sender_id` (empty = push off).
Export: debug + release Gradle presets enable the plugin; `POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED` permissions.

## N-GAME: game side (GDScript)
- **Settings sheet:** a Notifications switch (master) + toggles Rewards, Reminders, Game alerts, News & offers
  (Save.settings keys `notif` (bool, default true), `notif_rewards`, `notif_reminders`, `notif_game`,
  `notif_offers`, all default true). Turning the master on while permission is `ask` requests it; `denied` shows a
  one-line hint "Turn on notifications for Ludo Zing in your phone settings".
- **Permission moment:** never at launch. After the player's first win (any mode), once: an in-game soft prompt
  ("Get a heads-up when your free spin and daily reward are ready?" Not now / Yes) → Yes calls
  `request_permission()`. Not now: ask again after the next win at least 3 days later, at most 3 times in all.
  `Save.settings.notif_asked` (count) and `notif_asked_at`.
- **Local schedule** (pure policy `scripts/core/notif_plan.gd`, `NotifPlan.plan(now_unix, tz_offset_s, state)
  -> Array[{id, at, channel, title, body, link}]`, unit-tested): run on every app pause/close (cancel_all then
  schedule) and cancel_all on resume/launch (the player is here). Inputs: the reward times (server `/v1/rewards`
  `next_at` when signed in, else the offline rules), the last play time, the toggles.
  - Rewards: one reminder per calendar day at most: the earliest of daily / spin / free that is ready, fired at
    `max(ready_at, close_time + 2 h)`, text naming everything ready by then ("Your daily reward and a free spin are
    waiting"), link to the first. Only the next 2 days are scheduled.
  - Come-back: 1, 3 and 7 days after the last close (one each, then nothing until the player returns), copy that
    varies (a small pool, seeded by the day), link `home`.
  - Quiet hours 22:00–09:00 local time: a time inside them moves to 09:00 + a stable 0–40 min jitter. Never two
    notifications within 3 h of each other (a later one moves on; a come-back on a reward day is dropped).
- **Push registration:** with the push settings present and an account session: `push_init`, then on `push_token`
  → `POST /v1/push/token`; subscribe the topic `promos` when `notif` and `notif_offers` are on, unsubscribe
  otherwise; re-send prefs on every toggle change. Sign-out / account switch → `DELETE /v1/push/token`.
- **Away signal (online rooms):** on app pause / resume while connected send `{t: "away", on: true|false}`.
- **Opens:** on launch / `opened` / `push_received` tap: route the `link` (home, daily → daily sheet, spin → spin
  sheet, free → the free-coins button / shop, shop[:kind:id] → shop on that item, room:CODE → rejoin that room via
  the existing online flow, leaderboard → leaderboard sheet), and when `cid` is set `POST /v1/push/opened {cid}`.
  A push received in the foreground of kind `turn` for the room on screen is ignored; others show an in-game toast
  (tap = the link).

## N-SRV: server push core
Secrets (optional; unset = push off, every send is a no-op, endpoints still answer): `FCM_SERVICE_ACCOUNT` (the
service-account JSON of the Firebase project, whole). Project id from it.

- **FCM sender (`src/push.ts`):** OAuth access token via a JWT (RS256, WebCrypto, PKCS8 key from the JSON; scope
  `https://www.googleapis.com/auth/firebase.messaging`), cached in memory until 5 min before expiry. `POST
  https://fcm.googleapis.com/v1/projects/<id>/messages:send` with `{message: {token | topic, notification: {title,
  body}, data: {link, kind, cid?}, android: {priority: "high" (game) | "normal" (offers), ttl, collapse_key,
  notification: {channel_id, tag}}}}` (`kind`: `turn` | `joined` | `rematch` | `weekly` | `promo` | `test`).
  `UNREGISTERED` / `SENDER_ID_MISMATCH`, or `INVALID_ARGUMENT` whose message is about the registration token, on a
  token → that token row is deleted (any other `INVALID_ARGUMENT` is our message: counted failed, token kept); 429 /
  5xx / network errors are retried by the Pusher (after 1 and 2 min, then failed); a 401 renews the access token once.
  All HTTP through a replaceable fetcher (`setPushFetcher`, like `setGoogleFetcher`) so tests use a fake FCM
  (`setPushServiceAccount` stands in for the secret in tests).
- **Free-plan budget:** a Worker invocation may make at most 50 subrequests, so bulk sends never happen inline: a
  singleton Durable Object `Pusher` (SQLite) holds a queue of jobs and an alarm drains at most 40 sends per
  invocation, re-arming while work is left; scheduled campaigns are jobs with a `run_at`. Single event pushes from a
  Room go straight out (1–2 subrequests) in `ctx.waitUntil`. A segment campaign is paged out of D1 into the queue
  (500 tokens per alarm) when it starts, so `targeted` ends up as the devices actually sent to.
- **D1 (migration `0004_push.sql`):** `push_tokens (token PRIMARY KEY, account_id, platform, prefs_game, prefs_offers,
  tz_offset_min, created_at, updated_at)` (+ index on account_id); `push_campaigns (id, title, body, link, audience
  JSON, status draft|scheduled|sending|sent|canceled|failed, run_at, created_by, created_at, sent_at, targeted, sent,
  failed, opened)`; `push_opens (cid, account_id, at, PRIMARY KEY (cid, account_id))`; `push_events (day, kind, sent,
  failed)` for the event-push counters (UTC days, PRIMARY KEY (day, kind), pruned after 30 days). Times epoch ms;
  campaign ids `cmp_` + 12 base32 chars.
- **HTTP (authed with the session, ONLINE_V2.md "Common"):** `POST /v1/push/token {token, platform: "android",
  prefs: {game, offers}, tz_offset_min}` → `{ok}` (a token moves to this account if another one had it; ≤ 5 tokens
  per account, oldest dropped); `DELETE /v1/push/token {token}` → `{ok}`; `POST /v1/push/opened {cid}` (session
  optional; idempotent per account) → `{ok}`. Push off → the same answers (tokens are still stored, nothing sent).
  As built: `token` 32–1024 chars of `[A-Za-z0-9_:.-]`; `platform` optional, only `"android"`; `prefs.game` /
  `prefs.offers` optional (default true); `tz_offset_min` optional integer −840..840; bad input → `400 bad_request`.
  `DELETE` removes the token only if it belongs to the caller's account. `opened` counts only with a valid session
  (pushes reach accounts' devices only) and only for an existing campaign; without one it still answers `{ok}`.
- **Event pushes (channel `game`, only to accounts with `prefs_game`):**
  - Room protocol addition: client → server `{t: "away", on: bool}` (any time; ignored for unknown members). A member
    counts as away when it said so or has no open socket. Kept on the socket only (a new connection is not away); no
    reply; a non-bool `on` → `bad_message` (PROTOCOL.md "Away and event pushes").
  - "It's your turn" (`kind: "turn"`, link `room:<CODE>`): friend rooms, a turn starts for an away member with an
    account; at most once per member per 3 minutes and once per turn; never ghosts, never quick rooms. Body
    "<Name> is waiting for you in room <CODE>". As built: a turn starts = its `roll` phase with a person (not a bot)
    holding the seat; `<Name>` is someone else in the room who is not away (the host first), and with nobody there
    (everyone away) no push is sent (nobody is waiting).
  - "Friend joined" (`kind: "joined"`): a member joins the lobby while the host is away. Body "<Name> joined your room
    <CODE>"; at most once per host per 3 minutes.
  - "Rematch?" (`kind: "rematch"`): a rematch / new round opens in a friend room and a member is away. As built: when
    a match ends (`over`, the room back under lobby rules), to each away member while someone is here; body "<Name>
    wants a rematch in room <CODE>"; at most once per member per 3 minutes.
  - "Weekly result" (`kind: "weekly"`, link `leaderboard`): the daily cron on Monday (Bangladesh time) enqueues one
    push per listed account of last week's XP board top 100 ("You finished #N on last week's board!"), through the
    Pusher. As built: title "Weekly results are in"; one push per device with `prefs_game`; queued once per week
    (a re-run of the cron the same week queues nothing); listed = the public board's population (≥ 3 completed
    matches, not banned / merged).
  - All event pushes use `collapse_key` / `tag` per room (turn) so a phone shows one, and a 30 min TTL (weekly 1 day).
    As built: tag `room:<CODE>` for all three room pushes (turn, joined, rematch), `weekly` for the weekly result;
    a campaign's tag is its id, TTL 1 day.
- **Admin API (ADMIN_API.md conventions: admin cookie, audit entry per write):** `GET /admin/api/push` → `{configured,
  tokens: {total, offers, game}, events: last 14 days counters, campaigns: [...latest 50]}`; `POST
  /admin/api/push/campaigns {title (≤ 60), body (≤ 180), link?, audience, run_at?}` → campaign (status `scheduled`
  when run_at is in the future, else `sending` and queued now); `audience` = `{kind: "all"}` (topic `promos`, one
  send) | `{kind: "segment", inactive_days?, new_days?, level_min?, level_max?}` (tokens with `prefs_offers` of
  accounts matching all given filters: last_seen older than N days / created within N days / level range);
  `POST /admin/api/push/preview {audience}` → `{targeted}` (count, without sending); `POST
  /admin/api/push/test {title, body, link?, account_id}` → sends to that account's tokens now → `{sent, failed}`;
  `POST /admin/api/push/campaigns/:id/cancel` (scheduled only). Rate limits: at most 4 campaigns per day, test
  sends 20 per hour. Delivery stats per campaign: targeted / sent / failed / opened.
  As built (full table in ADMIN_API.md "Notifications"): `GET` also has `now`, `project_id` and `limits:
  {campaigns_per_day, campaigns_left, tests_per_hour, tests_left}`; `events` = `[{day, kind, sent, failed}]` rows
  (UTC days, oldest first). The create and cancel calls answer with the campaign object itself (`audience` parsed,
  times epoch ms; `run_at` is accepted as unix seconds or epoch ms, at most 30 days ahead). `link` must be one of the
  deep links above (default `home`). Segment filters: integers, days 1–365, levels 1–500; "inactive" = last seen (or
  created, never seen) more than N days ago; banned / merged accounts never get promos. Test sends go to every
  device of the account whatever its toggles (channel `offers`, `kind: "test"`, no `cid`) → `{sent, failed,
  tokens}`. Push off: `configured: false`, preview still works, campaign and test sends → `409 push_off`. Limits:
  4 campaigns in any 24 h (canceled ones don't count), 20 test sends in any hour → `429 rate_limited`; cancel of a
  non-scheduled campaign → `409 bad_state`. Audit actions `push.campaign`, `push.test`, `push.cancel`.

## N-ADMIN: console page
`server/admin/js/pages/notifications.js` in the console's existing style (pages, api.js, ui.js, table.js): a
"Push not configured" banner when `configured` is false (everything still visible, sends disabled); a compose form
(title, body with counters, deep link picker from the list above, audience: everyone / segment filters with a live
"≈ N players" from `/preview`, send now / schedule date-time in Bangladesh time), a "Send test to account" field, a
phone-style preview of the notification, the campaigns table (status, when, targeted / sent / failed / opened,
cancel for scheduled) and the event-push counters (14 days). Nav entry "Notifications".

## Setup (owner, later, in Chrome with approval per step)
Create the Firebase project for `com.flipfold.ludozing` (Android app), copy the 4 config values into the project
settings `ludo_zing/push/*`, create a service-account key for FCM and store it with `tools/cf.sh secret put
FCM_SERVICE_ACCOUNT`. Until then push stays off and everything else works.
