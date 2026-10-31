class_name SetupSheet
extends Sheet
## The setup popups (index.html #cpuSheet / #localSheet and the Snakes & Ladders ones): colour, number of opponents
## or players, Pass & Play a row per seat (its colour + an editable name, "Player 2"...), for Ludo the mode
## (Individual or Teams (2 v 2)) and, vs Computer, the computer's skill. Opens with the last setup of that game and
## mode (Save.prefs.last_setup[game][mode] = {count, color, teams, bot_level?, names?}; names by seat order) and saves
## it on Start. Emits `start` with the game config:
##   Ludo:  {game = "ludo", players = [4 x "human" | "cpu" | "off"], teams = bool, bot_level = "easy|normal|hard",
##           names = [4] (Pass & Play only)}
##   S & L: {game = "sl", mode = "cpu" | "local", n = 2..4, color = 0..3, bot_level, names = [4] (Pass & Play only)}
## names: 4 Strings indexed by player COLOUR (0 Red, 1 Green, 2 Yellow, 3 Blue), the name to show for each seat in
## play ("" for a colour not at the table); see seat_colors() / names_by_color().
## (internal key `teams` is the Teams (2 v 2) mode; bot_level is the computer's move choice only — the dice are the
## same fair random rolls for everyone.)
## Layout never jumps: the mode row stays (Teams is disabled below 4 players) and the note keeps two lines.

signal start(config: Dictionary)

const PAIR_NOTE := "Teams: Red + Yellow vs Green + Blue."     # l10n   (old name kept for callers; shown through L10n.t)
const TEAMS_NOTE := PAIR_NOTE
const SWATCH_H := 76.0
const MAX_NAME := 12                    ## Pass & Play names (they must fit the game's player tiles)

var game := "ludo"
var mode := "cpu"
var color := 0
var count := 3                          # opponents (vs Computer) or players (Pass & Play)
var teams := false                      # Teams (2 v 2) chosen (applies with four players)
var bot_level := "normal"
var _mode_box: VBoxContainer
var _mode_seg: HBoxContainer
var _mode_info: Control
var _note: Label
var _swatches := []
var names: Array = ["", "", "", ""]     # Pass & Play: what was typed per seat (seat order; "" = the default)
var _box: VBoxContainer                 # where the options go (body; Pass & Play: a scroll area on short screens)
var _seat_rows := []                    # Pass & Play: [{row, dot, edit}] per seat


func _init(game_: String, mode_: String) -> void:
	game = game_
	mode = mode_
	count = 3 if mode == "cpu" else 4
	bot_level = _pref_level()
	_load_last()
	super((L10n.t("Play vs computer") if mode == "cpu" else L10n.t("Pass & Play")), UIKit.W.form, true, Sheet.LOOK_PM)
	body.add_theme_constant_override("separation", UIKit.SPACE.sm)
	_box = add_scroll_body(UIKit.SPACE.sm)   # grows with its content; scrolls only on short screens (4 name rows, 320x568)
	set_kicker(tr("Snakes & Ladders") if game == "sl" else tr("Ludo"))
	if mode == "cpu":
		_section(tr("Your colour"))
		var row := UIKit.hbox(UIKit.SPACE.sm)
		for c in 4:
			var b := Swatch.new(c, _colorblind())
			b.button_pressed = c == color
			b.pressed.connect(_pick_color.bind(c))
			UIKit.wire_press(b, "select")
			row.add_child(b)
			_swatches.append(b)
		_box.add_child(UIKit.margin(row, 0, 0, 0, UIKit.SPACE.xs))
		_section(tr("Opponents"))
		_box.add_child(UIKit.segmented([[1, "1"], [2, "2"], [3, "3"]], count, func(v): count = v; _sync()))
	else:
		_section(tr("Players"))
		_box.add_child(UIKit.segmented([[2, "2"], [3, "3"], [4, "4"]], count, func(v): count = v; _sync()))
		var seats := UIKit.vbox(UIKit.SPACE.sm)
		for i in 4:
			seats.add_child(_seat_row(i))
		_box.add_child(UIKit.margin(seats, 0, UIKit.SPACE.xs, 0, 0))
	if game == "ludo":
		_mode_box = UIKit.vbox(UIKit.SPACE.sm)
		var cap := _caption_row(tr("Mode"))
		_mode_info = Info.icon("team" if teams else "ind")
		cap.add_child(_mode_info)
		_mode_box.add_child(cap)
		_mode_seg = UIKit.segmented([[false, tr("Individual")], [true, tr("Teams (2 v 2)")]], teams, func(v): teams = v; _sync())
		var tb := _mode_seg.get_child(1) as Button                # below 4 players: the same look, faded (see _sync)
		tb.add_theme_stylebox_override("disabled", tb.get_theme_stylebox("normal"))
		tb.add_theme_color_override("font_disabled_color", Palette.MUTED)
		UIKit.deny_disabled(tb, func() -> String: return tr("Teams need 4 players."))
		_mode_box.add_child(_mode_seg)
		_box.add_child(_mode_box)
		if mode == "cpu":
			_section(tr("Difficulty"))
			_box.add_child(UIKit.segmented([["easy", tr("Easy")], ["normal", tr("Normal")], ["hard", tr("Hard")]], bot_level, func(v): bot_level = str(v); _sync()))
	_note = UIKit.paragraph("", UIKit.FS.body, Palette.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_note.custom_minimum_size.y = 44.0          # two lines reserved: the card never jumps when the note changes
	_box.add_child(_note)
	add_button(tr("Start game"), "honey", _submit, "lg")
	_sync()

func _ready() -> void:
	_nudge_modes.call_deferred()   # the Teams ⓘ pulses once the sheet is on screen (while unread)


# ---------- pieces ----------

## A row for a section caption (and an optional ⓘ after it).
func _caption_row(text: String) -> HBoxContainer:
	var h := UIKit.hbox(UIKit.SPACE.xs)
	h.custom_minimum_size.y = 24.0
	var l := UIKit.caption(text)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	return h

func _section(text: String) -> void:
	_box.add_child(UIKit.margin(_caption_row(text), 0, UIKit.SPACE.xs, 0, 0))

## Pass & Play: one seat, its colour (a disc with the colour-blind symbol when that's on) and its name field.
func _seat_row(i: int) -> HBoxContainer:
	var row := UIKit.hbox(UIKit.SPACE.sm)
	var dot := SeatDot.new(_colorblind())
	row.add_child(dot)
	var e := LineEdit.new()
	e.name = "Name%d" % (i + 1)
	e.max_length = MAX_NAME
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.custom_minimum_size = Vector2(0, UIKit.TAP)
	e.add_theme_font_override("font", UIKit.font_body(800))
	e.add_theme_font_size_override("font_size", UIKit.FS.h3)
	e.placeholder_text = L10n.seat_name(default_name(i))
	e.text = str(names[i]) if i < names.size() else ""
	e.select_all_on_focus = true
	e.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
	e.text_changed.connect(func(t: String): names[i] = t)
	e.focus_exited.connect(func():
		var clean := clean_name(e.text)
		if clean != e.text:
			e.text = clean
		names[i] = clean)
	row.add_child(e)
	_seat_rows.append({row = row, dot = dot, edit = e})
	return row

## The name a seat gets when its field is left empty: the profile's name for the first seat (when it has one),
## else "Player 1", "Player 2"...
static func default_name(seat: int) -> String:
	if seat == 0:
		var tree := Engine.get_main_loop() as SceneTree
		var save: Node = tree.root.get_node_or_null("Save") if tree and tree.root else null
		var prof: Variant = save.get("profile") if save else null
		var n := str((prof as Dictionary).get("name", "")) if prof is Dictionary else ""
		if n.strip_edges() != "" and n != "You":
			return n.substr(0, MAX_NAME)
	return "Player %d" % (seat + 1)

## Trimmed, single spaces, at most MAX_NAME characters.
static func clean_name(t: String) -> String:
	return " ".join(t.strip_edges().split(" ", false)).substr(0, MAX_NAME)

## The colours of the Pass & Play seats, in seat order (Ludo: 2 players sit opposite).
static func seat_colors(game_: String, count_: int) -> Array:
	if game_ == "sl":
		return range(clampi(count_, 2, 4))
	return [0, 2] if count_ == 2 else ([0, 1, 2] if count_ == 3 else [0, 1, 2, 3])

## cfg.names: [4] by colour from the typed names in seat order (an empty one gets default_name(seat)).
static func names_by_color(game_: String, count_: int, typed: Array) -> Array:
	var out := ["", "", "", ""]
	var cols := seat_colors(game_, count_)
	for i in cols.size():
		var t := clean_name(str(typed[i])) if i < typed.size() else ""
		out[int(cols[i])] = t if t != "" else default_name(i)
	return out


# ---------- changes ----------

func _pick_color(c: int) -> void:
	color = c
	for k in 4:
		_swatches[k].set_pressed_no_signal(k == c)
		_swatches[k].queue_redraw()
	_sync()

func _four() -> bool:
	return count == 3 if mode == "cpu" else count == 4

func _sync() -> void:
	var four := _four()
	var cols := seat_colors(game, count)
	for i in _seat_rows.size():
		var r: Dictionary = _seat_rows[i]
		(r.row as Control).visible = i < cols.size()
		if i < cols.size():
			(r.dot as SeatDot).set_color(int(cols[i]))
	if _mode_seg:
		var ind_b := _mode_seg.get_child(0) as Button
		var team_b := _mode_seg.get_child(1) as Button
		team_b.disabled = not four
		team_b.modulate.a = 1.0 if four else 0.45
		team_b.tooltip_text = "" if four else tr("Teams need 4 players.")
		ind_b.set_pressed_no_signal(not (four and teams))
		team_b.set_pressed_no_signal(four and teams)
	if _mode_info:
		var k := "team" if four and teams else "ind"
		if _mode_info.get("key") != k:
			if Info.is_open() and Info._bubble.anchor == _mode_info:
				Info.close()
			(_mode_info as Info.InfoIcon).stop_pulse()
			_mode_info.set("key", k)
	_note.text = _note_text()
	if is_inside_tree():
		_nudge_modes()

func _note_text() -> String:
	if game == "sl":
		return ((tr("Roll a 1 to enter.") + " ") if _sl_need_one() else "") + tr("First to square 100 wins.")
	if _four() and teams:
		if mode == "cpu":
			return tr("%s %s is your teammate.") % [tr(TEAMS_NOTE), tr(Palette.NAMES[(color + 2) % 4])]
		return tr(TEAMS_NOTE) + " " + tr("Teammates share the win.")
	if not _four():
		return tr("First to get all four pawns home wins.") + " " + tr("Teams need 4 players.")
	return tr("First to get all four pawns home wins.")

## Pulse the Teams ⓘ while Teams is chosen and that explanation is unread (never the Individual one: the choice
## comes first, SET-UP-02).
func _nudge_modes() -> void:
	if game != "ludo" or not is_inside_tree() or _mode_info == null:
		return
	Info.nudge("team", _four() and teams, self)

func _submit() -> void:
	var cfg := {}
	var level := bot_level if mode == "cpu" else _pref_level()
	if game == "sl":
		cfg = {game = "sl", mode = mode, n = count + 1 if mode == "cpu" else count, color = color, bot_level = level}
		if mode == "local":
			cfg.names = names_by_color(game, count, names)
	elif mode == "cpu":
		var rivals: Array = [2] if count == 1 else ([1, 2] if count == 2 else [1, 2, 3])   # offsets from my seat; one rival sits opposite
		var players := ["off", "off", "off", "off"]
		players[color] = "human"
		for k in rivals:
			players[(color + k) % 4] = "cpu"
		cfg = {game = "ludo", players = players, teams = count == 3 and teams, bot_level = level}
	else:
		var seats: Array = [0, 2] if count == 2 else ([0, 1, 2] if count == 3 else [0, 1, 2, 3])
		var players := []
		for c in 4:
			players.append("human" if seats.has(c) else "off")
		cfg = {game = "ludo", players = players, teams = count == 4 and teams, bot_level = level,
			names = names_by_color(game, count, names)}
	_save_last()
	start.emit(cfg)
	close()


# ---------- remembered setup (Save.prefs.last_setup[game][mode]) ----------

func _prefs() -> Variant:
	var tree := Engine.get_main_loop() as SceneTree
	var save: Node = tree.root.get_node_or_null("Save") if tree and tree.root else null
	return save.get("prefs") if save else null

func _pref_level() -> String:
	var p: Variant = _prefs()
	var v: Variant = (p as Dictionary).get("bot_level", "normal") if p is Dictionary else "normal"
	return str(v) if ["easy", "normal", "hard"].has(v) else "normal"

func _colorblind() -> bool:
	var p: Variant = _prefs()
	return p is Dictionary and bool((p as Dictionary).get("colorblind", false))

func _sl_need_one() -> bool:
	var p: Variant = _prefs()
	return p is Dictionary and bool((p as Dictionary).get("sl_need_one", false))

## Pre-fill from the last setup of this game and mode; anything missing or out of range keeps the defaults.
func _load_last() -> void:
	var p: Variant = _prefs()
	if not p is Dictionary:
		return
	var all: Variant = (p as Dictionary).get("last_setup")
	if not all is Dictionary or not (all as Dictionary).get(game) is Dictionary:
		return
	var last: Variant = ((all as Dictionary)[game] as Dictionary).get(mode)
	if not last is Dictionary:
		return
	var d := last as Dictionary
	var lo := 1 if mode == "cpu" else 2
	var hi := 3 if mode == "cpu" else 4
	if typeof(d.get("count")) in [TYPE_INT, TYPE_FLOAT]:
		count = clampi(int(d.count), lo, hi)
	if mode == "cpu" and typeof(d.get("color")) in [TYPE_INT, TYPE_FLOAT]:
		color = clampi(int(d.color), 0, 3)
	teams = bool(d.get("teams", false)) and game == "ludo"
	if mode == "cpu" and ["easy", "normal", "hard"].has(d.get("bot_level")):
		bot_level = str(d.bot_level)
	if mode == "local" and d.get("names") is Array:
		for i in mini(4, (d.names as Array).size()):
			names[i] = clean_name(str(d.names[i]))

func _save_last() -> void:
	var p: Variant = _prefs()
	if not p is Dictionary:
		return
	var prefs := p as Dictionary
	if not prefs.get("last_setup") is Dictionary:
		prefs.last_setup = {}
	var all: Dictionary = prefs.last_setup
	if not all.get(game) is Dictionary:
		all[game] = {}
	var entry := {count = count, color = color, teams = teams}
	if mode == "local":
		var typed := []
		for i in 4:
			typed.append(clean_name(str(names[i])))
		entry.names = typed                  # seat order, "" = the default name
	if mode == "cpu" and game == "ludo":
		entry.bot_level = bot_level
		prefs.bot_level = bot_level
	(all[game] as Dictionary)[mode] = entry
	var save := (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Save")
	if save:
		save.save()


# ---------- widgets ----------

## A colour choice: the player colour face with a darker lip, the colour name (and the colour-blind symbol when
## that setting is on). Selected: a 3 px honey ring 3 px outside the face and a ✓ badge on the corner.
class Swatch extends Button:
	var c := 0
	var _ring: StyleBoxFlat
	var _badge: StyleBoxFlat
	var _check: Texture2D

	func _init(c_: int, symbols := false) -> void:
		c = c_
		toggle_mode = true
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(0, SetupSheet.SWATCH_H)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tooltip_text = tr(Palette.NAMES[c])
		var face: Color = Palette.PLAYER[c]
		var deep: Color = Palette.PLAYER_DARK[c]
		# a light tint of the colour with its colour as the rim, so the real pawn in that colour reads on it
		var normal := UIKit.box(face.lerp(Color.WHITE, 0.78), UIKit.R.md, UIKit.BW.line, face)
		normal.border_width_bottom = UIKit.LIP.md
		normal.border_color = face
		normal.shadow_size = 3
		normal.shadow_offset = Vector2(0, 3)
		normal.shadow_color = Color(deep, 0.55)
		var down := normal.duplicate() as StyleBoxFlat
		down.border_width_bottom = UIKit.BW.line
		down.shadow_offset = Vector2(0, 1)
		down.expand_margin_top = -2
		for st in ["normal", "hover"]:
			add_theme_stylebox_override(st, normal)
		for st in ["pressed", "hover_pressed"]:
			add_theme_stylebox_override(st, normal)
		add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		button_down.connect(func(): add_theme_stylebox_override("normal", down); add_theme_stylebox_override("pressed", down))
		button_up.connect(func(): add_theme_stylebox_override("normal", normal); add_theme_stylebox_override("pressed", normal))
		# the pawn of this colour over its name (the colour-blind symbol rides on the pawn)
		var row := UIKit.vbox(0)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.offset_bottom = -UIKit.LIP.md
		var pawn := SeatDot.new(symbols)
		pawn.custom_minimum_size = Vector2(32, 38)
		pawn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		pawn.set_color(c)
		row.add_child(pawn)
		var l := UIKit.label(tr(Palette.NAMES[c]), UIKit.FS.label, deep, UIKit.font_body(900))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		l.clip_text = true
		row.add_child(l)
		add_child(row)
		_ring = StyleBoxFlat.new()
		_ring.draw_center = false
		_ring.set_border_width_all(UIKit.BW.rim)
		_ring.border_color = Palette.HONEY
		_ring.set_corner_radius_all(UIKit.R.md + 6)
		_ring.corner_detail = 10
		_ring.anti_aliasing = true
		_badge = UIKit.box(Palette.HONEY, UIKit.R.pill, UIKit.BW.line, Color.WHITE)
		_badge.shadow_size = 2
		_badge.shadow_offset = Vector2(0, 1)
		_badge.shadow_color = Palette.shadow(0.3)
		_check = UIKit.svg("ic_check")
		toggled.connect(func(_on: bool): queue_redraw())

	func _draw() -> void:
		if not button_pressed:
			return
		draw_style_box(_ring, Rect2(Vector2.ZERO, size).grow(6.0))
		var d := 22.0
		var p := Vector2(size.x - d + 7.0, -7.0)
		draw_style_box(_badge, Rect2(p, Vector2(d, d)))
		if _check:
			draw_texture_rect(_check, Rect2(p + Vector2(5, 5), Vector2(d - 10, d - 10)), false, Palette.ON_HONEY)


## A seat's colour as the board's pawn in that colour (PawnArt; with the colour-blind symbol on its body when that
## setting is on). Same size on every row; used by the Pass & Play rows, the colour choices and the lobby.
class SeatDot extends Control:
	var c := 0
	var symbols := false
	var _sym: TextureRect
	var rim := Color.TRANSPARENT          ## a white rim for a pawn on its own colour (the colour choices)

	func _init(symbols_ := false) -> void:
		symbols = symbols_
		custom_minimum_size = Vector2(40, 44)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		if symbols:
			_sym = UIKit.symbol(0, 14)
			_sym.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(_sym)

	func set_color(c_: int) -> void:
		c = c_
		tooltip_text = tr(Palette.NAMES[c])
		if _sym:
			_sym.texture = UIKit.svg("sym_" + str(Palette.SYMBOL[c]))
		queue_redraw()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED and _sym:
			var d := minf(size.x, size.y) * 0.3
			_sym.size = Vector2(d, d)
			_sym.position = Vector2(size.x / 2.0 - d / 2.0, size.y * 0.66 - d / 2.0)

	func _draw() -> void:
		PawnArt.draw(self, Rect2(Vector2.ZERO, size).grow(-1.0), c, rim)
