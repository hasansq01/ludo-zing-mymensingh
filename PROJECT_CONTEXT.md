# Ludo Zing Mymensingh — Project Context

Read this and `TASKS.md` before any major change, then inspect the relevant code in `index.html`.

> **LOCKED: the home screen** (approved 2026-10-19). Don't change its layout, camera settings (`HOME_TABLE_EL`,
> `TABLE_MAX_W`, `TABLE_DROP`, `HOME_GAPS`, `homeFit`), scene transforms, UI sizes, colours or spacing during unrelated
> work. After any change run `tests\visual\run.ps1` and report failures. Update the baseline only after the user approves
> a requested visual change (see `tests/visual/README.md`). Never update it just to make a test pass.
Update both files when a significant decision, feature or bug fix lands. Last reviewed: 2026-10-19 (after the visual redesign).

## What it is
A mobile-first 3D Ludo game for the browser, played on a round table inside a cozy room (four room themes). Built entirely with Claude.
Targets: YouTube Playables (main) and static hosting. Live: https://ludo-king-mymensingh.pages.dev
(Cloudflare Pages, free plan, project `ludo-king-mymensingh`, deployed by uploading the build zip).

## Technology
- One HTML file, `index.html` (~3,190 lines): inline CSS + plain JS in one IIFE. No framework, no bundler, no Node.
- three.js **r128** (CDN in source, local copy in the build). WebGL, PCF soft shadows, sRGB output (colours go through `lin()`),
  no tone mapping (keeps pastels clean); moderate light levels instead. No post-processing: "bloom" is additive soft sprites.
- Fonts: Lilita One (display), Nunito (body), Orbitron 700 (no longer used since the splash logo became the supplied SVG; still in the font list).
- Board, walls, rugs, skies, posters and latte art are drawn on canvas textures. Rounded furniture uses `rbox()` (bevelled
  extrusion with smoothed normals). Dice is a CSS 3D cube, not WebGL. No image assets are needed.
- Sound (2026-10-20): `Sound` module, Web Audio, everything synthesised (no audio files). Graph: voices -> effects bus /
  music bus -> master -> x1.6 makeup -> limiter (DynamicsCompressor, -6 dB, 12:1) -> speakers. Started by the first
  pointerdown / keydown (browser autoplay rules). It goes quiet (master gain 0, music stopped; never a context
  suspend) only when the page is hidden AND unfocused; every tap / key resumes it. Reason: the Claude app's browser
  pane reports `hidden` while the game is on screen and fires it right after taps; the first version suspended on
  `hidden` and stayed silent there (fixed 2026-10-20). YouTube mute / pause (`ytAudio`, `halted`) always win. Named effects via `sfx(name)`: tap, select, roll, land, step, six, capture, pair, split, coin, buy, home,
  ladder, snake, win, lose, error, tick; per-sound minimum gap + 24-voice cap. A global click listener plays `tap` for
  buttons / tabs / choices unless the handler already played a sound. Music: generated cozy loop (Fmaj7 Dm7 Bbmaj7 C6
  pad, soft bass, wandering music-box melody) scheduled ~1 s ahead. Measured peaks at default volume: effects 0.18-0.6,
  music ~0.1, everything at once 0.61 (old beeps peaked at 0.07). `Sound.peak()` reads the output level for tests.
- Celebrations: `Celebrate.run()` (2D canvas `.celebrate` over #stage, pointer-events none, removes itself ~3 s):
  burst / cannons / flares / rain, random, never the same twice in a row; on every Ludo and Snakes & Ladders win.
  `HomeFx.burst()` (three.js): gold + player-colour rings, glow, particles and rising sparkles where a pawn reaches the
  centre, once per arrival (a pair = one burst); disposed after 1.2 s; ticked from `frameLoop`.
- Build/test tooling is PowerShell (Windows): `tools/build.ps1`, `tools/serve.ps1`.

## File structure
| Path | Purpose |
|---|---|
| `index.html` | The whole game (source of truth). Also runs as a Claude artifact. Contains the `window.__ludo` test hook (also exposes `scene`, `renderer`, `Rooms` for visual checks). |
| `tools/build.ps1` | Builds `dist/` + `ludo-king-mymensingh-playables.zip`: local three.js and fonts, SDK script first, strips test hook, checks Playables limits. Re-downloads fonts when its font list changes (`vendor/fonts.query`). Writes the zip with .NET ZipFile and forward-slash entry names (PS 5.1 `Compress-Archive` wrote `fonts\x.woff2`, which Cloudflare served as a literal backslash name, so fonts 404'd on every deploy before 2026-10-19). |
| `tools/serve.ps1` | Static server for `dist/` on http://localhost:8080. |
| `tests/visual/` | Home-screen regression safeguard: `run.ps1` (build + headless Chrome over DevTools + pixel diff), `vt-checks.js` (layout + locked numbers), `baseline/home-390x844.png` + `APPROVALS.md`. |
| `tests/pair-rules.js` | 25 pair/regression rule tests; paste into the console on the **source** page (needs the test hook). |
| `tests/pair-capture-split.js` | 151 pair capture + home-lane split tests with real forced rolls and moves, all four colours; source page with `?vt=1`. |
| `tests/snakes-ladders.js` | 46 Snakes & Ladders tests (board data, landing rule, real turns with forced dice, rewards); source page with `?vt=1`. |
| `tests/team-rules.js` | 28 Pair Mode (teams) + Free Hand tests, partly with real forced rolls; run on the source page with `?vt=1` (no saving). |
| `tests/daily-rewards.js` | 32 Daily Reward tests; source page with `?vt=1`. |
| `tests/shop-preview.js` | 42 Shop preview tests (cards, camera, buy / insufficient / no double charge / use, restore on close, fallback + retry); source page with `?vt=1`, after the splash. |
| `tests/info-icons.js` | 40 feature-info (ⓘ) tests: placements, explanations vs rule code, pulse / read state, tap area, keyboard, dismissal; source page with `?vt=1`. |
| `vendor/` | Downloaded three.js + font files, reused by the build. |
| `dist/`, `ludo-king-mymensingh-playables.zip` | Build output (generated). |
| `firebase/firestore.rules`, `firebase/SETUP.md` | Firestore security rules for player progress; the manual Firebase / Google / Facebook setup steps. |
| `submission/` | YouTube Playables submission kit (`SUBMISSION.md`, two screenshots). |
| `README.md` | Build, test and deploy commands. |
| `build/`, `ludo-royale-web.zip` | Obsolete early build; not used. |

## Architecture (inside `index.html`)
- **Layout:** everything lives in `#stage`. Desktop: centred 9:16 portrait frame. Phones (aspect < 10:16): full viewport.
  `#stage` has `transform:translateZ(0)` so `position:fixed` children are framed by it. Renderer/camera size from
  `SW()`/`SH()` (stage size) with a `ResizeObserver`.
- **YouTube SDK layer** (top of the IIFE): `YT`, `IN_YT`, `Store` (cloud save via `loadData`/`saveData` in YouTube,
  `localStorage` keys `ludoRoyalePrefs`/`ludoRoyaleProfile` elsewhere, 400 ms debounce), `firstFrameReady`, `gameReady`,
  `onPause`/`onResume` (sets `halted`), audio enable flag, error logging. `body.yt` hides `.no-yt` elements.
  If the cloud save can't be read (or takes over 10 s), saving stays off for that session so the cloud save is never overwritten.
- **Screens:** splash → welcome (every launch, unless a Google/Facebook session is restored) → home → game (`setScreen`). Bottom sheets for setup, settings,
  how to play, pause, pair prompt, win, spin, shop, inventory, discard-changes.
- **Splash (`#splash`, `runSplash(tasks, done)`, redone 2026-10-21):** deep plum-night gradient; `#studio` = the user's
  `Desktop\Brandmark.svg` (511×511 circle mark) | thin rule | `Desktop\Logo.svg` (2071×449, parallelogram + FLIPFOLD STUDIO,
  #CBCBCB + white), both inlined byte-for-byte (paths unchanged), sized from `--u` = min(90px, 14cqw, 17cqh) (`.splash`
  is a size container, so it fits the 9:16 desktop frame and phones). Bar: rounded plum track, lavender gradient fill with
  glow + sheen; "Loading N%" below. Progress is real: scene built (25%, before runSplash), then weighted tasks — saved
  progress (essential, weight 2, fails after 20 s of unpaused time), fonts (max 4 s) and first frames (max 1.5 s)
  (optional, count when they give up). Never shows 100% before all are done; then `.done` (450 ms glow sweep + logo
  highlight) and one fade to welcome / home. An essential failure shows `#loadErr` (friendly text + Retry = reload;
  nothing is saved, so progress is untouched). No minimum display time or hard cap any more.
- **Welcome (`#welcome`, `showWelcome()`):** shown on every launch and refresh unless `Account.init()` restored a valid
  Google/Facebook session (startup checks `Account.user`; `P.guestSince` no longer decides). Game logo with bobbing pawns,
  a benefits panel (Save Progress / Play with Friends / Earn Coins), then Continue as Guest (honey primary), Continue with
  Google (white, Google G) and Continue with Facebook (blue, f). Guests keep their local progress and see "Welcome back" /
  "Continue" once they have some. No decorative frame; the 9:16 stage has square corners and no outline. No Support link
  (no destination exists). Inside YouTube the save text says "Saved automatically".
- **Accounts (`Account` module, top of the IIFE):** Firebase Authentication (Google, Facebook) + Cloud Firestore, SDK
  10.12.2 loaded by `import()` from gstatic only when needed (preloaded while sign-in buttons are visible so the popup
  opens straight from the tap; falls back to `signInWithRedirect` if popups are blocked). Off when `FIREBASE_CONFIG` is
  `null` (buttons disabled + honest note) and always off inside YouTube (buttons `.no-yt`). Progress doc
  `players/{uid}` = `{ v, prefs, profile, updatedAt }` (rules in `firebase/firestore.rules`). Sign-in (popup or
  redirect, both via `finishSignIn`): guest blob backed up to `ludoRoyaleGuestBackup`; if the account has progress, the guest's
  is merged in (`mergeProgress`: account keeps identity/choices; owned dice, rooms and claimed achievements are joined;
  coins, XP and each stat take the higher value, never the sum; spin/free-coin timers take the later claim), otherwise the
  guest progress is uploaded. The account flag (`ludoRoyaleAccount`) is stored only after the sync succeeds; if the sync
  fails, Firebase is signed out and the guest progress restored. A stored flag without a live Firebase session is cleared
  at startup.
  Signed in: every local save also pushes to the account (1.5 s debounce, flush on tab hide); at start-up the newer of
  account vs device (`ludoRoyaleSavedAt`) wins. Sign out (Profile → Account) restores the guest backup. Errors map to
  plain messages (cancelled, other provider, unauthorized domain, method off, offline, bad config, rules).
  `Store.replace()` / `reloadSaved()` swap the whole profile.
- **Pause:** pause menu (Resume, Restart, Settings, Exit to home with a second-tap confirm). Outside YouTube, hiding the
  tab opens it (`visibilitychange`); inside YouTube only the SDK pauses. Timers (`wait`) count only unpaused time.
- **Snakes & Ladders 3D gameplay (2026-10-21):** matches are played on the jungle scene's table (`Jungle.play(true)`):
  the table stops turning, the sign, the coiled-snake tree and the two decor pawns hide, 3D glossy pawns (with contact
  shadows and a pulsing ring under the current player) follow SL's own per-player xy / lift mapped onto the 3D board,
  so all rules and animations stay in SL. A small orange snake is coiled on the table beside the board. The flat canvas
  board is hidden (`body.sl-3d`) and stays as the fallback until the scene is ready. Camera views: '3d' (50° angled) and
  'top' (straight down, square 1 bottom-left); `playView()` fits the board into the `#slBoard` box; all camera moves
  (landing <-> match, 3d <-> top) ease by real time (~1 s). Setting: gear on the S&L page -> `#slSetSheet` "Camera view",
  saved as `prefs.slCam` (separate from Ludo's `prefs.cam`). Top View also hides the framing trees / vines.
- **S&L scenes (2026-10-21):** the Jungle module builds its world from a scene config (`SCENES` inside Jungle: sky,
  fog, lights, ground, table finish, board style `B` (tile bands, grout, frame / lip, number ink, ladder rail / rung or
  candy `stripe`, snake colours), sign style, motes (fireflies / snow), falling leaves / sprinkles, and `world()` for the
  scenery + screen-anchored framing; `frame` piece with the coiled snake is hidden in matches). `buildWorld(id)` disposes
  the previous world (shared caches kept) and rebuilds; `Jungle.setScene` / `start()` pick the equipped one; previews
  via `Jungle.thumb(id)` (built + rendered once, only while the S&L page is closed, queued). Scenes: jungle (free,
  default), frost 20,000, candy 22,000, desert 25,000, cloud 25,000, enchanted 25,000 (`SL_SCENES`, Shop > Scenes,
  Inventory > Scenes). Profile: `P.scenes` (always includes jungle), `P.scene`; `buyScene` uses `commitProfile`. Board
  layout, snakes, ladders and rules are the game's data in every scene. The Shop's tab row has class `four` (icon above
  label on phones).
- **S&L pause menu (2026-10-21):** `card('pause')` renders `.slp` in `#slOv`, which gets class `pause` (fixed, whole
  page, blurred backdrop). Actions via `data-sl`: resume, restart (-> inline confirm restart-yes / restart-no; a restart
  is `newGame` with the same mode / players / colour), settings (opens `#slSetSheet`; the game stays paused), quit =
  Exit to Home (`exit()`).
- **Daily Reward (2026-10-21):** `#dailyBtn` ("Rewards", gift icon, badge when claimable) is the second button of the
  left side column, in the slot FB Group had (user's choice; FB Group is now only in Settings > Community, `#setGroup`); `#dailySheet` (.pm modal, 3x2 grid + wide Day 7).
  Config `DAILY_CYCLES` (array of cycles x 7 rewards: `coins`, `dice` (SKINS id) or `char` (CHARS id) + `or` coins if
  already owned). State `P.daily {cycle, streak, last (local YYYY-MM-DD), lastAt, autoOn, history[<=60]}`;
  `dailyState()` decides; `claimDaily()` writes via `commitProfile` after re-reading the stored profile. Limitation:
  local only (browser storage or the signed-in account's sync / YouTube cloud save); the device clock decides the day.
  Tests: `tests/daily-rewards.js` (32).
- **Shop preview (2026-10-21):** `viewWith()` adds View (`data-pv="room:id"` / `"scene:id"`) to Shop Rooms / Scenes
  cards only. `Preview` opens `#pvSheet` (2026-10-21 layout fix): one `.pv` card (28px radius, 4px border + ring,
  overflow hidden) = `.pv-view` (square, max min(58cqh, 440px), shrinks on short frames) + `.pv-panel` joined below;
  the sheet is a size container with safe-area padding; breakpoints at 481 / 768 px frame width and 600 / 430 px
  height (compact panel). The 3D view is the preview's OWN `THREE.WebGLRenderer` on a canvas created inside `.pv-view`
  on open and disposed (`forceContextLoss`) on close, so the card clips it like any element. While open, `frameLoop`
  only calls `Preview.render` (the café stays frozen behind the dimmed sheet). Rooms: `Rooms.set(id)` + Preview's own orbit camera (limits ray-checked
  against furniture in all 5 rooms: az .3-.9, el 0-.62, zoom .45-1); closing -> `Rooms.set(P.room)`. Scenes:
  `Jungle.previewOpen(id)` builds that world (`pvOn` blocks thumbs / setScene / start from swapping it),
  `previewRender(now, R, o, draw)` orbits around the landing camera, always leaves out the hanging sign and hides the
  other anchored framing pieces off-angle, `previewEnd`
  rebuilds the equipped world. Buy = `buyRoom(id, false)` / `buyScene(id, false)` (own without equipping; cards still pass
  equip = true); Use = `useRoom` / `useScene`. Failure -> card thumbnail + Retry. Tests: `tests/shop-preview.js` (42).
- **Feature info (2026-10-21):** `INFO` (title + bullet texts per key: ind, team, pair, free, capture, slEntry, sl, cam,
  slcam, daily, scenes) and `Info` (defined before `askPair`). Icons are `<span class="info-i" data-info="key">` (static
  HTML, or `infoBtn(key, cls, auto)` in rendered markup; `Info.fill` adds the art, role=button, label). One bubble
  `#infoTip` (fixed, below the icon or above it, clamped to the screen); closes on a tap elsewhere, its X, Escape, a sheet
  change or resize; a click on an icon inside a `<label>` doesn't pick that option. Pulse: `Info.nudge(key, on, root)`
  (mode change, Single/Pair picker shown, Free Hand state shown, S&L match start, camera change) and `Info.auto(root)` for
  `data-auto` icons when a sheet opens / cards are built; plays 4 beats, only until the key is read (`'open'`) and at most
  3 showings, kept in `prefs.info`. The texts restate the rule code (foe, dest, victimsAt, pairPartner, waitingSix,
  SL.land, dailyState, buyScene): change them together.
- **Coin sound:** `Sound` renders two coin samples (small / 500+ big) with an OfflineAudioContext and plays them as
  buffers (`sfx('coin', amount)`), max two at once, ±2.5% pitch variation.
- **Camera view (Ludo games only, 2026-10-21):** Settings > Preferences "Camera view" 3D View (default, the angled
  table) / Top View (`prefs.cam`). Top View = same live board, camera at 89.5° rolled 45° (`camRoll`, via `camera.up`)
  so the board is an axis-aligned square with your base bottom-left next to your card; `topFit()` measures the band
  between the top-row cards / status bar and the bottom-row cards and sizes (<= 97% width) and centres the board in it
  (`viewY`); cups hidden in Top View. Switching eases elevation, zoom and roll (~1.5 s), mid-game, no state touched.
  Home / Snakes & Ladders never use it (roll forced to 0 off the game screen).
- **Settings:** sound on/off (hidden in YouTube, where YouTube's mute decides), Master / Music / Effects volume sliders
  (0-100, step 5; prefs `vol: {master, music, sfx}`, defaults 80 / 50 / 85) and game speed Relaxed (1) / Fast (0.55).
  `prefers-reduced-motion` multiplies speed by 0.4 and stops the home orbit.
- **Input:** tap/click pawns (raycast) and the dice. Keyboard: Space/Enter roll, 1–4 move a pawn, Esc closes a sheet,
  closes the profile page or opens pause.
- **Start-up error panel** (`#fatal`): shown only for errors before the 3D renderer is up (`data-booted`).
- **Visual-test mode (`?vt=1`, `VT`):** seeded `Math.random`, frozen orbit / easing / `ts` / CSS animations, no saves,
  straight to home, exposes `window.__vt` and loads `vt-checks.js`. Inert without the flag.
- **Hot reload:** `window.claude.hot` snapshot keeps an in-progress game across Claude artifact updates (skips splash/welcome).
- **Camera:** fixed (not user-rotatable). Game view: diamond board (rotated 45°), seat azimuth
  `seatAz(c) = -PI/2*(c+1) - PI/4`, elevation 62°. Home view (order: HUD → logo → table → game buttons → tab bar): two horizontal mode buttons side by side
  (`.modes` row: VS COMPUTER left, PASS & PLAY right, equal width, 12px apart and 12px from the screen edges, max 560px
  total; buttons sit 12px + 4% of the screen height above the tab bar (`.home{container-type:size}`, `4cqh`; 1.5% under 640px
  tall); 62px tall, 56px under 740px, 46px under 520px; label size follows the button width via container units, and a
  container query shrinks the icon under 150px). `.home-wrap` hides horizontal overflow. `measureHome()` reads the band from the logo's bottom (+12px) to the
  buttons' top (−16px; 6/10px under 640px tall). `homeFit()` picks the smallest camera distance (max 56, inside the
  walls) at which the whole table top is at most 99% of the viewport width (`TABLE_MAX_W`, max 616px) and no taller than the
  band, then places its far rim `TABLE_DROP` (7% of the viewport height; 2.5% under 640px tall) below the band top; the rest of the band shows open room. Home camera tilt `HOME_TABLE_EL` = 33° (more board top, less front rim); splash/welcome stay at `HOME_EL` 26°. Slow orbit; cached
  per size/lens/band. Splash and welcome keep the old fixed view.
- **Very short screens (`fitStage`):** when the window is under 540px tall (phone landscape, split screen) the stage keeps
  a 320×568 layout and is scaled down as a whole (`translate(-50%,-50%) scale(s)`) instead of squeezing the UI.
  Portrait screens widen the FOV.
- **Cups:** in a game, two cups on the far side only; on home, four cups (one per side).
- **Rooms (`Rooms` module, `ROOM_LIST`/`ROOMS`):** shared table, cups, board, hemisphere + shadow-casting key spot light.
  Each theme is a group built on first use by `BUILD[id]()`, with exactly 3 point lights (so switching never recompiles
  shaders) and optional per-room animations (`Rooms.tick`). `Rooms.set(id)` toggles groups and sets background, fog, light
  colours and table tint (`MOOD`). `Rooms.thumb(id)` renders a cached 240×320 shop preview (2× supersampled) from a fixed corner.
  Themes: `night` Moonlit Café (**default**, free — the café after dark: starry windows with lit rooftops, glowing lamps,
  candles, extra string lights, amber light), `cafe` Corner Café (free, daytime), `dream` Pastel Dream Room (3,000),
  `studio` Sunny Cozy Studio (4,000), `cloud` Cloudside Playroom (5,000). Free rooms (`FREE_ROOMS`, price 0) are always
  owned; `DEFAULT_ROOM` = `night`. Both cafés come from one builder, `BUILD.cafe(night)`. Dark rooms (`MOOD.dark`) add
  `body.room-dark`, which switches the welcome/home veils to plum and captions over the 3D room to white.
- **Design tokens (`:root`):** page/table backgrounds; surfaces `--panel --card --surface-2 --chip --track`; lines; ink
  `--ink` (plum) / `--muted`; accents `--gold(-hi/-deep) --peach --coral --lavender --sky --teal --pink`; player colours
  `--red --green --yellow --blue`; depth `--shadow-sm/--shadow/--shadow-lg --press --gloss`; `--halo` for text over the 3D room.
  Tabs: one shared component `.gtabs` + `initTabs`/`selectTab`/`showPane` (Shop, Inventory, Profile collection).
  Flat, solid, cozy colours (no gradients, gloss, bevels or shadows): rounded-top tabs with a plum-outlined icon (`#ti*`
  symbols) and deep-plum (#563044) label. Active tab = its category colour `--tc` (Rooms terracotta #E09478, Dice sage
  #91B58A, Coins/Avatars honey #E7B85F; Frames rose, Nameplates lavender, Badges teal) with a 3px bottom bar in a
  darker shade `--tc2`, and is taller (48 vs 40px); inactive tabs are beige #EDE0D2. Rooms uses #E09478 rather than
  the suggested #D98262 so plum text reaches 4.5:1. The content area `.gtray` has no frame. Collection uses icon-only
  tabs (`.gtabs.icons`, labels kept for screen readers + title). Narrow rows shrink font/icon (container query).
  Arrow/Home/End keys, roving tabindex, aria-selected.
  Close button `.x-btn`: glossy red circle, white X, honey rim, top-right corner of the modal (Shop, Inventory; aria-label,
  Escape still closes). Shop/Inventory modal: `#shopSheet,#invSheet` are size containers with 12px (or safe-area)
  padding; the card is `width:100%; max-width:440px; height:min(100%,680px)`, so it never resizes between tabs and
  follows rotation. Title, description, tabs and X are fixed; only `.shop-pane` scrolls (hidden scrollbar,
  `overscroll-behavior:contain`, no horizontal overflow); grid is two `minmax(0,1fr)` columns. Narrow (<=340px) and
  short (<=640px) containers tighten padding/gaps/type. `html.sheet-open` (set in `openSheet`/`closeSheet`) stops the
  home and profile scrollers behind any open modal.
  Buttons: `.roll` (honey primary), `.ghost` (white secondary), `.item button`, `.claim`; all share the 3D "lip" + gloss style.
- **Game state `S`:** `{ id, players[4] ('human'|'cpu'|'off'), names, view, tok[4][4], pairs[], turn, dice, sixes, phase, pick, winner, teams, free[4] }`.
  Phases: `roll → rolling → choose | pick → moving → …`, `over`.
- **Pair Mode (teams; not the same-colour `pairs`):** only 4-player games (`newGame(players, teams)` forces `teams` off unless
  all four seats play). Partners sit opposite: Red + Yellow, Green + Blue (`mateOf(c) = (c+2)%4`). `foe(c, o)` excludes
  the partner, so partners never capture or block each other (`victimsAt`, `oppPairAt`, AI `threatAt`). A player who has all
  four pawns home is finished, but the team wins only when both partners are home (`gameOver` shows "Your team wins!" /
  "A & B win"; `recordResult` counts a win when you are either partner). Free Hand: a finished player still takes turns;
  until it rolls a 6 nothing moves (`waitingSix`); that 6 sets `S.free[c]` (kept for the rest of the game) and is used at
  once. From then on `moverOf(c)` = partner: `movables`, `move`, `choosePick`, `pickAI`, the glowing tokens and the
  Single/Pair chooser all use the partner's pawns, and every normal rule applies (exact finish, extra rolls, three 6s,
  captures, same-colour pairs). Setup: "Mode" row (Individual / Pair) in vs Computer (only with 3 opponents) and
  Pass & Play (only with 4 players); `lastTeams` is reused by Restart / Rematch and kept across live reloads. HUD:
  each card shows "w/ <partner colour>", a "Done · need 6" / "Free Hand" chip, and the partner whose pawns the roll
  moves gets a dashed outline; status messages name it ("rolled 4 for Yellow").
- **Profile `P`:** name, id (`LKM-XXXX-XXXX`), guestSince (first "Continue as Guest" time), avatar, frame, plate, badge, xp, coins, lastSpin, lastFree, owned dice, dice,
  `stats{played,wins,losses,streak,bestStreak,coinsEarned,pairsFormed,ppGames}`, `claimed[]`, `rooms[]` (owned themes, always includes the free `night` and `cafe`), `room` (selected theme). `ensureProfile()` fills missing fields;
  `commitProfile()` rolls back on a failed save.

## Gameplay rules (as implemented)
- 52-cell track; colours 0 red, 1 green, 2 yellow, 3 blue; start offsets `OFF=[0,13,26,39]`; stars `[8,21,34,47]`; `SAFE` = starts + stars.
- Progress per token: -1 base, 0–50 track, 51–55 home column, 56 (`GOAL`) finished. Exact roll needed to finish.
- Leave base only on a 6. A 6, a capture, or reaching home gives another roll. Three 6s in a row lose the turn.
- No legal move: message from `stuckReason()`; a 6 still re-rolls.
- Capture: landing on an opponent on a non-safe square sends it to base. A single captures **only one** pawn even from a stack.
- Modes: vs Computer (pick colour, 1–3 CPU rivals: Mocha, Biscotti, Espresso) and Pass & Play (2–4 humans).
- CPU (`pickAI`) scores moves: finishing, leaving base, entering home column, captures, safe squares, threat avoidance.

### Pair feature
- **Forming:** a single landing on a loose same-colour pawn on a main-track square gets an optional "make a pair?" prompt
  (CPU pairs automatically when not on a safe square). Never on any colour's start square, never in the home column,
  never with a pawn already paired. Passing over a pawn does not count.
- Forming a pair does not give an extra roll.
- **Moving:** even rolls only, moves **half** the roll (2→1, 4→2, 6→3). Either pawn moves the whole pair.
  A pair can reach at most progress 53 from the track (50 + 3), so it always stops in its home column first and splits there.
- **Single/Pair selector:** after a roll where both a pair and a single can move (human only), `#unitPick` asks which kind moves.
- **Blocking:** a single cannot jump an opponent pair. It may land on the pair's square, then leaves only with an exact 1.
  An opposing **pair** passes a pair freely (no 1 needed). Your own pairs never block your own singles. Blocking applies on
  the main track only.
- **Capture:** only a pair can capture a pair (both pawns go home). A single never captures a pair. A pair never captures
  a single (since 2026-10-20): it just shares the square, no extra roll. Enforced in `victimsAt`, so CPU and humans alike;
  the AI's `threatAt` ignores paired pawns. Safe squares protect everyone.
- **Splitting:** a pair splits automatically (no button) when it lands on **any** colour's start square, or when it lands
  on any cell of its home column (`HOME[c]`, progress 51-55: the coloured lanes to the centre, marked by the user on
  2026-10-20). Both pawns stay on that cell as singles. Pairs that reach the centre are dissolved (only possible for a
  pair already in the lane from an older saved game). Tests: `tests/pair-capture-split.js` (151, real moves, all colours).
- Visuals: paired pawns stand side by side at 0.8 scale.
- Code: `pairOf`, `unitOf`, `oppPairAt`, `onStartSquare`, `dest`, `victimsAt`, `pairPartner`, `stuckReason`, `askPair`, `choosePick`, `move`.

## UI/UX requirements (from the user)
- Mobile first; portrait. Desktop shows the centred 9:16 frame; no control may overflow the frame.
- Fixed camera; diamond board; cups never in the player's way.
- Ludo-King-style HUD: player cards in the four corners, clockwise from the viewer's bottom-left. Each card shows name,
  finished-pawn pips and progress %. Your card uses your profile name and avatar. The dice moves into the active player's card.
- Home top bar (`.h-top` > `.h-bar`, ids unchanged), styled after the user's casual-game HUD reference in our colours:
  one solid peach (#ffd6b3) 56px row, 12px from the screen edges, light top / darker bottom edge. White-framed avatar;
  name (display font, ellipsis) over a recessed plum XP track with a honey level star on its left end
  (`renderProfileChip` fills `#profileLvl`/`#profileXp` from `levelInfo`); coins as a recessed plum track (cream number,
  `fmtCoins`: 12.5K / 1.2M) with the coin overlapping its left end and a teal white-bordered "+" its right end; honey
  gear with plum outline, no background. `.h-top` keeps the old 50px layout height so nothing below
  moves. Container queries tighten gaps under 330px and hide the level row under 250px. No secondary currency exists.
- Lively home: logo, top bar, daily spin, free coins, FB group, share, only two premium mode tiles
  (vs Computer, Pass & Play), bottom tab bar (Snake & Ladder, Inventory, Home, Shop, Online), café table visible behind.
- Snakes & Ladders (Snake tab, `SL` module, `#slPage`): full-screen page over the lobby (`body.sl-open` hides the home
  and stops the 3D render loop). 10x10 canvas board drawn once per size (`drawBoard`: tinted zig-zag cells, wooden
  ladders, wavy outlined snakes with eyes, numbers on top), tokens animated each frame. Rules live in `land(from, v)`:
  a pawn off the board (square 0) enters only on a 1 (2-6 don't move it; a 6 still rolls again; one pawn per player),
  `LADDERS` / `SNAKES` maps, exact roll to 100 (overshoot stays put), a 6 rolls again, a third 6 ends the turn.
  Dice: the Ludo CSS cube (`.cube` / `.face`, `PIPS` / `SHOW`, equipped skin vars, hop + tumble roll) in `#slDice`;
  only the look and animation are shared, not Ludo's dice logic.
  Setup card: vs Computer (you are Red + 1-3 CPUs: Mocha, Biscotti, Espresso; they roll by themselves) or Pass & Play,
  2-4 players. Back / Escape mid-game pauses (Resume / Quit); a hidden page pauses too (not inside YouTube, which uses
  `halted`). Reward: `SL_REWARD` (100) coins via `addCoins` only for beating the computer, once per game, and only if
  replaying your recorded rolls through `land` really reaches 100; stats `slPlayed` (all finished games) and `slWins`
  (validated wins vs computer) show in Profile > Stats. Tests: `tests/snakes-ladders.js` (46).
- Snakes & Ladders landing (`Jungle` module): the Snake tab first shows a 3D jungle (`body.sl-landing`, `#slLand` with
  VS COMPUTER / PASS & PLAY in the home `.mode` button style); each button opens a centred setup popup over the
  landing, built from the same `.sheet` / `.card` modal as Ludo's: `#slCpuSheet` (your colour swatches + 1-3 opponents)
  or `#slLocalSheet` (2-4 players). No mode selector inside (the landing buttons choose it). Start game ->
  `startFrom(mode, n, color)`; vs Computer you play your colour and the computers take the next colours round.
  Back / Escape close the popup (landing stays). Finished game Back -> landing, landing Back -> home; mid-game Back pauses. The jungle is its own `THREE.Scene` + camera drawn by the shared renderer from `frameLoop` only
  while the landing is visible (setup/game/home draw nothing of it); built lazily on first open (`Jungle.start`).
  Contents (polished 2026-10-20): sky gradient + fog, grass and a soft-edged sandy clearing, round wooden table turning
  ~1 rev / 30 s with a framed 3D board (`buildBoard`: rounded cream frame like the Ludo board, honey lip, painted face
  with rounded pastel tiles and numbers (`boardFace`), 3D ladders and glossy tapered snakes built from SL.LADDERS /
  SL.SNAKES / SL.SNAKE_COL) and two glossy Ludo-style pawns (no dice); background of smooth rounded trees, two far
  palms (leaf geometry `leafGeo`), tidy bushes and ferns; a hanging wooden sign "SNAKES & LADDERS" (canvas text,
  Lilita One) with ropes, vines and a little snake; two framing snakes (left tree coil, purple hanging right). Snakes
  share one model (`snake`: tapered body `taperGeo` with painted back pattern and pale belly, `snakeHead` with big
  eyes, smile, cheeks, nostrils, flicking tongue); the head is aimed by an outer group and bobs in an inner one.
  Sunbeams, fireflies, falling leaves, swaying foliage. Framing pieces use
  `anchor(obj, sx, sy, k, onGround, s)`: screen position + a fraction of the camera-to-table distance, scaled with
  distance, so the layout holds on any screen shape. The view is offset 7% (table slightly below centre); the landing
  buttons sit 10px + 3vh above the bottom. Performance: shared per-colour materials, static scenery merged into one
  mesh per material (`mergeStatic`, the turning table merged separately), no shadow maps; about 150 draw calls / 156k
  triangles at 390x844.
  The Home tab only marks the current screen (no action).
- Logo: "Ludo Zing Mymensingh" in a "Ludo Vibe" style, used across the game (renamed from "Ludo King" on 2026-10-21:
  only the gold word changed, KING -> ZING; same SVG, colours, sizes). The Cloudflare project / URL and zip keep the
  old `ludo-king-mymensingh` slug (changing it needs a new Pages project).
- Welcome screen: Google / Facebook buttons and `#wNote` are hidden by class `signin-off` on `#welcome` (2026-10-21);
  the Firebase / Account code is unchanged; remove the class to show them again.
- Studio splash: Moonfrog-style minimal black (style only, no Moonfrog branding); the Flipfold Studio logo must never be
  redrawn, recoloured or distorted. Welcome screen: Ludo Club layout as inspiration only; never fake login.
- Profile page: header (avatar, name, ID, level, XP), avatar/name editing with validation (`NAME_RULE`, 2–14 chars),
  stats from real games only, 6 achievements with coin rewards (claimed by tapping), collection (avatars, frames, nameplates,
  badges, dice, rooms). Sign-in, sound, privacy and help moved to Settings (see below). Inside YouTube the name can't
  be edited and the ID copy button is hidden.
- Characters (Collection tab `chars`, after Avatars): `CHARS` = 10 male + 10 female portrait avatars, appended to
  `AVATARS` (so `AVATARS[0]`, the fallback, is still Red Pawn). Art is generated SVG (`personSVG(p)`: skin, hair colour,
  hairstyle, outfit colour/detail, accessory) cached in `avArt`; `.avatar.person` / `.ava.person` show it full-bleed.
  Arif (male) and Nadia (female) are free (`price: 0`); the other 18 cost 10,000–12,000 coins. Ownership: `P.avOwned`
  (ids), joined on sign-in by `mergeProgress` like `owned` / `rooms`; `isUnlocked` returns ownership for priced items;
  `ensureProfile` drops unknown ids and resets an equipped-but-not-owned character to Red Pawn. Buying: `buyAvatar`
  (Buy button only when affordable, otherwise "Need X"; re-checks price/ownership, `commitProfile` rolls back coins
  and ownership if saving fails; button disabled on the first tap). A purchase does not equip; Equip uses the common
  collection equip path (`P.avatar`). Cards: Free / Owned / Equipped tag, lock icon + coin price when for sale (shown
  in full colour). Edit Profile's avatar grid lists them too; a locked one says where to buy it.
  Presentation (style ref: user's casual-game profile screenshots, in our palette): `#profilePage` (`.ppage`) is a
  dimmed full-screen overlay (size container) holding a fixed-size modal `.pm` (max 440x720): cream panel, white rim,
  warm-brown outline, coral title ribbon `.pm-title` over the top edge, red `.x-btn` (`#ppBack`). Folder tabs `.ftabs`
  (`#ppTabs`: Profile / Achievements, shared `initTabs`/`showPane`; the row spans the panel edge to edge, the panel's
  top corners are square, the selected tab overlaps and covers the panel's 3px top border, inactive tabs stop on it;
  no box-shadow patches) sit on a framed inner panel `.pm-inner`
  (`#ppPane`), which alone scrolls (hidden scrollbar). Profile tab: avatar left; name plate, Player ID + copy, level
  star on a plum XP bar with "x / y XP", honey Edit; striped stat rows; Collection (last section).
  Achievements tab: cards (medal, title, description, teal progress bar, honey "Reward" strip with Claim / Claimed /
  In progress). Edit Profile (`#ppEditBox`, `.pm-ov`) is a second modal on top: name field, avatar grid on an orange
  tray, green Save; X / Escape = `cancelEdit` (asks via `discardSheet` if unsaved, Discard just closes the editor).
  There is no country or referral code in this game; the Player ID stands where the reference shows a referral code.
  Modal stacking: each `.pm` is `isolation:isolate` (its X can't rise above a modal opened on top) and `syncModalStack`
  (a MutationObserver on `hidden` inside `#stage`) marks covered modals `inert`, which hides their X; only the topmost
  modal is interactive (Profile under Edit Profile or any sheet; Edit Profile under Discard changes?).
- Settings (`#settingsSheet`, a `.sheet.pm-sheet`, same `.pm` modal look, uppercase "SETTINGS" ribbon, 540px tall
  fixed): folder tabs `#setTabs` Preferences / Account (`data-tab="community"`) over an orange inner panel `#setPane` (only it scrolls);
  cream rows `.set-row`. Preferences: Sound (ON/OFF pill switch `#sndSwitch`), Master / Music / Effects sliders (`.vol`, teal fill via `--v`),
  Game speed (Relaxed / Fast).
  Account tab, in subsections `.set-h` (only "Privacy & help" shows inside YouTube): Account: sign-in status
  `#ppAccTxt`, error `#ppAccMsg`, Google/Facebook or Sign out in `#ppAccBtns` (ids kept, so `renderAccount`,
  `doSignIn`, `setAuthBusy` are unchanged; `openSheet('settingsSheet')` calls `renderAccount`); Community: Facebook
  group "Join" and "Share" reuse the home buttons' actions (both still "coming soon" toasts); Privacy & help: privacy
  note, How to play (`#btnHow`). Fixed bottom action: Done (teal). Only real
  options: there is no music, notifications, language, colour choice, rating, support or policy link in the game.
- Stats: played/wins/losses/streaks count only games with one human vs the computer; Pass & Play games count as `ppGames`.
- Economy: start 5,000 coins; win vs CPU +200; free coins 300 every 4 h; daily spin (100–1,000); dice skins Crema/Espresso/Royal Gold;
  Moonlit Café and Corner Café are free; every other room must be bought: 3,000 / 4,000 / 5,000 (Shop → Rooms; switch in Inventory or Profile → Collection → Rooms).
  Shop has category tabs Rooms / Dice / Coins (`#shopTabs`, `showShopTab`): tabs and Done stay fixed, only `#shopPane`
  scrolls (reset on tab switch); the shop tab opens on Rooms, the coin "+" opens on Coins. Dice purchases refuse items
  already owned. Coins only, no real money.
- Visual direction (2026-10-19 redesign): cozy, bright, softly glossy casual-game look — cream/peach/honey surfaces,
  lavender/pink/sky/teal accents, plum text, rounded shapes, warm light. References: isometric yellow bedroom, pastel music
  room, Playstudios-style colourful 3D art (direction only, never copied). Avoid dark brown UI, heavy glow and clutter.
- XP: win vs CPU 100, loss vs CPU 40, Pass & Play game 30. Level n needs 100 + 50·(n−1) XP.

## YouTube Playables constraints
SDK script must load first; bundle < 30 MiB (aim < 15 MiB); relative paths; simple file names; no external requests except
Google/YouTube (the Firebase SDK and sign-in never load inside YouTube); no clipboard, no name/username collection, no share prompts, external links or exit button; no Page Visibility
API inside YouTube; English. Build currently ~892 KB in 6 files. Never expose keys, never enable paid plans, never submit forms
or accept terms for the user.

## Known issues and risks
- **Sign-in needs setup:** `FIREBASE_CONFIG` is `null` until the user creates the Firebase project and pastes the config
  (`firebase/SETUP.md`). Real Google/Facebook sign-in has not been tested end-to-end yet; the SDK load, popup→redirect
  fallback, error handling, restore and sign-out paths were tested locally (fake config / test hook).
- Facebook Login requires the Facebook app in Live mode with a privacy policy URL before the public can sign in.
- **Trademark:** "Ludo King" is Gametion's trademark; the game was renamed "Ludo Zing Mymensingh" (2026-10-21). The URL
  slug still says ludo-king.
- Share button toast still says "when the game is live on Facebook"; FB group button is a placeholder toast (both hidden in YouTube).
- The Online tab is a "coming soon" toast only.
- SDK integration can only be fully verified in YouTube's test suite (after approval).
- YouTube's overlay controls may sit near the in-game pause/settings icons; check in the test suite.
- In-game "How to play" says opponents must roll a 1 to pass a pair, but doesn't say an opposing pair passes freely.
- `submission/SUBMISSION.md` says the bundle is 802 KB in 5 files; the current build is ~876 KB in 6 files, and its
  screenshots predate the redesign, studio splash and welcome screen.
- The game logo is still the Claude-drawn `#brandLogo` symbol; the user said they will supply their own logo SVG (pending).
- YouTube Playables: the extra welcome tap before play is not yet checked against YouTube's review expectations.
- No open gameplay bugs known. Automated tests cover pair rules only.
