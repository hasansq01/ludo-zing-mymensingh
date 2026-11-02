extends "res://tests/test_suite.gd"
## A pair and a single pawn of yours on one square (LudoMatch.units_sharing, _ask_unit): the tap there can't tell
## them apart, so "Which one moves?" asks, the same inline prompt as "Join these two pawns?" (LudoHUD.ask_two), with
## how far each goes; each answer moves that one; a tap elsewhere on the board closes it without a move; an odd roll
## (the pair can't move) or two singles on one square ask nothing. Nothing here writes user://save.json: Save plays
## on copies of the profile and prefs with its debounced write cut, then gets the originals back.

const Live := preload("res://tests/test_reroll.gd")   # (its LiveApp: the parts of main a live match needs)
const SQ := 20                                        # Red's progress 20: a plain track square (no star, no start)

var _sp := {}
var _spf := {}

func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree

func run() -> void:
	_sandbox()
	_rules()
	var app = Live.LiveApp.new()
	_tree().root.add_child(app)
	app.build()
	await _ask_and_move(app, 0, "Move one pawn")
	await _ask_and_move(app, 1, "Move the pair")
	await _tap_elsewhere(app)
	await _no_question(app)
	app.ludo.stop()
	app.queue_free()
	await _frames(2)
	_restore()

func _sandbox() -> void:
	_sp = Save.profile
	_spf = Save.prefs
	Save.profile = _sp.duplicate(true)
	Save.prefs = _spf.duplicate(true)
	if Save._timer.timeout.is_connected(Save.flush):
		Save._timer.timeout.disconnect(Save.flush)

func _restore() -> void:
	Save._dirty = false
	Save.profile = _sp
	Save.prefs = _spf
	if not Save._timer.timeout.is_connected(Save.flush):
		Save._timer.timeout.connect(Save.flush)

func _frames(n: int) -> void:
	for k in n:
		await _tree().process_frame

func _until(f: Callable, secs := 6.0) -> bool:
	var t0 := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - t0) / 1000.0 < secs:
		if f.call():
			return true
		await _tree().process_frame
	return bool(f.call())

## A state on your move: Red's pair (pawns 0 + 1) and Red's pawn 2 on SQ, rolled `dice`.
func _state(dice: int, paired := true) -> Dictionary:
	var s := Ludo.new_game(["human", "cpu", "off", "off"])
	s.tok[0] = [SQ, SQ, SQ, -1]
	s.pairs = [{c = 0, a = 0, b = 1}] if paired else []
	s.dice = dice
	s.phase = "choose"
	s.turn = 0
	return s


func _rules() -> void:
	var s := _state(4)
	var u := Ludo.unit_for_token(s, 2)
	var both := LudoMatch.units_sharing(s, u)
	check("units_sharing: the single on the pair's square -> {pair, single}", not both.is_empty() and both.pair.pair == true \
		and both.single.token == 2 and both.pair.to == SQ + 2 and both.single.to == SQ + 4, both)
	check("units_sharing: the same, tapped on the pair", LudoMatch.units_sharing(s, Ludo.unit_for_token(s, 0)).single.token == 2)
	s = _state(3)
	check("units_sharing: odd roll (the pair can't move) -> {}", LudoMatch.units_sharing(s, Ludo.unit_for_token(s, 2)).is_empty())
	s = _state(4, false)
	check("units_sharing: two (three) singles on one square move the same -> {}", LudoMatch.units_sharing(s, Ludo.unit_for_token(s, 2)).is_empty())


## Opens a match, lays out _state(4), lets the board glow, then taps the square.
func _ready_match(app: Node, s: Dictionary) -> LudoMatch:
	var L: LudoMatch = app.ludo
	await L.start(["human", "cpu", "off", "off"], false, {pair_ask = false})
	await _until(func(): return not L._busy)
	L.S = s
	L.board.relayout(s)
	L.hud.update(s, 0)
	L._choose(L._id, 0)
	await _frames(2)
	return L

func _tap_square(L: LudoMatch) -> void:
	var at := L.world.camera.unproject_position(L.board.pawn_target(2))
	await _until(func(): return L.board.pick(L.world.camera, at) >= 0, 3.0)   # (the pawns glide to the laid-out squares)
	L.tap(at)
	await _frames(1)

func _ask_and_move(app: Node, answer: int, label: String) -> void:
	var L := await _ready_match(app, _state(4))
	check("%s: all three pawns glow" % label, L.board.movable.has(0) and L.board.movable.has(1) and L.board.movable.has(2), L.board.movable)
	await _tap_square(L)
	var up: bool = L.hud.pair_box.visible and L._unit_ask
	var at := L.world.camera.unproject_position(L.board.pawn_target(2))
	check("%s: the tap asks which one moves (nothing moved yet)" % label, up and L.S.tok[0] == [SQ, SQ, SQ, -1], [up, L.S.tok[0],
		L.board.pick(L.world.camera, at), app.paused, L._sheet_open(), L._busy, L.S.phase])
	check("%s: the question and how far each goes" % label, L.hud._pair_cap.text == "Which one moves?" \
		and L.hud.pair_yes.text == "Move the pair (2)" and L.hud.pair_no.text == "Move one pawn (4)",
		[L.hud._pair_cap.text, L.hud.pair_yes.text, L.hud.pair_no.text])
	L.hud._answer(answer == 1)
	await _frames(1)
	var want: Array = [SQ + 2, SQ + 2, SQ, -1] if answer == 1 else [SQ, SQ, SQ + 4, -1]
	check("%s: that one moves" % label, L.S.tok[0] == want and not L.hud.pair_box.visible and not L._unit_ask, [L.S.tok[0], want])
	await _until(func(): return L.S.turn == 0 and not L._busy or L.S.phase == "over", 3.0)

func _tap_elsewhere(app: Node) -> void:
	var L := await _ready_match(app, _state(4))
	await _tap_square(L)
	var up: bool = L.hud.pair_box.visible
	L.tap(Vector2(4, 4))                               # a corner: no pawn there
	await _frames(1)
	check("a tap elsewhere while asking: closes it, nothing moves", up and not L.hud.pair_box.visible and not L._unit_ask \
		and L.S.tok[0] == [SQ, SQ, SQ, -1] and L.S.phase == "choose", [up, L.S.tok[0], L.S.phase])
	L.hud._answer(true)                                # (a late click on the closed box: nothing)
	await _frames(1)
	check("…and a late answer does nothing", L.S.tok[0] == [SQ, SQ, SQ, -1])
	await _tap_square(L)
	check("…tapping the square again asks again", L.hud.pair_box.visible and L._unit_ask)
	L.hud._answer(false)
	await _frames(1)
	check("…and that answer moves", L.S.tok[0] == [SQ, SQ, SQ + 4, -1], L.S.tok[0])

func _no_question(app: Node) -> void:
	var L := await _ready_match(app, _state(4, false))
	await _tap_square(L)                               # (every choice is the same move: it goes by itself anyway)
	var asked: bool = L.hud.pair_box.visible
	var moved := await _until(func(): return L.S.tok[0].count(SQ + 4) == 1, 3.0)
	check("three singles on one square: no question, one of them moves 4", not asked and moved \
		and L.S.tok[0].count(SQ) == 2, [asked, L.S.tok[0]])
	var yes := [null]
	var L2 := await _ready_match(app, _state(4))
	L2.hud.cancel_pair()                               # (nothing open: harmless)
	(func(): yes[0] = await L2.hud.ask_pair()).call()
	await _frames(1)
	check("the pair question still reads as before", L2.hud._pair_cap.text == "Join these two pawns?" \
		and L2.hud.pair_yes.text == "Pair up" and L2.hud.pair_no.text == "Keep single")
	L2.hud._answer(true)
	await _frames(1)
	check("…and answers as before", yes[0] == true)
