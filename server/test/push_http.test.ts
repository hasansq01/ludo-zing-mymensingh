// /v1/push/token (POST / DELETE) and /v1/push/opened (NOTIFICATIONS.md "N-SRV" HTTP): validation, a token moving
// between accounts, the 5-device cap, prefs, opens counted once per account, and the same answers with push off.
import { SELF } from "cloudflare:test";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { setPushServiceAccount } from "../src/push";
import { DB, T0, guest, ok, rows, v1 } from "./acc_helpers";
import { fcmToken, register } from "./push_helpers";

beforeAll(() => setPushServiceAccount(null)); // push off: storing tokens works the same
afterAll(() => setPushServiceAccount(undefined));

const tokensOf = (account: string) =>
  rows<{ token: string; platform: string; prefs_game: number; prefs_offers: number; tz_offset_min: number | null }>(
    "SELECT token, platform, prefs_game, prefs_offers, tz_offset_min FROM push_tokens WHERE account_id = ? ORDER BY updated_at, token",
    account,
  );

async function insertCampaign(id: string): Promise<void> {
  await DB.prepare("INSERT INTO push_campaigns (id, title, body, link, audience, status, created_at) VALUES (?, 't', 'b', 'home', '{\"kind\":\"all\"}', 'sent', 0)").bind(id).run();
}

describe("POST /v1/push/token", () => {
  it("stores the token with its prefs and offset; registering again updates it", async () => {
    const g = await guest();
    const t = fcmToken();
    expect(await ok("push/token", { session: g.session, body: { token: t, platform: "android", prefs: { game: true, offers: false }, tz_offset_min: 360 } })).toEqual({ ok: true });
    expect(await tokensOf(g.id)).toEqual([{ token: t, platform: "android", prefs_game: 1, prefs_offers: 0, tz_offset_min: 360 }]);
    await ok("push/token", { session: g.session, body: { token: t, prefs: { game: false, offers: true } } });
    expect(await tokensOf(g.id)).toEqual([{ token: t, platform: "android", prefs_game: 0, prefs_offers: 1, tz_offset_min: null }]);
  });

  it("prefs default to on", async () => {
    const g = await guest();
    const t = fcmToken();
    await ok("push/token", { session: g.session, body: { token: t } });
    expect(await tokensOf(g.id)).toMatchObject([{ prefs_game: 1, prefs_offers: 1 }]);
  });

  it("a token another account had moves to this one", async () => {
    const [a, b] = [await guest(), await guest()];
    const t = fcmToken();
    await register(a.session, t);
    await register(b.session, t);
    expect(await tokensOf(a.id)).toEqual([]);
    expect((await tokensOf(b.id)).map((r) => r.token)).toEqual([t]);
  });

  it("an account keeps its 5 latest devices", async () => {
    const g = await guest();
    const ts: string[] = [];
    for (let k = 0; k < 7; k++) {
      ts.push(fcmToken());
      await ok("push/token", { session: g.session, body: { token: ts[k] }, now: T0 + k });
    }
    expect((await tokensOf(g.id)).map((r) => r.token)).toEqual(ts.slice(2));
  });

  it("needs a session; bad input is 400", async () => {
    expect((await v1("push/token", { body: { token: fcmToken() } })).status).toBe(401);
    const g = await guest();
    for (const body of [
      {},
      { token: "short" },
      { token: "x".repeat(2000) },
      { token: "has spaces in it, which tokens never have......" },
      { token: fcmToken(), platform: "ios" },
      { token: fcmToken(), prefs: { game: "yes" } },
      { token: fcmToken(), prefs: [] },
      { token: fcmToken(), tz_offset_min: 1000 },
      { token: fcmToken(), tz_offset_min: 1.5 },
    ]) {
      const r = await v1("push/token", { session: g.session, body });
      expect(r.status, JSON.stringify(body)).toBe(400);
      expect(r.body.error).toBe("bad_request");
    }
    expect(await tokensOf(g.id)).toEqual([]);
    expect((await v1("push/token", { session: g.session })).status).toBe(405); // GET
  });
});

describe("DELETE /v1/push/token", () => {
  it("removes this account's token only", async () => {
    const [a, b] = [await guest(), await guest()];
    const [ta, tb] = [fcmToken(), fcmToken()];
    await register(a.session, ta);
    await register(b.session, tb);
    expect(await ok("push/token", { method: "DELETE", session: a.session, body: { token: tb } })).toEqual({ ok: true });
    expect((await tokensOf(b.id)).map((r) => r.token)).toEqual([tb]); // not a's to delete
    await ok("push/token", { method: "DELETE", session: a.session, body: { token: ta } });
    expect(await tokensOf(a.id)).toEqual([]);
    expect((await v1("push/token", { method: "DELETE", body: { token: ta } })).status).toBe(401);
  });
});

describe("POST /v1/push/opened", () => {
  it("counts an open once per account; repeats and unknown campaigns change nothing", async () => {
    const cid = "cmp_openedaaaaaa";
    await insertCampaign(cid);
    const [a, b] = [await guest(), await guest()];
    for (const s of [a.session, a.session, b.session, a.session]) expect(await ok("push/opened", { session: s, body: { cid } })).toEqual({ ok: true });
    expect((await rows<{ opened: number }>("SELECT opened FROM push_campaigns WHERE id = ?", cid))[0].opened).toBe(2);
    expect(await rows("SELECT account_id FROM push_opens WHERE cid = ? ORDER BY account_id", cid)).toHaveLength(2);
    await ok("push/opened", { session: a.session, body: { cid: "cmp_unknownaaaaa" } });
    expect(await rows("SELECT * FROM push_opens WHERE cid = 'cmp_unknownaaaaa'")).toEqual([]);
  });

  it("the session is optional (nothing is counted without one); a malformed cid is 400", async () => {
    const cid = "cmp_anonaaaaaaaa";
    await insertCampaign(cid);
    const r = await SELF.fetch("https://x/v1/push/opened", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ cid }) });
    expect(r.status).toBe(200);
    expect(await r.json()).toEqual({ ok: true });
    expect((await rows<{ opened: number }>("SELECT opened FROM push_campaigns WHERE id = ?", cid))[0].opened).toBe(0);
    const g = await guest();
    for (const body of [{}, { cid: 5 }, { cid: "cmp_x" }, { cid: "CMP_AAAAAAAAAAAA" }]) {
      expect((await v1("push/opened", { session: g.session, body })).status).toBe(400);
    }
    expect((await v1("push/opened", {})).status).toBe(405);
  });
});
