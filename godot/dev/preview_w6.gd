extends Control
## Dev preview (W6): Settings, How to play, Credits, the setup sheets and the info bubble over a home-like
## background; saves screenshots and quits. The real save is never written: Save's timer is unhooked, its dirty
## flag cleared before quitting, and user://save.json is backed up first and put back at the end if it changed.
##   godot --path . --resolution 390x844 res://dev/preview_w6.tscn -- <which> [narrow] [cb] [need1] [ask] [out_dir]
## which: settings | settings_off | settings_bottom | reset | howto | howto_bottom | credits | setup_cpu | setup_teams |
##        setup_local | setup_3p | sl_cpu | sl_local | info_team | info_ind | all

const OUT := "/private/tmp/claude-501/-Users-shihabshaharia-Coding-ludo-zing-mymensingh/d8feebe6-eee1-4f48-a116-aa2f313481c9/scratchpad/w6"

var layer: Control
var out := OUT
var tag := ""
var _backup := ""
var _had_file := false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UIKit.theme()
	_had_file = FileAccess.file_exists(Save.PATH)
	if _had_file:
		_backup = FileAccess.get_file_as_string(Save.PATH)
	Save._timer.timeout.disconnect(Save.flush)
	var keep_prefs: Dictionary = Save.prefs.duplicate(true)
	var keep_profile: Dictionary = Save.profile.duplicate(true)
	var bg := TextureRect.new()
	var g := GradientTexture2D.new()
	g.gradient = Gradient.new()
	g.gradient.set_color(0, Palette.PLUM_NIGHT)
	g.gradient.set_color(1, Palette.RUST)
	g.fill_to = Vector2(0, 1)
	bg.texture = g
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	layer = Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layer)
	Info.state_source = {}
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("/"):
			out = a
	if args.has("narrow"):
		get_tree().root.content_scale_size = Vector2i(320, 844)
		tag += "_narrow"
		await get_tree().process_frame
	Save.prefs.colorblind = args.has("cb")
	Save.prefs.sl_need_one = args.has("need1")
	Save.prefs.pair_ask = args.has("ask")
	for f in ["cb", "need1", "ask"]:
		if args.has(f):
			tag += "_" + f
	var which: String = args[0] if args.size() > 0 else "settings"
	if which == "app":
		await _app()
		Save.prefs = keep_prefs
		Save.profile = keep_profile
		Save._dirty = false
		_restore()
		get_tree().quit()
		return
	var list: Array = [which] if which != "all" else ["settings", "settings_bottom", "howto", "howto_bottom", "credits",
			"setup_cpu", "setup_teams", "setup_local", "setup_3p", "sl_cpu", "sl_local", "info_team", "reset"]
	for w: String in list:
		await _run(w)
		for c in layer.get_children():
			c.queue_free()
		Info.close()
		await _wait(0.2)
	Save.prefs = keep_prefs
	Save.profile = keep_profile
	Save._dirty = false
	_restore()
	get_tree().quit()

func _run(w: String) -> void:
	match w:
		"settings", "settings_off", "settings_bottom":
			var s := SettingsSheet.new()
			s.open(layer)
			await _wait(0.8)
			if w == "settings_off":
				s._switch.button_pressed = false
				await _wait(0.4)
			if w == "settings_bottom":
				s.scroll_box.scroll_vertical = 100000
				await _wait(0.4)
			await _shot(w)
		"reset":
			var s := SettingsSheet.new()
			s.open(layer)
			await _wait(0.6)
			s.scroll_box.scroll_vertical = 100000
			await _wait(0.3)
			s._confirm_reset()
			await _wait(0.6)
			await _shot("reset_confirm")
		"howto", "howto_bottom":
			var s := HowToSheet.new()
			s.open(layer)
			await _wait(0.8)
			if w == "howto_bottom":
				s.scroll_box.scroll_vertical = 100000
				await _wait(0.4)
			await _shot(w)
		"credits":
			var s := SettingsSheet.new()
			s.open(layer)
			await _wait(0.5)
			s._open_credits()
			await _wait(0.7)
			await _shot(w)
		"setup_cpu", "setup_teams", "setup_3p":
			Save.prefs.last_setup = {}
			if w == "setup_teams":
				Save.prefs.last_setup = {ludo = {cpu = {count = 3, color = 1, teams = true, bot_level = "hard"}}}
			if w == "setup_3p":
				Save.prefs.last_setup = {ludo = {cpu = {count = 2, color = 2, teams = true, bot_level = "easy"}}}
			var s := SetupSheet.new("ludo", "cpu")
			s.start.connect(func(cfg): print(w, " config: ", cfg))
			s.open(layer)
			await _wait(0.9)
			await _shot(w)
			s._submit()
			print(w, " saved: ", Save.prefs.last_setup, " bot_level pref: ", Save.prefs.bot_level)
		"setup_local":
			var s := SetupSheet.new("ludo", "local")
			s.start.connect(func(cfg): print(w, " config: ", cfg))
			s.open(layer)
			await _wait(0.9)
			await _shot(w)
		"sl_cpu", "sl_local":
			var s := SetupSheet.new("sl", "cpu" if w == "sl_cpu" else "local")
			s.start.connect(func(cfg): print(w, " config: ", cfg))
			s.open(layer)
			await _wait(0.9)
			await _shot(w)
		"info_team", "info_ind":
			Save.prefs.last_setup = {ludo = {cpu = {count = 3, color = 0, teams = w == "info_team"}}}
			var s := SetupSheet.new("ludo", "cpu")
			s.open(layer)
			await _wait(0.8)
			Info.open_key("team" if w == "info_team" else "ind")
			await _wait(0.6)
			await _shot(w)

## In the real app over Home: Settings and the Ludo / S&L setups as main opens them.
func _app() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	var t := 0.0
	while not main.screen in ["home", "welcome"] and t < 40.0:
		await _wait(0.25)
		t += 0.25
	for c in main.screens.get_children():
		if c is Welcome:
			c.continued.emit()
	await _wait(2.5)
	main.close_all_sheets() if main.has_method("close_all_sheets") else null
	await _wait(0.5)
	main.open_settings()
	await _wait(1.0)
	await _shot("app_settings")
	main.close_all_sheets() if main.has_method("close_all_sheets") else null
	await _wait(0.5)
	main._open_setup("ludo", "cpu")
	await _wait(1.0)
	await _shot("app_setup_cpu")
	main.close_all_sheets() if main.has_method("close_all_sheets") else null
	await _wait(0.5)
	main._open_setup("sl", "local")
	await _wait(1.0)
	await _shot("app_setup_sl_local")

func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var vs := get_viewport_rect().size
	var path := "%s/%s%s_%dx%d.png" % [out, name, tag, int(vs.x), int(vs.y)]
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)

func _restore() -> void:
	var now_has := FileAccess.file_exists(Save.PATH)
	if _had_file and (not now_has or FileAccess.get_file_as_string(Save.PATH) != _backup):
		var f := FileAccess.open(Save.PATH, FileAccess.WRITE)
		f.store_string(_backup)
		f.close()
		print("restored the save file")
	elif not _had_file and now_has:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Save.PATH))

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if is_instance_valid(Save):
			Save._dirty = false
