// Gem purchases on Google Play (ECONOMY_V1.md §2 "Gem purchases"): the game buys a consumable gem pack with Play
// Billing and sends {product_id, token}; the server asks the Play Developer API whether that purchase is paid, grants
// the pack's gems once (purchases.token is the primary key) and consumes it. A daily cron reads the voided purchases
// (refunds, chargebacks) and takes their gems back.
//
// Secrets: PLAY_SERVICE_ACCOUNT, a service account with access to the app in Play Console (falls back to
// FCM_SERVICE_ACCOUNT, the same Google Cloud project's account, when it was given that access). PLAY_PACKAGE: the
// application id (default com.flipfold.ludozing).
import { type AccEnv, type Authed, type Step, BadRequest, authedJson, guardedInsert, isUnique, json, mutate, readBody } from "./accounts";
import { ECON_V1 } from "./econ";
import { gcall, googleToken, parseServiceAccount, type ServiceAccount } from "./gauth";

export const PUBLISHER_SCOPE = "https://www.googleapis.com/auth/androidpublisher";
const API = "https://androidpublisher.googleapis.com/androidpublisher/v3/applications";
export const DEFAULT_PACKAGE = "com.flipfold.ludozing";
const TOKEN_RE = /^[A-Za-z0-9._:-]{10,1024}$/;

export interface IapEnv extends AccEnv {
  PLAY_SERVICE_ACCOUNT?: string;
  FCM_SERVICE_ACCOUNT?: string;
  PLAY_PACKAGE?: string;
}

/** undefined: the secrets; a string or null: that instead (tests). */
let override: string | null | undefined;

/** Tests: use this service-account JSON instead of the secrets (null: purchases can't be checked). */
export function setIapServiceAccount(json: string | null | undefined): void {
  override = json;
}

function account(env: IapEnv): ServiceAccount | null {
  if (override !== undefined) return parseServiceAccount(override);
  return parseServiceAccount(env.PLAY_SERVICE_ACCOUNT) ?? parseServiceAccount(env.FCM_SERVICE_ACCOUNT);
}

export function iapConfigured(env: IapEnv): boolean {
  return account(env) !== null;
}

function pkg(env: IapEnv): string {
  return env.PLAY_PACKAGE || DEFAULT_PACKAGE;
}

/** The Play purchase (purchases.products.get): null when Google doesn't know it, "down" when the API failed. */
interface PlayPurchase {
  purchaseState?: number; // 0 purchased, 1 canceled, 2 pending
  consumptionState?: number; // 0 yet to be consumed, 1 consumed
  orderId?: string;
  obfuscatedExternalAccountId?: string;
  purchaseTimeMillis?: string;
}

async function playGet(env: IapEnv, productId: string, token: string): Promise<PlayPurchase | null | "down"> {
  const sa = account(env);
  if (!sa) return "down";
  const url = `${API}/${encodeURIComponent(pkg(env))}/purchases/products/${encodeURIComponent(productId)}/tokens/${encodeURIComponent(token)}`;
  for (let attempt = 0; attempt < 2; attempt++) {
    const at = await googleToken(sa, PUBLISHER_SCOPE, attempt > 0);
    if (!at) return "down";
    let res: Response;
    try {
      res = await gcall(url, { headers: { Authorization: `Bearer ${at}` } });
    } catch (e) {
      console.error("Play purchases.products.get failed:", e);
      return "down";
    }
    if (res.status === 401 && attempt === 0) continue;
    if (res.status === 404 || res.status === 400 || res.status === 410) return null;
    if (!res.ok) {
      console.error(`Play purchases.products.get: ${res.status} ${(await res.text().catch(() => "")).slice(0, 200)}`);
      return "down";
    }
    return (await res.json().catch(() => null)) as PlayPurchase | null;
  }
  return "down";
}

/** Consumes the purchase so it can be bought again (best effort: the game consumes too if this failed). */
async function playConsume(env: IapEnv, productId: string, token: string): Promise<boolean> {
  const sa = account(env);
  if (!sa) return false;
  const at = await googleToken(sa, PUBLISHER_SCOPE);
  if (!at) return false;
  try {
    const res = await gcall(`${API}/${encodeURIComponent(pkg(env))}/purchases/products/${encodeURIComponent(productId)}/tokens/${encodeURIComponent(token)}:consume`, {
      method: "POST",
      headers: { Authorization: `Bearer ${at}` },
    });
    return res.ok;
  } catch (e) {
    console.error("Play consume failed:", e);
    return false;
  }
}

interface PurchaseRow {
  token: string;
  account_id: string;
  product_id: string;
  gems: number;
  status: string;
}

/** GET /v1/iap/products -> {products: [{id, gems}]} (prices come from Play on the device). */
export function iapProducts(a: Authed): Response {
  return authedJson(a, { products: Object.entries(ECON_V1.products).map(([id, gems]) => ({ id, gems })) });
}

/**
 * POST /v1/iap/verify {product_id, token} -> {ok, profile, gems, consumed} (a token granted before to this account:
 * the same with duplicate: true) | 409 pending | 409 invalid | 503 unavailable.
 */
export async function iapVerify(req: Request, env: IapEnv, a: Authed, now: number): Promise<Response> {
  const o = await readBody(req);
  const productId = o.product_id;
  const token = o.token;
  if (typeof productId !== "string" || !(productId in ECON_V1.products)) throw new BadRequest("product_id: a gem pack");
  if (typeof token !== "string" || !TOKEN_RE.test(token)) throw new BadRequest("token: the purchase token");
  const gems = ECON_V1.products[productId];
  const db = env.DB;

  const prior = async (): Promise<Response | null> => {
    const p = await db.prepare("SELECT token, account_id, product_id, gems, status FROM purchases WHERE token = ?").bind(token).first<PurchaseRow>();
    if (!p) return null;
    if (p.account_id !== a.row.id || p.product_id !== productId) return authedJson(a, { error: "invalid", msg: "this purchase belongs to another account" }, 409);
    const cur = await mutate(env, a.row.id, now, (_r, prof) => ({ result: prof }));
    return authedJson(a, { ok: true, duplicate: true, gems: p.gems, profile: cur, voided: p.status === "voided" });
  };
  const again = await prior();
  if (again) return again;
  if (!iapConfigured(env)) return json({ error: "unavailable", msg: "purchases can't be checked right now" }, 503);

  const pp = await playGet(env, productId, token);
  if (pp === "down") return json({ error: "unavailable", msg: "Google Play didn't answer: try again" }, 503);
  if (!pp) return authedJson(a, { error: "invalid", msg: "Google Play doesn't know this purchase" }, 409);
  if (pp.purchaseState === 2) return authedJson(a, { error: "pending", msg: "the payment isn't complete yet" }, 409);
  if (pp.purchaseState !== 0) return authedJson(a, { error: "invalid", msg: "this purchase was canceled" }, 409);
  if (pp.obfuscatedExternalAccountId && pp.obfuscatedExternalAccountId !== a.row.id) {
    return authedJson(a, { error: "invalid", msg: "this purchase belongs to another account" }, 409);
  }
  if (pp.consumptionState === 1) {
    // consumed: granted by a request running alongside this one (it consumes right after granting), else never
    // granted here at all (someone else's token or a replay)
    return (await prior()) ?? authedJson(a, { error: "invalid", msg: "this purchase was already used" }, 409);
  }

  let res: Response | null;
  try {
    res = await mutate(env, a.row.id, now, (_row, p): Step<Response> => {
      const q = { ...p, gems: p.gems + gems };
      return {
        result: authedJson(a, { ok: true, profile: q, gems }),
        write: {
          profile: q,
          ledger: { coins: 0, xp: 0, gems, reason: "iap", ref: `${productId}:${(pp.orderId ?? "").slice(0, 40)}` },
          extra: (g) => [
            guardedInsert(db, g, "purchases", ["token", "account_id", "product_id", "order_id", "at", "gems", "status"], [token, a.row.id, productId, pp.orderId ?? null, now, gems, "granted"]),
          ],
        },
      };
    });
  } catch (e) {
    if (isUnique(e)) return (await prior()) ?? authedJson(a, { error: "invalid" }, 409); // the same token at once
    throw e;
  }
  if (!res) return json({ error: "unauthorized" }, 401);
  const consumed = await playConsume(env, productId, token);
  const body = (await res.json()) as Record<string, unknown>;
  return authedJson(a, { ...body, consumed });
}

/**
 * Cron: purchases voided in the last 3 days (Play voidedpurchases.list) lose their gems (`iap_void`; the balance
 * never goes below 0: a shortfall is noted in the ledger ref). Returns how many were voided now.
 */
export async function voidRefunded(env: IapEnv, now = Date.now()): Promise<number> {
  const sa = account(env);
  if (!sa) return 0;
  const at = await googleToken(sa, PUBLISHER_SCOPE);
  if (!at) return 0;
  const tokens: string[] = [];
  let page: string | undefined;
  for (let k = 0; k < 10; k++) {
    const u = new URL(`${API}/${encodeURIComponent(pkg(env))}/purchases/voidedpurchases`);
    u.searchParams.set("startTime", String(now - 3 * 86_400_000));
    u.searchParams.set("maxResults", "1000");
    if (page) u.searchParams.set("token", page);
    let res: Response;
    try {
      res = await gcall(u.toString(), { headers: { Authorization: `Bearer ${at}` } });
    } catch (e) {
      console.error("voidedpurchases.list failed:", e);
      break;
    }
    if (!res.ok) {
      console.error(`voidedpurchases.list: ${res.status}`);
      break;
    }
    const j = (await res.json().catch(() => ({}))) as { voidedPurchases?: Array<{ purchaseToken?: string }>; tokenPagination?: { nextPageToken?: string } };
    for (const v of j.voidedPurchases ?? []) if (typeof v.purchaseToken === "string") tokens.push(v.purchaseToken);
    page = j.tokenPagination?.nextPageToken;
    if (!page) break;
  }
  let n = 0;
  for (const t of tokens) {
    const p = await env.DB.prepare("SELECT token, account_id, product_id, gems, status FROM purchases WHERE token = ? AND status = 'granted'").bind(t).first<PurchaseRow>();
    if (!p) continue;
    await mutate(env, p.account_id, now, async (_row, prof): Promise<Step<void>> => {
      const cur = await env.DB.prepare("SELECT status FROM purchases WHERE token = ?").bind(t).first<{ status: string }>();
      if (cur?.status !== "granted") return { result: undefined };
      const take = Math.min(prof.gems, p.gems);
      const short = p.gems - take;
      return {
        result: undefined,
        write: {
          profile: { ...prof, gems: prof.gems - take },
          ledger: { coins: 0, xp: 0, gems: -take, reason: "iap_void", ref: `${p.product_id}${short ? `:short ${short}` : ""}` },
          extra: (g) => [env.DB.prepare(`UPDATE purchases SET status = 'voided', voided_at = ? WHERE token = ? AND status = 'granted' AND ${g.sql}`).bind(now, t, ...g.params)],
        },
      };
    });
    n++;
  }
  return n;
}
