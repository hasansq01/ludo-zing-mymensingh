// Crash / unexpected-exit reports: POST /v1/diag/crash (ADMIN_API.md "Crashes"). The client sends one report when the
// run before it died (it never closed cleanly, or Android's exit reason says it was killed). No login needed; a valid
// session only attaches the account id. Everything is bounded: the body, every string, the stored payload.
import { ipKey, optionalAccount, type AccEnv } from "./accounts";

export const MAX_BODY = 160 * 1024;
export const MAX_PAYLOAD = 128 * 1024;
export const MAX_LOG = 32 * 1024;
export const MAX_TRACE = 64 * 1024;
/** Reports accepted per day: per client IP (HMAC) and per device id. */
export const LIMITS = { per_ip: 20, per_pid: 5 } as const;
const DAY_MS = 86_400_000;
const MAX_SAMPLES = 40;
const MAX_CRUMBS = 60;

const ABC = "abcdefghijklmnopqrstuvwxyz234567";
const enc = new TextEncoder();
const bytes = (s: string): number => enc.encode(s).length;

function json(body: unknown, status = 200): Response {
  return Response.json(body, { status, headers: { "Cache-Control": "no-store" } });
}

function newId(): string {
  const r = new Uint8Array(16);
  crypto.getRandomValues(r);
  let s = "crs_";
  for (const v of r) s += ABC[v & 31];
  return s;
}

// ---------- scrubbing and bounding ----------

/** A defensive scrub of free text: bearer tokens, JWT-like strings, e-mail addresses, long hex / base64 tokens. */
export function scrub(text: string): string {
  return text
    .replace(/Bearer\s+\S+/gi, "[redacted]")
    .replace(/eyJ[A-Za-z0-9_-]{5,}(?:\.[A-Za-z0-9_-]+){0,2}/g, "[redacted]")
    .replace(/[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+/g, "[redacted]")
    .replace(/\b[A-Fa-f0-9]{32,}\b/g, "[redacted]")
    // base64 / url-safe tokens: 32+ characters with a letter and a digit (plain identifiers and paths stay)
    .replace(/[A-Za-z0-9+_-]{32,}={0,2}/g, (t) => (/\d/.test(t) && /[A-Za-z]/.test(t) ? "[redacted]" : t));
}

type Obj = Record<string, unknown>;
const isObj = (v: unknown): v is Obj => !!v && typeof v === "object" && !Array.isArray(v);

/** A string cut to `max` characters (control characters but newlines / tabs removed), or undefined. */
function str(v: unknown, max: number): string | undefined {
  if (typeof v !== "string") return undefined;
  // eslint-disable-next-line no-control-regex
  const t = v.replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/g, " ");
  return t.length > max ? t.slice(0, max) : t;
}

function num(v: unknown, min: number, max: number): number | undefined {
  return typeof v === "number" && Number.isFinite(v) ? Math.min(max, Math.max(min, v)) : undefined;
}

/** `o` with the listed keys replaced by their cleaned values (undefined drops the key); unknown keys are kept. */
function clean(o: Obj, fields: Record<string, (v: unknown) => unknown>): Obj {
  const out: Obj = { ...o };
  for (const [k, f] of Object.entries(fields)) {
    const v = f(o[k]);
    if (v === undefined) delete out[k];
    else out[k] = v;
  }
  return out;
}

const S = (max: number) => (v: unknown) => str(v, max);
const N = (min: number, max: number) => (v: unknown) => num(v, min, max);
const B = (v: unknown) => (typeof v === "boolean" ? v : undefined);
const sub = (fields: Record<string, (v: unknown) => unknown>) => (v: unknown) => (isObj(v) ? clean(v, fields) : undefined);
const MS = N(0, 4e12);

/** Keeps the end of a text (a log tail) / the start (a trace's top frames), `cut` characters shorter at least. */
const keepEnd = (s: string, cut: number): string => (cut >= s.length ? "" : "…" + s.slice(cut + 3));
const keepStart = (s: string, cut: number): string => (cut >= s.length ? "" : s.slice(0, s.length - cut - 3) + "…");

/**
 * The report as stored: known fields bounded, unknown ones kept. Over MAX_PAYLOAD bytes: the log is shortened first
 * (its END stays: it is a tail), then the trace (its START stays: the top frames), then samples and crumbs are
 * dropped from the start; as a last resort unknown fields (and oversized unknown values inside the sections) go.
 */
export function boundPayload(o: Obj): Obj {
  const p = clean(o, {
    v: N(0, 1000),
    pid: S(64),
    sid: S(40),
    trigger: S(40),
    app: sub({ code: N(0, 1e9), name: S(40) }),
    device: sub({
      model: S(80), os: S(40), os_version: S(40), sdk: N(0, 1000), cpu_count: N(0, 1024), gpu: S(120),
      gpu_vendor: S(80), gpu_api: S(200), screen: S(20), ram_gb: N(0, 1024), tier: S(20),
    }),
    started_at: MS,
    last_at: MS,
    ended: B,
    foreground: B,
    screen: S(40),
    match: sub({ game: S(20), mode: S(20), minutes: N(0, 1e5), turns: N(0, 1e6) }),
    samples: (v) => (Array.isArray(v) ? v.filter(isObj).slice(-MAX_SAMPLES).map((x) => clean(x, {
      t: N(0, 1e8), mem: N(0, 1e6), mem_peak: N(0, 1e6), vmem: N(0, 1e6), fps: N(0, 1e4), objects: N(0, 1e10), nodes: N(0, 1e9), screen: S(40), fg: B,
    })) : undefined),
    crumbs: (v) => (Array.isArray(v) ? v.filter(isObj).slice(-MAX_CRUMBS).map((x) => clean(x, { t: N(0, 1e8), e: S(40), d: S(200) })) : undefined),
    exit: sub({
      reason: S(40), code: N(-1e9, 1e9), status: N(-1e9, 1e9), importance: N(0, 1e9), importance_name: S(40), pss_kb: N(0, 1e10),
      rss_kb: N(0, 1e10), at: MS, description: (v) => str(v, 2000) !== undefined ? scrub(str(v, 2000)!) : undefined, trace: S(MAX_TRACE),
    }),
    log: (v) => {
      const t = str(v, Infinity);
      if (t === undefined) return undefined;
      return scrub(t.length > MAX_LOG ? t.slice(t.length - MAX_LOG) : t);
    },
  });
  const size = () => bytes(JSON.stringify(p));
  let over = size() - MAX_PAYLOAD;
  if (over > 0 && typeof p.log === "string") {
    p.log = keepEnd(p.log, over);
    over = size() - MAX_PAYLOAD;
  }
  const ex = p.exit as Obj | undefined;
  if (over > 0 && ex && typeof ex.trace === "string") {
    ex.trace = keepStart(ex.trace, over);
    over = size() - MAX_PAYLOAD;
  }
  while (over > 0) {
    const s = p.samples as unknown[] | undefined;
    const c = p.crumbs as unknown[] | undefined;
    const target = s?.length || c?.length ? ((s?.length ?? 0) >= (c?.length ?? 0) ? s! : c!) : null;
    if (!target) break;
    target.shift();
    over = size() - MAX_PAYLOAD;
  }
  if (over > 0) {
    const known = new Set(["v", "pid", "sid", "trigger", "app", "device", "started_at", "last_at", "ended", "foreground", "screen", "match", "samples", "crumbs", "exit", "log"]);
    for (const k of Object.keys(p)) if (!known.has(k)) delete p[k];
    for (const k of ["app", "device", "match", "exit"]) {
      const sect = p[k];
      if (isObj(sect)) for (const [f, x] of Object.entries(sect)) if (typeof x === "object" || (typeof x === "string" && x.length > 1000 && f !== "trace")) delete sect[f];
    }
  }
  return p;
}

// ---------- POST /v1/diag/crash ----------

/**
 * POST /v1/diag/crash {v, pid, sid, trigger, app, device, ..., log} -> 200 {ok: true, id}. Needs pid (1-64 chars) and
 * sid (1-40); no login (a valid `Authorization: Bearer` session adds the account id, an invalid one is ignored).
 * Over 160 KB: 413 {error: "too_large"}; bad JSON / pid / sid: 400 {error: "bad_request"}; the same (pid, sid) again:
 * 200 {ok: true, dup: true}; past 20 reports per client IP or 5 per pid in 24 h: 429 {error: "rate"}; D1 down: 503 busy.
 */
export async function postCrash(req: Request, env: AccEnv, now: number): Promise<Response> {
  const len = Number(req.headers.get("Content-Length"));
  if (Number.isFinite(len) && len > MAX_BODY) return json({ error: "too_large" }, 413);
  const text = await req.text();
  if (bytes(text) > MAX_BODY) return json({ error: "too_large" }, 413);
  let o: unknown;
  try {
    o = JSON.parse(text);
  } catch {
    return json({ error: "bad_request" }, 400);
  }
  if (!isObj(o)) return json({ error: "bad_request" }, 400);
  const pid = str(o.pid, 64)?.trim();
  const sid = str(o.sid, 40)?.trim();
  if (!pid || !sid) return json({ error: "bad_request" }, 400);

  const db = env.DB;
  try {
    const dup = await db.prepare("SELECT id FROM crash_reports WHERE pid = ? AND sid = ?").bind(pid, sid).first();
    if (dup) return json({ ok: true, dup: true });
    const ip = await ipKey(env, req);
    const since = now - DAY_MS;
    const [byIp, byPid] = await db.batch([
      db.prepare("SELECT COUNT(*) AS n FROM crash_reports WHERE ip = ? AND received_at > ?").bind(ip ?? "", since),
      db.prepare("SELECT COUNT(*) AS n FROM crash_reports WHERE pid = ? AND received_at > ?").bind(pid, since),
    ]);
    if ((ip && ((byIp.results[0] as { n: number }).n >= LIMITS.per_ip)) || (byPid.results[0] as { n: number }).n >= LIMITS.per_pid) {
      return json({ error: "rate" }, 429);
    }
    const account = await optionalAccount(req, env, now);

    const p = boundPayload({ ...o, pid, sid });
    const app = (p.app ?? {}) as Obj;
    const dev = (p.device ?? {}) as Obj;
    const ex = isObj(p.exit) ? p.exit : null;
    const match = isObj(p.match) ? p.match : null;
    const samples = Array.isArray(p.samples) ? (p.samples as Obj[]) : [];
    let peak: number | null = null;
    for (const s of samples) {
      const v = Math.max(typeof s.mem_peak === "number" ? s.mem_peak : -1, typeof s.mem === "number" ? s.mem : -1);
      if (v >= 0 && (peak === null || v > peak)) peak = v;
    }
    const exitReason = ex && typeof ex.reason === "string" && ex.reason ? ex.reason : null;
    const reason = exitReason ?? (typeof p.trigger === "string" && p.trigger ? p.trigger : "unknown");
    const id = newId();
    const v = (x: unknown) => (x === undefined ? null : x);
    try {
      await db
        .prepare(
          `INSERT INTO crash_reports (id, received_at, pid, sid, account_id, ip, app_code, app_version, model, android, gpu, reason,
             foreground, screen, game, mode, match_min, mem_peak_mb, payload)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        )
        .bind(
          id, now, pid, sid, account, ip, v(app.code), v(app.name), v(dev.model), v(dev.os_version), v(dev.gpu), reason,
          typeof p.foreground === "boolean" ? (p.foreground ? 1 : 0) : null, v(p.screen), v(match?.game), v(match?.mode),
          v(match?.minutes), peak, JSON.stringify(p),
        )
        .run();
    } catch (e) {
      if (String(e).includes("UNIQUE")) return json({ ok: true, dup: true }); // a parallel request stored it first
      throw e;
    }
    return json({ ok: true, id });
  } catch (e) {
    console.error("crash report failed:", e);
    return json({ error: "busy" }, 503);
  }
}
