class_name SnakeBite
extends Node3D
## The snake that eats a pawn (SLBoard.slide): a small cartoon head in the snake's colours rises out of the board at
## the painted head, opens its jaws, the pawn hops in, the jaws snap shut (a squash, a ring, a few crumbs) and the
## head sinks back; a bulge in the snake's colour runs down the painted body (SLBoard.snake_body) to the tail, where
## the board pops the pawn back out. Pure presentation.
##
## Built once per board, with the board (~2 ms on a desktop), then reused: the head is ~1.4k triangles in 15 meshes (one
## per colour per moving part), the bulge 5, the ring and crumbs 6 (at most ~1.9k triangles and 21 draws on screen at
## once); all hidden while idle. Materials are SLScenes' toy standard / lambert ones (the scene's own 3D snakes use
## them, so ShaderWarmUp has compiled them) and MeshKit's unlit alpha (the pawn ring's): no new shader compiles
## mid-game. pose() allocates nothing.
##
##   bite.start(path, col, pattern, face, total)   path: the painted body in board space, head first
##   bite.pose(u)                                    u: seconds at speed 1 since the start (0 .. total)
##   bite.finish()                                   hide it all
##
## Head space: +Z the snout, +Y up, one unit = half the head's width; the head is drawn at SIZE board units per unit.

const SIZE := 1.8                    ## head scale (board units per head unit; a square is 1.5: the head is 1.2 squares wide)
const NECK_H := 0.55                 ## the jaw hinge above the neck's base (head units)
const HINGE_Z := -0.12
const PITCH := -0.22                 ## the head looks a little up
const OPEN_UP := -0.95               ## the upper jaw's swing when open (radians; snout up)
const OPEN_DN := 0.34                ## the lower jaw's
const MOUTH := Vector3(0, 0.12, 0.46)   ## where the pawn drops in (hinge space, open)
const DEPTH := (NECK_H + 0.75) * SIZE + 0.15   ## how far below the face the head waits (board units)

## The timeline, in seconds at speed 1 (the board scales it by the speed setting).
const RISE := 0.18                   ## out of the board
const OPEN0 := 0.04                  ## the jaws open ...
const OPEN1 := 0.2
const CHOMP_AT := 0.34               ## ... the pawn is in: snap
const SNAP := 0.06
const SQUASH := 0.16
const SINK0 := 0.5                   ## back into the board
const SINK := 0.16
const BULGE0 := 0.44                 ## the bulge sets off from the head
const POP := 0.24                    ## the pawn's hop out of the tail (the board's part)
const POP_OVERLAP := 0.04            ## the pop starts this long before the bulge reaches the tail
const EXTRA := 0.25                  ## total = the old slide's duration + EXTRA (both times the speed)

const CRUMBS := 5
const CRUMB_DIRS := [Vector3(1, 0, 0.35), Vector3(-1, 0, 0.35), Vector3(0.6, 0, 1), Vector3(-0.6, 0, 1), Vector3(0, 0, 1.2)]
const MOUTH_COL := "#a8324a"
const CHEEK_COL := "#ff9fb0"
const TONGUE_COL := "#e5484d"
const PUPIL_COL := "#2a1d24"
const CREAM := Color(1, 0.957, 0.84)

var pop_at := 0.0                    ## when the pawn starts popping out (u)
var total := 0.0

var _root: Node3D                    # at the head, turned to face
var _riser: Node3D                   # rises, squashes
var _hinge: Node3D
var _upper: Node3D
var _lower: Node3D
var _eyes: Node3D
var _tongue: Node3D
var _disc: MeshInstance3D            # the dark patch the neck comes out of
var _body_parts: Array[MeshInstance3D] = []      # take the snake's colour
var _pat_parts: Array[MeshInstance3D] = []       # the pattern (per pattern mesh)
var _jaw: MeshInstance3D
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _crumbs: Array[MeshInstance3D] = []
var _lead: Node3D                    # the bulge: lead and trailing segments
var _trail: Node3D
var _bulge_mats: Array[MeshInstance3D] = []      # [lead ink, lead body, trail ink, trail body]
var _path := PackedVector3Array()
var _lens := PackedFloat32Array()
var _len := 0.0
var _bulge_dur := 0.3
var _mouth_at := Vector3.ZERO        # board space, open pose
var _tail_at := Vector3.ZERO
var _cursor := 1
var _pattern := "?"

static var _meshes := {}             # name -> ArrayMesh (shared by every board)


func _init() -> void:
	name = "SnakeBite"
	visible = false
	_build()
	_paint(Color(SLBoard.SNAKE_COL[0]), "")            # (every part has its material from the start)

## Pose the head and the bulge for this snake. path: the painted body (board space, head first); face: the way the
## head looks (board space, horizontal); tot: the whole timeline (u).
func start(path: PackedVector3Array, col: Color, pattern: String, face: Vector3, tot: float) -> void:
	_path = path
	_lens.resize(path.size())
	_lens[0] = 0.0
	for j in range(1, path.size()):
		_lens[j] = _lens[j - 1] + path[j].distance_to(path[j - 1])
	_len = _lens[_lens.size() - 1]
	total = tot
	pop_at = maxf(BULGE0 + 0.2, tot - POP)
	_bulge_dur = pop_at + POP_OVERLAP - BULGE0
	_tail_at = path[path.size() - 1]
	_paint(col, pattern)
	_root.position = Vector3(path[0].x, SLBoard.TOP, path[0].z)
	_root.rotation = Vector3(0, atan2(face.x, face.z), 0)
	_riser.scale = Vector3.ONE * SIZE
	_riser.position = Vector3.ZERO
	_hinge.rotation = Vector3(PITCH - 0.12, 0, 0)        # (as pose() has it open)
	_mouth_at = _root.transform * _riser.transform * _hinge.transform * MOUTH
	_cursor = 1
	visible = true
	pose(0.0)

## Where the pawn drops in (board space).
func mouth() -> Vector3:
	return _mouth_at

## The painted tail's tip (board space).
func tail() -> Vector3:
	return _tail_at

func finish() -> void:
	visible = false

## Everything at time u (seconds at speed 1).
func pose(u: float) -> void:
	# ---- the head: up, open, snap, squash, down ----
	var y := -DEPTH
	if u < SINK0:
		y = lerpf(-DEPTH, 0.0, _back(clampf(u / RISE, 0.0, 1.0)))
	else:
		var r := clampf((u - SINK0) / SINK, 0.0, 1.0)
		y = lerpf(0.0, -DEPTH, r * r)
	var up := y > -DEPTH + 0.01
	_riser.visible = up
	_disc.visible = up
	var open := 0.0
	if u < CHOMP_AT:
		open = _out(clampf((u - OPEN0) / (OPEN1 - OPEN0), 0.0, 1.0))
	else:
		var k := clampf((u - CHOMP_AT) / SNAP, 0.0, 1.0)
		open = 1.0 - k * k - sin(k * PI) * 0.08          # snaps shut, a hair past
	var q := 0.0
	if u >= CHOMP_AT and u < CHOMP_AT + SQUASH:
		q = sin((u - CHOMP_AT) / SQUASH * PI)
	_riser.position.y = y
	_riser.scale = Vector3(SIZE * (1.0 + 0.16 * q), SIZE * (1.0 - 0.22 * q), SIZE * (1.0 + 0.16 * q))
	_hinge.rotation.x = PITCH - 0.12 * open + 0.18 * q
	_upper.rotation.x = OPEN_UP * open
	_lower.rotation.x = OPEN_DN * open
	_eyes.scale = Vector3(1.0, maxf(0.15, 1.0 - 1.4 * q), 1.0)     # a happy squint on the chomp
	var e := clampf((y + DEPTH) / DEPTH, 0.0, 1.0)
	_disc.scale = Vector3(e, 1.0, e) * SIZE
	_tongue.visible = u < CHOMP_AT
	if open < 0.3:                                       # a flick out between the lips while it rises
		_tongue.position.z = 0.3 + sin(u * 70.0) * 0.06
	else:
		_tongue.position.z = lerpf(0.3, -0.05, clampf((open - 0.3) / 0.4, 0.0, 1.0))
	# ---- the ring: round the neck as it comes up, round the mouth on the chomp, round the tail on the pop ----
	var ring_k := -1.0
	var ring_at := Vector3.ZERO
	var ring_r := 1.0
	if u < 0.24:
		ring_k = u / 0.24
		ring_at = _root.position + Vector3(0, 0.03, 0)
		ring_r = SIZE * (0.9 + 0.9 * ring_k)
	elif u >= CHOMP_AT and u < CHOMP_AT + 0.24:
		ring_k = (u - CHOMP_AT) / 0.24
		ring_at = _mouth_at
		ring_r = SIZE * (0.7 + 1.5 * _out(ring_k))
	elif u >= pop_at + POP * 0.35 and u < total:
		ring_k = clampf((u - pop_at - POP * 0.35) / (total - pop_at - POP * 0.35 + 0.0001), 0.0, 1.0)
		ring_at = _tail_at + Vector3(0, 0.04, 0)
		ring_r = 0.6 + 1.2 * _out(ring_k)
	_ring.visible = ring_k >= 0.0
	if _ring.visible:
		_ring.position = ring_at
		_ring.scale = Vector3(ring_r, 1.0, ring_r)
		_ring_mat.albedo_color.a = 0.85 * (1.0 - ring_k)
	# ---- crumbs out of the snapping jaws ----
	var ck := (u - CHOMP_AT) / 0.3
	for i in CRUMBS:
		var c := _crumbs[i]
		c.visible = ck >= 0.0 and ck < 1.0
		if c.visible:
			var d: Vector3 = _root.basis * (CRUMB_DIRS[i] as Vector3)
			c.position = _mouth_at + d * (0.5 + 1.1 * _out(ck)) * SIZE * 0.5 + Vector3(0, sin(ck * PI) * 0.7 + 0.2, 0)
			c.scale = Vector3.ONE * (1.0 - ck) * 0.11 * SIZE
	# ---- the bulge down the body ----
	var bk := (u - BULGE0) / _bulge_dur
	var on := bk > 0.0 and bk < 1.0
	_lead.visible = on
	_trail.visible = on
	if on:
		var d := (bk * bk * (3.0 - 2.0 * bk)) * _len
		var grow := clampf(bk / 0.14, 0.0, 1.0) * clampf((1.0 - bk) / 0.1, 0.0, 1.0)
		var pulse := 1.0 + 0.13 * sin(u * TAU * 6.0)
		_put_bulge(_lead, d, grow * pulse)
		_put_bulge(_trail, d - 0.85, grow * (1.0 + 0.13 * sin(u * TAU * 6.0 + 2.2)) * 0.7)

## A bulge segment at distance d down the body (hidden before the head), as wide as the painted body there and more.
func _put_bulge(seg: Node3D, d: float, k: float) -> void:
	if d <= 0.05 or k <= 0.001:
		seg.visible = false
		return
	while _cursor < _path.size() - 1 and _lens[_cursor] < d:
		_cursor += 1
	while _cursor > 1 and _lens[_cursor - 1] > d:
		_cursor -= 1
	var j := _cursor
	var a := _path[j - 1]
	var b := _path[j]
	var f := clampf((d - _lens[j - 1]) / maxf(0.0001, _lens[j] - _lens[j - 1]), 0.0, 1.0)
	var p := a.lerp(b, f)
	var t := b - a
	var along := d / maxf(_len, 0.001)
	var half := SLBoard.C * (0.15 - 0.115 * pow(along, 1.15))      # the painted body's half width (_paint_snakes)
	var w := (half * 1.8 + 0.12) * k
	seg.position = Vector3(p.x, SLBoard.TOP + 0.004, p.z)
	seg.rotation = Vector3(0, atan2(t.x, t.z), 0)
	seg.scale = Vector3(w, (0.1 + half * 0.55) * k, w * 1.45)

static func _back(k: float) -> float:              # ease out with a little overshoot
	var c := 1.9
	var m := k - 1.0
	return 1.0 + (c + 1.0) * m * m * m + c * m * m

static func _out(k: float) -> float:
	return 1.0 - (1.0 - k) * (1.0 - k)


# ---------- colours ----------

func _paint(col: Color, pattern: String) -> void:
	var body := SLScenes._std(col, 0.4)
	for mi in _body_parts:
		mi.material_override = body
	_jaw.material_override = SLScenes._std(col.lightened(0.16), 0.45)
	_disc.material_override = SLScenes._lam(col.darkened(0.5))
	var pat := col.darkened(0.2)
	if pattern == "stripes":
		pat = col.lerp(Color.WHITE, 0.6)
	elif pattern == "diamonds":
		pat = col.lerp(CREAM, 0.65)
	if pattern != _pattern:
		_pattern = pattern
		_pat_parts[0].mesh = _mesh("pat_head_" + pattern)
		_pat_parts[1].mesh = _mesh("pat_neck_" + pattern)
	for mi in _pat_parts:
		mi.material_override = SLScenes._std(pat, 0.4)
	var ink := SLScenes._std(col.darkened(0.45), 0.6)
	_bulge_mats[0].material_override = ink
	_bulge_mats[2].material_override = ink
	_bulge_mats[1].material_override = body
	_bulge_mats[3].material_override = body
	for i in CRUMBS:
		_crumbs[i].material_override = SLScenes._std(Color.WHITE if i % 2 else col.lightened(0.3), 0.4)


# ---------- the meshes (once) ----------

func _build() -> void:
	_root = Node3D.new()
	add_child(_root)
	_disc = _put(_root, _mesh("disc"), null, Vector3(0, 0.006, 0))
	_riser = Node3D.new()
	_root.add_child(_riser)
	_body_parts.append(_put(_riser, _mesh("neck"), null))
	_pat_parts.append(null)                              # (the head's pattern, under _upper)
	_pat_parts.append(_put(_riser, null, null))
	_hinge = Node3D.new()
	_hinge.position = Vector3(0, NECK_H, HINGE_Z)
	_riser.add_child(_hinge)
	_upper = Node3D.new()
	_hinge.add_child(_upper)
	_body_parts.append(_put(_upper, _mesh("cranium"), null))
	_pat_parts[0] = _put(_upper, null, null)
	_put(_upper, _mesh("palate"), SLScenes._std(MOUTH_COL, 0.6))
	_put(_upper, _mesh("cheeks"), SLScenes._lam(CHEEK_COL))
	_put(_upper, _mesh("fangs"), SLScenes._std("#ffffff", 0.25))
	_put(_upper, _mesh("nostrils"), SLScenes._std(PUPIL_COL, 0.3))
	_eyes = Node3D.new()
	_eyes.position = EYE
	_upper.add_child(_eyes)
	_put(_eyes, _mesh("eye_whites"), SLScenes._std("#ffffff", 0.25))
	_put(_eyes, _mesh("pupils"), SLScenes._std(PUPIL_COL, 0.2))
	_lower = Node3D.new()
	_hinge.add_child(_lower)
	_jaw = _put(_lower, _mesh("jaw"), null)
	_put(_lower, _mesh("floor"), SLScenes._std(MOUTH_COL, 0.6))
	_tongue = Node3D.new()
	_tongue.position = Vector3(0, 0.08, 0.3)
	_lower.add_child(_tongue)
	_put(_tongue, _mesh("tongue"), SLScenes._lam(TONGUE_COL))
	_ring_mat = MeshKit.unlit(Color(1, 1, 1, 0.85))
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring = _put(self, MeshKit.torus(0.5, 0.035, 28, 6), _ring_mat)
	var crumb := _mesh("crumb")
	for i in CRUMBS:
		_crumbs.append(_put(self, crumb, null))
	var dome := _mesh("dome")
	for k in 2:
		var seg := Node3D.new()
		add_child(seg)
		_bulge_mats.append(_put(seg, dome, null, Vector3(0, -0.02, 0), Vector3(1.16, 0.62, 1.12)))   # ink rim
		_bulge_mats.append(_put(seg, dome, null))
		if k == 0:
			_put(seg, dome, SLScenes._std("#ffffff", 0.3), Vector3(-0.32, 0.72, 0.18), Vector3(0.2, 0.2, 0.32))   # shine
			_lead = seg
		else:
			_trail = seg

static func _put(parent: Node3D, mesh: Mesh, m: Material, pos := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	if m:
		mi.material_override = m
	mi.position = pos
	mi.scale = scl
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

const EYE := Vector3(0, 0.34, 0.2)                 # the eyes' centre (upper jaw space)
const CRANIUM := [Vector3(0, 0.1, 0.38), Vector3(0.5, 0.3, 0.62)]
const JAW := [Vector3(0, -0.12, 0.36), Vector3(0.44, 0.17, 0.58)]

static func _mesh(key: String) -> ArrayMesh:
	if _meshes.has(key):
		return _meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	match key:
		"disc":
			_tube(st, 0.4, 0.4, -0.01, 0.01, 16, true)
		"neck":
			_tube(st, 0.32, 0.27, -1.6, NECK_H + 0.04, 12, false)
			_ell(st, Vector3(0, NECK_H - 0.02, HINGE_Z * 0.5), Vector3(0.28, 0.18, 0.32), 10, 5)    # under the hinge
		"cranium":
			_ell(st, CRANIUM[0], CRANIUM[1], 14, 9)
		"palate":
			_ell(st, Vector3(0, -0.19, 0.46), Vector3(0.38, 0.05, 0.48), 14, 5)
		"cheeks":
			for s in [-1.0, 1.0]:
				_ell(st, Vector3(s * 0.39, 0.02, 0.74), Vector3(0.09, 0.06, 0.08), 6, 3)
		"fangs":
			for s in [-1.0, 1.0]:
				_ell(st, Vector3(s * 0.19, -0.17, 0.78), Vector3(0.045, 0.09, 0.045), 6, 4)
		"nostrils":
			for s in [-1.0, 1.0]:
				_ell(st, Vector3(s * 0.12, 0.27, 0.94), Vector3(0.04, 0.03, 0.035), 5, 3)
		"eye_whites":
			for s in [-1.0, 1.0]:
				_ell(st, Vector3(s * 0.25, 0, 0), Vector3(0.18, 0.18, 0.17), 10, 6)
				_ell(st, Vector3(s * 0.25 - 0.03, 0.13, 0.13), Vector3(0.035, 0.035, 0.03), 5, 3)    # highlights
		"pupils":
			for s in [-1.0, 1.0]:
				_ell(st, Vector3(s * 0.25, 0.06, 0.1), Vector3(0.095, 0.1, 0.085), 8, 5)
		"jaw":
			_ell(st, JAW[0], JAW[1], 14, 7)
		"floor":
			_ell(st, Vector3(0, 0.04, 0.4), Vector3(0.34, 0.05, 0.44), 14, 5)
		"tongue":
			_ell(st, Vector3(0, 0, 0.26), Vector3(0.05, 0.022, 0.28), 6, 3)
			for s in [-1.0, 1.0]:
				_ell(st, Vector3(s * 0.05, 0, 0.6), Vector3(0.03, 0.02, 0.1), 5, 3, Basis(Vector3.UP, s * 0.5))
		"crumb":
			_ell(st, Vector3.ZERO, Vector3.ONE, 6, 4)
		"dome":
			_ell(st, Vector3.ZERO, Vector3.ONE, 12, 6)
		"pat_head_stripes":                          # a pale band across the head behind the eyes
			_ell(st, Vector3(0, 0.27, -0.03), Vector3(0.46, 0.12, 0.09), 10, 4)
		"pat_neck_stripes":
			for y in [0.16, -0.24]:
				_tube(st, 0.3 + (0.16 - y) * 0.025, 0.295 + (0.16 - y) * 0.025, y - 0.06, y + 0.06, 12, false)
		"pat_head_diamonds":                         # a pale diamond on the crown
			_ell(st, Vector3(0, 0.36, 0.02), Vector3(0.13, 0.05, 0.17), 4, 2)
		"pat_neck_diamonds":
			for y in [0.15, -0.3]:
				_ell(st, Vector3(0, y, 0.29 + (0.15 - y) * 0.03), Vector3(0.1, 0.13, 0.05), 4, 2, Basis(Vector3.RIGHT, PI / 2))
		_:                                           # back spots: two on the crown, two down the neck
			if key.begins_with("pat_head"):
				for s in [-1.0, 1.0]:
					_ell(st, Vector3(s * 0.15, 0.31, -0.02), Vector3(0.1, 0.05, 0.09), 7, 3)
			else:
				for p in [Vector3(0.22, 0.1, 0.18), Vector3(-0.2, -0.3, 0.22)]:
					_ell(st, p, Vector3(0.1, 0.09, 0.05), 7, 3, Basis(Vector3.UP, atan2(p.x, p.z)))
	var m := st.commit()
	_meshes[key] = m
	return m

## An ellipsoid (centre c, radii r, turned by rot) with true normals.
static func _ell(st: SurfaceTool, c: Vector3, r: Vector3, seg: int, rings: int, rot := Basis()) -> void:
	var pts := []
	var nrm := []
	for i in rings + 1:
		var v := PI * i / rings
		for j in seg + 1:
			var a := TAU * j / seg
			var unit := Vector3(sin(v) * cos(a), cos(v), sin(v) * sin(a))
			pts.append(c + rot * (unit * r))
			nrm.append((rot * Vector3(unit.x / r.x, unit.y / r.y, unit.z / r.z)).normalized())
	for i in rings:
		for j in seg:
			var a := i * (seg + 1) + j
			var b := a + seg + 1
			if i > 0:
				_tri(st, pts, nrm, a, b, a + 1)
			if i < rings - 1:
				_tri(st, pts, nrm, a + 1, b, b + 1)

## A tapered tube round Y from y0 (radius r0) to y1 (radius r1), capped when asked.
static func _tube(st: SurfaceTool, r0: float, r1: float, y0: float, y1: float, seg: int, caps: bool) -> void:
	var pts := []
	var nrm := []
	var slope := (r0 - r1) / (y1 - y0)
	for j in seg + 1:
		var a := TAU * j / seg
		var d := Vector3(cos(a), 0, sin(a))
		var n := (d + Vector3(0, slope, 0)).normalized()
		pts.append(d * r0 + Vector3(0, y0, 0))
		pts.append(d * r1 + Vector3(0, y1, 0))
		nrm.append(n)
		nrm.append(n)
	for j in seg:
		_tri(st, pts, nrm, j * 2, j * 2 + 1, j * 2 + 2)
		_tri(st, pts, nrm, j * 2 + 1, j * 2 + 3, j * 2 + 2)
	if caps:
		var top := pts.size()
		pts.append(Vector3(0, y1, 0))
		nrm.append(Vector3.UP)
		for j in seg + 1:
			pts.append(pts[j * 2 + 1])
			nrm.append(Vector3.UP)
		for j in seg:
			_tri(st, pts, nrm, top, top + 1 + j, top + 2 + j)

## One triangle, wound so its front faces along its normals (Godot's fronts are clockwise).
static func _tri(st: SurfaceTool, pts: Array, nrm: Array, a: int, b: int, c: int) -> void:
	var pa: Vector3 = pts[a]
	var pb: Vector3 = pts[b]
	var pc: Vector3 = pts[c]
	var n: Vector3 = nrm[a] + nrm[b] + nrm[c]
	var order := [a, b, c] if (pb - pa).cross(pc - pa).dot(n) <= 0.0 else [a, c, b]
	for i: int in order:
		st.set_normal(nrm[i])
		st.add_vertex(pts[i])
