class_name WinCard
extends Control
## The picture a player shares after a win (1080 x 1350, the 4:5 feed shape): the Ludo Zing logo (the owner's art,
## drawn unchanged), your avatar in its equipped frame under a crown, your name, "1ST PLACE · LUDO", the title ribbon
## ("You win!") and the coins won, on warm gold rays. Drawn at its real size (not a scaled-up 360 px layout) so the
## text stays sharp; every size below is in output pixels.
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
	var logo := BrandLogo.new()
	logo.size = Vector2(400, 274)
	logo.position = Vector2(cx - 200.0, 64)
	add_child(logo)
	# the avatar: a soft shadow under it, the avatar's own frame ring, the crown on top
	var ava_top := AVA_TOP
	var shadow := Panel.new()
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ss := UIKit.box(Color(Palette.SHADOW_DEEP, 0.0), 96)
	ss.shadow_size = 46
	ss.shadow_color = Color(Palette.SHADOW_DEEP, 0.30)
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
	_text(eyebrow_text().to_upper(), Vector2(60, 792), W - 120, 44, Palette.CREMA, UIKit.font_caps(900, 4))
	var who := str(data.get("name", ""))
	var px := 92
	while px > 56 and UIKit.font_display().get_string_size(who, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > W - 140:
		px -= 4                              # a long name shrinks before it is cut
	var nm := _text(who, Vector2(60, 838), W - 120, px, Palette.INK_STRONG, UIKit.font_display())
	nm.size.y = 92.0 * 1.25
	nm.position.y = 838.0 + (92 - px) * 0.4
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_ribbon(title_text(), 948.0)
	if int(data.get("coins", 0)) > 0:
		_coins(1096.0)
	var foot := 1244.0 if int(data.get("coins", 0)) > 0 else 1170.0
	_text(L10n.t("Play with me on Google Play"), Vector2(60, foot), W - 120, 44, Palette.CREMA, UIKit.font_body(900))

## A one-line centred label of `px` at `pos` in a box `w` wide.
func _text(t: String, pos: Vector2, w: float, px: int, color: Color, font: Font) -> Label:
	var l := UIKit.label(t, px, color, font, HORIZONTAL_ALIGNMENT_CENTER)
	l.position = pos
	l.size = Vector2(w, px * 1.25)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l

## The orange title ribbon (the app's RibbonTitle look: rim, lip, white Lilita) across the middle, at `y`.
func _ribbon(t: String, y: float) -> void:
	var font := UIKit.font_display()
	var px := 76
	var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var w := clampf(tw + 150.0, 520.0, W - 120.0)
	var h := 120.0
	var x := (W - w) / 2.0
	var lip := Panel.new()
	lip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ls := UIKit.box(Palette.RIBBON_LIP, 58)
	ls.shadow_size = 22
	ls.shadow_color = Palette.RIBBON_SHADOW
	ls.shadow_offset = Vector2(0, 12)
	lip.add_theme_stylebox_override("panel", ls)
	lip.position = Vector2(x, y + 12)
	lip.size = Vector2(w, h)
	add_child(lip)
	var face := Panel.new()
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.add_theme_stylebox_override("panel", UIKit.box(Palette.RIBBON, 58, 8, Palette.RIBBON_RIM))
	face.position = Vector2(x, y)
	face.size = Vector2(w, h)
	add_child(face)
	var l := _text(t, Vector2(x, y), w, px, Color.WHITE, font)
	l.size.y = h
	l.add_theme_color_override("font_outline_color", Palette.RIBBON_LIP)
	l.add_theme_constant_override("outline_size", 10)
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

## The coins line: a white pill with the coin and "+228 coins".
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
	var st := UIKit.box(Color.WHITE, 69, 7, Palette.HONEY_TINT_EDGE)
	st.border_width_bottom = 16
	st.shadow_size = 24
	st.shadow_color = Color(Palette.SHADOW, 0.20)
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
	var a := UIKit.label(n, 84, Palette.ON_HONEY, big)
	a.position = Vector2(x0 + coin + 22.0, cy - 54.0)
	a.size = Vector2(nw + 6.0, 108)
	a.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(a)
	var b := UIKit.label(word, 46, Palette.CREMA, small)
	b.position = Vector2(x0 + coin + 22.0 + nw + 18.0, cy - 28.0)
	b.size = Vector2(ww + 6.0, 62)
	b.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(b)

func _draw() -> void:
	# warm cream to honey, rays from behind the avatar, a few confetti dots, the rim of the card
	var top := Palette.PM_RIM
	var bot := Palette.HONEY_TINT
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(W, 0), Vector2(W, H), Vector2(0, H)]),
		PackedColorArray([top, top, bot, bot]))
	var c := Vector2(W / 2.0, AVA_TOP + AVA / 2.0)
	var n := 18
	for i in n:
		var a0 := -0.12 + TAU * i / n
		var a1 := a0 + TAU / n * 0.5
		draw_colored_polygon(PackedVector2Array([c, c + Vector2(cos(a0), sin(a0)) * 1500.0, c + Vector2(cos(a1), sin(a1)) * 1500.0]),
			Color(Palette.GOLD_HI, 0.30))
	for k in 6:
		draw_circle(c, 330.0 - k * 36.0, Color(Color.WHITE, 0.10 + k * 0.05), true, -1.0, true)
	var dots := [[120, 150, 0], [940, 120, 3], [70, 520, 2], [1010, 560, 1], [150, 660, 1], [950, 690, 0], [88, 1080, 3], [996, 1060, 2],
		[100, 1200, 2], [985, 1220, 1]]
	for d: Array in dots:
		draw_circle(Vector2(d[0], d[1]), 16.0, Color(Palette.PLAYER[d[2]], 0.75), true, -1.0, true)
	var rim := StyleBoxFlat.new()
	rim.draw_center = false
	rim.set_border_width_all(10)
	rim.border_color = Palette.PM_RING
	rim.set_corner_radius_all(60)
	rim.anti_aliasing = true
	draw_style_box(rim, Rect2(Vector2(26, 26), Vector2(W - 52, H - 52)))
	var rim2 := rim.duplicate() as StyleBoxFlat
	rim2.border_color = Color(Color.WHITE, 0.9)
	rim2.set_border_width_all(6)
	rim2.set_corner_radius_all(52)
	draw_style_box(rim2, Rect2(Vector2(36, 36), Vector2(W - 72, H - 72)))

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
