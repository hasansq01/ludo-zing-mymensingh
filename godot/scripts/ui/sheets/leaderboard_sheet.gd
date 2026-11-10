class_name LeaderboardSheet
extends Sheet
## Leaderboard (server/ONLINE_V2.md section 4): the top 50 of GET /v1/leaderboard. Two boards, "Level" (total XP) and
## "Online wins", each Weekly or All time. A row: rank (a gold / silver / bronze medal for 1 to 3), avatar, name and
## level, the value. Your own row is pinned under the list ("#12"), or says "Play 2 more matches to appear" while
## you are below min_matches. A refresh button and pulling the list down at its top reload it. States: loading,
## empty, offline ("Connect to the internet..." with Try again) and a server error. Answers are kept for 30 s per
## board / period, so switching tabs is instant (and refreshes in the background once they are older).
##
##   LeaderboardSheet.new().open(app.sheet_layer)
## Long-press another player's row (its `uid`) to add them to your friends (Social.ask_friend).
## Tests: set fetch_fn (board, period) -> {ok, top, me, min_matches | error} (a coroutine) and auto_load false.

const ROW_H := 60.0
const ME_NOTE_W := 40.0                 # the pinned bar's note: wraps inside at least this width
const AVA_PX := 48.0                     ## the avatar in its frame (the frame art needs the room to read)
const CACHE_SEC := 30.0
const PULL_PX := 90.0
const FIXED_H := 700.0

var board := "xp"                       ## "xp" (Level) | "wins" (Online wins)
var period := "week"                    ## "week" | "all"
var fetch_fn := Callable()              ## (board, period) -> Dictionary (coroutine); default: Account.leaderboard
var auto_load := true
var state := ""                         ## "loading" | "empty" | "offline" | "error" | "list"
var rows_shown := 0
var me_label: Label
var refresh_button: Button
var retry_button: Button
var board_seg: HBoxContainer
var period_seg: HBoxContainer
var week_label: Label                   ## "New week in 2d 6h" under the tabs (Weekly only)

var _list: VBoxContainer
var _me_bar: PanelContainer
var _me_box: HBoxContainer
var _cache := {}                        # "board|period" -> {at (msec), data}
var _req := 0
var _loading := false
var _pull := 0.0


func _init(width: float = UIKit.W.catalog) -> void:
	super(L10n.t("Leaderboard"), width, true, LOOK_GAME)
	body.add_theme_constant_override("separation", UIKit.SPACE.sm)
	board_seg = UIKit.segmented([["xp", tr("Level")], ["wins", tr("Online wins")]], board, _set_board, "sm")
	board_seg.name = "Boards"
	UIKit.segmented_game(board_seg)
	body.add_child(board_seg)
	var bar := UIKit.hbox(UIKit.SPACE.sm)
	period_seg = UIKit.segmented([["week", tr("Weekly")], ["all", tr("All time")]], period, _set_period, "sm")
	period_seg.name = "Periods"
	period_seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIKit.segmented_game(period_seg)
	bar.add_child(period_seg)
	refresh_button = UIKit.icon_button("ic_reset", "glass", UIKit.TAP, 22)
	refresh_button.name = "Refresh"
	refresh_button.pressed.connect(func(): load_board(true))
	bar.add_child(refresh_button)
	body.add_child(bar)
	week_label = UIKit.label("", UIKit.FS.small, Palette.G_GOLD, UIKit.font_body(900), HORIZONTAL_ALIGNMENT_CENTER)
	week_label.name = "WeekLeft"
	body.add_child(week_label)
	_list = add_scroll_body(UIKit.SPACE.sm)
	fit(0.88, FIXED_H)
	scroll_box.gui_input.connect(_on_scroll_input)
	_me_bar = PanelContainer.new()
	var mst := UIKit.box(Palette.TEAL, UIKit.R.lg, UIKit.BW.rim, Color.WHITE)
	mst.border_width_bottom = UIKit.LIP.md + 2
	mst.border_color = Color.WHITE
	mst.shadow_color = Color(0, 0, 0, 0.35); mst.shadow_size = 8; mst.shadow_offset = Vector2(0, 3)
	UIKit.pad(mst, UIKit.SPACE.md, UIKit.SPACE.sm)
	_me_bar.add_theme_stylebox_override("panel", mst)
	_me_bar.name = "MeBar"
	_me_box = UIKit.hbox(UIKit.SPACE.sm)
	_me_bar.add_child(_me_box)
	body.add_child(_me_bar)
	_me_bar.visible = false
	me_label = UIKit.label("", UIKit.FS.label, Color.WHITE, UIKit.font_body(800))


func _ready() -> void:
	if auto_load:
		load_board()


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
	load_board()

## Select a board / period from code (tests, deep links): the segmented rows follow.
func select(board_: String, period_: String) -> void:
	board = board_
	period = period_
	for pair in [[board_seg, board_], [period_seg, period_]]:
		for b: Button in (pair[0] as HBoxContainer).get_children():
			if b.get_meta("value") == pair[1]:
				b.button_pressed = true         # the group un-presses the others; _set_board / _set_period see no change
	load_board()


# ---------- loading ----------

## Show the board / period: the kept answer at once (when there is one), then a fresh one when it is older than
## 30 s or `force`.
func load_board(force := false) -> void:
	week_label.visible = period == "week"
	week_label.text = L10n.t("New week in %s") % left_text(week_left(Time.get_unix_time_from_system()))
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
		_show_state("loading", tr("Loading…"))
		_me_bar.visible = false
	_loading = true
	refresh_button.disabled = true
	var r: Dictionary = await _fetch(board, period)
	if not is_instance_valid(self) or _closing or my != _req:
		return
	_loading = false
	refresh_button.disabled = false
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
		_show_state("error", tr("The leaderboard isn’t available right now. Try again soon."), true)

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

func _clear() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	retry_button = null
	rows_shown = 0

func _show_state(kind: String, text: String, retry := false) -> void:
	state = kind
	_clear()
	var v := UIKit.vbox(UIKit.SPACE.md)
	v.name = "State"
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.custom_minimum_size.y = 220
	if kind == "empty":
		var ic := UIKit.icon("ic_trophy", 56)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		ic.modulate = Color(1, 1, 1, 0.6)
		v.add_child(ic)
	var l := UIKit.paragraph(text, UIKit.FS.body_l, Palette.G_SUB, HORIZONTAL_ALIGNMENT_CENTER)
	l.name = "Message"
	v.add_child(l)
	if retry:
		retry_button = UIKit.btn(tr("Try again"), "honey", "sm")
		retry_button.name = "Retry"
		retry_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		retry_button.custom_minimum_size.x = 160
		retry_button.pressed.connect(func(): load_board(true))
		v.add_child(retry_button)
	_list.add_child(v)
	if scroll_box:
		scroll_box.scroll_vertical = 0

func _render(r: Dictionary) -> void:
	var top: Array = r.get("top", []) if r.get("top") is Array else []
	if top.is_empty():
		_show_state("empty", tr("No one is on the board yet. Play online matches to be the first."))
	else:
		state = "list"
		_clear()
		var shown := 0
		var mine := _my_rank(r)
		var podium: Array = []
		for e: Variant in top:
			if e is Dictionary and int((e as Dictionary).get("rank", 0)) >= 1 and int((e as Dictionary).get("rank", 0)) <= 3:
				podium.append(e)
		if podium.size() >= 1:
			_list.add_child(_podium(podium, board))
			shown += podium.size()
		for e: Variant in top:
			if not e is Dictionary or shown >= 50 or podium.has(e):
				continue
			_list.add_child(_row(e, board, mine))
			shown += 1
		rows_shown = shown
	_render_me(r)

## The top three on a podium: 2nd left, 1st in the middle (higher, crowned, larger), 3rd right; each with its avatar in
## its frame, place medal, name, level pill and value, standing on a gold / silver / bronze pedestal with its place.
## Each column is named "Row<rank>" with a "Rank" (the medal) and a "Level" (the pill), like the list rows.
func _podium(entries: Array, board_: String) -> Control:
	var row := UIKit.hbox(UIKit.SPACE.xs)
	row.name = "Podium"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var by_rank := {}
	for e: Dictionary in entries:
		by_rank[int(e.get("rank", 0))] = e
	for rank in [2, 1, 3]:
		if not by_rank.has(rank):
			var gap := Control.new()
			gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(gap)
			continue
		row.add_child(_podium_column(by_rank[rank], rank, board_))
	return UIKit.margin(row, 0, UIKit.SPACE.sm, 0, UIKit.SPACE.sm)

func _podium_column(e: Dictionary, rank: int, board_: String) -> Control:
	var col := UIKit.vbox(2)
	col.name = "Row%d" % rank
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_END
	col.alignment = BoxContainer.ALIGNMENT_END
	var px := 96.0 if rank == 1 else 72.0
	var ava := Collection.make_avatar_of(str(e.get("avatar", "pawn-red")), str(e.get("frame", "classic")), px)
	ava.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(ava)
	var medal_box := Control.new()
	medal_box.name = "Rank"
	medal_box.custom_minimum_size = Vector2(0, 30)
	medal_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := PlayerTile.PlaceBadge.make(rank, 32.0)
	medal_box.add_child(m)
	medal_box.resized.connect(func() -> void: m.position = Vector2((medal_box.size.x - 32.0) / 2.0, -10.0))
	col.add_child(medal_box)
	var nm := UIKit.label(str(e.get("name", L10n.t("Player"))), UIKit.FS.body if rank != 1 else UIKit.FS.h3, Palette.G_TEXT, UIKit.font_display(), HORIZONTAL_ALIGNMENT_CENTER)
	nm.name = "Name"
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.add_theme_constant_override("outline_size", 5)
	nm.add_theme_color_override("font_outline_color", Palette.G_OUTLINE)
	col.add_child(nm)
	var lv := LevelBadge.new(maxi(1, int(e.get("level", 1))), "xs")
	lv.name = "Level"
	lv.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(lv)
	var val := UIKit.label(value_text(int(e.get("value", 0)), board_), UIKit.FS.small, Palette.G_GOLD, UIKit.font_body(900, true), HORIZONTAL_ALIGNMENT_CENTER)
	val.name = "Value"
	col.add_child(val)
	var ped := PanelContainer.new()
	ped.name = "Pedestal"
	ped.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ped.custom_minimum_size = Vector2(0, {1: 64.0, 2: 48.0, 3: 36.0}[rank])
	var face := PlayerTile.PlaceBadge.face_color(rank)
	var st := UIKit.box(face, 0, 0)
	st.corner_radius_top_left = UIKit.R.md; st.corner_radius_top_right = UIKit.R.md
	st.border_width_bottom = UIKit.LIP.md
	st.border_color = face.darkened(0.3)
	ped.add_theme_stylebox_override("panel", st)
	var pl := UIKit.label(str(rank), UIKit.FS.h1, face.darkened(0.55), UIKit.font_display(), HORIZONTAL_ALIGNMENT_CENTER)
	pl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	pl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ped.add_child(pl)
	col.add_child(ped)
	var uid := str(e.get("uid", ""))
	var acc := Account.instance()
	if uid != "" and not (acc != null and str(acc.account.get("uid", "")) == uid):
		col.mouse_filter = Control.MOUSE_FILTER_PASS
		LongPress.attach(col, func():
			var so := Social.instance()
			if so != null:
				so.ask_friend(self, e))
	return col

## Seconds until the weekly board starts again: Monday 00:00 in Bangladesh (UTC+6), the server's week (rewards.ts).
static func week_left(now_unix: float) -> int:
	var local := int(now_unix) + 6 * 3600
	var days := int(floor(local / 86400.0))
	var weekday := posmod(days + 3, 7)               # 0 = Monday (1970-01-01 was a Thursday)
	var next_monday := (days - weekday + 7) * 86400
	return next_monday - local

## "2d 6h" / "5h 12m".
static func left_text(sec: int) -> String:
	var d := sec / 86400
	var h := (sec % 86400) / 3600
	if d > 0:
		return L10n.t("%dd %dh") % [d, h]
	return L10n.t("%dh %dm") % [h, (sec % 3600) / 60]

func _row(e: Dictionary, board_: String, mine := 0) -> Control:
	var rank := int(e.get("rank", 0))
	var h := UIKit.hbox(UIKit.SPACE.sm)
	h.custom_minimum_size.y = AVA_PX
	h.add_child(_rank_cell(rank))
	var ava := Collection.make_avatar_of(str(e.get("avatar", "pawn-red")), str(e.get("frame", "classic")), AVA_PX)
	ava.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ava)
	var col := UIKit.vbox(0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var nm := UIKit.label(str(e.get("name", L10n.t("Player"))), UIKit.FS.h3, Palette.G_TEXT, UIKit.font_display())
	nm.name = "Name"
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(nm)
	var lv := LevelBadge.new(maxi(1, int(e.get("level", 1))), "xs")       # "Lv 9": the pill, as on the avatars
	lv.name = "Level"
	lv.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(lv)
	h.add_child(col)
	var val := UIKit.label(value_text(int(e.get("value", 0)), board_), UIKit.FS.h3, Palette.G_GOLD, UIKit.font_body(900, true), HORIZONTAL_ALIGNMENT_RIGHT)
	val.name = "Value"
	val.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(val)
	var p := PanelContainer.new()
	var you := rank > 0 and rank == mine
	var rs := UIKit.box(Palette.WOOD_HI, UIKit.R.md, UIKit.BW.rim if you else UIKit.BW.line, Palette.TEAL if you else Palette.WOOD_LIP)
	rs.border_width_bottom = UIKit.LIP.sm + 1
	UIKit.pad(rs, UIKit.SPACE.md, UIKit.SPACE.xs)
	p.add_theme_stylebox_override("panel", rs)
	p.add_child(h)
	p.name = "Row%d" % rank
	if rank >= 1 and rank <= 3 and rank != mine:      # the top three: a wash of their medal's metal and a rim of it
		var st := (p.get_theme_stylebox("panel") as StyleBoxFlat).duplicate() as StyleBoxFlat
		var metal := PlayerTile.PlaceBadge.face_color(rank)
		st.bg_color = st.bg_color.lerp(metal, 0.16)
		st.border_color = metal.darkened(0.08)
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT]:
			st.set_border_width(side, UIKit.BW.line)
		st.border_width_bottom = UIKit.LIP.md
		p.add_theme_stylebox_override("panel", st)
	var uid := str(e.get("uid", ""))
	var acc := Account.instance()
	var own := acc != null and str(acc.account.get("uid", "")) == uid
	if uid != "" and not own and not (rank > 0 and rank == mine):   # long-press: add them to your friends (Social)
		LongPress.attach(p, func():
			var s := Social.instance()
			if s != null:
				s.ask_friend(self, e))
	return p

## Your rank on this board (0: not listed).
static func _my_rank(r: Dictionary) -> int:
	var me: Variant = r.get("me")
	if me is Dictionary and bool((me as Dictionary).get("listed", true)) and (me as Dictionary).get("rank") != null:
		return int((me as Dictionary).get("rank", 0))
	return 0

## 1 to 3 a medal (the result screen's place badges), then the number.
func _rank_cell(rank: int) -> Control:
	var cell := Control.new()
	cell.custom_minimum_size = Vector2(32, AVA_PX)
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.name = "Rank"
	if rank >= 1 and rank <= 3:
		var m := PlayerTile.PlaceBadge.make(rank, 32.0)
		m.position = Vector2(0, (AVA_PX - 32.0) / 2.0)
		cell.add_child(m)
		return cell
	var l := UIKit.label(str(rank), UIKit.FS.h3, Palette.G_SUB, UIKit.font_body(900, true), HORIZONTAL_ALIGNMENT_CENTER)
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
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

func _render_me(r: Dictionary) -> void:
	for c in _me_box.get_children():
		_me_box.remove_child(c)
		c.queue_free()
	var me: Variant = r.get("me")
	var p: Dictionary = Save.profile
	var ava := Collection.make_avatar(AVA_PX)
	ava.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var col := UIKit.vbox(0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var nm := UIKit.label(tr("You"), UIKit.FS.h3, Color.WHITE, UIKit.font_display())
	nm.add_theme_constant_override("outline_size", 4)
	nm.add_theme_color_override("font_outline_color", Palette.TEAL.darkened(0.45))
	nm.name = "YouName"
	col.add_child(nm)
	var sub := ""
	var rank_text := ""
	var value := ""
	if me is Dictionary:
		var m: Dictionary = me
		var listed := bool(m.get("listed", true))
		var v := int(m.get("value", 0))
		if not listed:
			var acc := Account.instance()
			var done := int(acc.account.get("completed_matches", 0)) if acc != null else 0
			var n := matches_to_go(int(r.get("min_matches", 3)), done)
			sub = tr_n("Play %d more match to appear", "Play %d more matches to appear", n) % n
			value = value_text(v, board)
		elif m.get("rank") == null or int(m.get("rank", 0)) <= 0:
			sub = tr("Not ranked yet")
			value = value_text(v, board)
		else:
			rank_text = "#%d" % int(m.rank)
			sub = tr("Level %d") % int(Save.level_info(int(p.get("xp", 0))).level)
			value = value_text(v, board)
	else:
		sub = tr("Connect to see your rank")
	var rl := UIKit.label(rank_text, UIKit.FS.h2, Color.WHITE, UIKit.font_display(), HORIZONTAL_ALIGNMENT_CENTER)
	rl.name = "YouRank"
	rl.custom_minimum_size.x = 34
	rl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rl.visible = rank_text != ""
	_me_box.add_child(rl)
	_me_box.add_child(ava)
	me_label = UIKit.label(sub, UIKit.FS.small, Palette.TEAL.darkened(0.6), UIKit.font_body(800))
	me_label.name = "YouNote"
	me_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	me_label.custom_minimum_size.x = ME_NOTE_W   # (a wrapping label with no width yet asks for one glyph per line)
	col.add_child(me_label)
	_me_box.add_child(col)
	if value != "":
		var vl := UIKit.label(value, UIKit.FS.h3, Color.WHITE, UIKit.font_body(900, true), HORIZONTAL_ALIGNMENT_RIGHT)
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
