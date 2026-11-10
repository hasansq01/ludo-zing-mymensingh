class_name EmotePackSheet
extends OfferSheet
## The Shop's offer of an emote pack or a text pack (kind "emotes" | "text") on the offer card (OfferSheet): its emotes
## playing their animation (EmoteArt.frames; stickers with their names) where the art goes, how many there are, and
## the action (price, "or N gems", "Need 2.5K", Use, In use). Buy / Use go through the server wallet (Account) when
## there is one, else the local rules (previews, tests).
## A few animations loop seamlessly (SEAMLESS, and the phrases' gentle bob); the others replay with a short pause.
##   var s := EmotePackSheet.new("pawns"); s.changed.connect(refresh_shop); s.open(layer)

const SEAMLESS := ["happy", "party", "cheer"]
## The emotes' display names (assets/emotes/emotes.json, shown through L10n.t), listed for the extractor.
const _EMOTE_NAMES := ["Happy", "Laugh", "Cry", "Angry", "Shocked", "Love", "Celebrate", "Cool", "Tease", "Hi!", "High five",
	"Confused", "Facepalm", "Heartbroken", "Winner", "Champ", "Roll it!", "Peek-a-boo", "Thinking", "Hmph!", "Give up", "Sleepy"]  # l10n
const PAUSE_SEC := 0.9                   ## held on the last frame between two plays of a non-looping emote

var pack_id: String:
	get: return item_id
var _cells: Array[EmoteCell] = []


func _init(pack_id_ := "starter", kind_ := "emotes") -> void:
	var k := "text" if kind_ == "text" else "emotes"
	var pk := Emotes.text_pack(pack_id_) if k == "text" else Emotes.pack(pack_id_)
	super(k, pack_id_, str(pk.get("name", "Emotes")))


func _pack() -> Dictionary:
	return Emotes.text_pack(item_id) if kind == "text" else Emotes.pack(item_id)

## The pack's emotes playing, four to a row (three for a pack of six).
func _make_art() -> Control:
	var emotes: Array = _pack().get("emotes", [])
	var g := GridContainer.new()
	g.name = "Grid"
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.columns = 3 if emotes.size() <= 6 else 4
	g.add_theme_constant_override("h_separation", 4)
	g.add_theme_constant_override("v_separation", 6)
	var k := 0
	for eid: String in emotes:
		var cell := EmoteCell.new(eid, float(k) * 0.22)
		_cells.append(cell)
		g.add_child(cell)
		k += 1
	var c := CenterContainer.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(g)
	return c

func _fact_list() -> Array:
	var pk := _pack()
	var n := (pk.get("emotes", []) as Array).size()
	var out: Array = [(tr("%d phrases") if kind == "text" else tr("%d animated emotes")) % n]
	if bool(pk.get("premium", false)):
		out.append(tr("Premium"))
	return out


## One emote: its animation on a tinted well and its name under it. Plays through, and for the emotes that don't
## loop seamlessly rests on the last frame for PAUSE_SEC before the next play. Plays only while it is on screen.
class EmoteCell extends VBoxContainer:
	var emote_id := ""
	var _rect: TextureRect
	var _frames: SpriteFrames
	var _t := 0.0
	var _seamless := false

	func _init(id: String, offset_sec := 0.0) -> void:
		emote_id = id
		name = "Emote_%s" % id
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_theme_constant_override("separation", 2)
		var phrase := bool(EmoteArt.info(id).get("text", false))
		_seamless = SEAMLESS.has(id) or phrase
		_frames = EmoteArt.frames(id)
		_t = offset_sec
		_rect = TextureRect.new()
		_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_rect.custom_minimum_size = Vector2(70, 92 if phrase else 74)
		_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_rect.texture = EmoteArt.icon(id)
		add_child(_rect)
		var nm := L10n.t(str(EmoteArt.info(id).get("name", id)))
		var l := UIKit.label(nm, 11, Color.WHITE, UIKit.font_body(900), HORIZONTAL_ALIGNMENT_CENTER)
		l.name = "Name"
		l.add_theme_constant_override("outline_size", 4)
		l.add_theme_color_override("font_outline_color", Color(0.1, 0.03, 0.2, 0.8))
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.custom_minimum_size.x = 72
		l.visible = not phrase              # a phrase's sticker already says it
		add_child(l)
		_show(0.0)

	## Seconds of one play (frames / fps).
	func play_sec() -> float:
		if _frames == null or not _frames.has_animation("default"):
			return 0.0
		var fps := _frames.get_animation_speed("default")
		return float(_frames.get_frame_count("default")) / fps if fps > 0.0 else 0.0

	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		_t += delta
		_show(_t)

	## The frame at time t: a seamless loop wraps; the others play once, hold on the last frame, then start over.
	func frame_at(t: float) -> int:
		if _frames == null:
			return 0
		var n := _frames.get_frame_count("default")
		var d := play_sec()
		if n == 0 or d <= 0.0:
			return 0
		var cyc := d if _seamless else d + PAUSE_SEC
		var u := fposmod(t, cyc)
		return mini(int(u / d * n), n - 1)

	func _show(t: float) -> void:
		if _frames == null:
			return
		var n := _frames.get_frame_count("default")
		if n > 0:
			_rect.texture = _frames.get_frame_texture("default", frame_at(t))
