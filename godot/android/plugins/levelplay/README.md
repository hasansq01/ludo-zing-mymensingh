# LevelPlay plugin (rewarded ads, primary network)

Godot Android v2 plugin, Kotlin, Engine singleton **`LevelPlay`**. Unity LevelPlay mediation SDK
(`com.unity3d.ads-mediation:mediation-sdk` 9.7.0, ad-unit API: `LevelPlay.init`, `LevelPlayRewardedAd`) with
**ironSource Ads only** (no mediation adapters yet), and Google's UMP consent SDK (`user-messaging-platform` 4.0.0,
the same form as the AdMob plugin). Rewarded ads only, shown only inside `show_rewarded()`. Contract:
`server/ECONOMY_V1.md` section 5. GDScript wrapper: `godot/scripts/net/ads.gd` (`Ads`).

`Ads` drives this plugin when it is in the build and AdMob's otherwise (project setting `ludo_zing/ads/provider`:
`auto` (default), `levelplay` or `admob` to force one). Both plugins have the same methods and signals.

## Methods (called by name from GDScript, run on the UI thread, never throw)

| Method | What it does |
|---|---|
| `initialize()` | `LevelPlay.init` with the app key, once, only when UMP says ads may be requested (again after a failed init). |
| `request_consent(test_device_hashed_id: String)` | UMP `requestConsentInfoUpdate` + `loadAndShowConsentFormIfRequired`; starts LevelPlay when allowed. |
| `show_privacy_options()` | The UMP privacy options form ("Privacy choices" in Settings). |
| `load_rewarded(unit_id: String)` | Loads one `LevelPlayRewardedAd` (waits for init; answers `rewarded_loaded` at once if one is ready). |
| `show_rewarded(user_id: String, custom_data: String)` | Sets `LevelPlay_Rewarded_Server_Params` `uid=<user_id>`, `nonce=<custom_data>`, then shows. The ad is used up. |
| `is_rewarded_ready() -> bool` | An ad is loaded and none is showing. |
| `set_test_suite(on: bool)` | Dev only: `is_test_suite` + adapters debug before init; the test suite opens when the SDK is ready. |
| `launch_test_suite()` | Opens the integration test suite again (after `set_test_suite(true)`). |

## Signals

The AdMob plugin's: `consent_done(can_request_ads, privacy_options_required)`, `rewarded_loaded`,
`rewarded_failed(code, message)` (-1 no activity, -2 consent not given, -3 no app key, else LevelPlay's load or init
error code), `rewarded_earned(type, amount)` (at most once per show), `rewarded_closed`,
`rewarded_show_failed(code, message)` (-1 not loaded / already showing, else LevelPlay's code).

## Consent and privacy

- UMP is the consent form (EEA / UK, and the US states message if published), shown by `request_consent()`. UMP
  stores the IAB TCF and Google Additional Consent strings, and LevelPlay reads them by itself (SDK 7.7.0+), so
  GDPR needs no extra call. LevelPlay is started only when `canRequestAds()` is true.
- Before init (and after the privacy options form): `LevelPlayPrivacySettings.setCOPPA(false)` (the app is 13+, not
  child-directed) and `setCCPA(...)` when an IAB US Privacy string (`IABUSPrivacy_String`) is stored. LevelPlay's docs
  don't say it reads GPP strings, so a US opt-out reaches it only through that string.
- UMP needs the AdMob application id meta-data. The AdMob plugin adds it; with AdMob off for a preset this export
  plugin adds it from `ludo_zing/ads/app_id`. The UMP message itself is set up in AdMob (Privacy & messaging): add
  ironSource and Unity Ads (and any later adapter's network) to its ad partners.

## Server-to-server rewards

The game never grants. `POST /v1/ads/start` gives `{nonce, user_id, custom_data}`; `show_rewarded` puts them in the
custom parameters; LevelPlay calls `GET /v1/ads/levelplay` with `custom_nonce` / `custom_uid` and an MD5 signature
made with the private key (Worker secret `LEVELPLAY_S2S_KEY`). Dashboard (Apps > the app > Set S2S callback):

    https://ludo-zing-rooms.flipfold.workers.dev/v1/ads/levelplay?userId=[USER_ID]&rewards=[REWARDS]&eventId=[EVENT_ID]&itemName=[ITEM_NAME]&placement=[PLACEMENT_NAME]

Set a private key there and the same string with `tools/cf.sh secret put LEVELPLAY_S2S_KEY` (server/). Until the
secret is set the endpoint answers 503 and LevelPlay keeps retrying.

## Files

| Path | What |
|---|---|
| `src/main/java/com/flipfold/ludozing/levelplay/LevelPlayPlugin.kt` | The plugin. |
| `godot/addons/levelplay/bin/{debug,release}/LevelPlay-*.aar` | Built AARs (tracked). |
| `godot/addons/levelplay/export_plugin.gd` | For presets with `plugins/levelplay=true` and Gradle build: adds the AAR, the Maven dependencies (LevelPlay, UMP, `play-services-appset`, `play-services-ads-identifier`), `<meta-data com.flipfold.ludozing.levelplay.APP_KEY>` from `ludo_zing/ads/levelplay_app_key`, and the AdMob app id for UMP when AdMob is off. |
| `godot/addons/levelplay/editor_plugin.gd`, `plugin.cfg` | Editor plugin (enabled in `project.godot`); registers the settings and the export plugin. |
| `tools/build-levelplay-plugin.sh` | Builds both AARs and copies them to `godot/addons/levelplay/bin/`. |
| `godot/tests/test_ads.gd` | Provider choice, the fake plugin as LevelPlay, settings, export snippet. |

Settings (`project.godot` `[ludo_zing]`): `ads/levelplay_app_key` = `2928a1d3d`, `ads/levelplay_rewarded_unit` =
`ij2h0kzjw5bnxhll`, `ads/provider` = `auto`, `ads/levelplay_test_suite` (dev only, default off). Presets: `Android`
and `Android Release` have `plugins/levelplay=true`; `Android Emulator` has it `false` (no Gradle build).

## Build

`tools/build-levelplay-plugin.sh` (JDK 17+, Android SDK). Needed only after changing the Kotlin or the versions; then
commit the AARs. Changing a version: update `build.gradle` and the `*_DEPENDENCY` constants in
`godot/addons/levelplay/export_plugin.gd`. The SDK pulls `adquality-sdk` (Maven Central) by itself.

## Testing

- Turn `ludo_zing/ads/levelplay_test_suite` on locally (don't commit it) and build with the `Android` preset: the
  integration test suite opens when the SDK is ready (it lists the networks and can show test ads).
- Register test devices (the phone's advertising id) in the LevelPlay dashboard to get test ads from the real
  ad unit. Never tap real ads on our own phones.
- Logcat: `adb logcat -s LevelPlay:V Ads:V GodotPluginRegistry:V godot:V` (the SDK also logs under `IronSource` tags).

## Adding mediation adapters later

Each network is one more Maven dependency in `export_plugin.gd` (`_get_android_dependencies`), nothing in the Kotlin,
plus the network turned on for the app in the LevelPlay dashboard (Setup > SDK Networks) and in its own console. Use
the adapter version LevelPlay lists for the SDK version (docs: LevelPlay > Android > Mediation networks; adapters are
`com.unity3d.ads-mediation:<network>-adapter`, on Maven Central since 9.0.0). Each adapter brings that network's SDK
(APK size, low-end memory): add one at a time and check the build on the low-spec emulator (`tools/lowspec-avd.sh`).

- **Unity Ads**: `com.unity3d.ads-mediation:unityads-adapter` + `com.unity3d.ads:unity-ads`.
- **AdMob (as a bidder)**: `com.unity3d.ads-mediation:admob-adapter` + `com.google.android.gms:play-services-ads`
  (already in the build through the AdMob plugin) and the AdMob application id meta-data (already there).
- **Mintegral**: `com.unity3d.ads-mediation:mintegral-adapter` + the Mintegral SDK artifacts it names (their Maven
  repo: `https://dl-maven-android.mintegral.com/repository/mbridge_android_sdk_oversea`, added to the Gradle build).
- **Pangle**: `com.unity3d.ads-mediation:pangle-adapter` + `com.pangle.global:pag-sdk` (their Maven repo:
  `https://artifact.bytedance.com/repository/pangle`).

The network SDK names and repositories above are a starting point: take the exact ones from LevelPlay's page for
that network. A network with its own Maven repository needs it returned from the export plugin's
`_get_android_dependencies_maven_repos`. Add each network to the UMP message's ad partners too, and re-check the
Play Data safety answers.
