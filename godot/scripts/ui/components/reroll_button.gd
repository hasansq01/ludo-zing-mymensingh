class_name RerollButton
extends Control
## The "Roll again" button of a re-roll offer (server/ECONOMY_V1.md section 4): a chunky gold game button beside the dice with a ring
## around the seconds left that shrinks over the 3 s window, "Roll again" and its price ("Free" with a free re-roll, else
## a small gem and the gem price). A tap emits `pressed` once; then it shows a spinner ("Rolling…") until hide_offer()
## (the server's `rerolled`, or an error).
##
##   var b := RerollButton.new(); hud.add_child(b)
##   b.pressed.connect(...)
##   b.show_offer(left_ms, total_ms, free, cost)       # b.visible, ring running
##   b.set_busy(true)                                   # after the tap
##   b.hide_offer()

signal pressed

const W := 152.0
const H := 56.0
const RING_R := 18.0
const BUSY_MAX_MS := 6000
const GEM := Color("#5fd0ee")
const GEM_DEEP := Color("#2fb0d8")
const GEM_LIGHT := Color("#c9f3fc")
const GEM_EDGE := Color("#1d7fa6")

var left_ms := 0.0                       ## ms left on the ring (counts down by itself while visible)
var total_ms := 3000.0
var costs_nothing := true
var cost := 5
var busy := false
var _end := 0
var _busy_at := 0
var _spin := 0.0
var _down := false


func _init() -> void:
	name = "RerollButton"
	custom_minimum_size = Vector2(W, H)
	size = Vector2(W, H)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	visible = false

func show_offer(left_ms_: float, total_ms_: float, free_: bool, cost_: int) -> void:
	left_ms = maxf(0.0, left_ms_)
	total_ms = maxf(1.0, total_ms_)
	costs_nothing = free_
	cost = cost_
	busy = false
	_end = Time.get_ticks_msec() + int(left_ms)
	visible = true
	set_process(true)
	queue_redraw()

## The tap went out: a spinner in place of the ring (no second tap).
func set_busy(on: bool) -> void:
	busy = on
	_busy_at = Time.get_ticks_msec()
	queue_redraw()

func hide_offer() -> void:
	visible = false
	busy = false
	_down = false
	set_process(false)

## The label under "Roll again" ("Free" or "5" beside the gem).
func price_text() -> String:
	return tr("Free") if costs_nothing else str(cost)

func _process(d: float) -> void:
	if not visible:
		return
	if not busy:
		left_ms = maxf(0.0, float(_end - Time.get_ticks_msec()))
		if left_ms <= 0.0:
			hide_offer()                  # the window closed
			return
	elif Time.get_ticks_msec() - _busy_at > BUSY_MAX_MS:
		hide_offer()                      # no answer: give up quietly
		return
	_spin = fmod(_spin + d * TAU * 1.1, TAU)
	queue_redraw()

func _gui_input(e: InputEvent) -> void:
	var press: bool = (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) \
		or (e is InputEventScreenTouch and e.pressed)
	var release: bool = (e is InputEventMouseButton and not e.pressed and e.button_index == MOUSE_BUTTON_LEFT) \
		or (e is InputEventScreenTouch and not e.pressed)
	if press and not busy:
		_down = true
		queue_redraw()
		accept_event()
	elif release and _down:
		_down = false
		queue_redraw()
		accept_event()
		tap()

## The press (also what tests call): once, and not while busy or hidden.
func tap() -> void:
	if busy or not visible:
		return
	UIKit.sfx("tap")
	pressed.emit()

## The game look's chunky gold button (MatchLook.draw_gold_button): the seconds in a brown ring on the left, "Roll
## again" in display type and the price under it; pressed, the face drops by its lip.
func _draw() -> void:
	var ink := Palette.GL_BROWN_TEXT
	var face := MatchLook.draw_gold_button(self, Rect2(0, 0, W, H), 18.0, _down, busy)
	var cy := face.get_center().y
	var c := Vector2(8.0 + RING_R + 1.0, cy)
	draw_circle(c, RING_R, Color(ink, 0.12), true, -1.0, true)
	if busy:
		draw_arc(c, RING_R - 1.5, 0.0, TAU, 32, Color(ink, 0.2), 3.0, true)
		draw_arc(c, RING_R - 1.5, _spin, _spin + TAU * 0.3, 16, ink, 3.0, true)
	else:
		var k := clampf(left_ms / total_ms, 0.0, 1.0)
		draw_arc(c, RING_R - 1.5, 0.0, TAU, 32, Color(ink, 0.18), 3.0, true)
		if k > 0.0:
			draw_arc(c, RING_R - 1.5, -PI / 2.0, -PI / 2.0 + TAU * k, 32, ink, 3.0, true)
		var f := UIKit.font_display()
		var t := str(int(ceil(left_ms / 1000.0)))
		var fs := 19
		var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, c + Vector2(-w / 2.0, fs * 0.36), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
	var x := c.x + RING_R + 8.0
	var f2 := UIKit.font_display()
	draw_string(f2, Vector2(x, cy - (0.0 if not busy else -6.0)), tr("Rolling…") if busy else tr("Roll again"), HORIZONTAL_ALIGNMENT_LEFT, W - x - 6.0, 18, ink)
	if busy:
		return
	var f3 := UIKit.font_body(900, true)
	if costs_nothing:
		draw_string(f3, Vector2(x, cy + 16.0), tr("Free"), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(ink, 0.85))
	else:
		draw_gem(self, Vector2(x + 7.0, cy + 10.0), 14.0)
		draw_string(f3, Vector2(x + 18.0, cy + 16.0), str(cost), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(ink, 0.9))

## A small gem (the cut-diamond shape of assets/ui/gem.svg) centred at c, size px wide, drawn on `item`.
static func draw_gem(item: CanvasItem, c: Vector2, px: float) -> void:
	var s := px / 28.0                    # the svg's 32 box: the gem spans 2..30 wide, 4..29 tall
	var o := c - Vector2(16.0, 16.5) * s
	var p := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s
	item.draw_colored_polygon(PackedVector2Array([p.call(9, 4), p.call(23, 4), p.call(30, 12), p.call(16, 29), p.call(2, 12)]), GEM)
	item.draw_colored_polygon(PackedVector2Array([p.call(2, 12), p.call(30, 12), p.call(16, 29)]), GEM_DEEP)
	item.draw_colored_polygon(PackedVector2Array([p.call(9, 4), p.call(23, 4), p.call(26, 12), p.call(6, 12)]), GEM_LIGHT)
	item.draw_polyline(PackedVector2Array([p.call(9, 4), p.call(23, 4), p.call(30, 12), p.call(16, 29), p.call(2, 12), p.call(9, 4)]), GEM_EDGE, maxf(1.2, 1.4 * s), true)
