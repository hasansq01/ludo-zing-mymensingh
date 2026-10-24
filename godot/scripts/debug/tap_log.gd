class_name TapLog
extends RefCounted
## Device-test hook: prints where to tap ("[tapme] x y" in device / window pixels) so adb scripts can drive a
## game. Debug builds only (OS.is_debug_build()); release builds never print and never wait for it.
##
##   if TapLog.enabled():
##       TapLog.point(button)                        # a Control: the centre of its global rect
##       TapLog.point(Vector2(120, 400))             # a UI position (canvas coordinates)
##       TapLog.point(pawn.global_position, camera)  # a 3D point seen by a camera

## The last lines printed (newest last, at most 32), for tests.
static var lines: Array[String] = []

static func enabled() -> bool:
	return OS.is_debug_build()

## Prints one point; returns it in device pixels (Vector2(-1, -1) when disabled or unknown).
static func point(where: Variant, cam: Camera3D = null) -> Vector2:
	if not enabled():
		return Vector2(-1, -1)
	var ui := Vector2(-1, -1)
	if where is Control:
		ui = (where as Control).get_global_rect().get_center()
	elif where is Vector3 and cam != null:
		ui = cam.unproject_position(where)
	elif where is Vector2:
		ui = where
	else:
		return Vector2(-1, -1)
	var px := ui * ui_to_window()
	var line := "[tapme] %d %d" % [int(px.x), int(px.y)]
	print(line)
	lines.append(line)
	if lines.size() > 32:
		lines.remove_at(0)
	return px

## Several points (Controls, Vector2s or Vector3s with cam) in order.
static func points(list: Array, cam: Camera3D = null) -> void:
	for w in list:
		point(w, cam)

## Factor from UI (canvas, 390 px wide base) to window pixels.
static func ui_to_window() -> float:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return 1.0
	var vis := tree.root.get_visible_rect().size.x
	return float(DisplayServer.window_get_size().x) / vis if vis > 0 else 1.0
