extends Node
## Dev: performance probe of the real app at one quality tier. Loads main (timing the splash), idles on Home, opens the
## Shop (time from open to the first room thumbnail visible, and to all of them), shows the Dice tab, then plays a
## Ludo match (four computers) and a Snakes & Ladders match, and prints per phase: average / p95 / peak frame time,
## average GPU time of the main view, draw calls, primitives, video / texture memory.
## Frames are uncapped (vsync off, max_fps 0) so the numbers compare the work per frame, not the frame cap.
##   godot --path . --resolution 390x844 res://dev/perf_probe.tscn -- [low|medium|high|auto] [nobake] [win=WxH] [hitch]
## hitch: instead, times the main-thread pieces one by one (wall time and the longest frame): a 2048 bake and its
## steps, the café build, the S&L board build, every room switch, every S&L scene build, the first Dice3D.
## nobake: the Shop's thumbnails render live (Thumbnailer.use_baked = false, own empty cache dir): the "before".
## win=WxH: the window in pixels (e.g. 1080x2340 for a phone's 3D load; the UI stays 390 wide).
## The real save is never written (flush unhooked; the file is restored at the end anyway).

const PHASE_SEC := {home = 2.5, dice = 2.0, ludo = 8.0, sl = 8.0}

var main: Node
var tier := "auto"
var nobake := false
var _backup := ""
var _had_save := false
var _frames: Array = []                  # [usec] of the running phase
var _gpu: Array = []
var _calls: Array = []
var _prims: Array = []
var _last := 0
var _rec := false
var _spikes: Array = []                  # frames over 50 ms in the running phase
var _t_begin := 0
var results := {}
var hitch := false
var shot_dir := ""                       # shots=<dir>: a screenshot of each match (checks the tier's look)
var warm := false                        # draw the hidden HUD dice once on Home (what a splash warm-up would do)


func _ready() -> void:
	get_tree().create_timer(240.0).timeout.connect(func():
		print("perf_probe: timeout")
		_finish())
	for a: String in OS.get_cmdline_user_args():
		if a in Quality.TIERS or a == "auto":
			tier = a
		elif a == "nobake":
			nobake = true
		elif a == "hitch":
			hitch = true
		elif a == "warm":
			warm = true
		elif a.begins_with("shots="):
			shot_dir = a.trim_prefix("shots=")
		elif a.begins_with("win="):
			var p := a.trim_prefix("win=").split("x")
			DisplayServer.window_set_size(Vector2i(int(p[0]), int(p[1])))
	_had_save = FileAccess.file_exists("user://save.json")
	if _had_save:
		_backup = FileAccess.get_file_as_string("user://save.json")
	if Save._timer and Save._timer.timeout.is_connected(Save.flush):
		Save._timer.timeout.disconnect(Save.flush)
	var nowrite := func(_p: Dictionary) -> bool:
		return true
	Catalog.writer = nowrite
	Collection.writer = nowrite
	Save.prefs.welcome_seen = true
	Save.prefs.tutorial_done = true
	Rewards.mark_auto_open(Save.profile)          # no daily sheet popping up mid-measurement
	if nobake:
		Thumbnailer.use_baked = false
		Thumbnailer.dir = "user://perf_thumbs/"
		Thumbnailer.clear(true)
	Quality.force("" if tier == "auto" else tier)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	await get_tree().process_frame
	Quality.apply(get_viewport())
	print("perf_probe: tier %s (detected %s) %s, window %s, 3D scale %.2f, msaa %d, atlas %d" % [Quality.tier(),
		Quality.detected(), Quality.info, DisplayServer.window_get_size(), get_viewport().scaling_3d_scale,
		get_viewport().msaa_3d, get_viewport().positional_shadow_atlas_size])
	if hitch:
		await _hitches()
		_finish()
		return
	# ---- splash ----
	var t0 := Time.get_ticks_msec()
	main = load("res://scenes/main.tscn").instantiate()
	_begin()
	add_child(main)
	await _until(func(): return main.screen == "home", 60)
	_end("splash")
	results.splash.ms = Time.get_ticks_msec() - t0
	main.close_all_sheets()
	if warm:
		for d in [main.hud.get("dice"), main.sl.get("dice")]:
			if d is Dice3D:
				d.viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		await get_tree().process_frame
		await get_tree().process_frame
		_begin()
		await main.sl_scenes.set_scene(main.baker, SLScenes.scene_in_use())   # the equipped scene, built hidden
		_end("warm_sl_prebuild")
		_begin()                                 # one drawn frame of it (under the splash, in the real fix)
		main.sl_board.visible = true
		main._show_world(false)
		for i in 3:
			await get_tree().process_frame
		main._show_world(true)
		main.sl_board.visible = false
		_end("warm_sl_draw")
	# ---- home ----
	await _measure("home", PHASE_SEC.home)
	# ---- shop: open -> first / all room thumbnails visible ----
	_begin()
	var s0 := Time.get_ticks_usec()
	var shop := ShopSheet.new("rooms", 400.0, false)
	main._wire_shop(shop)
	shop.open(main.sheet_layer)
	var first := -1.0
	var all := -1.0
	while Time.get_ticks_usec() - s0 < 60_000_000:
		await get_tree().process_frame
		var views := _views(shop)
		var shown := views.filter(func(v): return v.picture.texture != null and v.picture.modulate.a > 0.99)
		if first < 0.0 and shown.size() > 0:
			first = (Time.get_ticks_usec() - s0) / 1000.0
		if views.size() > 0 and shown.size() == views.size():
			all = (Time.get_ticks_usec() - s0) / 1000.0
			break
	_end("shop_rooms")
	results.shop_rooms.first_thumb_ms = snappedf(first, 0.1)
	results.shop_rooms.all_thumbs_ms = snappedf(all, 0.1)
	if shop._tabs:
		shop._tabs.tap("dice")
	await _measure("shop_dice", PHASE_SEC.dice)
	main.close_all_sheets()
	await _sleep(0.3)
	# ---- Ludo: four computers ----
	_begin()
	main.start_ludo({game = "ludo", players = ["cpu", "cpu", "cpu", "cpu"], teams = false})
	await _sleep(PHASE_SEC.ludo)
	_end("ludo")
	await _shot("ludo")
	main.go_home()
	await _sleep(0.5)
	# ---- Snakes & Ladders ----
	_begin()
	main.start_sl({game = "sl", mode = "cpu", n = 4, color = 0})
	await _sleep(PHASE_SEC.sl)
	_end("sl")
	await _shot("sl")
	_finish()

## Times one awaitable step: wall ms and the longest frame while it ran.
func _timed(label: String, fn: Callable) -> void:
	await get_tree().process_frame
	_begin()
	var t := Time.get_ticks_usec()
	await fn.call()
	var wall := (Time.get_ticks_usec() - t) / 1000.0
	await get_tree().process_frame
	_end(label)
	results[label] = {wall_ms = snappedf(wall, 0.1), peak_ms = results[label].get("peak_ms", 0.0), frames = results[label].frames}

func _hitches() -> void:
	var baker := TexBaker.new()
	add_child(baker)
	await _timed("bake_2048_board", func(): await baker.bake(Vector2i(2048, 2048), LudoBoard.paint))
	await _timed("bake_2048_nomips", func(): await baker.bake(Vector2i(2048, 2048), LudoBoard.paint, false, false))
	await _timed("bake_1024", func(): await baker.bake(Vector2i(1024, 1024), LudoBoard.paint))
	# the read-back steps of one 2048 bake, on their own
	var vp := SubViewport.new()
	vp.size = Vector2i(2048, 2048)
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var painter := TexBaker.Painter.new()
	painter.fn = LudoBoard.paint
	painter.size = Vector2(2048, 2048)
	vp.add_child(painter)
	add_child(vp)
	await RenderingServer.frame_post_draw
	var t := Time.get_ticks_usec()
	var img := vp.get_texture().get_image()
	var t_get := Time.get_ticks_usec()
	img.generate_mipmaps()
	var t_mip := Time.get_ticks_usec()
	var tex := ImageTexture.create_from_image(img)
	var t_up := Time.get_ticks_usec()
	results.bake_steps = {get_image_ms = (t_get - t) / 1000.0, mipmaps_ms = (t_mip - t_get) / 1000.0,
		upload_ms = (t_up - t_mip) / 1000.0, format = img.get_format()}
	vp.queue_free()
	tex = null
	var world := TableWorld.new()
	await _timed("cafe_new", func(): add_child(world))
	await _timed("cafe_build_room", func(): await world.build_room(baker, func(_f): pass, "night"))
	for id: String in Thumbnailer.ids("room"):
		if id != "night":
			await _timed("room_switch_" + id, func(): await world.rooms.set_room(baker, id))
	await _timed("room_switch_back_night", func(): await world.rooms.set_room(baker, "night"))
	var board := SLBoard.new()
	var scenes := SLScenes.new()
	scenes.visible = false
	add_child(scenes)
	scenes.attach_board(board)
	await _timed("sl_board_build", func(): await board.build(baker))
	for id: String in Thumbnailer.ids("scene"):
		await _timed("sl_scene_" + id, func(): await scenes.set_scene(baker, id))
	world.queue_free()
	scenes.queue_free()
	await get_tree().process_frame
	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(holder)
	await _timed("first_dice3d", func():
		var d := Dice3D.new()
		holder.add_child(d)
		await get_tree().process_frame
		await get_tree().process_frame)
	await _timed("second_dice3d", func():
		var d := Dice3D.new()
		holder.add_child(d)
		await get_tree().process_frame
		await get_tree().process_frame)
	var d1: Dice3D = holder.get_child(0)
	await _timed("third_dice3d_shared_shader", func():
		var d := Dice3D.new()
		holder.add_child(d)
		d.mat.shader = d1.mat.shader             # what one static Shader shared by every Dice3D would cost
		await get_tree().process_frame
		await get_tree().process_frame)
	await _timed("baked_dice_art", func():
		holder.add_child(Thumbnailer.dice_art("gold"))
		await get_tree().process_frame
		await get_tree().process_frame)

func _shot(what: String) -> void:
	if shot_dir == "":
		return
	DirAccess.make_dir_recursive_absolute(shot_dir)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shot_dir.path_join("%s_%s.png" % [what, Quality.tier()]))

func _views(n: Node) -> Array:
	var out := []
	for c in n.get_children():
		if c is Thumbnailer.View:
			out.append(c)
		out.append_array(_views(c))
	return out

func _process(_d: float) -> void:
	Engine.max_fps = 0                        # main caps menus at 30: uncapped while measuring
	var now := Time.get_ticks_usec()
	if _rec and _last > 0:
		_frames.append(now - _last)
		if now - _last > 50000:
			_spikes.append("%.0f ms at +%.2f s (nodes %d, screen %s)" % [(now - _last) / 1000.0, (now - _t_begin) / 1e6,
				Performance.get_monitor(Performance.OBJECT_NODE_COUNT), main.screen if main else "-"])
		var rid := get_viewport().get_viewport_rid()
		_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
		_calls.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		_prims.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	_last = now

func _begin() -> void:
	_frames.clear()
	_gpu.clear()
	_calls.clear()
	_prims.clear()
	_spikes.clear()
	_t_begin = Time.get_ticks_usec()
	_rec = true

func _end(phase: String) -> void:
	_rec = false
	var f := _frames.duplicate()
	f.sort()
	var n := f.size()
	var avg := 0.0
	for x in f:
		avg += x
	var r := {frames = n}
	if n > 0:
		r.avg_ms = snappedf(avg / n / 1000.0, 0.01)
		r.p95_ms = snappedf(f[int(n * 0.95)] / 1000.0, 0.01)
		r.peak_ms = snappedf(f[n - 1] / 1000.0, 0.01)
		r.gpu_ms = snappedf(_mean(_gpu), 0.01)
		r.draw_calls = roundi(_mean(_calls))
		r.primitives = roundi(_mean(_prims))
	r.nodes = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	if not _spikes.is_empty():
		r.spikes = _spikes.duplicate()
	r.vmem_mb = snappedf(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0, 0.1)
	r.tex_mb = snappedf(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED) / 1048576.0, 0.1)
	results[phase] = r

static func _mean(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for x in a:
		s += float(x)
	return s / a.size()

func _measure(phase: String, sec: float) -> void:
	_begin()
	await _sleep(sec)
	_end(phase)

func _finish() -> void:
	print("PERF %s%s %s" % [Quality.tier(), " nobake" if nobake else "", JSON.stringify(results)])
	for k in results:
		print("  %-11s %s" % [k, results[k]])
	if nobake:
		Thumbnailer.clear(true)               # the probe's own cache dir
	if _had_save:
		var cur := FileAccess.get_file_as_string("user://save.json")
		if cur != _backup:
			var fw := FileAccess.open("user://save.json", FileAccess.WRITE)
			if fw:
				fw.store_string(_backup)
	get_tree().quit()

func _sleep(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _until(cond: Callable, timeout: float) -> void:
	var t := 0.0
	while not cond.call() and t < timeout:
		await get_tree().process_frame
		t += get_process_delta_time()
