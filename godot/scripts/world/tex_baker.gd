class_name TexBaker
extends Node
## Paints procedural textures on the GPU and bakes them into mipmapped ImageTextures, like the canvas textures in
## index.html (board, wood rings, planks, brick, night sky...). A SubViewport runs a Control whose _draw calls the
## painter; one frame later its image is read back, mipmapped (so boards seen at an angle don't shimmer) and the
## viewport is freed.
## Big textures are rendered at Quality.texture_scale() of their size (low 0.5, medium 0.75: a 2048 board is 1024 on
## low, a quarter of the memory and of the read-back / mipmap work); the painters keep drawing in the nominal size
## (size_2d_override stretches the canvas). Nothing is made smaller than MIN_SIDE on its longer side.

const MIN_SIDE := 512

class Painter extends Control:
	var fn: Callable
	var ms := 0                         # how long the painter's _draw took (BootTrace)
	func _draw() -> void:
		var t := Time.get_ticks_msec()
		fn.call(self)
		ms = Time.get_ticks_msec() - t

## await bake(Vector2i(1024, 1024), func(c: Control): c.draw_rect(...))
func bake(size: Vector2i, fn: Callable, transparent := false, mipmaps := true) -> ImageTexture:
	var vp := SubViewport.new()
	var px := scaled_size(size)
	vp.size = px
	if px != size:
		vp.size_2d_override = size
		vp.size_2d_override_stretch = true
	vp.transparent_bg = transparent
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var p := Painter.new()
	p.fn = fn
	p.size = Vector2(size)
	vp.add_child(p)
	add_child(vp)
	var t0 := Time.get_ticks_msec()
	await RenderingServer.frame_post_draw
	var t1 := Time.get_ticks_msec()
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if img == null or img.is_empty():           # headless / no renderer: a plain 4x4 stand-in
		img = Image.create(4, 4, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.9, 0.85, 0.8))
	var t2 := Time.get_ticks_msec()
	if mipmaps:
		img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	if BootTrace.active():
		print("[boot]   bake %dx%d (%dx%d) frame %d (draw %d) read %d mips+upload %d ms" % [size.x, size.y, px.x, px.y, t1 - t0, p.ms, t2 - t1, Time.get_ticks_msec() - t2])
	return tex

## The pixel size a texture of nominal `size` is baked at on this quality tier.
static func scaled_size(size: Vector2i) -> Vector2i:
	var longest := maxi(size.x, size.y)
	if longest <= MIN_SIDE:
		return size
	var k := clampf(maxf(Quality.texture_scale(), float(MIN_SIDE) / longest), 0.1, 1.0)
	return Vector2i(maxi(1, roundi(size.x * k)), maxi(1, roundi(size.y * k)))


# ---------- drawing helpers for painters ----------

static func star_points(center: Vector2, r: float, inner := 0.45, points := 5) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in points * 2:
		var a := -PI / 2 + k * PI / points
		var rr := r * inner if k % 2 else r
		pts.append(center + Vector2(cos(a), sin(a)) * rr)
	return pts

static func round_rect(c: CanvasItem, rect: Rect2, radius: float, fill: Color, border := 0.0, border_color := Color.TRANSPARENT) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(int(radius))
	sb.corner_detail = 12
	sb.anti_aliasing = true
	if border > 0:
		sb.set_border_width_all(int(border))
		sb.border_color = border_color
	c.draw_style_box(sb, rect)

static func circle(c: CanvasItem, center: Vector2, r: float, fill: Color) -> void:
	c.draw_circle(center, r, fill, true, -1.0, true)

static func ring(c: CanvasItem, center: Vector2, r: float, width: float, color: Color) -> void:
	c.draw_arc(center, r, 0, TAU, 96, color, width, true)
