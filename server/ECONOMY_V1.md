# Economy v1: Coins + Gems, coin tables, re-rolls, rewarded ads, gem purchases

Owner's goal (2026-10-26). The server decides every coin and gem change; the game only shows what the server says.
This file is the contract between the server (`server/src/`), the game (`godot/`) and the admin console. Earlier
rules stay as written in ONLINE_V2.md and `src/econ/README.md` unless this file changes them.

## 0. Numbers at a glance

| Thing | Value |
|---|---|
| Starting coins (new profiles) | **2,500** (was 5,000). Existing accounts and saves keep their balance |
| Starting gems / free re-rolls | 0 / 0 |
| Coin tables (quick match, Ludo and S&L, 2 and 4 players) | Practice (free) · 100 · 500 (open from the start; owner 2026-10-30) · 2,000 (level 6) · 10,000 (level 10) · 50,000 (level 15) |
| Table fee | **5%** of the pot (was 10%; owner 2026-10-31) |
| Payout | The pool = the pot minus the fee (rounded down). 2 players: the winner gets the pool. 4 players: 1st **60%**, 2nd **30%**, 3rd **10%** of the pool, each rounded down, the remainder to the house (was 75 / 25; owner 2026-10-31) |
| House bonus | 1st place at a paid table also gets **20% of the pool** as new coins, on top of the pot (ledger `table_bonus`). Not for ghosts, not at Practice (owner 2026-10-31). E.g. 100 table: 2 players 190 + 38 = 228; 4 players 228 + 76 = 304 (2nd 114, 3rd 38) |
| Practice table | XP as before (ONLINE_REWARDS), coins: win 50, finish 10 |
| Friend rooms | Free (ONLINE_REWARDS): Ludo win **300**, finish **50**; S&L **200** / **25** (was 150 / 20 and 100 / 10; owner 2026-10-31). XP unchanged |
| Nobody connected (quick match) | The match freezes; back within 2 min resumes it; else it ends, settled by progress (§3 "Nobody connected"; owner 2026-10-31) |
| Broke | Coins < 100 (can't afford the cheapest table): a **daily bonus of 300 coins** (once per Bangladesh day) and the **refill ad** (500 coins) |
| Re-roll | Once per player per match, online matches only (quick and friend rooms). Costs **1 free re-roll** (if you have one) else **5 gems** |
| Rewarded ads (max 8 a day) | `reroll` +1 free re-roll (3/day) · `refill` +500 coins, only while broke (2/day) · `double` the coin payout of a won coin-table match again (2/day) · `gems` +2 gems (1/day) |
| Gems earned | Level-up +5 per level · weekly boards (XP and wins, last week): 1st 50, 2nd 30, 3rd 20, 4th–10th 10 · each achievement +10 · `gems` ad +2 |
| Gem prices in the shop | Every paid item can also be bought for `ceil(price / 100)` gems (rooms, dice, scenes, characters, emote packs) |
| Gems → Coins exchange | 10 → 1,000 · 50 → 5,500 · 120 → 14,000 (one way) |
| Gem packs (Google Play, consumable) | `gems_80` 80 · `gems_220` 220 · `gems_500` 500 · `gems_1200` 1,200. Prices are set in Play Console (Bangladesh taka tiers), not here |

Server-only values live in `src/econ/rules.ts` (`ECON_V1`). Values the offline game also uses (starting coins,
`gems` / `rerolls` profile fields, gem prices of shop items) come from the GDScript catalog through
`catalog.json` and are parity-tested.

## 1. Profile and storage

- Profile (GDScript `Save._ensure` and `src/econ/profile.ts normalizeProfile`): new int fields **`gems`** (≥ 0,
  default 0) and **`rerolls`** (free re-rolls held, 0–9, default 0). `coins` default 2,500.
- D1 migration `0005_economy.sql`:
  - `accounts.gems INTEGER NOT NULL DEFAULT 0`, `accounts.rerolls INTEGER NOT NULL DEFAULT 0`.
  - `ledger.delta_gems INTEGER NOT NULL DEFAULT 0`, `ledger.gems_after INTEGER`.
    New reasons: `entry`, `entry_refund`, `payout`, `broke`, `reroll`, `ad`, `iap`, `iap_void`, `exchange`,
    `level`, `weekly`, `buy` (gems too). Sum of an account's `delta_gems` = its gems (as for coins).
  - `entries(id PK, account_id, at, game, size, tier, amount, status, room, match_id, payout, settled_at)`: one coin
    table entry. `status`: `held` (taken at queue time) → `refunded` | `playing` (seated in a room) → `settled`
    (paid out; `payout` may be 0) | `forfeit` (left the match) | `refunded` (match abandoned / never started).
  - `rerolls(match_id, account_id, at, paid)` PK (match_id, account_id): once per match. `paid` = `free` | `gems`.
  - `ad_rewards(nonce PK, account_id, kind, ref, created_at, status, tx_id UNIQUE, granted_at, amount)`.
    `status`: `pending` → `granted` | `expired` | `rejected`.
  - `purchases(token PK, account_id, product_id, order_id, at, gems, status, voided_at)`. `status`: `granted` |
    `voided`.
  - `weekly_prizes(period, board, account_id, rank, gems)` PK (period, board, account_id).
- Every write still goes through `accounts.ts mutate` (one D1 batch, optimistic concurrency, ledger row).
  `mutate` also gives **level-up gems**: when a write raises the level, it adds 5 gems per level gained and a
  second ledger row (`level`, ref = the new level).

## 2. HTTP API (game)

All need `Authorization: Bearer <session>`; errors as in ONLINE_V2.md. Every success returns the new `profile`
(which now has `gems` and `rerolls`).

| Method | Path | Body → answer |
|---|---|---|
| POST | `/v1/shop/buy` | `{kind, id, currency?: "coins" \| "gems"}` (default coins). Errors as before plus `gems` (+`short`) |
| POST | `/v1/gems/exchange` | `{pack: 0 \| 1 \| 2}` (10 / 50 / 120 gems) → `{ok, profile, gems, coins}` · 409 `gems` (+`short`) |
| GET | `/v1/tables` | → `{tables: [{id, entry, level, unlocked, affordable}], fee_pct: 10, broke: bool, broke_bonus: {available, next_at, amount}}` |
| POST | `/v1/rewards/broke` | → `{ok, profile, coins}` · 409 `not_broke` · 409 `claimed` (+`next_at`) |
| POST | `/v1/ads/start` | `{kind, ref?}` (`ref` = match id for `double`) → `{ok, nonce, user_id, custom_data, left}` · 409 `cap` (+`next_at`) · 409 `not_eligible` (refill while not broke; double for a match you didn't win at a coin table, older than 15 min, or already doubled) |
| GET | `/v1/ads/status?nonce=` | → `{status: "pending" \| "granted" \| "expired" \| "rejected", kind, amount?, profile?}` |
| GET | `/v1/ads/ssv?...` | AdMob server-side verification callback (no session; signature-checked). 200 on success / duplicate, 400 bad signature |
| GET | `/v1/ads/today` | → `{left: {reroll, refill, double, gems}, total_left}` |
| POST | `/v1/iap/verify` | `{product_id, token}` → `{ok, profile, gems}` (also for a token granted before: `duplicate: true`) · 409 `pending` (not paid yet) · 409 `invalid` · 503 `unavailable` (Play API down: retry) |
| GET | `/v1/iap/products` | → `{products: [{id, gems}]}` |

`/v1/ads/start` → the game shows the ad with AdMob's server-side verification options `user_id = account id`,
`custom_data = nonce`. AdMob calls `/v1/ads/ssv`; the server checks the ECDSA signature against Google's keys
(`https://www.gstatic.com/admob/reward/verifier-keys.json`, cached 24 h), matches `custom_data` to a pending
nonce of that `user_id` (not expired: 30 min), checks the day cap again, and grants once (`transaction_id` is
unique). The game polls `/v1/ads/status` (every 1.5 s, up to 20 s) after the ad closes with the reward earned,
then shows the reward. **Nothing is ever granted from the game's word alone.**

Gem purchases: the game buys with Google Play Billing, then sends `{product_id, token}`. The server calls the
Android Publisher API `purchases.products.get` (service account, secret `PLAY_SERVICE_ACCOUNT`), requires
`purchaseState == 0`, grants the product's gems once (the token is the primary key), then calls
`purchases.products.consume` so the game doesn't need to. A daily cron reads `voidedpurchases.list` and takes the
gems of refunded purchases back (`iap_void`; the balance can't go below 0, any shortfall is noted in the ledger
`ref`).

## 3. Coin tables (quick match)

- Queue: `GET /v1/quick/ws?game=&players=&table=<id>` (`practice`, `t100`, `t500`, `t2k`, `t10k`, `t50k`;
  default `practice`). One Matchmaker per `game:size:table`.
- At `hello` the Matchmaker checks the level and takes the entry (`entries` row `held`, ledger `entry`).
  Errors: `locked` (level too low), `coins` (+`short`). Leaving the queue (cancel, socket closed, replaced)
  refunds it at once (`entry_refund`). A matched entry moves to the room (`playing`, `room`).
- Ghost seats pay a virtual entry, so the pot is always `entry × size`. Payouts that would go to a ghost are not
  paid to anyone (so the bots must be fair; their win rate per table is on the Economy page).
- At `over`, the Room settles: places are the final standings with **seats that left** (`leave`) removed (they
  forfeit, whatever their place). The pool (pot minus 5%) goes to the first place (2 players) or 60 / 30 / 10% to the
  first three (4 players), human or ghost. Each human entry becomes `settled` with its `payout` (ledger `payout`, ref =
  match id), or `forfeit`; a human 1st place also gets the **house bonus** (20% of the pool, ledger `table_bonus`,
  ref = match id, its own row in the same batch). A disconnected player whose seat a bot played keeps their place and
  payout (reconnect grace applies as before).
- XP at a coin table: as `ONLINE_REWARDS` (win / finish). Practice: XP + 50 / 10 coins.
- Abandoned (every human left: they forfeited), no-show (nobody connected before the start), or an admin closing the
  room: entries still `held` / `playing` are refunded (the leavers' forfeited). A running match is **never** closed
  with refunds because people are away or the room is idle / empty / swept by the cron: it is settled by progress
  (below). A cron still refunds any `held` / `playing` entry older than 3 hours (a lost Room or grant, never a
  normal path).
- Invariant: for every match, `sum(pot payouts) ≤ entry × size × 0.95` (the pool); the bonus is separate new coins.
  Tested.

### Nobody connected (owner decision 2026-10-31)

- **Freeze.** The moment no person in a running match has an open socket (all disconnected or left), the match
  freezes: no ghost, bot or timeout step is played, no ghost emote, nothing chained, and the room keeps one alarm: the
  freeze's deadline (`TIMING.abandonAfter`, 2 min). While at least one other person is connected the 20 s per-seat
  grace still applies as before (the seat becomes a bot). Friend rooms freeze too, and still end as abandoned (no
  rewards) after the 10 min empty-room timeout.
- **Resume.** Someone back within 2 minutes resumes the match where it was: their seat comes back from bot mode as on
  any reconnect, the time spent frozen is added to the graces of the people still away and to an open re-roll hold,
  and the current turn gets a fresh deadline (nobody loses a turn to the freeze).
- **Settlement by progress** (`src/settle.ts`, `room.ts endAway`): after 2 minutes with nobody back the match ends for
  good (status over, `over.ended = "away"`, the room is kept 10 min for people coming back, then deleted). Every seat
  (people, bots, ghosts) is placed: sides that had finished keep their real places first, the rest by score. Ludo:
  pawns home first, then the distance travelled (per pawn `min(p, 56) + 1`, 0 in base; pairs counted per pawn;
  Teams: the team's sum). S&L: the square reached. Ties: the lower colour first. Places are then paid exactly as at
  a normal `over` (seats that left forfeit and are skipped; normal payouts, bonus, XP and stats for the place; ghosts'
  prizes stay with the house).
- **Anti-gaming.** A person who was disconnected (not finished) and is 1st in the paid order gets the 1st prize (and
  bonus) only with a **clear lead** over the next seat behind them (any seat: ghost, bot, or a leaver's bot; seats
  that left while ahead don't count). Clear: Ludo, more pawns home, or a distance lead of more than 25% of one pawn's
  full track (57 steps), i.e. 15+ steps; S&L, 20+ squares (`ECON_V1.away_lead`). Not clear: their entry is
  **refunded** instead (entry `refunded`, ledger `entry_refund`, ref `<entry>:away`; outcome "finish", its XP; no
  prize, no bonus, not doubled by an ad) and the 1st prize stays with the house. People placed 2nd or lower get their
  place's normal payout; a loser loses the entry as if they had played on. Players who explicitly left forfeit.

## 4. Re-roll (rooms)

- Trigger ("a bad roll"): Ludo, your roll ended your turn without a move (`need_six`, or `stuck` on a non-6);
  S&L, your roll ended on a snake. Your seat hasn't re-rolled this match, it isn't played by a bot (mode cpu), and
  you can pay (cached at match start: free re-rolls > 0 or gems ≥ 5; refreshed after each use and when the
  client sends `reroll` anyway).
- Then the server holds the turn for **3 s**: it sends `{t: "reroll_offer", n, until, free, gems}` to that player
  only and `{t: "hold", c, until}` to everyone; anyone else's `roll` before `until` gets `error {code: "hold"}`.
  Bots / ghosts wait until `until`.
- Client → `{t: "reroll", n}` (n = the current action count) within the window. The server pays (free re-roll
  first, else 5 gems; `rerolls` row), puts the state back to before the bad roll, sends `{t: "rerolled", c, paid}`
  to everyone, then `sync` (the restored state, `n` back to the roll's index) and the new roll as a normal `act`.
  It is a new random roll (not a 6 for sure). Errors: `reroll_used`, `reroll_closed` (window over / state moved),
  `gems` (can't pay).
- Ghosts: on a bad roll, if their once-per-match re-roll is unused, 25% chance they use it after 1.2–2.2 s
  (same messages; `paid: "free"`).
- The game shows the offer as a "Roll again" button with a 3 s ring, a toast for everyone ("Rahim rolled again"),
  and disables the next player's roll button until `hold.until`.

## 5. Rewarded ads (game)

- Google Mobile Ads SDK (AdMob), rewarded ads only, never shown without a tap. UMP consent form at first launch
  where required (EEA / UK), and a "Privacy choices" entry in Settings when the form says so.
- Android plugin `godot/android/plugins/admob` (Kotlin AAR, v2 plugin like `notifications`), GDScript wrapper
  `scripts/net/ads.gd` (`Ads`): `init()`, `consent()`, `load_rewarded()`, `show_rewarded(user_id, custom_data)`,
  signals `loaded`, `failed(code)`, `earned`, `closed`. A safe stub off Android.
- Ad unit ids in `project.godot` `[ludo_zing] ads/app_id`, `ads/rewarded_unit` (Google's test ids until the owner's
  AdMob account exists).
- Where ads appear: Rewards sheet (`gems` ad, `reroll` ad), the broke popup (`refill`), the coin-table result card
  (`double`). Each shows "N left today".

## 6. Gem shop (game)

- Android plugin `godot/android/plugins/billing` (Play Billing Library 7), wrapper `scripts/net/billing.gd`
  (`Billing`): `connect()`, `query(product_ids)` → prices, `buy(product_id)`, signals `purchased(product_id, token)`,
  `failed(code)`, `pending`. After `purchased` the game calls `/v1/iap/verify`; it retries on the next launch for
  tokens not yet verified (`Save.prefs.iap_pending`).
- Store sheet: gem packs (prices from Play), the exchange packs, current balances.

## 7. Admin console

- Accounts: gems and free re-rolls shown; `POST /admin/api/accounts/:id/gems {delta, reason}` (as `/coins`;
  `account.gems` audit action).
- **Economy** page: `GET /admin/api/economy?days=14` → per Bangladesh day: coins created / spent by ledger
  reason, gems created / spent by reason, table fees (pot − the place shares), entries and payouts per table, ghost
  win rate per table, re-rolls (free / gems / ghost), ad rewards per kind, purchases (count, gems, voided), and the
  pot payouts and the **house bonus** (coins created per day, apart from the payouts; owner 2026-10-31).

## 8. Owner decisions 2026-10-31

1. Quick matches with nobody connected: freeze, resume within 2 min, else settle by progress with the anti-gaming
   refund (§3 "Nobody connected"). Friend rooms: freeze, then abandoned after the empty timeout (no rewards).
2. Rewards: A. friend-room coins Ludo 300 / 50, S&L 200 / 25 (XP unchanged). B. table fee 5%. C. 4-player tables pay
   60 / 30 / 10% of the pool. D. the house bonus: 20% of the pool to a human 1st place at a paid table, as new coins
   (ledger `table_bonus`), shown separately on the admin Economy page.

The game shows the same maths (`godot/scripts/core/coin_tables.gd`): the Quick match picker's "Win N" is 1st place's
total (its share plus the bonus), and the result screen shows the bonus, a refund and the away ending.

## 9. Order of work

1. Server: migration, profile gems / rerolls, mutate (level gems), shop gems, exchange, broke, tables, admin gems.
2. Server: entries in Matchmaker + Room settlement; re-roll; ghosts' re-roll.
3. Server: ads (start / ssv / status) and IAP (verify, consume, voided cron); weekly prizes; achievements gems.
4. Game: catalog / Save (Sonnet), top bar + shop + store + exchange + broke + tables + re-roll UI (Sonnet),
   AdMob and Billing plugins (Sonnet). Admin Economy page (Sonnet).
5. Owner steps (ask first): AdMob account + rewarded ad unit with the SSV URL; Play Console app, gem products,
   license testers, and API access for the service account.
