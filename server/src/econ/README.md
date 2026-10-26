# Server economy (`src/econ/`)

Pure TypeScript functions over a profile, with no I/O. They compute exactly what the offline game computes today,
plus the server-only rules of ONLINE_V2.md "Economy decisions" (`rules.ts`). The endpoints in ONLINE_V2.md §2 call
them directly, store the returned profile and write one ledger row per change (`delta.coins`, `delta.xp`). Inputs
are never mutated. Every function takes the server's clock (`now`, unix seconds) and day key (`today = dayKey(now)`).

| File | What |
| --- | --- |
| `catalog.json` | Generated, do not edit. Items, achievements, defaults, reward tables, match rewards, level numbers. |
| `catalog.ts` | Types and lookups over `catalog.json`. |
| `rules.ts` | Server-only values (the Economy decisions): day offset (Bangladesh), online rewards, claim limits, import caps. |
| `gd.ts` | GDScript value semantics (`int()`, `is_equal_approx`, `strip_edges`) so stored data reads the same. |
| `profile.ts` | Profile shape, `normalizeProfile` (Save._ensure), `newProfile`, `levelInfo`, ownership, unlocks, `equipped`. |
| `shop.ts` | `buy`, `equip`. |
| `rewards.ts` | Day keys (and ISO weeks for the leaderboard), daily calendar, spin, free coins. |
| `achievements.ts` | Progress and claims. |
| `matches.ts` | Offline results, claims with limits, online rewards. |
| `import.ts` | The one-time import of the local profile. |

Regenerate the generated files from the repo root:

```
godot --headless --path godot -s res://dev/export_catalog.gd -- ../server/src/econ/catalog.json
godot --headless --path godot -s res://dev/econ_parity_dump.gd        # server/test/fixtures/econ_cases.json
```

`test/econ_parity.test.ts` replays about 2,000 GDScript-recorded cases and must match exactly. It also fails when
`catalog.json` differs from what the GDScript builds. The recorded cases are the offline game's (device days,
offline values); the functions they replay take the day key, the clock and the spin segment as arguments, so the
server values of `rules.ts` never reach them. `test/econ_rules.test.ts` covers the server-only rules.

## Rules

| Rule | Value | Source |
| --- | --- | --- |
| Starting profile | 2,500 coins, 0 gems, 0 re-rolls, 0 XP, rooms Moonlit Café + Corner Café, Classic dice, Jungle scene, Red Pawn, Wood frame, Plain plate, no badge, all stats 0 | `Save._ensure` |
| Level | Level n needs 100 + 50·(n−1) XP to reach n+1 | `Save.level_info` |
| Gems and re-rolls | `gems` ≥ 0 and `rerolls` clamped 0..9, both normalized like `coins` (default 0). Existing saves keep their coins | `Save._ensure` |
| Gem prices | Every item the Shop sells (price > 0) costs `ceil(price / 100)` gems (`gems` in `catalog.json`; free and unlock-only items have none) | `Catalog.gem_price` |
| Rooms | Dream 3,000 · Studio 4,000 · Cloudside 5,000 (Moonlit, Corner free) | `Rooms.LIST` |
| Dice | Crema 1,000 · Espresso 2,500 · Royal Gold 6,000 (Classic free) | `Catalog.DICE` |
| S&L scenes | Frost 20,000 · Candy 22,000 · Desert / Cloud / Enchanted 25,000 (Jungle free) | `SLScenes.LIST` |
| Characters | 18 at 10,000–12,000; Arif and Nadia free | `Collection.CHARS` |
| Unlock-only | Lucky Dice avatar (First Victory), Robot (Winning Streak), Crown (level 5); frames Gold (level 5), Mint (Master of Pairs), Royal (Coin Collector); plates Espresso (Experienced Player), Ruby (Winning Streak); each badge needs its achievement | `Collection` |
| Buy | Checks in order: exists → not owned (free items count as owned) → affordable. Pays the price once, adds the item and equips it, as the Shop does. `buy(profile, kind, id, currency = "coins")`: with `"gems"` it pays the gem price from `gems` (coins and `coinsEarned` untouched, `delta.gems` negative). Errors are `unknown`, `owned`, `coins` / `gems` (+`short`), and `locked` for an unlock-only item not yet unlocked (`owned` once it is) | `Catalog.buy_*`, `SLScenes.buy_scene`, `Collection.buy_char` |
| Equip | Owned rooms, dice and scenes; unlocked avatar, frame, plate and badge (`""` = no badge). Errors `unknown`, `locked` | `Catalog.equip_*`, `Collection.equip` |
| Achievements | First Victory (1 win) 200 · Winning Streak (best streak 3) 300 · Experienced Player (25 vs-computer games) 500 · Master of Pairs (10 pairs) 300 · Multiplayer Champion (5 Pass & Play) 300 · Coin Collector (10,000 earned) 500. Each pays once and counts as earned. Errors `unknown`, `not_done`, `claimed` | `Collection.ACH`, `claim_ach` |
| Daily reward | 3 cycles of 7 days (`catalog.rewards.daily_cycles`), one claim per day. The next day continues the run; a missed day restarts at Day 1 of the cycle; after Day 7 the next cycle starts (and wraps after the third). A dice tile already owned pays its `or` coins, and so does a character tile whose character is owned. Error `claimed` + `next_at` | `Rewards.daily_state`, `claim_daily` |
| Spin | 8 segments 100, 250, 150, 500, 100, 1000, 200, 300, uniform (so 100 has a 2/8 chance). Once per day. `rollSpin()` draws the segment (crypto RNG); `spin()` takes it as an argument. Error `spun` + `next_at` | `Rewards.PRIZES`, `spin` |
| Free coins | 300 every 14,400 s (4 h). Error `cooldown` + `next_at` | `Rewards.claim_free` |
| Coins earned | Every gain (rewards, matches, achievements) also adds to `stats.coinsEarned`; purchases don't subtract | `Save.add_coins`, `Rewards._add_coins` |
| Offline Ludo | vs Computer (exactly one human, at least one computer): a win pays 200 coins and 100 XP and counts played, wins and streak; a loss pays 20 coins and 40 XP and counts played and losses and resets the streak. Pass & Play (two or more humans): 0 coins, 30 XP, ppGames +1 | `LudoRules.win_reward / play_reward`, `Save.record_ludo` |
| Offline S&L | vs Computer: a win pays 100 coins (slWins +1), a loss pays 10. Pass & Play pays 0. Every game counts slPlayed. No XP | `SnakesLaddersRules.claim_*_reward`, `Save.record_sl` |
| Claim limits | `claimLimit`, in order: a match shorter than 60 s (Ludo) or 30 s (S&L) (`too_short`); an S&L win vs Computer whose `rolls` don't replay from square 0 to exactly 100, or has none or more than 2,000 (`replay`); a claim made after 20 granted claims in the last 3,600 s (`hourly`). Each grants nothing (coins, XP and stats all 0, `granted: false`). Then the day's caps (Bangladesh day): 6,000 coins and 3,000 XP from claims. The claim that reaches a cap is paid the **remainder** (`daily_coins` / `daily_xp`, `granted: true`: its stats count, the coins / XP over the cap are left out, also of `coinsEarned`); once both remainders are 0, nothing (`granted: false`). A claim worth 0 coins and 0 XP is always granted. Every limited claim comes back with `limited: true, reason, would`. The earlier claims are a list (`ClaimRecord[]`) or their totals (`ClaimTotals`, what the endpoint reads in one query). Malformed claims return `invalid` | `rules.ts` `CLAIM_LIMITS` (new) |
| Online matches | Ludo: win 150 coins + 100 XP, finish (to the end, not winning) 20 coins + 40 XP. Snakes & Ladders: win 100 + 60 XP, finish 10 + 25 XP. Left early: 0. Coins count as earned; no stats | `rules.ts` `ONLINE_REWARDS` (Ludo XP = `LudoMatch.NET_XP_*`) |
| Import | Once per account. Coins capped to 0–50,000, XP to 0–200,000, each stat to 0–1,000,000 (best streak ≥ streak). Owned items must exist (characters: paid ones only). Equipped items must be owned or unlocked, else the default is used. An achievement stays claimed only when it exists and its goal is met. The name is trimmed to 16 characters, and a valid `LZM-` ID is kept. Reward timers are kept only when they are in the past: a future spin day becomes today, a future free-coins time becomes now, a future daily `last` is reset. The daily history is dropped. `notes` lists every change | `import.ts` (new) |

## Intentional differences from the offline game

- **Days.** The game uses the device's local calendar day (`Rewards.day_key`, `Time.get_date_dict_from_system`) for
  the daily reward and the spin. The server uses `dayKey(now, DAY_OFFSET_MIN)`, a fixed offset from UTC:
  `DAY_OFFSET_MIN = 360`, so the server day starts at Bangladesh midnight (18:00 UTC) for the daily reward, the spin,
  their `next_at`, the claim caps and the leaderboard weeks (`isoWeek`: Monday 00:00 Bangladesh). Free coins are a
  4-hour cooldown, not a day, so the offset doesn't apply to them. Every day function takes an `offsetMin` argument
  (`0` = UTC days).
- **Clock.** The game's "clock moved back" protections (a claimed day never reopens; free coins never wait longer
  than one period) are kept as they are. The server clock doesn't go back.
- **History stamps.** `claim_daily` stamps history with the wall clock. The port uses the `now` it is given.
- **Damaged data.** Godot raises a script error on `int(null)` and `int([])` in `Save._ensure`. The port uses
  the default instead.
- **S&L wins are replayed.** As the game (`replay_reaches_100` before paying), an S&L win claim vs Computer carries
  `rolls` (the player's dice values in order, ≤ 2,000) and `need_one` (the "need a 1 to start" rule), replayed with
  `rules/sl.ts` `replayReaches100`. Ludo claims are trusted within the limits.
- **The claim's `xp` field is ignored.** The server computes XP from the rules. `pairs` (new, optional) feeds
  `stats.pairsFormed`, capped at 6 per claim.
- **Online coins are new.** Today the game gives online players XP only (`LudoMatch._net_game_over`, 100 / 40)
  and no coins; online S&L gets its own (smaller) table with XP.
- **Claim caps.** The offline game has none; the server's pay the remainder of the day (above).
- **Labels.** The port has no text: the client still formats captions ("Day 4: Crema dice unlocked").
