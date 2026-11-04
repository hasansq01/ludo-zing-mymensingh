extends Node
## Dev: a screenshot tour of every screen and state of the app, for UI/UX audits.
## godot --path . --resolution 390x844 res://dev/tour.tscn -- <out_dir> [--lobby]
## --lobby: only the lobby states (Home: Ludo / Snakes & Ladders, the free-coins toast, Play again / Continue match,
## the setup sheets with Pass & Play names, the daily calendar, Settings' lower half): a quick pass for 320 px checks.
## Runs on a throwaway profile: the save is never written while the tour runs (the debounced flush is unhooked), and
## the real save is backed up first and restored at the end anyway.

var out := "/tmp"
var main: Node
var n := 0
var lobby_only := false
var _backup := ""

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size():
		out = args[0]
	lobby_only = args.has("--lobby")
	if FileAccess.file_exists("user://save.json"):
		_backup = FileAccess.get_file_as_string("user://save.json")
	if Save._timer and Save._timer.timeout.is_connected(Save.flush):
		Save._timer.timeout.disconnect(Save.flush)      # dev run: nothing reaches user://save.json
	Save.prefs.welcome_seen = false          # the tour starts with the first-run welcome
	Save.prefs.tutorial_done = true          # setup sheets, not the guided first match (dev/tutorial_preview shoots that)
	Save.profile.name = "You"
	Rewards.daily_data(Save.profile).auto_on = ""    # the daily reward may open by itself today (after the first game)
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _until(func(): return main.screen == "splash" and main._splash != null, 10)
	await _sleep(0.6)
	await shot("splash_loading")
	await _until(func(): return main.screen in ["home", "welcome"], 40)
	await _sleep(1.4)
	await shot("welcome")
	for c in main.screens.get_children():
		if c is Welcome:
			c.name_edit.text = "Shihab"
			c._pick(Welcome.free_avatars()[1])
			await _sleep(0.5)
			await shot("welcome_filled")
			c.play_button.pressed.emit()
	await _until(func(): return main.screen == "home", 10)
	await _sleep(2.2)
	await shot("home_first_run_no_daily")
	await close_top()
	if lobby_only:
		await _lobby_states()
		_restore()
		get_tree().quit()
		return
	# ---- lobby sheets ----
	await sheet_shot(func(): main._on_tab("daily"), "daily_reward")
	await sheet_shot(func(): main._on_tab("spin"), "daily_spin")
	main._on_tab("free")
	await _sleep(0.5)
	await shot("free_coins_toast")
	await _sleep(2.2)
	await sheet_shot(func(): main._on_tab("profile"), "profile")
	main._on_tab("profile")
	await _sleep(0.8)
	var ps: Sheet = main._top_sheet()
	if ps and ps.get("_tabs"):
		ps._tabs.tap("ach")                   # TabStrip.tap redraws the highlight and emits picked
		await _sleep(0.5)
		await shot("profile_achievements")
	await close_top()
	# the one Shop (decision 4): every tab, then the "Owned" filter (the old Inventory / Collection)
	for t in ["rooms", "scenes", "dice", "avatars", "frames", "plates", "badges", "coins"]:
		await sheet_shot(func(): _open_shop(t), "shop_" + t)
	for t in ["rooms", "avatars", "frames"]:
		await sheet_shot(func(): _open_shop(t, true), "shop_owned_" + t)
	_open_shop("rooms")
	await _sleep(0.7)
	var sh: Sheet = main._top_sheet()
	if sh and sh.get("_tabs"):
		sh._tabs.tap("plates")
		await _sleep(0.5)
		await shot("shop_tab_tap_plates")
	await close_top()
	await sheet_shot(func(): PreviewSheet.new("dream").open(main.sheet_layer), "shop_preview_dream", 3.0)
	await sheet_shot(func(): main.open_settings(), "settings")
	await sheet_shot(func(): HowToSheet.new().open(main.sheet_layer), "how_to_play")
	await sheet_shot(func(): main._confirm_quit(), "quit_confirm")
	await sheet_shot(func(): main._on_tab("inventory"), "shop_owned")
	# ---- Ludo setup ----
	await sheet_shot(func(): main._open_setup("ludo", "cpu"), "setup_vs_computer")
	var setup: Sheet = await _top_after(func(): main._open_setup("ludo", "cpu"), 0.7)
	for b in setup.find_children("*", "Button", true, false) if setup else []:
		if b.text == "Teams (2 v 2)":
			b.button_pressed = true
	await _sleep(0.4)
	await shot("setup_vs_computer_teams")
	Info.open_key("team")
	await _sleep(0.5)
	await shot("info_bubble_team")
	Info.close()
	await close_top()
	await sheet_shot(func(): main._open_setup("ludo", "local"), "setup_pass_and_play")
	# ---- Ludo game ----
	main.speed = 0.5
	main.start_ludo({game = "ludo", players = ["human", "cpu", "cpu", "cpu"], teams = false})
	await _sleep(2.0)
	await shot("ludo_start")
	main.ludo.roll(6)
	await _sleep(2.4)
	await shot("ludo_choose_glowing")
	# a mid-game board: pawns spread around, a pair, a pawn home
	var S: Dictionary = main.ludo.S
	S.tok = [[12, 12, 30, 56], [5, 40, -1, -1], [20, 51, -1, 56], [8, 25, 44, -1]]
	S.pairs = [{c = 0, a = 0, b = 1}]
	S.turn = 0
	S.phase = "roll"
	main.world.board.relayout(S)
	main.hud.update(S, 0)
	await _sleep(1.2)
	await shot("ludo_midgame")
	# decision 3: no Single / Pair step; the pair and the singles all glow, the tap decides
	main.ludo.roll(4)
	await _sleep(2.0)
	await shot("ludo_pair_and_singles_glow")
	main.ludo.move(0)                         # pawn 0 is paired: the pair moves
	await _sleep(1.6)
	await shot("ludo_after_pair_move")
	await _sleep(1.4)
	# house rule "Ask before pairing": the inline prompt
	main.ludo.stop()                          # freezes the match (its turns stop)
	S.turn = 0                                # the prompt only shows on your own turn
	S.phase = "choose"
	S.dice = 2
	main.ludo.S = S
	main.ludo.app = main
	main.world.board.relayout(S)
	main.hud.update(S, 0)
	main.ludo._idle_line()
	main.ludo._ask_pair.call_deferred()
	await _sleep(0.9)
	await shot("ludo_pair_prompt")
	if main.hud.has_method("cancel_pair"):
		main.hud.cancel_pair()
	await close_top()
	main.start_ludo({game = "ludo", players = ["human", "cpu", "cpu", "cpu"], teams = false})
	await _sleep(1.5)
	main.open_pause()
	await _sleep(0.6)
	await shot("pause")
	main._ask_restart()
	await _sleep(0.6)
	await shot("pause_restart_confirm")
	main._back()
	await _sleep(0.4)
	main._ask_exit()
	await _sleep(0.6)
	await shot("pause_exit_confirm")
	await close_top()
	Save.prefs.cam = "top"
	main._on_prefs_changed()
	await _sleep(2.0)
	await shot("ludo_top_view")
	Save.prefs.cam = "3d"
	main._on_prefs_changed()
	main.start_ludo({game = "ludo", players = ["human", "cpu", "cpu", "cpu"], teams = true})
	await _sleep(2.5)
	await shot("ludo_teams_start")
	main.ludo._id += 1                       # freeze the match (its turns stop) but keep its state
	var TS: Dictionary = main.ludo.S
	TS.tok = [[56, 56, 56, 56], [56, 56, 40, 30], [56, 56, 56, 56], [20, 10, -1, 56]]
	TS.winner = 0
	Save.profile.xp = int(Save.profile.xp) + 100
	main._xp_start = int(Save.profile.xp) - 100
	main._on_finished({title = "Your team wins!", reward = 200, human_won = true}, "ludo")
	await _sleep(3.2)
	await shot("ludo_team_win_result")
	await close_top()
	main.start_ludo({game = "ludo", players = ["human", "cpu", "cpu", "cpu"], teams = false})
	await _sleep(1.0)
	main.ludo._id += 1
	var LS: Dictionary = main.ludo.S
	LS.tok = [[56, 30, 12, -1], [56, 56, 56, 56], [44, 50, 20, 8], [5, -1, -1, -1]]
	LS.winner = 1
	LS.finished = [1]
	Save.profile.xp = int(Save.profile.xp) + 40
	main._xp_start = int(Save.profile.xp) - 40
	main._on_finished({title = "", reward = 0, human_won = false}, "ludo")
	await _sleep(3.0)
	await shot("ludo_lose_result")
	await close_top()
	# ---- Snakes & Ladders: picked on Home's switch (the backdrop is the equipped scene; no separate landing) ----
	main.go_home()
	main.home.select_game("sl")
	await _sleep(3.5)
	await shot("home_sl_selected")
	await sheet_shot(func(): main._open_setup("sl", "cpu"), "sl_setup_vs_computer")
	main.start_sl({game = "sl", mode = "cpu", n = 4, color = 0})
	await _sleep(3.0)
	await shot("sl_start")
	for k in 8:
		if main.sl.G.players[main.sl.G.turn].you and main.sl.G.phase == "roll":
			main.sl.roll()
		await _sleep(1.2)
	await shot("sl_midgame")
	Save.prefs.sl_cam = "top"
	main._on_prefs_changed()
	await _sleep(2.0)
	await shot("sl_top_view")
	Save.prefs.sl_cam = "3d"
	main._on_prefs_changed()
	main.sl._id += 1
	var G: Dictionary = main.sl.G
	G.players[0].pos = 100
	G.winner = 0
	G.phase = "over"
	Save.profile.xp = int(Save.profile.xp) + 300
	main._xp_start = int(Save.profile.xp) - 300           # crosses a level: "Level up!"
	main._on_finished({title = "You win!", reward = 100, human_won = true, vs_cpu = true}, "sl")
	await _sleep(3.4)
	await shot("sl_win_result")
	await close_top()
	main.go_home()
	await _sleep(0.9)
	await shot("home_after_games_coins_fly")
	await _sleep(1.6)
	await shot("home_after_first_game_daily")
	await close_top()
	await _lobby_states()
	_restore()
	get_tree().quit()

## The lobby states the re-audit asked to re-shoot: Home (Ludo / S&L), the free-coins toast, Pass & Play names, the
## Play again and Continue match slots (a match started through Setup), Settings' lower half, the daily calendar.
func _lobby_states() -> void:
	main.go_home()
	main.home.select_game("ludo")
	await _sleep(1.0)
	await shot("lobby_home_ludo")
	Rewards.claim_free(Save.profile)                  # the free coins cool down: a tap says when (toast over the tiles)
	main.home.refresh()
	await _sleep(0.4)
	main._on_tab("free")
	await _sleep(0.45)
	await shot("lobby_free_cooldown_toast")
	await _sleep(2.2)
	main.home.select_game("sl")
	await _sleep(3.5)
	await shot("lobby_home_sl")
	await sheet_shot(func(): main._on_tab("scenes"), "lobby_change_scene_shop")
	await sheet_shot(func(): main._on_tab("daily"), "lobby_daily")
	# Pass & Play setup with names (S&L picked: the S&L setup)
	main._open_setup("sl", "local")
	await _sleep(0.8)
	await shot("lobby_setup_sl_pass_play")
	await close_top()
	main.home.select_game("ludo")
	await _sleep(0.6)
	var su: Sheet = await _top_after(func(): main._open_setup("ludo", "local"), 0.8)
	for b in su.find_children("*", "Button", true, false) if su else []:
		if b.text == "3":
			b.button_pressed = true
	for e: LineEdit in su.find_children("Name*", "LineEdit", true, false) if su else []:
		if e.name == "Name2":
			e.text = "Rafi"
			e.text_changed.emit("Rafi")
	await _sleep(0.4)
	await shot("lobby_setup_ludo_pass_play_names")
	# Start it from the sheet (a real setup: last_setup + last_played are kept), then back Home: "Play again"
	if is_instance_valid(su) and su.has_method("_submit"):
		su.call("_submit")
	await _sleep(2.0)
	print("names in the match: ", main.last_ludo.get("names", []))
	await shot("lobby_ludo_pass_play_match")
	Rewards.mark_auto_open(Save.profile)              # (the daily calendar would open itself after this first game)
	main.go_home()
	await _sleep(1.4)
	await close_top()
	await shot("lobby_home_play_again")
	# a match left for later (Pause -> Exit to home): "Continue match"
	main._open_setup("ludo", "cpu")
	await _sleep(0.8)
	await shot("lobby_setup_ludo_cpu")
	# the setup may have been dismissed meanwhile (a click on the window's dim backdrop, Escape): open it again
	var sc: Sheet = main._top_sheet()
	if not (sc and sc.has_method("_submit")):
		sc = await _top_after(func(): main._open_setup("ludo", "cpu"), 0.5)
	if sc and sc.has_method("_submit"):
		sc.call("_submit")
	else:
		push_warning("tour: no setup sheet to start the Continue-match game from")
	await _sleep(2.0)
	main._flush_match()
	var kept: Dictionary = MatchStore.load()
	var summary := str(MatchStore.peek().get("summary", ""))
	main.go_home()
	if not kept.is_empty():
		MatchStore.save("ludo", kept, summary)
	main.home.refresh()
	await _sleep(1.4)
	await shot("lobby_home_continue")
	MatchStore.clear()
	main.home.refresh()
	# Settings, scrolled to the end
	main.open_settings()
	await _sleep(0.9)
	var st: Sheet = main._top_sheet()
	if st and st.scroll_box:
		st.scroll_box.scroll_vertical = 100000
	await _sleep(0.5)
	await shot("lobby_settings_lower")
	await close_top()

func _open_shop(t: String, owned := false) -> void:
	var s = ShopSheet.new(t, float(UIKit.W.catalog), owned)
	if main.has_method("apply_shop_changes"):
		main.apply_shop_changes(s)
	else:
		main._wire_shop(s)
	s.open(main.sheet_layer)

## Opens a sheet and returns the top sheet `wait` s later; when it was dismissed meanwhile (a stray click on the
## tour's window lands on the dim backdrop, Escape), it is closed and opened once more. Null if it still isn't there.
func _top_after(open: Callable, wait: float) -> Sheet:
	for attempt in 2:
		open.call()
		await _sleep(wait)
		var s: Sheet = main._top_sheet()
		if s:
			return s
		push_warning("tour: the sheet was dismissed before its shot; opening it again")
		main.close_all_sheets()
	return null

func sheet_shot(open: Callable, name: String, wait := 0.9) -> void:
	open.call()
	await _sleep(wait)
	await shot(name)
	await close_top()

func close_top() -> void:
	main.close_all_sheets()
	Info.close()
	await _sleep(0.35)

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
		Save.load_data()          # the in-memory profile matches the file again, so a late flush rewrites the same data

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_restore()

func _sleep(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _until(f: Callable, timeout: float) -> void:
	var t0 := Time.get_ticks_msec()
	while not f.call() and (Time.get_ticks_msec() - t0) / 1000.0 < timeout:
		await get_tree().process_frame
