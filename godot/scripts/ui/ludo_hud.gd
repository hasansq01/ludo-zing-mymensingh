class_name LudoHUD
extends Control
## The Ludo game screen's interface over the 3D board: the GameTopBar (pause, the event line, gear) and four
## PlayerTiles in the screen corners (clockwise from the viewer's own corner, bottom-left). Every tile keeps the
## same footprint (avatar + dice slot); only the active player's slot shows, and the one die (Dice3D, tinted in that
## player's colour) glides from tile to tile. Tiles are framed in their player's colour so they map to the bases.
## Also: floating pop texts ("+1 roll", "Home!") on their own layer under the tutorial's coach marks, the inline
## "Pair up / Keep single" prompt (house rule "Ask before pairing") and the ⓘ team / pair icons beside your own
## tile's nameplate (not in the event line, which stays one quiet line).
## tutorial = true (LudoMatch, during the guided first match): the event line stays empty (the coach bubble is the
## one voice), the turn pops are left out (the bubble says it) and the staged progress pills are hidden.
##
## The event line: say() for transient events, idle() for the persistent state line (never stale: LudoMatch sets
## it at every phase change), hide_for_result() when the game is over.
## Online (set_online): your seat is "you" (S.me), the friends' tiles show their own avatars (seats), the dice wake
## only on your turn (hold_dice while your roll request is out), set_timer() draws the server's turn countdown on the
## active tile, set_badges() puts "Offline" / "Bot" on tiles, show_away() the "I’m back" prompt, set_banner() the
## "Reconnecting…" pill under the top tiles.
## Play on: a side that has finished while the game goes on shows its place badge and is dimmed (update(), from the
## state); show_finish() is the "You finished 1st!" card (Keep watching / Home: finish_home_pressed) for your side.

signal dice_pressed
signal pause_pressed
signal settings_pressed
signal pick_chosen(kind: String)         # legacy (the Single / Pair step is gone); never emitted
signal pair_answered(yes: bool)
signal away_pressed                      # online: "I’m back" (a bot was playing your seat)
signal finish_home_pressed               # the finish card's Home (online: leave the room)

const POS := ["bl", "tl", "tr", "br"]
const DICE := 72.0                       # the die's control (its face is DICE_FILL of it, ≈ 62 px)
const DICE_FILL := 0.86
const TILE_GAP := 8.0                    # top tiles: below the top bar

var safe_top := 0.0
var safe_bottom := 0.0
var top: GameTopBar
var tiles: Array = []                    # per colour: Tile (a PlayerTile)
var dice: Dice3D
var pair_box: PanelContainer             # the inline pair prompt
var pair_yes: Button
var pair_no: Button
var _s: Dictionary
var _turn := -1
var _corner := ["", "", "", ""]
var _team_info: Control
var _pair_info: Control
var _help: HBoxContainer                 # the ⓘ icons beside your tile's nameplate
var _help_tile := -1
var _pop_layer: Control                  # pops live here, under the coach marks (added after it by Tutorial)
var _dice_snap := true
var _over := false
var coach: Control                       # the tutorial's CoachMarks while it runs (board pops go above its scrim)
var online := false
var me := -1                             # online: your colour
var seats := {}                          # online: colour -> seat {id, name, avatar, frame, bot, online}
var hold_dice := false                   # online: your roll request is out (the dice wait for the server's act)
var banner: PanelContainer               # online: "Reconnecting…"
var away_box: PanelContainer             # online: "You were away…" + I’m back
var away_button: Button
var finish_card: FinishCard              # play on: "You finished 1st!" while the others play on
var tutorial := false:
	set(v):
		tutorial = v
		if v and top:
			top.clear()


## A PlayerTile whose dice slot only shows while it is that player's turn: every tile has the same fixed size
## (avatar + slot) and the avatar never moves; waiting, only the avatar card is drawn (the reserved slot space is
## fully invisible: no fill, border or shadow); on the turn the card widens towards the screen centre and the slot
## fades in beside the avatar. The nameplate and the progress pill stay centred under the avatar; `help` (ⓘ icons)
## sits beside the nameplate.
class Tile extends PlayerTile:
	var open_k := 0.0:
		set(v):
			open_k = v
			queue_redraw()
	var help: Control
	var badge := ""                       # online: "" | "offline" | "bot"
	var timer_end := 0                    # online: Time.get_ticks_msec() when the server's turn timer runs out (0: none)
	var timer_total := 15000.0
	var _badge: PanelContainer
	var _open_tw: Tween
	var _slot_bg := Color.WHITE
	var _slot_edge := Color.WHITE
	const TIMER_R := 13.0

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

	## Online: "offline" / "bot" tag on the avatar's top edge ("" removes it).
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
		_apply_done()
		_layout()

	## The countdown disc's centre (the avatar's outer top corner).
	func timer_center() -> Vector2:
		var ap := _ava_pos()
		return ap + (Vector2(-3, -3) if side != "right" else Vector2(AVA + 3, -3))

	## (the ⓘ icons beside your nameplate stay as they are on a finished tile)
	func _apply_done() -> void:
		super()
		if help and is_instance_valid(help):
			help.modulate.a = 1.0

	func _init(c := 0, side_ := "left") -> void:
		super(c, side_)
		_slot_bg = _sb_slot.bg_color
		_slot_edge = _sb_slot.border_color

	func set_state(active_: bool, mover_: bool, home: int, pct: float, chip := "") -> void:
		var was := active
		super(active_, mover_, home, pct, chip)
		if was != active or (_open_tw == null and open_k != (1.0 if active else 0.0)):
			if _open_tw:
				_open_tw.kill()
			if not is_inside_tree() or PlayerTile._pref("reduce_motion"):
				open_k = 1.0 if active else 0.0
			else:
				_open_tw = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
				_open_tw.tween_property(self, "open_k", 1.0 if active else 0.0, 0.22 if active else 0.16)

	func _layout() -> void:
		super()
		var cx := _ava_pos().x + AVA / 2.0
		for p: Control in [_name_pill, _prog_pill, _chip_pill]:
			if p and p.visible:
				p.position.x = clampf(round(cx - p.size.x / 2.0), 0.0, CARD_W - p.size.x)
		if help and is_instance_valid(help) and help.visible:
			help.size = help.get_combined_minimum_size()
			var ny := _name_pill.position.y + (_name_pill.size.y - help.size.y) / 2.0
			var hx := _name_pill.position.x + _name_pill.size.x + UIKit.SPACE.xs if side != "right" else _name_pill.position.x - UIKit.SPACE.xs - help.size.x
			help.position = Vector2(round(hx), round(ny))
		if _badge and is_instance_valid(_badge):
			_badge.size = _badge.get_combined_minimum_size()
			var ap := _ava_pos()
			var w := _badge.size.x                # inner top corner, clear of the countdown disc on the outer one
			var bx := maxf(ap.x + AVA - w + 6.0, ap.x + TIMER_R + 2.0) if side != "right" else minf(ap.x - 6.0, ap.x + AVA - TIMER_R - 2.0 - w)
			_badge.position = Vector2(round(bx), round(ap.y - _badge.size.y / 2.0 - 2.0))

	func _draw() -> void:
		var closed := Rect2(_ava_pos() - Vector2(PAD, PAD), Vector2(AVA + 2.0 * PAD, CARD_H))
		var full := Rect2(Vector2.ZERO, Vector2(CARD_W, CARD_H))
		var card := Rect2(closed.position.lerp(full.position, open_k), closed.size.lerp(full.size, open_k))
		if active:
			var a := 0.75 if _reduce_motion() else 0.45 + 0.45 * _glow
			_sb_glow.shadow_color.a = a * open_k
			_sb_glow.shadow_size = int(10 + 8 * _glow)
			draw_style_box(_sb_glow, card.grow(-4))
		draw_style_box(_sb_card_on if active else _sb_card, card)
		if open_k > 0.01:                          # waiting: nothing at all where the die parks
			var k := clampf((open_k - 0.3) / 0.7, 0.0, 1.0)   # the slot fades in once the card has widened
			_sb_slot.bg_color = Color(_slot_bg, _slot_bg.a * k)
			_sb_slot.border_color = Color(_slot_edge, _slot_edge.a * k)
			draw_style_box(_sb_slot, Rect2(_slot_pos(), Vector2(SLOT, SLOT)))
		if kind == "you":
			draw_style_box(_sb_you, Rect2(_ava_pos(), Vector2(AVA, AVA)).grow(2))
		if mover:
			draw_style_box(_sb_mover, Rect2(_ava_pos(), Vector2(AVA, AVA)).grow(3))
		if timer_end > 0:
			_draw_timer()

	## The server's turn countdown: a white disc with the seconds left and a ring that empties (red near the end).
	func _draw_timer() -> void:
		var left := maxf(0.0, float(timer_end - Time.get_ticks_msec()))
		var k := clampf(left / maxf(timer_total, 1.0), 0.0, 1.0)
		var m := timer_center()
		var late := left <= 5000.0
		draw_circle(m + Vector2(0, 1.5), TIMER_R + 1.0, Palette.shadow(0.25), true, -1.0, true)
		draw_circle(m, TIMER_R + 1.0, Color.WHITE, true, -1.0, true)
		draw_arc(m, TIMER_R - 2.0, 0.0, TAU, 40, Palette.TRACK, 3.0, true)
		if k > 0.0:
			draw_arc(m, TIMER_R - 2.0, -PI / 2.0, -PI / 2.0 + TAU * k, 40, Palette.RED if late else Palette.PLAYER[color_index], 3.0, true)
		var f := UIKit.font_body(900, true)
		var t := str(int(ceil(left / 1000.0)))
		var fs := UIKit.FS.small
		var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, m + Vector2(-w / 2.0, fs * 0.36), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.DANGER if late else Palette.INK)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	top = GameTopBar.new("pause")
	top.left_pressed.connect(func(): pause_pressed.emit())
	top.gear_pressed.connect(func(): settings_pressed.emit())
	add_child(top)
	for c in 4:
		var t := Tile.new(c, "left")
		t.mouse_filter = Control.MOUSE_FILTER_STOP          # your tile is a roll target too (CL-21)
		t.gui_input.connect(_on_tile_input.bind(c))
		add_child(t)
		tiles.append(t)
	dice = Dice3D.new()
	dice.fill = DICE_FILL
	dice.custom_minimum_size = Vector2(DICE, DICE)
	dice.size = Vector2(DICE, DICE)
	dice.pressed.connect(func(): dice_pressed.emit())
	dice.visible = false
	add_child(dice)
	_build_pair_box()
	_build_online()
	finish_card = FinishCard.new()
	finish_card.home_pressed.connect(func(): finish_home_pressed.emit())
	add_child(finish_card)
	_pop_layer = Control.new()
	_pop_layer.name = "Pops"
	_pop_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pop_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pop_layer)
	_help = UIKit.hbox(UIKit.SPACE.xxs)
	_help.name = "Help"
	_help.mouse_filter = Control.MOUSE_FILTER_PASS
	_help.visible = false
	resized.connect(_layout)

func _build_pair_box() -> void:
	pair_box = PanelContainer.new()
	var st := UIKit.surface("card", false, true).duplicate() as StyleBoxFlat
	UIKit.pad(st, UIKit.SPACE.md, UIKit.SPACE.sm)
	pair_box.add_theme_stylebox_override("panel", st)
	pair_box.mouse_filter = Control.MOUSE_FILTER_STOP
	var col := UIKit.vbox(UIKit.SPACE.xs)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	var cap := UIKit.label("Join these two pawns?", UIKit.FS.body, Palette.INK, UIKit.font_body(800), HORIZONTAL_ALIGNMENT_CENTER)
	var head := UIKit.hbox(UIKit.SPACE.xs)
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(cap)
	head.add_child(Info.icon("pair", false, 20))
	col.add_child(head)
	var row := UIKit.hbox(UIKit.SPACE.sm)
	pair_yes = UIKit.button("Pair up", "honey", "sm")
	pair_no = UIKit.button("Keep single", "ghost", "sm")
	for b in [pair_yes, pair_no]:
		b.custom_minimum_size.x = 132
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	pair_yes.pressed.connect(func(): _answer(true))
	pair_no.pressed.connect(func(): _answer(false))
	col.add_child(row)
	pair_box.add_child(col)
	pair_box.visible = false
	add_child(pair_box)

## Online pieces: the reconnect pill and the away prompt (hidden until needed).
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
	var spin := Spinner.new()
	row.add_child(spin)
	var bl := UIKit.label("", UIKit.FS.label, Palette.ON_HONEY, UIKit.font_body(900))
	bl.name = "Text"
	bl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(bl)
	banner.add_child(row)
	banner.visible = false
	add_child(banner)
	away_box = PanelContainer.new()
	away_box.name = "Away"
	var st := UIKit.surface("card", false, true).duplicate() as StyleBoxFlat
	UIKit.pad(st, UIKit.SPACE.md, UIKit.SPACE.sm)
	away_box.add_theme_stylebox_override("panel", st)
	away_box.mouse_filter = Control.MOUSE_FILTER_STOP
	var col := UIKit.vbox(UIKit.SPACE.xs)
	var l := UIKit.label("You were away — a bot played for you.", UIKit.FS.body, Palette.INK, UIKit.font_body(800), HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(l)
	away_button = UIKit.button("I’m back", "honey", "sm")
	away_button.name = "Back"
	away_button.pressed.connect(func(): away_pressed.emit())
	col.add_child(away_button)
	away_box.add_child(col)
	away_box.visible = false
	add_child(away_box)

## Online on / off: your colour and the seats (colour -> seat dictionaries from the server).
func set_online(on: bool, me_ := -1, seats_: Array = []) -> void:
	online = on
	me = me_ if on else -1
	seats = {}
	for st in seats_:
		if st is Dictionary:
			seats[int(st.get("color", -1))] = st
	hold_dice = false
	if not on:
		set_banner("")
		show_away(false)
		set_badges(["", "", "", ""])
		set_timer(-1, 0.0, 1.0)

## The server's turn timer on colour c's tile (left / total in ms; c < 0 clears every tile).
func set_timer(c: int, left_ms: float, total_ms: float) -> void:
	for k in 4:
		var t: Tile = tiles[k]
		t.timer_end = 0
		if k == c and left_ms > 0.0:
			t.timer_end = Time.get_ticks_msec() + int(left_ms)
			t.timer_total = total_ms
		t.queue_redraw()

## Online badges by colour: "" | "offline" | "bot".
func set_badges(b: Array) -> void:
	for c in 4:
		(tiles[c] as Tile).set_badge(str(b[c]) if c < b.size() else "")

## "You were away — a bot played for you." with I’m back (above your tile row, like the pair prompt).
func show_away(on: bool) -> void:
	if on == away_box.visible:
		return
	away_box.visible = on and not _over
	if away_box.visible:
		_place_bottom(away_box)
		UIKit.pop_in(away_box)

## The reconnect pill under the top tiles ("" hides it).
func set_banner(text: String) -> void:
	(banner.find_child("Text", true, false) as Label).text = text
	banner.visible = text != "" and not _over
	if banner.visible:
		_place_banner()

func _place_banner() -> void:
	banner.size = banner.get_combined_minimum_size()
	var band := board_band()
	banner.position = Vector2(round((size.x - banner.size.x) / 2.0), band.position.y + UIKit.SPACE.xs)

## Rebuild the tiles for a new game.
func setup(s: Dictionary) -> void:
	_s = s
	_turn = -1
	_over = false
	_dice_snap = true
	top.show_bar()
	top.clear()
	pair_box.visible = false
	finish_card.visible = false
	for c in 4:
		var t: Tile = tiles[c]
		t.visible = LudoRules.active(s, c)
		_corner[c] = POS[(c - int(s.view) + 4) % 4]
		t.side = "left" if _corner[c] in ["bl", "tl"] else "right"
		var kind := "you" if NetLudo.you(s, c) else ("cpu" if s.players[c] == "cpu" and not online else "human")
		var nm := LudoRules.pname(s, c)
		t.set_player(nm, kind, nm.to_lower() if kind == "cpu" and PlayerTile.CPU_IDS.has(nm.to_lower()) else "")
		if online and kind == "human" and seats.has(c):
			t.set_look(str(seats[c].get("avatar", "")), str(seats[c].get("frame", "")))
		t.set_place(0)
		t.set_done(0)
		t.set_progress_visible(not tutorial)
		t.set_chip_colors([])
	_place_help(_own_tile(s))
	_set_info(_team_info, false)
	_set_info(_pair_info, false)
	if s.teams:
		if _team_info == null:
			_team_info = Info.icon("team", true, 20)
			_help.add_child(_team_info)
		_set_info(_team_info, true)
	_sync_help()
	_layout()
	update(s, s.turn)
	if s.teams:
		Info.nudge("team", true, _help)

## The tile the ⓘ icons sit on: yours (vs the computer), else the seat the board is turned to (Pass & Play).
func _own_tile(s: Dictionary) -> int:
	for c in 4:
		if LudoRules.active(s, c) and NetLudo.you(s, c):
			return c
	return int(s.view)

func _place_help(c: int) -> void:
	if c == _help_tile and _help.get_parent() == tiles[c]:
		return
	if _help.get_parent():
		_help.get_parent().remove_child(_help)
	if _help_tile >= 0:
		(tiles[_help_tile] as Tile).help = null
	_help_tile = c
	var t: Tile = tiles[c]
	t.add_child(_help)
	t.help = _help

func _sync_help() -> void:
	var any := false
	for ch in _help.get_children():
		if (ch as CanvasItem).visible:
			any = true
	if _help.visible != any:
		_help.visible = any
		if _help_tile >= 0:
			(tiles[_help_tile] as Tile)._layout()

func _set_info(ic: Control, on: bool) -> void:
	if ic:
		ic.visible = on

func _layout() -> void:
	var w := size.x
	var h := size.y
	if w <= 0:
		return
	top.safe_top = safe_top
	for c in 4:
		var t: Tile = tiles[c]
		var left: bool = _corner[c] in ["bl", "tl", ""]
		var is_top: bool = _corner[c] in ["tl", "tr"]
		var x: float = UIKit.SCREEN_GUTTER if left else w - UIKit.SCREEN_GUTTER - PlayerTile.CARD_W
		var y: float = top.bottom() + TILE_GAP if is_top else h - safe_bottom - UIKit.SCREEN_GUTTER - t.tile_height()
		t.position = Vector2(x, y)
		t._layout()
	if pair_box.visible:
		_place_pair_box()
	if away_box and away_box.visible:
		_place_bottom(away_box)
	if finish_card and finish_card.visible:
		_place_bottom(finish_card)
	if banner and banner.visible:
		_place_banner()

## The free band between the top and bottom tile rows (UI pixels, full width): the board is framed in it.
func board_band() -> Rect2:
	var y0 := top.bottom() + TILE_GAP
	var y1 := size.y - safe_bottom - UIKit.SCREEN_GUTTER
	var top_h := 0.0
	var bot_h := 0.0
	for c in 4:
		var t: Tile = tiles[c]
		if not t.visible:
			continue
		if _corner[c] in ["tl", "tr"]:
			top_h = maxf(top_h, t.tile_height() * PlayerTile.ACTIVE_SCALE)
		else:
			bot_h = maxf(bot_h, t.tile_height() * PlayerTile.ACTIVE_SCALE)
	return Rect2(0, y0 + top_h, size.x, maxf(0.0, y1 - bot_h - (y0 + top_h)))

## The tiles' screen rects (at their active size), for keeping the board clear of them.
func tile_rects() -> Array:
	var out := []
	for c in 4:
		var t: Tile = tiles[c]
		if t.visible:
			var r := Rect2(t.position, Vector2(PlayerTile.CARD_W, t.tile_height()))
			out.append(r.grow(PlayerTile.CARD_W * (PlayerTile.ACTIVE_SCALE - 1.0) / 2.0 + 4.0))
	return out

func _process(delta: float) -> void:
	if _turn < 0 or not dice.visible:
		return
	var r: Rect2 = (tiles[_turn] as Tile).dice_slot_rect()
	var want := r.get_center() - dice.size / 2.0
	if _dice_snap:
		dice.global_position = want
		_dice_snap = false
	else:
		var k := 1.0 - pow(0.8, delta * 60.0)
		dice.global_position = dice.global_position.lerp(want, k)

## Refresh everything from the state; `turn` is the player shown as active (the presentation can lag the rules).
func update(s: Dictionary, turn: int) -> void:
	_s = s
	_turn = turn
	var over: bool = s.phase == "over"
	var mover := LudoRules.mover_of(s, turn) if turn >= 0 else -1
	for c in 4:
		var t: Tile = tiles[c]
		if not t.visible:
			continue
		var home := 0
		for p in s.tok[c]:
			if p >= LudoRules.GOAL:
				home += 1
		var chip := team_chip(s, c)
		if chip != "":
			var m := LudoRules.mate_of(c)
			t.set_chip_colors([mini(c, m), maxi(c, m)])
		t.set_state(c == turn and not over, mover == c and mover != turn and not over, home, LudoRules.progress(s, c), chip)
		t.set_done(done_place(s, c))
	top.set_turn(turn)
	dice.visible = turn >= 0 and not over
	if turn >= 0:
		dice.set_tint(Palette.PLAYER[turn])
	var can_roll: bool = turn >= 0 and s.phase == "roll" and LudoRules.is_human(s, turn) and not over \
		and (not online or (turn == me and not hold_dice))
	if can_roll and not dice.active and not dice.rolling:
		dice.show_ready()                    # a neutral pose while waiting: the last roll's face is not a spoiler
	dice.set_active(can_roll)
	var you_pair := false
	for q in s.pairs:
		if NetLudo.you(s, q.c) or (not online and LudoRules.is_human(s, q.c) and not s.players.has("cpu")):
			you_pair = true
	if you_pair and _pair_info == null:
		_pair_info = Info.icon("pair", true, 20)
		_help.add_child(_pair_info)
	_set_info(_pair_info, you_pair)
	_sync_help()
	_layout()

## Play on: the place colour c's side finished in (its pawns all home: Teams, both partners'), else 0. A side ranked
## by progress at the end is not "done" (no badge).
static func done_place(s: Dictionary, c: int) -> int:
	if not LudoRules.all_home(s, c):
		return 0
	if LudoRules.team_on(s):
		return 1 if LudoRules.all_home(s, LudoRules.mate_of(c)) else 0
	var fin: Variant = s.get("finished", [])
	var k := (fin as Array).find(c) if fin is Array else -1
	return k + 1 if k >= 0 else 0

## The "You finished 1st!" card over the board (your side finished, the game goes on). home: offer Home.
func show_finish(place: int, team := false, home := true) -> void:
	if _over:
		return
	finish_card.present(place, team, home)
	_place_bottom(finish_card)

func hide_finish() -> void:
	finish_card.visible = false

## The team chip under a tile in Teams (2 v 2), led by the two teammates' colour dots: "With Yellow" on your tile,
## "With you" on your teammate's, "Rivals" on the other team's (no you: "With <teammate's colour>" on every tile).
## All four pawns home: "Helping Yellow", or "Roll a 6 to help". "" outside Teams.
static func team_chip(s: Dictionary, c: int) -> String:
	if not LudoRules.team_on(s):
		return ""
	var m := LudoRules.mate_of(c)
	if LudoRules.all_home(s, c):
		return ("Helping " + Palette.NAMES[m]) if s.free[c] else "Roll a 6 to help"
	var me := -1
	for k in 4:
		if LudoRules.active(s, k) and NetLudo.you(s, k):
			me = k
	if me < 0 or c == me:
		return "With " + Palette.NAMES[m]
	if c == LudoRules.mate_of(me):
		return "With you"
	return "Rivals"

## A transient event line (GameTopBar.say): kind "event" pops and stays readable, "info" just shows.
## Quiet during the tutorial (the coach bubble is the only instruction).
func say(bb: String, sec := 1.6, kind := "info") -> void:
	if not _over and not tutorial:
		top.say(bb, sec, kind)

## The persistent state line ("Your turn — tap the dice"). Quiet during the tutorial.
func idle(bb: String) -> void:
	if not _over and not tutorial:
		top.set_idle(bb)

## Old callers: a transient message.
func set_message(bb: String) -> void:
	say(bb, 1.6, "info")

## Old callers (the Single / Pair row is gone).
func show_pick(_on: bool) -> void:
	pass

## Game over: the bar, the die and any prompt go away behind the result screen.
func hide_for_result() -> void:
	_over = true
	top.hide_for_result()
	dice.visible = false
	pair_box.visible = false
	away_box.visible = false
	banner.visible = false
	finish_card.visible = false
	set_timer(-1, 0.0, 1.0)

## A short pop text that rises and fades at a screen point (UI pixels): "+1 roll", "Home!". Pops sit on their own
## layer under the tutorial's coach marks (never over its caption). board = true: a pop on the board (a capture,
## "Home!"), which is the lesson itself: during the tutorial it shows above the dim scrim (still under the caption).
func pop(text: String, at: Vector2, color := Palette.HONEY, fs := 26, board := false) -> void:
	var l := UIKit.label(text, fs, color, UIKit.font_display(), HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_color_override("font_outline_color", Palette.INK_STRONG)
	l.add_theme_constant_override("outline_size", maxi(6, int(fs * 0.28)))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var host: Control = _pop_layer
	if board and is_instance_valid(coach) and coach.has_method("pop_host"):
		host = coach.call("pop_host")
	host.add_child(l)
	l.size = l.get_combined_minimum_size()
	var p := at - l.size / 2.0
	p.x = clampf(p.x, 8.0, size.x - l.size.x - 8.0)
	l.position = p
	l.pivot_offset = l.size / 2.0
	var still := PlayerTile._pref("reduce_motion")
	l.scale = Vector2(0.4, 0.4) if not still else Vector2.ONE
	var tw := l.create_tween().set_parallel(true)
	if not still:
		tw.tween_property(l, "scale", Vector2(1.15, 1.15), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.chain().tween_property(l, "scale", Vector2.ONE, 0.1)
		tw.parallel().tween_property(l, "position:y", p.y - 40.0, 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(l, "modulate:a", 0.0, 0.25)
	tw.chain().tween_callback(l.queue_free)

## A pop about the turn ("+1 roll" after a 6) just above the active player's dice slot. Left out during the
## tutorial: the coach bubble anchored there already says it.
func turn_pop(text: String, color := Palette.HONEY, fs := 26) -> void:
	if tutorial or is_instance_valid(coach):
		return
	pop(text, turn_point(), color, fs)

## Where to pop texts about the turn (just inside the active player's tile, towards the screen centre).
func turn_point() -> Vector2:
	if _turn < 0:
		return size / 2.0
	var r: Rect2 = (tiles[_turn] as Tile).dice_slot_rect()
	var up: bool = _corner[_turn] in ["bl", "br"]
	return r.get_center() + Vector2(0, -r.size.y * 0.9 if up else r.size.y * 1.4)

## The pop a tile does when one of its pawns gets home.
func bump_tile(c: int) -> void:
	var t: Tile = tiles[c]
	if PlayerTile._pref("reduce_motion"):
		return
	var k: Vector2 = t.scale
	var tw := create_tween()
	tw.tween_property(t, "scale", k * 1.08, 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(t, "scale", k, 0.18)

## The "Ask before pairing" prompt, anchored at the bottom over the board (not a modal: the board stays visible).
## Coroutine: returns the answer.
func ask_pair() -> bool:
	top.set_idle("")                         # the prompt asks the question itself: the bar goes quiet,
	top.cancel_message()                     # and no stale event stays over a question aimed at you
	pair_box.visible = true
	_place_pair_box()
	UIKit.pop_in(pair_box)
	Sound.sfx("select")
	var yes: bool = await pair_answered
	return yes

## Closes the prompt without an answer (a new game, leaving).
func cancel_pair() -> void:
	if pair_box.visible:
		pair_box.visible = false
		pair_answered.emit(false)

func _answer(yes: bool) -> void:
	if not pair_box.visible:
		return
	pair_box.visible = false
	pair_answered.emit(yes)

func _place_pair_box() -> void:
	_place_bottom(pair_box)

## A prompt centred just above the bottom tile row (the pair question, the away prompt).
func _place_bottom(box: Control) -> void:
	box.size = box.get_combined_minimum_size()
	var ytop := size.y
	for c in 4:
		var t: Tile = tiles[c]
		if t.visible and _corner[c] in ["bl", "br"]:
			ytop = minf(ytop, t.position.y - (PlayerTile.ACTIVE_SCALE - 1.0) * t.tile_height())
	box.position = Vector2(round((size.x - box.size.x) / 2.0), ytop - box.size.y - UIKit.SPACE.sm)

func _on_tile_input(e: InputEvent, c: int) -> void:
	var hit := false
	if e is InputEventScreenTouch and e.pressed:
		hit = true
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		hit = e.device != InputEvent.DEVICE_ID_EMULATION
	if hit and c == _turn and not _s.is_empty() and _s.phase == "roll" and LudoRules.is_human(_s, c) and (not online or c == me):
		accept_event()
		dice_pressed.emit()


## A small turning ring (the reconnect pill).
class Spinner extends Control:
	var _a := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(16, 16)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(d: float) -> void:
		if is_visible_in_tree():
			_a = fmod(_a + d * TAU * 1.1, TAU)
			queue_redraw()

	func _draw() -> void:
		var m := size / 2.0
		draw_arc(m, 6.0, 0.0, TAU, 32, Color(Palette.ON_HONEY, 0.18), 2.5, true)
		draw_arc(m, 6.0, _a, _a + TAU * 0.3, 16, Palette.ON_HONEY, 2.5, true)
