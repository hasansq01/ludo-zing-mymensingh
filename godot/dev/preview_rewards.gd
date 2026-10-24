extends Control
## Dev preview for the reward sheets: shows one over a warm background, saves screenshots and quits. Works on a copy
## of the profile and never writes user://save.json.
##   godot --path . res://dev/preview_rewards.tscn -- daily [fresh|today|missed|claim|claim7|done|day7|owned] [narrow] [fly] [out_dir]
##   godot --path . res://dev/preview_rewards.tscn -- spin [ready|spun|run|jackpot] [narrow] [fly] [out_dir]
## fly: a stand-in home coin counter at the top (DailySheet.coin_target_override), so claims fly coins to it;
## without it the sheets use the fallback (coin burst + Toast).

const OUT := "/private/tmp/claude-501/-Users-shihabshaharia-Coding-ludo-zing-mymensingh/d8feebe6-eee1-4f48-a116-aa2f313481c9/scratchpad/agent_rewards"

var out := OUT
var tag := ""

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UIKit.theme()
	var bg := TextureRect.new()
	var g := GradientTexture2D.new()
	g.gradient = Gradient.new()
	g.gradient.set_color(0, Color("#ffd9a8"))
	g.gradient.set_color(1, Color("#f29a6b"))
	g.fill_to = Vector2(0, 1)
	bg.texture = g
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layer)
	Save._timer.timeout.disconnect(Save.flush)   # previews never write the real save file
	Save.profile = Save.profile.duplicate(true)  # ... and work on a copy
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("/"):
			out = a
	if args.has("narrow"):
		get_tree().root.content_scale_size = Vector2i(320, 844)
		await get_tree().process_frame
	var which := args[0] if args.size() > 0 else "daily"
	var mode := args[1] if args.size() > 1 and not args[1].begins_with("/") and args[1] != "narrow" and args[1] != "fly" else ""
	tag = "%s_%s%s%s" % [which, mode, "_narrow" if args.has("narrow") else "", "_fly" if args.has("fly") else ""]
	var p := Save.profile
	if args.has("fly"):
		var counter := CoinAmount.new(5000, "lg", "night")
		counter.position = Vector2(get_viewport_rect().size.x - 150, 22)
		add_child(counter)
		DailySheet.coin_target_override = counter
	var today := Rewards.day_key()
	var y := Rewards.add_days(today, -1)
	p.coins = 5000
	p.dice_owned = ["classic"]
	if which == "daily":
		match mode:
			"fresh": p.daily = {}
			"missed": p.daily = {cycle = 0, streak = 4, last = Rewards.add_days(today, -3), history = []}
			"done": p.daily = {cycle = 0, streak = 7, last = today, history = []}
			"day7", "claim7": p.daily = {cycle = 0, streak = 6, last = y, history = []}
			"owned":
				p.daily = {cycle = 0, streak = 3, last = y, history = []}
				p.dice_owned = ["classic", "crema"]
			_: p.daily = {cycle = 0, streak = 3, last = y, history = []}
		var s := DailySheet.new()
		s.claimed.connect(func(r): print("claimed ", r))
		s.open(layer)
		await get_tree().create_timer(0.9).timeout
		if mode == "claim" or mode == "claim7":
			s._claim()
			await get_tree().create_timer(0.16).timeout
			shot("a")
			await get_tree().create_timer(0.3).timeout
			shot("b")
			await get_tree().create_timer(0.3).timeout
			shot("c")
			await get_tree().create_timer(1.6).timeout
			print("coins ", p.coins, " owned ", p.dice_owned, " daily ", p.daily)
			s._claim()   # a second tap: nothing
			print("after second tap coins ", p.coins)
		shot("")
	else:
		p.last_spin = today if mode == "spun" else ""
		var s := SpinSheet.new()
		s.rng.seed = 5
		if mode == "jackpot":   # find a seed that lands on the 1000 segment
			for sd in 200:
				var t := RandomNumberGenerator.new()
				t.seed = sd
				if t.randi_range(0, Rewards.PRIZES.size() - 1) == SpinSheet.JACKPOT:
					s.rng.seed = sd
					break
		s.spun.connect(func(prize): print("spun ", prize, " coins ", p.coins, " last_spin ", p.last_spin))
		s.open(layer)
		await get_tree().create_timer(0.9).timeout
		if mode == "run" or mode == "jackpot":
			s._spin()
			for t in [0.5, 1.5, 3.0]:
				await get_tree().create_timer(t - (0.0 if t == 0.5 else (0.5 if t == 1.5 else 1.5))).timeout
				shot("t%.1f" % t)
			await get_tree().create_timer(1.5).timeout
			shot("landed")
			await get_tree().create_timer(1.5).timeout
		shot("")
	Save._dirty = false   # previews never write the real save file
	get_tree().quit()

func shot(suffix: String) -> void:
	var vs := get_viewport_rect().size
	var path := "%s/%s%s_%dx%d.png" % [out, tag, ("_" + suffix) if suffix != "" else "", int(vs.x), int(vs.y)]
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
