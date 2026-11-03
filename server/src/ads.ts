// Rewarded ads (ECONOMY_V1.md §2, §5): the game asks for a nonce (POST /v1/ads/start {kind, ref?}), shows a rewarded
// ad with AdMob's server-side verification options (user_id = the account, custom_data = the nonce), and AdMob calls
// GET /v1/ads/ssv when the ad was watched. The callback is checked against Google's published ECDSA keys and grants
// the reward once (transaction_id is unique); the game polls GET /v1/ads/status?nonce=. Nothing is granted on the
// game's word. Day caps per kind and in total (Bangladesh day), checked at start and again at the callback.
// LevelPlay (the primary network) does the same through GET /v1/ads/levelplay: its MD5 signature with the private key
// (secret LEVELPLAY_S2S_KEY), the nonce and account id as custom parameters, eventId once. Both grant via grantAd().
import { type AccEnv, type Authed, type Step, BadRequest, authedJson, json, mutate, readBody } from "./accounts";
import { ECON_V1, addCoins, type Profile } from "./econ";
import { econDay, econDayStartMs } from "./wallet";
import { nextDayAt } from "./econ";
import { gcall } from "./gauth";

export const KEYS_URL = "https://www.gstatic.com/admob/reward/verifier-keys.json";
const KEYS_TTL_MS = 24 * 3600_000;
export type AdKind = "reroll" | "refill" | "double" | "gems";
const KINDS = Object.keys(ECON_V1.ads) as AdKind[];
const NONCE_RE = /^ad_[a-z2-7]{24}$/;

// ---------- the verifier keys and the signature ----------

interface VerifierKey {
  keyId: number;
  pem?: string;
  base64?: string;
}

let keyCache: { at: number; keys: Map<string, Promise<CryptoKey>> } | null = null;

interface TestKeys {
  __lzAdKeys?: VerifierKey[];
}

async function verifierKeys(env: { TEST_MODE?: string }, renew = false): Promise<Map<string, Promise<CryptoKey>>> {
  if (!renew && keyCache && Date.now() - keyCache.at < KEYS_TTL_MS) return keyCache.keys;
  let list: VerifierKey[] = [];
  const t = env.TEST_MODE === "1" ? (globalThis as unknown as TestKeys).__lzAdKeys : undefined;
  if (t) list = t;
  else {
    const res = await gcall(KEYS_URL);
    if (!res.ok) throw new Error(`verifier keys: ${res.status}`);
    list = ((await res.json()) as { keys?: VerifierKey[] }).keys ?? [];
  }
  const keys = new Map<string, Promise<CryptoKey>>();
  for (const k of list) {
    const b64 = k.base64 ?? (k.pem ?? "").replace(/-----[A-Z ]+-----/g, "").replace(/\s+/g, "");
    if (!b64) continue;
    const der = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
    const p = crypto.subtle.importKey("spki", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["verify"]);
    p.catch(() => undefined);
    keys.set(String(k.keyId), p);
  }
  keyCache = { at: Date.now(), keys };
  return keys;
}

/** Tests: forget the cached keys. */
export function resetAdKeys(): void {
  keyCache = null;
}

function unb64url(s: string): Uint8Array {
  const b = s.replace(/-/g, "+").replace(/_/g, "/");
  return Uint8Array.from(atob(b + "=".repeat((4 - (b.length % 4)) % 4)), (c) => c.charCodeAt(0));
}

/** An ASN.1 DER ECDSA signature (SEQUENCE {r, s}) -> the 64-byte r || s WebCrypto verifies. */
export function derToRaw(der: Uint8Array): Uint8Array | null {
  let i = 0;
  if (der[i++] !== 0x30) return null;
  let len = der[i++];
  if (len & 0x80) i += len & 0x7f;
  const out = new Uint8Array(64);
  for (let k = 0; k < 2; k++) {
    if (der[i++] !== 0x02) return null;
    len = der[i++];
    let v = der.slice(i, i + len);
    i += len;
    while (v.length > 32 && v[0] === 0) v = v.slice(1);
    if (v.length > 32) return null;
    out.set(v, k * 32 + (32 - v.length));
  }
  return out;
}

/**
 * Checks an SSV callback URL: the signed message is the query string up to (not including) "&signature=", the
 * signature (web-safe base64 DER) and key_id are the last parameters.
 */
export async function verifySsv(env: { TEST_MODE?: string }, url: URL): Promise<boolean> {
  const q = url.search.startsWith("?") ? url.search.slice(1) : url.search;
  const at = q.indexOf("&signature=");
  if (at < 0) return false;
  const message = q.slice(0, at);
  const sig = url.searchParams.get("signature");
  const keyId = url.searchParams.get("key_id");
  if (!sig || !keyId) return false;
  let raw: Uint8Array | null;
  try {
    raw = derToRaw(unb64url(sig));
  } catch {
    return false;
  }
  if (!raw) return false;
  for (const renew of [false, true]) {
    const keys = await verifierKeys(env, renew);
    const kp = keys.get(keyId);
    if (!kp) continue; // a new key: fetch the list again once
    const key = await kp;
    return crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, key, raw, new TextEncoder().encode(message));
  }
  return false;
}

// ---------- caps ----------

interface Counts {
  total: number;
  by: Record<string, number>;
}

async function todayCounts(db: D1Database, accountId: string, now: number): Promise<Counts> {
  const rows = await db
    .prepare("SELECT kind, COUNT(*) AS n FROM ad_rewards WHERE account_id = ? AND status = 'granted' AND granted_at >= ? GROUP BY kind")
    .bind(accountId, econDayStartMs(now))
    .all<{ kind: string; n: number }>();
  const by: Record<string, number> = {};
  let total = 0;
  for (const r of rows.results ?? []) {
    by[r.kind] = r.n;
    total += r.n;
  }
  return { total, by };
}

function left(c: Counts): { left: Record<string, number>; total_left: number } {
  const total_left = Math.max(0, ECON_V1.ads_per_day - c.total);
  const l: Record<string, number> = {};
  for (const k of KINDS) l[k] = Math.min(total_left, Math.max(0, ECON_V1.ads[k].per_day - (c.by[k] ?? 0)));
  return { left: l, total_left };
}

/** What `double` would pay for match `ref`: the coin-table payout this account won there (0: not eligible). */
async function doubleAmount(db: D1Database, accountId: string, ref: string, now: number): Promise<number> {
  const g = await db
    .prepare("SELECT coins, at, outcome FROM match_grants WHERE match_id = ? AND account_id = ?")
    .bind(ref, accountId)
    .first<{ coins: number; at: number; outcome: string }>();
  if (!g || g.coins <= 0 || now - g.at > ECON_V1.double_within_ms) return 0;
  const paid = await db.prepare("SELECT 1 AS x FROM entries WHERE match_id = ? AND account_id = ? AND status = 'settled' AND payout > 0").bind(ref, accountId).first();
  if (!paid) return 0; // coin tables only
  const used = await db.prepare("SELECT 1 AS x FROM ad_rewards WHERE account_id = ? AND kind = 'double' AND ref = ? AND status IN ('pending', 'granted') AND created_at > ?").bind(accountId, ref, now - ECON_V1.ad_nonce_ms).first();
  return used ? -1 : g.coins;
}

function newNonce(): string {
  const r = new Uint8Array(24);
  crypto.getRandomValues(r);
  let s = "ad_";
  for (const v of r) s += "abcdefghijklmnopqrstuvwxyz234567"[v & 31];
  return s;
}

// ---------- HTTP ----------

/** GET /v1/ads/today -> {left: {kind: n}, total_left, next_at}. */
export async function adsToday(env: AccEnv, a: Authed, now: number): Promise<Response> {
  return authedJson(a, { ...left(await todayCounts(env.DB, a.row.id, now)), next_at: nextDayAt(econDay(now)) });
}

/** POST /v1/ads/start {kind, ref?} -> {ok, nonce, user_id, custom_data, left} | 409 cap | 409 not_eligible. */
export async function adsStart(req: Request, env: AccEnv, a: Authed, now: number): Promise<Response> {
  const o = await readBody(req);
  const kind = o.kind as AdKind;
  if (!KINDS.includes(kind)) throw new BadRequest(`kind: ${KINDS.join(" | ")}`);
  const ref = typeof o.ref === "string" ? o.ref.slice(0, 64) : null;
  const db = env.DB;
  const c = left(await todayCounts(db, a.row.id, now));
  if (c.left[kind] <= 0) return authedJson(a, { error: "cap", next_at: nextDayAt(econDay(now)), ...c }, 409);
  const p = a.row;
  if (kind === "refill" && p.coins >= ECON_V1.broke_below) return authedJson(a, { error: "not_eligible", msg: "the refill is for when you can't afford a table" }, 409);
  if (kind === "reroll" && p.rerolls >= ECON_V1.reroll_free_max) return authedJson(a, { error: "not_eligible", msg: "you hold the most free re-rolls already" }, 409);
  if (kind === "double") {
    if (!ref) throw new BadRequest("ref: the match id");
    const amt = await doubleAmount(db, a.row.id, ref, now);
    if (amt <= 0) return authedJson(a, { error: "not_eligible", msg: amt < 0 ? "already doubled" : "only a coin-table win of the last 15 minutes can be doubled" }, 409);
  }
  const nonce = newNonce();
  await db.prepare("INSERT INTO ad_rewards (nonce, account_id, kind, ref, created_at, status) VALUES (?, ?, ?, ?, ?, 'pending')").bind(nonce, a.row.id, kind, ref, now).run();
  return authedJson(a, { ok: true, nonce, user_id: a.row.id, custom_data: nonce, ...c });
}

/** GET /v1/ads/status?nonce= -> {status, kind, amount?, profile?}. */
export async function adsStatus(env: AccEnv, a: Authed, url: URL, now: number): Promise<Response> {
  const nonce = url.searchParams.get("nonce") ?? "";
  if (!NONCE_RE.test(nonce)) throw new BadRequest("nonce");
  const r = await env.DB.prepare("SELECT kind, status, amount, created_at FROM ad_rewards WHERE nonce = ? AND account_id = ?").bind(nonce, a.row.id).first<{ kind: string; status: string; amount: number; created_at: number }>();
  if (!r) return authedJson(a, { error: "not_found" }, 404);
  const status = r.status === "pending" && now - r.created_at > ECON_V1.ad_nonce_ms ? "expired" : r.status;
  const out: Record<string, unknown> = { status, kind: r.kind };
  if (status === "granted") {
    out.amount = r.amount;
    out.profile = await mutate(env, a.row.id, now, (_row, p) => ({ result: p }));
  }
  return authedJson(a, out);
}

/** The reward of one kind applied to a profile: [new profile, ledger coins, ledger gems, amount]. */
function applyReward(p: Profile, kind: AdKind, double: number): [Profile, number, number, number] {
  const q = structuredClone(p);
  switch (kind) {
    case "reroll": {
      const before = q.rerolls;
      q.rerolls = Math.min(ECON_V1.reroll_free_max, q.rerolls + ECON_V1.ads.reroll.amount);
      return [q, 0, 0, q.rerolls - before];
    }
    case "refill":
      addCoins(q, ECON_V1.ads.refill.amount);
      return [q, ECON_V1.ads.refill.amount, 0, ECON_V1.ads.refill.amount];
    case "double":
      addCoins(q, double);
      return [q, double, 0, double];
    case "gems":
      q.gems += ECON_V1.ads.gems.amount;
      return [q, 0, ECON_V1.ads.gems.amount, ECON_V1.ads.gems.amount];
  }
}

/** What a verified callback did: granted, or why nothing was granted. All are final: the network must not retry. */
export type GrantResult = "granted" | "duplicate" | "ignored" | "expired" | "cap" | "not_eligible" | "unknown";

/**
 * The reward for one verified callback, shared by AdMob (/v1/ads/ssv) and LevelPlay (/v1/ads/levelplay): `nonce` must
 * be an ad of `user` (else "ignored"), `tx` (the network's transaction / event id, namespaced per network) counts at
 * most once, the nonce must not be expired and the day caps are checked again. Grants once.
 */
export async function grantAd(env: AccEnv, nonce: string, user: string, tx: string, now: number): Promise<GrantResult> {
  if (!NONCE_RE.test(nonce) || !tx) return "ignored";
  const db = env.DB;
  const ad = await db.prepare("SELECT * FROM ad_rewards WHERE nonce = ?").bind(nonce).first<{ account_id: string; kind: AdKind; ref: string | null; status: string; created_at: number }>();
  if (!ad || ad.account_id !== user) return "ignored";
  if (ad.status !== "pending") return "duplicate";
  // one event never pays twice, not even for another nonce (tx_id is UNIQUE too: this keeps it a clean answer)
  if (await db.prepare("SELECT 1 AS x FROM ad_rewards WHERE tx_id = ?").bind(tx).first()) return "duplicate";
  const r = await mutate(env, ad.account_id, now, async (_row, p): Promise<Step<GrantResult>> => {
    const cur = await db.prepare("SELECT status FROM ad_rewards WHERE nonce = ?").bind(nonce).first<{ status: string }>();
    if (cur?.status !== "pending") return { result: "duplicate" };
    const reject = (why: GrantResult): Step<GrantResult> => ({
      result: why,
      write: { extra: () => [db.prepare("UPDATE ad_rewards SET status = 'rejected', tx_id = ?, granted_at = ? WHERE nonce = ? AND status = 'pending'").bind(tx, now, nonce)] },
    });
    if (now - ad.created_at > ECON_V1.ad_nonce_ms) return reject("expired");
    const c = left(await todayCounts(db, ad.account_id, now));
    if (c.left[ad.kind] <= 0) return reject("cap");
    let dbl = 0;
    if (ad.kind === "double") {
      const g = await db.prepare("SELECT coins FROM match_grants WHERE match_id = ? AND account_id = ?").bind(ad.ref ?? "", ad.account_id).first<{ coins: number }>();
      dbl = Math.max(0, g?.coins ?? 0);
      if (!dbl) return reject("not_eligible");
    }
    const [q, coins, gems, amount] = applyReward(p, ad.kind, dbl);
    return {
      result: "granted",
      write: {
        profile: q,
        ledger: { coins, xp: 0, gems, reason: "ad", ref: `${ad.kind}:${nonce}` },
        extra: (g) => [
          db.prepare(`UPDATE ad_rewards SET status = 'granted', tx_id = ?, granted_at = ?, amount = ? WHERE nonce = ? AND status = 'pending' AND ${g.sql}`).bind(tx, now, amount, nonce, ...g.params),
        ],
      },
    };
  });
  return r ?? "unknown";
}

/**
 * GET /v1/ads/ssv?ad_network=&ad_unit=&custom_data=&key_id=&reward_amount=&reward_item=&timestamp=&transaction_id=
 * &user_id=&signature=&key_id= (AdMob). 200 for a granted, duplicate or refused-by-the-rules callback (AdMob only
 * retries on errors); 400 for a bad signature or unknown nonce.
 */
export async function adsSsv(req: Request, env: AccEnv, now: number): Promise<Response> {
  if (req.method !== "GET") return json({ error: "method" }, 405);
  const url = new URL(req.url);
  if (!(await verifySsv(env, url).catch((e) => (console.error("SSV verify failed:", e), false)))) return json({ error: "signature" }, 400);
  const nonce = url.searchParams.get("custom_data") ?? "";
  const user = url.searchParams.get("user_id") ?? "";
  const tx = (url.searchParams.get("transaction_id") ?? "").slice(0, 128);
  // a signed callback that matches no pending ad (AdMob's "Verify URL" test sends none) grants nothing: 200 so
  // AdMob doesn't retry it
  const r = await grantAd(env, nonce, user, tx, now);
  return json(r === "duplicate" ? { ok: true, duplicate: true } : { ok: true, result: r });
}

// ---------- LevelPlay (ironSource) server-to-server callback ----------

async function md5Hex(s: string): Promise<string> {
  const d = new Uint8Array(await crypto.subtle.digest("MD5", new TextEncoder().encode(s)));
  return Array.from(d, (b) => b.toString(16).padStart(2, "0")).join("");
}

/** Same text, compared without stopping at the first difference. */
function sameText(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/**
 * LevelPlay's callback signature: md5(timestamp + eventId + userId + rewards + private key) in hex, with the
 * URL-decoded userId (docs.unity.com/grow/levelplay/platform/settings/event-handlers). The custom_ parameters are
 * not signed; the nonce they carry is secret and single-use, and an eventId pays at most once.
 */
export async function levelPlaySignature(key: string, p: URLSearchParams): Promise<string> {
  return md5Hex(`${p.get("timestamp") ?? ""}${p.get("eventId") ?? ""}${p.get("userId") ?? ""}${p.get("rewards") ?? ""}${key}`);
}

/**
 * GET /v1/ads/levelplay?userId=[USER_ID]&rewards=[REWARDS]&eventId=[EVENT_ID]&itemName=[ITEM_NAME]
 * &placement=[PLACEMENT_NAME] (+ timestamp and signature, which LevelPlay adds; + custom_nonce and custom_uid, the
 * /v1/ads/start nonce and the account id the game sets as LevelPlay_Rewarded_Server_Params before the ad shows).
 * LevelPlay retries until a 200 whose body contains "<eventId>:OK", so every final answer (granted, duplicate,
 * ignored, refused by the rules) is that, plus the result. A bad signature is a 400; an unset secret
 * (LEVELPLAY_S2S_KEY) a 503, so a callback that comes before the secret is set is retried and still pays.
 */
export async function adsLevelPlay(req: Request, env: AccEnv, now: number): Promise<Response> {
  if (req.method !== "GET" && req.method !== "POST") return json({ error: "method" }, 405);
  const key = env.LEVELPLAY_S2S_KEY ?? "";
  if (!key) return json({ error: "unconfigured" }, 503);
  const p = new URL(req.url).searchParams;
  if (req.method === "POST" && (req.headers.get("Content-Type") ?? "").includes("application/x-www-form-urlencoded")) {
    for (const [k, v] of new URLSearchParams(await req.text())) if (!p.has(k)) p.set(k, v);
  }
  const eventId = (p.get("eventId") ?? "").slice(0, 128);
  const sig = (p.get("signature") ?? "").toLowerCase();
  if (!eventId || !sig || !sameText(sig, await levelPlaySignature(key, p))) return json({ error: "signature" }, 400);
  // the dashboard's "Callback test" carries no nonce: acknowledged, nothing granted
  const r = await grantAd(env, p.get("custom_nonce") ?? "", p.get("custom_uid") ?? "", `lp:${eventId}`, now);
  return new Response(`${eventId}:OK ${r}`, { headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store" } });
}
