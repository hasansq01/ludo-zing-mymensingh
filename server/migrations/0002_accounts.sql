-- Ludo Zing online v2 (ONLINE_V2.md §1, §2, §4, §6): accounts, devices, the coin/XP ledger, offline match claims,
-- leaderboard scores, online match grants, plus the room / match columns and the quick-match stats of §3.
-- Times are epoch ms unless a column says otherwise. 0001's tables stay; `players` stays the per-pid table of the
-- friend rooms and is linked to accounts through `devices`.

-- One row per account (guest or Google-linked). The profile is stored in columns + JSON (src/accounts.ts
-- rowToProfile / profileColumns); `version` + `rev` are the optimistic-concurrency guard of every write.
CREATE TABLE IF NOT EXISTS accounts (
  id TEXT PRIMARY KEY,                   -- "acc_" + 16 base32 chars
  created_at INTEGER NOT NULL,
  last_seen INTEGER,
  google_player_id TEXT UNIQUE,          -- Play Games player id (NULL: guest)
  google_name TEXT,
  public_id TEXT,                        -- the game's "LZM-XXXX-XXXX" player ID (profile.id)
  name TEXT,
  avatar TEXT,
  frame TEXT,
  plate TEXT,
  badge TEXT,
  coins INTEGER NOT NULL DEFAULT 0,
  xp INTEGER NOT NULL DEFAULT 0,
  online_wins INTEGER NOT NULL DEFAULT 0, -- wins in online matches (friend rooms + quick match)
  stats TEXT,                            -- json profile.stats
  owned TEXT,                            -- json {rooms, dice_owned, scenes, av_owned}
  equipped TEXT,                         -- json {room, dice, scene} (avatar / frame / plate / badge are columns)
  rewards TEXT,                          -- json {daily, last_spin, last_free}
  achievements TEXT,                     -- json {claimed: [ids]}
  banned INTEGER NOT NULL DEFAULT 0,
  ban_reason TEXT,
  note TEXT,
  merged_into TEXT,                      -- retired by a Google conflict "keep here": the account that took its Google id
  imported INTEGER NOT NULL DEFAULT 0,   -- the one-time local profile import happened
  version INTEGER NOT NULL DEFAULT 0,    -- +1 on every write
  rev TEXT                               -- random token of the latest write (guards the statements batched with it)
);

-- Device ids (pid, Save.prefs.net_pid) -> account. A pid belongs to one account at a time.
CREATE TABLE IF NOT EXISTS devices (
  pid TEXT PRIMARY KEY,
  account_id TEXT NOT NULL,
  first_seen INTEGER,
  last_seen INTEGER
);

-- Every coin / XP change. reason: import | buy | daily | spin | free | achievement | claim | match | admin.
CREATE TABLE IF NOT EXISTS ledger (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  account_id TEXT NOT NULL,
  at INTEGER NOT NULL,
  delta_coins INTEGER NOT NULL DEFAULT 0,
  delta_xp INTEGER NOT NULL DEFAULT 0,
  reason TEXT NOT NULL,
  ref TEXT,
  balance_after INTEGER
);

-- Offline match claims (POST /v1/claims). id = the client's claim id (unique per account: retries are idempotent).
-- granted: the claim was applied (coins / XP / stats, possibly cut to the daily caps); limited: something was cut
-- or nothing was paid (reason too_short | hourly | daily_coins | daily_xp | replay).
CREATE TABLE IF NOT EXISTS claims (
  id TEXT NOT NULL,
  account_id TEXT NOT NULL,
  at INTEGER NOT NULL,
  game TEXT,
  mode TEXT,
  payload TEXT,                          -- json: the claim as sent
  coins INTEGER NOT NULL DEFAULT 0,
  xp INTEGER NOT NULL DEFAULT 0,
  granted INTEGER NOT NULL DEFAULT 0,
  limited INTEGER NOT NULL DEFAULT 0,
  reason TEXT,
  result TEXT,                           -- json: the response returned (replayed for a retry)
  PRIMARY KEY (account_id, id)
);

-- Leaderboards: board xp | wins, period "all" | "week:YYYY-Www" (ISO week, Bangladesh time).
CREATE TABLE IF NOT EXISTS scores (
  account_id TEXT NOT NULL,
  board TEXT NOT NULL,
  period TEXT NOT NULL,
  value INTEGER NOT NULL DEFAULT 0,
  updated_at INTEGER,
  PRIMARY KEY (account_id, board, period)
) WITHOUT ROWID;

-- Online match rewards: once per account per match (grantOnlineMatch).
CREATE TABLE IF NOT EXISTS match_grants (
  match_id TEXT NOT NULL,
  account_id TEXT NOT NULL,
  at INTEGER,
  game TEXT,
  outcome TEXT,                          -- win | finish | left
  coins INTEGER NOT NULL DEFAULT 0,
  xp INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (match_id, account_id)
) WITHOUT ROWID;

-- Quick match (ONLINE_V2.md §3; written by the Matchmaker / Room through db.ts recordQuickStat). Counters per UTC day.
CREATE TABLE IF NOT EXISTS quick_stats (
  day TEXT NOT NULL,                     -- YYYY-MM-DD (UTC)
  game TEXT NOT NULL,                    -- ludo | sl
  size INTEGER NOT NULL,                 -- 2 | 4
  queued INTEGER NOT NULL DEFAULT 0,     -- humans who joined the queue
  matched INTEGER NOT NULL DEFAULT 0,    -- humans placed in a match
  ghost_filled INTEGER NOT NULL DEFAULT 0, -- seats filled with disguised bots
  wait_ms_total INTEGER NOT NULL DEFAULT 0, -- sum of the matched humans' waits
  human_wins INTEGER NOT NULL DEFAULT 0, -- matches with ghosts won by a human
  ghost_wins INTEGER NOT NULL DEFAULT 0, -- matches with ghosts won by a ghost
  PRIMARY KEY (day, game, size)
) WITHOUT ROWID;

-- Rooms and matches: game, quick-match flags, ghosts.
ALTER TABLE rooms ADD COLUMN game TEXT DEFAULT 'ludo';
ALTER TABLE rooms ADD COLUMN public INTEGER DEFAULT 0;
ALTER TABLE rooms ADD COLUMN quick INTEGER DEFAULT 0;
ALTER TABLE matches ADD COLUMN game TEXT DEFAULT 'ludo';
ALTER TABLE matches ADD COLUMN quick INTEGER DEFAULT 0;
ALTER TABLE matches ADD COLUMN ghosts INTEGER DEFAULT 0;
ALTER TABLE matches ADD COLUMN human_won INTEGER;

CREATE INDEX IF NOT EXISTS accounts_last_seen ON accounts (last_seen, id);
CREATE INDEX IF NOT EXISTS accounts_created ON accounts (created_at);
CREATE INDEX IF NOT EXISTS devices_account ON devices (account_id);
CREATE INDEX IF NOT EXISTS ledger_account ON ledger (account_id, id);
CREATE INDEX IF NOT EXISTS claims_account_at ON claims (account_id, at);
CREATE INDEX IF NOT EXISTS claims_at ON claims (at);
CREATE INDEX IF NOT EXISTS scores_board ON scores (board, period, value);
CREATE INDEX IF NOT EXISTS match_grants_account ON match_grants (account_id, at);
CREATE INDEX IF NOT EXISTS matches_quick ON matches (quick, started_at);
