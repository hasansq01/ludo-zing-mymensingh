class_name LobbySheet
extends Sheet
## A friends room before the match (PROTOCOL.md `lobby`): the big room code with Copy and Share (Share opens the
## phone's share sheet with an invite line, or copies it where there is none), the game (Ludo / Snakes & Ladders: lobby.settings.game),
## the members in join order (avatar, level, name, online dot, the seat colour they will play), the house rules
## (Ludo only, one grouped card as in Settings) and the way out. All but the way out scroll; on a phone 4 members and
## the rules don't fit, so the sheet shows the scroll_hint chevron while there is more below.
##   Host:   the game, Teams (2 v 2) (only with exactly 4 players), Start game (needs 2 or more). ("Ask before
##           pairing" is not a room rule: everyone plays their own Settings choice.)
##   Others: the same choices, read only, and "Waiting for host…".
## Leave (and Back) asks first. The sheet has no close button: leaving is a choice, not a dismissal.
##
##   var s := LobbySheet.new(code, my_member_id)
##   s.update(lobby_msg, is_host)               # every `lobby` message
##   s.set_status("reconnecting")               # NetClient.status
##   s.settings_changed.connect(func(teams): ...); s.start_pressed.connect(...); s.leave_pressed.connect(...)
##   s.game_changed.connect(func(game): ...)    # the host picked "ludo" | "sl"

signal settings_changed(teams: bool)
signal game_changed(game: String)
signal start_pressed
signal leave_pressed

const AVA := 40.0
const MAX := 4

var code := ""
var me_id := ""
var host := false
var members: Array = []
var teams := false
var game := "ludo"

var code_label: Label
var copy_button: Button
var share_button: Button
var start_button: Button
var leave_button: Button
var teams_switch: SettingsSheet.Switch
var game_picker: HBoxContainer
var _rules_cap: Control
var count_label: Label
var note: Label
var status_pill: PanelContainer
var _list: VBoxContainer
var _teams_row: Control
var _rules_card: Control
var _teams_note: Label
var _quiet := false                       # setting the switches from a lobby message: don't echo it back


func _init(code_: String, me_id_ := "", game_ := "ludo") -> void:
	code = code_
	me_id = me_id_
	game = game_ if game_ in ["ludo", "sl"] else "ludo"
	super(L10n.t("Friends room"), UIKit.W.form, false, Sheet.LOOK_PM)
	dismissable = false
	back_action = func(): leave_pressed.emit()
	set_kicker(_kicker_text())
	body.add_theme_constant_override("separation", UIKit.SPACE.md)
	status_pill = _status_pill()
	body.add_child(status_pill)
	var box := add_scroll_body(UIKit.SPACE.sm)
	box.add_child(UIKit.margin(_code_card(), 0, 0, 0, UIKit.SPACE.xs))   # scrolls away on a short screen (LO-03)
	box.add_child(UIKit.caption(tr("Game")))
	game_picker = UIKit.segmented([["ludo", tr("Ludo")], ["sl", tr("Snakes & Ladders")]], game, func(v):
		if _quiet or not host or str(v) == game:
			return
		game = str(v)
		game_changed.emit(game)
		_refresh(), "sm")
	game_picker.name = "Game"
	UIKit.fit_segmented(game_picker)                  # "Snakes & Ladders" gets the room it needs before anything shrinks
	box.add_child(game_picker)
	game_picker.mouse_filter = Control.MOUSE_FILTER_PASS    # a guest's (untappable) picker still answers a tap
	game_picker.gui_input.connect(func(e: InputEvent) -> void:
		if not host and Sheet._is_tap(e):
			UIKit.deny(self, tr("Only the host can pick the game."), game_picker))
	var head := UIKit.hbox(UIKit.SPACE.xs)
	var cap := UIKit.caption(tr("Players"))
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(cap)
	count_label = UIKit.label("", UIKit.FS.small, Palette.MUTED, UIKit.font_body(900, true), HORIZONTAL_ALIGNMENT_RIGHT)
	count_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(count_label)
	box.add_child(head)
	_list = UIKit.vbox(UIKit.SPACE.sm)
	box.add_child(_list)
	_rules_cap = UIKit.caption(tr("House rules"))
	box.add_child(_rules_cap)
	# one grouped card with a divider, as Settings' House rules
	var rules := _rules_group()
	teams_switch = SettingsSheet.Switch.new(false)
	teams_switch.name = "Teams"
	teams_switch.toggled.connect(func(_on: bool): _changed())
	UIKit.deny_disabled(teams_switch, func() -> String:
		return tr("Only the host can change the rules.") if not host else tr("Teams need exactly 4 players."))
	_teams_row = _rule_row(tr("Teams (2 v 2)"), tr("Red + Yellow vs Green + Blue"), teams_switch)
	_teams_note = _teams_row.find_child("Note", true, false) as Label
	rules.add_child(_teams_row)
	# ("Ask before pairing" is not a room rule: everyone plays their own Settings choice)
	_rules_card = rules.get_parent() as Control
	box.add_child(_rules_card)
	scroll_hint = true                    # 4 players and the rules don't fit a phone: show that the list goes on
	note = UIKit.paragraph("", UIKit.FS.body, Palette.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	note.name = "Note"
	body.add_child(UIKit.margin(note, 0, UIKit.SPACE.xs, 0, 0))   # clear of the scroll fade above it
	leave_button = UIKit.btn(tr("Leave"), "ghost", "md")
	leave_button.name = "Leave"
	leave_button.pressed.connect(func(): leave_pressed.emit())
	start_button = UIKit.btn(tr("Start game"), "honey", "md")
	start_button.name = "Start"
	start_button.pressed.connect(func():
		if not start_button.disabled:
			start_pressed.emit())
	UIKit.deny_disabled(start_button, func() -> String:         # why the game can't start yet
		if not host:
			return tr("Waiting for the host to start the game.")
		if status_pill.visible:
			return tr("Reconnecting. Hold on a moment.")
		if members.size() < 2:
			return tr("Wait for a friend to join first.")
		return tr("Teams need exactly 4 players."))
	for b: Button in [leave_button, start_button]:
		UIKit.fit_text(b, 12)
	var row := add_row([leave_button, start_button])
	leave_button.size_flags_stretch_ratio = 0.7
	row.name = "Actions"
	fit(0.92)
	_refresh()


# ---------- pieces ----------

## The room code in big letters ("K7Q X2M") with Copy and Share beside it, one row.
func _code_card() -> Control:
	var p := PanelContainer.new()
	var st := UIKit.box(Palette.PANE, UIKit.R.lg, UIKit.BW.line, Palette.ROW_EDGE)
	UIKit.pad(st, UIKit.PAD.pane, UIKit.SPACE.sm)
	p.add_theme_stylebox_override("panel", st)
	var h := UIKit.hbox(UIKit.SPACE.sm)
	var col := UIKit.vbox(0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_child(UIKit.eyebrow(tr("Room code")))
	code_label = UIKit.label(spaced(code), UIKit.FS.title, Palette.INK, UIKit.font_display())
	code_label.name = "Code"
	code_label.add_theme_constant_override("outline_size", 0)
	col.add_child(code_label)
	h.add_child(col)
	var btns := UIKit.hbox(UIKit.SPACE.sm)
	btns.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	copy_button = UIKit.button(tr("Copy"), "white", "sm")
	copy_button.name = "Copy"
	copy_button.pressed.connect(copy_code)
	share_button = UIKit.button(tr("Share"), "teal", "sm")
	share_button.name = "Share"
	share_button.pressed.connect(share)
	for b: Button in [copy_button, share_button]:
		btns.add_child(b)
	var stack := UIKit.vbox(UIKit.SPACE.xs)
	stack.add_child(h)
	p.add_child(stack)
	# beside the code on a normal card, under it on a narrow one (< 340 px: they don't fit in one row)
	var place := func(narrow: bool):
		var to: Control = stack if narrow else h
		if btns.get_parent() != to:
			if btns.get_parent():
				btns.get_parent().remove_child(btns)
			to.add_child(btns)
		for b: Button in [copy_button, share_button]:
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL if narrow else Control.SIZE_FILL
	var tree := Engine.get_main_loop() as SceneTree       # the card isn't in the tree yet: ask the screen
	place.call(tree != null and minf(UIKit.W.form, tree.root.get_visible_rect().size.x - 2.0 * UIKit.GUTTER) < NARROW_W)
	narrow_changed.connect(place)
	return p

## "K7QX2M" -> "K7Q X2M" (easier to read out and to type).
static func spaced(c: String) -> String:
	return c.substr(0, 3) + " " + c.substr(3) if c.length() == 6 else c

## The room line of the invite (Share adds the store link).
static func invite_text(c: String) -> String:
	return L10n.t("Join my Ludo Zing room: %s") % c

func _status_pill() -> PanelContainer:
	var p := PanelContainer.new()
	p.name = "Status"
	var st := UIKit.box(Palette.HONEY_TINT, UIKit.R.pill, UIKit.BW.line, Palette.HONEY_TINT_EDGE)
	UIKit.pad(st, UIKit.SPACE.md, UIKit.SPACE.xs)
	p.add_theme_stylebox_override("panel", st)
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var l := UIKit.label(tr("Reconnecting…"), UIKit.FS.label, Palette.ON_HONEY, UIKit.font_body(900), HORIZONTAL_ALIGNMENT_CENTER)
	l.name = "Text"
	p.add_child(l)
	p.visible = false
	return p

## The house rules' row card (Settings' grouped look: one card, the lines split by a divider); returns its column.
func _rules_group() -> VBoxContainer:
	var st := UIKit.surface("row").duplicate() as StyleBoxFlat
	st.content_margin_top = 0
	st.content_margin_bottom = UIKit.LIP.md - UIKit.BW.line
	st.content_margin_left = 14
	st.content_margin_right = 10
	var p := PanelContainer.new()
	p.name = "Rules"
	p.add_theme_stylebox_override("panel", st)
	var col := UIKit.vbox(0)
	p.add_child(col)
	return col

func _rule_divider() -> ColorRect:
	var d := ColorRect.new()
	d.color = Palette.ROW_EDGE
	d.custom_minimum_size = Vector2(0, 2)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return d

## One rule line (as SettingsSheet._line): the title and its note left, the switch right, 56 px tall.
func _rule_row(title_: String, sub: String, sw: Button) -> Control:
	var h := UIKit.hbox(UIKit.SPACE.md)
	h.custom_minimum_size.y = SettingsSheet.ROW_H
	var v := UIKit.vbox(1)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.add_child(UIKit.label(title_, UIKit.FS.body_l, Palette.INK, UIKit.font_body(800)))
	var n := UIKit.paragraph(sub, UIKit.FS.small, Palette.SUB)          # wraps: never widens the card
	n.name = "Note"
	v.add_child(n)
	h.add_child(v)
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(sw)
	return UIKit.margin(h, 0, 6, 0, 6)

## One member (or an open seat when m is empty).
func _member_row(m: Dictionary, index: int) -> Control:
	var empty := m.is_empty()
	var mine := not empty and NetClient.id_str(m.get("id", "")) == me_id
	var c := int(m.get("color", -1)) if not empty else -1
	if c < 0 and not empty:
		var cols := NetFake.Room.seat_colors(game, maxi(2, members.size()))
		c = cols[index] if index < cols.size() else -1
	var row := UIKit.hbox(UIKit.SPACE.sm)
	var p := UIKit.list_row(row, "empty" if empty else ("you" if mine else ""), Palette.PLAYER[c] if mine and c >= 0 else Color.TRANSPARENT)
	if empty:
		var ph := Control.new()
		ph.custom_minimum_size = Vector2(AVA, AVA)
		ph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ph.draw.connect(func():
			var r := AVA / 2.0
			ph.draw_arc(Vector2(r, r), r - 2.0, 0.0, TAU, 40, Palette.LINE_STRONG, 2.0, true))
		row.add_child(ph)
		var more := MAX - members.size()
		var t := UIKit.label(tr("Waiting for friends to join…") if more > 1 else tr("Waiting for one more friend…"), UIKit.FS.body, Palette.MUTED, UIKit.font_body(800))
		t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		t.clip_text = true
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	var lv := LevelBadge.new(maxi(1, int(m.get("level", 1))), "xs")
	lv.name = "Level"
	lv.position = Vector2(-2.0, AVA - lv.px + 2.0)       # inside the avatar's box, bottom left
	lv.size = Vector2(lv.px, lv.px)
	av.add_child(lv)
	row.add_child(av)
	var nm := UIKit.label((tr("%s (you)") % L10n.seat_name(str(m.get("name", "Player")))) if mine else L10n.seat_name(str(m.get("name", "Player"))), UIKit.FS.h3, Palette.INK, UIKit.font_body(900))
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.clip_text = true
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(nm)
	if NetClient.id_str(m.get("id", "")) == _host_id:
		var tag := UIKit.tag(tr("Host"), "honey")
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(tag)
	if not bool(m.get("online", true)):
		var off := UIKit.tag(tr("Away"), "white")
		off.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(off)
	if c >= 0:
		var seat := SetupSheet.SeatDot.new(PlayerTile._pref("colorblind"))
		seat.custom_minimum_size = Vector2(28, 28)
		seat.skin = str(m.get("pawn", ""))           # their pawn skin, as it will stand on the board
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
	game = str(s.get("game", "ludo")) if str(s.get("game", "ludo")) in ["ludo", "sl"] else "ludo"
	set_kicker(_kicker_text())
	_refresh()

## NetClient.status: "reconnecting" shows the pill and holds the buttons.
func set_status(st: String) -> void:
	status_pill.visible = st in ["reconnecting", "connecting"]
	(status_pill.get_node("Text") as Label).text = tr("Connecting…") if st == "connecting" else tr("Reconnecting…")
	_refresh()

func can_start() -> bool:
	return host and members.size() >= 2 and (game != "ludo" or not teams or members.size() == 4) and not status_pill.visible

func _kicker_text() -> String:
	return tr("Snakes & Ladders online") if game == "sl" else tr("Ludo online")

func _refresh() -> void:
	for ch in _list.get_children():
		_list.remove_child(ch)
		ch.queue_free()
	for k in members.size():
		_list.add_child(_member_row(members[k], k))
	if members.size() < MAX:
		_list.add_child(_member_row({}, members.size()))   # one open-seat row, not one per seat (the card stays short)
	count_label.text = tr("%d of %d") % [members.size(), MAX]
	_quiet = true
	for b: Button in game_picker.get_children():
		b.set_pressed_no_signal(str(b.get_meta("value")) == game)
		# not the host: the same picker showing the host's choice, just not tappable (a disabled Button would draw the
		# theme's grey disabled box over both halves, which reads as broken)
		b.mouse_filter = Control.MOUSE_FILTER_STOP if host else Control.MOUSE_FILTER_IGNORE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if host else Control.CURSOR_ARROW
	var ludo := game == "ludo"
	for r: Control in [_rules_cap, _rules_card]:
		r.visible = ludo
	teams_switch.set_pressed_no_signal(teams)
	teams_switch._set_t(1.0 if teams else 0.0)
	_quiet = false
	var four := members.size() == 4
	teams_switch.disabled = not host or (not four and not teams)
	teams_switch.modulate.a = 1.0 if not teams_switch.disabled else 0.5
	_teams_note.text = tr("Red + Yellow vs Green + Blue") if four else tr("Needs exactly 4 players")
	start_button.disabled = not can_start()
	start_button.text = tr("Start game") if host else tr("Waiting for host…")
	UIKit.set_kind(start_button, "honey" if host else "off")
	UIKit.refit_text(start_button)            # after set_kind (it resets the size): the guest's text fits at 320 px too
	if host:
		start_button.disabled = not can_start()
	else:
		start_button.disabled = true
	if members.size() < 2:
		note.text = tr("Share the code. The game can start when a friend joins.")
	elif host and ludo and teams and not four:
		note.text = tr("Teams need exactly 4 players.")
	elif host:
		note.text = tr("Everyone’s here? Start when you’re ready.")
	else:
		note.text = tr("The host starts the game.")

func _changed() -> void:
	if _quiet or not host:
		return
	teams = teams_switch.button_pressed
	settings_changed.emit(teams)
	_refresh()

func copy_code() -> void:
	DisplayServer.clipboard_set(code)
	Toast.show(self, tr("Code copied"), null, 1.6, "info")

## The phone's share sheet with the invite (room line and store link); without one, copied with a toast. Returns
## "shared" | "copied" (Share.send).
func share() -> String:
	return Share.send(self, Share.invite_text(code))


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
