@tool
extends EditorPlugin
## Registers the ads project settings (Project Settings > Ludo Zing > Ads: the AdMob app id and the rewarded ad unit
## id; Google's public test ids until the owner's AdMob account exists) and the Android export plugin that links the
## AdMob AAR + the Google Mobile Ads and UMP SDKs into Gradle exports. See export_plugin.gd and
## godot/android/plugins/admob/README.md.

const ExportPlugin := preload("res://addons/admob/export_plugin.gd")

var _export: EditorExportPlugin

func _enter_tree() -> void:
	for key in ExportPlugin.DEFAULTS:
		if not ProjectSettings.has_setting(key):
			ProjectSettings.set_setting(key, ExportPlugin.DEFAULTS[key])
		ProjectSettings.set_initial_value(key, ExportPlugin.DEFAULTS[key])
		ProjectSettings.add_property_info({name = key, type = TYPE_STRING})
		ProjectSettings.set_as_basic(key, true)
	_export = ExportPlugin.new()
	add_export_plugin(_export)

func _exit_tree() -> void:
	if _export:
		remove_export_plugin(_export)
		_export = null
