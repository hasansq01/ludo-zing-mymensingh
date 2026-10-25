extends "res://tests/test_suite.gd"
## EmoteArt: the captured emote stickers (manifest integrity, frames and icons present).

func run() -> void:
	var m := EmoteArt.manifest()
	var emotes: Array = m.get("emotes", [])
	var sets: Array = m.get("sets", [])
	check("emotes: 24 in the manifest", emotes.size() == 24, emotes.size())
	check("emotes: 4 sets of 6", sets.size() == 4 and sets.all(func(s: Dictionary) -> bool: return s.emotes.size() == 6), sets.size())
	var prices: Array = sets.map(func(s: Dictionary) -> int: return int(s.price))
	check("emotes: set prices", prices == [0, 2500, 4000, 3500], prices)
	var ids := {}
	for e in emotes:
		ids[e.id] = true
	check("emotes: ids unique", ids.size() == 24, ids.size())
	var in_sets := true
	for s in sets:
		for id in s.emotes:
			in_sets = in_sets and ids.has(id)
	check("emotes: every set member exists", in_sets)
	var missing: Array = []
	for e in emotes:
		for i in int(e.frames):
			if not ResourceLoader.exists("res://assets/emotes/%s/%03d.webp" % [e.id, i]):
				missing.append("%s/%d" % [e.id, i])
		if EmoteArt.icon(e.id) == null:
			missing.append(e.id + "/icon")
	check("emotes: every frame file and icon loads", missing.is_empty(), missing)
	var sf := EmoteArt.frames("happy")
	var want := int(EmoteArt.info("happy").frames)
	check("frames: SpriteFrames built from the manifest", sf != null and sf.get_frame_count("default") == want, want)
	check("frames: cached", EmoteArt.frames("happy") == sf)
	check("frames: unknown id is null", EmoteArt.frames("nope") == null and EmoteArt.icon("nope") == null)
	var t := EmoteArt.icon("happy")
	check("icon: full size with alpha", t != null and t.get_width() == 344 and t.get_height() == 218 and t.get_image().detect_alpha() != Image.ALPHA_NONE)
