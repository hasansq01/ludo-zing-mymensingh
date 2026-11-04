extends Node
## Dev: leaving and coming back to an online match in the real app (main.gd's pause / resume handling, the real
## LudoMatch / SLMatch), against the in-process fake server (NetFake.Hub; no network). For each game:
##   1. the app goes to the background mid-match: no pause menu over the board
##   2. a bot takes the seat while the phone is away (the server's grace / timeouts): the away prompt
##   3. the app comes back: the seat is asked back by itself, the prompt goes, no menu
##   4. back in front first, the bot's `mode cpu` arriving just after (acts catching up): taken back as well
## Prints PASS / FAIL lines and takes a screenshot at each step.
##   godot --path . --resolution 390x844 res://dev/back_check.tscn -- <out_dir>
## Never writes user://save.json: Save's debounced flush is unhooked and Save._dirty is cleared before every pause
## (main.gd flushes on pause).

var out := "/tmp"
var main: Node
var hub: NetFake.Hub
var n := 0
var fails := 0
var _drive_left := 0.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size():
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	if Save._timer and Save._timer.timeout.is_connected(Save.flush):
		Save._timer.timeout.disconnect(Save.flush)      # dev run: nothing reaches user://save.json
	Save.prefs.welcome_seen = true
	Save.prefs.tutorial_done = true
	Save.prefs.erase("net_room")
	Save.prefs.speed = 0.55
	Save.prefs.quick_players = 2
	Rewards.daily_data(Save.profile).auto_on = Time.get_date_string_from_system()   # no daily sheet popping up
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _until(func(): return main.screen == "home", 60)
	await _sleep(1.5)
	main.close_all_sheets()
	hub = NetFake.Hub.new(7)
	var net: NetClient = main.online.net
	net.url_base = "ws://fake"
	net.make_transport = hub.transport_factory()
	net.http_fn = hub.http
	net.session_fn = func() -> String: return "dev-session"
	await _check("ludo")
	await _check("sl")
	print("BACK CHECK: %s (%d failed)" % ["PASS" if fails == 0 else "FAIL", fails])
	Save._dirty = false
	get_tree().quit(1 if fails else 0)

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

func _check(game: String) -> void:
	main.home.select_game(game)
	await _sleep(1.5)
	main.home.quick_button.pressed.emit()
	await _sleep(0.6)
	(main.online.quick_sheet as QuickSheet).find.emit(2)
	await _sleep(1.0)
	hub.mm.fill(game, 2)
	await _until(func(): return main.screen == game and main.get(game).online, 15)
	await _sleep(2.5)
	var M: Node = main.get(game)
	var me: int = M.ns.me
	var room: NetFake.Room = hub.rooms.get(main.online.net.code)
	# 1. to the background
	Save._dirty = false
	main._notification(NOTIFICATION_APPLICATION_PAUSED)
	await _sleep(0.8)
	await shot(game + "_1_background")
	_ok(game + ": the app in the background opens no pause menu over an online board", main._pause_sheet == null)
	# 2. a bot takes the seat while away
	room._act({k = "mode", c = me, mode = "cpu"})
	await _sleep(1.2)
	await shot(game + "_2_bot_took_the_seat")
	_ok(game + ": while away, the bot plays the seat (the away prompt is up)", _seat_cpu(room, me) and _away_up(M))
	# 3. back in front
	main._notification(NOTIFICATION_APPLICATION_RESUMED)
	await _until(func(): return not _seat_cpu(room, me), 5)
	await _sleep(1.0)
	await shot(game + "_3_back")
	_ok(game + ": back in the app: the seat is yours again (server side) without a tap", not _seat_cpu(room, me))
	_ok(game + ": ... the away prompt is gone and no menu is open", not _away_up(M) and main._pause_sheet == null)
	# 4. back in front first, the bot's act arriving just after
	Save._dirty = false
	main._notification(NOTIFICATION_APPLICATION_PAUSED)
	await _sleep(0.5)
	main._notification(NOTIFICATION_APPLICATION_RESUMED)
	await _sleep(0.3)
	room._act({k = "mode", c = me, mode = "cpu"})
	await _until(func(): return not _seat_cpu(room, me), 5)
	await _sleep(1.0)
	await shot(game + "_4_late_bot_sent_away")
	_ok(game + ": a bot showing up just after coming back is sent away too", not _seat_cpu(room, me) and not _away_up(M))
	main.online.leave()
	main.close_all_sheets()
	main.go_home()
	await _until(func(): return main.screen == "home", 10)
	await _sleep(1.0)

func _seat_cpu(room: NetFake.Room, c: int) -> bool:
	if room.game == "sl":
		for p in room.S.players:
			if int(p.c) == c:
				return bool(p.cpu)
		return false
	return room.S.players[c] == "cpu"

func _away_up(M: Node) -> bool:
	var box: Control = M.hud.away_box if M is LudoMatch else M.away_box
	return box != null and box.visible

func _ok(what: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		fails += 1

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	n += 1
	get_viewport().get_texture().get_image().save_png("%s/%02d_%s.png" % [out, n, name])

func _sleep(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _until(f: Callable, timeout: float) -> void:
	var t0 := Time.get_ticks_msec()
	while not f.call() and (Time.get_ticks_msec() - t0) / 1000.0 < timeout:
		await get_tree().process_frame
