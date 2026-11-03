extends Node
## Dev: the café world alone (no UI, no save): each room with a Ludo board in 3D View and Top View, as in a match.
## godot --path . --resolution 390x844 res://dev/world_shots.tscn -- <out_dir> [tag] [rooms|all] [cues]
## "cues": a pair and a mixed stack on one star, two singles sharing a square, a finished pawn, your pawns movable.

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "/tmp"
	var tag: String = args[1] if args.size() > 1 else "world"
	var ids: Array = Rooms.LIST.map(func(r): return r.id)
	if args.size() > 2 and args[2] != "all":
		ids = Array(args[2].split(","))
	var cues := args.size() > 3 and args[3] == "cues"
	var baker := TexBaker.new()
	add_child(baker)
	var w := TableWorld.new()
	add_child(w)
	w.top_band = 844.0 - 2 * (68.0 + 118.0) + 40.0
	await w.build_room(baker, func(_f): pass, str(ids[0]))
	var S := {players = ["human", "cpu", "cpu", "cpu"], pairs = [], tok = [[12, 12, 30, -1], [5, 40, -1, -1], [20, 51, -1, -1], [8, 25, 44, -1]]}
	if cues:
		S.tok = [[8, 8, 20, 56], [7, 40, -1, -1], [34, 51, -1, -1], [21, 25, 44, -1]]
		S.pairs = [{c = 0, a = 0, b = 1}]
	for id in ids:
		await w.rooms.set_room(baker, id)
		w.board.relayout(S)
		w.board.set_movable([0, 1, 2] if cues else [], 0 if cues else -1)
		for v in ["3d", "top"]:
			w.view_game(0, v == "top")
			await get_tree().create_timer(2.6).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/%s_%s_%s.png" % [out, tag, id, v])
			print("shot ", tag, " ", id, " ", v)
	get_tree().quit()
