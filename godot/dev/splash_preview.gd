extends Control
## Preview: splash progress 0 -> 1, finish, then Celebrate on cream. Screenshots to OUT, then quits.

const OUT := "/private/tmp/claude-501/-Users-shihabshaharia-Coding-ludo-zing-mymensingh/d8feebe6-eee1-4f48-a116-aa2f313481c9/scratchpad/agent_splash/"

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var tag := "%dx%d" % [int(get_viewport_rect().size.x), int(get_viewport_rect().size.y)]
	var cream := ColorRect.new()
	cream.color = Palette.CREAM
	cream.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(cream)
	var splash := Splash.new()
	add_child(splash)
	var t := 0.0
	var shot50 := false
	while t < 1.5:
		await get_tree().process_frame
		t += get_process_delta_time()
		splash.set_progress(t / 1.5)
		if not shot50 and t > 0.8:
			shot50 = true
			await _shot("splash_50_" + tag)
	var fin := splash.finish
	var done := [false]
	(func(): await fin.call(); done[0] = true).call()
	while splash._shown < 1.0:
		await get_tree().process_frame
	await get_tree().create_timer(0.2).timeout
	await _shot("splash_finish_" + tag)
	await get_tree().create_timer(0.45).timeout
	await _shot("splash_fade_" + tag)
	while not done[0]:
		await get_tree().process_frame
	for style in ["burst", "cannons", "flares", "rain"]:
		var t0 := Time.get_ticks_msec()
		Celebrate.run(self, style)
		await get_tree().create_timer(0.6 if style != "flares" else 1.35).timeout
		var t1 := Time.get_ticks_msec()
		await _shot("celebrate_%s_%s" % [style, tag])
		print("  timer %d ms, shot %d ms" % [t1 - t0, Time.get_ticks_msec() - t1])
		await get_tree().create_timer(3.2).timeout
		print("children after %s: %d" % [style, get_child_count()])
	var kinds := []
	for i in 6:
		var c := Celebrate.run(self)
		kinds.append(c.kind)
		c.queue_free()
	print("random kinds: ", kinds)
	get_tree().quit()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + name + ".png")
	print("saved ", name)
