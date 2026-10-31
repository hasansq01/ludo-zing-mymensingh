extends SceneTree
## Loads scripts the way the game does (autoloads present) and reports the ones that don't compile:
##   godot --headless --path godot -s res://tools/parse_check.gd                      # every script under scripts/
##   godot --headless --path godot -s res://tools/parse_check.gd -- scripts/ui/a.gd scripts/ui/b.gd
## Godot prints each error (SCRIPT ERROR / Parse Error) above the summary; exit code 1 when one fails.

const Extract := preload("res://tools/l10n_extract.gd")


func _initialize() -> void:
	var files := PackedStringArray()
	for a in OS.get_cmdline_user_args():
		if a.ends_with(".gd"):
			files.append("res://" + a.trim_prefix("godot/").trim_prefix("res://"))
	if files.is_empty():
		files = Extract.new().scripts()
	var bad := PackedStringArray()
	for f in files:
		var s: Script = load(f)
		if s == null or not s.can_instantiate() and not (s as GDScript).is_abstract():
			bad.append(f)
	print("parse_check: %d scripts, %d failed %s" % [files.size(), bad.size(), ", ".join(bad)])
	quit(1 if bad.size() else 0)
