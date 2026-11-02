class_name LeakProbe
extends Node
## The graphics leak test (internal testers): on some Mali phones (Infinix X6886, Mali-G57 r54p1, Android 16) the
## process's native memory grows ~105 MB a minute (~60 KB a frame) until Android refuses new mappings
## (vm.max_map_count) and the app dies after ~20 minutes, while Godot's own counters stay flat: the GPU driver keeps
## something the game draws every frame. This test finds what: it turns one kind of drawing off (or changes it) at a
## time for STEP_SEC, measures how fast native memory and the mapping count grow in each step (CrashWatch's
## native_mem_now: the plugin's diag_mem_now), puts everything back, and sends the numbers as a "probe" report
## (CrashWatch.send_probe -> /v1/diag/crash, trigger "probe").
##
## Started from Settings: seven taps on the version line (SettingsSheet.probe_requested -> main.start_leak_probe).
## Best run during a Ludo match. While it runs the dice may stop moving and the board may vanish for a few seconds:
## that is the test.
##
##   var p := LeakProbe.new(); p.app = main; main.add_child(p); await p.run()
## Tests: step_sec, settle_sec, measure_fn, send_fn, viewport.

signal step_started(i: int, total: int, step: String)
signal finished(result: Dictionary)

const STEP_SEC := 20.0
const SETTLE_SEC := 3.0
## In this order. "subviews": every 3D SubViewport (the dice, previews): off = not drawn, no_msaa = drawn without
## MSAA. "main": the main view's MSAA / 3D scale / 3D at all. ui_hidden: the 2D interface (app.ui_root) hidden, the 3D
## drawn as usual. fps_15: if the growth halves, it is per frame.
const STEPS := ["base", "subviews_off", "subviews_no_msaa", "main_no_msaa", "main_scale_1", "main_no_3d", "all_2d",
	"ui_hidden", "fps_15", "base_again"]

var app: Node = null                     ## main.gd (crash_watch, screen); null in tests
var viewport: Viewport = null            ## the main view (default: the root window)
var step_sec := STEP_SEC
var settle_sec := SETTLE_SEC
var measure_fn := Callable()             ## () -> {native_mb, maps, mem}: tests; CrashWatch.native_mem_now by default
var send_fn := Callable()                ## (result) -> void: tests; CrashWatch.send_probe by default
var running := false
var result: Dictionary = {}

var _saved := {}                         # what each change touched, to put back


func run() -> Dictionary:
	if running:
		return {}
	running = true
	if viewport == null:
		viewport = get_tree().root
	var steps: Array = []
	var t0 := Time.get_ticks_msec()
	for i in STEPS.size():
		var name: String = STEPS[i]
		step_started.emit(i + 1, STEPS.size(), name)
		_apply(name)
		await _wait(settle_sec)
		var a := _measure()
		var ta := Time.get_ticks_msec()
		var frames_a := Engine.get_process_frames()
		await _wait(step_sec)
		var b := _measure()
		var dt := maxf((Time.get_ticks_msec() - ta) / 1000.0, 0.001)
		var frames := Engine.get_process_frames() - frames_a
		var s := {step = name, sec = snappedf(dt, 0.1), fps = snappedf(frames / dt, 0.1)}
		for k in ["native_mb", "maps", "mem"]:
			if a.has(k) and b.has(k):
				s[k + "_per_min"] = snappedf((float(b[k]) - float(a[k])) / dt * 60.0, 0.1)
				s[k] = b[k]
		if s.has("native_mb_per_min") and frames > 0:
			s.kb_per_frame = snappedf((float(b.native_mb) - float(a.native_mb)) * 1024.0 / frames, 0.1)
		steps.append(s)
		_restore()
	result = {
		steps = steps,
		total_sec = snappedf((Time.get_ticks_msec() - t0) / 1000.0, 0.1),
		screen = str(app.get("screen")) if app != null and app.get("screen") != null else "",
		tier = Quality.tier(),
		subviews = _subviews().size(),
	}
	running = false
	_send(result)
	finished.emit(result)
	return result


# ---------- the changes ----------

func _apply(step: String) -> void:
	match step:
		"subviews_off":
			for vp in _subviews():
				_save(vp, "render_target_update_mode")
				vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		"subviews_no_msaa":
			for vp in _subviews():
				_save(vp, "msaa_3d")
				vp.msaa_3d = Viewport.MSAA_DISABLED
		"main_no_msaa":
			_save(viewport, "msaa_3d")
			viewport.msaa_3d = Viewport.MSAA_DISABLED
		"main_scale_1":
			_save(viewport, "scaling_3d_scale")
			viewport.scaling_3d_scale = 1.0
		"main_no_3d":
			_save(viewport, "disable_3d")
			viewport.disable_3d = true
		"all_2d":
			_save(viewport, "disable_3d")
			viewport.disable_3d = true
			for vp in _subviews():
				_save(vp, "render_target_update_mode")
				vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		"ui_hidden":
			var ui: Variant = app.get("ui_root") if app != null else null
			if ui is CanvasItem:
				_save(ui, "visible")
				(ui as CanvasItem).visible = false
		"fps_15":
			_saved["max_fps"] = Engine.max_fps
			Engine.max_fps = 15

func _save(o: Object, prop: String) -> void:
	var key := "%d:%s" % [o.get_instance_id(), prop]
	if not _saved.has(key):
		_saved[key] = [o, prop, o.get(prop)]

func _restore() -> void:
	for key: String in _saved:
		if key == "max_fps":
			Engine.max_fps = int(_saved[key])
			continue
		var e: Array = _saved[key]
		if is_instance_valid(e[0]):
			(e[0] as Object).set(e[1], e[2])
	_saved.clear()

## The 3D SubViewports drawn into the interface (the dice, previews): every SubViewport in the tree but the main view.
func _subviews() -> Array[SubViewport]:
	var out: Array[SubViewport] = []
	for n in get_tree().root.find_children("*", "SubViewport", true, false):
		if n != viewport:
			out.append(n as SubViewport)
	return out


# ---------- measuring and sending ----------

func _measure() -> Dictionary:
	if measure_fn.is_valid():
		return measure_fn.call()
	var cw: Variant = app.get("crash_watch") if app != null else null
	if cw is CrashWatch:
		var m: Dictionary = (cw as CrashWatch).native_mem_now()
		if not m.is_empty():
			return m
	return {mem = snappedf(OS.get_static_memory_usage() / 1048576.0, 0.1)}   # (desktop debug builds)

func _send(r: Dictionary) -> void:
	if send_fn.is_valid():
		send_fn.call(r)
		return
	var cw: Variant = app.get("crash_watch") if app != null else null
	if cw is CrashWatch:
		(cw as CrashWatch).send_probe(r)

func _wait(sec: float) -> void:
	if sec > 0.0:
		await get_tree().create_timer(sec, true).timeout
	else:
		await get_tree().process_frame
