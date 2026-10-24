extends SceneTree
## Runs only the Collection suite:  godot --headless --path godot -s res://dev/run_collection_tests.gd

func _initialize() -> void:
	var suite = load("res://tests/test_collection.gd").new()
	suite.run()
	var bad: Array = suite.results.filter(func(r): return not r.ok)
	print("test_collection.gd: %d passed, %d failed" % [suite.results.size() - bad.size(), bad.size()])
	for r in bad:
		print("  FAIL %s  got %s" % [r.name, r.got])
	quit(1 if bad else 0)
