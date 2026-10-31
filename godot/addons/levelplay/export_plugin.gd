@tool
extends EditorExportPlugin
## Android export side of the LevelPlay plugin (Godot v2 Android plugin architecture).
##
## For an Android preset with the export option "plugins/levelplay" on and "Use Gradle Build" on, it adds:
## - the plugin AAR (bin/debug or bin/release, built by tools/build-levelplay-plugin.sh). Its own manifest brings the
##   plugin registration (singleton "LevelPlay") and the AD_ID permission,
## - the Maven dependencies: the LevelPlay SDK (com.unity3d.ads-mediation:mediation-sdk, ironSource Ads only: no
##   mediation adapters), Google's UMP consent SDK and the Play services LevelPlay asks for (app set id, ads id),
## - the <meta-data com.flipfold.ludozing.levelplay.APP_KEY> element in <application>, with the value of the project
##   setting ludo_zing/ads/levelplay_app_key (the plugin reads it to start the SDK),
## - when the AdMob plugin is off for the preset: <meta-data com.google.android.gms.ads.APPLICATION_ID> from
##   ludo_zing/ads/app_id, which the UMP consent SDK needs (the AdMob plugin adds it otherwise).
## The option off (or a non-Gradle preset such as "Android Emulator"): nothing is added,
## Engine.has_singleton("LevelPlay") is false and ads.gd uses AdMob or its stub.

const PLUGIN_NAME := "LevelPlayPlugin"
const ENABLE_OPTION := "plugins/levelplay"
const ADMOB_OPTION := "plugins/admob"
const APP_KEY_SETTING := "ludo_zing/ads/levelplay_app_key"
const REWARDED_UNIT_SETTING := "ludo_zing/ads/levelplay_rewarded_unit"
const PROVIDER_SETTING := "ludo_zing/ads/provider"
const TEST_SUITE_SETTING := "ludo_zing/ads/levelplay_test_suite"
const ADMOB_APP_ID_SETTING := "ludo_zing/ads/app_id"
const APP_KEY_META := "com.flipfold.ludozing.levelplay.APP_KEY"
## Ludo Zing's LevelPlay app (Android) and rewarded ad unit; "auto" = LevelPlay when its plugin is in the build, else
## AdMob ("levelplay" / "admob" force one); the test suite is for dev builds only.
const DEFAULTS := {
	"ludo_zing/ads/levelplay_app_key": "2928a1d3d",
	"ludo_zing/ads/levelplay_rewarded_unit": "ij2h0kzjw5bnxhll",
	"ludo_zing/ads/provider": "auto",
	"ludo_zing/ads/levelplay_test_suite": false,
}
## Keep in sync with levelPlayVersion / umpVersion in godot/android/plugins/levelplay/build.gradle.
const LEVELPLAY_DEPENDENCY := "com.unity3d.ads-mediation:mediation-sdk:9.7.0"
const UMP_DEPENDENCY := "com.google.android.ump:user-messaging-platform:4.0.0"
## LevelPlay's integration guide (step 2): the app set id and the advertising id.
const PLAY_DEPENDENCIES := [
	"com.google.android.gms:play-services-appset:16.1.0",
	"com.google.android.gms:play-services-ads-identifier:18.3.0",
]

func _get_name() -> String:
	return PLUGIN_NAME

func _supports_platform(platform: EditorExportPlatform) -> bool:
	return platform is EditorExportPlatformAndroid

func _get_export_options(platform: EditorExportPlatform) -> Array[Dictionary]:
	if not (platform is EditorExportPlatformAndroid):
		return []
	return [{
		option = {name = ENABLE_OPTION, type = TYPE_BOOL},
		default_value = false,
	}]

func _get_export_option_warning(platform: EditorExportPlatform, option: String) -> String:
	if option != ENABLE_OPTION or not get_option(ENABLE_OPTION):
		return ""
	if not get_option("gradle_build/use_gradle_build"):
		return "LevelPlay needs \"Use Gradle Build\": it is skipped for this preset."
	if app_key().is_empty():
		return "Project setting %s is empty: LevelPlay is skipped for this preset." % APP_KEY_SETTING
	return ""

## The LevelPlay app key from the project settings ("" when unset).
static func app_key() -> String:
	return str(ProjectSettings.get_setting(APP_KEY_SETTING, "")).strip_edges()

## On for this export: the preset option is set, the preset uses the Gradle build (v2 plugins need it) and there is
## an app key (without one the plugin can't start the SDK).
func _active() -> bool:
	return bool(get_option(ENABLE_OPTION)) and bool(get_option("gradle_build/use_gradle_build")) \
		and not app_key().is_empty()

func _get_android_libraries(platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
	if not _active():
		return PackedStringArray()
	# paths are relative to res://addons/
	if debug:
		return PackedStringArray(["levelplay/bin/debug/LevelPlay-debug.aar"])
	return PackedStringArray(["levelplay/bin/release/LevelPlay-release.aar"])

func _get_android_dependencies(platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
	if not _active():
		return PackedStringArray()
	return PackedStringArray([LEVELPLAY_DEPENDENCY, UMP_DEPENDENCY] + PLAY_DEPENDENCIES)

func _get_android_manifest_application_element_contents(platform: EditorExportPlatform, debug: bool) -> String:
	if not _active():
		return ""
	# the AdMob plugin adds the AdMob app id itself; two copies of the same meta-data would break the manifest merge
	var admob_id := "" if bool(get_option(ADMOB_OPTION)) else \
		str(ProjectSettings.get_setting(ADMOB_APP_ID_SETTING, "")).strip_edges()
	return manifest_contents(app_key(), admob_id)

## The <application> children: the LevelPlay app key, and the AdMob app id for UMP when given. Escaped for XML.
static func manifest_contents(key: String, admob_app_id := "") -> String:
	var s := """
		<meta-data
			android:name="%s"
			android:value="%s" />
""" % [APP_KEY_META, key.xml_escape(true)]
	if admob_app_id != "":
		s += """
		<meta-data
			android:name="com.google.android.gms.ads.APPLICATION_ID"
			android:value="%s" />
""" % admob_app_id.xml_escape(true)
	return s
