class_name HomeScreen
extends Control
## The lobby over the slowly orbiting café ("Scene + dock", the layout the user picked). The top half is the café
## scene: the top bar (player chip with level, coins with a "+", the gear) and the game logo over the 3D table. The
## bottom is a cream dock: the three lobby features on its top edge (Spin / Daily / Free coins, live states), the
## quick-action slot (Continue match, else Play again, else hidden), the Ludo / Snakes & Ladders switch, the online
## row (QUICK MATCH, the primary action, and PLAY WITH FRIENDS), the offline row (VS COMPUTER, PASS & PLAY) and the
## nav (Home / Shop / Inventory). Every mode works for both games. Icons: the home family in assets/ui/home/hi_*.svg.
##
## Contract with main.gd:
##   play_game(game, mode)   game "ludo" | "sl", mode "cpu" | "local" (VS COMPUTER / PASS & PLAY); "online" only when
##                           nothing listens to play_friends (older main.gd builds)
##   quick_match(game)       QUICK MATCH (Online.open_quick)
##   play_friends(game)      PLAY WITH FRIENDS (Online.open_friends)
##   play(mode)              legacy: only emitted for Ludo when nothing is connected to play_game
##   continue_match()        the Continue match slot (MatchStore has a saved match)
##   play_again(cfg)         the Play again slot: cfg {game, mode, setup} from Save.prefs.last_played and
##                           Save.prefs.last_setup[game][mode]
##   game_switched(game)     the Ludo / Snakes & Ladders switch changed (Save.prefs.home_game is already updated)
##   open_tab(tab)           shop | inventory | profile | settings | coins | spin | daily | free | leaderboard | scenes (the Shop's Scenes tab,
##                           from "Change scene" while Snakes & Ladders is picked; home: already here, not emitted)
##   select_game(game)       pick "ludo" | "sl" on the switch from code (emits game_switched when it changes)
##   safe_top / safe_bottom  set by main; the layout keeps >= BOTTOM_MIN px above the bottom edge regardless
##   free_band() -> Vector2  (top, bottom) of the free area for the 3D table, in UI px
##   table_width_factor      the table may be this many screen widths wide when framed (bigger board)
##   coin_amount             the CoinAmount in the top bar (CoinFly target); side_button(id) -> the feature button
##   coin_fly_active         set true while a CoinFly runs to coin_amount (refresh() then leaves the number alone;
##                           in-flight CoinFly overlays aimed at coin_amount, anywhere in the tree, are detected too)
##   hold_coins(sec)         call BEFORE a reward is granted when a CoinFly will follow (Save.changed fires on the
##                           grant, before the fly exists): the counter keeps its old number for up to `sec` (or until
##                           the fly lands and counts it up); refresh() runs again when the hold ends

signal play(mode: String)                ## legacy (Ludo only): "cpu" | "local"
signal play_game(game: String, mode: String)
signal quick_match(game: String)
signal play_friends(game: String)
signal continue_match
signal play_again(cfg: Dictionary)          ## {game, mode, setup} (setup = Save.prefs.last_setup[game][mode])
signal game_switched(game: String)
signal open_tab(tab: String)             ## shop | inventory | profile | settings | coins | spin | daily | free | scenes

const HI := "res://assets/ui/home/hi_%s.svg"
const MATCH_STORE := "res://scripts/core/match_store.gd"
const REWARDS := "res://scripts/core/rewards.gd"
const BAR_H := 52.0                      # top bar height
const NAV_H := 64.0
const G := 16.0                          # screen gutter (UIKit.SCREEN_GUTTER)
const BOTTOM_MIN := 20.0                 # gesture-nav phones report 0 in immersive mode: keep this clear anyway
const TILE := 60.0                       # feature tile
const LIP_OVER := 30.0                   # how far the feature tiles rise above the dock's top edge
const QUICK_H := 56.0
const SWITCH_H := 60.0
const MODE_H := 58.0                     # the online row: QUICK MATCH (primary) + PLAY WITH FRIENDS
const FRIENDS_H := 52.0                  # the offline row under it: VS COMPUTER + PASS & PLAY
const AVATAR := 42.0                     # the top bar's avatar
const SWITCH_ICON := 32.0
const SWITCH_FS := 15                    # the switch labels (UIKit.FS.label + 1); never below UIKit.FS.label

var safe_top := 0.0:
	set(v):
		safe_top = v
		if is_node_ready():
			_layout()
var safe_bottom := 0.0:
	set(v):
		safe_bottom = v
		if is_node_ready():
			_layout()
var table_width_factor := 1.3
var coin_fly_active := false
var _hold_until := 0                     # Time.get_ticks_msec() until which refresh() leaves coin_amount alone
var game := "ludo"

var logo: BrandLogo
var coin_amount: CoinAmount
var sides := {}                          # id -> SideButton (spin | daily | free)

var _top: HBoxContainer
var _name: Label
var _avatar: Control
var _level: LevelBadge
var _xp: Meter
var _veil: TextureRect
var _dock: Panel
var _quick: Button
var _quick_icon: TextureRect
var _quick_title: Label
var _quick_sub: Label
var _quick_go: Button
var _quick_kind := ""                    # "continue" | "again" | ""
var _again := {}                         # {game, mode} for Play again
var _switch: PanelContainer
var _switch_buttons := {}                # game -> Button
var _switch_parts := {}                  # game -> {row, icon, label, text}
var _scene_chip: Button                  # "Change scene" (Snakes & Ladders selected): the Shop's Scenes tab
var _modes: HBoxContainer
var friends_button: Button               # PLAY WITH FRIENDS (online rooms)
var quick_button: Button                 # QUICK MATCH (the matchmaker)
var _online: HBoxContainer               # the online row
var _tabs: HBoxContainer                 # the nav row (dev/tap_dbg.gd reads its first child)
var _rule: ColorRect
var _dots := {}                          # feature id -> red dot
var _cd_text := {}                       # feature id -> countdown shown
var _timer: Timer
var _band := Vector2(200, 500)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	game = _pref_game()
	_build_veil()
	_build_top_bar()
	logo = BrandLogo.new()
	logo.bob = true
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(logo)
	_build_dock()
	_timer = Timer.new()
	_timer.wait_time = 1.0
	_timer.timeout.connect(_refresh_sides)
	add_child(_timer)
	visibility_changed.connect(_on_visibility)
	Save.changed.connect(refresh)
	resized.connect(_layout)
	refresh()
	_on_visibility()


# =====================================================================================================================
# Build
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


## A flat Button with its own styleboxes (press feedback from UIKit.wire_press).
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


## The cream glass of the top bar chips: glass, a white rim, a soft shadow.
static func _chip_style(r := 18, pressed := false) -> StyleBoxFlat:
	var s := UIKit.box(Palette.GLASS_PRESSED if pressed else Palette.GLASS, r, UIKit.BW.line, Color.WHITE)
	UIKit.shade(s, "sm")
	UIKit.pad(s, 8, 6)
	return s


static func _fill(c: Control) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _build_top_bar() -> void:
	_top = UIKit.hbox(UIKit.SPACE.sm)
	add_child(_top)
	# player chip: avatar, name, the level star over the XP bar (opens the profile)
	var chip := _flat_button(_chip_style(), _chip_style(18, true))
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chip.custom_minimum_size = Vector2(0, BAR_H)
	chip.pressed.connect(func(): open_tab.emit("profile"))
	_top.add_child(chip)
	var r := UIKit.hbox(UIKit.SPACE.sm)
	_fill(r)
	r.offset_left = 5; r.offset_top = 5; r.offset_right = -10; r.offset_bottom = -5
	r.add_theme_constant_override("separation", UIKit.SPACE.md)     # room for the star's overhang
	chip.add_child(r)
	# the avatar with the level star on its bottom-right corner (a 28 px badge, 12 px digits: readable, and never
	# on top of the XP bar)
	var av := Control.new()
	av.custom_minimum_size = Vector2(AVATAR, AVATAR)
	av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	av.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_child(av)
	_avatar = Collection.make_avatar(AVATAR)
	_avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	av.add_child(_avatar)
	_level = LevelBadge.new(1, "sm")
	_level.position = Vector2(AVATAR - _level.px + 9.0, AVATAR - _level.px + 4.0)
	_level.size = Vector2(_level.px, _level.px)
	av.add_child(_level)
	var col := UIKit.vbox(3)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_child(col)
	_name = UIKit.label("You", UIKit.FS.label + 1, Palette.INK, UIKit.font_body(900))
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name.clip_text = true
	col.add_child(_name)
	# web .pxp: gold on a dark inset ink track, with the numbers ("140 / 150"; "140/150" when tight, none when it
	# can't fit)
	_xp = Meter.new("night", 16, true)
	col.add_child(_xp)
	# coins: the balance and a teal "+" (opens the Earn coins hub)
	var coins := _flat_button(_chip_style(UIKit.R.pill), _chip_style(UIKit.R.pill, true))
	coins.custom_minimum_size = Vector2(108, BAR_H)
	coins.pressed.connect(func(): open_tab.emit("coins"))
	_top.add_child(coins)
	var cr := UIKit.hbox(6)
	_fill(cr)
	cr.offset_left = 6; cr.offset_right = -6
	cr.alignment = BoxContainer.ALIGNMENT_CENTER
	coins.add_child(cr)
	coin_amount = CoinAmount.new(int(Save.profile.get("coins", 0)), "lg", "plain")
	coin_amount.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cr.add_child(coin_amount)
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
	var gear := UIKit.icon_button(HI % "gear", "glass", int(BAR_H), 32)
	gear.pressed.connect(func(): open_tab.emit("settings"))
	_top.add_child(gear)


func _build_dock() -> void:
	_dock = Panel.new()
	var s := UIKit.box(Palette.CARD, 0, 0)
	s.corner_radius_top_left = UIKit.R.xl + 2; s.corner_radius_top_right = UIKit.R.xl + 2
	s.corner_detail = 12
	s.shadow_size = 18; s.shadow_offset = Vector2(0, -2); s.shadow_color = Palette.shadow(0.35)
	s.border_width_top = UIKit.BW.line; s.border_color = Color.WHITE
	_dock.add_theme_stylebox_override("panel", s)
	_dock.mouse_filter = Control.MOUSE_FILTER_STOP        # taps on the dock never reach the 3D room
	add_child(_dock)
	for f in [["spin", "Spin", HI % "spin"], ["daily", "Daily", HI % "gift"], ["free", "Free", HI % "coins"],
			["leaderboard", "Ranks", "res://assets/ui/ic_trophy.svg"]]:
		var sb := SideButton.new(f[0], f[1], f[2], [Palette.CARD, Palette.LIP_CREAM], TILE)
		sb.caption.add_theme_font_override("font", UIKit.font_body(900))   # font_caps renders too light for now
		sb.caption.add_theme_color_override("font_color", Palette.INK)
		sb.caption.add_theme_constant_override("outline_size", 0)
		sb.pressed.connect(func(id): open_tab.emit(id))
		add_child(sb)
		sides[f[0]] = sb
		var dot := Panel.new()
		dot.add_theme_stylebox_override("panel", UIKit.box(Palette.RED, UIKit.R.pill, UIKit.BW.line, Color.WHITE))
		dot.size = Vector2(14, 14)
		dot.position = Vector2((SideButton.WIDTH - TILE) / 2.0 + TILE - 11.0, -4.0)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.visible = false
		sb.add_child(dot)
		_dots[f[0]] = dot
	_build_quick()
	_build_switch()
	_scene_chip = UIKit.button_with("Change scene", UIKit.icon("cat_scenes", 22), "white", "sm")
	_scene_chip.name = "ChangeScene"
	_scene_chip.pressed.connect(func(): open_tab.emit("scenes"))
	_scene_chip.visible = game == "sl"
	add_child(_scene_chip)
	_online = UIKit.hbox(UIKit.SPACE.md - 2)
	_online.name = "Online"
	quick_button = _row_button("QUICK MATCH", "honey", HI % "quick", 36, 20)
	quick_button.name = "QuickMatch"
	quick_button.size_flags_stretch_ratio = 1.35
	quick_button.pressed.connect(func(): quick_match.emit(game))
	_online.add_child(quick_button)
	friends_button = _row_button("PLAY WITH\nFRIENDS", "white", "perk_friends", 30, 15)
	friends_button.name = "Friends"
	friends_button.pressed.connect(_friends)
	_online.add_child(friends_button)
	add_child(_online)
	_modes = UIKit.hbox(UIKit.SPACE.md - 2)
	_modes.add_child(_mode_button("VS COMPUTER", "teal", "cpu", "cpu"))
	_modes.add_child(_mode_button("PASS & PLAY", "white", "pass_play", "local"))
	add_child(_modes)
	_rule = ColorRect.new()
	_rule.color = Palette.LINE
	_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rule)
	_build_nav()


## The quick-action slot: Continue match / Play again (hidden when there is neither).
func _build_quick() -> void:
	var st := UIKit.box(Palette.SURFACE_2, UIKit.R.lg, UIKit.BW.line, Palette.ROW_EDGE)
	st.border_width_bottom = UIKit.LIP.sm
	UIKit.pad(st, 8, 6)
	var pr := st.duplicate() as StyleBoxFlat
	pr.bg_color = Palette.CHIP
	pr.border_width_bottom = 1
	_quick = _flat_button(st, pr)
	_quick.custom_minimum_size = Vector2(0, QUICK_H)
	_quick.pressed.connect(_on_quick)
	add_child(_quick)
	var r := UIKit.hbox(10)
	_fill(r)
	r.offset_left = 8; r.offset_right = -8
	_quick.add_child(r)
	_quick_icon = UIKit.icon(HI % "resume", 40)
	_quick_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.add_child(_quick_icon)
	var col := UIKit.vbox(0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_child(col)
	_quick_title = UIKit.label("", UIKit.FS.h3, Palette.INK, UIKit.font_body(900))
	col.add_child(_quick_title)
	_quick_sub = UIKit.label("", UIKit.FS.small, Palette.MUTED, UIKit.font_body(800))
	_quick_sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_quick_sub.clip_text = true
	col.add_child(_quick_sub)
	_quick_go = UIKit.button("Resume", "teal", "xs")
	_quick_go.mouse_filter = Control.MOUSE_FILTER_IGNORE      # the whole slot is the button
	_quick_go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_quick_go.custom_minimum_size.x = 84
	r.add_child(_quick_go)
	_quick.visible = false


## The game switch: two segments (family icon + name); the selected one is a raised white face.
func _build_switch() -> void:
	_switch = PanelContainer.new()
	var ts := UIKit.box(Palette.CHIP, UIKit.R.lg)
	UIKit.pad(ts, 4)
	_switch.add_theme_stylebox_override("panel", ts)
	add_child(_switch)
	var row := UIKit.hbox(4)
	_switch.add_child(row)
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
		b.custom_minimum_size = Vector2(0, UIKit.TAP + 4)
		for k in ["normal", "hover", "disabled"]:
			b.add_theme_stylebox_override(k, off)
		for k in ["pressed", "hover_pressed"]:
			b.add_theme_stylebox_override(k, on)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		UIKit.wire_press(b, "select")
		b.clip_contents = true                # nothing ever spills past its half (the label fits, see _fit_switch)
		var r := UIKit.hbox(UIKit.SPACE.sm)
		_fill(r)
		r.alignment = BoxContainer.ALIGNMENT_CENTER
		b.add_child(r)
		var ic := UIKit.icon(HI % g[2], SWITCH_ICON)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		r.add_child(ic)
		var l := UIKit.label(g[1], SWITCH_FS, Palette.INK, UIKit.font_body(900))
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		l.add_theme_constant_override("line_spacing", -3)
		r.add_child(l)
		var key: String = g[0]
		_switch_parts[key] = {row = r, icon = ic, label = l, text = g[1]}
		b.button_pressed = key == game
		b.toggled.connect(func(v: bool): if v: _set_game(key))
		row.add_child(b)
		_switch_buttons[key] = b


func _mode_button(text: String, kind: String, icon_name: String, mode: String) -> Button:
	var b := _row_button(text, kind, HI % icon_name, 32, 17)
	b.pressed.connect(func(): _play(mode))
	return b


## A dock button: icon + caps label (Lilita, `fs`, shrinking to fit the button down to 12; "\n" = two lines).
func _row_button(text: String, kind: String, icon_path: String, icon_px: float, fs: int) -> Button:
	var ic := UIKit.icon(icon_path, icon_px)
	var b := UIKit.button_with(text, ic, kind, "md")
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := b.find_child("Content", true, false) as HBoxContainer
	if row:
		row.add_theme_constant_override("separation", UIKit.SPACE.xs + 2)
	var l := b.find_child("Text", true, false) as Label
	if l:
		l.add_theme_font_size_override("font_size", fs)
		l.add_theme_constant_override("line_spacing", -4)
		var fit := func() -> void:
			var room := b.size.x - 2.0 * UIKit.SPACE.sm - icon_px - float(UIKit.SPACE.xs + 2)
			var f := l.get_theme_font("font")
			var k := fs
			var widest := func(sz: int) -> float:
				var m := 0.0
				for ln in l.text.split("\n"):
					m = maxf(m, f.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x)
				return m
			while k > UIKit.FS.small and float(widest.call(k)) > room:
				k -= 1
			l.add_theme_font_size_override("font_size", k)
			ic.custom_minimum_size = Vector2(icon_px, icon_px) * (1.0 if float(widest.call(k)) <= room else 0.8)
		b.resized.connect(fit)
	return b


func _build_nav() -> void:
	_tabs = UIKit.hbox(6)
	add_child(_tabs)
	for t in [["home", "Home"], ["shop", "Shop"], ["inventory", "Inventory"]]:   # the profile: the player chip up top
		var on: bool = t[0] == "home"
		var st := UIKit.box(Palette.HONEY_TINT if on else Color(1, 1, 1, 0), UIKit.R.lg, UIKit.BW.line if on else 0, Palette.HONEY_TINT_EDGE)
		UIKit.pad(st, 0)
		var pr := UIKit.box(Palette.CHIP, UIKit.R.lg)
		UIKit.pad(pr, 0)
		var b := _flat_button(st, pr)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, NAV_H - 8)
		var col := UIKit.vbox(0)
		_fill(col)
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		b.add_child(col)
		var ic := UIKit.icon(HI % t[0], 30)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(ic)
		col.add_child(UIKit.label(t[1], UIKit.FS.small, Palette.INK if on else Palette.SUB, UIKit.font_body(900), HORIZONTAL_ALIGNMENT_CENTER))
		var id: String = t[0]
		if not on:
			b.pressed.connect(func(): open_tab.emit(id))
		_tabs.add_child(b)


# =====================================================================================================================
# Actions
# =====================================================================================================================

func _play(mode: String) -> void:
	play_game.emit(game, mode)
	if game == "ludo" and get_signal_connection_list("play_game").is_empty():
		play.emit(mode)                    # older main.gd builds listen to play(mode) only


## PLAY WITH FRIENDS: Online listens to play_friends; older main.gd builds get play_game(game, "online").
func _friends() -> void:
	if get_signal_connection_list("play_friends").is_empty():
		_play("online")
	else:
		play_friends.emit(game)

func _set_game(g: String) -> void:
	if g == game:
		return
	game = g
	if Save.prefs.get("home_game", "ludo") != g:
		Save.prefs.home_game = g
		Save.save()
	_scene_chip.visible = g == "sl"
	_layout()
	game_switched.emit(g)


## Pick the game on the switch from code (as if tapped): "ludo" | "sl". Emits game_switched when it changes.
func select_game(g: String) -> void:
	if not g in ["ludo", "sl"]:
		return
	var b: Button = _switch_buttons.get(g)
	if b and not b.button_pressed:
		b.button_pressed = true                # the toggled handler runs _set_game
	else:
		_set_game(g)


func _pref_game() -> String:
	var g: Variant = Save.prefs.get("home_game", "ludo")
	return str(g) if g in ["ludo", "sl"] else "ludo"


func _on_quick() -> void:
	if _quick_kind == "continue":
		continue_match.emit()
	elif _quick_kind == "again":
		play_again.emit(_again.duplicate(true))


## A feature button by id (spin | daily | free), for CoinFly origins and coach marks.
func side_button(id: String) -> Control:
	return sides.get(id)


# =====================================================================================================================
# State
# =====================================================================================================================

func _on_visibility() -> void:
	if not is_inside_tree():
		return
	var on := is_visible_in_tree()
	if on:
		_refresh_sides()
		_timer.start()
	else:
		_timer.stop()


## The live state of Spin / Daily reward / Free coins (once per second while visible).
func _refresh_sides() -> void:
	if sides.is_empty() or not ResourceLoader.exists(REWARDS):
		return
	var R: Script = load(REWARDS)
	var p: Dictionary = Save.profile
	var spin_ok: bool = R.can_spin(p)
	var daily_ok := bool((R.daily_state(p) as Dictionary).get("claimable", false))
	var left: int = R.free_left_sec(p)
	var midnight := Fmt.until(int(R.sec_to_midnight()))
	_side_state("spin", spin_ok, "" if spin_ok else midnight)
	_side_state("daily", daily_ok, "" if daily_ok else midnight)
	_side_state("free", left <= 0, "" if left <= 0 else Fmt.clock(left))


func _side_state(id: String, is_ready: bool, countdown: String) -> void:
	if _cd_text.get(id, "-") != countdown:          # set_countdown re-lays the button: only on change
		_cd_text[id] = countdown
		(sides[id] as SideButton).set_countdown(countdown)
	(_dots[id] as Control).visible = is_ready
	(sides[id] as SideButton).set_ready(is_ready)     # cooling down: the tile greys out (still tappable: it says when)


func refresh() -> void:
	if not is_inside_tree():
		return
	var p: Dictionary = Save.profile
	_name.text = str(p.get("name", "You"))
	if _avatar and _avatar.has_method("refresh"):
		_avatar.refresh()
	var li := Save.level_info(int(p.get("xp", 0)))
	_level.set_level(int(li.level))
	_xp.set_value(float(li.into), float(li.need))
	if not _coins_busy():
		coin_amount.set_amount(int(p.get("coins", 0)))
	var sel: Button = _switch_buttons.get(game)
	if sel and not sel.button_pressed:
		sel.set_pressed_no_signal(true)
	_refresh_sides()
	_refresh_quick()


## Keep the counter on its current number for up to `sec` while a CoinFly is about to land on it (the fly counts
## it up on its first arrival). Call before granting the coins; refresh() runs again when the hold ends.
func hold_coins(sec := 2.5) -> void:
	var until := Time.get_ticks_msec() + int(sec * 1000.0)
	if until <= _hold_until:
		return
	_hold_until = until
	if is_inside_tree():
		get_tree().create_timer(sec + 0.05).timeout.connect(func():
			if Time.get_ticks_msec() >= _hold_until:
				refresh())


## A CoinFly is counting the balance up (or about to): leave the number to it.
func _coins_busy() -> bool:
	if coin_fly_active:
		return true
	if coin_amount._tw and coin_amount._tw.is_valid() and coin_amount._tw.is_running():
		return true
	var fly := _fly_to(get_tree().root, coin_amount)
	if fly:
		return true
	return Time.get_ticks_msec() < _hold_until


## The first CoinFly under `n` aimed at `target`, or null (sheets host their own flies, not only main's ui_root).
static func _fly_to(n: Node, target: Control) -> CoinFly:
	for c in n.get_children():
		if c is CoinFly:
			if (c as CoinFly)._target == target and not c.is_queued_for_deletion():
				return c
		elif c.get_child_count() > 0 and not (c is Node3D):
			var f := _fly_to(c, target)
			if f:
				return f
	return null


func _refresh_quick() -> void:
	var kind := ""
	if ResourceLoader.exists(MATCH_STORE):
		var MS: Script = load(MATCH_STORE)
		if MS.has_saved():
			var pk: Dictionary = MS.peek()
			kind = "continue"
			var g := str(pk.get("game", "ludo"))
			var sub := str(pk.get("summary", ""))
			if sub == "":
				sub = "Snakes & Ladders" if g == "sl" else "Ludo"
			var ago := _ago(int(pk.get("saved_at", 0)))
			_quick_title.text = "Continue match"
			_quick_sub.text = sub + (" · " + ago if ago != "" and sub.length() + ago.length() <= 30 else "")
			_quick_icon.texture = UIKit.svg(HI % "resume")
			_quick_go.text = "Resume"
			UIKit.set_kind(_quick_go, "teal")
	if kind == "":
		_again = _last_played()
		if not _again.is_empty():
			kind = "again"
			_quick_title.text = "Play again"
			_quick_sub.text = _setup_line(_again)
			_quick_icon.texture = UIKit.svg(HI % "again")
			_quick_go.text = "Play"
			UIKit.set_kind(_quick_go, "honey")
	if kind != _quick_kind:
		_quick_kind = kind
		_quick.visible = kind != ""
		_layout()
		var main := get_parent()
		while main and not main.has_method("_fit_home"):
			main = main.get_parent()
		if main:
			main.call("_fit_home")              # the free band changed: re-frame the table


## The last game and mode played with a remembered setup: {game, mode, setup} or {}.
static func _last_played() -> Dictionary:
	var lp: Variant = Save.prefs.get("last_played")
	if not lp is Dictionary:
		return {}
	var g := str((lp as Dictionary).get("game", ""))
	var m := str((lp as Dictionary).get("mode", ""))
	var all: Variant = Save.prefs.get("last_setup")
	if not all is Dictionary or not (all as Dictionary).get(g) is Dictionary:
		return {}
	var d: Variant = ((all as Dictionary)[g] as Dictionary).get(m)
	if not d is Dictionary or not g in ["ludo", "sl"] or not m in ["cpu", "local"]:
		return {}
	return {game = g, mode = m, setup = d}


## "Ludo · vs 3 computers · Normal" / "Snakes & Ladders · 3 players" / "Ludo · Teams (2 v 2) · Hard".
static func _setup_line(a: Dictionary) -> String:
	var d: Dictionary = a.setup
	var parts := PackedStringArray(["Snakes & Ladders" if a.game == "sl" else "Ludo"])
	var n := int(d.get("count", 3 if a.mode == "cpu" else 2))
	if bool(d.get("teams", false)) and a.game == "ludo":
		parts.append("Teams (2 v 2)")
	elif a.mode == "cpu":
		parts.append("vs %d computer%s" % [n, "" if n == 1 else "s"])
	else:
		parts.append("%d players" % n)
	if a.mode == "cpu" and d.get("bot_level") is String:
		parts.append(str(d.bot_level).capitalize())
	return " · ".join(parts)


static func _ago(unix: int) -> String:
	if unix <= 0:
		return ""
	var s := int(Time.get_unix_time_from_system()) - unix
	if s < 60:
		return "just now"
	if s < 3600:
		return "%d min ago" % (s / 60)
	if s < 86400:
		return "%dh ago" % (s / 3600)
	var d := s / 86400
	return "yesterday" if d == 1 else "%d days ago" % d


## Kept for older callers: the short coin form (Fmt.coins).
static func _short(n: int) -> String:
	return Fmt.coins(n)


# =====================================================================================================================
# Layout
# =====================================================================================================================

## Lay out for the current size and safe area; updates the free band for the table.
func _layout() -> void:
	var w := size.x
	var h := size.y
	if w <= 0 or _dock == null:
		return
	var top := safe_top
	var bottom := h - maxf(safe_bottom + 8.0, BOTTOM_MIN)
	_veil.position = Vector2.ZERO
	_veil.size = Vector2(w, top + 180)
	var cw := minf(w - 2 * G, 480.0)            # content width (tablets: centred column)
	var x := roundf((w - cw) / 2.0)
	_top.position = Vector2(x, top + UIKit.SPACE.sm)
	_top.size = Vector2(cw, BAR_H)
	var y_bar := top + UIKit.SPACE.sm + BAR_H
	# the dock, bottom up: nav, rule, mode buttons, switch, quick slot, feature tiles on the edge
	var nav_y := bottom - NAV_H + 4
	_tabs.position = Vector2(x - 6, nav_y)
	_tabs.size = Vector2(cw + 12, NAV_H - 4)
	_rule.position = Vector2(x, nav_y - UIKit.SPACE.sm)
	_rule.size = Vector2(cw, 2)
	_modes.position = Vector2(x, nav_y - UIKit.SPACE.lg - FRIENDS_H)
	_modes.size = Vector2(cw, FRIENDS_H)
	_online.position = Vector2(x, _modes.position.y - UIKit.SPACE.sm - MODE_H)
	_online.size = Vector2(cw, MODE_H)
	_switch.position = Vector2(x, _online.position.y - UIKit.SPACE.md - SWITCH_H)
	_switch.size = Vector2(cw, SWITCH_H)
	var top_of := _switch.position.y
	if _quick.visible:
		_quick.position = Vector2(x, top_of - 10 - QUICK_H)
		_quick.size = Vector2(cw, QUICK_H)
		top_of = _quick.position.y
	_fit_switch(cw)
	var below := TILE - LIP_OVER + 3 + 18 + 20            # tile part inside the dock + caption + countdown pill
	var dock_y := top_of - UIKit.SPACE.md - below
	_dock.position = Vector2(0, dock_y)
	_dock.size = Vector2(w, h - dock_y + 4)
	var ids := ["spin", "daily", "free", "leaderboard"]
	var tw := SideButton.WIDTH
	var gap := clampf((w - 2.0 * G - ids.size() * tw) / (ids.size() - 1.0), 4.0, 28.0)
	var total := ids.size() * tw + (ids.size() - 1) * gap
	var x0 := roundf((w - total) / 2.0)
	for i in ids.size():
		(sides[ids[i]] as Control).position = Vector2(x0 + i * (tw + gap), dock_y - LIP_OVER)
	# the logo in the scene, as large as the space allows
	var lw := minf(270.0, w - 2 * G)
	var lh := lw * 266.0 / 320.0
	var max_h := 0.24 * h
	if lh > max_h:
		lh = max_h
		lw = lh * 320.0 / 266.0
	logo.size = Vector2(lw, lh)
	logo.position = Vector2(roundf((w - lw) / 2.0), y_bar + 14)
	_band = Vector2(logo.position.y + logo.size.y, dock_y - LIP_OVER - 10)
	# Snakes & Ladders: "Change scene" just above the feature tiles; the board is framed above it
	if _scene_chip.visible:
		var bs := _scene_chip.get_combined_minimum_size()
		var row := _scene_chip.get_node_or_null("Content") as Control
		if row:                                  # the content row isn't part of the button's minimum size
			bs.x = maxf(bs.x, row.get_combined_minimum_size().x + 2.0 * float(UIKit.BTN.sm.pad) + 8.0)
		_scene_chip.size = bs
		_scene_chip.position = Vector2(roundf((w - bs.x) / 2.0), dock_y - LIP_OVER - 8.0 - bs.y)
		_band.y = _scene_chip.position.y - 4.0


## The switch labels at the size that fits their half (item: the long "Snakes & Ladders" never overflows): 15 px with
## a 32 px icon, then 14 px, then a 26 px icon, then the name on two lines. Both halves use the same size.
func _fit_switch(cw: float) -> void:
	if _switch_parts.is_empty():
		return
	var half := (cw - 8.0 - 4.0) / 2.0                     # panel padding 4 + 4, the gap between the halves
	var room := half - 2.0 * UIKit.SPACE.sm
	var font := UIKit.font_body(900)
	var widest := func(fs: int, two: bool) -> float:
		var m := 0.0
		for k in _switch_parts:
			var t: String = _switch_parts[k].text
			var lines: PackedStringArray = _two_lines(t).split("\n") if two else PackedStringArray([t])
			for ln in lines:
				m = maxf(m, font.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
		return m
	var pick := [SWITCH_FS, SWITCH_ICON, UIKit.SPACE.sm, false]
	var tries := [[SWITCH_FS, SWITCH_ICON, UIKit.SPACE.sm, false], [UIKit.FS.label, SWITCH_ICON, UIKit.SPACE.sm, false],
		[UIKit.FS.label, 26.0, UIKit.SPACE.xs + 2, false], [UIKit.FS.label, 30.0, UIKit.SPACE.sm, true]]
	for t in tries:
		pick = t
		if float(t[1]) + float(t[2]) + float(widest.call(t[0], t[3])) <= room:
			break
	for k in _switch_parts:
		var part: Dictionary = _switch_parts[k]
		var l: Label = part.label
		l.add_theme_font_size_override("font_size", int(pick[0]))
		l.text = _two_lines(part.text) if pick[3] else part.text
		(part.icon as Control).custom_minimum_size = Vector2(pick[1], pick[1])
		(part.row as HBoxContainer).add_theme_constant_override("separation", int(pick[2]))


## "Snakes & Ladders" -> "Snakes &\nLadders" (a name of one word stays on one line).
static func _two_lines(t: String) -> String:
	var at := t.rfind(" ")
	return t if at < 0 else t.substr(0, at) + "\n" + t.substr(at + 1)


## The band between the logo and the dock's feature tiles, in UI pixels (for the home camera framing).
func free_band() -> Vector2:
	return _band
