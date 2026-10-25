// Helpers for the push tests: a service account with an RSA key generated here, and a fake Google (OAuth token
// endpoint + FCM v1) that verifies the JWT's RS256 signature with the public key, records every message and answers
// per token as told (ok / unregistered / invalid token / bad payload / unavailable / sender mismatch).
import { SELF, env } from "cloudflare:test";
import { expect } from "vitest";
import { FCM_SCOPE, TOKEN_URL, sendUrl, setPushFetcher, setPushServiceAccount } from "../src/push";
import type { Env } from "../src/room";

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export type Json = Record<string, any>;

export const PENV = env as unknown as Env;
export const PROJECT = "ludo-zing-test";
export const CLIENT_EMAIL = "fcm-sender@ludo-zing-test.iam.gserviceaccount.com";

export type Behaviour = "ok" | "unregistered" | "invalid_token" | "bad_payload" | "unavailable" | "sender_mismatch" | "throw";

function b64(buf: ArrayBuffer): string {
  let s = "";
  for (const b of new Uint8Array(buf)) s += String.fromCharCode(b);
  return btoa(s);
}

function unb64url(s: string): Uint8Array {
  const bin = atob(s.replace(/-/g, "+").replace(/_/g, "/"));
  return Uint8Array.from(bin, (c) => c.charCodeAt(0));
}

export function decodePart(s: string): Json {
  return JSON.parse(new TextDecoder().decode(unb64url(s)));
}

export interface FakeFcm {
  serviceAccount: string;
  publicKey: CryptoKey;
  /** Every OAuth exchange: the JWT's header and claims, and whether its signature verified. */
  oauth: Array<{ header: Json; claims: Json; verified: boolean; body: URLSearchParams }>;
  /** Every FCM send (accepted or not): the message, the bearer, the URL. */
  sends: Array<{ url: string; auth: string; message: Json }>;
  /** Accepted messages only. */
  delivered: Json[];
  /** token (or "topic:<name>") -> how FCM answers (default ok). */
  behaviour: Map<string, Behaviour>;
  /** expires_in of the issued access tokens (s). */
  expiresIn: number;
  /** Bearer tokens FCM refuses with 401 (once each). */
  revoked: Set<string>;
  /** The OAuth endpoint refuses (invalid_grant). */
  oauthDown: boolean;
  reset(): void;
}

/** A fresh RSA key + service account, the fake installed as the push fetcher and the push secret. */
export async function installFakeFcm(): Promise<FakeFcm> {
  const kp = (await crypto.subtle.generateKey(
    { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
    true,
    ["sign", "verify"],
  )) as CryptoKeyPair;
  const pkcs8 = (await crypto.subtle.exportKey("pkcs8", kp.privateKey)) as ArrayBuffer;
  const pem = `-----BEGIN PRIVATE KEY-----\n${b64(pkcs8).replace(/(.{64})/g, "$1\n")}\n-----END PRIVATE KEY-----\n`;
  const serviceAccount = JSON.stringify({
    type: "service_account",
    project_id: PROJECT,
    private_key_id: "key-1",
    private_key: pem,
    client_email: CLIENT_EMAIL,
    token_uri: TOKEN_URL,
  });
  let issued = 0;
  const valid = new Set<string>();
  const f: FakeFcm = {
    serviceAccount,
    publicKey: kp.publicKey,
    oauth: [],
    sends: [],
    delivered: [],
    behaviour: new Map(),
    expiresIn: 3600,
    revoked: new Set(),
    oauthDown: false,
    reset() {
      f.oauth.length = 0;
      f.sends.length = 0;
      f.delivered.length = 0;
      f.behaviour.clear();
      f.revoked.clear();
      f.expiresIn = 3600;
      f.oauthDown = false;
    },
  };
  setPushFetcher(async (url, init) => {
    if (url === TOKEN_URL) {
      const body = new URLSearchParams(String(init?.body ?? ""));
      const jwt = body.get("assertion") ?? "";
      const [h, c, s] = jwt.split(".");
      const verified = await crypto.subtle.verify("RSASSA-PKCS1-v1_5", kp.publicKey, unb64url(s), new TextEncoder().encode(`${h}.${c}`));
      f.oauth.push({ header: decodePart(h), claims: decodePart(c), verified, body });
      if (!verified || f.oauthDown || body.get("grant_type") !== "urn:ietf:params:oauth:grant-type:jwt-bearer") {
        return Response.json({ error: "invalid_grant" }, { status: 400 });
      }
      const at = `ya29.fake-${++issued}`;
      valid.add(at);
      return Response.json({ access_token: at, expires_in: f.expiresIn, token_type: "Bearer" });
    }
    if (url === sendUrl(PROJECT)) {
      const auth = new Headers(init?.headers).get("Authorization") ?? "";
      const message = (JSON.parse(String(init?.body ?? "{}")) as Json).message;
      f.sends.push({ url, auth, message });
      const at = auth.replace(/^Bearer /, "");
      if (!valid.has(at) || f.revoked.has(at)) {
        f.revoked.delete(at);
        valid.delete(at);
        return Response.json({ error: { code: 401, status: "UNAUTHENTICATED", message: "bad credentials" } }, { status: 401 });
      }
      const b = f.behaviour.get(message.token ?? `topic:${message.topic}`) ?? "ok";
      const err = (code: number, status: string, msg: string, errorCode?: string) =>
        Response.json(
          { error: { code, status, message: msg, details: errorCode ? [{ "@type": "type.googleapis.com/google.firebase.fcm.v1.FcmError", errorCode }] : [] } },
          { status: code },
        );
      switch (b) {
        case "unregistered":
          return err(404, "NOT_FOUND", "Requested entity was not found.", "UNREGISTERED");
        case "invalid_token":
          return err(400, "INVALID_ARGUMENT", "The registration token is not a valid FCM registration token", "INVALID_ARGUMENT");
        case "bad_payload":
          return err(400, "INVALID_ARGUMENT", "Invalid value at 'message.android.ttl'", "INVALID_ARGUMENT");
        case "sender_mismatch":
          return err(403, "PERMISSION_DENIED", "SenderId mismatch", "SENDER_ID_MISMATCH");
        case "unavailable":
          return err(503, "UNAVAILABLE", "try again", "UNAVAILABLE");
        case "throw":
          throw new Error("network down (test)");
      }
      f.delivered.push(message);
      return Response.json({ name: `projects/${PROJECT}/messages/${f.sends.length}` });
    }
    return new Response("unexpected", { status: 599 });
  });
  setPushServiceAccount(serviceAccount);
  return f;
}

export function uninstallFakeFcm(): void {
  setPushFetcher(null);
  setPushServiceAccount(undefined);
}

let tokSeq = 0;
/** A plausible FCM registration token (unique). */
export function fcmToken(tag = "t"): string {
  tokSeq++;
  const r = crypto.getRandomValues(new Uint8Array(24));
  const rand = Array.from(r, (b) => b.toString(16).padStart(2, "0")).join("");
  return `${tag}${tokSeq.toString(36)}:APA91b${rand}`.slice(0, 160);
}

/** POST /v1/push/token for a session. */
export async function register(session: string, token: string, prefs: { game?: boolean; offers?: boolean } = {}, extra: Json = {}): Promise<void> {
  const r = await SELF.fetch("https://x/v1/push/token", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${session}` },
    body: JSON.stringify({ token, platform: "android", prefs: { game: true, offers: true, ...prefs }, tz_offset_min: 360, ...extra }),
  });
  expect(r.status, await r.clone().text()).toBe(200);
}

export function pusherStub() {
  return PENV.PUSHER.get(PENV.PUSHER.idFromName("pusher"));
}
