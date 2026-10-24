extends Node
## Repro: after Continue (welcome) / Exit to Home, is the first tap on the Snake tab ignored?
var main: Node
func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	while main.screen != "welcome":
		await get_tree().process_frame
	await get_tree().create_timer(1.5).timeout
	for c in main.screens.get_children():
		if c is Welcome:
			c.continued.emit()
	while main.screen != "home":
		await get_tree().process_frame
	await get_tree().create_timer(2.5).timeout
	var top: Sheet = main._top_sheet()
	if top:
		top.close()
		await get_tree().create_timer(0.6).timeout
	var tab: Control = main.home._tabs.get_child(0)
	var p := tab.get_global_rect().get_center()
	print("tab rect ", tab.get_global_rect(), " hover-control-at-point: ", _control_at(p))
	_tap(p)
	await get_tree().create_timer(1.5).timeout
	print("after 1st tap: screen=", main.screen)
	get_tree().quit()

func _control_at(p: Vector2) -> String:
	var out := []
	for n in get_tree().root.find_children("*", "Control", true, false):
		var c := n as Control
		if c.is_visible_in_tree() and c.mouse_filter == Control.MOUSE_FILTER_STOP and c.get_global_rect().has_point(p):
			out.append(str(c.get_path()).get_file() + ":" + c.get_class())
	return ", ".join(out)

func _tap(p: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = p
		e.global_position = p
		get_viewport().push_input(e)
		await get_tree().process_frame
