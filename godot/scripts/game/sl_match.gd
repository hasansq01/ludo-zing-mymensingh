class_name SLMatch
extends Node
## Runs one Snakes & Ladders game in its 3D scene world (index.html SL module: begin, roll, again, next, win) with
## its own HUD: the GameTopBar (pause, the one-line event line, gear), a row of compact player tiles (avatar,
## name, square; the rules ⓘ sits in the corner of your own tile), the board between them and the dice, and the dice centred at the bottom on a pad in the colour of
## the player whose turn it is (Dice3D.set_turn: the die glows in that colour; in Pass & Play a name pill under it
## says whose turn it is). After 4 s of waiting on your turn the die's hand pointer taps it and the pad pulses.
## A tap during a computer's turn fast-forwards it (and the computer turns after it, until yours comes).
##
## finished(result) carries ResultScreen-ready data:
##   {game = "sl", title, sub, standings = [{color, name, kind, cpu_id, place, finished, pos, progress}],
##    human_won, reward, vs_cpu, color}
## The live game is kept in MatchStore ("sl") after every turn and when the app goes to the background (main calls
## save_match()), and cleared when it ends:
## {game = "sl", cfg = the setup, G = the rules state}; resume() takes that (or a bare rules state).

signal finished(result: Dictionary)
signal pause_pressed
signal settings_pressed

const CPU_ROLL_WAIT := 0.35              # a computer's turn starts, then it rolls
const CPU_AFTER_WAIT := 0.25             # after a computer's move, before the next turn
const HUMAN_AFTER_WAIT := 0.3            # after your move
const HOLD_WAIT := 0.9                   # a roll that can't move (three 6s, need a 1, overshoot): read it
const SPECIAL_WAIT := 0.35               # after a ladder or a snake
const DICE_PX := 96.0                    # the control; the resting die itself is ~74 % of it (71 px)
const FF := 0.3                          # speed factor while a tap fast-forwards computer turns
const TILE_GAP := 8.0

var app: Node
var world: TableWorld
var board: SLBoard
var scenes: SLScenes                     # the scene world the match is played in (camera framing)
var hud: Control
var top: GameTopBar
var bar: GameTopBar                      # the same bar, under the name main.gd looks for (hide_for_result / show_bar)
var dice: Dice3D
var dice_pad: DicePad
var chips: HBoxContainer                 # the player tiles row (SLTile)
var _info: Control
var _pops: Control
var G := {}
var setup := {}
var rng := RandomNumberGenerator.new()
var autoplay := false
var _id := 0
var _busy := false
var _again := false                      # the last roll was a 6: the same player rolls again
var _ff := false                         # fast-forwarding computer turns
var _waiting := false                    # a human may roll now

func _init(app_: Node, world_: TableWorld, board_: SLBoard) -> void:
	app = app_
	world = world_
	board = board_

func _ready() -> void:
	rng.randomize()
	set_process(false)


# =====================================================================================================================
# HUD
# =====================================================================================================================

## The HUD lives in the app's UI root; built once.
func build_hud(parent: Control) -> Control:
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(hud)
	chips = HBoxContainer.new()
	chips.add_theme_constant_override("separation", int(TILE_GAP))
	chips.alignment = BoxContainer.ALIGNMENT_CENTER
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(chips)
	dice_pad = DicePad.new()
	hud.add_child(dice_pad)
	dice = Dice3D.new()
	dice.custom_minimum_size = Vector2(DICE_PX, DICE_PX)
	dice.size = Vector2(DICE_PX, DICE_PX)
	dice.pressed.connect(_on_dice)
	hud.add_child(dice)
	_pops = Control.new()
	_pops.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pops.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_pops)
	top = GameTopBar.new("pause")
	top.name = "TopBar"
	top.left_pressed.connect(func(): pause_pressed.emit())
	top.gear_pressed.connect(func(): settings_pressed.emit())
	hud.add_child(top)
	bar = top
	# the event bar keeps the height of its first (narrow) layout: shrink it back whenever its text reflows
	top.bar.minimum_size_changed.connect((func(): if is_instance_valid(top): top.bar.size = Vector2(top.bar.size.x, 0)).call_deferred)
	_info = Info.icon("sl", false, 18)
	hud.resized.connect(_layout)
	return hud

func _layout() -> void:
	if hud == null:
		return
	var w := hud.size.x
	var h := hud.size.y
	var safe_top: float = app.safe_top if app else 0.0
	var safe_bottom: float = app.safe_bottom if app else 0.0
	top.safe_top = safe_top
	# the tiles: equal widths between the 16 px gutters
	var g: float = UIKit.SCREEN_GUTTER
	var n := chips.get_child_count()
	var tw := floorf((w - 2.0 * g - TILE_GAP * maxf(n - 1, 0)) / maxf(n, 1)) if n > 0 else 0.0
	tw = minf(tw, 112.0)
	var short := not SLTile.fits_long(tw)       # one format for the whole row: "Square 47" or "Sq 47" on every tile
	for c in chips.get_children():
		(c as SLTile).short = short
		(c as SLTile).set_width(tw)
	var row_w := tw * n + TILE_GAP * maxf(n - 1, 0)
	var tile_y := top.bottom() + UIKit.SPACE.sm + 2.0
	chips.size = Vector2(row_w, SLTile.H)
	chips.position = Vector2(round((w - row_w) / 2.0), tile_y)
	# the dice, centred at the bottom on its pad
	var dy := h - safe_bottom - DICE_PX - 30.0
	dice.position = Vector2(round((w - DICE_PX) / 2.0), dy)
	var pad := DICE_PX + 4.0
	dice_pad.size = Vector2(pad, pad)
	dice_pad.position = dice.position - Vector2(2, 2)
	dice_pad.pivot_offset = dice_pad.size / 2.0
	if scenes:                                # the board fills the width between the tiles and the dice
		var btop := tile_y + SLTile.H + 14.0
		var bbottom := dy - 18.0
		var bw := w * SLScenes.PLAY_FILL
		scenes.set_board_box(Rect2((w - bw) / 2.0, btop, bw, maxf(bbottom - btop, bw * 0.6)))

## The tiles are built for each game (their avatars and names).
func _build_tiles() -> void:
	if _info and _info.get_parent():
		_info.get_parent().remove_child(_info)
	for ch in chips.get_children():
		chips.remove_child(ch)
		ch.queue_free()
	var own := -1
	for k in G.players.size():
		var p: Dictionary = G.players[k]
		var kind := "you" if p.you else ("cpu" if p.cpu else "human")
		chips.add_child(SLTile.new(int(p.c), str(p.name), kind, str(p.name).to_lower() if p.cpu else ""))
		if own < 0 and (p.you or not p.cpu):
			own = k
	if _info and own >= 0:                   # the rules ⓘ: in the corner of your tile (Pass & Play: the first)
		(chips.get_child(own) as SLTile).set_corner(_info)

func _refresh_tiles() -> void:
	for k in mini(G.players.size(), chips.get_child_count()):
		var p: Dictionary = G.players[k]
		var t: SLTile = chips.get_child(k)
		var pos := int(p.pos)
		t.set_state(k == G.turn and G.phase != "over", false, -1, clampf(pos / 100.0, 0.0, 1.0))
		t.set_square(pos)

## The dice in the turn's colour: the pad and the die's glow; can_tap: you may roll now (pulse, then the hand hint).
## Pass & Play: the name pill under the die says whose turn it is (the phone goes round the table).
func _set_dice_turn(p: Dictionary, can_tap: bool) -> void:
	var c := int(p.c)
	dice_pad.set_color(c, can_tap)
	if can_tap and not dice.active and not dice.rolling:
		dice.show_ready()                     # a neutral pose while waiting, not the last roll's face
	var who := "%s’s turn" % p.name if G.get("mode", "cpu") == "local" else ""
	dice.set_turn(Palette.PLAYER[c], can_tap, who, PlayerTile.name_color(c))
	_waiting = can_tap
	set_process(true)

func _process(_delta: float) -> void:
	dice_pad.hint = _waiting and dice.hinting()


# =====================================================================================================================
# Input
# =====================================================================================================================

func _on_dice() -> void:
	if G.is_empty() or G.phase != "roll":
		return
	if _cpu_turn():
		_ff = true                            # a tap on a computer's turn: hurry it along
		return
	if _busy or autoplay or app.paused or app._top_sheet() != null:
		return
	roll()

## A tap anywhere during a computer's turn fast-forwards it.
func _unhandled_input(e: InputEvent) -> void:
	if hud == null or not hud.is_visible_in_tree() or G.is_empty() or G.phase == "over":
		return
	var press: bool = (e is InputEventScreenTouch and e.pressed) or (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT)
	if press and _cpu_turn() and not app.paused and app._top_sheet() == null:
		_ff = true

func _cpu_turn() -> bool:
	return not G.is_empty() and bool(G.players[G.turn].cpu)


# =====================================================================================================================
# Flow
# =====================================================================================================================

func live(id: int) -> bool:
	return id == _id and not G.is_empty() and is_inside_tree()

## The animation speed now: the Settings speed, faster while fast-forwarding a computer's turn.
func _spd() -> float:
	return float(app.speed) * (FF if _ff else 1.0)

## Waits sec x speed, paused while the app is; a fast-forward tap shortens what is left.
func wait(sec: float) -> void:
	var left := sec
	while left > 0.0 and is_inside_tree():
		await get_tree().process_frame
		if not app.paused:
			left -= get_process_delta_time() / maxf(_spd(), 0.01)

## "You" or the player's bold name (tinted by GameTopBar with the turn's colour).
func _who(p: Dictionary) -> String:
	return "You" if p.you else "[b]%s[/b]" % p.name

func _human(p: Dictionary) -> bool:
	return not p.cpu and not autoplay

func start(cfg: Dictionary) -> void:
	setup = cfg.duplicate()
	G = SnakesLaddersRules.new_game(str(cfg.get("mode", "cpu")), int(cfg.get("n", 2)), int(cfg.get("color", 0)),
		{need_one = _need_one_pref()})
	var nm: Variant = cfg.get("names")                   # Pass & Play: the names typed in setup, by colour
	if str(cfg.get("mode", "cpu")) == "local" and nm is Array and (nm as Array).size() == 4:
		for p in G.players:
			if not p.cpu and str(nm[p.c]) != "":
				p.name = str(nm[p.c])
	await _open()

## Continue a saved game: MatchStore.load() as save_match() stored it ({game, cfg, G}) or a bare rules state.
func resume(state: Dictionary) -> void:
	var g: Variant = state.get("G", state)
	if not g is Dictionary or not (g as Dictionary).has("players"):
		push_warning("SLMatch.resume: no game in %s" % [state.keys()])
		return
	G = _normalized(g)
	var cfg: Variant = state.get("cfg", {})
	setup = cfg if cfg is Dictionary and not (cfg as Dictionary).is_empty() else {game = "sl", mode = G.mode, n = G.players.size(), color = int(G.players[0].c)}
	if G.phase != "roll":
		G.phase = "roll"
	await _open()

func _open() -> void:
	_id += 1
	_busy = false
	_again = false
	_ff = false
	var cols := []
	for p in G.players:
		cols.append(int(p.c))
	board.setup_players(cols)
	board.place(_positions())
	if scenes:
		scenes.play(true, Save.prefs.sl_cam)
	top.show_bar()
	top.clear()
	_build_tiles()
	_refresh_tiles()
	_layout()
	await get_tree().process_frame
	_layout()
	if scenes:
		scenes.snap_camera()
	Info.nudge("sl", true, hud)
	_begin()

func stop() -> void:
	_id += 1
	G = {}
	_waiting = false
	_ff = false
	_busy = false
	board.set_current(-1)
	if dice:
		dice.set_turn(dice.tint, false)
	if top:
		top.clear()
	set_process(false)

func _positions() -> Array:
	var out := []
	for p in G.players:
		out.append(int(p.pos))
	return out

func _begin() -> void:
	var id := _id
	var p: Dictionary = G.players[G.turn]
	board.set_current(G.turn)
	top.set_turn(int(p.c))
	_refresh_tiles()
	if not p.cpu:
		_ff = false
	if p.cpu or autoplay:
		top.set_idle("%s is rolling…" % _who(p) if not p.you else "Rolling…")
		_set_dice_turn(p, false)
		await wait(CPU_ROLL_WAIT)
		if live(id) and G.phase == "roll":
			roll()
	else:
		top.set_idle("Your turn" if p.you else "%s’s turn" % _who(p))
		_set_dice_turn(p, true)
		if TapLog.enabled():
			(func(): TapLog.point(dice)).call_deferred()

func roll(forced := 0) -> void:
	if G.is_empty() or G.phase != "roll" or _busy or app.paused:
		return
	var id := _id
	_busy = true
	var p: Dictionary = G.players[G.turn]
	var pi: int = G.turn
	var soft: bool = p.cpu
	_set_dice_turn(p, false)
	dice_pad.rolling = true
	var v := forced if forced > 0 else rng.randi_range(1, 6)
	var sp := _spd()
	var dur := 0.75 * maxf(sp, 0.05)
	Sound.sfx("roll", {dur = dur, soft = soft})
	if _human(p):                             # the dice-land haptic at its first table hit (Sound.IMPACT_AT)
		get_tree().create_timer(dur * Sound.IMPACT_AT).timeout.connect(func():
			if live(id):
				Haptics.light())
	await dice.roll(v, sp)
	dice_pad.rolling = false
	if not live(id):
		return
	Sound.sfx("land", {soft = soft})          # skipped when the scheduled landing already played
	var ev := SnakesLaddersRules.apply_roll(G, v)
	for e in ev:
		match e.type:
			"three_sixes":
				top.say("%s rolled three 6s. Turn over." % _who(p), HOLD_WAIT + 0.6, "event")
				Sound.sfx("error", {soft = soft})
				await wait(HOLD_WAIT)
			"wait":
				if p.you:
					top.say("You rolled a %d. You need a 1 to start." % v, 1.6)
				else:
					top.say("%s rolled a %d and needs a 1 to start." % [_who(p), v], 1.6)
				await wait(HOLD_WAIT)
			"over":
				if p.you:
					top.say("You rolled a %d. You need exactly %d to finish." % [v, e.need], 1.8)
				else:
					top.say("%s rolled a %d and needs exactly %d to finish." % [_who(p), v, e.need], 1.8)
				await wait(HOLD_WAIT)
			"move":
				await _walk(id, p, pi, e, v)
				if not live(id):
					return
			"win":
				_busy = false
				_win(p)
				return
			"turn":
				_again = e.again
				if e.again:
					if p.you:
						top.say("You rolled a 6. Roll again!", 1.6, "event")
					else:
						top.say("%s rolled a 6 and rolls again." % _who(p), 1.6, "event")
					Sound.sfx("six", {soft = soft})
					_pop("Roll again!", board.pawn_top(pi), Palette.HONEY, 26)
				_save()
				await wait(CPU_AFTER_WAIT if p.cpu else HUMAN_AFTER_WAIT)
				_busy = false
				if live(id):
					_begin()
				return
		if not live(id):
			return
	_busy = false

## The pawn hops square by square, then rides a ladder or a snake.
func _walk(id: int, p: Dictionary, pi: int, e: Dictionary, v: int) -> void:
	var soft: bool = p.cpu
	top.say(("You rolled a %d." if p.you else "%s rolled a %d.") % ([v] if p.you else [_who(p), v]), 1.2 if int(e.from) > 0 else 1.4)
	var sq: int = int(e.from)
	for k in int(e.steps):
		while app.paused and live(id):
			await get_tree().process_frame
		sq += 1
		await board.hop_to(pi, sq, _spd())
		Sound.sfx("step", {soft = soft})
		if pi < chips.get_child_count():
			(chips.get_child(pi) as SLTile).set_square(sq)
		if not live(id):
			return
	if e.ladder:
		if p.you:
			top.say("Ladder! You climbed to %d." % e.to, 1.8, "event")
		else:
			top.say("Ladder! %s climbed to %d." % [_who(p), e.to], 1.8, "event")
		Sound.sfx("ladder", {soft = soft})
		if _human(p):
			Haptics.success()
		_pop("Up to %d!" % e.to, board.pawn_top(pi), Palette.GOLD_HI, 30)
		await board.climb(pi, e.via, e.to, _spd())
	elif e.snake:
		if p.you:
			top.say("Snake! You slid down to %d." % e.to, 1.8, "event")
		else:
			top.say("Snake! %s slid down to %d." % [_who(p), e.to], 1.8, "event")
		Sound.sfx("snake", {soft = soft})
		if _human(p):
			Haptics.medium()
		_pop("Down to %d" % e.to, board.pawn_top(pi), Palette.CORAL, 30)
		await board.slide(pi, e.via, e.to, _spd())
	if not live(id):
		return
	board.place(_positions())
	_refresh_tiles()
	if e.ladder or e.snake:
		await wait(SPECIAL_WAIT)

func _win(p: Dictionary) -> void:
	var id := _id
	_waiting = false
	dice.set_turn(dice.tint, false)
	board.set_current(-1)
	_refresh_tiles()
	top.set_idle("")
	top.say("You reached 100!" if p.you else "%s reached 100!" % _who(p), 2.0, "event")
	Sound.sfx("lose" if p.cpu else "win")
	if _human(p):
		Haptics.success()
	_pop("100!", board.pawn_top(G.winner), Palette.GOLD_HI, 36)
	var reward := SnakesLaddersRules.claim_win_reward(G)
	var won_paid := reward > 0
	if not won_paid:
		reward = SnakesLaddersRules.claim_play_reward(G)   # you lost vs the computer: a small participation reward
	print("[sl] game over: winner %s reward=%d" % [p.name, reward])
	Save.record_sl(won_paid)                  # a win counts only when the replay check paid out, as on the web
	if reward > 0:
		Save.add_coins(reward)
	_clear_store()
	await wait(0.9)
	if not live(id):
		return
	var result := result_data(reward)
	top.hide_for_result()
	finished.emit(result)

## The finished game for ResultScreen (and the log).
func result_data(reward := 0) -> Dictionary:
	var rows := []
	for s: Dictionary in SnakesLaddersRules.standings(G):
		var p: Dictionary = G.players[int(s.idx)]
		rows.append({color = int(s.color), name = str(s.name), kind = "you" if p.you else ("cpu" if p.cpu else "human"),
			cpu_id = str(p.name).to_lower() if p.cpu else "", place = int(s.place), finished = bool(s.finished),
			pos = int(s.pos), progress = float(s.progress)})
	var w: Dictionary = G.players[int(G.winner)] if int(G.winner) >= 0 else {}
	var won := not w.is_empty() and not bool(w.cpu)
	var title := "Game over"
	var sub := ""
	var me: Dictionary = {}
	for r: Dictionary in rows:
		if r.kind == "you":
			me = r
	if not w.is_empty():                      # headlined from your side: "You finished 2nd" / "Mocha won"
		if w.you or me.is_empty():
			title = "You win!" if w.you else "%s wins!" % w.name
			sub = "First to square 100!"
		else:
			title = "You finished %s" % ResultScreen.ordinal(maxi(int(me.place), 2))
			sub = "%s won · you reached square %d" % [w.name, int(me.pos)] if int(me.pos) > 0 else "%s won" % w.name
	return {game = "sl", title = title, sub = sub, standings = rows, human_won = won,
		reward = reward,
		vs_cpu = G.mode == "cpu", color = int(w.get("c", 0))}


# =====================================================================================================================
# Pops over the board
# =====================================================================================================================

## A big word that pops up over a pawn and floats away ("Up to 84!", "Down to 6", "Roll again!").
func _pop(text: String, at: Vector3, col: Color, fs: int) -> void:
	if _pops == null or scenes == null or scenes.camera == null:
		return
	var cam := scenes.camera
	if cam.is_position_behind(at):
		return
	var sp := cam.unproject_position(at)
	var l := UIKit.label(text, fs, col, UIKit.font_display(), HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_color_override("font_outline_color", Palette.INK_DEEP)
	l.add_theme_constant_override("outline_size", maxi(6, fs / 4))
	l.add_theme_color_override("font_shadow_color", Palette.shadow(0.35))
	l.add_theme_constant_override("shadow_offset_y", 3)
	_pops.add_child(l)
	l.size = l.get_combined_minimum_size()
	var w := hud.size.x
	var x := clampf(sp.x - l.size.x / 2.0, 12.0, w - 12.0 - l.size.x)
	l.position = Vector2(x, sp.y - l.size.y - 18.0)
	l.pivot_offset = l.size / 2.0
	var reduce := bool(Save.prefs.get("reduce_motion", false))
	var tw := l.create_tween()
	if reduce:
		l.modulate.a = 0.0
		tw.tween_property(l, "modulate:a", 1.0, 0.12)
		tw.tween_interval(0.8)
	else:
		l.scale = Vector2(0.4, 0.4)
		tw.tween_property(l, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(l, "position:y", l.position.y - 26.0, 1.0).set_ease(Tween.EASE_OUT)
		tw.tween_interval(0.35)
	tw.tween_property(l, "modulate:a", 0.0, 0.3)
	tw.tween_callback(l.queue_free)


# =====================================================================================================================
# Saving (MatchStore) and prefs
# =====================================================================================================================

func _need_one_pref() -> bool:
	return bool(Save.prefs.get("sl_need_one", true))

## Keeps the live game in MatchStore (after every turn; main also calls it when the app goes to the background,
## loses focus or Back is pressed). A finished game, autoplay and dev previews (MatchStore.enabled off) keep nothing.
func save_match() -> void:
	if autoplay or G.is_empty() or G.phase == "over":
		return
	MatchStore.save("sl", {game = "sl", cfg = setup.duplicate(true), G = G.duplicate(true)}, summary())

## The Continue card's line: "Snakes & Ladders vs Computer · Square 47" / "Snakes & Ladders · Pass & Play".
func summary() -> String:
	var title := "Snakes & Ladders vs Computer" if G.mode == "cpu" else "Snakes & Ladders · Pass & Play"
	for p in G.players:
		if p.you:
			return title + " · " + ("Off the board" if int(p.pos) == 0 else "Square %d" % int(p.pos))
	return title

func _save() -> void:
	save_match()

func _clear_store() -> void:
	if not autoplay:
		MatchStore.clear("sl")

## A saved state back to the rules' types (JSON turns ints into floats).
static func _normalized(state: Dictionary) -> Dictionary:
	var g := state.duplicate(true)
	for k in ["turn", "sixes", "winner"]:
		g[k] = int(g.get(k, 0 if k != "winner" else -1))
	g.mode = str(g.get("mode", "cpu"))
	g.phase = str(g.get("phase", "roll"))
	g.paid = bool(g.get("paid", false))
	g.need_one = bool(g.get("need_one", false))
	var players := []
	for p in g.get("players", []):
		var q: Dictionary = (p as Dictionary).duplicate(true)
		q.c = int(q.get("c", 0))
		q.pos = int(q.get("pos", 0))
		q.you = bool(q.get("you", false))
		q.cpu = bool(q.get("cpu", false))
		q.ladders = int(q.get("ladders", 0))
		q.snakes = int(q.get("snakes", 0))
		var rolls := []
		for r in q.get("rolls", []):
			rolls.append(int(r))
		q.rolls = rolls
		players.append(q)
	g.players = players
	return g


# =====================================================================================================================
# Pieces
# =====================================================================================================================

## A compact player tile ("PlayerTile lite"): the avatar (your equipped one, the café mascots, or the pawn tile in
## Pass & Play), the name and the square ("Off board", "Square 47"; the row picks one format for every tile:
## `short` = "Sq 47" when "Square 100" doesn't fit the tile). Framed in the player's colour (lighter while waiting).
## Your turn: the full-colour ring, a soft glow, a little lift and a pointer under it. Same calls as PlayerTile:
## set_state(active, mover, home, pct), set_note(text). set_corner(c): a small control (the rules ⓘ) in its top
## right corner.
class SLTile extends Control:
	const H := 92.0
	const AVA := 38.0
	const NAME_Y := 47.0
	const NAME_H := 20.0
	const NOTE_H := 18.0
	const OFF_BOARD := "Off board"
	var color_index := 0
	var kind := "cpu"
	var active := false
	var square := 0
	var short := false                   ## "Sq 47" instead of "Square 47" (set by the row, the same for every tile)
	var corner: Control
	var _ava: Control
	var _name: Label
	var _note: Label
	var _note_pill: PanelContainer
	var _sb: StyleBoxFlat
	var _sb_on: StyleBoxFlat
	var _sb_glow: StyleBoxFlat
	var _tw: Tween
	var _t := 0.0

	func _init(c: int, name_: String, kind_: String, cpu_id := "") -> void:
		color_index = posmod(c, 4)
		kind = kind_
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(84, H)
		var col: Color = Palette.PLAYER[color_index]
		_sb = UIKit.box(Palette.GLASS, UIKit.R.md + 2, UIKit.BW.line, PlayerTile.frame_color(color_index, false))
		_sb.border_width_bottom = UIKit.LIP.sm + 1
		UIKit.shade(_sb, "sm")
		_sb_on = _sb.duplicate()
		_sb_on.bg_color = Palette.CARD
		_sb_on.set_border_width_all(UIKit.BW.rim)
		_sb_on.border_width_bottom = UIKit.LIP.sm + 2
		_sb_on.border_color = col
		_sb_glow = StyleBoxFlat.new()
		_sb_glow.bg_color = Color(col, 0.0)
		_sb_glow.set_corner_radius_all(UIKit.R.md + 6)
		_sb_glow.shadow_color = Color(col.lightened(0.1), 0.6)
		_sb_glow.shadow_size = 12
		_ava = PlayerTile.make_avatar(color_index, kind, AVA, cpu_id if cpu_id != "" else name_)
		add_child(_ava)
		_name = UIKit.label(name_, UIKit.FS.label, Palette.INK_STRONG, UIKit.font_body(900), HORIZONTAL_ALIGNMENT_CENTER)
		_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_child(_name)
		_note = UIKit.label(OFF_BOARD, UIKit.FS.small, PlayerTile.name_color(color_index), UIKit.font_body(900, true), HORIZONTAL_ALIGNMENT_CENTER)
		_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_note_pill = PanelContainer.new()
		var st := UIKit.box((Palette.TINT[color_index] as Color).lerp(Color.WHITE, 0.55), UIKit.R.pill, 0, Color.TRANSPARENT)
		UIKit.pad(st, 7, 0)
		_note_pill.add_theme_stylebox_override("panel", st)
		_note_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_note_pill.add_child(_note)
		add_child(_note_pill)
		resized.connect(_layout)
		set_process(false)

	func set_width(w: float) -> void:
		custom_minimum_size = Vector2(w, H)
		size = custom_minimum_size
		_layout()

	func set_state(active_: bool, _mover := false, _home := -1, _pct := 0.0, _chip := "") -> void:
		if active_ != active or _tw == null:
			active = active_
			_animate()
		set_process(active and not PlayerTile._pref("reduce_motion"))
		queue_redraw()

	## The square shown on the tile (0 = still waiting: "Off board").
	func set_square(n: int) -> void:
		square = n
		set_note(square_text(n, short))

	func set_note(t: String) -> void:
		_note.text = t
		_layout()

	## A small control in the top-right corner (the rules ⓘ on your own tile).
	func set_corner(c: Control) -> void:
		corner = c
		if c.get_parent() != self:
			if c.get_parent():
				c.get_parent().remove_child(c)
			add_child(c)
		_layout()

	## "Square 47" / "Sq 47"; 0 = "Off board".
	static func square_text(n: int, short_ := false) -> String:
		if n <= 0:
			return OFF_BOARD
		return ("Sq %d" if short_ else "Square %d") % n

	## The long form fits a tile `w` px wide (its widest case, "Square 100"), so the row can use it everywhere.
	static func fits_long(w: float) -> bool:
		var f := UIKit.font_body(900, true)
		return f.get_string_size("Square 100", HORIZONTAL_ALIGNMENT_LEFT, -1, UIKit.FS.small).x <= w - 2.0 * 6.0 - 14.0

	func _layout() -> void:
		var w := size.x
		var f := UIKit.font_body(900)
		var fs: int = UIKit.FS.label
		while fs > UIKit.FS.small and f.get_string_size(_name.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > w - 14.0:
			fs -= 1
		_name.add_theme_font_size_override("font_size", fs)
		_ava.position = Vector2(round((w - AVA) / 2.0), 7)
		_ava.size = Vector2(AVA, AVA)
		_name.position = Vector2(4, NAME_Y)
		_name.size = Vector2(w - 8, NAME_H)
		if square > 0:                       # the row may have switched the format since
			_note.text = square_text(square, short)
		_note_pill.size = Vector2.ZERO
		var m := _note_pill.get_combined_minimum_size()
		_note_pill.size = Vector2(minf(m.x, w - 8), NOTE_H)
		_note_pill.position = Vector2(round((w - _note_pill.size.x) / 2.0), H - NOTE_H - 6)
		if corner and is_instance_valid(corner):
			corner.size = corner.get_combined_minimum_size()
			corner.position = Vector2(w - corner.size.x - 4, 4)
		pivot_offset = Vector2(w / 2.0, H / 2.0)
		queue_redraw()

	func _animate() -> void:
		var k := 1.06 if active else 1.0
		if _tw:
			_tw.kill()
		if not is_inside_tree() or PlayerTile._pref("reduce_motion"):
			scale = Vector2(k, k)
			_tw = create_tween() if is_inside_tree() else null
			return
		_tw = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_tw.tween_property(self, "scale", Vector2(k, k), 0.26 if active else 0.18)

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, Vector2(size.x, H))
		if active:
			var g := 0.5 + 0.5 * sin(_t * TAU / 1.4)
			_sb_glow.shadow_color.a = 0.35 + 0.4 * g
			_sb_glow.shadow_size = int(8 + 6 * g)
			draw_style_box(_sb_glow, r.grow(-3))
		draw_style_box(_sb_on if active else _sb, r)
		if kind == "you":                    # the equipped avatar has its own colours: a ring in the seat colour
			var ring := StyleBoxFlat.new()
			ring.bg_color = Palette.PLAYER[color_index]
			ring.set_corner_radius_all(int(AVA * 0.3) + 2)
			ring.anti_aliasing = true
			draw_style_box(ring, Rect2(_ava.position, _ava.size).grow(2))
		if active:                           # a pointer under the tile, towards the board
			var c := Vector2(size.x / 2.0, H + 6.0 + 2.0 * sin(_t * TAU / 1.0))
			var col: Color = Palette.PLAYER[color_index]
			draw_colored_polygon(PackedVector2Array([c + Vector2(-7, -4), c + Vector2(7, -4), c + Vector2(0, 5)]), Color.WHITE)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-4.5, -2.5), c + Vector2(4.5, -2.5), c + Vector2(0, 3)]), col)


## The dice's pad: a rounded tile in the colour of the player whose turn it is (white rim, a darker lip). On your
## turn it glows; after the idle hint it pulses.
class DicePad extends Control:
	var color_index := 0
	var on := false
	var hint := false
	var rolling := false
	var _t := 0.0
	var _sb := StyleBoxFlat.new()
	var _lip := StyleBoxFlat.new()
	var _glow := StyleBoxFlat.new()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		for s in [_sb, _lip, _glow]:
			s.set_corner_radius_all(UIKit.R.lg + 6)
			s.anti_aliasing = true
			s.corner_detail = 10
		_sb.set_border_width_all(UIKit.BW.rim)
		_sb.border_color = Color.WHITE
		_glow.bg_color = Color(1, 1, 1, 0)

	func set_color(c: int, active: bool) -> void:
		color_index = posmod(c, 4)
		on = active
		queue_redraw()

	func _process(delta: float) -> void:
		_t += delta
		var k := 1.0
		if hint and not rolling and not PlayerTile._pref("reduce_motion"):
			k = 1.0 + 0.05 * (0.5 + 0.5 * sin(_t * TAU / 0.9))
		scale = Vector2(k, k)
		queue_redraw()

	func _draw() -> void:
		var col: Color = Palette.PLAYER[color_index]
		var r := Rect2(Vector2.ZERO, size)
		if on:
			var g := 0.5 + 0.5 * sin(_t * TAU / (0.9 if hint else 1.6))
			_glow.shadow_color = Color(col.lightened(0.2), 0.45 + 0.35 * g)
			_glow.shadow_size = int(10 + (10 if hint else 5) * g)
			draw_style_box(_glow, r.grow(-4))
		_lip.bg_color = (Palette.PLAYER_DARK[color_index] as Color)
		draw_style_box(_lip, Rect2(r.position + Vector2(0, 5), r.size))
		_sb.bg_color = col.lerp(Color.WHITE, 0.12) if on else col.lerp(Palette.CHIP, 0.35)
		draw_style_box(_sb, r)
		# a soft sheen on the upper half
		var sheen := StyleBoxFlat.new()
		sheen.bg_color = Color(1, 1, 1, 0.18)
		sheen.set_corner_radius_all(UIKit.R.lg)
		draw_style_box(sheen, Rect2(r.position + Vector2(8, 6), Vector2(r.size.x - 16, r.size.y * 0.38)))
