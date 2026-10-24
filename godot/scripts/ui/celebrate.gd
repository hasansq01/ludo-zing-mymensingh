class_name Celebrate
extends Control
## Win confetti (index.html Celebrate): a full-rect overlay that draws paper confetti and firework sparks for ~3 s,
## then frees itself. Styles: burst (from the centre), cannons (bottom corners), flares (rockets that pop), rain
## (from the top); picked at random, never the same style twice in a row. Colours: the player colours plus the
## gold / pink / lavender accents (Palette).
## intensity (0.1 .. 1): 1 = the full win celebration; lower is a quieter, smaller one for small wins (fewer and
## slower pieces, fewer rockets, no firework pops below 0.75). Reduce motion scales it down further.
## Call it for wins only (a match the player won, a Pass & Play finish, a big reward), never on a loss.
##
##   Celebrate.run(ui_layer)                 # a win
##   Celebrate.run(sheet, "burst", 0.5)      # a small win (Day 7 reward, the spin jackpot)

const KINDS := ["burst", "cannons", "flares", "rain"]
const COLS := [Palette.PLAYER[0], Palette.PLAYER[1], Palette.PLAYER[2], Palette.PLAYER[3], Palette.GOLD_FILL,
	Palette.PINK, Palette.LAVENDER, Palette.INFO, Palette.PEACH]
const SPARK_HI := Palette.GOLD_HI
const TRAIL := Palette.GOLD_FILL

static var last := ""
static var _paper: Texture2D

## Which style this one plays.
var kind := ""
## 1 = full; lower = a smaller, quieter celebration.
var intensity := 1.0

var _parts: Array[Part] = []
var _rockets: Array[Rocket] = []
var _w := 390.0
var _h := 844.0


class Part:
	var confetti := true
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var rot := 0.0
	var vr := 0.0
	var sw := 0.0
	var s := 8.0
	var col := Color.WHITE
	var t := 0.0
	var max_t := 3.0
	var strip := false


class Rocket:
	var pos := Vector2.ZERO
	var vy := 0.0
	var top := 0.0
	var col := Color.WHITE
	var delay := 0.0


## Starts a celebration over `parent` (full rect, ignores input) and returns it. `style` forces one of KINDS.
## intensity < 1: a smaller, quieter celebration (see the header).
static func run(parent: Control, style := "", intensity := 1.0) -> Celebrate:
	var c := Celebrate.new()
	c.kind = style if KINDS.has(style) else ""
	c.intensity = clampf(intensity, 0.1, 1.0)
	if Sheet.reduce_motion():
		c.intensity = maxf(0.1, c.intensity * 0.4)
	parent.add_child(c)
	return c

## n pieces at this intensity (at least 1).
func _n(full: int) -> int:
	return maxi(1, int(round(full * intensity)))

## Launch speeds shrink a little with the intensity (a small win stays closer to its origin).
func _v() -> float:
	return lerpf(0.7, 1.0, intensity)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	if _paper == null:
		# white with a clear 1px border: linear filtering gives the tiny rotated pieces soft (anti-aliased) edges
		var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(Color(1, 1, 1, 0))
		img.fill_rect(Rect2i(1, 1, 6, 6), Color.WHITE)
		_paper = ImageTexture.create_from_image(img)


func _ready() -> void:
	var s := size if size.x > 0.0 and size.y > 0.0 else get_viewport_rect().size
	_w = s.x
	_h = s.y
	if kind == "":
		var options := KINDS.filter(func(k): return k != last)
		kind = options[randi() % options.size()]
	last = kind
	match kind:
		"burst": _burst()
		"cannons": _cannons()
		"flares": _flares()
		_: _rain()


func _confetti(at: Vector2, v: Vector2) -> void:
	var p := Part.new()
	p.pos = at
	p.vel = v
	p.rot = randf() * TAU
	p.vr = randf_range(-9.0, 9.0)
	p.sw = randf() * TAU
	p.s = randf_range(6.0, 10.0)
	p.strip = randf() < 0.3
	p.col = COLS[randi() % COLS.size()]
	p.max_t = randf_range(2.2, 3.2)
	_parts.append(p)


func _spark(at: Vector2, col: Color, n: int, speed: float) -> void:
	for i in n:
		var p := Part.new()
		p.confetti = false
		p.pos = at
		p.vel = Vector2.from_angle(randf() * TAU) * speed * randf_range(0.35, 1.0)
		p.col = col
		p.max_t = randf_range(0.9, 1.4)
		p.s = randf_range(1.6, 2.8)
		_parts.append(p)


func _burst() -> void:
	var at := Vector2(_w * 0.5, _h * 0.4)
	for i in _n(150):
		var a := randf_range(-PI, 0.0) + randf_range(-0.3, 0.3)
		var v := randf_range(0.45, 1.15) * _h * _v()
		_confetti(at, Vector2(cos(a) * v * 0.8, sin(a) * v))


func _cannons() -> void:
	for side in [[0.0, 1.0], [_w, -1.0]]:
		for i in _n(90):
			var a := randf_range(0.95, 1.4)
			var v := randf_range(0.9, 1.45) * _h * _v()
			_confetti(Vector2(side[0], _h), Vector2(side[1] * cos(a) * v, -sin(a) * v))


func _flares() -> void:
	for i in _n(5):
		var r := Rocket.new()
		r.pos = Vector2(randf_range(0.18, 0.82) * _w, _h + 10.0)
		r.vy = -randf_range(1.05, 1.3) * _h
		r.top = randf_range(0.14, 0.38) * _h
		r.col = COLS[randi() % COLS.size()]
		r.delay = i * 0.22 + randf() * 0.1
		_rockets.append(r)
	for i in _n(40):
		_confetti(Vector2(randf() * _w, -randf_range(10.0, 140.0)), Vector2(randf_range(-40.0, 40.0), randf_range(30.0, 120.0)))


func _rain() -> void:
	for i in _n(170):
		_confetti(Vector2(randf() * _w, -randf_range(10.0, _h * 0.6)), Vector2(randf_range(-50.0, 50.0), randf_range(40.0, 160.0)))


func _process(delta: float) -> void:
	var dt := minf(0.05, delta)
	for i in range(_rockets.size() - 1, -1, -1):
		var k := _rockets[i]
		k.delay -= dt
		if k.delay > 0.0:
			continue
		k.pos.y += k.vy * dt
		k.vy *= pow(0.985, dt * 60.0)
		if k.pos.y <= k.top:
			_spark(k.pos, k.col, _n(46), _h * 0.42 * _v())
			_spark(k.pos, SPARK_HI, _n(14), _h * 0.2 * _v())
			_rockets.remove_at(i)
			if intensity >= 0.75:
				Sound.sfx("tick")
		else:
			var p := Part.new()
			p.confetti = false
			p.pos = k.pos + Vector2(randf_range(-2.0, 2.0), 6.0)
			p.vel = Vector2(randf_range(-15.0, 15.0), randf_range(20.0, 60.0))
			p.col = TRAIL
			p.max_t = 0.35
			p.s = 1.6
			_parts.append(p)
	var drag_c := pow(0.985, dt * 60.0)
	var drag_s := pow(0.96, dt * 60.0)
	for i in range(_parts.size() - 1, -1, -1):
		var p := _parts[i]
		p.t += dt
		if p.t >= p.max_t:
			_parts.remove_at(i)
			continue
		if p.confetti:
			p.vel.y += _h * 0.9 * dt
			p.vel *= drag_c
			p.vel.y = minf(p.vel.y, _h * 0.32)
			p.sw += dt * 5.0
			p.rot += p.vr * dt
			p.pos.x += (p.vel.x + sin(p.sw) * 30.0) * dt
		else:
			p.vel.y += _h * 0.25 * dt
			p.vel *= drag_s
			p.pos.x += p.vel.x * dt
		p.pos.y += p.vel.y * dt
	if _parts.is_empty() and _rockets.is_empty():
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	for p in _parts:
		var fade := minf(1.0, (p.max_t - p.t) / 0.5)
		if p.confetti:
			# a paper square tumbling: squash on one axis as it flips, the back face a little darker
			var flip := cos(p.sw)
			var c := p.col if flip >= 0.0 else p.col.darkened(0.22)
			c.a = fade
			draw_set_transform(p.pos, p.rot, Vector2(1.0, absf(flip) * 0.8 + 0.2))
			if p.strip:
				draw_texture_rect(_paper, Rect2(-p.s * 0.65, -p.s * 0.17, p.s * 1.3, p.s * 0.34), false, c)
			else:
				draw_texture_rect(_paper, Rect2(-p.s * 0.55, -p.s * 0.3, p.s * 1.1, p.s * 0.6), false, c)
		else:
			draw_set_transform(Vector2.ZERO)
			var c := p.col
			c.a = fade * 0.25
			draw_circle(p.pos, p.s * 2.0, c, true, -1.0, true)
			c.a = fade * 0.95
			draw_circle(p.pos, p.s, c, true, -1.0, true)
	draw_set_transform(Vector2.ZERO)
	for k in _rockets:
		if k.delay <= 0.0:
			var c := k.col
			c.a = 0.3
			draw_circle(k.pos, 6.0, c, true, -1.0, true)
			draw_circle(k.pos, 3.0, k.col, true, -1.0, true)
			draw_circle(k.pos, 1.5, Color.WHITE, true, -1.0, true)
