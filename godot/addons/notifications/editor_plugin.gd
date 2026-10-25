@tool
extends EditorPlugin
## Registers the push project settings (Project Settings > Ludo Zing > Push: the Firebase project's four values,
## empty = push off) and the Android export plugin that links the Notifications AAR + firebase-messaging into
## Gradle exports. See export_plugin.gd and godot/android/plugins/notifications/README.md.

const ExportPlugin := preload("res://addons/notifications/export_plugin.gd")

var _export: EditorExportPlugin

func _enter_tree() -> void:
	for key in ExportPlugin.PUSH_SETTINGS:
		# only registered: an empty value equals the initial value, so nothing is written to project.godot
		if not ProjectSettings.has_setting(key):
			ProjectSettings.set_setting(key, "")
		ProjectSettings.set_initial_value(key, "")
		ProjectSettings.add_property_info({name = key, type = TYPE_STRING})
		ProjectSettings.set_as_basic(key, true)
	_export = ExportPlugin.new()
	add_export_plugin(_export)

func _exit_tree() -> void:
	if _export:
		remove_export_plugin(_export)
		_export = null
