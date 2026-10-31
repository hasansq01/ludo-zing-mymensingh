class_name Rooms
extends Node3D
## The café's room themes around the shared table (index.html: ROOM_LIST, MOOD, Rooms, BUILD.*): each theme is a
## group built on first use; only the chosen one is visible. Its mood sets the background, fog, hemisphere fill,
## key light and table tint on the TableWorld.
## Builders put pieces under `_cur` (the room being built) with the helpers below, in the web version's units.

## l10n-keys: desc
const LIST := [
	{id = "night", name = "Moonlit Café", price = 0, desc = "The café after dark: string lights, candles, stars."},
	{id = "cafe", name = "Corner Café", price = 0, desc = "Honey wood, peach brick and pastel cups."},
	{id = "dream", name = "Pastel Dream Room", price = 3000, desc = "Blush and lavender, fairy lights, a cosy bed."},
	{id = "studio", name = "Sunny Cozy Studio", price = 4000, desc = "Butter-yellow walls, warm wood, soft sunbeams."},
	{id = "cloud", name = "Cloudside Playroom", price = 5000, desc = "Sky-blue walls, floating clouds, toy blocks."},
]
const DEFAULT := "night"
## bg (+ fog), hemisphere [sky, ground, intensity], key [colour, intensity], table tint, dark (night captions)
const MOOD := {
	night = {bg = Color("#2b2244"), hemi = [Color("#8a6aa8"), Color("#8a5038"), 0.32], key = [Color("#ffd6a0"), 0.85], table = Color("#fff0dc"), dark = true},
	cafe = {bg = Color("#f6e3d2"), hemi = [Color("#fff1e0"), Color("#f0c8a8"), 0.5], key = [Color("#fff1dc"), 0.9], table = Color("#ffffff"), dark = false},
	dream = {bg = Color("#f3e0f0"), hemi = [Color("#fff0f8"), Color("#e6d0ff"), 0.5], key = [Color("#fff0f4"), 0.85], table = Color("#fff3f3"), dark = false},
	studio = {bg = Color("#fbe9cc"), hemi = [Color("#fff6dc"), Color("#f2c89a"), 0.5], key = [Color("#fff2d6"), 0.95], table = Color("#ffffff"), dark = false},
	cloud = {bg = Color("#dff0ff"), hemi = [Color("#f0f8ff"), Color("#d9e8ff"), 0.52], key = [Color("#fff6ec"), 0.88], table = Color("#fff8f0"), dark = false},
}
## Calibration to the three.js render. With no shadow pass (see TableWorld.SHADOWS) every light adds in linear
## light as in three.js, so the key spot takes the web intensity as is (per-light probes: Godot 0.94 = web 0.94 on
## a white Lambert square at the board centre). The old 0.647 only made up for the sRGB-space shadow pass.
const KEY_SCALE := 1.0

var world: TableWorld
var current := ""
var _built := {}                         # id -> Node3D
var _room_anims := {}                    # id -> [Callable(t)]
var _cur: Node3D
var _anims := []
var rng := RandomNumberGenerator.new()

func _init(world_: TableWorld) -> void:
	world = world_
	name = "Rooms"

static func info(id: String) -> Dictionary:
	for r in LIST:
		if r.id == id:
			return r
	return {}

## Build a theme if needed (awaitable: textures are painted on the GPU), then show it and apply its mood.
func set_room(baker: TexBaker, id: String) -> void:
	if not MOOD.has(id):
		id = DEFAULT
	if not _built.has(id):
		await build(baker, id)
	for k in _built:
		_built[k].visible = k == id
	current = id
	apply_mood(id)

func build(baker: TexBaker, id: String) -> void:
	rng.seed = hash(id)
	_cur = Node3D.new()
	_cur.name = "Room_" + id
	_cur.visible = false
	add_child(_cur)
	_anims = []
	match id:
		"night":
			await _build_cafe(baker, true)
		"cafe":
			await _build_cafe(baker, false)
		_:
			# the other themes live in their own files: res://scripts/world/rooms/<id>.gd, `static func build(rooms, baker)`
			var path := "res://scripts/world/rooms/%s.gd" % id
			if ResourceLoader.exists(path):
				await load(path).build(self, baker)
			else:
				await _build_cafe(baker, true)
	_built[id] = _cur
	_room_anims[id] = _anims

func apply_mood(id: String) -> void:
	var m: Dictionary = MOOD[id]
	var env := world.env
	env.background_color = m.bg
	env.fog_light_color = m.bg
	# the hemisphere light: a flat ambient at the mean of its sky and ground colours (in linear light), plus a light
	# from above in (sky - ground) / 2 and a negative one from below in the same colour (TableWorld.hemi)
	var sky: Color = m.hemi[0]
	var ground: Color = m.hemi[1]
	env.ambient_light_color = sky.srgb_to_linear().lerp(ground.srgb_to_linear(), 0.5).linear_to_srgb()
	env.ambient_light_energy = m.hemi[2]
	var d := (sky.srgb_to_linear() - ground.srgb_to_linear()) * 0.5 * float(m.hemi[2])
	var dm := maxf(0.0001, maxf(d.r, maxf(d.g, d.b)))
	for hl in world.hemi:
		hl.light_color = Color(maxf(d.r, 0) / dm, maxf(d.g, 0) / dm, maxf(d.b, 0) / dm).linear_to_srgb()
		hl.light_energy = dm if dm > 0.002 else 0.0
		hl.visible = hl.light_energy > 0.0
	world.key.light_color = m.key[0]
	world.key.light_energy = m.key[1] * KEY_SCALE
	world.set_table_tint(m.table)

func tick(t: float) -> void:
	for a in _room_anims.get(current, []):
		a.call(t)

static func _hsl(h: float, s: float, l: float) -> Color:
	# CSS hsl() -> Color
	s /= 100.0; l /= 100.0
	var cc := (1.0 - absf(2 * l - 1)) * s
	var hh := fmod(h / 60.0, 6.0)
	var x := cc * (1.0 - absf(fmod(hh, 2.0) - 1))
	var rgb := Vector3.ZERO
	if hh < 1: rgb = Vector3(cc, x, 0)
	elif hh < 2: rgb = Vector3(x, cc, 0)
	elif hh < 3: rgb = Vector3(0, cc, x)
	elif hh < 4: rgb = Vector3(0, x, cc)
	elif hh < 5: rgb = Vector3(x, 0, cc)
	else: rgb = Vector3(cc, 0, x)
	var m := l - cc / 2
	return Color(rgb.x + m, rgb.y + m, rgb.z + m)

func _paint_planks(c: Control) -> void:
	var w := c.size.x
	var h := c.size.y
	var rows := 8
	var rh := h / rows
	var rr := RandomNumberGenerator.new(); rr.seed = 11
	for r in rows:
		var x := -rr.randf_range(0, 400)
		while x < w:
			var ln := rr.randf_range(260, 520)
			c.draw_rect(Rect2(x, r * rh, ln, rh), _hsl(31 + rr.randf_range(-3, 3), 62, 70 + rr.randf_range(-4, 4)))
			for k in 5:
				var y := r * rh + rr.randf_range(4, rh - 4)
				c.draw_line(Vector2(x, y), Vector2(x + ln, y + rr.randf_range(-6, 6)), Color(150 / 255.0, 90 / 255.0, 50 / 255.0, 0.12), 1.5, true)
			c.draw_rect(Rect2(x, r * rh, 2, rh), Color(140 / 255.0, 80 / 255.0, 50 / 255.0, 0.22))
			x += ln
		c.draw_rect(Rect2(0, r * rh, w, 2.5), Color(140 / 255.0, 80 / 255.0, 50 / 255.0, 0.25))
		c.draw_rect(Rect2(0, r * rh + 3, w, 2), Color(1, 1, 1, 0.18))

func _paint_brick(c: Control) -> void:
	var w := c.size.x
	var h := c.size.y
	c.draw_rect(Rect2(Vector2.ZERO, c.size), Color("#fff3ea"))
	var rr := RandomNumberGenerator.new(); rr.seed = 5
	var bw := 64.0
	var bh := 30.0
	for r in int(h / bh) + 1:
		for k in range(-1, int(w / bw) + 2):
			var x := k * bw + (r % 2) * bw / 2
			TexBaker.round_rect(c, Rect2(x + 3, r * bh + 3, bw - 6, bh - 6), 5, _hsl(rr.randf_range(14, 26), rr.randf_range(62, 78), rr.randf_range(80, 87)))

func _wall_painter(top: Color, bottom: Color, wains: float, dots: bool) -> Callable:
	return func(c: Control):
		var h := c.size.y
		for k in 32:
			c.draw_rect(Rect2(0, h * k / 32.0, c.size.x, h / 32.0 + 1), top.lerp(bottom, k / 31.0))
		if dots:
			var y := 26.0
			var row := 0
			while y < h * (1 - wains) - 10:
				var x := (row % 2) * 32 + 18.0
				while x < c.size.x:
					TexBaker.circle(c, Vector2(x, y), 4.5, Color(1, 1, 1, 0.55))
					x += 64
				y += 46; row += 1
		if wains > 0:
			c.draw_rect(Rect2(0, h * (1 - wains), c.size.x, h * wains), Color("#fffaf4"))
			c.draw_rect(Rect2(0, h * (1 - wains), c.size.x, 6), Color(200 / 255.0, 150 / 255.0, 120 / 255.0, 0.25))
			var x := 20.0
			while x < c.size.x:                       # wainscot panels
				c.draw_rect(Rect2(x, h * (1 - wains) + 22, 72, h * wains - 44), Color(200 / 255.0, 150 / 255.0, 120 / 255.0, 0.18), false, 3.0)
				x += 92

func _paint_night_sky(c: Control) -> void:
	var w := c.size.x
	var h := c.size.y
	var stops := [[0.0, Color("#1f1a4a")], [0.55, Color("#3d2f70")], [1.0, Color("#8a5a86")]]
	for k in 64:
		var t := k / 63.0
		var col: Color = stops[0][1]
		for s in 2:
			if t >= stops[s][0] and t <= stops[s + 1][0]:
				col = (stops[s][1] as Color).lerp(stops[s + 1][1], (t - stops[s][0]) / (stops[s + 1][0] - stops[s][0]))
		c.draw_rect(Rect2(0, h * k / 64.0, w, h / 64.0 + 1), col)
	var rr := RandomNumberGenerator.new(); rr.seed = 3
	for k in 40:
		c.draw_colored_polygon(TexBaker.star_points(Vector2(rr.randf_range(0, w), rr.randf_range(0, h * 0.6)), rr.randf_range(2, 5)), Color(1, 1, 1, 0.85))
	TexBaker.circle(c, Vector2(w * 0.3, h * 0.24), 38, Color("#fff6d6"))
	TexBaker.circle(c, Vector2(w * 0.3 + 18, h * 0.24 - 8), 34, Color("#1f1a4a").lerp(Color("#3d2f70"), 0.4))
	var x := -10.0
	while x < w:                                  # rooftops across the street with a few warm windows
		var bw := rr.randf_range(50, 110)
		var bh := rr.randf_range(120, 300)
		c.draw_rect(Rect2(x, h - bh, bw, bh), Color("#2a2350"))
		var yy := h - bh + 16
		while yy < h - 10:
			var xx := x + 9
			while xx < x + bw - 12:
				if rr.randf() < 0.3:
					c.draw_rect(Rect2(xx, yy, 9, 11), Color(1, 214 / 255.0, 140 / 255.0, 0.9) if rr.randf() < 0.7 else Color(1, 180 / 255.0, 200 / 255.0, 0.85))
				xx += 20
			yy += 24
		x += bw + rr.randf_range(6, 18)

## index.html skyTex({stops: #8fcaff / #cfe8ff / #ffe8d2, clouds: 7, sun, hills: #a8dca0}): a sunny afternoon.
func _paint_day_sky(c: Control) -> void:
	var w := c.size.x
	var h := c.size.y
	var stops := [[0.0, Color("#8fcaff")], [0.6, Color("#cfe8ff")], [1.0, Color("#ffe8d2")]]
	for k in 64:
		var t := k / 63.0
		var col: Color = stops[0][1]
		for s in 2:
			if t >= stops[s][0] and t <= stops[s + 1][0]:
				col = (stops[s][1] as Color).lerp(stops[s + 1][1], (t - stops[s][0]) / (stops[s + 1][0] - stops[s][0]))
		c.draw_rect(Rect2(0, h * k / 64.0, w, h / 64.0 + 1), col)
	for k in 24:                                  # the sun's soft glow, then its disc
		TexBaker.circle(c, Vector2(w * 0.7, h * 0.32), 160.0 * (1.0 - k / 24.0), Color(1, 0.94, 0.75, 0.05 + 0.02 * k / 24.0))
	TexBaker.circle(c, Vector2(w * 0.7, h * 0.32), 40, Color(1, 0.98, 0.86))
	var rr := RandomNumberGenerator.new(); rr.seed = 4
	for k in 7:
		var cx := rr.randf_range(-20, w + 20)
		var cy := rr.randf_range(h * 0.2, h * 0.75)
		var sz := rr.randf_range(22, 44)
		for b in [[0, 0, 1.0], [-1.1, 0.3, 0.7], [1.1, 0.3, 0.75], [-0.5, -0.35, 0.8], [0.5, -0.3, 0.7]]:
			TexBaker.circle(c, Vector2(cx + b[0] * sz, cy + b[1] * sz), b[2] * sz, Color(1, 1, 1, 0.92))
	var hills := PackedVector2Array([Vector2(0, h)])
	var x := 0.0
	while x <= w:
		hills.append(Vector2(x, h * 0.86 - sin(x / 70.0) * 22 - sin(x / 23.0) * 6))
		x += 8
	hills.append(Vector2(w, h))
	c.draw_colored_polygon(hills, Color("#a8dca0"))

func _paint_rug(c: Control) -> void:
	var w := c.size.x
	c.draw_rect(Rect2(Vector2.ZERO, c.size), Color("#ffe3c8"))
	var cols := [Color("#ffd0a6"), Color("#fff4e6"), Color("#ffc28f")]
	for k in 3:
		c.draw_arc(c.size / 2, w / 2 - 20 - k * 30, 0, TAU, 128, cols[k], 14, true)
	var rr := RandomNumberGenerator.new(); rr.seed = 9
	for k in 2000:
		c.draw_rect(Rect2(rr.randf_range(0, w), rr.randf_range(0, w), 2, 2), Color(1, 1, 1, rr.randf_range(0, 0.08)))

func _paint_menu(c: Control) -> void:
	var w := c.size.x
	c.draw_rect(Rect2(Vector2.ZERO, c.size), Color("#fffaf2"))
	var f: Font = UIKit.font_display()
	var title := tr("Today's Brew")
	var tw := f.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 76).x
	c.draw_string(f, Vector2((w - tw) / 2, 112), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 76, Color("#ff8f7a"))
	var items := [["Espresso", "2.50"], ["Cappuccino", "3.20"], ["Flat White", "3.40"], ["Honey Latte", "3.80"], ["Lavender Mocha", "3.90"], ["Ludo & Latte", "5.00"]]
	var body: Font = UIKit.font_body(700)
	for k in items.size():
		var col := Color("#e08a10") if k == 5 else Color("#5a3348")
		c.draw_string(body, Vector2(110, 214 + k * 74), items[k][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 44, col)
		var pw := body.get_string_size(items[k][1], HORIZONTAL_ALIGNMENT_LEFT, -1, 44).x
		c.draw_string(body, Vector2(w - 110 - pw, 214 + k * 74), items[k][1], HORIZONTAL_ALIGNMENT_LEFT, -1, 44, col)
	var dots := [Color("#ffb3c7"), Color("#b49cff"), Color("#7cc4ff"), Color("#9fe3d2")]
	for k in 4:
		TexBaker.circle(c, Vector2(70 + k * 30, 640), 10, dots[k])

func _art_painter(pal: Array, kind: String) -> Callable:
	return func(c: Control):
		var w := c.size.x
		var h := c.size.y
		c.draw_rect(Rect2(Vector2.ZERO, c.size), pal[0])
		if kind == "arch":
			for e in [[pal[1], 110.0], [pal[2], 80.0], [pal[3], 50.0]]:
				var pts := PackedVector2Array()
				for k in 33:
					var a := PI + PI * k / 32.0
					pts.append(Vector2(w / 2, h * 0.72) + Vector2(cos(a), sin(a)) * e[1])
				c.draw_colored_polygon(pts, e[0])
			TexBaker.circle(c, Vector2(w * 0.76, h * 0.25), 26, pal[4] if pal.size() > 4 else pal[1])
		else:
			var rr := RandomNumberGenerator.new(); rr.seed = 21
			for k in 6:
				TexBaker.circle(c, Vector2(rr.randf_range(40, w - 40), rr.randf_range(40, h - 40)), rr.randf_range(24, 62), pal[1 + (k % (pal.size() - 1))])


# ---------- the Moonlit Café (BUILD.cafe(true)) ----------


func _build_cafe(baker: TexBaker, night: bool) -> void:
	var planks := await baker.bake(Vector2i(1024, 1024), _paint_planks)
	var brick := await baker.bake(Vector2i(640, 512), _paint_brick)
	var wall_l := await baker.bake(Vector2i(640, 512), _wall_painter(Color("#ffeede"), Color("#ffe3cf"), 0.3, false))
	var wall_r := await baker.bake(Vector2i(640, 512), _wall_painter(Color("#fff1c9"), Color("#ffe7b0"), 0.3, true))
	var sky := await baker.bake(Vector2i(512, 640), _paint_night_sky if night else _paint_day_sky)
	var rug := await baker.bake(Vector2i(512, 512), _paint_rug)
	var menu := await baker.bake(Vector2i(1024, 680), _paint_menu)
	var arts := [
		await baker.bake(Vector2i(256, 320), _art_painter([Color("#fff1e0"), Color("#ffb98a"), Color("#ff8f7a"), Color("#ffd86b"), Color("#7cc4ff")], "arch")),
		await baker.bake(Vector2i(256, 320), _art_painter([Color("#eef5ff"), Color("#b49cff"), Color("#7cc4ff"), Color("#ffb3c7")], "dots")),
		await baker.bake(Vector2i(256, 320), _art_painter([Color("#fff4f8"), Color("#9fe3d2"), Color("#ffd86b"), Color("#ff8f7a"), Color("#b49cff")], "arch")),
	]
	var R := _cur
	# shell: floor, ceiling, four walls, skirting and cornice
	MeshKit.put(R, MeshKit.plane(2 * TableWorld.W, 2 * TableWorld.W), MeshKit.tex_mat(planks, 0.5, Vector2(3, 3)), Vector3(0, TableWorld.Y0, 0), Vector3.ZERO, Vector3.ONE, false)
	MeshKit.put(R, MeshKit.plane(2 * TableWorld.W, 2 * TableWorld.W), MeshKit.mat(Color("#fff7f0"), 0.95), Vector3(0, TableWorld.Y0 + TableWorld.H, 0), Vector3(PI, 0, 0), Vector3.ONE, false)
	var walls := {back = MeshKit.tex_mat(brick, 0.9, Vector2(4, 4)), left = MeshKit.tex_mat(wall_l, 0.9), right = MeshKit.tex_mat(wall_r, 0.9), front = MeshKit.tex_mat(wall_l, 0.9)}
	for side in ["back", "left", "right", "front"]:
		var g := _wall_group(side, 0)
		MeshKit.put(g, MeshKit.plane(2 * TableWorld.W, TableWorld.H), walls[side], Vector3(0, TableWorld.H / 2, 0), Vector3(PI / 2, 0, 0), Vector3.ONE, false)
		MeshKit.put(g, MeshKit.rbox(2 * TableWorld.W, 3.2, 1.4, 0.5), MeshKit.mat(Color.WHITE, 0.35), Vector3(0, 1.6, 0.7))
		MeshKit.put(g, MeshKit.rbox(2 * TableWorld.W, 2, 1.6, 0.6), MeshKit.mat(Color.WHITE, 0.35), Vector3(0, TableWorld.H - 1, 0.8), Vector3.ZERO, Vector3.ONE, false)
	var honey := MeshKit.mat(Color("#e8a868"), 0.35)
	var cream := MeshKit.mat(Color("#fff4ea"), 0.3)
	var enamel := MeshKit.mat(Color("#fff8f0"), 0.28)
	var chrome := MeshKit.mat(Color("#e9ecf2"), 0.18, 0.85)
	# round rug under the table
	var rugm := MeshKit.tex_mat(rug, 1.0)
	MeshKit.put(R, TableWorld._disc(25, 64), rugm, Vector3(0, TableWorld.Y0 + 0.08, 0), Vector3.ZERO, Vector3.ONE, false)
	# counter along the back wall, espresso machine, grinder, cake dome, cups, stools
	var BZ := -52.0
	var CT := TableWorld.Y0 + 41.6
	MeshKit.put(R, MeshKit.rbox(84, 40, 12, 1.4), cream, Vector3(0, TableWorld.Y0 + 20, BZ))
	for k in range(-3, 4):
		MeshKit.put(R, MeshKit.rbox(10, 30, 0.6, 0.3), MeshKit.mat(Color("#ffe2cc"), 0.4), Vector3(k * 11.5, TableWorld.Y0 + 20, BZ + 6.2), Vector3.ZERO, Vector3.ONE, false)
	MeshKit.put(R, MeshKit.rbox(87, 2, 14, 0.8), honey, Vector3(0, TableWorld.Y0 + 40.8, BZ + 0.5))
	MeshKit.put(R, MeshKit.cylinder(0.4, 0.4, 84, 12), MeshKit.mat(Color("#f2c06b"), 0.25, 0.5), Vector3(0, TableWorld.Y0 + 5, BZ + 7.6), Vector3(0, 0, PI / 2), Vector3.ONE, false)
	MeshKit.put(R, MeshKit.rbox(20, 12, 9, 1.4), MeshKit.mat(Color("#9fe3d2"), 0.25), Vector3(-16, CT + 6, BZ - 1))
	MeshKit.put(R, MeshKit.rbox(20.4, 1.4, 9.4, 0.5), chrome, Vector3(-16, CT + 12.6, BZ - 1))
	for x in [-21.0, -11.0]:
		MeshKit.put(R, MeshKit.cylinder(1.2, 1.2, 1.6, 20), chrome, Vector3(x, CT + 3.8, BZ + 4))
		world.cup(R, Vector3(x, CT + 0.6 - TableWorld.TT, BZ + 4), rng.randf_range(0, 6), Color("#fffaf2"))
	MeshKit.put(R, MeshKit.rbox(5.6, 9, 5.6, 1.4), MeshKit.mat(Color("#ffd86b"), 0.3), Vector3(-32, CT + 4.5, BZ - 1))
	var glass := MeshKit.mat(Color(0.75, 0.5, 0.31, 0.75), 0.15)
	glass = glass.duplicate(); glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	MeshKit.put(R, MeshKit.cylinder(3.4, 1.4, 6, 24), glass, Vector3(-32, CT + 12, BZ - 1))
	MeshKit.put(R, MeshKit.cylinder(5, 5, 0.4, 32), cream, Vector3(18, CT + 2.2, BZ))
	MeshKit.put(R, MeshKit.cylinder(0.6, 1.6, 2, 16), cream, Vector3(18, CT + 1, BZ))
	MeshKit.put(R, MeshKit.cylinder(3, 3, 2.4, 32), MeshKit.mat(Color("#ffb3c7"), 0.6), Vector3(18, CT + 3.6, BZ))
	MeshKit.put(R, MeshKit.cylinder(3.05, 3.05, 0.5, 32), MeshKit.mat(Color("#fff6ee"), 0.5), Vector3(18, CT + 5, BZ))
	var dome := MeshKit.mat(Color(1, 1, 1, 0.18), 0.05).duplicate()
	dome.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var dm := SphereMesh.new(); dm.radius = 5; dm.height = 10; dm.is_hemisphere = true
	MeshKit.put(R, dm, dome, Vector3(18, CT + 2.4, BZ), Vector3.ZERO, Vector3.ONE, false)
	var cup_cols := [Color("#ffc6a5"), Color("#d8caff"), Color("#bfe3ff"), Color("#fffaf2")]
	var cup_mesh := MeshKit.lathe(PackedVector2Array([Vector2(0, 0), Vector2(1.05, 0), Vector2(1.2, 0.15), Vector2(1.45, 1.4), Vector2(1.62, 2.9), Vector2(1.55, 3), Vector2(1.45, 1.5), Vector2(1.12, 0.32), Vector2(0, 0.32)]), 40)
	for k in 4:
		MeshKit.put(R, cup_mesh, MeshKit.mat(cup_cols[k], 0.2), Vector3(32, CT + k * 1.4, BZ - 2))
	MeshKit.put(R, MeshKit.rbox(4.4, 7, 4.4, 1.2), MeshKit.mat(Color("#ffb98a"), 0.2), Vector3(38, CT + 3.5, BZ + 1))
	for x in [-30.0, -15.0, 0.0, 15.0, 30.0]:
		MeshKit.put(R, MeshKit.cylinder(3.6, 3.6, 1.8, 28), MeshKit.mat(Color("#ffb98a"), 0.6), Vector3(x, TableWorld.Y0 + 28, BZ + 12))
		MeshKit.put(R, MeshKit.torus(3.5, 0.55, 28, 10), MeshKit.mat(Color("#ffb98a"), 0.6), Vector3(x, TableWorld.Y0 + 28.6, BZ + 12))
		MeshKit.put(R, MeshKit.cylinder(0.6, 0.6, 27, 12), enamel, Vector3(x, TableWorld.Y0 + 13.5, BZ + 12))
		MeshKit.put(R, MeshKit.torus(2.6, 0.3, 28, 8), honey, Vector3(x, TableWorld.Y0 + 9, BZ + 12))
		MeshKit.put(R, MeshKit.cylinder(3.4, 3.8, 0.6, 28), enamel, Vector3(x, TableWorld.Y0 + 0.3, BZ + 12))
	# shelves with pastel jars on the back wall
	for y in [TableWorld.Y0 + 54, TableWorld.Y0 + 68]:
		MeshKit.put(R, MeshKit.rbox(56, 1.4, 6, 0.5), honey, Vector3(-14, y, -TableWorld.W + 3))
		var x := -40.0
		while x < 12:
			var kind := rng.randf()
			var col: Color = [Color("#d8caff"), Color("#bfe3ff"), Color("#ffc6a5"), Color("#9fe3d2"), Color("#fff2b8")][rng.randi_range(0, 4)]
			if kind < 0.45:
				var jh := rng.randf_range(4, 6.5)
				MeshKit.put(R, MeshKit.rbox(3.4, jh, 3.4, 1), MeshKit.mat(col, 0.15), Vector3(x, y + 0.7 + jh / 2, -TableWorld.W + 3))
			elif kind < 0.75:
				MeshKit.put(R, cup_mesh, MeshKit.mat(col, 0.2), Vector3(x, y + 0.6, -TableWorld.W + 3))
			else:
				var bh := rng.randf_range(7, 9)
				MeshKit.put(R, MeshKit.cylinder(0.9, 1.2, bh, 14), MeshKit.mat(col, 0.1), Vector3(x, y + 0.7 + bh / 2, -TableWorld.W + 3))
			x += rng.randf_range(4.5, 7)
	# menu board
	var mb := _wall_group("back", 34)
	MeshKit.put(mb, MeshKit.rbox(32, 22, 1.2, 0.6), honey, Vector3(0, 62, 1))
	var mm := MeshKit.tex_mat(menu, 0.8)
	MeshKit.put(mb, MeshKit.plane(30, 20), mm, Vector3(0, 62, 1.7), Vector3(PI / 2, 0, 0), Vector3.ONE, false)
	# string lights over the counter and along the right wall
	_fairy(R, Vector3(-TableWorld.W + 4, TableWorld.Y0 + 82, -TableWorld.W + 4), Vector3(TableWorld.W - 4, TableWorld.Y0 + 82, -TableWorld.W + 4), 7, 22, [Color("#fff0c8"), Color("#ffd6e6"), Color("#d9f0ff")], 0.6 if night else 0.5)
	if night:
		_fairy(R, Vector3(TableWorld.W - 4, TableWorld.Y0 + 84, -TableWorld.W + 4), Vector3(TableWorld.W - 4, TableWorld.Y0 + 84, TableWorld.W - 4), 8, 22, [Color("#fff0c8"), Color("#ffd6e6"), Color("#e6dcff")], 0.6)
	# window wall: three windows to a starry evening with a moon and lit windows across the street
	for k in 3:
		var wg := _window("left", [-32.0, 0.0, 32.0][k], 48, 20, 34, sky)
		if k != 1:
			var pl := _plant(wg, 0, 4, 0.5, Color("#ffc6a5"))
			pl.position.y = 29.6
	# gallery wall: pastel prints in honey frames
	var gal := _wall_group("right", 0)
	for k in 3:
		MeshKit.put(gal, MeshKit.rbox(17.2, 21.2, 1, 0.45), honey, Vector3([-30, 0, 30][k], 56, 0.7))
		MeshKit.put(gal, MeshKit.plane(15, 19), MeshKit.tex_mat(arts[k], 0.7), Vector3([-30, 0, 30][k], 56, 1.25), Vector3(PI / 2, 0, 0), Vector3.ONE, false)
	# other café tables with pastel chairs and candle jars
	var chair_cols := [Color("#9fe3d2"), Color("#ffb98a"), Color("#d8caff"), Color("#bfe3ff")]
	var tables := [[-40.0, -10.0], [42.0, 8.0], [-32.0, 38.0], [34.0, 40.0]]
	for seed in 4:
		var x: float = tables[seed][0]
		var z: float = tables[seed][1]
		MeshKit.put(R, MeshKit.cylinder(9, 9, 1.2, 40), honey, Vector3(x, TableWorld.TT - 0.6, z))
		MeshKit.put(R, MeshKit.cylinder(0.9, 1.3, 28, 16), enamel, Vector3(x, TableWorld.Y0 + 14.6, z))
		MeshKit.put(R, MeshKit.cylinder(5, 5.5, 0.8, 32), enamel, Vector3(x, TableWorld.Y0 + 0.4, z))
		for k in 2:
			var a := k * PI + seed
			var chair := Node3D.new()
			chair.position = Vector3(x + cos(a) * 13, TableWorld.Y0, z + sin(a) * 13)
			chair.rotation.y = -a + PI / 2
			R.add_child(chair)
			var cm := MeshKit.mat(chair_cols[(seed + k) % 4], 0.45)
			MeshKit.put(chair, MeshKit.rbox(9, 1.6, 9, 0.7), cm, Vector3(0, 18, 0))
			MeshKit.put(chair, MeshKit.rbox(9, 11, 1.6, 0.8), cm, Vector3(0, 25, 4.1))
			for l in [[-3.8, -3.8], [3.8, -3.8], [-3.8, 3.8], [3.8, 3.8]]:
				MeshKit.put(chair, MeshKit.cylinder(0.45, 0.4, 18, 8), enamel, Vector3(l[0], 9, l[1]))
		world.cup(R, Vector3(x + rng.randf_range(-3, 3), -0.1 - TableWorld.TT + TableWorld.TT, z + rng.randf_range(-3, 3)), rng.randf_range(0, 6), [Color("#fffaf2"), Color("#d8caff"), Color("#ffc6a5")][seed % 3])
		if not night:
			continue
		var jar := MeshKit.emissive(Color("#ffc98a"), 0.6)   # a little candle jar on every table, after dark
		jar.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		jar.albedo_color.a = 0.75
		MeshKit.put(R, MeshKit.cylinder(1, 1, 2.2, 20), jar, Vector3(x - 3, TableWorld.TT + 1.1, z + 2), Vector3.ZERO, Vector3.ONE, false)
		MeshKit.put(R, MeshKit.sphere(1, 12, 9), MeshKit.unlit(Color("#fff0c0")), Vector3(x - 3, TableWorld.TT + 2.6, z + 2), Vector3.ZERO, Vector3(0.3, 0.55, 0.3), false)
		var f := MeshKit.glow(Color("#ffc070"), 7, 0.6)
		f.position = Vector3(x - 3, TableWorld.TT + 2.6, z + 2)
		R.add_child(f)
		var sd := float(seed)
		_anims.append(func(t: float): f.modulate.a = 0.5 + 0.12 * sin(t * 7 + sd * 3) + 0.06 * sin(t * 13 + sd))
	_plant(R, -52, -50, 1.3); _plant(R, 52, -48, 1.1, Color("#ffc6a5")); _plant(R, -52, 52, 1.4, Color("#d8caff"))
	_plant(R, 52, 52, 1.2); _plant(R, -52, 16, 0.9, Color("#bfe3ff"))
	for p in [[-28.0, Color("#fff4ea")], [0.0, Color("#ffc6a5")], [28.0, Color("#d8caff")]]:
		_pendant(R, p[0], BZ, TableWorld.Y0 + 70, p[1], 0.8 if night else 0.5)
	_pendant(R, 0, 0, 42, Color("#fff4ea"), 0.8 if night else 0.5)
	# warm lamplight pools inside, cool moonlight at the windows
	if night:
		_omni(Color("#ffb870"), 1.15, 120, Vector3(-20, TableWorld.Y0 + 62, BZ + 10))
		_omni(Color("#9a8cff"), 0.35, 130, Vector3(-46, TableWorld.Y0 + 50, 0))
		_omni(Color("#ffb070"), 0.85, 110, Vector3(30, TableWorld.Y0 + 62, 30))
	else:
		_omni(Color("#ffd9a8"), 0.5, 120, Vector3(-24, TableWorld.Y0 + 64, BZ + 8))
		_omni(Color("#fff0dc"), 0.38, 140, Vector3(-44, TableWorld.Y0 + 50, 0))
		_omni(Color("#ffe6c8"), 0.3, 140, Vector3(34, TableWorld.Y0 + 70, 40))

## A group on a wall's foot line: local x runs along the wall, +z points into the room, y = 0 is the floor.
func _wall_group(side: String, u: float) -> Node3D:
	var g := Node3D.new()
	match side:
		"back":
			g.position = Vector3(u, TableWorld.Y0, -TableWorld.W)
		"front":
			g.position = Vector3(-u, TableWorld.Y0, TableWorld.W); g.rotation.y = PI
		"left":
			g.position = Vector3(-TableWorld.W, TableWorld.Y0, -u); g.rotation.y = PI / 2
		_:
			g.position = Vector3(TableWorld.W, TableWorld.Y0, u); g.rotation.y = -PI / 2
	_cur.add_child(g)
	return g

func _window(side: String, u: float, y: float, w: float, h: float, sky: Texture2D) -> Node3D:
	var g := _wall_group(side, u)
	var fm := MeshKit.mat(Color.WHITE, 0.3)
	var t := 1.5
	MeshKit.put(g, MeshKit.plane(w, h), MeshKit.unlit(Color.WHITE, sky), Vector3(0, y, 0.2), Vector3(PI / 2, 0, 0), Vector3.ONE, false)
	MeshKit.put(g, MeshKit.rbox(w + 2 * t, t, 1.8, 0.6), fm, Vector3(0, y + h / 2 + t / 2, 0.9))
	MeshKit.put(g, MeshKit.rbox(w + 2 * t, t, 1.8, 0.6), fm, Vector3(0, y - h / 2 - t / 2, 0.9))
	MeshKit.put(g, MeshKit.rbox(t, h, 1.8, 0.6), fm, Vector3(-w / 2 - t / 2, y, 0.9))
	MeshKit.put(g, MeshKit.rbox(t, h, 1.8, 0.6), fm, Vector3(w / 2 + t / 2, y, 0.9))
	MeshKit.put(g, MeshKit.rbox(0.9, h, 0.9, 0.35), fm, Vector3(0, y, 0.6))
	MeshKit.put(g, MeshKit.rbox(w, 0.9, 0.9, 0.35), fm, Vector3(0, y + h * 0.14, 0.6))
	MeshKit.put(g, MeshKit.rbox(w + 7, 1.3, 5, 0.6), fm, Vector3(0, y - h / 2 - t - 0.5, 2.4))
	var cm := MeshKit.mat(Color("#fff3e6"), 0.85)
	for sx in [-1, 1]:
		for k in 4:
			MeshKit.put(g, MeshKit.cylinder(1.15, 1.35, h + 8, 14), cm, Vector3(sx * (w / 2 + 2.2 + k * 2), y + 1, 3 + (k % 2) * 0.6))
	MeshKit.put(g, MeshKit.cylinder(0.4, 0.4, w + 24, 10), MeshKit.mat(Color("#e8b070"), 0.3), Vector3(0, y + h / 2 + 5.5, 3.2), Vector3(0, 0, PI / 2))
	return g

func _plant(parent: Node3D, x: float, z: float, s := 1.0, pot := Color("#fff6ee")) -> Node3D:
	var g := Node3D.new()
	g.position = Vector3(x, TableWorld.Y0 if parent == _cur else 0.0, z)
	g.rotation.y = rng.randf_range(0, 6)
	g.scale = Vector3.ONE * s
	parent.add_child(g)
	MeshKit.put(g, MeshKit.cylinder(3.2, 2.4, 6, 28), MeshKit.mat(pot, 0.3), Vector3(0, 3, 0))
	MeshKit.put(g, MeshKit.torus(3.1, 0.35, 28, 8), MeshKit.mat(pot, 0.3), Vector3(0, 6, 0))
	MeshKit.put(g, MeshKit.cylinder(2.9, 2.9, 0.3, 24), MeshKit.mat(Color("#8a5a3c"), 0.9), Vector3(0, 5.8, 0), Vector3.ZERO, Vector3.ONE, false)
	var l1 := MeshKit.mat(Color("#5cc46c"), 0.45)
	var l2 := MeshKit.mat(Color("#86dc7c"), 0.45)
	for k in 10:
		var a := k / 10.0 * TAU + rng.randf_range(-0.2, 0.2)
		var leaf := MeshKit.put(g, MeshKit.sphere(1, 16, 10), l1 if k % 2 else l2, Vector3(cos(a) * 2.6, 8 + rng.randf_range(0, 4), sin(a) * 2.6), Vector3.ZERO, Vector3(3.4, 0.55, 1.5))
		leaf.rotation_order = EULER_ORDER_YXZ
		leaf.rotation = Vector3(0, -a, rng.randf_range(0.3, 0.8))
	return g

func _pendant(parent: Node3D, x: float, z: float, y: float, shade: Color, bright: float) -> void:
	MeshKit.put(parent, MeshKit.cylinder(0.12, 0.12, TableWorld.Y0 + TableWorld.H - y, 6), MeshKit.mat(Color("#f2ece6"), 0.5), Vector3(x, (TableWorld.Y0 + TableWorld.H + y) / 2, z), Vector3.ZERO, Vector3.ONE, false)
	var dm := SphereMesh.new(); dm.radius = 4.2; dm.height = 8.4; dm.is_hemisphere = true
	var sm := MeshKit.mat(shade, 0.3).duplicate()
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	MeshKit.put(parent, dm, sm, Vector3(x, y, z), Vector3.ZERO, Vector3.ONE, false)
	MeshKit.put(parent, MeshKit.sphere(1, 12, 9), MeshKit.unlit(Color("#fff1d0")), Vector3(x, y - 1.2, z), Vector3.ZERO, Vector3.ONE * 1.3, false)
	var gl := MeshKit.glow(Color("#ffd9a0"), 18 + bright * 12, bright)
	gl.position = Vector3(x, y - 2.5, z)
	parent.add_child(gl)

func _fairy(parent: Node3D, a: Vector3, b: Vector3, sag: float, n: int, cols: Array, size: float) -> void:
	var curve := Curve3D.new()
	for k in 25:
		var t := k / 24.0
		curve.add_point(a.lerp(b, t) + Vector3(0, -sin(t * PI) * sag, 0))
	var path := Path3D.new()
	path.curve = curve
	parent.add_child(path)
	var wire := CSGPolygon3D.new()
	wire.mode = CSGPolygon3D.MODE_PATH
	wire.path_node = wire.get_path_to(path) if wire.is_inside_tree() else NodePath("..")
	var sprites := []
	var length := curve.get_baked_length()
	for k in range(1, n):
		var q := curve.sample_baked(length * k / n)
		var col: Color = cols[k % cols.size()]
		MeshKit.put(parent, MeshKit.sphere(1, 12, 9), MeshKit.unlit(col), q - Vector3(0, 0.5, 0), Vector3.ZERO, Vector3.ONE * size, false)
		var gl := MeshKit.glow(col, size * 9, 0.45)
		gl.position = q - Vector3(0, 0.5, 0)
		parent.add_child(gl)
		sprites.append(gl)
	# the wire itself: thin segments between the curve points
	var wm := MeshKit.mat(Color("#fff8f0"), 0.5)
	for k in 24:
		var p0 := curve.get_point_position(k)
		var p1 := curve.get_point_position(k + 1)
		var seg := MeshKit.put(parent, MeshKit.cylinder(0.09, 0.09, 1.0, 5), wm, (p0 + p1) / 2, Vector3.ZERO, Vector3.ONE, false)
		seg.scale = Vector3(1, p0.distance_to(p1), 1)
		seg.look_at_from_position((p0 + p1) / 2, p1, Vector3.UP if absf((p1 - p0).normalized().y) < 0.99 else Vector3.RIGHT)
		seg.rotate_object_local(Vector3.RIGHT, PI / 2)
	_anims.append(func(t: float):
		for k in sprites.size():
			sprites[k].modulate.a = 0.32 + 0.2 * sin(t * 2.2 + k * 1.7))

func _omni(color: Color, intensity: float, dist: float, pos: Vector3) -> void:
	# three.js PointLight(color, intensity, dist, decay 2), legacy lights: intensity * (1 - d/dist)^2. Godot's
	# (1 - (d/range)^4)^2 * d^-attenuation fits it within 14% from 20 units to 85% of dist with attenuation 0.85,
	# range 0.94 * dist and energy 0.157 * dist^0.85 * intensity (least-max fit, dist 90..160).
	var o := OmniLight3D.new()
	o.light_color = color
	o.light_energy = intensity * 0.157 * pow(dist, 0.85)
	o.omni_range = dist * 0.94
	o.omni_attenuation = 0.85
	o.position = pos
	o.shadow_enabled = false
	_cur.add_child(o)


