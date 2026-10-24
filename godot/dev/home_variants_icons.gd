extends Control
## Dev (W1): the home icon family (assets/ui/home/hi_*.svg) on one sheet at 96 / 48 / 24 px, on cream, on the
## night plum and over the real café lobby. godot --path . --resolution 1400x820 res://dev/home_variants_icons.tscn -- <out.png> [cafe.png]

const NAMES := ["ludo", "snakes", "cpu", "pass_play", "home", "shop", "profile", "gear", "spin", "gift", "coins", "coin", "again", "resume"]

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "/tmp/icons.png"
	var cafe := args[1] if args.size() > 1 else ""
	var bg := ColorRect.new()
	bg.color = Palette.CARD
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var bands := [["On cream", Palette.CARD, Palette.INK], ["On the night lobby", Palette.PLUM_NIGHT, Color.WHITE], ["Over the café", Color.TRANSPARENT, Color.WHITE]]
	var y := 8.0
	var bh := 262.0
	for i in bands.size():
		var b: Array = bands[i]
		var band := Control.new()
		band.position = Vector2(0, y)
		band.size = Vector2(size.x, bh)
		band.clip_contents = true
		add_child(band)
		if b[1].a > 0:
			var r := ColorRect.new()
			r.color = b[1]
			r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			band.add_child(r)
		elif cafe != "":
			var img := Image.load_from_file(cafe)
			var tr := TextureRect.new()
			tr.texture = ImageTexture.create_from_image(img)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			band.add_child(tr)
		var t := UIKit.label(b[0], 14, b[2], UIKit.font_body(900))
		t.position = Vector2(16, 4)
		band.add_child(t)
		for k in NAMES.size():
			var col := k % 7
			var row := k / 7
			var x0 := 16.0 + col * 196.0
			var y0 := 28.0 + row * 116.0
			var px := 0.0
			for s in [96.0, 48.0, 24.0]:
				var ic := UIKit.icon("res://assets/ui/home/hi_%s.svg" % NAMES[k], s)
				ic.size = Vector2(s, s)
				ic.position = Vector2(x0 + px, y0 + (96.0 - s) / 2.0)
				band.add_child(ic)
				px += s + 8.0
			var nl := UIKit.label(NAMES[k], 12, b[2], UIKit.font_body(800))
			nl.position = Vector2(x0, y0 + 96)
			band.add_child(nl)
		y += bh + 8.0
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
	get_tree().quit()
