class_name RewardsSheet
extends Sheet
## Home's gift: Daily spin / Daily reward / Free coins in one game-look popup (Sheet LOOK_GAME: "Rewards", the X). Each
## row is one button, a wood tile: the reward's icon on a coloured disc, its name (outlined white) and what it gives
## (cream), and on the right its state: a gold Spin / Claim (a teal Go for the missions) while it is ready (the tile
## wears a gold rim), else the countdown on a dark chip (to midnight for the spin and the daily reward, the clock for
## the free coins). A tap does what the reward's own button does (main._on_tab via `picked`): the spin sheet, the daily
## calendar, or the free coins claimed (they fly from the row into Home's counter). The states come from
## HomeScreen.reward_states (the gift's red count reads the same) and tick once per second.
##
## The Shop's "Get coins" is this same sheet (RewardsSheet.new("Get coins", true)): same rows, names, countdowns and
## taps, plus a "Win vs computer" info row under them (what a win pays).
##
## Economy v1: under them a "Free with a video" section (only where AdFlow.available(): Android with an ads plugin):
## "Free re-roll" (kind reroll) and "+2 gems" (kind gems), each with "N left today" (GET /v1/ads/today). A tap runs
## AdFlow.watch(kind); the reward is shown from the server's answer, and the counts refresh after.
##
## The row pieces (disc, wait_chip, relook, fit_game) are shared with the Welcome, Daily, Missions, Store and Out of
## coins popups.
##
##   var s := RewardsSheet.new(); s.picked.connect(main._on_tab); s.open(layer)

signal picked(id: String)                ## a row was tapped: "spin" | "daily" | "free"

const ROWS := [["spin", "spin"], ["daily", "gift"], ["free", "coins"]]   # id, icon (and Daily missions under them)
## id -> [title, action button]; shown through L10n.t.
# l10n:begin
const ROW_TEXT := {
	spin = ["Lucky Draw", "Spin"],
	daily = ["Daily reward", "Claim"],
	free = ["Free coins", "Claim"],
}
# l10n:end

## Dev / tests: show the video section even where ads can't run (the previews).
static var force_videos := false

const VIDEO_ROWS := [
	["reroll", "res://assets/ui/home/hi_again.svg"],
	["gems", "res://assets/ui/gem.svg"],
]
## kind -> [title, note]; shown through L10n.t.
# l10n:begin
const VIDEO_TEXT := {
	reroll = ["Free re-roll", "Roll again in an online match"],
	gems = ["+2 gems", "Gems buy rooms, dice and more"],
}
# l10n:end

var flow: AdFlow
var wins_row := false                    ## the Get coins variant: a "Win vs computer" info row after the rewards
var _rows := {}                          # id -> Row
var _vrows := {}                         # ad kind -> VideoRow
var _left := {}                          # ad kind -> videos left today (empty until GET /v1/ads/today answers)
var _video_box: VBoxContainer
var _tick: Timer


func _init(title_ := "Rewards", wins_row_ := false) -> void:   # l10n
	super(L10n.t(title_), UIKit.W.form, true, LOOK_GAME)
	wins_row = wins_row_
	var list := add_scroll_body(UIKit.SPACE.sm + 2)
	for r in ROWS:
		var row := Row.new(r[0], L10n.t(ROW_TEXT[r[0]][0]), HomeScreen.HI % r[1], L10n.t(ROW_TEXT[r[0]][1]), _note(r[0]))
		row.pressed.connect(_go.bind(str(r[0])))
		list.add_child(row)
		_rows[r[0]] = row
	var mis := Row.new("missions", L10n.t("Daily missions"), HomeScreen.HI % "again", L10n.t("Go"), L10n.t("Three goals, then a chest"))
	mis.pressed.connect(_go.bind("missions"))
	mis.set_state(true, "")
	list.add_child(mis)
	if wins_row:
		list.add_child(_wins_row())
	if videos_shown():
		_video_box = UIKit.vbox(UIKit.SPACE.sm + 2)
		_video_box.name = "Videos"
		_video_box.add_child(UIKit.margin(GameUI.outlined(tr("Free with a video"), 17, GameUI.GOLD, 2), 4, UIKit.SPACE.sm, 0, 0))
		for v in VIDEO_ROWS:
			var vr := VideoRow.new(v[0], L10n.t(VIDEO_TEXT[v[0]][0]), v[1], L10n.t(VIDEO_TEXT[v[0]][1]))
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
			return L10n.t("Win up to %s coins") % Fmt.coins_full(Rewards.PRIZES.max())
		"daily":
			return L10n.t("A new gift every day")
		_:
			return L10n.t("%s coins every %dh") % [Fmt.gain(Rewards.FREE_AMOUNT), roundi(Rewards.FREE_EVERY_SEC / 3600.0)]


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
			extra = " · " + tr("you have %d") % rr
		vr.set_left(n, extra, flow == null or not flow.busy)


func video_row(kind: String) -> Control:
	return _vrows.get(kind)


func _watch(kind: String) -> void:
	if _closing or flow == null or flow.busy:
		return
	var vr: VideoRow = _vrows[kind]
	if int(_left.get(kind, 1)) <= 0:
		UIKit.deny(self, Account.error_text("cap"), vr, 2.0)
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
		var what := tr("+%d gems") % amount if info.kind == "gems" else tr("+%d free re-roll") % maxi(1, amount)
		Toast.show(self, what, card, 2.0, "gem" if info.kind == "gems" else "good")
	else:
		Sound.sfx("error")
		Haptics.error()
		Toast.show(self, str(info.get("text", tr("Something went wrong. Please try again."))), card, 2.4, "bad")
	await load_today()


## What a win pays: an info row (not a button), the same wood tile.
func _wins_row() -> Control:
	var h := UIKit.hbox(UIKit.SPACE.md)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(RewardsSheet.disc("ic_trophy", "red", 50.0, 28.0))
	var col := UIKit.vbox(0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(GameUI.outlined(tr("Win vs computer"), 19, GameUI.TEXT, 2))
	var n := GameUI.text(tr("%s in Ludo, %s in Snakes & Ladders") % [Fmt.gain(LudoRules.WIN_REWARD), Fmt.gain(SnakesLaddersRules.REWARD)], 14)
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(n)
	h.add_child(col)
	var p := GameUI.tile(16.0, 0.0)
	p.name = "Wins"
	p.custom_minimum_size.y = 72
	p.add_child(UIKit.margin(h, 10, 8, 12, 8))
	return p


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
			Toast.show(self, tr("%s coins") % Fmt.gain(n), card, 1.8, "coin")
	else:
		var path := "res://scripts/ui/sheets/%s_sheet.gd" % id
		if ResourceLoader.exists(path) and get_parent():
			var s: Sheet = load(path).new()
			s.open(get_parent())


# ---------- the game look's row pieces (shared with the Welcome, Daily, Missions, Store and Out of coins popups) ----------

## A round icon disc in a GameUI look's colours ("teal", "blue", "purple", "green", "red", "gold") with the icon on it
## (a res:// path or an assets/ui name) and a small lip under it.
static func disc(icon_path: String, look := "teal", d := 50.0, icon_size := 32.0) -> GamePanel:
	var c: Array = GameUI.LOOKS[look]
	var p := GamePanel.vertical(c[0], c[1])
	p.name = "Disc"
	p.radius = d / 2.0
	p.lip = 3.0
	p.lip_color = c[2]
	p.border = 2.0
	p.border_color = Color(Color.WHITE, 0.3)
	p.custom_minimum_size = Vector2(d, d + 3.0)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.add_child(UIKit.icon(icon_path, icon_size))
	p.add_child(cc)
	return p

## A dark chip with a gold rim for a countdown or a state ("in 4h 14m", "Done today"); its label is the child "Text".
static func wait_chip(min_w := 80.0, fs := 14) -> PanelContainer:
	var c := PanelContainer.new()
	c.name = "Wait"
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := UIKit.box(Palette.GL_CHIP_BG, 14, 2, Palette.GL_CHIP_RIM)
	st.content_margin_left = 9; st.content_margin_right = 9; st.content_margin_top = 6; st.content_margin_bottom = 7
	c.add_theme_stylebox_override("panel", st)
	c.size_flags_horizontal = Control.SIZE_SHRINK_END
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.custom_minimum_size.x = min_w
	var l := UIKit.label("", fs, Palette.GL_CREAM_RIM, UIKit.font_body(900, true), HORIZONTAL_ALIGNMENT_CENTER)
	l.name = "Text"
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(l)
	return c

## A reward amount in the game look: white display figures with the dark outline beside the coin / gem art.
static func amount(a: CoinAmount) -> CoinAmount:
	a.mouse_filter = Control.MOUSE_FILTER_IGNORE
	a.set_color(Color.WHITE)
	a.text_label.add_theme_constant_override("outline_size", 6)
	a.text_label.add_theme_color_override("font_outline_color", Palette.GL_INK)
	return a

## Give a GameButton another look after it was made (Claim -> the quiet wood "Come back tomorrow", Swap -> Need 40).
static func relook(b: GameUI.GameButton, look: String) -> void:
	if b.look == look:
		return
	b.look = look
	var c: Array = GameUI.LOOKS[look]
	b.face.c0 = c[0]
	b.face.c1 = (c[0] as Color).lerp(c[1], 0.5)
	b.face.c2 = c[1]
	b.face.lip_color = c[2]
	b.face.lip2_color = c[3]
	b.label.add_theme_color_override("font_color", c[4])
	if (c[5] as Color).a > 0.0:
		b.label.add_theme_constant_override("outline_size", 6 if b.size_name == "lg" else 4)
		b.label.add_theme_color_override("font_outline_color", c[5])
	else:
		b.label.add_theme_constant_override("outline_size", 0)

## A GameButton's label shrinks (down to min_fs) until its upper-cased text fits the face: now, on every resize, and
## whenever refit() is called after the text changed.
static func fit_game(b: GameUI.GameButton, min_fs := 13) -> void:
	b.set_meta("fit_min", min_fs)
	b.resized.connect(refit.bind(b))
	refit(b)

static func refit(b: GameUI.GameButton) -> void:
	if not is_instance_valid(b):
		return
	var z: Array = GameUI.SIZES[b.size_name]
	var room := b.size.x - 24.0
	if b.icon_rect:
		room -= b.icon_rect.custom_minimum_size.x + 8.0
	var fs := int(z[1])
	if room > 0.0:
		var f := UIKit.font_display()
		var t := b.text.to_upper()
		var lo := int(b.get_meta("fit_min", 13))
		while fs > lo and f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > room:
			fs -= 1
	if b.label.get_theme_font_size("font_size") != fs:
		b.label.add_theme_font_size_override("font_size", fs)

## A row's title and note: one line each, the note a size or two smaller when it would not fit, then clipped with an
## ellipsis; on a narrow card (a row under 280 px) the icon is dropped so "Win up to 1,000 coins" still reads whole.
static func _fit_text(title: Label, note: Label, icon: Control, row: Control) -> void:
	for l: Label in [title, note]:
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	note.set_meta("fit_fs", note.get_theme_font_size("font_size"))
	note.resized.connect(shrink_label.bind(note))
	row.resized.connect(func(): icon.visible = row.size.x >= 280.0 or row.size.x <= 0.0)

## A one-line label shrinks (its "fit_fs" meta size down to 2 px less) until its text fits its width; still too long,
## it wraps onto a second line at that size (the row has room for two).
static func shrink_label(l: Label) -> void:
	if not is_instance_valid(l) or l.size.x <= 0.0:
		return
	var top := int(l.get_meta("fit_fs", 14))
	var f := l.get_theme_font("font")
	var fs := top
	while fs > top - 2 and f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > l.size.x:
		fs -= 1
	var two := f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > l.size.x
	if two:
		fs = top - 1
	if l.get_theme_font_size("font_size") != fs:
		l.add_theme_font_size_override("font_size", fs)
	var mode := TextServer.AUTOWRAP_WORD_SMART if two else TextServer.AUTOWRAP_OFF
	if l.autowrap_mode != mode:
		l.autowrap_mode = mode
		l.clip_text = not two
		l.max_lines_visible = 2 if two else -1
		l.add_theme_constant_override("line_spacing", -4 if two else 0)
	var h := ceilf(f.get_height(fs) * 2.0 - 4.0) if two else 0.0
	if l.custom_minimum_size.y != h:
		l.custom_minimum_size.y = h

## The wood tile behind a Row / VideoRow button; pressed, it darkens a touch.
static func _row_face(b: Button) -> GamePanel:
	for k in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(k, StyleBoxEmpty.new())
	var face := GameUI.tile(16.0, 0.0)
	face.name = "Face"
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(face)
	face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.button_down.connect(func(): face.modulate = Color(0.85, 0.82, 0.8))
	b.button_up.connect(func(): face.modulate = Color.WHITE)
	return face

## Ready: the tile wears a gold rim.
static func _row_look(face: GamePanel, on: bool) -> void:
	face.border = 3.0 if on else 2.0
	face.border_color = Palette.GL_TITLE if on else Palette.GL_TILE_RIM

## A row's content over its tile: the disc, the title (outlined white) over the note (cream). [content, note label]
static func _row_content(b: Button, title: String, icon_path: String, look: String, note: String) -> Array:
	var content := UIKit.hbox(UIKit.SPACE.md)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.offset_left = 10; content.offset_right = -12
	b.add_child(content)
	var ic := RewardsSheet.disc(icon_path, look, 50.0, 34.0)
	content.add_child(ic)
	var col := UIKit.vbox(0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(col)
	var t := GameUI.outlined(title, 19, GameUI.TEXT, 2)
	t.name = "Title"
	col.add_child(t)
	var n := GameUI.text(note, 14)
	col.add_child(n)
	RewardsSheet._fit_text(t, n, ic, b)
	return [content, n]

## The disc colour of a row ("spin", "daily", "free", "missions", the video kinds).
static func disc_look(id: String) -> String:
	match id:
		"spin", "gems":
			return "purple"
		"daily":
			return "teal"
		"free":
			return "blue"
		"missions", "reroll":
			return "green"
	return "teal"


## A reward row: one button (a wood tile, the gold rim = ready); the action on the right is drawn, not tappable itself.
class Row extends Button:
	var id := ""
	var go: Button                       # Spin / Claim (ready)
	var wait: PanelContainer             # the countdown chip (not ready)
	var wait_label: Label
	var face: GamePanel
	var _content: HBoxContainer
	var _shake_tw: Tween
	var _lit := false                    # wearing the gold rim (ready)

	func _init(id_: String, title: String, icon_path: String, action: String, note: String) -> void:
		id = id_
		name = id_.capitalize()
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(0, 72)
		face = RewardsSheet._row_face(self)
		UIKit.wire_press(self)
		_content = RewardsSheet._row_content(self, title, icon_path, RewardsSheet.disc_look(id_), note)[0]
		# Go (on to another popup): teal; anything that pays out right here: gold
		go = GameUI.button(action, "teal" if id_ == "missions" or action == L10n.t("Go") else "gold", "sm")
		go.name = "Go"
		go.mouse_filter = Control.MOUSE_FILTER_IGNORE         # the whole row is the button
		go.size_flags_horizontal = Control.SIZE_SHRINK_END
		go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		go.custom_minimum_size.x = 84
		_content.add_child(go)
		RewardsSheet.fit_game(go, 12)
		wait = RewardsSheet.wait_chip()
		wait_label = wait.get_node("Text")
		_content.add_child(wait)
		wait.visible = false

	## Ready: the Spin / Claim button; else the countdown ("in 13h 20m", "in 3:53:09").
	func set_state(is_ready: bool, countdown: String) -> void:
		if is_ready != _lit:
			_lit = is_ready
			RewardsSheet._row_look(face, is_ready)
		go.visible = is_ready
		wait.visible = not is_ready
		var t := tr("in %s") % countdown if countdown != "" else ""
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


## A "Free with a video" row: disc, title, "N left today", and a teal Watch button (the whole row is the button).
class VideoRow extends Button:
	var kind := ""
	var go: Button
	var wait: PanelContainer
	var wait_label: Label
	var note: Label
	var face: GamePanel
	var _base_note := ""

	func _init(kind_: String, title: String, icon_path: String, note_: String) -> void:
		kind = kind_
		_base_note = note_
		name = "Video_" + kind_
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(0, 72)
		face = RewardsSheet._row_face(self)
		UIKit.wire_press(self)
		var parts := RewardsSheet._row_content(self, title, icon_path, RewardsSheet.disc_look(kind_), note_)
		var content: HBoxContainer = parts[0]
		note = parts[1]
		note.name = "Note"
		go = GameUI.button(tr("Watch"), "teal", "sm")
		go.name = "Go"
		go.mouse_filter = Control.MOUSE_FILTER_IGNORE
		go.size_flags_horizontal = Control.SIZE_SHRINK_END
		go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		go.custom_minimum_size.x = 84
		content.add_child(go)
		RewardsSheet.fit_game(go, 12)
		wait = RewardsSheet.wait_chip()
		wait_label = wait.get_node("Text")
		content.add_child(wait)
		wait.visible = false

	## n: videos left today (-1 = not known yet). `extra` follows the count on the note line.
	func set_left(n: int, extra: String, can_watch: bool) -> void:
		var done := n == 0
		go.visible = not done
		wait.visible = done
		wait_label.text = tr("Done today")
		note.text = ((tr("%d left today") % n) if n > 0 else (tr("Come back tomorrow") if done else _base_note)) + extra
		RewardsSheet.shrink_label(note)
		go.text = tr("Watch")
		go.disabled = not can_watch

	func set_busy(on: bool) -> void:
		go.text = "…" if on else tr("Watch")
		disabled = on
