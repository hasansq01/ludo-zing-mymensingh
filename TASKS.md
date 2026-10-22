# Tasks — Ludo Zing Mymensingh

See `PROJECT_CONTEXT.md` for details. Update this list whenever work starts, finishes or is dropped.
Last reviewed: 2026-10-19.

## Completed
- [x] 3D WebGL Ludo core: board, tokens, dice, turns, captures, exact finish, three-6s rule.
- [x] Café scene: round table, board, coffee cups, café background.
- [x] Fixed camera (no rotation); diamond (45°) board; cups only on the far side in a game.
- [x] Splash screen with real loading steps; home screen.
- [x] Mobile-first HUD: corner player cards, CSS 3D dice beside the active player.
- [x] Lively lobby: profile chip, coins, daily spin, free coins, shop, inventory, dice skins, tab bar, animations.
- [x] Home: two mode tiles (vs Computer, Pass & Play); four cups on home only; table visible.
- [x] Logo "Ludo Zing Mymensingh" used across the game.
- [x] Single captures only one pawn from a stack.
- [x] Pair feature: optional forming, even rolls / half moves, blocking, pair-only capture of pairs.
- [x] Pair fixes: no forming on start squares, auto-split on any start square, pair passes pair freely, Single/Pair selector.
- [x] Pair rule tests (`tests/pair-rules.js`, 25 tests; all passed on 2026-10-19 after the visual redesign and again after Pair Mode).
- [x] Pair Mode (4-player teams, Red + Yellow vs Green + Blue) with Free Hand, for Pass & Play and vs Computer; team rule
      tests `tests/team-rules.js` 28/28; four-CPU team game played to a team win through Free Hand with no stalls;
      home regression suite passes. Built; deployed 2026-10-20 (third deploy).
- [x] 20 character avatars (10 male, 10 female; Arif and Nadia free, 18 at 10,000-12,000 coins) in Profile > Collection >
      Characters: buy (affordability check, no double charge, rollback on save failure), equip, persistence after reload,
      Edit Profile and in-game card tested; home regression suite passes. Built; deployed 2026-10-20 (third deploy).
- [x] Nested modals: only the topmost shows its close button (stacking layer per modal + inert covered modals). Tested
      Profile > Edit Profile > Discard and Settings > How to play at 320, 390 and 1366 wide. Built; deployed 2026-10-20 (third deploy).
- [x] Pause menu, settings (sound, Relaxed/Fast speed), how-to-play sheet, keyboard controls.
- [x] Player profile page: identity, avatar/name editing, real stats, achievements, collection, preferences, persistence.
- [x] YouTube Playables integration: SDK lifecycle, cloud save, audio, pause/resume, error logging, YouTube-only hidden UI.
- [x] Production build script with Playables limit checks; local server.
- [x] Deployed free on Cloudflare Pages (https://ludo-king-mymensingh.pages.dev) and verified live.
- [x] Submission kit (`submission/`).
- [x] Desktop 9:16 centred portrait frame; full screen on phones; overflow fixes. Built, deployed, verified.
- [x] Project memory docs (`PROJECT_CONTEXT.md`, `TASKS.md`), checked against the code on 2026-10-19.
- [x] Flipfold Studio splash (supplied logo, real loading progress, 12 s cap, background-tab safe) and first-launch
      Welcome / Continue as Guest screen. Built, tested, deployed and verified live (2026-10-19).
- [x] Global visual redesign (2026-10-19): design tokens, bright cozy UI on every screen, restyled Corner Café, glossy
      board/pawns, lighter lighting. Three purchasable rooms (Pastel Dream Room, Sunny Cozy Studio, Cloudside Playroom) with
      rendered shop previews, ownership, selection (Shop, Inventory, Profile → Rooms) and persistence. Profile-page overflow fixed.
      Built and tested.
- [x] Moonlit Café: night version of the café, now the default room; both cafés free, other rooms must be bought.
      Night overlays/captions for dark rooms. Built and tested.

- [x] Welcome: removed the rounded colour frame and stage corner curves/outline; added Continue with Google / Facebook
      next to Continue as Guest. Firebase Auth + Firestore progress sync, restore, sign-out back to guest, profile Account row.
      Built and tested.

- [x] Home screen clean-up: compact horizontal VS COMPUTER / PASS & PLAY buttons; camera zoomed out so the whole table
      shows (90% width, ~20% smaller), table just below the logo; landscape / very short screens scale the whole frame.
      Checked at 320×568, 360×800, 390×844, 430×932, 844×390, 768×1024, 1366×768, 1920×1080. Built, tested locally (not deployed).
- [x] Home refinement: game buttons side by side; table 10% larger (99% width) and 4% lower. Checked at 320×568,
      390×844, 844×390, 768×1024, 1920×1080. Built and tested.
- [x] Home final refinement: camera tilt 26°→33°, table ~3% lower, game buttons raised by 4% of the screen height.
      Checked at 320×568, 390×844, 844×390, 768×1024, 1920×1080. Built and tested.
- [x] Deployed (2026-10-19): redesign, rooms, Moonlit Café, sign-in UI, home layout. Fixed the build zip's backslash paths so the
      web fonts load on the live site (they had never loaded before); verified live.
- [x] Regression safeguard for the locked home screen (2026-10-19): `tests/visual` (screenshot baseline 390×844, layout +
      locked-number checks at 6 sizes, approval-gated baseline updates). Passes (0.000% pixel diff); a planted change was caught.
- [x] Startup: welcome screen on every launch unless a Google/Facebook session is restored; safe merge of guest progress
      into an existing account; sign-in counts only after a successful sync. Tested (guest launches/refresh, stale and invalid
      sessions, failed sign-in, sign-out, merge rules); home regression suite passes. Built; deployed 2026-10-19 (second deploy).
- [x] Shop split into Rooms / Dice / Coins tabs with a fixed header, scrolling product pane and duplicate-purchase guard.
      Tested every tab, purchase and equip; home regression suite passes. Built; deployed 2026-10-19 (second deploy).
- [x] Shared text-tab component (plum labels, red indicator) for Shop, Inventory (new Rooms / Dice tabs) and Profile
      collection; tested at mobile and desktop; home regression suite passes. Built; deployed 2026-10-19 (second deploy).
- [x] Game-style coloured icon tabs + glossy red close button (Cut the Rope reference) for Shop, Inventory and Profile
      collection, replacing the text tabs and Done buttons. Tested at 390x844 / 320x568; regression suite passes. Built; deployed 2026-10-19 (second deploy).
- [x] Shop/Inventory mobile overflow rules (fixed-size modal, only products scroll, hidden scrollbar, background scroll
      lock) + flat cozy tab colours, no coloured content frame. Tested at 320x568, 360x640, 390x844, 844x390, 1366x768
      and on rotation; regression suite passes. Built; deployed 2026-10-19 (second deploy).
- [x] Single-row cozy top bar (avatar + name + level/XP, coins +, settings). Tested at 320/360/390/430 widths with long
      names and large balances; layout checks pass. Built; deployed 2026-10-19 (second deploy).

- [x] Profile redesigned as reference-style modals (Player Profile with Profile / Achievements tabs, Edit Profile on
      top). Tested edit / save / validation / discard / Escape and fit at 320x568, 360x640, 390x844, 430x932, 844x390,
      1366x768. Built; deployed 2026-10-19 (second deploy).
- [x] Settings redesigned as a reference-style modal (Preferences / Community tabs, fixed bottom actions), existing
      options only. All controls tested at the same six sizes. Built; deployed 2026-10-19 (second deploy).
- [x] Account & preferences moved from the Profile into Settings (Preferences: sound; Account: sign-in, community,
      privacy, help). Same handlers and ids; tested at six sizes. Built; deployed 2026-10-19 (second deploy).
- [x] Tab joins fixed (folder tabs: flush row, square panel top corners, selected tab covers the border, no shadow
      patch; flat tabs: selected tab covers the baseline, row flush). Measured at 1x; fit tests pass. Built; deployed 2026-10-19 (second deploy).
- [x] Second deploy (2026-10-19, on the user's request): everything above marked "second deploy", including the restyled top
      bar that is not yet approved for the home screenshot baseline. Verified live: all 6 files match the build byte for byte,
      fonts load, no console errors; welcome, home top bar, Settings and Profile checked at 390x844.

## In progress
- [ ] **User:** approve the restyled top bar (reference-style HUD, second version) so the home screenshot baseline can
      be updated (screenshot differs 5.35%, only in the bar region x 12-377, y 9-64; all layout checks and locked
      numbers pass).
- [ ] **User:** Firebase / Google / Facebook setup from `firebase/SETUP.md`, then paste `FIREBASE_CONFIG` and test real sign-in.

## Pending / not started
- [x] Renamed to "Ludo Zing Mymensingh" (2026-10-21): page title, logo (KING -> ZING, same design), logo labels,
      group toast, docs. Kept on purpose: the Cloudflare project / URL `ludo-king-mymensingh.pages.dev`, the zip name and
      Firebase example IDs (renaming them means a new Pages project), and the saved-data keys (`ludoRoyale…`).
- [x] Welcome screen: Google / Facebook buttons and the sign-in note hidden (class `signin-off` on `#welcome`; the auth
      code is unchanged, remove the class to show them again) (2026-10-21).
- [ ] User submits the YouTube Playables interest form (user's own action).
- [ ] After approval: run YouTube's test suite; check overlay controls vs. in-game corner icons.
- [x] Snakes & Ladders on the Snake tab (vs Computer / Pass & Play, 2-4 players, validated coin reward, profile stats);
      `tests/snakes-ladders.js` 29/29; full 4-player game played to a finish; fits 320x568 to 1366x768. Built; deployed 2026-10-20 (third deploy).
      The tab's "Soon" chip was removed (home screenshot differs 0.21%, inside the 0.5% limit).
- [x] 3D jungle landing for Snakes & Ladders (rotating table with the real board, sign, snakes, ambient motion) with
      VS COMPUTER / PASS & PLAY leading to the existing setup; both paths, Back/Escape, render-only-when-visible and
      tappable buttons tested; 33/33 tests; checked at 320x568, 390x844, landscape and desktop. Built; deployed 2026-10-20 (third deploy).
- [x] Snakes & Ladders setup now uses centred popups like Ludo's (vs Computer: colour + opponents; Pass & Play: players);
      the in-page setup panel and its duplicate mode selector are gone. 35/35 tests. Built; deployed 2026-10-20 (third deploy).
- [x] Third deploy (2026-10-20, on the user's request): Pair Mode, character avatars, nested-modal fix, Snakes & Ladders
      (game, 3D jungle landing, setup popups, Ludo dice). Verified live: all 6 files match the build byte for byte, fonts
      load, no console errors; welcome, home, jungle landing, Pass & Play popup and a real roll checked at 390x844.
- [x] Rule fixes (2026-10-20): a pair never captures a single (and a single never a pair); a pair splits by itself on
      any cell of its home lane (progress 51-55, all colours); Snakes & Ladders needs a 1 to enter. Tests:
      `tests/pair-capture-split.js` 151/151, `tests/snakes-ladders.js` 46/46, `tests/team-rules.js` 28/28,
      `tests/pair-rules.js` 25/25; home regression suite passes. Built; deployed 2026-10-20 (fourth deploy).
- [x] Snakes & Ladders landing polish (2026-10-20): smoother rounded foliage, remodelled friendly snakes (also fixed the
      left snake's head aiming upward), framed 3D board with 3D ladders/snakes, dice cubes removed, landing buttons
      raised 3% (view nudged so they clear the table at 320x568). Checked 320x568, 390x844, 430x932, 844x390;
      `tests/snakes-ladders.js` 46/46; home regression suite passes. Built; deployed 2026-10-20 (fourth deploy).
- [x] Fourth deploy (2026-10-20, on the user's request): pair capture / home-lane split rules, Snakes & Ladders roll-1
      entry, polished jungle landing. Verified live: all 6 files match the build byte for byte, no console errors;
      jungle landing, Pass & Play popup and real rolls (both players entered on a 1, square 1 ladder to 38) at 390x844.
- [x] Audio + celebration upgrade (2026-10-20): new Web Audio engine (buses, limiter, ~4-8x louder effects, generated
      music), Master / Music / Effects sliders saved in prefs, 18 named effects incl. error feedback, random win
      celebrations (burst / cannons / flares / rain), magical burst when a pawn reaches the centre. Tested levels, mute,
      sliders, persistence, one burst per arrival, cleanup; rule suites pass; home regression suite passes. Built;
      deployed 2026-10-21 (sixth deploy).
- [x] Sound fixes (2026-10-21): (1) the deployed build loads the YouTube SDK, and outside YouTube its
      isAudioEnabled() is false, which silenced ALL sound on the website (the old beeps too); `YT` is now null unless
      IN_PLAYABLES_ENV. (2) The Claude app's browser pane reports the page hidden while in use; audio now mutes only
      when hidden AND unfocused, never suspends, and every tap resumes it.
- [x] Fifth deploy (2026-10-21): audio + celebrations; files matched but the live check found no sound (fix 1 above).
- [x] Sixth deploy (2026-10-21, on the user's request): the sound fixes. Verified live: all 6 files match the build byte
      for byte; with the SDK present (IN_PLAYABLES_ENV false) a tap starts the audio context ("running") and voices
      play (taps + music); no console errors; home regression suite passes.
- [x] Snakes & Ladders: ladders 1 -> 38 and 80 -> 100 removed from `LADDERS` (2026-10-21, user's marked screenshot); the
      2D board and the 3D landing board draw from that data. Rule checks pass (1 and 80 no longer climb, all 7 other
      ladders and 10 snakes work, new reward path); `tests/snakes-ladders.js` 51/51; both ladders checked gone on the
      in-game board and the 3D landing board. Built; **not deployed**.
- [x] Ludo Top View camera (2026-10-21): Settings "Camera view" 3D View / Top View, saved, switchable mid-match with a
      smooth glide; board sized and centred between the card rows; pawn tapping works; tested 320x568, 390x844,
      430x932, desktop frame, Pair Mode. Settings modal max height 540 -> 610 px so the new row fits. Built; deployed 2026-10-21 (seventh deploy).
- [x] Seventh deploy (2026-10-21, on the user's request): Top View camera, Ludo Zing rename + ZING logo, hidden sign-in
      buttons, welcome layout, two ladders removed. Verified live: all 6 files match the build byte for byte; welcome
      screen (title, logo position, sign-in hidden), sound runs after the first tap, vs Computer game started and
      switched to Top View at 390x844 (a dice tap there was not confirmed to roll); no console errors.
- [x] Daily Reward (2026-10-21): 7-day calendar popup (Rewards button in the FB Group slot, user-approved; FB Group
      now only in Settings > Community; home baseline updated with approval; opens
      by itself once on the first eligible home visit of a day), configurable `DAILY_CYCLES` (3 cycles: coins, dice
      skins, characters; owned items pay their `or` coins), local-calendar-day rules, missed day -> Day 1, saved in
      the profile (`P.daily`), duplicate-proof (busy flag, re-check of the stored profile, commitProfile rollback).
      `tests/daily-rewards.js` 32/32; reload, stale-tab and real-tap claims checked. Built; **not deployed**.
- [x] Coin pickup sound (2026-10-21): rendered coin sample (clink + struck-metal partials + sparkle tail) played as a
      buffer, richer variant for 500+ coins, max two at once; used by every coin gain. Built; **not deployed**.
- [x] Snakes & Ladders 3D gameplay + 3D View / Top View (2026-10-21): matches on the jungle table with 3D pawns,
      camera setting in a new S&L settings popup (gear), saved, switchable mid-match with a smooth glide; rules suite
      51/51; checked 390x844 and 320x568, real roll onto square 1, preference restored for a new match. Built; **not deployed**.
- [x] Snakes & Ladders pause menu redesign (2026-10-21): centred compact modal over the blurred game (logo, "Paused",
      Resume / Restart Game (with confirm) / Settings / Exit to Home). All buttons tested with real taps at 390x844 and
      320x568; S&L suite 51/51. Built; **not deployed**.
- [x] Five premium Snakes & Ladders scenes (2026-10-21): Frosty Wonderland 20K, Candy Kingdom 22K, Desert Temple 25K,
      Cloud Kingdom 25K, Enchanted Jungle 25K, each its own 3D world, table, lighting, particles and board / ladder /
      snake colours; Shop > Scenes + Inventory > Scenes with rendered previews, Buy / Owned / In use; insufficient
      coins refused; purchase via commitProfile; persists after reload. Built; **not deployed**.
- [x] Feature info icons (2026-10-21): an ⓘ beside Individual / Pair (both Ludo setups), the Single/Pair picker and the
      "Create a Pair?" prompt, the Free Hand state and the team tag (capture rules) on the Pair Mode player cards, the S&L
      setup rules text and in-game status line, both Camera view rows, the Daily Reward heading and the Shop / Inventory
      Scenes panes. Tap opens a compact bubble (kept on screen, beside the icon); the icon pulses when its feature is
      selected / appears until read once (max 3 showings), saved in `prefs.info`. Texts written from the rule code.
      `tests/info-icons.js` 40/40 at 375x812, 320x568 and a 1366x768 desktop frame (bubble kept inside the stage).
      Regression the same day: pair-capture-split 151/151, team-rules 28/28, pair-rules 25/25, daily-rewards 32/32,
      snakes-ladders 51/51 (jungle scene only), scene buy / refuse / equip and sound switch spot checks, home visual
      suite PASS (0.000%). Built; **not deployed**.
- [x] Splash redesign (2026-10-21): supplied Brandmark.svg | rule | Logo.svg (inserted verbatim, verified element by
      element), centred and responsive; polished real-progress bar (essential / optional tasks, no timer cap, 99% max until
      done), 450 ms completion sweep + logo highlight, single fade to welcome; failure -> message + Retry (tested with a
      copy that throws while loading the save; Retry reloads). Checked 375x812, 320x568, 844x390, 1366x768; home visual suite
      PASS (0.000%). Built; **not deployed**.
- [x] Shop preview (2026-10-21): View on every Shop Rooms / Scenes card (beside Buy / Use / In use; Inventory, Dice,
      Coins unchanged) opens a full-screen 3D preview of the real room (café scene, room switched in, own orbit camera)
      or the real S&L scene (Jungle.previewOpen), drawn into the see-through box while the café render pauses. Drag /
      pinch / wheel / +/- / reset, eased; room limits ray-checked in all 5 rooms; scene framing pieces hidden off the
      landing angle. Buy from the preview (owned, not equipped -> Use), Use equips; insufficient coins refused; closing
      restores the room / scene in use; fallback thumbnail + Retry. `tests/shop-preview.js` 42/42; info 40/40, daily 32/32,
      S&L 51/51, team 28/28; purchase persisted across a real reload; 320x568, 375x812, 1366x768 frame; home visual
      suite PASS. Built; **not deployed**.
- [x] Shop preview layout fix (2026-10-21, user's Candy Kingdom screenshot): black strips / white gaps / broken corners
      came from drawing into a see-through hole of the main canvas. Now one clipped rounded card; the 3D view has its
      own renderer + canvas (released on close); panel joined with consistent padding; square view (less empty space),
      table framed just below centre, hanging sign left out of the preview, hint moved bottom-left. Checked all 5 rooms
      + 6 scenes at 375x812; layout checks (card in frame, view joins panel, canvas fills view, X / tools inside and
      apart, no overflow) pass at 320x568, 375x812, 480x853, 600x900, 768x1024, 1366x768, 844x390. Room camera limits
      re-ray-checked. `tests/shop-preview.js` 44/44, info 40/40, S&L 51/51. Built; **not deployed**.
- [x] Eighth deploy (2026-10-21, on the user's request): everything marked "not deployed" above — Daily Reward + coin
      sound, S&L 3D gameplay + camera views, S&L pause menu, five premium scenes, feature info icons, new splash
      (Brandmark + Logo SVGs, real-progress bar, Retry), Shop preview (with the card layout fix). Verified live: all 6
      files match the build byte for byte (SHA256; index.html via `/` since Pages redirects /index.html); the splash
      ran to 100% only at the end and went to the welcome screen; as a guest, Shop > Scenes > View Candy Kingdom opened
      the card preview with its own 3D canvas (343x343) and Buy — 22K, closed cleanly (canvas released); no console
      errors at 375x812.
- [x] Bars polish (2026-10-22, user's marked screenshot): blue replaced by the café palette (honey/peach bars, peach-cream
      tiles, coral Home, teal "+", plum tracks); top row in three groups (cream profile capsule, coin pill, cream gear
      tile); five equal tab columns (no negative margins, Home raised by transform inside its column); badges centred
      above their icons; checked 320x568 to 1366x768 + landscape: equal tabs, gaps >= 5px, labels whole, badges clear of
      icons, top groups apart; all actions tested. Approved by the user; home baseline updated 2026-10-22 (APPROVALS.md).
      Not deployed.
- [x] Top + bottom bars redesign (2026-10-22, user's filled-game-UI reference; supersedes the unapproved cream nav of the
      same day): full-width solid blue bars painted on the home layer (`.home::before` top incl. safe area, `.home::after`
      bottom incl. safe area), so the header / tab bar boxes and every locked number stay the same. Top row restyled for
      blue (white name, navy XP / coin tracks, green "+", gold gear). Bottom: filled blue tiles with white labels, Home the
      raised coral active tile (transform, slightly wider), new outlined/shaded icons, glossy Free / Soon badges, press +
      tap flash (invisible when animations are frozen / reduced). Labels whole 320 px to the 220 px landscape frame; top
      row no overlap; profile, coins +, settings and all 5 tabs tested. **Home baseline not updated: awaiting approval.**
      Not deployed.
- [ ] Optional: drop Orbitron from the font list (unused since the splash redesign; needs a build with network for fonts).
- [ ] Online play (placeholder "coming soon").
- [ ] Real share and FB group actions, or remove them (share toast still mentions Facebook).
- [ ] Add "an opposing pair passes freely" to the in-game How to play text.
- [ ] Update `submission/SUBMISSION.md` (bundle now ~892 KB in 6 files) and retake its screenshots after the redesign.
- [ ] Swap `#brandLogo` for the user's own game-logo SVG once supplied (use unchanged).
- [ ] Support link (only if a support destination exists).
- [ ] Optional: Facebook Instant Games build (earlier plan, superseded by YouTube).
- [ ] Optional: delete obsolete `build/` and `ludo-royale-web.zip`.
- [ ] Optional: more tests (CPU, profile, other screens). Playwright could reuse `?vt=1` if Node is ever installed.
