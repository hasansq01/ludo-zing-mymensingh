class_name WinCard
extends Control
## The picture a player shares after a win (1080 x 1350, the 4:5 feed shape), in the game look of the result screen:
## the orange burst with light rays and sparkles inside a gold rim, the Ludo Zing logo (the owner's art, drawn
## unchanged), your avatar in its equipped frame under a crown, "1ST PLACE · LUDO" on a dark chip, your name in outlined
## white display type, the title in big outlined gold ("YOU WIN!") and the coins won on a dark pill. Drawn at its real
## size (not a scaled-up 360 px layout) so the text stays sharp; every size below is in output pixels.
##
##   var card := WinCard.new({name = "Mocha", place = 1, title = "You win!", coins = 228, game = "ludo"})
##   var path := await WinCard.render(host, data)        # user://share/win_card.png, "" when nothing was drawn
## data: name, title, place (1st / 2nd ...), coins (0 = no coins line), game ("ludo" | "sl"); avatar and frame
## (ids; empty = the equipped ones from the live profile).
## render() draws the card once, in a SubViewport it frees right after (never UPDATE_ONCE on a viewport that lives on:
## it turns itself to UPDATE_DISABLED), and saves the PNG; it costs one frame on the phone and nothing afterwards.

const W := 1080
const H := 1350
const DIR := "user://share"
const FILE := "win_card.png"
const AVA := 340.0
const AVA_TOP := 428.0

var data := {}


func _init(data_: Dictionary = {}) -> void:
	data = data_
	size = Vector2(W, H)
	custom_minimum_size = size
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UIKit.theme()
	_build()

## "1ST PLACE · LUDO": the eyebrow over the name.
func eyebrow_text() -> String:
	return "%s · %s" % [L10n.t("%s place") % ResultScreen.ordinal(int(data.get("place", 1))),
		Share.game_name(str(data.get("game", "ludo")))]

## The title in the ribbon: data.title, else "You win!".
func title_text() -> String:
	var t := str(data.get("title", ""))
	return t if t != "" else L10n.t("You win!")

func _build() -> void:
	var cx := W / 2.0
	# the burst behind everything (the result screen's): glow on the avatar, rays all round
	var burst := GamePanel.radial(Palette.GL_GOLD_GLOW, Palette.GL_GOLD, Palette.GL_BURST_MID)
	burst.c3 = Palette.GL_BURST_DEEP
	burst.mid = 0.2
	burst.mid2 = 0.55
	burst.center = Vector2(0.5, (AVA_TOP + AVA / 2.0) / H)
	burst.reach = Vector2(0.95, 0.95 * float(W) / float(H))
	burst.radius = 0.0
	burst.rays = 0.26
	burst.ray_count = 20.0
	burst.ray_width = 7.0 / 18.0
	burst.ray_center = burst.center
	burst.ray_angle = deg_to_rad(4.0)
	burst.position = Vector2.ZERO
	burst.size = Vector2(W, H)
	add_child(burst)
	# (built before the card joins a tree, so no `resized` reaches the shader: hand it the size once it is ready)
	burst.ready.connect(burst.set.bind("radius", 0.0))
	var logo := BrandLogo.new()
	logo.size = Vector2(400, 274)
	logo.position = Vector2(cx - 200.0, 64)
	add_child(logo)
	# the avatar: a soft shadow under it, the avatar's own frame ring, the crown on top
	var ava_top := AVA_TOP
	var shadow := Panel.new()
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ss := UIKit.box(Color(Palette.GL_INK, 0.0), 96)
	ss.shadow_size = 46
	ss.shadow_color = Color(0, 0, 0, 0.4)
	ss.shadow_offset = Vector2(0, 22)
	shadow.add_theme_stylebox_override("panel", ss)
	shadow.position = Vector2(cx - AVA / 2.0 + 24, ava_top + 24)
	shadow.size = Vector2(AVA - 48, AVA - 48)
	add_child(shadow)
	var id := str(data.get("avatar", ""))
	var ava: Control
	if id != "":
		ava = Collection.make_avatar_of(id, str(data.get("frame", "classic")), AVA)
	else:
		ava = Collection.make_avatar(AVA)
	ava.position = Vector2(cx - AVA / 2.0, ava_top)
	add_child(ava)
	var crown := UIKit.icon("ic_crown", 150)
	crown.size = Vector2(150, 150)
	crown.pivot_offset = Vector2(75, 115)
	crown.rotation = deg_to_rad(-8.0)
	crown.position = Vector2(cx - 75.0, ava_top - 98.0)
	crown.visible = int(data.get("place", 1)) == 1
	add_child(crown)
	_chip(eyebrow_text().to_upper(), 798.0)
	var who := str(data.get("name", ""))
	var px := 92
	while px > 56 and UIKit.font_display().get_string_size(who, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > W - 160:
		px -= 4                              # a long name shrinks before it is cut
	var nm := _text(who, Vector2(60, 862), W - 120, px, Color.WHITE, UIKit.font_display())
	nm.size.y = 92.0 * 1.25
	nm.position.y = 862.0 + (92 - px) * 0.4
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_outline(nm, 12)
	_title(title_text().to_upper(), 962.0)
	if int(data.get("coins", 0)) > 0:
		_coins(1100.0)
	var foot := 1250.0 if int(data.get("coins", 0)) > 0 else 1176.0
	_text(L10n.t("Play with me on Google Play"), Vector2(60, foot), W - 120, 42, Palette.GL_CREAM_RIM, UIKit.font_body(900))
	var frame := Frame.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.position = Vector2.ZERO
	frame.size = Vector2(W, H)
	add_child(frame)

## A one-line centred label of `px` at `pos` in a box `w` wide.
func _text(t: String, pos: Vector2, w: float, px: int, color: Color, font: Font) -> Label:
	var l := UIKit.label(t, px, color, font, HORIZONTAL_ALIGNMENT_CENTER)
	l.position = pos
	l.size = Vector2(w, px * 1.25)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l

## The dark outline of the game look's display type (px each side).
static func _outline(l: Label, px: int) -> void:
	l.add_theme_constant_override("outline_size", px * 2)
	l.add_theme_color_override("font_outline_color", Palette.GL_INK)

## "1ST PLACE · LUDO" on a dark chip (the reveal's "NEW PAWNS!"), centred at `y`.
func _chip(t: String, y: float) -> void:
	var font := UIKit.font_caps(900, 4)
	var px := 40
	var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x + 90.0
	var p := Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", UIKit.box(Color(Palette.GL_INK, 0.92), 34))
	p.position = Vector2((W - w) / 2.0, y)
	p.size = Vector2(w, 66)
	add_child(p)
	var l := _text(t, Vector2(p.position.x, y), w, px, Palette.GL_TITLE, font)
	l.size.y = 66.0

## The title in big outlined gold display type (the result screen's "YOU WIN!") at `y`, sized to the card.
func _title(t: String, y: float) -> void:
	var font := UIKit.font_display()
	var px := 118
	while px > 64 and font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > W - 150:
		px -= 4
	var l := _text(t, Vector2(40, y), W - 80, px, Palette.GL_TITLE, font)
	l.size.y = 140.0
	l.position.y = y + (118 - px) * 0.5 - 4.0
	_outline(l, 16)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	l.add_theme_constant_override("shadow_offset_y", 10)
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

## The coins line: a dark pill with the coin, "+228" in outlined gold and "coins" in cream.
func _coins(y: float) -> void:
	var n := "+%s" % Fmt.coins_full(int(data.get("coins", 0)))
	var big := UIKit.font_display()
	var small := UIKit.font_body(900)
	var word := L10n.t("coins")
	var nw := big.get_string_size(n, HORIZONTAL_ALIGNMENT_LEFT, -1, 84).x
	var ww := small.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, 46).x
	var coin := 96.0
	var content := coin + 22.0 + nw + 18.0 + ww
	var w := minf(content + 110.0, W - 120.0)
	var h := 128.0
	var x := (W - w) / 2.0
	var p := Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := UIKit.box(Color(Palette.GL_INK, 0.82), 64, 5, Palette.GL_CHIP_RIM)
	st.shadow_size = 24
	st.shadow_color = Color(0, 0, 0, 0.3)
	st.shadow_offset = Vector2(0, 10)
	p.add_theme_stylebox_override("panel", st)
	p.position = Vector2(x, y)
	p.size = Vector2(w, h)
	add_child(p)
	var x0 := x + (w - content) / 2.0
	var cy := y + (h - 9.0) / 2.0
	var ic := UIKit.icon("coin", coin)
	ic.size = Vector2(coin, coin)
	ic.position = Vector2(x0, cy - coin / 2.0)
	add_child(ic)
	var a := UIKit.label(n, 84, Palette.GL_TITLE, big)
	a.position = Vector2(x0 + coin + 22.0, cy - 54.0)
	a.size = Vector2(nw + 6.0, 108)
	a.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_outline(a, 8)
	add_child(a)
	var b := UIKit.label(word, 46, Palette.GL_CREAM_RIM, small)
	b.position = Vector2(x0 + coin + 22.0 + nw + 18.0, cy - 28.0)
	b.size = Vector2(ww + 6.0, 62)
	b.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(b)

func _draw() -> void:
	pass

## Over everything: the sparkles (the reveal's white diamonds with a soft glow) and the card's gold rim.
class Frame extends Control:
	const SPARKS := [[150, 470, 34], [930, 430, 26], [110, 690, 22], [975, 680, 30], [150, 1180, 20], [935, 1190, 24]]

	func _draw() -> void:
		for s: Array in SPARKS:
			var c := Vector2(s[0], s[1])
			var r: float = s[2]
			for j in 6:
				var g := r + r * 0.18 + j * r * 0.17
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -g), c + Vector2(g, 0), c + Vector2(0, g), c + Vector2(-g, 0)]), Color(1, 1, 1, 0.12))
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), Color.WHITE)
		var rim := StyleBoxFlat.new()
		rim.draw_center = false
		rim.set_border_width_all(14)
		rim.border_color = Palette.GL_GOLD
		rim.set_corner_radius_all(64)
		rim.anti_aliasing = true
		rim.corner_detail = 16
		draw_style_box(rim, Rect2(Vector2(22, 22), size - Vector2(44, 44)))
		var rim2 := rim.duplicate() as StyleBoxFlat
		rim2.border_color = Palette.GL_INK
		rim2.set_border_width_all(6)
		rim2.set_corner_radius_all(52)
		draw_style_box(rim2, Rect2(Vector2(36, 36), size - Vector2(72, 72)))

## The card as a PNG under user://share/, drawn once in a temporary SubViewport (freed before this returns). `host`:
## any node in the tree. Returns the file's absolute path, or "" when nothing could be drawn (headless has no renderer).
static func render(host: Node, data_: Dictionary) -> String:
	if host == null or not host.is_inside_tree() or DisplayServer.get_name() == "headless":
		return ""
	var vp := SubViewport.new()
	vp.size = Vector2i(W, H)
	vp.transparent_bg = false
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	host.add_child(vp)
	var card := WinCard.new(data_)
	vp.add_child(card)
	var tree := host.get_tree()
	await tree.process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image() if is_instance_valid(vp) else null
	if is_instance_valid(vp):
		vp.queue_free()
	if img == null or img.is_empty():
		return ""
	DirAccess.make_dir_recursive_absolute(DIR)
	var path := "%s/%s" % [DIR, FILE]
	img.convert(Image.FORMAT_RGB8)
	if img.save_png(path) != OK:
		return ""
	return ProjectSettings.globalize_path(path)
