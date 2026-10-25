-- Ludo Zing online v2 policy decisions (lead, 2026-10-24; ONLINE_V2.md "Policy decisions"):
--   leaderboards list only accounts with >= 3 completed matches (accounts.completed_matches),
--   ban sources so that lifting one ban lifts only the bans it caused (accounts.ban_source, players.ban_source),
--   guest account creation is rate limited per client IP (guest_creations; pruned by the daily cron).

-- Online matches played to the end (outcome win / finish) + granted offline claims. Incremented in the same batch as
-- the grant (accounts.ts mutate).
ALTER TABLE accounts ADD COLUMN completed_matches INTEGER NOT NULL DEFAULT 0;
-- Why the account is banned: 'admin_account' (Accounts page) | 'pid:<pid>' (that device's ban reached the account).
ALTER TABLE accounts ADD COLUMN ban_source TEXT;
-- Why the pid is banned: 'admin_pid' (Players page) | 'account:<account id>' (that account's ban reached the device).
ALTER TABLE players ADD COLUMN ban_source TEXT;

-- One row per guest account created: an HMAC of the client IP (never the IP itself) and the time (epoch ms).
CREATE TABLE IF NOT EXISTS guest_creations (
  ip TEXT NOT NULL,
  at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS guest_creations_ip_at ON guest_creations (ip, at);
CREATE INDEX IF NOT EXISTS scores_period ON scores (period);

-- Backfill: matches already completed.
UPDATE accounts SET completed_matches =
  (SELECT COUNT(*) FROM claims c WHERE c.account_id = accounts.id AND c.granted = 1)
  + (SELECT COUNT(*) FROM match_grants g WHERE g.account_id = accounts.id AND g.outcome IN ('win', 'finish'));

-- Backfill: existing pid bans were made on the Players page; an account ban that matches one of its devices' pid bans
-- (same reason) came from it, any other account ban from the Accounts page.
UPDATE players SET ban_source = 'admin_pid' WHERE banned = 1;
UPDATE accounts SET ban_source = COALESCE(
  (SELECT 'pid:' || d.pid FROM devices d JOIN players p ON p.pid = d.pid
   WHERE d.account_id = accounts.id AND p.banned = 1 AND p.ban_reason IS accounts.ban_reason LIMIT 1),
  'admin_account')
WHERE banned = 1;
