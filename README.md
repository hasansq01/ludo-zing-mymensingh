# Ludo Zing Mymensingh

A 3D Ludo game (plain HTML + three.js r128, one page). `index.html` is the source; it also runs as a Claude artifact.

## Build
```bash
powershell -ExecutionPolicy Bypass -File tools\build.ps1
```
Creates `dist/` (self-contained: index.html, three.min.js, fonts) and `ludo-king-mymensingh-playables.zip`.
Third-party files are downloaded once into `vendor/`. The build fails if it finds external requests, bad file names or oversize files.

## Test locally
```bash
powershell -ExecutionPolicy Bypass -File tools\serve.ps1
```
Then open http://localhost:8080/.

Home-screen regression tests (locked design, see `tests/visual/README.md`):
```bash
powershell -ExecutionPolicy Bypass -File tests\visual\run.ps1
``` Pair-rule tests: `tests/pair-rules.js` , Pair Mode (teams) tests: `tests/team-rules.js` and Snakes & Ladders tests: `tests/snakes-ladders.js` (both need the test hook, so run them against the source `index.html` with `?vt=1`, not `dist/`).

## Deploy (Cloudflare Pages, free plan): automatic
Every push to GitHub builds the web game and publishes it (`.github/workflows/deploy-web.yml`), so the website always
matches GitHub; no zip upload by hand.
- `main` → the live site, `https://ludo-king-mymensingh.pages.dev`
- any other branch → its own link, `https://<branch>.ludo-king-mymensingh.pages.dev` (`Skin` → `skin.`, `feature/emotes` → `feature-emotes.`)
- add `?demo=1` to any link for the demo version; Settings › Account › Version shows the branch and commit a page runs.
- the run's summary (GitHub › Actions) lists the links, and its artifact is the Playables zip.

One-time setup (GitHub › repository Settings › Secrets and variables › Actions › New repository secret):
1. `CLOUDFLARE_ACCOUNT_ID`: Cloudflare dashboard › Workers & Pages › the Account ID on the right.
2. `CLOUDFLARE_API_TOKEN`: Cloudflare › My Profile › API Tokens › Create Token › Custom token, permission
   Account › Cloudflare Pages › Edit.

Until both exist the run still builds (and keeps the zip) but publishes nothing and says why. By hand, if ever needed:
Workers & Pages → project `ludo-king-mymensingh` → Create deployment → upload `ludo-king-mymensingh-playables.zip`.
