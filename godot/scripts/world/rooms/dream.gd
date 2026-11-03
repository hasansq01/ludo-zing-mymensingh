extends RefCounted
## The Pastel Dream Room (index.html BUILD.dream): a blush and lavender bedroom at twilight with a canopy bed,
## fairy lights, a neon heart, a moon and stars on the wall, a window seat, a dresser with a round mirror,
## a bookshelf, a floor lamp, a beanbag and a hanging egg chair. Same units and positions as the web version.

const Y0 := TableWorld.Y0
const W := TableWorld.W
const H := TableWorld.H


static func build(rooms: Rooms, baker: TexBaker) -> void:
	var rng := rooms.rng
	var planks := await baker.bake(Vector2i(1024, 1024), _planks_painter(Vector3(28, 34, 88), 9))
	var wall_back := await baker.bake(Vector2i(640, 512), _wall_painter(Color("#ffd3e6"), Color("#ffe4ef"), "stars", Color(1, 1, 1, 0.75), 0.26, Color("#fff6fa")))
	var wall_left := await baker.bake(Vector2i(640, 512), _wall_painter(Color("#dccfff"), Color("#ece4ff"), "", Color.TRANSPARENT, 0.26, Color("#fff6fa")))
	var wall_right := await baker.bake(Vector2i(640, 512), _wall_painter(Color("#ffe0ec"), Color("#ffeaf2"), "stripes", Color(1, 1, 1, 0.42), 0.26, Color("#fff6fa")))
	var wall_front := await baker.bake(Vector2i(640, 512), _wall_painter(Color("#fff3ea"), Color("#fff8f2"), "hearts", Color(1, 170 / 255.0, 200 / 255.0, 0.35), 0.26, Color("#ffeef5")))
	var sky := await baker.bake(Vector2i(512, 640), _sky_painter())
	var rug := await baker.bake(Vector2i(512, 512), _rug_painter(Color("#e6dcff"), Color(1, 1, 1, 0.75), [Color("#d6c8ff")]))
	var R := rooms._cur

	# ---- shell: floor, ceiling, four walls, skirting and cornice
	MeshKit.put(R, MeshKit.plane(2 * W, 2 * W), MeshKit.tex_mat(planks, 0.5, Vector2(3, 3)), Vector3(0, Y0, 0), Vector3.ZERO, Vector3.ONE, false)
	MeshKit.put(R, MeshKit.plane(2 * W, 2 * W), MeshKit.mat(Color("#fff3fa"), 0.95), Vector3(0, Y0 + H, 0), Vector3(PI, 0, 0), Vector3.ONE, false)
	var walls := {back = MeshKit.tex_mat(wall_back, 0.9), left = MeshKit.tex_mat(wall_left, 0.9), right = MeshKit.tex_mat(wall_right, 0.9), front = MeshKit.tex_mat(wall_front, 0.9)}
	var trim := MeshKit.mat(Color.WHITE, 0.3)
	for side in ["back", "left", "right", "front"]:
		var g := rooms._wall_group(side, 0)
		MeshKit.put(g, MeshKit.plane(2 * W, H), walls[side], Vector3(0, H / 2, 0), Vector3(PI / 2, 0, 0), Vector3.ONE, false)
		MeshKit.put(g, MeshKit.rbox(2 * W, 3.2, 1.4, 0.5), trim, Vector3(0, 1.6, 0.7), Vector3.ZERO, Vector3.ONE, false)
		MeshKit.put(g, MeshKit.rbox(2 * W, 2, 1.6, 0.6), trim, Vector3(0, H - 1, 0.8), Vector3.ZERO, Vector3.ONE, false)

	var white := MeshKit.mat(Color("#fffaf8"), 0.3)
	var lav := MeshKit.mat(Color("#c9b3ff"), 0.55)
	var pink := MeshKit.mat(Color("#ffb3cf"), 0.7)
	var pink_lt := MeshKit.mat(Color("#ffd3e3"), 0.75)
	var gold := MeshKit.mat(Color("#f2c06b"), 0.25, 0.5)
	var SPH := MeshKit.sphere(1, 24, 16)
	MeshKit.put(R, TableWorld._disc(26, 64), MeshKit.tex_mat(rug, 1.0), Vector3(0, Y0 + 0.08, 0), Vector3.ZERO, Vector3.ONE, false)

	# ---- bed against the back wall
	var bw := rooms._wall_group("back", -24)
	var bed := _grp(bw, 0, 0)
	_put(bed, MeshKit.rbox(28, 24, 2.4, 4), lav, Vector3(0, 15, 1.4), Vector3.ZERO, Vector3.ONE, true)
	_put(bed, MeshKit.rbox(22, 16, 0.8, 3), MeshKit.mat(Color("#e0d4ff"), 0.6), Vector3(0, 16, 2.7))
	_put(bed, MeshKit.rbox(28, 5, 36, 1.4), white, Vector3(0, 4.5, 19), Vector3.ZERO, Vector3.ONE, true)
	_put(bed, MeshKit.rbox(26.5, 4, 34, 1.8), MeshKit.mat(Color("#fff8f2"), 0.8), Vector3(0, 8.6, 19), Vector3.ZERO, Vector3.ONE, true)
	_put(bed, MeshKit.rbox(28, 3, 23, 1.4), pink, Vector3(0, 10.6, 25.5), Vector3.ZERO, Vector3.ONE, true)
	_put(bed, MeshKit.rbox(28.4, 3.4, 4.5, 1.6), pink_lt, Vector3(0, 11.4, 13.2), Vector3.ZERO, Vector3.ONE, true)
	for px in [-6.5, 6.5]:
		_put(bed, MeshKit.rbox(10.5, 3.4, 6.5, 1.6), MeshKit.mat(Color("#fff6fb"), 0.85), Vector3(px, 12, 6), Vector3(-0.35, 0, 0), Vector3.ONE, true)
	_put(bed, MeshKit.rbox(8, 7, 2.4, 1.2), MeshKit.mat(Color("#c9b3ff"), 0.85), Vector3(0, 13.5, 8.6), Vector3(-0.3, 0, 0), Vector3.ONE, true)
	_plush(bed, 8, 12.6, 9, Color.WHITE, 0.9, -0.3)
	# canopy: a soft arch of sheer fabric above the bed
	var veil := MeshKit.mat(Color("#fff0f6"), 0.9).duplicate() as StandardMaterial3D
	veil.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	veil.albedo_color.a = 0.8
	veil.cull_mode = BaseMaterial3D.CULL_DISABLED
	_put(bed, _cyl_segment(15, 15, 8, 40, -PI / 2, PI), veil, Vector3(0, 52, 5), Vector3(-PI / 2, 0, 0))
	for sx in [-1, 1]:
		_put(bed, _open_cyl(1.2, 2.6, 40, 16), veil, Vector3(sx * 15, 32, 8))
	# nightstand + little lamp
	var ns := _grp(bw, 20, 6)
	_put(ns, MeshKit.rbox(8, 11, 8, 1), white, Vector3(0, 5.5, 0), Vector3.ZERO, Vector3.ONE, true)
	_put(ns, MeshKit.rbox(7, 3.2, 0.6, 0.3), pink_lt, Vector3(0, 7, 4.1))
	_put(ns, SPH, gold, Vector3(0, 7, 4.6), Vector3.ZERO, Vector3.ONE * 0.35)
	_put(ns, _open_cyl(1.6, 2.4, 3, 20), _emis_mat(Color("#ffd3e3"), 0.8, Color("#ffc0d8"), 0.45, true), Vector3(0, 16, 0))
	_put(ns, MeshKit.cylinder(0.25, 0.25, 4, 8), gold, Vector3(0, 13, 0))
	_glow(ns, Color("#ffd6e6"), 9, Vector3(0, 15.5, 0), 0.55)
	# fairy lights across the back wall + moon and stars
	rooms._fairy(bw, Vector3(-22, 66, 2), Vector3(60, 64, 2), 6, 20, [Color("#fff3c8"), Color("#ffd6e6"), Color("#e6dcff")], 0.55)
	var md := rooms._wall_group("back", 30)
	_put(md, _moon_mesh(6), _emis_mat(Color("#fff1a8"), 0.35, Color("#ffe680"), 0.45), Vector3(0, 46, 1.4), Vector3(0, 0, 0.3))
	_glow(md, Color("#fff1a8"), 22, Vector3(0, 46, 3), 0.25)
	var star_m := _emis_mat(Color.WHITE, 0.3, Color("#fff2c0"), 0.5)
	var star_g := _star_mesh(1.6, 0.7, 0.5)
	for st in [[-10, 56, 1.6], [9, 54, 1.2], [-6, 36, 1], [12, 40, 1.4], [2, 60, 0.9]]:
		_put(md, star_g, star_m, Vector3(st[0], st[1], 1.2), Vector3.ZERO, Vector3.ONE * float(st[2]))

	# ---- left wall: twilight window with a cushioned window seat
	var wl := _window(rooms, "left", 0, 50, 30, 34, sky, Color("#d8caff"), Color("#f2c06b"))
	_put(wl, MeshKit.rbox(40, 9, 10, 1.4), white, Vector3(0, 4.5, 5), Vector3.ZERO, Vector3.ONE, true)
	_put(wl, MeshKit.rbox(38, 2.6, 9, 1.2), pink_lt, Vector3(0, 10.2, 5), Vector3.ZERO, Vector3.ONE, true)
	for cu in [[-12, Color("#c9b3ff")], [12, Color("#ffb3cf")]]:
		_put(wl, MeshKit.rbox(7, 7, 2.4, 1.2), MeshKit.mat(cu[1], 0.85), Vector3(cu[0], 14.6, 2.6), Vector3(-0.15, 0, 0), Vector3.ONE, true)
	_puff(wl, Vector3(0, 13.4, 4), 1.2, Color.WHITE, 0.05)

	# ---- right wall: neon heart, dresser and round mirror
	var rw := rooms._wall_group("right", -14)
	_put(rw, _heart_tube(), MeshKit.unlit(Color("#ff8fc0")), Vector3(0, 58, 1.4))
	_glow(rw, Color("#ff8fc0"), 34, Vector3(0, 58, 3), 0.35)
	var dr := _grp(rw, 0, 5)
	_put(dr, MeshKit.rbox(22, 15, 9, 1.2), white, Vector3(0, 7.5, 0), Vector3.ZERO, Vector3.ONE, true)
	for y in [4.5, 10.0]:
		_put(dr, MeshKit.rbox(20, 4.6, 0.6, 0.4), pink_lt, Vector3(0, y, 4.6))
		for x in [-5, 5]:
			_put(dr, SPH, gold, Vector3(x, y, 5.1), Vector3.ZERO, Vector3.ONE * 0.45)
	_put(dr, MeshKit.cylinder(1.4, 1.8, 4, 16), MeshKit.mat(Color("#bfe3ff"), 0.1), Vector3(-6, 17, 0))
	var fl_cols := [Color("#ffb3cf"), Color("#fff1a8"), Color("#c9b3ff"), Color.WHITE]
	var fl_pos := [[0, 0], [1.2, 0.8], [-1, 0.9], [0.4, -1]]
	for k in 4:
		_put(dr, SPH, MeshKit.mat(fl_cols[k], 0.7), Vector3(-6 + fl_pos[k][0], 21 + k * 0.4, fl_pos[k][1]), Vector3.ZERO, Vector3.ONE * 1.3)
	_plush(dr, 6, 15, 0, Color("#ffd3e3"), 0.8, -0.4)
	var mir_mat := StandardMaterial3D.new()
	mir_mat.albedo_texture = _mirror_tex()
	mir_mat.roughness = 0.05
	mir_mat.metallic = 0.2
	_put(rw, TableWorld._disc(8, 48), mir_mat, Vector3(30, 38, 1.4), Vector3(PI / 2, 0, 0))
	_put(rw, MeshKit.torus(8.2, 0.7, 48, 12), gold, Vector3(30, 38, 1.4), Vector3(PI / 2, 0, 0), Vector3.ONE, true)

	# ---- front wall: bookshelf with plushies, floor lamp, plant; a beanbag
	var fw := rooms._wall_group("front", 0)
	var sh := _cube_shelf(rng, fw, -18, 0, 3, 2, Color("#fffaf8"), [Color("#ffb3cf"), Color("#c9b3ff"), Color("#bfe3ff"), Color("#fff1a8"), Color("#9fe3d2")])
	var top: float = sh.get_meta("top")
	_plush(sh, -8, top, 4.5, Color("#fff6ee"), 0.9, 0.2)
	_plush(sh, 9, top, 4.5, Color("#d8caff"), 0.8, -0.2)
	_floor_lamp(fw, 14, 6, Color("#ffd3e3"))
	rooms._plant(fw, 30, 6, 1, Color("#d8caff"))
	var bb := _grp(R, 36, 30, rng.randf_range(0, 6), 1.1)
	_put(bb, SPH, MeshKit.mat(Color("#ffb3cf"), 0.85), Vector3(0, 4, 0), Vector3.ZERO, Vector3(7, 4.4, 7), true)
	_put(bb, SPH, MeshKit.mat(Color("#ffb3cf"), 0.85), Vector3(0, 6.5, -2.6), Vector3.ZERO, Vector3(5.4, 4.6, 3.6), true)

	# ---- hanging egg chair in the corner
	var ec := Node3D.new()
	ec.position = Vector3(-42, Y0 + 30, 36)
	R.add_child(ec)
	var wicker := MeshKit.mat(Color("#f2d2a6"), 0.7).duplicate() as StandardMaterial3D
	wicker.cull_mode = BaseMaterial3D.CULL_DISABLED
	_put(ec, _sphere_part(8, 28, 18, PI * 0.15, PI * 1.7, 0, PI * 0.8), wicker, Vector3.ZERO, Vector3(0, PI * 0.8, 0), Vector3(1, 1.25, 1), true)
	_put(ec, MeshKit.rbox(9, 2.4, 9, 1.2), pink_lt, Vector3(0, -6.5, 0), Vector3.ZERO, Vector3.ONE, true)
	_put(ec, MeshKit.rbox(6, 6, 2.2, 1.1), lav, Vector3(0, -3, -3), Vector3(0.3, PI * 0.8, 0))
	_put(ec, MeshKit.cylinder(0.18, 0.18, 56, 6), gold, Vector3(0, 38, 0))
	rooms._anims.append(func(t: float): ec.rotation.y = sin(t * 0.5) * 0.08)

	# ---- lights: rosy neon glow on the right, lavender twilight from the window, a warm pool by the bed
	rooms._omni(Color("#ff9cc8"), 0.38, 90, Vector3(50, Y0 + 58, -14))
	rooms._omni(Color("#d6c8ff"), 0.38, 150, Vector3(-40, Y0 + 60, 10))
	rooms._omni(Color("#ffe6c8"), 0.36, 120, Vector3(-4, Y0 + 30, -44))


# ---------- placement helpers (three.js put/grp: XYZ Euler order, no shadow unless asked) ----------

static func _put(p: Node3D, mesh: Mesh, m: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE, cast := false) -> MeshInstance3D:
	var mi := MeshKit.put(p, mesh, m, pos, Vector3.ZERO, scl, cast)
	mi.rotation_order = EULER_ORDER_XYZ
	mi.rotation = rot
	return mi

static func _grp(parent: Node3D, x: float, z: float, ry := 0.0, s := 1.0) -> Node3D:
	var g := Node3D.new()
	g.position = Vector3(x, 0, z)
	g.rotation.y = ry
	g.scale = Vector3.ONE * s
	parent.add_child(g)
	if parent.name.begins_with("Room_"):
		g.position.y = Y0
	return g

static func _glow(parent: Node3D, col: Color, size: float, pos: Vector3, op: float) -> Sprite3D:
	var s := MeshKit.glow(col, size, op)
	s.position = pos
	parent.add_child(s)
	return s

static func _emis_mat(col: Color, rough: float, emis: Color, energy: float, double := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.emission_enabled = true
	m.emission = emis
	m.emission_energy_multiplier = energy
	if double:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


# ---------- props ----------

## index.html windowOn(side, u, y, w, h, sky, {curtain, rod})
static func _window(rooms: Rooms, side: String, u: float, y: float, w: float, h: float, sky: Texture2D, curtain: Color, rod: Color) -> Node3D:
	var g := rooms._wall_group(side, u)
	var fm := MeshKit.mat(Color.WHITE, 0.3)
	var t := 1.5
	_put(g, MeshKit.plane(w, h), MeshKit.unlit(Color.WHITE, sky), Vector3(0, y, 0.2), Vector3(PI / 2, 0, 0))
	_put(g, MeshKit.rbox(w + 2 * t, t, 1.8, 0.6), fm, Vector3(0, y + h / 2 + t / 2, 0.9))
	_put(g, MeshKit.rbox(w + 2 * t, t, 1.8, 0.6), fm, Vector3(0, y - h / 2 - t / 2, 0.9))
	_put(g, MeshKit.rbox(t, h, 1.8, 0.6), fm, Vector3(-w / 2 - t / 2, y, 0.9))
	_put(g, MeshKit.rbox(t, h, 1.8, 0.6), fm, Vector3(w / 2 + t / 2, y, 0.9))
	_put(g, MeshKit.rbox(0.9, h, 0.9, 0.35), fm, Vector3(0, y, 0.6))
	_put(g, MeshKit.rbox(w, 0.9, 0.9, 0.35), fm, Vector3(0, y + h * 0.14, 0.6))
	_put(g, MeshKit.rbox(w + 7, 1.3, 5, 0.6), fm, Vector3(0, y - h / 2 - t - 0.5, 2.4), Vector3.ZERO, Vector3.ONE, true)
	var cm := MeshKit.mat(curtain, 0.85)
	for sx in [-1, 1]:
		for k in 4:
			_put(g, MeshKit.cylinder(1.15, 1.35, h + 8, 14), cm, Vector3(sx * (w / 2 + 2.2 + k * 2), y + 1, 3 + (k % 2) * 0.6), Vector3.ZERO, Vector3.ONE, true)
	var rm := MeshKit.mat(rod, 0.3)
	_put(g, MeshKit.cylinder(0.4, 0.4, w + 24, 10), rm, Vector3(0, y + h / 2 + 5.5, 3.2), Vector3(0, 0, PI / 2))
	for sx in [-1, 1]:
		_put(g, MeshKit.sphere(1, 24, 16), rm, Vector3(sx * (w / 2 + 12), y + h / 2 + 5.5, 3.2), Vector3.ZERO, Vector3.ONE * 0.9)
	return g

## index.html plush(): a soft bunny
static func _plush(p: Node3D, x: float, y: float, z: float, col: Color, s := 1.0, ry := 0.0) -> Node3D:
	var g := Node3D.new()
	g.position = Vector3(x, y, z)
	g.scale = Vector3.ONE * s
	g.rotation.y = ry
	p.add_child(g)
	var SPH := MeshKit.sphere(1, 24, 16)
	var c := MeshKit.mat(col, 0.9)
	var pink_in := MeshKit.mat(Color("#ffb3cc"), 0.8)
	var eye := MeshKit.mat(Color("#4a2b3d"), 0.4)
	_put(g, SPH, c, Vector3(0, 2, 0), Vector3.ZERO, Vector3(2.2, 2.1, 1.9), true)
	_put(g, SPH, c, Vector3(0, 5, 0.2), Vector3.ZERO, Vector3.ONE * 1.75, true)
	for ex in [-0.7, 0.7]:
		_put(g, SPH, c, Vector3(ex, 7.4, 0), Vector3(0, 0, ex * -0.25), Vector3(0.55, 1.7, 0.45))
		_put(g, SPH, pink_in, Vector3(ex, 7.4, 0.3), Vector3(0, 0, ex * -0.25), Vector3(0.3, 1.2, 0.2))
		_put(g, SPH, eye, Vector3(ex * 0.85, 5.3, 1.6), Vector3.ZERO, Vector3.ONE * 0.2)
	return g

## index.html puff(): a soft cloud of a few spheres
static func _puff(p: Node3D, pos: Vector3, s: float, col: Color, emis: float) -> Node3D:
	var g := Node3D.new()
	g.position = pos
	g.scale = Vector3.ONE * s
	p.add_child(g)
	var cm := _emis_mat(col, 0.9, col, emis)
	var SPH := MeshKit.sphere(1, 24, 16)
	for b in [[0, 0, 0, 1.3], [-1.4, -0.3, 0.2, 1], [1.5, -0.25, 0, 1.05], [-0.6, 0.7, -0.2, 0.95], [0.7, 0.6, 0.3, 0.9], [2.5, -0.55, 0.1, 0.7], [-2.4, -0.6, 0, 0.7]]:
		var r: float = b[3]
		_put(g, SPH, cm, Vector3(b[0], b[1], b[2]), Vector3.ZERO, Vector3(r, r * 0.9, r * 0.85))
	return g

## index.html cubeShelf(): a cube bookcase with books in most cubbies; its top height is in meta "top"
static func _cube_shelf(rng: RandomNumberGenerator, p: Node3D, x: float, z: float, cols: int, rows: int, wood: Color, book_cols: Array) -> Node3D:
	var g := _grp(p, x, z)
	var wm := MeshKit.mat(wood, 0.4)
	var cw := 9.5
	var ch := 9.5
	var d := 8.5
	var t := 0.9
	var W2 := cols * cw
	var H2 := rows * ch
	_put(g, MeshKit.rbox(W2 + t, t, d, 0.35), wm, Vector3(0, t / 2, d / 2), Vector3.ZERO, Vector3.ONE, true)
	for r in range(1, rows + 1):
		_put(g, MeshKit.rbox(W2 + t, t, d, 0.35), wm, Vector3(0, r * ch + t / 2, d / 2), Vector3.ZERO, Vector3.ONE, true)
	for c in cols + 1:
		_put(g, MeshKit.rbox(t, H2 + t, d, 0.35), wm, Vector3(-W2 / 2 + c * cw, H2 / 2 + t / 2, d / 2), Vector3.ZERO, Vector3.ONE, true)
	for r in rows:
		for c in cols:
			if (r + c) % 3 == 2:
				continue                                # leave some cubbies open
			var bx := -W2 / 2 + c * cw + 1.4
			var n := 4 + int(floor(rng.randf_range(0, 3)))
			var k := 0
			while k < n and bx < -W2 / 2 + (c + 1) * cw - 1.6:
				var bt := rng.randf_range(0.9, 1.5)
				var bh := rng.randf_range(5.2, 7.6)
				var bc: Color = book_cols[int(floor(rng.randf_range(0, book_cols.size())))]
				_put(g, MeshKit.rbox(bt, bh, 6, 0.2), MeshKit.mat(bc, 0.6), Vector3(bx + bt / 2, r * ch + t + bh / 2, d / 2 + 0.3), Vector3(0, 0, -0.18 if k == n - 1 else 0.0))
				bx += bt + 0.15
				k += 1
	g.set_meta("top", H2 + t)
	return g

## index.html floorLamp(): a pole lamp with a glowing open shade (no shadows: it's a light)
static func _floor_lamp(p: Node3D, x: float, z: float, shade: Color) -> Node3D:
	var g := _grp(p, x, z)
	var pole := MeshKit.mat(Color("#e8b070"), 0.3)
	_put(g, MeshKit.cylinder(3.4, 3.8, 0.8, 28), pole, Vector3(0, 0.4, 0))
	_put(g, MeshKit.cylinder(0.35, 0.35, 40, 10), pole, Vector3(0, 20, 0))
	_put(g, _open_cyl(3.4, 5.4, 7, 28), _emis_mat(shade, 0.8, shade, 0.35, true), Vector3(0, 42, 0))
	_put(g, MeshKit.sphere(1, 24, 16), MeshKit.unlit(Color("#fff3d6")), Vector3(0, 40.5, 0), Vector3.ZERO, Vector3.ONE * 1.1)
	_glow(g, Color("#ffe2b0"), 16, Vector3(0, 40, 0), 0.55)
	return g

static func _mirror_tex() -> GradientTexture2D:
	var gr := Gradient.new()
	gr.offsets = PackedFloat32Array([0.0, 0.45, 0.55, 1.0])
	gr.colors = PackedColorArray([Color("#f3efff"), Color("#ffffff"), Color("#e8e0ff"), Color("#ffe6f0")])
	var t := GradientTexture2D.new()
	t.gradient = gr
	t.fill = GradientTexture2D.FILL_LINEAR
	t.fill_from = Vector2(0, 0)
	t.fill_to = Vector2(1, 1)
	t.width = 256
	t.height = 256
	return t


# ---------- geometry ----------

## An open-ended cylinder (no caps), like THREE.CylinderGeometry(..., openEnded = true).
static func _open_cyl(top: float, bottom: float, h: float, segs: int) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top; m.bottom_radius = bottom; m.height = h; m.radial_segments = segs; m.rings = 1
	m.cap_top = false; m.cap_bottom = false
	return m

## THREE.CylinderGeometry(rTop, rBottom, h, radial, 1, true, thetaStart, thetaLength): part of an open cylinder.
static func _cyl_segment(rt: float, rb: float, h: float, radial: int, th0: float, thl: float) -> ArrayMesh:
	var pts := []
	var nrms := []
	var uvs := []
	var slope := (rb - rt) / h
	for iy in 2:
		var r := rt if iy == 0 else rb
		for ix in radial + 1:
			var th := th0 + thl * ix / radial
			pts.append(Vector3(r * sin(th), h / 2 - iy * h, r * cos(th)))
			nrms.append(Vector3(sin(th), slope, cos(th)).normalized())
			uvs.append(Vector2(float(ix) / radial, iy))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ix in radial:
		var a := ix
		var b := ix + radial + 1
		var n: Vector3 = (nrms[a] + nrms[a + 1]) / 2
		MeshKit._tri_oriented(st, pts, nrms, uvs, a, b, a + 1, n)
		MeshKit._tri_oriented(st, pts, nrms, uvs, b, b + 1, a + 1, n)
	return st.commit()

## THREE.SphereGeometry(r, wSeg, hSeg, phiStart, phiLength, thetaStart, thetaLength): a partial sphere.
static func _sphere_part(r: float, ws: int, hs: int, ph0: float, phl: float, th0: float, thl: float) -> ArrayMesh:
	var pts := []
	var nrms := []
	var uvs := []
	for iy in hs + 1:
		var v := float(iy) / hs
		for ix in ws + 1:
			var u := float(ix) / ws
			var ph := ph0 + u * phl
			var th := th0 + v * thl
			var p := Vector3(-r * cos(ph) * sin(th), r * cos(th), r * sin(ph) * sin(th))
			pts.append(p)
			nrms.append(p.normalized() if p.length() > 0.0001 else Vector3.UP)
			uvs.append(Vector2(u, v))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iy in hs:
		for ix in ws:
			var a := iy * (ws + 1) + ix
			var b := a + ws + 1
			var n: Vector3 = (nrms[a] + nrms[b + 1]).normalized()
			MeshKit._tri_oriented(st, pts, nrms, uvs, a, b, a + 1, n)
			MeshKit._tri_oriented(st, pts, nrms, uvs, b, b + 1, a + 1, n)
	return st.commit()

## THREE.ExtrudeGeometry(shape, {depth, bevelThickness, bevelSize, bevelSegments}) centred, with smooth normals.
static func _extrude(shape: PackedVector2Array, depth: float, bt: float, bsz: float, bsegs: int) -> ArrayMesh:
	var n := shape.size()
	var area := 0.0
	for i in n:
		area += shape[i].cross(shape[(i + 1) % n])
	var sgn := 1.0 if area > 0 else -1.0
	var edge_n := []                                  # outward normal of edge i -> i+1
	for i in n:
		var e := shape[(i + 1) % n] - shape[i]
		edge_n.append(Vector2(e.y, -e.x).normalized() * sgn)
	var miter := []                                   # bevel direction per vertex (three.js getBevelVec, capped)
	for i in n:
		var n0: Vector2 = edge_n[(i - 1 + n) % n]
		var n1: Vector2 = edge_n[i]
		var mv := (n0 + n1) / maxf(1.0 + n0.dot(n1), 0.05)
		if mv.length_squared() > 2.0:
			mv = mv.normalized() * sqrt(2.0)
		miter.append(mv)
	# rings from the front cap to the back cap: [offset, z, z-normal weight]
	var rings := []
	for b in bsegs:
		var t := float(b) / bsegs
		rings.append([bsz * sin(t * PI / 2), -bt * cos(t * PI / 2), -cos(t * PI / 2)])
	rings.append([bsz, 0.0, 0.0])
	rings.append([bsz, depth, 0.0])
	for b in range(bsegs - 1, -1, -1):
		var t := float(b) / bsegs
		rings.append([bsz * sin(t * PI / 2), depth + bt * cos(t * PI / 2), cos(t * PI / 2)])
	var pts := []
	var nrms := []
	var uvs := []
	for rg in rings:
		var off: float = rg[0]
		var wz: float = rg[2]
		for i in n:
			var mv: Vector2 = miter[i]
			var q: Vector2 = shape[i] + mv * off
			pts.append(Vector3(q.x, q.y, rg[1]))
			var mn := mv.normalized()
			nrms.append((Vector3(mn.x, mn.y, 0) * sqrt(maxf(0.0, 1.0 - wz * wz)) + Vector3(0, 0, wz)).normalized())
			uvs.append(q)
	var nr := rings.size()
	# caps
	var tris := Geometry2D.triangulate_polygon(shape)
	var cap0 := pts.size()
	for i in n:
		pts.append(Vector3(shape[i].x, shape[i].y, -bt)); nrms.append(Vector3(0, 0, -1)); uvs.append(shape[i])
	var cap1 := pts.size()
	for i in n:
		pts.append(Vector3(shape[i].x, shape[i].y, depth + bt)); nrms.append(Vector3(0, 0, 1)); uvs.append(shape[i])
	# centre the bounding box (three.js geometry.center())
	var lo: Vector3 = pts[0]
	var hi: Vector3 = pts[0]
	for p in pts:
		lo = lo.min(p); hi = hi.max(p)
	var ctr := (lo + hi) / 2
	for k in pts.size():
		pts[k] = pts[k] - ctr
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in nr - 1:
		var wz: float = (rings[j][2] + rings[j + 1][2]) / 2
		for i in n:
			var i2 := (i + 1) % n
			var a := j * n + i
			var b := j * n + i2
			var c := (j + 1) * n + i
			var d := (j + 1) * n + i2
			var en: Vector2 = edge_n[i]
			var fn := Vector3(en.x, en.y, wz * 0.5)
			MeshKit._tri_oriented(st, pts, nrms, uvs, a, b, d, fn)
			MeshKit._tri_oriented(st, pts, nrms, uvs, a, d, c, fn)
	for k in range(0, tris.size(), 3):
		MeshKit._tri_oriented(st, pts, nrms, uvs, cap0 + tris[k], cap0 + tris[k + 1], cap0 + tris[k + 2], Vector3(0, 0, -1))
		MeshKit._tri_oriented(st, pts, nrms, uvs, cap1 + tris[k], cap1 + tris[k + 1], cap1 + tris[k + 2], Vector3(0, 0, 1))
	return st.commit()

## index.html starGeo(r1, r2, d): a puffy five-point star
static func _star_mesh(r1: float, r2: float, d: float) -> ArrayMesh:
	var s := PackedVector2Array()
	for k in 10:
		var a := PI / 2 + k * PI / 5
		var r := r2 if k % 2 else r1
		s.append(Vector2(cos(a) * r, sin(a) * r))
	return _extrude(s, d, d * 0.4, d * 0.35, 2)

## index.html moonGeo(r): a puffy crescent, open to the right
static func _moon_mesh(r: float) -> ArrayMesh:
	var s := PackedVector2Array()
	var c := r * 0.44
	var ri := sqrt(c * c + r * r)
	for k in 25:
		var a := PI / 2 + k / 24.0 * PI
		s.append(Vector2(cos(a) * r, sin(a) * r))
	var f0 := atan2(-r, -c)
	var f1 := atan2(r, -c) - TAU
	for k in range(1, 24):
		var f := f0 + (f1 - f0) * k / 24.0
		s.append(Vector2(c + cos(f) * ri, sin(f) * ri))
	return _extrude(s, 1, 0.5, 0.4, 3)

## The neon heart: a tube (radius .32) along the classic heart curve, scaled by .42, in the xy plane.
static func _heart_tube() -> ArrayMesh:
	var segs := 120
	var radial := 8
	var rad := 0.32
	var pts := []
	var nrms := []
	var uvs := []
	var hp := func(a: float) -> Vector3:
		return Vector3(16 * pow(sin(a), 3), 13 * cos(a) - 5 * cos(2 * a) - 2 * cos(3 * a) - cos(4 * a), 0) * 0.42
	for i in segs + 1:
		var a := TAU * i / segs
		var p: Vector3 = hp.call(a)
		var tg: Vector3 = (hp.call(a + 0.001) - hp.call(a - 0.001)).normalized()
		var nn := tg.cross(Vector3.BACK).normalized()
		for j in radial + 1:
			var v := TAU * j / radial
			var dir := nn * cos(v) + Vector3.BACK * sin(v)
			pts.append(p + dir * rad)
			nrms.append(dir)
			uvs.append(Vector2(float(i) / segs, float(j) / radial))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in segs:
		for j in radial:
			var a := i * (radial + 1) + j
			var b := a + radial + 1
			var fn: Vector3 = (nrms[a] + nrms[a + 1]).normalized()
			MeshKit._tri_oriented(st, pts, nrms, uvs, a, b, a + 1, fn)
			MeshKit._tri_oriented(st, pts, nrms, uvs, b, b + 1, a + 1, fn)
	return st.commit()


# ---------- painted textures ----------

static func _hsl(h: float, s: float, l: float) -> Color:
	return Rooms._hsl(h, s, l)

## index.html planks(base, rows): honey-to-blush floorboards
static func _planks_painter(base: Vector3, rows: int) -> Callable:
	return func(c: Control):
		var w := c.size.x
		var h := c.size.y
		var rh := h / rows
		var rr := RandomNumberGenerator.new(); rr.seed = 29
		for r in rows:
			var x := -rr.randf_range(0, 400)
			while x < w:
				var ln := rr.randf_range(260, 520)
				c.draw_rect(Rect2(x, r * rh, ln, rh), _hsl(base.x + rr.randf_range(-3, 3), base.y, base.z + rr.randf_range(-4, 4)))
				for k in 5:
					var y := r * rh + rr.randf_range(4, rh - 4)
					c.draw_line(Vector2(x, y), Vector2(x + ln, y + rr.randf_range(-6, 6)), Color(150 / 255.0, 90 / 255.0, 50 / 255.0, 0.12), 1.5, true)
				c.draw_rect(Rect2(x, r * rh, 2, rh), Color(140 / 255.0, 80 / 255.0, 50 / 255.0, 0.22))
				x += ln
			c.draw_rect(Rect2(0, r * rh, w, 2.5), Color(140 / 255.0, 80 / 255.0, 50 / 255.0, 0.25))
			c.draw_rect(Rect2(0, r * rh + 3, w, 2), Color(1, 1, 1, 0.18))

static func _bez(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var u := 1.0 - t
	return p0 * u * u * u + p1 * 3 * u * u * t + p2 * 3 * u * t * t + p3 * t * t * t

## index.html wallTex({top, bottom, pat, patColor, wains, wainsColor})
static func _wall_painter(top: Color, bottom: Color, pat: String, pat_col: Color, wains: float, wains_col: Color) -> Callable:
	return func(c: Control):
		var w := c.size.x
		var h := c.size.y
		for k in 64:
			c.draw_rect(Rect2(0, h * k / 64.0, w, h / 64.0 + 1), top.lerp(bottom, (k + 0.5) / 64.0))
		if pat == "stars" or pat == "hearts":
			var y := 26.0
			var row := 0
			while y < h * (1 - wains) - 10:
				var x := (row % 2) * 32 + 18.0
				while x < w:
					if pat == "stars":
						c.draw_colored_polygon(TexBaker.star_points(Vector2(x, y), 7), pat_col)
					else:
						var hp := PackedVector2Array()
						for k in 12:
							hp.append(_bez(Vector2(x, y + 6), Vector2(x - 10, y - 1), Vector2(x - 5, y - 9), Vector2(x, y - 3), k / 12.0))
						for k in 12:
							hp.append(_bez(Vector2(x, y - 3), Vector2(x + 5, y - 9), Vector2(x + 10, y - 1), Vector2(x, y + 6), k / 12.0))
						c.draw_colored_polygon(hp, pat_col)
					x += 64
				y += 46; row += 1
		elif pat == "stripes":
			var x := 0.0
			while x < w:
				c.draw_rect(Rect2(x, 0, 18, h), pat_col)
				x += 40
		if wains > 0:
			var y0 := h * (1 - wains)
			c.draw_rect(Rect2(0, y0, w, h - y0), wains_col)
			var x := 10.0
			while x < w:
				c.draw_rect(Rect2(x, y0 + 14, 60, h - y0 - 30), Color(140 / 255.0, 90 / 255.0, 110 / 255.0, 0.14), false, 3.0)
				x += 80
			c.draw_rect(Rect2(0, y0 - 6, w, 8), Color(1, 1, 1, 0.9))

## index.html skyTex({stops: #a99cff / #f4b6d8 / #ffd9c2, stars, moon, clouds: 4}): a lavender-pink twilight.
static func _sky_painter() -> Callable:
	return func(c: Control):
		var w := c.size.x
		var h := c.size.y
		var stops := [[0.0, Color("#a99cff")], [0.55, Color("#f4b6d8")], [1.0, Color("#ffd9c2")]]
		for k in 64:
			var t := (k + 0.5) / 64.0
			var col: Color = stops[0][1]
			for s in 2:
				if t >= stops[s][0] and t <= stops[s + 1][0]:
					col = (stops[s][1] as Color).lerp(stops[s + 1][1], (t - stops[s][0]) / (stops[s + 1][0] - stops[s][0]))
			c.draw_rect(Rect2(0, h * k / 64.0, w, h / 64.0 + 1), col)
		var rr := RandomNumberGenerator.new(); rr.seed = 17
		for k in 40:
			c.draw_colored_polygon(TexBaker.star_points(Vector2(rr.randf_range(0, w), rr.randf_range(0, h * 0.6)), rr.randf_range(2, 5)), Color(1, 1, 1, 0.85))
		TexBaker.circle(c, Vector2(w * 0.3, h * 0.24), 38, Color("#fff6d6"))
		TexBaker.circle(c, Vector2(w * 0.3 + 18, h * 0.24 - 8), 34, Color("#a99cff"))
		for k in 4:
			var cx := rr.randf_range(-20, w + 20)
			var cy := rr.randf_range(h * 0.2, h * 0.75)
			var sz := rr.randf_range(22, 44)
			for b in [[0, 0, 1.0], [-1.1, 0.3, 0.7], [1.1, 0.3, 0.75], [-0.5, -0.35, 0.8], [0.5, -0.3, 0.7]]:
				TexBaker.circle(c, Vector2(cx + b[0] * sz, cy + b[1] * sz), b[2] * sz, Color(1, 230 / 255.0, 245 / 255.0, 0.7))

## index.html rugTex({base, dots, rings})
static func _rug_painter(base: Color, dots: Color, rings: Array) -> Callable:
	return func(c: Control):
		var w := c.size.x
		c.draw_rect(Rect2(Vector2.ZERO, c.size), base)
		for k in rings.size():
			c.draw_arc(c.size / 2, w / 2 - 20 - k * 30, 0, TAU, 128, rings[k], 14, true)
		var rr := RandomNumberGenerator.new(); rr.seed = 13
		for k in 90:
			TexBaker.circle(c, Vector2(rr.randf_range(0, w), rr.randf_range(0, w)), rr.randf_range(4, 9), dots)
		for k in 2000:
			c.draw_rect(Rect2(rr.randf_range(0, w), rr.randf_range(0, w), 2, 2), Color(1, 1, 1, rr.randf_range(0, 0.08)))
