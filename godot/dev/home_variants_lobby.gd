extends Control
## Dev (W1): three candidate home layouts over the real café, built from the shared pieces the final HomeScreen
## will use (top bar, feature buttons, game entry, quick-resume slot, bottom nav). Driven by dev/home_variants.gd.
##   A  "Two game cards"  logo, feature row under the top bar, the table as the hero, Ludo / S&L cards side by side
##   B  "Game switcher"   one game banner (Ludo <-> S&L), a mode switch and one big Play; features docked right
##   C  "Scene + dock"    the café scene up top, a cream dock below with folder tabs (Ludo / S&L), the two mode
##                        buttons, the nav; the three features sit on the dock's top edge

signal play(game: String, mode: String)
signal open_tab(tab: String)

const HI := "res://assets/ui/home/hi_%s.svg"
const BAR_H := 52.0
const NAV_H := 64.0
const G := 16.0                         # screen gutter

var variant := "A"
var quick := {}                         # {kind: "continue" | "again", title, sub} or {} (no quick slot)
var safe_top := 0.0
var safe_bottom := 0.0
var game := "ludo"
var mode := "cpu"

var logo: BrandLogo
var _top: HBoxContainer
var _nav: Control
var _feat: Array = []                   # feature controls
var _quick: Control
var _cards: Array = []                  # A: game cards
var _banner: Control                    # B
var _seg: Control                       # B
var _playb: Button                      # B
var _dock: Panel                        # C
var _switch: PanelContainer             # C
var _modes: HBoxContainer               # C
var _band := Vector2.ZERO


func _init(variant_ := "A", quick_ := {}) -> void:
	variant = variant_
	quick = quick_


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil()
	_top = _top_bar()
	add_child(_top)
	logo = BrandLogo.new()
	logo.bob = true
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(logo)
	match variant:
		"A": _build_a()
		"B": _build_b()
		_: _build_c()
	resized.connect(_layout)
	_layout.call_deferred()


# =====================================================================================================================
# shared pieces
# =====================================================================================================================

func _veil() -> void:
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(Palette.VEIL, 0.45), Color(Palette.VEIL, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0.5, 0.0)
	gt.fill_to = Vector2(0.5, 1.0)
	var veil := TextureRect.new()
	veil.texture = gt
	veil.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.name = "Veil"
	add_child(veil)


static func _flat_button(st: StyleBox, pr: StyleBox = null) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	for k in ["normal", "hover", "disabled"]:
		b.add_theme_stylebox_override(k, st)
	for k in ["pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(k, pr if pr else st)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	UIKit.wire_press(b)
	return b


## The cream glass chip style of the lobby (top bar, feature chips, quick slot): glass + white rim + soft shadow.
static func _chip_style(r := 18, pressed := false) -> StyleBoxFlat:
	var s := UIKit.box(Palette.GLASS_PRESSED if pressed else Palette.GLASS, r, UIKit.BW.line, Color.WHITE)
	UIKit.shade(s, "sm")
	UIKit.pad(s, 8, 6)
	return s


func _top_bar() -> HBoxContainer:
	var row := UIKit.hbox(8)
	var p: Dictionary = Save.profile
	# player chip: avatar, name, level star over the XP bar
	var chip := _flat_button(_chip_style(), _chip_style(18, true))
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chip.custom_minimum_size = Vector2(0, BAR_H)
	chip.pressed.connect(func(): open_tab.emit("profile"))
	row.add_child(chip)
	var r := UIKit.hbox(8)
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.offset_left = 5; r.offset_top = 5; r.offset_right = -10; r.offset_bottom = -5
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(r)
	var av := Collection.make_avatar(42)
	av.mouse_filter = Control.MOUSE_FILTER_IGNORE
	av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.add_child(av)
	var col := UIKit.vbox(3)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_child(col)
	var nm := UIKit.label(str(p.get("name", "You")), UIKit.FS.label + 1, Palette.INK, UIKit.font_body(900))
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.clip_text = true
	col.add_child(nm)
	var li := Save.level_info(int(p.get("xp", 0)))
	var m := Meter.new("xp", 10)
	m.set_value(float(li.into), float(li.need))
	var lv := LevelBadge.row(LevelBadge.new(int(li.level), "xs"), m)
	lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(lv)
	# coins: the balance + a teal "+" (opens the Earn coins hub)
	var coins := _flat_button(_chip_style(UIKit.R.pill), _chip_style(UIKit.R.pill, true))
	coins.custom_minimum_size = Vector2(0, BAR_H)
	coins.pressed.connect(func(): open_tab.emit("coins"))
	row.add_child(coins)
	var cr := UIKit.hbox(6)
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cr.offset_left = 6; cr.offset_right = -6
	cr.alignment = BoxContainer.ALIGNMENT_CENTER
	coins.add_child(cr)
	var amt := CoinAmount.new(int(p.get("coins", 0)), "lg", "plain")
	amt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cr.add_child(amt)
	var plus := PanelContainer.new()
	plus.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ps := UIKit.box(Palette.TEAL, UIKit.R.pill, UIKit.BW.line, Color.WHITE)
	UIKit.pad(ps, 0)
	plus.add_theme_stylebox_override("panel", ps)
	plus.custom_minimum_size = Vector2(26, 26)
	plus.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var pl := UIKit.label("+", 20, Color.WHITE, UIKit.font_display(), HORIZONTAL_ALIGNMENT_CENTER)
	pl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pl.add_theme_constant_override("line_spacing", -4)
	plus.add_child(pl)
	cr.add_child(plus)
	var minw := amt.get_combined_minimum_size().x + 26 + 6 + 12
	coins.custom_minimum_size.x = maxf(minw, 108)
	var gear := UIKit.icon_button(HI % "gear", "glass", int(BAR_H), 32)
	gear.pressed.connect(func(): open_tab.emit("settings"))
	row.add_child(gear)
	return row


## The live state of the three lobby features (Rewards module).
func _feature_states() -> Array:
	var spin_ok := true
	var spin_txt := "Ready"
	var daily_ok := false
	var daily_txt := "Day 1"
	var free_ok := true
	var free_txt := "Ready"
	if ResourceLoader.exists("res://scripts/core/rewards.gd"):
		var R: Script = load("res://scripts/core/rewards.gd")
		var p: Dictionary = Save.profile
		spin_ok = R.can_spin(p)
		spin_txt = "Ready" if spin_ok else Fmt.until(R.sec_to_midnight())
		var ds: Dictionary = R.daily_state(p)
		daily_ok = bool(ds.get("claimable", false))
		daily_txt = "Claim" if daily_ok else "Tomorrow"
		var left: int = R.free_left_sec(p)
		free_ok = left <= 0
		free_txt = "Ready" if free_ok else Fmt.clock(left)
	return [
		{id = "spin", title = "Spin", short = "Spin", icon = "spin", ready = spin_ok, state = spin_txt},
		{id = "daily", title = "Rewards", short = "Rewards", icon = "gift", ready = daily_ok, state = daily_txt},
		{id = "free", title = "Free", short = "Free", icon = "coins", ready = free_ok, state = free_txt},
	]


static func _dot() -> Panel:
	var d := Panel.new()
	d.add_theme_stylebox_override("panel", UIKit.box(Palette.RED, UIKit.R.pill, UIKit.BW.line, Color.WHITE))
	d.size = Vector2(14, 14)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return d


## A: a feature chip (icon + name + live state), one third of the row.
func _feature_chip(f: Dictionary) -> Button:
	var b := _flat_button(_chip_style(16), _chip_style(16, true))
	b.custom_minimum_size = Vector2(0, 56)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(func(): open_tab.emit(f.id))
	var r := UIKit.hbox(6)
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.offset_left = 6; r.offset_right = -4
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(r)
	var ic := UIKit.icon(HI % f.icon, 40)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.add_child(ic)
	var col := UIKit.vbox(0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_child(col)
	var t := UIKit.label(f.title, UIKit.FS.label, Palette.INK, UIKit.font_body(900))
	t.clip_text = true
	col.add_child(t)
	var s := UIKit.label(f.state, UIKit.FS.small, Palette.TEAL_INK if f.ready else Palette.MUTED, UIKit.font_body(800, true))
	col.add_child(s)
	if f.ready:
		var d := _dot()
		b.add_child(d)
		b.resized.connect(func(): d.position = Vector2(b.size.x - 10, -4))
	return b


## B / C: a square feature tile (SideButton with a cream tile and the family icon).
func _feature_tile(f: Dictionary, tile := 60.0, on_cream := false) -> SideButton:
	var cap: String = f.short
	var sb := SideButton.new(f.id, cap, HI % f.icon, [Palette.CARD, Palette.LIP_CREAM], tile)
	sb.caption.add_theme_font_override("font", UIKit.font_body(900))   # font_caps() renders at the regular weight
	if not f.ready:
		sb.set_countdown(f.state)
	sb.set_badge("")
	if f.ready:
		var d := _dot()
		sb.add_child(d)
		d.position = Vector2((SideButton.WIDTH - tile) / 2.0 + tile - 11, -4)
	if on_cream:
		sb.caption.add_theme_color_override("font_color", Palette.INK)
		sb.caption.add_theme_constant_override("outline_size", 0)
	sb.pressed.connect(func(id): open_tab.emit(id))
	return sb


## B: the features in one glass rail (icon, name, state), docked on the right edge.
func _feature_rail() -> PanelContainer:
	var panel := PanelContainer.new()
	var s := UIKit.box(Palette.GLASS, 22, UIKit.BW.line, Color.WHITE)
	UIKit.shade(s, "md")
	UIKit.pad(s, 4, 8)
	panel.add_theme_stylebox_override("panel", s)
	var col := UIKit.vbox(4)
	panel.add_child(col)
	var first := true
	for f in _feature_states():
		if not first:
			var hr := ColorRect.new()
			hr.color = Palette.LINE
			hr.custom_minimum_size = Vector2(0, 2)
			col.add_child(hr)
		first = false
		var st := StyleBoxEmpty.new()
		var b := _flat_button(st, UIKit.box(Palette.CHIP, 16))
		b.custom_minimum_size = Vector2(64, 74)
		var id: String = f.id
		b.pressed.connect(func(): open_tab.emit(id))
		var c := UIKit.vbox(0)
		c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		c.alignment = BoxContainer.ALIGNMENT_CENTER
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(c)
		var ic := UIKit.icon(HI % f.icon, 36)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		c.add_child(ic)
		c.add_child(UIKit.label(f.short, UIKit.FS.small, Palette.INK, UIKit.font_body(900), HORIZONTAL_ALIGNMENT_CENTER))
		var sl := UIKit.label(f.state if not f.ready else "Ready", UIKit.FS.small, Palette.TEAL_INK if f.ready else Palette.MUTED, UIKit.font_body(800, true), HORIZONTAL_ALIGNMENT_CENTER)
		if f.id == "free" and not f.ready:
			sl.text = str(f.state).substr(0, str(f.state).rfind(":"))   # "3:53"
		c.add_child(sl)
		if f.ready:
			var d := _dot()
			b.add_child(d)
			d.position = Vector2(44, 2)
		col.add_child(b)
	return panel


## C: the game switch: two big segments with the family icon + name (the selected one is a raised white face).
func _game_switch() -> PanelContainer:
	var track := PanelContainer.new()
	var ts := UIKit.box(Palette.CHIP, 18)
	UIKit.pad(ts, 4)
	track.add_theme_stylebox_override("panel", ts)
	var row := UIKit.hbox(4)
	track.add_child(row)
	var group := ButtonGroup.new()
	for g in [["ludo", "Ludo", "ludo"], ["sl", "Snakes & Ladders", "snakes"]]:
		var on := UIKit.box(Color.WHITE, 14, 0)
		UIKit.shade(on, "sm")
		on.border_width_bottom = 3; on.border_color = Palette.LIP_CREAM
		var off := StyleBoxFlat.new()
		off.bg_color = Color(1, 1, 1, 0)
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.button_pressed = g[0] == game
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 52)
		for k in ["normal", "hover"]:
			b.add_theme_stylebox_override(k, off)
		for k in ["pressed", "hover_pressed"]:
			b.add_theme_stylebox_override(k, on)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		UIKit.wire_press(b)
		var r := UIKit.hbox(8)
		r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		r.alignment = BoxContainer.ALIGNMENT_CENTER
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(r)
		r.add_child(UIKit.icon(HI % g[2], 32))
		var l := UIKit.label(g[1], UIKit.FS.label + 1, Palette.INK, UIKit.font_body(900))
		r.add_child(l)
		var key: String = g[0]
		b.toggled.connect(func(v): if v: game = key)
		row.add_child(b)
	return track


func _quick_slot() -> Button:
	var b := _flat_button(_chip_style(18), _chip_style(18, true))
	b.custom_minimum_size = Vector2(0, 56)
	b.pressed.connect(func(): play.emit(str(quick.get("game", "ludo")), str(quick.kind)))
	var r := UIKit.hbox(10)
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.offset_left = 8; r.offset_right = -8
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(r)
	var cont: bool = quick.kind == "continue"
	var ic := UIKit.icon(HI % ("resume" if cont else "again"), 42)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.add_child(ic)
	var col := UIKit.vbox(0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_child(col)
	col.add_child(UIKit.label(str(quick.title), UIKit.FS.h3, Palette.INK, UIKit.font_body(900)))
	var sub := UIKit.label(str(quick.sub), UIKit.FS.small, Palette.MUTED, UIKit.font_body(800))
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	sub.clip_text = true
	col.add_child(sub)
	var go := UIKit.button("Resume" if cont else "Play", "teal" if cont else "honey", "xs")
	go.mouse_filter = Control.MOUSE_FILTER_IGNORE
	go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	go.custom_minimum_size.x = 84
	r.add_child(go)
	return b


## The bottom nav: Home / Shop / Profile. look "bar": a floating cream bar; "flat": inside the C dock.
func _nav_bar(look := "bar") -> Control:
	var holder := PanelContainer.new()
	if look == "bar":
		var s := UIKit.box(Palette.GLASS, 24, UIKit.BW.line, Color.WHITE)
		UIKit.shade(s, "md")
		UIKit.pad(s, 6, 4)
		holder.add_theme_stylebox_override("panel", s)
	else:
		holder.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var row := UIKit.hbox(6)
	holder.add_child(row)
	for t in [["home", "Home"], ["shop", "Shop"], ["profile", "Profile"]]:
		var on: bool = t[0] == "home"
		var st := UIKit.box(Palette.HONEY_TINT if on else Color(1, 1, 1, 0), 18, UIKit.BW.line if on else 0, Palette.HONEY_TINT_EDGE)
		UIKit.pad(st, 0)
		var pr := UIKit.box(Palette.CHIP, 18)
		UIKit.pad(pr, 0)
		var b := _flat_button(st, pr)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, NAV_H - 8)
		var col := UIKit.vbox(0)
		col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(col)
		var ic := UIKit.icon(HI % t[0], 30)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(ic)
		col.add_child(UIKit.label(t[1], UIKit.FS.small, Palette.INK if on else Palette.SUB, UIKit.font_body(900), HORIZONTAL_ALIGNMENT_CENTER))
		var id: String = t[0]
		b.pressed.connect(func(): open_tab.emit(id))
		row.add_child(b)
	return holder


func _mode_btn(text: String, kind: String, icon_name: String, size := "sm", game_ := "ludo", mode_ := "cpu") -> Button:
	var ic := UIKit.icon(HI % icon_name, 30 if size == "sm" else 36)
	var b := UIKit.button_with(text, ic, kind, size)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var l := b.find_child("Text", true, false) as Label
	if l:
		l.add_theme_font_size_override("font_size", 17 if size == "sm" else 18)
	b.pressed.connect(func(): play.emit(game_, mode_))
	return b


# =====================================================================================================================
# A: two game cards
# =====================================================================================================================

func _build_a() -> void:
	var row := UIKit.hbox(8)
	for f in _feature_states():
		row.add_child(_feature_chip(f))
	add_child(row)
	_feat = [row]
	if not quick.is_empty():
		_quick = _quick_slot()
		add_child(_quick)
	for g in [["ludo", "Ludo", "ludo"], ["sl", "Snakes & Ladders", "snakes"]]:
		_cards.append(_game_card(g[0], g[1], g[2]))
	_nav = _nav_bar()
	add_child(_nav)


func _game_card(id: String, title: String, icon_name: String) -> Control:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var panel := PanelContainer.new()
	var s := UIKit.box(Palette.CARD, 22, UIKit.BW.line, Color.WHITE)
	UIKit.shade(s, "md", Palette.SHADOW_DEEP)
	UIKit.pad(s, 10, 10)
	s.content_margin_top = 40
	panel.add_theme_stylebox_override("panel", s)
	panel.name = "Panel"
	root.add_child(panel)
	var col := UIKit.vbox(8)
	panel.add_child(col)
	var t := UIKit.label(title, UIKit.FS.h3 + 1, Palette.INK, UIKit.font_display(), HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(t)
	col.add_child(_mode_btn("VS COMPUTER", "honey", "cpu", "sm", id, "cpu"))
	col.add_child(_mode_btn("PASS & PLAY", "teal", "pass_play", "sm", id, "local"))
	var ic := UIKit.icon(HI % icon_name, 64)
	ic.name = "Icon"
	ic.size = Vector2(64, 64)
	root.add_child(ic)
	return root


# =====================================================================================================================
# B: game switcher + one big Play
# =====================================================================================================================

func _build_b() -> void:
	var rail := _feature_rail()
	add_child(rail)
	_feat = [rail]
	if not quick.is_empty():
		_quick = _quick_slot()
		add_child(_quick)
	_banner = _game_banner()
	add_child(_banner)
	_seg = UIKit.segmented([["cpu", "vs Computer"], ["local", "Pass & Play"]], mode, func(v): mode = v, "md")
	add_child(_seg)
	_playb = UIKit.button("Play", "honey", "lg")
	_playb.custom_minimum_size.y = 64
	_playb.add_theme_font_size_override("font_size", 30)
	_playb.pressed.connect(func(): play.emit(game, mode))
	add_child(_playb)
	_nav = _nav_bar()
	add_child(_nav)


func _game_banner() -> Control:
	var panel := PanelContainer.new()
	var s := UIKit.box(Palette.CARD, 22, UIKit.BW.line, Color.WHITE)
	UIKit.shade(s, "md", Palette.SHADOW_DEEP)
	UIKit.pad(s, 6, 8)
	panel.add_theme_stylebox_override("panel", s)
	var row := UIKit.hbox(6)
	panel.add_child(row)
	var prev := UIKit.icon_button("ic_back", "glass", 44, 22)
	prev.pressed.connect(func(): _switch_game())
	row.add_child(prev)
	var mid := UIKit.hbox(12)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(mid)
	var ic := UIKit.icon(HI % ("ludo" if game == "ludo" else "snakes"), 60)
	ic.name = "GameIcon"
	mid.add_child(ic)
	var col := UIKit.vbox(0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_child(col)
	var t := UIKit.label("Ludo" if game == "ludo" else "Snakes & Ladders", UIKit.FS.h1, Palette.INK, UIKit.font_display())
	t.name = "GameTitle"
	col.add_child(t)
	var dots := UIKit.hbox(6)
	dots.name = "Dots"
	for i in 2:
		var d := Panel.new()
		var on := (i == 0) == (game == "ludo")
		d.add_theme_stylebox_override("panel", UIKit.box(Palette.GOLD if on else Palette.TRACK, UIKit.R.pill))
		d.custom_minimum_size = Vector2(18 if on else 8, 8)
		dots.add_child(d)
	col.add_child(dots)
	var next := UIKit.icon_button("ic_back", "glass", 44, 22)
	(next.get_child(0).get_child(0) as TextureRect).flip_h = true
	next.pressed.connect(func(): _switch_game())
	row.add_child(next)
	return panel


func _switch_game() -> void:
	game = "sl" if game == "ludo" else "ludo"
	var old := _banner
	_banner = _game_banner()
	add_child(_banner)
	old.queue_free()
	_layout()


# =====================================================================================================================
# C: scene + dock
# =====================================================================================================================

func _build_c() -> void:
	_dock = Panel.new()
	var s := UIKit.box(Palette.CARD, 0, 0)
	s.corner_radius_top_left = 30; s.corner_radius_top_right = 30
	s.shadow_size = 18; s.shadow_offset = Vector2(0, -2); s.shadow_color = Palette.shadow(0.35)
	s.border_width_top = UIKit.BW.line; s.border_color = Color.WHITE
	_dock.add_theme_stylebox_override("panel", s)
	_dock.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dock)
	for f in _feature_states():
		var t := _feature_tile(f, 60.0, true)
		add_child(t)
		_feat.append(t)
	if not quick.is_empty():
		_quick = _quick_slot()
		add_child(_quick)
	_switch = _game_switch()
	add_child(_switch)
	_modes = UIKit.hbox(10)
	_modes.add_child(_mode_btn("VS COMPUTER", "honey", "cpu", "md", "ludo", "cpu"))
	_modes.add_child(_mode_btn("PASS & PLAY", "teal", "pass_play", "md", "ludo", "local"))
	add_child(_modes)
	_nav = _nav_bar("flat")
	add_child(_nav)


# =====================================================================================================================
# layout
# =====================================================================================================================

func _logo_at(y: float, w: float, max_w: float, max_h: float) -> void:
	var lw := minf(max_w, w - 2 * G)
	var lh := lw * 266.0 / 320.0
	if lh > max_h:
		lh = max_h
		lw = lh * 320.0 / 266.0
	logo.size = Vector2(lw, lh)
	logo.position = Vector2(round((w - lw) / 2.0), y)


func _layout() -> void:
	var w := size.x
	var h := size.y
	if w <= 0:
		return
	var top := safe_top
	var bottom := h - maxf(safe_bottom + 8.0, 20.0)       # gesture-nav phones report 0 in immersive mode: keep 20
	var veil := get_node("Veil") as TextureRect
	veil.position = Vector2.ZERO
	veil.size = Vector2(w, top + 180)
	_top.position = Vector2(G, top + 8)
	_top.size = Vector2(w - 2 * G, BAR_H)
	var y_bar := top + 8 + BAR_H
	match variant:
		"A":
			_nav.position = Vector2(G, bottom - NAV_H)
			_nav.size = Vector2(w - 2 * G, NAV_H)
			var row: Control = _feat[0]
			row.position = Vector2(G, y_bar + 8)
			row.size = Vector2(w - 2 * G, 56)
			_logo_at(y_bar + 8 + 56 + 16, w, 210, 0.19 * h)
			var cw := (w - 2 * G - 12) / 2.0
			var ch := 40.0 + 24 + 8 + 48 + 8 + 48 + 10
			var cy := _nav.position.y - 16 - ch
			for i in _cards.size():
				var c: Control = _cards[i]
				c.position = Vector2(G + i * (cw + 12), cy - 28)
				c.size = Vector2(cw, ch + 28)
				var p := c.get_node("Panel") as Control
				p.position = Vector2(0, 28)
				p.size = Vector2(cw, ch)
				var ic := c.get_node("Icon") as Control
				ic.position = Vector2(round((cw - 64) / 2.0), 0)
			var band_bottom := cy - 28 - 8
			if _quick:
				_quick.position = Vector2(G, cy - 28 - 12 - 56)
				_quick.size = Vector2(w - 2 * G, 56)
				band_bottom = _quick.position.y - 8
			_band = Vector2(logo.position.y + logo.size.y, band_bottom)
		"B":
			_nav.position = Vector2(G, bottom - NAV_H)
			_nav.size = Vector2(w - 2 * G, NAV_H)
			_playb.position = Vector2(G, _nav.position.y - 16 - 64)
			_playb.size = Vector2(w - 2 * G, 64)
			_seg.position = Vector2(G, _playb.position.y - 8 - 48)
			_seg.size = Vector2(w - 2 * G, 48)
			_banner.size = Vector2(w - 2 * G, 0)
			_banner.size = Vector2(w - 2 * G, _banner.get_combined_minimum_size().y)
			_banner.position = Vector2(G, _seg.position.y - 8 - _banner.size.y)
			var band_bottom := _banner.position.y - 8
			if _quick:
				_quick.position = Vector2(G, _banner.position.y - 12 - 56)
				_quick.size = Vector2(w - 2 * G, 56)
				band_bottom = _quick.position.y - 8
			# features docked on the right, under the top bar; the logo centres in the space left of them
			var rail: Control = _feat[0]
			rail.size = rail.get_combined_minimum_size()
			var fx := w - G - rail.size.x
			rail.position = Vector2(fx, y_bar + 12)
			var avail := fx - G - 8
			_logo_at(y_bar + 12, avail + 2 * G, 250, 0.22 * h)
			logo.position.x = round(G + (avail - logo.size.x) / 2.0)
			_band = Vector2(logo.position.y + logo.size.y, band_bottom)
		_:
			var nav_y := bottom - NAV_H + 4
			_nav.position = Vector2(G - 6, nav_y)
			_nav.size = Vector2(w - 2 * G + 12, NAV_H - 4)
			var sep := get_node_or_null("NavRule") as ColorRect
			if sep == null:
				sep = ColorRect.new()
				sep.name = "NavRule"
				sep.color = Palette.LINE
				sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
				add_child(sep)
			sep.position = Vector2(G, nav_y - 8)
			sep.size = Vector2(w - 2 * G, 2)
			_modes.position = Vector2(G, nav_y - 16 - 58)
			_modes.size = Vector2(w - 2 * G, 58)
			_switch.position = Vector2(G, _modes.position.y - 12 - 60)
			_switch.size = Vector2(w - 2 * G, 60)
			var top_of := _switch.position.y
			if _quick:
				_quick.position = Vector2(G, top_of - 10 - 56)
				_quick.size = Vector2(w - 2 * G, 56)
				top_of = _quick.position.y
			var cap_h := 40.0
			var dock_y := top_of - 12 - cap_h - 30
			_dock.position = Vector2(0, dock_y)
			_dock.size = Vector2(w, h - dock_y + 4)
			if _quick:
				(_quick as Button).add_theme_stylebox_override("normal", _quick_on_cream())
			var n := _feat.size()
			var gap := 28.0
			var tw := SideButton.WIDTH
			var total := n * tw + (n - 1) * gap
			var x0 := roundf((w - total) / 2.0)
			for i in n:
				var sb := _feat[i] as SideButton
				sb.position = Vector2(x0 + i * (tw + gap), dock_y - 30)
			_logo_at(y_bar + 14, w, 270, 0.24 * h)
			_band = Vector2(logo.position.y + logo.size.y, dock_y - 30 - 10)


func _quick_on_cream() -> StyleBoxFlat:
	var s := UIKit.box(Palette.SURFACE_2, 18, UIKit.BW.line, Palette.ROW_EDGE)
	UIKit.pad(s, 8, 6)
	return s


## The band between the logo and the first control below it, in UI pixels (for the home camera framing).
func free_band() -> Vector2:
	return _band
