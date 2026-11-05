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
## The themed skins (a body and a head of their own; web PR "Skin", Hasan's reference sheet):
##   candy    a candy-striped bell, a frosted cupcake head with sprinkles
##   fruity   a bell with juice drips, a fruit for a head by seat: strawberry, watermelon slice, orange, blueberry
##   blossom  a bell wrapped in a vine, a big flower for a head
##   ice      a faceted crystal column and gem head, crystals on top and round the foot
##   pirate   a bell with belt and bandana, an eye patch and a tricorn with a skull and gold trim
##   robo     a robot in the seat colour with a white head: dark visor, glowing eyes, chest light, ears, antenna
##   wizard   a robe with a scarf, a big floppy hat and gold stars
##   space    a space suit in the seat colour, a big white helmet with a visor in a dark shade of that colour
## (The web's Robo and Space have white suits; here the seat colour stays the main colour, so pawns on the track can
## always be told apart: see Catalog.PAWNS.)
##   dragon   a scaly bell, gold horns, a crest, bat wings and a gem on the chest
## Their many small colours share one colour table per seat (a 32 x 32 texture, palette()): every accent mesh points its
## UVs at the table's cells, so a themed pawn stays at four draw calls (seat colour body + head, accents body + head)
## and uses the finishes' textured shader. The ones with a face tip their head back in Top View (pose()).
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
##   PawnSkins.pose(d, k, stretch)          place the head: raised with the board's stretch, tipped back by d.look x k
##                                          (k: 0 in 3D View .. 1 in Top View) so a face looks up at the camera

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
## The themed skins' bodies (radius, height): a bell, a robe, a suit on a foot, a crystal column.
const BELL := [[0, 0], [.37, 0], [.38, .04], [.355, .09], [.31, .16], [.26, .27], [.215, .4], [.18, .52], [.16, .6], [.12, .66], [0, .68]]
const ROBE := [[0, 0], [.37, 0], [.38, .04], [.365, .09], [.33, .19], [.28, .33], [.225, .47], [.175, .58], [.13, .65], [0, .67]]
const FOOT := [[0, 0], [.36, 0], [.38, .03], [.38, .08], [.35, .12], [0, .12]]
const SUIT := [[0, .1], [.3, .1], [.3, .3], [.285, .42], [.245, .52], [.18, .59], [.09, .625], [0, .63]]
const COLUMN := [[0, 0], [.33, 0], [.34, .05], [.29, .12], [.235, .3], [.2, .46], [.23, .55], [.15, .64], [0, .66]]
const BELL_HEAD_Y := 0.79               ## the head's centre on a bell
## Top View: how far a skin's head tips back (radians) and the height it turns about.
const LOOK := {robo = [1.3, .82], space = [1.3, .82], pirate = [1.0, .79], blossom = [1.0, .83], fruity = [.9, .8], wizard = [.8, .76], dragon = [.8, .79]}
## The textures of the themed bodies: where a mesh's v (its height) is above SOLID_V they are the plain seat colour,
## so a head in the same material can point at SOLID_UV.
const SOLID_V := 0.72
const SOLID_UV := Vector2(0.5, 0.86)
## The fruit on a fruity pawn, by seat (red, green, yellow, blue).
const FRUIT := ["strawberry", "melon", "orange", "blueberry"]
const THEMED := ["candy", "fruity", "blossom", "ice", "pirate", "robo", "wizard", "space", "dragon"]
const PALETTE_CELLS := 8                ## the colour table: 8 x 8 cells of 4 x 4 pixels
## The table's fixed colours (the seat-dependent ones: _palette_colors).
const INKS := {gold = "#f4bd3c", white = "#f7f4ee", dark = "#24202b", leaf = "#55b046", stem = "#7a4a21", cream = "#fff4e6",
	felt = "#2b2530", belt = "#5b3a22", flesh = "#ff4b5c", rind = "#2e8b3e", seed = "#2b1b1b", dot = "#ffe38a", navy = "#4a5fc4",
	orange = "#ff9a1f", pink = "#ff6fa8", sky = "#5ac8fa", lemon = "#ffd23f", lime = "#7ed957", tang = "#ff8a3d", violet = "#b38bff"}

static var _meshes := {}                # skin id -> {body: Mesh, head: Mesh, accents: [{mesh, key, part}], top, finish}
static var _tex := {}                   # "marble|<colour>" -> ImageTexture
static var _solids := {}                # "octa|<radius>" -> ArrayMesh


# =====================================================================================================================
# Dressing a pawn
# =====================================================================================================================

## Builds skin `id` (unknown: Classic) in `color` under `g`: a Body and a Head node with their meshes. See the header
## for what it returns. Every material is the pawn's own (each pawn glows and dims on its own).
static func dress(g: Node3D, id: String, color: Color) -> Dictionary:
	var sk := meshes(id, color)
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
		var am := accent_material(str(a.key), col, color)
		MeshKit.put(head if a.part == "head" else body, a.mesh, am, Vector3.ZERO)
		accents.append({mat = am, base = col})
	var look: Array = LOOK.get(Catalog.pawn(id).get("id", ""), [0.0, HEAD_Y])
	return {body = body, head = head, mat = m, base = m.albedo_color, accents = accents, top = float(sk.top), look = float(look[0]), pivot = float(look[1])}

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
		"stripes", "scales", "vine":
			m.albedo_color = Color.WHITE
			m.albedo_texture = texture(finish(id), color)
	if id == "ice":                              # clear crystal: paler than the seat colour, very glossy
		m.albedo_color = color.lerp(Color.WHITE, 0.12)
		m.roughness = 0.08
	return m

## An accent part's material (the gold, the inside of the ears, the froth, the knight's eyes): the pawn material's
## features (no new shader variant), gold made metallic.
static func accent_material(key: String, color: Color, seat := Color.WHITE) -> StandardMaterial3D:
	var m := LudoBoard.pawn_material(color)
	match key:
		"palette":                               # the colour table: the finishes' textured shader, a soft gloss
			m.albedo_texture = palette(seat)
			m.roughness = 0.3
			m.clearcoat = 0.7
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
		"palette": return Color.WHITE
		"gold": return GOLD
		"ear": return EAR
		"ink": return INK
		"froth": return froth(color)
	return color

## The teacup's froth: a light tint of the seat colour, still clearly that colour from straight above (Top View).
static func froth(color: Color) -> Color:
	return color.lerp(Color.WHITE, 0.32)

## "marble" | "glitter" | "stripes" | "scales" | "vine" | "" (the skin's surface).
static func finish(id: String) -> String:
	match id:
		"marble", "glitter": return id
		"candy": return "stripes"
		"dragon": return "scales"
		"blossom": return "vine"
	return ""

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

## Places a dressed pawn's head (d: what dress() returned): at HEAD_Y x `stretch` (the board's 3D View makes the body
## taller), tipped back by the skin's look angle x k about its turning height, so a face reads from straight above.
## k: 0 in 3D View (unchanged) .. 1 in Top View. Skins without a look just follow the stretch.
static func pose(d: Dictionary, k: float, stretch := 1.0) -> void:
	var head: Node3D = d.head
	var look := float(d.get("look", 0.0))
	var y := HEAD_Y * stretch
	if look <= 0.0:
		head.position.y = y
		return
	var a := -look * k
	var dy := float(d.pivot) - HEAD_Y
	head.rotation.x = a
	head.position = Vector3(0, y + dy * (1.0 - cos(a)), -dy * sin(a))

## How far camera `cam` is from the game view (0) towards looking straight down (1): pose()'s k on a board that has
## no TableWorld to ask (the S&L scenes).
static func top_k(cam: Camera3D) -> float:
	if cam == null:
		return 0.0
	var el := asin(clampf(cam.global_transform.basis.z.y, -1.0, 1.0))
	return clampf((el - TableWorld.GAME_EL) / (TableWorld.TOP_EL - TableWorld.GAME_EL), 0.0, 1.0)

## True when the glitter drift should run (Quality extras on, Reduce motion off): the boards pass `not moving()`.
static func moving(reduce_motion: bool) -> bool:
	return not reduce_motion and Quality.extras()


# =====================================================================================================================
# Meshes (built once per skin, shared by every pawn wearing it)
# =====================================================================================================================

## `seat`: only the fruity skin's head differs by seat colour (its own key); the others are one set of meshes for all.
static func meshes(id: String, seat := Color.WHITE) -> Dictionary:
	if Catalog.pawn(id).is_empty():
		id = Catalog.FREE_PAWN
	var cache_key := id
	if id == "fruity":
		cache_key = "fruity|" + FRUIT[maxi(Palette.PLAYER.find(seat), 0)]
	if _meshes.has(cache_key):
		return _meshes[cache_key]
	if id in THEMED:
		_meshes[cache_key] = _themed(id, maxi(Palette.PLAYER.find(seat), 0))
		return _meshes[cache_key]
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
# The themed skins (a body and head of their own, many small colours from the colour table)
# =====================================================================================================================

## A themed skin's meshes: seat-colour body + head, then the accents on body and head, all from the colour table.
## Parts are [mesh, transform, cell]; all in pawn units (y up from the board), the head's moved to its node's origin.
static func _themed(id: String, seat: int) -> Dictionary:
	var f: Dictionary = _skin_candy() if id == "candy" else _skin_fruity(seat) if id == "fruity" else _skin_blossom() if id == "blossom" \
		else _skin_ice() if id == "ice" else _skin_pirate() if id == "pirate" else _skin_robo() if id == "robo" \
		else _skin_wizard() if id == "wizard" else _skin_space() if id == "space" else _skin_dragon()
	var lift := Transform3D(Basis(), Vector3(0, -HEAD_Y, 0))
	var body: Mesh = _bake(f.body)
	var head: Mesh = _bake(f.head, lift) if not (f.head as Array).is_empty() else null
	var accents := []
	var top := body.get_aabb().end.y
	if head:
		top = maxf(top, head.get_aabb().end.y + HEAD_Y)
	if not (f.body_acc as Array).is_empty():
		var m := _bake(f.body_acc)
		accents.append({key = "palette", part = "body", mesh = m})
		top = maxf(top, m.get_aabb().end.y)
	if not (f.head_acc as Array).is_empty():
		var m := _bake(f.head_acc, lift)
		accents.append({key = "palette", part = "head", mesh = m})
		top = maxf(top, m.get_aabb().end.y + HEAD_Y)
	return {body = body, head = head, accents = accents, top = top, finish = finish(id)}

static func _skin_candy() -> Dictionary:
	var y := BELL_HEAD_Y
	var acc := [[_patch(.212, 0.0, TAU, 0.0, 1.42, 20, 7), _at(Vector3(0, y, 0)), "cream"]]
	for k in 7:
		var a := TAU * k / 7.0
		acc.append([MeshKit.sphere(.03, 8, 5), _at(Vector3(sin(a) * .19, y - .012 - (k % 2) * .03, cos(a) * .19), Vector3(0, a, 0), Vector3(1.1, 1.7, .7)), "cream"])
	var r := RandomNumberGenerator.new()
	r.seed = 3
	var cols := ["pink", "sky", "lemon", "lime", "tang", "violet"]
	for k in 14:
		var th := .15 + r.randf() * .95
		var ph := r.randf() * TAU
		var n := Vector3(sin(th) * sin(ph), cos(th), sin(th) * cos(ph))
		acc.append([MeshKit.cylinder(.012, .012, .055, 5), _at(Vector3(n.x * .214, y + n.y * .214, n.z * .214), Vector3(th - PI / 2.0, ph, r.randf() * 3.0), 1.0, true), cols[k % cols.size()]])
	return {body = [[_lathe(BELL), Transform3D()]], head = [[MeshKit.sphere(.2, 22, 14), _at(Vector3(0, y, 0)), SOLID_UV]], body_acc = [], head_acc = acc}

static func _skin_fruity(seat: int) -> Dictionary:
	var y := .8
	var head := []
	var acc := []
	match FRUIT[seat]:
		"strawberry":
			var prof := [[0, -.2], [.07, -.18], [.14, -.11], [.195, -.01], [.205, .07], [.165, .14], [.08, .18], [0, .19]]
			head.append([MeshKit.lathe(_pts(prof), 24), _at(Vector3(0, y, 0))])
			var r := RandomNumberGenerator.new()
			r.seed = 11
			for k in 18:
				var dy := -.14 + (k % 4) * .065 + r.randf() * .02
				var a := k * 2.4
				var rr := _r_at(prof, dy) + .004
				acc.append([MeshKit.sphere(.015, 6, 3), _at(Vector3(sin(a) * rr, y + dy, cos(a) * rr), Vector3(0, a, 0), Vector3(1, 1.4, .6)), "dot"])
			for k in 6:
				var a := TAU * k / 6.0
				acc.append(_leaf(Vector3(sin(a) * .085, y + .175, cos(a) * .085), a, .3, 1.1))
			acc.append([MeshKit.cylinder(.015, .02, .07, 6), _at(Vector3(0, y + .21, 0)), "leaf"])
		"melon":
			var a0 := PI * 1.5 - .72
			var a1 := PI * 1.5 + .72
			var at := Vector3(0, y + .15, 0)
			acc.append([_extrude(_sector(.255, a0, a1), .12, 0.0), _at(at), "flesh"])
			acc.append([_extrude(_sector(.277, a0, a1, .255), .121, 0.0), _at(at), "white"])
			acc.append([_extrude(_sector(.3, a0, a1, .275), .124, 0.0), _at(at), "rind"])
			var r := RandomNumberGenerator.new()
			r.seed = 5
			for k in 7:
				var a := a0 + .18 + (k / 6.0) * (a1 - a0 - .36)
				var rr := .12 + (k % 2) * .07 + r.randf() * .02
				acc.append([MeshKit.sphere(.014, 6, 3), _at(Vector3(cos(a) * rr, at.y + sin(a) * rr, .066), Vector3(0, 0, a + PI / 2.0), Vector3(.8, 1.4, .5)), "seed"])
		"orange":
			acc.append([MeshKit.sphere(.2, 22, 14), _at(Vector3(0, y, 0), Vector3.ZERO, Vector3(1.05, .97, 1.05)), "orange"])
			acc.append([MeshKit.cylinder(.014, .018, .05, 6), _at(Vector3(0, y + .2, 0)), "stem"])
			acc.append(_leaf(Vector3(.06, y + .215, .02), PI / 2.0 - .3, .25, 1.25))
		_:
			head.append([MeshKit.sphere(.2, 22, 14), _at(Vector3(0, y, 0), Vector3.ZERO, Vector3(1.09, .96, 1.09))])
			for k in 5:
				var a := TAU * k / 5.0
				acc.append([MeshKit.cylinder(0.0, .03, .075, 6), _at(Vector3(sin(a) * .05, y + .19, cos(a) * .05), Vector3(.7, a, 0), 1.0, true), "navy"])
			acc.append([MeshKit.cylinder(.055, .055, .02, 12), _at(Vector3(0, y + .185, 0)), "navy"])
	var drips := [[MeshKit.lathe(_pts([[_r_at(BELL, .5) + .01, .5], [_r_at(BELL, .56) + .014, .56], [_r_at(BELL, .62) + .014, .62], [.13, .67], [0, .69]]), 32), Transform3D(), "shade18"]]
	for k in 9:
		var a := TAU * k / 9.0
		var dy := .47 - (k % 2) * .04
		var rr := _r_at(BELL, dy) + .004
		drips.append([MeshKit.sphere(.03, 8, 5), _at(Vector3(sin(a) * rr, dy, cos(a) * rr), Vector3(0, a, 0), Vector3(1, 1.7, .6)), "shade18"])
	return {body = [[_lathe(BELL), Transform3D()]], head = head, body_acc = drips, head_acc = acc}

## A leaf (a flattened ball) on the colour table's green.
static func _leaf(p: Vector3, ry: float, tilt: float, sc: float) -> Array:
	return [MeshKit.sphere(.07, 8, 4), _at(p, Vector3(tilt, ry, 0), Vector3(.5 * sc, .16 * sc, sc), true), "leaf"]

static func _skin_blossom() -> Dictionary:
	var m := _at(Vector3(0, .83, .03), Vector3(-.22, 0, 0))
	var acc := []
	for k in 5:
		var a := TAU * k / 5.0
		acc.append([MeshKit.sphere(.105, 14, 8), m * _at(Vector3(sin(a) * .14, cos(a) * .14, 0), Vector3(0, 0, -a), Vector3(.8, 1.05, .32)), "petal"])
	acc.append([MeshKit.sphere(.085, 14, 8), m * _at(Vector3(0, 0, .03), Vector3.ZERO, Vector3(1, 1, .6)), "mid"])
	acc.append([MeshKit.sphere(.13, 14, 6), m * _at(Vector3(0, 0, -.04), Vector3.ZERO, Vector3(1, 1, .35)), "leaf"])
	var leaves := [[MeshKit.cylinder(.05, .07, .14, 10), _at(Vector3(0, .66, 0)), "leaf"]]
	for sx in [-1.0, 1.0]:
		leaves.append([MeshKit.sphere(.08, 10, 5), _at(Vector3(sx * .2, .63, .03), Vector3(0, sx * -.3, sx * -.4), Vector3(1.4, .22, .6)), "leaf"])
	return {body = [[_lathe(BELL), Transform3D()]], head = [], body_acc = leaves, head_acc = acc}

static func _skin_ice() -> Dictionary:
	var acc := [[_octa(.07), _at(Vector3(0, 1.0, 0), Vector3.ZERO, Vector3(1, 2.1, 1)), "tint5"]]
	for k in 5:
		var a := TAU * k / 5.0
		acc.append([_octa(.045 if k % 2 else .055), _at(Vector3(sin(a) * .09, .96, cos(a) * .09), Vector3(.45, a, 0), Vector3(1, 1.9 if k % 2 else 2.3, 1), true), "tint5"])
	var foot := []
	for k in 12:
		var a := TAU * k / 12.0
		foot.append([_octa(.052 if k % 2 else .066), _at(Vector3(sin(a) * .27, .17, cos(a) * .27), Vector3(.5, a, 0), Vector3(1, 2.2 if k % 2 else 2.7, 1), true), "tint5"])
	return {body = [[_flat(MeshKit.lathe(_pts(COLUMN), 8)), Transform3D()]], head = [[_ico(.19), _at(Vector3(0, .78, 0), Vector3.ZERO, Vector3(1, 1.1, 1))]], body_acc = foot, head_acc = acc}

static func _skin_pirate() -> Dictionary:
	var y := BELL_HEAD_Y
	var dy := y - HEAD_Y
	var f := _at(Vector3(0, .84 + dy, .06), Vector3(-.3, 0, 0), Vector3(1.12, 1.1, 1))
	var flap := _crescent()
	var rim := PackedVector2Array()
	for p in flap:
		rim.append(Vector2(p.x * 1.05, .02 + (p.y - .02) * 1.12))
	var acc := [
		[_patch(.205, 0.0, TAU, 0.0, PI / 2.0, 18, 6), _at(Vector3(0, .84 + dy, -.01), Vector3.ZERO, Vector3(1, .7, 1)), "felt"],
		[MeshKit.cylinder(.26, .26, .026, 24), _at(Vector3(0, .852 + dy, -.01), Vector3.ZERO, Vector3(1.12, 1, .88)), "felt"],
		[MeshKit.torus(.204, .012, 24, 5), _ring_at(Vector3(0, .76 + dy, 0), Vector3(PI / 2.0 - .25, 0, .3)), "felt"],
		[MeshKit.sphere(.06, 10, 6), _at(Vector3(-.074, .775 + dy, .186), Vector3(-.15, -.4, 0), Vector3(1, .9, .35)), "felt"],
		[_extrude(flap, .03, 0.0), f * _at(Vector3(0, 0, .015)), "felt"],
		[_extrude(rim, .02, 0.0), f * _at(Vector3(0, 0, .012)), "gold"],
		[MeshKit.sphere(.048, 10, 6), f * _at(Vector3(0, .13, .036), Vector3.ZERO, Vector3(1, .95, .45)), "white"],
	]
	for sx in [-1.0, 1.0]:
		acc.append([MeshKit.cylinder(.012, .012, .13, 5), f * _at(Vector3(0, .115, .034), Vector3(0, 0, sx * .85)), "white"])
	var body_acc := [
		[MeshKit.cylinder(_r_at(BELL, .24) + .01, _r_at(BELL, .18) + .01, .06, 24), _at(Vector3(0, .21, 0)), "belt"],
		[MeshKit.torus(.03, .011, 8, 4), _on_surf(BELL, .21, 0.0, .018, -.35) * Transform3D(Basis(Vector3.RIGHT, PI / 2.0) * Basis.from_scale(Vector3(1.25, 1, 1)), Vector3.ZERO), "gold"],
		[MeshKit.torus(.15, .04, 20, 6), _at(Vector3(0, .64, 0)), "tint35"],
		[MeshKit.sphere(.03, 8, 5), _at(Vector3(0, .615, .175)), "tint35"],
	]
	for sx in [-1.0, 1.0]:
		body_acc.append([MeshKit.sphere(.045, 8, 5), _at(Vector3(sx * .045, .6, .17), Vector3(0, 0, sx * .5), Vector3(1.2, .8, .5)), "tint35"])
	return {body = [[_lathe(BELL), Transform3D()]], head = [[MeshKit.sphere(.2, 22, 14), _at(Vector3(0, y, 0))]], body_acc = body_acc, head_acc = acc}

## The tricorn's front flap: a crescent with pointed ends.
static func _crescent() -> PackedVector2Array:
	var out := PackedVector2Array()
	for c: Array in [[Vector2(-.29, .01), Vector2(-.22, .21), Vector2(0, .215)], [Vector2(0, .215), Vector2(.22, .21), Vector2(.29, .01)], [Vector2(.29, .01), Vector2(0, .09), Vector2(-.29, .01)]]:
		_bezier(out, c[0], c[1], c[2], 8)
	return out

static func _skin_robo() -> Dictionary:
	var y := .82
	var sc := Vector3(1.22, 1, 1.08)
	var body := [[_lathe(FOOT), Transform3D()], [_lathe(SUIT), Transform3D()]]
	var body_acc := [
		[MeshKit.torus(.13, .03, 20, 6), _at(Vector3(0, .63, 0)), "white"],
		[MeshKit.cylinder(.06, .06, .02, 18), _on_surf(SUIT, .34, 0.0, .004, PI / 2.0 - .2), "white"],
		[MeshKit.torus(.065, .013, 20, 5), _on_surf(SUIT, .34, 0.0, .012, -.2) * Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3.ZERO), "white"],
		[MeshKit.sphere(.035, 10, 6), _on_surf(SUIT, .34, 0.0, .016, -.2) * Transform3D(Basis.from_scale(Vector3(1, 1, .55)), Vector3.ZERO), "eye"],
	]
	var head := []
	for sx in [-1.0, 1.0]:
		head.append([MeshKit.cylinder(.06, .06, .05, 18), _at(Vector3(sx * .232, y, 0), Vector3(0, 0, PI / 2.0))])
	var acc := [
		[MeshKit.sphere(.19, 22, 14), _at(Vector3(0, y, 0), Vector3.ZERO, sc), "white"],
		[_patch(.197, PI / 2.0 - 1.05, PI / 2.0 + 1.05, 1.0, 2.05, 16, 7), _at(Vector3(0, y, 0), Vector3.ZERO, sc), "dark"],
		[MeshKit.cylinder(.012, .012, .08, 6), _at(Vector3(0, y + .2, 0)), "white"],
		[MeshKit.sphere(.036, 10, 6), _at(Vector3(0, y + .26, 0)), "eye"],
	]
	for sx in [-1.0, 1.0]:
		var ph: float = PI / 2.0 + sx * .36
		var p := Vector3(-cos(ph) * sin(1.5) * .2 * sc.x, y + cos(1.5) * .2 * sc.y, sin(ph) * sin(1.5) * .2 * sc.z)
		acc.append([MeshKit.sphere(.04, 10, 6), _at(p, Vector3(0, atan2(p.x, p.z), 0), Vector3(1, 1.3, .4)), "eye"])
	return {body = body, head = head, body_acc = body_acc, head_acc = acc}

static func _skin_wizard() -> Dictionary:
	var t := 1.0                                   # the hat's floppy tip leans this far
	var head := [
		[MeshKit.sphere(.165, 18, 10), _at(Vector3(0, .76, 0))],
		[MeshKit.cylinder(.31, .32, .035, 28), _at(Vector3(0, .855, 0), Vector3(.08, 0, 0))],
		[MeshKit.cylinder(.085, .2, .2, 20), _at(Vector3(0, .96, 0))],
		[MeshKit.sphere(.085, 12, 7), _at(Vector3(0, 1.06, 0))],
		[MeshKit.cylinder(0.0, .085, .16, 14), _at(Vector3(sin(t) * .1, 1.06 + cos(t) * .08, 0), Vector3(0, 0, -t))],
	]
	var body_acc := [
		[MeshKit.torus(.15, .045, 20, 6), _at(Vector3(0, .63, 0)), "tint3"],
		[_extrude(_star(.065), .022, 0.0), _on_surf(ROBE, .3, 0.0, .006, -.38), "star"],
	]
	for tail: Array in [[-.045, -.5], [.04, .35]]:
		body_acc.append([MeshKit.sphere(.05, 10, 6), _at(Vector3(tail[0], .54, _r_at(ROBE, .54) + .02), Vector3(-.3, 0, tail[1]), Vector3(.8, 1.6, .45)), "tint3"])
	return {body = [[_lathe(ROBE), Transform3D()]], head = head, body_acc = body_acc,
		head_acc = [[_extrude(_star(.06), .02, 0.0), _at(Vector3(0, .955, .157), Vector3(-.62, 0, 0)), "star"]]}

static func _skin_space() -> Dictionary:
	var y := .82
	var body := [[_lathe(FOOT), Transform3D()], [_lathe(SUIT), Transform3D()]]
	var body_acc := [
		[MeshKit.torus(.17, .035, 22, 6), _at(Vector3(0, .615, 0)), "white"],
		[MeshKit.cylinder(.075, .075, .02, 20), _on_surf(SUIT, .32, 0.0, .004, PI / 2.0 - .15), "white"],
		[_extrude(_star(.055), .018, 0.0), _on_surf(SUIT, .32, 0.0, .022, -.15), "gold"],
	]
	var head := []
	for sx in [-1.0, 1.0]:
		head.append([MeshKit.cylinder(.06, .06, .05, 18), _at(Vector3(sx * .245, y, 0), Vector3(0, 0, PI / 2.0))])
	var acc := [
		[MeshKit.sphere(.24, 24, 14), _at(Vector3(0, y, 0)), "white"],
		[_patch(.25, PI / 2.0 - 1.0, PI / 2.0 + 1.0, .62, 1.92, 16, 8), _at(Vector3(0, y, 0), Vector3.ZERO, Vector3(1, 1, 1.02)), "shade38"],
		[MeshKit.sphere(.032, 8, 5), _at(Vector3(-.075, y + .17, .172), Vector3(-.75, -.45, .3), Vector3(1.5, .7, .4)), "white"],
	]
	return {body = body, head = head, body_acc = body_acc, head_acc = acc}

static func _skin_dragon() -> Dictionary:
	var y := BELL_HEAD_Y
	var acc := []
	for sx in [-1.0, 1.0]:
		acc.append([MeshKit.cylinder(.036, .05, .12, 10), _at(Vector3(sx * .11, y + .18, -.01), Vector3(-.15, 0, -sx * .55)), "gold"])
		acc.append([MeshKit.cylinder(0.0, .036, .14, 10), _at(Vector3(sx * .175, y + .285, -.03), Vector3(-.25, 0, sx * .2)), "gold"])
	for k in 3:
		var th: float = [.25, .7, 1.15][k]
		acc.append([MeshKit.cylinder(0.0, .04 - k * .006, .1, 6), _at(Vector3(0, y + cos(th) * .19, -sin(th) * .19), Vector3(-th, 0, 0), Vector3(.5, 1, 1)), "shade25"])
	var wing := PackedVector2Array([Vector2(0, 0), Vector2(.02, .1)])
	_bezier(wing, Vector2(.02, .1), Vector2(.1, .16), Vector2(.17, .12), 5)
	_bezier(wing, Vector2(.17, .12), Vector2(.15, .08), Vector2(.16, .04), 3)
	_bezier(wing, Vector2(.16, .04), Vector2(.12, .06), Vector2(.11, .02), 3)
	_bezier(wing, Vector2(.11, .02), Vector2(.08, .04), Vector2(.06, -.01), 3)
	_bezier(wing, Vector2(.06, -.01), Vector2(.03, .01), Vector2(0, 0), 3)
	var body_acc := [[_octa(.05), _on_surf(BELL, .36, 0.0, .012, -.3) * Transform3D(Basis.from_scale(Vector3(.85, 1.25, .5)), Vector3.ZERO), "gold"]]
	var w := _extrude(wing, .016, 0.0)
	for sx in [-1.0, 1.0]:
		body_acc.append([w, _at(Vector3(sx * .14, .38, -.05), Vector3(0, sx * .35, 0), Vector3(sx * 1.35, 1.35, 1)), "tint28"])
	return {body = [[_lathe(BELL), Transform3D()]], head = [[MeshKit.sphere(.2, 22, 14), _at(Vector3(0, y, 0)), SOLID_UV]], body_acc = body_acc, head_acc = acc}


# ---------- building blocks ----------

## A transform: position, rotation in radians (x, then y, then z; yxz: y, then x, then z) and a scale.
static func _at(p: Vector3, r := Vector3.ZERO, sc: Variant = 1.0, yxz := false) -> Transform3D:
	var rx := Basis(Vector3.RIGHT, r.x)
	var ry := Basis(Vector3.UP, r.y)
	var rz := Basis(Vector3.BACK, r.z)
	var b: Basis = (ry * rx * rz) if yxz else (rx * ry * rz)
	return Transform3D(b * Basis.from_scale(sc if sc is Vector3 else Vector3.ONE * float(sc)), p)

## A torus turned so its hole's axis (its own y) points along z before rotation r.
static func _ring_at(p: Vector3, r: Vector3) -> Transform3D:
	return _at(p, r) * Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3.ZERO)

## A part lying on a lathe's surface at height y, angle a round the pawn (0 = its front), dz off the surface.
static func _on_surf(profile: Array, y: float, a := 0.0, dz := 0.0, tilt := -.35) -> Transform3D:
	var r := _r_at(profile, y) + dz
	return _at(Vector3(sin(a) * r, y, cos(a) * r), Vector3(tilt, a, 0), 1.0, true)

## A lathe profile's radius at height y.
static func _r_at(profile: Array, y: float) -> float:
	for k in range(1, profile.size()):
		if y <= float(profile[k][1]):
			var a: Array = profile[k - 1]
			var b: Array = profile[k]
			var d := float(b[1]) - float(a[1])
			return float(a[0]) + (float(b[0]) - float(a[0])) * (y - float(a[1])) / (d if d != 0.0 else 1.0)
	return 0.0

## An indexed lathe (MeshKit's stores every triangle's corners: the shared ones are stored once here).
static func _lathe(profile: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.create_from(MeshKit.lathe(_pts(profile), 36), 0)
	st.index()
	return st.commit()

## One mesh from [mesh, transform, cell] parts, under `outer`: a cell (a colour table key, or a UV) replaces the part's
## UVs, none keeps them. Mirrored parts get their winding flipped so they still face out.
static func _bake(parts: Array, outer := Transform3D()) -> ArrayMesh:
	var vs := PackedVector3Array()
	var ns := PackedVector3Array()
	var us := PackedVector2Array()
	var ix := PackedInt32Array()
	for p: Array in parts:
		var src: Array = (p[0] as Mesh).surface_get_arrays(0)
		var xf: Transform3D = outer * (p[1] as Transform3D)
		var nb := xf.basis.inverse().transposed()
		var base := vs.size()
		var pv: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
		var pn: PackedVector3Array = src[Mesh.ARRAY_NORMAL]
		var pu: Variant = src[Mesh.ARRAY_TEX_UV]
		var uv: Variant = null
		if p.size() > 2:
			uv = p[2] if p[2] is Vector2 else _cell(str(p[2]))
		for i in pv.size():
			vs.append(xf * pv[i])
			ns.append((nb * pn[i]).normalized())
			us.append(uv if uv != null else (pu[i] if pu != null else Vector2.ZERO))
		var pi: Variant = src[Mesh.ARRAY_INDEX]
		var flip := xf.basis.determinant() < 0.0
		var count: int = (pi as PackedInt32Array).size() if pi != null else pv.size()
		for t in range(0, count, 3):
			for k: int in ([0, 2, 1] if flip else [0, 1, 2]):
				ix.append(base + (int(pi[t + k]) if pi != null else t + k))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vs
	arrays[Mesh.ARRAY_NORMAL] = ns
	arrays[Mesh.ARRAY_TEX_UV] = us
	arrays[Mesh.ARRAY_INDEX] = ix
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out

## Triangles to a mesh, each with its own corners and its flat normal (facets).
static func _facets(tris: PackedVector3Array) -> ArrayMesh:
	var ns := PackedVector3Array()
	ns.resize(tris.size())
	for t in range(0, tris.size(), 3):
		var n := (tris[t + 2] - tris[t]).cross(tris[t + 1] - tris[t]).normalized()   # (Godot: clockwise front faces)
		ns[t] = n
		ns[t + 1] = n
		ns[t + 2] = n
	var us := PackedVector2Array()
	us.resize(tris.size())
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = tris
	arrays[Mesh.ARRAY_NORMAL] = ns
	arrays[Mesh.ARRAY_TEX_UV] = us
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out

## A smooth mesh cut into facets (the crystal column).
static func _flat(m: Mesh) -> ArrayMesh:
	var src: Array = m.surface_get_arrays(0)
	var pv: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
	var pi: Variant = src[Mesh.ARRAY_INDEX]
	var tris := PackedVector3Array()
	var count: int = (pi as PackedInt32Array).size() if pi != null else pv.size()
	for k in count:
		tris.append(pv[int(pi[k]) if pi != null else k])
	return _facets(tris)

## A faceted solid round the origin from its corners and faces (each turned outward).
static func _solid(corners: Array, faces: Array) -> ArrayMesh:
	var tris := PackedVector3Array()
	for f: Array in faces:
		var a: Vector3 = corners[f[0]]
		var b: Vector3 = corners[f[1]]
		var c: Vector3 = corners[f[2]]
		if (c - a).cross(b - a).dot(a + b + c) < 0.0:
			var t := b
			b = c
			c = t
		tris.append_array([a, b, c])
	return _facets(tris)

static func _octa(r: float) -> ArrayMesh:
	var key := "octa|%s" % r
	if not _solids.has(key):
		_solids[key] = _solid([Vector3(r, 0, 0), Vector3(-r, 0, 0), Vector3(0, r, 0), Vector3(0, -r, 0), Vector3(0, 0, r), Vector3(0, 0, -r)],
			[[0, 2, 4], [2, 1, 4], [1, 3, 4], [3, 0, 4], [2, 0, 5], [1, 2, 5], [3, 1, 5], [0, 3, 5]])
	return _solids[key]

static func _ico(r: float) -> ArrayMesh:
	var g := (1.0 + sqrt(5.0)) / 2.0
	var c := []
	for v: Vector3 in [Vector3(-1, g, 0), Vector3(1, g, 0), Vector3(-1, -g, 0), Vector3(1, -g, 0), Vector3(0, -1, g), Vector3(0, 1, g),
			Vector3(0, -1, -g), Vector3(0, 1, -g), Vector3(g, 0, -1), Vector3(g, 0, 1), Vector3(-g, 0, -1), Vector3(-g, 0, 1)]:
		c.append(v.normalized() * r)
	return _solid(c, [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]])

## A piece of a sphere: `ph` runs round y (PI / 2 is the front, +z), `th` down from the top. Smooth, outward.
static func _patch(r: float, ph0: float, ph1: float, th0: float, th1: float, ws: int, hs: int) -> ArrayMesh:
	var vs := PackedVector3Array()
	var ns := PackedVector3Array()
	for j in hs + 1:
		var th := lerpf(th0, th1, float(j) / hs)
		for i in ws + 1:
			var ph := lerpf(ph0, ph1, float(i) / ws)
			var n := Vector3(-cos(ph) * sin(th), cos(th), sin(ph) * sin(th))
			vs.append(n * r)
			ns.append(n)
	var ix := PackedInt32Array()
	for j in hs:
		for i in ws:
			var a := j * (ws + 1) + i
			var b := a + 1
			var c := a + ws + 1
			var d := c + 1
			ix.append_array([a, c, b, b, c, d] if _front(vs, a, c, b) else [a, b, c, b, d, c])
	var us := PackedVector2Array()
	us.resize(vs.size())
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vs
	arrays[Mesh.ARRAY_NORMAL] = ns
	arrays[Mesh.ARRAY_TEX_UV] = us
	arrays[Mesh.ARRAY_INDEX] = ix
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out

## Does this order of corners face outward (away from the origin)? (Godot: clockwise front faces)
static func _front(vs: PackedVector3Array, a: int, b: int, c: int) -> bool:
	return (vs[c] - vs[a]).cross(vs[b] - vs[a]).dot(vs[a] + vs[b] + vs[c]) >= 0.0

## Appends a quadratic curve (its end points included, without repeating the last point already there).
static func _bezier(out: PackedVector2Array, a: Vector2, c: Vector2, b: Vector2, n: int) -> void:
	for k in n + 1:
		var t := float(k) / n
		var p := a.lerp(c, t).lerp(c.lerp(b, t), t)
		if out.is_empty() or out[out.size() - 1].distance_to(p) > 0.0001:
			if not (out.size() > 2 and out[0].distance_to(p) < 0.0001):
				out.append(p)

## A five-pointed star of radius r.
static func _star(r: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in 10:
		var a := TAU * k / 10.0
		var rr := r * .45 if k % 2 else r
		out.append(Vector2(sin(a) * rr, cos(a) * rr))
	return out

## A slice of a disc from a0 to a1 (from its centre, or from radius r_in: a band).
static func _sector(r: float, a0: float, a1: float, r_in := 0.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := 10
	for k in n + 1:
		var a := lerpf(a0, a1, float(k) / n)
		out.append(Vector2(cos(a), sin(a)) * r)
	if r_in > 0.0:
		for k in range(n, -1, -1):
			var a := lerpf(a0, a1, float(k) / n)
			out.append(Vector2(cos(a), sin(a)) * r_in)
	else:
		out.append(Vector2.ZERO)
	return out


# ---------- the colour table ----------

## Where a colour of the table sits (a UV at the middle of its cell).
static func _cell(key: String) -> Vector2:
	var i := _cell_keys().find(key)
	assert(i >= 0, "unknown colour " + key)
	return Vector2((i % PALETTE_CELLS + 0.5) / PALETTE_CELLS, (i / PALETTE_CELLS + 0.5) / PALETTE_CELLS)

static func _cell_keys() -> Array:
	return INKS.keys() + ["eye", "tint3", "tint5", "tint28", "tint35", "shade18", "shade25", "shade38", "petal", "mid", "star"]

## The colour table for a seat colour: INKS and the shades of the seat. 32 x 32, made once per colour, no mipmaps
## (they would blend the cells).
static func palette(seat: Color) -> ImageTexture:
	var key := "palette|%s" % seat.to_html()
	if _tex.has(key):
		return _tex[key]
	var c := maxi(Palette.PLAYER.find(seat), 0)
	var tint := func(k: float) -> Color: return seat.lerp(Color.WHITE, k)
	var shade := func(k: float) -> Color: return seat.lerp(Color.BLACK, k)
	var cols := {eye = tint.call(.3), tint3 = tint.call(.3), tint5 = tint.call(.5), tint28 = tint.call(.28), tint35 = tint.call(.35),
		shade18 = shade.call(.18), shade25 = shade.call(.25), shade38 = shade.call(.38),
		petal = Color(["#ff86b0", "#8be07a", "#ffd84a", "#5fb0ff"][c]), mid = Color("#e5484d" if c == 2 else "#ffd23f"), star = Color("#ff8a3d" if c == 2 else "#ffd84a")}
	var keys := _cell_keys()
	var cell := 4
	var n := PALETTE_CELLS * cell
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	for i in keys.size():
		var k: String = keys[i]
		var col: Color = cols[k] if cols.has(k) else Color(str(INKS[k]))
		img.fill_rect(Rect2i(i % PALETTE_CELLS * cell, i / PALETTE_CELLS * cell, cell, cell), col)
	var t := ImageTexture.create_from_image(img)
	_tex[key] = t
	return t


# ---------- the themed bodies' textures ----------

## Candy stripes, a vine or scales over the seat colour: u round the pawn, v its height (plain above SOLID_V). 96 x 96.
static func _body_texture(kind: String, color: Color) -> ImageTexture:
	var n := 96
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	img.fill(color)
	var data := img.get_data()
	match kind:
		"stripes":
			var cream := Color("#fff8f2")
			var solid := int(SOLID_V * n)
			for y in solid:
				for x in n:
					var t := fposmod(float(x) / n * 4.0 + float(y) / n * 3.0, 1.0)      # 4 stripes round, leaning
					var edge := minf(minf(t, 0.6 - t), 1.0) if t < 0.6 else -minf(t - 0.6, 1.0 - t)
					_put(data, n, x, y, cream.lerp(color, clampf(edge / 0.03 + 0.5, 0.0, 1.0)))
		"vine":
			var c := maxi(Palette.PLAYER.find(color), 0)
			var band := Color("#5cae3a") if c == 2 else color.lerp(Color.WHITE, 0.62)
			var wave := func(u: float) -> float: return .32 + .12 * sin(u * TAU * 2.0)
			for x in n:
				var mid: float = wave.call(float(x) / n) * n
				for y in range(int(mid) - 3, int(mid) + 4):
					_put(data, n, x, y, band)
			var green := Color("#4caf50")
			for k in 6:
				var u := float(k) / 6.0 + 0.04
				var v: float = wave.call(u) + (.075 if k % 2 else -.075)
				_ellipse_px(data, n, u * n, v * n, 6.0, 3.0, .6 if k % 2 else -.6, green)
		"scales":
			var fill := color.lerp(Color.BLACK, 0.1)
			var line := color.lerp(Color.BLACK, 0.32)
			var cell := 12
			var row := 8
			var rows := int(0.55 * n / row)
			for r in rows:                                  # from the foot up: each row overlaps the one below
				for k in n / cell:
					var cx := k * cell + (cell / 2 if r % 2 else 0) + cell / 2
					var cy := r * row + cell / 2
					for dy in range(-cell / 2, 1):             # the round end towards the foot
						for dx in range(-cell / 2, cell / 2 + 1):
							var d := sqrt(float(dx * dx + dy * dy))
							if d <= cell / 2.0:
								_put(data, n, posmod(cx + dx, n), cy + dy, line if d > cell / 2.0 - 1.4 else fill)
	var out := Image.create_from_data(n, n, false, Image.FORMAT_RGBA8, data)
	out.generate_mipmaps()
	return ImageTexture.create_from_image(out)

static func _put(data: PackedByteArray, n: int, x: int, y: int, c: Color) -> void:
	if y < 0 or y >= n:
		return
	var i := (y * n + posmod(x, n)) * 4
	data[i] = c.r8
	data[i + 1] = c.g8
	data[i + 2] = c.b8
	data[i + 3] = 255

static func _ellipse_px(data: PackedByteArray, n: int, cx: float, cy: float, rx: float, ry: float, rot: float, c: Color) -> void:
	var cr := cos(rot)
	var sr := sin(rot)
	var m := int(ceilf(maxf(rx, ry)))
	for dy in range(-m, m + 1):
		for dx in range(-m, m + 1):
			var a := (dx * cr + dy * sr) / rx
			var b := (-dx * sr + dy * cr) / ry
			if a * a + b * b <= 1.0:
				_put(data, n, int(cx) + dx, int(cy) + dy, c)


# =====================================================================================================================
# Finish textures (one small texture per finish and colour, made once and kept)
# =====================================================================================================================

## A finish's surface in `color`: the themed bodies' (_body_texture), or the marble / glitter one (seamless round the pawn, mipmapped): marble 64 x 64 (soft veins over a
## faint cloud), glitter 96 x 96 (single-pixel specks: a few white or pale gold, more in a light tint, the rest the
## colour a shade deeper so the specks stand out).
static func texture(kind: String, color: Color) -> ImageTexture:
	var key := "%s|%s" % [kind, color.to_html()]
	if _tex.has(key):
		return _tex[key]
	if kind != "marble" and kind != "glitter":
		_tex[key] = _body_texture(kind, color)
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
