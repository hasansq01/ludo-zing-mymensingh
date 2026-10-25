@tool
extends EditorExportPlugin
## Android export side of the PlayGames plugin (Godot v2 Android plugin architecture).
##
## For an Android preset with the export option "plugins/play_games" on and "Use Gradle Build" on, it adds:
## - the plugin AAR (bin/debug or bin/release, built by tools/build-play-games-plugin.sh),
## - the Maven dependency com.google.android.gms:play-services-games-v2,
## - <meta-data com.google.android.gms.games.APP_ID> from the project setting ludo_zing/play_games/app_id.
## An empty app id = disabled: no APP_ID meta-data, and the Games SDK's auto-init provider is removed from the
## manifest, so nothing in the SDK runs; the plugin then reports initialized(false, "no_app_id").
## The option off (or a non-Gradle preset such as "Android Emulator"): nothing is added, Engine.has_singleton
## ("PlayGamesPlugin") is false and res://scripts/net/play_games.gd falls back to its stub.

const PLUGIN_NAME := "PlayGamesPlugin"
const ENABLE_OPTION := "plugins/play_games"
const APP_ID_SETTING := "ludo_zing/play_games/app_id"
const WEB_CLIENT_SETTING := "ludo_zing/play_games/web_client_id"
## Keep in sync with playGamesVersion in godot/android/plugins/play_games/build.gradle.
const PLAY_GAMES_DEPENDENCY := "com.google.android.gms:play-services-games-v2:22.1.0"

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
		return "Play Games needs \"Use Gradle Build\": it is skipped for this preset."
	var id := app_id()
	if id.is_empty():
		return "%s is empty: Play Games is built in but disabled." % APP_ID_SETTING
	if not is_valid_app_id(id):
		return "%s should be the numeric Play Games project id (got \"%s\")." % [APP_ID_SETTING, id]
	return ""

## On for this export: the preset option is set and the preset uses the Gradle build (v2 plugins need it).
func _active() -> bool:
	return bool(get_option(ENABLE_OPTION)) and bool(get_option("gradle_build/use_gradle_build"))

func _get_android_libraries(platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
	if not _active():
		return PackedStringArray()
	# paths are relative to res://addons/
	if debug:
		return PackedStringArray(["play_games/bin/debug/PlayGames-debug.aar"])
	return PackedStringArray(["play_games/bin/release/PlayGames-release.aar"])

func _get_android_dependencies(platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
	if not _active():
		return PackedStringArray()
	return PackedStringArray([PLAY_GAMES_DEPENDENCY])

func _get_android_manifest_application_element_contents(platform: EditorExportPlatform, debug: bool) -> String:
	if not _active():
		return ""
	return manifest_contents(app_id())

static func app_id() -> String:
	return str(ProjectSettings.get_setting(APP_ID_SETTING, "")).strip_edges()

static func is_valid_app_id(id: String) -> bool:
	return id.is_valid_int() and not id.begins_with("-") and not id.begins_with("+")

## The <application> children for an app id ("" = disabled). The id is numeric; written plainly, aapt would store
## it as an integer (or a float, losing digits) and the Games SDK, which reads a string, would not find it. The
## first digit is therefore written as a \u003X escape, which aapt decodes back to the same digit as a string.
static func manifest_contents(id: String) -> String:
	if id.is_empty():
		return """
		<provider
			android:name="com.google.android.gms.games.provider.PlayGamesInitProvider"
			android:authorities="${applicationId}.playgamesinitprovider"
			tools:node="remove" />
"""
	var value := id.xml_escape(true)
	if is_valid_app_id(id):
		value = "\\u003" + id.substr(0, 1) + id.substr(1)
	return """
		<meta-data
			android:name="com.google.android.gms.games.APP_ID"
			android:value="%s" />
""" % value
