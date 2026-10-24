class_name TouchScroll
extends Node
## Drag-to-scroll for a ScrollContainer that works wherever the finger lands, including on buttons, toggles,
## segmented controls and sliders (Godot's own touch drag only sees presses that reach the ScrollContainer, so a
## drag that starts on a control with MOUSE_FILTER_STOP never scrolls).
##
## It watches the input before the GUI does (_input). A press inside the scroll area is left alone, so taps and
## horizontal slider drags behave as usual. Once the finger moves mostly vertically past DEADZONE, the press on the
## control under it is cancelled (a synthetic move + release far outside, so no button fires and no toggle flips;
## a slider that jumped to the touch point gets its value back) and the drag scrolls the content, with a fling.
##   TouchScroll.attach(scroll_container)      (UIKit.scroll() does this)

const DEADZONE := 10.0          ## UI px of vertical travel before a drag becomes a scroll
const FRICTION := 4.5           ## fling decay per second (exponential)
const MIN_FLING := 120.0        ## px/s; slower releases just stop
const MAX_FLING := 4200.0
const OFF := Vector2(-100000, -100000)

var _sc: ScrollContainer
var _tracking := false
var _dragging := false
var _start := Vector2.ZERO
var _from := 0.0                ## scroll_vertical when the drag began
var _pos := 0.0                 ## float scroll position (scroll_vertical is an int)
var _vel := 0.0                 ## scroll px/s (positive = content moves up)
var _last_y := 0.0
var _last_t := 0
var _flinging := false
var _ranges := {}               ## Range -> value at press (restored when the press turns into a scroll)
var _synthetic := false
var _press_at := Vector2.ZERO


static func attach(sc: ScrollContainer) -> TouchScroll:
	var t := TouchScroll.new()
	t.name = "TouchScroll"
	t._sc = sc
	sc.scroll_deadzone = 100000       # the built-in touch drag stays off: this node handles every drag
	sc.add_child(t)
	return t


func _ready() -> void:
	set_process(false)


func _input(event: InputEvent) -> void:
	if _synthetic or not is_instance_valid(_sc):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_on_press(event.position)
		elif _tracking:
			_tracking = false
			if _dragging:
				_dragging = false
				get_viewport().set_input_as_handled()
				_start_fling()
	elif event is InputEventMouseMotion and _tracking:
		if not (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
			_tracking = false
			_dragging = false
			return
		var d: Vector2 = event.position - _start
		if not _dragging:
			if absf(d.y) < DEADZONE or absf(d.y) < absf(d.x) * 1.2:
				return
			_begin_drag(event.position)
		get_viewport().set_input_as_handled()
		_drag_to(event.position.y)


func _on_press(at: Vector2) -> void:
	_flinging = false
	set_process(false)
	_tracking = false
	_dragging = false
	if not _sc.is_visible_in_tree() or not _sc.get_global_rect().has_point(at) or _max_scroll() <= 0.0:
		return
	if Info.is_open() or _covered(at):
		return                            # a bubble, a newer sheet or its scrim is on top here
	_tracking = true
	_press_at = at
	_start = at
	_ranges.clear()
	for r in _sc.find_children("*", "Slider", true, false):
		_ranges[r] = (r as Range).value


## True when something drawn after the scroll area (a later sibling of it or of any ancestor, in the same canvas
## layer) takes input at `at`.
func _covered(at: Vector2) -> bool:
	var n: Node = _sc
	while n.get_parent() != null and not (n is CanvasLayer):
		var p := n.get_parent()
		for i in range(n.get_index() + 1, p.get_child_count()):
			if _takes_input(p.get_child(i), at):
				return true
		n = p
	return false


static func _takes_input(n: Node, at: Vector2) -> bool:
	if n is CanvasLayer or not (n is CanvasItem) or not (n as CanvasItem).visible:
		return false
	if n is Control:
		var c := n as Control
		if c.mouse_filter != Control.MOUSE_FILTER_IGNORE and c.get_global_rect().has_point(at):
			return true
	for ch in n.get_children():
		if _takes_input(ch, at):
			return true
	return false


func _begin_drag(at: Vector2) -> void:
	_dragging = true
	_start = at
	_pos = float(_sc.scroll_vertical)
	_from = _pos
	_vel = 0.0
	_last_y = at.y
	_last_t = Time.get_ticks_usec()
	_cancel_press.call_deferred()        # not from inside _input: push_input there would nest event handling


## Ends the GUI's press on whatever control the finger went down on, without activating it.
func _cancel_press() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var on_slider := false
	for r in _ranges:
		if is_instance_valid(r) and (r as Control).get_global_rect().has_point(_press_at):
			on_slider = true
	_synthetic = true
	if not on_slider:                     # a slider would follow the move to its minimum
		var mm := InputEventMouseMotion.new()
		mm.position = OFF
		mm.global_position = OFF
		mm.button_mask = MOUSE_BUTTON_MASK_LEFT
		vp.push_input(mm)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = OFF
	up.global_position = OFF
	vp.push_input(up)
	_synthetic = false
	for r in _ranges:
		if is_instance_valid(r) and not is_equal_approx(r.value, _ranges[r]):
			r.value = _ranges[r]
	_ranges.clear()


func _drag_to(y: float) -> void:
	_pos = clampf(_from - (y - _start.y), 0.0, _max_scroll())
	_sc.scroll_vertical = int(round(_pos))
	var now := Time.get_ticks_usec()
	var dt := float(now - _last_t) / 1000000.0
	if dt > 0.0005:
		var v := -(y - _last_y) / dt
		_vel = lerpf(_vel, v, 0.6) if dt < 0.1 else v
		_last_y = y
		_last_t = now


func _start_fling() -> void:
	if float(Time.get_ticks_usec() - _last_t) / 1000000.0 > 0.08:
		_vel = 0.0                        # the finger rested before lifting
	_vel = clampf(_vel, -MAX_FLING, MAX_FLING)
	if absf(_vel) < MIN_FLING:
		return
	_flinging = true
	set_process(true)


func _process(delta: float) -> void:
	if not _flinging or not is_instance_valid(_sc):
		set_process(false)
		return
	_pos += _vel * delta
	_vel *= exp(-FRICTION * delta)
	var top := _max_scroll()
	if _pos <= 0.0 or _pos >= top:
		_pos = clampf(_pos, 0.0, top)
		_vel = 0.0
	_sc.scroll_vertical = int(round(_pos))
	if absf(_vel) < 20.0:
		_flinging = false
		set_process(false)


func _max_scroll() -> float:
	var bar := _sc.get_v_scroll_bar()
	return maxf(0.0, bar.max_value - bar.page)
