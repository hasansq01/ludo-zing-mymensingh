class_name PawnSkins
extends RefCounted
## The 3D looks of the pawn skins (Catalog.PAWNS), shared by the Ludo board, the Snakes & Ladders board, the Shop's
## pictures (PawnStage) and the bake tool. Every skin keeps the seat colour as the pawn's main colour, so pawns on the
## track can always be told apart. Classic is the free turned pawn; every other skin is built in _skin_*: a body and a
## head in the seat colour plus accents (see each one's comment).
## Their many small colours share one colour table per seat (a 64 x 64 texture, palette()): every accent mesh points its
## UVs at the table's cells, so a pawn stays at four draw calls (seat colour body + head, accents body + head) and uses
## the finishes' textured shader. "~gold" and the other ~ cells are foils: ramps in the table that a part's UVs read by
## its surface's direction, a reflection baked into the mesh. It makes metal and gems shine in any lighting, for nothing
## at run time. The skins with a face tip their head back in Top View (pose()).
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
const CUP := [[0, 0], [.37, 0], [.39, .02], [.385, .045], [.3, .06], [.18, .07], [.16, .09], [.17, .14], [.22, .26],
	[.27, .4], [.3, .52], [.315, .6], [.322, .63], [.305, .648], [.287, .632], [.276, .58]]
const FROTH := [[.29, .62], [.255, .662], [.18, .69], [.09, .702], [0, .705]]
const TWINKLE := 0.035                  ## glitter: the specks drift round the pawn this many turns a second
## The themed skins' bodies (radius, height): a bell, a robe, a suit on a foot, a crystal column.
const BELL := [[0, 0], [.37, 0], [.39, .02], [.392, .055], [.365, .09], [.32, .115], [.28, .19], [.24, .29], [.205, .4], [.175, .51], [.155, .6], [.12, .665], [0, .69]]
## The classic body, finely turned: foot, waist, collar.
const TURNED := [[0, 0], [.37, 0], [.39, .02], [.392, .055], [.365, .085], [.315, .105], [.255, .15], [.195, .24], [.16, .33], [.138, .42], [.13, .475], [.16, .5],
	[.245, .515], [.262, .54], [.245, .565], [.16, .585], [.12, .61], [0, .62]]
## Kitty's round little body.
const CHUBBY := [[0, 0], [.3, 0], [.322, .02], [.33, .06], [.325, .14], [.3, .26], [.262, .4], [.205, .52], [.15, .6], [.11, .66], [0, .68]]
const ROBE := [[0, 0], [.37, 0], [.38, .04], [.365, .09], [.33, .19], [.28, .33], [.225, .47], [.175, .58], [.13, .65], [0, .67]]
const FOOT := [[0, 0], [.36, 0], [.38, .03], [.38, .08], [.35, .12], [0, .12]]
const SUIT := [[0, .1], [.3, .1], [.3, .3], [.285, .42], [.245, .52], [.18, .59], [.09, .625], [0, .63]]
const COLUMN := [[0, 0], [.33, 0], [.34, .05], [.29, .12], [.235, .3], [.2, .46], [.23, .55], [.15, .64], [0, .66]]
const BELL_HEAD_Y := 0.79               ## the head's centre on a bell
## Top View: how far a skin's head tips back (radians) and the height it turns about.
const TIP_3D := 0.45                    ## 3D View: this share of a skin's look angle
const LOOK := {robo = [1.3, .82], space = [1.3, .82], pirate = [1.0, .8], blossom = [1.0, .83], fruity = [.9, .8], wizard = [.8, .73], dragon = [1.0, .8], kitty = [1.0, .79]}
## The textures of the themed bodies: where a mesh's v (its height) is above SOLID_V they are the plain seat colour,
## so a head in the same material can point at SOLID_UV.
const SOLID_V := 0.72
const SOLID_UV := Vector2(0.5, 0.86)
## The fruit on a fruity pawn, by seat (red, green, yellow, blue).
const FRUIT := ["strawberry", "melon", "orange", "blueberry"]
const THEMED := ["trim", "candy", "fruity", "blossom", "marble", "ice", "pirate", "robo", "wizard", "kitty", "space", "teacup", "dragon", "glitter", "crown", "knight"]
const PALETTE_SIZE := 64                ## the colour table's width and height, in pixels
const PALETTE_CELLS := 8                ## cells a row, each 8 x 8 pixels
const PALETTE_ROWS := 6                 ## rows of cells; the foil ramps (FOILS) fill the rest of the table
const FOILS := ["~gold", "~silver", "~gem", "~frost", "~visor"]
## The table's fixed colours (the seat-dependent ones: _palette_colors).
const INKS := {gold = "#f4bd3c", white = "#f7f4ee", dark = "#24202b", leaf = "#55b046", stem = "#7a4a21", cream = "#fff4e6",
	felt = "#2b2530", belt = "#5b3a22", flesh = "#ff4b5c", rind = "#2e8b3e", seed = "#2b1b1b", dot = "#ffe38a", navy = "#4a5fc4",
	orange = "#ff9a1f", pink = "#ff6fa8", sky = "#5ac8fa", lemon = "#ffd23f", lime = "#7ed957", tang = "#ff8a3d", violet = "#b38bff",
	cherry = "#e8213f", skin = "#ffd4ac", skin2 = "#f4b48a", glow = "#5ff2ff", ear = "#ffb3c4"}

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
		"stripes", "scales":
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

## "marble" | "glitter" | "stripes" | "scales" | "" (the skin's surface).
static func finish(id: String) -> String:
	match id:
		"marble", "glitter": return id
		"candy": return "stripes"
		"dragon": return "scales"
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
## taller), tipped back about its turning height so a face looks up at the camera: part of the skin's look angle in
## 3D View (its camera is steep too), all of it in Top View. k: 0 in 3D View .. 1 in Top View. Skins without a look just
## follow the stretch.
static func pose(d: Dictionary, k: float, stretch := 1.0) -> void:
	var head: Node3D = d.head
	var look := float(d.get("look", 0.0))
	var y := HEAD_Y * stretch
	if look <= 0.0:
		head.position.y = y
		return
	var a := -look * lerpf(TIP_3D, 1.0, k)
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
	var out := {body = _lathe(TURNED), head = MeshKit.sphere(HEAD_R, 28, 18), accents = [], top = CLASSIC_TOP, finish = ""}
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

## A skin's meshes: seat-colour body + head, then the accents on body and head, all from the colour table.
## Parts are [mesh, transform, cell]; all in pawn units (y up from the board), the head's moved to its node's origin.
static func _themed(id: String, seat: int) -> Dictionary:
	var f: Dictionary = _skin(id, seat)
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

static func _skin(id: String, seat: int) -> Dictionary:
	match id:
		"trim": return _skin_trim()
		"candy": return _skin_candy()
		"fruity": return _skin_fruity(seat)
		"blossom": return _skin_blossom()
		"marble": return _skin_marble()
		"ice": return _skin_ice()
		"pirate": return _skin_pirate()
		"robo": return _skin_robo()
		"wizard": return _skin_wizard()
		"kitty": return _skin_kitty()
		"space": return _skin_space()
		"teacup": return _skin_teacup()
		"dragon": return _skin_dragon()
		"glitter": return _skin_glitter()
		"crown": return _skin_crown()
	return _skin_knight()

## The classic pawn's body and head, turned more finely (the plain base of the finishes and the jewellery).
static func _turned() -> Array:
	return [[_lathe(TURNED), Transform3D()]]

static func _round_head() -> Array:
	return [[MeshKit.sphere(HEAD_R, 20, 12), _at(Vector3(0, HEAD_Y, 0)), SOLID_UV]]

## Gold Trim: engraved bands, a collar of beads, a band and a finial on the head.
static func _skin_trim() -> Dictionary:
	var body_acc := [
		[MeshKit.torus(.372, .024, 30, 4), _at(Vector3(0, .06, 0)), "~gold"],
		[MeshKit.torus(.3, .016, 26, 4), _at(Vector3(0, .115, 0)), "~gold"],
		[MeshKit.torus(.15, .018, 16, 4), _at(Vector3(0, .34, 0)), "~gold"],
		[_lathe([[.255, .5], [.268, .52], [.268, .56], [.25, .58]], 28), Transform3D(), "~gold"],
	]
	for k in 10:
		var a := TAU * k / 10.0
		body_acc.append([_octa(.024), _at(Vector3(sin(a) * .262, .19 + (k % 2) * .0, cos(a) * .262), Vector3(0, a, 0), Vector3(1, 1.5, .6), true), "~gold"])
	for k in 6:
		var a := TAU * k / 6.0
		body_acc.append([_octa(.022), _at(Vector3(sin(a) * .272, .54, cos(a) * .272), Vector3(0, a, 0), Vector3(1, 1, .6), true), "~gem"])
	var head_acc := [
		[MeshKit.torus(.178, .012, 28, 5), _at(Vector3(0, HEAD_Y - .06, 0)), "~gold"],
		[_lathe([[.045, HEAD_Y + .172], [.058, HEAD_Y + .19], [.03, HEAD_Y + .215], [.018, HEAD_Y + .24], [.03, HEAD_Y + .26], [.024, HEAD_Y + .285], [0, HEAD_Y + .315]], 12), Transform3D(), "~gold"],
	]
	return {body = _turned(), head = _round_head(), body_acc = body_acc, head_acc = head_acc}

## Marble: a polished statue, gold at the foot and the collar.
static func _skin_marble() -> Dictionary:
	var body_acc := [
		[MeshKit.torus(.374, .02, 30, 4), _at(Vector3(0, .058, 0)), "~gold"],
		[MeshKit.torus(.258, .016, 24, 4), _at(Vector3(0, .54, 0)), "~gold"],
		[MeshKit.torus(.15, .012, 16, 4), _at(Vector3(0, .34, 0)), "~gold"],
	]
	return {body = _turned(), head = [[MeshKit.sphere(HEAD_R, 20, 12), _at(Vector3(0, HEAD_Y, 0))]], body_acc = body_acc,
		head_acc = [[MeshKit.sphere(.032, 10, 6), _at(Vector3(0, HEAD_Y + HEAD_R + .012, 0)), "~gold"]]}

## Glitter: silver at the foot and collar, bright four-point glints on the pawn, a diamond on the head.
static func _skin_glitter() -> Dictionary:
	var body_acc := [
		[MeshKit.torus(.374, .02, 30, 4), _at(Vector3(0, .058, 0)), "~silver"],
		[MeshKit.torus(.258, .016, 24, 4), _at(Vector3(0, .54, 0)), "~silver"],
	]
	for g: Array in [[.18, .3, .7], [.2, -.7, .55], [.1, 2.6, .5]]:
		var y: float = g[0]
		var r := _r_at(TURNED, y) + .012
		body_acc.append([_extrude(_star4(.075 * float(g[2]) / .6), .01, 0.0), _at(Vector3(sin(g[1]) * r, y, cos(g[1]) * r), Vector3(-.3, g[1], 0), 1.0, true), "white"])
	var head_acc := [
		[_extrude(_star4(.06), .01, 0.0), _at(Vector3(sin(.7) * .19, HEAD_Y + .06, cos(.7) * .19), Vector3(-.3, .7, 0), 1.0, true), "white"],
		[_octa(.05), _at(Vector3(0, HEAD_Y + HEAD_R + .05, 0), Vector3(0, .4, 0), Vector3(1, 1.5, 1)), "~silver"],
	]
	return {body = _turned(), head = [[MeshKit.sphere(HEAD_R, 20, 12), _at(Vector3(0, HEAD_Y, 0))]], body_acc = body_acc, head_acc = head_acc}

## Royal Crown: a king. A big arched crown with gems, an ermine cape, a gold chain.
static func _skin_crown() -> Dictionary:
	var y := HEAD_Y
	var r := .172
	var band_y := y + .135
	var acc := [
		[_lathe([[r, band_y - .02], [r + .012, band_y], [r + .012, band_y + .05], [r + .004, band_y + .065]], 28), Transform3D(), "~gold"],
		[MeshKit.sphere(r - .012, 12, 6), _at(Vector3(0, band_y + .035, 0), Vector3.ZERO, Vector3(1, .55, 1)), "shade38"],
	]
	for k in 6:
		var a := TAU * k / 6.0
		var p := Vector3(sin(a) * (r + .006), band_y + .1, cos(a) * (r + .006))
		acc.append([MeshKit.cylinder(0.0, .042, .1, 6), _at(p + Vector3(0, -.008, 0), Vector3(0, a, 0), Vector3(1, 1, .45), true), "~gold"])
		acc.append([MeshKit.sphere(.017, 6, 4), _at(p + Vector3(0, .048, 0)), "white"])
		var g := Vector3(sin(a + PI / 6.0) * (r + .014), band_y + .024, cos(a + PI / 6.0) * (r + .014))
		acc.append([_octa(.019 if k % 2 else .023), _at(g, Vector3(0, a + PI / 6.0, 0), Vector3(1, 1, .6), true), "~gem" if k % 2 == 0 else "white"])
	for rot in [0.0, PI / 2.0]:                      # the two arches, to an orb and a small cross
		var path := []
		for k in 9:
			var t := PI * k / 8.0
			path.append([Vector3(Basis(Vector3.UP, rot) * Vector3(cos(t) * (r - .004), band_y + .05 + sin(t) * .1, 0)), .011])
		acc.append([_tube(path, 4), Transform3D(), "~gold"])
	acc.append([MeshKit.sphere(.033, 10, 6), _at(Vector3(0, band_y + .165, 0)), "~gold"])
	acc.append([MeshKit.cylinder(.01, .01, .065, 5), _at(Vector3(0, band_y + .215, 0)), "~gold"])
	acc.append([MeshKit.cylinder(.009, .009, .05, 5), _at(Vector3(0, band_y + .222, 0), Vector3(0, 0, PI / 2.0)), "~gold"])
	var cape := [[_lathe([[.12, .62], [.19, .555], [.24, .535], [.272, .565], [.262, .61], [.2, .66], [.11, .68]], 22), Transform3D(), "cream"]]
	for k in 8:
		var a := TAU * k / 8.0
		cape.append([MeshKit.sphere(.014, 5, 3), _at(Vector3(sin(a) * .262, .59, cos(a) * .262), Vector3.ZERO, Vector3(.8, 1.5, .8)), "dark"])
	cape.append([MeshKit.torus(.374, .022, 30, 4), _at(Vector3(0, .058, 0)), "~gold"])
	cape.append([MeshKit.torus(.15, .014, 16, 4), _at(Vector3(0, .34, 0)), "~gold"])
	cape.append([_octa(.042), _at(Vector3(0, .5, _r_at(TURNED, .5) + .01), Vector3(-.1, 0, 0), Vector3(1, 1.25, .55)), "~gem"])
	return {body = _turned(), head = _round_head(), body_acc = cape, head_acc = acc}

## Chess Knight: a horse with a real neck: bevelled, a mane, ears, an eye, a gold bridle, on a gold-ringed base.
static func _skin_knight() -> Dictionary:
	var body := [[_lathe(KNIGHT_BASE, 32), Transform3D()]]
	var neck := _bevelled(_pts(KNIGHT), KNIGHT_THICK, .035)
	var head := [[neck, _at(Vector3(0, 0, 0))]]
	var acc := []
	for sz in [-1.0, 1.0]:
		var e := Vector3(.075, .845, sz * (KNIGHT_THICK / 2.0 + .004))
		acc.append([MeshKit.sphere(.036, 10, 6), _at(e, Vector3.ZERO, Vector3(1, 1, .35)), "white"])
		acc.append([MeshKit.sphere(.024, 8, 5), _at(e + Vector3(.006, -.002, sz * .009), Vector3.ZERO, Vector3(1, 1.1, .4)), "dark"])
		acc.append([MeshKit.sphere(.008, 5, 3), _at(e + Vector3(.012, .008, sz * .017)), "white"])
		acc.append([MeshKit.sphere(.014, 6, 4), _at(Vector3(.262, .72, sz * (KNIGHT_THICK / 2.0 - .002)), Vector3.ZERO, Vector3(1, 1, .4)), "dark"])
		head.append([_extrude(PackedVector2Array([Vector2(-.05, .955), Vector2(-.025, 1.09), Vector2(.035, .985)]), .05, 0.0), _at(Vector3(0, 0, sz * .055))])
		# the bridle's cheek strap, each side
		acc.append([_tube([[Vector3(.2, .68, sz * .104), .011], [Vector3(.12, .75, sz * .104), .011], [Vector3(.02, .88, sz * .104), .011]], 5), Transform3D(), "~gold"])
		acc.append([_tube([[Vector3(.27, .67, sz * .104), .011], [Vector3(.2, .68, sz * .104), .011], [Vector3(.17, .755, sz * .104), .011]], 5), Transform3D(), "~gold"])
		acc.append([MeshKit.sphere(.019, 8, 5), _at(Vector3(.2, .68, sz * .108)), "~gold"])
	# the mane: tufts down the back of the neck, a shade deeper
	var mane := PackedVector2Array([Vector2(-.02, 1.03), Vector2(-.09, 1.02), Vector2(-.1, .97), Vector2(-.17, .95), Vector2(-.17, .89),
		Vector2(-.24, .85), Vector2(-.23, .78), Vector2(-.28, .72), Vector2(-.25, .65), Vector2(-.28, .58), Vector2(-.235, .52), Vector2(-.24, .46), Vector2(-.17, .46),
		Vector2(-.17, .62), Vector2(-.12, .8), Vector2(-.05, .94)])
	acc.append([_bevelled(mane, .11, .02), Transform3D(), "shade38"])
	acc.append([MeshKit.torus(.195, .018, 26, 5), _at(Vector3(0, .445, 0)), "~gold"])
	var body_acc := [
		[MeshKit.torus(.366, .02, 30, 4), _at(Vector3(0, .05, 0)), "~gold"],
		[MeshKit.torus(.29, .012, 30, 5), _at(Vector3(0, .125, 0)), "~gold"],
	]
	return {body = body, head = head, body_acc = body_acc, head_acc = acc}

## Candy Pop: a candy-striped bell, a swirl of frosting with sprinkles and a cherry.
static func _skin_candy() -> Dictionary:
	var y := .72
	var path := []
	var turns := 2.6
	for k in 34:
		var t := k / 33.0
		var a := t * turns * TAU
		var rr := lerpf(.178, .012, pow(t, .85))
		path.append([Vector3(cos(a) * rr, y + t * .29, sin(a) * rr), lerpf(.064, .024, t)])
	var acc := [[_tube(path, 6), Transform3D(), "cream"]]
	acc.append([MeshKit.sphere(.13, 14, 8), _at(Vector3(0, y + .09, 0), Vector3.ZERO, Vector3(1, 1.05, 1)), "cream"])
	acc.append([MeshKit.sphere(.05, 12, 8), _at(Vector3(0, y + .325, 0)), "cherry"])
	acc.append([MeshKit.sphere(.014, 6, 4), _at(Vector3(-.016, y + .345, .03)), "white"])
	acc.append([_tube([[Vector3(0, y + .365, 0), .006], [Vector3(.02, y + .395, 0), .006], [Vector3(.05, y + .42, 0), .005]], 4), Transform3D(), "stem"])
	var r := RandomNumberGenerator.new()
	r.seed = 3
	var cols := ["pink", "sky", "lemon", "lime", "tang", "violet"]
	for k in 12:
		var t := .08 + .78 * k / 11.0
		var a := r.randf() * TAU
		var rr := lerpf(.215, .05, t)
		acc.append([MeshKit.cylinder(.009, .009, .04, 4), _at(Vector3(cos(a) * rr, y + t * .29 + .02, sin(a) * rr), Vector3(r.randf() * 3.0, a, r.randf() * 3.0)), cols[k % cols.size()]])
	var lace := []
	for k in 12:
		var a := TAU * k / 12.0
		lace.append([MeshKit.sphere(.04, 6, 4), _at(Vector3(sin(a) * .172, .62, cos(a) * .172), Vector3.ZERO, Vector3(1, .85, 1)), "cream"])
	lace.append([MeshKit.torus(.372, .018, 30, 4), _at(Vector3(0, .052, 0)), "cream"])
	return {body = [[_lathe(BELL), Transform3D()]], head = [[MeshKit.sphere(.12, 12, 8), _at(Vector3(0, y + .05, 0)), SOLID_UV]], body_acc = lace, head_acc = acc}

## Fruity: a big glossy fruit for a head by seat, its juice dripping over a bell, a leaf collar.
static func _skin_fruity(seat: int) -> Dictionary:
	var y := .82
	var head := []
	var acc := []
	match FRUIT[seat]:
		"strawberry":
			var prof := [[0, -.23], [.05, -.215], [.11, -.16], [.175, -.07], [.215, .02], [.215, .09], [.17, .15], [.09, .185], [0, .195]]
			head.append([_lathe(prof, 22), _at(Vector3(0, y, 0))])
			for k in 16:
				var dy := -.18 + (k % 6) * .05
				var a := k * 2.4
				var rr := _r_at(prof, dy) + .002
				acc.append([MeshKit.sphere(.015, 5, 3), _at(Vector3(sin(a) * rr, y + dy, cos(a) * rr), Vector3(0, a, 0), Vector3(.8, 1.4, .45), true), "dot"])
			for k in 7:
				var a := TAU * k / 7.0
				acc.append([_extrude(_leaf_poly(.17, .05), .016, 0.0), _at(Vector3(sin(a) * .01, y + .18, cos(a) * .01), Vector3(.28, a, 0), 1.0, true) * _at(Vector3.ZERO, Vector3(PI / 2.0, 0, 0)), "leaf"])
			acc.append([_tube([[Vector3(0, y + .19, 0), .018], [Vector3(.01, y + .25, 0), .014]], 5), Transform3D(), "stem"])
		"melon":                                     # the green seat: a crisp apple
			var prof := [[0, -.135], [.06, -.175], [.145, -.18], [.21, -.11], [.235, -.01], [.22, .1], [.15, .165], [.07, .165], [0, .12]]
			head.append([_lathe(prof, 24), _at(Vector3(0, y, 0))])
			acc.append([_tube([[Vector3(0, y + .1, 0), .017], [Vector3(.012, y + .18, 0), .014], [Vector3(.04, y + .25, 0), .017]], 5), Transform3D(), "stem"])
			acc.append([_extrude(_leaf_poly(.15, .055), .014, 0.0), _at(Vector3(.03, y + .185, 0), Vector3(.2, 0, -.7)), "lime"])
			acc.append([MeshKit.sphere(.05, 8, 5), _at(Vector3(-.09, y + .09, .165), Vector3(0, 0, .5), Vector3(.5, 1.1, .25)), "white"])
		"orange":
			acc.append([MeshKit.sphere(.225, 22, 14), _at(Vector3(0, y, 0), Vector3.ZERO, Vector3(1.04, .97, 1.04)), "orange"])
			for k in 20:
				var th := 0.35 + 2.3 * fposmod(k * .381, 1.0)
				var a := k * 2.4
				acc.append([MeshKit.sphere(.009, 5, 3), _at(Vector3(sin(th) * sin(a) * .232, y + cos(th) * .218, sin(th) * cos(a) * .232)), "tang"])
			acc.append([MeshKit.cylinder(.014, .022, .05, 6), _at(Vector3(0, y + .225, 0)), "stem"])
			acc.append([_extrude(_leaf_poly(.15, .055), .014, 0.0), _at(Vector3(.015, y + .225, 0), Vector3(.25, 0, -.9)), "leaf"])
			acc.append([MeshKit.sphere(.05, 8, 5), _at(Vector3(-.1, y + .09, .165), Vector3(0, 0, .5), Vector3(.5, 1.1, .25)), "white"])
		_:
			head.append([MeshKit.sphere(.22, 22, 14), _at(Vector3(0, y, 0), Vector3.ZERO, Vector3(1.05, .97, 1.05))])
			for k in 6:
				var a := TAU * k / 6.0
				acc.append([MeshKit.cylinder(0.0, .034, .07, 4), _at(Vector3(sin(a) * .05, y + .215, cos(a) * .05), Vector3(.75, a, 0), 1.0, true), "navy"])
			acc.append([MeshKit.cylinder(.056, .06, .02, 12), _at(Vector3(0, y + .205, 0)), "shade38"])
			acc.append([MeshKit.sphere(.05, 8, 5), _at(Vector3(-.1, y + .09, .165), Vector3(0, 0, .5), Vector3(.5, 1.1, .25)), "white"])
	var drips := [[_lathe([[_r_at(BELL, .46) + .007, .46], [_r_at(BELL, .54) + .012, .54], [_r_at(BELL, .62) + .014, .62], [.125, .675], [0, .695]], 26), Transform3D(), "tint3"]]
	for k in 10:
		var a := TAU * k / 10.0
		var dy := .44 - (k % 3) * .055
		var rr := _r_at(BELL, dy) + .004
		drips.append([MeshKit.sphere(.033, 6, 4), _at(Vector3(sin(a) * rr, dy, cos(a) * rr), Vector3(0, a, 0), Vector3(1, 2.2, .5), true), "tint3"])
	for k in 5:
		var a := TAU * k / 5.0 + .3
		drips.append([_extrude(_leaf_poly(.15, .05), .014, 0.0), _at(Vector3(sin(a) * .09, .655, cos(a) * .09), Vector3(-.15, a, 0), 1.0, true) * _at(Vector3.ZERO, Vector3(PI / 2.0, 0, 0)), "leaf"])
	drips.append([MeshKit.torus(.372, .016, 30, 4), _at(Vector3(0, .052, 0)), "tint3"])
	return {body = [[_lathe(BELL), Transform3D()]], head = head, body_acc = drips, head_acc = acc}

## A pointed leaf along +y in its plane, its base at the origin.
static func _leaf_poly(l: float, w: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	_bezier(out, Vector2.ZERO, Vector2(w * 1.5, l * .45), Vector2(0, l), 5)
	_bezier(out, Vector2(0, l), Vector2(-w * 1.5, l * .45), Vector2.ZERO, 5)
	out.remove_at(out.size() - 1)
	return out

## Blossom: a double flower with a golden heart, a skirt of petals, leaves at the neck.
static func _skin_blossom() -> Dictionary:
	var m := _at(Vector3(0, .845, .035), Vector3(-.28, 0, 0))
	var acc := []
	for k in 6:
		var a := TAU * k / 6.0
		acc.append([MeshKit.sphere(.12, 10, 5), m * _at(Vector3(sin(a) * .175, cos(a) * .175, -.02), Vector3(sin(a) * -.45, cos(a) * .45, -a), Vector3(.72, 1.05, .22)), "petal"])
	for k in 6:
		var a := TAU * (k + .5) / 6.0
		acc.append([MeshKit.sphere(.085, 8, 5), m * _at(Vector3(sin(a) * .105, cos(a) * .105, .03), Vector3(sin(a) * -.5, cos(a) * .5, -a), Vector3(.7, 1.05, .28)), "petal2"])
	acc.append([MeshKit.sphere(.07, 10, 6), m * _at(Vector3(0, 0, .055), Vector3.ZERO, Vector3(1, 1, .6)), "~gold"])
	for k in 5:
		var a := k * 2.4
		var rr := sqrt((k + .5) / 5.0) * .045
		acc.append([MeshKit.sphere(.009, 5, 3), m * _at(Vector3(cos(a) * rr, sin(a) * rr, .095)), "stem"])
	acc.append([MeshKit.sphere(.15, 10, 5), m * _at(Vector3(0, 0, -.06), Vector3.ZERO, Vector3(1, 1, .3)), "leaf"])
	var skirt := [[_lathe([[.05, .68], [.085, .72], [.05, .78]], 12), Transform3D(), "leaf"]]
	var low := _extrude(_leaf_poly(.27, .095), .012, 0.0)
	var high := _extrude(_leaf_poly(.22, .075), .012, 0.0)
	for k in 9:                                     # lotus petals rising from the hem, pointed, overlapping
		var a := TAU * k / 9.0
		skirt.append([low, _at(Vector3(sin(a) * .342, .085, cos(a) * .342), Vector3(-.47, a, 0), 1.0, true), "petal2"])
	for k in 7:
		var a := TAU * (k + .5) / 7.0
		skirt.append([high, _at(Vector3(sin(a) * .262, .28, cos(a) * .262), Vector3(-.34, a, 0), 1.0, true), "petal"])
	for sx in [-1.0, 1.0]:
		skirt.append([_extrude(_leaf_poly(.27, .08), .018, 0.0), _at(Vector3(sx * .06, .64, .03), Vector3(.1, 0, sx * -1.15)), "leaf"])
	skirt.append([MeshKit.torus(.372, .016, 30, 4), _at(Vector3(0, .05, 0)), "~gold"])
	return {body = [[_lathe(BELL), Transform3D()]], head = [], body_acc = skirt, head_acc = acc}

## Ice Crystal: a faceted column and gem head, a crown of tall shards, a frozen foot; the shards catch the light.
static func _skin_ice() -> Dictionary:
	var acc := [[_octa(.082), _at(Vector3(0, 1.005, 0), Vector3(0, .4, 0), Vector3(1, 1.75, 1)), "~frost"]]
	for k in 6:
		var a := TAU * k / 6.0
		var big := k % 2 == 0
		acc.append([_octa(.058 if big else .045), _at(Vector3(sin(a) * .105, .945 if big else .92, cos(a) * .105), Vector3(.5, a, 0), Vector3(1, 2.2 if big else 1.8, 1), true), "~frost"])
	var foot := [[_lathe([[.39, .002], [.395, .02], [.37, .055], [.3, .075]], 8), Transform3D(), "~frost"]]
	for k in 12:
		var a := TAU * k / 12.0
		foot.append([_octa(.05 if k % 2 else .066), _at(Vector3(sin(a) * .29, .14 if k % 2 else .17, cos(a) * .29), Vector3(.42, a, 0), Vector3(1, 2.0 if k % 2 else 2.8, 1), true), "~frost"])
	return {body = [[_flat(MeshKit.lathe(_pts(COLUMN), 8)), Transform3D()]], head = [[_ico(.2), _at(Vector3(0, .78, 0), Vector3.ZERO, Vector3(1, 1.08, 1))]], body_acc = foot, head_acc = acc}

## A face's eye on a head centred at c: the white, the pupil and a shine, yaw round the head, pitch above its middle.
static func _eye(c: Vector3, r: float, yaw: float, pitch: float, size: float, iris := "dark") -> Array:
	var p := _sph(c, r, yaw, pitch)
	var rot := Vector3(-pitch, yaw, 0)
	var mk := _at(p, rot, 1.0, true)
	return [
		[MeshKit.sphere(size, 8, 5), mk * _at(Vector3.ZERO, Vector3.ZERO, Vector3(1, 1.14, .4)), "white"],
		[MeshKit.sphere(size * .68, 8, 5), mk * _at(Vector3(0, -size * .05, size * .24), Vector3.ZERO, Vector3(1, 1.12, .4)), iris],
		[MeshKit.sphere(size * .24, 6, 4), mk * _at(Vector3(size * .24, size * .3, size * .47)), "white"],
	]

## The point at yaw (round y, 0 = the front +z) and pitch (up) on a sphere of radius r about c.
static func _sph(c: Vector3, r: float, yaw: float, pitch: float) -> Vector3:
	return c + r * Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))

## Pirate: a captain. A tricorn with a skull, an eye patch, a black beard, a coat with gold buttons and epaulettes.
static func _skin_pirate() -> Dictionary:
	var y := .8
	var c := Vector3(0, y, 0)
	var f := _at(Vector3(0, y + .085, .08), Vector3(-.2, 0, 0), Vector3(1.18, 1.1, 1))
	var flap := _crescent()
	var rim := PackedVector2Array()
	for p in flap:
		rim.append(Vector2(p.x * 1.05, .02 + (p.y - .02) * 1.1))
	var acc := [
		[_patch(.205, 0.0, TAU, 0.0, PI / 2.0, 12, 4), _at(Vector3(0, y + .05, -.01), Vector3.ZERO, Vector3(1.02, .95, 1.02)), "felt"],
		[MeshKit.cylinder(.27, .27, .022, 22), _at(Vector3(0, y + .065, -.01), Vector3.ZERO, Vector3(1.2, 1, .9)), "felt"],
		[MeshKit.torus(.272, .009, 18, 3), _at(Vector3(0, y + .078, -.01), Vector3.ZERO, Vector3(1.2, 1, .9)), "~gold"],
		[_extrude(flap, .03, 0.0), f * _at(Vector3(0, 0, .012)), "felt"],
		[_extrude(rim, .02, 0.0), f * _at(Vector3(0, 0, .006)), "~gold"],
		[MeshKit.sphere(.05, 10, 6), f * _at(Vector3(0, .125, .034), Vector3.ZERO, Vector3(1, .95, .4)), "white"],
		[MeshKit.sphere(.012, 5, 3), f * _at(Vector3(-.018, .13, .052)), "dark"],
		[MeshKit.sphere(.012, 5, 3), f * _at(Vector3(.018, .13, .052)), "dark"],
	]
	for sx in [-1.0, 1.0]:
		acc.append([MeshKit.cylinder(.009, .009, .13, 4), f * _at(Vector3(0, .1, .03), Vector3(0, 0, sx * 1.05)), "white"])
	acc.append_array(_eye(c, .2, .4, .0, .054))
	acc.append([MeshKit.sphere(.06, 8, 5), _at(_sph(c, .197, -.4, .0), Vector3(0, -.4, 0), Vector3(1, 1, .3), true), "felt"])
	acc.append([MeshKit.torus(.203, .009, 16, 3), _at(c + Vector3(0, .012, 0), Vector3(.1, 0, .22)), "felt"])
	acc.append([MeshKit.sphere(.11, 10, 6), _at(c + Vector3(0, -.15, .115), Vector3(.3, 0, 0), Vector3(1.05, .78, .45)), "felt"])
	acc.append([MeshKit.sphere(.055, 8, 5), _at(c + Vector3(-.05, -.075, .18), Vector3(0, 0, -.45), Vector3(.95, .36, .35)), "felt"])
	acc.append([MeshKit.sphere(.055, 8, 5), _at(c + Vector3(.05, -.075, .18), Vector3(0, 0, .45), Vector3(.95, .36, .35)), "felt"])
	acc.append([_tube([[c + Vector3(-.035, -.115, .19), .007], [c + Vector3(0, -.13, .205), .007], [c + Vector3(.04, -.11, .19), .007]], 3), Transform3D(), "white"])
	var body_acc := [
		[_lathe([[_r_at(BELL, .18) + .012, .18], [_r_at(BELL, .24) + .012, .24]], 24), Transform3D(), "belt"],
		[MeshKit.cylinder(.05, .05, .018, 12), _on_surf(BELL, .21, 0.0, .012, PI / 2.0 - .35), "~gold"],
		[MeshKit.torus(.372, .016, 30, 4), _at(Vector3(0, .052, 0)), "~gold"],
		[_lathe([[.11, .56], [.155, .55], [.17, .62], [.13, .69]], 18), Transform3D(), "white"],
	]
	for k in 3:
		var dy := .31 + k * .075
		body_acc.append([MeshKit.sphere(.019, 6, 4), _on_surf(BELL, dy, 0.0, .006), "~gold"])
	for sx in [-1.0, 1.0]:
		body_acc.append([MeshKit.sphere(.075, 10, 6), _at(Vector3(sx * .185, .55, 0), Vector3(0, 0, sx * -.5), Vector3(1.1, .55, 1.1)), "~gold"])
	return {body = [[_lathe(BELL), Transform3D()]], head = [[MeshKit.sphere(.2, 16, 10), _at(c), "skin"]], body_acc = body_acc, head_acc = acc}

## The tricorn's front flap: a crescent with pointed ends.
static func _crescent() -> PackedVector2Array:
	var out := PackedVector2Array()
	for c: Array in [[Vector2(-.29, .01), Vector2(-.22, .21), Vector2(0, .215)], [Vector2(0, .215), Vector2(.22, .21), Vector2(.29, .01)], [Vector2(.29, .01), Vector2(0, .09), Vector2(-.29, .01)]]:
		_bezier(out, c[0], c[1], c[2], 8)
	out.remove_at(out.size() - 1)
	return out

## Robo Bot: a friendly robot: glowing eyes and smile on a dark screen, silver joints, an antenna, a heart in its chest.
static func _skin_robo() -> Dictionary:
	var y := .82
	var c := Vector3(0, y, 0)
	var sc := Vector3(1.2, .98, 1.05)
	var body := [[_lathe(FOOT, 26), Transform3D()], [_lathe(SUIT, 24), Transform3D()]]
	var body_acc := [
		[MeshKit.torus(.372, .018, 30, 4), _at(Vector3(0, .05, 0)), "~silver"],
		[_lathe([[.306, .1], [.312, .115], [.306, .135]], 24), Transform3D(), "~silver"],
		[_lathe([[.11, .6], [.16, .625], [.13, .67], [.08, .69]], 18), Transform3D(), "~silver"],
		[MeshKit.cylinder(.09, .09, .016, 16), _on_surf(SUIT, .34, 0.0, .002, PI / 2.0 - .15), "dark"],
		[MeshKit.torus(.09, .01, 18, 4), _on_surf(SUIT, .34, 0.0, .012, PI / 2.0 - .15), "~silver"],
		[_extrude(_heart(.05), .012, 0.0), _on_surf(SUIT, .34, 0.0, .016, -.15), "glow"],
	]
	for sx in [-1.0, 1.0]:
		body_acc.append([MeshKit.sphere(.082, 12, 7), _at(Vector3(sx * .3, .42, 0), Vector3.ZERO, Vector3(.9, 1.2, 1)), "~silver"])
	var acc := [
		[MeshKit.sphere(.2, 20, 12), _at(c, Vector3.ZERO, sc), "white"],
		[_patch(.205, PI / 2.0 - 1.08, PI / 2.0 + 1.08, .85, 2.05, 14, 6), _at(c, Vector3.ZERO, sc), "dark"],
		[MeshKit.cylinder(.012, .012, .08, 5), _at(c + Vector3(0, .225, 0)), "~silver"],
		[MeshKit.sphere(.04, 10, 6), _at(c + Vector3(0, .285, 0)), "glow"],
		[MeshKit.sphere(.012, 5, 3), _at(c + Vector3(-.012, .3, .03)), "white"],
		[MeshKit.cylinder(.05, .058, .018, 12), _at(c + Vector3(0, .196, 0)), "~silver"],
	]
	for sx in [-1.0, 1.0]:
		var ph: float = sx * .4
		acc.append([MeshKit.sphere(.05, 10, 6), _at(Vector3(sin(ph) * .2 * sc.x, y + .03, cos(ph) * .2 * sc.z) * Vector3(1, 1, 1.02), Vector3(0, ph, 0), Vector3(1, 1.25, .25), true), "glow"])
		acc.append([MeshKit.sphere(.014, 5, 3), _at(Vector3(sin(ph) * .208 * sc.x - .012, y + .05, cos(ph) * .208 * sc.z + .012)), "white"])
		acc.append([MeshKit.cylinder(.068, .068, .05, 14), _at(Vector3(sx * .245, y, 0), Vector3(0, 0, PI / 2.0)), "~silver"])
		acc.append([MeshKit.cylinder(.036, .036, .054, 10), _at(Vector3(sx * .25, y, 0), Vector3(0, 0, PI / 2.0)), "tint3"])
	var smile := []
	for k in 7:
		var t := lerpf(-.55, .55, k / 6.0)
		smile.append([Vector3(sin(t) * .208 * sc.x, y - .075 - cos(t * 2.4) * .022, cos(t) * .208 * sc.z), .009])
	acc.append([_tube(smile, 4), Transform3D(), "glow"])
	return {body = body, head = [], body_acc = body_acc, head_acc = acc}

## Little Wizard: a real wizard: a long white beard, a big crooked starry hat, gold on the robe.
static func _skin_wizard() -> Dictionary:
	var y := .73
	var c := Vector3(0, y, 0)
	var up := .05                                  # the hat sits this far above the brows, tipped back
	var tip := _at(Vector3.ZERO, Vector3(-.14, 0, 0))
	tip.origin = Vector3(0, y + up, 0) - tip.basis * Vector3(0, y + up, 0)
	var bend := [[Vector3(0, y + .1 + up, -.005), .185], [Vector3(0, y + .17 + up, -.012), .135], [Vector3(.005, y + .235 + up, -.016), .098], [Vector3(.025, y + .29 + up, -.012), .066], [Vector3(.07, y + .335 + up, 0), .04], [Vector3(.13, y + .352 + up, .012), .022], [Vector3(.18, y + .34 + up, .018), .004]]
	var hat := [[_tube(bend, 14), tip], [_lathe([[0, y + .06 + up], [.17, y + .058 + up], [.3, y + .042 + up], [.31, y + .058 + up], [.28, y + .074 + up], [0, y + .09 + up]], 24), tip]]
	var acc := [
		[MeshKit.sphere(.165, 16, 10), _at(c), "skin"],
		[MeshKit.torus(.19, .022, 20, 3), tip * _at(Vector3(0, y + .118 + up, -.005)), "~gold"],
		[_extrude(_star(.058), .018, 0.0), tip * _at(Vector3(0, y + .125 + up, .19), Vector3(-.1, 0, 0)), "~gold"],
		[_extrude(_star(.042), .014, 0.0), tip * _at(Vector3(-.075, y + .225 + up, .082), Vector3(-.35, -.65, .3)), "star"],
		[_extrude(_star(.028), .012, 0.0), tip * _at(Vector3(.05, y + .285 + up, .055), Vector3(-.5, .5, -.2)), "star"],
		[MeshKit.sphere(.028, 8, 5), tip * _at(Vector3(.185, y + .338 + up, .018)), "~gold"],
		[MeshKit.sphere(.032, 8, 5), _at(c + Vector3(0, -.028, .165)), "skin2"],
		[MeshKit.sphere(.07, 8, 5), _at(c + Vector3(-.052, -.064, .15), Vector3(0, 0, -.32), Vector3(1.05, .4, .4)), "white"],
		[MeshKit.sphere(.07, 8, 5), _at(c + Vector3(.052, -.064, .15), Vector3(0, 0, .32), Vector3(1.05, .4, .4)), "white"],
		[MeshKit.sphere(.05, 6, 4), _at(c + Vector3(-.066, .068, .146), Vector3(0, 0, .25), Vector3(1, .3, .4)), "white"],
		[MeshKit.sphere(.05, 6, 4), _at(c + Vector3(.066, .068, .146), Vector3(0, 0, -.25), Vector3(1, .3, .4)), "white"],
	]
	acc.append_array(_eye(c, .16, .4, .1, .04))
	acc.append_array(_eye(c, .16, -.4, .1, .04))
	var beard := [
		[MeshKit.sphere(.15, 10, 7), _at(Vector3(0, .565, .135), Vector3(.1, 0, 0), Vector3(.95, 1.15, .45)), "white"],
		[MeshKit.sphere(.1, 8, 6), _at(Vector3(0, .42, .19), Vector3(.2, 0, 0), Vector3(.9, 1.25, .45)), "white"],
		[_tube([[Vector3(0, .33, .215), .05], [Vector3(.01, .27, .232), .032], [Vector3(.035, .225, .25), .006]], 6), Transform3D(), "white"],
		[MeshKit.torus(.372, .02, 30, 4), _at(Vector3(0, .05, 0)), "~gold"],
	]
	for st: Array in [[.2, 1.05, .05], [.16, 2.5, .04], [.36, -1.25, .036], [.13, -.5, .036], [.45, 2.1, .032], [.3, .85, .03]]:
		beard.append([_extrude(_star(st[2]), .012, 0.0), _on_surf(ROBE, st[0], st[1], .002), "star"])
	return {body = [[_lathe(ROBE), Transform3D()]], head = hat, body_acc = beard, head_acc = acc}

## Kitty: a whole cat: a big head with ears, a muzzle, whiskers and bright eyes, a bell on its collar, paws and a tail.
static func _skin_kitty() -> Dictionary:
	var y := .79
	var c := Vector3(0, y, 0)
	var sc := Vector3(1.14, .98, 1.0)
	var head := [[MeshKit.sphere(.205, 18, 12), _at(c, Vector3.ZERO, sc)]]
	var acc := []
	for sx in [-1.0, 1.0]:
		var tilt := Basis(Vector3.BACK, -sx * deg_to_rad(24.0)) * Basis.from_scale(Vector3(1, 1, .5))
		var at := c + Vector3(sx * .135, .205, -.01)
		head.append([MeshKit.cylinder(0.0, .1, .17, 10), Transform3D(tilt, at)])
		acc.append([MeshKit.cylinder(0.0, .062, .118, 8), Transform3D(tilt, at + Vector3(sx * -.003, -.012, .03)), "ear"])
		# whiskers
		for k in 2:
			var w: float = .055 * (k - .5)
			acc.append([_tube([[c + Vector3(sx * .1, -.05 + w * .5, .17), .0055], [c + Vector3(sx * .2, -.05 + w, .17), .005], [c + Vector3(sx * .285, -.05 + w * 2.0, .135), .003]], 3), Transform3D(), "cream"])
	acc.append_array(_cat_eye(c, sc, .44))
	acc.append_array(_cat_eye(c, sc, -.44))
	acc.append([MeshKit.sphere(.07, 10, 6), _at(c + Vector3(-.05, -.075, .165), Vector3.ZERO, Vector3(1, .78, .55)), "cream"])
	acc.append([MeshKit.sphere(.07, 10, 6), _at(c + Vector3(.05, -.075, .165), Vector3.ZERO, Vector3(1, .78, .55)), "cream"])
	acc.append([MeshKit.sphere(.022, 8, 5), _at(c + Vector3(0, -.045, .207), Vector3.ZERO, Vector3(1.15, .8, .6)), "pink"])
	acc.append([_tube([[c + Vector3(-.045, -.108, .205), .0055], [c + Vector3(-.02, -.12, .212), .0055], [c + Vector3(0, -.098, .212), .0055], [c + Vector3(.02, -.12, .212), .0055], [c + Vector3(.045, -.108, .205), .0055]], 3), Transform3D(), "dark"])
	for k in 3:                                       # tabby marks on the forehead
		var xk: float = (k - 1) * .05
		acc.append([MeshKit.sphere(.04, 6, 4), _at(_sph(c, .2, xk * 1.1, .85 - absf(xk)), Vector3(-.85, xk, 0), Vector3(.28, 1.05, .22), true), "shade25"])
	var body_acc := [
		[MeshKit.torus(.13, .024, 22, 5), _at(Vector3(0, .625, 0), Vector3(.08, 0, 0)), "collar"],
		[MeshKit.sphere(.044, 12, 8), _at(Vector3(0, .565, .158)), "~gold"],
		[MeshKit.cylinder(.012, .012, .012, 6), _at(Vector3(0, .55, .2), Vector3(PI / 2.0, 0, 0)), "dark"],
	]
	for sx in [-1.0, 1.0]:
		body_acc.append([MeshKit.sphere(.08, 10, 6), _at(Vector3(sx * .11, .062, .285), Vector3.ZERO, Vector3(1, .78, 1.05)), "cream"])
		for k in 3:
			var kx: float = (k - 1) * .036
			body_acc.append([MeshKit.sphere(.011, 5, 3), _at(Vector3(sx * .11 + kx, .085 - absf(kx) * .3, .358)), "ear"])
	var tail := []
	for k in 11:
		var t := k / 10.0
		var a := lerpf(2.7, .95, t)                   # from behind, round the right side to the front, its tip up
		tail.append([Vector3(sin(a) * .335, .05 + t * t * .26, cos(a) * .335), lerpf(.046, .036, t)])
	var tail_end: Vector3 = tail[10][0]
	body_acc.append([_tube(tail, 6), Transform3D(), "shade18"])
	body_acc.append([MeshKit.sphere(.042, 8, 5), _at(tail_end), "cream"])
	return {body = [[_lathe(CHUBBY), Transform3D()]], head = head, body_acc = body_acc, head_acc = acc}

static func _cat_eye(c: Vector3, sc: Vector3, yaw: float) -> Array:
	var p := _sph(Vector3.ZERO, .2, yaw, .1) * sc + c
	var mk := _at(p, Vector3(-.1, yaw, 0), 1.0, true)
	return [
		[MeshKit.sphere(.052, 10, 6), mk * _at(Vector3.ZERO, Vector3.ZERO, Vector3(1, 1.15, .35)), "lime"],
		[MeshKit.sphere(.04, 8, 6), mk * _at(Vector3(0, 0, .012), Vector3.ZERO, Vector3(.52, 1.3, .35)), "dark"],
		[MeshKit.sphere(.013, 5, 3), mk * _at(Vector3(.013, .022, .024)), "white"],
	]

## Space Explorer: a white helmet with a gold mirror visor, a backpack, a chest pack with lights and a badge.
static func _skin_space() -> Dictionary:
	var y := .82
	var c := Vector3(0, y, 0)
	var body := [[_lathe(FOOT, 26), Transform3D()], [_lathe(SUIT, 24), Transform3D()]]
	var body_acc := [
		[_lathe([[.385, .012], [.392, .03], [.39, .055], [.372, .085], [.345, .1]], 26), Transform3D(), "white"],
		[MeshKit.torus(.306, .012, 30, 4), _at(Vector3(0, .2, 0)), "white"],
		[_lathe([[.15, .6], [.21, .595], [.215, .635], [.15, .665], [.08, .68]], 22), Transform3D(), "~silver"],
		[MeshKit.cylinder(.098, .098, .03, 14), _on_surf(SUIT, .36, 0.0, .004, PI / 2.0 - .2) * _at(Vector3.ZERO, Vector3.ZERO, Vector3(1, 1, .72)), "white"],
		[MeshKit.sphere(.016, 6, 4), _on_surf(SUIT, .385, -.07, .03), "cherry"],
		[MeshKit.sphere(.016, 6, 4), _on_surf(SUIT, .385, .0, .03), "lemon"],
		[MeshKit.sphere(.016, 6, 4), _on_surf(SUIT, .385, .07, .03), "lime"],
		[MeshKit.cylinder(.012, .012, .1, 4), _on_surf(SUIT, .32, 0.0, .03, PI / 2.0 - .2) * _at(Vector3.ZERO, Vector3(0, 0, PI / 2.0), Vector3(1, 1, .4)), "dark"],
		[MeshKit.sphere(.16, 10, 6), _at(Vector3(0, .4, -.27), Vector3.ZERO, Vector3(1, 1.25, .5)), "white"],
		[_extrude(_star(.045), .012, 0.0), _on_surf(SUIT, .28, 1.0, .004), "~gold"],
	]
	var acc := [
		[MeshKit.sphere(.245, 24, 14), _at(c), "white"],
		[_patch(.25, PI / 2.0 - .98, PI / 2.0 + .98, .68, 1.92, 16, 8), _at(c, Vector3.ZERO, Vector3(1, 1, 1.02)), "~visor"],
		[MeshKit.torus(.218, .016, 26, 4), _at(c + Vector3(0, 0, .065), Vector3(PI / 2.0, 0, 0), Vector3(1.05, 1, 1.02)), "~silver"],
		[MeshKit.sphere(.04, 8, 5), _at(_sph(c, .248, -.42, .42), Vector3(-.42, -.42, .5), Vector3(1.6, .7, .3), true), "white"],
	]
	for sx in [-1.0, 1.0]:
		acc.append([MeshKit.cylinder(.066, .066, .05, 14), _at(Vector3(sx * .245, y, 0), Vector3(0, 0, PI / 2.0)), "~silver"])
		acc.append([MeshKit.sphere(.018, 6, 4), _at(Vector3(sx * .275, y, 0)), "cherry"])
	return {body = body, head = [], body_acc = body_acc, head_acc = acc}

## Teacup: fine china: gold rim, band, handle and saucer edge, a heart drawn in the froth.
static func _skin_teacup() -> Dictionary:
	var handle := []
	for k in 11:
		var t := lerpf(-1.15, 1.75, k / 10.0)
		handle.append([Vector3(.285 + cos(t) * .085, .39 + sin(t) * .1, 0), .021])
	var acc := [
		[_lathe(FROTH, 26), Transform3D(), "tint35"],
		[_extrude(_heart(.1), .006, 0.0), _at(Vector3(0, .702, .012), Vector3(-PI / 2.0 + .08, 0, 0)), "cream"],
		[_lathe([[.3, .615], [.325, .63], [.327, .643], [.308, .652], [.292, .64]], 30), Transform3D(), "~gold"],
		[_lathe([[.2, .25], [.208, .265], [.208, .29], [.218, .305]], 26), Transform3D(), "~gold"],
		[MeshKit.torus(.37, .014, 30, 4), _at(Vector3(0, .032, 0)), "~gold"],
		[_lathe([[.178, .068], [.176, .08], [.158, .092]], 18), Transform3D(), "~gold"],
		[_tube(handle, 7), Transform3D(), "~gold"],
	]
	for k in 12:
		var a := TAU * k / 12.0
		var yy := .435
		var rr := _r_at(CUP, yy) + .002
		acc.append([_extrude(_heart(.024), .006, 0.0) if k % 2 == 0 else MeshKit.sphere(.011, 6, 4), _at(Vector3(sin(a) * rr, yy, cos(a) * rr), Vector3(-.32, a, 0), 1.0, true), "~gold"])
	return {body = [[_lathe(CUP, 28), Transform3D()]], head = [], body_acc = acc, head_acc = []}

## Dragon: a snout, slit eyes and nostrils, swept gold horns, a crest down the back, wings, a pale belly and a tail.
static func _skin_dragon() -> Dictionary:
	var y := .8
	var c := Vector3(0, y, 0)
	var head := [
		[MeshKit.sphere(.185, 20, 12), _at(c), SOLID_UV],
		[MeshKit.sphere(.125, 14, 8), _at(c + Vector3(0, -.05, .145), Vector3.ZERO, Vector3(1.05, .78, 1.05)), SOLID_UV],
	]
	var acc := []
	for sx in [-1.0, 1.0]:
		acc.append([_tube([[c + Vector3(sx * .1, .14, -.04), .046], [c + Vector3(sx * .16, .2, -.09), .036], [c + Vector3(sx * .185, .27, -.14), .022], [c + Vector3(sx * .175, .335, -.18), .003]], 7), Transform3D(), "~gold"])
		acc.append([_extrude(_leaf_poly(.15, .05), .012, 0.0), _at(c + Vector3(sx * .165, .03, -.03), Vector3(0, sx * .3, -sx * 1.25)), "tint28"])
		var e := _sph(c, .176, sx * .5, .22)
		var mk := _at(e, Vector3(-.22, sx * .5, 0), 1.0, true)
		acc.append([MeshKit.sphere(.05, 10, 6), mk * _at(Vector3.ZERO, Vector3(0, 0, sx * -.25), Vector3(1.1, .95, .35)), "lemon"])
		acc.append([MeshKit.sphere(.036, 8, 5), mk * _at(Vector3(0, 0, .012), Vector3.ZERO, Vector3(.4, 1.25, .35)), "dark"])
		acc.append([MeshKit.sphere(.012, 5, 3), mk * _at(Vector3(.012, .018, .021)), "white"])
		acc.append([MeshKit.sphere(.06, 8, 5), _at(_sph(c, .18, sx * .5, .47), Vector3(-.47, sx * .5, sx * -.32), Vector3(1.15, .32, .4), true), "shade25"])
		acc.append([MeshKit.sphere(.014, 6, 4), _at(c + Vector3(sx * .04, -.012, .252), Vector3.ZERO, Vector3(1, .8, .5)), "dark"])
		acc.append([MeshKit.cylinder(0.0, .016, .036, 4), _at(c + Vector3(sx * .055, -.105, .232), Vector3(PI, 0, 0)), "white"])
	acc.append([_tube([[c + Vector3(-.095, -.075, .205), .005], [c + Vector3(-.03, -.092, .252), .006], [c + Vector3(.03, -.092, .252), .006], [c + Vector3(.095, -.075, .205), .005]], 3), Transform3D(), "dark"])
	for k in 4:
		var th: float = [.15, .6, 1.05, 1.5][k]
		acc.append([MeshKit.cylinder(0.0, .058 - k * .006, .1, 4), _at(Vector3(0, y + cos(th) * .185, -sin(th) * .185), Vector3(-th, 0, 0), Vector3(.32, 1, 1)), "~gold"])
	var wing := PackedVector2Array([Vector2(0, 0), Vector2(.015, .08)])
	_bezier(wing, Vector2(.015, .08), Vector2(.09, .24), Vector2(.235, .25), 6)
	_bezier(wing, Vector2(.235, .25), Vector2(.2, .16), Vector2(.235, .1), 3)
	_bezier(wing, Vector2(.235, .1), Vector2(.17, .12), Vector2(.15, .03), 3)
	_bezier(wing, Vector2(.15, .03), Vector2(.1, .07), Vector2(.065, -.03), 3)
	_bezier(wing, Vector2(.065, -.03), Vector2(.03, 0), Vector2(.0, 0), 3)
	wing.remove_at(wing.size() - 1)
	var w := _extrude(wing, .014, 0.0)
	var body_acc := [
				[_octa(.046), _on_surf(BELL, .4, 0.0, .022, -.3) * Transform3D(Basis.from_scale(Vector3(.85, 1.25, .5)), Vector3.ZERO), "~gold"],
		[MeshKit.torus(.372, .016, 30, 4), _at(Vector3(0, .05, 0)), "~gold"],
		[MeshKit.sphere(.21, 14, 8), _at(Vector3(0, .36, .125), Vector3(-.1, 0, 0), Vector3(.72, 1.35, .45)), "tint35"],
	]
	for sx in [-1.0, 1.0]:
		body_acc.append([w, _at(Vector3(sx * .12, .42, -.1), Vector3(0, sx * .28, 0), Vector3(sx * 1.05, 1.05, 1)), "tint28"])
		body_acc.append([_tube([[Vector3(sx * .12, .42, -.1), .012], [Vector3(sx * .19, .58, -.125), .012], [Vector3(sx * .31, .68, -.17), .005]], 4), Transform3D(), "shade25"])
	for k in 5:
		var yy := .16 + k * .105
		var rr := _r_at(BELL, yy)
		body_acc.append([MeshKit.cylinder(0.0, .056, .1, 4), _at(Vector3(0, yy, -rr - .012), Vector3(-1.0, 0, 0), Vector3(.3, 1, 1)), "~gold"])
	var tail := []
	for k in 11:
		var t := k / 10.0
		var a := lerpf(3.0, 5.0, t)
		tail.append([Vector3(sin(a) * .335, .05 + t * .06, cos(a) * .335), lerpf(.055, .012, t)])
	var tip: Vector3 = tail[10][0]
	body_acc.append([_tube(tail, 7), Transform3D(), "shade18"])
	body_acc.append([_octa(.04), _at(tip + Vector3(0, .012, 0), Vector3(0, .7, 0), Vector3(1, .5, 1.5)), "~gold"])
	return {body = [[_lathe(BELL), Transform3D()]], head = head, body_acc = body_acc, head_acc = acc}


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
static func _lathe(profile: Array, segments := 26) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.create_from(MeshKit.lathe(_pts(profile), segments), 0)
	st.index()
	return st.commit()

## A tube along a path of [point, radius], with its ends closed: horns, tails, whiskers, a bent hat, a swirl of frosting.
static func _tube(path: Array, sides := 8) -> ArrayMesh:
	var vs := PackedVector3Array()
	var ns := PackedVector3Array()
	var ix := PackedInt32Array()
	var n := path.size()
	var side := Vector3.ZERO
	for j in n:
		var p: Vector3 = path[j][0]
		var t: Vector3 = ((path[mini(j + 1, n - 1)][0] as Vector3) - (path[maxi(j - 1, 0)][0] as Vector3)).normalized()
		if j == 0:
			side = t.cross(Vector3.UP if absf(t.y) < .9 else Vector3.RIGHT).normalized()
		side = (side - t * side.dot(t)).normalized()         # carried along the path, so the tube doesn't twist
		var up := t.cross(side)
		for k in sides:
			var a := TAU * k / sides
			var d := side * cos(a) + up * sin(a)
			vs.append(p + d * float(path[j][1]))
			ns.append(d)
	var tri := func(a: int, b: int, c: int) -> void:
		var flip := (vs[c] - vs[a]).cross(vs[b] - vs[a]).dot(ns[a] + ns[b] + ns[c]) < 0.0   # (Godot: clockwise front faces)
		ix.append_array([a, c, b] if flip else [a, b, c])
	for j in n - 1:
		for k in sides:
			var a := j * sides + k
			var b := j * sides + (k + 1) % sides
			var c := a + sides
			var d := b + sides
			tri.call(a, b, c)
			tri.call(b, d, c)
	for e: int in [0, n - 1]:                             # the ends
		if float(path[e][1]) > 0.001:
			var mid := vs.size()
			var t: Vector3 = ((path[mini(e + 1, n - 1)][0] as Vector3) - (path[maxi(e - 1, 0)][0] as Vector3)).normalized() * (1.0 if e > 0 else -1.0)
			vs.append(path[e][0])
			ns.append(t)
			for k in sides:
				var a := e * sides + k
				var b := e * sides + (k + 1) % sides
				var flip := (vs[b] - vs[mid]).cross(vs[a] - vs[mid]).dot(t) < 0.0
				ix.append_array([mid, b, a] if flip else [mid, a, b])
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

## A flat outline given thickness with a rounded-off edge (a chamfer of `bevel`): the knight's head, its mane.
static func _bevelled(poly: PackedVector2Array, depth: float, bevel: float) -> ArrayMesh:
	var n := poly.size()
	var sign_ := 1.0 if _area(poly) > 0.0 else -1.0
	var out2 := PackedVector2Array()
	var inner := PackedVector2Array()
	for i in n:
		var e0 := poly[i] - poly[posmod(i - 1, n)]
		var e1 := poly[(i + 1) % n] - poly[i]
		var o := (Vector2(e0.y, -e0.x).normalized() + Vector2(e1.y, -e1.x).normalized()).normalized() * sign_
		out2.append(o)
		inner.append(poly[i] - o * bevel)
	var vs := PackedVector3Array()
	var ns := PackedVector3Array()
	var tri := func(a: Vector3, na: Vector3, b: Vector3, nb: Vector3, c: Vector3, nc: Vector3) -> void:
		var flip := (c - a).cross(b - a).dot(na + nb + nc) < 0.0   # (Godot: clockwise front faces)
		vs.append_array([a, c, b] if flip else [a, b, c])
		ns.append_array([na, nc, nb] if flip else [na, nb, nc])
	var hz := depth / 2.0
	var mid := hz - bevel
	var tris := Geometry2D.triangulate_polygon(inner)
	var cap := inner
	if tris.is_empty():                                   # (a tight corner crossed itself: the plain outline)
		tris = Geometry2D.triangulate_polygon(poly)
		cap = poly
	for side: float in [1.0, -1.0]:
		var face := Vector3(0, 0, side)
		for k in range(0, tris.size(), 3):
			var a := cap[tris[k]]
			var b := cap[tris[k + 1]]
			var c := cap[tris[k + 2]]
			tri.call(Vector3(a.x, a.y, side * hz), face, Vector3(b.x, b.y, side * hz), face, Vector3(c.x, c.y, side * hz), face)
		for i in n:
			var j := (i + 1) % n
			var na := Vector3(out2[i].x, out2[i].y, side).normalized()
			var nb := Vector3(out2[j].x, out2[j].y, side).normalized()
			var ia := Vector3(inner[i].x, inner[i].y, side * hz)
			var ib := Vector3(inner[j].x, inner[j].y, side * hz)
			var oa := Vector3(poly[i].x, poly[i].y, side * mid)
			var ob := Vector3(poly[j].x, poly[j].y, side * mid)
			tri.call(ia, na, ib, nb, ob, nb)
			tri.call(ia, na, ob, nb, oa, na)
	for i in n:
		var j := (i + 1) % n
		var na := Vector3(out2[i].x, out2[i].y, 0)
		var nb := Vector3(out2[j].x, out2[j].y, 0)
		var a0 := Vector3(poly[i].x, poly[i].y, mid)
		var b0 := Vector3(poly[j].x, poly[j].y, mid)
		var a1 := Vector3(poly[i].x, poly[i].y, -mid)
		var b1 := Vector3(poly[j].x, poly[j].y, -mid)
		tri.call(a0, na, b0, nb, b1, nb)
		tri.call(a0, na, b1, nb, a1, na)
	var us := PackedVector2Array()
	us.resize(vs.size())
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vs
	arrays[Mesh.ARRAY_NORMAL] = ns
	arrays[Mesh.ARRAY_TEX_UV] = us
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

## One mesh from [mesh, transform, cell] parts, under `outer`: a cell (a colour table key, or a UV) replaces the part's
## UVs, a foil ("~gold") points them at its ramp by each vertex's direction, none keeps them. Mirrored parts get their
## winding flipped so they still face out.
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
		var foil := -1
		if p.size() > 2:
			foil = FOILS.find(p[2]) if p[2] is String else -1
			if foil < 0:
				uv = p[2] if p[2] is Vector2 else _cell(str(p[2]))
		for i in pv.size():
			var nv := (nb * pn[i]).normalized()
			vs.append(xf * pv[i])
			ns.append(nv)
			if foil >= 0:
				us.append(_foil_uv(foil, nv))
			else:
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

## Four sharp points: a glint.
static func _star4(r: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in 8:
		var a := TAU * k / 8.0
		var rr := r * .2 if k % 2 else r
		out.append(Vector2(sin(a) * rr, cos(a) * rr))
	return out

## A heart s tall from its middle.
static func _heart(s: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	_bezier(out, Vector2(0, -s), Vector2(-s * 1.3, -s * .1), Vector2(-s * .8, s * .55), 5)
	_bezier(out, Vector2(-s * .8, s * .55), Vector2(-s * .42, s * 1.05), Vector2(0, s * .42), 5)
	_bezier(out, Vector2(0, s * .42), Vector2(s * .42, s * 1.05), Vector2(s * .8, s * .55), 5)
	_bezier(out, Vector2(s * .8, s * .55), Vector2(s * 1.3, -s * .1), Vector2(0, -s), 5)
	if out[0].distance_to(out[out.size() - 1]) < 0.0001:
		out.remove_at(out.size() - 1)
	return out

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
	var cell := float(PALETTE_SIZE) / PALETTE_CELLS
	return Vector2((i % PALETTE_CELLS + 0.5) * cell, (i / PALETTE_CELLS + 0.5) * cell) / PALETTE_SIZE

static func _cell_keys() -> Array:
	return INKS.keys() + ["eye", "tint3", "tint5", "tint28", "tint35", "shade18", "shade25", "shade38", "petal", "petal2", "mid", "star", "collar"]

## The height of ramp `foil` in the table: the rows under the cells, shared out.
static func _foil_v(foil: int) -> float:
	var top := PALETTE_ROWS * PALETTE_SIZE / PALETTE_CELLS
	var row := float(PALETTE_SIZE - top) / FOILS.size()
	return (top + (foil + 0.5) * row) / PALETTE_SIZE

## Where a surface facing `n` reads its ramp: from below (0) through the horizon to the sky (1), a little off to the side.
static func _foil_uv(foil: int, n: Vector3) -> Vector2:
	return Vector2(clampf(0.5 + 0.5 * (n.y * 0.86 + n.x * 0.18), 0.02, 0.98), _foil_v(foil))

## A foil's stops: [position, colour] from below to the sky, a bright bounce and a dark horizon like polished metal.
static func _foil_stops(foil: String, seat: Color) -> Array:
	match foil:
		"~gold":
			return [[0.0, Color("#7a4310")], [.26, Color("#d68c1c")], [.42, Color("#ffeb9e")], [.5, Color("#a8650f")], [.62, Color("#f2b632")], [.82, Color("#ffe279")], [1.0, Color("#fffbe0")]]
		"~silver":
			return [[0.0, Color("#5f6775")], [.28, Color("#c3ccd8")], [.43, Color("#ffffff")], [.51, Color("#6e7888")], [.68, Color("#d8e0ea")], [1.0, Color("#ffffff")]]
		"~gem":
			return [[0.0, seat.lerp(Color.BLACK, .55)], [.3, seat.lerp(Color.BLACK, .15)], [.45, seat.lerp(Color.WHITE, .55)], [.55, seat.lerp(Color.BLACK, .3)], [.75, seat.lerp(Color.WHITE, .25)], [1.0, Color.WHITE]]
		"~frost":
			return [[0.0, seat.lerp(Color.BLACK, .08)], [.3, seat.lerp(Color.WHITE, .38)], [.47, Color.WHITE], [.56, seat.lerp(Color.WHITE, .2)], [.8, seat.lerp(Color.WHITE, .7)], [1.0, Color.WHITE]]
	return [[0.0, Color("#3c1d08")], [.28, Color("#b4620f")], [.45, Color("#ffd878")], [.52, Color("#6e3a0c")], [.7, Color("#e39a25")], [.88, Color("#ffe9a6")], [1.0, Color("#fff8df")]]

## The colour table for a seat colour: INKS, the shades of the seat and the foil ramps. Made once per colour, no mipmaps
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
		petal = Color(["#ff86b0", "#8be07a", "#ffd84a", "#5fb0ff"][c]), petal2 = Color(["#ffc2d6", "#c9f2be", "#fff0a6", "#b4d9ff"][c]),
		mid = Color("#e5484d" if c == 2 else "#ffd23f"), star = Color("#ff8a3d" if c == 2 else "#ffd84a"),
		collar = Color("#ffd23f" if c == 0 else "#e8213f")}
	var keys := _cell_keys()
	var cell := PALETTE_SIZE / PALETTE_CELLS
	var img := Image.create_empty(PALETTE_SIZE, PALETTE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	for i in keys.size():
		var k: String = keys[i]
		var col: Color = cols[k] if cols.has(k) else Color(str(INKS[k]))
		img.fill_rect(Rect2i(i % PALETTE_CELLS * cell, i / PALETTE_CELLS * cell, cell, cell), col)
	var top := PALETTE_ROWS * cell
	var row := (PALETTE_SIZE - top) / FOILS.size()
	for f in FOILS.size():
		var stops := _foil_stops(FOILS[f], seat)
		for x in PALETTE_SIZE:
			var u := (x + 0.5) / PALETTE_SIZE
			var col: Color = stops[0][1]
			for k in stops.size() - 1:
				if u >= float(stops[k][0]):
					col = (stops[k][1] as Color).lerp(stops[k + 1][1], clampf((u - float(stops[k][0])) / (float(stops[k + 1][0]) - float(stops[k][0])), 0.0, 1.0))
			img.fill_rect(Rect2i(x, top + f * row, 1, row), col)
	var t := ImageTexture.create_from_image(img)
	_tex[key] = t
	return t


# ---------- the themed bodies' textures ----------

## Candy stripes or scales over the seat colour: u round the pawn, v its height (plain above SOLID_V). 96 x 96.
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


# =====================================================================================================================
# Finish textures (one small texture per finish and colour, made once and kept)
# =====================================================================================================================

## A finish's surface in `color`: the themed bodies' (_body_texture), or the marble / glitter one (seamless round the pawn, mipmapped): marble 96 x 96 (thin veins over a
## faint cloud), glitter 96 x 96 (single-pixel specks: a few white or pale gold, more in a light tint, the rest the
## colour a shade deeper so the specks stand out).
static func texture(kind: String, color: Color) -> ImageTexture:
	var key := "%s|%s" % [kind, color.to_html()]
	if _tex.has(key):
		return _tex[key]
	if kind != "marble" and kind != "glitter":
		_tex[key] = _body_texture(kind, color)
		return _tex[key]
	var n := 96
	var lum := PackedByteArray()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	if kind == "marble":
		var noise := FastNoiseLite.new()
		noise.seed = 7
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = 0.022
		noise.fractal_octaves = 3
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
				var w := absf(sin((float(x) / n * 2.0 + float(y) / n) * TAU + v * 4.5))
				var w2 := absf(sin((float(x) / n * 3.0 - float(y) / n * 2.0) * TAU + v * 6.0))
				var k := pow(1.0 - w, 12.0) + pow(1.0 - w2, 22.0) * 0.6
				c = color.lerp(deep, (1.0 - v) * 0.55).lerp(vein, minf(1.0, k * 1.2))
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
