class_name DailySheet
extends Sheet
## Daily reward (index.html #dailySheet / renderDaily / claimDaily): the 7-day login calendar in the .pm sheet look
## (Sheet "pm" + a RibbonTitle "Daily reward"; the 48 px X is the only dismiss
## control). A pane holds a 3 x 2 grid of day tiles plus a wide Day 7: claimed (dimmed, teal check badge), today
## (honey ring with a breathing glow, teal header; tapping it claims) or locked (muted). The art grows with the
## reward: one coin, a pair, a pile; dice skins in their Catalog colours; characters as their portrait.
## One honey "Claim" button; once claimed it turns into a quiet "Come back tomorrow · 13h 20m" (live countdown).
## A claim pops the tile, stamps the check, flies the coins to the home coin counter (CoinFly; when there is no
## counter on screen, a coin burst at the tile), shows a "good" Toast with what was won and plays Haptics.success().
## The rules live in Rewards.
##
## After a successful claim the sheet closes itself AUTO_CLOSE_SEC later (auto_close; one tap: claim and done). The
## coins keep flying to the home counter over the closing sheet (the CoinFly lives on the sheet's layer).
##
##   var s := DailySheet.new(); s.claimed.connect(func(r): ...); s.open(layer)

signal claimed(result: Dictionary)

const AUTO_CLOSE_SEC := 0.8

## Where reward coins fly (previews / tests). null: the home screen's coin counter (Main.home), when on screen.
static var coin_target_override: Control = null

var profile: Dictionary
var _day_override := ""
var _tiles: Array[Tile] = []
var _btn: Button
var _note: Label
var _busy := false
var _shown_day := ""
var _timer: Timer
var auto_close := true                ## close AUTO_CLOSE_SEC after a successful claim


## p: the profile to read and change (default: Save.profile). today: a fixed day key (previews), "" = the real day.
func _init(p: Dictionary = {}, today := "", width := float(UIKit.W.form)) -> void:
	super("", width, true, LOOK_PM)
	profile = p if not p.is_empty() else Save.profile
	_day_override = today
	ribbon = RibbonTitle.new("Daily reward")   # the Sheet places it on the card's top edge (no ⓘ: the grid explains itself)
	ribbon.name = "Ribbon"
	header.add_child(ribbon)
	title_label = ribbon.label
	_build()
	_render()


func _ready() -> void:
	_timer = Timer.new()
	_timer.wait_time = 1.0
	_timer.timeout.connect(_tick)
	add_child(_timer)
	_timer.start()


func _day() -> String:
	return _day_override if _day_override != "" else Rewards.day_key()


# ---------- build ----------

func _build() -> void:
	var list := add_scroll_body(UIKit.SPACE.sm)   # fit(): scrolls only on very short screens
	var pane := UIKit.panel("pane")
	list.add_child(pane)
	var col := UIKit.vbox(UIKit.SPACE.sm)
	pane.add_child(col)
	var grid := UIKit.grid(3, UIKit.SPACE.sm)
	col.add_child(grid)
	for k in 7:
		var t := Tile.new(k)
		t.tapped.connect(_claim)
		_tiles.append(t)
		if k < 6:
			grid.add_child(t)
		else:
			col.add_child(t)
	_note = UIKit.paragraph("", UIKit.FS.body, Palette.SUB, HORIZONTAL_ALIGNMENT_CENTER)
	_note.add_theme_font_override("font", UIKit.font_body(800))
	_note.visible = false
	col.add_child(_note)
	_btn = UIKit.button("Claim", "honey", "lg")
	_btn.name = "Claim"
	_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn.clip_text = true
	_btn.pressed.connect(_claim)
	_btn.resized.connect(_fit_btn)
	body.add_child(_btn)


# ---------- state ----------

## Redraws the tiles, the button and the note from Rewards.daily_state (index.html renderDaily).
func _render() -> Dictionary:
	var st := Rewards.daily_state(profile, _day())
	_shown_day = st.key
	var next := tomorrow_index(st)
	for k in 7:
		_tiles[k].tomorrow = k == next
		_tiles[k].set_info(st.rewards[k])
	var can := bool(st.claimable)
	if can:
		if _btn.get_meta("kit_kind", "") != "honey":
			UIKit.style_button(_btn, "honey", "lg")
		_btn.disabled = _busy
		_btn.text = "Claim"
	else:
		if _btn.get_meta("kit_kind", "") != "off":
			UIKit.style_button(_btn, "off", "lg")
			_btn.add_theme_color_override("font_disabled_color", Palette.SUB)
		_btn.disabled = true
		_btn.text = "Come back tomorrow · %s" % Fmt.until(Rewards.sec_to_midnight())
	_fit_btn()
	# the note only when it tells something the grid doesn't: a broken run
	_note.text = "You missed a day, so you’re back to Day 1." if can and bool(st.missed) else ""
	_note.visible = _note.text != ""
	return st

## The calendar tile that unlocks tomorrow (day + 1), or -1 (the cycle ends today). st: Rewards.daily_state().
static func tomorrow_index(st: Dictionary) -> int:
	var k := int(st.today) + 1 if bool(st.get("claimable", false)) else int(st.get("claimed", 0))
	var list: Array = st.get("rewards", [])
	return k if k >= 0 and k < list.size() and str((list[k] as Dictionary).get("status", "")) == "locked" else -1

## A tile's status line: "CLAIMED", "TODAY", "TOMORROW", or none (later days: the header already says "Day 5").
static func status_text(status: String, is_tomorrow: bool) -> String:
	match status:
		"claimed": return "CLAIMED"
		"today": return "TODAY"
	return "TOMORROW" if is_tomorrow else ""

## The button text at the largest size that fits (lg 24, the countdown 20 down to 14).
func _fit_btn() -> void:
	var room := _btn.size.x
	if room <= 0.0:
		room = card.custom_minimum_size.x - 2.0 * (UIKit.PAD.pane + 4)
	room -= 2.0 * float(UIKit.BTN.lg.pad)
	var f := UIKit.font_display()
	var fs := int(UIKit.BTN.lg.fs) if not _btn.disabled else UIKit.FS.h2
	while fs > UIKit.FS.label and f.get_string_size(_btn.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > room:
		fs -= 1
	if fs != _btn.get_theme_font_size("font_size"):
		_btn.add_theme_font_size_override("font_size", fs)

## Once a second: a new day re-opens the calendar while it's showing; the countdown refreshes.
func _tick() -> void:
	if _busy:
		return
	_render()


# ---------- claiming ----------

## True when the reward comes from the server (the game: an Account and the live profile; previews and tests keep
## the local rules).
func _server() -> bool:
	return Account.wallet_active() and is_same(profile, Save.profile)

func _claim() -> void:
	if _busy or _closing:
		return
	var st := Rewards.daily_state(profile, _day())
	if not st.claimable:
		Haptics.error()
		Sound.sfx("error")
		_render()
		return
	var g: Dictionary = st.rewards[st.today].grant   # what this claim gives (coins, dice, char)
	_busy = true
	_btn.disabled = true
	if int(g.get("coins", 0)) > 0:
		DailySheet.hold_home_coins(self)   # the grant fires Save.changed: the counter waits for the fly
	var r: Dictionary
	if _server():
		r = await Account.instance().daily()
		if not is_instance_valid(self) or _closing:
			return
		if not r.get("ok", false):
			_busy = false
			Sound.sfx("error")
			Haptics.error()
			Toast.show(self, Account.error_text(str(r.get("error", "")), "claim"), card, 2.4, "bad")
			_render()
			return
	else:
		r = Rewards.claim_daily(profile, _day())
		if not r.ok:
			_busy = false
			Sound.sfx("error")
			_render()
			return
		r.char = str(g.get("char", ""))
	_render()
	var tile := _tiles[int(r.day) - 1]
	tile.pop()
	Haptics.success()
	if str(r.dice) != "" or str(r.char) != "":
		Sound.sfx("buy")
	if int(r.day) == 7:
		Celebrate.run(self, "", 0.6)
	Toast.show(self, reward_text(r), card, 2.2, "good")
	DailySheet.reward_coins(self, tile.get_global_rect().get_center(), int(r.coins),
			str(r.dice) != "" or str(r.char) != "", int(profile.get("coins", -1)))
	var tw := create_tween()
	tw.tween_interval(0.9)
	tw.tween_callback(func():
		_busy = false
		_render())
	claimed.emit(r)
	if auto_close:
		var tc := create_tween()
		tc.tween_interval(AUTO_CLOSE_SEC)
		tc.tween_callback(close)

## "+200 coins", "Crema dice unlocked", "+800 coins · Rafi unlocked" (one toast line on a phone).
static func reward_text(r: Dictionary) -> String:
	var bits := []
	if int(r.get("coins", 0)) > 0:
		bits.append("%s coins" % Fmt.gain(int(r.coins)))
	if str(r.get("dice", "")) != "":
		bits.append("%s dice unlocked" % Rewards.DICE_NAMES.get(r.dice, r.dice))
	if str(r.get("char", "")) != "":
		bits.append("%s unlocked" % Rewards.char_name(str(r.char)))
	return " · ".join(bits)


# ---------- reward coins (shared with SpinSheet) ----------

## Coins from `from_global` to the home coin counter (CoinFly), or - with no counter on screen - a coin burst there.
## host: the sheet (the coins draw over it). item: an item came with it ("Unlocked!" on the burst).
## total: the balance after the reward (the counter counts up to it; -1: its amount + amount).
static func reward_coins(host: Control, from_global: Vector2, amount: int, item := false, total := -1) -> void:
	var to := coin_target(host)
	if to and amount > 0:
		# the fly lives on the sheet's layer: it keeps going (and counts the balance up) when the sheet closes
		var fly_host: Control = host.get_parent() if host.get_parent() is Control else host
		var tw := fly_host.create_tween()
		tw.tween_interval(0.12)   # the tile pop first
		tw.tween_callback(func():
			if is_instance_valid(fly_host) and is_instance_valid(to):
				CoinFly.run(fly_host, from_global, to, amount, Callable(), total))
		return
	var burst := CoinBurst.new(from_global - host.get_global_rect().position, amount, item)
	host.add_child(burst)
	if amount > 0:
		var tw := host.create_tween()
		tw.tween_interval(0.42)
		tw.tween_callback(func(): Sound.sfx("coin", amount))

## Tell the home screen a CoinFly is coming (HomeScreen.hold_coins): its counter keeps the old balance until the
## coins land and count it up, instead of jumping on the Save.changed of the grant. No-op without a home.
static func hold_home_coins(from: Node, sec := 2.5) -> void:
	if is_instance_valid(coin_target_override) or from == null or not from.is_inside_tree():
		return
	var app := _app(from)
	if app == null:
		return
	var home: Variant = app.get("home")
	if home is Control and is_instance_valid(home) and (home as Control).is_visible_in_tree() and (home as Object).has_method("hold_coins"):
		(home as Object).call("hold_coins", sec)

## The visible home coin counter (a CoinAmount on Main.home), or null (no home yet, home hidden, no CoinAmount).
static func coin_target(from: Node) -> Control:
	if is_instance_valid(coin_target_override):
		return coin_target_override
	if from == null or not from.is_inside_tree():
		return null
	var app := _app(from)
	if app == null:
		return null
	var home: Variant = app.get("home")
	if not (home is Control) or not is_instance_valid(home) or not (home as Control).is_visible_in_tree():
		return null
	for key in ["coin_amount", "coins_amount", "coin_chip", "balance"]:
		if key in home:
			var v: Variant = (home as Control).get(key)
			if v is CoinAmount and (v as Control).is_visible_in_tree():
				return v
	return _find_coin_amount(home)

## The app (main.gd, the node with `home`): /root/Main in the game, else the current scene or one of its children
## (dev tours host Main under their own node).
static func _app(from: Node) -> Node:
	var tree := from.get_tree()
	var app := tree.root.get_node_or_null("Main")
	if app and "home" in app:
		return app
	var cs := tree.current_scene
	if cs == null:
		return null
	if "home" in cs:
		return cs
	for c in cs.get_children():
		if "home" in c:
			return c
	return null

static func _find_coin_amount(n: Node) -> Control:
	for c in n.get_children():
		if c is CoinAmount and (c as Control).is_visible_in_tree():
			return c
		var deep := _find_coin_amount(c)
		if deep:
			return deep
	return null


# ---------- drawing helpers (shared with SpinSheet) ----------

## The game's coin (assets/ui/coin.svg) drawn as vectors, crisp at any size: `d` is the icon box size.
## sat < 1 mutes the colours (locked tiles).
static func draw_coin(ci: CanvasItem, c: Vector2, d: float, alpha := 1.0, sat := 1.0) -> void:
	var u := d / 32.0
	var o := c - Vector2(16, 16) * u
	var dark := _mute(Palette.GOLD_DEEP, sat, alpha)
	var face := _mute(Palette.GOLD_HI, sat, alpha)
	var mark := _mute(Palette.GOLD, sat, alpha)
	ci.draw_circle(o + Vector2(16, 16.5) * u, 15 * u, dark, true, -1.0, true)
	ci.draw_circle(o + Vector2(16, 15) * u, 14 * u, face, true, -1.0, true)
	ci.draw_arc(o + Vector2(16, 15) * u, 10 * u, 0, TAU, 48, mark, 2 * u, true)
	var star := PackedVector2Array()
	for v in [Vector2(16, 8.6), Vector2(17.9, 12.5), Vector2(22.1, 13.1), Vector2(19.1, 16.1), Vector2(19.8, 20.3),
			Vector2(16, 18.3), Vector2(12.2, 20.3), Vector2(12.9, 16.1), Vector2(9.9, 13.1), Vector2(14.1, 12.5)]:
		star.append(o + v * u)
	ci.draw_colored_polygon(star, mark)
	star.append(star[0])
	ci.draw_polyline(star, mark, 0.5 * u, true)   # soft edges for the star

## n coins as one picture centred on c: 1 coin, a pair, or a pile of three (the reward looks as big as it is).
static func draw_coins(ci: CanvasItem, c: Vector2, d: float, n: int, alpha := 1.0, sat := 1.0) -> void:
	match n:
		1:
			draw_coin(ci, c, d, alpha, sat)
		2:
			var s := d * 0.86
			draw_coin(ci, c + Vector2(-s * 0.26, s * 0.12), s, alpha, sat)
			draw_coin(ci, c + Vector2(s * 0.26, -s * 0.06), s, alpha, sat)
		_:
			var s := d * 0.8
			draw_coin(ci, c + Vector2(-s * 0.36, s * 0.2), s, alpha, sat)
			draw_coin(ci, c + Vector2(s * 0.36, s * 0.2), s, alpha, sat)
			draw_coin(ci, c + Vector2(0, -s * 0.16), s * 1.04, alpha, sat)

## How many coins a tile shows for an amount (index.html shows one for all; the pile grows with the reward).
static func coin_count(coins: int) -> int:
	return 1 if coins <= 150 else (2 if coins <= 300 else 3)

static func _mute(col: Color, sat: float, alpha: float) -> Color:
	var g := col.get_luminance()
	var m := Color(g, g, g).lerp(col, sat)
	m.a = col.a * alpha
	return m

## A small dice face showing five (index.html miniDie) in a Catalog dice skin's colours.
static func draw_die(ci: CanvasItem, r: Rect2, skin: String, alpha := 1.0, sat := 1.0) -> void:
	var look := Catalog.dice(skin)
	if look.is_empty():
		look = Catalog.dice(Catalog.FREE_DICE)
	var rad := int(r.size.x * 0.22)
	var edge := UIKit.box(_mute(look.edge, sat, alpha), rad)
	ci.draw_style_box(edge, r)
	var top := UIKit.box(_mute(look.bg, sat, alpha), rad)
	ci.draw_style_box(top, Rect2(r.position, r.size - Vector2(0, r.size.y * 0.095)))
	var pad := r.size.x * 0.12
	var cell := (r.size.x - pad * 2) / 3.0
	var pr := r.size.x * 0.085
	var pip := _mute(look.pip, sat, alpha)
	for g in [Vector2(0, 0), Vector2(2, 0), Vector2(1, 1), Vector2(0, 2), Vector2(2, 2)]:
		ci.draw_circle(r.position + Vector2(pad, pad * 0.9) + (g + Vector2(0.5, 0.5)) * cell, pr, pip, true, -1.0, true)

## Text with a 1-2 px drop shadow under it (the CSS text-shadow on headers and buttons).
static func draw_text_shadowed(ci: CanvasItem, f: Font, pos: Vector2, text: String, width: float, fs: int, col: Color, shadow: Color, dy := 1.0) -> void:
	ci.draw_string(f, pos + Vector2(0, dy), text, HORIZONTAL_ALIGNMENT_CENTER, width, fs, shadow)
	ci.draw_string(f, pos, text, HORIZONTAL_ALIGNMENT_CENTER, width, fs, col)


# ---------- pieces ----------

## One day of the calendar (.dtile): header band, art, value and status; the wide one is Day 7.
class Tile extends Control:
	signal tapped
	const HEAD := 26.0
	const RADIUS := 14
	var k := 0
	var wide := false
	var info := {}
	var status := "locked"
	var tomorrow := false                # the day after today: "TOMORROW" (later days show no status)
	var _glow_t := 0.0
	var _pop := 1.0
	var _stamp := 1.0
	var _ring: StyleBoxFlat            # today's ring (changes every frame)
	static var _sb := {}               # cached faces / lips / headers per state
	static var _caps: FontVariation    # Nunito 900, letter-spaced (.ds); UIKit.font_caps() renders too light (nested variation)

	static func status_font() -> Font:
		if _caps == null:
			_caps = FontVariation.new()
			_caps.base_font = load("res://assets/fonts/Nunito.woff2")
			_caps.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 900}
			_caps.spacing_glyph = 1
		return _caps

	func _init(index: int) -> void:
		k = index
		wide = index == 6
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		custom_minimum_size = Vector2(0, 100 if wide else 132)
		_ring = UIKit.box(Palette.HONEY, RADIUS + 4, 0, Color.TRANSPARENT, 8, Color(Palette.GOLD, 0.35))

	func set_info(i: Dictionary) -> void:
		var was := status
		info = i
		status = str(i.status)
		var today := status == "today"
		set_process(today and not Sheet.reduce_motion())
		mouse_filter = Control.MOUSE_FILTER_STOP if today else Control.MOUSE_FILTER_IGNORE
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if today else Control.CURSOR_ARROW
		if was == "today" and status == "claimed":
			_stamp = 0.0
		queue_redraw()

	func _gui_input(e: InputEvent) -> void:
		if status == "today" and Sheet._is_tap(e):
			accept_event()
			tapped.emit()

	func _process(delta: float) -> void:
		_glow_t += delta
		queue_redraw()

	## The claim: the tile pops and the check stamps down onto it.
	func pop() -> void:
		_stamp = 0.0
		var big := 1.04 if wide else 1.1   # the wide tile stays inside the pane
		var tw := create_tween()
		tw.tween_method(_set_pop, 1.0, big, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_method(_set_pop, big, 1.0, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		var ts := create_tween()
		ts.tween_interval(0.1)
		ts.tween_method(_set_stamp, 0.0, 1.0, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	func _set_pop(v: float) -> void:
		_pop = v
		queue_redraw()

	func _set_stamp(v: float) -> void:
		_stamp = v
		queue_redraw()

	## [face, lip, head] for a state (cached).
	static func _styles(st: String) -> Array:
		if _sb.has(st):
			return _sb[st]
		var face: Color
		var lip: Color
		var head: Color
		match st:
			"claimed":
				face = Palette.CHIP_DIM; lip = Palette.LIP_CREAM; head = Palette.TAN_DEEP
			"today":
				face = Color.WHITE; lip = Palette.HONEY_LIP; head = Palette.TEAL
			_:
				face = Palette.CARD; lip = Palette.TAN; head = Palette.TAN
		var f := UIKit.box(face, RADIUS)
		var l := UIKit.box(lip, RADIUS, 0, Color.TRANSPARENT, 0 if st == "claimed" else 5, Palette.shadow(0.12))
		var h := UIKit.box(head, RADIUS)
		h.corner_radius_bottom_left = 0; h.corner_radius_bottom_right = 0
		_sb[st] = [f, l, h]
		return _sb[st]

	func _draw() -> void:
		if info.is_empty():
			return
		var w := size.x
		var h := size.y
		draw_set_transform(size / 2.0 * (1.0 - _pop), 0.0, Vector2(_pop, _pop))
		var claimed := status == "claimed"
		var today := status == "today"
		var sb := _styles(status)
		if today:   # the honey ring, breathing (still with Reduce motion)
			var g := 0.0 if not is_processing() else 0.5 - 0.5 * cos(_glow_t * TAU / 1.6)
			var sp := lerpf(3.0, 4.5, g)
			_ring.bg_color = Palette.HONEY.lerp(Palette.GOLD_HI, g)
			_ring.set_corner_radius_all(int(RADIUS + sp))
			_ring.shadow_size = int(lerpf(6.0, 12.0, g))
			_ring.shadow_color = Color(Palette.GOLD, lerpf(0.28, 0.5, g))
			_ring.shadow_offset = Vector2(0, 3)
			var rr := Rect2(Vector2(-sp, -sp), Vector2(w + sp * 2, h + sp * 2))
			draw_style_box(_ring, rr)
		draw_style_box(sb[1], Rect2(0, 3, w, h))
		draw_style_box(sb[0], Rect2(0, 0, w, h))
		draw_style_box(sb[2], Rect2(0, 0, w, HEAD))
		var fd := UIKit.font_display()
		DailySheet.draw_text_shadowed(self, fd, Vector2(0, 19), "Day %d" % (k + 1), w, 16, Color.WHITE, Color(Palette.INK, 0.3))
		var a := 0.5 if claimed else 1.0
		var sat := 0.7 if status == "locked" else 1.0
		var gr: Dictionary = info.grant
		var st_text := DailySheet.status_text(status, tomorrow)
		var st_col := Palette.TEAL_INK if today else (Palette.SUB if tomorrow else Color(Palette.MUTED, 0.8))
		if wide:
			_draw_wide(w, gr, st_text, st_col, a, sat)
		else:
			var icon_c := Vector2(w / 2.0, HEAD + 6 + 23)
			var label := ""
			if str(gr.dice) != "":
				DailySheet.draw_die(self, Rect2(icon_c - Vector2(21, 21), Vector2(42, 42)), gr.dice, a, sat)
				label = "%s dice" % Rewards.DICE_NAMES.get(gr.dice, gr.dice)
			elif str(gr.get("char", "")) != "":
				_draw_portrait(icon_c, 23, str(gr.char), a)
				label = Rewards.char_name(str(gr.char))
			else:
				DailySheet.draw_coins(self, icon_c, 42, DailySheet.coin_count(int(gr.coins)), a, sat)
				label = Fmt.coins(int(gr.coins))
			var fs := 18
			while fs > 12 and fd.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > w - 8:
				fs -= 1
			var vy := HEAD + 6 + 46 + 8 + fd.get_ascent(18)
			draw_string(fd, Vector2(0, vy), label, HORIZONTAL_ALIGNMENT_CENTER, w, fs, Color(Palette.INK, a))
			var sfs: int = UIKit.FS.small              # "TOMORROW" shrinks on a narrow tile instead of being cut
			while sfs > 10 and status_font().get_string_size(st_text, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs).x > w - 6.0:
				sfs -= 1
			draw_string(status_font(), Vector2(0, vy + 19), st_text, HORIZONTAL_ALIGNMENT_CENTER, w, sfs, st_col)
			if claimed:
				_draw_check(icon_c)
		draw_set_transform(Vector2.ZERO)

	## Day 7: the item (or a pile of coins) beside the value and status, centred as a group.
	func _draw_wide(w: float, g: Dictionary, st_text: String, st_col: Color, a: float, sat: float) -> void:
		var fd := UIKit.font_display()
		var fc := status_font()
		var label := str(info.label)
		var fs := 20
		var iw := 84.0
		var room := w - iw - 14 - 24
		while fs > 14 and fd.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > room:
			fs -= 1
		var tw := maxf(minf(room, fd.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x), fc.get_string_size(st_text, HORIZONTAL_ALIGNMENT_LEFT, -1, UIKit.FS.small).x)
		var x0 := (w - (iw + 14 + tw)) / 2.0
		var cy := HEAD + 3 + (size.y - HEAD - 3) / 2.0
		var art_c := Vector2(x0 + iw / 2.0, cy)
		if str(g.dice) != "":
			DailySheet.draw_die(self, Rect2(Vector2(x0, cy - 21), Vector2(42, 42)), g.dice, a, sat)
			DailySheet.draw_coin(self, Vector2(x0 + 64, cy + 4), 38, a, sat)
		elif str(g.get("char", "")) != "":
			_draw_portrait(Vector2(x0 + 26, cy), 26, str(g.char), a)
			DailySheet.draw_coin(self, Vector2(x0 + 68, cy + 8), 34, a, sat)
		else:
			DailySheet.draw_coins(self, art_c, 50, 3, a, sat)
		var tx := x0 + iw + 14
		var ly := cy + 2.0 if st_text != "" else cy + 2.0 + fd.get_ascent(fs) * 0.4   # no status line: centred alone
		draw_string(fd, Vector2(tx, ly), label, HORIZONTAL_ALIGNMENT_LEFT, room, fs, Color(Palette.INK, a))
		draw_string(fc, Vector2(tx, cy + 22), st_text, HORIZONTAL_ALIGNMENT_LEFT, -1, UIKit.FS.small, st_col)
		if status == "claimed":
			_draw_check(art_c)

	## A character portrait, cut to a circle, in a white ring.
	func _draw_portrait(c: Vector2, r: float, id: String, a: float) -> void:
		draw_circle(c + Vector2(0, 2), r + 3, Color(Palette.SHADOW, 0.2 * a), true, -1.0, true)
		draw_circle(c, r + 3, Color(Color.WHITE, a), true, -1.0, true)
		var tex := Collection.avatar_texture(id, 128)
		var pts := PackedVector2Array()
		var uvs := PackedVector2Array()
		for i in 48:
			var v := Vector2.from_angle(TAU * i / 48.0)
			pts.append(c + v * r)
			uvs.append(Vector2(0.5, 0.5) + v * 0.42)   # a little zoom: the tile's rounded corners stay outside
		draw_colored_polygon(pts, Color(1, 1, 1, a), uvs, tex)

	## The teal check badge (.chk), stamped in by pop().
	func _draw_check(c: Vector2) -> void:
		var s := lerpf(2.2, 1.0, _stamp)
		var al := clampf(_stamp * 1.4, 0.0, 1.0)
		draw_circle(c + Vector2(0, 2) * s, 17 * s, Color(Palette.TEAL_OUTLINE, 0.3 * al), true, -1.0, true)
		draw_circle(c, 17 * s, Color(Color.WHITE, al), true, -1.0, true)
		draw_circle(c, 14 * s, Color(Palette.TEAL, al), true, -1.0, true)
		var u := 18.0 / 24.0 * s
		var o := c - Vector2(12, 12) * u
		var pts := [o + Vector2(5, 12.5) * u, o + Vector2(9.5, 17) * u, o + Vector2(19, 7.5) * u]
		draw_polyline(PackedVector2Array(pts), Color(1, 1, 1, al), 3.6 * u, true)
		for p: Vector2 in pts:
			draw_circle(p, 1.8 * u, Color(1, 1, 1, al), true, -1.0, true)


## Coins bursting out of a point (and the "+amount" rising), then gone (~1.1 s). The fallback when there is no coin
## counter to fly to.
class CoinBurst extends Control:
	var origin := Vector2.ZERO
	var amount := 0
	var item := false
	var t := 0.0
	var _coins := []   # [start offset, velocity, size, spin delay]

	func _init(at: Vector2, coins: int, got_item: bool) -> void:
		origin = at
		amount = coins
		item = got_item
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var n := 0 if coins <= 0 else clampi(6 + coins / 150, 7, 14)
		if Sheet.reduce_motion():
			n = mini(n, 4)
		for i in n:
			var ang := -PI / 2.0 + randf_range(-1.15, 1.15)
			var sp := randf_range(240.0, 430.0)
			_coins.append([Vector2(randf_range(-10, 10), randf_range(-8, 8)), Vector2(cos(ang), sin(ang)) * sp, randf_range(18.0, 26.0), randf_range(0.0, 0.08)])

	func _process(delta: float) -> void:
		t += delta
		if t > 1.15:
			queue_free()
		queue_redraw()

	func _draw() -> void:
		for c in _coins:
			var tt := maxf(0.0, t - float(c[3]))
			if tt <= 0.0:
				continue
			var p: Vector2 = origin + c[0] + c[1] * tt + Vector2(0, 900.0) * tt * tt * 0.5
			var fade := clampf(1.0 - (tt - 0.55) / 0.4, 0.0, 1.0)
			var squash := absf(cos(tt * 9.0 + float(c[2])))   # the coin turning over as it flies
			draw_set_transform(p, 0.0, Vector2(maxf(0.25, squash), 1.0))
			DailySheet.draw_coin(self, Vector2.ZERO, c[2], fade)
		draw_set_transform(Vector2.ZERO)
		var text := Fmt.gain(amount) if amount > 0 else ("Unlocked!" if item else "")
		if text == "":
			return
		var k := clampf(t / 0.9, 0.0, 1.0)
		var rise := 1.0 - pow(1.0 - k, 3.0)
		var al := clampf(t / 0.12, 0.0, 1.0) * clampf((1.15 - t) / 0.3, 0.0, 1.0)
		var f := UIKit.font_display()
		var fs := 30
		var pos := origin + Vector2(-150, -30 - 60 * rise)
		var sc := 1.0 + 0.25 * maxf(0.0, 1.0 - t / 0.18)
		draw_set_transform(pos + Vector2(150, 0) * (1.0 - sc), 0.0, Vector2(sc, sc))
		draw_string_outline(f, Vector2.ZERO, text, HORIZONTAL_ALIGNMENT_CENTER, 300, fs, 8, Color(Palette.GOLD_DEEP, al * 0.85))
		draw_string(f, Vector2.ZERO, text, HORIZONTAL_ALIGNMENT_CENTER, 300, fs, Color(Palette.GOLD_HI, al))
		draw_set_transform(Vector2.ZERO)
