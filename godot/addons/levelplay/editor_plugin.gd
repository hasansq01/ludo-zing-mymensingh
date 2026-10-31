@tool
extends EditorPlugin
## Registers the LevelPlay project settings (Project Settings > Ludo Zing > Ads: the LevelPlay app key and rewarded ad
## unit id, which ad provider to use, the dev test suite switch) and the Android export plugin that links the LevelPlay
## AAR + the LevelPlay and UMP SDKs into Gradle exports. See export_plugin.gd and
## godot/android/plugins/levelplay/README.md.

const ExportPlugin := preload("res://addons/levelplay/export_plugin.gd")

var _export: EditorExportPlugin

func _enter_tree() -> void:
	for key in ExportPlugin.DEFAULTS:
		var v: Variant = ExportPlugin.DEFAULTS[key]
		if not ProjectSettings.has_setting(key):
			ProjectSettings.set_setting(key, v)
		ProjectSettings.set_initial_value(key, v)
		var info := {name = key, type = typeof(v)}
		if key == ExportPlugin.PROVIDER_SETTING:
			info.hint = PROPERTY_HINT_ENUM
			info.hint_string = "auto,levelplay,admob"
		ProjectSettings.add_property_info(info)
		ProjectSettings.set_as_basic(key, true)
	_export = ExportPlugin.new()
	add_export_plugin(_export)

func _exit_tree() -> void:
	if _export:
		remove_export_plugin(_export)
		_export = null
