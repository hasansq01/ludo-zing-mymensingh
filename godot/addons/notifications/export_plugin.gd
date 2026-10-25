@tool
extends EditorExportPlugin
## Android export side of the Notifications plugin (Godot v2 Android plugin architecture).
##
## For an Android preset with the export option "plugins/notifications" on and "Use Gradle Build" on, it adds:
## - the plugin AAR (bin/debug or bin/release, built by tools/build-notifications-plugin.sh). Its own manifest brings
##   the plugin registration, the POST_NOTIFICATIONS and RECEIVE_BOOT_COMPLETED permissions, the alarm / boot
##   receivers, the FCM service and FCM's default icon / colour / channel ("game") meta-data,
## - the Maven dependency com.google.firebase:firebase-messaging,
## - the removal of firebase-common's FirebaseInitProvider: there is no google-services.json, so it would only log
##   that it can't initialise; the plugin initialises Firebase itself in push_init() (project settings
##   ludo_zing/push/*, read at runtime by res://scripts/net/notifier.gd; all empty = push off).
## The option off (or a non-Gradle preset such as "Android Emulator"): nothing is added, Engine.has_singleton
## ("NotificationsPlugin") is false and notifier.gd falls back to its stub.

const PLUGIN_NAME := "NotificationsPlugin"
const ENABLE_OPTION := "plugins/notifications"
const PUSH_SETTINGS := ["ludo_zing/push/project_id", "ludo_zing/push/app_id", "ludo_zing/push/api_key",
	"ludo_zing/push/sender_id"]
## Keep in sync with firebaseMessagingVersion in godot/android/plugins/notifications/build.gradle.
const FIREBASE_MESSAGING_DEPENDENCY := "com.google.firebase:firebase-messaging:26.0.1"

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
		return "Notifications needs \"Use Gradle Build\": it is skipped for this preset."
	var set_count := 0
	for key in PUSH_SETTINGS:
		if not str(ProjectSettings.get_setting(key, "")).strip_edges().is_empty():
			set_count += 1
	if set_count != 0 and set_count != PUSH_SETTINGS.size():
		return "Only %d of the 4 ludo_zing/push/* settings are set: push stays off." % set_count
	return ""

## On for this export: the preset option is set and the preset uses the Gradle build (v2 plugins need it).
func _active() -> bool:
	return bool(get_option(ENABLE_OPTION)) and bool(get_option("gradle_build/use_gradle_build"))

func _get_android_libraries(platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
	if not _active():
		return PackedStringArray()
	# paths are relative to res://addons/
	if debug:
		return PackedStringArray(["notifications/bin/debug/Notifications-debug.aar"])
	return PackedStringArray(["notifications/bin/release/Notifications-release.aar"])

func _get_android_dependencies(platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
	if not _active():
		return PackedStringArray()
	return PackedStringArray([FIREBASE_MESSAGING_DEPENDENCY])

func _get_android_manifest_application_element_contents(platform: EditorExportPlatform, debug: bool) -> String:
	if not _active():
		return ""
	return manifest_contents()

## The <application> children: FirebaseInitProvider removed (here, in the app manifest, so the removal wins the
## manifest merge over firebase-common's library manifest).
static func manifest_contents() -> String:
	return """
		<provider
			android:name="com.google.firebase.provider.FirebaseInitProvider"
			android:authorities="${applicationId}.firebaseinitprovider"
			tools:node="remove" />
"""
