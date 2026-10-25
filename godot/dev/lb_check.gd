extends Control
## Dev: the leaderboard's pinned "You" bar across refreshes (the phone showed it tall and empty after a refresh).
## Opens the sheet with a fake fetch (you ranked #1, one row, like the phone), refreshes a few times, prints the bar's
## height after each and takes screenshots.
##   godot --path . --resolution 390x844 res://dev/lb_check.tscn -- <out_dir> [--unlisted]
## --unlisted: the longest note ("Play 3 more matches to appear") instead of your level.
## Nothing is saved (no Save writes).

var out := "/tmp"
var n := 0

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size():
		out = a[0]
	DirAccess.make_dir_recursive_absolute(out)
	var bg := ColorRect.new()
	bg.color = Color(0.25, 0.2, 0.25)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(layer)
	var s := LeaderboardSheet.new()
	s.auto_load = false
	s.fetch_fn = func(_b: String, _p: String) -> Dictionary:
		await get_tree().create_timer(0.4).timeout
		return {ok = true, min_matches = 3, top = [{rank = 1, name = "You", avatar = "", frame = "", level = 2, value = 200}],
			me = {rank = 1, value = 200, listed = not OS.get_cmdline_user_args().has("--unlisted")}}
	s.open(layer)
	await get_tree().create_timer(0.8).timeout
	s.load_board(true)
	for k in 4:
		await get_tree().create_timer(1.2).timeout
		await _report(s, "load%d" % k)
		s.refresh_button.pressed.emit()
	await get_tree().create_timer(1.2).timeout
	await _report(s, "final")
	get_tree().quit()

func _report(s: LeaderboardSheet, tag: String) -> void:
	await RenderingServer.frame_post_draw
	var bar: Control = s._me_bar
	print("%s  me_bar h=%.0f y=%.0f  card bottom=%.0f  note h=%.0f" % [tag, bar.size.y, bar.global_position.y,
		s.card.get_global_rect().end.y, s.me_label.size.y if is_instance_valid(s.me_label) else -1])
	for c in s._me_box.get_children():
		print("    ", c.name, " ", c.get_class(), " size=", c.size, " min=", c.get_combined_minimum_size())
	print("    box size=", s._me_box.size, " min=", s._me_box.get_combined_minimum_size(), " bar min=", bar.get_combined_minimum_size())
	n += 1
	get_viewport().get_texture().get_image().save_png("%s/%02d_%s.png" % [out, n, tag])
