@tool
extends EditorExportPlugin
## Android export side of the AdMob plugin (Godot v2 Android plugin architecture).
##
## For an Android preset with the export option "plugins/admob" on and "Use Gradle Build" on, it adds:
## - the plugin AAR (bin/debug or bin/release, built by tools/build-admob-plugin.sh). Its own manifest brings the
##   plugin registration (singleton "AdMob"),
## - the Maven dependencies com.google.android.gms:play-services-ads and com.google.android.ump:user-messaging-platform,
## - the <meta-data com.google.android.gms.ads.APPLICATION_ID> element in <application>, with the value of the project
##   setting ludo_zing/ads/app_id (the Ads SDK crashes at start without it).
## The option off (or a non-Gradle preset such as "Android Emulator"): nothing is added, Engine.has_singleton("AdMob")
## is false and ads.gd falls back to its stub.

const PLUGIN_NAME := "AdMobPlugin"
const ENABLE_OPTION := "plugins/admob"
const APP_ID_SETTING := "ludo_zing/ads/app_id"
const REWARDED_UNIT_SETTING := "ludo_zing/ads/rewarded_unit"
## Ludo Zing's AdMob app and rewarded unit (shihabsdev@gmail.com AdMob; the unit has server-side verification).
const DEFAULTS := {
	"ludo_zing/ads/app_id": "ca-app-pub-1525695956680184~8542680820",
	"ludo_zing/ads/rewarded_unit": "ca-app-pub-1525695956680184/5856807738",
}
## Keep in sync with playServicesAdsVersion / umpVersion in godot/android/plugins/admob/build.gradle.
const ADS_DEPENDENCY := "com.google.android.gms:play-services-ads:25.5.0"
const UMP_DEPENDENCY := "com.google.android.ump:user-messaging-platform:4.0.0"

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
		return "AdMob needs \"Use Gradle Build\": it is skipped for this preset."
	if app_id().is_empty():
		return "Project setting %s is empty: AdMob is skipped for this preset." % APP_ID_SETTING
	return ""

## The AdMob application id from the project settings ("" when unset).
static func app_id() -> String:
	return str(ProjectSettings.get_setting(APP_ID_SETTING, "")).strip_edges()

## On for this export: the preset option is set, the preset uses the Gradle build (v2 plugins need it) and there is
## an app id (without one the Ads SDK crashes at start).
func _active() -> bool:
	return bool(get_option(ENABLE_OPTION)) and bool(get_option("gradle_build/use_gradle_build")) \
		and not app_id().is_empty()

func _get_android_libraries(platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
	if not _active():
		return PackedStringArray()
	# paths are relative to res://addons/
	if debug:
		return PackedStringArray(["admob/bin/debug/AdMob-debug.aar"])
	return PackedStringArray(["admob/bin/release/AdMob-release.aar"])

func _get_android_dependencies(platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
	if not _active():
		return PackedStringArray()
	return PackedStringArray([ADS_DEPENDENCY, UMP_DEPENDENCY])

func _get_android_manifest_application_element_contents(platform: EditorExportPlatform, debug: bool) -> String:
	if not _active():
		return ""
	return manifest_contents(app_id())

## The <application> child: the AdMob application id. Escaped for XML attribute use.
static func manifest_contents(id: String) -> String:
	return """
		<meta-data
			android:name="com.google.android.gms.ads.APPLICATION_ID"
			android:value="%s" />
""" % id.xml_escape(true)
