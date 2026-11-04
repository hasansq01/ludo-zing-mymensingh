// S&L state hash (PROTOCOL.md "S&L state hash"): FNV-1a 32-bit over the UTF-8 bytes of a canonical string, as 8
// lowercase hex digits (the same FNV as the Ludo hash). The GDScript twin is godot/scripts/net/sl_state_hash.gd
// (SLStateHash.of); both are tested on shared traces (test/rules_sl_parity.test.ts).
//
//   turn | phase | sixes | winner | need_one ("0"/"1") | players | finished
//
// players: one "c.pos.cpu.ladders.snakes.rolls" per player in array (turn) order, comma-joined, where cpu is "0"/"1"
// and rolls is every recorded roll as one digit, concatenated ("" before the first roll). finished: the player
// indices in finish order, comma-joined ("" when none / missing).
// mode, paid, name and you are not hashed. Every number goes through Math.trunc (GDScript int()).

import type { SlState } from "./sl";
import { fnv1a32 } from "./hash";

const int = (x: unknown): string => String(Math.trunc(Number(x)));
const bit = (x: unknown): string => (x ? "1" : "0");

/** The canonical string that slStateHash() hashes. */
export function slStateHashInput(s: SlState): string {
  const players = s.players.map(
    (p) =>
      `${int(p.c)}.${int(p.pos)}.${bit(p.cpu)}.${int(p.ladders)}.${int(p.snakes)}.${(p.rolls ?? []).map(int).join("")}`,
  );
  const finished = (Array.isArray(s.finished) ? s.finished : []).map(int).join(",");
  return [int(s.turn), String(s.phase), int(s.sixes), int(s.winner), bit(s.need_one ?? false), players.join(","), finished]
    .join("|");
}

export function slStateHash(s: SlState): string {
  return fnv1a32(slStateHashInput(s));
}
