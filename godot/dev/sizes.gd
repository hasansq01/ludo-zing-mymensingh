extends Node
func _ready() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	while main.screen != "home":
		await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout
	print("vp ", get_viewport().get_visible_rect().size)
	print("ui_root ", main.ui_root.size, " screens ", main.screens.size, " home ", main.home.size, " hud ", main.hud.size)
	print("anchors home ", main.home.anchor_right, " ", main.home.anchor_bottom, " offs ", main.home.offset_right, " ", main.home.offset_bottom)
	print("zoom ", main.world.home_zoom, " vy ", main.world.home_view_y, " cam ", main.world.camera.global_position)
	get_tree().quit()
