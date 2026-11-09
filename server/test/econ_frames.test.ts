// Frames (Collection.FRAMES, kind "frame"): some sold for coins (also gems), some for gems only, some earned. Buying
// lists the frame in av_owned and puts it in use; earned frames still refuse to be bought; the import keeps coin frames.
// Nameplates (Collection.PLATES) sell the same way.
import { describe, expect, it } from "vitest";
import { buy, equip, equipped, importProfile, isUnlocked, item, items, newProfile, type Profile } from "../src/econ";

const ID = "LZM-AAAA-BBBB";
function wallet(coins: number, gems = 0): Profile {
  const p = newProfile(ID);
  p.coins = coins;
  p.gems = gems;
  return p;
}

describe("frames: catalogue", () => {
  it("Wood is free; coin frames carry gems; gem-only frames have no coin price; earned ones are unlock-only", () => {
    expect(item("frame", "classic")).toMatchObject({ price: 0, free: true, default: true });
    const fs = items("frame");
    const coin = fs.filter((f) => f.price > 0);
    const gemOnly = fs.filter((f) => f.price === 0 && (f.gems ?? 0) > 0);
    const earned = fs.filter((f) => f.unlock);
    expect(coin.map((f) => f.id).sort()).toEqual(["ludo", "rose", "silver"]);
    expect(gemOnly.map((f) => f.id).sort()).toEqual(["diamond", "ice", "rickshaw", "wings"]);
    expect(earned.map((f) => f.id).sort()).toEqual(["gold", "mint", "royal"]);
    for (const f of coin) expect([f.buy, f.gems]).toEqual([true, Math.ceil(f.price / 100)]);
  });
});

describe("frames: buying", () => {
  it("coins: pays, owns, puts it in use; a second buy is 'owned'", () => {
    const r = buy(wallet(5000), "frame", "rose");
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect([r.profile.coins, r.profile.av_owned, r.profile.frame, r.price]).toEqual([1000, ["rose"], "rose", 4000]);
    expect([isUnlocked("frame", "rose", r.profile), equipped("frame", r.profile)]).toEqual([true, "rose"]);
    expect(buy(r.profile, "frame", "rose")).toEqual({ ok: false, error: "owned" });
  });

  it("not enough coins: says how many are short and changes nothing", () => {
    const p = wallet(1000);
    expect(buy(p, "frame", "ludo")).toEqual({ ok: false, error: "coins", short: 5000 });
    expect([p.coins, p.av_owned]).toEqual([1000, []]);
  });

  it("gem-only frames refuse coins and sell for their gems", () => {
    expect(buy(wallet(99999, 500), "frame", "wings")).toEqual({ ok: false, error: "gems_only" });
    expect(buy(wallet(0, 100), "frame", "wings", "gems")).toEqual({ ok: false, error: "gems", short: 20 });
    const r = buy(wallet(0, 130), "frame", "wings", "gems");
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect([r.profile.gems, r.profile.coins, r.profile.av_owned, r.profile.frame, r.delta.gems]).toEqual([10, 0, ["wings"], "wings", -120]);
  });

  it("coin frames can be paid in gems too", () => {
    const r = buy(wallet(0, 20), "frame", "silver", "gems");
    expect(r.ok && [r.profile.gems, r.profile.frame]).toEqual([5, "silver"]);
  });

  it("earned frames: locked until earned, then owned; Wood is owned; unknown ids are unknown", () => {
    expect(buy(wallet(99999), "frame", "gold")).toEqual({ ok: false, error: "locked" });
    const lv = wallet(0);
    lv.xp = 100000;
    expect(buy(lv, "frame", "gold")).toEqual({ ok: false, error: "owned" });
    expect(buy(wallet(0), "frame", "classic")).toEqual({ ok: false, error: "owned" });
    expect(buy(wallet(99999), "frame", "nope")).toEqual({ ok: false, error: "unknown" });
  });

  it("equip: only a bought frame", () => {
    expect(equip(wallet(0), "frame", "diamond")).toMatchObject({ ok: false, error: "locked" });
    const p = wallet(0);
    p.av_owned = ["diamond"];
    expect(equip(p, "frame", "diamond")).toMatchObject({ ok: true });
  });
});

describe("nameplates: sold like frames", () => {
  it("coin plates pay and equip; gem-only plates refuse coins; earned plates stay locked", () => {
    const r = buy(wallet(4000), "plate", "scroll");
    expect(r.ok && [r.profile.coins, r.profile.av_owned, r.profile.plate]).toEqual([1000, ["scroll"], "scroll"]);
    expect(buy(wallet(99999, 500), "plate", "neon")).toEqual({ ok: false, error: "gems_only" });
    const g = buy(wallet(0, 130), "plate", "crystal", "gems");
    expect(g.ok && [g.profile.gems, g.profile.plate]).toEqual([10, "crystal"]);
    expect(buy(wallet(99999), "plate", "ruby")).toEqual({ ok: false, error: "locked" });
    expect(buy(wallet(0), "plate", "plain")).toEqual({ ok: false, error: "owned" });
  });

  it("plate ids never repeat a frame's or a character's (they share av_owned)", () => {
    const plates = items("plate").map((p) => p.id);
    const others = [...items("frame"), ...items("char"), ...items("avatar")].map((p) => p.id);
    expect(plates.filter((id) => others.includes(id))).toEqual([]);
  });
});

describe("frames: import", () => {
  it("keeps paid characters and coin frames, drops gem-only frames and junk", () => {
    const base = newProfile(ID);
    const r = importProfile({ av_owned: ["ch-rafi", "silver", "wings", "nope", "silver", 3, "scroll", "neon"], frame: "silver" }, base, "2026-10-31", 1_800_000_000);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.profile.av_owned).toEqual(["ch-rafi", "silver", "scroll"]);
    expect(r.profile.frame).toBe("silver");
  });
});
