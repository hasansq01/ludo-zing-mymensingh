extends Control
## Dev preview of the feature-info (ⓘ) bubbles: opens a sheet with its icons, taps one like a finger would, saves
## screenshots and quits. Info state lives in a local Dictionary and Save never writes (no user://save.json).
##   godot --path . res://dev/preview_info.tscn -- setup|sl|settings|daily|edge [out_dir]

const OUT := "/private/tmp/claude-501/-Users-shihabshaharia-Coding-ludo-zing-mymensingh/d8feebe6-eee1-4f48-a116-aa2f313481c9/scratchpad/agent_info"

var layer: Control
var out := OUT

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UIKit.theme()
	var bg := TextureRect.new()
	var g := GradientTexture2D.new()
	g.gradient = Gradient.new()
	g.gradient.set_color(0, Color("#ffd9a8"))
	g.gradient.set_color(1, Color("#f29a6b"))
	g.fill_to = Vector2(0, 1)
	bg.texture = g
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	layer = Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layer)
	Save._timer.timeout.disconnect(Save.flush)   # previews never write the real save file
	Info.state_source = {}
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("/"):
			out = a
	var which: String = args[0] if args.size() > 0 else "setup"
	match which:
		"setup":
			await _setup()
		"sl":
			var s := SetupSheet.new("sl", "cpu")
			s.open(layer)
			await _wait(0.9)
			await _shot("sl_setup")   # (no ⓘ in the S&L setup any more: the note says it)
		"settings":
			var s := SettingsSheet.new()
			s.open(layer)
			await _wait(0.8)
			await _shot("settings")   # (no ⓘ in Settings any more, visual.md SET-01)
		"daily":
			var s := DailySheet.new(Save.profile.duplicate(true), "2026-10-24")
			s.open(layer)
			await _wait(0.9)
			await _shot("daily_pulse")
			await _tap_icon("daily")
			await _shot("daily_bubble")
		"edge":   # icons near the screen edges: the bubble flips above and stays on screen
			var row := UIKit.hbox(0)
			row.position = Vector2(8, 790)
			add_child(row)
			row.add_child(Info.icon("pair"))
			var r2 := UIKit.hbox(0)
			r2.position = Vector2(356, 40)
			add_child(r2)
			r2.add_child(Info.icon("free", false, 18))
			await _wait(0.3)
			await _tap_icon("pair")
			await _shot("edge_above")
			await _tap_icon("free")
			await _shot("edge_right")
	print("state: ", Info.state_source)
	get_tree().quit()

func _setup() -> void:
	var s := SetupSheet.new("ludo", "cpu")
	s.open(layer)
	await _wait(0.8)
	await _shot("setup_ind_pulse")
	var pair_btn := _find_button(s, "Teams (2 v 2)")
	pair_btn.button_pressed = true
	await _wait(0.75)
	await _shot("setup_team_pulse")
	print("teams before tap: ", s.teams, "  team showings: ", Info.showings("team"))
	await _tap_icon("team")
	print("open after tapping team: ", Info.open_key_now(), "  team read: ", Info.is_read("team"))
	await _shot("setup_team_bubble")
	await _tap(Vector2(195, 800))   # a tap elsewhere (the dim) closes the bubble and the sheet
	print("after tap elsewhere: open=", Info.is_open())
	await _wait(0.3)
	await _shot("setup_after_close")

func _find_button(n: Node, text: String) -> Button:
	if n is Button and (n as Button).text == text:
		return n
	for c in n.get_children():
		var b := _find_button(c, text)
		if b:
			return b
	return null

func _tap_icon(key: String) -> void:
	for ic in get_tree().get_nodes_in_group(Info.GROUP):
		if ic.key == key and ic.is_visible_in_tree():
			var c: Vector2 = (ic as Control).get_global_transform_with_canvas() * ((ic as Control).size / 2.0)
			await _tap(c + Vector2(0, 14))   # off-centre (inside the 44 px target, outside the dot)
			await _wait(0.45)
			return
	push_warning("no icon " + key)

func _tap(p: Vector2) -> void:
	var sp := get_viewport().get_screen_transform() * p   # canvas → window pixels
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = sp
		e.global_position = sp
		Input.parse_input_event(e)
		await get_tree().process_frame

func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout

func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var vs := get_viewport_rect().size
	var path := "%s/godot_%s_%dx%d.png" % [out, tag, int(vs.x), int(vs.y)]
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
