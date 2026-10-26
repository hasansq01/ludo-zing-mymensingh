// Economy v1: gem prices, gems / rerolls on the profile, and buying with gems.
import { describe, expect, it } from "vitest";
import { CATALOG, buy, newProfile, normalizeProfile, type Profile } from "../src/econ";

const ID = "LZM-AAAA-BBBB";
function rich(gems: number, coins = 100): Profile {
  const p = newProfile(ID);
  p.gems = gems;
  p.coins = coins;
  return p;
}

describe("gems and rerolls on the profile", () => {
  it("new profile: 2,500 coins, 0 gems, 0 rerolls", () => {
    const p = newProfile(ID);
    expect([p.coins, p.gems, p.rerolls]).toEqual([2500, 0, 0]);
  });
  it("normalizes like coins", () => {
    const p = normalizeProfile({ id: ID, coins: 700, gems: -3, rerolls: 40 });
    expect([p.coins, p.gems, p.rerolls]).toEqual([700, 0, 9]);
    const q = normalizeProfile({ id: ID, gems: "12", rerolls: -1 });
    expect([q.gems, q.rerolls]).toEqual([12, 0]);
    const r = normalizeProfile({ id: ID, gems: null, rerolls: [] });
    expect([r.gems, r.rerolls]).toEqual([0, 0]);
  });
});

describe("catalog gem prices", () => {
  it("every item sold for coins has ceil(price / 100) gems, others none", () => {
    for (const it of CATALOG.items) {
      if (it.buy && it.price > 0) expect(it.gems, `${it.kind}:${it.id}`).toBe(Math.ceil(it.price / 100));
      else expect(it.gems, `${it.kind}:${it.id}`).toBeUndefined();
    }
    expect(CATALOG.items.some((it) => it.gems !== undefined)).toBe(true);
  });
});

describe("buy with gems", () => {
  it("room: pays gems, coins and coinsEarned untouched", () => {
    const p = rich(100, 123);
    const r = buy(p, "room", "dream", "gems");
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.price).toBe(30);
    expect(r.profile.gems).toBe(70);
    expect(r.profile.coins).toBe(123);
    expect(r.profile.stats.coinsEarned).toBe(p.stats.coinsEarned);
    expect(r.profile.room).toBe("dream");
    expect(r.delta).toMatchObject({ coins: 0, xp: 0, gems: -30, items: [{ kind: "room", id: "dream" }] });
    expect(p.gems).toBe(100);
  });
  it("short of gems", () => {
    const r = buy(rich(10, 99999), "room", "dream", "gems");
    expect(r).toEqual({ ok: false, error: "gems", short: 20 });
  });
  it("coins default is unchanged and gems are not used", () => {
    const r = buy(rich(1000, 99999), "dice", "crema");
    expect(r.ok && r.profile.coins === 98999 && r.profile.gems === 1000 && r.delta.gems === undefined).toBe(true);
  });
  it("owned and free items are refused before the price", () => {
    expect(buy(rich(0), "room", "night", "gems")).toEqual({ ok: false, error: "owned" });
    expect(buy(rich(0), "dice", "classic", "gems")).toEqual({ ok: false, error: "owned" });
    expect(buy(rich(0), "char", "ch-arif", "gems")).toMatchObject({ ok: false });
    expect(buy(rich(0), "room", "nope", "gems")).toEqual({ ok: false, error: "unknown" });
    const r = buy(rich(100), "dice", "crema", "gems");
    if (!r.ok) throw new Error("buy");
    expect(buy(r.profile, "dice", "crema", "gems")).toEqual({ ok: false, error: "owned" });
  });
  it("emote pack and S&L scene", () => {
    const e = buy(rich(40), "emotes", "friends", "gems");
    expect(e.ok && e.price === 40 && e.profile.gems === 0 && e.profile.emote_set === "friends").toBe(true);
    const s = buy(rich(300), "scene", "frost", "gems");
    expect(s.ok && s.price === 200 && s.profile.gems === 100 && s.profile.scene === "frost").toBe(true);
  });
  it("character", () => {
    const ch = CATALOG.items.find((i) => i.kind === "char" && i.price > 0)!;
    const r = buy(rich(500), "char", ch.id, "gems");
    expect(r.ok && r.price === Math.ceil(ch.price / 100) && r.profile.avatar === ch.id).toBe(true);
    expect(buy(rich(5), "char", ch.id, "gems")).toMatchObject({ ok: false, error: "gems" });
  });
  it("unlock-only kinds stay locked / owned", () => {
    expect(buy(rich(999), "avatar", "dice", "gems")).toEqual({ ok: false, error: "locked" });
    expect(buy(rich(999), "frame", "classic", "gems")).toEqual({ ok: false, error: "owned" });
  });
});
