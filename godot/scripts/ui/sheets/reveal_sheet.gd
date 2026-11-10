class_name RevealSheet
extends Sheet
## The moment after a purchase: the item large over slow-turning rays in its rarity colours, "It's yours!", its name
## and "In use now" (every Shop purchase puts the item in use), one button to carry on. Replaces the old toast.
##   RevealSheet.new("pawn", "dragon", "Dragon pawns").open(layer)

const MAX_W := 360.0
const ART_H := 220.0

var kind := ""
var item_id := ""
var _rays: Control


func _init(kind_ := "dice", id := "classic", title := "") -> void:
	super("", MAX_W, true, LOOK_GAME)
	kind = kind_
	item_id = id
	var rar := ShopSheet.rarity(kind, id)
	var c: Array = Palette.RARITY.get(rar, Palette.RARITY.legendary)
	body.add_theme_constant_override("separation", UIKit.SPACE.sm)
	var chip := PanelContainer.new()
	chip.name = "Yours"
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var cs := UIKit.box(Palette.G_OUTLINE, UIKit.R.md, UIKit.BW.line, Palette.G_GOLD)
	UIKit.pad(cs, 14, 3)
	chip.add_theme_stylebox_override("panel", cs)
	chip.add_child(UIKit.label(L10n.t("It’s yours!").to_upper(), UIKit.FS.label, Palette.G_GOLD, UIKit.font_display(), HORIZONTAL_ALIGNMENT_CENTER))
	body.add_child(chip)
	var nm := UIKit.label(title, UIKit.FS.h1 + 8, Color.WHITE, UIKit.font_display(), HORIZONTAL_ALIGNMENT_CENTER)
	nm.name = "ItemName"
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.add_theme_constant_override("outline_size", 9)
	nm.add_theme_color_override("font_outline_color", Palette.G_OUTLINE)
	body.add_child(nm)
	# the stage: rays behind, the item in front
	var stage := Control.new()
	stage.name = "Stage"
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.custom_minimum_size = Vector2(0, ART_H)
	stage.clip_contents = true
	_rays = RayBurst.new(c[0], c[1])
	_rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(_rays)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(center)
	center.add_child(art(kind, id))
	stage.resized.connect(func() -> void:
		var d := maxf(stage.size.x, stage.size.y) * 1.6
		_rays.size = Vector2(d, d)
		_rays.position = (stage.size - _rays.size) / 2.0
		_rays.pivot_offset = _rays.size / 2.0)
	body.add_child(stage)
	var note := UIKit.label(L10n.t("In use now"), UIKit.FS.body_l, Palette.G_SUB, UIKit.font_body(900), HORIZONTAL_ALIGNMENT_CENTER)
	note.name = "Note"
	body.add_child(note)
	var ok := UIKit.btn(L10n.t("Awesome!"), "teal", "md")
	ok.name = "Ok"
	ok.pressed.connect(close)
	body.add_child(ok)
	fit(0.92)


func _ready() -> void:
	if Sheet.reduce_motion():
		return
	var tw := _rays.create_tween().set_loops()
	tw.tween_property(_rays, "rotation", TAU, 24.0).from(0.0)


## The item's picture for the reveal (as the Shop and its previews draw it).
static func art(kind_: String, id: String) -> Control:
	match kind_:
		"dice":
			return Thumbnailer.dice_art(id, 170)
		"pawn":
			var p := Thumbnailer.pawn_art(id)
			p.custom_minimum_size = Vector2(230, 180)
			if p is TextureRect:
				(p as TextureRect).stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			return p
		"frame":
			return Collection.make_avatar_of(Collection.equipped("avatar"), id, 170)
		"plate":
			return Collection.make_plate(str(Collection.profile().get("name", "You")), id, "", 30, true, 220.0)
		"avatar", "char":
			return Collection.make_avatar_of(id, Collection.equipped("frame"), 160)
		"room", "scene":
			var v := Thumbnailer.view(kind_, id, UIKit.R.lg)
			v.custom_minimum_size = Vector2(260, 180)
			return v
		"emotes", "text":
			var row := UIKit.hbox(UIKit.SPACE.sm)
			var pack: Dictionary = Emotes.pack(id) if kind_ == "emotes" else Emotes.text_pack(id)
			for eid: String in (pack.get("emotes", []) as Array).slice(0, 3):
				var t := TextureRect.new()
				t.texture = EmoteArt.icon(eid)
				t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				t.custom_minimum_size = Vector2(88, 88)
				t.mouse_filter = Control.MOUSE_FILTER_IGNORE
				row.add_child(t)
			return row
	return Control.new()


## Rays from the centre over a soft glow, drawn once; the reveal turns the whole control slowly (no redraws).
class RayBurst extends Control:
	var glow: Color
	var face: Color

	func _init(g: Color, f: Color) -> void:
		glow = g
		face = f
		resized.connect(queue_redraw)

	func _draw() -> void:
		var c := size / 2.0
		var r := size.x / 2.0
		for k in 7:
			draw_circle(c, r * (0.62 - k * 0.07), Color(face.lerp(glow, k / 6.0), 0.18 + k * 0.08), true, -1.0, true)
		for i in 18:
			var a0 := TAU * i / 18.0
			var a1 := a0 + TAU / 46.0
			draw_colored_polygon(PackedVector2Array([c, c + Vector2(cos(a0), sin(a0)) * r, c + Vector2(cos(a1), sin(a1)) * r]), Color(glow, 0.32))
