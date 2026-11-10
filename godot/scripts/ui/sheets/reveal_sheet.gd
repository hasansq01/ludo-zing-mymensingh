class_name RevealSheet
extends Sheet
## The moment after a purchase (the Buying mock-up's reveal): the whole screen an orange burst (a radial glow with
## light rays turning slowly; still with Reduce motion) and a few twinkling sparkles; "NEW PAWNS!" on a dark chip, the
## name in outlined display type, the item large, a pill with what it cost and what is left ("−6,000 · 124.1K left"),
## the teal USE NOW (puts the item in use when it isn't already, then back to the Shop) and "Keep shopping" (back to
## the Shop as it is). Back is Keep shopping; a tap on the burst does nothing.
##   var rv := RevealSheet.new("pawn", "dragon", "Dragon", 6000, false)
##   rv.used.connect(...); rv.kept.connect(...); rv.open(layer)

signal used                              ## USE NOW (the item is in use now)
signal kept                              ## Keep shopping

## The chip per kind.
# l10n:begin
const NEW_TEXT := {pawn = "New pawns!", dice = "New dice!", room = "New room!", scene = "New scene!", emotes = "New emotes!",
	text = "New emotes!", char = "New character!", avatar = "New character!", frame = "New frame!", plate = "New nameplate!"}
# l10n:end
const TURN_SEC := 60.0                   ## one turn of the rays
const BASE_H := 844.0                    ## the mock's screen height (positions scale with the screen)

var kind := ""
var item_id := ""
var item_name := ""
var paid := 0
var gems := false
var burst: GamePanel
var content: Control
var _chip: PanelContainer
var _name_l: Label
var _art: Control
var _pill: PanelContainer
var _use_btn: Button
var _keep: Button
var _sparkles: Sparkles
var _acting := false


func _init(kind_ := "pawn", id := "classic", name_ := "", paid_ := 0, gems_ := false) -> void:
	super("", 390.0, false, LOOK_CARD)
	kind = kind_
	item_id = id
	item_name = name_
	paid = paid_
	gems = gems_
	dismissable = false
	back_action = _on_keep
	backdrop.color = Color("#3b1608")
	card.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	header.visible = false
	# the burst: radial-gradient(70% 45% at 50% 42%, #fff1b8, #ffbf3c 22%, #c25a12 52%, #3b1608) + 20 rays
	burst = GamePanel.radial(Color("#fff1b8"), Color("#ffbf3c"), Color("#c25a12"))
	burst.name = "Burst"
	burst.c3 = Color("#3b1608")
	burst.mid = 0.22
	burst.mid2 = 0.52
	burst.center = Vector2(0.5, 0.42)
	burst.reach = Vector2(0.7, 0.45)
	burst.radius = 0.0
	burst.rays = 0.3
	burst.ray_count = 20.0
	burst.ray_width = 7.0 / 18.0
	burst.ray_reach = 450.0
	burst.ray_angle = deg_to_rad(4.0)
	burst.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.add_child(burst)
	burst.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sparkles = Sparkles.new()
	_sparkles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.add_child(_sparkles)
	_sparkles.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content = Control.new()
	content.name = "Reveal"
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(content)
	content.resized.connect(_layout)
	# NEW PAWNS!
	_chip = PanelContainer.new()
	_chip.name = "New"
	_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cs := UIKit.box(Color("#3b1a0c"), 12)
	cs.content_margin_left = 16; cs.content_margin_right = 16 - 3
	cs.content_margin_top = 3; cs.content_margin_bottom = 3
	_chip.add_theme_stylebox_override("panel", cs)
	var cl := UIKit.label(L10n.t(str(NEW_TEXT.get(kind, "New!"))).to_upper(), 15, Color("#ffd45e"), OfferSheet.spaced_display(3))
	cl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chip.add_child(cl)
	content.add_child(_chip)
	_name_l = UIKit.label(L10n.t(item_name), 58, Color.WHITE, UIKit.font_display(), HORIZONTAL_ALIGNMENT_CENTER)
	_name_l.name = "ItemName"
	_name_l.add_theme_constant_override("outline_size", 9)
	_name_l.add_theme_color_override("font_outline_color", Color("#3b1a0c"))
	_name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(_name_l)
	_art = Control.new()
	_art.name = "Art"
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(_art)
	var a := art(kind, id)
	_art.add_child(a)
	a.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# −6,000 · 124.1K left
	_pill = PanelContainer.new()
	_pill.name = "Paid"
	_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ps := UIKit.box(Color(0.231, 0.102, 0.047, 0.75), 16)
	ps.content_margin_left = 16; ps.content_margin_right = 16
	ps.content_margin_top = 8; ps.content_margin_bottom = 8
	_pill.add_theme_stylebox_override("panel", ps)
	var ph := UIKit.hbox(8)
	ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := UIKit.icon("gem" if gems else "coin", 22)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ph.add_child(ic)
	var left := int(Save.profile.get("gems", 0)) if gems else Catalog.coins()
	var pt := UIKit.label("−%s · %s" % [Fmt.coins_full(paid), L10n.t("%s left") % (Fmt.coins_full(left) if gems else Fmt.coins(left))], 18, Color("#fff1b8"), UIKit.font_display())
	pt.name = "PaidText"
	pt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ph.add_child(pt)
	_pill.add_child(ph)
	content.add_child(_pill)
	# USE NOW / Keep shopping
	var face := OfferSheet._face(Color("#6ff0d6"), Color("#2fb39c"), Color("#1d7f6e"), Color("#0f4f44"))
	face.radius = 22.0
	face.lip2 = 5.0
	face.border = 3.0
	face.border_color = Color.WHITE
	_use_btn = OfferSheet.chunky(face)
	_use_btn.name = "UseNow"
	_use_btn.text = L10n.t("Use now")
	_use_btn.custom_minimum_size.y = 73
	var ul := UIKit.label(_use_btn.text.to_upper(), 30, Color.WHITE, UIKit.font_display(), HORIZONTAL_ALIGNMENT_CENTER)
	ul.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ul.add_theme_constant_override("outline_size", 5)
	ul.add_theme_color_override("font_outline_color", Color("#1d4f45"))
	ul.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.add_child(ul)
	_use_btn.pressed.connect(_on_use)
	content.add_child(_use_btn)
	_keep = Button.new()
	_keep.name = "KeepShopping"
	_keep.flat = true
	_keep.focus_mode = Control.FOCUS_NONE
	_keep.text = L10n.t("Keep shopping")
	for k in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		_keep.add_theme_stylebox_override(k, StyleBoxEmpty.new())
	_keep.add_theme_font_override("font", UIKit.font_display())
	_keep.add_theme_font_size_override("font_size", 19)
	for k in ["font_color", "font_hover_color", "font_focus_color"]:
		_keep.add_theme_color_override(k, Color("#fff1b8"))
	for k in ["font_pressed_color", "font_hover_pressed_color"]:
		_keep.add_theme_color_override(k, Color("#ffd45e"))
	_keep.custom_minimum_size.y = 48
	_keep.draw.connect(_underline)
	UIKit.wire_press(_keep)
	_keep.pressed.connect(_on_keep)
	content.add_child(_keep)


func _ready() -> void:
	Sound.sfx("buy")
	content.modulate.a = 0.0                 # comes in with the burst (the backdrop's fade)
	content.create_tween().tween_property(content, "modulate:a", 1.0, 0.12 if Sheet.reduce_motion() else 0.18)
	if Sheet.reduce_motion():
		return
	var tw := burst.create_tween().set_loops()
	tw.tween_property(burst, "ray_angle", deg_to_rad(4.0) + TAU / 20.0, TURN_SEC / 20.0).from(deg_to_rad(4.0))
	_sparkles.twinkle = true
	# the item lands: a quick pop of the art and the name
	for c: Control in [_art, _name_l]:
		c.pivot_offset = c.size / 2.0
		c.scale = Vector2(0.6, 0.6)
		var pt := c.create_tween()
		pt.tween_property(c, "scale", Vector2.ONE, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## The mock's positions on a 390 x 844 screen; the top part moves with the screen's height, the buttons stay at the
## bottom.
func _layout() -> void:
	var w := content.size.x
	var h := content.size.y
	if w < 10.0 or h < 10.0:
		return
	var k := clampf(h / BASE_H, 0.75, 1.2)
	var top := _safe_top() * 0.5
	var cm := _chip.get_combined_minimum_size()
	_chip.size = cm
	_chip.position = Vector2(roundf((w - cm.x) / 2.0), top + 104.0 * k)
	var fs := 58
	var font := UIKit.font_display()
	while fs > 30 and font.get_string_size(_name_l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 12.0 > w - 32.0:
		fs -= 2
	_name_l.add_theme_font_size_override("font_size", fs)
	var nm := _name_l.get_combined_minimum_size()
	_name_l.size = Vector2(w - 32.0, nm.y)
	_name_l.position = Vector2(16.0, _chip.position.y + cm.y + 4.0 - (nm.y - fs * 1.05) * 0.5 - fs * 0.42)
	var aw := minf(320.0, w - 40.0)
	var ah := 260.0 * k
	_art.size = Vector2(aw, ah)
	_art.position = Vector2(roundf((w - aw) / 2.0), top + 220.0 * k)
	_art.pivot_offset = _art.size / 2.0
	_name_l.pivot_offset = _name_l.size / 2.0
	var pm := _pill.get_combined_minimum_size()
	_pill.size = pm
	_pill.position = Vector2(roundf((w - pm.x) / 2.0), top + 500.0 * k)
	var bw := w - 64.0
	_keep.size = Vector2(bw, 48)
	_keep.position = Vector2(32.0, h - 96.0 - 48.0)
	_use_btn.size = Vector2(bw, 73)
	_use_btn.position = Vector2(32.0, _keep.position.y - 12.0 - 68.0)   # its 5 px outer lip hangs into the gap
	burst.ray_center = Vector2(0.5, (top + 360.0 * k) / h)
	_sparkles.k = k
	_sparkles.top = top
	_sparkles.queue_redraw()

## The link's underline (4 px under the text, its colour).
func _underline() -> void:
	var f := _keep.get_theme_font("font")
	var fs := _keep.get_theme_font_size("font_size")
	var tw := f.get_string_size(_keep.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var y := (_keep.size.y + f.get_ascent(fs) - f.get_descent(fs)) / 2.0 + 4.0
	var down := _keep.get_draw_mode() == BaseButton.DRAW_PRESSED or _keep.get_draw_mode() == BaseButton.DRAW_HOVER_PRESSED
	_keep.draw_line(Vector2((_keep.size.x - tw) / 2.0, y), Vector2((_keep.size.x + tw) / 2.0, y), Color("#ffd45e") if down else Color("#fff1b8"), 2.0)

## USE NOW: put it in use (a purchase usually did already), then back to the Shop.
func _on_use() -> void:
	if _acting or _closing:
		return
	if ShopSheet._owned(kind, item_id) and not ShopSheet._in_use(kind, item_id):
		_acting = true
		var why: String = await ShopSheet.equip_item(kind, item_id)
		_acting = false
		if not is_instance_valid(self) or _closing:
			return
		if why != "":
			Sound.sfx("error")
			Haptics.error()
			Toast.show(self, why, _use_btn, 2.2, "bad")
			return
	Sound.sfx("select")
	used.emit()
	close()

func _on_keep() -> void:
	if _closing:
		return
	kept.emit()
	close()


## The item's picture for the reveal, large (as the Shop and the offer draw it).
static func art(kind_: String, id: String) -> Control:
	var c := CenterContainer.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	match kind_:
		"pawn":
			return OfferSheet.pawn_pair(id)
		"dice":
			c.add_child(Thumbnailer.dice_art(id, 190))
		"frame":
			c.add_child(Collection.make_avatar_of(Collection.equipped("avatar"), id, 200))
		"plate":
			c.add_child(Collection.make_plate(str(Collection.profile().get("name", "You")), id, "", 34, true, 260.0))
		"avatar", "char":
			c.add_child(Collection.make_avatar_of(id, Collection.equipped("frame"), 200))
		"room", "scene":
			var fr := PanelContainer.new()
			fr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var st := UIKit.box(Color("#3b1a0c"), 22, 4, Color.WHITE)
			UIKit.pad(st, 0)
			fr.add_theme_stylebox_override("panel", st)
			fr.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
			var v := Thumbnailer.view(kind_, id, 0)
			v.custom_minimum_size = Vector2(300, 200)
			fr.add_child(v)
			c.add_child(fr)
		"emotes", "text":
			var g := GridContainer.new()
			g.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var pack: Dictionary = Emotes.pack(id) if kind_ == "emotes" else Emotes.text_pack(id)
			var icons: Array = (pack.get("emotes", []) as Array).slice(0, 4)
			g.columns = 2
			g.add_theme_constant_override("h_separation", 6)
			g.add_theme_constant_override("v_separation", 6)
			for eid: String in icons:
				var t := TextureRect.new()
				t.texture = EmoteArt.icon(eid)
				t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				t.custom_minimum_size = Vector2(118, 118)
				t.mouse_filter = Control.MOUSE_FILTER_IGNORE
				g.add_child(t)
			c.add_child(g)
	return c


## The mock's four white sparkles (rotated squares with a glow), twinkling unless Reduce motion.
class Sparkles extends Control:
	## [x from the left (or < 0: from the right), y, size] on the 390 x 844 mock
	const AT := [[60.0, 190.0, 12.0], [-70.0, 240.0, 9.0], [90.0, 480.0, 8.0], [-56.0, 470.0, 14.0]]
	var k := 1.0
	var top := 0.0
	var twinkle := false
	var _t := 0.0

	func _process(delta: float) -> void:
		if twinkle:
			_t += delta
			queue_redraw()

	func _draw() -> void:
		for i in AT.size():
			var a: Array = AT[i]
			var s: float = a[2]
			var x: float = a[0] if a[0] >= 0.0 else size.x + a[0] - s
			var c := Vector2(x + s / 2.0, top + a[1] * k + s / 2.0)
			var tw := 1.0 if not twinkle else 0.9 + 0.1 * sin(_t * 2.4 + i * 1.7)
			var r := s * 0.75 * tw                    # half the diagonal of the s x s square
			# box-shadow 0 0 12px 4px rgba(255,255,255,.8): a tight bright glow fading out
			for j in 6:
				var g := r + s * 0.12 + j * s * 0.13
				var q := PackedVector2Array([c + Vector2(0, -g), c + Vector2(g, 0), c + Vector2(0, g), c + Vector2(-g, 0)])
				draw_colored_polygon(q, Color(1, 1, 1, 0.16 * tw))
			var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
			draw_colored_polygon(pts, Color.WHITE)
