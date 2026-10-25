class_name QuickSheet
extends Sheet
## Quick match (Home's QUICK MATCH, the result's Play again): pick a table (2 or 4 players, the last choice is
## preselected), then "Finding players…": a row of seats (yours first, the others searching: a soft pulse and a
## sweeping ring), the time waited and Cancel. When the server has seated everyone, reveal(seats, me) fills the
## seats one by one (avatar, name, level; every player looks the same) and emits revealed; the caller then opens
## the match. The sheet only shows; Online does the network work:
##
##   var s := QuickSheet.new("ludo", 2)
##   s.find.connect(func(players): ...)          # "Find players" (also Try again)
##   s.cancel_pressed.connect(...)               # Cancel, the X, Back, a backdrop tap while searching
##   s.open(app.sheet_layer)
##   s.set_searching(); s.set_queued(position, eta_s); s.set_matched()
##   await s.reveal(seats, my_colour)            # then the match
##   s.set_error("Online play is down for maintenance.")   # back to the picker with the message
## stage: "pick" | "searching" | "matched" | "found" | "error".

signal find(players: int)
signal cancel_pressed
signal revealed

const SLOT_GAP := 10.0
const REVEAL_STEP := 0.28                ## s between two players popping into their seats

var game := "ludo"
var players := 2
var stage := "pick"
var step_sec := REVEAL_STEP              ## 0: reveal at once (tests)
var hold_sec := 0.55                     ## how long the full table shows before revealed
var picker: HBoxContainer
var find_button: Button
var cancel_button: Button
var status_label: Label
var sub_label: Label
var note_label: Label
var slots_row: HBoxContainer
var slots: Array = []                    ## Slot
var _pick_box: Control
var _search_box: Control
var _started_ms := 0
var _eta := 0
var _t := 0.0


func _init(game_ := "ludo", players_ := 2) -> void:
	game = game_ if game_ in ["ludo", "sl"] else "ludo"
	players = players_ if players_ in [2, 4] else 2
	super("Quick match", UIKit.W.form, true, Sheet.LOOK_PM)
	dismissable = true
	back_action = func(): _cancel()
	set_kicker("Snakes & Ladders online" if game == "sl" else "Ludo online")
	body.add_theme_constant_override("separation", UIKit.SPACE.md)
	_build_pick()
	_build_search()
	note_label = UIKit.paragraph("", UIKit.FS.body, Palette.DANGER, HORIZONTAL_ALIGNMENT_CENTER)
	note_label.name = "Note"
	note_label.visible = false
	body.add_child(note_label)
	body.move_child(note_label, _pick_box.get_index())
	_show("pick")
	fit()
	set_process(true)

func _build_pick() -> void:
	_pick_box = UIKit.vbox(UIKit.SPACE.md)
	_pick_box.name = "Pick"
	var intro := UIKit.paragraph("Play people online. Pick a table and we’ll seat you in a few seconds.",
		UIKit.FS.body, Palette.SUB, HORIZONTAL_ALIGNMENT_CENTER)
	_pick_box.add_child(intro)
	_pick_box.add_child(UIKit.caption("Players"))
	picker = UIKit.segmented([[2, "2 players"], [4, "4 players"]], players, func(v): players = int(v))
	picker.name = "Players"
	_pick_box.add_child(picker)
	find_button = UIKit.button_with("Find players", UIKit.icon("perk_friends", 30), "honey", "lg")
	find_button.name = "Find"
	find_button.pressed.connect(func():
		if stage in ["pick", "error"]:
			find.emit(players))
	_pick_box.add_child(find_button)
	body.add_child(_pick_box)

func _build_search() -> void:
	_search_box = UIKit.vbox(UIKit.SPACE.sm)
	_search_box.name = "Search"
	status_label = UIKit.label("Finding players…", UIKit.FS.h1, Palette.INK, UIKit.font_display(), HORIZONTAL_ALIGNMENT_CENTER)
	status_label.name = "Status"
	status_label.add_theme_constant_override("outline_size", 0)
	_search_box.add_child(status_label)
	sub_label = UIKit.label("", UIKit.FS.label, Palette.MUTED, UIKit.font_body(800, true), HORIZONTAL_ALIGNMENT_CENTER)
	sub_label.name = "Sub"
	_search_box.add_child(sub_label)
	slots_row = UIKit.hbox(int(SLOT_GAP))
	slots_row.name = "Seats"
	slots_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_search_box.add_child(UIKit.margin(slots_row, 0, UIKit.SPACE.sm, 0, UIKit.SPACE.sm))
	cancel_button = UIKit.btn("Cancel", "ghost", "md")
	cancel_button.name = "Cancel"
	cancel_button.pressed.connect(_cancel)
	_search_box.add_child(cancel_button)
	body.add_child(_search_box)

func _show(s: String) -> void:
	stage = s
	_pick_box.visible = s in ["pick", "error"]
	_search_box.visible = not _pick_box.visible
	note_label.visible = s == "error" and note_label.text != ""
	cancel_button.visible = s in ["searching", "matched"]
	cancel_button.disabled = s != "searching" and s != "matched"
	find_button.text = ""
	var fl := find_button.find_child("Text", true, false) as Label
	if fl:
		fl.text = "Try again" if s == "error" else "Find players"
	if is_inside_tree():
		fit_now()

# ---------- states ----------

## Waiting in the queue: your seat and searching seats (n: the table size; default the picker's).
func set_searching(n := -1) -> void:
	if n in [2, 4]:
		players = n
	_started_ms = Time.get_ticks_msec()
	_eta = 0
	_build_slots()
	status_label.text = "Finding players…"
	_show("searching")
	_update_sub()

## queued {position, eta_s}: the rough wait.
func set_queued(_position: int, eta_s: int) -> void:
	_eta = maxi(0, eta_s)
	_update_sub()

## matched: a table was found; the room is being joined (the seats are revealed at the start).
func set_matched() -> void:
	status_label.text = "Players found!"
	_show("matched")
	sub_label.text = "Getting the table ready…"

## The players at the table pop into their seats one by one (yours stays first). Coroutine; emits revealed.
## seats: the server's seats [{color, name, avatar, frame, level}]; me: your colour.
func reveal(seats: Array, me: int) -> void:
	_show("found")
	status_label.text = "Players found!"
	sub_label.text = "Get ready…"
	var others := seats.filter(func(st): return int(st.get("color", -1)) != me)
	while slots.size() < others.size() + 1:
		var s := Slot.new(_slot_px())
		slots_row.add_child(s)
		slots.append(s)
	for st: Dictionary in seats:
		if int(st.get("color", -1)) == me and not slots.is_empty():
			(slots[0] as Slot).fill_you(int(st.get("level", (slots[0] as Slot).level)))
	for k in others.size():
		await _sleep(step_sec)
		if not is_inside_tree():
			return
		(slots[k + 1] as Slot).fill(others[k])
		UIKit.sfx("tap")
	await _sleep(hold_sec)
	revealed.emit()

## Back to the picker with a message (a refused or failed search).
func set_error(text: String) -> void:
	note_label.text = text
	_show("error")

func _cancel() -> void:
	if stage in ["searching", "matched"]:
		cancel_pressed.emit()
	close()

func on_back() -> void:
	_cancel()

func _build_slots() -> void:
	for s in slots:
		(s as Node).queue_free()
	slots = []
	for k in players:
		var s := Slot.new(_slot_px())
		slots_row.add_child(s)
		slots.append(s)
	(slots[0] as Slot).fill_you(Save.level_info(int(Save.profile.get("xp", 0))).level if _has_save() else 1)

func _slot_px() -> float:
	return 64.0 if players <= 2 else 52.0

func _has_save() -> bool:
	return Engine.get_main_loop() is SceneTree and (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Save") != null

func _process(delta: float) -> void:
	_t += delta
	if stage == "searching" and Engine.get_frames_drawn() % 10 == 0:
		_update_sub()

## "0:07 · usually about 6 s"
func _update_sub() -> void:
	if stage != "searching":
		return
	var sec := int((Time.get_ticks_msec() - _started_ms) / 1000.0) if _started_ms > 0 else 0
	var t := "%d:%02d" % [sec / 60, sec % 60]
	sub_label.text = t + (" · usually about %d s" % _eta if _eta > 0 and sec < _eta + 20 else "")

## Seconds waited so far (tests).
func elapsed() -> float:
	return (Time.get_ticks_msec() - _started_ms) / 1000.0 if _started_ms > 0 else 0.0

func _sleep(s: float) -> void:
	if s > 0.0 and is_inside_tree():
		await get_tree().create_timer(s).timeout


## One seat: a searching ring (a soft pulse and a sweeping arc) until a player sits in it; then the avatar, the
## name and the level star. Your seat says "You".
class Slot extends VBoxContainer:
	var px := 64.0
	var filled := false
	var level := 1
	var ring: Control
	var name_label: Label
	var _ava: Control
	var _badge: LevelBadge
	var _t := 0.0

	func _init(px_ := 64.0) -> void:
		px = px_
		add_theme_constant_override("separation", UIKit.SPACE.xs)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(px + 10.0, 0)
		ring = Control.new()
		ring.custom_minimum_size = Vector2(px + 8.0, px + 8.0)
		ring.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ring.draw.connect(_draw_ring)
		add_child(ring)
		name_label = UIKit.label("Searching", UIKit.FS.small, Palette.MUTED, UIKit.font_body(800), HORIZONTAL_ALIGNMENT_CENTER)
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.custom_minimum_size = Vector2(px + 10.0, 0)
		add_child(name_label)

	func fill_you(level_: int) -> void:
		_put(Collection.make_avatar(px), "You", level_)

	## A player in this seat: {name, avatar, frame, level, color}.
	func fill(st: Dictionary) -> void:
		var id := str(st.get("avatar", ""))
		var c := int(st.get("color", 0))
		var a: Control
		if id != "" and not Collection.avatar(id).is_empty():
			a = Collection.make_avatar_of(id, str(st.get("frame", "classic")) if str(st.get("frame", "")) != "" else "classic", px)
		else:
			a = PlayerTile.make_avatar(c, "human", px)
		_put(a, str(st.get("name", "Player")), int(st.get("level", 1)))
		UIKit.pop_in(ring, 0.24)

	func _put(a: Control, nm: String, level_: int) -> void:
		filled = true
		level = level_
		if _ava:
			_ava.queue_free()
		_ava = a
		_ava.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ava.position = Vector2(4, 4)
		_ava.size = Vector2(px, px)
		ring.add_child(_ava)
		if _badge == null:
			_badge = LevelBadge.new(level_, "xs" if px < 60.0 else "sm")
			ring.add_child(_badge)
		_badge.set_level(level_)
		_badge.position = Vector2(px + 8.0 - _badge.px + 2.0, px + 8.0 - _badge.px + 2.0)
		_badge.size = Vector2(_badge.px, _badge.px)
		name_label.text = nm
		name_label.add_theme_color_override("font_color", Palette.INK)
		name_label.add_theme_font_override("font", UIKit.font_body(900))
		name_label.add_theme_font_size_override("font_size", UIKit.FS.label)
		set_process(false)
		ring.queue_redraw()

	func _ready() -> void:
		set_process(not filled)

	func _process(delta: float) -> void:
		_t += delta
		ring.queue_redraw()

	func _draw_ring() -> void:
		var c := Vector2(px / 2.0 + 4.0, px / 2.0 + 4.0)
		var r := px / 2.0
		if filled:
			return
		var reduce := PlayerTile._pref("reduce_motion")
		var k := 0.5 + 0.5 * sin(_t * TAU / 1.6)
		ring.draw_circle(c, r, Color(Palette.CHIP, 0.9 if reduce else 0.7 + 0.3 * k), true, -1.0, true)
		ring.draw_arc(c, r - 1.5, 0.0, TAU, 48, Palette.LINE_STRONG, 2.0, true)
		if not reduce:
			var a0 := _t * TAU / 1.2
			ring.draw_arc(c, r - 1.5, a0, a0 + PI * 0.6, 24, Palette.HONEY_LIP, 3.0, true)
		var f := UIKit.font_display()
		var fs := int(px * 0.42)
		var w := f.get_string_size("?", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		ring.draw_string(f, c + Vector2(-w / 2.0, fs * 0.36), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(Palette.MUTED, 0.55))
