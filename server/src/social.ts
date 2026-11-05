// Recent players, friends and game invites (PROTOCOL.md "Recent players, friends and invites"; D1 migration 0007):
//   - a Room records who sat at the table when an online match starts (playedStmts): each person's recent list gets
//     every other seat, friend rooms and quick matches alike, the newest 30 kept;
//   - /v1/social/* lists them, adds and removes friends (one-way: a favourites list, nobody is asked or told), sends
//     an invite into the caller's friend room (a push to the person's phones and the pending list the game reads),
//     accepts or declines one, and keeps Settings' "Invites from players";
//   - the daily cron prunes old invites and the ghost rows no list refers to (pruneSocial).
// Privacy: people are known by their public handle (`uid`, 16 hex characters, never the account id). A list only
// ever holds people the account played with or added itself, and only they can be invited. An invite that reaches
// nobody (invites turned off) is answered and stored exactly like one that reaches a phone and is ignored.
// Ghosts (quick-match seats the server plays, src/ghosts.ts) get a handle of the same shape when they are seated and a
// ghost_people row with the identity they had at the table, so they appear in lists like people; an invite to one is
// an invite nobody reads. Every answer below builds a ghost and a person with the same code path and the same fields,
// and the push (the only extra work for a person) runs after the answer, in waitUntil.
import * as A from "./accounts";
import { DEFAULT_AVATAR, DEFAULT_FRAME, levelInfo, reservedName } from "./econ";
import { pushAccount, pushConfigured, type Note } from "./push";
import type { Env, GameKind, Room } from "./room";

export const SOCIAL = {
  recent: 30, // people kept per account (newest first)
  friends: 100, // friends per account
  inviteTtlMs: 10 * 60_000, // an invite expires after this (or when the room's match starts)
  againMs: 60_000, // the same room, still unanswered: another tap reminds them only after this long
  pairPerHour: 6, // invites from the same person to the same person per hour, in any rooms
  declineBlockMs: 30 * 60_000, // after their "Not now": no invites from that person to them for this long
  perHour: 20, // invites one account may send per hour ...
  perDay: 60, // ... and per day
  pushesPerHour: 6, // invite pushes one person gets per hour (more are still listed in the game)
  listInvites: 10, // pending invites listed
  keepMs: 2 * 86_400_000, // invite rows are kept this long (the rate limits read them)
  ghostKeepMs: 30 * 86_400_000, // ghost rows no list refers to are pruned after this
  ghostLevelDays: 4, // a ghost's level seen in a list goes up by one every this many days, ...
  ghostLevelMax: 12, // ... at most this much (people level up while they play; a stored level would never move)
} as const;

export const UID_RE = /^[0-9a-f]{16}$/;
export const INVITE_RE = /^inv_[a-z2-7]{16}$/;
const CODE_RE = /^[23456789ABCDEFGHJKMNPQRSTUVWXYZ]{6}$/;
const ID_ABC = "abcdefghijklmnopqrstuvwxyz234567";

/** A new public handle (accounts.uid, a ghost's handle): 16 hex characters. */
export function newUid(): string {
  return Array.from(crypto.getRandomValues(new Uint8Array(8)), (b) => b.toString(16).padStart(2, "0")).join("");
}

function newInviteId(): string {
  let s = "inv_";
  for (const v of crypto.getRandomValues(new Uint8Array(16))) s += ID_ABC[v & 31];
  return s;
}

/** A ghost seat's identity as stored in ghost_people (Room: Member.gid and its name, avatar, frame, level). */
export interface GhostPerson {
  uid: string;
  name: string;
  avatar: string;
  frame: string;
  level: number;
}

/** A ghost's level as a list shows it: the table's level, a little higher as days pass (SOCIAL.ghostLevel*). */
export function ghostLevel(level: number, created: number, now: number): number {
  const days = Math.max(0, Math.floor((now - created) / (SOCIAL.ghostLevelDays * 86_400_000)));
  return Math.max(1, Math.trunc(level) || 1) + Math.min(SOCIAL.ghostLevelMax, days);
}

const sec = (ms: number) => Math.floor(ms / 1000);

// ---------- the Room: who played ----------

/** One seat of a match for playedStmts: a person (their account, null when unknown) or a ghost. */
export type Played = { account: string | null } | { ghost: GhostPerson };

/**
 * The D1 statements of a match that started at `now` (Room.startMatch): ghost seats get their ghost_people row;
 * accounts without a handle get one; every account gets every other seat (accounts, ghosts) in recent_players, then
 * its list is cut to the newest SOCIAL.recent. `code`: a friend room, whose pending invites end now (null: quick).
 */
export function playedStmts(db: D1Database, seats: Played[], game: GameKind, now: number, code: string | null): D1PreparedStatement[] {
  const accounts = [...new Set(seats.flatMap((s) => ("account" in s && s.account && A.ACCOUNT_RE.test(s.account) ? [s.account] : [])))];
  const ghosts = seats.flatMap((s) => ("ghost" in s && UID_RE.test(s.ghost.uid) ? [s.ghost] : []));
  const out: D1PreparedStatement[] = [];
  for (const g of ghosts) {
    out.push(
      db
        .prepare("INSERT OR IGNORE INTO ghost_people (uid, name, avatar, frame, level, created_at) VALUES (?, ?, ?, ?, ?, ?)")
        .bind(g.uid, g.name, g.avatar, g.frame, Math.max(1, Math.trunc(g.level) || 1), now),
    );
  }
  if (accounts.length) {
    out.push(
      db.prepare(`UPDATE accounts SET uid = lower(hex(randomblob(8))) WHERE uid IS NULL AND id IN (${accounts.map(() => "?").join(", ")})`).bind(...accounts),
    );
  }
  const upsert = "ON CONFLICT (account_id, uid) DO UPDATE SET game = excluded.game, at = excluded.at";
  for (const me of accounts) {
    for (const other of accounts) {
      if (other === me) continue;
      out.push(
        db.prepare(`INSERT INTO recent_players (account_id, uid, game, at) SELECT ?, uid, ?, ? FROM accounts WHERE id = ? AND uid IS NOT NULL ${upsert}`).bind(me, game, now, other),
      );
    }
    for (const g of ghosts) {
      out.push(db.prepare(`INSERT INTO recent_players (account_id, uid, game, at) VALUES (?, ?, ?, ?) ${upsert}`).bind(me, g.uid, game, now));
    }
    out.push(
      db
        .prepare(
          `DELETE FROM recent_players WHERE account_id = ?1 AND uid NOT IN
             (SELECT uid FROM recent_players WHERE account_id = ?1 ORDER BY at DESC, uid LIMIT ${SOCIAL.recent})`,
        )
        .bind(me),
    );
  }
  if (code) out.push(db.prepare("UPDATE invites SET status = 'expired' WHERE code = ? AND status = 'pending'").bind(code));
  return out;
}

// ---------- people ----------

/** The columns that resolve a handle to a person (a live account or a ghost); `r` is the table holding `uid`. */
const PERSON_COLS = `a.id AS account_id, a.name AS name, a.avatar AS avatar, a.frame AS frame, a.xp AS xp,
  g.name AS g_name, g.avatar AS g_avatar, g.frame AS g_frame, g.level AS g_level, g.created_at AS g_created`;
const PERSON_JOIN = (uid: string) => `LEFT JOIN accounts a ON a.uid = ${uid} AND a.banned = 0 AND a.merged_into IS NULL
  LEFT JOIN ghost_people g ON g.uid = ${uid}`;

interface PersonRow {
  uid: string;
  account_id: string | null;
  name: string | null;
  avatar: string | null;
  frame: string | null;
  xp: number | null;
  g_name: string | null;
  g_avatar: string | null;
  g_frame: string | null;
  g_level: number | null;
  g_created: number | null;
}

/** A name as others see it: "You" (the profile's default, what every client calls itself) and "" become "Player". */
export function shownName(name: string | null | undefined): string {
  return name && !reservedName(name) ? name : "Player";
}

/** {uid, name, avatar, frame, level}: the same five fields, built the same way, for a person and a ghost. */
function personOut(r: PersonRow, now: number): Record<string, unknown> {
  const human = r.account_id !== null;
  return {
    uid: r.uid,
    name: shownName(human ? r.name : r.g_name),
    avatar: (human ? r.avatar : r.g_avatar) || DEFAULT_AVATAR,
    frame: (human ? r.frame : r.g_frame) || DEFAULT_FRAME,
    level: human ? levelInfo(Math.max(0, r.xp ?? 0)).level : ghostLevel(r.g_level ?? 1, r.g_created ?? now, now),
  };
}

interface Known extends PersonRow {
  /** Settings' "Invites from players" of the account (1 for a ghost: nothing to look up). */
  invites_on: number;
  played: number;
  friend: number;
}

/** A handle as `viewer` knows it: who it is (null: nobody), whether the viewer played with them / added them. One read. */
async function known(db: D1Database, viewer: string, uid: string): Promise<Known | null> {
  const r = await db
    .prepare(
      `SELECT ?2 AS uid, ${PERSON_COLS}, COALESCE(p.invites, 1) AS invites_on,
         EXISTS (SELECT 1 FROM recent_players WHERE account_id = ?1 AND uid = ?2) AS played,
         EXISTS (SELECT 1 FROM friends WHERE account_id = ?1 AND uid = ?2) AS friend
       FROM (SELECT 1) ${PERSON_JOIN("?2")} LEFT JOIN social_prefs p ON p.account_id = a.id`,
    )
    .bind(viewer, uid)
    .first<Known>();
  return r && (r.account_id !== null || r.g_name !== null) ? r : null;
}

/** The account's own handle (made now when it has none yet). */
async function ownUid(db: D1Database, a: A.Authed): Promise<string> {
  const have = (a.row as A.AccountRow & { uid?: string | null }).uid;
  if (have) return have;
  await db.prepare("UPDATE accounts SET uid = ? WHERE id = ? AND uid IS NULL").bind(newUid(), a.row.id).run();
  return (await db.prepare("SELECT uid FROM accounts WHERE id = ?").bind(a.row.id).first<{ uid: string }>())!.uid;
}

/** The recent list: {uid, name, avatar, frame, level, game, played_at (unix s), friend}, newest first. */
async function recentList(db: D1Database, me: string, now: number): Promise<Record<string, unknown>[]> {
  const { results } = await db
    .prepare(
      `SELECT r.uid AS uid, r.game AS game, r.at AS at, ${PERSON_COLS},
         EXISTS (SELECT 1 FROM friends f WHERE f.account_id = r.account_id AND f.uid = r.uid) AS friend
       FROM recent_players r ${PERSON_JOIN("r.uid")}
       WHERE r.account_id = ? AND (a.id IS NOT NULL OR g.uid IS NOT NULL)
       ORDER BY r.at DESC, r.uid LIMIT ${SOCIAL.recent}`,
    )
    .bind(me)
    .all<PersonRow & { game: string; at: number; friend: number }>();
  return results.map((r) => ({ ...personOut(r, now), game: r.game, played_at: sec(r.at), friend: r.friend === 1 }));
}

/** The friends list: {uid, name, avatar, frame, level, added_at, game, played_at} (the last two null: never played). */
async function friendsList(db: D1Database, me: string, now: number): Promise<Record<string, unknown>[]> {
  const { results } = await db
    .prepare(
      `SELECT f.uid AS uid, f.at AS added, r.game AS game, r.at AS at, ${PERSON_COLS}
       FROM friends f LEFT JOIN recent_players r ON r.account_id = f.account_id AND r.uid = f.uid ${PERSON_JOIN("f.uid")}
       WHERE f.account_id = ? AND (a.id IS NOT NULL OR g.uid IS NOT NULL)
       ORDER BY COALESCE(r.at, f.at) DESC, f.uid LIMIT ${SOCIAL.friends}`,
    )
    .bind(me)
    .all<PersonRow & { added: number; game: string | null; at: number | null }>();
  return results.map((r) => ({ ...personOut(r, now), added_at: sec(r.added), game: r.game ?? null, played_at: r.at === null ? null : sec(r.at) }));
}

async function invitesOn(db: D1Database, me: string): Promise<boolean> {
  const r = await db.prepare("SELECT invites FROM social_prefs WHERE account_id = ?").bind(me).first<{ invites: number }>();
  return !r || r.invites === 1;
}

// ---------- HTTP ----------

function room(env: Env, code: string): DurableObjectStub<Room> {
  return env.ROOMS.get(env.ROOMS.idFromName(code));
}

function str(o: Record<string, unknown>, k: string, re: RegExp, what: string): string {
  const v = o[k];
  if (typeof v !== "string" || !re.test(v)) throw new A.BadRequest(`${k}: ${what}`);
  return v;
}

const GAME_NAMES: Record<string, string> = { ludo: "Ludo", sl: "Snakes & Ladders" };

/**
 * /v1/social/* (authed). null for a path that isn't one of them. Bad input -> A.BadRequest (index.ts answers 400).
 *   GET    social                  -> {recent, friends, prefs: {invites}, max: {recent, friends}}
 *   POST   social/friends          {uid} | {code, member} -> {ok, friend}
 *   DELETE social/friends          {uid} -> {ok}
 *   GET    social/invites          -> {invites: [{id, from, code, game, sent_at, expires_at}]}
 *   POST   social/invites          {uid, code} -> {ok, expires_at}
 *   GET    social/invites/sent     -> {sent: [{uid, status, ...}]}: where the caller's own invites stand
 *   POST   social/invites/accept   {id} | {code} -> {ok, code, game} | 410 gone
 *   POST   social/invites/decline  {id} | {code} -> {ok}
 *   POST   social/prefs            {invites} -> {ok, prefs}
 */
export async function handleSocial(req: Request, env: A.AccEnv, ctx: ExecutionContext, a: A.Authed, path: string, now: number): Promise<Response | null> {
  const m = req.method;
  const method = () => A.json({ error: "method" }, 405);
  switch (path) {
    case "social":
      return m === "GET" ? await overview(env, a, now) : method();
    case "social/friends":
      if (m === "POST") return await addFriend(req, env, a, now);
      return m === "DELETE" ? await removeFriend(req, env, a) : method();
    case "social/invites":
      if (m === "POST") return await sendInvite(req, env, ctx, a, now);
      return m === "GET" ? await pendingInvites(env, a, now) : method();
    case "social/invites/accept":
      return m === "POST" ? await acceptInvite(req, env, a, now) : method();
    case "social/invites/sent":
      return m === "GET" ? await sentInvites(env, a, now) : method();
    case "social/invites/decline":
      return m === "POST" ? await declineInvite(req, env, a, now) : method();
    case "social/prefs":
      return m === "POST" ? await setPrefs(req, env, a, now) : method();
  }
  return null;
}

async function overview(env: A.AccEnv, a: A.Authed, now: number): Promise<Response> {
  const db = env.DB;
  const [recent, friends, invites] = await Promise.all([recentList(db, a.row.id, now), friendsList(db, a.row.id, now), invitesOn(db, a.row.id)]);
  return A.authedJson(a, { recent, friends, prefs: { invites }, max: { recent: SOCIAL.recent, friends: SOCIAL.friends } });
}

/**
 * POST social/friends {uid} (a handle from the lists or the leaderboard) | {code, member} (a member of the room the
 * caller is in: the lobby, a match). Idempotent. 404 not_found (nobody), 400 for yourself, 409 friends_full.
 */
async function addFriend(req: Request, env: A.AccEnv, a: A.Authed, now: number): Promise<Response> {
  const o = await A.readBody(req);
  const db = env.DB;
  let uid: string;
  if (o.uid !== undefined) {
    uid = str(o, "uid", UID_RE, "a player's uid");
  } else {
    const code = str(o, "code", CODE_RE, "a room code");
    if (typeof o.member !== "number" || !Number.isInteger(o.member) || o.member < 1 || o.member > 1000) throw new A.BadRequest("member: a member id");
    const seat = await room(env, code).socialSeat(a.row.id, o.member).catch(() => null);
    if (!seat) return A.authedJson(a, { error: "not_found" }, 404);
    // one batch of two either way: the seat's row made sure of, then its handle read back
    const g = "ghost" in seat ? seat.ghost : null;
    const res = await db.batch<{ uid: string | null }>(
      g
        ? [
            db.prepare("INSERT OR IGNORE INTO ghost_people (uid, name, avatar, frame, level, created_at) VALUES (?, ?, ?, ?, ?, ?)").bind(g.uid, g.name, g.avatar, g.frame, g.level, now),
            db.prepare("SELECT uid FROM ghost_people WHERE uid = ?").bind(g.uid),
          ]
        : [
            db.prepare("UPDATE accounts SET uid = ? WHERE id = ? AND uid IS NULL").bind(newUid(), (seat as { account: string }).account),
            db.prepare("SELECT uid FROM accounts WHERE id = ?").bind((seat as { account: string }).account),
          ],
    );
    const found = res[1].results[0]?.uid;
    if (!found) return A.authedJson(a, { error: "not_found" }, 404);
    uid = found;
  }
  if (uid === (await ownUid(db, a))) throw new A.BadRequest("that is you");
  const p = await known(db, a.row.id, uid);
  if (!p) return A.authedJson(a, { error: "not_found" }, 404);
  if (!p.friend) {
    const n = await db.prepare("SELECT COUNT(*) AS n FROM friends WHERE account_id = ?").bind(a.row.id).first<{ n: number }>();
    if ((n?.n ?? 0) >= SOCIAL.friends) return A.authedJson(a, { error: "friends_full", max: SOCIAL.friends }, 409);
    await db.prepare("INSERT OR IGNORE INTO friends (account_id, uid, at) VALUES (?, ?, ?)").bind(a.row.id, uid, now).run();
  }
  return A.authedJson(a, { ok: true, friend: personOut(p, now) });
}

/** DELETE social/friends {uid}: off the list (nothing else changes; idempotent). */
async function removeFriend(req: Request, env: A.AccEnv, a: A.Authed): Promise<Response> {
  const uid = str(await A.readBody(req), "uid", UID_RE, "a player's uid");
  await env.DB.prepare("DELETE FROM friends WHERE account_id = ? AND uid = ?").bind(a.row.id, uid).run();
  return A.authedJson(a, { ok: true });
}

/**
 * POST social/invites {uid, code}: invite someone from the recent or friends list into the caller's friend room
 * `code`. 404 not_found: not someone on the caller's lists; 409 not_in_room / room_full / started: the caller's
 * room can't take them (Room.inviteCheck). Invites are open by default: a new room's invite replaces the old one at
 * once, and an unanswered one can be repeated after SOCIAL.againMs (sooner: answered {ok} with no second push). What
 * stops them: 429 {error: "rate", scope: "person", declined: true, retry_at}: they said "Not now" (an explicit answer;
 * ignoring an invite never blocks); 429 {error: "rate", scope: "person", retry_at}: SOCIAL.pairPerHour; 429 {error:
 * "rate", scope: "total", retry_at}: SOCIAL.perHour / perDay in all. Otherwise 200 {ok, expires_at, again_at} whatever
 * happens next: the invite reaches the person (listed, pushed) only when their invites are on, and nobody is told
 * whether it did.
 */
async function sendInvite(req: Request, env: A.AccEnv, ctx: ExecutionContext, a: A.Authed, now: number): Promise<Response> {
  const o = await A.readBody(req);
  const uid = str(o, "uid", UID_RE, "a player's uid");
  const code = str(o, "code", CODE_RE, "a room code");
  const db = env.DB;
  const me = a.row.id;
  if (uid === (await ownUid(db, a))) throw new A.BadRequest("that is you");
  const p = await known(db, me, uid);
  if (!p || (!p.played && !p.friend)) return A.authedJson(a, { error: "not_found" }, 404);
  const check = await room(env, code)
    .inviteCheck(me)
    .catch((): { ok: false; error: "not_in_room" } => ({ ok: false, error: "not_in_room" }));
  if (!check.ok) return A.authedJson(a, { error: check.error }, 409);
  const r = await db
    .prepare(
      `SELECT COALESCE(SUM(to_uid = ?2 AND at > ?4), 0) AS pair, MIN(CASE WHEN to_uid = ?2 AND at > ?4 THEN at END) AS pair_first,
         MAX(CASE WHEN to_uid = ?2 AND status = 'declined' THEN expires_at END) AS declined_at,
         MAX(CASE WHEN to_uid = ?2 AND code = ?3 AND status = 'pending' AND expires_at > ?6 THEN at END) AS open_at,
         MAX(CASE WHEN to_uid = ?2 AND code = ?3 AND status = 'pending' AND expires_at > ?6 THEN expires_at END) AS open_until,
         COALESCE(SUM(at > ?4), 0) AS hour, MIN(CASE WHEN at > ?4 THEN at END) AS hour_first,
         COUNT(*) AS day, MIN(at) AS day_first
       FROM invites WHERE from_account = ?1 AND at > ?5`,
    )
    .bind(me, uid, code, now - 3_600_000, now - 86_400_000, now)
    .first<{ pair: number; pair_first: number | null; declined_at: number | null; open_at: number | null; open_until: number | null; hour: number; hour_first: number | null; day: number; day_first: number | null }>();
  if (r?.declined_at && now < r.declined_at + SOCIAL.declineBlockMs) {
    return A.authedJson(a, { error: "rate", scope: "person", declined: true, retry_at: sec(r.declined_at + SOCIAL.declineBlockMs) }, 429);
  }
  if (r?.open_at && now < r.open_at + SOCIAL.againMs) {
    return A.authedJson(a, { ok: true, expires_at: sec(r.open_until ?? now), again_at: sec(r.open_at + SOCIAL.againMs) });
  }
  if (r && r.pair >= SOCIAL.pairPerHour) return A.authedJson(a, { error: "rate", scope: "person", retry_at: sec((r.pair_first ?? now) + 3_600_000) }, 429);
  if (r && r.hour >= SOCIAL.perHour) return A.authedJson(a, { error: "rate", scope: "total", retry_at: sec((r.hour_first ?? now) + 3_600_000) }, 429);
  if (r && r.day >= SOCIAL.perDay) return A.authedJson(a, { error: "rate", scope: "total", retry_at: sec((r.day_first ?? now) + 86_400_000) }, 429);
  const id = newInviteId();
  const to = p.account_id !== null && p.invites_on === 1 ? p.account_id : null;
  const expires = now + SOCIAL.inviteTtlMs;
  await db.batch([
    db.prepare("UPDATE invites SET status = 'expired' WHERE from_account = ? AND to_uid = ? AND status = 'pending'").bind(me, uid), // (the room they were asked to before)
    db
      .prepare("INSERT INTO invites (id, from_account, to_uid, to_account, code, game, at, expires_at, status) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'pending')")
      .bind(id, me, uid, to, code, check.game, now, expires),
  ]);
  if (to) ctx.waitUntil(invitePush(env, id, to, shownName(check.name), check.game, code, now).catch((e) => console.error("invite push failed:", e)));
  return A.authedJson(a, { ok: true, expires_at: sec(expires), again_at: sec(now + SOCIAL.againMs) });
}

/**
 * GET social/invites/sent: where the caller's invites stand, for the lists' buttons: {sent: [{uid, status: "invited",
 * code, expires_at, again_at} | {uid, status: "declined", retry_at}]}. Accepted, expired and replaced ones aren't listed.
 */
async function sentInvites(env: A.AccEnv, a: A.Authed, now: number): Promise<Response> {
  const { results } = await env.DB.prepare(
    "SELECT to_uid AS uid, code, status, at, expires_at AS exp FROM invites WHERE from_account = ? AND at > ? ORDER BY at ASC",
  )
    .bind(a.row.id, now - SOCIAL.inviteTtlMs - SOCIAL.declineBlockMs)
    .all<{ uid: string; code: string; status: string; at: number; exp: number }>();
  const last = new Map(results.map((r) => [r.uid, r]));
  const sent: Record<string, unknown>[] = [];
  for (const r of last.values()) {
    if (r.status === "pending" && r.exp > now) sent.push({ uid: r.uid, status: "invited", code: r.code, expires_at: sec(r.exp), again_at: sec(r.at + SOCIAL.againMs) });
    else if (r.status === "declined" && now < r.exp + SOCIAL.declineBlockMs) sent.push({ uid: r.uid, status: "declined", retry_at: sec(r.exp + SOCIAL.declineBlockMs) });
  }
  return A.authedJson(a, { sent });
}

/** The invite's push (kind "invite", channel game, link room:<CODE>), unless the person had SOCIAL.pushesPerHour. */
async function invitePush(env: A.AccEnv, id: string, to: string, name: string, game: GameKind, code: string, now: number): Promise<void> {
  if (!pushConfigured(env)) return;
  // the cap and the mark in one statement (invites sent a moment apart push in parallel)
  const r = await env.DB.prepare(
    "UPDATE invites SET pushed = 1 WHERE id = ?1 AND (SELECT COUNT(*) FROM invites WHERE to_account = ?2 AND pushed = 1 AND at > ?3) < ?4",
  )
    .bind(id, to, now - 3_600_000, SOCIAL.pushesPerHour)
    .run();
  if (!r.meta.changes) return;
  const note: Note = {
    kind: "invite",
    title: "Game invite",
    body: `${name} invited you to play ${GAME_NAMES[game] ?? "Ludo"} in room ${code}`,
    link: `room:${code}`,
    channel: "game",
    tag: `invite:${code}`,
    ttl_s: Math.floor(SOCIAL.inviteTtlMs / 1000),
  };
  await pushAccount(env, to, note, { pref: "game", count: true });
}

/** GET social/invites: the pending invites to the caller (newest first), each with who sent it. */
async function pendingInvites(env: A.AccEnv, a: A.Authed, now: number): Promise<Response> {
  const { results } = await env.DB.prepare(
    `SELECT i.id AS id, i.code AS code, i.game AS game, i.at AS sent, i.expires_at AS expires,
       a.uid AS uid, a.id AS account_id, a.name AS name, a.avatar AS avatar, a.frame AS frame, a.xp AS xp
     FROM invites i JOIN accounts a ON a.id = i.from_account AND a.banned = 0 AND a.merged_into IS NULL
     WHERE i.to_account = ? AND i.status = 'pending' AND i.expires_at > ?
     ORDER BY i.at DESC LIMIT ${SOCIAL.listInvites}`,
  )
    .bind(a.row.id, now)
    .all<PersonRow & { id: string; code: string; game: string; sent: number; expires: number }>();
  const invites = results.map((r) => ({ id: r.id, from: personOut(r, now), code: r.code, game: r.game, sent_at: sec(r.sent), expires_at: sec(r.expires) }));
  return A.authedJson(a, { invites });
}

/** {id} or {code} (a push was tapped: only the room is known) of the caller's pending invites. */
function inviteKey(o: Record<string, unknown>): { id: string | null; code: string | null } {
  if (o.id !== undefined) return { id: str(o, "id", INVITE_RE, "an invite id"), code: null };
  return { id: null, code: str(o, "code", CODE_RE, "a room code") };
}

/**
 * POST social/invites/accept {id} | {code}: the invite (still pending, not expired, the inviter still in the room and
 * the room still taking people: Room.inviteCheck) is accepted: {ok, code, game}; the game then joins the room as with
 * a code. Otherwise 410 {error: "gone"} (and it is expired).
 */
async function acceptInvite(req: Request, env: A.AccEnv, a: A.Authed, now: number): Promise<Response> {
  const k = inviteKey(await A.readBody(req));
  const db = env.DB;
  const inv = await db
    .prepare(
      "SELECT id, from_account, code, game FROM invites WHERE to_account = ? AND status = 'pending' AND expires_at > ? AND (id = ? OR code = ?) ORDER BY at DESC LIMIT 1",
    )
    .bind(a.row.id, now, k.id, k.code)
    .first<{ id: string; from_account: string; code: string; game: string }>();
  if (!inv) return A.authedJson(a, { error: "gone" }, 410);
  // still worth joining: the inviter is still in the room and it can still take someone
  const check = await room(env, inv.code)
    .inviteCheck(inv.from_account)
    .catch(() => null);
  const open = !!check && check.ok;
  await db
    .prepare(`UPDATE invites SET status = ? WHERE to_account = ? AND code = ? AND status = 'pending'`)
    .bind(open ? "accepted" : "expired", a.row.id, inv.code)
    .run();
  if (!open) return A.authedJson(a, { error: "gone" }, 410);
  return A.authedJson(a, { ok: true, code: inv.code, game: check.game });
}

/**
 * POST social/invites/decline {id} | {code}: "Not now". Idempotent. The inviter's row then says so, and they can't
 * invite this person again for SOCIAL.declineBlockMs (counted from expires_at, which a decline sets to now).
 */
async function declineInvite(req: Request, env: A.AccEnv, a: A.Authed, now: number): Promise<Response> {
  const k = inviteKey(await A.readBody(req));
  await env.DB.prepare("UPDATE invites SET status = 'declined', expires_at = ? WHERE to_account = ? AND status = 'pending' AND (id = ? OR code = ?)")
    .bind(now, a.row.id, k.id, k.code)
    .run();
  return A.authedJson(a, { ok: true });
}

/** POST social/prefs {invites: bool}: Settings' "Invites from players". Off also ends the pending ones. */
async function setPrefs(req: Request, env: A.AccEnv, a: A.Authed, now: number): Promise<Response> {
  const o = await A.readBody(req);
  if (typeof o.invites !== "boolean") throw new A.BadRequest("invites: bool");
  const db = env.DB;
  const stmts = [
    db
      .prepare("INSERT INTO social_prefs (account_id, invites, updated_at) VALUES (?, ?, ?) ON CONFLICT (account_id) DO UPDATE SET invites = excluded.invites, updated_at = excluded.updated_at")
      .bind(a.row.id, o.invites ? 1 : 0, now),
  ];
  if (!o.invites) stmts.push(db.prepare("UPDATE invites SET status = 'expired' WHERE to_account = ? AND status = 'pending'").bind(a.row.id));
  await db.batch(stmts);
  return A.authedJson(a, { ok: true, prefs: { invites: o.invites } });
}

// ---------- erase, prune ----------

/**
 * The rows of these accounts (admin "Erase account"): their lists, prefs and invites, and every row that points at
 * their handles (others' recent / friends entries, invites to them). `uids`: the accounts' handles, read beforehand.
 */
export function eraseStmts(db: D1Database, ids: string[], uids: string[]): D1PreparedStatement[] {
  const IN = (n: number) => `(${Array(n).fill("?").join(", ")})`;
  const U = uids.length ? uids : [""];
  return [
    db.prepare(`DELETE FROM recent_players WHERE account_id IN ${IN(ids.length)} OR uid IN ${IN(U.length)}`).bind(...ids, ...U),
    db.prepare(`DELETE FROM friends WHERE account_id IN ${IN(ids.length)} OR uid IN ${IN(U.length)}`).bind(...ids, ...U),
    db
      .prepare(`DELETE FROM invites WHERE from_account IN ${IN(ids.length)} OR to_account IN ${IN(ids.length)} OR to_uid IN ${IN(U.length)}`)
      .bind(...ids, ...ids, ...U),
    db.prepare(`DELETE FROM social_prefs WHERE account_id IN ${IN(ids.length)}`).bind(...ids),
  ];
}

/** Daily cron: invites older than SOCIAL.keepMs, ghost rows older than SOCIAL.ghostKeepMs that no list refers to. */
export async function pruneSocial(db: D1Database, now: number): Promise<{ invites: number; ghosts: number }> {
  const res = await db.batch([
    db.prepare("DELETE FROM invites WHERE at < ?").bind(now - SOCIAL.keepMs),
    db
      .prepare(
        `DELETE FROM ghost_people WHERE created_at < ? AND NOT EXISTS (SELECT 1 FROM recent_players r WHERE r.uid = ghost_people.uid)
           AND NOT EXISTS (SELECT 1 FROM friends f WHERE f.uid = ghost_people.uid)`,
      )
      .bind(now - SOCIAL.ghostKeepMs),
  ]);
  return { invites: res[0].meta.changes ?? 0, ghosts: res[1].meta.changes ?? 0 };
}
