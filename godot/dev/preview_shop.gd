extends Node
## Dev preview of the merged Shop (ShopSheet: Rooms / Scenes / Dice / Avatars / Frames / Plates / Badges, the Owned
## filter, the Get coins sheet, the buy confirm, the "Need" toast and the room preview) inside the real app, so the
## room and scene cards show their real 3D thumbnails. Screenshots go to out_dir, then it quits.
## Never writes the save: the flush timer is unhooked, Catalog / Collection writes go to a no-op writer, and the
## profile (and the save file, belt and braces) are restored at the end.
##   godot --path . --resolution 390x844 res://dev/preview_shop.tscn -- <out_dir> [narrow] [quick]
##   narrow: lay the UI out at 320 px wide. quick: tabs only (no flows).

var out := "/tmp"
var main: Node
var _file_backup := ""
var _profile_backup := {}
var _prefs_backup := {}
var _fails := 0


func _ready() -> void:
	get_tree().create_timer(150.0).timeout.connect(func():
		print("preview_shop: timeout")
		_finish())
	var args := OS.get_cmdline_user_args()
	for a: String in args:
		if a.begins_with("/"):
			out = a
	DirAccess.make_dir_recursive_absolute(out)
	if FileAccess.file_exists("user://save.json"):
		_file_backup = FileAccess.get_file_as_string("user://save.json")
	if Save._timer.timeout.is_connected(Save.flush):
		Save._timer.timeout.disconnect(Save.flush)
	_profile_backup = Save.profile.duplicate(true)
	_prefs_backup = Save.prefs.duplicate(true)
	var nowrite := func(_p: Dictionary) -> bool:
		Save.changed.emit()
		return true
	Catalog.writer = nowrite
	Collection.writer = nowrite
	if args.has("narrow"):
		get_tree().root.content_scale_size = Vector2i(320, 844)
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _until(func(): return main.screen in ["home", "welcome"], 60)
	for c in main.screens.get_children():
		if c is Welcome:
			c.continued.emit()
	await _until(func(): return main.screen == "home", 10)
	await _sleep(1.0)
	main.close_all_sheets()
	_setup_profile()
	main.home.refresh()
	await _sleep(0.4)
	var suffix := "_320" if args.has("narrow") else ""
	# every tab, all items
	for t in ["rooms", "scenes", "dice", "avatars", "frames", "plates", "badges"]:
		var s := _open_shop(t, false)
		if t in ["rooms", "scenes"]:
			var kind := "room" if t == "rooms" else "scene"
			await _until(func(): return Thumbnailer.ids(kind).all(func(id): return Thumbnailer.is_ready(kind, id)), 40)
		await _sleep(1.0)
		await shot("shop_%s%s" % [t, suffix])
		if t == "avatars":
			s.scroll_box.scroll_vertical = 100000
			await _sleep(0.4)
			await shot("shop_avatars_end%s" % suffix)
		main.close_all_sheets()
		await _sleep(0.3)
	# owned filter
	for t in ["rooms", "avatars", "frames"]:
		_open_shop(t, true)
		await _sleep(0.9)
		await shot("owned_%s%s" % [t, suffix])
		main.close_all_sheets()
		await _sleep(0.3)
	# the Get coins sheet (from the Shop's button)
	var shop := _open_shop("rooms", false)
	await _sleep(0.6)
	shop.open_earn()
	await _sleep(0.8)
	await shot("earn%s" % suffix)
	main.close_all_sheets()
	await _sleep(0.3)
	if args.has("quick"):
		_finish()
		return
	# buy: dice Crema -> confirm -> Yes -> toast + In use
	shop = _open_shop("dice", false)
	await _sleep(0.8)
	var coins0 := Catalog.coins()
	shop._on_buy("dice", "crema", "Crema")
	await _sleep(0.5)
	await shot("buy_confirm%s" % suffix)
	var dlg: Sheet = main._top_sheet()
	check("Buy asks first", dlg != shop and dlg.has_meta("confirm") and Catalog.coins() == coins0)
	var yes: Button = dlg.find_child("Yes", true, false)
	yes.pressed.emit()
	await _sleep(0.5)
	await shot("buy_done%s" % suffix)
	check("bought once, in use", Catalog.owns_dice("crema") and Catalog.dice_in_use() == "crema" and Catalog.coins() == coins0 - 1000)
	main.close_all_sheets()
	await _sleep(0.3)
	# cancel keeps the coins
	shop = _open_shop("rooms", false)
	await _sleep(0.8)
	coins0 = Catalog.coins()
	shop._on_buy("room", "dream", "Pastel Dream Room")
	await _sleep(0.5)
	dlg = main._top_sheet()
	(dlg.find_child("No", true, false) as Button).pressed.emit()
	await _sleep(0.4)
	check("Cancel spends nothing", Catalog.coins() == coins0 and not Catalog.owns_room("dream"))
	# not enough coins: "Need 3.7K" on the button, a toast on tap
	shop.scroll_box.scroll_vertical = 100000
	await _sleep(0.3)
	shop._on_buy("room", "cloud", "Cloudside Playroom")
	await _sleep(0.4)
	await shot("need_toast%s" % suffix)
	check("Need spends nothing", Catalog.coins() == coins0)
	main.close_all_sheets()
	await _sleep(0.3)
	# the room preview (View on a room card)
	shop = _open_shop("rooms", false)
	await _sleep(0.8)
	var vb: Button = null
	for b in shop.find_children("View", "Button", true, false):
		if b.get_meta("view", "") == "dream":
			vb = b
	check("View on the Pastel Dream Room card", vb != null)
	if vb:
		vb.pressed.emit()
		await _sleep(0.3)
		var pv: Sheet = main._top_sheet()
		check("View opens the preview over a hidden Shop", pv is PreviewSheet and not shop.visible)
		await _until(func(): return pv.ready_3d or pv.failed, 20)
		await _sleep(1.6)
		await shot("preview_dream%s" % suffix)
		(pv as PreviewSheet)._on_act()
		await _sleep(0.5)
		await shot("preview_confirm%s" % suffix)
		dlg = main._top_sheet()
		(dlg.find_child("Yes", true, false) as Button).pressed.emit()
		await _sleep(0.6)
		await shot("preview_bought%s" % suffix)
		check("the drag hint fades by itself", pv.get("_hint_faded") and (pv.get("_hint") as Control).modulate.a < 0.05)
		check("preview Buy owns it and puts it in use", Catalog.owns_room("dream") and Catalog.room_in_use() == "dream")
		pv.close()
		await _sleep(0.6)
		check("closing returns to the Shop", shop.visible and main._top_sheet() == shop)
	_finish()


func _setup_profile() -> void:
	var p: Dictionary = Save.profile
	p.name = "Shihab"
	p.coins = 5300
	p.xp = 120
	p.rooms = ["night", "cafe"]; p.room = "night"
	p.dice_owned = ["classic"]; p.dice = "classic"
	p.scenes = ["jungle"]; p.scene = "jungle"
	p.av_owned = []; p.avatar = "pawn-red"; p.frame = "classic"; p.plate = "plain"; p.badge = ""
	var st: Dictionary = p.get("stats", {})
	st.wins = 1; st.played = 3; st.bestStreak = 1
	p.stats = st

func _open_shop(t: String, owned: bool) -> ShopSheet:
	var s := ShopSheet.new(t, 400.0, owned)
	main._wire_shop(s)
	s.open(main.sheet_layer)
	return s

func check(what: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_fails += 1

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("shot ", name)

func _finish() -> void:
	print("preview_shop: %d failed" % _fails)
	Save.profile.clear()
	Save.profile.merge(_profile_backup, true)
	Save.prefs.clear()
	Save.prefs.merge(_prefs_backup, true)
	Save._dirty = false
	Catalog.writer = Callable()
	Collection.writer = Callable()
	if _file_backup != "":
		var f := FileAccess.open("user://save.json", FileAccess.WRITE)
		f.store_string(_file_backup)
		f.close()
	get_tree().quit()

func _sleep(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _until(f: Callable, timeout: float) -> void:
	var t0 := Time.get_ticks_msec()
	while not f.call() and (Time.get_ticks_msec() - t0) / 1000.0 < timeout:
		await get_tree().process_frame
