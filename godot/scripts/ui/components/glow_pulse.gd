class_name GlowPulse
extends Node2D
## A soft glow round a rounded card that breathes without redrawing: its StyleBoxFlat (a shadow round a clear box) is
## drawn once, behind the parent's own drawing (show_behind_parent), and pulse() only changes the alpha and the scale.
## A Node2D, not a Control: Control.set_scale queues a redraw, Node2D's doesn't (nor does modulate on either).
##
## Why: a StyleBoxFlat (or a polygon) drawn in _draw becomes a triangle array, and the GL Compatibility renderer gives
## every one its own GPU buffers, made and freed on each redraw. Redrawn every frame (the old breathing glow of the
## turn tiles and the dice pad: shadow_size changed per frame), that is dozens of buffers a frame, and Mali drivers
## (Infinix X6886 / Mali-G57, OPPO CPH2251 / Mali-G68) keep ~60-70 KB of native memory a frame: CrashWatch saw the app
## killed after ~20-30 minutes. Transform and modulate changes reuse the recorded drawing.
##
##   var g := GlowPulse.new(style); add_child(g); g.place(card_rect.grow(-4))
##   g.pulse(k)                       # k 0..1 each frame (e.g. 0.5 + 0.5 * sin(t)); g.still() for reduce motion

var style: StyleBoxFlat
var size := Vector2.ZERO                 ## the glowing box (drawn centred on this node's position)
var alpha_lo := 0.45                     ## modulate alpha at k = 0 / 1
var alpha_hi := 0.9
var grow := 0.06                         ## the scale breathes between 1 - grow / 2 and 1 + grow / 2
var still_alpha := 0.75                  ## still(): reduce motion
var strength := 1.0:                     ## times the alpha (a card fading in): set it, the breath keeps going
	set(v):
		strength = v
		_apply()
var _a := 0.75


func _init(style_: StyleBoxFlat = null) -> void:
	style = style_ if style_ != null else StyleBoxFlat.new()
	show_behind_parent = true

func _draw() -> void:
	draw_style_box(style, Rect2(-size / 2.0, size))

## Where the glowing box sits (in the parent's coordinates); the scale breathes round its middle. A redraw only when
## its size changes.
func place(r: Rect2) -> void:
	position = r.get_center()
	if r.size != size:
		size = r.size
		queue_redraw()

## A new style (a colour change): one redraw.
func set_style(s: StyleBoxFlat) -> void:
	style = s
	queue_redraw()

## The breath at k (0..1): alpha and scale only, no redraw.
func pulse(k: float) -> void:
	k = clampf(k, 0.0, 1.0)
	_a = lerpf(alpha_lo, alpha_hi, k)
	_apply()
	var s := 1.0 + grow * (k - 0.5)
	scale = Vector2(s, s)

## No breathing (reduce motion): a steady glow.
func still() -> void:
	_a = still_alpha
	_apply()
	scale = Vector2.ONE

func _apply() -> void:
	modulate.a = _a * strength
