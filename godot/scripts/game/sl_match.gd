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
##
## Online (friend rooms and quick match, server/PROTOCOL.md "Game types"): start_online(start_or_sync, net). The
## server is authoritative and this match is a replica (NetSL): your dice tap sends `roll` (nothing is rolled
## locally); every `act` (yours, a friend's, a bot's) is queued and played in order through the same path as offline
## play (the dice tumble to the server's value, then SnakesLaddersRules.apply_roll and the same walk, ladder, snake
## and message animations), faster while acts are waiting. After each act the S&L state hash is checked; a mismatch
## (or a gap) sends sync_req and the `sync` replaces the state and re-lays the board. No local dice or computer
## turns, no pause (the server keeps time), no MatchStore save. The HUD adds the server's turn timer on the active
## tile, Offline / Bot tags, "Reconnecting…" and, when a bot took your seat, the "I’m back" prompt. Every seat that
## isn't a bot is shown as a person (friends and quick-match players alike).
##
## Play on (SnakesLaddersRules header): a player who reaches 100 while others are still playing gets their place
## (a pop over the pawn, "You finished 1st!" / "Rafi finished 2nd!", the place badge on the tile, which dims); the
## pawn stays on 100 and the turn order skips them. Your own finish online: the FinishCard (Keep watching / Home =
## leave the room; the server grants your place at the end). The result at the end shows the full standings.

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
const NET_CATCHUP := 0.45                # pace while server acts are queued behind the one playing

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
# online (start_online)
var online := false
var net: Object                           # NetClient (anything with send_msg(Dictionary) -> bool and member_id)
var ns: NetSL
var _net_pumping := false
var _net_sent := -1                       # n of our last roll request (one per step: no double taps)
var _net_ready := false                   # the board is up: queued acts may play
var _ended := false
var _turn := {}                           # the server's last `turn` {c, end (ticks ms), total}: shown once the acts before it played
var banner: PanelContainer                # online: "Reconnecting…"
var away_box: PanelContainer              # online: "You were away…" + I’m back
var away_button: Button
var finish_card: FinishCard               # play on: "You finished 1st!" while the others play on
var _my_place := 0                        # play on: the place you finished in while the game went on (0: not yet)
var _my_away := false                     # online: a bot was playing your seat when you finished

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
	_build_online()
	hud.resized.connect(_layout)
	return hud

## Online pieces: the reconnect pill under the tiles and the away prompt above the dice (hidden until needed).
func _build_online() -> void:
	banner = PanelContainer.new()
	banner.name = "Banner"
	var bs := UIKit.box(Palette.HONEY_TINT, UIKit.R.pill, UIKit.BW.line, Color.WHITE)
	UIKit.shade(bs, "sm")
	UIKit.pad(bs, UIKit.SPACE.md, UIKit.SPACE.xs)
	banner.add_theme_stylebox_override("panel", bs)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := UIKit.hbox(UIKit.SPACE.sm)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(LudoHUD.Spinner.new())
	var bl := UIKit.label("", UIKit.FS.label, Palette.ON_HONEY, UIKit.font_body(900))
	bl.name = "Text"
	bl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(bl)
	banner.add_child(row)
	banner.visible = false
	hud.add_child(banner)
	away_box = PanelContainer.new()
	away_box.name = "Away"
	var st := UIKit.surface("card", false, true).duplicate() as StyleBoxFlat
	UIKit.pad(st, UIKit.SPACE.md, UIKit.SPACE.sm)
	away_box.add_theme_stylebox_override("panel", st)
	away_box.mouse_filter = Control.MOUSE_FILTER_STOP
	var col := UIKit.vbox(UIKit.SPACE.xs)
	col.add_child(UIKit.label("You were away — a bot played for you.", UIKit.FS.body, Palette.INK, UIKit.font_body(800), HORIZONTAL_ALIGNMENT_CENTER))
	away_button = UIKit.button("I’m back", "honey", "sm")
	away_button.name = "Back"
	away_button.pressed.connect(_net_back)
	col.add_child(away_button)
	away_box.add_child(col)
	away_box.visible = false
	hud.add_child(away_box)
	finish_card = FinishCard.new()
	finish_card.home_pressed.connect(_finish_home)
	finish_card.visibility_changed.connect(_layout)
	hud.add_child(finish_card)

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
	if banner and banner.visible:
		banner.size = banner.get_combined_minimum_size()
		banner.position = Vector2(round((w - banner.size.x) / 2.0), tile_y + SLTile.H + UIKit.SPACE.md)
	if away_box and away_box.visible:
		away_box.size = Vector2(minf(w - 2.0 * g, 320.0), 0)
		away_box.size = Vector2(away_box.size.x, away_box.get_combined_minimum_size().y)
		away_box.position = Vector2(round((w - away_box.size.x) / 2.0), dy - away_box.size.y - UIKit.SPACE.md)
	if finish_card and finish_card.visible:
		finish_card.size = finish_card.get_combined_minimum_size()
		finish_card.position = Vector2(round((w - finish_card.size.x) / 2.0), dy - finish_card.size.y - UIKit.SPACE.md)
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
		var kind := "you" if p.you else ("cpu" if p.cpu and not online else "human")
		var t := SLTile.new(int(p.c), str(p.name), kind, str(p.name).to_lower() if kind == "cpu" else "")
		if online and kind == "human":
			var st := ns.seat(int(p.c))
			t.set_look(str(st.get("avatar", "")), str(st.get("frame", "")))
		chips.add_child(t)
		if own < 0 and (p.you or (not p.cpu and not online)):
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
		t.set_done(done_place(G, k))

## Play on: the place player k finished in (reached 100), else 0 (also for players ranked by square at the end).
static func done_place(g: Dictionary, k: int) -> int:
	if int(g.players[k].pos) < 100:
		return 0
	var fin: Variant = g.get("finished", [])
	var at := (fin as Array).find(k) if fin is Array else -1
	return at + 1 if at >= 0 else (1 if int(g.get("winner", -1)) == k else 0)

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
	if online:
		for t in chips.get_children():
			if (t as SLTile).timer_end > 0:
				(t as SLTile).queue_redraw_all()


# =====================================================================================================================
# Input
# =====================================================================================================================

func _on_dice() -> void:
	if G.is_empty() or G.phase != "roll":
		return
	if online:
		if not _busy and ns.my_turn():
			roll()
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
	return not online and not G.is_empty() and bool(G.players[G.turn].cpu)


# =====================================================================================================================
# Flow
# =====================================================================================================================

func live(id: int) -> bool:
	return id == _id and not G.is_empty() and is_inside_tree()

## The animation speed now: the Settings speed, faster while fast-forwarding a computer's turn.
func _spd() -> float:
	return float(app.speed) * (FF if _ff else (NET_CATCHUP if online and ns != null and ns.pending() > 0 else 1.0))

## Waits sec x speed, paused while the app is; a fast-forward tap shortens what is left.
func wait(sec: float) -> void:
	var left := sec
	while left > 0.0 and is_inside_tree():
		await get_tree().process_frame
		if online or not app.paused:              # online the server keeps time: no pause
			left -= get_process_delta_time() / maxf(_spd(), 0.01)

## "You" or the player's bold name (tinted by GameTopBar with the turn's colour).
func _who(p: Dictionary) -> String:
	return "You" if p.you else "[b]%s[/b]" % p.name

func _human(p: Dictionary) -> bool:
	if online:
		return bool(p.you)                        # online: haptics for your own moves only
	return not p.cpu and not autoplay

## Quieter sounds for everyone but the person holding this phone.
func _soft(p: Dictionary) -> bool:
	return not bool(p.you) if online else bool(p.cpu)

func start(cfg: Dictionary) -> void:
	_offline()
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
	_offline()
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
	_my_place = 0
	_my_away = false
	if finish_card:
		finish_card.visible = false
	for k in G.players.size():
		if bool(G.players[k].you):
			_my_place = done_place(G, k)
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
	if online:
		_net_open()
		return
	_begin()

func stop() -> void:
	_id += 1
	_offline()
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
	if online:                                # the server rolls for bots and keeps the timer: only show the turn
		_net_badges()
		var mine := ns.my_turn()
		top.set_idle(_net_wait_line(p))
		_set_dice_turn(p, mine and _net_sent != ns.n)
		if mine and TapLog.enabled():
			(func(): TapLog.point(dice)).call_deferred()
		return
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
	if online:
		_net_request()                        # the server rolls; its act tumbles the dice (_net_act)
		return
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
	await _play_roll(id, p, pi, v, ev)

## The rules' events of one roll, animated (offline and online alike): three 6s, waiting for a 1, overshooting,
## the walk with its ladder or snake, the win, the next turn.
func _play_roll(id: int, p: Dictionary, pi: int, v: int, ev: Array) -> void:
	var soft := _soft(p)
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
			"finished":
				await _finished_one(p, pi, int(e.place), ev.back().type == "win")
				if not live(id):
					return
			"win":
				_busy = false
				_win(G.players[int(G.winner)])
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
				await wait(CPU_AFTER_WAIT if soft else HUMAN_AFTER_WAIT)
				_busy = false
				if live(id):
					_begin()
				return
		if not live(id):
			return
	_busy = false

## The pawn hops square by square, then rides a ladder or a snake.
func _walk(id: int, p: Dictionary, pi: int, e: Dictionary, v: int) -> void:
	var soft := _soft(p)
	top.say(("You rolled a %d." if p.you else "%s rolled a %d.") % ([v] if p.you else [_who(p), v]), 1.2 if int(e.from) > 0 else 1.4)
	var sq: int = int(e.from)
	for k in int(e.steps):
		while app.paused and not online and live(id):
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

## Play on: player pi just reached 100 in `place`. The tile gets its place badge; while the game goes on a pop over
## the pawn says it, and your own finish gets a small celebration and, online, the FinishCard. ending: this roll
## ends the game (_win follows and says it).
func _finished_one(p: Dictionary, pi: int, place: int, ending: bool) -> void:
	if bool(p.you):
		_my_place = place
		_my_away = online and bool(p.cpu)
	_refresh_tiles()
	print("[sl] %s finished %s%s" % [p.name, ResultScreen.ordinal(place), " (game over)" if ending else ""])
	if ending:
		return
	var nth := ResultScreen.ordinal(place)
	top.say("%s finished %s! The others play on." % [_who(p), nth], 2.4, "event")
	_pop("%s finished %s!" % ["You" if p.you else str(p.name), nth], board.pawn_top(pi), Palette.GOLD_HI if place == 1 else Palette.HONEY, 30)
	Sound.sfx("win", {soft = _soft(p)})
	if bool(p.you):
		Haptics.success()
		Celebrate.run(hud, "burst", 0.45)
		if online:
			finish_card.present(place)
			_layout()
	await wait(0.6)

## The finish card's Home: online, leave the room (your place is granted at the end).
func _finish_home() -> void:
	if online and app.has_method("leave_online_match"):
		app.call("leave_online_match")

## The end (w: the winner, the first to 100); the last finisher's roll (or the server's end) got here.
func _win(w: Dictionary) -> void:
	if online:
		await _net_game_over(w)
		return
	var p := w
	var id := _id
	_waiting = false
	dice.set_turn(dice.tint, false)
	board.set_current(-1)
	_refresh_tiles()
	top.set_idle("")
	if _homes() <= 1:                         # (play on: the later finishes already popped)
		top.say("You reached 100!" if p.you else "%s reached 100!" % _who(p), 2.0, "event")
		_pop("100!", board.pawn_top(G.winner), Palette.GOLD_HI, 36)
	Sound.sfx("lose" if p.cpu else "win")
	if _human(p):
		Haptics.success()
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

## How many players are on square 100.
func _homes() -> int:
	return G.players.filter(func(x): return int(x.pos) >= 100).size()

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
			if bool(me.finished):
				sub = "%s won · you reached 100 too" % w.name
			else:
				sub = "%s won · you reached square %d" % [w.name, int(me.pos)] if int(me.pos) > 0 else "%s won" % w.name
	return {game = "sl", title = title, sub = sub, standings = rows, human_won = won,
		reward = reward,
		vs_cpu = G.mode == "cpu", color = int(w.get("c", 0))}


# =====================================================================================================================
# Online (friend rooms, quick match)
# =====================================================================================================================

## An online match from the server's `start` (or a `sync` when joining one in progress). net: the NetClient.
func start_online(msg: Dictionary, net_: Object) -> void:
	online = true
	net = net_
	_turn = {}
	ns = NetSL.new()
	ns.begin(msg, _me_id())
	G = ns.S
	setup = {game = "sl", mode = "online", n = G.players.size(), color = maxi(ns.me, 0)}
	_net_sent = -1
	_net_pumping = false
	_net_ready = false
	_ended = false
	await _open()

func _me_id() -> String:
	return str(net.get("member_id")) if net else ""

## Back to an offline match: no replica, the online pieces hidden.
func _offline() -> void:
	if not online:
		return
	online = false
	net = null
	_net_pumping = false
	_net_ready = false
	_set_banner("")
	_show_away(false)

## _open's last step online: show the turn the state is in, then play what the server sent meanwhile.
func _net_open() -> void:
	_busy = false
	_net_ready = true
	_net_badges()
	if G.phase == "over":
		var w := int(G.winner)
		if w >= 0:
			_net_game_over(G.players[w])
		return
	_begin()
	_net_kick()

## A server message for the match: act / sync / over (queued, played in order).
func net_push(msg: Dictionary) -> void:
	if not online or ns == null:
		return
	ns.push(msg)
	_net_kick()

## Plays the queue, one message at a time, each to the end of its animation.
func _net_kick() -> void:
	if _net_pumping or not online or G.is_empty() or not _net_ready:
		return
	_net_pumping = true
	var id := _id
	while live(id) and online:
		var m := ns.next()
		if m.is_empty():
			break
		match str(m.get("t", "")):
			"need_sync":
				_net_send({t = "sync_req"})
			"sync":
				_net_pumping = false
				_net_resync(m)
				return                             # _open plays the rest of the queue
			"over":
				_net_end(m)
			"act":
				await _net_act(id, m)
	if id == _id:
		_net_pumping = false
		_show_turn()

## One server action through the offline animation path.
func _net_act(id: int, m: Dictionary) -> void:
	var a: Dictionary = m.get("a", {})
	match str(a.get("k", "")):
		"roll":
			if G.phase != "roll":
				ns.apply_rules(a)
				_net_check(m)
				return
			_busy = true
			var pi := int(G.turn)
			var p: Dictionary = G.players[pi]
			var v := clampi(int(a.get("v", 1)), 1, 6)
			_set_dice_turn(p, false)
			dice_pad.rolling = true
			var sp := _spd()
			var dur := 0.75 * maxf(sp, 0.05)
			var soft := _soft(p)
			Sound.sfx("roll", {dur = dur, soft = soft})
			if _human(p):
				get_tree().create_timer(dur * Sound.IMPACT_AT).timeout.connect(func():
					if live(id):
						Haptics.light())
			_set_timer(-1, 0.0, 1.0)              # the roll is in: the next `turn` shows once this act has played
			await dice.roll(v, sp)
			dice_pad.rolling = false
			if not live(id):
				return
			Sound.sfx("land", {soft = soft})
			var ev := ns.apply_rules(a)
			_net_check(m)
			await _play_roll(id, p, pi, v, ev)
		"end":                                 # the server ends the match (only bots / ghosts left to finish)
			var ev := ns.apply_rules(a)
			_net_check(m)
			if not ev.is_empty():
				_busy = false
				_win(G.players[int(G.winner)])
		"mode":
			ns.apply_rules(a)
			_net_check(m)
			_net_badges()
			if not _busy and G.phase == "roll":
				_begin()

## After an act's rules step: the hash. A mismatch asks for a snapshot.
func _net_check(m: Dictionary) -> void:
	if _net_sent >= 0 and _net_sent < ns.n:
		_net_sent = -1                         # our request was answered (or overtaken)
	if not ns.verify(m):
		push_warning("[net] S&L hash mismatch at n=%d: sync_req" % int(m.get("n", -1)))
		_net_send({t = "sync_req"})

## A full snapshot: replace the state, re-lay the board and go on from there.
func _net_resync(m: Dictionary) -> void:
	ns.begin(m, _me_id())
	G = ns.S
	_net_sent = -1
	_net_ready = false
	await _open()

## `over`: the result (the winning roll's events usually got there first).
func _net_end(m: Dictionary) -> void:
	if _ended:
		return
	var w := int(G.winner)
	if G.phase != "over":
		w = ns.index_of(int(m.get("winner", -1)))
		G.phase = "over"
		G.winner = w
		board.place(_positions())
		_refresh_tiles()
	if w >= 0:
		_net_game_over(G.players[w])

## Your roll request (one per step).
func _net_request() -> void:
	if not online or G.is_empty() or _busy or not ns.my_turn() or _net_sent == ns.n:
		return
	if _net_send(ns.request("roll")):
		_net_sent = ns.n
		_set_dice_turn(G.players[G.turn], false)

func _net_send(msg: Dictionary) -> bool:
	return net != null and bool(net.call("send_msg", msg))

## turn {c, deadline, now}: the server's clock for the current roll, on that player's tile.
## Kept until the acts before it have played (the timer then shows on the tile whose turn the board shows).
func net_turn(msg: Dictionary) -> void:
	if not online:
		return
	var left := maxf(0.0, float(msg.get("deadline", 0)) - float(msg.get("now", 0)))
	_turn = {c = int(msg.get("c", -1)), end = Time.get_ticks_msec() + int(left), total = maxf(left, NetSL.phase_sec() * 1000.0)}
	if not _net_pumping:
		_show_turn()

func _show_turn() -> void:
	if _turn.is_empty() or G.is_empty() or G.phase == "over":
		_set_timer(-1, 0.0, 1.0)
		return
	_set_timer(int(_turn.c), float(int(_turn.end) - Time.get_ticks_msec()), float(_turn.total))

## presence {id, online}: the Offline tag.
func net_presence(msg: Dictionary) -> void:
	if not online:
		return
	ns.set_online(NetClient.id_str(msg.get("id", "")), bool(msg.get("online", true)))
	_net_badges()

## A request the server refused (stale, not your turn): the dice wake again.
func net_error(msg: Dictionary) -> void:
	if not online:
		return
	push_warning("[net] request refused: %s" % str(msg.get("code", "")))
	_net_sent = -1
	if not G.is_empty() and not _busy and G.phase == "roll":
		_begin()

## NetClient.status: the "Reconnecting…" pill.
func net_status(st: String) -> void:
	if online:
		_set_banner("Reconnecting…" if st in ["reconnecting", "connecting"] else "")

## "I’m back": your seat is yours again (the server answers with a `mode human` act).
func _net_back() -> void:
	if online:
		_net_send({t = "back"})

## The Offline / Bot tags on the tiles, and the away prompt when a bot plays for you.
func _net_badges() -> void:
	if not online or G.is_empty():
		return
	for k in mini(G.players.size(), chips.get_child_count()):
		var p: Dictionary = G.players[k]
		var st := ns.seat(int(p.c))
		var b := ""
		if bool(p.cpu) and not bool(p.you):     # (your own seat: the away prompt says it)
			b = "bot"
		elif not bool(p.you) and not st.is_empty() and not bool(st.get("online", true)):
			b = "offline"
		(chips.get_child(k) as SLTile).set_badge(b)
	var mine := ns.mine()
	_show_away(not mine.is_empty() and bool(mine.cpu) and G.phase != "over")

## The event line while you wait: "Your turn", "Rafi’s turn", "Rafi is away. A bot is playing…".
func _net_wait_line(p: Dictionary) -> String:
	if ns.my_turn():
		return "Your turn"
	if bool(p.you):
		return "A bot is playing for you"
	if bool(p.cpu):
		return "%s is away. A bot is playing…" % _who(p)
	return "%s’s turn" % _who(p)

## The server's countdown on the tile of colour c (c < 0 clears every tile).
func _set_timer(c: int, left_ms: float, total_ms: float) -> void:
	var count := 0 if G.is_empty() else mini(G.players.size(), chips.get_child_count())
	for k in count:
		var t: SLTile = chips.get_child(k)
		t.set_timer(left_ms if int(G.players[k].c) == c else 0.0, total_ms)

func _set_banner(text: String) -> void:
	if banner == null:
		return
	(banner.find_child("Text", true, false) as Label).text = text
	banner.visible = text != "" and not _ended
	_layout()

func _show_away(on: bool) -> void:
	if away_box == null or away_box.visible == on:
		return
	away_box.visible = on and not _ended
	_layout()
	if away_box.visible:
		UIKit.pop_in(away_box)

## The online end: the server grants the rewards (Online refreshes the profile); the result shows what this match
## earns (ONLINE_V2.md "Economy decisions"), with everyone's own avatar.
func _net_game_over(w: Dictionary) -> void:
	if _ended:
		return
	_ended = true
	var id := _id
	_waiting = false
	_busy = false
	dice.set_turn(dice.tint, false)
	board.set_current(-1)
	_set_timer(-1, 0.0, 1.0)
	_refresh_tiles()
	_set_banner("")
	if away_box:
		away_box.visible = false
	if finish_card:
		finish_card.visible = false
	top.set_idle("")
	if _homes() <= 1:                         # (play on: the later finishes already popped)
		top.say("You reached 100!" if w.you else "%s reached 100!" % _who(w), 2.0, "event")
		_pop("100!", board.pawn_top(int(G.winner)), Palette.GOLD_HI, 36)
	var won := bool(w.you)
	Sound.sfx("win" if won else "lose")
	if won:
		Haptics.success()
	var mine := ns.mine()
	# the server's outcome: fixed when you were ranked (play on: finished earlier, then maybe watched / left)
	var away: bool = _my_away if _my_place > 0 else (not mine.is_empty() and bool(mine.cpu))
	var outcome := "" if mine.is_empty() else ("left" if away else ("win" if won else "finish"))
	var rw := NetReplica.online_reward("sl", outcome)
	var xp_before := int(Save.profile.get("xp", 0))
	var xp_after := xp_before
	var reward := 0
	if NetReplica.server_rewards():
		reward = int(rw.coins)
		xp_after = xp_before + int(rw.xp)
	elif int(rw.xp) > 0:                       # no account (old builds, dev): the XP stays local, no coins
		Save.profile.xp = xp_before + int(rw.xp)
		Save.save()
		Save.changed.emit()
		xp_after = int(Save.profile.xp)
	print("[sl] online game over: winner %s outcome=%s" % [w.name, outcome])
	await wait(0.9)
	if not live(id):
		return
	var result := result_data(reward)
	for r: Dictionary in result.standings:
		var st := ns.seat(int(r.color))
		if r.kind != "you":
			r.kind = "human"
			r.cpu_id = ""
			r.name = str(st.get("name", r.name))
		r.avatar = str(st.get("avatar", ""))
		r.frame = str(st.get("frame", ""))
		r.level = int(st.get("level", 1))
	result.online = true
	result.vs_cpu = false
	result.human_won = won
	result.xp_before = xp_before
	result.xp_after = xp_after
	top.hide_for_result()
	finished.emit(result)


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
	if autoplay or online or G.is_empty() or G.phase == "over":
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
	if not autoplay and not online:
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
	if g.get("finished") is Array:            # (states saved before play on have none: the rules make it)
		g.finished = (g.finished as Array).map(func(x): return int(x))
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
	var badge := ""                      ## online: "" | "offline" | "bot"
	var timer_end := 0                   ## online: Time.get_ticks_msec() when the server's roll timer runs out (0: none)
	var timer_total := 15000.0
	var _badge: PanelContainer
	var _disc: Control
	var done_place := 0                  ## play on: finished in this place (badge, dimmed); 0 = playing
	var _place_badge: Control
	const TIMER_R := 13.0

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
		_disc = Control.new()                # the countdown disc, over the avatar's corner
		_disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_disc.draw.connect(_draw_timer)
		add_child(_disc)
		resized.connect(_layout)
		set_process(false)

	## Online: this player's own avatar and frame (catalog ids) instead of the pawn tile.
	func set_look(avatar_id: String, frame_id: String) -> void:
		if avatar_id == "" or Collection.avatar(avatar_id).is_empty():
			return
		if _ava:
			_ava.queue_free()
		_ava = Collection.make_avatar_of(avatar_id, frame_id if frame_id != "" else "classic", AVA)
		_ava.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_ava)
		move_child(_ava, 0)
		_layout()

	## Online: an "Offline" / "Bot" tag on the tile's top edge ("" removes it).
	func set_badge(b: String) -> void:
		if b == badge:
			return
		badge = b
		if _badge:
			_badge.queue_free()
			_badge = null
		if b != "":
			_badge = UIKit.tag("Bot" if b == "bot" else "Offline", "ink" if b == "bot" else "white")
			_badge.name = "Badge"
			add_child(_badge)
		_layout()

	## Online: the server's roll countdown on this tile (left_ms 0 hides it).
	func set_timer(left_ms: float, total_ms: float) -> void:
		timer_end = Time.get_ticks_msec() + int(left_ms) if left_ms > 0.0 else 0
		timer_total = maxf(total_ms, 1.0)
		if _disc:
			_disc.queue_redraw()

	func queue_redraw_all() -> void:
		queue_redraw()
		if _disc:
			_disc.queue_redraw()

	## A white disc with the seconds left and a ring that empties (red near the end), like the Ludo tiles'.
	func _draw_timer() -> void:
		if timer_end <= 0:
			return
		var left := maxf(0.0, float(timer_end - Time.get_ticks_msec()))
		var k := clampf(left / timer_total, 0.0, 1.0)
		var m := Vector2(TIMER_R + 1.0, TIMER_R + 1.0)
		var late := left <= 5000.0
		_disc.draw_circle(m + Vector2(0, 1.5), TIMER_R + 1.0, Palette.shadow(0.25), true, -1.0, true)
		_disc.draw_circle(m, TIMER_R + 1.0, Color.WHITE, true, -1.0, true)
		_disc.draw_arc(m, TIMER_R - 2.0, 0.0, TAU, 40, Palette.TRACK, 3.0, true)
		if k > 0.0:
			_disc.draw_arc(m, TIMER_R - 2.0, -PI / 2.0, -PI / 2.0 + TAU * k, 40, Palette.RED if late else Palette.PLAYER[color_index], 3.0, true)
		var f := UIKit.font_body(900, true)
		var t := str(int(ceil(left / 1000.0)))
		var fs: int = UIKit.FS.small
		var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		_disc.draw_string(f, m + Vector2(-w / 2.0, fs * 0.36), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.DANGER if late else Palette.INK)

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

	## Play on: this player finished in place n while the game goes on: a place badge on the avatar's corner and the
	## tile dimmed; 0 = still playing.
	func set_done(n: int) -> void:
		if n == done_place:
			return
		done_place = n
		if _place_badge:
			_place_badge.queue_free()
			_place_badge = null
		if n > 0:
			_place_badge = PlayerTile.PlaceBadge.make(n, 24)
			_place_badge.name = "Place"
			add_child(_place_badge)
		var k := PlayerTile.DONE_ALPHA if n > 0 else 1.0
		self_modulate.a = k
		for ch in get_children():
			if ch is CanvasItem and ch != _place_badge and ch != corner:   # (the rules ⓘ stays as it is)
				(ch as CanvasItem).modulate.a = k
		_layout()

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
		if _disc:
			_disc.size = Vector2(2.0 * TIMER_R + 2.0, 2.0 * TIMER_R + 4.0)
			_disc.position = _ava.position - Vector2(TIMER_R - 2.0, TIMER_R - 2.0)
			move_child(_disc, get_child_count() - 1)
		if _badge and is_instance_valid(_badge):            # the top edge, clear of the countdown disc on its left
			_badge.size = _badge.get_combined_minimum_size()
			var bx := maxf((w - _badge.size.x) / 2.0, _ava.position.x + TIMER_R + 4.0)
			_badge.position = Vector2(round(minf(bx, w - _badge.size.x - 2.0)), round(-_badge.size.y / 2.0))
		if _place_badge and is_instance_valid(_place_badge):  # the avatar's top-left corner (no timer once finished)
			_place_badge.position = _ava.position - Vector2(9, 9)
			move_child(_place_badge, get_child_count() - 1)
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
