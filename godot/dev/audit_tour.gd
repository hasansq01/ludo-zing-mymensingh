extends Node
## Dev: the UI/UX audit tour. Screenshots of every sheet (scripts/ui/sheets/*), every nested path a player can reach
## (Profile -> Leaderboard / Inventory, Shop -> Preview / Emote pack / Store, Rewards -> Spin / Daily, Settings ->
## How to play / Credits, Pause -> Settings, Home -> Quick match -> its states, Friends -> Lobby), the match HUDs
## (Ludo and Snakes & Ladders: top bar, player tiles, emote picker, Roll again), toasts, the result screens, Home,
## the Snakes & Ladders landing, the welcome and splash screens. Used for before / after comparisons.
##   godot --path . --resolution 360x780 res://dev/audit_tour.tscn -- <out_dir> [--safe=38,16] [--only=a,b]
## --logical=320x568 lays the UI out at that logical size (the project's stretch base is 390x844 with aspect expand,
## so a narrow window alone still lays out at >= 390 px). Use it with a --resolution of the same size to see the
## narrow (< 340 px) layouts, e.g. --resolution 320x568 ... -- out --logical=320x568.
## Sections (--only takes these names): boot home rewards profile shop store settings misc setup online ludo sl
## Online sheets run against the in-process fake server (NetFake.Hub, as dev/econ_shots.gd): no network.
## Never writes the real save: Save's debounced flush is unhooked, and the file is backed up and restored at the end.

var out := "/tmp/audit"
var main: Node
var n := 0
var _backup := ""
var hub: NetFake.Hub
var only: PackedStringArray = []
var coins := 5000
var level := 7

const SECTIONS := ["boot", "home", "rewards", "profile", "shop", "store", "settings", "misc", "setup", "online", "ludo", "sl"]


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() and not args[0].begins_with("--"):
		out = args[0]
	for a in args:
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=").split(",")
		if a.begins_with("--logical="):                 # lay the UI out at this logical size (see the header)
			var wh := a.trim_prefix("--logical=").split("x")
			if wh.size() == 2:
				var root := get_tree().root
				root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
				root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
				root.content_scale_size = Vector2i(int(wh[0]), int(wh[1]))
	DirAccess.make_dir_recursive_absolute(out)
	if FileAccess.file_exists("user://save.json"):
		_backup = FileAccess.get_file_as_string("user://save.json")
	if Save._timer and Save._timer.timeout.is_connected(Save.flush):
		Save._timer.timeout.disconnect(Save.flush)      # dev run: nothing reaches user://save.json
	var boot := _on("boot")
	Save.prefs.welcome_seen = not boot
	Save.prefs.tutorial_done = true
	Save.prefs.erase("net_room")
	Save.prefs.home_game = "ludo"
	Save.prefs.quick_players = 2
	Save.prefs.quick_table = "practice"
	Save.profile.name = "Shihab"
	Save.profile.coins = 4800
	Save.profile.xp = maxi(int(Save.profile.get("xp", 0)), 1400)
	Rewards.daily_data(Save.profile).auto_on = Time.get_date_string_from_system()   # no daily sheet popping up
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	if boot:
		await _until(func(): return main.screen == "splash" and main._splash != null, 10)
		await _sleep(0.6)
		await shot("splash")
		await _until(func(): return main.screen in ["home", "welcome"], 60)
		await _sleep(1.4)
		await shot("welcome")
		for c in main.screens.get_children():
			if c is Welcome:
				c.name_edit.text = "Shihab"
				c._pick(Welcome.free_avatars()[1])
				await _sleep(0.5)
				await shot("welcome_filled")
				c.play_button.pressed.emit()
	await _until(func(): return main.screen == "home", 60)
	await _sleep(1.6)
	main.close_all_sheets()
	_fake_net()
	for s in SECTIONS:
		if s != "boot" and _on(s):
			print("== section ", s)
			await call("_s_" + s)
			main.close_all_sheets()
			Info.close()
			if main.screen != "home":
				main.go_home()
				await _sleep(1.2)
	_restore()
	get_tree().quit()

func _on(s: String) -> bool:
	return only.is_empty() or only.has(s)

func _fake_net() -> void:
	hub = NetFake.Hub.new(5)
	var net: NetClient = main.online.net
	net.url_base = "ws://fake"
	net.make_transport = hub.transport_factory()
	net.http_fn = hub.http
	net.session_fn = func() -> String: return "dev-session"
	main.online.coins_fn = func() -> int: return coins
	main.online.level_fn = func() -> int: return level
	main.online.reveal_fast = true

func _process(_d: float) -> void:
	if hub == null:
		return
	for r: NetFake.Room in hub.rooms.values():
		if r.playing and Engine.get_process_frames() % 50 == 0:
			r.step()

# =====================================================================================================================
# Sections
# =====================================================================================================================

func _s_home() -> void:
	main.home.select_game("ludo")
	await _sleep(1.2)
	await shot("home_ludo")
	main._on_tab("free")                              # the free-coins toast (or its cooldown)
	await _sleep(0.5)
	await shot("toast_free_coins")
	await _sleep(2.4)
	Rewards.claim_free(Save.profile)
	main.home.refresh()
	main._on_tab("free")
	await _sleep(0.5)
	await shot("toast_free_cooldown")
	await _sleep(2.4)
	main._home_toast("+25 gems", "gem")
	await _sleep(0.4)
	await shot("toast_gem")
	await _sleep(2.2)
	main._home_toast("This match can’t be continued.", "bad")
	await _sleep(0.4)
	await shot("toast_bad")
	await _sleep(2.2)
	main.home._show_continue("Ludo vs Computer · 0% · 12h ago")    # the Continue match pill (a kept match)
	await _sleep(0.8)
	await shot("home_continue")
	main.home._show_continue("")
	await _sleep(0.5)
	main.home.select_game("sl")
	await _sleep(3.2)
	await shot("home_sl_landing")
	main.home.select_game("ludo")
	await _sleep(1.2)
	await sheet_shot(func(): main._confirm_quit(), "quit_confirm")

func _s_rewards() -> void:
	await sheet_shot(func(): main._on_tab("rewards"), "rewards")
	main._on_tab("rewards")
	await _sleep(0.8)
	main._on_tab("spin")                              # Rewards -> Spin (the row's action), stacked
	await _sleep(0.9)
	await shot("rewards_to_spin_stacked")
	main.close_all_sheets()
	await _sleep(0.3)
	main._on_tab("rewards")
	await _sleep(0.8)
	main._on_tab("daily")
	await _sleep(0.9)
	await shot("rewards_to_daily_stacked")
	main.close_all_sheets()
	await _sleep(0.3)
	await sheet_shot(func(): main._on_tab("spin"), "spin")
	await sheet_shot(func(): main._on_tab("daily"), "daily")
	main._on_tab("daily")
	await _sleep(0.9)
	var dsh := main._top_sheet() as DailySheet     # a later day's tile: why it can't be claimed
	if dsh:
		dsh._tiles[4].refused.emit("Day 5 opens in a few days.")
		await _sleep(0.4)
		await shot("daily_locked_toast")

func _s_profile() -> void:
	main._on_tab("profile")
	await _sleep(0.9)
	await shot("profile_me")
	var ps: Sheet = main._top_sheet()
	if ps and ps.scroll_box:
		ps.scroll_box.scroll_vertical = 360
		await _sleep(0.4)
		await shot("profile_me_scrolled")
		ps.scroll_box.scroll_vertical = 100000
		await _sleep(0.4)
		await shot("profile_me_bottom")
		ps.scroll_box.scroll_vertical = 0
	if ps and ps.get("_tabs"):
		ps._tabs.tap("ach")
		await _sleep(0.5)
		await shot("profile_achievements")
		ps.scroll_box.scroll_vertical = 100000
		await _sleep(0.4)
		await shot("profile_achievements_bottom")
		ps._tabs.tap("profile")
		await _sleep(0.4)
	# Profile -> Leaderboard (stacked over the Profile)
	if ps and ps.has_method("_open_leaderboard"):
		ps._open_leaderboard()
		await _sleep(1.4)
		await shot("profile_to_leaderboard_stacked")
		var lb := main._top_sheet() as LeaderboardSheet
		if lb:
			lb.fetch_fn = _fake_board
			lb.load_board(true)
			await _sleep(0.9)
			await shot("profile_to_leaderboard_filled")
			lb.close()
			await _sleep(0.5)
	# Profile -> Inventory (the Shop on Avatars, owned only, replacing the Profile)
	if ps and ps.has_method("_customise"):
		ps._customise()
		await _sleep(1.4)
		await shot("profile_to_customise_stacked")
		var top: Sheet = main._top_sheet()
		if top and top != ps:
			top.close()
			await _sleep(0.5)
	main.close_all_sheets()
	await _sleep(0.3)
	# the Leaderboard on its own (Home's Ranks): offline state, then filled
	main._on_tab("leaderboard")
	await _sleep(1.6)
	await shot("leaderboard_offline")
	var lb2 := main._top_sheet() as LeaderboardSheet
	if lb2:
		lb2.fetch_fn = _fake_board
		lb2.load_board(true)
		await _sleep(0.9)
		await shot("leaderboard_filled")
		lb2.select("wins", "all")
		await _sleep(0.9)
		await shot("leaderboard_wins_all")

func _fake_board(_b: String, _p: String) -> Dictionary:
	await get_tree().create_timer(0.2).timeout
	var names := ["Mimi", "Rafi", "Tanvir Ahmed Chowdhury", "Nusrat", "Arif", "Sadia", "Karim", "Joya", "Rumana", "Babu", "Lipi", "Sumon"]
	var top := []
	for k in names.size():
		top.append({rank = k + 1, name = names[k], avatar = "", frame = "", level = 40 - k * 3, value = 98000 - k * 7300})
	return {ok = true, min_matches = 3, top = top, me = {rank = 23, value = 1400, listed = true}}

func _s_shop() -> void:
	for t in ["rooms", "scenes", "dice", "emotes", "avatars", "frames", "plates", "badges"]:
		await sheet_shot(func(): _open_shop(t), "shop_" + t)
	await sheet_shot(func(): _open_shop("coins"), "shop_get_coins", 1.4)
	for t in ["rooms", "avatars"]:
		await sheet_shot(func(): _open_shop(t, true), "shop_owned_" + t)
	await sheet_shot(func(): main._on_tab("inventory"), "inventory")
	var ls := _open_shop("avatars")                # a locked card: what unlocks it
	await _sleep(0.8)
	for c: Control in ls._cards:
		if str(c.get_meta("item", "")) == "robot":
			c.gui_input.emit(_tap())
	await _sleep(0.4)
	await shot("shop_locked_toast")
	main.close_all_sheets()
	await _sleep(0.3)
	await sheet_shot(func(): CollectionSheet.new("frames").open(main.sheet_layer), "collection_frames")
	# Shop -> Preview (a room's View)
	var s := _open_shop("rooms")
	await _sleep(0.8)
	s._on_view("room", "dream")
	await _sleep(3.0)
	await shot("shop_to_preview_room")
	main.close_all_sheets()
	await _sleep(0.3)
	s = _open_shop("scenes")
	await _sleep(0.8)
	s._on_view("scene", _first_scene())
	await _sleep(3.0)
	await shot("shop_to_preview_scene")
	main.close_all_sheets()
	await _sleep(0.3)
	# Shop -> Emote pack
	s = _open_shop("emotes")
	await _sleep(0.8)
	s._on_view("emotes", "starter")
	await _sleep(1.2)
	await shot("shop_to_emote_pack")
	main.close_all_sheets()
	await _sleep(0.3)
	# Shop -> a purchase confirm (stacked)
	s = _open_shop("dice")
	await _sleep(0.8)
	Sheet.confirm(s, "Buy Galaxy dice?", "2,500 coins. You’ll have 2,300 left.", "Buy")
	await _sleep(0.7)
	await shot("shop_buy_confirm_stacked")

func _first_scene() -> String:
	return "candy" if SLScenes.SCENES.has("candy") else str(SLScenes.SCENES.keys()[0])

func _s_store() -> void:
	await sheet_shot(func(): main.open_store(), "store_gems", 1.2)
	# Shop -> Store (from "Not enough gems": stacked)
	var s := _open_shop("rooms")
	await _sleep(0.8)
	s.store_requested.emit()
	await _sleep(1.2)
	await shot("shop_to_store_stacked")

func _s_settings() -> void:
	main.open_settings()
	await _sleep(0.9)
	await shot("settings_top")
	var st: Sheet = main._top_sheet()
	if st and st.scroll_box:
		for k in 4:
			st.scroll_box.scroll_vertical = 420 * (k + 1)
			await _sleep(0.35)
			await shot("settings_scroll_%d" % (k + 1))
		st.scroll_box.scroll_vertical = 100000
		await _sleep(0.35)
		await shot("settings_bottom")
	if st and st.has_method("_open_howto"):
		st._open_howto()
		await _sleep(1.0)
		await shot("settings_to_howto_stacked")
		var h: Sheet = main._top_sheet()
		if h and h.has_method("show_game"):
			h.show_game("sl")
			await _sleep(0.4)
			await shot("settings_to_howto_sl")
		if h and h != st:
			h.close()
			await _sleep(0.4)
	if st and st.has_method("_open_credits"):
		st._open_credits()
		await _sleep(1.0)
		await shot("settings_to_credits_stacked")
	main.close_all_sheets()
	await _sleep(0.3)
	main.open_settings()
	await _sleep(0.8)
	st = main._top_sheet()
	if st and st.has_method("_confirm_reset"):
		st._confirm_reset()
		await _sleep(0.6)
		await shot("settings_reset_confirm")

func _s_misc() -> void:
	await sheet_shot(func(): HowToSheet.new().open(main.sheet_layer), "howto_ludo")
	var h := HowToSheet.new()
	h.open(main.sheet_layer)
	await _sleep(0.8)
	if h.scroll_box:
		h.scroll_box.scroll_vertical = 100000
	await _sleep(0.4)
	await shot("howto_ludo_bottom")
	h.show_game("sl")
	await _sleep(0.4)
	await shot("howto_sl")
	main.close_all_sheets()
	await _sleep(0.3)
	var here := {name = "Shihab", avatar = "pawn-red", level = 3, coins = 8450, wins = 12}
	var there := {name = "Mimi", avatar = "ch-mim", level = 14, coins = 52300, wins = 88}
	await sheet_shot(func(): ConflictSheet.new({kind = "conflict", here = here, there = there}, null).open(main.sheet_layer), "conflict")
	await sheet_shot(func(): ConflictSheet.new({kind = "other_google", here = here, there = null}, null).open(main.sheet_layer), "conflict_other_google")
	var b := BrokeSheet.new({available = true, next_at = 0, amount = 300})
	b.coins_fn = func() -> int: return 40
	b.ad_ok_fn = func() -> bool: return true
	b.open(main.sheet_layer)
	b.refresh()
	await _sleep(0.9)
	await shot("broke")
	main.close_all_sheets()
	await _sleep(0.3)
	var b2 := BrokeSheet.new({available = false, next_at = int(Time.get_unix_time_from_system()) + 3600 * 5, amount = 300})
	b2.coins_fn = func() -> int: return 40
	b2.open(main.sheet_layer)
	b2.refresh()
	await _sleep(0.9)
	await shot("broke_cooldown")

func _s_setup() -> void:
	await sheet_shot(func(): main._open_setup("ludo", "cpu"), "setup_ludo_cpu")
	await sheet_shot(func(): main._open_setup("ludo", "local"), "setup_ludo_local")
	var su: Sheet = await _top_after(func(): main._open_setup("ludo", "local"), 0.8)
	for bt in su.find_children("*", "Button", true, false) if su else []:
		if bt.text == "4":
			bt.button_pressed = true
	await _sleep(0.4)
	await shot("setup_ludo_local_4")
	main.close_all_sheets()
	await _sleep(0.3)
	await sheet_shot(func(): main._open_setup("sl", "cpu"), "setup_sl_cpu")
	await sheet_shot(func(): main._open_setup("sl", "local"), "setup_sl_local")
	# the on-screen keyboard: simulated at 42% of the window (grey), Name2 focused; the field and Start stay above it
	for g in [["ludo", "setup_kb_ludo_local"], ["sl", "setup_kb_sl_local"]]:
		var sk: Sheet = await _top_after(func(): main._open_setup(g[0], "local"), 0.8)
		var ed := sk.find_child("Name2", true, false) as LineEdit if sk else null
		if ed:
			Sheet.kb_debug_px = float(get_window().size.y) * 0.42
			var kl := CanvasLayer.new()
			kl.layer = 100
			var kr := ColorRect.new()
			kr.color = Color(0.45, 0.45, 0.48, 1.0)
			var vs := get_viewport().get_visible_rect().size
			kr.position = Vector2(0, vs.y * 0.58)
			kr.size = Vector2(vs.x, vs.y * 0.42)
			kl.add_child(kr)
			get_tree().root.add_child(kl)
			ed.grab_focus()
			await _sleep(0.7)
			await shot(g[1])
			print("kb lift ", sk._kb, " card ", sk.card.get_global_rect(), " vp ", get_viewport().get_visible_rect().size)
			ed.text_submitted.emit(ed.text)       # Enter: on to Name3
			await _sleep(0.3)
			print("after enter focus owner: ", get_viewport().gui_get_focus_owner().name)
			kl.queue_free()
			Sheet.kb_debug_px = -1.0
		main.close_all_sheets()
		await _sleep(0.4)

func _s_online() -> void:
	main.home.select_game("ludo")
	await _sleep(0.8)
	main.home.quick_button.pressed.emit()
	await _sleep(1.0)
	await shot("quick_picker_2p")
	var qs: QuickSheet = main.online.quick_sheet
	if qs:
		qs._on_row("t10k")                     # a locked table: a toast, the sheet doesn't change
		await _sleep(0.4)
		await shot("quick_locked_toast")
		await _sleep(2.0)
		qs.players = 4
		qs._refresh_rows()
		(qs.picker.get_child(1) as Button).button_pressed = true
		await _sleep(0.4)
		await shot("quick_picker_4p")
		coins = 800
		qs.set_wallet(level, coins)
		qs._refresh_rows()
		await _sleep(0.3)
		await shot("quick_picker_800_coins")
		qs._on_row("t2k")                      # a table you can't pay: a toast too
		await _sleep(0.4)
		await shot("quick_unaffordable_toast")
		await _sleep(2.0)
		qs.find.emit(4)
		await _sleep(2.2)
		await shot("quick_searching_4")
		qs.cancel_pressed.emit()
		qs.close()
		await _sleep(0.6)
	coins = 5000
	main.close_all_sheets()
	await _sleep(0.3)
	main.home.friends_button.pressed.emit()
	await _sleep(0.9)
	await shot("friends")
	var fr = main.online.friends
	if fr and fr.has_method("set_code"):
		fr.set_code("K7QX2M")
		await _sleep(0.3)
		await shot("friends_code_typed")
	main.close_all_sheets()
	await _sleep(0.3)
	var ls := LobbySheet.new("K7QX2M", "m1", "ludo")
	ls.open(main.sheet_layer)
	ls.update({code = "K7QX2M", host = "m1", settings = {teams = false, pair_ask = true, game = "ludo"}, members = [
		{id = "m1", name = "Shihab", avatar = "pawn-red", level = 7, online = true, color = 0},
		{id = "m2", name = "Rafi", avatar = "ch-rafi", level = 12, online = true, color = 1},
		{id = "m3", name = "Tanvir Ahmed C", avatar = "", level = 3, online = false, color = 2}]}, true)
	await _sleep(0.9)
	await shot("lobby_host")
	ls.update({code = "K7QX2M", host = "m2", settings = {teams = false, pair_ask = false, game = "sl"}, members = [
		{id = "m2", name = "Rafi", avatar = "ch-rafi", level = 12, online = true, color = 0},
		{id = "m1", name = "Shihab", avatar = "pawn-red", level = 7, online = true, color = 1}]}, false)
	await _sleep(0.6)
	await shot("lobby_guest_sl")
	ls.start_button.gui_input.emit(_tap())    # a guest's disabled Start says why
	await _sleep(0.4)
	await shot("lobby_guest_start_toast")

func _s_ludo() -> void:
	main.speed = 0.5
	main.start_ludo({game = "ludo", players = ["human", "cpu", "cpu", "cpu"], teams = false})
	await _sleep(2.4)
	await shot("ludo_hud_start")
	main.ludo._id += 1                                # freeze the match (no more turns)
	var S: Dictionary = main.ludo.S
	S.tok = [[12, 12, 30, 56], [5, 40, -1, -1], [20, 51, -1, 56], [8, 25, 44, -1]]
	S.turn = 0
	S.phase = "roll"
	main.world.board.relayout(S)
	main.hud.update(S, 0)
	await _sleep(1.0)
	await shot("ludo_hud_midgame")
	main.hud.emote_picker.open()
	await _sleep(0.8)
	await shot("ludo_emote_picker")
	main.hud.emote_picker.close()
	await _sleep(0.4)
	main.hud.emotes.show_emote(1, "laugh")
	main.hud.emotes.show_emote(0, "party")
	await _sleep(0.7)
	await shot("ludo_emotes_shown")
	main.hud.show_reroll(3000, 3000, false, 5)
	await _sleep(0.5)
	await shot("ludo_reroll_offer")
	main.hud.hide_reroll()
	main.open_pause()
	await _sleep(0.7)
	await shot("pause")
	main.open_settings()
	await _sleep(0.9)
	await shot("pause_to_settings_stacked")
	var st: Sheet = main._top_sheet()
	if st and st != main._pause_sheet:
		st.close()
		await _sleep(0.4)
	main._ask_restart()
	await _sleep(0.6)
	await shot("pause_restart_confirm")
	main._back()
	await _sleep(0.4)
	main.close_all_sheets()
	# results: a win with a level up, a loss
	var TS: Dictionary = main.ludo.S
	TS.tok = [[56, 56, 56, 56], [56, 56, 40, 30], [20, 10, -1, 56], [5, -1, -1, -1]]
	TS.winner = 0
	Save.profile.xp = int(Save.profile.xp) + 300
	main._xp_start = int(Save.profile.xp) - 300
	main._on_finished({title = "You win!", reward = 200, human_won = true, vs_cpu = true}, "ludo")
	await _sleep(3.4)
	await shot("ludo_result_win")
	main.close_all_sheets()
	await _sleep(0.3)
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
	await shot("ludo_result_lose")
	# a coin-table result (as econ_shots builds it)
	if is_instance_valid(main._result):
		var data: Dictionary = main._result.data.duplicate(true)
		main.close_all_sheets()
		await _sleep(0.3)
		data.table = {tier = "t100", entry = 100, payout = 190, match_id = "m-audit"}
		data.reward = 190
		data.human_won = true
		data.ads = true
		var r := ResultScreen.new(data)
		main._result = r
		r.open(main.sheet_layer)
		await _sleep(4.0)
		await shot("ludo_result_coin_table")
	main.close_all_sheets()
	# teams
	main.start_ludo({game = "ludo", players = ["human", "cpu", "cpu", "cpu"], teams = true})
	await _sleep(2.4)
	await shot("ludo_hud_teams")

func _s_sl() -> void:
	main.start_sl({game = "sl", mode = "cpu", n = 4, color = 0})
	await _sleep(3.0)
	await shot("sl_hud_start")
	for k in 6:
		if main.sl.G.players[main.sl.G.turn].you and main.sl.G.phase == "roll":
			main.sl.roll()
		await _sleep(1.2)
	await shot("sl_hud_midgame")
	main.sl._id += 1
	if main.sl.emote_picker:
		main.sl.emote_picker.open()
		await _sleep(0.8)
		await shot("sl_emote_picker")
		main.sl.emote_picker.close()
		await _sleep(0.4)
	if main.sl.reroll_button:
		main.sl.reroll_button.show_offer(3000, 3000, true, 0)
		main.sl._layout()
		await _sleep(0.5)
		await shot("sl_reroll_offer")
		main.sl.reroll_button.hide_offer()
	main.open_pause()
	await _sleep(0.7)
	await shot("sl_pause")
	main.close_all_sheets()
	var G: Dictionary = main.sl.G
	G.players[0].pos = 100
	G.winner = 0
	G.phase = "over"
	Save.profile.xp = int(Save.profile.xp) + 300
	main._xp_start = int(Save.profile.xp) - 300
	main._on_finished({title = "You win!", reward = 100, human_won = true, vs_cpu = true}, "sl")
	await _sleep(3.4)
	await shot("sl_result_win")
	if is_instance_valid(main._result):             # the same result with a level up (SH-09: the tag sits in the XP tile)
		var d2: Dictionary = main._result.data.duplicate(true)
		main.close_all_sheets()
		await _sleep(0.3)
		var b := Collection.level_info(int(d2.xp_before))
		d2.xp_before = int(d2.xp_before) - int(b.into) + int(b.need) - 60
		d2.xp_after = int(d2.xp_before) + 300
		d2.level_before = Collection.level_info(int(d2.xp_before)).level
		d2.level_after = Collection.level_info(int(d2.xp_after)).level
		var r2 := ResultScreen.new(d2)
		main._result = r2
		r2.open(main.sheet_layer)
		await _sleep(4.2)
		await shot("sl_result_levelup")
	main.close_all_sheets()
	main.go_home()
	await _sleep(1.0)
	await shot("home_after_game")

# =====================================================================================================================
# Helpers
# =====================================================================================================================

func _open_shop(t: String, owned := false) -> ShopSheet:
	var s := ShopSheet.new(t, float(UIKit.W.catalog), owned)
	main._wire_shop(s)
	s.open(main.sheet_layer)
	return s

func _top_after(open: Callable, wait: float) -> Sheet:
	for attempt in 2:
		open.call()
		await _sleep(wait)
		var s: Sheet = main._top_sheet()
		if s:
			return s
		main.close_all_sheets()
	return null

func sheet_shot(open: Callable, name: String, wait := 0.9) -> void:
	open.call()
	await _sleep(wait)
	await shot(name)
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


## A left-button press (what a disabled button's gui_input sees).
func _tap() -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	return e
