# Ludo Zing Mymensingh — YouTube Playables submission kit

## Live game
https://ludo-king-mymensingh.pages.dev — Cloudflare Pages (free plan), deployed from `ludo-king-mymensingh-playables.zip`.

## Where things go
- **Interest form** (early access, by application): https://docs.google.com/forms/d/e/1FAIpQLSdvdQ0lgIq2369aemj1O6w8R8FwGn9O5ARRGODDDUbVINCRJQ/viewform
  Page 1 asks for email, an acknowledgement and how you heard about Playables. Paste the live game URL wherever the form asks for a link to your game.
- After YouTube approves you, they give access to the Developer Portal and test suite. There you upload
  `ludo-king-mymensingh-playables.zip` (index.html at the root) and fill the metadata below.

## Title
Ludo Zing Mymensingh

## Short description
Classic Ludo on a cozy café table in 3D. Race your four pawns home against the computer or pass the phone to friends.

## Full description
Sit down at a round café table and play Ludo in 3D. Roll the dice, bring your pawns out on a 6, capture rivals and race all four tokens home. Play against up to three computer opponents or pass one device between 2–4 friends.

Pairs add a twist: land two of your pawns together to form a Pair that blocks single opponents and can only be captured by another Pair. Earn coins from wins and the daily spin, unlock dice styles, avatars, frames and achievements, and track your stats on your profile.

## Controls
- Touch or mouse: tap the dice to roll, tap a glowing pawn to move it.
- After an even roll with a Pair on the board, choose **Single** or **Pair**.
- Keyboard (optional): Space or Enter rolls, keys 1–4 move pawns, Esc closes dialogs.

## Category / audience
Board game · general audience 13+ · English · single player vs computer and local pass-and-play · no in-app purchases, no ads.

## Screenshots
- `screenshot-home-mobile.jpg` — main menu over the 3D café table (750×1624)
- `screenshot-gameplay-mobile.jpg` — a game in progress (375×812)
YouTube's design rules say thumbnails, titles and descriptions must not carry branding or logos, so use a gameplay screenshot (no logo) as the thumbnail.

## What the build already does for Playables
- Loads `https://www.youtube.com/game_api/v1` before any game code.
- `firstFrameReady()` while the loading screen shows; `gameReady()` once the menu is interactive.
- Saves profile and settings with `saveData` (only after `loadData` resolves); no browser storage inside YouTube.
- Follows `isAudioEnabled` / `onAudioEnabledChange`; hides the in-game mute switch inside YouTube.
- Stops rendering, timers, animations and sound on `onPause`; resumes on `onResume`; no Page Visibility API inside YouTube.
- No external requests: three.js and fonts ship in the bundle. No share prompts, community links, name entry or clipboard use inside YouTube.
- 802 KB initial bundle in 5 files, relative paths only, plain file names, touch + mouse, any aspect ratio, English.

## Open items for the review
- **Trademark:** "Ludo King" is a registered trademark of another game (Gametion). Playables trust & safety rules say games MUST NOT infringe third-party trademarks. The game is now "Ludo Zing Mymensingh" (logo and title updated 2026-10-21). The hosting URL slug still reads `ludo-king-mymensingh`; consider a new Pages project with a matching slug before applying.
- **Test suite:** the SDK is a no-op outside YouTube, so the integration can only be fully verified in YouTube's test suite after approval.
- **Icon placement:** YouTube overlays its own close/mute/menu controls; check in the test suite that the in-game pause and settings icons in the top corners don't sit next to them.
