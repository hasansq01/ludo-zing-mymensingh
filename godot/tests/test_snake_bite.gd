extends "res://tests/test_suite.gd"
## The snake eating a pawn (SLBoard.slide + SnakeBite): the timeline (the old slide's time + EXTRA, times the speed),
## the pawn gone while swallowed and back on the tail square at the end, the bulge on the painted body, cut-offs
## (place() mid-gulp), Reduce motion (a plain glide), the triangle budget and that it only uses material kinds the
## game already compiles. The tweens are stepped by hand (custom_step), so no frames are needed.

const HEAD := 62

func run() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var board := SLBoard.new()
	tree.root.add_child(board)
	board.reduce_motion = 0
	board.setup_players([0, 1])
	board.place([HEAD, 3])
	var tail: int = SL.SNAKES[HEAD]
	var bite: SnakeBite = board._bite
	check("the bite is built with the board, hidden", bite != null and not bite.visible)

	# ---- the timeline ----
	var t: Dictionary = board.pawns[0]
	var g: Node3D = t.node
	var body := SLBoard.snake_body(HEAD)
	var L := g.position.distance_to(SLBoard.grid_to_world(body[0])) + SLBoard.grid_to_world(body[body.size() - 1]).distance_to(board.cell_world(tail))
	for j in range(1, body.size()):
		L += SLBoard.grid_to_world(body[j]).distance_to(SLBoard.grid_to_world(body[j - 1]))
	var old := 0.6 + 0.05 * L / SLBoard.C
	board.slide(0, HEAD, tail, 1.0)
	var tw: Tween = t.tw
	tw.pause()
	check("a gulp lasts the old slide's time + EXTRA", absf(bite.total - (old + SnakeBite.EXTRA)) < 0.001, [bite.total, old])
	check("... and the pop is its last POP seconds", absf(bite.pop_at - (bite.total - SnakeBite.POP)) < 0.001, bite.pop_at)
	check("the pawn's square is the tail's already (as before)", int(t.pos) == tail)
	tw.custom_step(0.1)
	check("rising: the head is up, the pawn hops", bite.visible and bite._riser.visible and g.visible and g.position.y > SLBoard.TOP + 0.2, g.position)
	tw.custom_step(SnakeBite.CHOMP_AT + 0.08 - 0.1)
	check("swallowed: the pawn is gone", not g.visible)
	check("... the jaws are shut", absf(bite._upper.rotation.x) < 0.15, bite._upper.rotation.x)
	var mid := maxf(SnakeBite.SINK0 + SnakeBite.SINK + 0.02, SnakeBite.BULGE0 + (bite.pop_at - SnakeBite.BULGE0) * 0.5)
	tw.custom_step(mid - SnakeBite.CHOMP_AT - 0.08)
	check("mid-body: the head is back under the board", not bite._riser.visible)
	var near := 9.0
	for q in body:
		near = minf(near, Vector2(bite._lead.position.x, bite._lead.position.z).distance_to(Vector2(SLBoard.grid_to_world(q).x, SLBoard.grid_to_world(q).z)))
	check("... the bulge is on the painted body", bite._lead.visible and near < 0.2, near)
	check("... and still hidden pawn", not g.visible)
	tw.custom_step(bite.pop_at + 0.1 - mid)
	check("popping out of the tail", g.visible and g.position.distance_to(bite.tail()) < 2.5 and g.scale.x < float(t.scale) * 1.3)
	tw.custom_step(bite.total)                            # to the end (the slide coroutine finishes)
	check("landed on the tail square", not t.anim and g.visible and g.position.is_equal_approx(t.target), [g.position, t.target])
	check("... full size, upright, the snake gone", is_equal_approx(g.scale.x, float(t.scale)) and g.rotation == Vector3.ZERO and not bite.visible)

	# ---- the speed setting scales it all ----
	board.place([HEAD, 3])
	board.slide(0, HEAD, tail, 0.5)
	tw = t.tw
	tw.pause()
	tw.custom_step((old + SnakeBite.EXTRA) * 0.5 - 0.02)
	check("Fast: half the time (still going just before)", t.anim)
	tw.custom_step(0.04)
	check("... and done just after", not t.anim and g.visible)

	# ---- cut off mid-gulp (a sync re-lays the board) ----
	board.place([HEAD, 3])
	board.slide(0, HEAD, tail, 1.0)
	t.tw.pause()
	(t.tw as Tween).custom_step(SnakeBite.CHOMP_AT + 0.2)
	board.place([40, 3])
	check("place() mid-gulp: the pawn is back, the snake gone", g.visible and not bite.visible and not t.get("bitten", false))
	check("... and its scale follows the board again", not t.anim)

	# ---- Reduce motion: a plain glide down the body ----
	board.reduce_motion = 1
	board.place([HEAD, 3])
	board.slide(0, HEAD, tail, 1.0)
	tw = t.tw
	tw.pause()
	tw.custom_step(old * 0.5)
	check("Reduce motion: no snake head, the pawn glides", not bite.visible and g.visible and g.rotation == Vector3.ZERO)
	tw.custom_step(old * 0.5 + 0.01)
	check("... in the old slide's time", not t.anim and g.position.is_equal_approx(t.target))
	board.reduce_motion = 0

	# ---- cheap: triangles, draw calls, material kinds ----
	var tris := 0
	var draws := 0
	var kinds := {}
	for mi in _meshes(bite._root, []):
		tris += _tris(mi.mesh)
		draws += 1
		kinds[ShaderWarmUp._kind(mi)] = true
	check("the head is under 1.6k triangles in under 16 meshes", tris < 1600 and draws < 16, [tris, draws])
	var known := {}
	for m in [SLScenes._std("#123456", 0.4), SLScenes._lam("#123456")]:
		var probe := MeshInstance3D.new()
		probe.material_override = m
		known[ShaderWarmUp._kind(probe)] = true
		probe.free()
	var ring_probe := MeshInstance3D.new()
	ring_probe.material_override = (board.pawns[0].ring as MeshInstance3D).material_override
	known[ShaderWarmUp._kind(ring_probe)] = true
	ring_probe.free()
	for mi in _meshes(bite, []):
		kinds[ShaderWarmUp._kind(mi)] = true
	check("only material kinds the scenes and pawns already use (no new shaders)", kinds.keys().all(func(k): return known.has(k)), kinds.keys())
	board.queue_free()

static func _meshes(n: Node, out: Array) -> Array:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_meshes(c, out)
	return out

static func _tris(m: Mesh) -> int:
	var k := 0
	for s in m.get_surface_count():
		k += (m as ArrayMesh).surface_get_array_len(s) / 3 if m is ArrayMesh else 0
	return k
