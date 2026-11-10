class_name HowToSheet
extends Sheet
## How to play (index.html #howSheet and the INFO texts), a game-look popup (the dark café card, the outlined gold
## title, the round red X). A two-way choice Ludo / Snakes & Ladders (ShopSheet's filter buttons; it opens on the game
## picked on Home) over the rules: each topic a wood tile with its icon and an outlined white title, the rules as cream
## lines with gold dots and the key words in white (Ludo: basics, captures & safe squares, pairs, Teams (2 v 2);
## Snakes & Ladders: its card), then the fair-dice promise on a gold-rimmed tile. Only the rules scroll.
## The close X is the only way out. The rules follow the house-rule settings (pair_ask, sl_need_one).
## The Ludo tab starts with a "Replay tutorial" row (from Home only, not over a live match): it starts the guided first
## match through the app (main.start_ludo(Tutorial.config()), which closes the sheets).
## The texts restate ludo_rules.gd / snakes_ladders_rules.gd: change them together with Info.INFO.

## l10n-keys: t
## Static sections; the pairs and Snakes & Ladders cards are built by sections() (they follow the house rules).
const SECTIONS := [
	{t = "Ludo basics", c = 0, icon = "res://assets/ui/home/hi_ludo.svg", game = "ludo", b = [
		"Get all four of your pawns around the board and into the centre. The first player with all four home wins.",  # l10n
		"Roll a [b]6[/b] to bring a pawn out of your base.",  # l10n
		"Tap a glowing pawn to move it. When only one move is possible, it moves by itself.",  # l10n
		"A [b]6[/b], a capture or getting a pawn home earns you [b]another roll[/b]. Roll three 6s in a row and you lose the turn.",  # l10n
		"You need the [b]exact number[/b] to reach the centre. A bigger roll can’t move that pawn."]},  # l10n
	{t = "Captures & safe squares", c = 1, icon = "ic_star", game = "ludo", b = [
		"Land on a loose pawn of another colour to send it [b]back to its base[/b], then roll again.",  # l10n
		"A single pawn captures one pawn at a time, even from a stack.",  # l10n
		"[b]Star squares[/b] and [b]coloured start squares[/b] are safe: nobody can be captured there."]},  # l10n
]
const TEAMS := {t = "Teams (2 v 2)", c = 3, icon = "perk_friends", game = "ludo", b = [
	"Two teams of teammates sitting opposite: [b]Red + Yellow[/b] play against [b]Green + Blue[/b]. Four players only.",  # l10n
	"Teammates never capture or block each other. Only the other team’s pawns can be captured.",  # l10n
	"All four of your pawns home? Roll a [b]6[/b] to start [b]Help your teammate[/b]. Until then your turn passes.",  # l10n
	"That 6 already moves your teammate’s pawns, and so does every roll after it.",  # l10n
	"Your team wins when [b]both teammates[/b] have all four pawns home."]}  # l10n
const FAIR_DICE := "Every roll is random and the same for every player — the computer never gets better dice."  # l10n

const FIXED_H := 680.0                   ## one card height for both tabs
const REPLAY_TITLE := "New to Ludo?"  # l10n
const REPLAY_TEXT := "A one-minute guided game."  # l10n
const REPLAY_BUTTON := "Replay tutorial"  # l10n

var game := "ludo"                       ## the tab on show: "ludo" | "sl"
var _width := 370.0
var _scroll: ScrollContainer             # (old name) the scroll area
var _inner: VBoxContainer                # (old name) its content
var _tabs: HBoxContainer                # the Ludo / Snakes & Ladders choice (filter buttons, meta "value")
var _panes := {}                         # game -> VBoxContainer
var replay_button: Button                ## "Replay tutorial" (null when the app can't start it from here)


## start: "ludo" | "sl" | "" (= the game picked on Home, Save.prefs.home_game).
func _init(width := 370.0, start := "") -> void:
	super(tr("How to play"), width, true, LOOK_GAME)
	_width = width
	game = start if start in ["ludo", "sl"] else ("sl" if _pref_str("home_game") == "sl" else "ludo")
	_tabs = UIKit.hbox(8)
	_tabs.name = "GameTabs"
	var group := ButtonGroup.new()
	for t: Array in [["ludo", tr("Ludo"), "res://assets/ui/home/hi_ludo.svg"], ["sl", tr("Snakes & Ladders"), "res://assets/ui/home/hi_snakes.svg"]]:
		var b := ShopSheet.filter_button(str(t[1]), group, 46.0, 15)
		b.icon = UIKit.svg(str(t[2]))
		b.add_theme_constant_override("icon_max_width", 22)
		b.size_flags_stretch_ratio = 1.0 if t[0] == "ludo" else 1.7     # the long name gets the room
		b.add_theme_constant_override("h_separation", 6)
		b.clip_text = true
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.set_meta("value", t[0])
		var key: String = t[0]
		b.toggled.connect(func(on: bool):
			if on and key != game:
				show_game(key))
		UIKit.wire_press(b)
		_tabs.add_child(b)
	body.add_child(_tabs)
	_inner = add_scroll_body(UIKit.SPACE.md)
	_scroll = scroll_box
	fit(0.88, FIXED_H)
	for key in ["ludo", "sl"]:
		var v := UIKit.vbox(UIKit.SPACE.md)
		if key == "ludo" and can_replay():
			v.add_child(_replay_card())
		for sec: Dictionary in sections():
			if str(sec.get("game", "ludo")) == key:
				v.add_child(_section(str(sec.t), int(sec.c), sec.b, str(sec.get("icon", ""))))
		v.add_child(_fair_card(key == "ludo"))     # computer skill: Ludo only (S&L is pure dice)
		_inner.add_child(v)
		_panes[key] = v
	show_game(game)


## Show the rules of one game ("ludo" | "sl"), from the top.
func show_game(key: String) -> void:
	game = "sl" if key == "sl" else "ludo"
	for b: Button in _tabs.get_children():
		b.set_pressed_no_signal(b.get_meta("value") == game)
	for k in _panes:
		(_panes[k] as Control).visible = k == game
	if scroll_box:
		scroll_box.scroll_vertical = 0


## The app (main.gd) that can start the tutorial: the root's "Main" (the way the other sheets reach it).
static func _app() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	var app := tree.root.get_node_or_null("Main")
	return app if app else tree.root.find_child("Main", true, false)

## The replay row shows when the app can start a game and no match is on (Home): replaying from the pause menu's
## Settings would end the live match.
static func can_replay() -> bool:
	var app := _app()
	return app != null and app.has_method("start_ludo") and str(app.get("screen")) == "home"

## Starts the guided first match (the app closes the sheets as the game screen comes up).
func replay_tutorial() -> void:
	var app := _app()
	if app and app.has_method("start_ludo"):
		app.call("start_ludo", Tutorial.config())

func _replay_card() -> Control:
	var h := UIKit.hbox(UIKit.SPACE.md)
	var ic := UIKit.icon("ic_hand", 34)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var v := UIKit.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var t := GameUI.outlined(tr(REPLAY_TITLE), 20, GameUI.TEXT, 2)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size.x = 40          # (a wrapping label with no width yet asks for one glyph per line)
	v.add_child(t)
	var p := GameUI.text(tr(REPLAY_TEXT), 14, GameUI.SUB)
	p.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	p.custom_minimum_size.x = 40
	v.add_child(p)
	h.add_child(v)
	# icon + text on one line, the full-width button under it
	var col := UIKit.vbox(UIKit.SPACE.md)
	col.add_child(h)
	replay_button = GameUI.button(tr(REPLAY_BUTTON), "gold", "md")
	replay_button.name = "ReplayTutorial"
	GameUI.fit_button_text(replay_button, 13)
	replay_button.pressed.connect(replay_tutorial)
	col.add_child(replay_button)
	var tile := GameUI.tile(18.0, 14.0)
	tile.add_child(col)
	return tile

## Every rules card in order, with the house rules applied (Save.prefs.pair_ask, sl_need_one).
static func sections() -> Array:
	var ask := _pref("pair_ask")
	var need_one := _pref("sl_need_one")
	var pairs := {t = "Pairs", c = 2, icon = "two_pawns", game = "ludo", b = [
		"Land a pawn on another of your own and they join into a [b]pair[/b]. Pairs never form on a start square or in the home lane, and never by themselves on a star.",  # l10n
		("[b]Ask before pairing[/b] is on: you choose each time." if ask else "Pairs form by themselves. Turn on [b]Ask before pairing[/b] in Settings to choose each time."),  # l10n
		"A pair moves on [b]even rolls only[/b], and half the roll: a 4 moves it 2 squares. Tap either pawn of a pair to move it.",  # l10n
		"Single pawns can’t jump your pair. They must land on it, then roll exactly a [b]1[/b] to move on.",  # l10n
		"[b]Only a pair can capture a pair[/b], and a pair never captures a single pawn.",  # l10n
		"A pair splits by itself on any coloured start square or when it enters its home lane."]}  # l10n
	var sl := {t = "Snakes & Ladders", c = -1, icon = "res://assets/ui/home/hi_snakes.svg", game = "sl", b = [
		("Everyone starts off the board. Roll a [b]1[/b] to step onto square 1 (house rule [b]Need a 1 to start[/b])." if need_one  # l10n
				else "Everyone starts off the board. [b]Any roll[/b] moves you on: a 3 takes you to square 3."),  # l10n
		"Land on the foot of a [b]ladder[/b] to climb it. Land on a [b]snake’s head[/b] to slide down to its tail.",  # l10n
		"A [b]6[/b] gives you another roll. Three 6s in a row end your turn.",  # l10n
		"You need the [b]exact roll[/b] to land on 100. The first player to reach square [b]100[/b] wins."]}  # l10n
	if not need_one:
		(sl.b as Array).append("For the classic start, turn on [b]Need a 1 to start[/b] in Settings.")  # l10n
	return SECTIONS + [pairs, TEAMS, sl]

static func _pref_str(name: String) -> String:
	var tree := Engine.get_main_loop() as SceneTree
	var save: Node = tree.root.get_node_or_null("Save") if tree and tree.root else null
	var prefs: Variant = save.get("prefs") if save else null
	return str((prefs as Dictionary).get(name, "")) if prefs is Dictionary else ""

static func _pref(name: String) -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	var save: Node = tree.root.get_node_or_null("Save") if tree and tree.root else null
	var prefs: Variant = save.get("prefs") if save else null
	return prefs is Dictionary and bool((prefs as Dictionary).get(name, false))


## A wood tile: the topic's icon (else a coloured chip) + its title in outlined white, then the rules as a dotted list.
func _section(title_text: String, colour: int, lines: Array, icon := "") -> Control:
	var accent: Color = Palette.TEAL if colour < 0 else Palette.PLAYER[colour]
	var v := UIKit.vbox(UIKit.SPACE.xs)
	var head := UIKit.hbox(UIKit.SPACE.sm)
	var tex := UIKit.svg(icon) if icon != "" else null
	if tex:
		var ic := UIKit.icon(icon, 32)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(ic)
	else:
		var chip := Panel.new()
		chip.custom_minimum_size = Vector2(16, 16)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		chip.add_theme_stylebox_override("panel", UIKit.box(accent, 5, UIKit.BW.line, Color.WHITE))
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_child(chip)
	var t := GameUI.outlined(tr(title_text), 21, GameUI.TEXT, 2)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size.x = 40
	head.add_child(t)
	v.add_child(UIKit.margin(head, 0, 0, 0, UIKit.SPACE.xs))
	for line: String in lines:
		v.add_child(_bullet(line))
	var tile := GameUI.tile(18.0, 14.0)
	tile.add_child(v)
	return tile

## The fair-dice promise: a wood tile with a gold rim and the dice icon, its title in gold.
func _fair_card(skill_line := true) -> Control:
	var h := UIKit.hbox(UIKit.SPACE.md)
	var ic := UIKit.icon("cat_dice", 34)
	ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(ic)
	var v := UIKit.vbox(3)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(GameUI.outlined(tr("Fair dice"), 21, GameUI.GOLD, 2))
	var p := GameUI.text(tr(FAIR_DICE), 15, GameUI.TEXT)
	p.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	p.custom_minimum_size.x = 40
	v.add_child(p)
	if skill_line:
		var s := GameUI.text(tr("Computer skill (Easy, Normal, Hard) only changes how it moves."), 13, GameUI.SUB)
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		s.custom_minimum_size.x = 40
		v.add_child(s)
	h.add_child(v)
	var tile := GameUI.tile(18.0, 14.0)
	tile.border_color = Palette.GL_CHIP_RIM
	tile.add_child(h)
	return tile

## One rule: a gold dot and wrapped cream text (RichTextLabel, [b] for the key words in white).
func _bullet(bb: String) -> HBoxContainer:
	var h := UIKit.hbox(UIKit.SPACE.xxs)
	var dot := UIKit.bullet(GameUI.GOLD, 6.0)
	h.add_child(dot)
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.mouse_filter = Control.MOUSE_FILTER_PASS
	r.selection_enabled = false
	r.add_theme_font_override("normal_font", UIKit.font_body(800))
	r.add_theme_font_override("bold_font", UIKit.font_body(900))
	r.add_theme_font_size_override("normal_font_size", 15)
	r.add_theme_font_size_override("bold_font_size", 15)
	r.add_theme_color_override("default_color", GameUI.SUB)
	r.add_theme_constant_override("line_separation", 3)
	var strong := Color.WHITE.to_html(false)
	r.text = tr(bb).replace("[b]", "[b][color=#%s]" % strong).replace("[/b]", "[/color][/b]")
	h.add_child(r)
	return h


# ---------- shared with the other sheets (forwarders) ----------

## (old) A vertical-only scroll area with a slim honey scrollbar: use UIKit.scroll().
static func make_scroll() -> ScrollContainer:
	return UIKit.scroll()

## (old) Fit a card and its scroll area to the screen: use Sheet.fit() / add_scroll_body() (Sheet.fit_card).
static func fit_card(c: Control, sc: ScrollContainer, inner: Control, width: float, vp: Vector2) -> void:
	Sheet.fit_card(c, sc, inner, width, vp)
