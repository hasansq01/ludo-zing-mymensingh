extends RefCounted
## Sunny Cozy Studio (index.html BUILD.studio): butter-yellow walls, warm wood, two big sunny windows with soft
## sunbeams, a cube shelf with a turntable, a guitar, a peach sofa, an easel and hanging plants.
## Same units and positions as the web builder; pieces go under rooms._cur.

const W := TableWorld.W
const H := TableWorld.H
const Y0 := TableWorld.Y0

static var _rng: RandomNumberGenerator

static func _r(a: float, b: float) -> float:
	return _rng.randf_range(a, b)

## put() with three.js's XYZ Euler order (only matters when more than one angle is set).
static func _p(parent: Node3D, mesh: Mesh, m: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE, shadow := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation_order = EULER_ORDER_XYZ
	mi.rotation = rot
	mi.scale = scl
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

## A THREE.PlaneGeometry (XY, facing +z) tilted by rx about x.
static func _plane(parent: Node3D, w: float, h: float, m: Material, pos: Vector3, rx := 0.0) -> MeshInstance3D:
	return _p(parent, MeshKit.plane(w, h), m, pos, Vector3(PI / 2 + rx, 0, 0))

## A THREE.CircleGeometry facing +z.
static func _circle(parent: Node3D, r: float, segs: int, m: Material, pos: Vector3) -> MeshInstance3D:
	return _p(parent, TableWorld._disc(r, segs), m, pos, Vector3(PI / 2, 0, 0))

## grp(x, z, ry, s, parent): a group standing on the floor (or at y = 0 inside another group).
static func _grp(parent: Node3D, x: float, z: float, ry := 0.0, s := 1.0, on_floor := false) -> Node3D:
	var g := Node3D.new()
	g.position = Vector3(x, Y0 if on_floor else 0.0, z)
	g.rotation.y = ry
	g.scale = Vector3.ONE * s
	parent.add_child(g)
	return g

static func _col(hex: int) -> Color:
	return Color.hex((hex << 8) | 0xff)


# ---------- textures (index.html planks / wallTex / skyTex / artTex / rugTex) ----------


static func _vgrad(c: Control, stops: Array) -> void:
	var w := c.size.x
	var h := c.size.y
	var n := 96
	for k in n:
		var t := (k + 0.5) / n
		var col: Color = stops[0][1]
		for s in stops.size() - 1:
			if t >= stops[s][0] and t <= stops[s + 1][0]:
				col = (stops[s][1] as Color).lerp(stops[s + 1][1], (t - stops[s][0]) / maxf(0.0001, stops[s + 1][0] - stops[s][0]))
		if t > stops[stops.size() - 1][0]:
			col = stops[stops.size() - 1][1]
		c.draw_rect(Rect2(0, h * k / n, w, h / n + 1), col)

static func _planks_painter(base: Vector3, rows: int) -> Callable:
	return func(c: Control):
		var w := c.size.x
		var h := c.size.y
		var rh := h / rows
		var rr := RandomNumberGenerator.new(); rr.seed = 28
		for r in rows:
			var x := -rr.randf_range(0, 400)
			while x < w:
				var ln := rr.randf_range(260, 520)
				var l := rr.randf_range(-4, 4)
				c.draw_rect(Rect2(x, r * rh, ln, rh), Rooms._hsl(base.x + rr.randf_range(-3, 3), base.y, base.z + l))
				for k in 5:
					var y := r * rh + rr.randf_range(4, rh - 4)
					var c1 := Vector2(x + ln * 0.3, y + rr.randf_range(-6, 6))
					var c2 := Vector2(x + ln * 0.7, y + rr.randf_range(-6, 6))
					var pts := PackedVector2Array()
					for q in 13:
						var t := q / 12.0
						var u := 1.0 - t
						pts.append(Vector2(x, y) * u * u * u + c1 * 3 * u * u * t + c2 * 3 * u * t * t + Vector2(x + ln, y) * t * t * t)
					c.draw_polyline(pts, Color(150 / 255.0, 90 / 255.0, 50 / 255.0, 0.12), 1.5, true)
				c.draw_rect(Rect2(x, r * rh, 2, rh), Color(140 / 255.0, 80 / 255.0, 50 / 255.0, 0.22))
				x += ln
			c.draw_rect(Rect2(0, r * rh, w, 2.5), Color(140 / 255.0, 80 / 255.0, 50 / 255.0, 0.25))
			c.draw_rect(Rect2(0, r * rh + 3, w, 2), Color(1, 1, 1, 0.18))

## wallTex({top, bottom, pat, patColor, wains, wainsColor})
static func _wall_painter(o: Dictionary) -> Callable:
	return func(c: Control):
		var w := c.size.x
		var h := c.size.y
		var top: Color = o.top
		var bottom: Color = o.get("bottom", top)
		_vgrad(c, [[0.0, top], [1.0, bottom]])
		var pat: String = o.get("pat", "")
		var wains: float = o.get("wains", 0.0)
		var rr := RandomNumberGenerator.new(); rr.seed = 7
		if pat == "dots":
			var y := 26.0
			var row := 0
			while y < h * (1 - wains) - 10:
				var x := (row % 2) * 32 + 18.0
				while x < w:
					TexBaker.circle(c, Vector2(x, y), 4.5, o.pat_color)
					x += 64
				y += 46; row += 1
		elif pat == "slats":
			var x := 0.0
			while x < w:
				c.draw_rect(Rect2(x, 0, 24, h), Rooms._hsl(rr.randf_range(28, 34), rr.randf_range(55, 65), rr.randf_range(66, 72)))
				c.draw_rect(Rect2(x + 24, 0, 2, h), Color(140 / 255.0, 80 / 255.0, 40 / 255.0, 0.25))
				x += 26
		if wains > 0:
			var y0 := h * (1 - wains)
			c.draw_rect(Rect2(0, y0, w, h - y0), o.wains_color)
			var x := 10.0
			while x < w:
				c.draw_rect(Rect2(x, y0 + 14, 60, h - y0 - 30), Color(140 / 255.0, 90 / 255.0, 110 / 255.0, 0.14), false, 3.0)
				x += 80
			c.draw_rect(Rect2(0, y0 - 6, w, 8), Color(1, 1, 1, 0.9))

## skyTex({stops: #7cc4ff / #cbe8ff / #fff1d6, sun, clouds: 6, hills: #9fd99a})
static func _paint_sky(c: Control) -> void:
	var w := c.size.x
	var h := c.size.y
	_vgrad(c, [[0.0, Color("#7cc4ff")], [0.55, Color("#cbe8ff")], [1.0, Color("#fff1d6")]])
	var g := Gradient.new()                       # the sun: a radial glow of radius 160
	g.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	g.colors = PackedColorArray([Color8(255, 250, 220, 255), Color8(255, 240, 190, 230), Color8(255, 240, 190, 0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 320; gt.height = 320
	c.draw_texture_rect(gt, Rect2(w * 0.7 - 160, h * 0.32 - 160, 320, 320), false)
	var rr := RandomNumberGenerator.new(); rr.seed = 6
	for k in 6:
		var cx := rr.randf_range(-20, w + 20)
		var cy := rr.randf_range(h * 0.2, h * 0.75)
		var s := rr.randf_range(22, 44)
		for b in [[0, 0, 1.0], [-1.1, 0.3, 0.7], [1.1, 0.3, 0.75], [-0.5, -0.35, 0.8], [0.5, -0.3, 0.7]]:
			TexBaker.circle(c, Vector2(cx + b[0] * s, cy + b[1] * s), b[2] * s, Color(1, 1, 1, 0.92))
	var hills := PackedVector2Array([Vector2(0, h)])
	var x := 0.0
	while x <= w:
		hills.append(Vector2(x, h * 0.86 - sin(x / 70.0) * 22 - sin(x / 23.0) * 6))
		x += 8
	hills.append(Vector2(w, h))
	c.draw_colored_polygon(hills, Color("#9fd99a"))

static func _art_painter(pal: Array, kind: String, seed_: int) -> Callable:
	return func(c: Control):
		var w := c.size.x
		var h := c.size.y
		c.draw_rect(Rect2(Vector2.ZERO, c.size), Color(pal[0]))
		if kind == "arch":
			for e in [[pal[1], 110.0], [pal[2], 80.0], [pal[3], 50.0]]:
				var pts := PackedVector2Array()
				for k in 41:
					var a := PI + PI * k / 40.0
					pts.append(Vector2(w / 2, h * 0.72) + Vector2(cos(a), sin(a)) * e[1])
				c.draw_colored_polygon(pts, Color(e[0]))
			TexBaker.circle(c, Vector2(w * 0.76, h * 0.25), 26, Color(pal[4] if pal.size() > 4 else pal[1]))
		elif kind == "note":
			TexBaker.circle(c, Vector2(w / 2, h * 0.45), 90, Color(pal[1]))
			var n2 := Color(pal[2])
			var el := PackedVector2Array()            # the note head: an ellipse tilted -0.4
			for k in 32:
				var a := TAU * k / 32.0
				el.append(Vector2(w * 0.44, h * 0.6) + Vector2(cos(a) * 22, sin(a) * 16).rotated(-0.4))
			c.draw_colored_polygon(el, n2)
			c.draw_rect(Rect2(w * 0.44 + 16, h * 0.2, 9, h * 0.4), n2)
			var fl := PackedVector2Array([Vector2(w * 0.44 + 25, h * 0.2)])   # the flag
			var p0 := Vector2(w * 0.44 + 25, h * 0.2)
			var cp := Vector2(w * 0.7, h * 0.26)
			var p1 := Vector2(w * 0.64, h * 0.38)
			for k in range(1, 13):
				var t := k / 12.0
				fl.append(p0 * (1 - t) * (1 - t) + cp * 2 * (1 - t) * t + p1 * t * t)
			fl.append(Vector2(w * 0.44 + 25, h * 0.3))
			c.draw_colored_polygon(fl, n2)
			for k in 6:
				c.draw_rect(Rect2(24 + k * 36, h - 46, 22, 18 + (k % 3) * 8), Color(pal[3]))
		else:
			var rr := RandomNumberGenerator.new(); rr.seed = seed_
			for k in 6:
				var col := Color(pal[1 + (k % (pal.size() - 1))])
				TexBaker.circle(c, Vector2(rr.randf_range(40, w - 40), rr.randf_range(40, h - 40)), rr.randf_range(24, 62), col)

## rugTex({base: #fff3d6, check: #ffd9a8})
static func _paint_rug(c: Control) -> void:
	var w := c.size.x
	c.draw_rect(Rect2(Vector2.ZERO, c.size), Color("#fff3d6"))
	var s := w / 8
	for y in 8:
		for x in 8:
			if (x + y) % 2:
				c.draw_rect(Rect2(x * s, y * s, s, s), Color("#ffd9a8"))
	var rr := RandomNumberGenerator.new(); rr.seed = 9
	for k in 2000:
		c.draw_rect(Rect2(rr.randf_range(0, w), rr.randf_range(0, w), 2, 2), Color(1, 1, 1, rr.randf_range(0, 0.08)))


# ---------- props (index.html windowOn / framed / floorLamp / sofa / cubeShelf) ----------


static func _window_on(rooms: Rooms, side: String, u: float, y: float, w: float, h: float, sky: Texture2D, curtain: Color, rod: Color, beam: Color) -> Node3D:
	var g := rooms._wall_group(side, u)
	var fm := MeshKit.mat(Color.WHITE, 0.3)
	var t := 1.5
	_plane(g, w, h, MeshKit.unlit(Color.WHITE, sky), Vector3(0, y, 0.2))
	_p(g, MeshKit.rbox(w + 2 * t, t, 1.8, 0.6), fm, Vector3(0, y + h / 2 + t / 2, 0.9))
	_p(g, MeshKit.rbox(w + 2 * t, t, 1.8, 0.6), fm, Vector3(0, y - h / 2 - t / 2, 0.9))
	_p(g, MeshKit.rbox(t, h, 1.8, 0.6), fm, Vector3(-w / 2 - t / 2, y, 0.9))
	_p(g, MeshKit.rbox(t, h, 1.8, 0.6), fm, Vector3(w / 2 + t / 2, y, 0.9))
	_p(g, MeshKit.rbox(0.9, h, 0.9, 0.35), fm, Vector3(0, y, 0.6))
	_p(g, MeshKit.rbox(w, 0.9, 0.9, 0.35), fm, Vector3(0, y + h * 0.14, 0.6))
	_p(g, MeshKit.rbox(w + 7, 1.3, 5, 0.6), fm, Vector3(0, y - h / 2 - t - 0.5, 2.4), Vector3.ZERO, Vector3.ONE, true)   # sill
	var cm := MeshKit.mat(curtain, 0.85)
	for sx in [-1, 1]:
		for k in 4:
			_p(g, MeshKit.cylinder(1.15, 1.35, h + 8, 14), cm, Vector3(sx * (w / 2 + 2.2 + k * 2), y + 1, 3 + (k % 2) * 0.6), Vector3.ZERO, Vector3.ONE, true)
	var rm := MeshKit.mat(rod, 0.3)
	_p(g, MeshKit.cylinder(0.4, 0.4, w + 24, 10), rm, Vector3(0, y + h / 2 + 5.5, 3.2), Vector3(0, 0, PI / 2))
	for sx in [-1, 1]:
		_p(g, MeshKit.sphere(1), rm, Vector3(sx * (w / 2 + 12), y + h / 2 + 5.5, 3.2), Vector3.ZERO, Vector3.ONE * 0.9)
	# a soft sunbeam falling from the window into the room: additive, unlit, no depth write, no shadow
	var gr := Gradient.new()
	gr.offsets = PackedFloat32Array([0.0, 1.0])
	gr.colors = PackedColorArray([Color8(255, 240, 200, 230), Color8(255, 240, 200, 0)])
	var bt := GradientTexture2D.new()
	bt.gradient = gr
	bt.fill_from = Vector2(0, 0)
	bt.fill_to = Vector2(0, 1)
	bt.width = 64; bt.height = 256
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.albedo_color = Color(beam, 0.22)
	bm.albedo_texture = bt
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	bm.render_priority = 2
	_plane(g, w * 0.9, 70, bm, Vector3(0, y - 22, 26), -0.95)
	return g

static func _framed(p: Node3D, x: float, y: float, w: float, h: float, art: Texture2D, fm: Material, z := 1.0) -> void:
	_p(p, MeshKit.rbox(w + 2.2, h + 2.2, 1, 0.45), fm, Vector3(x, y, z - 0.3))
	_plane(p, w, h, MeshKit.tex_mat(art, 0.7), Vector3(x, y, z + 0.25))

static func _floor_lamp(p: Node3D, x: float, z: float, shade: Color) -> Node3D:
	var g := _grp(p, x, z)
	var pole := MeshKit.mat(Color("#e8b070"), 0.3)
	_p(g, MeshKit.cylinder(3.4, 3.8, 0.8, 28), pole, Vector3(0, 0.4, 0))
	_p(g, MeshKit.cylinder(0.35, 0.35, 40, 10), pole, Vector3(0, 20, 0))
	var sh := CylinderMesh.new()
	sh.top_radius = 3.4; sh.bottom_radius = 5.4; sh.height = 7; sh.radial_segments = 28; sh.rings = 1
	sh.cap_top = false; sh.cap_bottom = false
	var sm := MeshKit.emissive(shade, 0.35)
	sm.roughness = 0.8
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_p(g, sh, sm, Vector3(0, 42, 0))
	_p(g, MeshKit.sphere(1), MeshKit.unlit(Color("#fff3d6")), Vector3(0, 40.5, 0), Vector3.ZERO, Vector3.ONE * 1.1)
	var gl := MeshKit.glow(Color("#ffe2b0"), 16, 0.55)
	gl.position = Vector3(0, 40, 0)
	g.add_child(gl)
	return g

static func _sofa(p: Node3D, x: float, z: float, ry: float, col: Color, accent: Color) -> Node3D:
	var g := _grp(p, x, z, ry)
	var c := MeshKit.mat(col, 0.75)
	var leg := MeshKit.mat(Color("#e8b070"), 0.35)
	_p(g, MeshKit.rbox(28, 6, 12, 1.6), c, Vector3(0, 5.5, 0), Vector3.ZERO, Vector3.ONE, true)
	for cx in [-6.6, 6.6]:
		_p(g, MeshKit.rbox(13, 3.4, 10.5, 1.5), c, Vector3(cx, 10, 0.8), Vector3.ZERO, Vector3.ONE, true)
	_p(g, MeshKit.rbox(28, 12, 4.5, 2), c, Vector3(0, 12, -4.6), Vector3.ZERO, Vector3.ONE, true)
	for ax in [-13.0, 13.0]:
		_p(g, MeshKit.rbox(4.4, 10, 12.5, 2), c, Vector3(ax, 9, 0), Vector3.ZERO, Vector3.ONE, true)
	for l in [[-12, -5], [12, -5], [-12, 5], [12, 5]]:
		_p(g, MeshKit.cylinder(0.6, 0.45, 2.6, 10), leg, Vector3(l[0], 1.3, l[1]))
	for q in [[-8.0, 0.5], [8.0, -0.4]]:
		_p(g, MeshKit.rbox(6, 6, 1.8, 0.9), MeshKit.mat(accent, 0.8), Vector3(q[0], 14, -1.6), Vector3(-0.25, 0, q[1]), Vector3.ONE, true)
	return g

## cubeShelf(p, x, z, cols, rows, wood, bookCols): returns the group; its top is rows * 9.5 + 0.9.
static func _cube_shelf(p: Node3D, x: float, z: float, cols: int, rows: int, wood: Color, book_cols: Array) -> Node3D:
	var g := _grp(p, x, z)
	var wm := MeshKit.mat(wood, 0.4)
	var cw := 9.5
	var ch := 9.5
	var d := 8.5
	var t := 0.9
	var w2 := cols * cw
	var h2 := rows * ch
	_p(g, MeshKit.rbox(w2 + t, t, d, 0.35), wm, Vector3(0, t / 2, d / 2), Vector3.ZERO, Vector3.ONE, true)
	for r in range(1, rows + 1):
		_p(g, MeshKit.rbox(w2 + t, t, d, 0.35), wm, Vector3(0, r * ch + t / 2, d / 2), Vector3.ZERO, Vector3.ONE, true)
	for c in cols + 1:
		_p(g, MeshKit.rbox(t, h2 + t, d, 0.35), wm, Vector3(-w2 / 2 + c * cw, h2 / 2 + t / 2, d / 2), Vector3.ZERO, Vector3.ONE, true)
	for r in rows:
		for c in cols:
			if (r + c) % 3 == 2:
				continue                         # leave some cubbies open
			var bx := -w2 / 2 + c * cw + 1.4
			var n := 4 + int(floor(_r(0, 3)))
			var k := 0
			while k < n and bx < -w2 / 2 + (c + 1) * cw - 1.6:
				var bt := _r(0.9, 1.5)
				var bh := _r(5.2, 7.6)
				var bc: Color = book_cols[int(floor(_r(0, book_cols.size()))) % book_cols.size()]
				_p(g, MeshKit.rbox(bt, bh, 6, 0.2), MeshKit.mat(bc, 0.6), Vector3(bx + bt / 2, r * ch + t + bh / 2, d / 2 + 0.3), Vector3(0, 0, -0.18 if k == n - 1 else 0.0))
				bx += bt + 0.15
				k += 1
	g.set_meta("top", h2 + t)
	return g


# ---------- the room ----------


static func build(rooms: Rooms, baker: TexBaker) -> void:
	_rng = rooms.rng
	var floor_tex := await baker.bake(Vector2i(1024, 1024), _planks_painter(Vector3(28, 58, 62), 7))
	var wall_back := await baker.bake(Vector2i(640, 512), _wall_painter({top = Color("#ffe89a"), bottom = Color("#fff0bf"), wains = 0.22, wains_color = Color("#fffaf0")}))
	var wall_left := await baker.bake(Vector2i(640, 512), _wall_painter({top = Color("#ffd9c0"), bottom = Color("#ffe6d4"), wains = 0.22, wains_color = Color("#fffaf0")}))
	var wall_right := await baker.bake(Vector2i(640, 512), _wall_painter({top = Color("#fff4e0"), bottom = Color("#fff7ea"), pat = "dots", pat_color = Color8(255, 190, 120, 77), wains = 0.3, wains_color = Color("#f2c48d")}))
	var wall_front := await baker.bake(Vector2i(640, 512), _wall_painter({top = Color("#f2c48d"), pat = "slats"}))
	var rug_tex := await baker.bake(Vector2i(512, 512), _paint_rug)
	var sky := await baker.bake(Vector2i(512, 640), _paint_sky)
	var posters := [
		await baker.bake(Vector2i(256, 320), _art_painter(["#fff4e0", "#ffb98a", "#ff8f7a", "#7cc4ff"], "note", 1)),
		await baker.bake(Vector2i(256, 320), _art_painter(["#eaf6ff", "#ffd86b", "#ffb98a", "#9fe3d2", "#ff8f7a"], "arch", 2)),
		await baker.bake(Vector2i(256, 320), _art_painter(["#fff0f6", "#b49cff", "#4a2b3d", "#ffd86b"], "note", 3)),
	]
	var gallery := [
		await baker.bake(Vector2i(256, 320), _art_painter(["#fffaf0", "#ff8f7a", "#ffd86b", "#7cc4ff"], "arch", 4)),
		await baker.bake(Vector2i(256, 320), _art_painter(["#fffaf0", "#ff8f7a", "#ffd86b", "#7cc4ff"], "dots", 5)),
		await baker.bake(Vector2i(256, 320), _art_painter(["#fffaf0", "#ff8f7a", "#ffd86b", "#7cc4ff"], "dots", 6)),
	]
	var easel_art := await baker.bake(Vector2i(256, 320), _art_painter(["#fffaf0", "#ffd86b", "#ffb98a", "#9fe3d2", "#7cc4ff"], "dots", 7))
	var R := rooms._cur

	# shell: floor, ceiling, four painted walls, skirting and cornice
	MeshKit.put(R, MeshKit.plane(2 * W, 2 * W), MeshKit.tex_mat(floor_tex, 0.45, Vector2(3, 3)), Vector3(0, Y0, 0), Vector3.ZERO, Vector3.ONE, false)
	MeshKit.put(R, MeshKit.plane(2 * W, 2 * W), MeshKit.mat(Color("#fffaf0"), 0.95), Vector3(0, Y0 + H, 0), Vector3(PI, 0, 0), Vector3.ONE, false)
	var walls := {back = MeshKit.tex_mat(wall_back, 0.9), left = MeshKit.tex_mat(wall_left, 0.9), right = MeshKit.tex_mat(wall_right, 0.9), front = MeshKit.tex_mat(wall_front, 0.7)}
	var trim := MeshKit.mat(Color("#fffaf0"), 0.3)
	for side in ["back", "left", "right", "front"]:
		var g := rooms._wall_group(side, 0)
		_plane(g, 2 * W, H, walls[side], Vector3(0, H / 2, 0))
		_p(g, MeshKit.rbox(2 * W, 3.2, 1.4, 0.5), trim, Vector3(0, 1.6, 0.7))
		_p(g, MeshKit.rbox(2 * W, 2, 1.6, 0.6), trim, Vector3(0, H - 1, 0.8))
	var wood := MeshKit.mat(Color("#e7a463"), 0.35)
	var dark := MeshKit.mat(Color("#9a5e3a"), 0.4)
	var cream := MeshKit.mat(Color("#fff6ea"), 0.3)
	var chrome := MeshKit.mat(Color("#e9ecf2"), 0.18, 0.85)
	# square checked rug under the table
	MeshKit.put(R, MeshKit.plane(50, 37.5), MeshKit.tex_mat(rug_tex, 1.0), Vector3(0, Y0 + 0.08, 0), Vector3.ZERO, Vector3.ONE, false)

	# back wall: cube shelf with a turntable, guitar on its stand, posters, floor lamp
	var bw := rooms._wall_group("back", 0)
	var books := [0xff8f7a, 0x7cc4ff, 0xffd86b, 0x9fe3d2, 0xb49cff, 0xfff6ea].map(func(h: int): return _col(h))
	var sh := _cube_shelf(bw, -14, 0, 3, 2, Color("#f0b77a"), books)
	var top: float = sh.get_meta("top")
	var tt := _grp(sh, -6, 4.5)
	tt.position.y = top
	_p(tt, MeshKit.rbox(12, 2, 9, 0.7), MeshKit.mat(Color("#f6c38e"), 0.3), Vector3(0, 1, 0), Vector3.ZERO, Vector3.ONE, true)
	_p(tt, MeshKit.cylinder(3.8, 3.8, 0.4, 40), MeshKit.mat(Color("#3d2a3a"), 0.25), Vector3(-1, 2.2, 0))
	_p(tt, MeshKit.cylinder(1.2, 1.2, 0.45, 24), MeshKit.mat(Color("#ffd86b"), 0.5), Vector3(-1, 2.25, 0))
	_p(tt, MeshKit.rbox(0.5, 0.5, 5, 0.2), chrome, Vector3(3.6, 2.8, -0.6), Vector3(0, 0.5, 0))
	_p(sh, MeshKit.rbox(10, 10, 0.4, 0.2), MeshKit.mat(Color("#fff6ea"), 0.6), Vector3(7, top + 5.6, -3), Vector3(-0.12, 0, 0))   # record sleeve
	_p(sh, MeshKit.cylinder(3.6, 3.6, 0.3, 40), MeshKit.mat(Color("#3d2a3a"), 0.25), Vector3(7, top + 5.6, -2.7), Vector3(PI / 2 - 0.12, 0, 0))
	var gt := _grp(bw, 10, 6, -0.25)
	var gbody := MeshKit.mat(Color("#f2b06a"), 0.25)
	_p(gt, MeshKit.sphere(1), gbody, Vector3(0, 8, 0), Vector3.ZERO, Vector3(5, 5.2, 1.8), true)
	_p(gt, MeshKit.sphere(1), gbody, Vector3(0, 15, 0), Vector3.ZERO, Vector3(3.8, 3.8, 1.7), true)
	_circle(gt, 1.4, 24, MeshKit.mat(Color("#4a2b3d"), 0.6), Vector3(0, 12, 1.75))
	_p(gt, MeshKit.rbox(1.4, 17, 1, 0.3), dark, Vector3(0, 26, 0.4), Vector3.ZERO, Vector3.ONE, true)
	_p(gt, MeshKit.rbox(2.2, 4, 1, 0.4), dark, Vector3(0, 36, 0.2))
	for k in 6:
		_p(gt, MeshKit.cylinder(0.04, 0.04, 26, 4), chrome, Vector3(-0.5 + k * 0.2, 22, 1.9))
	for l in [[-2.4, 1.0], [2.4, 1.0], [0.0, -2.5]]:
		_p(gt, MeshKit.cylinder(0.25, 0.25, 8, 8), MeshKit.mat(Color("#4a2b3d"), 0.4), Vector3(l[0], 3.6, l[1]), Vector3(l[1] * 0.06, 0, l[0] * -0.08))
	var frame_cols := [Color("#fff6ea"), Color("#e7a463"), Color("#4a2b3d")]
	var spots := [[-26.0, 58.0], [-4.0, 62.0], [16.0, 54.0]]
	for k in 3:
		_framed(bw, spots[k][0], spots[k][1], 13, 17, posters[k], MeshKit.mat(frame_cols[k], 0.35))
	_floor_lamp(bw, 34, 6, Color("#fff3d6"))

	# left wall: two big sunny windows with sunbeams, a radiator under one, a plant on the other's sill
	for k in 2:
		var g := _window_on(rooms, "left", [-22.0, 22.0][k], 50, 26, 38, sky, Color("#fff1c9"), Color("#e7a463"), Color("#fff0c8"))
		if k == 0:
			for r in 9:
				_p(g, MeshKit.rbox(1.6, 12, 3, 0.7), cream, Vector3(-8 + r * 2, 13, 2.6), Vector3.ZERO, Vector3.ONE, true)
		else:
			var pl := rooms._plant(g, -6, 4, 0.55, Color("#ffb98a"))
			pl.position.y = 29.6

	# right wall: peach sofa with cushions, a small gallery, a side table with a cup
	var rw := rooms._wall_group("right", 0)
	_sofa(rw, 0, 8, 0, Color("#ffb98a"), Color("#fff1a8"))
	var gal_frames := [Color("#ffe9a8"), Color("#9fe3d2"), Color("#ffd3e3")]
	for k in 3:
		_framed(rw, [-16.0, 0.0, 16.0][k], 42 + (k % 2) * 4, 9, 11, gallery[k], MeshKit.mat(gal_frames[k], 0.4))
	var st := _grp(rw, 22, 8)
	_p(st, MeshKit.cylinder(4, 4, 1, 28), wood, Vector3(0, 12, 0), Vector3.ZERO, Vector3.ONE, true)
	_p(st, MeshKit.cylinder(0.5, 0.5, 12, 10), wood, Vector3(0, 6, 0))
	rooms.world.cup(st, Vector3(0, 12.5 - TableWorld.TT, 0), 1, Color("#ffc6a5"))

	# front wall: easel with a painting, a big plant, a shelf of hanging plants
	var fw := rooms._wall_group("front", 0)
	var ez := _grp(fw, 16, 10, -0.2)
	for q in [[-4.0, -0.12], [4.0, 0.12]]:
		_p(ez, MeshKit.cylinder(0.35, 0.35, 34, 8), wood, Vector3(q[0], 16, 0), Vector3(0, 0, q[1]), Vector3.ONE, true)
	_p(ez, MeshKit.cylinder(0.35, 0.35, 30, 8), wood, Vector3(0, 14, -3), Vector3(-0.2, 0, 0))
	_p(ez, MeshKit.rbox(13, 1, 3, 0.4), wood, Vector3(0, 12, 0.8))
	_p(ez, MeshKit.rbox(12, 15, 0.8, 0.3), cream, Vector3(0, 20.5, 0.9), Vector3(-0.08, 0, 0), Vector3.ONE, true)
	_plane(ez, 11, 14, MeshKit.tex_mat(easel_art, 0.8), Vector3(0, 20.5, 1.35), -0.08)
	rooms._plant(fw, -30, 7, 1.5, Color("#fff6ea"))
	var hs := _grp(fw, -4, 0)
	_p(hs, MeshKit.rbox(30, 1.4, 6, 0.5), wood, Vector3(0, 56, 3), Vector3.ZERO, Vector3.ONE, true)
	var pots := [Color("#ffb98a"), Color("#fff6ea"), Color("#9fe3d2")]
	var leaf_a := MeshKit.mat(Color("#5cc46c"), 0.5)
	var leaf_b := MeshKit.mat(Color("#86dc7c"), 0.5)
	for k in 3:
		var x: float = [-10.0, 0.0, 10.0][k]
		_p(hs, MeshKit.cylinder(2, 1.6, 3.4, 20), MeshKit.mat(pots[k], 0.35), Vector3(x, 58.4, 3))
		for v in 3:
			for j in 7:
				_p(hs, MeshKit.sphere(1), leaf_a if j % 2 else leaf_b, Vector3(x - 1.6 + v * 1.6, 56 - j * 2.6 - v, 5.8 + sin(j) * 0.5), Vector3.ZERO, Vector3(1.1, 0.6, 0.9))

	# sunlight through the windows, warm lamplight by the shelf, a soft fill by the sofa
	rooms._omni(Color("#fff0c8"), 0.55, 160, Vector3(-48, Y0 + 52, 0))
	rooms._omni(Color("#ffe2b8"), 0.33, 110, Vector3(34, Y0 + 44, -50))
	rooms._omni(Color("#fff4e6"), 0.25, 140, Vector3(30, Y0 + 70, 40))
