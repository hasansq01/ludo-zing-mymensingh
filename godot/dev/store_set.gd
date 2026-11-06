extends Node
## Dev: the whole set of Play Store screenshots from the real app, through the 1080x1920 launcher:
##   STORE_SCENE=store_set godot --path . --resolution 1080x1920 res://dev/store_shots.tscn -- <out_dir>
## Home, a Ludo match, Snakes & Ladders, the quick match tables, a win, emotes, the daily reward, the Shop, and the
## Lucky Draw as a spare. Sound off. The tables come from the in-process fake server (NetFake.Hub): no request leaves
## this machine for them. Nothing reaches user://save.json: Save.writes_off is on, the profile is only changed in
## memory, and no match is stored.

var out := "/tmp"
var main: Node
var n := 0
var hub: NetFake.Hub


func _ready() -> void:
	Save.writes_off = true
	MatchStore.enabled = false
	AudioServer.set_bus_mute(0, true)
	var args := OS.get_cmdline_user_args()
	if args.size():
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	var today := Time.get_date_string_from_system()
	Save.prefs.welcome_seen = true
	Save.prefs.tutorial_done = true
	Save.prefs.erase("net_room")
	Save.prefs.speed = 0.55
	Save.prefs.cam = "3d"
	Save.prefs.sl_cam = "top"
	Save.prefs.home_game = "ludo"
	Save.prefs.room_auto = true
	Save.prefs.quick_players = 4
	Save.profile.room = "night"              # (room_auto: the café by the clock, run this in the daytime)
	Save.profile.name = "Sajib"
	Save.profile.avatar = "w-kenji"
	Save.profile.coins = 12450
	Save.profile.gems = 120
	for pair in [["dice_owned", "gold"], ["pawns_owned", "kitty"]]:
		if not (Save.profile[pair[0]] as Array).has(pair[1]):
			(Save.profile[pair[0]] as Array).append(pair[1])
	Save.profile.dice = "gold"
	Save.profile.pawn = "kitty"
	Save.profile.daily = {cycle = 0, streak = 3, last = Rewards.add_days(today, -1), history = []}
	Rewards.daily_data(Save.profile).auto_on = today
	Quality.force("high")
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _until(func(): return main.screen == "home", 60)
	await _sleep(2.5)
	main.close_all_sheets()
	main.home.refresh()
	await _sleep(1.0)
	_wire_fake_server()
	await shot("01-home")
	await _tables()
	await _sheet("daily", "07-daily-reward")
	await _sheet("spin", "09-lucky-draw")
	await _shop("pawns", "08-shop-pawns", 0)
	await _shop("dice", "08-shop-dice", 0)
	await _text_pack("bangla", "10-text-pack-bangla")
	await _text_pack("react", "10-text-pack-reactions")
	await _ludo()
	await _sl()
	get_tree().quit()

func _process(_d: float) -> void:
	Save._dirty = false

func _wire_fake_server() -> void:
	hub = NetFake.Hub.new(5)
	var net: NetClient = main.online.net
	net.url_base = "ws://fake"
	net.make_transport = hub.transport_factory()
	net.http_fn = hub.http
	net.session_fn = func() -> String: return "dev-session"
	main.online.coins_fn = func() -> int: return 12450
	main.online.level_fn = func() -> int: return 9

func _tables() -> void:
	main.home.quick_button.pressed.emit()
	await _sleep(0.9)
	var qs: QuickSheet = main.online.quick_sheet
	qs.players = 4
	qs._refresh_rows()
	qs.picker.get_child(1).button_pressed = true
	await _sleep(0.6)
	await shot("04-quick-match-tables")
	qs.close()
	await _sleep(0.5)
	main.close_all_sheets()

func _sheet(tab: String, name: String) -> void:
	main._on_tab(tab)
	await _sleep(1.4)
	await shot(name)
	main.close_all_sheets()
	await _sleep(0.6)

func _shop(tab: String, name: String, scroll: int) -> void:
	var s := ShopSheet.new(tab)
	s.open(main.sheet_layer)
	await _sleep(1.2)
	s.scroll_box.scroll_vertical = scroll
	await _sleep(1.6)
	await shot(name)
	main.close_all_sheets()
	await _sleep(0.6)

func _text_pack(id: String, name: String) -> void:
	var s := EmotePackSheet.new(id, "text")
	s.open(main.sheet_layer)
	await _sleep(1.6)
	await shot(name)
	main.close_all_sheets()
	await _sleep(0.6)

func _ludo() -> void:
	main.start_ludo({game = "ludo", players = ["human", "cpu", "cpu", "cpu"], teams = false, bot_level = "normal"})
	var L: LudoMatch = main.ludo
	await _until(func(): return not L.S.is_empty() and L.S.phase == "roll" and not L._busy and L.S.turn == 0, 20)
	await _sleep(1.0)
	_place(L, [[12, 27, -1, -1], [5, 20, 38, -1], [33, 9, -1, -1], [22, 41, 3, -1]])
	await _sleep(1.5)
	await shot("02-ludo-3d-board")
	main.hud.emotes.show_emote(0, "t-gg")
	main.hud.emotes.show_emote(1, "gLaugh")
	main.hud.emotes.show_emote(2, "t-bgg")
	main.hud.emotes.show_emote(3, "t-wow")
	await _sleep(1.0)
	await shot("06-emotes")
	await _sleep(3.0)
	L.autoplay = true
	_place(L, [[56, 56, 56, 51], [30, 44, -1, -1], [12, -1, 20, -1], [40, 7, -1, -1]])
	await _sleep(0.6)
	L.roll(5)
	await _until(func(): return is_instance_valid(main._result), 30)
	await _sleep(4.5)
	await shot("05-win-result")
	main._result.queue_free()
	main.go_home()
	await _sleep(1.0)

func _place(L: LudoMatch, tok: Array) -> void:
	for c in 4:
		L.S.tok[c] = (tok[c] as Array).duplicate()
	L.S.pairs = []
	L.S.turn = 0
	L.S.phase = "roll"
	L.S.sixes = 0
	L._id += 1
	L.board.relayout(L.S)
	L.hud.update(L.S, 0)
	L._busy = false

func _sl() -> void:
	main.start_sl({game = "sl", mode = "cpu", n = 4, color = 0})
	await _until(func(): return main.screen == "sl" and not main.sl.G.is_empty(), 20)
	var M = main.sl
	await _until(func(): return M.G.phase == "roll" and not M._busy and M.G.turn == 0, 20)
	await _sleep(1.0)
	var pos := [28, 57, 40, 73]
	for k in pos.size():
		M.G.players[k].pos = pos[k]
	M.G.turn = 0
	M.G.sixes = 0
	M._id += 1
	M._busy = false
	M.board.place(M._positions())
	M._refresh_tiles()
	await _sleep(1.5)
	await shot("03-snakes-and-ladders")
	main.go_home()
	await _sleep(0.6)

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	n += 1
	var img := get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_png("%s/%s.png" % [out, name])
	print("shot ", name, " ", img.get_size())

func _sleep(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _until(f: Callable, timeout: float) -> void:
	var t0 := Time.get_ticks_msec()
	while not f.call() and (Time.get_ticks_msec() - t0) / 1000.0 < timeout:
		await get_tree().process_frame
