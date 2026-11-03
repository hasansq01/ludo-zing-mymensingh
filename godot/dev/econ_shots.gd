extends Node
## Dev: screenshots of the coin tables and re-rolls in the real app, against the in-process fake server (NetFake.Hub:
## the quick matchmaker with coin tables, ghost seats played by the fake room; no network):
##   01 the table picker (level 7, 800 coins: Practice and 100 / 500 playable, 2,000 greyed out, 10,000 locked)
##   02 the same for 4 players (the prizes follow)
##   03 the "Out of coins" popup (40 coins; the video button forced on for the picture)
##   04 a Ludo match at the 100 table with "Roll again" over the tile row after a bad roll
##   05 the next player's held state (a ghost may roll again: the dice sleep, the note under the tiles)
##   06 the coin-table result card with "Double it with a video" (the video forced on)
##   07 a lost coin-table result ("Entry 100 lost")
##   godot --path . --resolution 390x844 res://dev/econ_shots.tscn -- <out_dir>
## Never writes the real save: Save's debounced flush is unhooked and the file is restored at the end anyway.

var out := "/private/tmp/claude-501/econ-shots"
var main: Node
var n := 0
var _backup := ""
var hub: NetFake.Hub
var auto_me := false
var _drive_left := 0.0
var coins := 800
var level := 7


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size():
		out = args[0]
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
	Save.prefs.quick_table = "t100"
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
	main.online.coins_fn = func() -> int: return coins
	main.online.level_fn = func() -> int: return level
	main.online.reveal_fast = true
	if main.get("account") is Object:
		main.account.enabled = true          # the result shows the server's online rewards
		main.account.http_fn = func(_m: int, p: String, _b: Variant, _s: String) -> Dictionary:
			if p == "/v1/tables":            # the fake account: broke, the bonus is there (no request leaves this machine)
				return {status = 200, data = {ok = true, tables = [], broke_bonus = {available = true, next_at = 0, amount = 300}}, session = ""}
			return {status = 0}
	await _picker()
	await _broke()
	await _match()
	_restore()
	get_tree().quit()

func _process(d: float) -> void:
	if hub == null:
		return
	_drive_left -= d
	if _drive_left > 0.0:
		return
	_drive_left = 0.9
	if auto_me:
		_play_mine()

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

# ---------- screens ----------

func _picker() -> void:
	main.home.quick_button.pressed.emit()
	await _sleep(0.9)
	await shot("table_picker_2p")
	var qs: QuickSheet = main.online.quick_sheet
	qs.players = 4
	qs._refresh_rows()
	qs.picker.get_child(1).button_pressed = true
	await _sleep(0.4)
	await shot("table_picker_4p")
	qs.close()
	await _sleep(0.5)

func _broke() -> void:
	coins = 40
	main.home.quick_button.pressed.emit()
	await _sleep(0.9)
	var b: BrokeSheet = main.online.broke_sheet
	b.ad_ok_fn = func() -> bool: return true      # (no ad plugin on the desktop: shown for the picture)
	b.refresh()
	await _sleep(0.4)
	await shot("broke_popup")
	b.close()
	await _sleep(0.5)
	main.close_all_sheets()
	coins = 5000

func _room() -> NetFake.Room:
	return hub.rooms.get(main.online.net.code)

func _match() -> void:
	main.home.quick_button.pressed.emit()
	await _sleep(0.6)
	var qs: QuickSheet = main.online.quick_sheet
	qs.select_table("t100")
	qs.find.emit(2)
	await _sleep(0.8)
	var room := hub.mm.fill("ludo", 2, "t100")
	room.rr_default = {free = 1, gems = 0}
	room.window_ms = 3800
	await _until(func(): return main.screen == "ludo" and main.ludo.online, 15)
	await _sleep(2.0)
	var L: LudoMatch = main.ludo
	await _until(func(): return L.ns.my_turn() and L.S.phase == "roll" and not L._busy, 30)
	await _sleep(0.6)
	# a bad roll: "Roll again"
	room.dice = [3]
	L._on_dice()
	await _until(func(): return L.hud.reroll_button.visible, 10)
	await _sleep(0.35)
	await shot("ludo_roll_again_offer")
	await _sleep(4.2)
	# the next player's hold: a ghost's bad roll while it is your turn next
	await _until(func(): return L.ns.my_turn() and not L._busy, 30)
	room.ghost_reroll = 1.0
	room.window_ms = 9000                       # long enough to catch the held state on camera
	room.force_bad_roll(2, 3)
	await _sleep(0.6)
	room.step()
	await _until(func(): return L.rr.holds(L.ns.me), 10)
	await _sleep(1.2)                            # the ghost's dice settle; the hold still runs
	await shot("ludo_next_player_held")
	await _sleep(4.2)
	room.ghost_reroll = 0.0
	# the end: you win the 100 table
	_near_end(room, true)
	auto_me = true
	await _until(func(): return is_instance_valid(main._result), 120)
	auto_me = false
	await _sleep(0.5)
	var data: Dictionary = main._result.data.duplicate(true)
	main._result.queue_free()
	await _sleep(0.3)
	data.ads = true                            # (no ad plugin on the desktop: shown for the picture)
	var r := ResultScreen.new(data)
	main._result = r
	r.open(main.sheet_layer)
	await _sleep(4.5)
	await shot("result_coin_table_win")
	r.queue_free()
	await _sleep(0.3)
	# a loss
	data.table = {tier = "t100", entry = 100, payout = 0, match_id = data.table.match_id}
	data.reward = 0
	data.human_won = false
	var r2 := ResultScreen.new(data)
	main._result = r2
	r2.open(main.sheet_layer)
	await _sleep(4.0)
	await shot("result_coin_table_lost")
	main.online.leave()
	main.go_home()
	await _sleep(1.0)

func _near_end(room: NetFake.Room, win: bool) -> void:
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
	room.dice = [4]
	room._broadcast(room._sync_msg())
	room._broadcast(room._turn_msg())

# ---------- helpers ----------

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	n += 1
	get_viewport().get_texture().get_image().save_png("%s/%02d_%s.png" % [out, n, name])
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
