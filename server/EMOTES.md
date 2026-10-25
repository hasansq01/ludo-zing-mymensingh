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
- Quick-match ghosts react like people: see "Ghost behaviour" below. Indistinguishable from a person's emote.

## Ghost behaviour (BOT-EMO; `src/ghosts.ts`, driven by `src/room.ts`)
Policy is the pure, seeded `ghostEmoteReply(situation, persona, memory, trigger, rng, pack) -> {id, delayMs} | null`
(it updates `memory`); the Room only builds the situation, stores `persona` and `emo` (memory, plain JSON) on the
ghost's Member (so both survive eviction), and sends the planned emote through the match alarm (`gemotes`). Wire shape
is `{t:"emote", c, id}` exactly like a person's; persona and memory are never sent (the admin snapshot shows the persona).
- Triggers: own capture / being captured / a 6 / finishing; a person's emote (only one ghost answers); another ghost's
  emote (about 5%, at most once per match per other ghost); an opening "hi" early in the match (once, chatty and
  friendly only).
- Replies come from a weighted pool per incoming emote or event (including a "no reply" weight), restricted to the
  packs the ghost owns (starter + one paid; falls back to a generic pool inside the owned packs), never one of its last
  3 emotes. Sad emotes (cry, sad, sob) get a cheeky or a friendly answer, by personality, cheeky after the ghost just
  captured someone.
- Situation: ahead in the race (progress lead > 8%) boosts cool/tease/crown/laugh/champ/party, behind boosts
  cry/sad/facepalm/sob/flag; within 15 s after its own capture gloat emotes get x2; within 15 s after being captured
  angry/cry/facepalm/sob get x2.5 and love/happy/hi x0.3.
- Spam: heat rises by 1 per person's emote, cools 1 per 30 s, is forgotten after 60 s of quiet. Reply chance for the
  1st / 2nd / 3rd / later = 60% / 28% / 11% / 0% (x persona factor). At the 4th it may say "ok, enough" (facepalm or
  sleepy, if owned), then stays quiet for 45-90 s.
- Conversations: with one person it replies 1-3 times (random), then ignores that person for 60-120 s; a conversation
  idle for 40 s starts over.
- Timing: 1.0-3.5 s; on its own turn +0.5-1.5 s, or (35%) +3-5.5 s (after its move). Obeys the humans' limits (1 per
  2 s, 6 per 30 s) plus its own pace (persona gap 4-12 s).
- Personas (hidden, chosen at seat time; the ghosts of one match differ):
  | persona | answers a person | events | own gap | opens with hi | bias |
  |---|---|---|---|---|---|
  | chatty | x1.4 | x1.2-1.6 | 4 s | 45% | hi, happy, party, wow, cheer |
  | quiet | x0.5 | x0.3-0.6 | 12 s | 0 | cool, happy, hi; less tease/angry |
  | cheeky | x1.0 | capture x1.6 | 6 s | 0 | tease, cool, crown, laugh, champ |
  | friendly | x1.2 | finish x1.3, capture x0.6 | 5 s | 10% | love, hi, happy, highfive, cheer |
  | sore | x0.9 | captured x1.8, rest x0.6-0.8 | 6 s | 0 | angry, facepalm, cry, sob, sad, flag |
- Test hook `emoteChance` (TEST_MODE only): 0 = silence; 1 = every random gate passes (reply chance, spam, conversation
  end, "no reply"), while pools, no-repeat, owned packs and the rate limits still apply.

## Sounds (E-SFX)
`Sound.emote(id)` plays that emote's short sound (soft, calm mix, respects the sound settings); files in
`godot/assets/audio/emotes/<id>.ogg|wav`. Callers guard with `has_method`.

## In-game (E-HUD)
Picker button above your avatar, picker panel at the left of the board (equipped pack, 6 cells, 2 s cooldown after a
send), reactions pop beside the sender's dice/avatar (≈2.4 s, queue of 2 per player), in Ludo and S&L, 3D and Top
view, all seat positions. Offline: computer players react (capture / being captured / win), throttled (9 s per CPU,
4 s overall, never the same twice running). Pass & Play: the sender is the player to move.
