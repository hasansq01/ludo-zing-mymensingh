extends Node
## Dev: screenshots of the in-game emotes in the real app, no network (an in-process NetFake room for online):
##   Ludo vs Computer (3D, then Top view): the picker open, your reaction, a computer's (top seat), two at once;
##   Snakes & Ladders vs Computer: the picker open and a reaction; online Ludo (a friend room, two scripted
##   friends): a friend's emote arriving on their seat while yours shows.
##   godot --path . --resolution 390x844 res://dev/emote_shots.tscn -- <out_dir>
## Never writes user://save.json: Save's debounced flush is unhooked and its dirty flag is cleared every frame;
## MatchStore is off.

var out := "/tmp"
var main: Node
var n := 0
var room: NetFake.Room
var friends: Array = []


## A scripted friend (as in playon_shots.gd): a NetClient on the fake room playing its own turns from its replica.
class Friend extends Node:
	var net: NetClient
	var ns := NetLudo.new()
	var inbox: Array = []
	var sent := -1
	var wait := 0.0
	var playing := true

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
			wait = 0.5
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
	await _ludo("3d")
	await _ludo("top")
	await _prompts()
	await _pass_and_play()
	await _sl()
	await _online()
	Save._dirty = false
	get_tree().quit()

func _process(_d: float) -> void:
	Save._dirty = false                        # never let the quit-time flush write the real save

# ---------- Ludo vs Computer ----------

func _ludo(cam: String) -> void:
	Save.prefs.cam = cam
	main.start_ludo({game = "ludo", players = ["human", "cpu", "cpu", "cpu"], teams = false, bot_level = "normal"})
	var L: LudoMatch = main.ludo
	await _until(func(): return not L.S.is_empty() and L.S.phase == "roll" and not L._busy and L.S.turn == 0, 20)
	await _sleep(1.2)
	var hud: LudoHUD = main.hud
	hud.emote_picker.open()
	await _sleep(0.12)
	await shot("%s_picker_opening" % cam)
	await _sleep(0.5)
	await shot("%s_picker_open" % cam)
	hud.emote_picker.pick("happy")
	await _sleep(0.6)
	await shot("%s_your_reaction" % cam)
	await _sleep(0.3)
	hud.emote_picker.open()
	await _sleep(0.5)
	await shot("%s_picker_cooling" % cam)
	hud.emote_picker.close()
	await _sleep(2.4)
	hud.emotes.show_emote(1, "laugh")             # Mocha, top left
	await _sleep(0.8)
	await shot("%s_cpu_reaction_top" % cam)
	await _sleep(2.0)
	hud.emotes.show_emote(0, "party")
	hud.emotes.show_emote(2, "crown")
	hud.emotes.show_emote(3, "angry")
	await _sleep(0.7)
	await shot("%s_three_at_once" % cam)
	await _sleep(2.2)
	main.go_home()
	await _sleep(0.8)

# ---------- the button keeps clear of the prompts over the tile row ----------

func _prompts() -> void:
	Save.prefs.cam = "3d"
	main.start_ludo({game = "ludo", players = ["human", "cpu", "cpu", "cpu"], teams = false, bot_level = "normal"})
	var L: LudoMatch = main.ludo
	await _until(func(): return not L.S.is_empty() and L.S.phase == "roll" and not L._busy and L.S.turn == 0, 20)
	await _sleep(1.0)
	var hud: LudoHUD = main.hud
	hud.ask_pair()
	await _sleep(0.5)
	hud.emote_picker.open()
	await _sleep(0.5)
	await shot("prompt_pair_picker_open")
	hud.emote_picker.close()
	hud.cancel_pair()
	hud.show_finish(1, false, true)
	await _sleep(0.4)
	hud.emote_picker.pick("party")
	await _sleep(0.6)
	await shot("prompt_finish_card_reaction")
	hud.hide_finish()
	await _sleep(2.2)
	main.go_home()
	await _sleep(0.8)

# ---------- Pass & Play: the player to move sends ----------

func _pass_and_play() -> void:
	main.start_ludo({game = "ludo", players = ["human", "human", "human", "human"], teams = false})
	var L: LudoMatch = main.ludo
	await _until(func(): return not L.S.is_empty() and L.S.phase == "roll" and not L._busy and L.S.turn == 0, 20)
	await _sleep(1.0)
	L.S.turn = 1
	L._begin_turn()
	await _sleep(0.6)
	main.hud.emote_picker.pick("tease" if main.hud.emote_picker.ids.has("tease") else "cool")
	await _sleep(0.7)
	await shot("pp_green_to_move_sends")
	await _sleep(2.2)
	main.go_home()
	await _sleep(0.8)

# ---------- Snakes & Ladders ----------

func _sl() -> void:
	main.start_sl({game = "sl", mode = "cpu", n = 4, color = 0})
	var M: SLMatch = main.sl
	await _until(func(): return not M.G.is_empty() and M.G.phase == "roll" and not M._busy and M.G.turn == 0, 20)
	await _sleep(4.0)
	M.emote_picker.open()
	await _sleep(0.6)
	await shot("sl_picker_open")
	M.emote_picker.pick("love")
	await _sleep(0.15)
	M.emotes.show_emote(int(M.G.players[2].c), "cool")
	await _sleep(0.6)
	await shot("sl_reactions")
	await _sleep(2.5)
	main.go_home()
	await _sleep(0.6)

# ---------- online: a friend's emote ----------

func _online() -> void:
	Save.prefs.cam = "3d"
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
	var mitu := _friend("Mitu", "ch-mim")
	await _sleep(0.5)
	host.net.send_msg({t = "start"})
	await _until(func(): return main.screen == "ludo" and main.ludo.online and not main.ludo.S.is_empty(), 8)
	await _sleep(2.0)
	for f: Friend in friends:
		f.playing = false
	main.hud.emote_picker.pick("cool")
	await _sleep(0.3)
	host.net.send_emote("laugh")
	mitu.net.send_emote("love")
	await _sleep(0.7)
	await shot("online_friends_reactions")
	await _sleep(2.5)
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
