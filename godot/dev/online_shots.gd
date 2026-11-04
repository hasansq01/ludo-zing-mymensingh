extends Node
## Dev: screenshots of quick match and Snakes & Ladders online in the real app, against the in-process fake server
## (NetFake.Hub: rooms + matchmaker, ghost seats played by the fake room; no network):
## Home (Ludo / S&L) with QUICK MATCH, the table picker, "Finding players…" (2 and 4 seats), the players revealed,
## a quick-match Ludo match, its result (Play again = queue again), an S&L quick match (your turn with the timer,
## another player's turn, Reconnecting…, the away prompt), its result, and an S&L friends lobby (the game picker).
##   godot --path . --resolution 390x844 res://dev/online_shots.tscn -- <out_dir> [--narrow]
## --narrow: Home and the quick sheets only (run it at --resolution 320x640).
## Never writes the real save: Save's debounced flush is unhooked and the file is restored at the end anyway.

var out := "/tmp"
var main: Node
var n := 0
var _backup := ""
var hub: NetFake.Hub
var narrow := false
var auto_me := false                     # the app plays its own turns (after the shots of them)
var _drive_left := 0.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size():
		out = args[0]
	narrow = args.has("--narrow")
	DirAccess.make_dir_recursive_absolute(out)
	if FileAccess.file_exists("user://save.json"):
		_backup = FileAccess.get_file_as_string("user://save.json")
	if Save._timer and Save._timer.timeout.is_connected(Save.flush):
		Save._timer.timeout.disconnect(Save.flush)      # dev run: nothing reaches user://save.json
	Save.prefs.welcome_seen = true
	Save.prefs.tutorial_done = true
	Save.prefs.erase("net_room")
	Save.prefs.speed = 0.55
	Save.prefs.home_game = "ludo"
	Save.prefs.quick_players = 2
	Save.profile.name = "Shihab"
	Rewards.daily_data(Save.profile).auto_on = Time.get_date_string_from_system()   # no daily sheet popping up
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _until(func(): return main.screen == "home", 60)
	await _sleep(1.5)
	main.close_all_sheets()
	hub = NetFake.Hub.new(5)
	var net: NetClient = main.online.net
	net.url_base = "ws://fake"
	net.make_transport = hub.transport_factory()
	net.http_fn = hub.http
	net.session_fn = func() -> String: return "dev-session"
	if main.get("account") is Object:
		main.account.enabled = true          # the result shows the server's online rewards (no request is made)
	await _home_and_sheets()
	if not narrow:
		await _ludo_quick()
		await _sl_quick()
		await _sl_lobby()
	_restore()
	get_tree().quit()

func _process(d: float) -> void:
	if hub == null:
		return
	_drive_left -= d
	if _drive_left > 0.0:
		return
	_drive_left = 0.9
	for r: NetFake.Room in hub.rooms.values():
		if r.playing:
			r.step()                          # ghosts and bots
	if auto_me:
		_play_mine()

## The app's own turn through its UI paths (a dice tap, the first movable pawn, pairs yes).
func _play_mine() -> void:
	if main.screen == "ludo" and main.ludo.online:
		var L: LudoMatch = main.ludo
		if L._busy or not L.ns.my_turn() or L.ns.pending() > 0:
			return
		if main.hud.pair_box.visible:
			main.hud._answer(true)
		elif L.S.phase == "roll":
			L.roll()
		elif L.S.phase == "choose" and not main.world.board.movable.is_empty():
			L.move(int(LudoRules.units(L.S)[0].token))
	elif main.screen == "sl" and main.sl.online:
		var M: SLMatch = main.sl
		if not M._busy and M.ns.my_turn():
			M.roll()

# ---------- screens ----------

func _home_and_sheets() -> void:
	await shot("home_ludo_quick_match")
	main.home.select_game("sl")
	await _sleep(2.5)
	await shot("home_sl_quick_match")
	main.home.select_game("ludo")
	await _sleep(1.5)
	main.home.quick_button.pressed.emit()
	await _sleep(0.8)
	await shot("quick_picker")
	var qs: QuickSheet = main.online.quick_sheet
	(qs.picker.get_child(1) as Button).button_pressed = true      # 4 players
	await _sleep(0.3)
	qs.find.emit(4)
	await _sleep(2.6)
	await shot("finding_players_4")
	qs.cancel_pressed.emit()
	qs.close()
	await _sleep(0.6)
	main.home.friends_button.pressed.emit()
	await _sleep(0.8)
	await shot("friends_ludo")
	main.close_all_sheets()
	await _sleep(0.3)

func _ludo_quick() -> void:
	main.home.quick_button.pressed.emit()
	await _sleep(0.6)
	var qs: QuickSheet = main.online.quick_sheet
	(qs.picker.get_child(0) as Button).button_pressed = true
	qs.find.emit(2)
	await _sleep(3.2)
	await shot("finding_players_2")
	hub.mm.fill("ludo", 2)                    # a ghost takes the empty seat
	await _sleep(0.75)
	await shot("players_found")
	await _until(func(): return main.screen == "ludo" and main.ludo.online, 10)
	await _sleep(2.0)
	await _until(func(): return main.ludo.ns.my_turn() and main.ludo.S.phase == "roll" and not main.ludo._busy, 30)
	await _sleep(0.8)
	await shot("quick_ludo_your_turn")
	auto_me = true
	await _until(func(): return not main.ludo.ns.my_turn(), 20)
	await _sleep(1.2)
	await shot("quick_ludo_their_turn")
	_ludo_near_end()
	await _until(func(): return is_instance_valid(main._result), 120)
	auto_me = false
	await _sleep(4.0)
	await shot("quick_ludo_result")
	main._result.play_again.emit()
	await _sleep(1.2)
	await shot("quick_play_again_searching")
	main.online.cancel_quick()
	main.close_all_sheets()
	main.go_home()
	await _sleep(1.0)

func _ludo_near_end() -> void:
	var room := _room()
	var S := room.S
	var me: int = main.ludo.ns.me
	for c in 4:
		if S.players[c] != "off":
			S.tok[c] = [56, 56, 56, 52] if c == me else [56, 56, 40, 30]
	S.pairs = []
	S.phase = "roll"
	S.pending = {}
	S.sixes = 0
	S.turn = me
	room._broadcast(room._sync_msg())
	room._broadcast(room._turn_msg())

func _sl_quick() -> void:
	main.home.select_game("sl")
	await _sleep(2.0)
	main.home.quick_button.pressed.emit()
	await _sleep(0.6)
	var qs: QuickSheet = main.online.quick_sheet
	qs.find.emit(2)
	await _sleep(1.5)
	await shot("sl_finding_players")
	hub.mm.fill("sl", 2)
	await _until(func(): return main.screen == "sl" and main.sl.online, 15)
	await _sleep(2.5)
	await _until(func(): return main.sl.ns.my_turn() and not main.sl._busy, 30)
	await _sleep(1.0)
	await shot("sl_online_your_turn")
	auto_me = true
	await _until(func(): return not main.sl.ns.my_turn(), 20)
	await _sleep(1.0)
	await shot("sl_online_their_turn")
	auto_me = false
	# the socket drops: Reconnecting…
	var net: NetClient = main.online.net
	var pipe: NetFake.Pipe = net.transport
	net.make_transport = func() -> NetTransport:
		var p := hub.make_pipe()
		p.reachable = false
		return p
	pipe.drop()
	await _sleep(1.2)
	await shot("sl_online_reconnecting")
	net.make_transport = hub.transport_factory()
	await _until(func(): return net.is_open(), 20)
	await _sleep(1.5)
	# a bot takes your seat (two timeouts): the away prompt
	var room := _room()
	room._act({k = "mode", c = main.sl.ns.me, mode = "cpu"})
	await _sleep(1.2)
	await shot("sl_online_away")
	main.sl.away_button.pressed.emit()
	await _sleep(1.0)
	# near the end: everyone close to 100, then play it out
	for p in room.S.players:
		p.pos = 94 if int(p.c) == main.sl.ns.me else 70
	room.S.turn = main.sl.ns.index_of(main.sl.ns.me)
	room.S.sixes = 0
	room.dice = [6, 1, 2, 6]
	room._broadcast(room._sync_msg())
	room._broadcast(room._turn_msg())
	auto_me = true
	await _until(func(): return is_instance_valid(main._result), 120)
	auto_me = false
	await _sleep(4.0)
	await shot("sl_online_result")
	main.online.leave()
	main.go_home()
	await _sleep(1.0)

func _sl_lobby() -> void:
	main.home.select_game("sl")
	await _sleep(1.0)
	main.home.friends_button.pressed.emit()
	await _sleep(0.6)
	main.online.friends.create_room.emit()
	await _until(func(): return is_instance_valid(main.online.lobby_sheet), 5)
	await _sleep(1.0)
	var f := NetClient.new()
	f.use_save = false
	f.prefs = {}
	f.url_base = "ws://fake"
	f.profile_fn = func() -> Dictionary: return {name = "Rafi", avatar = "ch-rafi", frame = "classic"}
	f.make_transport = hub.transport_factory()
	add_child(f)
	f.join(main.online.net.code)
	await _sleep(1.0)
	await shot("sl_friends_lobby_host")
	f.leave()
	main.online.leave()
	main.close_all_sheets()

# ---------- helpers ----------

func _room() -> NetFake.Room:
	return hub.rooms.get(main.online.net.code)

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	n += 1
	get_viewport().get_texture().get_image().save_png("%s/%02d_%s%s.png" % [out, n, name, "_320" if narrow else ""])
	print("shot ", name)

func _restore() -> void:
	Save._dirty = false
	if _backup != "":
		var f := FileAccess.open("user://save.json", FileAccess.WRITE)
		f.store_string(_backup)
		f.close()
		Save.load_data()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_restore()

func _sleep(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _until(f: Callable, timeout: float) -> void:
	var t0 := Time.get_ticks_msec()
	while not f.call() and (Time.get_ticks_msec() - t0) / 1000.0 < timeout:
		await get_tree().process_frame
