extends "res://tests/test_suite.gd"
## Pre-baked thumbnails (Thumbnailer.baked, res://assets/thumbs/) and the quality tiers (Quality).
## Every room, S&L scene and dice skin in the catalogue must ship a baked picture: a new item without one fails here
## (bake it with `godot --path . res://dev/bake_thumbs.tscn`). The pictures must import as UI textures: lossy WebP,
## no mipmaps, never VRAM-compressed.

func run() -> void:
	_baked()
	_quality()

func _baked() -> void:
	for kind: String in Thumbnailer.BAKED_KINDS:
		var ids := Thumbnailer.ids(kind)
		check("%s catalogue is not empty" % kind, ids.size() > 0)
		var missing := ids.filter(func(id): return not FileAccess.file_exists(Thumbnailer.baked_path(kind, id)))
		check("every %s has a baked picture in assets/thumbs" % kind, missing.is_empty(), missing)
		var bad_import := []
		for id: String in ids:
			var ip := Thumbnailer.baked_path(kind, id) + ".import"
			if not FileAccess.file_exists(ip):
				bad_import.append(id + " (no .import)")
				continue
			var txt := FileAccess.get_file_as_string(ip)
			if not (txt.contains("compress/mode=1") and txt.contains("mipmaps/generate=false") and txt.contains("detect_3d/compress_to=0")):
				bad_import.append(id)
		check("every baked %s imports lossy, no mipmaps, no VRAM compression" % kind, bad_import.is_empty(), bad_import)
		var unloadable := ids.filter(func(id): return Thumbnailer.baked(kind, id) == null)
		check("every baked %s loads" % kind, unloadable.is_empty(), unloadable)
	var room_id: String = Thumbnailer.ids("room")[0]
	var t := Thumbnailer.baked("room", room_id)
	check("baked room picture is 4:3 and 2x the preview width", t != null and t.get_width() == Thumbnailer.BAKE_SIZE.x and t.get_height() == Thumbnailer.BAKE_SIZE.y, [t.get_width(), t.get_height()] if t else null)
	check("cached() returns the baked picture (no render)", Thumbnailer.cached("room", room_id) == t)
	check("room() returns the baked picture, not the placeholder", Thumbnailer.room(room_id) == t)
	check("is_ready with a bake", Thumbnailer.is_ready("scene", Thumbnailer.ids("scene")[0]))
	check("baked(unknown) is null", Thumbnailer.baked("room", "volcano") == null)
	var v := Thumbnailer.view("room", room_id)
	check("a View of a baked room shows it at once (no placeholder, no shimmer)", v.picture.texture == t and v.picture.modulate.a == 1.0 and v._shine == null)
	v.free()
	var d := Thumbnailer.dice_art("gold")
	check("dice_art: a baked die (no Dice3D / SubViewport)", not d is Dice3D and d.get_child_count() == 1 and (d.get_child(0) as TextureRect).texture == Thumbnailer.baked("dice", "gold"))
	check("dice_art: sized like a Dice3D", d.custom_minimum_size == Vector2(Thumbnailer.DICE_SIZE, Thumbnailer.DICE_SIZE))
	d.free()
	var total := 0
	for f in DirAccess.get_files_at(Thumbnailer.BAKED_DIR):
		if f.ends_with(".webp"):
			total += FileAccess.get_file_as_bytes(Thumbnailer.BAKED_DIR + f).size()
	check("baked pictures stay small (< 1.5 MB in all)", total > 0 and total < 1_572_864, total)
	t = null
	Thumbnailer._baked.clear()               # no textures held by static caches at exit
	Thumbnailer._mem.clear()
	Thumbnailer._ph.clear()

func _quality() -> void:
	check("three tiers, each fully configured", Quality.TIERS.all(func(t): return Quality.SETTINGS.has(t) and (Quality.SETTINGS[t] as Dictionary).has_all(["scale", "msaa", "aniso", "atlas", "game_fps", "menu_fps", "extras", "live", "tex"])))
	check("tier() is a known tier", Quality.TIERS.has(Quality.tier()), Quality.tier())
	check("detected() is a known tier", Quality.TIERS.has(Quality.detected()), Quality.detected())
	Quality.force("low")
	check("force(low)", Quality.tier() == "low" and not Quality.extras() and not Quality.live_previews() and Quality.game_fps() == 30)
	Quality.force("high")
	check("force(high)", Quality.tier() == "high" and Quality.extras() and Quality.live_previews() and Quality.game_fps() == 60)
	Quality.force("")
	check("scales go down with the tier", Quality.render_scale("low") < Quality.render_scale("medium") and Quality.render_scale("medium") < Quality.render_scale("high"))
	check("high renders at full scale on a 1080p phone", is_equal_approx(Quality.render_scale("high", Vector2(1080, 2340)), 1.0))
	var k := Quality.render_scale("low", Vector2(1440, 3200))
	check("low on a 1440p panel stays in the pixel budget (never below MIN_SCALE)", k >= Quality.MIN_SCALE and (k == Quality.MIN_SCALE or 1440 * 3200 * k * k <= Quality.MAX_3D_PIXELS.low + 1), k)
	check("no shadow atlas while nothing casts positional shadows", TableWorld.SHADOWS or Quality.shadow_atlas_size("high") == 0)
	var gpus := {
		"Mali-400 MP": "low", "Mali-T830": "low", "Mali-G52 MC2": "low", "Mali-G57 MC2": "medium",
		"Mali-G78 MP14": "high", "Mali-G310": "low", "Mali-G615 MC6": "high", "Mali-G510": "medium",
		"Adreno (TM) 506": "low", "Adreno (TM) 610": "low", "Adreno (TM) 650": "high", "Adreno (TM) 740": "high",
		"PowerVR Rogue GE8320": "low", "Apple M3 Pro": "high", "Samsung Xclipse 920": "high", "Some Unknown GPU": "",
	}
	var wrong := {}
	for g: String in gpus:
		if Quality.gpu_class(g) != gpus[g]:
			wrong[g] = Quality.gpu_class(g)
	check("GPU classes", wrong.is_empty(), wrong)
	var vp := SubViewport.new()
	Quality.force("low")
	Quality.apply_sub(vp)
	check("apply_sub(low): MSAA off", vp.msaa_3d == Viewport.MSAA_DISABLED)
	Quality.force("high")
	Quality.apply_sub(vp)
	check("apply_sub(high): MSAA 4x", vp.msaa_3d == Viewport.MSAA_4X)
	Quality.force("")
	vp.free()
