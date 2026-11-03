extends Control
## Dev preview: the Collection sheet (a tab) or the Player Profile (profile / achievements pane) over a warm
## background; saves a screenshot and quits. Never writes the save: Collection / Catalog writes go to a no-op writer,
## the flush timer is unhooked and Save.profile is restored before quitting.
## godot --path . res://dev/preview_collection.tscn -- col chars|avatars|frames|plates|badges [buy=<id>] [use=<id>] [scroll] [narrow] [new] [out_dir]
## godot --path . res://dev/preview_collection.tscn -- profile [ach] [claim=<id>] [open] [scroll] [narrow] [new] [out_dir]

const OUT := "/private/tmp/claude-501/-Users-shihabshaharia-Coding-ludo-zing-mymensingh/d8feebe6-eee1-4f48-a116-aa2f313481c9/scratchpad/agent_coll"

func _click(at: Vector2) -> void:
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = at
		e.global_position = at
		Input.parse_input_event(e)
		await get_tree().process_frame

func _ready() -> void:
	get_tree().create_timer(25.0).timeout.connect(get_tree().quit)   # never hang on a script error
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

	Save._timer.timeout.disconnect(Save.flush)
	var backup: Dictionary = Save.profile.duplicate(true)
	var nowrite := func(_p: Dictionary) -> bool:
		Save.changed.emit()
		return true
	Collection.writer = nowrite
	Catalog.writer = nowrite
	var args := OS.get_cmdline_user_args()
	if args.has("narrow"):
		get_tree().root.content_scale_size = Vector2i(320, 844)
		await get_tree().process_frame
	var kind := args[0] if args.size() > 0 else "col"
	var which := args[1] if args.size() > 1 and not args[1].contains("=") and not args[1].begins_with("/") else "chars"
	var out := OUT
	var p := Save.profile
	# a mid-game player (like the web reference shots)
	p.name = "Shihab"; p.coins = 10500; p.xp = 520
	p.stats = {played = 12, wins = 7, losses = 5, streak = 1, bestStreak = 3, coinsEarned = 6400, pairsFormed = 10, ppGames = 2, slPlayed = 3, slWins = 1}
	p.claimed = ["first"]; p.av_owned = ["ch-rafi"]; p.avatar = "ch-nadia"; p.frame = "mint"; p.plate = "ruby"; p.badge = "streak"
	if args.has("new"):
		p.name = "You"; p.coins = 5000; p.xp = 0
		for k in p.stats: p.stats[k] = 0
		p.claimed = []; p.av_owned = []; p.avatar = "pawn-red"; p.frame = "classic"; p.plate = "plain"; p.badge = ""
	var tag := ""
	var sheet: Sheet
	if kind == "sizes":   # the helpers the home chip / game cards use, at their sizes, in every frame
		var col := UIKit.vbox(14)
		col.position = Vector2(16, 40)
		layer.add_child(col)
		for f: Dictionary in Collection.FRAMES:
			var row := UIKit.hbox(14)
			for sz in [36, 44, 56, 78]:
				row.add_child(Collection.make_avatar_of(["ch-fahim", "robot", "ch-ayesha", "pawn-blue"][Collection.FRAMES.find(f)], f.id, sz))
			var t := TextureRect.new()
			t.texture = Collection.art_texture("ch-lamia", 128)
			t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			t.custom_minimum_size = Vector2(44, 44)
			row.add_child(t)
			col.add_child(row)
		for pl: Dictionary in Collection.PLATES:
			col.add_child(Collection.make_plate("Shihab", pl.id, "coins", 20, false))
		col.add_child(Collection.make_plate("A very long player name", "ruby", "first", 20, false, 160.0))
		var badges := UIKit.hbox(8)
		for a: Dictionary in Collection.ACH:
			badges.add_child(Collection.make_badge(a.id, 44, a.id == "veteran"))
		col.add_child(badges)
		var live := Collection.make_avatar(64)
		col.add_child(live)
		await get_tree().create_timer(0.5).timeout
		var path0 := "%s/sizes%s.png" % [out, "_hi" if args.has("hi") else ""]
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(path0)
		print("saved ", path0)
		Save.profile.clear()
		Save.profile.merge(backup)
		Save._dirty = false
		Collection.writer = Callable()
		Catalog.writer = Callable()
		get_tree().quit()
		return
	if kind == "profile":
		sheet = ProfileSheet.new()
		sheet.connect("profile_changed", func(): print("profile_changed"))
	else:
		sheet = CollectionSheet.new(which)
		sheet.connect("changed", func(): print("changed"))
	sheet.open(layer)
	await get_tree().create_timer(1.0).timeout
	for a: String in args:
		if a.begins_with("/"):
			out = a
		elif a.begins_with("buy=") or a.begins_with("use="):
			var id := a.substr(4)
			var k: String = "char" if Collection.is_character(id) else {avatars = "avatar", frames = "frame", plates = "plate", badges = "badge"}.get(which, "avatar")
			sheet.call("_on_press", k, id)
			print("after ", a, ": coins=", p.coins, " owned=", p.av_owned, " avatar=", p.avatar, " frame=", p.frame, " plate=", p.plate, " badge=", p.badge)
			tag += "_" + a.replace("=", "-")
			await get_tree().create_timer(0.5).timeout
		elif a == "ach":
			sheet.call("show_pane", "ach")
			tag += "_ach"
			await get_tree().create_timer(0.4).timeout
		elif a.begins_with("claim="):
			sheet.call("_claim", a.substr(6))
			print("after claim: coins=", p.coins, " claimed=", p.claimed, " earned=", p.stats.coinsEarned)
			tag += "_" + a.replace("=", "-")
			await get_tree().create_timer(0.5).timeout
		elif a == "open":
			sheet.call("_open_collection")
			tag += "_open"
			await get_tree().create_timer(0.8).timeout
			sheet = layer.get_child(layer.get_child_count() - 1)   # later actions go to the Collection on top
			kind = "profile"; which = "chars"
		elif a == "clicks":   # real input: the Avatars tab, then the Latte card's Use button
			var tabs: Control = sheet.get("_tabs")
			var r: Rect2 = tabs.call("_rect", 1)
			await _click(tabs.get_global_transform_with_canvas() * r.get_center())
			await get_tree().create_timer(0.4).timeout
			print("tab after click: ", sheet.get("tab"))
			var btns := sheet.find_children("*", "Button", true, false).filter(func(b): return b.text == "Use")
			var btn: Button = btns[3]
			await _click(btn.get_global_transform_with_canvas() * (btn.size / 2.0))
			await get_tree().create_timer(0.4).timeout
			print("after click use: avatar=", p.avatar)
			tag += "_clicks"
		elif a == "scroll":
			for sc: ScrollContainer in layer.find_children("*", "ScrollContainer", true, false):
				sc.scroll_vertical = 100000
			tag += "_scroll"
			await get_tree().create_timer(0.3).timeout
	var vs := get_viewport_rect().size
	var path := "%s/%s_%s%s%s_%dx%d.png" % [out, kind, which if kind == "col" else "main", tag, ("_new" if args.has("new") else "") + ("_hi" if args.has("hi") else ""), int(vs.x), int(vs.y)]
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path, " card ", sheet.card.size)
	Save.profile.clear()
	Save.profile.merge(backup)
	Save._dirty = false
	Collection.writer = Callable()
	Catalog.writer = Callable()
	get_tree().quit()
