extends SceneTree
## Runs only the feature-info suite:  godot --headless --path godot -s res://dev/run_info_tests.gd

func _initialize() -> void:
	await process_frame   # the icon / bubble checks need a live scene tree
	var suite = load("res://tests/test_info.gd").new()
	suite.run()
	var bad: Array = suite.results.filter(func(r): return not r.ok)
	print("test_info.gd: %d passed, %d failed" % [suite.results.size() - bad.size(), bad.size()])
	for r in bad:
		print("  FAIL %s  got %s" % [r.name, r.got])
	quit(1 if bad else 0)
