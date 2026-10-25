// Buying and equipping (Catalog.buy_room / buy_dice, SLScenes.buy_scene, Collection.buy_char, the equip functions).
// The checks run in the game's order; nothing changes on an error. Purchases equip the item, as the Shop does
// (rooms, dice and scenes by default, characters with equip_it = true).
import { FREE_DICE, item } from "./catalog";
import { clone, getInt, list, str } from "./gd";
import {
  type Delta,
  type Profile,
  coinsOf,
  isUnlocked,
  ownsDice,
  ownsRoom,
  ownsScene,
  sceneIds,
} from "./profile";

export type BuyError = "unknown" | "owned" | "coins" | "locked";

export type BuyResult =
  | { ok: true; profile: Profile; delta: Delta; price: number }
  | { ok: false; error: BuyError; /** Coins still missing (error "coins"). */ short?: number };

/**
 * POST /v1/shop/buy {kind, id}.
 *   unknown  no such item (or a kind the Shop doesn't sell)
 *   owned    already owned, or free for everyone (Arif, Nadia, the free rooms / dice / scene)
 *   coins    not enough coins
 *   locked   an unlock-only item (avatar, frame, plate, badge) that isn't unlocked yet; when it is, "owned"
 */
export function buy(profile: Profile, kind: string, id: string): BuyResult {
  switch (kind) {
    case "room":
    case "dice":
    case "scene": {
      const it = item(kind, id);
      if (!it) return { ok: false, error: "unknown" };
      const owned = kind === "room" ? ownsRoom(profile, id) : kind === "dice" ? ownsDice(profile, id) : ownsScene(profile, id);
      if (owned) return { ok: false, error: "owned" };
      return pay(profile, kind, id, it.price, (p) => {
        if (kind === "room") {
          const rooms = list(p, "rooms");
          rooms.push(id);
          p.rooms = rooms;
          p.room = id;
        } else if (kind === "dice") {
          const dice = list(p, "dice_owned");
          if (!dice.includes(FREE_DICE)) dice.unshift(FREE_DICE);
          dice.push(id);
          p.dice_owned = dice;
          p.dice = id;
        } else {
          const scenes = sceneIds(p);
          scenes.push(id);
          p.scenes = scenes;
          p.scene = id;
        }
      });
    }
    case "char": {
      const it = item("char", id);
      if (!it) return { ok: false, error: "unknown" };
      if (it.price <= 0) return { ok: false, error: "owned" };
      if (isUnlocked("char", id, profile)) return { ok: false, error: "owned" };
      return pay(profile, kind, id, it.price, (p) => {
        const owned = list(p, "av_owned");
        owned.push(id);
        p.av_owned = owned;
        p.avatar = id;
      });
    }
    case "avatar":
    case "frame":
    case "plate":
    case "badge": {
      const exists = kind === "badge" ? id === "" || item("badge", id) !== undefined : item(kind, id) !== undefined;
      if (!exists) return { ok: false, error: "unknown" };
      return { ok: false, error: isUnlocked(kind, id, profile) ? "owned" : "locked" };
    }
  }
  return { ok: false, error: "unknown" };
}

function pay(profile: Profile, kind: string, id: string, price: number, add: (p: Profile) => void): BuyResult {
  const have = coinsOf(profile);
  if (have < price) return { ok: false, error: "coins", short: price - have };
  const p = clone(profile);
  p.coins = getInt(p, "coins", 0) - price;
  add(p);
  return { ok: true, profile: p, delta: { coins: -price, xp: 0, items: [{ kind, id }] }, price };
}


// ---------- equipping ----------

export type EquipKind = "room" | "dice" | "scene" | "avatar" | "char" | "frame" | "plate" | "badge";

export type EquipResult = { ok: true; profile: Profile; changed: boolean } | { ok: false; error: "unknown" | "locked" };

const FIELD: Record<string, string> = { avatar: "avatar", char: "avatar", frame: "frame", plate: "plate", badge: "badge" };

/**
 * Puts an owned / unlocked item in use (PATCH /v1/me {avatar?, frame?, plate?, badge?}, and rooms / dice / scenes).
 * Catalog.equip_room / equip_dice, SLScenes.equip_scene, Collection.equip. Badge "" = no badge.
 */
export function equip(profile: Profile, kind: string, id: string): EquipResult {
  const p = profile;
  switch (kind) {
    case "room":
    case "dice": {
      if (!item(kind, id)) return { ok: false, error: "unknown" };
      if (!(kind === "room" ? ownsRoom(p, id) : ownsDice(p, id))) return { ok: false, error: "locked" };
      if (str(p[kind]) === id) return { ok: true, profile: p, changed: false };
      const q = clone(p);
      q[kind] = id;
      return { ok: true, profile: q, changed: true };
    }
    case "scene": {
      if (!item("scene", id)) return { ok: false, error: "unknown" };
      if (!ownsScene(p, id)) return { ok: false, error: "locked" };
      if (str(p.scene) === id && Array.isArray(p.scenes)) return { ok: true, profile: p, changed: false };
      const q = clone(p);
      q.scenes = sceneIds(q);
      q.scene = id;
      return { ok: true, profile: q, changed: true };
    }
    case "avatar":
    case "char":
    case "frame":
    case "plate":
    case "badge": {
      if (!isUnlocked(kind, id, p)) {
        const known =
          kind === "badge" ? id === "" || item("badge", id) !== undefined
          : kind === "avatar" || kind === "char" ? item("avatar", id) !== undefined || item("char", id) !== undefined
          : item(kind, id) !== undefined;
        return { ok: false, error: known ? "locked" : "unknown" };
      }
      const field = FIELD[kind];
      if (str(p[field]) === id && field in p) return { ok: true, profile: p, changed: false };
      const q = clone(p);
      q[field] = id;
      return { ok: true, profile: q, changed: true };
    }
  }
  return { ok: false, error: "unknown" };
}
