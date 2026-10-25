extends "res://tests/test_suite.gd"
## Online rooms, the UI pieces: the Friends sheet's code field (cleaning, paste of an invite line, Join only with a
## full code), the Lobby sheet (rows, host controls, Teams only with 4, Start with 2+, guests wait), the online
## result screen (Play again for the host, "Waiting for host…" for the others), the HUD's online parts (badges,
## the turn timer, I’m back, Reconnecting…) and the copy rules. Nothing here writes the save or opens a socket.

func run() -> void:
	_friends()
	_lobby()
	_result()
	_hud()
	_copy()

func _friends() -> void:
	var f := FriendsSheet.new()
	check("friends: builds with Create, code field, Paste, Join", f.create_button != null and f.code_edit != null and f.paste_button != null and f.join_button != null)
	check("friends: Join is off with no code", f.join_button.disabled)
	f.set_code("k7q x2m")
	check("friends: typed code is upper-cased and cleaned", f.code_edit.text == "K7QX2M" and f.code() == "K7QX2M", f.code_edit.text)
	check("friends: Join is on with 6 characters", not f.join_button.disabled)
	f.set_code("k7q")
	check("friends: Join is off again with 3", f.join_button.disabled and f.code_edit.text == "K7Q")
	f.set_code("hello 0O1IL")
	check("friends: letters that are never in a code are dropped", f.code_edit.text == "HE", f.code_edit.text)
	check("friends: a pasted invite line gives its code", FriendsSheet.code_from_text(LobbySheet.invite_text("K7QX2M")) == "K7QX2M")
	check("friends: a pasted bare code", FriendsSheet.code_from_text(" k7qx2m ") == "K7QX2M")
	var asked := []
	f.join_room.connect(func(c: String): asked.append(c))
	f.set_code("K7QX2M")
	f._join()
	check("friends: Join emits the code", asked == ["K7QX2M"], asked)
	f.set_busy("join")
	check("friends: busy holds every button", f.join_button.disabled and f.create_button.disabled and f.join_button.text == "Joining…")
	f._join()
	check("friends: no second join while busy", asked.size() == 1)
	f.set_busy("")
	check("friends: done: buttons back", not f.join_button.disabled and not f.create_button.disabled and f.join_button.text == "Join room")
	check("friends: 48 px targets", f.join_button.get_combined_minimum_size().y >= UIKit.TAP and f.paste_button.get_combined_minimum_size().y >= UIKit.TAP
		and f.code_edit.custom_minimum_size.y >= UIKit.TAP)
	f.free()

func _lobby_msg(n: int, host := "m1", teams := false, pair_ask := false) -> Dictionary:
	var cols := NetFake.Room.colors_for(n)
	var ms := []
	for k in n:
		ms.append({id = "m%d" % (k + 1), name = ["Ana", "Bo", "Cy", "Di"][k], avatar = "pawn-green", frame = "classic",
			online = k != 2, color = cols[k]})
	return {t = "lobby", code = "K7QX2M", host = host, members = ms, settings = {teams = teams, pair_ask = pair_ask}, max = 4}

func _lobby() -> void:
	var s := LobbySheet.new("K7QX2M", "m1")
	check("lobby: the code, spaced for reading", s.code_label.text == "K7Q X2M" and LobbySheet.spaced("ABCDEF") == "ABC DEF")
	check("lobby: no close button, Back asks (leave)", s.close_btn == null and not s.dismissable and s.back_action.is_valid())
	s.update(_lobby_msg(1), true)
	check("lobby: the member and one open-seat row", s._list.get_child_count() == 2 and s.count_label.text == "1 of 4")
	check("lobby: host alone can't start", s.start_button.disabled and s.start_button.text == "Start game")
	check("lobby: Teams off below 4", s.teams_switch.disabled and s._teams_note.text == "Needs exactly 4 players")
	s.update(_lobby_msg(2), true)
	check("lobby: host with a friend can start", not s.start_button.disabled and s.can_start())
	var sent := []
	s.settings_changed.connect(func(t: bool, p: bool): sent.append([t, p]))
	s.pair_switch.button_pressed = true
	check("lobby: the host's Ask before pairing goes out", sent == [[false, true]], sent)
	s.update(_lobby_msg(2, "m1", true), true)
	check("lobby: Teams on with 2: can't start", s.start_button.disabled and not s.teams_switch.disabled)
	s.update(_lobby_msg(4, "m1", true), true)
	check("lobby: Teams with 4: can start", not s.start_button.disabled and not s.teams_switch.disabled and s.count_label.text == "4 of 4")
	s.update(_lobby_msg(3, "m2"), false)
	check("lobby: guests wait for the host", s.start_button.disabled and s.start_button.text == "Waiting for host…")
	check("lobby: guests can't change the rules", s.pair_switch.disabled and s.teams_switch.disabled)
	var halves: Array = s.game_picker.get_children()
	check("lobby: guests see the game picker as it is (not the grey disabled look), just not tappable",
		halves.all(func(b): return not b.disabled and b.mouse_filter == Control.MOUSE_FILTER_IGNORE) and s.game_picker.modulate.a == 1.0)
	var picked: Array = []
	s.game_changed.connect(func(g): picked.append(g))
	(halves[1] as Button).pressed.emit()
	check("lobby: …and a pick by a guest changes nothing", picked.is_empty() and s.game == "ludo", [picked, s.game])
	sent.clear()
	s.pair_switch.button_pressed = not s.pair_switch.button_pressed
	check("lobby: …and nothing is sent", sent.is_empty())
	var started := []
	s.start_pressed.connect(func(): started.append(1))
	s.start_button.pressed.emit()
	check("lobby: a disabled Start emits nothing", started.is_empty())
	s.update(_lobby_msg(2), true)
	check("lobby: the host's game picker is tappable again", s.game_picker.get_children().all(func(b): return b.mouse_filter == Control.MOUSE_FILTER_STOP))
	s.set_status("reconnecting")
	check("lobby: reconnecting holds Start and shows the pill", s.status_pill.visible and s.start_button.disabled)
	s.set_status("open")
	check("lobby: back online", not s.status_pill.visible and not s.start_button.disabled)
	var left := []
	s.leave_pressed.connect(func(): left.append(1))
	s.on_back()
	check("lobby: Back = leave (asks)", left.size() == 1)
	s.free()

func _result() -> void:
	var st := [
		{color = 0, name = "You", kind = "you", place = 1, finished = true, progress = 1.0},
		{color = 2, name = "Bo", kind = "human", avatar = "pawn-green", frame = "classic", place = 2, finished = false, progress = 0.4},
	]
	var r := ResultScreen.new({game = "ludo", online = true, host = false, standings = st, human_won = true, reward = 0,
		xp_before = 10, xp_after = 110})
	check("online result: guests see Waiting for host…", r.again_button.text == "Waiting for host…" and r.again_button.disabled)
	r.set_host(true)
	check("online result: the new host can rematch", r.again_button.text == "Play again")
	check("online result: no coins tile", r.coins == null)
	check("online result: a friend's own avatar", ResultScreen._make_avatar(st[1], 40) is Collection.AvatarView)
	r.free()
	var off := ResultScreen.new({game = "ludo", standings = st, human_won = true, reward = 200})
	check("offline result: Play again as before", off.again_button.text == "Play again" and not off.is_online())
	off.free()

func _hud() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var hud := LudoHUD.new()
	hud.size = Vector2(390, 844)
	tree.root.add_child(hud)
	var seats := [{color = 0, id = "m1", name = "Ana", avatar = "pawn-green", frame = "classic", bot = false, online = true},
		{color = 2, id = "m2", name = "Bo", avatar = "pawn-blue", frame = "classic", bot = false, online = true}]
	var ns := NetLudo.new()
	ns.begin({n = 0, seats = seats, state = LudoRules.new_game(["human", "off", "human", "off"])}, "m2")
	hud.set_online(true, ns.me, ns.seats)
	hud.setup(ns.S)
	check("hud online: your tile is you, the friend's is a person", (hud.tiles[2] as PlayerTile).kind == "you" and (hud.tiles[0] as PlayerTile).kind == "human"
		and (hud.tiles[2] as PlayerTile).player_name == "You" and (hud.tiles[0] as PlayerTile).player_name == "Ana")
	check("hud online: the friend's own avatar", (hud.tiles[0] as PlayerTile)._ava is Collection.AvatarView)
	hud.update(ns.S, 0)
	check("hud online: the dice sleep on a friend's turn", not hud.dice.active)
	ns.S.turn = 2
	hud.update(ns.S, 2)
	check("hud online: and wake on yours", hud.dice.active)
	hud.hold_dice = true
	hud.update(ns.S, 2)
	check("hud online: not while your roll is out", not hud.dice.active)
	hud.set_badges(["offline", "", "bot", ""])
	check("hud online: badges", (hud.tiles[0] as LudoHUD.Tile).badge == "offline" and (hud.tiles[2] as LudoHUD.Tile).badge == "bot" and (hud.tiles[1] as LudoHUD.Tile).badge == "")
	hud.set_timer(2, 9000.0, 15000.0)
	check("hud online: the timer is on the active tile only", (hud.tiles[2] as LudoHUD.Tile).timer_end > 0 and (hud.tiles[0] as LudoHUD.Tile).timer_end == 0)
	hud.show_away(true)
	check("hud online: the away prompt with I’m back", hud.away_box.visible and hud.away_button.text == "I’m back" and hud.away_button.get_combined_minimum_size().y >= UIKit.TAP)
	hud.set_banner("Reconnecting…")
	check("hud online: the reconnect pill", hud.banner.visible)
	hud.hide_for_result()
	check("hud online: the result hides them", not hud.away_box.visible and not hud.banner.visible and (hud.tiles[2] as LudoHUD.Tile).timer_end == 0)
	hud.set_online(false)
	check("hud offline again: no badges", (hud.tiles[0] as LudoHUD.Tile).badge == "" and not hud.online)
	tree.root.remove_child(hud)
	hud.free()

func _copy() -> void:
	var files := ["res://scripts/ui/sheets/friends_sheet.gd", "res://scripts/ui/sheets/lobby_sheet.gd", "res://scripts/net/online.gd",
		"res://scripts/net/net_client.gd", "res://scripts/ui/ludo_hud.gd", "res://scripts/game/ludo_match.gd"]
	var bad := []
	var re := RegEx.create_from_string("\"[^\"]*[A-Za-z]'[A-Za-z][^\"]*\"")      # a straight apostrophe inside a string
	var color := RegEx.create_from_string("Color\\(\"#")
	for p in files:
		var src := FileAccess.get_file_as_string(p)
		for line in src.split("\n"):
			var code := line.split("#")[0] if not line.strip_edges().begins_with("##") else ""
			if re.search(code) and not code.contains("get(") and not code.contains("\\\""):
				bad.append([p.get_file(), line.strip_edges()])
			if color.search(line):
				bad.append([p.get_file(), "colour literal"])
	check("online copy: typographic apostrophes, no colour literals outside Palette", bad.is_empty(), bad)
	var ui := FileAccess.get_file_as_string("res://scripts/ui/sheets/lobby_sheet.gd") + FileAccess.get_file_as_string("res://scripts/ui/sheets/friends_sheet.gd")
	check("online copy: pawn, never token, in what players read", not RegEx.create_from_string("\"[^\"]*\\b[Tt]oken").search(ui))
	check("online copy: sentence-case titles", ui.contains("\"Play with friends\"") and ui.contains("\"Friends room\"") and ui.contains("\"Start game\""))
