extends Node
## Dev: Play Store screenshot launcher. Forces a borderless 1080x1920 window (a normal window is clamped to the
## display height), then switches to another dev scene, so its shots come out exactly 1080x1920.
##   godot --path . --resolution 1080x1920 res://dev/store_shots.tscn -- <args of that scene...>   with env STORE_SCENE=<dev scene name, e.g. econ_shots>
## The target scene's own save isolation applies; this launcher touches no save.

func _ready() -> void:
	var scene := OS.get_environment("STORE_SCENE")
	if scene == "":
		push_error("usage: STORE_SCENE=<dev scene> godot ... store_shots.tscn -- <args>")
		get_tree().quit()
		return
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_size(Vector2i(1080, 1920))
	DisplayServer.window_set_position(Vector2i(0, 0))
	for i in 10:
		await get_tree().process_frame
	print("window ", get_window().size, " viewport ", get_viewport().get_visible_rect().size)
	get_tree().change_scene_to_file("res://dev/%s.tscn" % scene)
