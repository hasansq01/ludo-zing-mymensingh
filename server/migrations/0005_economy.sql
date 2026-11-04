-- Economy v1 (ECONOMY_V1.md): gems and free re-rolls on accounts, gems in the ledger, coin-table entries, re-rolls,
-- rewarded-ad grants, gem purchases and the weekly gem prizes. Times are epoch ms.

ALTER TABLE accounts ADD COLUMN gems INTEGER NOT NULL DEFAULT 0;
ALTER TABLE accounts ADD COLUMN rerolls INTEGER NOT NULL DEFAULT 0;   -- free re-rolls held (0-9)

-- Sum of an account's delta_gems = its gems (as delta_coins / coins).
ALTER TABLE ledger ADD COLUMN delta_gems INTEGER NOT NULL DEFAULT 0;
ALTER TABLE ledger ADD COLUMN gems_after INTEGER;

-- One coin-table entry (quick match). status: held (taken at queue time) -> refunded | playing (seated in `room`)
-- -> settled (payout, possibly 0) | forfeit (left the match) | refunded (abandoned / never started / swept).
CREATE TABLE IF NOT EXISTS entries (
  id TEXT PRIMARY KEY,                   -- "ent_" + 16 base32 chars
  account_id TEXT NOT NULL,
  at INTEGER NOT NULL,
  game TEXT NOT NULL,                    -- ludo | sl
  size INTEGER NOT NULL,                 -- 2 | 4
  tier TEXT NOT NULL,                    -- t100 | t500 | t2k | t10k | t50k
  amount INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'held',
  room TEXT,                             -- room code once matched
  match_id TEXT,                         -- "<code>-<start ms>" once the match started
  place INTEGER,                         -- final place used for the payout (NULL: forfeit / refunded)
  payout INTEGER NOT NULL DEFAULT 0,
  settled_at INTEGER
) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS entries_account ON entries (account_id, at);
CREATE INDEX IF NOT EXISTS entries_status ON entries (status, at);
CREATE INDEX IF NOT EXISTS entries_match ON entries (match_id);

-- Re-rolls: once per account per match. paid: free | gems.
CREATE TABLE IF NOT EXISTS rerolls (
  match_id TEXT NOT NULL,
  account_id TEXT NOT NULL,
  at INTEGER NOT NULL,
  paid TEXT NOT NULL,
  PRIMARY KEY (match_id, account_id)
) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS rerolls_at ON rerolls (at);

-- Quick-match coin-table matches (one row per match with a coin table), for the Economy page: the pot, what was
-- paid to people, and whether a ghost took a paid place. fee = pot - pool (the 10%).
CREATE TABLE IF NOT EXISTS table_matches (
  match_id TEXT PRIMARY KEY,
  at INTEGER NOT NULL,
  game TEXT NOT NULL,
  size INTEGER NOT NULL,
  tier TEXT NOT NULL,
  entry INTEGER NOT NULL,
  humans INTEGER NOT NULL,
  ghosts INTEGER NOT NULL,
  pot INTEGER NOT NULL,                  -- entry x size (ghost entries are virtual)
  fee INTEGER NOT NULL,
  paid_humans INTEGER NOT NULL,          -- coins paid out to people
  winner_ghost INTEGER NOT NULL DEFAULT 0 -- 1st place was a ghost
) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS table_matches_at ON table_matches (at);

-- Rewarded ads. kind: reroll | refill | double | gems. status: pending -> granted | expired | rejected.
CREATE TABLE IF NOT EXISTS ad_rewards (
  nonce TEXT PRIMARY KEY,
  account_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  ref TEXT,                              -- double: the match id
  created_at INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  tx_id TEXT UNIQUE,                     -- AdMob transaction_id
  granted_at INTEGER,
  amount INTEGER NOT NULL DEFAULT 0      -- coins / gems / re-rolls granted
) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS ad_rewards_account ON ad_rewards (account_id, created_at);
CREATE INDEX IF NOT EXISTS ad_rewards_granted ON ad_rewards (status, granted_at);

-- Google Play gem purchases. token = purchaseToken. status: granted | voided.
CREATE TABLE IF NOT EXISTS purchases (
  token TEXT PRIMARY KEY,
  account_id TEXT NOT NULL,
  product_id TEXT NOT NULL,
  order_id TEXT,
  at INTEGER NOT NULL,
  gems INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'granted',
  voided_at INTEGER
) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS purchases_account ON purchases (account_id, at);
CREATE INDEX IF NOT EXISTS purchases_at ON purchases (at);

-- Weekly leaderboard gem prizes (Monday cron), once per period, board and account.
CREATE TABLE IF NOT EXISTS weekly_prizes (
  period TEXT NOT NULL,                  -- "week:YYYY-Www"
  board TEXT NOT NULL,                   -- xp | wins
  account_id TEXT NOT NULL,
  rank INTEGER NOT NULL,
  gems INTEGER NOT NULL,
  at INTEGER NOT NULL,
  PRIMARY KEY (period, board, account_id)
) WITHOUT ROWID;

-- Daily broke bonus: once per account per Bangladesh day.
CREATE TABLE IF NOT EXISTS broke_bonus (
  account_id TEXT NOT NULL,
  day TEXT NOT NULL,
  at INTEGER NOT NULL,
  coins INTEGER NOT NULL,
  PRIMARY KEY (account_id, day)
) WITHOUT ROWID;
