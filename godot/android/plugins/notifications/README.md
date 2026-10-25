# Notifications plugin (Android)

Our own Godot 4.7 Android plugin (v2 plugin architecture) for notifications: local ones (daily reward, free spin,
free coins, come-back nudges) scheduled with AlarmManager, and push through Firebase Cloud Messaging (your turn,
friend joined, rematch, weekly result, admin campaigns). Design context: `server/NOTIFICATIONS.md` (the shared
contract: ids, channels, links, "N-PLUG") and `server/ONLINE_V2.md` section 8.

Push is off until a Firebase project exists: with the four `ludo_zing/push/*` settings empty (the committed state)
no Firebase code runs and local notifications work as usual.

## Pieces

| Path | What |
| --- | --- |
| `godot/android/plugins/notifications/` | Kotlin library module (this folder). Gradle wrapper 8.11.1, AGP 8.6.1, Kotlin 2.1.21, Java 17, compileSdk 36, minSdk 24: the same versions as the Godot 4.7.2 build template. It compiles against `org.godotengine:godot:4.7.2.stable` (compile-only) and `com.google.firebase:firebase-messaging:26.0.1` (Google Maven; the version in firebase-bom 35.1.0). |
| `src/main/java/com/flipfold/ludozing/notifications/NotificationsPlugin.kt` | The plugin class (`GodotPlugin`). Engine singleton **`NotificationsPlugin`** (not `Notifier`, which would hide the GDScript `class_name Notifier`). |
| `Notifs.kt` | The schedule (SharedPreferences `lz_notifications`), the alarms, the four channels, posting, reading a tap back from the launch intent. |
| `Receivers.kt` | `AlarmReceiver` (a scheduled item is due: post it) and `BootReceiver` (`BOOT_COMPLETED`, `MY_PACKAGE_REPLACED`: arm the stored schedule again). |
| `PushService.kt` | `PushService` (`FirebaseMessagingService`: token refresh, messages) and `Push` (FirebaseApp from `FirebaseOptions`, saved for later processes). |
| `src/main/AndroidManifest.xml` | Plugin registration, `POST_NOTIFICATIONS` + `RECEIVE_BOOT_COMPLETED`, the receivers and the service, FCM's default icon / colour / channel meta-data. |
| `src/main/res/drawable/lz_notif_icon.xml` | The status-bar icon: a white die showing five (vector). `values/lz_notif.xml`: the accent colour (`Palette.GOLD_FILL`). |
| `godot/addons/notifications/bin/{debug,release}/Notifications-*.aar` | The built AARs. They are checked in, so exports work without building the plugin first. |
| `godot/addons/notifications/export_plugin.gd` | `EditorExportPlugin`: adds the AAR, the firebase-messaging Maven dependency and the removal of `FirebaseInitProvider` to Gradle Android exports. |
| `godot/addons/notifications/editor_plugin.gd`, `plugin.cfg` | Editor plugin, enabled in `project.godot` `[editor_plugins]`. It registers the export plugin and the project settings `ludo_zing/push/project_id`, `app_id`, `api_key`, `sender_id`. |
| `godot/scripts/net/notifier.gd` | `class_name Notifier`: the GDScript wrapper the game uses. A safe stub when the plugin is missing. |
| `godot/tests/test_notifier.gd` | Tests for the stub, for how plugin calls and signals are mapped (fake singleton), the push settings and the export plugin. |
| `tools/build-notifications-plugin.sh` | Rebuilds both AARs and copies them into `addons/notifications/bin/`. |

## How it works

1. **Export.** The `Android` and `Android Release` presets have `plugins/notifications=true` (and the permissions
   `post_notifications`, `receive_boot_completed`, which the AAR manifest declares as well). The `Android Emulator`
   preset has it `false`: it doesn't use the Gradle build, which v2 plugins need, so that APK has neither the plugin
   nor Firebase, and `notifier.gd` is a stub there (as on desktop). For an enabled Gradle preset `export_plugin.gd`
   returns the AAR, `com.google.firebase:firebase-messaging:26.0.1`, and
   `<provider android:name="com.google.firebase.provider.FirebaseInitProvider" tools:node="remove"/>`: without
   google-services.json that provider would only log that it can't initialise, and we initialise Firebase ourselves.
   The AAR's manifest sets `com.google.firebase.messaging.default_notification_icon` / `_color` /
   `_channel_id` (`game`), so a push the system shows uses our icon, and the `game` channel when it names none.
2. **Local notifications.** `schedule(id, at_unix, channel, title, body, link)` stores the item and arms an inexact
   `AlarmManager.setAndAllowWhileIdle(RTC_WAKEUP)` (no `SCHEDULE_EXACT_ALARM`: Android may fire it some minutes late,
   also in Doze). `AlarmReceiver` posts it on its channel (unknown channel -> `reminders`) and forgets it. A reboot
   or an app update re-arms what is stored; items already past are dropped. `cancel` / `cancel_all` also take an
   already shown local notification out of the shade. Push notifications are never touched by them.
3. **Channels** (created at plugin load and before every post): `rewards` "Rewards", `reminders` "Reminders",
   `game` "Game alerts" (high importance: heads-up), `offers` "News & offers".
4. **Taps.** Our notifications open the launcher activity with the extras `lz_link`, `lz_source` (`local` | `push`)
   and, for push, `lz_cid`. A push shown by the system (game in the background) opens it with the message data as
   extras (`link`, `cid`, `kind`) and FCM's `google.message_id`, which the plugin reads as `source: "push"`.
   godot-lib 4.7.2 has no `onNewIntent` hook for plugins (`GodotPlugin` offers `onMainCreate`, `onMainResume`, ...),
   but `GodotActivity.onNewIntent` calls `setIntent()` and Android always resumes the activity afterwards, so the
   plugin reads `activity.intent` in `onMainCreate` (cold start) and `onMainResume` (brought back), then removes the
   markers so the same tap is never read twice; a relaunch from recents (`FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY`) is
   ignored. The tap is kept for `take_launch_data()` and, when the game was already running, also signalled as
   `opened`; the wrapper makes sure the game gets it exactly once.
5. **Permission.** Android 13+ needs `POST_NOTIFICATIONS` at runtime: `request_permission()` shows the system dialog
   (the game asks after a soft prompt, never at launch). Below 13 there is nothing to ask.
6. **Push.** `push_init(project_id, app_id, api_key, sender_id)` checks Play services, builds `FirebaseOptions`,
   initialises the default `FirebaseApp`, saves the options (so `PushService` can initialise the same app in a
   process the game didn't start: a message arriving while the game is closed) and fetches the token ->
   `push_token`. FCM shows notification messages itself while the game is in the background. While the game is the
   resumed activity a message becomes `push_received` and nothing is shown; a data-only message, or one arriving
   while the game is paused, is posted by `PushService` on its channel with the `lz_*` extras.
7. **Runtime (GDScript).** `Notifier.new()` wraps `Engine.get_singleton("NotificationsPlugin")` when it exists,
   otherwise it is a stub. Signal answers are always deferred, never delivered inside the call that asked.

Logcat tag `Notifications`: `plugin loaded: sdk 35, permission ask, 0 scheduled, push off`, `fire <id>: posted on
<channel>`, `opened from a local notification (link daily)`, `push: firebase initialised, fetching token`.

### Plugin API (Kotlin -> GDScript; the wrapper has the same names)

| Method | Answer |
| --- | --- |
| `permission_state(): String` | `granted` \| `denied` \| `ask` \| `unsupported` (synchronous). `ask` = the system dialog can be shown (never asked, or refused once: Android 13+ allows a second ask). `denied` = it can't any more, or the app's notifications are off in the settings. Below Android 13: `granted` unless they are off (`denied`). |
| `request_permission()` | `permission_result(granted)`; at once below Android 13 or when already granted. |
| `schedule(id, at_unix: long, channel, title, body, link)` | none (replaces the same id) |
| `cancel(id)`, `cancel_all()` | none (local only) |
| `scheduled(): PackedStringArray` | ids still to come |
| `take_launch_data(): Dictionary` | `{link, cid, source}` of the tap that opened the game, once; then `{}`. Also `opened(data)` when tapped while running. |
| `get_status(): Dictionary` | `{sdk_int, permission, scheduled, push_ready, push_saved}` |
| `push_init(project_id, app_id, api_key, sender_id)` | `push_token(token)` (also on every refresh) or `push_failed(code)` |
| `push_subscribe(topic)`, `push_unsubscribe(topic)`, `push_delete_token()` | only failures: `push_failed` |
| (a push while the game is on screen) | `push_received({title, body, link, cid, kind})` |

`push_failed` codes: `not_configured` (an empty value), `no_play_services:<ConnectionResult>`, `not_initialized`
(a topic / token call before `push_init`), `error:<m>` (no token; FCM's message such as `SERVICE_NOT_AVAILABLE`),
`subscribe:<m>`, `unsubscribe:<m>`, `delete:<m>`. The wrapper adds `unavailable` (no plugin).

### Wrapper API (`Notifier`, `res://scripts/net/notifier.gd`)

**Methods:** `is_available()`, `status()`, `permission_state()`, `request_permission()`,
`schedule(id, at_unix, channel, title, body, link)`, `cancel(id)`, `cancel_all()`, `scheduled() -> Array`,
`take_launch_data() -> Dictionary`, `push_configured() -> bool` and `push_settings() -> Dictionary` (static: the
project settings), `push_init_from_settings()`, `push_init(project_id, app_id, api_key, sender_id)`,
`push_subscribe(topic)`, `push_unsubscribe(topic)`, `push_delete_token()`.

**Signals:** `permission_result(granted)`, `opened(data)`, `push_token(token)`, `push_failed(code)`,
`push_received(data)`.

Use one `Notifier` in the game: a tap that arrives while the game runs goes to whichever instance takes it first
(`opened` on one, `{}` everywhere else).

**Stub (tests):** `stub_scheduled` (id -> `{id, at, channel, title, body, link}`), `stub_launch` (returned once by
`take_launch_data()`), `stub_permission` (default `unsupported`) and `stub_grant` (the answer when it is `ask`).

## Rebuild

```sh
tools/build-notifications-plugin.sh          # assembleDebug + assembleRelease, copies the AARs to godot/addons/notifications/bin/
tools/build-notifications-plugin.sh --clean
```

- **Requirements:** the Android SDK (`ANDROID_HOME`, default `~/Library/Android/sdk`) and JDK 17+ (`JAVA_HOME`,
  default: Android Studio's JBR).
- **When to rebuild:** only after changing the Kotlin source, the resources or the versions. Then commit the new AARs.
- **Changing the firebase-messaging version:** update both `firebaseMessagingVersion` in `build.gradle` and
  `FIREBASE_MESSAGING_DEPENDENCY` in `godot/addons/notifications/export_plugin.gd` (what the app actually links), and
  `play-services-base` in `build.gradle` to the version that firebase-messaging's POM names.
- **Godot upgrade:** change `godotVersion` in `build.gradle` to match `godot --version`.

Then `tools/android-build.sh` (debug APK) or `tools/android-release.sh` (AAB) as usual. To check that it's in:
`aapt2 dump xmltree --file AndroidManifest.xml <apk>` lists `org.godotengine.plugin.v2.NotificationsPlugin`,
`AlarmReceiver`, `BootReceiver`, `PushService`, and no `FirebaseInitProvider`.

Logcat: `adb logcat -s Notifications:V GodotPluginRegistry:V godot:V FirebaseApp:V FirebaseMessaging:V`

Handy checks on a device or emulator:
- `adb shell dumpsys alarm | grep -A3 com.flipfold.ludozing`: the armed alarms (`lznotif:<id>`).
- `adb shell dumpsys notification --noredact | grep -A20 com.flipfold.ludozing`: posted notifications and the channels.
- A tap without the shade: `adb shell am start -n com.flipfold.ludozing/com.godot.game.GodotAppLauncher --es lz_link daily --es lz_source local`.

## Owner setup: Firebase (later)

1. Firebase console -> add a project (or use the Google Cloud project of Play Games), add an **Android app** with the
   package `com.flipfold.ludozing`. Skip the google-services.json and SDK steps: we don't use the Gradle plugin.
2. From the app's settings (or the downloaded google-services.json) copy the four values into `godot/project.godot`
   under `[ludo_zing]` (or Project Settings -> Ludo Zing -> Push): `push/project_id` (`project_info.project_id`),
   `push/app_id` (`client[].client_info.mobilesdk_app_id`, `1:…:android:…`), `push/api_key`
   (`client[].api_key[].current_key`), `push/sender_id` (`project_info.project_number`). None of them is a secret
   (they ship in every APK); restrict the API key to the Android app in Google Cloud Console if wanted.
3. Server side: a service-account key for FCM, `tools/cf.sh secret put FCM_SERVICE_ACCOUNT` (see the contract).

Checks once the values are in: logcat shows `push: firebase initialised, fetching token` and the game receives
`push_token`; a test send from the console's Notifications page arrives (in the shade with the game in the
background, as `push_received` with it on screen).

## Tested behaviour (2026-10-25, emulator `sdk_gphone64_arm64`, API 35, Google Play image, debug Gradle export)

- Push settings empty (the committed state): `GodotPluginRegistry: Initializing Godot plugin NotificationsPlugin`,
  `Notifications: plugin loaded: sdk 35, permission ask, 0 scheduled, push off`; no FirebaseApp / FCM log lines, no
  crash. `push_init_from_settings()` answers `push_failed("not_configured")`.
- `request_permission()` shows "Allow Ludo Zing to send you notifications?"; Allow -> `permission_result(true)`,
  state `granted`.
- `schedule("probe_daily", now + 50 s, "rewards", ...)`: `dumpsys alarm` lists an `RTC_WAKEUP` alarm
  `*walarm*:com.flipfold.ludozing.notifications.FIRE` with a +37 s window; it fired 37 s after the time
  (`fire probe_daily: posted on rewards`), and `dumpsys notification` shows `channel=rewards`, `color=0xffffc93c`,
  `icon=... id=0x7f060018` (`drawable/lz_notif_icon`), `flags=AUTO_CANCEL`. Tapping it in the shade (game running)
  -> `opened {link: "daily", source: "local"}`, notification gone.
- Cold start with `--es lz_link spin --es lz_source local`: `take_launch_data()` = `{link: "spin", cid: "",
  source: "local"}`. Brought back with FCM-style extras (`google.message_id`, `link room:ABCD`, `cid c9`): `opened
  {link: "room:ABCD", cid: "c9", source: "push"}`.
- App update (`MY_PACKAGE_REPLACED`) re-armed the 4 stored items; the game's own schedule (cancel_all on resume,
  plan on pause) shows up as FIRE alarms.
- `push_init` with dummy values: `FirebaseApp: ... initializing all Firebase APIs`, then `push_failed("error:Please set
  a valid API key ...")`, no crash. Not tested: a real token and real messages (no Firebase project yet).
- APK size: +1.05 MB for the debug APK (firebase-messaging and its dependencies; dex 7.0 -> 9.7 MB uncompressed).
