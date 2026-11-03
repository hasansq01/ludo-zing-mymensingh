# Play Games Services v2 plugin (Android)

Our own Godot 4.7 Android plugin (v2 plugin architecture) for Google Play Games Services v2: sign-in, a server
auth code for the game server, player name/id for the UI, leaderboards and achievements. Design context:
`server/ONLINE_V2.md` sections 1 (identity) and 7 (Play Games).

## Pieces

| Path | What |
| --- | --- |
| `godot/android/plugins/play_games/` | Kotlin library module (this folder). Gradle wrapper 8.11.1, AGP 8.6.1, Kotlin 2.1.21, Java 17, compileSdk 36, minSdk 24: the same versions as the Godot 4.7.2 build template. It compiles against `org.godotengine:godot:4.7.2.stable` (Maven Central, compile-only) and `com.google.android.gms:play-services-games-v2:22.1.0` (Google Maven). |
| `src/main/java/com/flipfold/ludozing/playgames/PlayGamesPlugin.kt` | The plugin class (`GodotPlugin`). Engine singleton **`PlayGamesPlugin`**. It is not called `PlayGames` because a singleton with that name would hide the GDScript `class_name PlayGames` in every script. |
| `src/main/AndroidManifest.xml` | `org.godotengine.plugin.v2.PlayGamesPlugin` meta-data, which is how Godot finds the plugin class. |
| `godot/addons/play_games/bin/{debug,release}/PlayGames-*.aar` | The built AARs. They are checked in, so exports work without building the plugin first. |
| `godot/addons/play_games/export_plugin.gd` | `EditorExportPlugin`. It adds the AAR, the Maven dependency and the manifest entries to Gradle Android exports. |
| `godot/addons/play_games/editor_plugin.gd`, `plugin.cfg` | Editor plugin, enabled in `project.godot` `[editor_plugins]`. It registers the export plugin and the project settings below. |
| `godot/scripts/net/play_games.gd` | `class_name PlayGames`: the GDScript wrapper the game uses. It is a safe stub when the plugin is missing or disabled. |
| `godot/tests/test_play_games.gd` | Tests for the stub, for how plugin signals are mapped (using a fake singleton) and for the manifest snippet. |
| `tools/build-play-games-plugin.sh` | Rebuilds both AARs and copies them into `addons/play_games/bin/`. |

`godot/android/plugins/.gdignore` stops Godot's importer from scanning the Kotlin and Gradle files.

## How it works

1. **Export.** The `Android` and `Android Release` presets have `plugins/play_games=true`. The `Android Emulator` preset has it set to `false`: that preset doesn't use the Gradle build, and v2 plugins need it. For an enabled Gradle preset, `export_plugin.gd` returns three things:
   - `_get_android_libraries`: `play_games/bin/debug/PlayGames-debug.aar` or `play_games/bin/release/PlayGames-release.aar`.
   - `_get_android_dependencies`: `com.google.android.gms:play-services-games-v2:22.1.0`. Gradle fetches it from Google Maven during the export.
   - `_get_android_manifest_application_element_contents`: depends on the project setting `ludo_zing/play_games/app_id`.
     - **Set**: adds `<meta-data android:name="com.google.android.gms.games.APP_ID" android:value="1…"/>`. The first digit is written as a `\u003X` escape. Without it, aapt stores the numeric id as an integer and the Games SDK, which reads a string, can't find it. With it, aapt stores the string. This was verified with `aapt2 dump xmltree`.
     - **Empty (the default; no real ids exist yet)**: no APP_ID, and the SDK's `PlayGamesInitProvider` is removed with `tools:node="remove"`. Nothing in the Games SDK runs. This matters because any Games call without an APP_ID ends in a fatal "developer error".
2. **Runtime (Kotlin).**
   - `onMainCreate` reads the APP_ID from the app's manifest meta-data.
   - If the APP_ID is set, it checks Play services (`GoogleApiAvailability`) and calls `PlayGamesSdk.initialize(activity)` once.
   - Logcat tag `PlayGames` shows `plugin loaded: app_id …` and `setup: …`.
   - When disabled, every method answers with error `"disabled"` and the Games SDK is never touched.
   - Every async method answers with exactly one signal. Results come from Play services tasks; `emitSignal` hands them to Godot's render thread.
3. **Runtime (GDScript).** `PlayGames.new()` wraps `Engine.get_singleton("PlayGamesPlugin")` when it exists, otherwise it is a stub. Answers are always deferred, never delivered inside the call that asked.

### Plugin API (Kotlin → GDScript)

| Method | Answer (signal) |
| --- | --- |
| `initialize(): bool` | `initialized(enabled, reason)`. `reason` is `""`, `no_app_id`, `no_activity`, `no_play_services:<n>` or `error:<m>`. |
| `isEnabled(): bool`, `getStatus(): Dictionary` | Synchronous. `getStatus()` returns `{app_id_set, play_services, initialized, error, sdk_int}`. |
| `isAuthenticated()` | `auth_checked(authenticated, error)`. PGS v2 signs in automatically at launch. |
| `signIn()` | `sign_in_completed(success, error)`, with `error` = `canceled` when the player backs out. |
| `requestServerSideAccess(webClientId, forceRefreshToken)` | `server_auth_code_completed(success, code, error)` |
| `getPlayerInfo()` | `player_info_completed(success, {display_name, player_id}, error)`. For the UI only: the server derives the real id. |
| `submitScore(leaderboardId, score: long)` | `score_submitted(id, success, error)`. Uses `submitScoreImmediate`. |
| `showAllLeaderboards()`, `showLeaderboard(id)`, `showAchievements()` | `ui_completed(kind, opened, error)`, then `ui_closed(kind)` |
| `unlockAchievement(id)` | `achievement_unlocked(id, success, error)` |

Error codes: `disabled`, `no_activity`, `canceled`, `not_signed_in`, `no_web_client_id`, `api:<CommonStatusCodes>`, `error:<message>`.

### Wrapper API (`PlayGames`, `res://scripts/net/play_games.gd`)

**Methods:**
- `is_available()`
- `status()`
- `check_signed_in()`, which runs from `_ready` unless `auto_check` is false
- `sign_in()`
- `request_server_auth_code(web_client_id := "", force_refresh := false)`. An empty `web_client_id` uses the project setting `ludo_zing/play_games/web_client_id`.
- `submit_score(board_id, value)`
- `show_leaderboards(board_id := "")`
- `show_achievements()`
- `unlock_achievement(id)`

**Signals:**
- `signed_in(player)`
- `signed_out`, from the automatic check: show the manual button
- `sign_in_failed(code)`
- `server_auth_code(code)`, `server_auth_code_failed(code)`
- `score_submitted(id, ok, error)`
- `achievement_unlocked(id, ok, error)`
- `ui_failed(kind, error)`, `ui_closed(kind)`

The stub, and the plugin when disabled, answer `"unavailable"`. `reason` tells you why:
- `no_plugin`: desktop, headless or the emulator preset
- `no_app_id`
- `no_play_services:<n>`
- `error:<m>`

Server flow (ONLINE_V2 §1): `sign_in` / automatic sign-in → `request_server_auth_code()` → `POST /v1/auth/google {server_auth_code}` with the guest session. Auth codes are single-use and short-lived, so request a new one for each link attempt.

## Rebuild

```sh
tools/build-play-games-plugin.sh          # assembleDebug + assembleRelease, copies the AARs to godot/addons/play_games/bin/
tools/build-play-games-plugin.sh --clean
```

- **Requirements:** the Android SDK (`ANDROID_HOME`, default `~/Library/Android/sdk`) and JDK 17+ (`JAVA_HOME`, default: Android Studio's JBR).
- **First run:** Gradle downloads AGP, Kotlin, godot-lib and play-services-games-v2 from Google Maven and Maven Central.
- **When to rebuild:** only after changing the Kotlin source or the versions. Then commit the new AARs.
- **Changing the games-v2 version:** update both `playGamesVersion` in `build.gradle` and `PLAY_GAMES_DEPENDENCY` in `godot/addons/play_games/export_plugin.gd`. The second is what the app actually links.
- **Godot upgrade:** change `godotVersion` in `build.gradle` to match `godot --version`. Check `godot/android/build/config.gradle` for new AGP, Kotlin or SDK versions.

Then `tools/android-build.sh` (debug APK) or `tools/android-release.sh` (AAB) as usual. To check that it's in:
`aapt2 dump xmltree --file AndroidManifest.xml <apk>` should list `org.godotengine.plugin.v2.PlayGamesPlugin`. With an APP_ID set it should also list `com.google.android.gms.games.APP_ID` as a quoted string.

Logcat: `adb logcat -s PlayGames:V GodotPluginRegistry:V godot:V`

## Signing certificate fingerprints

These are public values, not secrets.

| Key | Where | SHA-1 | SHA-256 |
| --- | --- | --- | --- |
| Upload key (alias `ludozing`, `CN=Flipfold Studio`) | `~/.android/ludo-zing-release/upload.jks` | `4F:B2:B3:7D:92:3F:F6:65:AE:AB:E3:2B:09:8B:00:7F:8A:6B:14:D4` | `CF:BC:8F:D5:DC:0F:5C:FB:59:87:65:9D:C6:09:A3:A8:E6:DD:4F:CD:A5:6E:16:ED:12:27:2E:2A:30:84:29:04` |
| Debug key (alias `androiddebugkey`), which signs `tools/android-build.sh` APKs | `~/.android/debug.keystore` | `AB:48:8C:90:90:E1:09:B9:31:08:5B:43:83:F5:4C:D8:FA:14:00:98` | `07:D4:BC:94:DA:C4:FE:51:AA:CD:F0:3F:A0:22:71:B2:5E:BD:7A:B5:80:BB:C1:5B:64:D4:C1:E8:D6:17:AE:29` |
| Play app signing key | Created by Google on the first AAB upload | Copy it from the Play Console (step 2) | — |

The debug fingerprint is only valid for this machine's `debug.keystore`. Another developer's debug key needs its own Android credential.

To recompute without printing passwords:

```sh
P=~/.android/ludo-zing-release/upload-key.properties
KSPASS="$(sed -n 's/^password=//p' "$P")" keytool -list -v -keystore "$(sed -n 's/^keystore=//p' "$P")" \
  -alias "$(sed -n 's/^alias=//p' "$P")" -storepass:env KSPASS | grep -E 'SHA1|SHA256'
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android | grep -E 'SHA1|SHA256'
```

## Owner setup: Play Console and Google Cloud

The owner does these steps once. Nothing in the repo holds a real id until step 9.

1. **Create the app.** In the Play Console, choose **Create app**: name "Ludo Zing", type Game, free. The package name `com.flipfold.ludozing` is fixed by the first upload.
2. **Turn on Play App Signing.** Build `tools/android-release.sh`. Upload `build/android/ludo-zing-release.aab` to **Test and release → Testing → Internal testing**, which turns on Play App Signing by default.
   Then open **Test and release → Setup → App signing** (called "App integrity" in some Console versions). Copy the **App signing key certificate SHA-1**. The upload key certificate shown there should match the upload SHA-1 above.
3. **Create the Play Games Services project.** Go to **Grow users → Play Games Services → Setup and management → Configuration** and choose **Create new Play Games Services project**.
   - Pick the Google Cloud project to link. Let the Console create one, or use the one for the server if it exists.
   - The page now shows the **Project ID**, a numeric id of about 12 digits. That is the **APP_ID**.
4. **Set up the OAuth consent screen.** In Google Cloud Console → **Google Auth Platform** (formerly "APIs & Services → OAuth consent screen") for the linked project:
   - Audience **External**
   - App name "Ludo Zing", user support email, developer contact email
   - App domain / privacy policy URL (required before publishing)
   - Scopes: PGS needs no extra scopes. The server uses the `games_lite` / default Play Games scope that comes with the server auth code.
   - While the app is in **Testing**, add the tester Google accounts, or publish the consent screen.
5. **Add Android credentials.** In Play Console → Play Games Services → Configuration → **Credentials → Add credential → Android**. Create one Android OAuth client per signing key, each with package `com.flipfold.ludozing`:
   - (a) **Play app signing key** SHA-1, from step 2. This one is for builds installed from Play.
   - (b) **Upload key** SHA-1 `4F:B2:B3:7D:92:3F:F6:65:AE:AB:E3:2B:09:8B:00:7F:8A:6B:14:D4`. This one is for a release-signed build sideloaded directly.
   - (c) **Debug key** SHA-1 `AB:48:8C:90:90:E1:09:B9:31:08:5B:43:83:F5:4C:D8:FA:14:00:98`. This one is for `tools/android-build.sh` debug APKs.

   Either use "Create OAuth client" in the Console dialog, or create the client in Cloud Console → Credentials → Create OAuth client ID → Android with the same package and SHA-1, then select it in the Play Console. Turn on anti-piracy only on (a) if you want it: with anti-piracy, sideloaded builds can't sign in.
6. **Add the Web credential** for the server auth code. In Configuration → **Add credential → Game server**, create a **Web application** OAuth client in the same Cloud project. No redirect URIs are needed for the server auth code exchange. Copy:
   - the **Web client ID** (`….apps.googleusercontent.com`)
   - the **Client secret**
7. **Add testers.** In Play Games Services → **Testers**, add the Google accounts that should be able to sign in before PGS is published.
8. **Create leaderboards.** In Play Games Services → **Leaderboards → Create leaderboard**: name, icon, score format Numeric, ordering "Larger is better", and limits. Repeat for each board ONLINE_V2 §4 calls for (for example wins, or coins/XP).
   Copy each **leaderboard ID** (`CgkI…`). **Get resources** exports them all. Achievements are optional; create them the same way if wanted.
9. **Put each id in its place:**

   | Id | Where it goes |
   | --- | --- |
   | **APP_ID** (step 3) | `godot/project.godot`, under `[ludo_zing]` add `play_games/app_id="<numeric id>"`, or set it in Project Settings → Ludo Zing → Play Games → App Id. Empty = disabled. `override.cfg` is *not* read by command-line exports (tested), so set it in `project.godot`. |
   | **Web client ID** (step 6) | Server secret `GOOGLE_WEB_CLIENT_ID` (`npx wrangler secret put GOOGLE_WEB_CLIENT_ID`). Client config: `ludo_zing/play_games/web_client_id` in `project.godot`; it is not a secret. |
   | **Client secret** (step 6) | Server secret `GOOGLE_WEB_CLIENT_SECRET` only. Never put it in the client or the repo. |
   | **Leaderboard / achievement IDs** (step 8) | Client config. They are not secrets; the lead decides where: constants or config next to the online code. |

10. **Publish PGS.** When the game ships, open Play Games Services → **Review and publish** and publish the PGS configuration. Unpublished PGS only works for testers. The Console's checklist lists anything still missing, such as icons, a privacy policy or a minimum number of achievements.

Checks once the ids are in:
- A debug build on a device or emulator with a tester account shows `PlayGames: setup: play_services=0 sdk initialized` in logcat.
- `sign_in()` signs in.
- `request_server_auth_code()` returns a code.

`api:10` (DEVELOPER_ERROR) almost always means one of these doesn't match the APK's signing key and package: the SHA-1, the package name or the APP_ID.

## Tested behaviour (2026-10-24, emulator `sdk_gphone64_arm64`, API 35, Google Play image, no Google account)

- **APP_ID empty (the committed state).**
  - The plugin registers (`GodotPluginRegistry: Initializing Godot plugin PlayGamesPlugin`) and logs `plugin loaded: app_id not set (disabled)`.
  - The wrapper reports `available=false reason=no_app_id`.
  - Every request answers `unavailable`.
  - The launch check gives `signed_out`.
  - No crash and no script errors.
- **Dummy APP_ID** (only in a throw-away copy of the project, never committed).
  - Logs `setup: play_services=0 sdk initialized`. Play services downloaded its Games module on demand.
  - The automatic check gives `signed_out`.
  - The manual `sign_in()` opens Google's sign-in / add-account flow (`SignInActivity` → account setup).
  - No crash.
  - A real sign-in needs the ids from the steps above plus a tester account on the device.
