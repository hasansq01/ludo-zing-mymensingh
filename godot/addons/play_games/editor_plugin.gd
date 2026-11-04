@tool
extends EditorPlugin
## Registers the Play Games project settings (Project Settings > Ludo Zing > Play Games) and the Android export
## plugin that links the PlayGames AAR + play-services-games-v2 into Gradle exports. See export_plugin.gd and
## godot/android/plugins/play_games/README.md.

const ExportPlugin := preload("res://addons/play_games/export_plugin.gd")

var _export: EditorExportPlugin

func _enter_tree() -> void:
	for key in [ExportPlugin.APP_ID_SETTING, ExportPlugin.WEB_CLIENT_SETTING]:
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
