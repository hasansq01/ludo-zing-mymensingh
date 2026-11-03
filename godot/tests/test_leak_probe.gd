extends "res://tests/test_suite.gd"
## The graphics leak test (res://scripts/debug/leak_probe.gd): every step changes only its own setting and puts it back,
## the growth is measured per step (here a fake leak that only grows while the main view draws with MSAA), the result
## is sent once, and the seven taps on Settings' version line ask for it. Nothing here writes the save.

## A fake memory reader: native memory grows LEAK MB a second while `vp` draws 3D with MSAA, else stays put.
class FakeMem extends RefCounted:
	const LEAK := 2.0
	var vp: Viewport
	var native := 300.0
	var maps := 5000.0
	var last := 0
	func read() -> Dictionary:
		var now := Time.get_ticks_msec()
		if last > 0 and vp.msaa_3d != Viewport.MSAA_DISABLED and not vp.disable_3d:
			var dt := (now - last) / 1000.0
			native += LEAK * dt
			maps += 60.0 * dt
		last = now
		return {native_mb = native, maps = int(maps), mem = 900}

var _root: Node

func run() -> void:
	_root = (Engine.get_main_loop() as SceneTree).root
	await _probe_tests()
	_settings_tests()


func _probe_tests() -> void:
	var main_vp := SubViewport.new()             # stands in for the root window
	main_vp.msaa_3d = Viewport.MSAA_2X
	main_vp.scaling_3d_scale = 0.85
	_root.add_child(main_vp)
	var dice := SubViewport.new()
	dice.msaa_3d = Viewport.MSAA_4X
	dice.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_root.add_child(dice)
	var fps_before := Engine.max_fps
	var mem := FakeMem.new()
	mem.vp = main_vp
	var sent: Array = []
	var p := LeakProbe.new()
	p.viewport = main_vp
	p.step_sec = 0.25
	p.settle_sec = 0.0
	p.measure_fn = mem.read
	p.send_fn = func(r: Dictionary) -> void: sent.append(r)
	var seen: Array = []
	var during := {}
	p.step_started.connect(func(i: int, n: int, step: String):
		seen.append(step)
		await (Engine.get_main_loop() as SceneTree).process_frame
		during[step] = [main_vp.msaa_3d, main_vp.scaling_3d_scale, main_vp.disable_3d, dice.render_target_update_mode,
			dice.msaa_3d, Engine.max_fps])
	_root.add_child(p)
	var r: Dictionary = await p.run()
	check("probe: every step in order", seen == LeakProbe.STEPS, seen)
	var steps: Array = r.get("steps", [])
	var rate := {}
	for s: Dictionary in steps:
		rate[s.step] = float(s.get("native_mb_per_min", -1.0))
	check("probe: a step per change, each with native / maps / RSS growth per minute and fps", steps.size() == LeakProbe.STEPS.size() \
		and steps.all(func(s): return s.has("native_mb_per_min") and s.has("maps_per_min") and s.has("mem_per_min") and s.has("fps")), steps)
	check("probe: the leak shows in the base steps (~120 MB a minute here)", rate.base > 60.0 and rate.base_again > 60.0, rate)
	check("probe: and stops in the steps that take the culprit away (main MSAA off, main 3D off, all 2D)",
		rate.main_no_msaa < 5.0 and rate.main_no_3d < 5.0 and rate.all_2d < 5.0, rate)
	check("probe: the other steps keep it (subviews off / no MSAA, full scale)", rate.subviews_off > 60.0 \
		and rate.subviews_no_msaa > 60.0 and rate.main_scale_1 > 60.0, rate)
	check("probe: kb per frame for the steps with frames", steps[0].has("kb_per_frame"), steps[0])
	check("probe: each step changes only its own setting", during.main_no_msaa[0] == Viewport.MSAA_DISABLED \
		and during.main_no_msaa[3] == SubViewport.UPDATE_WHEN_VISIBLE and during.subviews_off[3] == SubViewport.UPDATE_DISABLED \
		and during.subviews_off[0] == Viewport.MSAA_2X and during.subviews_no_msaa[4] == Viewport.MSAA_DISABLED \
		and is_equal_approx(during.main_scale_1[1], 1.0) and during.main_no_3d[2] == true and during.main_no_3d[3] == SubViewport.UPDATE_WHEN_VISIBLE \
		and during.all_2d[2] == true and during.all_2d[3] == SubViewport.UPDATE_DISABLED and during.fps_15[5] == 15 \
		and during.base[0] == Viewport.MSAA_2X and is_equal_approx(during.base[1], 0.85) \
		and during.base.slice(2) == [false, SubViewport.UPDATE_WHEN_VISIBLE, Viewport.MSAA_4X, fps_before], during)
	check("probe: everything back afterwards", main_vp.msaa_3d == Viewport.MSAA_2X and is_equal_approx(main_vp.scaling_3d_scale, 0.85) \
		and not main_vp.disable_3d and dice.render_target_update_mode == SubViewport.UPDATE_WHEN_VISIBLE \
		and dice.msaa_3d == Viewport.MSAA_4X and Engine.max_fps == fps_before,
		[main_vp.msaa_3d, main_vp.scaling_3d_scale, main_vp.disable_3d, dice.render_target_update_mode, dice.msaa_3d, Engine.max_fps])
	check("probe: sent once, with the steps and the tier", sent.size() == 1 and (sent[0].steps as Array).size() == steps.size() \
		and sent[0].has("tier") and int(sent[0].subviews) >= 1, sent)
	check("probe: not running any more; a second run works", not p.running)
	p.free()
	main_vp.free()
	dice.free()

func _settings_tests() -> void:
	var s := SettingsSheet.new()
	var asked := [0]
	s.probe_requested.connect(func(): asked[0] += 1)
	var line := s.find_child("VersionLine", true, false) as Control
	check("settings: the version line takes taps", line != null and line.mouse_filter != Control.MOUSE_FILTER_IGNORE)
	var tap := InputEventMouseButton.new()
	tap.button_index = MOUSE_BUTTON_LEFT
	tap.pressed = true
	for i in SettingsSheet.PROBE_TAPS - 1:
		s._on_version_tap(tap)
	check("settings: six taps ask nothing", asked[0] == 0)
	var up := tap.duplicate() as InputEventMouseButton
	up.pressed = false
	s._on_version_tap(up)
	check("settings: a release is not a tap", asked[0] == 0)
	s._on_version_tap(tap)
	check("settings: the seventh tap asks for the graphics test", asked[0] == 1, asked[0])
	s.free()
