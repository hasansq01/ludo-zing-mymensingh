// Rewarded ads and gem purchases (ECONOMY_V1.md §2): the AdMob callback's ECDSA signature (keys generated here and
// served as Google's), nonces, grants once per transaction, the day caps, the eligibility rules (refill, double),
// expiry; the Play purchase check (a fake Play Developer API), gems granted once per token, pending / canceled /
// foreign purchases refused, consume, and refunds voided by the cron.
import { SELF } from "cloudflare:test";
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { derToRaw, resetAdKeys } from "../src/ads";
import { ECON_V1 } from "../src/econ";
import { setGoogleFetcher } from "../src/gauth";
import { setIapServiceAccount, voidRefunded } from "../src/iap";
import { DB, row, rows } from "./admin_helpers";
import { E, type Msg } from "./room_client";
import { guest, type Guest } from "./quick_client";

// ---------- helpers ----------

async function call(path: string, g: Guest | null, init: { method?: string; body?: unknown } = {}): Promise<{ status: number; body: Msg }> {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (g) headers.Authorization = `Bearer ${g.session}`;
  const r = await SELF.fetch(`https://x/v1/${path}`, { method: init.method ?? (init.body ? "POST" : "GET"), headers, body: init.body ? JSON.stringify(init.body) : undefined });
  return { status: r.status, body: (await r.json()) as Msg };
}

async function setAcc(account: string, cols: Record<string, number>) {
  const k = Object.keys(cols);
  await DB.prepare(`UPDATE accounts SET ${k.map((c) => `${c} = ?`).join(", ")} WHERE id = ?`).bind(...k.map((c) => cols[c]), account).run();
}

async function acc(account: string) {
  return (await row<{ coins: number; gems: number; rerolls: number }>("SELECT coins, gems, rerolls FROM accounts WHERE id = ?", account))!;
}

function b64(buf: ArrayBuffer | Uint8Array): string {
  const a = buf instanceof Uint8Array ? buf : new Uint8Array(buf);
  let s = "";
  for (const x of a) s += String.fromCharCode(x);
  return btoa(s);
}

function b64urlOf(buf: Uint8Array): string {
  return b64(buf).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** r || s (64 bytes) -> ASN.1 DER, as AdMob sends it. */
function rawToDer(raw: Uint8Array): Uint8Array {
  const int = (v: Uint8Array) => {
    let i = 0;
    while (i < v.length - 1 && v[i] === 0) i++;
    let x = v.slice(i);
    if (x[0] & 0x80) x = Uint8Array.of(0, ...x);
    return Uint8Array.of(0x02, x.length, ...x);
  };
  const r = int(raw.slice(0, 32));
  const s = int(raw.slice(32));
  return Uint8Array.of(0x30, r.length + s.length, ...r, ...s);
}

let adKey: CryptoKeyPair;
const KEY_ID = "3335741209";

/** An AdMob SSV callback URL for this nonce, signed with the test key (or tampered). */
async function ssvUrl(o: { nonce: string; user: string; tx: string; tamper?: boolean; key?: string }): Promise<string> {
  const q = new URLSearchParams({
    ad_network: "5450213213286189855",
    ad_unit: "1234567890",
    custom_data: o.nonce,
    reward_amount: "1",
    reward_item: "Reward",
    timestamp: String(Date.now()),
    transaction_id: o.tx,
    user_id: o.user,
  }).toString();
  const sig = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, adKey.privateKey, new TextEncoder().encode(o.tamper ? `${q}x` : q)));
  return `https://x/v1/ads/ssv?${q}&signature=${b64urlOf(rawToDer(sig))}&key_id=${o.key ?? KEY_ID}`;
}

async function ssv(url: string): Promise<{ status: number; body: Msg }> {
  const r = await SELF.fetch(url);
  return { status: r.status, body: (await r.json()) as Msg };
}

let txn = 0;

/** start + a valid callback; returns the start answer. */
async function watch(g: Guest, kind: string, ref?: string): Promise<Msg> {
  const s = await call("ads/start", g, { body: { kind, ref } });
  expect(s.status, JSON.stringify(s.body)).toBe(200);
  const r = await ssv(await ssvUrl({ nonce: s.body.nonce, user: g.account, tx: `tx${++txn}${Date.now()}` }));
  expect(r.status, JSON.stringify(r.body)).toBe(200);
  return s.body;
}

beforeAll(async () => {
  adKey = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"])) as CryptoKeyPair;
  const spki = (await crypto.subtle.exportKey("spki", adKey.publicKey)) as ArrayBuffer;
  (globalThis as unknown as { __lzAdKeys?: unknown }).__lzAdKeys = [{ keyId: Number(KEY_ID), base64: b64(spki) }];
  resetAdKeys();
});

afterAll(() => {
  delete (globalThis as unknown as { __lzAdKeys?: unknown }).__lzAdKeys;
  resetAdKeys();
});

// ---------- ads ----------

describe("the AdMob signature", () => {
  it("DER -> r || s keeps both 32-byte halves (leading zeros, sign bytes)", () => {
    const raw = new Uint8Array(64);
    raw[31] = 7; // r = 7 (31 leading zeros)
    raw[32] = 0x80; // s with the top bit set (DER adds a 0x00)
    expect(Array.from(derToRaw(rawToDer(raw))!)).toEqual(Array.from(raw));
    expect(derToRaw(Uint8Array.of(1, 2, 3))).toBeNull();
  });

  it("a valid callback grants; a tampered one, an unknown key or a wrong user_id grants nothing", async () => {
    const g = await guest();
    const s = await call("ads/start", g, { body: { kind: "gems" } });
    expect(s.body).toMatchObject({ ok: true, user_id: g.account, custom_data: s.body.nonce });
    expect((await ssv(await ssvUrl({ nonce: s.body.nonce, user: g.account, tx: "bad1", tamper: true }))).status).toBe(400);
    expect((await ssv(await ssvUrl({ nonce: s.body.nonce, user: g.account, tx: "bad2", key: "999" }))).status).toBe(400);
    const other = await guest();
    expect((await ssv(await ssvUrl({ nonce: s.body.nonce, user: other.account, tx: "bad3" }))).body).toEqual({ ok: true, result: "ignored" });
    // AdMob's "Verify URL" test callback: signed, no nonce
    expect(await ssv(await ssvUrl({ nonce: "", user: "", tx: "verify" }))).toEqual({ status: 200, body: { ok: true, result: "ignored" } });
    expect((await acc(g.account)).gems).toBe(0);
    expect((await call(`ads/status?nonce=${s.body.nonce}`, g)).body.status).toBe("pending");

    const ok = await ssv(await ssvUrl({ nonce: s.body.nonce, user: g.account, tx: "good1" }));
    expect(ok).toEqual({ status: 200, body: { ok: true, result: "granted" } });
    expect((await acc(g.account)).gems).toBe(ECON_V1.ads.gems.amount);
    const st = await call(`ads/status?nonce=${s.body.nonce}`, g);
    expect(st.body).toMatchObject({ status: "granted", kind: "gems", amount: 2 });
    expect(st.body.profile.gems).toBe(2);
    // AdMob retries / duplicates: granted once
    expect((await ssv(await ssvUrl({ nonce: s.body.nonce, user: g.account, tx: "good1" }))).body).toMatchObject({ duplicate: true });
    expect((await acc(g.account)).gems).toBe(2);
    const led = await rows<Msg>("SELECT delta_gems, reason, ref FROM ledger WHERE account_id = ? AND reason = 'ad'", g.account);
    expect(led).toEqual([{ delta_gems: 2, reason: "ad", ref: `gems:${s.body.nonce}` }]);
  });

  it("a session can't fake the callback: /v1/ads/ssv needs the signature, whatever the headers", async () => {
    const g = await guest();
    const s = await call("ads/start", g, { body: { kind: "reroll" } });
    const r = await SELF.fetch(`https://x/v1/ads/ssv?custom_data=${s.body.nonce}&user_id=${g.account}&transaction_id=t`, { headers: { Authorization: `Bearer ${g.session}` } });
    expect(r.status).toBe(400);
    expect((await acc(g.account)).rerolls).toBe(0);
  });
});

describe("ad kinds and caps", () => {
  it("reroll: +1 free re-roll, 3 a day", async () => {
    const g = await guest();
    for (let k = 0; k < 3; k++) await watch(g, "reroll");
    expect((await acc(g.account)).rerolls).toBe(3);
    const s = await call("ads/start", g, { body: { kind: "reroll" } });
    expect(s.status).toBe(409);
    expect(s.body.error).toBe("cap");
    const t = await call("ads/today", g);
    expect(t.body.left).toMatchObject({ reroll: 0, gems: 1 });
    expect(t.body.total_left).toBe(ECON_V1.ads_per_day - 3);
  });

  it("refill: only while broke (< 100 coins): +500 coins, counted as earned", async () => {
    const g = await guest();
    expect((await call("ads/start", g, { body: { kind: "refill" } })).body.error).toBe("not_eligible");
    await setAcc(g.account, { coins: 40 });
    await watch(g, "refill");
    expect((await acc(g.account)).coins).toBe(540);
  });

  it("double: a coin-table win of the last 15 minutes, once", async () => {
    const g = await guest();
    const mid = "DBLXYZ-1";
    const now = Date.now();
    await DB.batch([
      DB.prepare("INSERT INTO match_grants (match_id, account_id, at, game, outcome, coins, xp) VALUES (?, ?, ?, 'ludo', 'win', 180, 100)").bind(mid, g.account, now),
      DB.prepare("INSERT INTO entries (id, account_id, at, game, size, tier, amount, status, match_id, place, payout) VALUES ('ent_dddddddddddddddd', ?, ?, 'ludo', 2, 't100', 100, 'settled', ?, 0, 180)").bind(g.account, now, mid),
    ]);
    expect((await call("ads/start", g, { body: { kind: "double", ref: "OTHER-1" } })).body.error).toBe("not_eligible");
    const before = (await acc(g.account)).coins;
    await watch(g, "double", mid);
    expect((await acc(g.account)).coins).toBe(before + 180);
    expect((await call("ads/start", g, { body: { kind: "double", ref: mid } })).body.error).toBe("not_eligible");
  });

  it("8 ads a day in total, whatever the kinds", async () => {
    const g = await guest();
    const day = Date.now();
    // 7 already granted today (seeded), the 8th works, the 9th is over the total cap
    const kinds = ["reroll", "reroll", "reroll", "refill", "refill", "double", "double"];
    await DB.batch(kinds.map((k, i) => DB.prepare("INSERT INTO ad_rewards (nonce, account_id, kind, created_at, status, tx_id, granted_at, amount) VALUES (?, ?, ?, ?, 'granted', ?, ?, 1)").bind(`ad_seed${i}${g.account.slice(4, 21)}`, g.account, k, day, `seed${i}${g.account}`, day)));
    await watch(g, "gems");
    const t = await call("ads/today", g);
    expect(t.body.total_left).toBe(0);
    expect(t.body.left).toEqual({ reroll: 0, refill: 0, double: 0, gems: 0 });
  });

  it("an old nonce is rejected at the callback (and says expired)", async () => {
    const g = await guest();
    const s = await call("ads/start", g, { body: { kind: "gems" } });
    await DB.prepare("UPDATE ad_rewards SET created_at = ? WHERE nonce = ?").bind(Date.now() - ECON_V1.ad_nonce_ms - 1000, s.body.nonce).run();
    expect((await call(`ads/status?nonce=${s.body.nonce}`, g)).body.status).toBe("expired");
    const r = await ssv(await ssvUrl({ nonce: s.body.nonce, user: g.account, tx: "late1" }));
    expect(r.body).toMatchObject({ ok: true, result: "expired" });
    expect((await acc(g.account)).gems).toBe(0);
  });

  it("bad kinds and nonces are 400", async () => {
    const g = await guest();
    expect((await call("ads/start", g, { body: { kind: "coins" } })).status).toBe(400);
    expect((await call("ads/status?nonce=nope", g)).status).toBe(400);
  });
});

// ---------- gem purchases ----------

interface FakePurchase {
  purchaseState: number;
  consumptionState?: number;
  orderId?: string;
  obfuscatedExternalAccountId?: string;
}

const play = {
  purchases: new Map<string, FakePurchase>(),
  consumed: [] as string[],
  voided: [] as string[],
  down: false,
  calls: [] as string[],
};

async function rsaServiceAccount(): Promise<string> {
  const k = (await crypto.subtle.generateKey({ name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" }, true, ["sign", "verify"])) as CryptoKeyPair;
  const pk = b64((await crypto.subtle.exportKey("pkcs8", k.privateKey)) as ArrayBuffer);
  return JSON.stringify({ project_id: "ludo-test", client_email: "iap@ludo-test.iam.gserviceaccount.com", private_key: `-----BEGIN PRIVATE KEY-----\n${pk}\n-----END PRIVATE KEY-----\n`, private_key_id: "k1" });
}

describe("gem purchases", () => {
  beforeAll(async () => setIapServiceAccount(await rsaServiceAccount()));
  afterAll(() => {
    setIapServiceAccount(undefined);
    setGoogleFetcher(null);
  });
  beforeEach(() => {
    play.purchases.clear();
    play.consumed = [];
    play.voided = [];
    play.down = false;
    play.calls = [];
    setGoogleFetcher(async (input, init) => {
      const u = new URL(input);
      play.calls.push(`${init?.method ?? "GET"} ${u.pathname}`);
      if (u.hostname === "oauth2.googleapis.com") return Response.json({ access_token: "at", expires_in: 3600 });
      if (play.down) return new Response("oops", { status: 500 });
      const m = u.pathname.match(/\/purchases\/products\/([^/]+)\/tokens\/([^/:]+)(:consume)?$/);
      if (m) {
        const p = play.purchases.get(decodeURIComponent(m[2]));
        if (!p) return Response.json({ error: { code: 400 } }, { status: 400 });
        if (m[3]) {
          play.consumed.push(decodeURIComponent(m[2]));
          p.consumptionState = 1;
          return new Response("", { status: 200 });
        }
        return Response.json(p);
      }
      if (u.pathname.endsWith("/purchases/voidedpurchases")) return Response.json({ voidedPurchases: play.voided.map((t) => ({ purchaseToken: t })) });
      return new Response("not found", { status: 404 });
    });
  });
  afterEach(() => setGoogleFetcher(null));

  it("a paid purchase grants its gems once, is consumed, and a retry says duplicate", async () => {
    const g = await guest();
    play.purchases.set("tok-aaaaaaaaaa", { purchaseState: 0, consumptionState: 0, orderId: "GPA.1", obfuscatedExternalAccountId: g.account });
    const r = await call("iap/verify", g, { body: { product_id: "gems_220", token: "tok-aaaaaaaaaa" } });
    expect(r.status, JSON.stringify(r.body)).toBe(200);
    expect(r.body).toMatchObject({ ok: true, gems: 220, consumed: true });
    expect(r.body.profile.gems).toBe(220);
    expect(play.consumed).toEqual(["tok-aaaaaaaaaa"]);
    const again = await call("iap/verify", g, { body: { product_id: "gems_220", token: "tok-aaaaaaaaaa" } });
    expect(again.body).toMatchObject({ ok: true, duplicate: true, gems: 220 });
    expect((await acc(g.account)).gems).toBe(220);
    expect(await row("SELECT product_id, gems, status, order_id FROM purchases WHERE token = 'tok-aaaaaaaaaa'")).toEqual({ product_id: "gems_220", gems: 220, status: "granted", order_id: "GPA.1" });
    expect(await row("SELECT delta_gems, reason FROM ledger WHERE account_id = ? AND reason = 'iap'", g.account)).toEqual({ delta_gems: 220, reason: "iap" });
  });

  it("the same token from another account is refused", async () => {
    const a = await guest();
    const b = await guest();
    play.purchases.set("tok-bbbbbbbbbb", { purchaseState: 0, consumptionState: 0 });
    expect((await call("iap/verify", a, { body: { product_id: "gems_80", token: "tok-bbbbbbbbbb" } })).status).toBe(200);
    const r = await call("iap/verify", b, { body: { product_id: "gems_80", token: "tok-bbbbbbbbbb" } });
    expect(r.status).toBe(409);
    expect(r.body.error).toBe("invalid");
    expect((await acc(b.account)).gems).toBe(0);
  });

  it("pending, canceled, unknown, consumed elsewhere, another account's purchase: no gems", async () => {
    const g = await guest();
    play.purchases.set("tok-pending01", { purchaseState: 2 });
    play.purchases.set("tok-cancel001", { purchaseState: 1 });
    play.purchases.set("tok-consumed1", { purchaseState: 0, consumptionState: 1 });
    play.purchases.set("tok-foreign01", { purchaseState: 0, consumptionState: 0, obfuscatedExternalAccountId: "acc_someoneelse12345" });
    const v = (token: string) => call("iap/verify", g, { body: { product_id: "gems_500", token } });
    expect((await v("tok-pending01")).body.error).toBe("pending");
    expect((await v("tok-cancel001")).body.error).toBe("invalid");
    expect((await v("tok-unknown01")).body.error).toBe("invalid");
    expect((await v("tok-consumed1")).body.error).toBe("invalid");
    expect((await v("tok-foreign01")).body.error).toBe("invalid");
    expect((await acc(g.account)).gems).toBe(0);
  });

  it("Play down: 503 unavailable (the game retries later); unknown product: 400", async () => {
    const g = await guest();
    play.down = true;
    play.purchases.set("tok-down00001", { purchaseState: 0 });
    expect((await call("iap/verify", g, { body: { product_id: "gems_80", token: "tok-down00001" } })).status).toBe(503);
    expect((await call("iap/verify", g, { body: { product_id: "gems_9999", token: "tok-down00001" } })).status).toBe(400);
    expect((await acc(g.account)).gems).toBe(0);
  });

  it("parallel verifies of one token grant once", async () => {
    const g = await guest();
    play.purchases.set("tok-parallel1", { purchaseState: 0, consumptionState: 0 });
    const rs = await Promise.all(Array.from({ length: 4 }, () => call("iap/verify", g, { body: { product_id: "gems_80", token: "tok-parallel1" } })));
    expect(rs.every((r) => r.status === 200)).toBe(true);
    expect((await acc(g.account)).gems).toBe(80);
    expect(rs.filter((r) => !r.body.duplicate).length).toBeGreaterThanOrEqual(1);
  });

  it("the cron takes back the gems of refunded purchases (never below 0) once", async () => {
    const g = await guest();
    play.purchases.set("tok-refund001", { purchaseState: 0, consumptionState: 0 });
    play.purchases.set("tok-refund002", { purchaseState: 0, consumptionState: 0 });
    await call("iap/verify", g, { body: { product_id: "gems_500", token: "tok-refund001" } });
    await call("iap/verify", g, { body: { product_id: "gems_80", token: "tok-refund002" } });
    await setAcc(g.account, { gems: 520 }); // spent 60 of the 580
    play.voided = ["tok-refund001", "tok-refund002", "tok-neverseen"];
    expect(await voidRefunded(E as never)).toBe(2);
    expect((await acc(g.account)).gems).toBe(0); // 520 - 500 = 20, then 20 of 80 (60 short)
    expect(await rows("SELECT status FROM purchases WHERE account_id = ? ORDER BY token", g.account)).toEqual([{ status: "voided" }, { status: "voided" }]);
    expect(await voidRefunded(E as never)).toBe(0);
    const led = await rows<Msg>("SELECT delta_gems, ref FROM ledger WHERE account_id = ? AND reason = 'iap_void' ORDER BY id", g.account);
    expect(led).toEqual([
      { delta_gems: -500, ref: "gems_500" },
      { delta_gems: -20, ref: "gems_80:short 60" },
    ]);
  });

  it("GET /v1/iap/products lists the packs", async () => {
    const g = await guest();
    const r = await call("iap/products", g);
    expect(r.body.products).toEqual([
      { id: "gems_80", gems: 80 },
      { id: "gems_220", gems: 220 },
      { id: "gems_500", gems: 500 },
      { id: "gems_1200", gems: 1200 },
    ]);
  });
});
