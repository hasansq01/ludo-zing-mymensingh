-- Recent players, friends and game invites (PROTOCOL.md "Recent players, friends and invites"; src/social.ts).
-- Times are epoch ms. Written by src/social.ts (the /v1/social endpoints, the daily prune) and by the Room at a match
-- start (who sat at the table). Erased with an account (admin.ts accountErase).

-- The public handle other players see for an account (recent and friends lists, the leaderboard, invites): 16
-- random hex characters, never the account id. New accounts get one when they are created (accounts.ts).
ALTER TABLE accounts ADD COLUMN uid TEXT;
UPDATE accounts SET uid = lower(hex(randomblob(8))) WHERE uid IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS accounts_uid ON accounts (uid);

-- Quick-match seats the server plays (src/ghosts.ts), kept with the identity they had at the table so they appear
-- in recent and friends lists exactly like people (same handle format, same fields). Never sent as such. Rows that
-- no list refers to any more are pruned after 30 days.
CREATE TABLE IF NOT EXISTS ghost_people (
  uid TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  avatar TEXT NOT NULL,
  frame TEXT NOT NULL,
  level INTEGER NOT NULL,                -- the level shown at the table (lists show it a little higher as days pass)
  created_at INTEGER NOT NULL
) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS ghost_people_created ON ghost_people (created_at);

-- Everyone an account played an online match with (friend rooms and quick match), one row per person, the newest
-- 30 kept. game: ludo | sl of the last match together; at: when it started.
CREATE TABLE IF NOT EXISTS recent_players (
  account_id TEXT NOT NULL,
  uid TEXT NOT NULL,
  game TEXT NOT NULL,
  at INTEGER NOT NULL,
  PRIMARY KEY (account_id, uid)
) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS recent_players_at ON recent_players (account_id, at);
CREATE INDEX IF NOT EXISTS recent_players_uid ON recent_players (uid);

-- Friends are one-way (a favourites list): adding someone tells them nothing. At most 100 per account.
CREATE TABLE IF NOT EXISTS friends (
  account_id TEXT NOT NULL,
  uid TEXT NOT NULL,
  at INTEGER NOT NULL,
  PRIMARY KEY (account_id, uid)
) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS friends_uid ON friends (uid);

-- Settings' "Invites from players" (no row: on).
CREATE TABLE IF NOT EXISTS social_prefs (
  account_id TEXT PRIMARY KEY,
  invites INTEGER NOT NULL DEFAULT 1,
  updated_at INTEGER
) WITHOUT ROWID;

-- Game invites into a friend room. Every invite sent is a row (the inviter's rate limits count them all); to_account
-- is the person it reaches, NULL when it reaches nobody (their invites are off, or nobody reads it): such a row is
-- never listed or pushed. status: pending | accepted | declined | expired. Rows are pruned after 2 days.
CREATE TABLE IF NOT EXISTS invites (
  id TEXT PRIMARY KEY,                   -- "inv_" + 16 base32 chars
  from_account TEXT NOT NULL,
  to_uid TEXT NOT NULL,
  to_account TEXT,
  code TEXT NOT NULL,                    -- the room
  game TEXT NOT NULL,                    -- the room's game when it was sent
  at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,           -- 10 minutes; also ended when the room's match starts
  status TEXT NOT NULL DEFAULT 'pending',
  pushed INTEGER NOT NULL DEFAULT 0      -- a push was sent for it
);
CREATE INDEX IF NOT EXISTS invites_to ON invites (to_account, status, expires_at);
CREATE INDEX IF NOT EXISTS invites_from ON invites (from_account, at);
CREATE INDEX IF NOT EXISTS invites_code ON invites (code, status);
CREATE INDEX IF NOT EXISTS invites_at ON invites (at);
