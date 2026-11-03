// Pawn skins (Catalog.PAWNS, kind "pawn"): the catalogue, the profile fields, buying with coins and gems (the gem-only
// skins refuse coins), equipping, the one-time import, and the wallet endpoints (one ledger row, no double spend).
import { describe, expect, it } from "vitest";
import { CATALOG, FREE_PAWN, buy, equip, equipped, importProfile, item, items, newProfile, normalizeProfile, ownsPawn, type Profile } from "../src/econ";
import { ledgerSum, ok, rows, setAccount, v1, guest } from "./acc_helpers";

const ID = "LZM-AAAA-BBBB";
function wallet(coins: number, gems = 0): Profile {
  const p = newProfile(ID);
  p.coins = coins;
  p.gems = gems;
  return p;
}

describe("pawn skins: catalogue and profile", () => {
  it("Classic is free and the default; a mix of coin and gem-only skins", () => {
    const ps = items("pawn");
    expect(ps.length).toBeGreaterThanOrEqual(7);
    expect(FREE_PAWN).toBe("classic");
    expect(item("pawn", "classic")).toMatchObject({ price: 0, buy: false, free: true, default: true });
    const coin = ps.filter((it) => it.buy);
    const gemOnly = ps.filter((it) => !it.buy && !it.free);
    expect(coin.length).toBeGreaterThan(0);
    expect(gemOnly.length).toBeGreaterThan(0);
    for (const it of coin) expect([it.price >= 1000 && it.price <= 6000, it.gems]).toEqual([true, Math.ceil(it.price / 100)]);
    for (const it of gemOnly) expect([it.price, (it.gems ?? 0) > 0]).toEqual([0, true]);
    expect(CATALOG.defaults).toMatchObject({ pawns_owned: ["classic"], pawn: "classic" });
  });

  it("a new profile owns and uses Classic; damaged fields are repaired, owned ones kept", () => {
    const p = newProfile(ID);
    expect([p.pawns_owned, p.pawn]).toEqual([["classic"], "classic"]);
    const q = normalizeProfile({ id: ID, pawns_owned: ["marble", 3], pawn: "crown" });
    expect([q.pawns_owned, q.pawn]).toEqual([["classic", "marble", 3], "classic"]); // crown isn't owned
    const r = normalizeProfile({ id: ID, pawns_owned: "x", pawn: 7 });
    expect([r.pawns_owned, r.pawn]).toEqual([["classic"], "classic"]);
    const s = normalizeProfile({ id: ID, pawns_owned: ["classic", "trim"], pawn: "trim" });
    expect([ownsPawn(s, "trim"), ownsPawn(s, "crown"), ownsPawn(s, "nope"), equipped("pawn", s)]).toEqual([true, false, false, "trim"]);
  });
});

describe("pawn skins: buy and equip", () => {
  it("coins: pays the price once, owns and equips it", () => {
    const p = wallet(5000);
    const r = buy(p, "pawn", "marble");
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect([r.profile.coins, r.profile.pawns_owned, r.profile.pawn, r.price]).toEqual([1500, ["classic", "marble"], "marble", 3500]);
    expect(r.delta).toEqual({ coins: -3500, xp: 0, items: [{ kind: "pawn", id: "marble" }] });
    expect(p.coins).toBe(5000); // input untouched
    expect(buy(r.profile, "pawn", "marble")).toEqual({ ok: false, error: "owned" });
  });

  it("errors: unknown, owned (Classic), coins (+short), gems_only for coins; nothing changes", () => {
    const p = wallet(1000);
    expect(buy(p, "pawn", "nope")).toEqual({ ok: false, error: "unknown" });
    expect(buy(p, "pawn", "classic")).toEqual({ ok: false, error: "owned" });
    expect(buy(p, "pawn", "teacup")).toEqual({ ok: false, error: "coins", short: 5000 });
    expect(buy(wallet(1_000_000), "pawn", "knight")).toEqual({ ok: false, error: "gems_only" });
    expect(buy(wallet(1_000_000, 0), "pawn", "knight", "gems")).toEqual({ ok: false, error: "gems", short: item("pawn", "knight")!.gems });
  });

  it("gems: a gem-only skin pays its own gem price, a coin skin ceil(price / 100); coins untouched", () => {
    const crown = item("pawn", "crown")!.gems!;
    const r = buy(wallet(100, 500), "pawn", "crown", "gems");
    expect(r.ok && [r.profile.gems, r.profile.coins, r.profile.pawn, r.delta.gems]).toEqual([500 - crown, 100, "crown", -crown]);
    const t = buy(wallet(0, 500), "pawn", "trim", "gems");
    expect(t.ok && [t.profile.gems, t.profile.pawns_owned]).toEqual([500 - 20, ["classic", "trim"]]);
  });

  it("equip: owned skins only; unknown 'unknown', not owned 'locked'", () => {
    const b = buy(wallet(5000), "pawn", "trim");
    expect(b.ok).toBe(true);
    if (!b.ok) return;
    const e1 = equip(b.profile, "pawn", "classic");
    expect(e1.ok && [e1.profile.pawn, e1.changed]).toEqual(["classic", true]);
    if (!e1.ok) return;
    const e2 = equip(e1.profile, "pawn", "trim");
    expect(e2.ok && e2.profile.pawn).toBe("trim");
    expect(equip(e1.profile, "pawn", "crown")).toEqual({ ok: false, error: "locked" });
    expect(equip(e1.profile, "pawn", "nope")).toEqual({ ok: false, error: "unknown" });
    const same = equip(b.profile, "pawn", "trim");
    expect(same.ok && same.changed).toBe(false);
  });

  it("import: coin skins that exist are kept; gem-only and unknown skins dropped; the equipped one checked", () => {
    const base = newProfile(ID);
    const r = importProfile({ pawns_owned: ["marble", "crown", "nope", "marble"], pawn: "crown" }, base, "2026-10-31", 1_800_000_000);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect([r.profile.pawns_owned, r.profile.pawn]).toEqual([["classic", "marble"], "classic"]);
    expect(r.notes).toEqual(expect.arrayContaining(['pawns_owned: dropped "crown"', 'pawns_owned: dropped "nope"', 'pawn: "crown" -> "classic"']));
  });
});

describe("pawn skins: the wallet endpoints", () => {
  it("buy with coins and gems, equip; one ledger row each; the profile keeps them", async () => {
    const a = await guest();
    await setAccount(a.id, { coins: 5000, gems: 300 });
    const r = await ok("shop/buy", { session: a.session, body: { kind: "pawn", id: "kitty" } });
    expect(r).toMatchObject({ ok: true, price: 5000, item: { kind: "pawn", id: "kitty" } });
    expect(r.profile).toMatchObject({ coins: 0, pawn: "kitty", pawns_owned: ["classic", "kitty"] });
    expect(await v1("shop/buy", { session: a.session, body: { kind: "pawn", id: "glitter" } })).toMatchObject({ status: 409, body: { error: "gems_only" } });
    const g = await ok("shop/buy", { session: a.session, body: { kind: "pawn", id: "glitter", currency: "gems" } });
    expect(g.profile).toMatchObject({ coins: 0, gems: 300 - item("pawn", "glitter")!.gems!, pawn: "glitter" });
    expect(await v1("shop/equip", { session: a.session, body: { kind: "pawn", id: "knight" } })).toMatchObject({ status: 409, body: { error: "locked" } });
    expect(await v1("shop/equip", { session: a.session, body: { kind: "pawn", id: "nope" } })).toMatchObject({ status: 404, body: { error: "unknown" } });
    expect((await ok("shop/equip", { session: a.session, body: { kind: "pawn", id: "kitty" } })).profile.pawn).toBe("kitty");
    const me = (await ok("me", { session: a.session })).profile;
    expect([me.pawn, me.pawns_owned]).toEqual(["kitty", ["classic", "kitty", "glitter"]]);
    const led = await rows("SELECT ref, delta_coins, delta_gems FROM ledger WHERE account_id = ? AND reason = 'buy' ORDER BY id", a.id);
    expect(led).toEqual([
      { ref: "pawn:kitty", delta_coins: -5000, delta_gems: 0 },
      { ref: "pawn:glitter", delta_coins: 0, delta_gems: -item("pawn", "glitter")!.gems! },
    ]);
  });

  it("parallel purchases of the same skin buy it once; of two skins, only what the coins allow", async () => {
    const a = await guest();
    const rs = await Promise.all([0, 1, 2, 3].map(() => v1("shop/buy", { session: a.session, body: { kind: "pawn", id: "trim" } })));
    expect(rs.filter((r) => r.status === 200)).toHaveLength(1);
    expect(rs.filter((r) => r.body.error === "owned")).toHaveLength(3);
    expect((await ok("me", { session: a.session })).profile.coins).toBe(500);
    const b = await guest();
    await setAccount(b.id, { coins: 6000 });
    const two = await Promise.all(["marble", "teacup"].map((id) => v1("shop/buy", { session: b.session, body: { kind: "pawn", id } })));
    const paid = two.filter((r) => r.status === 200);
    expect(paid).toHaveLength(1);
    const me = (await ok("me", { session: b.session })).profile;
    expect(me.coins).toBe(6000 - paid[0].body.price);
    expect(me.pawns_owned).toHaveLength(2);
    expect(await rows("SELECT * FROM ledger WHERE account_id = ? AND reason = 'buy'", b.id)).toHaveLength(1);
    expect(await ledgerSum(a.id)).toBe(500);
  });
});
