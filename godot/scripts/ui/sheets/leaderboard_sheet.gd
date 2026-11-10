class_name LeaderboardSheet
extends Sheet
## Leaderboard (server/ONLINE_V2.md section 4): the top 50 of GET /v1/leaderboard, as a screen of the game look (the
## Ranks mock-up), opened from Home's bottom bar (main._open_page: the bar stays below it) or over the Profile.
##   LEADERBOARD in gold display type, and "New week in 2d 6h" while the weekly board shows (the server's week starts
##   Monday 00:00 Bangladesh time). This week / All time in the Shop's filter style. Two boards: XP and Online wins,
##   picked at the podium's top left.
##   The podium: the first three on silver / gold / bronze blocks (heights 2 < 1 > 3), each in their own frame with
##   their medal under it, #1 crowned; then wood rows from #4 (rank, avatar, name, level pill, value).
##   Your bar pinned at the bottom (teal): "#12", your avatar, "You", how far the next player up is ("40 XP to pass
##   #11"), your value; "Play 2 more matches to appear" while you are below min_matches.
## Pulling the list down at its top reloads it. States: loading, empty, offline ("Connect to the internet..." with Try
## again) and a server error; the podium stays, empty, behind them. Answers are kept for 30 s per board / period, so
## switching is instant (and refreshes in the background once they are older).
##
##   LeaderboardSheet.new().open(app.sheet_layer)          # main: _open_page(LeaderboardSheet.new(), "leaderboard")
## Long-press another player's row or podium place (its `uid`) to add them to your friends (Social.ask_friend).
## Tests: set fetch_fn (board, period) -> {ok, top, me, min_matches | error} (a coroutine) and auto_load false.

const ROW_H := 58.0
const ME_NOTE_W := 40.0                 # the pinned bar's note: wraps inside at least this width
const AVA_PX := 52.0                    ## a row's avatar in its frame (the tile 42 px, as the mock)
const CACHE_SEC := 30.0
const PULL_PX := 90.0
const PODIUM_H := 290.0                 ## the mock's podium: the three places stand on its bottom edge
const PODIUM_W := 370.0                 ## ... and span this much (centred; wider than the rows by 4 px a side)
const WEEK_OFFSET_SEC := 6 * 3600       ## the server's day / week offset (econ DAY_OFFSET_MIN 360: Bangladesh)

const GOLD := Color("#ffd45e")
const CREAM := Color("#fff1b8")
const TAN := Color("#e7c7a6")
const OUTLINE := Color("#3b1a0c")
const WOOD_TOP := Color("#5a2c16")
const WOOD_BOTTOM := Color("#3b1a0c")
const WOOD_EDGE := Color("#8a4b26")
const YOU_EDGE := Color("#5fe0c8")
## The podium blocks, by place: [top, bottom, lip, number].
const BLOCK := {
	1: [Color("#ffe27a"), Color("#f2a20c"), Color("#b8600a"), Color("#7a3a08")],
	2: [Color("#dfe5ee"), Color("#9aa6b8"), Color("#7a8698"), Color("#3b4658")],
	3: [Color("#f0b98a"), Color("#c47a3e"), Color("#8a4f22"), Color("#5a2c10")],
}
## The places, in the mock's px: column width, block size, number size and its top pad, the avatar's box and tile,
## the medal (size, top in the box), name and value sizes.
const PLACE := {
	1: {col = 140.0, bw = 130.0, bh = 96.0, num = 36, pad = 6.0, box = 120.0, tile = 84.0, medal = 36.0, medal_y = 92.0, name = 18, xp = 14},
	2: {col = 120.0, bw = 110.0, bh = 76.0, num = 30, pad = 6.0, box = 92.0, tile = 64.0, medal = 32.0, medal_y = 66.0, name = 16, xp = 13},
	3: {col = 120.0, bw = 110.0, bh = 58.0, num = 28, pad = 4.0, box = 92.0, tile = 64.0, medal = 32.0, medal_y = 66.0, name = 16, xp = 13},
}

var board := "xp"                       ## "xp" (Level) | "wins" (Online wins)
var period := "week"                    ## "week" | "all"
var fetch_fn := Callable()              ## (board, period) -> Dictionary (coroutine); default: Account.leaderboard
var auto_load := true
var state := ""                         ## "loading" | "empty" | "offline" | "error" | "list"
var rows_shown := 0
var me_label: Label
var retry_button: Button
var board_seg: HBoxContainer            ## XP | Wins (the podium's top left)
var period_seg: HBoxContainer           ## This week | All time
var week_pill: PanelContainer           ## "New week in 2d 6h" (weekly board only)

var _list: VBoxContainer
var _podium: Podium
var _me_bar: PanelContainer
var _me_box: HBoxContainer
var _week_label: Label
var _cache := {}                        # "board|period" -> {at (msec), data}
var _req := 0
var _loading := false
var _pull := 0.0


func _init(width := 400.0) -> void:
	super("", width, true, LOOK_PM)
	var bg := ShopSheet._page_bg(Vector2(1.1, 0.55), Vector2(0.5, 0.22)) as StyleBoxTexture
	bg.content_margin_bottom = 16
	make_page(bg)
	var rays := Rays.new()
	card.add_child(rays)
	card.move_child(rays, 0)                 # over the ground, under everything else
	body.add_theme_constant_override("separation", 10)
	# LEADERBOARD and the new-week countdown
	var head := UIKit.hbox(10)
	head.name = "Head"
	head.custom_minimum_size.y = 38
	var title := ShopSheet.outlined(L10n.t("Leaderboard").to_upper(), 30, GOLD, 6)
	title.name = "PageTitle"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.clip_text = true                   # the countdown always shows in full; a long title (Bangla) shrinks first
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(title)
	week_pill = _week_pill()
	head.add_child(week_pill)
	body.add_child(head)
	# This week | All time
	period_seg = _segmented([["week", L10n.t("This week")], ["all", L10n.t("All time")]], period, _set_period, 38.0, 16)
	period_seg.name = "Periods"
	body.add_child(period_seg)
	_list = add_scroll_body(8)
	_fade.modulate.a = 0.0                   # the dark ground needs no fade (the sheet's is the PM face)
	scroll_box.gui_input.connect(_on_scroll_input)
	board_seg = _segmented([["xp", "XP"], ["wins", L10n.t("Wins")]], board, _set_board, 32.0, 14)
	board_seg.name = "Boards"
	board_seg.add_theme_constant_override("separation", 6)
	_podium = Podium.new(self, board_seg)
	_list.add_child(_podium)
	# your bar: a white rim round the teal face with its dark lip
	_me_bar = PanelContainer.new()
	_me_bar.name = "MeBar"
	var rim := UIKit.box(Color.WHITE, 20, 0)
	rim.shadow_color = Color(0, 0, 0, 0.45)
	rim.shadow_size = 10
	rim.shadow_offset = Vector2(0, 6)
	UIKit.pad(rim, 3)
	_me_bar.add_theme_stylebox_override("panel", rim)
	var face := GamePanel.vertical(Color("#5fe0c8"), Color("#2fb39c"))
	face.radius = 17.0
	face.lip = 6.0
	face.lip_color = Color("#1d7f6e")
	face.custom_minimum_size.y = 70.0
	_me_bar.add_child(face)
	_me_box = UIKit.hbox(10)
	_me_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := UIKit.margin(_me_box, 11, 0, 11, 0)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.add_child(m)
	var wide := UIKit.margin(_me_bar, -4, 0, -4, 0)   # the mock's bar: 10 px from the screen's sides (the page pads 14)
	wide.name = "MeBarBox"
	wide.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(wide)
	_me_bar.visible = false
	me_label = UIKit.label("", 12, Color("#0f4f44"), UIKit.font_body(900))
	var t := Timer.new()
	t.wait_time = 30.0
	t.autostart = true
	t.timeout.connect(_tick_week)
	add_child(t)


func _ready() -> void:
	_tick_week()
	if auto_load:
		load_board()


# ---------- header ----------

## The countdown pill: a clock and "New week in 2d 6h" on dark wood with a gold rim.
func _week_pill() -> PanelContainer:
	var p := PanelContainer.new()
	p.name = "NewWeek"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var st := UIKit.box(Color("#2a130a"), 12, 2, Color("#c98a3a"))
	st.content_margin_left = 10; st.content_margin_right = 10; st.content_margin_top = 4; st.content_margin_bottom = 4
	p.add_theme_stylebox_override("panel", st)
	var h := UIKit.hbox(5)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var clock := ClockIcon.new()
	clock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(clock)
	_week_label = UIKit.label("", 12, CREAM, UIKit.font_body(900))
	_week_label.name = "NewWeekText"
	_week_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(_week_label)
	p.add_child(h)
	return p

func _tick_week() -> void:
	if _week_label:
		_week_label.text = L10n.t("New week in %s") % week_left_text(week_left(int(Time.get_unix_time_from_system())))
	if week_pill:
		week_pill.visible = period == "week"

## Seconds until the weekly boards start again: Monday 00:00 in Bangladesh (the server's isoWeek, DAY_OFFSET_MIN 360).
static func week_left(now: int) -> int:
	var t := now + WEEK_OFFSET_SEC
	var days := floori(t / 86400.0)
	var dow := posmod(days + 3, 7)            # 0 = Monday (1970-01-01 was a Thursday)
	return (days - dow + 7) * 86400 - WEEK_OFFSET_SEC - now

## "2d 6h", then "5h 20m" on the last day.
static func week_left_text(sec: int) -> String:
	if sec >= 86400:
		return L10n.t("%dd %dh") % [sec / 86400, (sec % 86400) / 3600]
	return Fmt.until(sec)

## A row of the Shop's filter buttons; `value` is picked. Buttons carry meta "value".
func _segmented(options: Array, value: String, on_pick: Callable, h: float, fs: int) -> HBoxContainer:
	var row := UIKit.hbox(8)
	row.custom_minimum_size.y = h
	var group := ButtonGroup.new()
	for o: Array in options:
		var b := ShopSheet.filter_button(str(o[1]), group, h, fs)
		b.name = str(o[0])
		b.set_meta("value", o[0])
		b.button_pressed = o[0] == value
		var v: String = o[0]
		b.toggled.connect(func(x: bool): if x: on_pick.call(v))
		UIKit.wire_press(b)
		row.add_child(b)
	return row


# ---------- tabs ----------

func _set_board(v: Variant) -> void:
	if str(v) == board:
		return
	board = str(v)
	load_board()

func _set_period(v: Variant) -> void:
	if str(v) == period:
		return
	period = str(v)
	_tick_week()
	load_board()

## Select a board / period from code (tests, deep links): the segmented rows follow.
func select(board_: String, period_: String) -> void:
	board = board_
	period = period_
	_tick_week()
	for pair in [[board_seg, board_], [period_seg, period_]]:
		for b: Button in (pair[0] as HBoxContainer).get_children():
			if b.get_meta("value") == pair[1]:
				b.button_pressed = true         # the group un-presses the others; _set_board / _set_period see no change
	load_board()


# ---------- loading ----------

## Show the board / period: the kept answer at once (when there is one), then a fresh one when it is older than
## 30 s or `force`.
func load_board(force := false) -> void:
	var key := "%s|%s" % [board, period]
	_req += 1
	var my := _req
	var kept: Variant = _cache.get(key)
	var fresh: bool = kept != null and (Time.get_ticks_msec() - int(kept.at)) < CACHE_SEC * 1000.0
	if kept != null:
		_render(kept.data)
		if fresh and not force:
			return
	else:
		_show_state("loading", L10n.t("Loading…"))
		_me_bar.visible = false
	_loading = true
	var r: Dictionary = await _fetch(board, period)
	if not is_instance_valid(self) or _closing or my != _req:
		return
	_loading = false
	if r.get("ok", false):
		_cache[key] = {at = Time.get_ticks_msec(), data = r}
		_render(r)
		var me: Variant = r.get("me")
		if me is Dictionary and not bool((me as Dictionary).get("listed", true)):
			_refresh_account()
		return
	if kept != null:                       # a failed refresh keeps what is on screen
		Toast.show(self, Account.error_text(str(r.get("error", "")), "leaderboard"), card, 2.0, "bad")
		return
	_me_bar.visible = false
	if r.get("error", "") == "offline":
		_show_state("offline", Account.offline_text("leaderboard"), true)
	else:
		_show_state("error", L10n.t("The leaderboard isn’t available right now. Try again soon."), true)

func _fetch(b: String, p: String) -> Dictionary:
	if fetch_fn.is_valid():
		var out: Variant = await fetch_fn.call(b, p)
		return out if out is Dictionary else {ok = false, error = "offline"}
	var acc := Account.instance()
	if acc == null:
		return {ok = false, error = "offline"}
	return await acc.leaderboard(b, p)

## "Play N more matches" needs the account's completed_matches: ask GET /v1/me, then redraw the pinned row.
func _refresh_account() -> void:
	var acc := Account.instance()
	if acc == null:
		return
	var key := "%s|%s" % [board, period]
	if await acc.refresh_me() and is_instance_valid(self) and not _closing and _cache.has(key):
		_render_me(_cache[key].data)


# ---------- drawing ----------

## Everything under the podium goes; the podium is emptied.
func _clear() -> void:
	for c in _list.get_children():
		if c == _podium:
			continue
		_list.remove_child(c)
		c.queue_free()
	_podium.show_top([], board, 0)
	retry_button = null
	rows_shown = 0

func _show_state(kind: String, text: String, retry := false) -> void:
	state = kind
	_clear()
	var v := UIKit.vbox(12)
	v.name = "State"
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.custom_minimum_size.y = 120
	if kind == "empty":
		var ic := UIKit.icon("ic_trophy", 44)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		ic.modulate = Color(1, 1, 1, 0.6)
		v.add_child(ic)
	var l := UIKit.paragraph(text, 16, TAN, HORIZONTAL_ALIGNMENT_CENTER)
	l.name = "Message"
	l.add_theme_font_override("font", UIKit.font_body(900))
	v.add_child(l)
	if retry:
		retry_button = _gold_button(L10n.t("Try again"))
		retry_button.name = "Retry"
		retry_button.pressed.connect(func(): load_board(true))
		v.add_child(retry_button)
	_list.add_child(UIKit.margin(v, 8, 4, 8, 0))
	if scroll_box:
		scroll_box.scroll_vertical = 0

## A chunky gold button (the Shop's price button face) with dark display type.
static func _gold_button(text: String) -> Button:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.custom_minimum_size = Vector2(170, 48)
	for k in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		b.add_theme_stylebox_override(k, StyleBoxEmpty.new())
	var p := GamePanel.vertical(Color("#ffd45e"), Color("#f7a928"))
	p.radius = 14.0
	p.lip = 5.0
	p.lip_color = Color("#b86a0a")
	p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var l := UIKit.label(text, 18, Color("#4a2212"), UIKit.font_display(), HORIZONTAL_ALIGNMENT_CENTER)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	b.add_child(p)
	UIKit.wire_press(b)
	return b

func _render(r: Dictionary) -> void:
	var top: Array = (r.get("top", []) as Array).filter(func(e: Variant) -> bool: return e is Dictionary) if r.get("top") is Array else []
	if top.is_empty():
		_show_state("empty", L10n.t("No one is on the board yet. Play online matches to be the first."))
	else:
		state = "list"
		_clear()
		var mine := _my_rank(r)
		var shown := mini(top.size(), 50)
		_podium.show_top(top.slice(0, mini(3, shown)), board, mine)
		for k in range(3, shown):
			_list.add_child(_row(top[k], board, mine))
		rows_shown = shown
	_render_me(r)

## A wood row from #4: rank, avatar in its frame, name over the level pill, the value.
func _row(e: Dictionary, board_: String, mine := 0) -> Control:
	var rank := int(e.get("rank", 0))
	var you := rank > 0 and rank == mine
	var p := GamePanel.vertical(WOOD_TOP, WOOD_BOTTOM)
	p.radius = 16.0
	p.border = 2.0
	p.border_color = YOU_EDGE if you else WOOD_EDGE
	p.custom_minimum_size.y = ROW_H
	p.name = "Row%d" % rank
	var h := UIKit.hbox(10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(_rank_cell(rank))
	var ava := Collection.make_avatar_of(str(e.get("avatar", "pawn-red")), str(e.get("frame", "classic")), AVA_PX)
	ava.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ava.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(ava)
	var col := UIKit.vbox(1)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var nm := UIKit.label(str(e.get("name", L10n.t("Player"))), 16, Color.WHITE, UIKit.font_display())
	nm.name = "Name"
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(nm)
	var lv := LevelBadge.new(maxi(1, int(e.get("level", 1))), 16.0)      # "Lv 8": the pill, as on the avatars
	lv.name = "Level"
	lv.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(lv)
	h.add_child(col)
	var val := UIKit.label(value_text(int(e.get("value", 0)), board_), 16, CREAM, UIKit.font_display(), HORIZONTAL_ALIGNMENT_RIGHT)
	val.name = "Value"
	val.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	val.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(val)
	var m := UIKit.margin(h, 12, 0, 12, 0)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(m)
	_attach_friend(p, e, mine)
	return p

## Long-press another player (one with a handle, not you): add them to your friends.
func _attach_friend(c: Control, e: Dictionary, mine: int) -> void:
	var rank := int(e.get("rank", 0))
	var uid := str(e.get("uid", ""))
	var acc := Account.instance()
	var own := acc != null and str(acc.account.get("uid", "")) == uid
	if uid != "" and not own and not (rank > 0 and rank == mine):
		LongPress.attach(c, func():
			var s := Social.instance()
			if s != null:
				s.ask_friend(self, e))

## Your rank on this board (0: not listed).
static func _my_rank(r: Dictionary) -> int:
	var me: Variant = r.get("me")
	if me is Dictionary and bool((me as Dictionary).get("listed", true)) and (me as Dictionary).get("rank") != null:
		return int((me as Dictionary).get("rank", 0))
	return 0

## The rank: a medal for a tie into the top three (the podium has the real ones), then the number.
func _rank_cell(rank: int) -> Control:
	var cell := Control.new()
	cell.custom_minimum_size = Vector2(30, 42)
	cell.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.name = "Rank"
	if rank >= 1 and rank <= 3:
		var md := PlayerTile.PlaceBadge.make(rank, 30.0)
		md.position = Vector2(0, 6)
		cell.add_child(md)
		return cell
	var l := UIKit.label(str(rank), 20, TAN, UIKit.font_display(), HORIZONTAL_ALIGNMENT_CENTER)
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(l)
	return cell

## "1.2K XP" / "42 wins".
static func value_text(v: int, board_: String) -> String:
	if board_ == "xp":
		return L10n.t("%s XP") % Fmt.coins(v)
	return L10n.tn("%s win", "%s wins", v) % Fmt.coins(v)

## How many more finished matches until the account is listed.
static func matches_to_go(min_matches: int, completed: int) -> int:
	return maxi(1, min_matches - maxi(0, completed))

## The nearest player ahead of `value` on the shown list: [rank, how much more passes them]; [] when no one is.
static func next_up(top: Array, value: int) -> Array:
	var best: Dictionary = {}
	for e: Variant in top:
		if e is Dictionary and int((e as Dictionary).get("value", 0)) > value:
			if best.is_empty() or int((e as Dictionary).get("value", 0)) <= int(best.get("value", 0)):
				best = e
	if best.is_empty():
		return []
	return [int(best.get("rank", 0)), int(best.get("value", 0)) - value + 1]

func _render_me(r: Dictionary) -> void:
	for c in _me_box.get_children():
		_me_box.remove_child(c)
		c.queue_free()
	var me: Variant = r.get("me")
	var p: Dictionary = Save.profile
	var sub := ""
	var rank_text := ""
	var value := ""
	if me is Dictionary:
		var m: Dictionary = me
		var listed := bool(m.get("listed", true))
		var v := int(m.get("value", 0))
		value = value_text(v, board)
		if not listed:
			var acc := Account.instance()
			var done := int(acc.account.get("completed_matches", 0)) if acc != null else 0
			var n := matches_to_go(int(r.get("min_matches", 3)), done)
			sub = tr_n("Play %d more match to appear", "Play %d more matches to appear", n) % n
		elif m.get("rank") == null or int(m.get("rank", 0)) <= 0:
			sub = L10n.t("Not ranked yet")
		else:
			rank_text = "#%d" % int(m.rank)
			var up := next_up(r.get("top", []) if r.get("top") is Array else [], v)
			if int(m.rank) == 1:
				sub = L10n.t("Top of the board!")
			elif up.is_empty():
				sub = L10n.t("Level %d") % int(Save.level_info(int(p.get("xp", 0))).level)
			else:
				sub = L10n.t("%s to pass #%d") % [value_text(int(up[1]), board), int(up[0])]
	else:
		sub = L10n.t("Connect to see your rank")
	var rl := ShopSheet.outlined(rank_text, 26, Color.WHITE, 3, HORIZONTAL_ALIGNMENT_CENTER)
	rl.name = "YouRank"
	rl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rl.visible = rank_text != ""
	_me_box.add_child(rl)
	var ava := Collection.make_avatar(40.0)        # the tile 32 px, as the mock
	ava.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ava.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_me_box.add_child(ava)
	var col := UIKit.vbox(0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var nm := ShopSheet.outlined(L10n.t("You"), 18, Color.WHITE, 3)
	nm.name = "YouName"
	col.add_child(nm)
	me_label = UIKit.label(sub, 12, Color("#0f4f44"), UIKit.font_body(900))
	me_label.name = "YouNote"
	me_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	me_label.custom_minimum_size.x = ME_NOTE_W   # (a wrapping label with no width yet asks for one glyph per line)
	me_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(me_label)
	_me_box.add_child(col)
	if value != "":
		var vl := ShopSheet.outlined(value, 18, Color.WHITE, 3, HORIZONTAL_ALIGNMENT_RIGHT)
		vl.name = "YouValue"
		vl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_me_box.add_child(vl)
	_me_bar.visible = true
	_fit_me_bar.call_deferred()

## The pinned bar back to its contents' height once the new row has its width: the body only ever grows a child, so
## a taller moment during the rebuild would otherwise stay (the row pushed below the card on every refresh).
func _fit_me_bar() -> void:
	if not is_instance_valid(_me_bar):
		return
	_me_bar.reset_size()
	body.queue_sort()


# ---------- pull to refresh ----------

func _on_scroll_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_pull = 0.0
	elif e is InputEventMouseMotion and ((e as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		if scroll_box.scroll_vertical <= 0 and not _loading:
			_pull += (e as InputEventMouseMotion).relative.y
			if _pull >= PULL_PX:
				_pull = -100000.0
				Haptics.light()
				load_board(true)


# =====================================================================================================================
# The podium
# =====================================================================================================================

## The first three on their blocks: 2nd left, 1st in the middle (higher, crowned), 3rd right, standing on the bottom
## edge of a PODIUM_H area (6 px under the scroll's top, 4 more below so the rows start 12 px under it). An empty place
## keeps its block. `extra` (the board switch) sits at the top left.
class Podium extends Control:
	var sheet: LeaderboardSheet
	var extra: Control
	var _cols := {}                          # place -> VBoxContainer (the column, "Row<rank>" while someone stands there)

	func _init(sheet_: LeaderboardSheet, extra_: Control) -> void:
		sheet = sheet_
		extra = extra_
		name = "Podium"
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size.y = 6.0 + PODIUM_H + 4.0
		if extra:
			add_child(extra)
		show_top([], "xp", 0)
		resized.connect(_layout)

	func _layout() -> void:
		var ox := (size.x - PODIUM_W) / 2.0
		for n: int in _cols:
			var w: float = PLACE[n].col
			var x := ox if n == 2 else (ox + PODIUM_W - w if n == 3 else (size.x - w) / 2.0)
			var c := _cols[n] as Control
			var h := maxf(PODIUM_H, c.get_combined_minimum_size().y)   # a taller column grows up, as the mock's
			c.position = Vector2(x, 6.0 + PODIUM_H - h)
			c.size = Vector2(w, h)
		if extra:
			extra.size = extra.get_combined_minimum_size()
			extra.position = Vector2(maxf(0.0, ox + 6.0), 6.0)

	## Stand `top` (up to three entries, in order) on the places (new columns: a long-press never outlives its player).
	func show_top(top: Array, board_: String, mine: int) -> void:
		for n: int in _cols:
			var old: Node = _cols[n]
			remove_child(old)
			old.queue_free()
		_cols.clear()
		for n in [2, 1, 3]:
			var c := VBoxContainer.new()
			c.alignment = BoxContainer.ALIGNMENT_END
			c.add_theme_constant_override("separation", 0)
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var e: Dictionary = top[n - 1] if n <= top.size() else {}
			c.name = "Row%d" % int(e.get("rank", n)) if not e.is_empty() else "Place%d" % n
			if not e.is_empty():
				_fill(c, n, e, board_, mine)
			c.add_child(_block(n))
			_cols[n] = c
			c.minimum_size_changed.connect(_layout)
			add_child(c)
			move_child(c, 0)                      # under the board switch
		_layout()

	func _fill(c: VBoxContainer, n: int, e: Dictionary, board_: String, mine: int) -> void:
		var pl: Dictionary = PLACE[n]
		var rank := int(e.get("rank", n))
		if n == 1:
			var crown := Crown.new()
			crown.name = "Crown"
			crown.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			c.add_child(crown)
		var box := Control.new()
		box.name = "Avatar"
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.custom_minimum_size = Vector2(pl.box, pl.box)
		box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var s: float = pl.tile / Collection.FRAME_TILE
		var ava := Collection.make_avatar_of(str(e.get("avatar", "pawn-red")), str(e.get("frame", "classic")), s)
		ava.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ava.position = Vector2((pl.box - s) / 2.0, (pl.box - s) / 2.0)
		box.add_child(ava)
		var holder := Control.new()               # the medal (tests find "Rank"'s first child)
		holder.name = "Rank"
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.position = Vector2((pl.box - pl.medal) / 2.0, pl.medal_y)
		holder.size = Vector2(pl.medal, pl.medal)
		holder.add_child(PlayerTile.PlaceBadge.make(clampi(rank, 1, 3), pl.medal))
		box.add_child(holder)
		c.add_child(box)
		var gap := Control.new()
		gap.custom_minimum_size.y = 6.0
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.add_child(gap)
		var you := rank > 0 and rank == mine
		var nm := ShopSheet.outlined(str(e.get("name", L10n.t("Player"))), pl.name, YOU_EDGE if you else Color.WHITE, 3, HORIZONTAL_ALIGNMENT_CENTER)
		nm.name = "Name"
		nm.clip_text = true
		nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		c.add_child(nm)
		var val := UIKit.label(LeaderboardSheet.value_text(int(e.get("value", 0)), board_), pl.xp, CREAM, UIKit.font_display(), HORIZONTAL_ALIGNMENT_CENTER)
		val.name = "Value"
		val.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.add_child(val)
		var gap2 := Control.new()
		gap2.custom_minimum_size.y = 6.0
		gap2.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.add_child(gap2)
		sheet._attach_friend(c, e, mine)

	## The place's block: its metal top to bottom, a darker lip, the big number at the top.
	static func _block(n: int) -> GamePanel:
		var pl: Dictionary = PLACE[n]
		var col: Array = BLOCK[n]
		var b := GamePanel.vertical(col[0], col[1])
		b.name = "Block"
		b.radius = 14.0
		b.radius_bottom = 0.0
		b.lip = 6.0
		b.lip_color = col[2]
		b.custom_minimum_size = Vector2(pl.bw, pl.bh)
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var l := UIKit.label(str(n), pl.num, col[3], UIKit.font_display(), HORIZONTAL_ALIGNMENT_CENTER)
		l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var m := UIKit.margin(l, 0, int(pl.pad) - 4, 0, 0)
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(m)
		return b


## #1's crown (the mock's svg: five points, gold with a dark edge, a ruby in the middle).
class Crown extends Control:
	const PTS := [Vector2(4, 30), Vector2(2, 8), Vector2(16, 18), Vector2(27, 2), Vector2(38, 18), Vector2(52, 8), Vector2(50, 30)]

	func _init() -> void:
		custom_minimum_size = Vector2(54, 30)       # 34 drawn: the avatar's box overlaps its last 4 px
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var pts := PackedVector2Array(PTS)
		draw_colored_polygon(pts, GOLD)
		var loop := pts.duplicate()
		loop.append(pts[0])
		draw_polyline(loop, Color("#7a3a18"), 2.5, true)
		draw_circle(Vector2(27, 20), 4.0, Color("#e5484d"), true, -1.0, true)


## The countdown's clock (the mock's svg: a ring and two hands, cream).
class ClockIcon extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(13, 13)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var k := size.x / 24.0
		var w := 3.0 * k
		draw_arc(Vector2(12, 12) * k, 9.0 * k, 0.0, TAU, 32, CREAM, w, true)
		draw_polyline(PackedVector2Array([Vector2(12, 7) * k, Vector2(12, 12) * k, Vector2(15, 14) * k]), CREAM, w, true)


## The faint gold sunburst behind the podium (the mock's repeating-conic-gradient: 8 degrees of gold at 10% in every
## 20, inside a 350 px circle centred 210 px under the page's top). Drawn over the whole page, under its content.
class Rays extends Control:
	const SHADER := """shader_type canvas_item;
uniform vec2 area = vec2(400.0, 800.0);
uniform vec2 origin = vec2(0.0);       // the drawn rect's top left, in the control's px
uniform vec2 center = vec2(200.0, 210.0);
uniform float radius = 350.0;
uniform vec4 tint : source_color = vec4(1.0, 0.839, 0.369, 0.10);
void fragment() {
	vec2 p = origin + UV * area - center;
	float a = degrees(atan(p.x, -p.y));            // clockwise from straight up, as CSS conic angles
	float f = mod(a + 360.0, 20.0);
	float aa = max(fwidth(a), 0.001);
	float on = smoothstep(-aa, aa, f) * (1.0 - smoothstep(8.0 - aa, 8.0 + aa, f));
	float r = length(p);
	on *= 1.0 - smoothstep(radius - 1.0, radius + 1.0, r);
	COLOR = vec4(tint.rgb, tint.a * on);
}"""
	static var _shader: Shader
	var _mat: ShaderMaterial

	func _init() -> void:
		name = "Rays"
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		if _shader == null:
			_shader = Shader.new()
			_shader.code = SHADER
		_mat = ShaderMaterial.new()
		_mat.shader = _shader
		material = _mat
		resized.connect(queue_redraw)

	## The whole card (the content rect is inset by the page's margins).
	func _area() -> Rect2:
		var p := get_parent() as Control
		if p == null:
			return Rect2(Vector2.ZERO, size)
		return Rect2(-position, p.size)

	func _draw() -> void:
		var r := _area()
		_mat.set_shader_parameter("area", r.size)
		_mat.set_shader_parameter("origin", r.position)
		_mat.set_shader_parameter("center", Vector2(r.position.x + r.size.x / 2.0, r.position.y + 210.0))
		draw_rect(r, Color.WHITE)
