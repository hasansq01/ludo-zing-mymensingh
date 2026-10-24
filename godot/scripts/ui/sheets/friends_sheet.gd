class_name FriendsSheet
extends Sheet
## "Play with friends" (Home's third mode, Ludo only): make a room and share its code, or join a friend's room with
## theirs. The code field takes the 6-character room code: typed or pasted text is upper-cased and cleaned to the
## code alphabet (NetClient.clean_code), and Join stays off until the code is complete. The sheet only asks; the
## caller (Online) does the network work and calls set_busy() / set_busy("") around it.
##
##   var s := FriendsSheet.new()
##   s.create_room.connect(...); s.join_room.connect(func(code): ...)
##   s.open(app.sheet_layer)

signal create_room
signal join_room(code: String)

var code_edit: LineEdit
var create_button: Button
var join_button: Button
var paste_button: Button
var _busy := ""


func _init() -> void:
	super("Play with friends", UIKit.W.form, true, Sheet.LOOK_PM)
	set_kicker("Ludo online")
	body.add_theme_constant_override("separation", UIKit.SPACE.md)
	var intro := UIKit.paragraph("Play with up to 3 friends on their own phones. Make a room and share the code, or join theirs.",
		UIKit.FS.body, Palette.SUB, HORIZONTAL_ALIGNMENT_CENTER)
	body.add_child(intro)
	create_button = UIKit.button_with("Create room", UIKit.icon("perk_friends", 30), "honey", "lg")
	create_button.name = "Create"
	create_button.pressed.connect(func():
		if _busy == "":
			create_room.emit())
	body.add_child(create_button)
	body.add_child(_or_rule("or join a friend"))
	var col := UIKit.vbox(UIKit.SPACE.sm)
	var cap := UIKit.caption("Room code")
	col.add_child(cap)
	var row := UIKit.hbox(UIKit.SPACE.sm)
	code_edit = LineEdit.new()
	code_edit.name = "Code"
	code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_edit.custom_minimum_size = Vector2(0, UIKit.H.lg)
	code_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_edit.add_theme_font_override("font", UIKit.font_caps(900, 4))
	code_edit.add_theme_font_size_override("font_size", UIKit.FS.h1 + 2)
	code_edit.placeholder_text = "Enter code"
	code_edit.add_theme_color_override("font_placeholder_color", Color(Palette.MUTED, 0.6))
	code_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
	code_edit.select_all_on_focus = true
	code_edit.text_changed.connect(_on_code_changed)
	code_edit.text_submitted.connect(func(_t: String): _join())
	row.add_child(code_edit)
	paste_button = UIKit.button("Paste", "white", "sm")
	paste_button.name = "Paste"
	paste_button.custom_minimum_size.x = 84
	paste_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	paste_button.pressed.connect(paste)
	row.add_child(paste_button)
	col.add_child(row)
	body.add_child(col)
	join_button = UIKit.button("Join room", "teal", "lg")
	join_button.name = "Join"
	join_button.pressed.connect(_join)
	body.add_child(join_button)
	_refresh()

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

## The cleaned code in the field.
func code() -> String:
	return NetClient.clean_code(code_edit.text)

## Put text in the field as if typed (tests, deep links).
func set_code(t: String) -> void:
	code_edit.text = t
	_on_code_changed(t)

## The clipboard into the field (a pasted invite line works too: the code is picked out of it).
func paste() -> void:
	var t := DisplayServer.clipboard_get() if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD) else ""
	set_code(code_from_text(t))
	if code_edit.text == "":
		Toast.show(self, "No room code to paste", null, 1.6, "info")

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
	var ok := NetClient.valid_code(code())
	create_button.disabled = _busy != ""
	join_button.disabled = _busy != "" or not ok
	paste_button.disabled = _busy != ""
	code_edit.editable = _busy == ""
	var cl := create_button.find_child("Text", true, false) as Label
	if cl:
		cl.text = "Creating…" if _busy == "create" else "Create room"
	join_button.text = "Joining…" if _busy == "join" else "Join room"
