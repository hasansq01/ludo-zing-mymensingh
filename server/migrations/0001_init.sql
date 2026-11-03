-- Ludo Zing admin console: D1 schema v1 (ADMIN_API.md). Times are epoch ms.
-- Statements are idempotent (IF NOT EXISTS) so the test setup can apply them in any order.

CREATE TABLE IF NOT EXISTS players (
  pid TEXT PRIMARY KEY,
  name TEXT,
  avatar TEXT,
  frame TEXT,
  first_seen INTEGER,
  last_seen INTEGER,
  rooms INTEGER DEFAULT 0,
  matches INTEGER DEFAULT 0,
  wins INTEGER DEFAULT 0,
  banned INTEGER DEFAULT 0,
  ban_reason TEXT,
  note TEXT,
  last_room TEXT -- the room code of the player's latest join (used to kick a banned player)
);

CREATE TABLE IF NOT EXISTS rooms (
  code TEXT PRIMARY KEY,
  created_at INTEGER,
  updated_at INTEGER,
  host_pid TEXT,
  host_name TEXT,
  status TEXT, -- lobby | playing | over | closed
  members INTEGER,
  online INTEGER,
  settings TEXT, -- json {teams, pair_ask}
  closed_reason TEXT
);

CREATE TABLE IF NOT EXISTS matches (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  code TEXT,
  started_at INTEGER,
  ended_at INTEGER,
  players TEXT, -- json [{pid, name, color, bot}]
  teams INTEGER,
  pair_ask INTEGER,
  winner INTEGER,
  finished TEXT, -- json [colours]
  actions INTEGER,
  result TEXT -- playing | over | abandoned | closed
);

CREATE TABLE IF NOT EXISTS events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  at INTEGER,
  level TEXT, -- info | warn | error
  kind TEXT,
  code TEXT,
  pid TEXT,
  msg TEXT
);

CREATE TABLE IF NOT EXISTS config (
  key TEXT PRIMARY KEY,
  value TEXT
);

CREATE TABLE IF NOT EXISTS admin_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  at INTEGER,
  ip TEXT,
  action TEXT,
  target TEXT,
  detail TEXT
);

CREATE TABLE IF NOT EXISTS login_attempts (
  ip TEXT,
  at INTEGER
);

-- One row per player per UTC day they connected (overview: players_active per day). Pruned after 30 days.
CREATE TABLE IF NOT EXISTS player_days (
  day TEXT, -- YYYY-MM-DD (UTC)
  pid TEXT,
  PRIMARY KEY (day, pid)
) WITHOUT ROWID;

CREATE INDEX IF NOT EXISTS rooms_status_updated ON rooms (status, updated_at);
CREATE INDEX IF NOT EXISTS rooms_created ON rooms (created_at);
CREATE INDEX IF NOT EXISTS matches_started ON matches (started_at);
CREATE INDEX IF NOT EXISTS matches_code ON matches (code, started_at);
CREATE INDEX IF NOT EXISTS events_at ON events (at);
CREATE INDEX IF NOT EXISTS players_last_seen ON players (last_seen);
CREATE INDEX IF NOT EXISTS players_first_seen ON players (first_seen);
CREATE INDEX IF NOT EXISTS login_attempts_ip_at ON login_attempts (ip, at);
