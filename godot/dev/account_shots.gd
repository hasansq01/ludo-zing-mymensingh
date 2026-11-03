extends Node
## Dev: screenshots of the account UI at 390x844 (Home Ranks button, Profile Account section in its states, the
## Google conflict dialogs, the Leaderboard in every state, the offline "Connect to claim" messages, the result
## screen's claim note). A fake server (tests/fake_accounts.gd) answers; Save is a throwaway (the debounced write is
## unhooked and the real save is restored at the end).
##   godot --path godot --resolution 390x844 res://dev/account_shots.tscn -- <out_dir>

const Fake := preload("res://tests/fake_accounts.gd")

var out := "/tmp"
var main: Node
var n := 0
var f: Fake
var acc: Account
var pg: Fake.FakePG
var _backup := ""

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size():
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	if FileAccess.file_exists("user://save.json"):
		_backup = FileAccess.get_file_as_string("user://save.json")
	if Save._timer and Save._timer.timeout.is_connected(Save.flush):
		Save._timer.timeout.disconnect(Save.flush)
	Save.prefs.welcome_seen = true
	Save.prefs.tutorial_done = true
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _until(func(): return main.screen == "home", 60)
	await _sleep(1.5)
	main.close_all_sheets()
	# the fake server and an Account that talks to it
	f = Fake.new()
	f.profile.name = "Shihab"
	f.profile.xp = 740
	f.profile.coins = 8450
	f.profile.stats.wins = 12
	f.profile.stats.played = 20
	f.account.completed_matches = 1
	acc = main.account
	acc.enabled = true
	acc.http_fn = f.http
	pg = Fake.FakePG.new()
	acc.pg_factory = func(): return pg
	acc._pg = null
	await acc.sign_in_guest()
	main.home.refresh()
	await _sleep(0.6)

	await shot("home_ranks_button")

	# ---- profile: the Account section ----
	main._on_tab("profile")
	await _sleep(0.9)
	var ps: ProfileSheet = main._top_sheet()
	ps.scroll_box.ensure_control_visible(ps._acct_box)
	await _sleep(0.3)
	await shot("profile_account_guest")
	ps.scroll_box.scroll_vertical = 0
	await _sleep(0.2)
	await shot("profile_top_leaderboard_button")
	ps.scroll_box.ensure_control_visible(ps._acct_box)
	ps._acct_button.pressed.emit()
	await _sleep(0.8)
	await shot("profile_account_linked")
	# offline: no session
	f.online = false
	acc._session = ""
	acc.account.guest = true
	acc.account_changed.emit()
	await _sleep(0.4)
	await shot("profile_account_offline")
	await close_top()

	# ---- the conflict dialogs (raised by a sign-in) ----
	f.online = true
	await acc.sign_in_guest()
	acc.account.guest = true
	var here := {name = "Shihab", avatar = "pawn-red", level = 3, coins = 8450, wins = 12}
	var there := {name = "Mimi", avatar = "ch-mim", level = 14, coins = 52300, wins = 88}
	f.google_status = 409
	f.google_body = {error = "conflict", conflict = {here = here, there = there}, ticket = "T1"}
	acc.link_google()
	await _sleep(1.0)
	await shot("conflict_this_device_vs_google")
	var cs: ConflictSheet = main._top_sheet() as ConflictSheet
	if cs:
		cs.scroll_box.scroll_vertical = 9999
		await _sleep(0.3)
		await shot("conflict_scrolled")
	await close_top()
	acc.conflict = {}
	f.google_body = {error = "other_google", conflict = {here = here, there = null}, ticket = "T2"}
	acc.link_google()
	await _sleep(1.0)
	await shot("conflict_other_google_new_account")
	await close_top()
	acc.conflict = {}

	# ---- the leaderboard ----
	var names := ["Mimi", "Rafi", "Tanvir", "Nusrat", "Sabbir", "Anika", "Farhan", "Lamia", "Rahim", "Tisha", "Imran", "Sadia"]
	var avs := ["ch-mim", "ch-rafi", "ch-tanvir", "pawn-green", "pawn-blue", "pawn-red", "pawn-yellow", "ch-mim", "pawn-green", "pawn-blue", "pawn-red", "pawn-yellow"]
	var top := []
	for k in 12:
		top.append({rank = k + 1, name = names[k], avatar = avs[k], frame = "classic", level = 22 - k, value = 21400 - k * 1650})
	f.board = {top = top, me = {rank = 14, value = 3740, listed = true}, min_matches = 3}
	main._on_tab("leaderboard")
	await _sleep(1.2)
	await shot("leaderboard_level_weekly")
	var lb: LeaderboardSheet = main._top_sheet() as LeaderboardSheet
	f.board = {top = top.slice(0, 8), me = {rank = 0, value = 0, listed = false}, min_matches = 3}
	lb.select("wins", "all")
	await _sleep(0.8)
	await shot("leaderboard_wins_alltime_not_listed")
	f.board = {top = [], me = null, min_matches = 3}
	lb._cache.clear()
	lb.select("xp", "all")
	await _sleep(0.6)
	await shot("leaderboard_empty")
	f.online = false
	lb._cache.clear()
	lb.load_board(true)
	await _sleep(0.6)
	await shot("leaderboard_offline")
	lb.fetch_fn = func(_b: String, _p: String) -> Dictionary:
		await get_tree().create_timer(3.0).timeout
		return {ok = false, error = "offline"}
	lb._cache.clear()
	lb.load_board(true)
	await _sleep(0.5)
	await shot("leaderboard_loading")
	await close_top()
	f.online = true

	# ---- offline messages ----
	f.online = false
	acc._session = ""
	main._on_tab("daily")
	await _sleep(0.9)
	var ds: DailySheet = main._top_sheet() as DailySheet
	if ds:
		ds._claim()
		await _sleep(0.7)
		await shot("offline_daily_claim")
	await close_top()
	main._on_tab("spin")
	await _sleep(0.9)
	var ss: SpinSheet = main._top_sheet() as SpinSheet
	if ss:
		ss._spin()
		await _sleep(0.7)
		await shot("offline_spin")
	await close_top()
	main._on_tab("shop")
	await _sleep(1.0)
	var sh: ShopSheet = main._top_sheet() as ShopSheet
	if sh:
		sh._on_buy("room", "dream", "Dream")
		await _sleep(0.7)
		await shot("offline_shop_buy")
	await close_top()
	main._on_tab("free")
	await _sleep(0.7)
	await shot("offline_free_coins")
	await _sleep(2.0)
	# ---- the result screen's claim note ----
	f.online = true
	main._on_finished({title = "You win!", reward = 200, human_won = true, vs_cpu = true,
		standings = [{color = 0, name = "You", kind = "you", place = 1, finished = 4, progress = 1.0}, {color = 1, name = "Mocha", kind = "cpu", cpu_id = "mocha", place = 2, finished = 1, progress = 0.5}]}, "ludo")
	await _sleep(4.5)
	var rs := main._result as ResultScreen
	if rs:
		rs.set_claim_note("Daily limit reached")
		await _sleep(0.6)
		await shot("result_daily_limit_note")
	_restore()
	get_tree().quit()

func close_top() -> void:
	main.close_all_sheets()
	Info.close()
	await _sleep(0.4)

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	n += 1
	get_viewport().get_texture().get_image().save_png("%s/%02d_%s.png" % [out, n, name])
	print("shot ", name)

func _restore() -> void:
	Save._dirty = false
	if _backup != "":
		var fh := FileAccess.open("user://save.json", FileAccess.WRITE)
		fh.store_string(_backup)
		fh.close()
		Save.load_data()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_restore()

func _sleep(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _until(cond: Callable, timeout: float) -> void:
	var t0 := Time.get_ticks_msec()
	while not cond.call() and (Time.get_ticks_msec() - t0) / 1000.0 < timeout:
		await get_tree().process_frame
