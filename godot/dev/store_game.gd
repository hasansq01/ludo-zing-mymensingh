extends Node
## Dev: Play Store screenshots of the real app (home, a Ludo match mid-game with pawns out, an emote, the daily
## reward calendar), meant to be run through the 1080x1920 launcher:
##   STORE_SCENE=store_game godot --path . --resolution 1080x1920 res://dev/store_shots.tscn -- <out_dir>
## Never writes user://save.json: the flush timer is unhooked, the dirty flag is cleared every frame, MatchStore is
## off, and the save file and profile are restored at the end.

var out := "/tmp"
var main: Node
var n := 0
var _backup := ""
var _profile_backup := {}

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size():
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	if FileAccess.file_exists("user://save.json"):
		_backup = FileAccess.get_file_as_string("user://save.json")
	_profile_backup = Save.profile.duplicate(true)
	if Save._timer and Save._timer.timeout.is_connected(Save.flush):
		Save._timer.timeout.disconnect(Save.flush)
	MatchStore.enabled = false
	Save.prefs.welcome_seen = true
	Save.prefs.tutorial_done = true
	Save.prefs.erase("net_room")
	Save.prefs.speed = 0.55
	Save.prefs.cam = "3d"
	Save.prefs.home_game = "ludo"
	Save.profile.name = "Sajib"
	Save.profile.coins = 2450
	var today := Time.get_date_string_from_system()
	Save.profile.daily = {cycle = 0, streak = 3, last = Rewards.add_days(today, -1), history = []}
	Rewards.daily_data(Save.profile).auto_on = today
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _until(func(): return main.screen == "home", 60)
	await _sleep(2.0)
	main.close_all_sheets()
	main.home.refresh()
	await _sleep(1.0)
	await shot("home")
	main._on_tab("daily")
	await _sleep(1.2)
	await shot("daily_rewards")
	main.close_all_sheets()
	await _sleep(0.6)
	main.start_ludo({game = "ludo", players = ["human", "cpu", "cpu", "cpu"], teams = false, bot_level = "normal"})
	var L: LudoMatch = main.ludo
	await _until(func(): return not L.S.is_empty() and L.S.phase == "roll" and not L._busy and L.S.turn == 0, 20)
	await _sleep(1.0)
	var tok := [[12, 27, -1, -1], [5, 20, 38, -1], [33, 9, -1, -1], [22, 41, 3, -1]]
	for c in 4:
		L.S.tok[c] = (tok[c] as Array).duplicate()
	L.S.pairs = []
	L.S.turn = 0
	L.S.phase = "roll"
	L.S.sixes = 0
	L.board.relayout(L.S)
	L.hud.update(L.S, 0)
	L._busy = false
	await _sleep(1.5)
	await shot("ludo_mid")
	main.hud.emote_picker.open()
	await _sleep(0.7)
	main.hud.emote_picker.pick("happy")
	await _sleep(0.3)
	main.hud.emotes.show_emote(1, "laugh")
	main.hud.emotes.show_emote(2, "crown")
	await _sleep(0.7)
	await shot("ludo_emotes")
	main.go_home()
	await _sleep(0.8)
	_restore()
	get_tree().quit()

func _process(_d: float) -> void:
	Save._dirty = false

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	n += 1
	get_viewport().get_texture().get_image().save_png("%s/%02d_%s.png" % [out, n, name])
	print("shot ", name)

func _restore() -> void:
	Save._dirty = false
	Save.profile.clear()
	Save.profile.merge(_profile_backup, true)
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
