// State hash (PROTOCOL.md "State hash"): FNV-1a 32-bit over the UTF-8 bytes of a canonical string, as 8 lowercase
// hex digits. The GDScript twin is godot/scripts/net/state_hash.gd (StateHash.of); both are tested on shared traces.
//
//   tok(16 ints, colour-major) | pairs ("c.a.b") | turn | dice | sixes | phase | winner | free ("0"/"1" x4) |
//   finished | players | pending ("" or "c.i.to.extra(0/1).partner", partner -1 if absent)
//
// names, view, teams, pair_ask and pick are not hashed.

import type { LudoState } from "./ludo";

const int = (x: unknown): string => String(Math.trunc(Number(x)));
const bit = (x: unknown): string => (x ? "1" : "0");

/** The canonical string that stateHash() hashes. */
export function stateHashInput(s: LudoState): string {
  const tok: string[] = [];
  for (let c = 0; c < 4; c++) for (let i = 0; i < 4; i++) tok.push(int(s.tok[c][i]));
  const pairs = (s.pairs ?? []).map((q) => `${int(q.c)}.${int(q.a)}.${int(q.b)}`);
  const free = [0, 1, 2, 3].map((c) => bit(s.free?.[c])).join("");
  const finished = (s.finished ?? []).map(int);
  const p = (s.pending ?? {}) as Record<string, unknown>;
  const pending =
    Object.keys(p).length === 0
      ? ""
      : `${int(p.c)}.${int(p.i)}.${int(p.to)}.${bit(p.extra)}.${int(p.partner ?? -1)}`;
  return [
    tok.join(","),
    pairs.join(","),
    int(s.turn),
    int(s.dice),
    int(s.sixes),
    String(s.phase),
    int(s.winner),
    free,
    finished.join(","),
    s.players.join(","),
    pending,
  ].join("|");
}

/** FNV-1a 32 of a string's UTF-8 bytes, as 8 lowercase hex digits. */
export function fnv1a32(text: string): string {
  let h = 0x811c9dc5;
  for (const b of new TextEncoder().encode(text)) {
    h ^= b;
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return (h >>> 0).toString(16).padStart(8, "0");
}

export function stateHash(s: LudoState): string {
  return fnv1a32(stateHashInput(s));
}
