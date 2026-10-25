// The Pusher Durable Object (NOTIFICATIONS.md "N-SRV"): one instance ("pusher") holds the queue of bulk pushes in its
// SQLite storage and sends them from its alarm, at most SENDS_PER_ALARM per invocation (the free plan allows 50
// subrequests per invocation), re-arming while work is left. A Worker request never sends in bulk itself.
//
// Jobs: "campaign" (an admin campaign due at run_at: claims it in D1, then sends to the topic ("everyone") or turns
// into "expand"), "expand" (pages a segment's tokens out of D1 into send jobs, one page per alarm), "send" (one push
// to one token: a campaign's, whose note is in `notes`, or a queued event push such as the weekly result, which
// carries its own). D1 is the source of truth for a campaign's status: the claim is a conditional update, so a
// cancel and the start can't both win.
import { DurableObject } from "cloudflare:workers";
import * as P from "./push";
import type { Env } from "./room";

/**
 * FCM sends per alarm invocation, a campaign's topic send included. With at most 2 OAuth calls (a renewal) and 5 D1
 * calls (claim, count, one expansion page, the result batch) a drain stays under the 50 subrequests.
 */
export const SENDS_PER_ALARM = 40;
/** Tokens a segment's expansion reads from D1 per alarm. */
export const EXPAND_PAGE = 500;
/** The next alarm while due work is left (spreads a large campaign a little). */
const PACE_MS = 1000;
/** A send that failed for now (FCM 429 / 5xx, network) is retried after 1 min, then 2 min, then counted failed. */
const RETRY = { baseMs: 60_000, tries: 3 };
/** Batch keys (the weekly result's week) are kept this long. */
const BATCH_KEEP_MS = 60 * 86_400_000;

type JobRow = {
  id: number;
  kind: "campaign" | "expand" | "send";
  run_at: number;
  cid: string | null;
  token: string | null;
  note: string | null;
  cursor: string | null;
  tries: number;
};

export interface QueuedPush {
  /** Unique per job: the same key queued again is ignored. */
  key: string;
  token: string;
  note: P.Note;
}

/** Test-only knobs (TEST_MODE): the pace between alarms while work is due. */
export interface PusherHooks {
  paceMs?: number;
}

/** What one alarm invocation did (tests). */
export interface DrainStats {
  sends: number;
  sent: number;
  failed: number;
  dead: number;
  retried: number;
  started: number;
  expanded: number;
}

/** Per campaign / event kind results of one drain, written to D1 in one batch at its end. */
interface Tally {
  campaigns: Map<string, { sent: number; failed: number; targeted: number }>;
  events: Map<P.PushKind, { sent: number; failed: number }>;
  dead: Set<string>;
  /** Campaigns to close (claimed and nothing left in the queue): id -> null, or the status to set ("failed"). */
  close: Map<string, string | null>;
}

export class Pusher extends DurableObject<Env> {
  private sql: SqlStorage;
  private hooks: PusherHooks = {};
  private last: DrainStats | null = null;

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.sql = ctx.storage.sql;
    this.sql.exec(`
      CREATE TABLE IF NOT EXISTS jobs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        key TEXT UNIQUE,
        kind TEXT NOT NULL,
        run_at INTEGER NOT NULL,
        cid TEXT,
        token TEXT,
        note TEXT,
        cursor TEXT,
        tries INTEGER NOT NULL DEFAULT 0
      );
      CREATE INDEX IF NOT EXISTS jobs_due ON jobs (run_at, id);
      CREATE INDEX IF NOT EXISTS jobs_cid ON jobs (cid);
      CREATE TABLE IF NOT EXISTS notes (cid TEXT PRIMARY KEY, note TEXT NOT NULL, audience TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS batches (key TEXT PRIMARY KEY, at INTEGER NOT NULL);
    `);
    if (env.TEST_MODE === "1") this.hooks = ctx.storage.kv.get<PusherHooks>("hooks") ?? {};
  }

  // ----- RPC -----

  /** Queues a campaign (already in D1, status scheduled or sending) to start at runAt (epoch ms). */
  async enqueueCampaign(cid: string, runAt: number): Promise<void> {
    this.sql.exec("INSERT OR IGNORE INTO jobs (key, kind, run_at, cid) VALUES (?, 'campaign', ?, ?)", `campaign:${cid}`, runAt, cid);
    await this.arm(runAt);
  }

  /** Drops a campaign's jobs (the admin canceled it in D1 first). The number dropped. */
  async cancelCampaign(cid: string): Promise<number> {
    this.sql.exec("DELETE FROM jobs WHERE cid = ?", cid);
    const n = this.changes();
    this.sql.exec("DELETE FROM notes WHERE cid = ?", cid);
    return n;
  }

  /**
   * Queues pushes to send now, once per batch key (the weekly result: "weekly:<week>"; a second call with the same
   * batch, e.g. a retried cron, queues nothing). The number queued.
   */
  async enqueueBatch(batch: string, jobs: QueuedPush[]): Promise<number> {
    const now = Date.now();
    this.sql.exec("DELETE FROM batches WHERE at < ?", now - BATCH_KEEP_MS);
    if (this.sql.exec("SELECT 1 FROM batches WHERE key = ?", batch).toArray().length) return 0;
    let n = 0;
    this.ctx.storage.transactionSync(() => {
      this.sql.exec("INSERT INTO batches (key, at) VALUES (?, ?)", batch, now);
      for (const j of jobs) {
        this.sql.exec("INSERT OR IGNORE INTO jobs (key, kind, run_at, token, note) VALUES (?, 'send', ?, ?, ?)", j.key, now, j.token, JSON.stringify(j.note));
        n += this.changes();
      }
    });
    if (n) await this.arm(now);
    return n;
  }

  /** The queue: jobs by kind, the next run time (epoch ms, null when empty). */
  async pending(): Promise<{ jobs: number; campaign: number; expand: number; send: number; next_at: number | null; alarm: number | null }> {
    const out = { jobs: 0, campaign: 0, expand: 0, send: 0, next_at: null as number | null, alarm: await this.ctx.storage.getAlarm() };
    for (const r of this.sql.exec<{ kind: JobRow["kind"]; n: number; t: number }>("SELECT kind, COUNT(*) AS n, MIN(run_at) AS t FROM jobs GROUP BY kind")) {
      out[r.kind] = r.n;
      out.jobs += r.n;
      out.next_at = out.next_at === null ? r.t : Math.min(out.next_at, r.t);
    }
    return out;
  }

  /** Rows changed by the last statement (rowsWritten would count index rows too). */
  private changes(): number {
    return this.sql.exec<{ n: number }>("SELECT changes() AS n").one().n;
  }

  async testHooks(h: PusherHooks): Promise<void> {
    if (this.env.TEST_MODE !== "1") throw new Error("test hooks are disabled");
    this.hooks = h;
    this.ctx.storage.kv.put("hooks", h);
  }

  /** The last alarm's counts (TEST_MODE only). */
  async testLast(): Promise<DrainStats | null> {
    if (this.env.TEST_MODE !== "1") throw new Error("test hooks are disabled");
    return this.last;
  }

  // ----- the alarm: one drain -----

  async alarm(): Promise<void> {
    try {
      await this.drain();
    } catch (e) {
      console.error("pusher drain failed:", e);
    }
    await this.rearm();
  }

  /**
   * One drain, in three steps: the first due campaign starts (a claim; "all" is its one topic send), the first due
   * segment expansion reads one page, then due sends up to the budget (40, less a topic send) go out in parallel.
   * Their results are tallied and written to D1 in one batch; campaigns with nothing left in the queue are closed.
   */
  private async drain(): Promise<void> {
    const now = Date.now();
    const on = P.pushConfigured(this.env);
    const stats: DrainStats = { sends: 0, sent: 0, failed: 0, dead: 0, retried: 0, started: 0, expanded: 0 };
    this.last = stats;
    const t: Tally = { campaigns: new Map(), events: new Map(), dead: new Set(), close: new Map() };
    const touched = new Set<string>();
    let budget = SENDS_PER_ALARM;

    const first = (kind: JobRow["kind"]) =>
      this.sql.exec<JobRow>("SELECT * FROM jobs WHERE kind = ? AND run_at <= ? ORDER BY run_at, id LIMIT 1", kind, now).toArray()[0];
    const camp = first("campaign");
    if (camp) {
      stats.started++;
      budget -= await this.start(camp, on, t, now);
      touched.add(camp.cid!);
    }
    const exp = first("expand");
    if (exp) {
      stats.expanded += await this.expand(exp, t, now);
      touched.add(exp.cid!);
    }

    const notes = new Map<string, P.Note | null>();
    const sends: Array<{ j: JobRow; note: P.Note }> = [];
    const due = this.sql.exec<JobRow>("SELECT * FROM jobs WHERE kind = 'send' AND run_at <= ? ORDER BY run_at, id LIMIT ?", now, Math.max(0, budget)).toArray();
    for (const j of due) {
      if (j.cid) touched.add(j.cid);
      const note = this.noteOf(j, notes);
      if (note && on) {
        sends.push({ j, note });
        continue;
      }
      this.sql.exec("DELETE FROM jobs WHERE id = ?", j.id); // push switched off meanwhile (or a broken job)
      if (note) this.tally(t, j, note, "failed");
      stats.failed++;
    }
    stats.sends = sends.length;
    const rs = await Promise.all(sends.map(({ j, note }) => P.send(this.env, { token: j.token! }, note)));
    sends.forEach(({ j, note }, k) => {
      let r = rs[k];
      if (r === "retry" && j.tries + 1 < RETRY.tries) {
        this.sql.exec("UPDATE jobs SET tries = tries + 1, run_at = ? WHERE id = ?", now + RETRY.baseMs * 2 ** j.tries, j.id);
        stats.retried++;
        return;
      }
      if (r === "retry") r = "failed";
      this.sql.exec("DELETE FROM jobs WHERE id = ?", j.id);
      if (r === "dead") {
        t.dead.add(j.token!);
        stats.dead++;
      }
      if (r === "sent") stats.sent++;
      else stats.failed++;
      this.tally(t, j, note, r === "sent" ? "sent" : "failed");
    });
    for (const cid of touched) {
      if (!this.sql.exec("SELECT 1 FROM jobs WHERE cid = ? LIMIT 1", cid).toArray().length) {
        if (!t.close.has(cid)) t.close.set(cid, null);
        this.sql.exec("DELETE FROM notes WHERE cid = ?", cid);
      }
    }
    await this.flush(t, now);
  }

  /** A send job's note: its own (event pushes) or its campaign's (`notes`, read once per drain). */
  private noteOf(j: JobRow, cache: Map<string, P.Note | null>): P.Note | null {
    const parse = (raw: string | undefined | null): P.Note | null => {
      if (!raw) return null;
      try {
        return JSON.parse(raw) as P.Note;
      } catch {
        return null;
      }
    };
    if (j.note) return parse(j.note);
    if (!j.cid) return null;
    if (!cache.has(j.cid)) cache.set(j.cid, parse(this.sql.exec<{ note: string }>("SELECT note FROM notes WHERE cid = ?", j.cid).toArray()[0]?.note));
    return cache.get(j.cid)!;
  }

  private tally(t: Tally, j: JobRow, note: P.Note, r: "sent" | "failed"): void {
    if (j.cid) {
      const c = t.campaigns.get(j.cid) ?? { sent: 0, failed: 0, targeted: 0 };
      c[r]++;
      t.campaigns.set(j.cid, c);
    } else {
      const e = t.events.get(note.kind) ?? { sent: 0, failed: 0 };
      e[r]++;
      t.events.set(note.kind, e);
    }
  }

  /**
   * A campaign is due: claimed in D1 (scheduled / sending -> sending, its content read back; a canceled or unknown
   * one is dropped). "all": one topic send (targeted = the devices with offers on), done. A segment: its note is kept
   * and the job becomes the segment's expansion. Returns the sends used (0 or 1).
   */
  private async start(j: JobRow, on: boolean, t: Tally, now: number): Promise<number> {
    const cid = j.cid!;
    const db = this.env.DB;
    if (!on) {
      // push was switched off after it was queued: it can't be sent
      this.sql.exec("DELETE FROM jobs WHERE cid = ?", cid);
      await db.prepare("UPDATE push_campaigns SET status = 'failed', sent_at = ? WHERE id = ? AND status IN ('scheduled', 'sending')").bind(now, cid).run();
      return 0;
    }
    const c = await db
      // targeted counts from 0 again: the devices actually sent to replace the admin's estimate
      .prepare(
        "UPDATE push_campaigns SET status = 'sending', targeted = 0 WHERE id = ? AND status IN ('scheduled', 'sending') RETURNING id, title, body, link, audience",
      )
      .bind(cid)
      .first<Pick<P.CampaignRow, "id" | "title" | "body" | "link" | "audience">>();
    if (!c) {
      this.sql.exec("DELETE FROM jobs WHERE cid = ?", cid);
      return 0;
    }
    const aud = P.parseAudience(JSON.parse(c.audience));
    const note = P.campaignNote(c);
    if (typeof aud === "string") {
      this.sql.exec("DELETE FROM jobs WHERE id = ?", j.id);
      t.close.set(cid, "failed");
      return 0;
    }
    if (aud.kind === "all") {
      const targeted = await P.countAudience(db, aud, now);
      const r = await P.send(this.env, { topic: P.PROMO_TOPIC }, note);
      if (r === "retry" && j.tries + 1 < RETRY.tries) {
        this.sql.exec("UPDATE jobs SET tries = tries + 1, run_at = ? WHERE id = ?", now + RETRY.baseMs * 2 ** j.tries, j.id);
        return 1;
      }
      this.sql.exec("DELETE FROM jobs WHERE id = ?", j.id);
      t.campaigns.set(cid, { targeted, sent: r === "sent" ? targeted : 0, failed: r === "sent" ? 0 : targeted });
      if (r !== "sent") t.close.set(cid, "failed");
      return 1;
    }
    this.sql.exec("INSERT OR REPLACE INTO notes (cid, note, audience) VALUES (?, ?, ?)", cid, JSON.stringify(note), c.audience);
    this.sql.exec("UPDATE jobs SET kind = 'expand', cursor = '', run_at = ? WHERE id = ?", now, j.id);
    return 0;
  }

  /** One page of a segment's tokens -> send jobs. Returns the jobs added. */
  private async expand(j: JobRow, t: Tally, now: number): Promise<number> {
    const cid = j.cid!;
    const n = this.sql.exec<{ audience: string }>("SELECT audience FROM notes WHERE cid = ?", cid).toArray()[0];
    const aud = n ? P.parseAudience(JSON.parse(n.audience)) : "gone";
    if (typeof aud === "string") {
      this.sql.exec("DELETE FROM jobs WHERE id = ?", j.id);
      return 0;
    }
    const tokens = await P.audiencePage(this.env.DB, aud, now, j.cursor ?? "", EXPAND_PAGE);
    this.ctx.storage.transactionSync(() => {
      for (const token of tokens) {
        this.sql.exec("INSERT OR IGNORE INTO jobs (key, kind, run_at, cid, token) VALUES (?, 'send', ?, ?, ?)", `${cid}:${token}`, now, cid, token);
      }
      if (tokens.length < EXPAND_PAGE) this.sql.exec("DELETE FROM jobs WHERE id = ?", j.id);
      else this.sql.exec("UPDATE jobs SET cursor = ? WHERE id = ?", tokens[tokens.length - 1], j.id);
    });
    const c = t.campaigns.get(cid) ?? { sent: 0, failed: 0, targeted: 0 };
    c.targeted += tokens.length;
    t.campaigns.set(cid, c);
    return tokens.length;
  }

  /** The drain's D1 writes in one batch: campaign counters and closes, event counters, dead tokens. */
  private async flush(t: Tally, now: number): Promise<void> {
    const db = this.env.DB;
    const stmts: D1PreparedStatement[] = [];
    for (const [cid, c] of t.campaigns) {
      if (!c.sent && !c.failed && !c.targeted) continue;
      stmts.push(
        db
          .prepare("UPDATE push_campaigns SET sent = sent + ?, failed = failed + ?, targeted = targeted + ? WHERE id = ?")
          .bind(c.sent, c.failed, c.targeted, cid),
      );
    }
    for (const [cid, status] of t.close) {
      stmts.push(
        db
          .prepare(
            `UPDATE push_campaigns SET sent_at = ?, status = COALESCE(?, CASE WHEN sent = 0 AND failed > 0 THEN 'failed' ELSE 'sent' END)
             WHERE id = ? AND status = 'sending'`,
          )
          .bind(now, status, cid),
      );
    }
    for (const [kind, e] of t.events) stmts.push(P.countEvent(db, kind, e.sent, e.failed, now));
    stmts.push(...P.dropTokens(db, [...t.dead]));
    if (!stmts.length) return;
    try {
      await db.batch(stmts);
    } catch (e) {
      console.error("pusher D1 write failed:", e); // the counts of this drain are lost; the pushes went out
    }
  }

  // ----- the alarm -----

  /** Sets the alarm to `at` unless one is due sooner. */
  private async arm(at: number): Promise<void> {
    const cur = await this.ctx.storage.getAlarm();
    if (cur === null || at < cur) await this.ctx.storage.setAlarm(at);
  }

  /** After a drain: the next alarm at the next job (a little later when work is due now), none when empty. */
  private async rearm(): Promise<void> {
    const r = this.sql.exec<{ t: number | null }>("SELECT MIN(run_at) AS t FROM jobs").one();
    if (r.t === null) return;
    const pace = this.env.TEST_MODE === "1" ? (this.hooks.paceMs ?? PACE_MS) : PACE_MS;
    await this.ctx.storage.setAlarm(Math.max(r.t, Date.now() + pace));
  }
}
