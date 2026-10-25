// Google Play Games linking (ONLINE_V2.md §1) against a fake Google: link, relink, conflict, resolve here / there,
// another Google player on a linked account (other_google: stay / switch), device switching, errors, and the 503
// when the Google secrets are not set.
import { createExecutionContext, env, waitOnExecutionContext } from "cloudflare:test";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { verifySession } from "../src/accounts";
import { PLAYER_URL, TOKEN_URL, setGoogleFetcher } from "../src/google";
import worker from "../src/index";
import { ENV, T0, type Json, guest, newPid, ok, row, rows, setAccount, v1 } from "./acc_helpers";

const GENV = { ...(env as object), GOOGLE_WEB_CLIENT_ID: "web-client.apps.googleusercontent.com", GOOGLE_WEB_CLIENT_SECRET: "shh" };

/** code -> Play Games player id; "bad" -> invalid_grant, "down" -> 500. Each code works once, as Google's. */
const players = new Map<string, { id: string; name: string }>();
const used = new Set<string>();
const seenBodies: string[] = [];

beforeAll(() => {
  setGoogleFetcher(async (url, init) => {
    if (url === TOKEN_URL) {
      const body = String(init?.body ?? "");
      seenBodies.push(body);
      const code = new URLSearchParams(body).get("code") ?? "";
      if (code === "down") return new Response("oops", { status: 500 });
      if (code === "bad" || used.has(code) || !players.has(code)) return Response.json({ error: "invalid_grant" }, { status: 400 });
      used.add(code);
      return Response.json({ access_token: `at-${code}`, expires_in: 3599, token_type: "Bearer" });
    }
    if (url === PLAYER_URL) {
      const auth = new Headers(init?.headers).get("Authorization") ?? "";
      const code = auth.replace(/^Bearer at-/, "");
      const p = players.get(code);
      if (!p) return Response.json({ error: { code: 401 } }, { status: 401 });
      return Response.json({ kind: "games#player", playerId: p.id, displayName: p.name });
    }
    return new Response("unexpected", { status: 599 });
  });
});
afterAll(() => setGoogleFetcher(null));

let codeSeq = 0;
function codeFor(id: string, name = "Google Name"): string {
  const code = `4/0A${(codeSeq++).toString(36)}${id}`;
  players.set(code, { id, name });
  return code;
}

async function g(path: string, session: string | null, body: Json): Promise<{ status: number; body: Json }> {
  const ctx = createExecutionContext();
  const headers: Record<string, string> = { "Content-Type": "application/json", "X-Test-Now": String(T0) };
  if (session) headers.Authorization = `Bearer ${session}`;
  const r = await worker.fetch(new Request(`https://x/v1/${path}`, { method: "POST", headers, body: JSON.stringify(body) }), GENV as never, ctx);
  await waitOnExecutionContext(ctx);
  return { status: r.status, body: (await r.json()) as Json };
}

describe("Google linking", () => {
  it("is off (503 google_not_configured) without the Google secrets", async () => {
    const a = await guest();
    const r = await v1("auth/google", { session: a.session, body: { server_auth_code: "x" } });
    expect(r.status).toBe(503);
    expect(r.body).toEqual({ error: "google_not_configured" });
    expect((await v1("auth/google/resolve", { session: a.session, body: { keep: "here" } })).status).toBe(503);
  });

  it("links an unknown Google player to the guest account; linking again is a no-op", async () => {
    const a = await guest();
    const r = await g("auth/google", a.session, { server_auth_code: codeFor("gp-link-1", "Rafi G") });
    expect(r.status, JSON.stringify(r.body)).toBe(200);
    expect(r.body).toMatchObject({ linked: true, account: { id: a.id, guest: false, google_name: "Rafi G" } });
    expect(r.body.session).toBeTruthy();
    expect(r.body.profile.coins).toBe(5000);
    expect(seenBodies.at(-1)).toContain("client_id=web-client.apps.googleusercontent.com");
    expect(seenBodies.at(-1)).toContain("grant_type=authorization_code");
    const again = await g("auth/google", a.session, { server_auth_code: codeFor("gp-link-1") });
    expect(again.status).toBe(200);
    expect(again.body.linked).toBe(true);
    expect((await row("SELECT google_player_id FROM accounts WHERE id = ?", a.id))!.google_player_id).toBe("gp-link-1");
  });

  it("needs a session and a code; Google errors map to 401 / 502", async () => {
    const a = await guest();
    expect((await g("auth/google", null, { server_auth_code: "x" })).status).toBe(401);
    expect((await g("auth/google", a.session, {})).status).toBe(400);
    expect(await g("auth/google", a.session, { server_auth_code: "bad" })).toEqual({ status: 401, body: { error: "google_rejected" } });
    expect(await g("auth/google", a.session, { server_auth_code: "down" })).toEqual({ status: 502, body: { error: "google_failed" } });
    expect((await row("SELECT google_player_id FROM accounts WHERE id = ?", a.id))!.google_player_id).toBeNull();
  });

  it("conflict -> resolve 'there': this device switches to the Google account's account", async () => {
    const main = await guest();
    await ok("shop/buy", { session: main.session, body: { kind: "dice", id: "crema" } });
    expect((await g("auth/google", main.session, { server_auth_code: codeFor("gp-there") })).status).toBe(200);

    const pid = newPid();
    const fresh = await guest({ pid });
    const c = await g("auth/google", fresh.session, { server_auth_code: codeFor("gp-there") });
    expect(c.status).toBe(409);
    expect(c.body.error).toBe("conflict");
    expect(c.body.conflict.here).toMatchObject({ name: "You", coins: 5000, level: 1, wins: 0 });
    expect(c.body.conflict.there).toMatchObject({ coins: 4000, level: 1 });
    expect(typeof c.body.ticket).toBe("string");

    // a ticket from another account's session is refused
    const other = await guest();
    expect((await g("auth/google/resolve", other.session, { keep: "there", ticket: c.body.ticket })).body).toEqual({ error: "bad_ticket" });
    expect((await g("auth/google/resolve", fresh.session, { keep: "maybe", ticket: c.body.ticket })).status).toBe(400);

    const r = await g("auth/google/resolve", fresh.session, { keep: "there", ticket: c.body.ticket, pid });
    expect(r.status, JSON.stringify(r.body)).toBe(200);
    expect(r.body).toMatchObject({ switched: true, account: { id: main.id } });
    expect(r.body.profile.coins).toBe(4000);
    expect(await verifySession(ENV, r.body.session)).toEqual({ account_id: main.id });
    // the device now opens the Google account; the guest account is left as it is
    expect((await guest({ pid })).id).toBe(main.id);
    expect(await row("SELECT merged_into, google_player_id FROM accounts WHERE id = ?", fresh.id)).toEqual({ merged_into: null, google_player_id: null });
  });

  it("conflict -> resolve 'here': the Google id moves, the other account is retired and its devices follow", async () => {
    const oldPid = newPid();
    const old = await guest({ pid: oldPid });
    expect((await g("auth/google", old.session, { server_auth_code: codeFor("gp-here") })).status).toBe(200);

    const pid = newPid();
    const now = await guest({ pid });
    await ok("rewards/free", { session: now.session, body: {}, now: T0 });
    const c = await g("auth/google", now.session, { server_auth_code: codeFor("gp-here") });
    expect(c.status).toBe(409);
    // resolve with a fresh server auth code instead of the ticket
    const r = await g("auth/google/resolve", now.session, { keep: "here", server_auth_code: codeFor("gp-here"), pid });
    expect(r.status, JSON.stringify(r.body)).toBe(200);
    expect(r.body).toMatchObject({ linked: true, merged: old.id, account: { id: now.id, guest: false } });
    expect(r.body.profile.coins).toBe(5300);
    expect(await row("SELECT google_player_id, merged_into FROM accounts WHERE id = ?", old.id)).toEqual({ google_player_id: null, merged_into: now.id });
    expect((await row("SELECT google_player_id FROM accounts WHERE id = ?", now.id))!.google_player_id).toBe("gp-here");
    // the retired account's sessions stop working and its device opens the kept account
    expect((await v1("me", { session: old.session })).status).toBe(401);
    expect(await verifySession(ENV, old.session)).toBeNull();
    expect((await guest({ pid: oldPid })).id).toBe(now.id);
    expect(await rows("SELECT pid FROM devices WHERE account_id = ?", old.id)).toEqual([]);
  });

  it("an account linked to Google A that signs in with a new Google B: 409 other_google, then stay or switch", async () => {
    const pid = newPid();
    const a = await guest({ pid });
    expect((await g("auth/google", a.session, { server_auth_code: codeFor("gp-A") })).status).toBe(200);
    const c = await g("auth/google", a.session, { server_auth_code: codeFor("gp-B", "B"), pid });
    expect(c.status, JSON.stringify(c.body)).toBe(409);
    expect(c.body).toMatchObject({ error: "other_google", conflict: { here: { name: "You", coins: 5000 }, there: null } });
    expect(typeof c.body.ticket).toBe("string");
    // nothing switched or created yet
    expect((await guest({ pid })).id).toBe(a.id);
    expect(await row("SELECT id FROM accounts WHERE google_player_id = 'gp-B'")).toBeNull();
    // "here" can't move B onto an account that already has A
    expect(await g("auth/google/resolve", a.session, { keep: "here", ticket: c.body.ticket, pid })).toEqual({ status: 409, body: { error: "already_linked" } });
    // stay: nothing changes
    const stay = await g("auth/google/resolve", a.session, { keep: "stay", ticket: c.body.ticket, pid });
    expect(stay.status, JSON.stringify(stay.body)).toBe(200);
    expect(stay.body).toMatchObject({ stayed: true, account: { id: a.id, guest: false } });
    expect((await guest({ pid })).id).toBe(a.id);
    expect(await row("SELECT id FROM accounts WHERE google_player_id = 'gp-B'")).toBeNull();
    // switch: B's account is created and the device opens it; A's account is left as it is
    const sw = await g("auth/google/resolve", a.session, { keep: "switch", ticket: c.body.ticket, pid });
    expect(sw.status, JSON.stringify(sw.body)).toBe(200);
    expect(sw.body).toMatchObject({ switched: true, created: true, account: { guest: false, google_name: "B" } });
    expect(sw.body.account.id).not.toBe(a.id);
    expect(await verifySession(ENV, sw.body.session)).toEqual({ account_id: sw.body.account.id });
    expect((await guest({ pid })).id).toBe(sw.body.account.id);
    expect(await row("SELECT google_player_id, merged_into FROM accounts WHERE id = ?", a.id)).toEqual({ google_player_id: "gp-A", merged_into: null });
    // switching again with the same ticket opens the account made a moment ago (not a second one)
    const again = await g("auth/google/resolve", a.session, { keep: "switch", ticket: c.body.ticket });
    expect(again.body).toMatchObject({ switched: true, created: false, account: { id: sw.body.account.id } });
    expect(await rows("SELECT id FROM accounts WHERE google_player_id = 'gp-B'")).toHaveLength(1);
  });

  it("other_google when B already has an account: its summary, and switch opens it", async () => {
    const bPid = newPid();
    const b = await guest({ pid: bPid });
    await ok("shop/buy", { session: b.session, body: { kind: "dice", id: "crema" } });
    expect((await g("auth/google", b.session, { server_auth_code: codeFor("gp-B2") })).status).toBe(200);
    const pid = newPid();
    const a = await guest({ pid });
    expect((await g("auth/google", a.session, { server_auth_code: codeFor("gp-A2") })).status).toBe(200);
    const c = await g("auth/google", a.session, { server_auth_code: codeFor("gp-B2") });
    expect(c.status).toBe(409);
    expect(c.body).toMatchObject({ error: "other_google", conflict: { here: { coins: 5000 }, there: { coins: 4000 } } });
    // keep "there" means the same as "switch" here
    const sw = await g("auth/google/resolve", a.session, { keep: "there", ticket: c.body.ticket, pid });
    expect(sw.body).toMatchObject({ switched: true, created: false, account: { id: b.id } });
    expect(sw.body.profile.coins).toBe(4000);
    expect((await guest({ pid })).id).toBe(b.id);
    // a banned B can't be switched to
    await setAccount(b.id, { banned: 1, ban_reason: "cheating" });
    const c2 = await g("auth/google", a.session, { server_auth_code: codeFor("gp-B2") });
    expect(c2.status).toBe(403);
  });

  it("stay after a guest conflict changes nothing", async () => {
    const main = await guest();
    expect((await g("auth/google", main.session, { server_auth_code: codeFor("gp-stay") })).status).toBe(200);
    const pid = newPid();
    const fresh = await guest({ pid });
    const c = await g("auth/google", fresh.session, { server_auth_code: codeFor("gp-stay") });
    expect(c.body.error).toBe("conflict");
    const r = await g("auth/google/resolve", fresh.session, { keep: "stay", ticket: c.body.ticket, pid });
    expect(r.body).toMatchObject({ stayed: true, account: { id: fresh.id, guest: true } });
    expect((await guest({ pid })).id).toBe(fresh.id);
    expect((await row("SELECT google_player_id FROM accounts WHERE id = ?", main.id))!.google_player_id).toBe("gp-stay");
  });

  it("a banned Google account cannot be linked or merged", async () => {
    const a = await guest();
    expect((await g("auth/google", a.session, { server_auth_code: codeFor("gp-banned") })).status).toBe(200);
    await setAccount(a.id, { banned: 1, ban_reason: "bot farm" });
    const b = await guest();
    const r = await g("auth/google", b.session, { server_auth_code: codeFor("gp-banned") });
    expect(r.status).toBe(403);
    expect(r.body.error).toBe("banned");
  });
});
