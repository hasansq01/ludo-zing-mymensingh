// POST /v1/shop/buy and /v1/shop/equip: econ rules through the endpoint, ledger rows, and concurrency (parallel
// requests can't spend the same coins twice).
import { describe, expect, it } from "vitest";
import { T0, guest, ledgerSum, ok, rows, setAccount, v1 } from "./acc_helpers";

describe("shop", () => {
  it("buys an item: pays once, owns and equips it, one ledger row", async () => {
    const a = await guest();
    const r = await ok("shop/buy", { session: a.session, body: { kind: "dice", id: "crema" }, now: T0 });
    expect(r).toMatchObject({ ok: true, price: 1000, item: { kind: "dice", id: "crema" } });
    expect(r.profile).toMatchObject({ coins: 4000, dice: "crema" });
    expect(r.profile.dice_owned).toEqual(["classic", "crema"]);
    expect((await ok("me", { session: a.session })).profile.coins).toBe(4000);
    const led = await rows("SELECT reason, ref, delta_coins, delta_xp, balance_after FROM ledger WHERE account_id = ? AND reason = 'buy'", a.id);
    expect(led).toEqual([{ reason: "buy", ref: "dice:crema", delta_coins: -1000, delta_xp: 0, balance_after: 4000 }]);
    expect(await ledgerSum(a.id)).toBe(4000);
  });

  it("errors: owned, unknown, coins (+short), locked; nothing changes", async () => {
    const a = await guest();
    const buy = (kind: string, id: string) => v1("shop/buy", { session: a.session, body: { kind, id } });
    expect((await buy("dice", "classic")).body).toEqual({ error: "owned" });
    expect(await buy("dice", "nope")).toMatchObject({ status: 404, body: { error: "unknown" } });
    expect(await buy("hat", "x")).toMatchObject({ status: 404, body: { error: "unknown" } });
    expect(await buy("scene", "frost")).toMatchObject({ status: 409, body: { error: "coins", short: 15000 } });
    expect(await buy("frame", "gold")).toMatchObject({ status: 409, body: { error: "locked" } });
    expect(await buy("char", "ch-arif")).toMatchObject({ status: 409, body: { error: "owned" } }); // a free character
    for (const bad of [{}, { kind: "dice" }, { kind: 3, id: "x" }, { kind: "dice", id: "x".repeat(40) }]) {
      expect((await v1("shop/buy", { session: a.session, body: bad })).status).toBe(400);
    }
    expect((await v1("shop/buy", { body: { kind: "dice", id: "crema" } })).status).toBe(401);
    expect((await v1("shop/buy", { session: a.session, method: "GET" })).status).toBe(405);
    expect((await ok("me", { session: a.session })).profile.coins).toBe(5000);
    expect(await rows("SELECT * FROM ledger WHERE account_id = ? AND reason = 'buy'", a.id)).toEqual([]);
  });

  it("buys and equips an emote pack through the wallet", async () => {
    const a = await guest();
    const r = await ok("shop/buy", { session: a.session, body: { kind: "emotes", id: "pawns" } });
    expect(r).toMatchObject({ ok: true, price: 2500, item: { kind: "emotes", id: "pawns" } });
    expect(r.profile).toMatchObject({ coins: 2500, emote_sets: ["starter", "pawns"], emote_set: "pawns" });
    const led = await rows("SELECT ref, delta_coins FROM ledger WHERE account_id = ? AND reason = 'buy'", a.id);
    expect(led).toEqual([{ ref: "emotes:pawns", delta_coins: -2500 }]);
    expect((await v1("shop/buy", { session: a.session, body: { kind: "emotes", id: "pawns" } })).body).toEqual({ error: "owned" });
    expect(await v1("shop/buy", { session: a.session, body: { kind: "emotes", id: "friends" } })).toMatchObject({ status: 409, body: { error: "coins", short: 1500 } });
    expect(await v1("shop/equip", { session: a.session, body: { kind: "emotes", id: "friends" } })).toMatchObject({ status: 409, body: { error: "locked" } });
    const e = await ok("shop/equip", { session: a.session, body: { kind: "emotes", id: "starter" } });
    expect(e.profile.emote_set).toBe("starter");
    expect((await ok("me", { session: a.session })).profile).toMatchObject({ emote_set: "starter", emote_sets: ["starter", "pawns"] });
  });

  it("buys a character and a scene", async () => {
    const a = await guest();
    await setAccount(a.id, { coins: 40_000 });
    const c = await ok("shop/buy", { session: a.session, body: { kind: "char", id: "ch-rafi" } });
    expect(c.profile).toMatchObject({ coins: 30_000, avatar: "ch-rafi" });
    const s = await ok("shop/buy", { session: a.session, body: { kind: "scene", id: "frost" } });
    expect(s.profile).toMatchObject({ coins: 10_000, scene: "frost" });
    expect(s.profile.scenes).toEqual(["jungle", "frost"]);
  });

  it("equips owned items only", async () => {
    const a = await guest();
    await ok("shop/buy", { session: a.session, body: { kind: "room", id: "dream" } });
    const e = await ok("shop/equip", { session: a.session, body: { kind: "room", id: "night" } });
    expect(e.profile.room).toBe("night");
    expect((await ok("shop/equip", { session: a.session, body: { kind: "room", id: "dream" } })).profile.room).toBe("dream");
    expect(await v1("shop/equip", { session: a.session, body: { kind: "room", id: "studio" } })).toMatchObject({ status: 409, body: { error: "locked" } });
    expect(await v1("shop/equip", { session: a.session, body: { kind: "room", id: "zzz" } })).toMatchObject({ status: 404, body: { error: "unknown" } });
    expect((await ok("shop/equip", { session: a.session, body: { kind: "badge", id: "" } })).ok).toBe(true);
    expect((await ok("me", { session: a.session })).profile.room).toBe("dream");
  });
});

describe("concurrency", () => {
  it("parallel purchases can't spend the same coins (5,000 coins, three rooms of 3,000 / 4,000 / 5,000)", async () => {
    for (let round = 0; round < 3; round++) {
      const a = await guest();
      const items = ["dream", "studio", "cloud"];
      const rs = await Promise.all(items.map((id) => v1("shop/buy", { session: a.session, body: { kind: "room", id } })));
      const okd = rs.filter((r) => r.status === 200);
      expect(okd.length).toBe(1);
      for (const r of rs.filter((x) => x.status !== 200)) expect(r.body.error).toBe("coins");
      const me = await ok("me", { session: a.session });
      expect(me.profile.coins).toBe(5000 - okd[0].body.price);
      expect(me.profile.rooms.length).toBe(3);
      expect(await rows("SELECT * FROM ledger WHERE account_id = ? AND reason = 'buy'", a.id)).toHaveLength(1);
      expect(await ledgerSum(a.id)).toBe(me.profile.coins);
    }
  });

  it("parallel purchases of the same item buy it once", async () => {
    const a = await guest();
    const rs = await Promise.all([0, 1, 2, 3, 4].map(() => v1("shop/buy", { session: a.session, body: { kind: "dice", id: "crema" } })));
    expect(rs.filter((r) => r.status === 200)).toHaveLength(1);
    expect(rs.filter((r) => r.body.error === "owned")).toHaveLength(4);
    expect((await ok("me", { session: a.session })).profile.coins).toBe(4000);
  });

  it("parallel purchases of different affordable items all apply (none lost)", async () => {
    const a = await guest();
    await setAccount(a.id, { coins: 100_000 });
    const items: [string, string][] = [["dice", "crema"], ["dice", "espresso"], ["dice", "gold"], ["room", "dream"], ["room", "studio"], ["room", "cloud"]];
    const rs = await Promise.all(items.map(([kind, id]) => v1("shop/buy", { session: a.session, body: { kind, id } })));
    for (const r of rs) expect(r.status, JSON.stringify(r.body)).toBe(200);
    const me = await ok("me", { session: a.session });
    expect(me.profile.coins).toBe(100_000 - (1000 + 2500 + 6000 + 3000 + 4000 + 5000));
    expect(me.profile.dice_owned).toEqual(expect.arrayContaining(["classic", "crema", "espresso", "gold"]));
    expect(me.profile.rooms).toEqual(expect.arrayContaining(["dream", "studio", "cloud"]));
  });
});
