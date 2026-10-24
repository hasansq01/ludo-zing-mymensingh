extends RefCounted
## Cloudside Playroom (index.html BUILD.cloud): sky-blue cloud-papered walls, a pastel rainbow on the back wall,
## floating clouds and a hot-air balloon bobbing under the ceiling, porthole windows, a toy shelf, a kite, beanbags,
## a striped teepee and a star garland. Same units and positions as the web version.

const Y0 := TableWorld.Y0
const H := TableWorld.H
const W := TableWorld.W

static func build(rooms: Rooms, baker: TexBaker) -> void:
	var rng := rooms.rng
	var floor_t := await baker.bake(Vector2i(512, 512), _rug_painter(Color("#e6fbf6"), [], [Color("#9fe3d2"), Color("#bfe3ff"), Color("#d8caff"), Color("#fff1a8"), Color("#ffd3e3")]))
	var rug_t := await baker.bake(Vector2i(512, 512), _rug_painter(Color("#fffaf2"), [Color("#bfe3ff"), Color("#d8caff"), Color("#ffd3e3"), Color("#fff1a8")], []))
	var wall_b := await baker.bake(Vector2i(640, 512), _wall_painter(Color("#8fceff"), Color("#d6efff"), "clouds", Color(1, 1, 1, 0.9), 1))
	var wall_l := await baker.bake(Vector2i(640, 512), _wall_painter(Color("#a9d9ff"), Color("#e0f3ff"), "clouds", Color(1, 1, 1, 0.85), 2))
	var wall_r := await baker.bake(Vector2i(640, 512), _wall_painter(Color("#d9ccff"), Color("#eee8ff"), "clouds", Color(1, 1, 1, 0.7), 3))
	var wall_f := await baker.bake(Vector2i(640, 512), _wall_painter(Color("#bff0e4"), Color("#e2faf4"), "stars", Color(1, 1, 1, 0.8), 4))
	var sky := await baker.bake(Vector2i(512, 640), _paint_sky)
	var balloon_t := await baker.bake(Vector2i(256, 256), _stripe_painter([Color("#ff9f9a"), Color("#fff6ea"), Color("#ffe58a"), Color("#fff6ea"), Color("#8fcaff"), Color("#fff6ea"), Color("#c4b0ff"), Color("#fff6ea")], 16))
	var teepee_t := await baker.bake(Vector2i(256, 256), _stripe_painter([Color("#fffaf2"), Color("#d8caff")], 12))
	var R := rooms._cur

	# shell: floor, ceiling, four walls, skirting and cornice
	MeshKit.put(R, MeshKit.plane(2 * W, 2 * W), MeshKit.tex_mat(floor_t, 0.7, Vector2(4, 4)), Vector3(0, Y0, 0), Vector3.ZERO, Vector3.ONE, false)
	MeshKit.put(R, MeshKit.plane(2 * W, 2 * W), MeshKit.mat(Color("#eaf6ff"), 0.95), Vector3(0, Y0 + H, 0), Vector3(PI, 0, 0), Vector3.ONE, false)
	var walls := {back = MeshKit.tex_mat(wall_b, 0.9), left = MeshKit.tex_mat(wall_l, 0.9), right = MeshKit.tex_mat(wall_r, 0.9), front = MeshKit.tex_mat(wall_f, 0.9)}
	var white := MeshKit.mat(Color.WHITE, 0.3)
	for side in ["back", "left", "right", "front"]:
		var g := rooms._wall_group(side, 0)
		MeshKit.put(g, MeshKit.plane(2 * W, H), walls[side], Vector3(0, H / 2, 0), Vector3(PI / 2, 0, 0), Vector3.ONE, false)
		MeshKit.put(g, MeshKit.rbox(2 * W, 3.2, 1.4, 0.5), white, Vector3(0, 1.6, 0.7), Vector3.ZERO, Vector3.ONE, false)
		MeshKit.put(g, MeshKit.rbox(2 * W, 2, 1.6, 0.6), white, Vector3(0, H - 1, 0.8), Vector3.ZERO, Vector3.ONE, false)
	# round ringed rug under the table
	MeshKit.put(R, TableWorld._disc(25, 64), MeshKit.tex_mat(rug_t, 1.0), Vector3(0, Y0 + 0.08, 0), Vector3.ZERO, Vector3.ONE, false)

	# back wall: big pastel rainbow with clouds at its feet
	var bw := rooms._wall_group("back", 0)
	var bands := [Color("#ff9f9a"), Color("#ffc48a"), Color("#ffe58a"), Color("#9fe3c0"), Color("#8fcaff"), Color("#c4b0ff")]
	for k in 6:
		MeshKit.put(bw, _torus_xy(30 - k * 3.1, 1.55, 14, 64, PI), MeshKit.mat(bands[k], 0.35), Vector3(0, 18, 2.2))
	_puff(bw, Vector3(-26, 19, 5), 3.4, Color.WHITE, 0.1)
	_puff(bw, Vector3(26, 19, 5), 3.4, Color.WHITE, 0.1)
	_blocks(R, rng, -40, -46, [Color("#ff9f9a"), Color("#ffe58a"), Color("#8fcaff"), Color("#9fe3c0"), Color("#c4b0ff")])
	_blocks(R, rng, 40, -44, [Color("#c4b0ff"), Color("#ffc48a"), Color("#9fe3c0"), Color("#ff9f9a"), Color("#8fcaff")])

	# floating clouds near the ceiling, gently bobbing on strings
	var string_m := MeshKit.mat(Color.WHITE, 0.5)
	var clouds := [[-30.0, 52.0, -20.0, 3.2, Color("#e9e2ff")], [24.0, 56.0, -30.0, 3.8, Color.WHITE], [38.0, 48.0, 20.0, 2.8, Color("#dfeaff")], [-20.0, 58.0, 30.0, 3.4, Color("#f2ecff")], [0.0, 60.0, -6.0, 2.6, Color.WHITE]]
	for k in clouds.size():
		var c: Array = clouds[k]
		var y: float = c[1]
		var s: float = c[3]
		var p := _puff(R, Vector3(c[0], Y0 + y, c[2]), s, c[4], 0.12)
		MeshKit.put(p, MeshKit.cylinder(0.06, 0.06, H - y, 4), string_m, Vector3(0, (H - y) / 2 / s, 0), Vector3.ZERO, Vector3.ONE / s, false)
		var kk := float(k)
		rooms._anims.append(func(t: float): p.position.y = Y0 + y + sin(t * 0.6 + kk) * 1.2)

	# hot-air balloon hanging in a corner, slowly turning
	var hb := Node3D.new()
	hb.position = Vector3(40, Y0 + 54, -34)
	R.add_child(hb)
	MeshKit.put(hb, MeshKit.sphere(1), MeshKit.tex_mat(balloon_t, 0.45), Vector3.ZERO, Vector3.ZERO, Vector3(7, 8, 7))
	var skirt := CylinderMesh.new()
	skirt.top_radius = 3; skirt.bottom_radius = 1.6; skirt.height = 4; skirt.radial_segments = 20; skirt.rings = 1
	skirt.cap_top = false; skirt.cap_bottom = false
	MeshKit.put(hb, skirt, MeshKit.mat(Color("#ff9f9a"), 0.5), Vector3(0, -8.6, 0), Vector3.ZERO, Vector3.ONE, false)
	MeshKit.put(hb, MeshKit.rbox(4, 3, 4, 0.8), MeshKit.mat(Color("#e7a463"), 0.6), Vector3(0, -15, 0))
	for q in [[-1.6, -1.6], [1.6, -1.6], [-1.6, 1.6], [1.6, 1.6]]:
		MeshKit.put(hb, MeshKit.cylinder(0.07, 0.07, 4.6, 4), string_m, Vector3(q[0] * 0.9, -11.6, q[1] * 0.9), Vector3.ZERO, Vector3.ONE, false)
	MeshKit.put(hb, MeshKit.cylinder(0.06, 0.06, 41, 4), string_m, Vector3(0, 28, 0), Vector3.ZERO, Vector3.ONE, false)
	rooms._anims.append(func(t: float):
		hb.rotation.y = t * 0.15
		hb.position.y = Y0 + 54 + sin(t * 0.8) * 1.5)

	# left wall: two round porthole windows and a toy shelf
	var lw := rooms._wall_group("left", 0)
	var sky_m := MeshKit.unlit(Color.WHITE, sky)
	var ring_m := MeshKit.mat(Color("#fff1a8"), 0.3)
	for u in [-18.0, 18.0]:
		MeshKit.put(lw, _disc_xy(10, 48), sky_m, Vector3(u, 54, 0.2), Vector3.ZERO, Vector3.ONE, false)
		MeshKit.put(lw, _torus_xy(10.6, 1.4, 14, 48, TAU), ring_m, Vector3(u, 54, 1))
	MeshKit.put(lw, MeshKit.rbox(40, 1.4, 6, 0.6), white, Vector3(0, 34, 3))
	var toys := [[-14.0, Color("#ff9f9a")], [-6.0, Color("#8fcaff")], [8.0, Color("#9fe3c0")], [15.0, Color("#ffe58a")]]
	for k in 4:
		var x: float = toys[k][0]
		if k % 2:
			MeshKit.put(lw, MeshKit.rbox(3.4, 3.4, 3.4, 0.7), MeshKit.mat(toys[k][1], 0.35), Vector3(x, 36.4, 3), Vector3(0, 0.4, 0), Vector3.ONE, false)
		else:
			MeshKit.put(lw, MeshKit.sphere(1), MeshKit.mat(toys[k][1], 0.3), Vector3(x, 36.6, 3), Vector3.ZERO, Vector3.ONE * 1.9, false)
	_plush(lw, Vector3(0, 34.7, 3), Color("#bfe3ff"), 0.7)

	# right wall: a kite with a ribbon tail; beanbags on the floor
	var rw := rooms._wall_group("right", 0)
	var kite := Node3D.new()
	kite.position = Vector3(-14, 58, 1.2)
	kite.rotation.z = 0.25
	rw.add_child(kite)
	var panes := [[Color("#ff9f9a"), Vector2(0, 8), Vector2(0, 0), Vector2(-5.5, 0)], [Color("#8fcaff"), Vector2(0, 8), Vector2(5.5, 0), Vector2(0, 0)], [Color("#ffe58a"), Vector2(-5.5, 0), Vector2(0, 0), Vector2(0, -11)], [Color("#9fe3c0"), Vector2(0, 0), Vector2(5.5, 0), Vector2(0, -11)]]
	for pn in panes:
		MeshKit.put(kite, _tri_xy(pn[1], pn[2], pn[3]), MeshKit.mat(pn[0], 0.5), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)
	var tail := []
	for k in 11:
		tail.append(Vector3(sin(k * 0.9) * 2.5, -11 - k * 2.4, 0.1))
	MeshKit.put(kite, _tube(tail, 40, 0.12, 4), string_m, Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)
	var bows := [Color("#c4b0ff"), Color("#ff9f9a"), Color("#8fcaff")]
	var n_bow := 0
	for k in tail.size():
		if k % 3 == 2:
			var q: Vector3 = tail[k]
			MeshKit.put(kite, MeshKit.rbox(2, 1, 0.4, 0.2), MeshKit.mat(bows[n_bow % 3], 0.5), Vector3(q.x, q.y, 0.3), Vector3.ZERO, Vector3.ONE, false)
			n_bow += 1
	_beanbag(R, rng, 44, 10, Color("#8fcaff"), 1.1)
	_beanbag(R, rng, 46, 26, Color("#ffe58a"), 0.95)

	# front wall: striped teepee, star garland, a plant
	var tp := Node3D.new()
	tp.position = Vector3(-38, Y0, 40)
	tp.rotation.y = 0.6
	R.add_child(tp)
	var cone := CylinderMesh.new()
	cone.top_radius = 0; cone.bottom_radius = 12; cone.height = 26; cone.radial_segments = 6; cone.rings = 1
	cone.cap_top = false; cone.cap_bottom = false
	var cone_m := MeshKit.tex_mat(teepee_t, 0.8)
	cone_m.cull_mode = BaseMaterial3D.CULL_DISABLED
	MeshKit.put(tp, cone, cone_m, Vector3(0, 13, 0))
	var pole_m := MeshKit.mat(Color("#e7a463"), 0.5)
	for k in 6:
		var a := k / 6.0 * TAU
		MeshKit.put(tp, MeshKit.cylinder(0.25, 0.25, 34, 6), pole_m, Vector3(cos(a) * 4.2, 16, sin(a) * 4.2), Vector3(sin(a) * -0.32, 0, cos(a) * 0.32))
	var fw := rooms._wall_group("front", 0)
	var gpts := []
	for k in 13:
		var t := k / 12.0
		gpts.append(Vector3(-50 + t * 100, 70 - sin(t * PI) * 8, 2))
	MeshKit.put(fw, _tube(gpts, 40, 0.1, 4), string_m, Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)
	var star := _star_mesh(1.8, 0.8, 0.5)
	var star_cols := [Color("#ffe58a"), Color.WHITE, Color("#ff9f9a"), Color("#8fcaff")]
	for k in range(1, 16):
		var q := _catmull(gpts, k / 16.0)
		MeshKit.put(fw, star, _emat(star_cols[k % 4], 0.3, 0.3), Vector3(q.x, q.y - 2.4, q.z), Vector3.ZERO, Vector3.ONE, false)
	rooms._plant(fw, 30, 6, 1.1, Color("#bfe3ff"))

	# cool daylight from above, a warm fill, a lilac wash at the rainbow
	rooms._omni(Color("#d6ecff"), 0.41, 160, Vector3(-40, Y0 + 62, -10))
	rooms._omni(Color("#fff0d6"), 0.33, 130, Vector3(30, Y0 + 50, 40))
	rooms._omni(Color("#e6dcff"), 0.3, 140, Vector3(10, Y0 + 70, -46))


# ---------- props (index.html puff, blocks, beanbag, plush) ----------

static func _emat(col: Color, rough: float, emis: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = emis
	return m

## A soft cloud of seven squashed spheres, faintly self-lit.
static func _puff(p: Node3D, pos: Vector3, s: float, col: Color, emis: float) -> Node3D:
	var g := Node3D.new()
	g.position = pos
	g.scale = Vector3.ONE * s
	p.add_child(g)
	var cm := _emat(col, 0.9, emis)
	for b in [[0, 0, 0, 1.3], [-1.4, -0.3, 0.2, 1], [1.5, -0.25, 0, 1.05], [-0.6, 0.7, -0.2, 0.95], [0.7, 0.6, 0.3, 0.9], [2.5, -0.55, 0.1, 0.7], [-2.4, -0.6, 0, 0.7]]:
		var r: float = b[3]
		MeshKit.put(g, MeshKit.sphere(1), cm, Vector3(b[0], b[1], b[2]), Vector3.ZERO, Vector3(r, r * 0.9, r * 0.85), false)
	return g

## A little heap of five rounded toy blocks on the floor.
static func _blocks(R: Node3D, rng: RandomNumberGenerator, x: float, z: float, cols: Array) -> void:
	var g := Node3D.new()
	g.position = Vector3(x, Y0, z)
	g.rotation.y = rng.randf_range(0, 6)
	R.add_child(g)
	var spots := [[0, 0, 0], [4.4, 0, 0.6], [1.8, 0, 4.2], [2.2, 4.1, 1.4], [-3.6, 0, 3]]
	for k in spots.size():
		var sp: Array = spots[k]
		MeshKit.put(g, MeshKit.rbox(4, 4, 4, 0.8), MeshKit.mat(cols[k % cols.size()], 0.35), Vector3(sp[0], sp[1] + 2, sp[2]), Vector3(0, rng.randf_range(-0.4, 0.4), 0))

static func _beanbag(R: Node3D, rng: RandomNumberGenerator, x: float, z: float, col: Color, s: float) -> void:
	var g := Node3D.new()
	g.position = Vector3(x, Y0, z)
	g.rotation.y = rng.randf_range(0, 6)
	g.scale = Vector3.ONE * s
	R.add_child(g)
	MeshKit.put(g, MeshKit.sphere(1), MeshKit.mat(col, 0.85), Vector3(0, 4, 0), Vector3.ZERO, Vector3(7, 4.4, 7))
	MeshKit.put(g, MeshKit.sphere(1), MeshKit.mat(col, 0.85), Vector3(0, 6.5, -2.6), Vector3.ZERO, Vector3(5.4, 4.6, 3.6))

## A soft bunny.
static func _plush(p: Node3D, pos: Vector3, col: Color, s: float) -> void:
	var g := Node3D.new()
	g.position = pos
	g.scale = Vector3.ONE * s
	p.add_child(g)
	var c := MeshKit.mat(col, 0.9)
	var pink := MeshKit.mat(Color("#ffb3cc"), 0.8)
	var eye := MeshKit.mat(Color("#4a2b3d"), 0.4)
	var sph := MeshKit.sphere(1)
	MeshKit.put(g, sph, c, Vector3(0, 2, 0), Vector3.ZERO, Vector3(2.2, 2.1, 1.9))
	MeshKit.put(g, sph, c, Vector3(0, 5, 0.2), Vector3.ZERO, Vector3.ONE * 1.75)
	for ex in [-0.7, 0.7]:
		MeshKit.put(g, sph, c, Vector3(ex, 7.4, 0), Vector3(0, 0, ex * -0.25), Vector3(0.55, 1.7, 0.45), false)
		MeshKit.put(g, sph, pink, Vector3(ex, 7.4, 0.3), Vector3(0, 0, ex * -0.25), Vector3(0.3, 1.2, 0.2), false)
		MeshKit.put(g, sph, eye, Vector3(ex * 0.85, 5.3, 1.6), Vector3.ZERO, Vector3.ONE * 0.2, false)


# ---------- geometry (three.js Torus/Circle/Shape/Tube/Extrude stand-ins) ----------

static func _commit(pts: Array, nrms: Array, uvs: Array, tris: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(0, tris.size(), 3):
		MeshKit._tri(st, pts, nrms, uvs, tris[i], tris[i + 1], tris[i + 2])
	return st.commit()

static func _grid_tris(rows: int, cols: int) -> Array:
	# quads of a (rows + 1) x (cols + 1) vertex grid, row-major
	var tris := []
	for j in rows:
		for i in cols:
			var a := j * (cols + 1) + i
			tris.append_array([a, a + 1, a + cols + 2, a, a + cols + 2, a + cols + 1])
	return tris

## THREE.TorusGeometry(radius, tube, radial, tubular, arc): in the XY plane, the arc from +x round through +y.
static func _torus_xy(radius: float, tube: float, radial: int, tubular: int, arc: float) -> ArrayMesh:
	var pts := []
	var nrms := []
	var uvs := []
	for j in radial + 1:
		var v := TAU * j / radial
		for i in tubular + 1:
			var u := arc * i / tubular
			var n := Vector3(cos(v) * cos(u), cos(v) * sin(u), sin(v))
			pts.append(Vector3(cos(u), sin(u), 0) * radius + n * tube)
			nrms.append(n)
			uvs.append(Vector2(float(i) / tubular, float(j) / radial))
	return _commit(pts, nrms, uvs, _grid_tris(radial, tubular))

## THREE.CircleGeometry facing +z, its texture upright.
static func _disc_xy(r: float, segs: int) -> ArrayMesh:
	var pts := [Vector3.ZERO]
	var nrms := [Vector3.BACK]
	var uvs := [Vector2(0.5, 0.5)]
	var tris := []
	for k in segs + 1:
		var a := TAU * k / segs
		pts.append(Vector3(cos(a), sin(a), 0) * r)
		nrms.append(Vector3.BACK)
		uvs.append(Vector2(0.5 + cos(a) * 0.5, 0.5 - sin(a) * 0.5))
		if k:
			tris.append_array([0, k, k + 1])
	return _commit(pts, nrms, uvs, tris)

static func _tri_xy(a: Vector2, b: Vector2, c: Vector2) -> ArrayMesh:
	var n := [Vector3.BACK, Vector3.BACK, Vector3.BACK]
	return _commit([Vector3(a.x, a.y, 0), Vector3(b.x, b.y, 0), Vector3(c.x, c.y, 0)], n, [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], [0, 1, 2])

## THREE.CatmullRomCurve3(points).getPoint(t) (uniform; the curves here have evenly spaced points).
static func _catmull(pts: Array, t: float) -> Vector3:
	var n := pts.size()
	var p := (n - 1) * t
	var i := int(floor(p))
	var w := p - i
	if i >= n - 1:
		i = n - 2; w = 1.0
	var p1: Vector3 = pts[i]
	var p2: Vector3 = pts[i + 1]
	var p0: Vector3 = pts[i - 1] if i > 0 else p1 * 2 - p2
	var p3: Vector3 = pts[i + 2] if i + 2 < n else p2 * 2 - p1
	return 0.5 * (2 * p1 + (p2 - p0) * w + (2 * p0 - 5 * p1 + 4 * p2 - p3) * w * w + (3 * p1 - p0 - 3 * p2 + p3) * w * w * w)

## THREE.TubeGeometry along a Catmull-Rom curve through pts (curves in an XY plane).
static func _tube(pts: Array, segs: int, r: float, radial: int) -> ArrayMesh:
	var cs := []
	for k in segs + 1:
		cs.append(_catmull(pts, float(k) / segs))
	var vp := []
	var nrms := []
	var uvs := []
	for k in segs + 1:
		var tg: Vector3 = (cs[mini(k + 1, segs)] - cs[maxi(k - 1, 0)]).normalized()
		var nn := tg.cross(Vector3.BACK).normalized()
		var bb := nn.cross(tg).normalized()
		for j in radial + 1:
			var v := TAU * j / radial
			var d := nn * cos(v) + bb * sin(v)
			vp.append(cs[k] + d * r)
			nrms.append(d)
			uvs.append(Vector2(float(j) / radial, float(k) / segs))
	return _commit(vp, nrms, uvs, _grid_tris(segs, radial))

## starGeo(r1, r2, d): a bevelled, puffy five-point star facing +z, centred.
static func _star_mesh(r1: float, r2: float, d: float) -> ArrayMesh:
	var bt := d * 0.4
	var bs := d * 0.35
	var hz := d / 2 + bt
	var outline := []
	for k in 10:
		var a := PI / 2 + k * PI / 5
		outline.append(Vector2(cos(a), sin(a)) * (r2 if k % 2 else r1))
	var rings := [[1.0, hz], [0.0, d / 2], [0.0, -d / 2], [1.0, -hz]]   # [shrink to outline, z]
	var pts := []
	var nrms := []
	var uvs := []
	for rg in rings:
		for o in outline:
			var o2: Vector2 = o
			var q: Vector2 = o2 if rg[0] > 0.5 else o2 * (o2.length() + bs) / o2.length()
			var p := Vector3(q.x, q.y, rg[1])
			pts.append(p)
			nrms.append(Vector3(p.x, p.y, p.z * 5).normalized())
			uvs.append(Vector2.ZERO)
	var tris := []
	for rr in 3:
		for k in 10:
			var a := rr * 10 + k
			var b := rr * 10 + (k + 1) % 10
			tris.append_array([a, b, b + 10, a, b + 10, a + 10])
	for cap in [[0, hz], [30, -hz]]:
		var c := pts.size()
		pts.append(Vector3(0, 0, cap[1])); nrms.append(Vector3(0, 0, signf(cap[1]))); uvs.append(Vector2.ZERO)
		for k in 10:
			tris.append_array([c, cap[0] + k, cap[0] + (k + 1) % 10])
	return _commit(pts, nrms, uvs, tris)


# ---------- painted textures (index.html wallTex, skyTex, rugTex, stripeTex) ----------

static func _cloud_shape(c: Control, cx: float, cy: float, s: float, col: Color, blobs: Array) -> void:
	for b in blobs:
		TexBaker.circle(c, Vector2(cx + b[0] * s, cy + b[1] * s), b[2] * s, col)

## wallTex: vertical gradient, a pattern of soft clouds or stars, a white wainscot band (20% of the height).
static func _wall_painter(top: Color, bottom: Color, pat: String, pat_col: Color, seed_: int) -> Callable:
	return func(c: Control):
		var w := c.size.x
		var h := c.size.y
		for k in 64:
			c.draw_rect(Rect2(0, h * k / 64.0, w, h / 64.0 + 1), top.lerp(bottom, (k + 0.5) / 64.0))
		var wains := 0.2
		if pat == "clouds":
			var rr := RandomNumberGenerator.new(); rr.seed = seed_
			for k in 9:
				var cx := rr.randf_range(0, w)
				var cy := rr.randf_range(20, h * 0.62)
				var s := rr.randf_range(18, 34)
				_cloud_shape(c, cx, cy, s, pat_col, [[0, 0, 1], [-1.1, 0.25, 0.7], [1.1, 0.25, 0.75], [-0.45, -0.35, 0.8], [0.5, -0.3, 0.7]])
				c.draw_rect(Rect2(cx - 1.8 * s, cy + 0.1 * s, 3.6 * s, 0.62 * s), pat_col)
		else:
			var y := 26.0
			var row := 0
			while y < h * (1 - wains) - 10:
				var x := (row % 2) * 32 + 18.0
				while x < w:
					c.draw_colored_polygon(TexBaker.star_points(Vector2(x, y), 7), pat_col)
					x += 64
				y += 46; row += 1
		var y0 := h * (1 - wains)
		c.draw_rect(Rect2(0, y0, w, h - y0), Color.WHITE)
		var x := 10.0
		while x < w:
			c.draw_rect(Rect2(x, y0 + 14, 60, h - y0 - 30), Color(140 / 255.0, 90 / 255.0, 110 / 255.0, 0.14), false, 3.0)
			x += 80
		c.draw_rect(Rect2(0, y0 - 6, w, 8), Color(1, 1, 1, 0.9))

## skyTex({stops: #7cc4ff -> #e6f6ff, clouds: 8}) for the portholes.
static func _paint_sky(c: Control) -> void:
	var w := c.size.x
	var h := c.size.y
	for k in 64:
		c.draw_rect(Rect2(0, h * k / 64.0, w, h / 64.0 + 1), Color("#7cc4ff").lerp(Color("#e6f6ff"), (k + 0.5) / 64.0))
	var rr := RandomNumberGenerator.new(); rr.seed = 8
	for k in 8:
		_cloud_shape(c, rr.randf_range(-20, w + 20), rr.randf_range(h * 0.2, h * 0.75), rr.randf_range(22, 44), Color(1, 1, 1, 0.92), [[0, 0, 1], [-1.1, 0.3, 0.7], [1.1, 0.3, 0.75], [-0.5, -0.35, 0.8], [0.5, -0.3, 0.7]])

## rugTex({base, rings | tiles}) plus fluffy fibres.
static func _rug_painter(base: Color, rings: Array, tiles: Array) -> Callable:
	return func(c: Control):
		var w := c.size.x
		c.draw_rect(Rect2(Vector2.ZERO, c.size), base)
		for k in rings.size():
			TexBaker.ring(c, c.size / 2, w / 2 - 20 - k * 30, 14, rings[k])
		if tiles.size():
			var s := w / 4
			for y in 4:
				for x in 4:
					c.draw_rect(Rect2(x * s + 3, y * s + 3, s - 6, s - 6), tiles[(x + y * 3) % tiles.size()])
					var half := PackedVector2Array()
					for k in 17:
						var a := PI * k / 16.0
						half.append(Vector2(x * s + s / 2 + cos(a) * 14, y * s + 4 + sin(a) * 14))
					c.draw_colored_polygon(half, Color(1, 1, 1, 0.35))
		var rr := RandomNumberGenerator.new(); rr.seed = 9
		for k in 2000:
			c.draw_rect(Rect2(rr.randf_range(0, w), rr.randf_range(0, w), 2, 2), Color(1, 1, 1, rr.randf_range(0, 0.08)))

## stripeTex(cols, vertical, n)
static func _stripe_painter(cols: Array, n: int) -> Callable:
	return func(c: Control):
		var s := c.size.x / n
		for k in n:
			c.draw_rect(Rect2(k * s, 0, s + 1, c.size.y), cols[k % cols.size()])
