extends Control
## Dev preview: shows one sheet over a warm background, saves a screenshot and quits.
## godot --path . res://dev/preview_sheets.tscn -- settings|profile|howto [out_dir]

const OUT := "/private/tmp/claude-501/-Users-shihabshaharia-Coding-ludo-zing-mymensingh/d8feebe6-eee1-4f48-a116-aa2f313481c9/scratchpad/agent_sheets"

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
	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layer)
	Save._timer.timeout.disconnect(Save.flush)   # previews never write the real save file
	var args := OS.get_cmdline_user_args()
	if args.has("narrow"):   # let the UI get narrower than 390 (a 320-wide UI at --resolution 320x844)
		get_tree().root.content_scale_size = Vector2i(320, 844)
		await get_tree().process_frame
	var which := args[0] if args.size() > 0 else "settings"
	var out := OUT
	for a in args:
		if a.begins_with("/"):
			out = a
	var sheet: Sheet
	match which:
		"profile":
			sheet = ProfileSheet.new()
		"howto":
			sheet = HowToSheet.new()
		_:
			sheet = SettingsSheet.new()
	sheet.open(layer)
	await get_tree().create_timer(1.0).timeout
	if which == "profile" and args.has("err"):
		(sheet as ProfileSheet)._name_edit.text = "   "
		(sheet as ProfileSheet)._validate(true)
		await get_tree().create_timer(0.3).timeout
	if which == "settings" and args.has("howfrom"):
		(sheet as SettingsSheet)._open_howto()
		await get_tree().create_timer(0.6).timeout
	if which == "settings" and args.has("off"):
		(sheet as SettingsSheet)._switch.button_pressed = false
		await get_tree().create_timer(0.4).timeout
	if which == "profile" and args.has("save"):
		var ps := sheet as ProfileSheet
		var old_name := str(Save.profile.name)
		var old_stats: Dictionary = (Save.profile.stats as Dictionary).duplicate()
		var emitted := [false]
		ps.profile_changed.connect(func(): emitted[0] = true)
		ps._name_edit.text = "  Mina   Rahman  "
		ps._validate(true)
		print("save enabled: ", not ps._save_btn.disabled)
		ps._save_name()
		print("saved name: '", Save.profile.name, "' emitted: ", emitted[0], " btn disabled after: ", ps._save_btn.disabled)
		Save.profile.stats.played = 12; Save.profile.stats.wins = 7; Save.profile.stats.coinsEarned = 12500; Save.profile.xp = 260
		Save.changed.emit()
		await get_tree().create_timer(0.3).timeout
		get_viewport().get_texture().get_image().save_png(out + "/profile_saved.png")
		Save.profile.name = old_name
		Save.profile.stats = old_stats
		Save.profile.xp = 0
	var vs := get_viewport_rect().size
	var path := "%s/%s_%dx%d.png" % [out, which, int(vs.x), int(vs.y)]
	if args.has("err"):
		path = path.replace(".png", "_err.png")
	for tag in ["howfrom", "off"]:
		if args.has(tag):
			path = path.replace(".png", "_%s.png" % tag)
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path, " window ", get_window().size, " card ", sheet.card.size)
	Save._dirty = false   # previews never write the real save file
	get_tree().quit()
