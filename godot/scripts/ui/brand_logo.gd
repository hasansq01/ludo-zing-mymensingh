class_name BrandLogo
extends Control
## The game logo: the owner's supplied artwork (assets/ui/ludo_zing_logo.png, trimmed to its bounds and scaled to
## 960 px wide; owner 2026-10-30), drawn unchanged. Keeps the art's aspect (VIEW), centred in the control.
## The earlier code-drawn "LUDO ZING MYMENSINGH" lockup is in git history (brand_logo_art.svg + Lilita lettering).

const ART := preload("res://assets/ui/ludo_zing_logo.png")
const VIEW := Vector2(320, 219)        # the art's aspect (960 x 657)

## Gentle float, like the web's .brand-logo animation (3.2 s, 6 px).
var bob := false:
	set(v):
		bob = v
		set_process(v and is_visible_in_tree())
		queue_redraw()

var _t := 0.0

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(64, 44)        # the screens size it; this floor only keeps it visible
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

func _ready() -> void:
	set_process(bob and is_visible_in_tree())

## The float stops while the logo is hidden (the home screen under a game) and resumes when it shows (PF-03).
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_inside_tree():
		set_process(bob and is_visible_in_tree())

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	var s := minf(size.x / VIEW.x, size.y / VIEW.y)
	var o := (size - VIEW * s) / 2.0
	if bob:
		o.y -= (1.0 - cos(_t * TAU / 3.2)) / 2.0 * 6.4 * s
	draw_texture_rect(ART, Rect2(o, VIEW * s), false)
