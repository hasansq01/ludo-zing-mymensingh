class_name LobbySheet
extends Sheet
## A friends room before the match (PROTOCOL.md `lobby`): the big room code with Copy and Share (Share copies an
## invite line; Android has no share intent from here), the members in join order (avatar, name, online dot, the
## seat colour they will play), the house rules and the way out.
##   Host:   Teams (2 v 2) (only with exactly 4 players), Ask before pairing, Start game (needs 2 or more).
##   Others: the same rules, read only, and "Waiting for host…".
## Leave (and Back) asks first. The sheet has no close button: leaving is a choice, not a dismissal.
##
##   var s := LobbySheet.new(code, my_member_id)
##   s.update(lobby_msg, is_host)               # every `lobby` message
##   s.set_status("reconnecting")               # NetClient.status
##   s.settings_changed.connect(func(teams, pair_ask): ...); s.start_pressed.connect(...); s.leave_pressed.connect(...)

signal settings_changed(teams: bool, pair_ask: bool)
signal start_pressed
signal leave_pressed

const ROW_H := 50.0
const AVA := 40.0
const MAX := 4

var code := ""
var me_id := ""
var host := false
var members: Array = []
var teams := false
var pair_ask := false

var code_label: Label
var copy_button: Button
var share_button: Button
var start_button: Button
var leave_button: Button
var teams_switch: SettingsSheet.Switch
var pair_switch: SettingsSheet.Switch
var count_label: Label
var note: Label
var status_pill: PanelContainer
var _list: VBoxContainer
var _teams_row: Control
var _teams_note: Label
var _quiet := false                       # setting the switches from a lobby message: don't echo it back


func _init(code_: String, me_id_ := "") -> void:
	code = code_
	me_id = me_id_
	super("Friends room", UIKit.W.form, false, Sheet.LOOK_PM)
	dismissable = false
	back_action = func(): leave_pressed.emit()
	set_kicker("Ludo online")
	body.add_theme_constant_override("separation", UIKit.SPACE.md)
	status_pill = _status_pill()
	body.add_child(status_pill)
	body.add_child(_code_card())
	var box := add_scroll_body(UIKit.SPACE.sm)
	var head := UIKit.hbox(UIKit.SPACE.xs)
	var cap := UIKit.caption("Players")
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(cap)
	count_label = UIKit.label("", UIKit.FS.small, Palette.MUTED, UIKit.font_body(900, true), HORIZONTAL_ALIGNMENT_RIGHT)
	count_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(count_label)
	box.add_child(head)
	_list = UIKit.vbox(UIKit.SPACE.xs + 2)
	box.add_child(_list)
	box.add_child(UIKit.margin(UIKit.caption("House rules"), 0, UIKit.SPACE.xs, 0, 0))
	teams_switch = SettingsSheet.Switch.new(false)
	teams_switch.name = "Teams"
	teams_switch.toggled.connect(func(_on: bool): _changed())
	_teams_row = _rule_row("Teams (2 v 2)", "Red + Yellow vs Green + Blue", teams_switch)
	_teams_note = _teams_row.find_child("Note", true, false) as Label
	box.add_child(_teams_row)
	pair_switch = SettingsSheet.Switch.new(false)
	pair_switch.name = "PairAsk"
	pair_switch.toggled.connect(func(_on: bool): _changed())
	box.add_child(_rule_row("Ask before pairing", "You choose when two pawns meet", pair_switch))
	note = UIKit.paragraph("", UIKit.FS.body, Palette.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	note.name = "Note"
	body.add_child(note)
	leave_button = UIKit.btn("Leave", "ghost", "md")
	leave_button.name = "Leave"
	leave_button.pressed.connect(func(): leave_pressed.emit())
	start_button = UIKit.btn("Start game", "honey", "md")
	start_button.name = "Start"
	start_button.pressed.connect(func():
		if not start_button.disabled:
			start_pressed.emit())
	for b: Button in [leave_button, start_button]:
		UIKit.fit_text(b, 14)
	var row := add_row([leave_button, start_button])
	leave_button.size_flags_stretch_ratio = 0.7
	row.name = "Actions"
	fit()
	_refresh()


# ---------- pieces ----------

## The room code in big letters ("K7Q X2M") with Copy and Share under it.
func _code_card() -> Control:
	var p := PanelContainer.new()
	var st := UIKit.box(Palette.PANE, UIKit.R.lg, UIKit.BW.line, Palette.ROW_EDGE)
	UIKit.pad(st, UIKit.PAD.pane, UIKit.SPACE.sm)
	p.add_theme_stylebox_override("panel", st)
	var col := UIKit.vbox(UIKit.SPACE.xs)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	var cap := UIKit.eyebrow("Room code")
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(cap)
	code_label = UIKit.label(spaced(code), UIKit.FS.hero + 4, Palette.INK, UIKit.font_display(), HORIZONTAL_ALIGNMENT_CENTER)
	code_label.name = "Code"
	code_label.add_theme_constant_override("outline_size", 0)
	col.add_child(code_label)
	var row := UIKit.hbox(UIKit.SPACE.sm)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	copy_button = UIKit.button("Copy", "white", "sm")
	copy_button.name = "Copy"
	copy_button.pressed.connect(copy_code)
	share_button = UIKit.button("Share invite", "teal", "sm")
	share_button.name = "Share"
	share_button.pressed.connect(share)
	for b: Button in [copy_button, share_button]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	col.add_child(row)
	p.add_child(col)
	return p

## "K7QX2M" -> "K7Q X2M" (easier to read out and to type).
static func spaced(c: String) -> String:
	return c.substr(0, 3) + " " + c.substr(3) if c.length() == 6 else c

## The line Share copies.
static func invite_text(c: String) -> String:
	return "Join my Ludo Zing room: %s" % c

func _status_pill() -> PanelContainer:
	var p := PanelContainer.new()
	p.name = "Status"
	var st := UIKit.box(Palette.HONEY_TINT, UIKit.R.pill, UIKit.BW.line, Palette.HONEY_TINT_EDGE)
	UIKit.pad(st, UIKit.SPACE.md, UIKit.SPACE.xs)
	p.add_theme_stylebox_override("panel", st)
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var l := UIKit.label("Reconnecting…", UIKit.FS.label, Palette.ON_HONEY, UIKit.font_body(900), HORIZONTAL_ALIGNMENT_CENTER)
	l.name = "Text"
	p.add_child(l)
	p.visible = false
	return p

func _rule_row(title_: String, sub: String, sw: Button) -> Control:
	var p := PanelContainer.new()
	var st := UIKit.box(Palette.ROW, UIKit.R.md, UIKit.BW.line, Palette.ROW_EDGE)
	UIKit.pad(st, UIKit.PAD.row, UIKit.SPACE.xxs)
	p.add_theme_stylebox_override("panel", st)
	var h := UIKit.hbox(UIKit.SPACE.sm)
	var v := UIKit.vbox(0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.add_child(UIKit.label(title_, UIKit.FS.body_l, Palette.INK, UIKit.font_body(800)))
	var n := UIKit.label(sub, UIKit.FS.small, Palette.SUB, UIKit.font_body(700))
	n.name = "Note"
	v.add_child(n)
	h.add_child(v)
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(sw)
	p.add_child(h)
	return p

## One member (or an open seat when m is empty).
func _member_row(m: Dictionary, index: int) -> Control:
	var p := PanelContainer.new()
	var empty := m.is_empty()
	var mine := not empty and NetClient.id_str(m.get("id", "")) == me_id
	var c := int(m.get("color", -1)) if not empty else -1
	if c < 0 and not empty:
		var cols := NetFake.Room.colors_for(maxi(2, members.size()))
		c = cols[index] if index < cols.size() else -1
	var st := UIKit.box(Color.WHITE if not empty else Color(Palette.CHIP, 0.55), UIKit.R.md, UIKit.BW.line,
		Palette.PLAYER[c] if mine and c >= 0 else Palette.ROW_EDGE)
	UIKit.pad(st, UIKit.SPACE.sm, UIKit.SPACE.xs)
	if empty:
		st.draw_center = true
		st.border_color = Palette.LINE_STRONG
	p.add_theme_stylebox_override("panel", st)
	p.custom_minimum_size.y = ROW_H
	var row := UIKit.hbox(UIKit.SPACE.sm)
	p.add_child(row)
	if empty:
		var ph := Control.new()
		ph.custom_minimum_size = Vector2(AVA, AVA)
		ph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ph.draw.connect(func():
			var r := AVA / 2.0
			ph.draw_arc(Vector2(r, r), r - 2.0, 0.0, TAU, 40, Palette.LINE_STRONG, 2.0, true))
		row.add_child(ph)
		var more := MAX - members.size()
		var t := UIKit.label("Waiting for friends to join…" if more > 1 else "Waiting for one more friend…", UIKit.FS.body, Palette.MUTED, UIKit.font_body(800))
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(t)
		return p
	var av := Control.new()
	av.custom_minimum_size = Vector2(AVA, AVA)
	av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var a: Control = Collection.make_avatar(AVA) if mine else Collection.make_avatar_of(_avatar_id(m, c), str(m.get("frame", "classic")), AVA)
	a.mouse_filter = Control.MOUSE_FILTER_IGNORE
	av.add_child(a)
	var dot := OnlineDot.new(bool(m.get("online", true)))
	dot.position = Vector2(AVA - 11.0, AVA - 11.0)
	av.add_child(dot)
	row.add_child(av)
	var nm := UIKit.label(str(m.get("name", "Player")) + (" (you)" if mine else ""), UIKit.FS.h3, Palette.INK, UIKit.font_body(900))
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.clip_text = true
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(nm)
	if NetClient.id_str(m.get("id", "")) == _host_id:
		var tag := UIKit.tag("Host", "honey")
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(tag)
	if not bool(m.get("online", true)):
		var off := UIKit.tag("Away", "white")
		off.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(off)
	if c >= 0:
		var seat := SetupSheet.SeatDot.new(PlayerTile._pref("colorblind"))
		seat.custom_minimum_size = Vector2(28, 28)
		seat.set_color(c)
		row.add_child(seat)
	return p

static func _avatar_id(m: Dictionary, c: int) -> String:
	var id := str(m.get("avatar", ""))
	if id == "" or Collection.avatar(id).is_empty():
		return PlayerTile.PAWN_AVATARS[posmod(c, 4)]
	return id

var _host_id := ""

# ---------- state ----------

## A `lobby` message: members, host, settings. you_host: NetClient.is_host().
func update(msg: Dictionary, you_host: bool) -> void:
	host = you_host
	_host_id = NetClient.id_str(msg.get("host", ""))
	if str(msg.get("code", "")) != "":
		code = str(msg.code)
		code_label.text = spaced(code)
	members = (msg.get("members", []) as Array).duplicate(true) if msg.get("members") is Array else []
	var s: Dictionary = msg.get("settings", {}) if msg.get("settings") is Dictionary else {}
	teams = bool(s.get("teams", false))
	pair_ask = bool(s.get("pair_ask", false))
	_refresh()

## NetClient.status: "reconnecting" shows the pill and holds the buttons.
func set_status(st: String) -> void:
	status_pill.visible = st in ["reconnecting", "connecting"]
	(status_pill.get_node("Text") as Label).text = "Connecting…" if st == "connecting" else "Reconnecting…"
	_refresh()

func can_start() -> bool:
	return host and members.size() >= 2 and (not teams or members.size() == 4) and not status_pill.visible

func _refresh() -> void:
	for ch in _list.get_children():
		_list.remove_child(ch)
		ch.queue_free()
	for k in members.size():
		_list.add_child(_member_row(members[k], k))
	if members.size() < MAX:
		_list.add_child(_member_row({}, members.size()))   # one open-seat row, not one per seat (the card stays short)
	count_label.text = "%d of %d" % [members.size(), MAX]
	_quiet = true
	teams_switch.set_pressed_no_signal(teams)
	teams_switch._set_t(1.0 if teams else 0.0)
	pair_switch.set_pressed_no_signal(pair_ask)
	pair_switch._set_t(1.0 if pair_ask else 0.0)
	_quiet = false
	var four := members.size() == 4
	teams_switch.disabled = not host or (not four and not teams)
	pair_switch.disabled = not host
	for sw: Button in [teams_switch, pair_switch]:
		sw.modulate.a = 1.0 if not sw.disabled else 0.5
	_teams_note.text = "Red + Yellow vs Green + Blue" if four else "Needs exactly 4 players"
	start_button.disabled = not can_start()
	start_button.text = "Start game" if host else "Waiting for host…"
	UIKit.set_kind(start_button, "honey" if host else "off")
	if host:
		start_button.disabled = not can_start()
	else:
		start_button.disabled = true
	if members.size() < 2:
		note.text = "Share the code. The game can start when a friend joins."
	elif host and teams and not four:
		note.text = "Teams need exactly 4 players."
	elif host:
		note.text = "Everyone’s here? Start when you’re ready."
	else:
		note.text = "The host starts the game."

func _changed() -> void:
	if _quiet or not host:
		return
	teams = teams_switch.button_pressed
	pair_ask = pair_switch.button_pressed
	settings_changed.emit(teams, pair_ask)
	_refresh()

func copy_code() -> void:
	DisplayServer.clipboard_set(code)
	Toast.show(self, "Code copied", null, 1.6, "info")

func share() -> void:
	DisplayServer.clipboard_set(invite_text(code))
	Toast.show(self, "Invite copied. Paste it in a chat.", null, 2.0, "info")


## The green / grey presence dot on an avatar's corner.
class OnlineDot extends Control:
	var on := true

	func _init(on_ := true) -> void:
		on = on_
		custom_minimum_size = Vector2(14, 14)
		size = Vector2(14, 14)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_circle(Vector2(7, 7), 7.0, Color.WHITE, true, -1.0, true)
		draw_circle(Vector2(7, 7), 5.0, Palette.TEAL if on else Palette.TAN_DEEP, true, -1.0, true)
