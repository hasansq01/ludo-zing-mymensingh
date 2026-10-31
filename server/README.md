# Ludo Zing online rooms (Cloudflare)

Friend rooms for Ludo: a Cloudflare Worker with one Durable Object per room code. Free plan. Spec: `PROTOCOL.md`.

- Live: `https://ludo-zing-rooms.flipfold.workers.dev` (`wss://` for the room socket).
- Rules: `src/rules/` is a line-for-line TypeScript port of `godot/scripts/core/ludo_rules.gd`; `test/rules_parity`
  replays GDScript-recorded games (`godot/dev/net_parity_dump.gd` regenerates `test/fixtures/ludo_traces.json`).
  Any change to `ludo_rules.gd` must be mirrored here and the traces regenerated.

## Commands (from `server/`)

| | |
|---|---|
| `npx vitest run` / `npx tsc --noEmit` | tests (rules, parity, rooms) / typecheck |
| `npx wrangler dev --port 8787` | local server (emulator: `ws://10.0.2.2:8787`) |
| `node tools/sim.mjs --url ws://localhost:8787 --players 4` | N scripted clients play a full room game |
| `node tools/friend.mjs CODE` | a scripted friend joins your room (phone/emulator) and plays its turns |
| `tools/cf.sh deploy` / `tools/cf.sh tail` | deploy / live logs, with this project's own Cloudflare login |

## Admin console (`ADMIN_API.md`)

`/admin` on the same Worker: rooms, players (bans, notes), matches, events, config (maintenance, message of the
day, turn timers). Data in D1 `ludo-zing-admin` (`migrations/`); console files in `admin/` (static, no build).

- Deploy setup (once): `tools/cf.sh d1 migrations apply ludo-zing-admin --remote`, then
  `tools/cf.sh secret put ADMIN_PASSWORD`, then `tools/cf.sh deploy`. Without the secret the API answers 503.
- Rewarded ads via LevelPlay: `tools/cf.sh secret put LEVELPLAY_S2S_KEY` (the private key of the app's S2S callback
  in the LevelPlay dashboard). Without it `/v1/ads/levelplay` answers 503 and LevelPlay retries (ECONOMY_V1.md §2).
- Local: `cp .dev.vars.example .dev.vars` (git-ignored; `ADMIN_PASSWORD=dev-password-change-me`),
  `npx wrangler d1 migrations apply ludo-zing-admin --local`, `npx wrangler dev --port 8787`, open
  `http://localhost:8787/admin` (use `localhost`, not a LAN IP: the session cookie is `Secure`).
- Seed local data: with the dev server running, `node tools/seed-local.mjs` (applies local migrations, writes 14
  days of synthetic history incl. a banned player and events, plays 4 sim games; `--games N`, `--live` keeps a
  lobby and a bot match open until Ctrl-C, `--wipe` empties the local tables, `--no-history`). It only ever runs
  wrangler with `--local`. Note: `wrangler dev` reloads when files change, which drops sockets (sims then time out).
- Tests: `test/admin_*.test.ts` (D1 migrations applied by `test/setup.ts`; the password binding is in
  `vitest.config.ts`).

`tools/cf.sh login` if the project login (in `.wrangler/home`, git-ignored) expires. The Godot side:
`godot/scripts/net/*`; headless E2E: `godot --headless --path godot -s res://dev/net_e2e.gd -- --net=wss://...`.
