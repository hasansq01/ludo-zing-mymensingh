extends Node
## Dev: the real HomeScreen ("One big Play") inside main.tscn in its states, with PASS / FAIL checks of its buttons.
##   godot --path . --resolution 390x844 res://dev/home_variants_real.tscn -- <out_dir> <tag> [safe_top] [safe_bottom] --offline
## Shots: <out>/home_<state>_<tag>.png for
##   plain     nothing to claim (no count on the gift)
##   gift      Free spin + Free coins ready (the gift's count: 2)
##   continue  a kept match (the Continue match pill) and one reward ready
##   snakes    Snakes & Ladders picked (its scene is the backdrop)
##   rewards   the Rewards sheet open (spin ready, daily claimed, free coins counting down)
## Checks: QUICK MATCH / Friends / Computer / Pass & Play / Continue / the nav (Ranks too) / the gift, the Rewards
## sheet's rows (claiming the free coins drops the count), the Shop and Inventory opening on Scenes for S&L.
## Never writes user://save.json or user://match.json: Save's debounced flush is unhooked and Save._dirty is kept
## false (like dev/back_check.gd); MatchStore reads a match file in <out_dir> and never writes.

var out := "/tmp"
var tag := "390"
var main: Node
var fails := 0
var _log: Array = []


func _ready() -> void:
	if Save._timer and Save._timer.timeout.is_connected(Save.flush):
		Save._timer.timeout.disconnect(Save.flush)        # dev run: nothing reaches user://save.json
	var a := Array(OS.get_cmdline_user_args()).filter(func(s: String) -> bool: return not s.begins_with("--"))
	if a.size() > 0: out = a[0]
	if a.size() > 1: tag = a[1]
	DirAccess.make_dir_recursive_absolute(out)
	MatchStore.enabled = false                 # games started by the checks don't write a match file
	MatchStore.path = out.path_join("dev_match.json")
	if FileAccess.file_exists(MatchStore.path):
		DirAccess.remove_absolute(MatchStore.path)
	Save.prefs.welcome_seen = true
	Save.prefs.tutorial_done = true
	Save.prefs.notif = false                   # (no soft prompt over the shots)
	Save.prefs.erase("last_played")
	Save.prefs.home_game = "ludo"
	Save.profile.room = Rooms.DEFAULT
	Rewards.daily_data(Save.profile).auto_on = Time.get_date_string_from_system()   # no daily sheet popping up
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _until(func(): return main.screen in ["home", "welcome"], 120)   # (a cold shader cache: slow)
	await _sleep(0.8)
	for c in main.screens.get_children():
		if c is Welcome:
			c.continued.emit()
	await _until(func(): return main.screen == "home", 10)
	await _sleep(1.0)
	main.close_all_sheets()
	if a.size() > 2:
		main.safe_top = float(a[2])
		main.safe_bottom = float(a[3]) if a.size() > 3 else 0.0
		main.home.safe_top = main.safe_top
		main.home.safe_bottom = main.safe_bottom
	var home: HomeScreen = main.home
	Save.profile.name = "Shihab"
	Save.profile.coins = 5300
	Save.profile.xp = 260
	for sig in ["play", "play_game", "quick_match", "play_friends", "continue_match", "game_switched", "open_tab"]:
		home.connect(sig, func(x = null, y = null): _log.append([sig, x, y]))

	_rewards(false, false, false)
	await _state("plain")
	_ok("plain: no count on the gift", not home._gift_badge.visible)
	_rewards(true, false, true)
	await _state("gift")
	_ok("gift: the count is 2", home._gift_badge.visible and home._gift_badge.text == "2", home._gift_badge.text)
	_rewards(false, false, true)
	var f := FileAccess.open(MatchStore.path, FileAccess.WRITE)
	f.store_string(JSON.stringify({v = 1, game = "ludo", summary = "Ludo vs Computer · 35%", saved_at = int(Time.get_unix_time_from_system()) - 720, state = {x = 1}}))
	f.close()
	await _state("continue")
	_ok("continue: the pill shows, the count is 1", home._quick.visible and home._gift_badge.text == "1")
	_ok("continue: the pill sits between the logo and the dock", home._quick.position.y > home.logo.position.y + home.logo.size.y
		and home._quick.position.y + home._quick.size.y <= home._dock.position.y, [home._quick.position, home._dock.position])
	_log.clear()
	home._quick.pressed.emit()
	await _sleep(0.6)
	_ok("continue: the pill resumes", _log.has(["continue_match", null, null]), _log)
	main.go_home()
	DirAccess.remove_absolute(MatchStore.path)
	home.refresh()
	_ok("continue: gone with the match", not home._quick.visible)
	home.select_game("sl")
	await _until(func(): return main.sl_scenes.visible, 20)
	await _state("snakes", false)
	_ok("snakes: the S&L scene is the backdrop", main.sl_scenes.visible and not main.world.visible)
	await _shop_checks(home)
	home.select_game("ludo")
	await _sleep(0.8)
	await _mode_checks(home)
	await _rewards_sheet(home)
	print("HOME CHECK: %s (%d failed)" % ["PASS" if fails == 0 else "FAIL", fails])
	main.close_all_sheets()
	Save._dirty = false
	get_tree().quit(1 if fails else 0)


func _process(_d: float) -> void:
	Save._dirty = false


## Rewards ready now: spin, daily, free (in memory only).
func _rewards(spin: bool, daily: bool, free: bool) -> void:
	var p: Dictionary = Save.profile
	var today := Rewards.day_key()
	p.last_spin = "" if spin else today
	var d := Rewards.daily_data(p)
	d.last = Rewards.add_days(today, -1) if daily else today
	d.streak = 2 if daily else 3
	p.last_free = 0 if free else int(Time.get_unix_time_from_system()) - (Rewards.FREE_EVERY_SEC - 13990)
	main.home.refresh()


func _state(name: String, reset := true) -> void:
	if reset:
		main.close_all_sheets()
		main.go_home()
	main.home.refresh()
	main._fit_home()
	await _sleep(0.2)
	_frame_cam()
	await _sleep(1.4)
	main.close_all_sheets()
	await _shot(name)


func _frame_cam() -> void:
	var w = main.world
	w.orbit = false
	w.cam_target_az = TableWorld.seat_az(0) + 0.35
	w.cam_az = w.cam_target_az
	w.cam_zoom = w.cam_target_zoom
	w.cam_el = w.cam_target_el
	w.view_y = w.view_target_y


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "%s/home_%s_%s.png" % [out, name, tag]
	get_viewport().get_texture().get_image().save_png(path)
	print("shot ", path)


## Snakes & Ladders picked: the Shop and the Inventory open on Scenes (where "Change scene" went).
func _shop_checks(home: HomeScreen) -> void:
	for t in ["Shop", "Inventory"]:
		main.close_all_sheets()
		(home._tabs.get_node(t) as Button).pressed.emit()
		await _sleep(0.5)
		var s: Variant = main._top_sheet()
		_ok("snakes: %s opens on Scenes" % t, s is ShopSheet and (s as ShopSheet).tab == "scenes", (s as ShopSheet).tab if s is ShopSheet else s)
	main.close_all_sheets()


func _mode_checks(home: HomeScreen) -> void:
	main.close_all_sheets()
	_log.clear()
	home.quick_button.pressed.emit()
	home.friends_button.pressed.emit()
	(home._modes.get_node("Computer") as Button).pressed.emit()
	main.close_all_sheets()
	(home._modes.get_node("PassPlay") as Button).pressed.emit()
	main.close_all_sheets()
	(home._tabs.get_node("Ranks") as Button).pressed.emit()
	await _sleep(0.4)
	_ok("Ranks opens the leaderboard", main._top_sheet() is LeaderboardSheet, main._top_sheet())
	main.close_all_sheets()
	home.rewards_button.pressed.emit()
	await _sleep(0.4)
	_ok("the gift opens the Rewards sheet", main._top_sheet() is RewardsSheet, main._top_sheet())
	main.close_all_sheets()
	var want := [["quick_match", "ludo", null], ["play_friends", "ludo", null], ["play_game", "ludo", "cpu"],
		["play_game", "ludo", "local"], ["open_tab", "leaderboard", null], ["open_tab", "rewards", null]]
	_ok("buttons: quick, friends, computer, pass & play, ranks, gift", _log == want, _log)
	await _sleep(0.4)


## The Rewards sheet: its shot, then the free coins claimed from it (the count drops, coins land).
func _rewards_sheet(home: HomeScreen) -> void:
	_rewards(true, false, false)
	main.close_all_sheets()
	main.go_home()
	_frame_cam()
	await _sleep(1.0)
	home.rewards_button.pressed.emit()
	await _sleep(0.8)
	var s: RewardsSheet = main._top_sheet()
	await _shot("rewards")
	_ok("rewards: spin ready, daily and free counting down", (s.row("spin") as RewardsSheet.Row).go.visible
		and (s.row("daily") as RewardsSheet.Row).wait.visible and (s.row("free") as RewardsSheet.Row).wait_label.text.contains(":"))
	var coins := int(Save.profile.coins)
	(s.row("free") as Button).pressed.emit()                # not ready: says when (toast), nothing granted
	await _sleep(0.4)
	_ok("rewards: free coins not ready grants nothing", int(Save.profile.coins) == coins)
	Save.profile.last_free = 0
	await _sleep(1.2)
	_ok("rewards: free coins ready, the count is 2", home._gift_badge.text == "2" and (s.row("free") as RewardsSheet.Row).go.visible)
	(s.row("free") as Button).pressed.emit()
	await _sleep(0.3)
	await _shot("rewards_claimed")
	await _sleep(2.0)
	_ok("rewards: claimed: +%d coins, the count is 1" % Rewards.FREE_AMOUNT, int(Save.profile.coins) == coins + Rewards.FREE_AMOUNT
		and home._gift_badge.text == "1" and (s.row("free") as RewardsSheet.Row).wait.visible, [Save.profile.coins, home._gift_badge.text])
	(s.row("spin") as Button).pressed.emit()
	await _sleep(0.6)
	_ok("rewards: Spin opens the spin sheet over it", main._top_sheet() is SpinSheet, main._top_sheet())
	main.close_all_sheets()


func _ok(what: String, ok: bool, info: Variant = null) -> void:
	print(("PASS " if ok else "FAIL ") + what + ("" if ok or info == null else "  " + str(info)))
	if not ok:
		fails += 1


func _sleep(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _until(f: Callable, timeout: float) -> void:
	var t0 := Time.get_ticks_msec()
	while not f.call() and (Time.get_ticks_msec() - t0) / 1000.0 < timeout:
		await get_tree().process_frame
