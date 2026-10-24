extends Node
## Dev: checks TouchScroll — a vertical drag that starts on a toggle / button / slider scrolls and activates nothing;
## a tap still toggles; a horizontal drag on a slider still moves it.
## godot --path . --resolution 390x844 res://dev/touch_scroll_check.tscn

var sc: ScrollContainer
var toggles: Array[CheckButton] = []
var btn_hits := 0
var slider: HSlider
var fails := 0

func _ready() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	sc = UIKit.scroll()
	sc.position = Vector2(20, 100)
	sc.size = Vector2(350, 500)
	root.add_child(sc)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(vb)
	for i in 20:
		var t := CheckButton.new()
		t.text = "Toggle %d" % i
		t.custom_minimum_size.y = 60
		vb.add_child(t)
		toggles.append(t)
		if i == 2:
			var b := Button.new()
			b.text = "Button"
			b.custom_minimum_size.y = 60
			b.pressed.connect(func(): btn_hits += 1)
			vb.add_child(b)
			slider = HSlider.new()
			slider.custom_minimum_size = Vector2(300, 60)
			slider.value = 50
			vb.add_child(slider)
	# a cover over the lower part: drags there must not scroll
	var cover := ColorRect.new()
	cover.color = Color(0, 0, 0, 0.2)
	cover.position = Vector2(0, 520)
	cover.size = Vector2(390, 100)
	root.add_child(cover)
	for i in 5:
		await get_tree().process_frame
	await check()
	print("TOUCH_SCROLL ", "PASS" if fails == 0 else "FAIL %d" % fails)
	get_tree().quit()

func ok(c: bool, what: String) -> void:
	if not c:
		fails += 1
	print(("  ok   " if c else "  FAIL ") + what)

func check() -> void:
	var t0 := toggles[0]
	var p := t0.get_global_rect().get_center()
	# a tap toggles
	await press(p); await release(p)
	ok(t0.button_pressed, "tap toggles")
	# a vertical drag from a toggle scrolls and does not toggle
	var was := t0.button_pressed
	await drag(p, p + Vector2(0, -200))
	ok(sc.scroll_vertical > 150, "drag from a toggle scrolls (%d)" % sc.scroll_vertical)
	ok(t0.button_pressed == was, "drag does not toggle")
	await settle()
	sc.scroll_vertical = 0
	await get_tree().process_frame
	# from the button
	var b: Button = slider.get_parent().get_child(3)
	var bp := b.get_global_rect().get_center()
	await drag(bp, bp + Vector2(0, -120))
	ok(sc.scroll_vertical > 80, "drag from a button scrolls (%d)" % sc.scroll_vertical)
	ok(btn_hits == 0, "drag does not press the button")
	await settle()
	sc.scroll_vertical = 0
	await get_tree().process_frame
	await press(bp); await release(bp)
	ok(btn_hits == 1, "tap presses the button")
	# from the slider track: scrolls, value restored
	var sp := slider.get_global_rect().position + Vector2(40, 30)
	await drag(sp, sp + Vector2(0, -150))
	ok(sc.scroll_vertical > 100, "drag from a slider scrolls (%d)" % sc.scroll_vertical)
	ok(is_equal_approx(slider.value, 50.0), "slider value kept (%.1f)" % slider.value)
	await settle()
	sc.scroll_vertical = 0
	await get_tree().process_frame
	# horizontal drag on the slider moves it, no scroll
	var gp := slider.get_global_rect().position + Vector2(slider.size.x * 0.5, 30)
	await drag(gp, gp + Vector2(100, 4))
	ok(sc.scroll_vertical == 0, "horizontal slider drag does not scroll")
	ok(slider.value > 60.0, "horizontal slider drag moves it (%.1f)" % slider.value)
	# covered area: no scroll
	await drag(Vector2(200, 560), Vector2(200, 300))
	ok(sc.scroll_vertical == 0, "a drag on a cover does not scroll")

func ev_button(at: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	e.position = at
	e.global_position = at
	Input.parse_input_event(e)

func press(at: Vector2) -> void:
	move(at, 0)
	ev_button(at, true)
	await get_tree().process_frame

func release(at: Vector2) -> void:
	ev_button(at, false)
	await get_tree().process_frame
	await get_tree().process_frame

func move(at: Vector2, mask: int) -> void:
	var e := InputEventMouseMotion.new()
	e.position = at
	e.global_position = at
	e.button_mask = mask
	Input.parse_input_event(e)

func drag(a: Vector2, b: Vector2) -> void:
	await press(a)
	for i in range(1, 13):
		move(a.lerp(b, i / 12.0), MOUSE_BUTTON_MASK_LEFT)
		await get_tree().process_frame
	await get_tree().create_timer(0.15).timeout     # rest before lifting: no fling
	await release(b)

func settle() -> void:
	await get_tree().create_timer(0.3).timeout
