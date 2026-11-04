extends SceneTree
## Runs only the rewards suite headless:  godot --headless --path godot -s res://dev/run_reward_tests.gd

func _initialize() -> void:
	var script = load("res://tests/test_rewards.gd")
	if script == null or not script.can_instantiate():
		print("test_rewards.gd: failed to load")
		quit(1)
		return
	var suite = script.new()
	suite.run()
	var bad: Array = suite.results.filter(func(r): return not r.ok)
	print("test_rewards.gd: %d passed, %d failed" % [suite.results.size() - bad.size(), bad.size()])
	for r in bad:
		print("  FAIL %s  got %s" % [r.name, r.got])
	quit(1 if bad.size() else 0)
