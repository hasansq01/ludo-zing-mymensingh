// The FCM sender (src/push.ts) against a fake Google: the OAuth JWT (RS256, verified with the public key of a key
// generated here), the token exchange and its cache, message shapes per channel, error classification and dead
// tokens, and push off (no secret / a bad secret): no HTTP at all.
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  FCM_SCOPE,
  TOKEN_URL,
  classify,
  fcmMessage,
  levelXp,
  pushAccount,
  pushConfigured,
  pushProject,
  send,
  sendUrl,
  setPushServiceAccount,
  type Note,
} from "../src/push";
import { levelInfo } from "../src/econ";
import { guest } from "./quick_client";
import { CLIENT_EMAIL, PENV, PROJECT, fcmToken, installFakeFcm, register, uninstallFakeFcm, type FakeFcm } from "./push_helpers";

let fcm: FakeFcm;
beforeAll(async () => {
  fcm = await installFakeFcm();
});
afterAll(() => uninstallFakeFcm());
beforeEach(() => {
  fcm.reset();
  setPushServiceAccount(fcm.serviceAccount); // also drops the cached access token
});

const GAME: Note = { kind: "turn", title: "It's your turn", body: "Ann is waiting for you in room ABCDEF", link: "room:ABCDEF", channel: "game", tag: "room:ABCDEF", ttl_s: 1800 };
const OFFER: Note = { kind: "promo", title: "Weekend", body: "Double coins", link: "shop", cid: "cmp_aaaaaaaaaaaa", channel: "offers", tag: "cmp_aaaaaaaaaaaa", ttl_s: 86400 };

describe("OAuth", () => {
  it("signs an RS256 JWT with the service account's key and exchanges it for an access token", async () => {
    const before = Math.floor(Date.now() / 1000);
    expect(await send(PENV, { token: fcmToken() }, GAME)).toBe("sent");
    expect(fcm.oauth).toHaveLength(1);
    const o = fcm.oauth[0];
    expect(o.verified).toBe(true);
    expect(o.header).toEqual({ alg: "RS256", typ: "JWT", kid: "key-1" });
    expect(o.claims).toMatchObject({ iss: CLIENT_EMAIL, scope: FCM_SCOPE, aud: TOKEN_URL });
    expect(o.claims.iat).toBeGreaterThanOrEqual(before - 1);
    expect(o.claims.exp - o.claims.iat).toBe(3600);
    expect(o.body.get("grant_type")).toBe("urn:ietf:params:oauth:grant-type:jwt-bearer");
    expect(fcm.sends[0].url).toBe(sendUrl(PROJECT));
    expect(fcm.sends[0].auth).toMatch(/^Bearer ya29\.fake-\d+$/);
  });

  it("caches the access token: many sends, one exchange", async () => {
    await Promise.all([1, 2, 3, 4, 5].map(() => send(PENV, { token: fcmToken() }, GAME)));
    await send(PENV, { token: fcmToken() }, GAME);
    expect(fcm.oauth).toHaveLength(1);
    expect(fcm.delivered).toHaveLength(6);
    expect(new Set(fcm.sends.map((s) => s.auth)).size).toBe(1);
  });

  it("renews a token that expires within 5 minutes", async () => {
    fcm.expiresIn = 200; // < the 5 min margin: never reused
    await send(PENV, { token: fcmToken() }, GAME);
    await send(PENV, { token: fcmToken() }, GAME);
    expect(fcm.oauth).toHaveLength(2);
  });

  it("a refused access token (401) is renewed once and the send retried", async () => {
    await send(PENV, { token: fcmToken() }, GAME);
    fcm.revoked.add(fcm.sends[0].auth.replace("Bearer ", ""));
    expect(await send(PENV, { token: fcmToken() }, GAME)).toBe("sent");
    expect(fcm.oauth).toHaveLength(2);
    expect(fcm.sends).toHaveLength(3);
  });

  it("an OAuth refusal is a retry, nothing sent", async () => {
    fcm.oauthDown = true;
    expect(await send(PENV, { token: fcmToken() }, GAME)).toBe("retry");
    expect(fcm.sends).toHaveLength(0);
    fcm.oauthDown = false;
    expect(await send(PENV, { token: fcmToken() }, GAME)).toBe("sent"); // the failure is not cached
  });
});

describe("messages", () => {
  it("game alerts: high priority, 30 min TTL, channel game, collapse key = tag", async () => {
    const token = fcmToken();
    await send(PENV, { token }, GAME);
    expect(fcm.delivered[0]).toEqual({
      token,
      notification: { title: GAME.title, body: GAME.body },
      data: { link: "room:ABCDEF", kind: "turn" },
      android: { priority: "high", ttl: "1800s", collapse_key: "room:ABCDEF", notification: { channel_id: "game", tag: "room:ABCDEF" } },
    });
  });

  it("offers: normal priority, the campaign id in data, to a topic", async () => {
    await send(PENV, { topic: "promos" }, OFFER);
    expect(fcm.delivered[0]).toEqual({
      topic: "promos",
      notification: { title: "Weekend", body: "Double coins" },
      data: { link: "shop", kind: "promo", cid: "cmp_aaaaaaaaaaaa" },
      android: { priority: "normal", ttl: "86400s", collapse_key: "cmp_aaaaaaaaaaaa", notification: { channel_id: "offers", tag: "cmp_aaaaaaaaaaaa" } },
    });
  });

  it("no tag: no collapse key", () => {
    const m = fcmMessage({ token: "x" }, { ...GAME, tag: undefined }) as { message: { android: Record<string, unknown> } };
    expect(m.message.android).toEqual({ priority: "high", ttl: "1800s", notification: { channel_id: "game" } });
  });
});

describe("errors", () => {
  it("classifies FCM answers", () => {
    const e = (status: string, errorCode?: string, message = "") => ({ error: { status, message, details: errorCode ? [{ errorCode }] : [] } });
    expect(classify(404, e("NOT_FOUND", "UNREGISTERED"), true)).toBe("dead");
    expect(classify(403, e("PERMISSION_DENIED", "SENDER_ID_MISMATCH"), true)).toBe("dead");
    expect(classify(400, e("INVALID_ARGUMENT", "INVALID_ARGUMENT", "The registration token is not a valid FCM registration token"), true)).toBe("dead");
    expect(classify(400, e("INVALID_ARGUMENT", "INVALID_ARGUMENT", "Invalid value at 'message.data'"), true)).toBe("failed");
    expect(classify(404, e("NOT_FOUND", "UNREGISTERED"), false)).toBe("failed"); // a topic is never "dead"
    expect(classify(429, e("RESOURCE_EXHAUSTED", "QUOTA_EXCEEDED"), true)).toBe("retry");
    expect(classify(503, e("UNAVAILABLE", "UNAVAILABLE"), true)).toBe("retry");
    expect(classify(500, null, true)).toBe("retry");
    expect(classify(403, e("PERMISSION_DENIED", "THIRD_PARTY_AUTH_ERROR"), true)).toBe("failed");
  });

  it("send answers per token; a network error is a retry", async () => {
    const t = { un: fcmToken(), inv: fcmToken(), bad: fcmToken(), down: fcmToken(), net: fcmToken() };
    fcm.behaviour.set(t.un, "unregistered");
    fcm.behaviour.set(t.inv, "invalid_token");
    fcm.behaviour.set(t.bad, "bad_payload");
    fcm.behaviour.set(t.down, "unavailable");
    fcm.behaviour.set(t.net, "throw");
    expect(await send(PENV, { token: t.un }, GAME)).toBe("dead");
    expect(await send(PENV, { token: t.inv }, GAME)).toBe("dead");
    expect(await send(PENV, { token: t.bad }, GAME)).toBe("failed");
    expect(await send(PENV, { token: t.down }, GAME)).toBe("retry");
    expect(await send(PENV, { token: t.net }, GAME)).toBe("retry");
  });

  it("pushAccount sends to every device with the toggle on and deletes the dead tokens", async () => {
    const g = await guest();
    const [a, b, c] = [fcmToken("a"), fcmToken("b"), fcmToken("c")];
    await register(g.session, a);
    await register(g.session, b);
    await register(g.session, c, { game: false });
    fcm.behaviour.set(b, "unregistered");
    const r = await pushAccount(PENV, g.account, GAME, { pref: "game", count: true });
    expect(r).toEqual({ sent: 1, failed: 1, tokens: 2 });
    expect(fcm.delivered.map((m) => m.token)).toEqual([a]);
    const left = await PENV.DB.prepare("SELECT token FROM push_tokens WHERE account_id = ? ORDER BY token").bind(g.account).all<{ token: string }>();
    expect(left.results.map((x) => x.token).sort()).toEqual([a, c].sort());
    const ev = await PENV.DB.prepare("SELECT kind, sent, failed FROM push_events").all();
    expect(ev.results).toEqual([{ kind: "turn", sent: 1, failed: 1 }]);
    // no toggle filter (admin test sends): every device
    fcm.reset();
    expect(await pushAccount(PENV, g.account, GAME, { pref: null, count: false })).toEqual({ sent: 2, failed: 0, tokens: 2 });
  });
});

describe("push off", () => {
  it("no secret, or one that is not a service account: off, and sends make no HTTP call", async () => {
    for (const v of [null, "", "not json", JSON.stringify({ project_id: PROJECT, client_email: CLIENT_EMAIL }), JSON.stringify({ project_id: "Bad Id!", client_email: CLIENT_EMAIL, private_key: "-----BEGIN PRIVATE KEY-----" })]) {
      setPushServiceAccount(v);
      expect(pushConfigured(PENV)).toBe(false);
      expect(pushProject(PENV)).toBeNull();
      expect(await send(PENV, { token: fcmToken() }, GAME)).toBe("failed");
      expect(await pushAccount(PENV, "acc_aaaaaaaaaaaaaaaa", GAME, { pref: "game", count: true })).toEqual({ sent: 0, failed: 0, tokens: 0 });
    }
    expect(fcm.oauth).toHaveLength(0);
    expect(fcm.sends).toHaveLength(0);
    setPushServiceAccount(fcm.serviceAccount);
    expect(pushConfigured(PENV)).toBe(true);
    expect(pushProject(PENV)).toBe(PROJECT);
  });

  it("the deployed default: FCM_SERVICE_ACCOUNT unset in the test env", () => {
    setPushServiceAccount(undefined);
    expect(pushConfigured({})).toBe(false);
  });
});

describe("levels", () => {
  it("levelXp is where econ levelInfo starts each level", () => {
    for (const L of [1, 2, 3, 7, 20, 60]) {
      expect(levelInfo(levelXp(L)).level).toBe(L);
      if (L > 1) expect(levelInfo(levelXp(L) - 1).level).toBe(L - 1);
    }
  });
});
