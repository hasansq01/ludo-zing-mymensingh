# Ludo Zing Mymensingh: Godot version

The Android (Google Play) version of the game, being rebuilt in **Godot 4.7** from the web version (`../index.html`).
The web version stays the reference until the Godot version matches it.

## Layout
| Path | Purpose |
|---|---|
| `project.godot` | Portrait 390×844 base size (stretch canvas_items / expand), GL Compatibility renderer, 32-bit 4096 shadow atlas, autoloads `Save` and `Sound`. |
| `scenes/main.tscn`, `scripts/main.gd` | The app: splash with real loading progress, screens (home / Ludo / Snakes & Ladders), sheets, pause and win flow, Android back button and app pause, safe area, debug autoplay. |
| `scripts/core/` | Pure logic: `ludo_rules.gd`, `snakes_ladders_rules.gd`, `save.gd` (autoload, user://save.json), `catalog.gd` (shop), `rewards.gd` (daily reward, spin, free coins). |
| `scripts/game/` | `LudoMatch`, `SLMatch`: drive the rules, animate their events, play the computers. |
| `scripts/world/` | 3D: `TableWorld` (table, cups, lights, camera), `Rooms` + `rooms/*.gd` (five room themes and their moods), `LudoBoard`, `SLBoard`, `MeshKit` (rounded box, lathe, materials), `TexBaker` (GPU-painted textures, mipmapped). |
| `scripts/ui/` | `UIKit` (fonts, buttons, styles), `Sheet` (modal base), HUDs, home, setup, splash, confetti, 3D dice, logo; `sheets/` for settings, profile, how to play, shop, inventory, daily reward, spin. |
| `scripts/audio/sound.gd` | Autoload `Sound`: effects pool, music loop, buses. Sounds are synthesised offline by `tools/gen_audio.gd` into `assets/audio/`. |
| `assets/` | Fonts (Lilita One, Nunito variable), SVG art (logos, icons), app icon, audio. |
| `tests/` | Headless tests (ports of `../tests/*.js` plus turn-flow, shop and reward checks). |
| `dev/` | Desktop previews and the integration driver (not exported). |

## Rules design (why it looks like this)
The rules are pure functions over a plain Dictionary state: no nodes, timers or animation, and dice values are
passed in. `apply_roll`, `choose_pick`, `move` and `answer_pair` change the state and return events
(`rolled`, `move`, `capture`, `split`, `pair_offer`, `turn`, `game_over`, ...) that the 3D scene will animate.
This keeps three things possible: tests without a scene, saving a game as JSON, and online multiplayer, where the
server rolls the dice and runs the same rules as referee (planned: a Nakama server module, checked against these
same test cases).

Human-only steps are phases: `pick` (Single or Pair?) and `pair_ask` (make a pair?). A computer never stops in
them: it uses `pick_ai` and pairs up off safe squares. `auto_move_token` is the web version's "only one option
moves by itself" convenience.

## Renderer and lighting
- GL Compatibility (OpenGL ES 3): the Android emulator on Apple silicon shows a black screen with the Vulkan Mobile
  renderer, and Compatibility suits cheap phones. Desktop previews use the same renderer, so they match the phone.
- Lighting is ported from the web version's values (index.html MOOD + Rooms): hemisphere light as a flat ambient
  (sky/ground mean), the key spot from (4, 60, 10) with its cone and penumbra, the rooms' point lights, no tone
  mapping, no post-processing. Intensities were calibrated against web screenshots by sampling the same pixels
  (key x0.647, point lights x10: see Rooms.KEY_SCALE and Rooms._omni). Glow sprites must never cast shadows.

## Build for Android
```bash
tools/android-build.sh --run        # from the repo root: checks scripts, exports build/android/ludo-zing-debug.apk,
                                    # installs on the running emulator/device and launches it
```
Play Store build: `tools/android-release.sh` makes the signed App Bundle `build/android/ludo-zing-release.aab`
(Gradle; the Android build template is unpacked in `godot/android/build/`, not tracked). The upload key is kept
outside the repo in `~/.android/ludo-zing-release/` (created 2026-10-24; back it up: every update must be signed
with it, or reset it through Play App Signing). Bump `version/code` before each upload.

Debug soak test on a device: `adb shell "run-as com.flipfold.ludozing sh -c 'echo all > files/autoplay.txt'"`, restart
the app: it plays Ludo, Pair Mode and Snakes & Ladders games back to back and logs `[ludo]` / `[sl]` results.

## Run the tests
```bash
tools/godot-test.sh            # from the repo root; exit code 1 on any failure
```
or `godot --headless --path godot -s res://tests/run_tests.gd`.

Not ported yet: the browser tests that check the HTML interface (S&L landing, popups, pause, win card), the
visual home-screen test, daily rewards, shop preview and info icons. They come back with the Godot screens.
