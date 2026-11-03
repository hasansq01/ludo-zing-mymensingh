extends SceneTree
## Runs only the pawn skins suite:  godot --headless --path godot -s res://dev/run_pawn_tests.gd

func _initialize() -> void:
	await process_frame                       # the boards need a live scene tree
	var suite = load("res://tests/test_pawns.gd").new()
	await suite.run()
	var bad: Array = suite.results.filter(func(r): return not r.ok)
	print("test_pawns.gd: %d passed, %d failed" % [suite.results.size() - bad.size(), bad.size()])
	for r in bad:
		print("  FAIL %s  got %s" % [r.name, r.got])
	quit(1 if bad else 0)
