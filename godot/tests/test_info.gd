extends "res://tests/test_suite.gd"
## Feature info (Info, index.html INFO / Info and tests/info-icons.js): every explanation is there with a title and
## bullets; the pulse stops for good once a key is read and after 3 showings; the saved state survives JSON (floats)
## and junk; a bubble opens, toggles and closes; and the texts restate the rules the game really plays
## (ludo_rules.gd, snakes_ladders_rules.gd, rewards.gd, sl_scenes.gd). Every check runs on its own state
## Dictionary (Info.state_source): the real save is never read or written.

const KEYS := ["ind", "team", "pair", "free", "capture", "slEntry", "sl", "cam", "slcam", "daily", "scenes"]

var writes := 0
var _made: Array[Node] = []

func use(st: Dictionary) -> Dictionary:
	Info.state_source = st
	writes = 0
	Info.writer = func(_s: Dictionary) -> void: writes += 1
	return st

func run() -> void:
	var keep_src: Variant = Info.state_source
	var keep_writer: Callable = Info.writer
	var snd: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Sound")
	var keep_snd: bool = snd.enabled if snd else false
	if snd:
		snd.enabled = false      # opening a bubble plays "select": not in tests
	_run()
	if snd:
		snd.enabled = keep_snd
	Info.close()
	for c in (Engine.get_main_loop() as SceneTree).root.get_children():
		if c is Info.Bubble:
			c.free()
	for n in _made:
		if is_instance_valid(n):
			n.free()
	Info.state_source = keep_src
	Info.writer = keep_writer

func text(key: String, need_one := false) -> String:
	var d: Dictionary = Info.INFO_NEED_ONE[key] if need_one else Info.INFO[key]
	return (str(d.t) + " " + " ".join(d.b)).replace("[b]", "").replace("[/b]", "")

func icon_in_tree(key: String, auto := false) -> Control:
	var ic := Info.icon(key, auto)
	var root := (Engine.get_main_loop() as SceneTree).root
	root.add_child(ic)
	_made.append(ic)
	return ic

func _run() -> void:
	# ---- the explanations ----
	check("all 11 web keys are there, nothing else", Info.INFO.keys().size() == KEYS.size() and KEYS.all(func(k): return Info.INFO.has(k)), Info.INFO.keys())
	var bad := []
	for k: String in KEYS:
		var d: Dictionary = Info.INFO[k]
		var b: Array = d.get("b", [])
		if not d.get("t") is String or str(d.t).strip_edges() == "" or b.size() < 3 or not b.all(func(x): return x is String and (x as String).length() > 20):
			bad.append(k)
		for x: String in b:
			if x.count("[b]") != x.count("[/b]") or x.contains("<b>") or x.contains("</b>"):
				bad.append(k + ": " + x)
	check("each has a title and 3+ bullets, bold as balanced [b] bbcode", bad.is_empty(), bad)
	check("titles (Teams (2 v 2) renamed from Pair Mode)", Info.INFO.team.t == "Teams (2 v 2)" and Info.INFO.free.t == "Help your teammate" and Info.INFO.sl.t == "Snakes & Ladders rules" and Info.INFO.slEntry.t == "Entering the board" and Info.INFO.daily.t == "Daily reward")
	check("bubbles stay short (3 to 5 bullets)", KEYS.map(func(k): return (Info.INFO[k].b as Array).size()) == [3, 4, 4, 4, 4, 3, 4, 3, 3, 5, 4], KEYS.map(func(k): return (Info.INFO[k].b as Array).size()))
	var old_names := []
	for k: String in KEYS:
		var tx := text(k)
		if tx.contains("Pair Mode") or tx.contains("Free Hand") or tx.contains("partner") or tx.contains("token") or tx.contains("Single[/b] or"):
			old_names.append(k)
	check("no old names (Pair Mode, Free Hand, partner, token) or the Single / Pair step", old_names.is_empty(), old_names)
	check("the Need a 1 texts exist for both S&L keys", Info.INFO_NEED_ONE.keys().size() == 2 and Info.INFO_NEED_ONE.has("sl") and Info.INFO_NEED_ONE.has("slEntry"))

	# ---- pulse bookkeeping ----
	var st := use({})
	check("a new player: every key may pulse", KEYS.all(func(k): return Info.may(k) and not Info.is_read(k) and Info.showings(k) == 0))
	check("showing 1 counted", Info.count_showing("daily") and Info.showings("daily") == 1 and writes == 1)
	Info.count_showing("daily"); Info.count_showing("daily")
	check("3 showings: no more pulsing", Info.showings("daily") == 3 and not Info.may("daily"), st)
	check("a 4th showing is not counted or saved", not Info.count_showing("daily") and Info.showings("daily") == 3 and writes == 3, [st, writes])
	Info.mark_read("cam")
	check("reading stops the pulse for good", Info.is_read("cam") and not Info.may("cam") and st.cam == "open" and not Info.count_showing("cam"), st)
	var w := writes
	Info.mark_read("cam")
	check("reading twice saves once", writes == w)
	check("unknown keys are never counted", not Info.count_showing("nope") and not st.has("nope"))
	use({team = 2.0, pair = 3.0, sl = "open", cam = "junk", free = -4, ind = [1]})
	check("saved counts come back as floats (JSON) and still count", Info.showings("team") == 2 and Info.may("team") and not Info.may("pair"))
	check("junk or negative saved values count as unseen", Info.may("cam") and Info.showings("cam") == 0 and Info.showings("free") == 0 and Info.showings("ind") == 0)
	check("a saved 'open' is read", Info.is_read("sl") and not Info.may("sl"))

	if (Engine.get_main_loop() as SceneTree).root.is_inside_tree():
		_run_tree()
	else:   # SceneTree scripts get a live tree only after their first frame (run_tests.gd: await process_frame)
		print("test_info.gd: icon / bubble checks skipped: the scene tree is not live yet")
	_run_rules()

## Icons and the bubble in the live scene tree.
func _run_tree() -> void:
	var st: Dictionary
	# ---- nudge on real icons ----
	st = use({})
	var a := icon_in_tree("daily") as Info.InfoIcon
	var b := icon_in_tree("daily") as Info.InfoIcon
	var other := icon_in_tree("scenes") as Info.InfoIcon
	check("the dot is small, the tap target is 48 px", a.custom_minimum_size == Vector2(22, 22) and a._has_point(a.size / 2.0 + Vector2(0, 23)) and not a._has_point(a.size / 2.0 + Vector2(0, 25)))
	var small := Info.icon("cam", false, 18) as Info.InfoIcon
	_made.append(small)
	check("a small dot keeps the 48 px target", small._has_point(Vector2(9, 9) + Vector2(23, 0)))
	Info.nudge("daily")
	check("nudge pulses every visible icon of the key, counted once", a.pulsing and b.pulsing and not other.pulsing and Info.showings("daily") == 1, st)
	Info.nudge("daily")
	check("nudging while pulsing is the same showing", Info.showings("daily") == 1)
	Info.nudge("daily", false)
	check("nudge(key, false) stops them", not a.pulsing and not b.pulsing)
	a.visible = false
	b.visible = false
	Info.nudge("daily")
	check("hidden icons don't pulse and aren't counted", not a.pulsing and Info.showings("daily") == 1)
	a.visible = true
	b.visible = true
	Info.nudge("daily")
	a.visible = false            # the sheet hides: the pulse ends, the next showing counts afresh
	check("hiding an icon ends its pulse", not a.pulsing)
	a.visible = true
	Info.nudge("daily")
	check("…and a 3rd showing pulses", a.pulsing and Info.showings("daily") == 3, st)
	Info.nudge("daily", false)
	Info.nudge("daily")
	check("never a 4th", not a.pulsing and not b.pulsing and Info.showings("daily") == 3, st)
	Info.nudge("scenes", true, a)
	check("nudge(…, root) only touches icons under root", not other.pulsing and Info.showings("scenes") == 0)
	Info.nudge("scenes", true, other)
	check("…and pulses the ones under it", other.pulsing)

	# ---- the bubble ----
	Info.open(other)
	check("opening shows one bubble for that key", Info.is_open() and Info.open_key_now() == "scenes")
	check("opening reads the key and stops its pulse", Info.is_read("scenes") and not other.pulsing and st.scenes == "open", st)
	Info.nudge("scenes")
	check("a read key never pulses again", not other.pulsing)
	Info.open(a)
	check("another icon replaces the bubble (one at a time)", Info.open_key_now() == "daily" and _bubbles() == 1, _bubbles())
	Info.open(a)
	check("a second tap on the same icon closes it", not Info.is_open())
	Info.open(b)
	check("close() reports an open bubble", Info.close() and not Info.close())
	Info.open(b)
	b.visible = false
	check("the bubble closes when its icon leaves the screen (sheet closed)", not Info.is_open())
	b.visible = true
	Info.open(b)
	(Engine.get_main_loop() as SceneTree).root.remove_child(b)
	check("…or leaves the tree", not Info.is_open())
	(Engine.get_main_loop() as SceneTree).root.add_child(b)
	check("open_key finds a visible icon", Info.open_key("daily") and Info.open_key_now() == "daily")
	check("open_key is false when none is on screen", not Info.open_key("team"))
	Info.close()

## The texts restate the rules the game plays.
func _run_rules() -> void:
	var t: String
	var s: Dictionary
	t = text("pair")
	check("pair text: half the roll, even rolls, 4 moves 2", t.contains("half the roll") and t.contains("even rolls only") and t.contains("a 4 moves it 2 squares"))
	s = state([[10, 10, -1, -1], [-1, -1, -1, -1], [-1, -1, -1, -1], [-1, -1, -1, -1]], [{c = 0, a = 0, b = 1}])
	check("…a pair moves half of an even roll (dest)", Ludo.dest(s, 0, 0, 4) == 12 and Ludo.dest(s, 0, 0, 6) == 13)
	check("…and never on an odd roll", Ludo.dest(s, 0, 0, 3) == Ludo.NO_MOVE and Ludo.dest(s, 0, 0, 1) == Ludo.NO_MOVE)
	# an opponent single behind the pair: green token 2 squares before red's pair
	var g_before := prog(1, (Ludo.OFF[0] + 10 - 2 + 52) % 52)
	s = state([[10, 10, -1, -1], [g_before, -1, -1, -1], [-1, -1, -1, -1], [-1, -1, -1, -1]], [{c = 0, a = 0, b = 1}])
	check("pair text: singles can't jump a pair, they land on it (dest)", Ludo.dest(s, 1, 0, 3) == Ludo.NO_MOVE and Ludo.dest(s, 1, 0, 2) == g_before + 2)
	s.tok[1][0] = g_before + 2
	check("…then need exactly a 1 to move on", Ludo.dest(s, 1, 0, 1) == g_before + 3 and Ludo.dest(s, 1, 0, 2) == Ludo.NO_MOVE)
	check("pair/capture text: only a pair captures a pair, a pair never takes a single", text("pair").contains("Only a pair can capture a pair") and text("capture").contains("A pair never captures a single pawn"))
	s = state([[10, 10, 10, -1], [prog(1, 10), prog(1, 10), -1, -1], [prog(2, 14), -1, -1, -1], [-1, -1, -1, -1]], [{c = 0, a = 0, b = 1}, {c = 1, a = 0, b = 1}])
	check("…victims_at: a single never takes a pair", Ludo.victims_at(s, 0, 10, false).is_empty())
	check("…victims_at: a pair takes a pair", Ludo.victims_at(s, 0, 10, true).size() == 2)
	check("…victims_at: a pair never takes a single", Ludo.victims_at(s, 0, 14, true).is_empty() and Ludo.victims_at(s, 0, 14, false) == [[2, 0]])
	check("capture text: star and start squares are safe", text("capture").contains("Star squares and coloured start squares are safe")
		and Ludo.SAFE.has(Ludo.STARS[0]) and Ludo.SAFE.has(Ludo.OFF[1]))
	s = state([[8, -1, -1, -1], [prog(1, 8), -1, -1, -1], [-1, -1, -1, -1], [-1, -1, -1, -1]])
	check("…victims_at: nobody is captured on a star", Ludo.victims_at(s, 0, 8, false).is_empty())
	s = state([[5, 5, -1, -1], [-1, -1, -1, -1], [-1, -1, -1, -1], [-1, -1, -1, -1]])
	check("pair text: pairs form on a shared square (pair_partner)", Ludo.pair_partner(s, 0, 0) == 1)
	s = state([[13, 13, -1, -1], [-1, -1, -1, -1], [-1, -1, -1, -1], [-1, -1, -1, -1]])
	check("…but never on a start square", text("pair").contains("can’t form on a start square") and Ludo.pair_partner(s, 0, 0) == -1)
	check("team text: Red + Yellow vs Green + Blue", text("team").contains("Red + Yellow play against Green + Blue") and Ludo.mate_of(0) == 2 and Ludo.mate_of(1) == 3)
	s = state(base(), [], {teams = true})
	check("…partners never capture each other, the other team can be (foe)", not Ludo.foe(s, 0, 2) and Ludo.foe(s, 0, 1) and Ludo.foe(s, 0, 3))
	s = state([[56, 56, 56, 56], [-1, -1, -1, -1], [5, -1, -1, -1], [-1, -1, -1, -1]], [], {teams = true})
	check("free text: done needs a 6 first (waiting_six)", text("free").contains("you need a 6") and Ludo.waiting_six(s, 0) and Ludo.mover_of(s, 0) == 2)
	s.free[0] = true
	check("…then every roll moves the partner's pawns", not Ludo.waiting_six(s, 0) and Ludo.mover_of(s, 0) == 2 and text("free").contains("moves your teammate’s pawns"))
	s = state(base())
	check("ind text: no teams, anyone can be captured", text("ind").contains("no teams") and Ludo.foe(s, 0, 2) and Ludo.foe(s, 0, 1))

	t = text("sl") + " " + text("slEntry")
	check("sl texts (default): any roll enters", t.contains("Any roll moves your pawn onto the board") and t.contains("a 3 takes it to square 3") and not t.contains("Roll a 1"))
	check("…land(): any roll from off the board moves that many squares", [1, 2, 3, 5, 6].all(func(v): return SL.land(0, v).to == v and not SL.land(0, v).has("wait")) and SL.land(0, 4).to == SL.LADDERS[4])
	t = text("sl", true) + " " + text("slEntry", true)
	check("sl texts (Need a 1 to start): roll a 1 to enter", t.contains("Roll a 1 to enter the board") and t.contains("roll a 1 to step onto square 1"))
	check("…land(): only a 1 enters", SL.land(0, 1, true).to == 1 and [2, 3, 4, 5, 6].all(func(v): return SL.land(0, v, true).to == 0 and SL.land(0, v, true).has("wait")))
	var g := SL.new_game("local", 2, 0, {need_one = true})
	SL.apply_roll(g, 6)
	check("…a 6 off the board still rolls again", g.turn == 0 and g.players[0].pos == 0 and text("slEntry", true).contains("a 6 still gives you another roll"))
	var save: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Save")
	if save:
		var keep: bool = bool(save.prefs.get("sl_need_one", false))
		save.prefs.sl_need_one = false
		var off_ok := Info.entry("sl") == Info.INFO.sl and Info.entry("slEntry") == Info.INFO.slEntry
		save.prefs.sl_need_one = true
		var on_ok := Info.entry("sl") == Info.INFO_NEED_ONE.sl and Info.entry("slEntry") == Info.INFO_NEED_ONE.slEntry and Info.entry("team") == Info.INFO.team
		save.prefs.sl_need_one = keep
		check("entry() follows the Need a 1 to start house rule", off_ok and on_ok)
	g = SL.new_game("local", 2)
	g.players[0].pos = 10
	SL.apply_roll(g, 6); SL.apply_roll(g, 6)
	check("…three 6s in a row end the turn", g.turn == 0 and SL.apply_roll(g, 6).any(func(e): return e.type == "three_sixes") and g.turn == 1 and text("sl").contains("Three 6s in a row end your turn"))
	check("…the exact roll to 100, a bigger one stays put", SL.land(97, 6).to == 97 and SL.land(97, 6).has("over") and SL.land(97, 3).to == 100 and text("sl").contains("exact roll to land on 100"))
	var lad: int = SL.LADDERS.keys()[0]
	var sn: int = SL.SNAKES.keys()[0]
	check("…ladder feet climb, snake heads slide", SL.land(lad - 1, 1).to == SL.LADDERS[lad] and SL.land(sn - 1, 1).to == SL.SNAKES[sn])

	t = text("daily")
	check("daily text: 7 days, a missed day resets, owned items become coins", t.contains("Day 1 to Day 7") and t.contains("Miss a day") and t.contains("already own") and Rewards.cycle_rewards(0).size() == 7)
	var p := {coins = 0, dice_owned = ["classic"], daily = {cycle = 0, streak = 3, last = "2026-10-20"}}
	check("…next day continues the run", Rewards.daily_state(p, "2026-10-21").day == 4)
	check("…a missed day goes back to Day 1", Rewards.daily_state(p, "2026-10-23").day == 1)
	var dice_r := {"dice": "crema", "or": 400}
	check("…an owned dice is swapped for coins", Rewards.grant_of({dice_owned = ["classic", "crema"]}, dice_r).coins == 400 and Rewards.grant_of({dice_owned = ["classic"]}, dice_r).dice == "crema")
	t = text("scenes")
	check("scenes text: the free scenes are named, the others cost coins", t.contains("Jungle Clearing and Enchanted Jungle are free") and SLScenes.LIST[0].name == "Jungle Clearing"
		and SLScenes.LIST.all(func(x): return (x.price == 0) == SLScenes.FREE.has(x.id)))
	check("camera texts name both views (Settings: 3D / Top)", text("cam").contains("3D:") and text("cam").contains("Top:") and text("slcam").contains("Top:"))

func _bubbles() -> int:
	var n := 0
	for c in (Engine.get_main_loop() as SceneTree).root.get_children():
		if c is Info.Bubble and not c.closing:
			n += 1
	return n
