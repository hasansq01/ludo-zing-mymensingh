class_name MeshKit
extends RefCounted
## Procedural meshes shared by the 3D scenes (the web version's rbox(), LatheGeometry and friends).
## 1 unit ≈ 2.5 cm, as in index.html: the board is 15 units, the table top sits at y = -0.31.

static var _cache := {}

## Rounded box (soft toy-like edges), centred on the origin. Cached by size.
## Each face is a grid with extra rows inside the rounded band at its edges; every grid point is pushed out from
## an inner box by the radius, so edges and corners become smooth quarter-cylinders / sphere octants.
static func rbox(w: float, h: float, d: float, r := 0.5, seg := 3) -> ArrayMesh:
	var key := "rbox|%s|%s|%s|%s|%d" % [w, h, d, r, seg]
	if _cache.has(key):
		return _cache[key]
	r = clampf(r, 0.02, minf(w, minf(h, d)) / 2.0 - 0.005)
	var half := Vector3(w, h, d) / 2.0
	var inner := half - Vector3(r, r, r)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := [
		[Vector3.RIGHT, Vector3.BACK, Vector3.UP], [Vector3.LEFT, Vector3.BACK, Vector3.UP],
		[Vector3.UP, Vector3.RIGHT, Vector3.BACK], [Vector3.DOWN, Vector3.RIGHT, Vector3.BACK],
		[Vector3.BACK, Vector3.RIGHT, Vector3.UP], [Vector3.FORWARD, Vector3.RIGHT, Vector3.UP],
	]
	for f in faces:
		var nrm: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var au := _band_coords(absf(u.dot(half)), r, seg)
		var av := _band_coords(absf(v.dot(half)), r, seg)
		var pts := []
		var nrms := []
		var uvs := []
		for b in av:
			for a in au:
				var p: Vector3 = (nrm + u * a + v * b) * half          # point on the plain box face
				var c := p.clamp(-inner, inner)
				var dir := p - c
				dir = dir.normalized() if dir.length() > 0.00001 else nrm
				pts.append(c + dir * r)
				nrms.append(dir)
				uvs.append(Vector2((a + 1.0) / 2.0, (1.0 - b) / 2.0))
		var nu := au.size()
		for j in av.size() - 1:
			for i in nu - 1:
				var i0 := j * nu + i
				_tri(st, pts, nrms, uvs, i0, i0 + 1, i0 + nu + 1)
				_tri(st, pts, nrms, uvs, i0, i0 + nu + 1, i0 + nu)
	var mesh := st.commit()
	_cache[key] = mesh
	return mesh

## Grid coordinates -1..1 along one face axis of half-length hl: seg steps through each rounded band, none between.
static func _band_coords(hl: float, r: float, seg: int) -> Array:
	var out := []
	var inner := (hl - r) / hl
	for k in seg + 1:
		out.append(-1.0 + (1.0 - inner) * float(k) / seg)
	for k in range(seg, -1, -1):
		out.append(1.0 - (1.0 - inner) * float(k) / seg)
	return out

## One triangle, wound so its front faces along the normals (Godot: clockwise front faces).
static func _tri(st: SurfaceTool, pts: Array, nrms: Array, uvs: Array, a: int, b: int, c: int) -> void:
	var n: Vector3 = nrms[a] + nrms[b] + nrms[c]
	var pa: Vector3 = pts[a]
	if (pts[c] - pa).cross(pts[b] - pa).dot(n) < 0:
		var t := b; b = c; c = t
	for q in [a, b, c]:
		st.set_normal(nrms[q])
		st.set_uv(uvs[q])
		st.add_vertex(pts[q])

static func _tri_oriented(st: SurfaceTool, pts: Array, nrms: Array, uvs: Array, a: int, b: int, c: int, n: Vector3) -> void:
	var pa: Vector3 = pts[a]
	var cr: Vector3 = (pts[c] - pa).cross(pts[b] - pa)
	if cr.length_squared() < 1e-12:
		return                                     # degenerate (on the axis)
	if cr.dot(n) < 0:
		var t := b; b = c; c = t
	for q in [a, b, c]:
		st.set_normal(nrms[q])
		st.set_uv(uvs[q])
		st.add_vertex(pts[q])

## Lathe (surface of revolution) from a profile of (radius, height) points, like THREE.LatheGeometry.
## Normals come from the profile's tangent, pointing away from the axis on the outside.
static func lathe(profile: PackedVector2Array, segments := 36) -> ArrayMesh:
	var key := "lathe|%s|%d" % [str(profile), segments]
	if _cache.has(key):
		return _cache[key]
	var rows := profile.size()
	var n2 := []                                  # 2D normal (radial, up) per profile point
	for j in rows:
		var t := profile[mini(j + 1, rows - 1)] - profile[maxi(j - 1, 0)]
		n2.append(Vector2(t.y, -t.x).normalized())
	var pts := []
	var nrms := []
	var uvs := []
	for k in segments + 1:
		var a := TAU * k / segments
		for j in rows:
			var p := profile[j]
			pts.append(Vector3(cos(a) * p.x, p.y, sin(a) * p.x))
			nrms.append(Vector3(cos(a) * n2[j].x, n2[j].y, sin(a) * n2[j].x))
			uvs.append(Vector2(float(k) / segments, p.y))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in segments:
		for j in rows - 1:
			var i0 := k * rows + j
			var i1 := (k + 1) * rows + j
			if profile[j].x < 0.0001 and profile[j + 1].x < 0.0001:
				continue
			# orient by this segment's own outward normal (vertex normals are smoothed and blur sharp rims)
			var t := profile[j + 1] - profile[j]
			var sn := Vector2(t.y, -t.x)
			var a := TAU * (k + 0.5) / segments
			var face_n := Vector3(cos(a) * sn.x, sn.y, sin(a) * sn.x)
			_tri_oriented(st, pts, nrms, uvs, i0, i0 + 1, i1 + 1, face_n)
			_tri_oriented(st, pts, nrms, uvs, i0, i1 + 1, i1, face_n)
	var mesh := st.commit()
	_cache[key] = mesh
	return mesh

static func cylinder(top: float, bottom: float, height: float, segs := 32) -> CylinderMesh:
	var key := "cyl|%s|%s|%s|%d" % [top, bottom, height, segs]
	if _cache.has(key):
		return _cache[key]
	var m := CylinderMesh.new()
	m.top_radius = top; m.bottom_radius = bottom; m.height = height; m.radial_segments = segs; m.rings = 1
	_cache[key] = m
	return m

static func sphere(r: float, segs := 24, rings := 16) -> SphereMesh:
	var key := "sph|%s|%d|%d" % [r, segs, rings]
	if _cache.has(key):
		return _cache[key]
	var m := SphereMesh.new()
	m.radius = r; m.height = r * 2; m.radial_segments = segs; m.rings = rings
	_cache[key] = m
	return m

static func torus(radius: float, tube: float, rings := 48, ring_segs := 10) -> TorusMesh:
	var key := "tor|%s|%s|%d" % [radius, tube, rings]
	if _cache.has(key):
		return _cache[key]
	var m := TorusMesh.new()
	m.inner_radius = radius - tube; m.outer_radius = radius + tube; m.rings = rings; m.ring_segments = ring_segs
	_cache[key] = m
	return m

static func plane(w: float, h: float) -> PlaneMesh:
	var key := "pl|%s|%s" % [w, h]
	if _cache.has(key):
		return _cache[key]
	var m := PlaneMesh.new()
	m.size = Vector2(w, h)
	_cache[key] = m
	return m


# ---------- materials ----------

static var _mats := {}

## Matte-to-glossy standard material in an sRGB colour (Godot converts albedo colours to linear itself).
static func mat(color: Color, roughness := 0.55, metallic := 0.0) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [color.to_html(), roughness, metallic]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	_mats[key] = m
	return m

static func tex_mat(tex: Texture2D, roughness := 0.6, uv_scale := Vector2.ONE) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.roughness = roughness
	m.uv1_scale = Vector3(uv_scale.x, uv_scale.y, 1)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m

## Unlit colour (lamp bulbs, flames, the sky in a window).
static func unlit(color: Color, tex: Texture2D = null) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	if tex:
		m.albedo_texture = tex
	return m

static func emissive(color: Color, energy := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m

## Soft round glow texture (white centre fading out), shared by every "bloom" sprite.
static var _soft: GradientTexture2D

static func soft_texture() -> GradientTexture2D:
	if _soft:
		return _soft
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)])
	_soft = GradientTexture2D.new()
	_soft.gradient = g
	_soft.fill = GradientTexture2D.FILL_RADIAL
	_soft.fill_from = Vector2(0.5, 0.5)
	_soft.fill_to = Vector2(1.0, 0.5)
	_soft.width = 128
	_soft.height = 128
	return _soft

## Gentle "bloom": an additive soft billboard around a light source.
static func glow(color: Color, size: float, opacity := 0.5) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = soft_texture()
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.modulate = Color(color, opacity)
	s.pixel_size = size / 128.0
	s.shaded = false
	s.transparent = true
	s.double_sided = true
	s.no_depth_test = false
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # a glow is light, not a sheet that blocks it
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = soft_texture()
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	s.material_override = m
	return s

## Put a mesh instance under parent at a position, with optional rotation (radians) and scale.
static func put(parent: Node3D, mesh: Mesh, material: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE, shadow := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	if material:
		mi.material_override = material
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


# ---------- soft contact shadows ----------
# The GL Compatibility renderer draws a shadow-casting light in its own additive pass and adds that pass in sRGB
# space, not in linear light: over a bright ambient the key spot then lifts every colour towards white (a white
# surface under ambient 0.3 + a shadowed light 0.3 reads 255 instead of 203; tested on 4.7.2, also with HDR 2D).
# So the café's lights cast no real shadows; these soft blobs (alpha-blended darkening, no extra pass, no shadow
# map) stand in for the key spot's shadows under the pawns, cups, board and table, like the web's soft shadow map.

static var _blob_tex := {}
static var _blob_box_tex: ImageTexture

## A soft round shadow (64 x 64, alpha only): flat inside `core` of the radius, then fading smoothly to nothing at
## the rim (core 0: soft all the way from the middle).
static func blob_texture(core := 0.0) -> ImageTexture:
	if not _blob_tex.has(core):
		_blob_tex[core] = _shadow_tex(func(x: float, y: float) -> float: return maxf(Vector2(x, y).length() - core, 0.0) / (1.0 - core))
	return _blob_tex[core]

## A soft square shadow for the board: flat inside 70 % of the half size, fading to nothing at the edge.
static func blob_box_texture() -> ImageTexture:
	if _blob_box_tex == null:
		_blob_box_tex = _shadow_tex(func(x: float, y: float) -> float:
			var q := Vector2(maxf(absf(x) - 0.7, 0.0), maxf(absf(y) - 0.7, 0.0))
			return q.length() / 0.3)
	return _blob_box_tex

## dist(x, y) over -1..1 gives 0 (full shadow) .. 1 (none); the alpha falls off with a smoothstep.
static func _shadow_tex(dist: Callable) -> ImageTexture:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var d: float = dist.call((x + 0.5) / n * 2.0 - 1.0, (y + 0.5) / n * 2.0 - 1.0)
			var a := 1.0 - smoothstep(0.0, 1.0, clampf(d, 0.0, 1.0))
			img.set_pixel(x, y, Color(1, 1, 1, a * a * (3.0 - 2.0 * a)))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

## The material of a contact shadow: unlit, alpha-blended `color`, no depth write, drawn before other see-through
## things (glows, halos) so those stay on top.
static func shadow_mat(tex: Texture2D, color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.albedo_texture = tex
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.disable_fog = true
	m.render_priority = -1
	return m

## A flat soft shadow of size w x d lying on a surface (y up), under parent at pos.
static func contact_shadow(parent: Node3D, w: float, d: float, pos: Vector3, color := Color(0.24, 0.13, 0.07, 0.4), box := false, core := 0.0) -> MeshInstance3D:
	var mi := put(parent, plane(w, d), shadow_mat(blob_box_texture() if box else blob_texture(core), color), pos, Vector3.ZERO, Vector3.ONE, false)
	mi.name = "ContactShadow"
	return mi
