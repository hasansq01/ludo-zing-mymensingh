class_name RewardsSheet
extends Sheet
## Home's gift: Daily spin / Daily reward / Free coins in one small PM sheet ("Rewards" ribbon, the X). Each row is
## one button: the reward's icon, its name and what it gives, and on the right its state: a honey Spin / Claim
## while it is ready, else the countdown (to midnight for the spin and the daily reward, the clock for the free
## coins). A tap does what the reward's own button does (main._on_tab via `picked`): the spin sheet, the daily
## calendar, or the free coins claimed (they fly from the row into Home's counter). The states come from
## HomeScreen.reward_states (the gift's red count reads the same) and tick once per second.
##
## The Shop's "Get coins" is this same sheet (RewardsSheet.new("Get coins", true)): same rows, names, countdowns and
## taps, plus a "Win vs computer" info row under them (what a win pays).
##
## Economy v1: under them a "Free with a video" section (only where AdFlow.available(): Android with the AdMob plugin):
## "Free re-roll" (kind reroll) and "+2 gems" (kind gems), each with "N left today" (GET /v1/ads/today). A tap runs
## AdFlow.watch(kind); the reward is shown from the server's answer, and the counts refresh after.
##
##   var s := RewardsSheet.new(); s.picked.connect(main._on_tab); s.open(layer)

signal picked(id: String)                ## a row was tapped: "spin" | "daily" | "free"

const ROWS := [
	["spin", "Daily spin", "spin", "Spin"],
	["daily", "Daily reward", "gift", "Claim"],
	["free", "Free coins", "coins", "Claim"],
]

## Dev / tests: show the video section even where ads can't run (the previews).
static var force_videos := false

const VIDEO_ROWS := [
	["reroll", "Free re-roll", "res://assets/ui/home/hi_again.svg", "Roll again in an online match"],
	["gems", "+2 gems", "res://assets/ui/gem.svg", "Gems buy rooms, dice and more"],
]

var flow: AdFlow
var wins_row := false                    ## the Get coins variant: a "Win vs computer" info row after the rewards
var _rows := {}                          # id -> Row
var _vrows := {}                         # ad kind -> VideoRow
var _left := {}                          # ad kind -> videos left today (empty until GET /v1/ads/today answers)
var _video_box: VBoxContainer
var _tick: Timer


func _init(title_ := "Rewards", wins_row_ := false) -> void:
	super(title_, UIKit.W.form, true, LOOK_PM)
	wins_row = wins_row_
	var list := add_scroll_body(UIKit.SPACE.sm)
	for r in ROWS:
		var row := Row.new(r[0], r[1], HomeScreen.HI % r[2], r[3], _note(r[0]))
		row.pressed.connect(_go.bind(str(r[0])))
		list.add_child(row)
		_rows[r[0]] = row
	if wins_row:
		list.add_child(_wins_row())
	if videos_shown():
		_video_box = UIKit.vbox(UIKit.SPACE.sm)
		_video_box.name = "Videos"
		_video_box.add_child(UIKit.margin(UIKit.caption("Free with a video"), 4, UIKit.SPACE.sm, 0, 0))
		for v in VIDEO_ROWS:
			var vr := VideoRow.new(v[0], v[1], v[2], v[3])
			vr.pressed.connect(_watch.bind(str(v[0])))
			_video_box.add_child(vr)
			_vrows[v[0]] = vr
		list.add_child(_video_box)
		flow = AdFlow.new()
		flow.name = "AdFlow"
		flow.done.connect(_on_watched)
		add_child(flow)
	fit()


func _ready() -> void:
	Save.changed.connect(refresh)
	_tick = Timer.new()
	_tick.wait_time = 1.0
	_tick.timeout.connect(refresh)
	add_child(_tick)
	_tick.start()
	refresh()
	if _video_box != null:
		load_today()
		var ad := Ads.instance()
		if ad:
			ad.loaded.connect(_refresh_videos)
			ad.closed.connect(_refresh_videos)


## What each reward gives (the row's second line).
static func _note(id: String) -> String:
	match id:
		"spin":
			return "Win up to %s coins" % Fmt.coins_full(Rewards.PRIZES.max())
		"daily":
			return "A new gift every day"
		_:
			return "%s coins every %dh" % [Fmt.gain(Rewards.FREE_AMOUNT), roundi(Rewards.FREE_EVERY_SEC / 3600.0)]


## The row of a reward ("spin" | "daily" | "free"), or null (main flies the free coins from it).
func row(id: String) -> Control:
	return _rows.get(id)


## The live state of the three rows.
func refresh() -> void:
	var st := HomeScreen.reward_states(Save.profile)
	for id in _rows:
		(_rows[id] as Row).set_state(bool(st[id].ready), str(st[id].wait))


## The video section shows only where a rewarded ad can run.
static func videos_shown() -> bool:
	return force_videos or AdFlow.available()


## GET /v1/ads/today -> the "N left today" of each video row.
func load_today() -> void:
	if not Account.wallet_active():
		return
	var r: Dictionary = await Account.instance().ads_today()
	if not is_instance_valid(self) or _closing:
		return
	if r.get("ok", false) and r.get("left") is Dictionary:
		_left = (r.left as Dictionary).duplicate()
	_refresh_videos()


## "N left today" and the Watch / Back tomorrow state of each video row.
func _refresh_videos() -> void:
	var rr := int(Save.profile.get("rerolls", 0))
	for kind in _vrows:
		var vr: VideoRow = _vrows[kind]
		var n := int(_left.get(kind, -1))
		var extra := ""
		if kind == "reroll" and rr > 0:
			extra = " · you have %d" % rr
		vr.set_left(n, extra, flow == null or not flow.busy)


func video_row(kind: String) -> Control:
	return _vrows.get(kind)


func _watch(kind: String) -> void:
	if _closing or flow == null or flow.busy:
		return
	var vr: VideoRow = _vrows[kind]
	if int(_left.get(kind, 1)) <= 0:
		Toast.show(self, Account.error_text("cap"), card, 2.0, "bad")
		return
	vr.set_busy(true)
	flow.watch(kind)


func _on_watched(ok: bool, info: Dictionary) -> void:
	if not is_instance_valid(self) or _closing:
		return
	var vr: VideoRow = _vrows.get(str(info.get("kind", "")))
	if vr:
		vr.set_busy(false)
	if ok:
		Sound.sfx("buy")
		Haptics.success()
		var amount := int(info.get("amount", 0))
		var what := "+%d gems" % amount if info.kind == "gems" else "+%d free re-roll" % maxi(1, amount)
		Toast.show(self, what, card, 2.0, "gem" if info.kind == "gems" else "good")
	else:
		Sound.sfx("error")
		Haptics.error()
		Toast.show(self, str(info.get("text", "Something went wrong. Please try again.")), card, 2.4, "bad")
	await load_today()


## What a win pays: an info row (not a button), the same row card.
func _wins_row() -> Control:
	var h := UIKit.hbox(UIKit.SPACE.md)
	var ic := UIKit.icon("ic_trophy", 44)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var col := UIKit.vbox(-1)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(UIKit.label("Win vs computer", UIKit.FS.h3, Palette.INK, UIKit.font_body(900)))
	var n := UIKit.paragraph("%s in Ludo, %s in Snakes & Ladders" % [Fmt.gain(LudoRules.WIN_REWARD), Fmt.gain(SnakesLaddersRules.REWARD)],
			UIKit.FS.small + 1, Palette.SUB)
	col.add_child(n)
	h.add_child(col)
	var p := UIKit.list_row(h)
	p.name = "Wins"
	return p


## A row's title and note: one line each, clipped with an ellipsis; on a narrow card (a row under 280 px) the icon is
## dropped so "Win up to 1,000 coins" still reads whole.
static func _fit_text(title: Label, note: Label, icon: Control, row: Control) -> void:
	for l: Label in [title, note]:
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.resized.connect(func(): icon.visible = row.size.x >= 280.0 or row.size.x <= 0.0)


## The row card of a Row / VideoRow button: the shared list-row look (the gold rim = ready), pressed a touch darker.
static func _row_look(b: Button, on: bool) -> void:
	var st := UIKit.row_style("on" if on else "")
	var pr := st.duplicate() as StyleBoxFlat
	pr.bg_color = Palette.ROW.darkened(0.04)
	pr.border_width_bottom = 2
	for k in ["normal", "hover", "disabled"]:
		b.add_theme_stylebox_override(k, st)
	for k in ["pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(k, pr)


func _go(id: String) -> void:
	if _closing:
		return
	if picked.get_connections().is_empty():          # no Main (previews): do what the row does here
		_local(id)
	picked.emit(id)
	refresh.call_deferred()


## Without Main: the free coins are claimed here, the spin / daily sheets open over this one.
func _local(id: String) -> void:
	var main := get_tree().root.get_node_or_null("Main")
	if main and main.has_method("_on_tab"):
		main.call("_on_tab", id)
	elif id == "free":
		var n := Rewards.claim_free(Save.profile)
		if n > 0:
			Sound.sfx("coin", n)
			Toast.show(self, "%s coins" % Fmt.gain(n), card, 1.8, "coin")
	else:
		var path := "res://scripts/ui/sheets/%s_sheet.gd" % id
		if ResourceLoader.exists(path) and get_parent():
			var s: Sheet = load(path).new()
			s.open(get_parent())


## A reward row: one button (cream row card with a lip); the action on the right is drawn, not tappable itself.
class Row extends Button:
	var id := ""
	var go: Button                       # Spin / Claim (ready)
	var wait: PanelContainer             # the countdown pill (not ready)
	var wait_label: Label
	var _content: HBoxContainer
	var _shake_tw: Tween
	var _lit := false                    # wearing the gold rim (ready)

	func _init(id_: String, title: String, icon_path: String, action: String, note: String) -> void:
		id = id_
		name = id_.capitalize()
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(0, 72)
		RewardsSheet._row_look(self, false)
		add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		UIKit.wire_press(self)
		_content = UIKit.hbox(UIKit.SPACE.md)
		_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_content.offset_left = 10; _content.offset_right = -12; _content.offset_bottom = -2
		add_child(_content)
		var ic := UIKit.icon(icon_path, 44)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_content.add_child(ic)
		var col := UIKit.vbox(-1)
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_content.add_child(col)
		var t := UIKit.label(title, UIKit.FS.h3, Palette.INK, UIKit.font_body(900))
		col.add_child(t)
		var n := UIKit.label(note, UIKit.FS.small + 1, Palette.SUB, UIKit.font_body(800))
		col.add_child(n)
		RewardsSheet._fit_text(t, n, ic, self)
		go = UIKit.button(action, "honey", "sm")
		go.name = "Go"
		go.mouse_filter = Control.MOUSE_FILTER_IGNORE         # the whole row is the button
		go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		go.custom_minimum_size.x = 76
		_content.add_child(go)
		wait = PanelContainer.new()
		wait.name = "Wait"
		var ws := UIKit.box(Palette.CHIP, UIKit.R.pill)
		UIKit.pad(ws, 12, 6)
		wait.add_theme_stylebox_override("panel", ws)
		wait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		wait.custom_minimum_size.x = 76
		wait_label = UIKit.label("", UIKit.FS.label, Palette.SUB, UIKit.font_body(900, true), HORIZONTAL_ALIGNMENT_CENTER)
		wait.add_child(wait_label)
		_content.add_child(wait)
		wait.visible = false

	## Ready: the Spin / Claim button; else the countdown ("in 13h 20m", "in 3:53:09").
	func set_state(is_ready: bool, countdown: String) -> void:
		if is_ready != _lit:
			_lit = is_ready
			RewardsSheet._row_look(self, is_ready)
		go.visible = is_ready
		wait.visible = not is_ready
		var t := "in " + countdown if countdown != "" else ""
		if wait_label.text != t:
			wait_label.text = t

	## A tap while it isn't ready (the free coins say when): a short shake (none with Reduce motion).
	func shake() -> void:
		if not is_inside_tree() or Sheet.reduce_motion():
			return
		if _shake_tw and _shake_tw.is_valid():
			_shake_tw.kill()
		_content.offset_left = 10; _content.offset_right = -12
		_shake_tw = create_tween()
		for dx in [-6.0, 5.0, -4.0, 3.0, -1.5, 0.0]:
			_shake_tw.tween_property(_content, "position:x", 10.0 + dx, 0.05).set_trans(Tween.TRANS_SINE)


## A "Free with a video" row: icon, title, "N left today", and a honey Watch button (the whole row is the button).
class VideoRow extends Button:
	var kind := ""
	var go: Button
	var wait: PanelContainer
	var wait_label: Label
	var note: Label
	var _base_note := ""

	func _init(kind_: String, title: String, icon_path: String, note_: String) -> void:
		kind = kind_
		_base_note = note_
		name = "Video_" + kind_
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(0, 72)
		RewardsSheet._row_look(self, false)
		add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		UIKit.wire_press(self)
		var content := UIKit.hbox(UIKit.SPACE.md)
		content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.offset_left = 10; content.offset_right = -12; content.offset_bottom = -2
		add_child(content)
		var ic := UIKit.icon(icon_path, 44)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		content.add_child(ic)
		var col := UIKit.vbox(-1)
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(col)
		var t := UIKit.label(title, UIKit.FS.h3, Palette.INK, UIKit.font_body(900))
		col.add_child(t)
		note = UIKit.label(note_, UIKit.FS.small + 1, Palette.SUB, UIKit.font_body(800))
		note.name = "Note"
		col.add_child(note)
		RewardsSheet._fit_text(t, note, ic, self)
		go = UIKit.button("Watch", "honey", "sm")
		go.name = "Go"
		go.mouse_filter = Control.MOUSE_FILTER_IGNORE
		go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		go.custom_minimum_size.x = 76
		content.add_child(go)
		wait = PanelContainer.new()
		wait.name = "Wait"
		var ws := UIKit.box(Palette.CHIP, UIKit.R.pill)
		UIKit.pad(ws, 12, 6)
		wait.add_theme_stylebox_override("panel", ws)
		wait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		wait.custom_minimum_size.x = 76
		wait_label = UIKit.label("", UIKit.FS.label, Palette.SUB, UIKit.font_body(900, true), HORIZONTAL_ALIGNMENT_CENTER)
		wait.add_child(wait_label)
		content.add_child(wait)
		wait.visible = false

	## n: videos left today (-1 = not known yet). `extra` follows the count on the note line.
	func set_left(n: int, extra: String, can_watch: bool) -> void:
		var done := n == 0
		go.visible = not done
		wait.visible = done
		wait_label.text = "Done today"
		note.text = (("%d left today" % n) if n > 0 else ("Come back tomorrow" if done else _base_note)) + extra
		go.text = "Watch"
		go.disabled = not can_watch

	func set_busy(on: bool) -> void:
		go.text = "…" if on else "Watch"
		disabled = on
