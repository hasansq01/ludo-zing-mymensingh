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
## Tests: set fetch_fn (board, period) -> {ok, top, me, min_matches | error} (a coroutine) and auto_load false.

const ROW_H := 60.0
const ME_NOTE_W := 40.0                 # the pinned bar's note: wraps inside at least this width
const AVA_PX := 40.0
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

var _list: VBoxContainer
var _me_bar: PanelContainer
var _me_box: HBoxContainer
var _cache := {}                        # "board|period" -> {at (msec), data}
var _req := 0
var _loading := false
var _pull := 0.0


func _init(width: float = UIKit.W.catalog) -> void:
	super("Leaderboard", width, true, LOOK_PM)
	body.add_theme_constant_override("separation", UIKit.SPACE.sm)
	board_seg = UIKit.segmented([["xp", "Level"], ["wins", "Online wins"]], board, _set_board, "sm")
	board_seg.name = "Boards"
	body.add_child(board_seg)
	var bar := UIKit.hbox(UIKit.SPACE.sm)
	period_seg = UIKit.segmented([["week", "Weekly"], ["all", "All time"]], period, _set_period, "sm")
	period_seg.name = "Periods"
	period_seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(period_seg)
	refresh_button = UIKit.icon_button("ic_reset", "glass", UIKit.TAP, 22)
	refresh_button.name = "Refresh"
	refresh_button.pressed.connect(func(): load_board(true))
	bar.add_child(refresh_button)
	body.add_child(bar)
	_list = add_scroll_body(UIKit.SPACE.sm)
	fit(0.88, FIXED_H)
	scroll_box.gui_input.connect(_on_scroll_input)
	_me_bar = UIKit.list_row(null, "you")
	_me_bar.name = "MeBar"
	_me_box = UIKit.hbox(UIKit.SPACE.sm)
	_me_bar.add_child(_me_box)
	body.add_child(_me_bar)
	_me_bar.visible = false
	me_label = UIKit.label("", UIKit.FS.label, Palette.SUB, UIKit.font_body(800))


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
		_show_state("loading", "Loading…")
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
		_show_state("error", "The leaderboard isn’t available right now. Try again soon.", true)

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
	var l := UIKit.paragraph(text, UIKit.FS.body_l, Palette.SUB, HORIZONTAL_ALIGNMENT_CENTER)
	l.name = "Message"
	v.add_child(l)
	if retry:
		retry_button = UIKit.btn("Try again", "honey", "sm")
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
		_show_state("empty", "No one is on the board yet. Play online matches to be the first.")
	else:
		state = "list"
		_clear()
		var shown := 0
		var mine := _my_rank(r)
		for e: Variant in top:
			if not e is Dictionary or shown >= 50:
				continue
			_list.add_child(_row(e, board, mine))
			shown += 1
		rows_shown = shown
	_render_me(r)

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
	var nm := UIKit.label(str(e.get("name", "Player")), UIKit.FS.h3, Palette.INK, UIKit.font_display())
	nm.name = "Name"
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(nm)
	var lv := UIKit.label("Level %d" % maxi(1, int(e.get("level", 1))), UIKit.FS.small, Palette.SUB, UIKit.font_body(800))
	lv.name = "Level"
	col.add_child(lv)
	h.add_child(col)
	var val := UIKit.label(value_text(int(e.get("value", 0)), board_), UIKit.FS.h3, Palette.INK, UIKit.font_body(900, true), HORIZONTAL_ALIGNMENT_RIGHT)
	val.name = "Value"
	val.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(val)
	var p := UIKit.list_row(h, "you" if rank > 0 and rank == mine else "")   # rank 1 has its medal: no gold rim
	p.name = "Row%d" % rank
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
		var m := PlayerTile.PlaceBadge.make(rank, 30.0)
		m.position = Vector2(1, (AVA_PX - 30.0) / 2.0)
		cell.add_child(m)
		return cell
	var l := UIKit.label(str(rank), UIKit.FS.h3, Palette.MUTED, UIKit.font_body(900, true), HORIZONTAL_ALIGNMENT_CENTER)
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cell.add_child(l)
	return cell

## "1.2K XP" / "42 wins".
static func value_text(v: int, board_: String) -> String:
	if board_ == "xp":
		return "%s XP" % Fmt.coins(v)
	return "%s %s" % [Fmt.coins(v), "win" if v == 1 else "wins"]

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
	var nm := UIKit.label("You", UIKit.FS.h3, Palette.INK, UIKit.font_display())
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
			sub = "Play %d more %s to appear" % [n, "match" if n == 1 else "matches"]
			value = value_text(v, board)
		elif m.get("rank") == null or int(m.get("rank", 0)) <= 0:
			sub = "Not ranked yet"
			value = value_text(v, board)
		else:
			rank_text = "#%d" % int(m.rank)
			sub = "Level %d" % int(Save.level_info(int(p.get("xp", 0))).level)
			value = value_text(v, board)
	else:
		sub = "Connect to see your rank"
	var rl := UIKit.label(rank_text, UIKit.FS.h2, Palette.INK, UIKit.font_display(), HORIZONTAL_ALIGNMENT_CENTER)
	rl.name = "YouRank"
	rl.custom_minimum_size.x = 34
	rl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rl.visible = rank_text != ""
	_me_box.add_child(rl)
	_me_box.add_child(ava)
	me_label = UIKit.label(sub, UIKit.FS.small, Palette.SUB, UIKit.font_body(800))
	me_label.name = "YouNote"
	me_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	me_label.custom_minimum_size.x = ME_NOTE_W   # (a wrapping label with no width yet asks for one glyph per line)
	col.add_child(me_label)
	_me_box.add_child(col)
	if value != "":
		var vl := UIKit.label(value, UIKit.FS.h3, Palette.INK, UIKit.font_body(900, true), HORIZONTAL_ALIGNMENT_RIGHT)
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
