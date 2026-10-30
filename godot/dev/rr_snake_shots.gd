extends Node
## Dev: two screenshots of the S&L "Roll again" offer showing while the snake gulps the pawn (fake server, no network):
##   godot --path . --resolution 360x780 res://dev/rr_snake_shots.tscn -- <out_dir>
## Never writes the real save (flush unhooked, file restored at the end).
## Dev: screenshots of the coin tables and re-rolls in the real app, against the in-process fake server (NetFake.Hub:
##   godot --path . --resolution 390x844 res://dev/econ_shots.tscn -- <out_dir>
## Never writes the real save: Save's debounced flush is unhooked and the file is restored at the end anyway.

var out := "/private/tmp/claude-501/rr_snake"
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
	Save.prefs.speed = 1.0
	Save.prefs.home_game = "sl"
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
	main.home.quick_button.pressed.emit()
	await _sleep(0.6)
	var qs: QuickSheet = main.online.quick_sheet
	qs.select_table("practice")
	qs.find.emit(2)
	await _sleep(0.8)
	var room := hub.mm.fill("sl", 2, "practice")
	room.rr_default = {free = 1, gems = 0}
	room.window_ms = 3000
	await _until(func(): return main.screen == "sl" and main.sl.online, 15)
	await _sleep(2.0)
	var S: SLMatch = main.sl
	await _until(func(): return S.ns.my_turn() and S.G.phase == "roll" and not S._busy, 30)
	room.force_bad_roll(S.ns.me, 3)
	await _sleep(0.6)
	S._on_dice()
	await _until(func(): return S.reroll_button.visible, 10)
	await _sleep(0.3)
	await shot("offer_at_head")
	await _sleep(0.35)
	await shot("offer_mid_gulp")
	await _sleep(3.0)
	_restore()
	get_tree().quit()

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
