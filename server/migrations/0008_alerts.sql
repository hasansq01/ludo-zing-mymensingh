-- Alerts (ADMIN_API.md "Alerts", src/alerts.ts): what the 15-minute check warned about (a free-plan limit near, a
-- server problem, the morning summary), each pushed once to the owner's phone and listed on the console. Times are
-- epoch ms. Deleted after 90 days by the daily cron.

CREATE TABLE IF NOT EXISTS alerts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  key TEXT NOT NULL UNIQUE,              -- once only: e.g. "usage:workers_requests:90:2026-11-03"
  at INTEGER NOT NULL,
  level TEXT NOT NULL,                   -- info | warning | danger
  kind TEXT NOT NULL,                    -- usage | pace | server | summary | test
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  sent INTEGER NOT NULL DEFAULT 0,       -- devices the push reached
  failed INTEGER NOT NULL DEFAULT 0,
  read_at INTEGER                        -- marked read on the console (NULL: still in the banner)
);
CREATE INDEX IF NOT EXISTS alerts_at ON alerts (at);

-- The check's own state: "last_check" (JSON of the latest run), "usage_fails" (failed Cloudflare reads in a row).
CREATE TABLE IF NOT EXISTS alert_state (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  at INTEGER NOT NULL
) WITHOUT ROWID;
