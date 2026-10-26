@tool
extends EditorPlugin
## Registers the Android export plugin that links the Billing AAR + the Play Billing Library into Gradle exports.
## See export_plugin.gd and godot/android/plugins/billing/README.md.

const ExportPlugin := preload("res://addons/billing/export_plugin.gd")

var _export: EditorExportPlugin

func _enter_tree() -> void:
	_export = ExportPlugin.new()
	add_export_plugin(_export)

func _exit_tree() -> void:
	if _export:
		remove_export_plugin(_export)
		_export = null
