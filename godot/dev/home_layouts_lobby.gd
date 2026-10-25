extends Control
## Dev (home rethink): three lighter home layout candidates over the real café, mockups only (the real home is
## scripts/ui/home_screen.gd). Driven by dev/home_layouts.gd. Built from the same UIKit tokens, Palette colours,
## home icon family (assets/ui/home/hi_*.svg), BrandLogo and top bar as the real HomeScreen.
##   D  "One big Play"  smaller logo; one gift button in the top bar for Spin / Daily / Free (badge = how many are
##                      ready); a cream dock: Ludo / S&L switch, ONE big QUICK MATCH, a compact row of the other
##                      three modes; nav Home · Shop · Ranks · Inventory; Continue as a slim pill over the café
##   E  "Side rail"     the café + full logo stay the hero; Spin / Daily / Free / Ranks as a slim glass rail on the
##                      right edge with timer chips; a floating card: switch, QUICK MATCH, three small mode wells;
##                      a floating nav bar; Continue as a pill
##   F  "Game cards"    rewards as a chip strip under the top bar; two big game cards with art (Ludo, Snakes &
##                      Ladders), a tap opens that game's mode sheet (F2); Continue as a banner card
##   F2                 F with the Ludo mode sheet open (the real Sheet, "pm" look)

signal play(game: String, mode: String)
signal open_tab(tab: String)

const HI := "res://assets/ui/home/hi_%s.svg"
const TROPHY := "res://assets/ui/ic_trophy.svg"
const FRIENDS := "perk_friends"
const BAR_H := 52.0
const NAV_H := 60.0
const G := 16.0                         # screen gutter (UIKit.SCREEN_GUTTER)
const BOTTOM_MIN := 20.0

const ROUND_ART := """
shader_type canvas_item;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform vec2 rect_size = vec2(100.0);
uniform vec2 tex_size = vec2(720.0, 540.0);
uniform vec4 radii = vec4(16.0);       // tl, tr, br, bl
uniform float focus_y = 0.5;
uniform float zoom = 1.0;
void fragment() {
	float s = max(rect_size.x / tex_size.x, rect_size.y / tex_size.y) * zoom;
	vec2 shown = rect_size / s / tex_size;
	vec2 off = (1.0 - shown) * vec2(0.5, focus_y);
	vec4 c = texture(tex, off + UV * shown);
	vec2 p = UV * rect_size;
	vec2 h = rect_size * 0.5;
	float r = p.x < h.x ? (p.y < h.y ? radii.x : radii.w) : (p.y < h.y ? radii.y : radii.z);
	vec2 q = abs(p - h) - (h - vec2(r));
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
	c.a *= clamp(0.5 - d, 0.0, 1.0);
	COLOR = c;
}
"""

var variant := "D"
var quick := {}                         # {kind: "continue", game, title, sub} or {}
var safe_top := 0.0
var safe_bottom := 0.0
var table_width_factor := 1.3
var game := "ludo"

var logo: BrandLogo
var _veil: TextureRect
var _top: HBoxContainer
var _chip_text: Control                 # the name + XP column of the player chip (hidden when the bar is tight)
var _chip: Button
var _spacer: Control                    # takes the chip's room when the chip is only the avatar
var _nav: Control
var _quick: Control
var _dock: Panel
var _switch: PanelContainer
var _switch_parts := {}
var _primary: Button
var _modes: HBoxContainer
var _rule: ColorRect
var _rail: PanelContainer
var _card: PanelContainer
var _card_box: VBoxContainer
var _strip: HBoxContainer
var _cards: HBoxContainer
var _band := Vector2(200, 500)
var _rewards: Array = []


func _init(variant_ := "D", quick_ := {}) -> void:
	variant = variant_
	quick = quick_


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rewards = _reward_states()
	_build_veil()
	logo = BrandLogo.new()
	logo.bob = true
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(logo)
	match variant:
		"D": _build_d()
		"E": _build_e()
		_: _build_f()
	resized.connect(_layout)
	_layout.call_deferred()
	if variant == "F2":
		_open_mode_sheet.call_deferred("ludo")


# =====================================================================================================================
# shared pieces
# =====================================================================================================================

func _build_veil() -> void:
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(Palette.VEIL, 0.45), Color(Palette.VEIL, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0.5, 0.0)
	gt.fill_to = Vector2(0.5, 1.0)
	_veil = TextureRect.new()
	_veil.texture = gt
	_veil.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_veil)


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


static func _chip_style(r := 18, pressed := false) -> StyleBoxFlat:
	var s := UIKit.box(Palette.GLASS_PRESSED if pressed else Palette.GLASS, r, UIKit.BW.line, Color.WHITE)
	UIKit.shade(s, "sm")
	UIKit.pad(s, 8, 6)
	return s


static func _fill(c: Control) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE


## The top bar of today's home (player chip, coins with "+", gear); with_gift: the Rewards gift button before the
## gear, with a red count of the rewards that are ready.
func _build_top(with_gift := false) -> void:
	_top = UIKit.hbox(UIKit.SPACE.sm)
	add_child(_top)
	var p: Dictionary = Save.profile
	_chip = _flat_button(_chip_style(), _chip_style(18, true))
	_chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chip.custom_minimum_size = Vector2(BAR_H, BAR_H)
	_chip.pressed.connect(func(): open_tab.emit("profile"))
	_top.add_child(_chip)
	_spacer = Control.new()
	_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spacer.visible = false
	_top.add_child(_spacer)
	var r := UIKit.hbox(UIKit.SPACE.md)
	_fill(r)
	r.offset_left = 5; r.offset_top = 5; r.offset_right = -10; r.offset_bottom = -5
	_chip.add_child(r)
	var av := Control.new()
	av.custom_minimum_size = Vector2(42, 42)
	av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	av.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_child(av)
	var avatar := Collection.make_avatar(42)
	avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	av.add_child(avatar)
	var li := Save.level_info(int(p.get("xp", 0)))
	var lv := LevelBadge.new(int(li.level), "sm")
	lv.position = Vector2(42 - lv.px + 9.0, 42 - lv.px + 4.0)
	lv.size = Vector2(lv.px, lv.px)
	av.add_child(lv)
	var col := UIKit.vbox(3)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_child(col)
	_chip_text = col
	var nm := UIKit.label(str(p.get("name", "You")), UIKit.FS.label + 1, Palette.INK, UIKit.font_body(900))
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.clip_text = true
	col.add_child(nm)
	var xp := Meter.new("night", 12) if with_gift else Meter.new("night", 16, true)   # D: a tighter chip, no numbers
	xp.set_value(float(li.into), float(li.need))
	col.add_child(xp)
	var coins := _flat_button(_chip_style(UIKit.R.pill), _chip_style(UIKit.R.pill, true))
	coins.custom_minimum_size = Vector2(104, BAR_H)
	coins.pressed.connect(func(): open_tab.emit("coins"))
	_top.add_child(coins)
	var cr := UIKit.hbox(6)
	_fill(cr)
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
	plus.add_child(pl)
	cr.add_child(plus)
	if with_gift:
		var gift := UIKit.icon_button(HI % "gift", "glass", int(BAR_H), 38)
		gift.name = "Rewards"
		gift.pressed.connect(func(): open_tab.emit("rewards"))
		_top.add_child(gift)
		var n := 0
		for f in _rewards:
			if f.ready:
				n += 1
		if n > 0:
			var badge := UIKit.notify_badge(str(n))
			gift.add_child(badge)
			badge.position = Vector2(BAR_H - 16, -6)
	var gear := UIKit.icon_button(HI % "gear", "glass", int(BAR_H), 32)
	gear.pressed.connect(func(): open_tab.emit("settings"))
	_top.add_child(gear)


## Spin / Daily / Free coins, live from the Rewards module: [{id, title, icon, ready, state, short}].
func _reward_states() -> Array:
	var R: Script = load("res://scripts/core/rewards.gd")
	var p: Dictionary = Save.profile
	var spin_ok: bool = R.can_spin(p)
	var daily_ok := bool((R.daily_state(p) as Dictionary).get("claimable", false))
	var left: int = R.free_left_sec(p)
	var midnight := Fmt.until(int(R.sec_to_midnight()))
	var free_clock := Fmt.clock(left)
	return [
		{id = "spin", title = "Spin", icon = HI % "spin", ready = spin_ok, state = "Ready" if spin_ok else midnight},
		{id = "daily", title = "Daily", icon = HI % "gift", ready = daily_ok, state = "Claim" if daily_ok else midnight},
		{id = "free", title = "Free", icon = HI % "coins", ready = left <= 0, state = "Ready" if left <= 0 else free_clock.substr(0, free_clock.rfind(":"))},
	]


static func _dot() -> Panel:
	var d := Panel.new()
	d.add_theme_stylebox_override("panel", UIKit.box(Palette.RED, UIKit.R.pill, UIKit.BW.line, Color.WHITE))
	d.size = Vector2(14, 14)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return d


## The Ludo / Snakes & Ladders switch of today's home (family icon + name; the selected half a raised white face).
func _build_switch(h := 52.0) -> PanelContainer:
	var sw := PanelContainer.new()
	var ts := UIKit.box(Palette.CHIP, UIKit.R.lg)
	UIKit.pad(ts, 4)
	sw.add_theme_stylebox_override("panel", ts)
	var row := UIKit.hbox(4)
	sw.add_child(row)
	var group := ButtonGroup.new()
	var on := UIKit.box(Color.WHITE, UIKit.R.md, 0)
	UIKit.shade(on, "sm")
	on.border_width_bottom = UIKit.LIP.sm
	on.border_color = Palette.LIP_CREAM
	var off := StyleBoxFlat.new()
	off.bg_color = Color(1, 1, 1, 0)
	for g in [["ludo", "Ludo", "ludo"], ["sl", "Snakes & Ladders", "snakes"]]:
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, h - 8)
		for k in ["normal", "hover", "disabled"]:
			b.add_theme_stylebox_override(k, off)
		for k in ["pressed", "hover_pressed"]:
			b.add_theme_stylebox_override(k, on)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		UIKit.wire_press(b, "select")
		b.clip_contents = true
		var r := UIKit.hbox(UIKit.SPACE.sm)
		_fill(r)
		r.alignment = BoxContainer.ALIGNMENT_CENTER
		b.add_child(r)
		var ic := UIKit.icon(HI % g[2], 30)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		r.add_child(ic)
		var on_now: bool = g[0] == game
		var l := UIKit.label(g[1], UIKit.FS.label + 1, Palette.INK if on_now else Palette.SUB, UIKit.font_body(900))
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		r.add_child(l)
		_switch_parts[g[0]] = {row = r, icon = ic, label = l, text = g[1]}
		b.button_pressed = on_now
		var key: String = g[0]
		b.toggled.connect(func(v: bool): if v: game = key)
		row.add_child(b)
	return sw


## Labels of the switch at the size that fits its halves (14 px, then a 24 px icon, then two lines).
func _fit_switch(cw: float) -> void:
	var room := (cw - 12.0) / 2.0 - UIKit.SPACE.sm
	var font := UIKit.font_body(900)
	var wide := font.get_string_size("Snakes & Ladders", HORIZONTAL_ALIGNMENT_LEFT, -1, UIKit.FS.label + 1).x
	var two := false
	var fs := UIKit.FS.label + 1
	var ic := 30.0
	if ic + 8 + wide > room:
		fs = UIKit.FS.label
		ic = 24.0
		wide = font.get_string_size("Snakes & Ladders", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		two = ic + 6 + wide > room
	for k in _switch_parts:
		var part: Dictionary = _switch_parts[k]
		(part.label as Label).add_theme_font_size_override("font_size", fs)
		(part.label as Label).add_theme_constant_override("line_spacing", -3)
		(part.label as Label).text = "Snakes &\nLadders" if two and k == "sl" else part.text
		(part.icon as Control).custom_minimum_size = Vector2(ic, ic)


## A kit button with an icon over a short label (the compact secondary modes). look: a UIKit kind, or "well"
## (a flat CHIP well with no lip, for E's card).
func _tile_button(text: String, icon_path: String, look := "white", h := 66.0, icon_px := 30.0, fs := 13) -> Button:
	var b: Button
	var lip := 0.0
	if look == "well":
		var st := UIKit.box(Palette.SURFACE_2, UIKit.R.md, UIKit.BW.line, Palette.ROW_EDGE)
		UIKit.pad(st, 0)
		var pr := UIKit.box(Palette.CHIP, UIKit.R.md, UIKit.BW.line, Palette.ROW_EDGE)
		UIKit.pad(pr, 0)
		b = _flat_button(st, pr)
	else:
		b = UIKit.button("", look, "md")
		lip = float(UIKit.BTN.md.lip)
	b.custom_minimum_size = Vector2(0, h)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var col := UIKit.vbox(2)
	_fill(col)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.offset_bottom = -lip
	b.add_child(col)
	var ic := UIKit.icon(icon_path, icon_px)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(ic)
	var l := UIKit.label(text, fs, Palette.INK, UIKit.font_body(900), HORIZONTAL_ALIGNMENT_CENTER)
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(l)
	if lip > 0.0:
		b.button_down.connect(func(): col.offset_top = lip - 2.0; col.offset_bottom = -2.0)
		b.button_up.connect(func(): col.offset_top = 0.0; col.offset_bottom = -lip)
	return b


## The one big QUICK MATCH: honey, the bolt globe, a big caps label and a one-line hint.
func _big_play(h := 76.0, title_fs := 26, sub := "Play online now") -> Button:
	var b := UIKit.button("", "honey", "lg")
	b.custom_minimum_size = Vector2(0, h)
	b.name = "QuickMatch"
	var lip := float(UIKit.BTN.lg.lip)
	var r := UIKit.hbox(UIKit.SPACE.md)
	_fill(r)
	r.alignment = BoxContainer.ALIGNMENT_CENTER
	r.offset_bottom = -lip
	b.add_child(r)
	var ic := UIKit.icon(HI % "quick", h - 30.0)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.add_child(ic)
	var col := UIKit.vbox(0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_child(col)
	var t := UIKit.label("QUICK MATCH", title_fs, Palette.ON_HONEY, UIKit.font_display())
	t.add_theme_constant_override("line_spacing", -6)
	col.add_child(t)
	if sub != "":
		col.add_child(UIKit.label(sub, UIKit.FS.small + 1, Color(Palette.ON_HONEY, 0.72), UIKit.font_body(800)))
	b.button_down.connect(func(): r.offset_top = lip - 2.0; r.offset_bottom = -2.0)
	b.button_up.connect(func(): r.offset_top = 0.0; r.offset_bottom = -lip)
	b.pressed.connect(func(): play.emit(game, "quick"))
	return b


## The bottom nav. look "dock": flat inside a cream dock (today's); "bar": a floating glass bar.
func _build_nav(tabs: Array, look := "dock") -> Control:
	var holder := PanelContainer.new()
	if look == "bar":
		var s := UIKit.box(Palette.GLASS, UIKit.R.xl - 4, UIKit.BW.line, Color.WHITE)
		UIKit.shade(s, "md")
		UIKit.pad(s, 6, 4)
		holder.add_theme_stylebox_override("panel", s)
	else:
		holder.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var row := UIKit.hbox(4)
	holder.add_child(row)
	for t in tabs:
		var on: bool = t[0] == "home"
		var st := UIKit.box(Palette.HONEY_TINT if on else Color(1, 1, 1, 0), UIKit.R.lg, UIKit.BW.line if on else 0, Palette.HONEY_TINT_EDGE)
		UIKit.pad(st, 0)
		var pr := UIKit.box(Palette.CHIP, UIKit.R.lg)
		UIKit.pad(pr, 0)
		var b := _flat_button(st, pr)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 52)
		var col := UIKit.vbox(0)
		_fill(col)
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		b.add_child(col)
		var ic := UIKit.icon(t[2], 28)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(ic)
		col.add_child(UIKit.label(t[1], UIKit.FS.small, Palette.INK if on else Palette.SUB, UIKit.font_body(900), HORIZONTAL_ALIGNMENT_CENTER))
		var id: String = t[0]
		b.pressed.connect(func(): open_tab.emit(id))
		row.add_child(b)
	add_child(holder)
	return holder


const TABS3 := [["home", "Home", HI % "home"], ["shop", "Shop", HI % "shop"], ["inventory", "Inventory", HI % "inventory"]]
const TABS4 := [["home", "Home", HI % "home"], ["shop", "Shop", HI % "shop"], ["leaderboard", "Ranks", TROPHY],
		["inventory", "Inventory", HI % "inventory"]]


## The Continue match slot. look "pill": a slim glass pill over the café; "banner": a cream card with a lip.
func _build_quick(look := "pill") -> Button:
	var b: Button
	if look == "pill":
		var st := _chip_style(UIKit.R.pill)
		b = _flat_button(st, _chip_style(UIKit.R.pill, true))
	else:
		var st := UIKit.box(Palette.CARD, UIKit.R.lg, UIKit.BW.line, Color.WHITE)
		st.border_width_bottom = UIKit.LIP.md
		st.border_color = Color.WHITE
		UIKit.shade(st, "md", Palette.SHADOW_DEEP)
		UIKit.pad(st, 8, 6)
		var pr := st.duplicate() as StyleBoxFlat
		pr.bg_color = Palette.SURFACE_2
		b = _flat_button(st, pr)
	b.pressed.connect(func(): play.emit(str(quick.get("game", "ludo")), "continue"))
	var r := UIKit.hbox(10)
	_fill(r)
	r.offset_left = 6 if look == "pill" else 10
	r.offset_right = -6 if look == "pill" else -10
	b.add_child(r)
	var ic := UIKit.icon(HI % "resume", 36 if look == "pill" else 44)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.add_child(ic)
	var col := UIKit.vbox(-2)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_child(col)
	col.add_child(UIKit.label(str(quick.title), UIKit.FS.label + 1 if look == "pill" else UIKit.FS.h3, Palette.INK, UIKit.font_body(900)))
	var sub := UIKit.label(str(quick.sub), UIKit.FS.small, Palette.MUTED, UIKit.font_body(800))
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	sub.clip_text = true
	col.add_child(sub)
	var go := UIKit.button("Resume", "teal", "xs")
	go.mouse_filter = Control.MOUSE_FILTER_IGNORE
	go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	go.custom_minimum_size.x = 84
	r.add_child(go)
	add_child(b)
	return b


func _cream_dock() -> Panel:
	var d := Panel.new()
	var s := UIKit.box(Palette.CARD, 0, 0)
	s.corner_radius_top_left = UIKit.R.xl + 2; s.corner_radius_top_right = UIKit.R.xl + 2
	s.corner_detail = 12
	s.shadow_size = 18; s.shadow_offset = Vector2(0, -2); s.shadow_color = Palette.shadow(0.35)
	s.border_width_top = UIKit.BW.line; s.border_color = Color.WHITE
	d.add_theme_stylebox_override("panel", s)
	d.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(d)
	return d


func _place_logo(y: float, cx: float, max_w: float, max_h: float) -> void:
	var lw := max_w
	var lh := lw * 266.0 / 320.0
	if lh > max_h:
		lh = max_h
		lw = lh * 320.0 / 266.0
	logo.size = Vector2(roundf(lw), roundf(lh))
	logo.position = Vector2(roundf(cx - lw / 2.0), roundf(y))


# =====================================================================================================================
# D: one big Play
# =====================================================================================================================

func _build_d() -> void:
	_build_top(true)
	_dock = _cream_dock()
	if not quick.is_empty():
		_quick = _build_quick("pill")
	_switch = _build_switch(52)
	add_child(_switch)
	_primary = _big_play(76, 28)
	add_child(_primary)
	_modes = UIKit.hbox(UIKit.SPACE.sm + 2)
	_modes.add_child(_tile_button("Friends", UIKit.ICON_DIR + FRIENDS + ".svg", "white", 64))
	_modes.add_child(_tile_button("Computer", HI % "cpu", "white", 64))
	_modes.add_child(_tile_button("Pass & Play", HI % "pass_play", "white", 64))
	add_child(_modes)
	_rule = ColorRect.new()
	_rule.color = Palette.LINE
	_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rule)
	_nav = _build_nav(TABS4, "dock")


func _layout_d(w: float, h: float, top: float, bottom: float, cw: float, x: float) -> void:
	var y_bar := top + UIKit.SPACE.sm + BAR_H
	var nav_y := bottom - NAV_H + 4
	_nav.position = Vector2(x - 6, nav_y)
	_nav.size = Vector2(cw + 12, NAV_H - 4)
	_rule.position = Vector2(x, nav_y - UIKit.SPACE.sm)
	_rule.size = Vector2(cw, 2)
	var mh := 64.0 if h > 760 else 60.0
	_modes.position = Vector2(x, nav_y - UIKit.SPACE.lg - mh)
	_modes.size = Vector2(cw, mh)
	var ph := 76.0 if h > 760 else 68.0
	_primary.position = Vector2(x, _modes.position.y - UIKit.SPACE.md - ph)
	_primary.size = Vector2(cw, ph)
	_switch.position = Vector2(x, _primary.position.y - UIKit.SPACE.md - 52)
	_switch.size = Vector2(cw, 52)
	_fit_switch(cw)
	var dock_y := _switch.position.y - UIKit.SPACE.lg - 2
	_dock.position = Vector2(0, dock_y)
	_dock.size = Vector2(w, h - dock_y + 4)
	var band_bottom := dock_y - UIKit.SPACE.sm
	if _quick:
		var qh := 52.0
		_quick.position = Vector2(x, dock_y - UIKit.SPACE.md - qh)
		_quick.size = Vector2(cw, qh)
		band_bottom = _quick.position.y - UIKit.SPACE.xs
	_place_logo(y_bar + UIKit.SPACE.md, w / 2.0, minf(208.0, cw), clampf(0.185 * h, 100.0, 180.0))
	_band = Vector2(logo.position.y + logo.size.y, band_bottom)


# =====================================================================================================================
# E: side rail
# =====================================================================================================================

func _build_e() -> void:
	_build_top(false)
	_rail = _build_rail()
	add_child(_rail)
	if not quick.is_empty():
		_quick = _build_quick("pill")
	_card = PanelContainer.new()
	var s := UIKit.box(Palette.CARD, UIKit.R.xl, UIKit.BW.line, Color.WHITE)
	UIKit.shade(s, "lg", Palette.SHADOW_DEEP)
	UIKit.pad(s, UIKit.SPACE.md, UIKit.SPACE.md)
	_card.add_theme_stylebox_override("panel", s)
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_card)
	_card_box = UIKit.vbox(UIKit.SPACE.sm + 2)
	_card.add_child(_card_box)
	_switch = _build_switch(52)
	_card_box.add_child(_switch)
	_primary = _big_play(66, 26, "")
	_card_box.add_child(_primary)
	_modes = UIKit.hbox(UIKit.SPACE.sm)
	_modes.add_child(_tile_button("Friends", UIKit.ICON_DIR + FRIENDS + ".svg", "well", 58, 28))
	_modes.add_child(_tile_button("Computer", HI % "cpu", "well", 58, 28))
	_modes.add_child(_tile_button("Pass & Play", HI % "pass_play", "well", 58, 28))
	_card_box.add_child(_modes)
	_nav = _build_nav(TABS3, "bar")


## E's rail: Spin / Daily / Free / Ranks, each an icon with a small state chip (timer, "Claim") under it.
func _build_rail() -> PanelContainer:
	var panel := PanelContainer.new()
	var s := UIKit.box(Palette.GLASS, 22, UIKit.BW.line, Color.WHITE)
	UIKit.shade(s, "md")
	UIKit.pad(s, 4, 6)
	panel.add_theme_stylebox_override("panel", s)
	var col := UIKit.vbox(2)
	panel.add_child(col)
	var items: Array = _rewards.duplicate()
	items.append({id = "leaderboard", title = "Ranks", icon = TROPHY, ready = false, state = ""})
	for f in items:
		var b := _flat_button(StyleBoxEmpty.new(), UIKit.box(Palette.CHIP, 16))
		b.custom_minimum_size = Vector2(60, 66)
		var id: String = f.id
		b.pressed.connect(func(): open_tab.emit(id))
		var c := UIKit.vbox(1)
		_fill(c)
		c.alignment = BoxContainer.ALIGNMENT_CENTER
		b.add_child(c)
		var ic := UIKit.icon(f.icon, 38)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		ic.modulate = Color(1, 1, 1, 1.0 if f.ready or f.id == "leaderboard" else 0.92)
		c.add_child(ic)
		var chip := PanelContainer.new()
		var cs: StyleBoxFlat
		var txt: String = f.state
		var fg := Color.WHITE
		if f.id == "leaderboard":
			cs = UIKit.box(Color(0, 0, 0, 0), UIKit.R.pill)
			txt = "Ranks"
			fg = Palette.INK
		elif f.ready:
			cs = UIKit.box(Palette.TEAL, UIKit.R.pill)
		else:
			cs = UIKit.box(Palette.TOAST, UIKit.R.pill)
		UIKit.pad(cs, 6, 0)
		chip.add_theme_stylebox_override("panel", cs)
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var l := UIKit.label(txt, UIKit.FS.small, fg, UIKit.font_body(900, true), HORIZONTAL_ALIGNMENT_CENTER)
		chip.add_child(l)
		c.add_child(chip)
		if f.ready:
			var d := _dot()
			b.add_child(d)
			d.position = Vector2(44, 2)
		col.add_child(b)
	return panel


func _layout_e(w: float, h: float, top: float, bottom: float, cw: float, x: float) -> void:
	var y_bar := top + UIKit.SPACE.sm + BAR_H
	var nh := NAV_H + 4
	_nav.position = Vector2(x, bottom - nh)
	_nav.size = Vector2(cw, nh)
	var short := h < 760
	(_primary as Control).custom_minimum_size.y = 60.0 if short else 66.0
	_card.size = Vector2(cw, 0)
	var ch := _card.get_combined_minimum_size().y
	_card.position = Vector2(x, _nav.position.y - UIKit.SPACE.md - ch)
	_card.size = Vector2(cw, ch)
	_fit_switch(cw - 2 * UIKit.SPACE.md)
	var band_bottom := _card.position.y - UIKit.SPACE.sm
	if _quick:
		_quick.position = Vector2(x, _card.position.y - UIKit.SPACE.md - 52)
		_quick.size = Vector2(cw, 52)
		band_bottom = _quick.position.y - UIKit.SPACE.xs
	_rail.size = _rail.get_combined_minimum_size()
	var rx := x + cw - _rail.size.x
	_rail.position = Vector2(rx, y_bar + UIKit.SPACE.md)
	# the logo: as big as today's, centred in the room left of the rail
	var avail := rx - UIKit.SPACE.sm - x
	_place_logo(y_bar + UIKit.SPACE.md, x + avail / 2.0, minf(250.0, avail), clampf(0.24 * h, 110.0, 210.0))
	_band = Vector2(logo.position.y + logo.size.y, band_bottom)


# =====================================================================================================================
# F: game cards
# =====================================================================================================================

func _build_f() -> void:
	_build_top(false)
	_strip = UIKit.hbox(UIKit.SPACE.sm)
	for f in _rewards:
		_strip.add_child(_reward_chip(f))
	add_child(_strip)
	if not quick.is_empty():
		_quick = _build_quick("banner")
	_cards = UIKit.hbox(UIKit.SPACE.md)
	_cards.add_child(_game_card("ludo", "Ludo", "res://assets/thumbs/room_cafe.webp", "ludo", 0.62))
	_cards.add_child(_game_card("sl", "Snakes & Ladders", "res://assets/thumbs/scene_jungle.webp", "snakes", 0.7))
	add_child(_cards)
	_nav = _build_nav(TABS4, "bar")


## F: a reward chip (icon, name, live state), a third of the strip.
func _reward_chip(f: Dictionary) -> Button:
	var b := _flat_button(_chip_style(UIKit.R.pill), _chip_style(UIKit.R.pill, true))
	b.custom_minimum_size = Vector2(0, 48)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var id: String = f.id
	b.pressed.connect(func(): open_tab.emit(id))
	var r := UIKit.hbox(6)
	_fill(r)
	r.offset_left = 4; r.offset_right = -8
	b.add_child(r)
	var ic := UIKit.icon(f.icon, 36)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.add_child(ic)
	var col := UIKit.vbox(-3)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_child(col)
	var t := UIKit.label(f.title, UIKit.FS.label, Palette.INK, UIKit.font_body(900))
	t.clip_text = true
	col.add_child(t)
	var s := UIKit.label(f.state, UIKit.FS.small, Palette.TEAL_INK if f.ready else Palette.MUTED, UIKit.font_body(900, true))
	s.clip_text = true
	col.add_child(s)
	if f.ready:
		var d := _dot()
		b.add_child(d)
		b.resized.connect(func(): d.position = Vector2(b.size.x - 14, -3))
	return b


## F: a big game card: the art (rounded top), the family icon on the art's edge, the name, a PLAY bar. The whole
## card is one button (opens that game's mode sheet).
func _game_card(id: String, title: String, art_path: String, icon_name: String, focus_y: float) -> Button:
	var st := UIKit.box(Palette.CARD, UIKit.R.xl - 6, UIKit.BW.rim, Color.WHITE)
	st.border_width_bottom = UIKit.LIP.lg + 1
	st.border_color = Color.WHITE
	UIKit.shade(st, "lg", Palette.SHADOW_DEEP)
	UIKit.pad(st, 0)
	var pr := st.duplicate() as StyleBoxFlat
	pr.bg_color = Palette.SURFACE_2
	pr.border_width_bottom = 2
	var b := _flat_button(st, pr)
	b.name = "Card_" + id
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(func(): _open_mode_sheet(id))
	var art := ColorRect.new()
	art.name = "Art"
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = ROUND_ART
	mat.shader = sh
	var tex: Texture2D = load(art_path)
	mat.set_shader_parameter("tex", tex)
	mat.set_shader_parameter("tex_size", Vector2(tex.get_width(), tex.get_height()))
	mat.set_shader_parameter("focus_y", focus_y)
	mat.set_shader_parameter("zoom", 1.0)
	art.material = mat
	b.add_child(art)
	var badge := UIKit.icon(HI % icon_name, 46)
	badge.name = "Badge"
	b.add_child(badge)
	var t := UIKit.label(title, UIKit.FS.h2, Palette.INK, UIKit.font_display(), HORIZONTAL_ALIGNMENT_CENTER)
	t.name = "Title"
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	t.autowrap_mode = TextServer.AUTOWRAP_OFF
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(t)
	var go := UIKit.button("PLAY", "honey" if id == "ludo" else "teal", "md")
	go.name = "Go"
	go.mouse_filter = Control.MOUSE_FILTER_IGNORE      # the whole card is the button
	b.add_child(go)
	var lay := func() -> void:
		var cwid := b.size.x
		var ah := roundf(cwid * 0.66)
		art.position = Vector2(UIKit.BW.rim, UIKit.BW.rim)
		art.size = Vector2(cwid - 2 * UIKit.BW.rim, ah)
		var r := float(UIKit.R.xl - 6 - UIKit.BW.rim)
		mat.set_shader_parameter("rect_size", art.size)
		mat.set_shader_parameter("radii", Vector4(r, r, 6, 6))
		badge.size = Vector2(46, 46)
		badge.position = Vector2(roundf((cwid - 46) / 2.0), art.position.y + ah - 26)
		var f := t.get_theme_font("font")
		var fs := UIKit.FS.h2
		while fs > UIKit.FS.label + 2 and f.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > cwid - 16:
			fs -= 1
		t.add_theme_font_size_override("font_size", fs)
		t.position = Vector2(4, art.position.y + ah + 20)
		t.size = Vector2(cwid - 8, 26)
		go.position = Vector2(10, b.size.y - UIKit.LIP.lg - 1 - 8 - 50)
		go.size = Vector2(cwid - 20, 50)
	b.resized.connect(lay)
	return b


func _layout_f(w: float, h: float, top: float, bottom: float, cw: float, x: float) -> void:
	var y_bar := top + UIKit.SPACE.sm + BAR_H
	var nh := NAV_H + 4
	_nav.position = Vector2(x, bottom - nh)
	_nav.size = Vector2(cw, nh)
	_strip.position = Vector2(x, y_bar + UIKit.SPACE.sm)
	_strip.size = Vector2(cw, 48)
	var cardw := (cw - UIKit.SPACE.md) / 2.0
	var cardh := roundf(cardw * 0.66) + UIKit.BW.rim + 20 + 26 + 8 + 50 + 8 + UIKit.LIP.lg + 1
	_cards.position = Vector2(x, _nav.position.y - UIKit.SPACE.md - cardh)
	_cards.size = Vector2(cw, cardh)
	var band_bottom := _cards.position.y - UIKit.SPACE.sm
	if _quick:
		var qh := 64.0
		_quick.position = Vector2(x, _cards.position.y - UIKit.SPACE.md - qh)
		_quick.size = Vector2(cw, qh)
		band_bottom = _quick.position.y - UIKit.SPACE.sm
	var ly := _strip.position.y + 48 + UIKit.SPACE.md
	# the logo shrinks so the table keeps a band of at least ~150 px
	var max_h := clampf(minf(0.2 * h, band_bottom - ly - 150.0), 96.0, 190.0)
	_place_logo(ly, w / 2.0, minf(220.0, cw), max_h)
	_band = Vector2(logo.position.y + logo.size.y, band_bottom)


## F2: the game's mode sheet (the real Sheet, "pm" look): QUICK MATCH first and biggest, then three rows.
func _open_mode_sheet(id: String) -> void:
	var layer: Control = null
	var n := get_parent()
	while n and layer == null:
		if "sheet_layer" in n:
			layer = n.sheet_layer
		n = n.get_parent()
	if layer == null:
		layer = self
	var title := "Ludo" if id == "ludo" else "Snakes & Ladders"
	var s := Sheet.new(title, UIKit.W.form, true, "pm")
	game = id
	var col := UIKit.vbox(UIKit.SPACE.sm + 2)
	s.body.add_child(col)
	var art := ColorRect.new()
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.custom_minimum_size = Vector2(0, 112)
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = ROUND_ART
	mat.shader = sh
	var tex: Texture2D = load("res://assets/thumbs/room_cafe.webp" if id == "ludo" else "res://assets/thumbs/scene_jungle.webp")
	mat.set_shader_parameter("tex", tex)
	mat.set_shader_parameter("tex_size", Vector2(tex.get_width(), tex.get_height()))
	mat.set_shader_parameter("focus_y", 0.72 if id == "ludo" else 0.62)
	mat.set_shader_parameter("radii", Vector4(14, 14, 14, 14))
	art.material = mat
	art.resized.connect(func(): mat.set_shader_parameter("rect_size", art.size))
	col.add_child(art)
	var qm := _big_play(76, 26, "Play online now")
	col.add_child(qm)
	for m in [["Play with friends", "A private room, invite by code", UIKit.ICON_DIR + FRIENDS + ".svg", "friends"],
			["Vs computer", "Offline, at your pace", HI % "cpu", "cpu"],
			["Pass & play", "Take turns on one phone", HI % "pass_play", "local"]]:
		col.add_child(_mode_row(m[0], m[1], m[2], m[3]))
	s.fit()
	s.open(layer)


func _mode_row(title: String, sub: String, icon_path: String, mode: String) -> Button:
	var st := UIKit.box(Palette.ROW, UIKit.R.lg, UIKit.BW.line, Palette.ROW_EDGE)
	st.border_width_bottom = UIKit.LIP.sm
	UIKit.pad(st, 10, 6)
	var pr := st.duplicate() as StyleBoxFlat
	pr.bg_color = Palette.ROW.darkened(0.04)
	pr.border_width_bottom = 1
	var b := _flat_button(st, pr)
	b.custom_minimum_size = Vector2(0, 64)
	b.pressed.connect(func(): play.emit(game, mode))
	var r := UIKit.hbox(UIKit.SPACE.md)
	_fill(r)
	r.offset_left = 10; r.offset_right = -12
	b.add_child(r)
	var ic := UIKit.icon(icon_path, 40)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.add_child(ic)
	var col := UIKit.vbox(-2)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_child(col)
	col.add_child(UIKit.label(title, UIKit.FS.h3, Palette.INK, UIKit.font_body(900)))
	var sl := UIKit.label(sub, UIKit.FS.small, Palette.SUB, UIKit.font_body(800))
	sl.clip_text = true
	sl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(sl)
	var chev := UIKit.icon("ic_back", 20)
	chev.flip_h = true
	chev.modulate = Color(Palette.INK, 0.55)
	chev.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.add_child(chev)
	return b


# =====================================================================================================================
# layout
# =====================================================================================================================

func _layout() -> void:
	var w := size.x
	var h := size.y
	if w <= 0:
		return
	var top := safe_top
	var bottom := h - maxf(safe_bottom + 8.0, BOTTOM_MIN)
	_veil.position = Vector2.ZERO
	_veil.size = Vector2(w, top + 180)
	var cw := minf(w - 2 * G, 480.0)
	var x := roundf((w - cw) / 2.0)
	_top.position = Vector2(x, top + UIKit.SPACE.sm)
	_top.size = Vector2(cw, BAR_H)
	# a tight bar (narrow phones, or D's extra gift button): the player chip keeps only the avatar
	var others := 0.0
	for c in _top.get_children():
		if c != _chip and c != _spacer:
			others += (c as Control).get_combined_minimum_size().x + UIKit.SPACE.sm
	var full := cw - others >= 120.0          # room for the name and the XP bar (>= 50 px)
	_chip_text.visible = full
	_spacer.visible = not full
	_chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL if full else Control.SIZE_SHRINK_BEGIN
	_chip.custom_minimum_size.x = BAR_H + 2 if not full else BAR_H
	_top.size = Vector2(cw, BAR_H)
	match variant:
		"D": _layout_d(w, h, top, bottom, cw, x)
		"E": _layout_e(w, h, top, bottom, cw, x)
		_: _layout_f(w, h, top, bottom, cw, x)


## The band between the logo and the first control below it, in UI pixels (for the home camera framing).
func free_band() -> Vector2:
	return _band
