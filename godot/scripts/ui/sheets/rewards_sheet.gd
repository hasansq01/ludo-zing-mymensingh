class_name RewardsSheet
extends Sheet
## Home's gift: Free spin / Daily reward / Free coins in one small PM sheet ("Rewards" ribbon, the X). Each row is
## one button: the reward's icon, its name and what it gives, and on the right its state: a honey Spin / Claim
## while it is ready, else the countdown (to midnight for the spin and the daily reward, the clock for the free
## coins). A tap does what the reward's own button does (main._on_tab via `picked`): the spin sheet, the daily
## calendar, or the free coins claimed (they fly from the row into Home's counter). The states come from
## HomeScreen.reward_states (the gift's red count reads the same) and tick once per second.
##
## Economy v1: under them a "Free with a video" section (only where AdFlow.available(): Android with the AdMob plugin):
## "Free re-roll" (kind reroll) and "+2 gems" (kind gems), each with "N left today" (GET /v1/ads/today). A tap runs
## AdFlow.watch(kind); the reward is shown from the server's answer, and the counts refresh after.
##
##   var s := RewardsSheet.new(); s.picked.connect(main._on_tab); s.open(layer)

signal picked(id: String)                ## a row was tapped: "spin" | "daily" | "free"

const ROWS := [
	["spin", "Free spin", "spin", "Spin"],
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
var _rows := {}                          # id -> Row
var _vrows := {}                         # ad kind -> VideoRow
var _left := {}                          # ad kind -> videos left today (empty until GET /v1/ads/today answers)
var _video_box: VBoxContainer
var _tick: Timer


func _init() -> void:
	super("Rewards", UIKit.W.form, true, LOOK_PM)
	var list := add_scroll_body(UIKit.SPACE.sm + 2)
	for r in ROWS:
		var row := Row.new(r[0], r[1], HomeScreen.HI % r[2], r[3], _note(r[0]))
		row.pressed.connect(_go.bind(str(r[0])))
		list.add_child(row)
		_rows[r[0]] = row
	if videos_shown():
		_video_box = UIKit.vbox(UIKit.SPACE.sm + 2)
		_video_box.name = "Videos"
		_video_box.add_child(UIKit.margin(UIKit.caption("Free with a video"), 4, UIKit.SPACE.xs, 0, 0))
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


func _go(id: String) -> void:
	if _closing:
		return
	picked.emit(id)
	refresh.call_deferred()


## A reward row: one button (cream row card with a lip); the action on the right is drawn, not tappable itself.
class Row extends Button:
	var id := ""
	var go: Button                       # Spin / Claim (ready)
	var wait: PanelContainer             # the countdown pill (not ready)
	var wait_label: Label
	var _content: HBoxContainer
	var _shake_tw: Tween

	func _init(id_: String, title: String, icon_path: String, action: String, note: String) -> void:
		id = id_
		name = id_.capitalize()
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(0, 72)
		var st := UIKit.surface("row").duplicate() as StyleBoxFlat
		var pr := st.duplicate() as StyleBoxFlat
		pr.bg_color = Palette.ROW.darkened(0.04)
		pr.border_width_bottom = 2
		for k in ["normal", "hover", "disabled"]:
			add_theme_stylebox_override(k, st)
		for k in ["pressed", "hover_pressed"]:
			add_theme_stylebox_override(k, pr)
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
		t.clip_text = true
		t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		col.add_child(t)
		var n := UIKit.label(note, UIKit.FS.small + 1, Palette.SUB, UIKit.font_body(800))
		n.clip_text = true
		n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		col.add_child(n)
		go = UIKit.button(action, "honey", "sm")
		go.name = "Go"
		go.mouse_filter = Control.MOUSE_FILTER_IGNORE         # the whole row is the button
		go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		go.custom_minimum_size.x = 84
		_content.add_child(go)
		wait = PanelContainer.new()
		wait.name = "Wait"
		var ws := UIKit.box(Palette.CHIP, UIKit.R.pill)
		UIKit.pad(ws, 12, 6)
		wait.add_theme_stylebox_override("panel", ws)
		wait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		wait.custom_minimum_size.x = 84
		wait_label = UIKit.label("", UIKit.FS.label, Palette.SUB, UIKit.font_body(900, true), HORIZONTAL_ALIGNMENT_CENTER)
		wait.add_child(wait_label)
		_content.add_child(wait)
		wait.visible = false

	## Ready: the Spin / Claim button; else the countdown ("in 13h 20m", "in 3:53:09").
	func set_state(is_ready: bool, countdown: String) -> void:
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
		var st := UIKit.surface("row").duplicate() as StyleBoxFlat
		var pr := st.duplicate() as StyleBoxFlat
		pr.bg_color = Palette.ROW.darkened(0.04)
		pr.border_width_bottom = 2
		for k in ["normal", "hover", "disabled"]:
			add_theme_stylebox_override(k, st)
		for k in ["pressed", "hover_pressed"]:
			add_theme_stylebox_override(k, pr)
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
		t.clip_text = true
		t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		col.add_child(t)
		note = UIKit.label(note_, UIKit.FS.small + 1, Palette.SUB, UIKit.font_body(800))
		note.name = "Note"
		note.clip_text = true
		note.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		col.add_child(note)
		go = UIKit.button("Watch", "honey", "sm")
		go.name = "Go"
		go.mouse_filter = Control.MOUSE_FILTER_IGNORE
		go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		go.custom_minimum_size.x = 84
		content.add_child(go)
		wait = PanelContainer.new()
		wait.name = "Wait"
		var ws := UIKit.box(Palette.CHIP, UIKit.R.pill)
		UIKit.pad(ws, 12, 6)
		wait.add_theme_stylebox_override("panel", ws)
		wait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		wait.custom_minimum_size.x = 84
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
