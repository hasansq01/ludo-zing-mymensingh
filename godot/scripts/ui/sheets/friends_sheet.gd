class_name FriendsSheet
extends Sheet
## "Play with friends" (Home, Ludo or Snakes & Ladders), in three folder tabs over one pane (as How to play):
##   Room     make a room and share the code, or join a friend's room with theirs. The code field takes the
##            6-character room code: typed or pasted text is upper-cased and cleaned to the code alphabet
##            (NetClient.clean_code), and Join stays off until the code is complete. The sheet only asks; the caller
##            (Online) does the network work and calls set_busy() / set_busy("") around it.
##   Friends  your friends list (one-way, like favourites: the people you added; they aren't told), each with Invite.
##   Recent   the last 30 people you played online with (friend rooms and quick matches), newest first, with when and
##            the game, and Invite.
## Every row has a star button before Invite: filled on a friend (a tap asks Remove from friends?), an outline on anyone
## else (a tap adds them at once; Social.star).
## The lists come from Social (server/PROTOCOL.md "Recent players, friends and invites"): Loading…, the offline note
## with Try again, an empty note saying how people get there, or the rows (UIKit.list_row: avatar in its frame with the
## level star, name, the line under it, Invite). Long-press a row to add the person to friends or remove them
## (Social.ask_friend) too. Invite asks Social, which brings them into the room you are in (in none, a new room is made
## first and its lobby opens, closing this sheet); the button then says "Invited", "Remind" after a minute without an answer, or "Not now" if they said so.
## invite mode (the lobby's "Invite friends"): only Friends and Recent, under the title "Invite friends".
##
##   var s := FriendsSheet.new("sl")           # the game a new room starts with (the host can change it in the lobby)
##   s.create_room.connect(...); s.join_room.connect(func(code): ...)
##   s.open(app.sheet_layer)
##   s.show_tab("recent")
## Tests: set `social` (a Social with http_fn) before opening.

signal create_room
signal join_room(code: String)

const FIXED_H := 620.0                   ## one card height for every tab
const AVA := 44.0

var code_edit: LineEdit
var create_button: Button
var join_button: Button
var paste_button: Button
var game := "ludo"
var invite_mode := false
var tab := "room"                        ## the tab on show: "room" | "friends" | "recent"
var social: Social                       ## the lists (default: Social.instance())
var lists := {}                          ## "friends" | "recent" -> the VBoxContainer of its rows
var list_state := ""                     ## what the lists show: "loading" | "offline" | "error" | "list"
var _tabs: TabStrip
var _panes := {}                         # key -> VBoxContainer
var _busy := ""
var _wired := false


func _init(game_ := "ludo", invite_mode_ := false) -> void:
	game = game_ if game_ in ["ludo", "sl"] else "ludo"
	invite_mode = invite_mode_
	super(L10n.t("Invite friends") if invite_mode else L10n.t("Play with friends"), UIKit.W.form, true, Sheet.LOOK_PM)
	set_kicker(tr("Snakes & Ladders online") if game == "sl" else tr("Ludo online"))
	var stack := UIKit.vbox(0)
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(stack)
	var items := [
		{key = "friends", text = tr("Friends"), icon = "ic_star"},
		{key = "recent", text = tr("Recent"), icon = "ic_reset"},
	]
	if not invite_mode:
		items.push_front({key = "room", text = tr("Room"), icon = "perk_friends"})
	tab = "room" if not invite_mode else "friends"
	_tabs = TabStrip.new(items, tab, "folder")
	_tabs.name = "Tabs"
	_tabs.picked.connect(show_tab)
	stack.add_child(UIKit.margin(_tabs, 0, UIKit.SPACE.xs, 0, 0))
	var pane := PanelContainer.new()
	var ps := TabStrip.pane_style("folder")
	ps.content_margin_left = UIKit.PAD.pane - 2
	ps.content_margin_right = UIKit.PAD.pane - 2
	ps.content_margin_top = UIKit.PAD.pane + TabStrip.F_EDGE     # under the pane's own top line
	ps.content_margin_bottom = UIKit.SPACE.sm
	pane.add_theme_stylebox_override("panel", ps)
	_tabs.bind_pane(pane)
	pane.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(pane)
	var inner := add_scroll_body(UIKit.SPACE.md)
	var wrap := scroll_box.get_parent()     # the scroll area lives in the folder pane, under the tabs
	body.remove_child(wrap)
	pane.add_child(wrap)
	var fade := wrap.get_node_or_null("Fade") as TextureRect
	if fade:                                 # the scroll fade blends into the pane's cream
		var g := Gradient.new()
		g.colors = PackedColorArray([Color(Palette.PANE, 0.0), Palette.PANE])
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.width = 4
		gt.height = 32
		gt.fill_from = Vector2(0.5, 0.0)
		gt.fill_to = Vector2(0.5, 1.0)
		fade.texture = gt
	fit(0.88, FIXED_H)
	if not invite_mode:
		_panes.room = _room_pane()
		inner.add_child(_panes.room)
	for key in ["friends", "recent"]:
		var v := UIKit.vbox(UIKit.SPACE.sm)
		v.name = key.capitalize()
		inner.add_child(v)
		_panes[key] = v
		var l := UIKit.vbox(UIKit.SPACE.sm)
		l.name = "List"
		v.add_child(l)
		lists[key] = l
	if not invite_mode:
		_refresh()
	show_tab(tab)

func _ready() -> void:
	if tab != "room":
		_load()

## The Room tab: Create room, or join with a code (the sheet as it was before the lists).
func _room_pane() -> VBoxContainer:
	var v := UIKit.vbox(UIKit.SPACE.sm)
	v.name = "Room"
	var intro := UIKit.paragraph(tr("Play with up to 3 friends on their own phones. Make a room and share the code, or join theirs."),
		UIKit.FS.body, Palette.SUB, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(intro)
	create_button = UIKit.button_with(tr("Create room"), UIKit.icon("perk_friends", 30), "honey", "lg")
	create_button.name = "Create"
	create_button.pressed.connect(func():
		if _busy == "":
			create_room.emit())
	v.add_child(create_button)
	v.add_child(_or_rule(tr("or join a friend")))
	var col := UIKit.vbox(UIKit.SPACE.sm)
	var cap := UIKit.caption(tr("Room code"))
	col.add_child(cap)
	var row := UIKit.hbox(UIKit.SPACE.sm)
	code_edit = LineEdit.new()
	code_edit.name = "Code"
	code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_edit.custom_minimum_size = Vector2(0, UIKit.H.lg)
	code_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_edit.add_theme_font_override("font", UIKit.font_caps(900, 4))
	code_edit.add_theme_font_size_override("font_size", UIKit.FS.h1 + 2)
	code_edit.placeholder_text = tr("Enter code")
	code_edit.add_theme_color_override("font_placeholder_color", Color(Palette.MUTED, 0.6))
	code_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
	code_edit.select_all_on_focus = true
	code_edit.text_changed.connect(_on_code_changed)
	code_edit.text_submitted.connect(func(_t: String): _join())
	row.add_child(code_edit)
	paste_button = UIKit.button(tr("Paste"), "white", "sm")
	paste_button.name = "Paste"
	paste_button.custom_minimum_size.x = 84
	paste_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	paste_button.pressed.connect(paste)
	row.add_child(paste_button)
	col.add_child(row)
	v.add_child(col)
	join_button = UIKit.button(tr("Join room"), "teal", "lg")
	join_button.name = "Join"
	join_button.pressed.connect(_join)
	v.add_child(join_button)
	return v

## A thin rule with words in the middle ("or join a friend").
static func _or_rule(t: String) -> Control:
	var row := UIKit.hbox(UIKit.SPACE.sm)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for k in 3:
		if k == 1:
			var l := UIKit.label(t, UIKit.FS.small, Palette.MUTED, UIKit.font_body(800), HORIZONTAL_ALIGNMENT_CENTER)
			row.add_child(l)
			continue
		var line := ColorRect.new()
		line.color = Palette.LINE_STRONG
		line.custom_minimum_size = Vector2(0, 2)
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(line)
	return row


# ---------- tabs ----------

## Show a tab ("room" | "friends" | "recent"; invite mode has no Room), from the top. The lists load when first shown.
func show_tab(key: String) -> void:
	if not _panes.has(key):
		key = "friends"
	tab = key
	_tabs.select(key)
	for k in _panes:
		(_panes[k] as Control).visible = k == key
	if scroll_box:
		scroll_box.scroll_vertical = 0
	if key != "room" and is_inside_tree():
		_load()

func _social() -> Social:
	if social == null or not is_instance_valid(social):
		social = Social.instance()
	return social

## The lists from Social (its cache when fresh); redrawn whenever they change.
func _load(force := false) -> void:
	var s := _social()
	if s == null or not s.available():
		_render()
		return
	if not _wired:
		_wired = true
		s.changed.connect(_render)
		s.invited.connect(func(_uid: String): _render())
	_render()
	await s.refresh(force)
	if is_instance_valid(self) and not _closing:
		_render()


# ---------- the lists ----------

func _render() -> void:
	if not is_instance_valid(self) or _closing:
		return
	var s := _social()
	var st := "offline" if s == null or not s.available() else s.state
	match st:
		"ok":
			list_state = "list"
		"", "loading":
			list_state = "loading"
		"offline":
			list_state = "offline"
		_:
			list_state = "error"
	for key in ["friends", "recent"]:
		var l: VBoxContainer = lists[key]
		for c in l.get_children():
			l.remove_child(c)
			c.queue_free()
		match list_state:
			"loading":
				l.add_child(_note(tr("Loading…")))
			"offline":
				l.add_child(_note(tr("Connect to the internet to see your friends and the people you played with."), true))
			"error":
				l.add_child(_note(tr("Your lists aren’t available right now. Try again soon."), true))
			_:
				var people: Array = s.friends if key == "friends" else s.recent
				if people.is_empty():
					l.add_child(_empty(key))
					continue
				var hint := UIKit.label(tr("Tap the star to add or remove a friend."), UIKit.FS.small, Palette.MUTED, UIKit.font_body(800))
				hint.name = "Hint"
				hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				hint.custom_minimum_size.x = 60
				l.add_child(hint)
				for p: Variant in people:
					if p is Dictionary:
						l.add_child(_person_row(p, key))

## A centred note (with Try again for the offline / error states).
func _note(text: String, retry := false) -> Control:
	var v := UIKit.vbox(UIKit.SPACE.md)
	v.name = "State"
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.custom_minimum_size.y = 200
	var l := UIKit.paragraph(text, UIKit.FS.body_l, Palette.SUB, HORIZONTAL_ALIGNMENT_CENTER)
	l.name = "Message"
	v.add_child(l)
	if retry:
		var b := UIKit.btn(tr("Try again"), "honey", "sm")
		b.name = "Retry"
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		b.custom_minimum_size.x = 160
		b.pressed.connect(func(): _load(true))
		v.add_child(b)
	return v

## What an empty list says: how people get onto it.
func _empty(key: String) -> Control:
	var v := UIKit.vbox(UIKit.SPACE.sm)
	v.name = "Empty"
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.custom_minimum_size.y = 240
	var ic := UIKit.icon("ic_star" if key == "friends" else "ic_reset", 52)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ic.modulate = Color(1, 1, 1, 0.6)
	v.add_child(ic)
	var t := UIKit.label(tr("No friends yet") if key == "friends" else tr("No one here yet"), UIKit.FS.h3, Palette.INK, UIKit.font_body(900), HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(t)
	var msg := tr("Tap the star next to a player in Recent, or long-press them in the lobby, a match or the leaderboard.") if key == "friends" \
		else tr("Play an online match, and the people you meet show up here.")
	var l := UIKit.paragraph(msg, UIKit.FS.body, Palette.SUB, HORIZONTAL_ALIGNMENT_CENTER)
	l.name = "Message"
	v.add_child(l)
	return v

## One person: avatar in its frame with the level star, the name, the line under it, the friend star and Invite.
## Long-press: add / remove (as the star).
func _person_row(p: Dictionary, key: String) -> Control:
	var s := _social()
	var uid := str(p.get("uid", ""))
	var h := UIKit.hbox(UIKit.SPACE.sm)
	var av := Control.new()
	av.custom_minimum_size = Vector2(AVA, AVA)
	av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	av.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var a := Collection.make_avatar_of(str(p.get("avatar", "pawn-red")), str(p.get("frame", "classic")), AVA)
	a.mouse_filter = Control.MOUSE_FILTER_IGNORE
	av.add_child(a)
	var lv := LevelBadge.new(maxi(1, int(p.get("level", 1))), "xs")
	lv.name = "Level"
	lv.place_under(AVA, 5.0)
	av.add_child(lv)
	h.add_child(av)
	var col := UIKit.vbox(0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top := UIKit.hbox(UIKit.SPACE.xs)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nm := UIKit.label(L10n.seat_name(str(p.get("name", "Player"))), UIKit.FS.h3, Palette.INK, UIKit.font_body(900))
	nm.name = "Name"
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(nm)
	col.add_child(top)
	var sub := UIKit.label(sub_text(p, key, s.now() if s != null else 0), UIKit.FS.small, Palette.SUB, UIKit.font_body(800))
	sub.name = "Sub"
	sub.clip_text = true
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(sub)
	h.add_child(col)
	var fav := key == "friends" or bool(p.get("friend", false)) or (s != null and s.is_friend(uid))
	var star := UIKit.icon_button("ic_star" if fav else "ic_star_outline", "glass", UIKit.TAP, 26)
	star.name = "Star"
	star.set_meta("friend", fav)
	star.tooltip_text = tr("Remove from friends") if fav else tr("Add to friends")
	star.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	star.pressed.connect(_star.bind(p, star))
	h.add_child(star)
	var inv := UIKit.btn(_invite_text(s.invite_state(uid) if s != null else ""), "honey", "xs")   # dense (a 48 px target): the name and its line get the room
	inv.name = "Invite"
	inv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	inv.custom_minimum_size.x = 76
	UIKit.fit_text(inv, 12)
	if s != null and s.was_invited(uid):
		inv.disabled = true
		UIKit.set_kind(inv, "off")
	inv.pressed.connect(_invite.bind(p, inv))
	h.add_child(inv)
	var row := UIKit.list_row(h)
	row.name = "Row_" + uid
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	LongPress.attach(row, func():
		var so := _social()
		if so != null:
			so.ask_friend(self, p))
	return row

## The line under a name. Recent: "2h ago · Ludo" (the time first: a narrow row cuts the game's name, not the time).
## Friends: the same once you played, else "Added 3 days ago".
static func sub_text(p: Dictionary, key: String, now := 0) -> String:
	var played := int(p.get("played_at", 0)) if p.get("played_at") is int or p.get("played_at") is float else 0
	if played > 0:
		var g := L10n.t("Snakes & Ladders") if str(p.get("game", "ludo")) == "sl" else L10n.t("Ludo")
		return "%s · %s" % [Fmt.ago(played, now), g]
	if key == "friends":
		var added := int(p.get("added_at", 0)) if p.get("added_at") is int or p.get("added_at") is float else 0
		return L10n.t("Added %s") % Fmt.ago(added, now) if added > 0 else ""
	return ""

## The star: Social adds (or asks to remove) and says so; its `changed` redraws the lists with the new star.
func _star(p: Dictionary, b: Button) -> void:
	var s := _social()
	if s == null or b.disabled:
		return
	b.disabled = true
	await s.star(self, p)
	if is_instance_valid(b):
		b.disabled = false                   # (kept when Remove was cancelled; else the redraw replaced the row)

## A row's Invite button, by Social.invite_state.
static func _invite_text(state: String) -> String:
	match state:
		"invited":
			return L10n.t("Invited")
		"remind":
			return L10n.t("Remind")
		"declined":
			return L10n.t("Not now")
	return L10n.t("Invite")

func _invite(p: Dictionary, b: Button) -> void:
	var s := _social()
	if s == null or b.disabled:
		return
	b.disabled = true
	b.text = tr("Inviting…")
	await s.invite(p, game)
	if not is_instance_valid(b):
		return                               # (a new room's lobby closed this sheet)
	var done := s.was_invited(str(p.get("uid", "")))
	b.text = _invite_text(s.invite_state(str(p.get("uid", ""))))
	b.disabled = done
	UIKit.set_kind(b, "off" if done else "honey")


# ---------- the Room tab ----------

## The cleaned code in the field.
func code() -> String:
	return NetClient.clean_code(code_edit.text) if code_edit else ""

## Put text in the field as if typed (tests, deep links).
func set_code(t: String) -> void:
	code_edit.text = t
	_on_code_changed(t)

## The clipboard into the field (a pasted invite line works too: the code is picked out of it).
func paste() -> void:
	var t := DisplayServer.clipboard_get() if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD) else ""
	set_code(code_from_text(t))
	if code_edit.text == "":
		Toast.show(self, tr("No room code to paste"), null, 1.6, "info")

## A room code inside any text ("Join my Ludo Zing room: K7QX2M" -> "K7QX2M"): the last 6-character run of code
## letters, else the cleaned text.
static func code_from_text(t: String) -> String:
	var words := t.to_upper().replace(":", " ").replace(",", " ").replace(".", " ").split(" ", false)
	for k in range(words.size() - 1, -1, -1):
		if NetClient.valid_code(str(words[k])):
			return str(words[k])
	return NetClient.clean_code(t)

func _on_code_changed(t: String) -> void:
	var clean := NetClient.clean_code(t)
	if clean != t:
		code_edit.text = clean
		code_edit.caret_column = clean.length()
	_refresh()

func _join() -> void:
	if _busy != "" or not NetClient.valid_code(code()):
		return
	if code_edit.has_focus():
		code_edit.release_focus()
	join_room.emit(code())

## "create" | "join" while the network works ("" when done): the buttons say so and wait.
func set_busy(what: String) -> void:
	_busy = what
	_refresh()

func _refresh() -> void:
	if create_button == null:
		return                               # (invite mode: no Room tab)
	var ok := NetClient.valid_code(code())
	create_button.disabled = _busy != ""
	join_button.disabled = _busy != "" or not ok
	paste_button.disabled = _busy != ""
	code_edit.editable = _busy == ""
	var cl := create_button.find_child("Text", true, false) as Label
	if cl:
		cl.text = tr("Creating…") if _busy == "create" else tr("Create room")
	join_button.text = tr("Joining…") if _busy == "join" else tr("Join room")
	var join_off := join_button.disabled and _busy == ""        # can't be pressed yet: the off kind, not a faded teal
	UIKit.set_kind(join_button, "off" if join_off else "teal")
