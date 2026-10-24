class_name HowToSheet
extends Sheet
## How to play (index.html #howSheet and the INFO texts), in the .pm look with the "How to play" ribbon like its
## sister sheets. Folder tabs Ludo / Snakes & Ladders (it opens on the game picked on Home) over one pane; each tab
## lists its rules as cream cards (UIKit.surface("row")) with an icon per topic (Ludo: basics, captures & safe
## squares, pairs, Teams (2 v 2); Snakes & Ladders: its card), then the fair-dice promise. Only the pane scrolls.
## The close X is the only way out. The rules follow the house-rule settings (pair_ask, sl_need_one).
## The Ludo tab starts with a "Replay tutorial" row (from Home only, not over a live match): it starts the guided first
## match through the app (main.start_ludo(Tutorial.config()), which closes the sheets).
## The texts restate ludo_rules.gd / snakes_ladders_rules.gd: change them together with Info.INFO.

## Static sections; the pairs and Snakes & Ladders cards are built by sections() (they follow the house rules).
const SECTIONS := [
	{t = "Ludo basics", c = 0, icon = "res://assets/ui/home/hi_ludo.svg", game = "ludo", b = [
		"Get all four of your pawns around the board and into the centre. The first player with all four home wins.",
		"Roll a [b]6[/b] to bring a pawn out of your base.",
		"Tap a glowing pawn to move it. When only one move is possible, it moves by itself.",
		"A [b]6[/b], a capture or getting a pawn home earns you [b]another roll[/b]. Roll three 6s in a row and you lose the turn.",
		"You need the [b]exact number[/b] to reach the centre. A bigger roll can’t move that pawn."]},
	{t = "Captures & safe squares", c = 1, icon = "ic_star", game = "ludo", b = [
		"Land on a loose pawn of another colour to send it [b]back to its base[/b], then roll again.",
		"A single pawn captures one pawn at a time, even from a stack.",
		"[b]Star squares[/b] and [b]coloured start squares[/b] are safe: nobody can be captured there."]},
]
const TEAMS := {t = "Teams (2 v 2)", c = 3, icon = "perk_friends", game = "ludo", b = [
	"Two teams of teammates sitting opposite: [b]Red + Yellow[/b] play against [b]Green + Blue[/b]. Four players only.",
	"Teammates never capture or block each other. Only the other team’s pawns can be captured.",
	"All four of your pawns home? Roll a [b]6[/b] to start [b]Help your teammate[/b]. Until then your turn passes.",
	"That 6 already moves your teammate’s pawns, and so does every roll after it.",
	"Your team wins when [b]both teammates[/b] have all four pawns home."]}
const FAIR_DICE := "Every roll is random and the same for every player — the computer never gets better dice."

const FIXED_H := 680.0                   ## one card height for both tabs
const REPLAY_TITLE := "New to Ludo?"
const REPLAY_TEXT := "A one-minute guided game."
const REPLAY_BUTTON := "Replay tutorial"

var game := "ludo"                       ## the tab on show: "ludo" | "sl"
var _width := 370.0
var _scroll: ScrollContainer             # (old name) the scroll area
var _inner: VBoxContainer                # (old name) its content
var _tabs: TabStrip
var _panes := {}                         # game -> VBoxContainer
var replay_button: Button                ## "Replay tutorial" (null when the app can't start it from here)


## start: "ludo" | "sl" | "" (= the game picked on Home, Save.prefs.home_game).
func _init(width := 370.0, start := "") -> void:
	super("How to play", width, true, LOOK_PM)
	_width = width
	game = start if start in ["ludo", "sl"] else ("sl" if _pref_str("home_game") == "sl" else "ludo")
	var stack := UIKit.vbox(0)
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(stack)
	_tabs = TabStrip.new([
		{key = "ludo", text = "Ludo", icon = "res://assets/ui/home/hi_ludo.svg"},
		{key = "sl", text = "Snakes & Ladders", icon = "res://assets/ui/home/hi_snakes.svg"},
	], game, "folder")
	_tabs.picked.connect(show_game)
	stack.add_child(UIKit.margin(_tabs, 0, UIKit.SPACE.sm, 0, 0))
	var pane := PanelContainer.new()
	var ps := TabStrip.pane_style("folder")
	ps.content_margin_left = UIKit.PAD.pane - 2
	ps.content_margin_right = UIKit.PAD.pane - 2
	ps.content_margin_top = UIKit.PAD.pane
	ps.content_margin_bottom = UIKit.SPACE.sm
	pane.add_theme_stylebox_override("panel", ps)
	pane.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(pane)
	_inner = add_scroll_body(UIKit.SPACE.md)
	_scroll = scroll_box
	var wrap := scroll_box.get_parent()     # the scroll area lives in the folder pane, under the tabs
	body.remove_child(wrap)
	pane.add_child(wrap)
	var fade := wrap.get_node_or_null("Fade") as TextureRect
	if fade:                                 # the scroll fade blends into the pane's cream
		var g := Gradient.new()
		g.colors = PackedColorArray([Color(Palette.PANE, 0.0), Palette.PANE])
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.width = 4
		gt.height = 32
		gt.fill_from = Vector2(0.5, 0.0)
		gt.fill_to = Vector2(0.5, 1.0)
		fade.texture = gt
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
	_tabs.select(game)
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

func _replay_card() -> PanelContainer:
	var h := UIKit.hbox(UIKit.SPACE.md)
	var ic := UIKit.icon("ic_hand", 32)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var v := UIKit.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(UIKit.label(REPLAY_TITLE, UIKit.FS.h3, Palette.INK, UIKit.font_body(900)))
	var p := UIKit.paragraph(REPLAY_TEXT, UIKit.FS.small, Palette.SUB)
	v.add_child(p)
	h.add_child(v)
	replay_button = UIKit.btn(REPLAY_BUTTON, "honey", "sm")
	replay_button.name = "ReplayTutorial"
	replay_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	replay_button.custom_minimum_size.y = maxf(replay_button.custom_minimum_size.y, UIKit.TAP)
	replay_button.pressed.connect(replay_tutorial)
	h.add_child(replay_button)
	return UIKit.panel("row", h)

## Every rules card in order, with the house rules applied (Save.prefs.pair_ask, sl_need_one).
static func sections() -> Array:
	var ask := _pref("pair_ask")
	var need_one := _pref("sl_need_one")
	var pairs := {t = "Pairs", c = 2, icon = "two_pawns", game = "ludo", b = [
		"Land a pawn on another of your own and they join into a [b]pair[/b]. Pairs never form on a start square or in the home lane, and never by themselves on a star.",
		("[b]Ask before pairing[/b] is on: you choose each time." if ask else "Pairs form by themselves. Turn on [b]Ask before pairing[/b] in Settings to choose each time."),
		"A pair moves on [b]even rolls only[/b], and half the roll: a 4 moves it 2 squares. Tap either pawn of a pair to move it.",
		"Single pawns can’t jump your pair. They must land on it, then roll exactly a [b]1[/b] to move on.",
		"[b]Only a pair can capture a pair[/b], and a pair never captures a single pawn.",
		"A pair splits by itself on any coloured start square or when it enters its home lane."]}
	var sl := {t = "Snakes & Ladders", c = -1, icon = "res://assets/ui/home/hi_snakes.svg", game = "sl", b = [
		("Everyone starts off the board. Roll a [b]1[/b] to step onto square 1 (house rule [b]Need a 1 to start[/b])." if need_one
				else "Everyone starts off the board. [b]Any roll[/b] moves you on: a 3 takes you to square 3."),
		"Land on the foot of a [b]ladder[/b] to climb it. Land on a [b]snake’s head[/b] to slide down to its tail.",
		"A [b]6[/b] gives you another roll. Three 6s in a row end your turn.",
		"You need the [b]exact roll[/b] to land on 100. The first player to reach square [b]100[/b] wins."]}
	if not need_one:
		(sl.b as Array).append("For the classic start, turn on [b]Need a 1 to start[/b] in Settings.")
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


## A cream card: the topic's icon (else a coloured chip) + title, then the rules as a bulleted list.
func _section(title_text: String, colour: int, lines: Array, icon := "") -> PanelContainer:
	var accent: Color = Palette.TEAL if colour < 0 else Palette.PLAYER[colour]
	var v := UIKit.vbox(UIKit.SPACE.xs)
	var head := UIKit.hbox(UIKit.SPACE.sm)
	var tex := UIKit.svg(icon) if icon != "" else null
	if tex:
		var ic := UIKit.icon(icon, 30)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(ic)
	else:
		var chip := Panel.new()
		chip.custom_minimum_size = Vector2(14, 14)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		chip.add_theme_stylebox_override("panel", UIKit.box(accent, 5, UIKit.BW.line, Color.WHITE))
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_child(chip)
	var t := UIKit.label(title_text, UIKit.FS.h2, Palette.INK, UIKit.font_display())
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(t)
	v.add_child(UIKit.margin(head, 0, 0, 0, UIKit.SPACE.xxs))
	for line: String in lines:
		v.add_child(_bullet(line))
	return UIKit.panel("row", v)

## The fair-dice promise: a honey-tinted card with the star icon.
func _fair_card(skill_line := true) -> PanelContainer:
	var h := UIKit.hbox(UIKit.SPACE.md)
	var ic := UIKit.icon("cat_dice", 32)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var v := UIKit.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(UIKit.label("Fair dice", UIKit.FS.h2, Palette.INK, UIKit.font_display()))
	var p := UIKit.paragraph(FAIR_DICE, UIKit.FS.body, Palette.INK)
	v.add_child(p)
	if skill_line:
		v.add_child(UIKit.paragraph("Computer skill (Easy, Normal, Hard) only changes how it moves.", UIKit.FS.small, Palette.SUB))
	h.add_child(v)
	var st := UIKit.surface("row", true).duplicate() as StyleBoxFlat
	st.bg_color = Palette.HONEY_TINT
	st.border_color = Palette.HONEY_TINT_EDGE
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", st)
	panel.add_child(h)
	return panel

## One rule: a dot (UIKit.bullet) and wrapped text (RichTextLabel, [b] for bold in INK_STRONG).
func _bullet(bb: String) -> HBoxContainer:
	var h := UIKit.hbox(UIKit.SPACE.xxs)
	h.add_child(UIKit.bullet(Palette.INK))
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.mouse_filter = Control.MOUSE_FILTER_PASS
	r.selection_enabled = false
	r.add_theme_font_override("normal_font", UIKit.font_body(700))
	r.add_theme_font_override("bold_font", UIKit.font_body(900))
	r.add_theme_font_size_override("normal_font_size", UIKit.FS.body)
	r.add_theme_font_size_override("bold_font_size", UIKit.FS.body)
	r.add_theme_color_override("default_color", Palette.INK)
	r.add_theme_constant_override("line_separation", 2)
	var strong := Palette.INK_STRONG.to_html(false)
	r.text = bb.replace("[b]", "[b][color=#%s]" % strong).replace("[/b]", "[/color][/b]")
	h.add_child(r)
	return h


# ---------- shared with the other sheets (forwarders) ----------

## (old) A vertical-only scroll area with a slim honey scrollbar: use UIKit.scroll().
static func make_scroll() -> ScrollContainer:
	return UIKit.scroll()

## (old) Fit a card and its scroll area to the screen: use Sheet.fit() / add_scroll_body() (Sheet.fit_card).
static func fit_card(c: Control, sc: ScrollContainer, inner: Control, width: float, vp: Vector2) -> void:
	Sheet.fit_card(c, sc, inner, width, vp)
