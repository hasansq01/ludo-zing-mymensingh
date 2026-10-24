extends Node
## Dev: the real Settings sheet over the home screen — a vertical drag that starts on a toggle scrolls the sheet.
## godot --path . --resolution 780x1688 res://dev/settings_scroll_check.tscn   (any size; the save is backed up)

var main: Node
var _backup := ""

func _ready() -> void:
	if FileAccess.file_exists("user://save.json"):
		_backup = FileAccess.get_file_as_string("user://save.json")
	Save.prefs.welcome_seen = true
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	while main.screen != "home":
		await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout
	main.close_all_sheets()
	if "match" in OS.get_cmdline_user_args():
		main.start_ludo({game = "ludo", players = ["human", "cpu", "cpu", "cpu"], teams = false})
		await get_tree().create_timer(2.0).timeout
	main.open_settings()
	await get_tree().create_timer(1.0).timeout
	var sh: Sheet = main._top_sheet()
	var sc: ScrollContainer = sh.scroll_box
	var ts: TouchScroll = sc.get_node_or_null("TouchScroll")
	print("touchscroll: ", ts, " max: ", ts._max_scroll() if ts else -1.0)
	var t: Control = null
	for b in sh.find_children("*", "BaseButton", true, false):
		if b.is_visible_in_tree() and sc.is_ancestor_of(b) and b.toggle_mode:
			t = b
			break
	var p := t.get_global_rect().get_center()
	print("toggle ", t, " at ", p, " covered: ", ts._covered(p), " info: ", Info.is_open())
	var n: Node = sc
	while n.get_parent() != null and not (n is CanvasLayer):
		var par := n.get_parent()
		for i in range(n.get_index() + 1, par.get_child_count()):
			var c := par.get_child(i)
			if TouchScroll._takes_input(c, p):
				print("  covered by later sibling of ", n.name, ": ", c.name, " ", c.get_class())
		n = par
	var vp_scale: Vector2 = get_viewport().get_final_transform().get_scale()
	print("final transform scale ", vp_scale)
	var was: bool = t.button_pressed
	await drag(p, p + Vector2(0, -250))
	print("scroll after drag: ", sc.scroll_vertical, " toggled: ", t.button_pressed != was)
	_restore()
	get_tree().quit()

func ev(at: Vector2, down: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.pressed = down
	e.position = at * get_viewport().get_final_transform().get_scale()
	Input.parse_input_event(e)

func drag(a: Vector2, b: Vector2) -> void:
	ev(a, true)
	await get_tree().process_frame
	for i in range(1, 13):
		var e := InputEventScreenDrag.new()
		e.index = 0
		e.position = a.lerp(b, i / 12.0) * get_viewport().get_final_transform().get_scale()
		e.relative = (b - a) / 12.0
		Input.parse_input_event(e)
		await get_tree().process_frame
	await get_tree().create_timer(0.15).timeout
	ev(b, false)
	await get_tree().process_frame
	await get_tree().process_frame

func _restore() -> void:
	Save._dirty = false
	if _backup != "":
		var f := FileAccess.open("user://save.json", FileAccess.WRITE)
		f.store_string(_backup)
		f.close()
		Save.load_data()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_restore()
