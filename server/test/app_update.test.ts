// App versions (in-app updates): the policy (min_online / latest in the config table, edited in the admin console,
// read from GET /v1/config), and what refuses an app below min_online: POST /v1/rooms (X-App-Version), the room
// hello (`app`) and the quick-match hello. An app that reports no version is version 10.
import { SELF } from "cloudflare:test";
import { afterEach, describe, expect, it } from "vitest";
import { appVersion, CONFIG_DEFAULTS, parseConfig } from "../src/db";
import { DB, api, login } from "./admin_helpers";
import { Client, createRoom, newPid, roomInfo } from "./room_client";
import { QuickClient, guest } from "./quick_client";

const setMin = async (min: number) => {
  await DB.prepare("INSERT INTO config (key, value) VALUES ('min_online', ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value").bind(String(min)).run();
};
afterEach(async () => {
  await DB.prepare("DELETE FROM config WHERE key IN ('min_online', 'latest')").run();
});

describe("policy", () => {
  it("defaults: nobody blocked, latest 10; bad stored values fall back", () => {
    expect(CONFIG_DEFAULTS.min_online).toBe(0);
    expect(CONFIG_DEFAULTS.latest).toBe(10);
    expect(parseConfig({})).toMatchObject({ min_online: 0, latest: 10 });
    expect(parseConfig({ min_online: "12", latest: "13" })).toMatchObject({ min_online: 12, latest: 13 });
    expect(parseConfig({ min_online: "-1", latest: "x" })).toMatchObject({ min_online: 0, latest: 10 });
    expect(parseConfig({ min_online: "99999999" })).toMatchObject({ min_online: 0 });
  });

  it("a missing or bad version is 10", () => {
    for (const v of [undefined, null, "", "abc", 0, -3, 1.5, {}, "0", "1e3"]) expect(appVersion(v)).toBe(10);
    expect(appVersion(11)).toBe(11);
    expect(appVersion("11")).toBe(11);
  });

  it("GET /v1/config carries the policy; the admin edits it (validated, audited) and it applies", async () => {
    expect(await (await SELF.fetch("https://x/v1/config")).json()).toMatchObject({ min_online: 0, latest: 10 });
    const cookie = await login();
    expect(await api(cookie, "config", { method: "PUT", body: { min_online: 11, latest: 12 } })).toMatchObject({ min_online: 11, latest: 12 });
    expect(await api(cookie, "config")).toMatchObject({ min_online: 11, latest: 12 });
    // (the public copy is cached 60 s per isolate; an admin PUT clears this isolate's)
    expect(await (await SELF.fetch("https://x/v1/config")).json()).toMatchObject({ min_online: 11, latest: 12 });
    for (const bad of [{ min_online: -1 }, { latest: 1.5 }, { min_online: "11" }, { latest: 1_000_001 }]) {
      expect((await api(cookie, "config", { method: "PUT", body: bad }, 400)).error).toBe("bad_request");
    }
    const audit = await api(cookie, "audit?limit=5");
    expect(audit.items.some((a: { action: string }) => a.action === "config.update")).toBe(true);
    await api(cookie, "config", { method: "PUT", body: { min_online: 0, latest: 10 } });
    expect((await SELF.fetch("https://x/v1/rooms", { method: "POST" })).status).toBe(200);
  });
});

describe("POST /v1/rooms", () => {
  it("refuses an app below min_online with 426 update_required; a missing header is 10", async () => {
    const cookie = await login();
    await api(cookie, "config", { method: "PUT", body: { min_online: 11 } });
    const old = await SELF.fetch("https://x/v1/rooms", { method: "POST", headers: { "X-App-Version": "10" } });
    expect(old.status).toBe(426);
    expect(await old.json()).toMatchObject({ error: "update_required", min: 11, msg: expect.stringMatching(/update/i) });
    expect((await SELF.fetch("https://x/v1/rooms", { method: "POST" })).status).toBe(426); // v10 and older send none
    expect((await SELF.fetch("https://x/v1/rooms", { method: "POST", headers: { "X-App-Version": "11" } })).status).toBe(200);
    await api(cookie, "config", { method: "PUT", body: { min_online: 0 } });
    expect((await SELF.fetch("https://x/v1/rooms", { method: "POST" })).status).toBe(200);
  });
});

describe("room hello", () => {
  it("an outdated hello gets error update_required and the socket closes; nothing is joined", async () => {
    const code = await createRoom();
    await setMin(11);
    const c = await Client.open(code, newPid(), "Old");
    c.app = 10;
    c.hello();
    expect(await c.wait("error")).toMatchObject({ code: "update_required", min: 11 });
    expect(await c.waitClosed()).toBe(4000);
    expect((await roomInfo(code)).body).toMatchObject({ members: 0 });
  });

  it("a hello without `app` counts as 10; one at or above min_online joins", async () => {
    const code = await createRoom();
    await setMin(11);
    const none = await Client.open(code, newPid(), "NoApp");
    none.hello();
    expect(await none.wait("error")).toMatchObject({ code: "update_required" });
    const fresh = await Client.open(code, newPid(), "Fresh");
    fresh.app = 11;
    fresh.hello();
    expect((await fresh.waitFor((m) => m.t === "welcome" || m.t === "error")).t).toBe("welcome");
    fresh.close();
  });

  it("min_online 0 blocks nobody", async () => {
    const code = await createRoom();
    const c = await Client.join(code, { name: "Anyone" });
    expect(c.id).toBeGreaterThanOrEqual(0);
    c.close();
  });
});

describe("quick match hello", () => {
  it("an outdated app is refused before it is queued; a missing version is 10; a current one queues", async () => {
    await setMin(11);
    const old = await QuickClient.queue("ludo", 2, await guest(), "Old", { app: 10 });
    expect(await old.wait("error")).toMatchObject({ code: "update_required", min: 11 });
    expect(await old.waitClosed()).toBe(4000);

    const none = await QuickClient.queue("ludo", 2, await guest(), "NoApp");
    expect(await none.wait("error")).toMatchObject({ code: "update_required" });

    const fresh = await QuickClient.queue("ludo", 2, await guest(), "Fresh", { app: 11 });
    expect(await fresh.wait("queued")).toMatchObject({ t: "queued" });
    fresh.send({ t: "cancel" });
  });
});
