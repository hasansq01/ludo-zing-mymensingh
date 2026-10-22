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

## Deploy (Cloudflare Pages, free plan)
Workers & Pages → Create → Pages → Upload assets → project `ludo-king-mymensingh` → upload `ludo-king-mymensingh-playables.zip` (or the `dist` folder) → Deploy.
Live URL: `https://ludo-king-mymensingh.pages.dev`. Re-deploy by uploading a new build to the same project.
