-- Push notifications (NOTIFICATIONS.md "N-SRV"): device tokens, the admin's campaigns and their opens, and the
-- event-push counters. Times are epoch ms. Written by src/push.ts (tokens, opens, event counters), src/admin.ts
-- (campaigns) and the Pusher Durable Object (src/pusher.ts: campaign status and delivery counters).

-- One row per device (FCM registration token). A token belongs to one account at a time (the latest to register it);
-- an account keeps its 5 most recently updated tokens. prefs_*: the game's Game alerts / News & offers toggles.
CREATE TABLE IF NOT EXISTS push_tokens (
  token TEXT PRIMARY KEY,
  account_id TEXT NOT NULL,
  platform TEXT NOT NULL DEFAULT 'android',
  prefs_game INTEGER NOT NULL DEFAULT 1,
  prefs_offers INTEGER NOT NULL DEFAULT 1,
  tz_offset_min INTEGER,                 -- the device's UTC offset in minutes (NULL: not sent)
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS push_tokens_account ON push_tokens (account_id, updated_at);

-- Admin promos. audience: JSON {kind: "all"} | {kind: "segment", inactive_days?, new_days?, level_min?, level_max?}.
-- status: draft | scheduled | sending | sent | canceled | failed. targeted: devices the campaign was sent to (the
-- estimate until it is sent); sent / failed: FCM results ("all": the topic's devices, one send); opened: accounts
-- that opened it (push_opens).
CREATE TABLE IF NOT EXISTS push_campaigns (
  id TEXT PRIMARY KEY,                   -- "cmp_" + 12 base32 chars
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  link TEXT NOT NULL DEFAULT 'home',
  audience TEXT NOT NULL,
  status TEXT NOT NULL,
  run_at INTEGER,                        -- when it is (was) to be sent; NULL: at once
  created_by TEXT,
  created_at INTEGER NOT NULL,
  sent_at INTEGER,                       -- when the last send finished
  targeted INTEGER NOT NULL DEFAULT 0,
  sent INTEGER NOT NULL DEFAULT 0,
  failed INTEGER NOT NULL DEFAULT 0,
  opened INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS push_campaigns_created ON push_campaigns (created_at);

-- POST /v1/push/opened: once per campaign and account.
CREATE TABLE IF NOT EXISTS push_opens (
  cid TEXT NOT NULL,
  account_id TEXT NOT NULL,
  at INTEGER NOT NULL,
  PRIMARY KEY (cid, account_id)
) WITHOUT ROWID;

-- Event pushes per UTC day and kind (turn | joined | rematch | weekly), pruned after 30 days by the daily cron.
CREATE TABLE IF NOT EXISTS push_events (
  day TEXT NOT NULL,                     -- YYYY-MM-DD (UTC)
  kind TEXT NOT NULL,
  sent INTEGER NOT NULL DEFAULT 0,
  failed INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (day, kind)
) WITHOUT ROWID;
