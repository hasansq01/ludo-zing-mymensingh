class_name EmoteArt
extends RefCounted
## Animated emote stickers (captured from the web version, see assets/emotes/emotes.json).
## frames(id): SpriteFrames with one "default" animation (looping); the hold phase of the web sticker.
## icon(id): static frame for pickers and the shop. manifest(): {"emotes": [...], "sets": [...]}.

const DIR := "res://assets/emotes"
## How many emotes' animations stay in memory once nothing plays them: a frame is ~300 KB of video memory (344 x 218,
## uncompressed), an emote up to 37 frames (~11 MB), and all 70 together ~470 MB. Whoever plays one holds its own
## reference, so dropping it from here never stops a sticker on screen.
const KEEP_FRAMES := 6

static var _manifest: Dictionary = {}
static var _frames: Dictionary = {}      # id -> SpriteFrames; insertion order is oldest use first
static var _icons: Dictionary = {}


static func manifest() -> Dictionary:
	if _manifest.is_empty():
		var f := FileAccess.open(DIR + "/emotes.json", FileAccess.READ)
		if f != null:
			var data: Variant = JSON.parse_string(f.get_as_text())
			if data is Dictionary:
				_manifest = data
	return _manifest


## The manifest row of one emote ({} when unknown).
static func info(id: String) -> Dictionary:
	for e in manifest().get("emotes", []):
		if e.get("id", "") == id:
			return e
	return {}


static func icon(id: String) -> Texture2D:
	if not _icons.has(id):
		var path := "%s/%s/icon.webp" % [DIR, id]
		_icons[id] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _icons[id]


static func frames(id: String) -> SpriteFrames:
	if _frames.has(id):
		var kept: SpriteFrames = _frames[id]
		_frames.erase(id)                # back in as the newest
		_frames[id] = kept
		return kept
	var e := info(id)
	var sf: SpriteFrames = null
	if not e.is_empty():
		sf = SpriteFrames.new()
		sf.set_animation_speed("default", float(e.get("fps", 15.0)))
		sf.set_animation_loop("default", true)
		for i in int(e.get("frames", 0)):
			var tex := load("%s/%s/%03d.webp" % [DIR, id, i]) as Texture2D
			if tex != null:
				sf.add_frame("default", tex)
	_frames[id] = sf
	while _frames.size() > KEEP_FRAMES:
		_frames.erase(_frames.keys()[0])
	return sf
