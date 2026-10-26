# AdMob plugin (rewarded ads)

Godot Android v2 plugin, Kotlin, Engine singleton **`AdMob`**. Google Mobile Ads SDK (`play-services-ads` 25.5.0) and
the UMP consent SDK (`user-messaging-platform` 4.0.0). Rewarded ads only: no banners, no interstitials, and an ad is
shown only inside `show_rewarded()`. Contract: `server/ECONOMY_V1.md` section 5. GDScript wrapper:
`godot/scripts/net/ads.gd` (`Ads`, a safe stub off Android; its header says how the UI should use it).

## Methods (called by name from GDScript, run on the UI thread, never throw)

| Method | What it does |
|---|---|
| `initialize()` | `MobileAds.initialize`, once, only when UMP says ads may be requested. |
| `request_consent(test_device_hashed_id: String)` | UMP `requestConsentInfoUpdate` + `loadAndShowConsentFormIfRequired`; starts the SDK when allowed. Test device id may be `""`. |
| `show_privacy_options()` | The UMP privacy options form ("Privacy choices" in Settings). |
| `load_rewarded(unit_id: String)` | Loads one rewarded ad (not while one is loading; answers `rewarded_loaded` at once if one is ready). |
| `show_rewarded(user_id: String, custom_data: String)` | Sets `ServerSideVerificationOptions` (userId, customData) on the loaded ad, then shows it. The ad is used up. |
| `is_rewarded_ready() -> bool` | An ad is loaded and none is showing. |

## Signals

`consent_done(can_request_ads: bool, privacy_options_required: bool)`, `rewarded_loaded`,
`rewarded_failed(code: int, message: String)` (-1 no activity, -2 consent not given, else AdMob's code),
`rewarded_earned(type: String, amount: int)`, `rewarded_closed`, `rewarded_show_failed(code, message)` (-1 not loaded /
already showing). `Ads` relays them as `consent_done`, `loaded`, `failed`, `earned`, `closed`, `show_failed`, and
reloads after a close or failure with backoff 5 s, 15 s, 60 s.

## Files

| Path | What |
|---|---|
| `src/main/java/com/flipfold/ludozing/admob/AdMobPlugin.kt` | The plugin. |
| `godot/addons/admob/bin/{debug,release}/AdMob-*.aar` | Built AARs (tracked). |
| `godot/addons/admob/export_plugin.gd` | Adds the AAR, the two Maven dependencies and `<meta-data com.google.android.gms.ads.APPLICATION_ID>` (from the project setting `ludo_zing/ads/app_id`) for presets with `plugins/admob=true` and Gradle build. Skipped (with a warning) if the app id is empty: the Ads SDK crashes at start without it. |
| `godot/addons/admob/editor_plugin.gd`, `plugin.cfg` | Editor plugin (enabled in `project.godot`); registers the settings and the export plugin. |
| `tools/build-admob-plugin.sh` | Builds both AARs and copies them to `godot/addons/admob/bin/`. |
| `godot/tests/test_ads.gd` | Stub, fake-singleton relays, reload backoff, settings, export snippet. |

Presets: `Android` and `Android Release` have `plugins/admob=true`; `Android Emulator` has it `false` (no Gradle
build), so ads are the stub there.

## Build

`tools/build-admob-plugin.sh` (JDK 17+, Android SDK; defaults to Android Studio's JBR and `~/Library/Android/sdk`).
Needed only after changing the Kotlin or the versions; then commit the AARs. Changing a version: update
`build.gradle` and `ADS_DEPENDENCY` / `UMP_DEPENDENCY` in `godot/addons/admob/export_plugin.gd`.
`build.gradle` passes `-Xskip-metadata-version-check`: play-services-ads 25.x has Kotlin 2.3 metadata in internal
files, Godot's template compiles with Kotlin 2.1.21, and we only use the Java API.

Check an export: `aapt2 dump xmltree --file AndroidManifest.xml <apk>` shows the `APPLICATION_ID` meta-data and
`org.godotengine.plugin.v2.AdMob`; the dex has `com.flipfold.ludozing.admob.AdMobPlugin`.

## Real ads: what the owner must provide

Until then the project uses Google's public **test** ids (they always fill and never pay):

- `ludo_zing/ads/app_id` = `ca-app-pub-3940256099942544~3347511713`
- `ludo_zing/ads/rewarded_unit` = `ca-app-pub-3940256099942544/5224354917`

For production:

1. An AdMob account with the app (`com.flipfold.ludozing`) added: gives the **app id** (`ca-app-pub-XXXX~YYYY`).
2. A **rewarded ad unit** in that app (`ca-app-pub-XXXX/ZZZZ`), with **server-side verification** on and the callback
   URL `https://ludo-zing-rooms.flipfold.workers.dev/v1/ads/ssv`. Put both ids in `project.godot` `[ludo_zing]`.
3. In AdMob: a UMP consent message (Privacy & messaging) for the EEA / UK and the US states, published.
4. Play Console: the Advertising ID declaration and Data safety answers for ads (the SDK adds
   `com.google.android.gms.permission.AD_ID`). Link the app to the store listing in AdMob (app-ads.txt if there is a
   developer site).
5. In dev, to force the consent form: set `ludo_zing/ads/test_device` to the hashed id logcat prints
   (`Use new ConsentDebugSettings.Builder().addTestDeviceHashedId("...")`). Never ship real-id test taps: use test ids
   or register your phone as an AdMob test device.

Logcat: `adb logcat -s AdMob:V Ads:V GodotPluginRegistry:V godot:V`
