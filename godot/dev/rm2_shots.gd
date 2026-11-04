extends Node
## Dev (R-M2): screenshots of the Shop / Get coins / Preview / Settings / Profile / Welcome / info bubble sheets.
## godot --path . --resolution 390x844 res://dev/rm2_shots.tscn -- <out_dir> [name filter ...]
## Never writes user://save.json: the Save autoload's debounced writes are switched off and the profile and prefs
## are in-memory copies for this run only.

var out := "/tmp"
var only: Array = []
var main: Node
var n := 0

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size():
		out = args[0]
		only = args.slice(1)
	Save._timer.stop()
	if Save._timer.timeout.is_connected(Save.flush):
		Save._timer.timeout.disconnect(Save.flush)
	Save._dirty = false
	Save.profile = Save.profile.duplicate(true)
	Save.prefs = Save.prefs.duplicate(true)
	Save.prefs.welcome_seen = true
	Save.prefs.tutorial_done = true
	Save.profile.name = "Shihab"
	Save.profile.coins = 5500
	Save.profile.avatar = "ch-nadia"
	Save.profile.xp = 140
	Save.profile.stats.wins = maxi(1, int(Save.profile.stats.get("wins", 0)))
	Save.profile.stats.played = maxi(1, int(Save.profile.stats.get("played", 0)))
	Save.profile.stats.pairsFormed = 2
	Save.profile.stats.bestStreak = 1
	Save.profile.claimed = []
	Rewards.mark_auto_open(Save.profile)         # no daily calendar over the shots
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _until(func(): return main.screen in ["home", "welcome"], 40)
	await _sleep(1.6)
	main.close_all_sheets()
	await _sleep(0.3)
	if _want("welcome"):
		var w := Welcome.new()
		main.screens.add_child(w)
		await _sleep(0.9)
		await shot("welcome")
		w.queue_free()
		await _sleep(0.2)
	for t in ["rooms", "scenes", "avatars", "frames", "badges"]:
		if _want("shop_" + t):
			await sheet_shot(func(): _open_shop(t), "shop_" + t)
	for t in ["rooms", "avatars", "frames", "badges"]:
		if _want("owned_" + t):
			await sheet_shot(func(): _open_shop(t, true), "owned_" + t)
	if _want("earn"):
		await sheet_shot(func(): ShopSheet.make_earn().open(main.sheet_layer), "earn")
	if _want("preview_room"):
		await sheet_shot(func(): PreviewSheet.new("dream").open(main.sheet_layer), "preview_room", 3.0)
	if _want("preview_scene"):
		await sheet_shot(func(): PreviewSheet.new("frost", "scene").open(main.sheet_layer), "preview_scene", 6.0)
	if _want("preview_open"):                    # right after opening: the snapshot, no live view yet
		await sheet_shot(func(): PreviewSheet.new("candy", "scene").open(main.sheet_layer), "preview_open", 0.3)
	if _want("preview_scene_owned"):
		await sheet_shot(func(): PreviewSheet.new("jungle", "scene").open(main.sheet_layer), "preview_scene_owned", 6.0)
	if _want("settings"):
		main.open_settings()
		await _sleep(0.9)
		await shot("settings")
		var s: Sheet = main._top_sheet()
		if s and s.scroll_box:
			s.scroll_box.scroll_vertical = 100000
			await _sleep(0.4)
			await shot("settings_bottom")
		await close_top()
	if _want("credits"):
		await sheet_shot(func(): SettingsSheet.CreditsSheet.new().open(main.sheet_layer), "credits")
	if _want("profile"):
		main._on_tab("profile")
		await _sleep(0.9)
		await shot("profile")
		var ps: Sheet = main._top_sheet()
		if ps and ps.get("_tabs"):
			ps._tabs.tap("ach")
			await _sleep(0.5)
			await shot("profile_ach")
		await close_top()
	if _want("setup"):
		main._open_setup("ludo", "cpu")
		await _sleep(0.8)
		await shot("setup")
		Info.open_key("team")
		Info.open_key("ind")
		await _sleep(0.6)
		await shot("setup_info")
		Info.close()
		await close_top()
		main._open_setup("sl", "cpu")
		await _sleep(0.8)
		await shot("setup_sl")
		await close_top()
	if _want("kit"):
		await _kit()
	Save._dirty = false
	get_tree().quit()

## A kit sheet: medals at three sizes (earned + not earned), section labels, sm buttons, a PM sheet with a kicker.
func _kit() -> void:
	var s := Sheet.new("Kit check", UIKit.W.form, true, Sheet.LOOK_PM)
	s.set_kicker("Snakes & Ladders")
	var list := s.add_scroll_body()
	list.add_child(UIKit.caption("Medals"))
	for px in [26.0, 42.0, 68.0]:
		var row := UIKit.hbox(UIKit.SPACE.sm)
		for a: Dictionary in Collection.ACH:
			var b := Collection.make_badge(a.id, px)
			row.add_child(b)
		list.add_child(row)
	var row2 := UIKit.hbox(UIKit.SPACE.sm)
	for a: Dictionary in Collection.ACH:
		var b := Collection.make_badge(a.id, 42.0)
		Collection.set_dim(b, true, 1.0, 0.42)
		row2.add_child(b)
	list.add_child(row2)
	list.add_child(UIKit.caption("Buttons"))
	var h := UIKit.hbox(UIKit.SPACE.sm)
	for k in ["xs", "sm", "md"]:
		var b := UIKit.btn(k, "honey", k)
		h.add_child(b)
		b.ready.connect(func(): print("button ", k, " size ", b.size, " min ", b.get_combined_minimum_size()))
	list.add_child(h)
	s.open(main.sheet_layer)
	await _sleep(0.9)
	await shot("kit")
	await close_top()

func _want(name: String) -> bool:
	if only.is_empty():
		return true
	for f in only:
		if name.begins_with(str(f)):
			return true
	return false

func _open_shop(t: String, owned := false) -> void:
	var s = ShopSheet.new(t, float(UIKit.W.catalog), owned)
	if main.has_method("apply_shop_changes"):
		main.apply_shop_changes(s)
	s.open(main.sheet_layer)

func sheet_shot(open: Callable, name: String, wait := 0.9) -> void:
	open.call()
	await _sleep(wait)
	await shot(name)
	await close_top()

func close_top() -> void:
	main.close_all_sheets()
	Info.close()
	await _sleep(0.35)

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	n += 1
	get_viewport().get_texture().get_image().save_png("%s/%02d_%s.png" % [out, n, name])
	print("shot ", name)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE or what == NOTIFICATION_WM_CLOSE_REQUEST:
		if is_instance_valid(Save):
			Save._dirty = false

func _sleep(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _until(f: Callable, timeout: float) -> void:
	var t0 := Time.get_ticks_msec()
	while not f.call() and (Time.get_ticks_msec() - t0) / 1000.0 < timeout:
		await get_tree().process_frame
