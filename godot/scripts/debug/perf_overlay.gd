class_name PerfOverlay
extends CanvasLayer
## Debug builds only: a small performance read-out over the app, so testers on real phones can report numbers.
##   FPS and the frame cap, frame time (average / p95 / worst of the last FRAMES frames), the main view's CPU render
##   time (and GPU time where the driver measures it), draw calls, primitives, objects, video / texture / buffer
##   memory, the quality tier (and the detected one), the 3D scale and MSAA, the window, and the device facts
##   (model, GPU, RAM, cores, why the tier).
## Shown at launch by `--perf` on the command line or in user://debug_args.txt (Quality.arg; on Android: `adb shell
## run-as com.flipfold.ludozing sh -c 'echo --perf > files/debug_args.txt'`), toggled any time by a three-finger tap
## or F3. Tapping the panel copies the read-out to the clipboard; while shown, one "[perf] ..." line is printed every
## LOG_SEC (adb logcat -s godot), which tools/lowspec-capture.sh collects.
## Release builds: install() adds nothing (no node, no input handling, no prints).
##
##   main.gd _ready: PerfOverlay.install(self)

const FRAMES := 120
const REFRESH_SEC := 0.25
const LOG_SEC := 5.0
const FS := 11

var _times := PackedFloat32Array()      # the last FRAMES frame times in ms (a ring)
var _at := 0
var _last_us := 0
var _refresh := 0.0
var _log := 0.0
var _touches := {}
var _panel: PanelContainer
var _label: Label
var _measuring := false


## Adds the overlay under `host` (shown at once with --perf). Release builds: nothing. Returns the overlay or null.
static func install(host: Node) -> PerfOverlay:
	if not OS.is_debug_build() or host == null:
		return null
	var o := PerfOverlay.new()
	o.name = "PerfOverlay"
	host.add_child.call_deferred(o)
	return o

func _init() -> void:
	layer = 128                              # above the interface, the sheets and the splash
	_times.resize(FRAMES)
	_times.fill(0.0)

func _ready() -> void:
	if not OS.is_debug_build():
		queue_free()
		return
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.62)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(6)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.position = Vector2(4, 4)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.gui_input.connect(_on_panel_input)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", FS)
	_label.add_theme_color_override("font_color", Color(0.85, 1.0, 0.85))
	_label.add_theme_constant_override("line_spacing", -2)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_label)
	add_child(_panel)
	show_overlay(Quality.arg("perf") != "")
	Quality.detected()                       # fills Quality.info even when a tier was picked
	print("[perf] device %s" % JSON.stringify(Quality.info))

## Shows / hides the read-out (hidden: no per-frame work besides the gesture check).
func show_overlay(on: bool) -> void:
	visible = on
	set_process(on)
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, on)
	_measuring = on
	_last_us = Time.get_ticks_usec()
	_times.fill(0.0)
	_at = 0
	_refresh = 0.0
	_log = LOG_SEC
	if on:
		_update_text()

func toggle() -> void:
	show_overlay(not visible)

func _input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		var t := e as InputEventScreenTouch
		if t.pressed:
			_touches[t.index] = true
			if _touches.size() == 3:
				toggle()
		else:
			_touches.erase(t.index)
	elif e is InputEventKey and e.pressed and not e.echo and (e as InputEventKey).keycode == KEY_F3:
		toggle()

func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	_times[_at] = (now - _last_us) / 1000.0
	_at = (_at + 1) % FRAMES
	_last_us = now
	_refresh -= delta
	_log -= delta
	if _refresh <= 0.0:
		_refresh = REFRESH_SEC
		_update_text()
	if _log <= 0.0:
		_log = LOG_SEC
		print("[perf] " + line())

## The numbers as a Dictionary (fps, ms_avg, ms_p95, ms_max, cpu_ms, gpu_ms, draws, prims, objects, vram_mb,
## tex_mb, buf_mb, tier, detected, scale, msaa, max_fps, window).
func stats() -> Dictionary:
	var ft: Array = []
	for v in _times:
		if v > 0.0:
			ft.append(v)
	ft.sort()
	var avg := 0.0
	for v: float in ft:
		avg += v
	avg = avg / ft.size() if ft.size() > 0 else 0.0
	var vp := get_viewport()
	var rid := vp.get_viewport_rid()
	return {
		fps = Engine.get_frames_per_second(),
		ms_avg = avg,
		ms_p95 = percentile(ft, 0.95),
		ms_max = ft.back() if ft.size() > 0 else 0.0,
		cpu_ms = RenderingServer.viewport_get_measured_render_time_cpu(rid) if _measuring else 0.0,
		gpu_ms = RenderingServer.viewport_get_measured_render_time_gpu(rid) if _measuring else 0.0,
		process_ms = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		draws = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		prims = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		objects = int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		vram_mb = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		tex_mb = Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
		buf_mb = Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0,
		mem_mb = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		tier = Quality.tier(),
		detected = Quality.detected(),
		scale = vp.scaling_3d_scale,
		msaa = [0, 2, 4, 8][clampi(int(vp.msaa_3d), 0, 3)],
		max_fps = Engine.max_fps,
		window = DisplayServer.window_get_size(),
	}

## The value at fraction q (0..1) of a sorted Array of numbers (0 when empty).
static func percentile(sorted: Array, q: float) -> float:
	if sorted.is_empty():
		return 0.0
	return float(sorted[clampi(int(ceil(q * sorted.size())) - 1, 0, sorted.size() - 1)])

## One line for logs / bug reports.
func line() -> String:
	var s := stats()
	return ("fps %d cap %d | ms avg %.1f p95 %.1f max %.1f | render cpu %.1f gpu %.1f process %.1f | draws %d prims %d"
		+ " obj %d | vram %.0f MB (tex %.0f buf %.0f) mem %.0f MB | tier %s (auto %s) scale %.2f msaa %dx | %dx%d") % [
		s.fps, s.max_fps, s.ms_avg, s.ms_p95, s.ms_max, s.cpu_ms, s.gpu_ms, s.process_ms, s.draws, s.prims, s.objects,
		s.vram_mb, s.tex_mb, s.buf_mb, s.mem_mb, s.tier, s.detected, s.scale, s.msaa, s.window.x, s.window.y]

## The full read-out (what the panel shows and a tap copies).
func report() -> String:
	var s := stats()
	var i: Dictionary = Quality.info
	var lines := [
		"FPS %d  (cap %d)" % [s.fps, s.max_fps],
		"frame ms  avg %.1f  p95 %.1f  max %.1f" % [s.ms_avg, s.ms_p95, s.ms_max],
		"render cpu %.1f  gpu %s  process %.1f" % [s.cpu_ms, ("%.1f" % s.gpu_ms) if s.gpu_ms > 0.0 else "n/a", s.process_ms],
		"draws %d  prims %.1fk  obj %d" % [s.draws, s.prims / 1000.0, s.objects],
		"VRAM %.0f MB  tex %.0f  buf %.0f  mem %.0f" % [s.vram_mb, s.tex_mb, s.buf_mb, s.mem_mb],
		"tier %s  (auto: %s)  3D %.2f  MSAA %dx" % [s.tier, s.detected, s.scale, s.msaa],
		"window %dx%d" % [s.window.x, s.window.y],
	]
	if not i.is_empty():
		lines.append(str(i.get("model", "")))
		var gpu := str(i.get("gpu", ""))
		lines.append(gpu if gpu.length() <= 44 else gpu.left(43) + "…")
		lines.append("RAM %.1f GB  cores %d  screen %s" % [float(i.get("ram_gb", 0)), int(i.get("cores", 0)), str(i.get("screen", ""))])
		lines.append("why: %s" % str(i.get("why", "")))
	return "\n".join(lines)

func _update_text() -> void:
	if _label:
		_label.text = report()

func _on_panel_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		DisplayServer.clipboard_set(report())
		print("[perf] copied:\n" + report())
		get_viewport().set_input_as_handled()
