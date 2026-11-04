extends Node
## Dev: the shareable win cards (scripts/ui/components/win_card.gd) rendered to PNGs, no network:
## a Ludo win with coins, a Snakes & Ladders win in another frame, a free game with a long name, a 2nd place.
##   godot --path . --resolution 390x844 res://dev/share_shots.tscn -- <out_dir> [--share]
## With --share, or on Android (a build with the notifications plugin) the Ludo card is also sent to the phone's share sheet,
## to see the chooser; without the plugin that falls back to the clipboard.
## Never writes user://save.json: Save's debounced flush is unhooked, and the file is backed up and restored.

var out := "/tmp/share"
var _backup := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() and not args[0].begins_with("--"):
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	if FileAccess.file_exists("user://save.json"):
		_backup = FileAccess.get_file_as_string("user://save.json")
	if Save._timer and Save._timer.timeout.is_connected(Save.flush):
		Save._timer.timeout.disconnect(Save.flush)
	Save.profile.name = "Shihab"
	Save.profile.avatar = "ch-arif"
	Save.profile.frame = "classic"
	var host := Control.new()
	add_child(host)
	await get_tree().process_frame
	var cards := [
		["ludo_win", {name = "Shihab", place = 1, title = "You win!", coins = 228, game = "ludo"}],
		["sl_win", {name = "Mimi", place = 1, title = "You win!", coins = 1190, game = "sl", avatar = "pawn-blue", frame = "gold"}],
		["free_long_name", {name = "Sir Reginald Featherstonehaugh III", place = 1, title = "Your team wins!", coins = 0, game = "ludo", avatar = "pawn-red", frame = "royal"}],
		["second", {name = "Shihab", place = 2, title = "You finished 2nd", coins = 90, game = "ludo", avatar = "pawn-green", frame = "mint"}],
	]
	for c: Array in cards:
		var path := await WinCard.render(host, c[1])
		if path != "":
			DirAccess.copy_absolute(path, "%s/%s.png" % [out, c[0]])
		print("card ", c[0], " -> ", path)
	if "--share" in args or OS.has_feature("android"):
		var path := await WinCard.render(host, cards[0][1])
		print("share: ", Share.send(host, Share.win_text(228, "ludo"), path), " native=", Share.available(), " ", path)
		await get_tree().create_timer(30.0 if OS.has_feature("android") else 6.0).timeout
	Save._dirty = false
	if _backup != "":
		var f := FileAccess.open("user://save.json", FileAccess.WRITE)
		f.store_string(_backup)
		f.close()
	get_tree().quit()
