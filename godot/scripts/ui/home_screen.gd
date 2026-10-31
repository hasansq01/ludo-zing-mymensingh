class_name HomeScreen
extends Control
## The lobby over the slowly orbiting café ("One big Play", the layout the owner picked). The café scene is the hero:
## the top bar (player chip with level and XP, coins with a "+", the Rewards gift with a red count of the rewards
## ready now, the gear), a smaller game logo over the 3D table and, when a match was kept, a slim "Continue match"
## pill just above the dock. The cream dock at the bottom: the Ludo / Snakes & Ladders switch, one big QUICK MATCH,
## a row of three compact modes (Friends / Computer / Pass & Play) and the nav (Home / Shop / Ranks / Inventory).
## Every mode works for both games. Free spin / Daily reward / Free coins live in the Rewards sheet (the gift).
## Icons: the home family in assets/ui/home/hi_*.svg.
##
## Contract with main.gd:
##   play_game(game, mode)   game "ludo" | "sl", mode "cpu" | "local" (Computer / Pass & Play); "online" only when
##                           nothing listens to play_friends (older main.gd builds)
##   quick_match(game)       QUICK MATCH (Online.open_quick)
##   play_friends(game)      Friends (Online.open_friends)
##   play(mode)              legacy: only emitted for Ludo when nothing is connected to play_game
##   continue_match()        the Continue match pill (MatchStore has a saved match)
##   game_switched(game)     the Ludo / Snakes & Ladders switch changed (Save.prefs.home_game is already updated)
##   open_tab(tab)           rewards (the gift) | shop | leaderboard (Ranks) | inventory | profile | settings | coins
##                           (home: already here, not emitted)
##   select_game(game)       pick "ludo" | "sl" on the switch from code (emits game_switched when it changes)
##   safe_top / safe_bottom  set by main; the layout keeps >= BOTTOM_MIN px above the bottom edge regardless
##   free_band() -> Vector2  (top, bottom) of the free area for the 3D table, in UI px
##   table_width_factor      the table may be this many screen widths wide when framed (bigger board)
##   gem_amount              the gems under the coins in the same chip (tap: the Store, open_tab "store")
##   coin_amount             the CoinAmount in the top bar (CoinFly target); side_button(id) -> where the coins of
##                           reward `id` fly from when no Rewards sheet is open (the gift)
##   toast_anchor()          the control a Home toast sits above (never over the play buttons)
##   reward_states(p) / ready_count(p)   static: Free spin / Daily reward / Free coins now (the gift's count and the
##                           Rewards sheet read the same rules)
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
signal game_switched(game: String)
signal open_tab(tab: String)             ## rewards | shop | leaderboard | inventory | profile | settings | coins | store

const HI := "res://assets/ui/home/hi_%s.svg"
const TROPHY := "res://assets/ui/ic_trophy.svg"
# The table literals below ("Friends", "Computer", "Ranks"...) are shown through tr(); listed here for the extractor.
const _TABLE_TEXT := ["Computer", "Pass & Play", "Ludo", "Home", "Shop", "Ranks", "Inventory"]  # l10n
const REWARD_IDS := ["spin", "daily", "free"]
const BAR_H := 52.0                      # top bar height
const WALLET_W := 104.0                  # the coins-over-gems chip (grows with the numbers)
const NAV_H := 60.0
const G := 16.0                          # screen gutter (UIKit.SCREEN_GUTTER)
const BOTTOM_MIN := 20.0                 # gesture-nav phones report 0 in immersive mode: keep this clear anyway
const PILL_H := 52.0                     # the Continue match pill
const QUICK_INNER := 40.0                # its round icon and Resume pill: (PILL_H - 40) / 2 = 6 px all round, like the row's sides
const SWITCH_H := 56.0                   # (its halves: 48 px tall)
const PLAY_H := 76.0                     # the one big QUICK MATCH
const MODE_H := 64.0                     # the row of three: Friends / Computer / Pass & Play
const SHORT_H := 760.0                   # below this UI height the two get a little lower
const TABLE_MIN := 160.0                 # the free band the logo leaves for the table (when it can)
const AVATAR := 42.0                     # the top bar's avatar
const SWITCH_ICON := 30.0
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
var gem_amount: CoinAmount               # the gems next to the coins (tap: the Store)
var rewards_button: Button               # the gift (opens the Rewards sheet)
var quick_button: Button                 # QUICK MATCH (the matchmaker)
var friends_button: Button               # Friends (online rooms)

var _top: HBoxContainer
var _gems_button: Button
var _chip: Button                        # the player chip (only the avatar when the bar is tight)
var _chip_text: Control                  # its name + XP column
var _name: Label
var _avatar: Control
var _level: LevelBadge
var _xp: Meter
var _gift_badge: Label                   # the red count on the gift
var _badge_tw: Tween
var _ready_n := -1                       # the count shown
var _veil: TextureRect
var _dock: Panel
var _quick: Button                       # the Continue match pill
var _quick_icon: TextureRect
var _quick_title: Label
var _quick_sub: Label
var _quick_go: Button
var _quick_kind := ""                    # "continue" | ""
var _switch: PanelContainer
var _switch_buttons := {}                # game -> Button
var _switch_parts := {}                  # game -> {row, icon, label, text}
var _modes: HBoxContainer                # Friends / Computer / Pass & Play
var _tabs: HBoxContainer                 # the nav row (dev/tap_dbg.gd reads its first child)
var _rule: ColorRect
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
	_timer.timeout.connect(_refresh_rewards)
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


## A transparent button for a row inside a chip: a soft shade while pressed.
static func _row_button() -> Button:
	var pr := UIKit.box(Color(0.29, 0.17, 0.24, 0.08), UIKit.R.sm)
	UIKit.pad(pr, 0)
	var b := _flat_button(StyleBoxEmpty.new(), pr)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	_chip = _flat_button(_chip_style(), _chip_style(18, true))
	_chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chip.custom_minimum_size = Vector2(BAR_H, BAR_H)
	_chip.pressed.connect(func(): open_tab.emit("profile"))
	_top.add_child(_chip)
	var r := UIKit.hbox(UIKit.SPACE.md)                  # room for the star's overhang
	_fill(r)
	r.offset_left = 5; r.offset_top = 5; r.offset_right = -10; r.offset_bottom = -5
	_chip.add_child(r)
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
	_place_level()
	av.add_child(_level)
	var col := UIKit.vbox(3)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_child(col)
	_chip_text = col
	_name = UIKit.label(L10n.seat_name("You"), UIKit.FS.label + 1, Palette.INK, UIKit.font_body(900))
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name.clip_text = true
	col.add_child(_name)
	_xp = Meter.new("night", 12)                          # gold on a dark inset track, no numbers (the profile has them)
	col.add_child(_xp)
	# the wallet: one chip, coins over gems. Coins and a teal "+" open the Earn coins hub; the gems open the Store
	var wallet := PanelContainer.new()
	wallet.name = "Wallet"
	var wst := _chip_style(UIKit.R.lg)
	UIKit.pad(wst, 6, 0)
	wallet.add_theme_stylebox_override("panel", wst)
	wallet.custom_minimum_size = Vector2(WALLET_W, BAR_H)
	_top.add_child(wallet)
	var wv := UIKit.vbox(0)
	wv.alignment = BoxContainer.ALIGNMENT_CENTER
	wallet.add_child(wv)
	var coins := _row_button()
	coins.name = "Coins"
	coins.custom_minimum_size.y = 26
	coins.pressed.connect(func(): open_tab.emit("coins"))
	wv.add_child(coins)
	var cr := UIKit.hbox(5)
	_fill(cr)
	cr.alignment = BoxContainer.ALIGNMENT_CENTER
	coins.add_child(cr)
	coin_amount = CoinAmount.new(int(Save.profile.get("coins", 0)), "md", "plain")
	coin_amount.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cr.add_child(coin_amount)
	var plus := PanelContainer.new()
	plus.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ps := UIKit.box(Palette.TEAL, UIKit.R.pill, UIKit.BW.line, Color.WHITE)
	UIKit.pad(ps, 0)
	plus.add_theme_stylebox_override("panel", ps)
	plus.custom_minimum_size = Vector2(20, 20)
	plus.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var pl := UIKit.label("+", 16, Color.WHITE, UIKit.font_display(), HORIZONTAL_ALIGNMENT_CENTER)
	pl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	plus.add_child(pl)
	cr.add_child(plus)
	_gems_button = _row_button()
	_gems_button.name = "Gems"
	_gems_button.tooltip_text = tr("Store")
	_gems_button.custom_minimum_size.y = 22
	_gems_button.pressed.connect(func(): open_tab.emit("store"))
	wv.add_child(_gems_button)
	var gr := UIKit.hbox(0)
	_fill(gr)
	gr.alignment = BoxContainer.ALIGNMENT_CENTER
	_gems_button.add_child(gr)
	gem_amount = CoinAmount.gems(int(Save.profile.get("gems", 0)), "sm", "plain")
	gem_amount.name = "GemAmount"
	gr.add_child(gem_amount)
	# the gift: Free spin / Daily reward / Free coins (the Rewards sheet), with the count of those ready now
	rewards_button = UIKit.icon_button(HI % "gift", "glass", int(BAR_H), 38)
	rewards_button.name = "Rewards"
	rewards_button.pressed.connect(func(): open_tab.emit("rewards"))
	_top.add_child(rewards_button)
	_gift_badge = UIKit.notify_badge("0", false)          # (its gentle pulse: _show_count, off with Reduce motion)
	_gift_badge.name = "Count"
	_gift_badge.position = Vector2(BAR_H - 16.0, -6.0)
	_gift_badge.visible = false
	rewards_button.add_child(_gift_badge)
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
	_build_quick()
	_build_switch()
	quick_button = _big_play()
	quick_button.pressed.connect(func(): quick_match.emit(game))
	add_child(quick_button)
	_modes = UIKit.hbox(UIKit.SPACE.sm + 2)
	_modes.name = "Modes"
	friends_button = _tile_button(tr("Friends"), UIKit.ICON_DIR + "perk_friends.svg")
	friends_button.name = "Friends"
	friends_button.pressed.connect(_friends)
	_modes.add_child(friends_button)
	for m in [["Computer", "cpu", "cpu"], ["Pass & Play", "pass_play", "local"]]:
		var b := _tile_button(tr(m[0]), HI % m[1])
		b.name = str(m[0]).replace(" & ", "")
		var mode: String = m[2]
		b.pressed.connect(func(): _play(mode))
		_modes.add_child(b)
	add_child(_modes)
	_rule = ColorRect.new()
	_rule.color = Palette.LINE
	_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rule)
	_build_nav()


## The Continue match pill over the café (hidden when no match is kept): the resume icon, the title, the match and
## a teal Resume (the whole pill is the button).
func _build_quick() -> void:
	_quick = _flat_button(_chip_style(UIKit.R.pill), _chip_style(UIKit.R.pill, true))
	_quick.name = "Continue"
	_quick.pressed.connect(_on_quick)
	add_child(_quick)
	var r := UIKit.hbox(10)
	_fill(r)
	r.offset_left = 6; r.offset_right = -6
	_quick.add_child(r)
	_quick_icon = UIKit.icon(HI % "resume", QUICK_INNER)
	_quick_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.add_child(_quick_icon)
	var col := UIKit.vbox(-2)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_child(col)
	_quick_title = UIKit.label(tr("Continue match"), UIKit.FS.label + 1, Palette.INK, UIKit.font_body(900))
	col.add_child(_quick_title)
	_quick_sub = UIKit.label("", UIKit.FS.small, Palette.MUTED, UIKit.font_body(800))
	_quick_sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_quick_sub.clip_text = true
	col.add_child(_quick_sub)
	_quick_go = UIKit.button(tr("Resume"), "teal", "xs")
	_quick_go.mouse_filter = Control.MOUSE_FILTER_IGNORE      # the whole pill is the button
	_quick_go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_quick_go.custom_minimum_size = Vector2(92, QUICK_INNER)
	# a pill inside the pill, inset as far as the round icon on the left, so both ends read the same
	for k in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
		var st := _quick_go.get_theme_stylebox(k)
		if st is StyleBoxFlat:
			st = st.duplicate()
			(st as StyleBoxFlat).set_corner_radius_all(UIKit.R.pill)
			_quick_go.add_theme_stylebox_override(k, st)
	r.add_child(_quick_go)
	_quick.visible = false


## The game switch: two segments (family icon + name); the selected one is a raised white face, the other's name
## is the softer SUB.
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
	on.border_width_bottom = UIKit.LIP.sm      # the lip only: a blurred shadow here was sliced flat by the button clip
	on.border_color = Palette.LIP_CREAM
	var off := StyleBoxFlat.new()
	off.bg_color = Color(1, 1, 1, 0)
	for g in [["ludo", "Ludo", "ludo"], ["sl", "Snakes & Ladders", "snakes"]]:
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, UIKit.TAP)
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
		var l := UIKit.label(tr(g[1]), SWITCH_FS, Palette.INK, UIKit.font_body(900))
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		l.add_theme_constant_override("line_spacing", -3)
		r.add_child(l)
		var key: String = g[0]
		_switch_parts[key] = {row = r, icon = ic, label = l, text = tr(g[1])}
		b.button_pressed = key == game
		b.toggled.connect(func(v: bool): if v: _set_game(key))
		row.add_child(b)
		_switch_buttons[key] = b
	_tint_switch()


## The picked game's name in INK, the other one in SUB.
func _tint_switch() -> void:
	for k in _switch_parts:
		(_switch_parts[k].label as Label).add_theme_color_override("font_color", Palette.INK if k == game else Palette.SUB)


## The one big QUICK MATCH: honey, the bolt globe, the caps title and a one-line hint (the content follows the press).
func _big_play() -> Button:
	var b := UIKit.button("", "honey", "lg")
	b.name = "QuickMatch"
	var lip := float(UIKit.BTN.lg.lip)
	var r := UIKit.hbox(UIKit.SPACE.md)
	_fill(r)
	r.alignment = BoxContainer.ALIGNMENT_CENTER
	r.offset_bottom = -lip
	b.add_child(r)
	var ic := UIKit.icon(HI % "quick", PLAY_H - 30.0)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.add_child(ic)
	var col := UIKit.vbox(0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_child(col)
	var t := UIKit.label(tr("QUICK MATCH"), 28, Palette.ON_HONEY, UIKit.font_display())
	t.name = "Text"
	col.add_child(t)
	col.add_child(UIKit.label(tr("Play online now"), UIKit.FS.small + 1, Color(Palette.ON_HONEY, 0.72), UIKit.font_body(800)))
	b.button_down.connect(func(): r.offset_top = lip - 2.0; r.offset_bottom = -2.0)
	b.button_up.connect(func(): r.offset_top = 0.0; r.offset_bottom = -lip)
	b.resized.connect(func() -> void:                     # a smaller bolt on a lower button (short screens)
		ic.custom_minimum_size = Vector2.ONE * clampf(b.size.y - 30.0, 36.0, PLAY_H - 30.0))
	return b


## A compact mode: a white kit button with its icon over a short label (the content follows the press).
func _tile_button(text: String, icon_path: String) -> Button:
	var b := UIKit.button("", "white", "md")
	b.custom_minimum_size = Vector2(0, MODE_H)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lip := float(UIKit.BTN.md.lip)
	var col := UIKit.vbox(2)
	_fill(col)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.offset_bottom = -lip
	b.add_child(col)
	var ic := UIKit.icon(icon_path, 30)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(ic)
	var l := UIKit.label(text, UIKit.FS.label, Palette.INK, UIKit.font_body(900), HORIZONTAL_ALIGNMENT_CENTER)
	l.name = "Text"
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(l)
	b.button_down.connect(func(): col.offset_top = lip - 2.0; col.offset_bottom = -2.0)
	b.button_up.connect(func(): col.offset_top = 0.0; col.offset_bottom = -lip)
	return b


func _build_nav() -> void:
	_tabs = UIKit.hbox(4)
	add_child(_tabs)
	for t in [["home", "Home", HI % "home"], ["shop", "Shop", HI % "shop"], ["leaderboard", "Ranks", TROPHY],
			["inventory", "Inventory", HI % "inventory"]]:   # the profile: the player chip up top
		var on: bool = t[0] == "home"
		var st := UIKit.box(Palette.HONEY_TINT if on else Color(1, 1, 1, 0), UIKit.R.lg, UIKit.BW.line if on else 0, Palette.HONEY_TINT_EDGE)
		UIKit.pad(st, 0)
		var pr := UIKit.box(Palette.CHIP, UIKit.R.lg)
		UIKit.pad(pr, 0)
		var b := _flat_button(st, pr)
		b.name = str(t[1])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, NAV_H - 8)
		var col := UIKit.vbox(0)
		_fill(col)
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		b.add_child(col)
		var ic := UIKit.icon(t[2], 28)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(ic)
		col.add_child(UIKit.label(tr(t[1]), UIKit.FS.small, Palette.INK if on else Palette.SUB, UIKit.font_body(900), HORIZONTAL_ALIGNMENT_CENTER))
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


## Friends: Online listens to play_friends; older main.gd builds get play_game(game, "online").
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
	_tint_switch()
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


## Where the coins of reward `id` (spin | daily | free) fly from when no Rewards sheet is open: the gift. null for
## anything else.
func side_button(id: String) -> Control:
	return rewards_button if id in REWARD_IDS else null


## The control a Home toast sits above: the Continue pill when it shows, else the dock (never over the play buttons).
func toast_anchor() -> Control:
	return _quick if _quick.visible else _dock


# =====================================================================================================================
# State
# =====================================================================================================================

## Free spin / Daily reward / Free coins right now: {spin: {ready, wait}, daily: {...}, free: {...}}; wait is the
## countdown while it isn't ready ("13h 20m" to midnight; "3:53:09" for the free coins), "" when it is. The gift's
## count and the Rewards sheet both read this (the rules themselves are Rewards').
static func reward_states(p: Dictionary) -> Dictionary:
	var spin_ok := Rewards.can_spin(p)
	var daily_ok := bool(Rewards.daily_state(p).get("claimable", false))
	var left := Rewards.free_left_sec(p)
	var midnight := Fmt.until(Rewards.sec_to_midnight())
	return {
		spin = {ready = spin_ok, wait = "" if spin_ok else midnight},
		daily = {ready = daily_ok, wait = "" if daily_ok else midnight},
		free = {ready = left <= 0, wait = "" if left <= 0 else Fmt.clock(left)},
	}


## How many of Free spin / Daily reward / Free coins are ready now (the gift's red count).
static func ready_count(p: Dictionary) -> int:
	var n := 0
	for st: Dictionary in reward_states(p).values():
		if st.ready:
			n += 1
	return n


func _on_visibility() -> void:
	if not is_inside_tree():
		return
	var on := is_visible_in_tree()
	if on:
		_refresh_rewards()
		_timer.start()
	else:
		_timer.stop()
		_pulse(false)


## The gift's count (once per second while visible: a reward that becomes ready shows up by itself).
func _refresh_rewards() -> void:
	_show_count(ready_count(Save.profile))


func _show_count(n: int) -> void:
	if n != _ready_n:
		_ready_n = n
		_gift_badge.text = str(n)
		_gift_badge.visible = n > 0
	_pulse(n > 0 and is_visible_in_tree() and not Sheet.reduce_motion())


## The count's gentle pulse while something is ready (none with Reduce motion).
func _pulse(on: bool) -> void:
	var running := _badge_tw != null and _badge_tw.is_valid()
	if on == running:
		return
	if running:
		_badge_tw.kill()
		_badge_tw = null
		_gift_badge.scale = Vector2.ONE
		return
	_gift_badge.pivot_offset = _gift_badge.size / 2.0
	_badge_tw = _gift_badge.create_tween().set_loops()
	_badge_tw.tween_property(_gift_badge, "scale", Vector2(1.14, 1.14), 0.6).set_trans(Tween.TRANS_SINE)
	_badge_tw.tween_property(_gift_badge, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_SINE)
	_badge_tw.tween_interval(1.0)


## The level star on the avatar's bottom-right corner, placed from its real px (two-digit levels never drop below 28).
func _place_level() -> void:
	_level.position = Vector2(AVATAR - _level.px + 9.0, AVATAR - _level.px + 4.0)
	_level.size = Vector2(_level.px, _level.px)

func refresh() -> void:
	if not is_inside_tree():
		return
	var p: Dictionary = Save.profile
	_name.text = L10n.seat_name(str(p.get("name", "You")))
	if _avatar and _avatar.has_method("refresh"):
		_avatar.refresh()
	var li := Save.level_info(int(p.get("xp", 0)))
	_level.set_level(int(li.level))
	_place_level()
	_xp.set_value(float(li.into), float(li.need))
	if not _coins_busy():
		coin_amount.set_amount(int(p.get("coins", 0)))
	_show_gems(int(p.get("gems", 0)))
	var sel: Button = _switch_buttons.get(game)
	if sel and not sel.button_pressed:
		sel.set_pressed_no_signal(true)
	_tint_switch()
	_refresh_rewards()
	_refresh_quick()


## The gem balance in the top bar (under the coins).
func _show_gems(n: int) -> void:
	gem_amount.set_amount(n)


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


## The Continue match pill: shown while MatchStore keeps a match ("Ludo vs Computer · 35% · 12 min ago").
func _refresh_quick() -> void:
	if not MatchStore.has_saved():
		_show_continue("")
		return
	var pk := MatchStore.peek()
	var sub := str(pk.get("summary", ""))
	if sub == "":
		sub = tr("Snakes & Ladders") if str(pk.get("game", "ludo")) == "sl" else tr("Ludo")
	else:
		sub = MatchStore.localize_summary(sub)       # (the file keeps the English line)
	var ago := _ago(int(pk.get("saved_at", 0)))
	_show_continue(sub + (" · " + ago if ago != "" and sub.length() + ago.length() <= 30 else ""))


## Show the Continue match pill with `sub` under its title ("" hides it); the table is re-framed when it comes or goes.
func _show_continue(sub: String) -> void:
	_quick_sub.text = sub
	var kind := "continue" if sub != "" else ""
	if kind == _quick_kind:
		return
	_quick_kind = kind
	_quick.visible = kind != ""
	_layout()
	var main := get_parent()
	while main and not main.has_method("_fit_home"):
		main = main.get_parent()
	if main:
		main.call("_fit_home")              # the free band changed: re-frame the table


static func _ago(unix: int) -> String:
	if unix <= 0:
		return ""
	var s := int(Time.get_unix_time_from_system()) - unix
	if s < 60:
		return L10n.t("just now")
	if s < 3600:
		return L10n.t("%d min ago") % (s / 60)
	if s < 86400:
		return L10n.t("%dh ago") % (s / 3600)
	var d := s / 86400
	return L10n.t("yesterday") if d == 1 else L10n.t("%d days ago") % d


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
	_layout_top(x, top + UIKit.SPACE.sm, cw)
	var y_bar := top + UIKit.SPACE.sm + BAR_H
	# the dock, bottom up: nav, rule, the three modes, QUICK MATCH, the switch
	var short := h < SHORT_H
	var nav_y := bottom - NAV_H + 4
	_tabs.position = Vector2(x - 6, nav_y)
	_tabs.size = Vector2(cw + 12, NAV_H - 4)
	_rule.position = Vector2(x, nav_y - UIKit.SPACE.sm)
	_rule.size = Vector2(cw, 2)
	var mh := MODE_H - 4.0 if short else MODE_H
	_modes.position = Vector2(x, nav_y - UIKit.SPACE.lg - mh)
	_modes.size = Vector2(cw, mh)
	var ph := PLAY_H - 8.0 if short else PLAY_H
	quick_button.position = Vector2(x, _modes.position.y - UIKit.SPACE.md - ph)
	quick_button.size = Vector2(cw, ph)
	_switch.position = Vector2(x, quick_button.position.y - UIKit.SPACE.md - SWITCH_H)
	_switch.size = Vector2(cw, SWITCH_H)
	_fit_switch(cw)
	var dock_y := _switch.position.y - UIKit.SPACE.lg - 2
	_dock.position = Vector2(0, dock_y)
	_dock.size = Vector2(w, h - dock_y + 4)
	var band_bottom := dock_y - UIKit.SPACE.sm
	if _quick.visible:                            # Continue match: a slim pill just above the dock
		_quick.position = Vector2(x, dock_y - UIKit.SPACE.md - PILL_H)
		_quick.size = Vector2(cw, PILL_H)
		band_bottom = _quick.position.y - UIKit.SPACE.xs
	# the logo: smaller than the table under it (the café is the hero), smaller still when the table would get less
	# than TABLE_MIN px (a tall safe area, the Continue pill)
	var ly := roundf(y_bar + UIKit.SPACE.md)
	var lw := minf(208.0, cw)
	var lh := lw * BrandLogo.VIEW.y / BrandLogo.VIEW.x
	# short phones (320 x 568) may shrink it to 64 px, so the table keeps its band and the logo never meets the pill
	var max_h := clampf(minf(0.185 * h, band_bottom - ly - TABLE_MIN), 64.0, 180.0)
	if lh > max_h:
		lh = max_h
		lw = lh * BrandLogo.VIEW.x / BrandLogo.VIEW.y
	logo.size = Vector2(roundf(lw), roundf(lh))
	logo.position = Vector2(roundf((w - lw) / 2.0), ly)
	_band = Vector2(logo.position.y + logo.size.y, band_bottom)


## The top bar; when it is tight (narrower than a phone's 390 px UI) the player chip keeps only the avatar.
func _layout_top(x: float, y: float, cw: float) -> void:
	var others := 0.0
	for c in _top.get_children():
		if c != _chip:
			others += (c as Control).get_combined_minimum_size().x + UIKit.SPACE.sm
	_chip_text.visible = cw - others >= 120.0      # room for the name and the XP bar
	_top.position = Vector2(x, y)
	_top.size = Vector2(cw, BAR_H)


## The switch labels at the size that fits their half (item: the long "Snakes & Ladders" never overflows): 15 px with
## a 30 px icon, then 14 px, then a 26 px icon, then the name on two lines. Both halves use the same size.
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
		[UIKit.FS.label, 26.0, UIKit.SPACE.xs + 2, false], [UIKit.FS.label, 28.0, UIKit.SPACE.sm, true]]
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


## The band between the logo and the dock (or the Continue pill), in UI pixels (for the home camera framing).
func free_band() -> Vector2:
	return _band
