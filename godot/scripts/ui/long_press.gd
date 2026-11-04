class_name LongPress
extends RefCounted
## Long-press on any Control (add a player to your friends: a list row, a lobby member, a match tile, a leaderboard
## row). attach(c, on_hold) calls on_hold() once a press has stayed down HOLD_SEC without moving more than SLOP_PX, so
## a tap or a scroll drag never fires it, and a light haptic says it took. The press itself still reaches the control
## (and the scroll under it), as before.
##
##   LongPress.attach(row, func(): social.ask_friend(self, person))
## A touch arrives twice (the touch and the mouse event Godot emulates from it); only the last press of a gesture
## counts, so one hold fires once. Tests call LongPress.fire(c) to hold without waiting.

const HOLD_SEC := 0.5
const SLOP_PX := 12.0
const META := "long_press"


static func attach(c: Control, on_hold: Callable, sec := HOLD_SEC) -> void:
	if c.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		c.mouse_filter = Control.MOUSE_FILTER_PASS       # see presses, and let them on to the scroll / the row below
	var st := {id = 0, down = false, at = Vector2.ZERO}
	c.set_meta(META, on_hold)
	c.gui_input.connect(func(e: InputEvent) -> void: _on_input(c, e, st, sec))

## Whether a control has a long-press (tests, the audit tour).
static func has(c: Control) -> bool:
	return c != null and c.has_meta(META)

## The hold as if it happened (tests, the audit tour). False when there is none.
static func fire(c: Control) -> bool:
	if not has(c):
		return false
	(c.get_meta(META) as Callable).call()
	return true

static func _on_input(c: Control, e: InputEvent, st: Dictionary, sec: float) -> void:
	var press := (e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT) \
		or e is InputEventScreenTouch
	if press:
		if not e.is_pressed():
			st.down = false
			return
		st.id = int(st.id) + 1
		st.down = true
		st.at = e.position
		var my := int(st.id)
		var tree := c.get_tree()
		if tree == null:
			return
		tree.create_timer(sec).timeout.connect(func() -> void:
			if not is_instance_valid(c) or not st.down or int(st.id) != my or not c.is_visible_in_tree():
				return
			st.down = false
			Haptics.light()
			fire(c))
	elif (e is InputEventMouseMotion or e is InputEventScreenDrag) and st.down:
		if (e.position as Vector2).distance_to(st.at) > SLOP_PX:
			st.down = false
