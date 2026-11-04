extends Node
## Dev: screenshots of play on (a game goes on after the first finish) in the real app, no network:
##   1. Pass & Play Ludo, 4 players: Red finishes -> the "Red finished 1st!" pop, then the place badge on the dimmed
##      tile while Green plays on.
##   2. Online Ludo (an in-process NetFake room, two scripted friends): you finish first -> the "You finished 1st!"
##      card (Keep watching / Home); Keep watching, the friends play it out, the online result.
##   3. vs Computer: Mocha finishes 1st, you play on and finish 2nd -> the final standings (places, the computers
##      ranked by progress) and your reward.
##   4. Snakes & Ladders Pass & Play: Red reaches 100 first -> the pop and the tile badge.
##   godot --path . --resolution 390x844 res://dev/playon_shots.tscn -- <out_dir>
## Never writes user://save.json: Save's debounced flush is unhooked and its dirty flag is cleared every frame (so
## the quit-time flush has nothing to write); MatchStore is off.

const NEAR := [56, 56, 56, 55]

var out := "/tmp"
var main: Node
var n := 0
var room: NetFake.Room
var friends: Array = []


## A scripted friend (as in net_shots.gd): a NetClient on the fake room playing its own turns from its replica.
class Friend extends Node:
	var net: NetClient
	var ns := NetLudo.new()
	var inbox: Array = []
	var sent := -1
	var wait := 0.0
	var playing := true
	var delay := 0.5

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
	DirAccess.make_dir_recursive_absolute(out)
	if Save._timer and Save._timer.timeout.is_connected(Save.flush):
		Save._timer.timeout.disconnect(Save.flush)      # dev run: nothing reaches user://save.json
	MatchStore.enabled = false
	Save.prefs.welcome_seen = true
	Save.prefs.tutorial_done = true
	Save.prefs.erase("net_room")
	Save.prefs.speed = 0.55
	Save.prefs.cam = "3d"
	Save.prefs.home_game = "ludo"
	Save.profile.name = "Shihab"
	Rewards.daily_data(Save.profile).auto_on = Time.get_date_string_from_system()   # no daily sheet popping up
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _until(func(): return main.screen == "home", 60)
	await _sleep(1.5)
	main.close_all_sheets()
	await _pass_and_play()
	await _online()
	await _vs_computer()
	await _sl()
	Save._dirty = false
	get_tree().quit()

func _process(_d: float) -> void:
	Save._dirty = false                        # never let the quit-time flush write the real save

# ---------- 1. Pass & Play ----------

func _pass_and_play() -> void:
	main.start_ludo({game = "ludo", players = ["human", "human", "human", "human"], teams = false})
	var L: LudoMatch = main.ludo
	await _until(func(): return not L.S.is_empty() and L.S.phase == "roll" and not L._busy and L.S.turn == 0, 20)
	await _sleep(1.0)
	_set_tok(L, [NEAR, [56, 56, 40, 22], [56, 30, 12, -1], [44, 20, -1, -1]], 0)
	await _sleep(0.6)
	L.roll(1)
	await _until(func(): return (L.S.get("finished", []) as Array).size() == 1, 10)
	await _sleep(0.45)
	await shot("pp_red_finished_pop")
	await _until(func(): return L.S.turn == 1 and L.S.phase == "roll" and not L._busy, 10)
	await _sleep(1.6)
	await shot("pp_green_plays_on_red_badge")
	main.go_home()
	await _sleep(1.0)

# ---------- 2. Online: your finish card ----------

func _online() -> void:
	room = NetFake.Room.new("H4PPY8", 21)
	var net: NetClient = main.online.net
	net.url_base = "ws://fake"
	net.make_transport = room.transport_factory()
	net.http_fn = room.http
	var host := _friend("Rafi", "ch-rafi")
	await _sleep(0.3)
	main.online.open_friends()
	await _sleep(0.6)
	var fs: FriendsSheet = main.online.friends
	fs.set_code(room.code.to_lower())
	await _sleep(0.2)
	fs._join()
	await _until(func(): return is_instance_valid(main.online.lobby_sheet), 5)
	await _sleep(0.5)
	_friend("Mitu", "ch-mim")
	await _sleep(0.5)
	host.net.send_msg({t = "start"})
	await _until(func(): return main.screen == "ludo" and main.ludo.online and not main.ludo.S.is_empty(), 8)
	await _sleep(2.0)
	for f: Friend in friends:
		f.playing = false
	var L: LudoMatch = main.ludo
	var me: int = L.ns.me
	var S := room.S
	for c in 4:
		if S.players[c] != "off":
			S.tok[c] = NEAR.duplicate() if c == me else ([56, 56, 50, 44] if c == 0 else [56, 52, 46, 40])
	S.pairs = []
	S.phase = "roll"
	S.pending = {}
	S.sixes = 0
	S.turn = me
	room.dice = [1]
	room._broadcast(room._sync_msg())
	room._broadcast(room._turn_msg())
	await _until(func(): return L.ns.my_turn() and L.S.phase == "roll" and not L._busy, 10)
	await _sleep(0.8)
	L.roll()
	await _until(func(): return main.hud.finish_card.visible, 10)
	await _sleep(0.9)
	await shot("online_you_finished_card")
	main.hud.finish_card.watch_button.pressed.emit()
	for f: Friend in friends:
		f.playing = true
	await _sleep(1.2)
	await shot("online_watching_badge")
	var t0 := Time.get_ticks_msec()
	while not is_instance_valid(main._result) and Time.get_ticks_msec() - t0 < 120000:
		await _sleep(0.25)
	await _sleep(4.0)
	await shot("online_final_standings")
	main.online.leave()
	for f: Friend in friends:
		f.net.leave()
		f.queue_free()
	friends.clear()
	main.go_home()
	await _sleep(1.0)

func _friend(name_: String, avatar: String) -> Friend:
	var f := Friend.new(room, name_, avatar)
	add_child(f)
	friends.append(f)
	f.net.join(room.code)
	return f

# ---------- 3. vs Computer: 2nd place, the final standings ----------

func _vs_computer() -> void:
	main.start_ludo({game = "ludo", players = ["human", "cpu", "cpu", "cpu"], teams = false, bot_level = "normal"})
	var L: LudoMatch = main.ludo
	await _until(func(): return not L.S.is_empty() and L.S.phase == "roll" and not L._busy and L.S.turn == 0, 20)
	await _sleep(0.6)
	_set_tok(L, [[56, 56, 56, 54], NEAR, [56, 30, 20, -1], [40, 12, -1, -1]], 1)
	L.roll(1)                                   # Mocha's 1: home first
	await _until(func(): return (L.S.get("finished", []) as Array).size() == 1, 10)
	await _sleep(0.4)
	await shot("cpu_mocha_finished_you_play_on")
	await _until(func(): return L.S.turn == 0 and L.S.phase == "roll" and not L._busy, 40)
	await _sleep(0.4)
	L.S.tok[0] = [56, 56, 56, 54]
	L.roll(2)
	await _until(func(): return is_instance_valid(main._result), 20)
	await _sleep(4.5)
	await shot("cpu_final_standings_2nd")
	main.go_home()
	await _sleep(1.0)

## Lays out tokens (by colour) and gives colour `turn` the dice (a fresh roll phase).
func _set_tok(L: LudoMatch, tok: Array, turn: int) -> void:
	for c in 4:
		L.S.tok[c] = (tok[c] as Array).duplicate()
	L.S.pairs = []
	L.S.turn = turn
	L.S.phase = "roll"
	L.S.sixes = 0
	L.board.relayout(L.S)
	L.hud.update(L.S, turn)
	L._busy = false

# ---------- 4. Snakes & Ladders ----------

func _sl() -> void:
	main.start_sl({game = "sl", mode = "local", n = 3})
	var M: SLMatch = main.sl
	await _until(func(): return not M.G.is_empty() and M.G.phase == "roll" and not M._busy and M.G.turn == 0, 20)
	await _sleep(1.0)
	M.G.players[0].pos = 97
	M.G.players[1].pos = 76
	M.G.players[2].pos = 58
	M.board.place(M._positions())
	M._refresh_tiles()
	await _sleep(0.5)
	M.roll(3)
	await _until(func(): return (M.G.get("finished", []) as Array).size() == 1, 10)
	await _sleep(0.5)
	await shot("sl_red_finished_pop")
	await _sleep(1.8)
	await shot("sl_green_plays_on_red_badge")
	main.go_home()
	await _sleep(0.6)

# ---------- helpers ----------

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	n += 1
	get_viewport().get_texture().get_image().save_png("%s/%02d_%s.png" % [out, n, name])
	print("shot ", name)

func _sleep(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _until(f: Callable, timeout: float) -> void:
	var t0 := Time.get_ticks_msec()
	while not f.call() and (Time.get_ticks_msec() - t0) / 1000.0 < timeout:
		await get_tree().process_frame
