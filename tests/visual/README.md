# Home screen regression safeguard (LOCKED design)

The home screen approved on 2026-10-19 is locked. These tests fail if anything changes its look or layout.

## Run
```
powershell -ExecutionPolicy Bypass -File tests\visual\run.ps1              # build, then test
powershell -ExecutionPolicy Bypass -File tests\visual\run.ps1 -SkipBuild   # test the current dist/
```
Exit code 0 = pass, 1 = fail. About a minute. Needs only Windows PowerShell and Chrome (or Edge); no Node or Python.

## What it checks
1. **Screenshot** of the home screen at **390×844**, compared pixel by pixel with `baseline/home-390x844.png`
   (fails if more than 0.5% of pixels differ; a diff image is written to `output/home-390x844.diff.png`, red = changed).
   Covers the logo, the 3D table and camera angle, game buttons, HUD, side controls and bottom navigation.
2. **Layout checks** (`vt-checks.js`) at 390×844, 320×568, 430×932, 844×390 (landscape), 768×1024 and 1366×768:
   HUD / logo / side controls / 5 tabs visible inside the screen; both game buttons visible, tappable, in one row,
   equal size, VS COMPUTER left and PASS & PLAY right, labels not clipped, equal outer margins, ≥ 12px above the bottom
   navigation; table below the logo and side controls, above the buttons, fully on screen; nothing overflows; no scrolling.
3. **Locked numbers** at 390×844: buttons 177×62, 12px apart and 12px from the edges, 46px above the bottom navigation;
   camera tilt 33°; table 99% wide, rim from 38.8% to 70.0% of the screen height.

## How it works
- `index.html?vt=1` is a test-only mode: seeded randomness (the room props come out the same every run), frozen camera
  orbit, animations and lighting flicker, no saved progress, straight to the home screen. It then loads `vt-checks.js`,
  which reports into `document.title` and a `#vt-report` JSON block. Without `?vt=1` none of this runs.
- `run.ps1` builds `dist/`, serves it, starts headless Chrome with software WebGL (SwiftShader, so frames are identical
  run to run), and drives it over the DevTools protocol (exact viewport emulation, the same way Playwright does).
  `vt-checks.js` is copied into `dist/` only while the tests run; it is never part of the release zip.

## Rules
- The locked home screen (layout, camera settings, scene transforms, UI sizes, colours, spacing) must not change during
  unrelated work. Run these tests after any change, before reporting it done, and report failures. Don't hide them.
- **Never** update the baseline or the numbers in `vt-checks.js` just to make a failing test pass.
- Only after the user explicitly asks for a visual change, the change is implemented and tested, **and the user approves it**:
  ```
  powershell -ExecutionPolicy Bypass -File tests\visual\run.ps1 -UpdateBaseline -Approval "Approved by <name> on <date>: <what changed>"
  ```
  This refuses to run without an approval note or while layout checks fail, and it records the note in
  `baseline/APPROVALS.md`. Update the LOCK numbers in `vt-checks.js` in the same approved change if they moved.
- If Playwright (Node) is installed later, the same `?vt=1` mode and checks can be reused from a Playwright test.
