// Google Play Games Services v2 server-side access (ONLINE_V2.md §1): exchanges the server auth code the game gets
// from Play Games (`requestServerSideAccess(web_client_id)`) for an access token, then reads the Play Games player id.
// Every HTTP call goes through `googleFetch`, which tests replace with setGoogleFetcher() (a fake Google).

export const TOKEN_URL = "https://oauth2.googleapis.com/token";
export const PLAYER_URL = "https://games.googleapis.com/games/v1/players/me";

export type Fetcher = (input: string, init?: RequestInit) => Promise<Response>;

let googleFetch: Fetcher = (input, init) => fetch(input, init);

/** Tests: route Google's endpoints to a fake. `null` restores the real fetch. */
export function setGoogleFetcher(f: Fetcher | null): void {
  googleFetch = f ?? ((input, init) => fetch(input, init));
}

export interface GoogleEnv {
  GOOGLE_WEB_CLIENT_ID?: string;
  GOOGLE_WEB_CLIENT_SECRET?: string;
}

export function googleConfigured(env: GoogleEnv): boolean {
  return !!env.GOOGLE_WEB_CLIENT_ID && !!env.GOOGLE_WEB_CLIENT_SECRET;
}

export interface GooglePlayer {
  /** The Play Games player id (stable per game per Google account). */
  id: string;
  name: string;
}

export type GoogleResult =
  | { ok: true; player: GooglePlayer }
  /** rejected: Google refused the code (expired, used, wrong client); failed: Google unreachable / unexpected. */
  | { ok: false; error: "google_rejected" | "google_failed"; detail: string };

const TIMEOUT_MS = 8000;

async function call(url: string, init: RequestInit): Promise<Response> {
  const ac = new AbortController();
  const t = setTimeout(() => ac.abort(), TIMEOUT_MS);
  try {
    return await googleFetch(url, { ...init, signal: ac.signal });
  } finally {
    clearTimeout(t);
  }
}

/** Server auth code -> the Play Games player. Never throws. */
export async function playerFromAuthCode(env: GoogleEnv, code: string): Promise<GoogleResult> {
  let tok: Response;
  try {
    tok = await call(TOKEN_URL, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        code,
        client_id: env.GOOGLE_WEB_CLIENT_ID ?? "",
        client_secret: env.GOOGLE_WEB_CLIENT_SECRET ?? "",
        grant_type: "authorization_code",
        // Play Games server auth codes are exchanged without a redirect (an empty redirect_uri)
        redirect_uri: "",
      }).toString(),
    });
  } catch (e) {
    return { ok: false, error: "google_failed", detail: `token: ${String(e)}` };
  }
  const tj = (await tok.json().catch(() => null)) as { access_token?: unknown; error?: unknown } | null;
  if (!tok.ok) {
    // 400 invalid_grant / 401 invalid_client: the code (or our client) is not accepted
    const err = typeof tj?.error === "string" ? tj.error : String(tok.status);
    return { ok: false, error: tok.status >= 400 && tok.status < 500 ? "google_rejected" : "google_failed", detail: `token: ${err}` };
  }
  if (typeof tj?.access_token !== "string" || !tj.access_token) return { ok: false, error: "google_failed", detail: "token: no access_token" };

  let pr: Response;
  try {
    pr = await call(PLAYER_URL, { headers: { Authorization: `Bearer ${tj.access_token}` } });
  } catch (e) {
    return { ok: false, error: "google_failed", detail: `player: ${String(e)}` };
  }
  const pj = (await pr.json().catch(() => null)) as { playerId?: unknown; displayName?: unknown } | null;
  if (!pr.ok) return { ok: false, error: pr.status === 401 || pr.status === 403 ? "google_rejected" : "google_failed", detail: `player: ${pr.status}` };
  if (typeof pj?.playerId !== "string" || !/^[A-Za-z0-9_.:-]{1,128}$/.test(pj.playerId)) {
    return { ok: false, error: "google_failed", detail: "player: no playerId" };
  }
  const name = typeof pj.displayName === "string" ? pj.displayName.slice(0, 64) : "";
  return { ok: true, player: { id: pj.playerId, name } };
}
