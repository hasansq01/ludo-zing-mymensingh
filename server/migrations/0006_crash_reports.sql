-- Crash / unexpected-exit reports (POST /v1/diag/crash, src/diag.ts): one row per (device pid, session id) of a run
-- that died. Flat columns for filtering and the admin summary, the full report (device, samples, breadcrumbs, exit info,
-- the log tail) in `payload` (JSON, at most 128 KB). Times are epoch ms. Deleted after 90 days by the daily cron and
-- with an erased account (by account_id).

CREATE TABLE IF NOT EXISTS crash_reports (
  id TEXT PRIMARY KEY,                   -- "crs_" + 16 base32 chars
  received_at INTEGER NOT NULL,
  pid TEXT NOT NULL,                     -- the device id (Save.prefs pid)
  sid TEXT NOT NULL,                     -- the id of the run that died
  account_id TEXT,                       -- when the request carried a valid session
  ip TEXT,                               -- HMAC of the client IP (as guest_creations.ip), for the rate limit
  app_code INTEGER,
  app_version TEXT,
  model TEXT,
  android TEXT,
  gpu TEXT,                              -- the renderer name
  reason TEXT NOT NULL,                  -- exit.reason, else the trigger, else "unknown"
  foreground INTEGER,                    -- 0 / 1 at the last sample
  screen TEXT,
  game TEXT,
  mode TEXT,
  match_min REAL,
  mem_peak_mb REAL,                      -- max over the samples of mem_peak / mem
  payload TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS crash_reports_received ON crash_reports (received_at);
CREATE UNIQUE INDEX IF NOT EXISTS crash_reports_run ON crash_reports (pid, sid);
CREATE INDEX IF NOT EXISTS crash_reports_ip ON crash_reports (ip, received_at);
CREATE INDEX IF NOT EXISTS crash_reports_pid ON crash_reports (pid, received_at);
CREATE INDEX IF NOT EXISTS crash_reports_model ON crash_reports (model);
CREATE INDEX IF NOT EXISTS crash_reports_reason ON crash_reports (reason);
