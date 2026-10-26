@tool
extends EditorExportPlugin
## Android export side of the Billing plugin (Godot v2 Android plugin architecture).
##
## For an Android preset with the export option "plugins/billing" on and "Use Gradle Build" on, it adds:
## - the plugin AAR (bin/debug or bin/release, built by tools/build-billing-plugin.sh). Its own manifest brings the
##   plugin registration,
## - the Maven dependency com.android.billingclient:billing-ktx, whose manifest adds the
##   com.android.vending.BILLING permission.
## The option off (or a non-Gradle preset such as "Android Emulator"): nothing is added, Engine.has_singleton
## ("BillingPlugin") is false and res://scripts/net/billing.gd falls back to its stub.

const PLUGIN_NAME := "BillingPlugin"
const ENABLE_OPTION := "plugins/billing"
## Keep in sync with billingVersion in godot/android/plugins/billing/build.gradle.
const BILLING_DEPENDENCY := "com.android.billingclient:billing-ktx:8.3.0"

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
		return "Billing needs \"Use Gradle Build\": it is skipped for this preset."
	return ""

## On for this export: the preset option is set and the preset uses the Gradle build (v2 plugins need it).
func _active() -> bool:
	return bool(get_option(ENABLE_OPTION)) and bool(get_option("gradle_build/use_gradle_build"))

func _get_android_libraries(platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
	if not _active():
		return PackedStringArray()
	# paths are relative to res://addons/
	if debug:
		return PackedStringArray(["billing/bin/debug/Billing-debug.aar"])
	return PackedStringArray(["billing/bin/release/Billing-release.aar"])

func _get_android_dependencies(platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
	if not _active():
		return PackedStringArray()
	return PackedStringArray([BILLING_DEPENDENCY])
