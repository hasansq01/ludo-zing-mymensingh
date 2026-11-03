// Google service-account access tokens for any API scope (the Play Developer API for gem purchases; push.ts keeps
// its own FCM copy): a signed RS256 JWT exchanged at Google's token endpoint, cached per account + scope until
// 5 minutes before it expires. Tests route the HTTP calls through setGoogleFetcher.

export const TOKEN_URL = "https://oauth2.googleapis.com/token";

export type Fetcher = (input: string, init?: RequestInit) => Promise<Response>;

let gfetch: Fetcher = (input, init) => fetch(input, init);

/** Tests: route Google's endpoints (token, Play API) to a fake. `null` restores the real fetch. */
export function setGoogleFetcher(f: Fetcher | null): void {
  gfetch = f ?? ((input, init) => fetch(input, init));
  tokens.clear();
}

export interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
  private_key_id: string;
}

/** A service-account JSON (as downloaded from Google Cloud), or null when it isn't one. */
export function parseServiceAccount(raw: string | undefined | null): ServiceAccount | null {
  if (!raw) return null;
  try {
    const j = JSON.parse(raw) as Record<string, unknown>;
    if (typeof j.client_email === "string" && j.client_email.includes("@") && typeof j.private_key === "string" && j.private_key.includes("PRIVATE KEY")) {
      return {
        project_id: typeof j.project_id === "string" ? j.project_id : "",
        client_email: j.client_email,
        private_key: j.private_key,
        private_key_id: typeof j.private_key_id === "string" ? j.private_key_id : "",
      };
    }
  } catch {
    /* not JSON */
  }
  return null;
}

const enc = new TextEncoder();
const MARGIN_MS = 5 * 60_000;
export const TIMEOUT_MS = 8000;
const tokens = new Map<string, Promise<{ token: string; exp: number } | null>>();
const keys = new Map<string, Promise<CryptoKey>>();

export function b64url(data: ArrayBuffer | Uint8Array | string): string {
  const a = typeof data === "string" ? enc.encode(data) : data instanceof Uint8Array ? data : new Uint8Array(data);
  let s = "";
  for (const b of a) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function signingKey(pem: string): Promise<CryptoKey> {
  let p = keys.get(pem);
  if (!p) {
    const der = Uint8Array.from(atob(pem.replace(/-----[A-Z ]+-----/g, "").replace(/\s+/g, "")), (c) => c.charCodeAt(0));
    p = crypto.subtle.importKey("pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
    p.catch(() => keys.delete(pem));
    keys.set(pem, p);
  }
  return p;
}

/** fetch with the 8 s timeout, through the (test-replaceable) fetcher. */
export async function gcall(url: string, init: RequestInit = {}): Promise<Response> {
  const ac = new AbortController();
  const t = setTimeout(() => ac.abort(), TIMEOUT_MS);
  try {
    return await gfetch(url, { ...init, signal: ac.signal });
  } finally {
    clearTimeout(t);
  }
}

async function fetchToken(sa: ServiceAccount, scope: string): Promise<{ token: string; exp: number } | null> {
  try {
    const now = Date.now();
    const iat = Math.floor(now / 1000);
    const head = b64url(JSON.stringify({ alg: "RS256", typ: "JWT", kid: sa.private_key_id || undefined }));
    const claims = b64url(JSON.stringify({ iss: sa.client_email, scope, aud: TOKEN_URL, iat, exp: iat + 3600 }));
    const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", await signingKey(sa.private_key), enc.encode(`${head}.${claims}`));
    const res = await gcall(TOKEN_URL, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: `${head}.${claims}.${b64url(sig)}` }).toString(),
    });
    const j = (await res.json().catch(() => null)) as { access_token?: unknown; expires_in?: unknown; error?: unknown } | null;
    if (!res.ok || typeof j?.access_token !== "string" || !j.access_token) {
      console.error(`Google access token refused (${scope}): ${res.status} ${typeof j?.error === "string" ? j.error : ""}`);
      return null;
    }
    const ttl = typeof j.expires_in === "number" && j.expires_in > 0 ? j.expires_in : 3600;
    return { token: j.access_token, exp: now + ttl * 1000 };
  } catch (e) {
    console.error(`Google access token failed (${scope}):`, e);
    return null;
  }
}

/** A cached access token for this service account and scope (null: Google refused or is unreachable). */
export async function googleToken(sa: ServiceAccount, scope: string, renew = false): Promise<string | null> {
  const key = `${sa.client_email}\u0000${sa.private_key_id}\u0000${scope}`;
  const c = tokens.get(key);
  if (!renew && c) {
    const v = await c;
    if (v && v.exp - MARGIN_MS > Date.now()) return v.token;
  }
  const p = fetchToken(sa, scope);
  tokens.set(key, p);
  const v = await p;
  if (!v && tokens.get(key) === p) tokens.delete(key);
  return v?.token ?? null;
}
