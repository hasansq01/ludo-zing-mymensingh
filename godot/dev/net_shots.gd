extends Node
## Dev: screenshots of the friend-room screens in the real app, against an in-process NetFake room with scripted
## friends (no network): Home (Ludo / S&L), Friends, the lobby (host alone, two, four with Teams, as a guest), the
## online match (your turn with the timer, a friend's turn, offline and bot badges, the away prompt, Reconnecting…,
## the menu) and the online result (guest: Waiting for host…; host: Play again).
##   godot --path . --resolution 390x844 res://dev/net_shots.tscn -- <out_dir> [--quick]
## Never writes the real save: Save's debounced flush is unhooked and the file is restored at the end anyway.

var out := "/tmp"
var main: Node
var n := 0
var _backup := ""
var room: NetFake.Room
var friends: Array = []                   # Friend (scripted clients)
var quick := false


## A scripted friend: a NetClient on the fake room playing its own turns from its replica, with a human-ish pause.
class Friend extends Node:
	var net: NetClient
	var ns := NetLudo.new()
	var inbox: Array = []
	var sent := -1
	var wait := 0.0
	var playing := true
	var delay := 0.9

	func _init(r: NetFake.Room, name_: String, avatar: String) -> void:
		net = NetClient.new()
		net.use_save = false
		net.prefs = {}
		net.url_base = "ws://fake"
		net.profile_fn = func() -> Dictionary: return {name = name_, avatar = avatar, frame = "classic"}
		net.make_transport = r.transport_factory()
		net.http_fn = r.http
		net.message.connect(func(m: Dictionary): inbox.append(m))
		add_child(net)

	func _process(d: float) -> void:
		for m: Dictionary in inbox:
			match str(m.get("t", "")):
				"start", "sync":
					ns.begin(m, net.member_id)
					sent = -1
				"act":
					ns.push(m)
		inbox.clear()
		while true:
			var x := ns.next()
			if x.is_empty() or x.t != "act":
				break
			ns.play(x)
		if not playing or not ns.my_turn() or sent == ns.n:
			wait = delay
			return
		wait -= d
		if wait > 0.0:
			return
		var msg := {}
		match str(ns.S.phase):
			"roll":
				msg = ns.request("roll")
			"choose":
				var i := LudoRules.auto_move_token(ns.S)
				if i < 0:
					i = int(LudoRules.units(ns.S)[0].token)
				msg = ns.request("move", {i = i})
			"pair_ask":
				msg = ns.request("pair", {yes = true})
		if not msg.is_empty() and net.send_msg(msg):
			sent = ns.n


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size():
		out = args[0]
	quick = args.has("--quick")
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
	Save.profile.name = "Shihab"
	Rewards.daily_data(Save.profile).auto_on = Time.get_date_string_from_system()   # no daily sheet popping up
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _until(func(): return main.screen == "home", 60)
	await _sleep(1.5)
	main.close_all_sheets()
	_use_room("K7QX2M", 3)
	await _home()
	await _host_lobby()
	await _guest_and_match()
	_restore()
	get_tree().quit()

## Point the app's NetClient at a fresh fake room.
func _use_room(code: String, seed_: int) -> void:
	room = NetFake.Room.new(code, seed_)
	var net: NetClient = main.online.net
	net.url_base = "ws://fake"
	net.make_transport = room.transport_factory()
	net.http_fn = room.http

func _friend(name_: String, avatar: String) -> Friend:
	var f := Friend.new(room, name_, avatar)
	add_child(f)
	friends.append(f)
	f.net.join(room.code)
	return f

func _clear_friends() -> void:
	for f: Friend in friends:
		f.net.leave()
		f.queue_free()
	friends.clear()

# ---------- screens ----------

func _home() -> void:
	await shot("home_ludo")
	main.home.select_game("sl")
	await _sleep(2.5)
	await shot("home_sl_soon")
	main.home.friends_button.pressed.emit()
	await _sleep(0.5)
	await shot("home_sl_soon_toast")
	main.home.select_game("ludo")
	await _sleep(2.0)
	main.home.friends_button.pressed.emit()
	await _sleep(0.9)
	await shot("friends")
	var fs: FriendsSheet = main.online.friends
	fs.set_code("k7q")
	await _sleep(0.3)
	await shot("friends_typing")
	fs.set_code("")

func _host_lobby() -> void:
	var fs: FriendsSheet = main.online.friends
	fs.create_room.emit()
	await _until(func(): return is_instance_valid(main.online.lobby_sheet), 5)
	await _sleep(1.0)
	await shot("lobby_host_alone")
	_friend("Rafi", "ch-rafi")
	await _sleep(0.8)
	await shot("lobby_host_two")
	_friend("Mitu", "ch-mim")
	_friend("Tanvir", "ch-tanvir")
	await _sleep(0.5)
	main.online.lobby_sheet.teams_switch.button_pressed = true
	await _sleep(0.8)
	await shot("lobby_host_four_teams")
	main.online.lobby_sheet.share()
	await _sleep(0.4)
	await shot("lobby_share_toast")
	main.online.lobby_sheet.leave_pressed.emit()
	await _sleep(0.6)
	await shot("lobby_leave_confirm")
	var c: Sheet = main._top_sheet()
	if c and c.has_meta("confirm"):
		(c.find_child("Yes", true, false) as Button).pressed.emit()
	await _sleep(0.8)
	_clear_friends()

## You join a friend's room as a guest; the host starts; the match; the result.
func _guest_and_match() -> void:
	_use_room("H4PPY7", 11)
	var host := _friend("Rafi", "ch-rafi")
	await _sleep(0.3)
	main.online.open_friends()
	await _sleep(0.6)
	var fs: FriendsSheet = main.online.friends
	fs.set_code("h4ppy7")
	await _sleep(0.2)
	fs._join()
	await _until(func(): return is_instance_valid(main.online.lobby_sheet), 5)
	await _sleep(0.9)
	await shot("lobby_guest")
	var third := _friend("Mitu", "ch-mim")
	await _sleep(0.4)
	for mem in room.members:
		mem.pair_ask = true                   # everyone's own "Ask before pairing" (as their hellos would say)
	host.net.send_msg({t = "start"})
	await _until(func(): return main.screen == "ludo" and main.ludo.online, 5)
	await _sleep(2.5)
	await _until(func(): return main.ludo.ns.my_turn() and main.ludo.S.phase == "roll" and not main.ludo._busy, 30)
	await _sleep(0.6)
	await shot("match_your_turn_timer")
	main.ludo.roll()
	await _until(func(): return not main.ludo.ns.my_turn() or main.ludo.S.phase == "choose", 10)
	await _sleep(1.2)
	if main.ludo.S.phase == "choose" and main.ludo.ns.my_turn():
		await shot("match_choose")
	await _until(func(): return not main.ludo.ns.my_turn(), 15)
	await _sleep(0.8)
	await shot("match_friend_turn")
	# a friend drops off: Offline; another leaves: Bot
	host.playing = false
	host.net.transport.drop()
	host.net.set_process(false)
	await _sleep(0.8)
	third.net.leave()
	await _sleep(1.2)
	await shot("match_offline_and_bot_badges")
	# a bot takes your seat (two timeouts): the away prompt
	room._act({k = "mode", c = main.ludo.ns.me, mode = "cpu"})
	await _sleep(1.0)
	await shot("match_away_prompt")
	main.hud.away_button.pressed.emit()
	await _sleep(1.0)
	await shot("match_back")
	# the socket drops: Reconnecting…
	var pipe: NetFake.Pipe = main.online.net.transport
	main.online.net.make_transport = func() -> NetTransport:
		var p := room.make_pipe()
		p.reachable = false
		return p
	pipe.drop()
	await _sleep(1.2)
	await shot("match_reconnecting")
	main.online.net.make_transport = room.transport_factory()
	await _until(func(): return main.online.net.is_open(), 20)
	await _sleep(1.5)
	await shot("match_reconnected")
	main.open_pause()
	await _sleep(0.8)
	await shot("match_menu_online")
	main.close_all_sheets()
	main.paused = false
	# fast-forward: the server's state jumps near the end (a sync), then everyone plays it out
	_near_end()
	await _sleep(1.5)
	await shot("match_after_sync")
	await _play_out(240)
	await _until(func(): return is_instance_valid(main._result), 30)
	await _sleep(4.0)
	await shot("result_guest_waiting")
	main.online_host_changed(true)
	await _sleep(0.6)
	await shot("result_host_play_again")

## Puts the room's match near its end and sends everyone a sync (the app re-lays the board from it).
func _near_end() -> void:
	var S := room.S
	for c in 4:
		if S.players[c] != "off":
			S.tok[c] = [56, 56, 56, 50] if c == main.ludo.ns.me else [56, 56, 44, 30]
	S.pairs = []
	S.phase = "roll"
	S.pending = {}
	S.sixes = 0
	S.turn = main.ludo.ns.me
	var msg := room._sync_msg()
	room._broadcast(msg)
	room._broadcast(room._turn_msg())

## The app plays its own turns through its UI paths; bots and timeouts act for the others.
func _play_out(sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - t0) / 1000.0 < sec and not is_instance_valid(main._result):
		await _sleep(0.25)
		var L: LudoMatch = main.ludo
		if room.playing and room.S.players[int(room.S.turn)] == "cpu":
			room.step()
			continue
		if room.playing and not L.ns.my_turn() and room.S.players[int(room.S.turn)] == "human":
			var who := -1
			for f: Friend in friends:
				if is_instance_valid(f) and f.playing and f.ns.me == int(room.S.turn):
					who = 1
			if who < 0:
				room.timeout()
			continue
		if L._busy or L.ns.n != room.n:
			continue
		if main.hud.pair_box.visible:
			main.hud._answer(true)
		elif L.S.phase == "roll":
			L.roll()
		elif L.S.phase == "choose" and not main.world.board.movable.is_empty():
			var u: Array = LudoRules.units(L.S)
			L.move(int(u[0].token))

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
