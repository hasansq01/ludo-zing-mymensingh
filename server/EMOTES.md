# Emotes: shared contract (2026-10-25)

Ported from the web version on `origin/feature/emotes` (index.html `EMOTES`, `EMOTE_SETS`, `Emotes`). 24 animated
stickers in 4 packs of 6. Commits go to main; the branch is ported, not merged.

## Ids
| pack id | name | price | emotes (in order) |
|---|---|---|---|
| `starter` | Starter Set | 0 (free, owned + equipped by default) | happy, laugh, cool, angry, love, party |
| `pawns` | Pawn Pals | 2,500 | champ, sleepy, sob, gasp, confused, hi |
| `friends` | Friends Set | 4,000 | cry, wow, facepalm, cheer, think, tease |
| `game` | Game Set | 3,500 | dice, crown, highfive, flag, sad, peek |

Display names come from the branch's `EMOTES` table (Victory = happy, Celebrate = party, Shocked = wow, Yay! = cheer,
Thinking = think, Roll it! = dice, Winner = crown, Give up = flag, Disappointed = sad, Peek-a-boo = peek, …); the
manifest `godot/assets/emotes/emotes.json` is the source of truth for names, frames and fps.

## Art (EMO-ART)
`godot/assets/emotes/<id>/NNN.webp` frames + `icon.webp`, manifest `emotes.json`; `EmoteArt` (scripts/ui/emote_art.gd):
`frames(id) -> SpriteFrames`, `icon(id) -> Texture2D`, `manifest() -> Dictionary`.

## Profile (game Save.profile and the server profile, same keys)
- `emote_sets: Array[String]` owned packs, always includes `"starter"`.
- `emote_set: String` equipped pack (default `"starter"`). Only the equipped pack's 6 emotes appear in the picker.
- Buy / equip through the server wallet: `POST /v1/shop/buy {kind: "emotes", id: <pack>}`,
  `POST /v1/shop/equip {kind: "emotes", id: <pack>}` (buy also equips, like other items).
- GDScript helper (E-SHOP): `scripts/core/emotes.gd` class `Emotes`: `packs() -> Array` (manifest order),
  `pack(id)`, `pack_of(emote_id)`, `owned_packs()`, `equipped_pack()`, `equipped_ids() -> Array[String]`,
  `owns_emote(emote_id) -> bool`.

## Online relay (protocol v1 addition)
- Client → server: `{t: "emote", id}` (any time during a match; also in the lobby is fine).
- Server → others (not the sender): `{t: "emote", c, id}` where `c` = the sender's colour (lobby: `c` = -1 and
  `member` = id). The sender shows its own reaction locally at once.
- Server checks: the member's account owns the pack containing `id` (starter always), and a rate limit of 1 emote per
  2 s and 6 per 30 s per member; violations → `{t: "error", code: "emote_locked" | "emote_rate"}` (clients ignore
  quietly). Emotes never touch game state, `n` or the hash.
- Quick-match ghosts react like people: occasionally (≈25%) after their own capture, being captured, a 6, finishing, or
  a human's emote ("reply"), with 0.8–2.5 s delay, at most one per 8 s per ghost; each ghost "owns" starter plus one
  random paid pack. Indistinguishable from a person's emote.

## Sounds (E-SFX)
`Sound.emote(id)` plays that emote's short sound (soft, calm mix, respects the sound settings); files in
`godot/assets/audio/emotes/<id>.ogg|wav`. Callers guard with `has_method`.

## In-game (E-HUD)
Picker button above your avatar, picker panel at the left of the board (equipped pack, 6 cells, 2 s cooldown after a
send), reactions pop beside the sender's dice/avatar (≈2.4 s, queue of 2 per player), in Ludo and S&L, 3D and Top
view, all seat positions. Offline: computer players react (capture / being captured / win), throttled (9 s per CPU,
4 s overall, never the same twice running). Pass & Play: the sender is the player to move.
