class_name PawnSkins
extends RefCounted
## The 3D looks of the pawn skins (Catalog.PAWNS), shared by the Ludo board, the Snakes & Ladders board, the Shop's
## pictures (PawnStage) and the bake tool. Every skin keeps the seat colour as the pawn's main colour:
##   classic  the board's pawn: the LudoBoard.PAWN_PROFILE lathe and the 0.19 head sphere at y 0.74
##   trim     classic, with gold bands at the foot, the waist and the collar and a gold bead on the head
##   marble   classic in a marble of the seat colour (soft white veins baked into a small texture per colour)
##   glitter  classic in sparkles over the seat colour (a speck texture per colour, a little metallic; on medium and
##            high tiers the specks drift slowly round the pawn, see animate())
## (The textures are made once per finish and colour, at most 96 x 96, in a few milliseconds.)
##   kitty    classic, with two cat ears (pink inside) on the head
##   teacup   a cup on its saucer with a handle, frothy on top in a light tint of the seat colour (no head)
##   crown    classic, with a small gold crown on the head and a gem of the seat colour on its band
##   knight   a chess knight: a lower turned base and a horse's head (an extruded profile) with dark eyes
## Cheap by design (low-end Mali / MediaTek phones): StandardMaterial3D only, no shader of its own, the same material
## features as LudoBoard.pawn_material (clearcoat + emission), so a skin adds no shader variant except the finishes'
## albedo texture, which the boards keep drawn (hidden in their frames) so the splash / warm-up compiles it. A skin's
## extra parts are merged into one mesh per material: a pawn is at most four draw calls; the meshes are built once
## per skin and shared.
##
##   var d := PawnSkins.dress(node, "crown", Palette.PLAYER[0])
##   d = {body: Node3D (the board stretches it in 3D View), head: Node3D (at HEAD_Y, raised with the stretch),
##        mat: the seat-colour material (glow / dim), base: its albedo at rest, accents: [{mat, base}] (dim with it),
##        top: the skin's height (classic 0.93)}
##   PawnSkins.face(node, board, camera)    turn a pawn so its front (+z) looks at the camera (the knight's profile,
##                                          the ears, the handle read the same from every seat)

const HEAD_Y := 0.74
const HEAD_R := 0.19
const CLASSIC_TOP := 0.93
const GOLD := Color("#f4c542")
const EAR := Color("#ffb3c4")
const INK := Color("#2b1a24")
## The knight's horse head, facing +x, in pawn units (y up from the board): the profile that is extruded THICK deep.
const KNIGHT := [[.14, .44], [.165, .53], [.11, .62], [.135, .665], [.2, .672], [.275, .685], [.3, .725], [.28, .785],
	[.18, .865], [.085, .945], [.06, 1.0], [.02, 1.08], [-.03, .995], [-.075, .955], [-.125, .885], [-.185, .77],
	[-.205, .63], [-.195, .51], [-.165, .44]]
const KNIGHT_BASE := [[0, 0], [.37, 0], [.38, .05], [.33, .09], [.3, .12], [.3, .16], [.24, .2], [.2, .28], [.2, .36],
	[.25, .4], [.25, .45], [.18, .47], [0, .47]]
const KNIGHT_THICK := 0.2
## The teacup: saucer and cup in one lathe (outside up to the rim, the inside down to the froth).
const CUP := [[0, 0], [.39, 0], [.41, .02], [.4, .045], [.3, .06], [.18, .07], [.16, .09], [.17, .14], [.22, .26],
	[.27, .4], [.3, .52], [.315, .6], [.322, .63], [.305, .648], [.287, .632], [.276, .58]]
const FROTH := [[.278, .575], [.24, .594], [.14, .604], [0, .607]]
const TWINKLE := 0.035                  ## glitter: the specks drift round the pawn this many turns a second

static var _meshes := {}                # skin id -> {body: Mesh, head: Mesh, accents: [{mesh, key, part}], top, finish}
static var _tex := {}                   # "marble|<colour>" -> ImageTexture


# =====================================================================================================================
# Dressing a pawn
# =====================================================================================================================

## Builds skin `id` (unknown: Classic) in `color` under `g`: a Body and a Head node with their meshes. See the header
## for what it returns. Every material is the pawn's own (each pawn glows and dims on its own).
static func dress(g: Node3D, id: String, color: Color) -> Dictionary:
	var sk := meshes(id)
	var m := material(id, color)
	var body := Node3D.new()
	body.name = "Body"
	g.add_child(body)
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, HEAD_Y, 0)
	g.add_child(head)
	MeshKit.put(body, sk.body, m, Vector3.ZERO)
	if sk.head:
		MeshKit.put(head, sk.head, m, Vector3.ZERO)
	var accents := []
	for a: Dictionary in sk.accents:
		var col := accent_color(str(a.key), color)
		var am := accent_material(str(a.key), col)
		MeshKit.put(head if a.part == "head" else body, a.mesh, am, Vector3.ZERO)
		accents.append({mat = am, base = col})
	return {body = body, head = head, mat = m, base = m.albedo_color, accents = accents, top = float(sk.top)}

## Removes what dress() built (before dressing the pawn again in another skin).
static func undress(d: Dictionary) -> void:
	for k in ["body", "head"]:
		var n: Variant = d.get(k)
		if n is Node and is_instance_valid(n):
			(n as Node).get_parent().remove_child(n)
			(n as Node).queue_free()

## The seat-colour material of a skin: LudoBoard.pawn_material, with the finish (a texture of the colour) for marble
## and glitter. Its albedo_color is what dims (white for the textured finishes: the texture holds the colour).
static func material(id: String, color: Color) -> StandardMaterial3D:
	var m := LudoBoard.pawn_material(color)
	match finish(id):
		"marble":
			m.albedo_color = Color.WHITE
			m.albedo_texture = texture("marble", color)
			m.roughness = 0.18
		"glitter":
			m.albedo_color = Color.WHITE
			m.albedo_texture = texture("glitter", color)
			m.metallic = 0.3
			m.roughness = 0.2
			m.set_meta("twinkle", randf())
	return m

## An accent part's material (the gold, the inside of the ears, the froth, the knight's eyes): the pawn material's
## features (no new shader variant), gold made metallic.
static func accent_material(key: String, color: Color) -> StandardMaterial3D:
	var m := LudoBoard.pawn_material(color)
	match key:
		"gold":
			m.metallic = 0.75
			m.roughness = 0.3
			m.clearcoat = 0.4
		"ink":
			m.roughness = 0.35
		"froth":                                    # soft and matte: no glare off the cup's top in Top View
			m.roughness = 0.8
			m.metallic_specular = 0.2
			m.clearcoat = 0.0
		_:
			m.roughness = 0.4
			m.clearcoat = 0.3
	return m

static func accent_color(key: String, color: Color) -> Color:
	match key:
		"gold": return GOLD
		"ear": return EAR
		"ink": return INK
		"froth": return froth(color)
	return color

## The teacup's froth: a light tint of the seat colour, still clearly that colour from straight above (Top View).
static func froth(color: Color) -> Color:
	return color.lerp(Color.WHITE, 0.32)

## "marble" | "glitter" | "" (the skin's surface).
static func finish(id: String) -> String:
	return id if id == "marble" or id == "glitter" else ""

## Turns pawn node `g` (a child of `board`) about the vertical so its front (+z) looks at the camera: the skins with a
## front (the knight's profile, the ears, the handle, the crown's gem) read the same from every seat. Top View looks
## straight down: the front is the bottom of the screen then.
static func face(g: Node3D, board: Node3D, cam: Camera3D) -> void:
	if cam == null:
		return
	var b := cam.global_transform.basis
	var to_cam := Vector3(b.z.x, 0, b.z.z)
	if to_cam.length() < 0.25:
		to_cam = -Vector3(b.y.x, 0, b.y.z)
	if to_cam.length() < 0.0001:
		return
	var local := board.global_transform.basis.inverse() * to_cam
	g.rotation.y = atan2(local.x, local.z)

## Glitter: the specks drift slowly round the pawn (medium / high tiers, not with Reduce motion). Call per frame.
static func animate(m: StandardMaterial3D, now: float, still: bool) -> void:
	if m.has_meta("twinkle") and not still:
		m.uv1_offset.x = fposmod(now * TWINKLE + float(m.get_meta("twinkle")), 1.0)

## True when the glitter drift should run (Quality extras on, Reduce motion off): the boards pass `not moving()`.
static func moving(reduce_motion: bool) -> bool:
	return not reduce_motion and Quality.extras()


# =====================================================================================================================
# Meshes (built once per skin, shared by every pawn wearing it)
# =====================================================================================================================

static func meshes(id: String) -> Dictionary:
	if Catalog.pawn(id).is_empty():
		id = Catalog.FREE_PAWN
	if _meshes.has(id):
		return _meshes[id]
	var body: Mesh = MeshKit.lathe(_pts(LudoBoard.PAWN_PROFILE), 36)
	var head: Mesh = MeshKit.sphere(HEAD_R, 28, 18)
	var accents := []
	var top := CLASSIC_TOP
	match id:
		"trim":
			accents.append({key = "gold", part = "body", mesh = _merge([
				[MeshKit.torus(0.376, 0.03, 40, 8), Transform3D(Basis(), Vector3(0, 0.032, 0))],
				[MeshKit.torus(0.172, 0.024, 28, 8), Transform3D(Basis(), Vector3(0, 0.3, 0))],
				[MeshKit.torus(0.246, 0.033, 32, 8), Transform3D(Basis(), Vector3(0, 0.535, 0))]])})
			accents.append({key = "gold", part = "head", mesh = _merge([
				[MeshKit.sphere(0.055, 12, 8), Transform3D(Basis(), Vector3(0, HEAD_R + 0.02, 0))]])})
			top = CLASSIC_TOP + 0.07
		"kitty":
			var parts := [[head, Transform3D()]]
			var inner := []
			for sx in [-1.0, 1.0]:
				var tilt := Basis(Vector3.BACK, -sx * deg_to_rad(38.0))     # the ear's axis, tipped out to its side
				var dir: Vector3 = tilt * Vector3.UP
				var flat := Basis.from_scale(Vector3(1, 1, 0.55))
				parts.append([MeshKit.cylinder(0.0, 0.112, 0.21, 12), Transform3D(tilt * flat, dir * 0.25)])
				inner.append([MeshKit.cylinder(0.0, 0.07, 0.15, 10), Transform3D(tilt * flat, dir * 0.245 + Vector3(0, 0, 0.036))])
			head = _merge(parts)
			accents.append({key = "ear", part = "head", mesh = _merge(inner)})
			top = HEAD_Y + 0.29
		"teacup":
			body = _merge([
				[MeshKit.lathe(_pts(CUP), 36), Transform3D()],
				[MeshKit.torus(0.095, 0.032, 24, 8), Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0.315, 0.37, 0))]])
			head = null
			accents.append({key = "froth", part = "body", mesh = MeshKit.lathe(_pts(FROTH), 36)})
			top = 0.65
		"crown":
			var pts := []
			for k in 5:
				var a := TAU * k / 5.0 + PI / 2.0
				var at := Vector3(cos(a) * 0.142, 0.222, sin(a) * 0.142)
				pts.append([MeshKit.cylinder(0.0, 0.042, 0.085, 8), Transform3D(Basis(), at)])
				pts.append([MeshKit.sphere(0.019, 8, 6), Transform3D(Basis(), at + Vector3(0, 0.05, 0))])
			pts.append([MeshKit.lathe(_pts([[.142, .112], [.158, .112], [.15, .186], [.134, .186], [.142, .112]]), 28), Transform3D()])
			accents.append({key = "gold", part = "head", mesh = _merge(pts)})
			head = _merge([[head, Transform3D()], [MeshKit.sphere(0.03, 10, 8), Transform3D(Basis(), Vector3(0, 0.15, 0.155))]])
			top = HEAD_Y + 0.29
		"knight":
			body = MeshKit.lathe(_pts(KNIGHT_BASE), 36)
			head = _extrude(_pts(KNIGHT), KNIGHT_THICK, -HEAD_Y)
			var eyes := []
			for sz in [-1.0, 1.0]:
				eyes.append([MeshKit.sphere(0.024, 8, 6), Transform3D(Basis.from_scale(Vector3(1, 1, 0.5)), Vector3(0.105, 0.86 - HEAD_Y, sz * KNIGHT_THICK / 2.0))])
			accents.append({key = "ink", part = "head", mesh = _merge(eyes)})
			top = 1.08
	var out := {body = body, head = head, accents = accents, top = top, finish = finish(id)}
	_meshes[id] = out
	return out

static func _pts(a: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in a:
		out.append(Vector2(p[0], p[1]))
	return out

## One mesh from several: [[mesh, transform], ...] (surface 0 of each). Every part is de-indexed first (the lathes
## have no index array, the primitive meshes do: SurfaceTool can't mix the two), then the whole is indexed again so
## shared vertices are stored once.
static func _merge(parts: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	for p: Array in parts:
		var one := SurfaceTool.new()
		one.create_from(p[0], 0)
		one.deindex()
		st.append_from(one.commit(), 0, p[1])
	st.index()
	return st.commit()

## A flat profile (x, y) extruded `depth` deep along z (centred), lifted by `lift`: its two faces (triangulated) and
## its side walls (flat-shaded, normals out).
static func _extrude(poly: PackedVector2Array, depth: float, lift: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tris := Geometry2D.triangulate_polygon(poly)
	var hz := depth / 2.0
	var ccw := _area(poly) > 0.0
	for side in [1.0, -1.0]:
		var n := Vector3(0, 0, side)
		for k in range(0, tris.size(), 3):
			var v: Array[Vector3] = []
			for j in 3:
				var p := poly[tris[k + j]]
				v.append(Vector3(p.x, p.y + lift, side * hz))
			var flip := (v[2] - v[0]).cross(v[1] - v[0]).dot(n) < 0.0     # (Godot: clockwise front faces)
			for j: int in ([0, 2, 1] if flip else [0, 1, 2]):
				st.set_normal(n)
				st.set_uv(Vector2(v[j].x, v[j].y))
				st.add_vertex(v[j])
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var e := b - a
		var n := Vector3(e.y, -e.x, 0).normalized() * (1.0 if ccw else -1.0)
		var q := [Vector3(a.x, a.y + lift, hz), Vector3(b.x, b.y + lift, hz), Vector3(b.x, b.y + lift, -hz), Vector3(a.x, a.y + lift, -hz)]
		for tri: Array in [[0, 1, 2], [0, 2, 3]]:
			var p0: Vector3 = q[tri[0]]
			var p1: Vector3 = q[tri[1]]
			var p2: Vector3 = q[tri[2]]
			var flip := (p2 - p0).cross(p1 - p0).dot(n) < 0.0
			for j: int in ([tri[0], tri[2], tri[1]] if flip else tri):
				st.set_normal(n)
				st.set_uv(Vector2(float(i) / poly.size(), (q[j] as Vector3).y))
				st.add_vertex(q[j])
	return st.commit()

static func _area(poly: PackedVector2Array) -> float:
	var s := 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		s += a.x * b.y - b.x * a.y
	return s / 2.0


# =====================================================================================================================
# Finish textures (one small texture per finish and colour, made once and kept)
# =====================================================================================================================

## The marble / glitter surface in `color` (seamless round the pawn, mipmapped): marble 64 x 64 (soft veins over a
## faint cloud), glitter 96 x 96 (single-pixel specks: a few white or pale gold, more in a light tint, the rest the
## colour a shade deeper so the specks stand out).
static func texture(kind: String, color: Color) -> ImageTexture:
	var key := "%s|%s" % [kind, color.to_html()]
	if _tex.has(key):
		return _tex[key]
	var n := 64 if kind == "marble" else 96
	var lum := PackedByteArray()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	if kind == "marble":
		var noise := FastNoiseLite.new()
		noise.seed = 7
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = 0.045
		noise.fractal_octaves = 4
		var src := noise.get_seamless_image(n, n)      # tiles in both directions
		src.convert(Image.FORMAT_L8)
		lum = src.get_data()
	var data := PackedByteArray()
	data.resize(n * n * 4)
	var vein := color.lerp(Color.WHITE, 0.88)
	var deep := color.darkened(0.14)
	var spark := color.lerp(Color.WHITE, 0.9)
	var gold := color.lerp(Color("#fff1b8"), 0.9)
	var tint := color.lerp(Color.WHITE, 0.4)
	var under := color.darkened(0.04)
	for y in n:
		for x in n:
			var c: Color
			if kind == "marble":
				# veins: where a wave across the surface (bent by the noise) crosses zero; a soft cloud between
				var v := lum[y * n + x] / 255.0
				var w := absf(sin((float(x) / n * 2.0 + float(y) / n) * TAU + v * 7.0))
				var k := pow(1.0 - w, 7.0)
				c = color.lerp(deep, (1.0 - v) * 0.45).lerp(vein, minf(1.0, k * 1.1))
			else:
				var r := rng.randf()                    # per pixel: any tiling of it is seamless
				c = (gold if r > 0.975 else spark) if r > 0.93 else (tint if r > 0.84 else under)
			var i := (y * n + x) * 4
			data[i] = c.r8
			data[i + 1] = c.g8
			data[i + 2] = c.b8
			data[i + 3] = 255
	var img := Image.create_from_data(n, n, false, Image.FORMAT_RGBA8, data)
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_tex[key] = t
	return t

## A small hidden mesh in a finish material, for a board to keep drawn inside its frame: the warm-up and the
## splash's reveal then compile the textured pawn shader before any match shows a marble or glitter pawn.
static func warm_swatch(parent: Node3D, at: Vector3) -> MeshInstance3D:
	var mi := MeshKit.put(parent, MeshKit.sphere(0.05, 8, 6), material("marble", Palette.PLAYER[0]), at, Vector3.ZERO, Vector3.ONE, false)
	mi.name = "FinishWarm"
	return mi
