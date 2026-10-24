extends Node
## Dev preview: the real app (scenes/main.tscn) -> Shop -> View on Pastel Dream Room -> drag / zoom the 3D view,
## Buy, Use, fallback + Retry -> close -> home with the equipped room back. Saves screenshots and quits.
## Never writes the save: user://save.json is backed up first and put back at the end, Catalog writes go to a no-op
## writer, and Save.profile is a copy (coins / rooms set for the run) restored before quitting.
## godot --path . res://dev/preview_pv.tscn -- [out_dir] [room=<id>] [use] [narrow] [short]

const OUT := "/private/tmp/claude-501/-Users-shihabshaharia-Coding-ludo-zing-mymensingh/d8feebe6-eee1-4f48-a116-aa2f313481c9/scratchpad/agent_preview"
const SAVE_PATH := "user://save.json"

var out := OUT
var main: Node
var _save_backup: Variant = null          # file contents (PackedByteArray) or null when there was no file
var _profile_backup := {}
var _fails := 0

func _ready() -> void:
	get_tree().create_timer(90.0).timeout.connect(_finish)   # never hang
	var args := OS.get_cmdline_user_args()
	var room := "dream"
	for a: String in args:
		if a.begins_with("/"): out = a
		elif a.begins_with("room="): room = a.substr(5)
	var sz := Vector2i(320, 844) if args.has("narrow") else Vector2i(390, 560) if args.has("short") else Vector2i.ZERO
	if sz != Vector2i.ZERO:
		get_tree().root.content_scale_size = sz
		get_window().size = sz
	DirAccess.make_dir_recursive_absolute(out)
	if FileAccess.file_exists(SAVE_PATH):
		_save_backup = FileAccess.get_file_as_bytes(SAVE_PATH)
	_profile_backup = Save.profile.duplicate(true)
	Save._timer.timeout.disconnect(Save.flush)
	Catalog.writer = func(_p: Dictionary) -> bool: return true
	main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)            # /root/Main, as in the app
	await _until(func(): return main.is_inside_tree() and main.screen in ["home", "welcome"], 40)
	if main.screen == "welcome":
		for c in main.screens.get_children():
			if c.has_signal("continued"):
				c.continued.emit()
		await _until(func(): return main.screen == "home", 10)
	await _sleep(1.2)
	var top: Sheet = main._top_sheet()
	if top:
		top.close()
		await _sleep(0.5)
	# a run-only profile: the starter rooms, Moonlit Café in use, enough coins for one room
	var p: Dictionary = Save.profile
	p.coins = 3500
	p.rooms = ["night", "cafe"]
	p.room = "night"
	await main.apply_room("night")
	main.home.refresh()
	await _sleep(0.5)
	main._on_tab("shop")
	await _sleep(0.8)
	var shop: Sheet = main._top_sheet()
	await shot("shop_rooms")
	var view_b: Button = null
	for b in shop.find_children("*", "Button", true, false):
		if b.get_meta("view", "") == room:
			view_b = b
	check("View button on the %s card" % room, view_b != null)
	if view_b == null:
		_finish(); return
	shop.scroll_box.ensure_control_visible(view_b)
	await _sleep(0.3)
	await _click(view_b.get_global_transform_with_canvas() * (view_b.size / 2.0))
	await _sleep(0.3)
	var pv: Sheet = main._top_sheet()
	check("View opens the preview over a hidden Shop", pv is PreviewSheet and not shop.visible)
	await _until(func(): return pv.ready_3d or pv.failed, 20)
	check("the 3D view draws the previewed room", pv.ready_3d and main.world.rooms.current == room)
	check("nothing changed for the player", Save.profile.room == "night" and int(Save.profile.coins) == 3500)
	await _sleep(1.6)
	await shot("pv_open")
	# drag right-to-left and down (turns round the table and lifts the camera), real mouse input
	var view: Control = pv.get("_view")
	var c := view.get_global_transform_with_canvas() * (view.size / 2.0)
	var az0: float = pv.goal.az
	await _drag(c, c + Vector2(-120, 70))
	check("dragging turns the camera (within limits)", pv.goal.az > az0 and pv.goal.az <= 0.9 and pv.goal.el > 0.0 and pv.goal.el <= 0.62)
	await _drag(c, c + Vector2(2000, 2000))
	check("limits hold", is_equal_approx(pv.goal.az, 0.3) and is_equal_approx(pv.goal.el, 0.62))
	await _drag(c, c + Vector2(-90, -40))
	await _sleep(1.2)
	await shot("pv_dragged")
	for k in 8:
		pv._view_input(_wheel(true, c))
	check("zoom limit .45", is_equal_approx(pv.goal.zoom, 0.45))
	await _sleep(1.2)
	await shot("pv_zoomed")
	pv.goal = PreviewSheet.HOME.duplicate()
	await _sleep(1.0)
	# Buy (asks first; then owned and in use)
	var act: Button = pv.get("_act")
	check("panel shows Buy with the price", act != null and act.name == "Buy")
	await _click(act.get_global_transform_with_canvas() * (act.size / 2.0))
	await _sleep(0.5)
	var dlg: Sheet = main._top_sheet()
	check("Buy asks first, nothing spent yet", dlg != pv and dlg.has_meta("confirm") and int(Save.profile.coins) == 3500)
	await shot("pv_confirm")
	var yes: Button = dlg.find_child("Yes", true, false)
	await _click(yes.get_global_transform_with_canvas() * (yes.size / 2.0))
	await _sleep(0.6)
	check("Buy owns it and puts it in use, charged once", Catalog.owns_room(room) and Save.profile.room == room and int(Save.profile.coins) == 500 and pv.get("_act") == null)
	await shot("pv_used")
	# undo Use for the restore check (the run profile only)
	p.room = "night"
	main.apply_room("night")
	await _sleep(0.3)
	pv._panel()
	await _sleep(0.2)
	pv.start_3d()
	await _until(func(): return pv.ready_3d or pv.failed, 10)
	# fallback + Retry
	PreviewSheet.debug_fail = true
	pv.start_3d()
	await _sleep(0.4)
	check("failure shows the thumbnail + Retry", pv.failed and not pv.ready_3d)
	await shot("pv_fallback")
	PreviewSheet.debug_fail = false
	var retry: Button = pv.find_child("Retry", true, false)
	await _click(retry.get_global_transform_with_canvas() * (retry.size / 2.0))
	await _until(func(): return pv.ready_3d, 10)
	check("Retry brings the 3D view back", pv.ready_3d)
	await _sleep(0.8)
	# close: the café shows the room in use again, the Shop comes back
	var x: Button = pv.close_btn
	await _click(x.get_global_transform_with_canvas() * (x.size / 2.0))
	await _sleep(0.6)
	check("closing returns to the Shop", not is_instance_valid(pv) and shop.visible and main._top_sheet() == shop)
	await _until(func(): return main.world.rooms.current == "night", 5)
	check("closing restores the room in use", main.world.rooms.current == "night")
	await shot("shop_after")
	shop.close()
	await _sleep(1.0)
	await shot("home_restored")
	_finish()

func check(name: String, ok: bool) -> void:
	print(("PASS  " if ok else "FAIL  ") + name)
	if not ok:
		_fails += 1

func shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var vs := get_viewport().get_visible_rect().size
	var path := "%s/%s_%dx%d.png" % [out, tag, int(vs.x), int(vs.y)]
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)

func _finish() -> void:
	Catalog.writer = Callable()
	Save.profile.clear()
	Save.profile.merge(_profile_backup)
	Save._dirty = false
	if _save_backup is PackedByteArray:
		var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		f.store_buffer(_save_backup)
		f.close()
	elif FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	print("done, %d failed" % _fails)
	if is_instance_valid(main):
		main.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	get_tree().quit(1 if _fails else 0)

func _until(cond: Callable, sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	while not cond.call() and (Time.get_ticks_msec() - t0) / 1000.0 < sec:
		await get_tree().process_frame

func _sleep(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _click(at: Vector2) -> void:
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = at
		e.global_position = at
		Input.parse_input_event(e)
		await get_tree().process_frame

func _drag(from: Vector2, to: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = from
	e.global_position = from
	Input.parse_input_event(e)
	await get_tree().process_frame
	for k in range(1, 11):
		var m := InputEventMouseMotion.new()
		m.position = from.lerp(to, k / 10.0)
		m.global_position = m.position
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(m)
		await get_tree().process_frame
	var u := InputEventMouseButton.new()
	u.button_index = MOUSE_BUTTON_LEFT
	u.pressed = false
	u.position = to
	u.global_position = to
	Input.parse_input_event(u)
	await get_tree().process_frame

func _wheel(up: bool, at: Vector2) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	e.pressed = true
	e.factor = 1.0
	e.position = at
	return e
