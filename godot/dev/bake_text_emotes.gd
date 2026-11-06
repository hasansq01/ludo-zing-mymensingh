extends Node
## Dev: draws the text emotes (the phrase stickers, assets/emotes/t-*/NNN.webp + icon.webp, 344 x 218). Every phrase is
## a die-cut sticker: a shape per pack (Good Manners a glossy bubble, Ludo Talk a game tile, Reactions a comic burst,
## Bangla a rickshaw-art plaque, Team a banner), chunky lettering (Lilita One, Baloo Da 2 for Bangla, through
## UIKit.font_display()), its own props and a looping motion that suits the mood. Godot does the shaping, so Bangla's
## conjuncts come out right. Needs a window (not --headless):
##   godot --path . res://dev/bake_text_emotes.tscn -- <out_dir> [ids...]
## With out_dir "res://assets/emotes" it replaces the real art; a new frame file imports lossless, so set it lossy
## (the test "every frame imports lossy"), and emotes.json has FRAMES and FPS below. Touches no save.

const W := 344
const H := 218
const SS := 3                            # drawn this much larger, then scaled down
const FRAMES := 12
const FPS := 12.0
const QUALITY := 0.95
const INK := Color("#2a1a14")
const CUT := Color("#fffdf7")            # the sticker's white die-cut edge
const CENTER := Vector2(172, 109)

## text ("\n" = next line), style, top / bottom colours of the shape, motion, props: [kind, x, y, size, turn]
const PHRASES := {
	"t-hi": {t = "Hi!", s = "bubble", a = "#59c1ff", b = "#2467e0", m = "wave", p = [["hand", 302, 40, 1.25, 0.2], ["star", 36, 44, 0.9, 0.0]]},
	"t-luck": {t = "Good\nluck!", s = "bubble", a = "#5fdc7d", b = "#14964f", m = "bob", p = [["clover", 302, 40, 1.25, 0.2], ["star", 36, 44, 0.8, 0.0]]},
	"t-fun": {t = "Have\nfun!", s = "bubble", a = "#ffb24a", b = "#f0641e", m = "jump", p = [["confetti", 306, 40, 1.1, 0.0], ["confetti", 36, 44, 0.9, 1.4]]},
	"t-gg": {t = "GG", s = "bubble", a = "#b38bff", b = "#6a35d9", m = "jump", p = [["crown", 172, 34, 1.35, 0.0], ["star", 36, 44, 1.0, 0.0], ["star", 306, 40, 1.0, 0.0]]},
	"t-wp": {t = "Well\nplayed!", s = "bubble", a = "#3fd9c4", b = "#0b8f94", m = "bob", p = [["star", 302, 40, 1.25, 0.0], ["star", 36, 44, 0.8, 0.0]]},
	"t-thx": {t = "Thanks!", s = "bubble", a = "#ff7fa6", b = "#e0264f", m = "pulse", p = [["heart", 302, 40, 1.25, 0.2], ["heart", 36, 44, 0.8, -0.3]]},
	"t-sorry": {t = "Sorry!", s = "bubble", a = "#92a7cf", b = "#4d6398", m = "droop", p = [["drop", 303, 40, 1.2, 0.0], ["drop", 36, 44, 0.7, 0.0]]},
	"t-bye": {t = "Bye!", s = "bubble", a = "#7f9bff", b = "#3a4bd6", m = "wave", p = [["hand", 302, 40, 1.25, 0.2], ["star", 36, 44, 0.9, 0.0]]},

	"t-six": {t = "Roll\na 6!", s = "tile", a = "#ff6d5e", b = "#d3272c", m = "bob", p = [["die", 295, 42, 1.45, 0.3]]},
	"t-nice": {t = "Nice\nroll!", s = "tile", a = "#54d67c", b = "#16934f", m = "jump", p = [["die", 298, 40, 1.35, -0.25], ["star", 36, 44, 0.9, 0.0]]},
	"t-lucky": {t = "Lucky!", s = "tile", a = "#36d68f", b = "#0c8c62", m = "pulse", p = [["clover", 300, 40, 1.3, 0.2], ["coin", 36, 44, 1.05, 0.0]]},
	"t-again": {t = "Not\nagain!", s = "tile", a = "#8d9bb8", b = "#4c5877", m = "droop", p = [["cross", 303, 40, 1.2, 0.0], ["drop", 36, 44, 0.8, 0.0]]},
	"t-revenge": {t = "Revenge!", s = "tile", a = "#ff5a3c", b = "#b3123c", m = "shake", p = [["flame", 298, 40, 1.35, 0.0], ["flame", 36, 44, 0.95, 0.0]]},
	"t-safe": {t = "Safe!", s = "tile", a = "#37c9d6", b = "#0d7ea8", m = "pulse", p = [["shield", 298, 40, 1.35, 0.0], ["star", 36, 44, 0.85, 0.0]]},
	"t-pair": {t = "Pair\nup!", s = "tile", a = "#ffc53d", b = "#ee8a0c", m = "jump", p = [["pawn2", 298, 40, 1.35, 0.0]]},
	"t-home": {t = "Almost\nhome!", s = "tile", a = "#a97cff", b = "#6232d0", m = "bob", p = [["house", 300, 40, 1.3, 0.0], ["star", 36, 44, 0.8, 0.0]]},

	"t-wow": {t = "Wow!", s = "burst", a = "#ffb70f", b = "#ef5a06", m = "jump", p = [["bang", 303, 40, 1.2, 0.2], ["bang", 36, 44, 0.9, -0.25]]},
	"t-oops": {t = "Oops!", s = "burst", a = "#ff8c7a", b = "#e23a4e", m = "wobble", p = [["drop", 305, 40, 1.15, 0.0], ["drop", 36, 44, 0.8, 0.0]]},
	"t-close": {t = "So\nclose!", s = "burst", a = "#c87cff", b = "#7a2fdc", m = "shake", p = [["bang", 303, 40, 1.2, 0.2], ["star", 36, 44, 0.9, 0.0]]},
	"t-hurry": {t = "Hurry\nup!", s = "burst", a = "#5cc0ff", b = "#1a5fe0", m = "shake", p = [["clock", 300, 40, 1.3, 0.0]]},
	"t-wait": {t = "Wait…", s = "burst", a = "#a9b6cf", b = "#5a6a8e", m = "bob", p = [["qmark", 300, 40, 1.3, 0.15], ["clock", 36, 44, 0.95, 0.0]]},
	"t-turn": {t = "My\nturn!", s = "burst", a = "#7be35a", b = "#199a3c", m = "jump", p = [["star", 300, 40, 1.3, 0.0], ["pawn", 36, 44, 1.0, 0.0]]},
	"t-easy": {t = "Easy!", s = "burst", a = "#ffbf3f", b = "#f4701e", m = "wobble", p = [["flame", 302, 40, 1.25, 0.0], ["star", 36, 44, 0.9, 0.0]]},
	"t-nooo": {t = "Noooo!", s = "burst", a = "#ff4d4d", b = "#b00f30", m = "shake", p = [["bang", 303, 40, 1.2, 0.2], ["drop", 36, 44, 0.9, 0.0]]},

	"t-bgg": {t = "ভালো\nখেলা!", s = "plaque", a = "#ff4f8b", b = "#c9135e", m = "bob", p = [["star", 306, 40, 1.1, 0.0]]},
	"t-bluck": {t = "শুভকামনা!", s = "plaque", a = "#14b8a6", b = "#07796f", m = "pulse", p = [["clover", 306, 40, 1.1, 0.2]]},
	"t-bsix": {t = "ছক্কা\nচাই!", s = "plaque", a = "#f4542f", b = "#b81f1f", m = "jump", p = [["die", 303, 40, 1.2, 0.3]]},
	"t-bcome": {t = "আয়\nদেখি!", s = "plaque", a = "#7c3aed", b = "#4a1bb0", m = "shake", p = [["flame", 306, 40, 1.1, 0.0]]},
	"t-bagain": {t = "আবার!", s = "plaque", a = "#0ea5e9", b = "#0b62b5", m = "jump", p = [["die", 303, 40, 1.2, -0.3]]},
	"t-bwon": {t = "জিতে\nগেলাম!", s = "plaque", a = "#f59e0b", b = "#c9500a", m = "jump", p = [["crown", 306, 40, 1.05, 0.2]]},
	"t-bthx": {t = "ধন্যবাদ!", s = "plaque", a = "#ec3f7c", b = "#a8124f", m = "pulse", p = [["heart", 306, 40, 1.1, 0.2]]},
	"t-bugh": {t = "উফ!", s = "plaque", a = "#64748b", b = "#37435a", m = "wobble", p = [["drop", 306, 40, 1.1, 0.0]]},

	"t-help": {t = "Help\nme!", s = "banner", a = "#ff6b5a", b = "#cf2433", m = "shake", p = [["bang", 306, 40, 1.1, 0.2]]},
	"t-go": {t = "Go go\ngo!", s = "banner", a = "#3fd06f", b = "#0f8f4a", m = "jump", p = [["flame", 306, 38, 1.1, 0.0]]},
	"t-got": {t = "I got\nyou!", s = "banner", a = "#3bb6e8", b = "#116fb8", m = "pulse", p = [["shield", 305, 40, 1.15, 0.0]]},
	"t-partner": {t = "Nice one,\npartner!", s = "banner", a = "#b07cff", b = "#6a32d6", m = "bob", p = [["heart", 306, 40, 0.95, 0.2], ["heart", 268, 30, 0.6, -0.2]]},
}

var out := ""
var vp: SubViewport
var stage: Stage


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("usage: bake_text_emotes.tscn -- <out_dir> [ids...]")
		get_tree().quit(1)
		return
	out = args[0]
	var ids: Array = Array(args.slice(1)) if args.size() > 1 else PHRASES.keys()
	vp = SubViewport.new()
	vp.size = Vector2i(W * SS, H * SS)
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_2d = Viewport.MSAA_4X
	add_child(vp)
	stage = Stage.new()
	stage.size = Vector2(W * SS, H * SS)
	vp.add_child(stage)
	for id: String in ids:
		await _bake(id)
		print("baked ", id)
	print("done ", ids.size())
	get_tree().quit()

func _bake(id: String) -> void:
	var row: Dictionary = PHRASES[id]
	DirAccess.make_dir_recursive_absolute("%s/%s" % [out, id])
	stage.load_phrase(row)
	stage.mode = Stage.MASK_FILL
	stage.queue_redraw()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	stage.set_mask("fill", vp.get_texture().get_image())
	stage.mode = Stage.MASK_INK
	stage.queue_redraw()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	stage.set_mask("ink", vp.get_texture().get_image())
	stage.mode = Stage.FULL
	for f in FRAMES:
		stage.t = float(f) / FRAMES
		stage.queue_redraw()
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := _final(vp.get_texture().get_image())
		img.save_webp("%s/%s/%03d.webp" % [out, id, f], true, QUALITY)
		if f == 0:
			img.save_webp("%s/%s/icon.webp" % [out, id], true, QUALITY)

## Down to the art's size, then from premultiplied to plain alpha (a transparent viewport's edge pixels are darkened by
## their own coverage, which would leave a dark rim in the game).
func _final(src: Image) -> Image:
	src.convert(Image.FORMAT_RGBA8)
	src.resize(W, H, Image.INTERPOLATE_LANCZOS)
	var d := src.get_data()
	for i in range(0, d.size(), 4):
		var a := d[i + 3]
		if a > 0 and a < 255:
			d[i] = mini(255, d[i] * 255 / a)
			d[i + 1] = mini(255, d[i + 1] * 255 / a)
			d[i + 2] = mini(255, d[i + 2] * 255 / a)
	return Image.create_from_data(W, H, false, Image.FORMAT_RGBA8, d)


## Draws one phrase at time t (0..1, seamless).
class Stage extends Control:
	enum { FULL, MASK_FILL, MASK_INK }
	const INK_W := 6.0                   # the lettering's ink outline (art px)
	const SHAPE_INK := 5.0
	const SHAPE_CUT := 6.0
	const MARGIN := 0.92                 # all of it, so a moving sticker and its white edge stay inside the frame

	var mode := FULL
	var t := 0.0
	var row := {}
	var body := PackedVector2Array()
	var masks := {}
	var lines: PackedStringArray = []
	var font: Font
	var font_px := 80
	var baselines: Array = []
	var line_w: Array = []
	var top_c := Color.WHITE
	var bot_c := Color.WHITE

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func load_phrase(r: Dictionary) -> void:
		row = r
		masks.clear()
		font = UIKit.font_display()
		lines = str(r.t).split("\n")
		top_c = Color(str(r.a))
		bot_c = Color(str(r.b))
		body = _shape(str(r.s))
		_fit()

	func _body_rect() -> Rect2:
		var b := Rect2(body[0], Vector2.ZERO)
		for p in body:
			b = b.expand(p)
		return b

	## The largest type that fits the shape (one short word gets very big, up to 2 lines).
	func _fit() -> void:
		var box := _body_rect().grow(-27.0 if str(row.s) in ["burst", "plaque"] else -18.0)
		box.position.y += 2.0
		var px := 118
		while px > 26:
			var sz := px * SS
			var wide := 0.0
			for l in lines:
				wide = maxf(wide, font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x / SS)
			var pitch := _pitch(px)
			var tall := font.get_height(sz) / SS + pitch * (lines.size() - 1)
			if wide <= box.size.x - 2.0 * INK_W and tall <= box.size.y + (px * 0.3):
				break
			px -= 2
		font_px = px
		var sz2 := px * SS
		var pitch2 := _pitch(px)
		var asc := font.get_ascent(sz2) / SS
		var dsc := font.get_descent(sz2) / SS
		var block := asc + dsc + pitch2 * (lines.size() - 1)
		var y0 := box.get_center().y - block / 2.0 + asc
		baselines.clear()
		line_w.clear()
		for k in lines.size():
			baselines.append(y0 + pitch2 * k)
			line_w.append(font.get_string_size(lines[k], HORIZONTAL_ALIGNMENT_LEFT, -1, sz2).x / SS)

	func _pitch(px: int) -> float:
		return px * (1.02 if _bangla() else 0.95)

	func _bangla() -> bool:
		return str(row.s) == "plaque"

	func set_mask(k: String, img: Image) -> void:
		img.convert(Image.FORMAT_RGBA8)
		if k == "fill":
			_gradient_fill(img)
		else:
			_flat(img, Color.WHITE)
		masks[k] = ImageTexture.create_from_image(img)

	## The lettering: white at the top, a little warmer below; plain alpha again after the mask pass.
	func _gradient_fill(img: Image) -> void:
		var w := img.get_width()
		var h := img.get_height()
		var hi := Color("#ffffff")
		var lo := Color("#ffffff").lerp(top_c, 0.18)
		var d := img.get_data()
		var y_top := (float(baselines[0]) - font_px * 0.8) * SS
		var y_bot := float(baselines[-1]) * SS
		for y in h:
			var u := clampf((y - y_top) / maxf(y_bot - y_top, 1.0), 0.0, 1.0)
			var c := hi.lerp(lo, u * u)
			var r := int(c.r * 255.0)
			var g := int(c.g * 255.0)
			var b := int(c.b * 255.0)
			var row_at := y * w * 4
			for x in w:
				var i := row_at + x * 4
				if d[i + 3] > 0:
					d[i] = r
					d[i + 1] = g
					d[i + 2] = b
		img.set_data(w, h, false, Image.FORMAT_RGBA8, d)

	func _flat(img: Image, c: Color) -> void:
		var d := img.get_data()
		var r := int(c.r * 255.0)
		var g := int(c.g * 255.0)
		var b := int(c.b * 255.0)
		for i in range(0, d.size(), 4):
			if d[i + 3] > 0:
				d[i] = r
				d[i + 1] = g
				d[i + 2] = b
		img.set_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, d)

	# ---------- drawing ----------

	func _draw() -> void:
		var base := Transform2D().scaled(Vector2(SS_(), SS_()))
		if mode != FULL:
			draw_set_transform_matrix(Transform2D())
			for k in lines.size():
				var x := (CENTER_().x - float(line_w[k]) / 2.0) * SS_()
				var y := float(baselines[k]) * SS_()
				var sz := font_px * SS_()
				match mode:
					MASK_FILL:
						draw_string(font, Vector2(x, y), lines[k], HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color.WHITE)
					MASK_INK:
						draw_string_outline(font, Vector2(x, y), lines[k], HORIZONTAL_ALIGNMENT_LEFT, -1, sz, int(INK_W * 2.0 * SS_()), Color.WHITE)
						draw_string(font, Vector2(x, y), lines[k], HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color.WHITE)
			return
		var mo := _motion(t)
		var word: Transform2D = base * (Transform2D().translated(CENTER_() + mo.off)
			* Transform2D(mo.rot, Vector2.ONE).scaled_local(mo.scale * MARGIN)
			* Transform2D().translated(-CENTER_()))
		draw_set_transform_matrix(word)
		_draw_shape()
		_draw_type(mo)
		for p: Array in row.p:
			_draw_prop(base, word, p)

	func SS_() -> float:
		return 3.0

	func CENTER_() -> Vector2:
		return Vector2(172, 109)

	func _motion(u: float) -> Dictionary:
		var s := sin(TAU * u)
		var c := cos(TAU * u)
		var off := Vector2.ZERO
		var rot := 0.0
		var sc := Vector2.ONE
		match str(row.m):
			"bob":
				off.y = -3.0 * s
				rot = deg_to_rad(1.6) * c
			"wave":
				rot = deg_to_rad(4.5) * s
				off.y = -1.5 * absf(s)
			"pulse":
				var beat := pow(maxf(0.0, sin(TAU * u * 2.0)), 3.0)
				sc = Vector2.ONE * (1.0 + 0.04 * beat)
			"jump":
				var up := absf(sin(TAU * u))
				off.y = -7.0 * up
				var land := pow(1.0 - up, 4.0)
				sc = Vector2(1.0 + 0.045 * land, 1.0 - 0.045 * land)
			"shake":
				off.x = 3.6 * sin(TAU * u * 3.0)
				rot = deg_to_rad(2.2) * sin(TAU * u * 2.0)
			"wobble":
				rot = deg_to_rad(4.0) * s
				sc = Vector2(1.0 + 0.02 * c, 1.0 - 0.02 * c)
			"droop":
				off.y = 2.5 * (1.0 - c) * 0.5
				rot = deg_to_rad(-2.2) * (1.0 - c) * 0.5
		return {off = off, rot = rot, scale = sc}

	func _draw_shape() -> void:
		var d := body.duplicate()
		for i in d.size():
			d[i] += Vector2(0, 7)
		_poly(_grow(d, SHAPE_INK + SHAPE_CUT), Color(0.18, 0.08, 0.05, 0.28))
		_poly(_grow(body, SHAPE_INK + SHAPE_CUT), CUT)
		_poly(_grow(body, SHAPE_INK), INK)
		_grad(body, top_c, bot_c)
		match str(row.s):
			"bubble":
				_gloss()
			"tile":
				_tile_detail()
			"burst":
				_burst_detail()
			"plaque":
				_plaque_detail()
			"banner":
				_banner_detail()

	func _draw_type(_mo: Dictionary) -> void:
		var r := Rect2(0, 0, 344, 218)
		var side := bot_c.darkened(0.45)
		if masks.has("ink"):
			for k in range(6, 0, -1):            # the lettering's solid side, going down
				draw_texture_rect(masks.ink, Rect2(0, k, 344, 218), false, side.darkened(0.25 if k == 6 else 0.0))
			draw_texture_rect(masks.ink, r, false, INK)
		if masks.has("fill"):
			draw_texture_rect(masks.fill, r, false, Color.WHITE)

	# ---------- the pack shapes ----------

	func _shape(style: String) -> PackedVector2Array:
		match style:
			"bubble":
				var rr := _rrect(Rect2(24, 34, 296, 146), 54.0)
				var tail := PackedVector2Array([Vector2(70, 168), Vector2(58, 196), Vector2(116, 176)])
				var m := Geometry2D.merge_polygons(rr, tail)
				return m[0] if m.size() > 0 else rr
			"tile":
				return _rrect(Rect2(22, 36, 300, 148), 28.0)
			"burst":
				return _burst(16, 158.0, 94.0, 0.76)
			"plaque":
				return _scallop(_rrect(Rect2(26, 36, 292, 146), 40.0), 26, 6.5)
			"banner":
				return PackedVector2Array([Vector2(26, 42), Vector2(318, 42), Vector2(300, 112), Vector2(318, 178), Vector2(26, 178), Vector2(44, 112)])
		return _rrect(Rect2(24, 34, 296, 146), 40.0)

	func _rrect(r: Rect2, rad: float, per := 12) -> PackedVector2Array:
		var o := PackedVector2Array()
		var cs := [Vector2(r.end.x - rad, r.position.y + rad), Vector2(r.end.x - rad, r.end.y - rad),
			Vector2(r.position.x + rad, r.end.y - rad), Vector2(r.position.x + rad, r.position.y + rad)]
		for k in 4:
			for i in per + 1:
				var a := -PI / 2.0 + PI / 2.0 * k + PI / 2.0 * float(i) / per
				o.append((cs[k] as Vector2) + Vector2(cos(a), sin(a)) * rad)
		return o

	func _burst(n: int, rx: float, ry: float, inner: float) -> PackedVector2Array:
		var o := PackedVector2Array()
		var jitter := [1.0, 0.94, 1.03, 0.97, 1.0, 0.92, 1.04, 0.96]
		for k in n * 2:
			var a := TAU * float(k) / (n * 2) - PI / 2.0 + 0.1
			var f: float = float(jitter[k / 2 % jitter.size()]) if k % 2 == 0 else inner
			o.append(CENTER_() + Vector2(cos(a) * rx * f, sin(a) * ry * f))
		return o

	func _scallop(src: PackedVector2Array, bumps: int, depth: float) -> PackedVector2Array:
		var n := 200
		var dense := _resample(src, n)
		var o := PackedVector2Array()
		for i in n:
			var p := dense[i]
			var nrm := (p - CENTER_()).normalized()
			var b := absf(sin(PI * float(i) * bumps / n))
			o.append(p + nrm * depth * pow(b, 0.6))
		return o

	func _resample(src: PackedVector2Array, n: int) -> PackedVector2Array:
		var total := 0.0
		for i in src.size():
			total += src[i].distance_to(src[(i + 1) % src.size()])
		var o := PackedVector2Array()
		var step := total / n
		var at := 0.0
		var i2 := 0
		var seg := src[0].distance_to(src[1])
		for k in n:
			var want := step * k
			while at + seg < want and i2 < src.size() - 1:
				at += seg
				i2 += 1
				seg = src[i2].distance_to(src[(i2 + 1) % src.size()])
			o.append(src[i2].lerp(src[(i2 + 1) % src.size()], clampf((want - at) / maxf(seg, 0.001), 0.0, 1.0)))
		return o

	func _gloss() -> void:
		var r := _body_rect()
		var g := _rrect(Rect2(r.position.x + 16, r.position.y + 9, r.size.x - 32, 40), 20.0, 8)
		_poly(g, Color(1, 1, 1, 0.22))

	func _tile_detail() -> void:
		var r := _body_rect().grow(-9.0)
		_line(_rrect(r, 20.0), Color(1, 1, 1, 0.42), 3.0)
		var pip := Color(1, 1, 1, 0.3)
		for c: Vector2 in [r.position + Vector2(17, 17), Vector2(r.end.x - 17, r.position.y + 17), Vector2(r.position.x + 17, r.end.y - 17), r.end - Vector2(17, 17)]:
			draw_circle(c, 5.5, pip)

	func _burst_detail() -> void:
		for k in 16:
			var a := TAU * (float(k) + 0.25) / 16.0
			var a2 := a + TAU / 40.0
			var far := Vector2(cos(a) * 170.0, sin(a) * 100.0)
			var far2 := Vector2(cos(a2) * 170.0, sin(a2) * 100.0)
			var clip := Geometry2D.intersect_polygons(body, PackedVector2Array([CENTER_(), CENTER_() + far, CENTER_() + far2]))
			for c in clip:
				_poly(c, Color(1, 1, 1, 0.13))
		var pts := body.duplicate()
		var inner := _grow(pts, -8.0)
		_line(inner, Color(1, 1, 1, 0.38), 2.5)

	func _plaque_detail() -> void:
		var r := _body_rect().grow(-13.0)
		var gold := Color("#ffd65a")
		_line(_rrect(r, 30.0), Color("#7a2a12"), 7.0)
		_line(_rrect(r, 30.0), gold, 4.0)
		var inner := _rrect(r.grow(-7.0), 24.0)
		_line(inner, Color(1, 1, 1, 0.3), 1.5)
		for c: Vector2 in [r.position + Vector2(16, 16), Vector2(r.end.x - 16, r.position.y + 16), Vector2(r.position.x + 16, r.end.y - 16), r.end - Vector2(16, 16)]:
			_flower(c, 11.0)

	func _flower(c: Vector2, rad: float) -> void:
		for k in 6:
			var a := TAU * k / 6.0
			var q := c + Vector2(cos(a), sin(a)) * rad * 0.62
			draw_circle(q, rad * 0.55, Color("#7a2a12"))
		for k in 6:
			var a := TAU * k / 6.0
			var q := c + Vector2(cos(a), sin(a)) * rad * 0.62
			draw_circle(q, rad * 0.42, Color("#ffe27a") if k % 2 == 0 else Color("#ff9fc4"))
		draw_circle(c, rad * 0.34, Color("#7a2a12"))
		draw_circle(c, rad * 0.24, Color("#ffffff"))

	func _banner_detail() -> void:
		var top := PackedVector2Array([Vector2(44, 54), Vector2(300, 54)])
		var bot := PackedVector2Array([Vector2(44, 166), Vector2(300, 166)])
		for seg in [top, bot]:
			var x := 44.0
			while x < 296.0:
				draw_line(Vector2(x, (seg as PackedVector2Array)[0].y), Vector2(x + 9.0, (seg as PackedVector2Array)[0].y), Color(1, 1, 1, 0.55), 3.0, true)
				x += 16.0

	# ---------- props ----------

	func _draw_prop(base: Transform2D, word: Transform2D, p: Array) -> void:
		var kind := str(p[0])
		var at := Vector2(float(p[1]), float(p[2]))
		var size_k := float(p[3])
		var turn := float(p[4])
		var phase := at.x * 0.013
		var k := 1.0 + 0.09 * sin(TAU * t + phase)
		var rot := turn + 0.1 * sin(TAU * t + phase)
		var off := Vector2(0, -2.5 * sin(TAU * t + phase))
		if kind == "star" or kind == "confetti":
			k = 0.82 + 0.28 * (0.5 + 0.5 * cos(TAU * t + phase))
			rot = turn + TAU * t * (0.25 if kind == "star" else 1.0) * 0.5 * (1.0 if int(at.x) % 2 == 0 else -1.0)
			if kind == "star":
				rot = turn + 0.3 * sin(TAU * t + phase)
		elif kind == "die":
			rot = turn + 0.22 * sin(TAU * t + phase)
		elif kind == "flame":
			rot = 0.07 * sin(TAU * t * 2.0 + phase)
			k = 1.0 + 0.09 * sin(TAU * t * 2.0 + phase)
		elif kind == "clock":
			rot = 0.0
		elif kind == "hand":
			rot = turn + 0.42 * sin(TAU * t * 2.0)
			k = 1.0
			off = Vector2.ZERO
		var m: Transform2D = word * (Transform2D().translated(at + off) * Transform2D(rot, Vector2(k, k) * size_k))
		draw_set_transform_matrix(m)
		match kind:
			"heart":
				_sticker(_heart(), Color("#ff7fa6"), Color("#e8174d"))
				_poly(_ellipse(Vector2(-8, -9), 5.0, 3.5), Color(1, 1, 1, 0.75))
			"star":
				_sticker(_star(5, 21.0, 9.5), Color("#fff08a"), Color("#ffb000"))
			"clover":
				_clover()
			"die":
				_die()
			"flame":
				_sticker(_flame(1.0), Color("#ffd23c"), Color("#f4380f"))
				_poly(_flame(0.5, Vector2(0, 7)), Color("#fff3a8"))
			"drop":
				_sticker(_drop(), Color("#a9e4ff"), Color("#2f9bf0"))
				_poly(_ellipse(Vector2(-5, 3), 3.0, 4.5), Color(1, 1, 1, 0.8))
			"bang":
				_sticker(PackedVector2Array([Vector2(-8, -24), Vector2(9, -24), Vector2(5, 7), Vector2(-4, 7)]), Color("#ffe14d"), Color("#ff9d0a"))
				_sticker(_ellipse(Vector2(0, 17), 6.5, 6.5), Color("#ffe14d"), Color("#ff9d0a"))
			"qmark":
				_label_prop("?", Color("#ffe14d"))
			"cross":
				_sticker(_cross(), Color("#ff7a6b"), Color("#d91f2f"))
			"shield":
				_shield()
			"house":
				_house()
			"crown":
				_crown()
			"coin":
				_sticker(_ellipse(Vector2.ZERO, 19.0, 19.0), Color("#ffe471"), Color("#f5a800"))
				_line(_ellipse(Vector2.ZERO, 12.5, 12.5), Color("#b86f00"), 2.5)
			"clock":
				_clock()
			"pawn":
				_pawn(Vector2.ZERO, Color("#ff7b6b"), Color("#d91f2f"))
			"pawn2":
				_pawn(Vector2(-12, 0), Color("#6fb6ff"), Color("#1f5fd9"))
				_pawn(Vector2(12, 3), Color("#ff7b6b"), Color("#d91f2f"))
			"hand":
				_hand()
			"confetti":
				_confetti()
		draw_set_transform_matrix(base)

	func _sticker(pts: PackedVector2Array, a: Color, b: Color) -> void:
		_poly(_grow(pts, 6.5), CUT)
		_poly(_grow(pts, 3.5), INK)
		_grad(pts, a, b)

	func _label_prop(txt: String, c: Color) -> void:
		var sz := 44
		var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
		draw_string_outline(font, Vector2(-w / 2.0, 16), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 15, CUT)
		draw_string_outline(font, Vector2(-w / 2.0, 16), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 8, INK)
		draw_string(font, Vector2(-w / 2.0, 16), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, c)

	func _heart() -> PackedVector2Array:
		var o := PackedVector2Array()
		for i in 40:
			var a := TAU * i / 40.0
			var x := 16.0 * pow(sin(a), 3.0)
			var y := -(13.0 * cos(a) - 5.0 * cos(2.0 * a) - 2.0 * cos(3.0 * a) - cos(4.0 * a))
			o.append(Vector2(x, y) * 1.15)
		return o

	func _star(n: int, r1: float, r2: float) -> PackedVector2Array:
		var o := PackedVector2Array()
		for k in n * 2:
			var a := TAU * k / (n * 2) - PI / 2.0
			o.append(Vector2(cos(a), sin(a)) * (r1 if k % 2 == 0 else r2))
		return o

	func _ellipse(c: Vector2, rx: float, ry: float, n := 24) -> PackedVector2Array:
		var o := PackedVector2Array()
		for i in n:
			var a := TAU * i / n
			o.append(c + Vector2(cos(a) * rx, sin(a) * ry))
		return o

	func _flame(k: float, at := Vector2.ZERO) -> PackedVector2Array:
		var o := PackedVector2Array()
		var pts := [Vector2(0, -28), Vector2(7, -15), Vector2(16, -8), Vector2(19, 6), Vector2(14, 18), Vector2(4, 24), Vector2(-7, 24), Vector2(-16, 17), Vector2(-19, 5), Vector2(-14, -4), Vector2(-9, -2), Vector2(-7, -13)]
		for p: Vector2 in pts:
			o.append(at + p * k)
		return o

	func _drop() -> PackedVector2Array:
		var o := PackedVector2Array()
		o.append(Vector2(0, -24))
		for i in 21:
			var a := -0.35 + (PI + 0.7) * i / 20.0
			o.append(Vector2(cos(a) * 15.0, 7.0 + sin(a) * 15.0))
		return o

	func _cross() -> PackedVector2Array:
		var a := 16.0
		var b := 6.5
		var pts := [Vector2(-b, -a), Vector2(b, -a), Vector2(b, -b), Vector2(a, -b), Vector2(a, b), Vector2(b, b), Vector2(b, a), Vector2(-b, a), Vector2(-b, b), Vector2(-a, b), Vector2(-a, -b), Vector2(-b, -b)]
		var o := PackedVector2Array()
		for p: Vector2 in pts:
			o.append(p.rotated(PI / 4.0) * 1.25)
		return o

	func _clover() -> void:
		var stem := PackedVector2Array([Vector2(-3, 6), Vector2(3, 6), Vector2(9, 28), Vector2(3, 29)])
		_poly(_grow(stem, 6.5), CUT)
		_poly(_grow(stem, 3.5), INK)
		_poly(stem, Color("#1f9a4a"))
		var leaves: Array = []
		for k in 4:
			var a := PI / 4.0 + PI / 2.0 * k
			leaves.append(Vector2(cos(a), sin(a)) * 11.0)
		for c: Vector2 in leaves:
			_poly(_ellipse(c, 13.5, 13.5), CUT)
		for c: Vector2 in leaves:
			_poly(_ellipse(c, 10.5 + 3.0, 10.5 + 3.0), INK)
		for c: Vector2 in leaves:
			_grad(_ellipse(c, 10.5, 10.5), Color("#7ef08a"), Color("#1fae55"))

	func _die() -> void:
		var r := _rrect(Rect2(-21, -21, 42, 42), 9.0, 6)
		_sticker(r, Color("#ffffff"), Color("#e7dcc7"))
		var c := INK
		for q: Vector2 in [Vector2(-10.5, -11), Vector2(10.5, -11), Vector2(-10.5, 0), Vector2(10.5, 0), Vector2(-10.5, 11), Vector2(10.5, 11)]:
			draw_circle(q, 4.3, c)

	func _shield() -> void:
		var o := PackedVector2Array([Vector2(0, -25), Vector2(21, -17), Vector2(20, 4), Vector2(12, 17), Vector2(0, 26), Vector2(-12, 17), Vector2(-20, 4), Vector2(-21, -17)])
		_sticker(o, Color("#9af0ff"), Color("#1b9ad8"))
		var tick := PackedVector2Array([Vector2(-9, 0), Vector2(-2, 8), Vector2(11, -9)])
		draw_polyline(tick, Color.WHITE, 5.5, true)

	func _house() -> void:
		var o := PackedVector2Array([Vector2(0, -25), Vector2(25, -3), Vector2(18, -3), Vector2(18, 21), Vector2(-18, 21), Vector2(-18, -3), Vector2(-25, -3)])
		_sticker(o, Color("#fff0c2"), Color("#ffc64d"))
		var roof := PackedVector2Array([Vector2(0, -25), Vector2(25, -3), Vector2(-25, -3)])
		_grad(roof, Color("#ff8a6b"), Color("#e13a3a"))
		var door := _rrect(Rect2(-6, 5, 12, 16), 4.0, 4)
		_poly(door, Color("#7a4a26"))

	func _crown() -> void:
		var o := PackedVector2Array([Vector2(-27, 17), Vector2(-30, -13), Vector2(-14, -1), Vector2(0, -20), Vector2(14, -1), Vector2(30, -13), Vector2(27, 17)])
		_sticker(o, Color("#ffe96e"), Color("#ffae0c"))
		for q: Array in [[Vector2(0, 7), Color("#e8334f")], [Vector2(-15, 9), Color("#2f9bf0")], [Vector2(15, 9), Color("#22b463")]]:
			draw_circle(q[0], 4.2, q[1])

	func _clock() -> void:
		_sticker(_ellipse(Vector2.ZERO, 21.0, 21.0), Color("#ffffff"), Color("#e8e0d0"))
		var a := TAU * t - PI / 2.0
		draw_line(Vector2.ZERO, Vector2(cos(a), sin(a)) * 14.5, INK, 4.0, true)
		draw_line(Vector2.ZERO, Vector2(cos(a / 12.0 - 1.1), sin(a / 12.0 - 1.1)) * 9.0, Color("#e8334f"), 4.0, true)
		draw_circle(Vector2.ZERO, 3.2, INK)

	func _pawn(c: Vector2, a: Color, b: Color) -> void:
		var bodyp := PackedVector2Array([c + Vector2(-5, -7), c + Vector2(5, -7), c + Vector2(9, 12), c + Vector2(15, 18), c + Vector2(15, 25), c + Vector2(-15, 25), c + Vector2(-15, 18), c + Vector2(-9, 12)])
		var head := _ellipse(c + Vector2(0, -13), 11.0, 11.0)
		_poly(_grow(bodyp, 6.0), CUT)
		_poly(_grow(head, 6.0), CUT)
		_poly(_grow(bodyp, 3.2), INK)
		_poly(_grow(head, 3.2), INK)
		_grad(bodyp, a, b)
		_grad(head, a.lerp(Color.WHITE, 0.2), b)
		_poly(_ellipse(c + Vector2(-4, -17), 3.0, 2.2), Color(1, 1, 1, 0.8))

	## A waving open hand: four fingers, a thumb, a palm, turning about the wrist.
	func _hand() -> void:
		var parts: Array = [_rrect(Rect2(-15, -7, 30, 27), 11.0, 6)]
		for x: float in [-15.0, -6.0, 3.0, 12.0]:
			var top := -27.0 if absf(x + 1.5) < 6.0 else -22.0
			parts.append(_rrect(Rect2(x, top, 8.0, 24.0), 4.0, 4))
		var thumb := PackedVector2Array()
		for v in _rrect(Rect2(-5, -14, 9.5, 24), 4.5, 4):
			thumb.append(Vector2(-17, 4) + v.rotated(-0.85))
		parts.append(thumb)
		for q: PackedVector2Array in parts:
			_poly(_grow(q, 6.5), CUT)
		for q: PackedVector2Array in parts:
			_poly(_grow(q, 3.5), INK)
		for q: PackedVector2Array in parts:
			_poly(q, Color("#ffcf8f"))
		draw_line(Vector2(-7, 7), Vector2(9, 7), Color("#e39a5c"), 2.5, true)

	func _confetti() -> void:
		var cols := [Color("#ff5a7a"), Color("#ffd23c"), Color("#40c8ff"), Color("#6fe06a"), Color("#b98cff")]
		var at := [Vector2(-16, -14), Vector2(13, -19), Vector2(20, 6), Vector2(-20, 14), Vector2(2, 18)]
		for i in at.size():
			var q := (at[i] as Vector2)
			var r := PackedVector2Array([Vector2(-6, -3.5), Vector2(6, -3.5), Vector2(6, 3.5), Vector2(-6, 3.5)])
			var a := float(i) * 1.2 + TAU * t
			var o := PackedVector2Array()
			for v in r:
				o.append(q + v.rotated(a))
			_poly(_grow(o, 5.0), CUT)
			_poly(_grow(o, 2.6), INK)
			_poly(o, cols[i % cols.size()])

	# ---------- polygon helpers ----------

	func _poly(pts: PackedVector2Array, c: Color) -> void:
		if pts.size() >= 3:
			var cols := PackedColorArray()
			cols.resize(pts.size())
			cols.fill(c)
			draw_polygon(pts, cols)

	func _grad(pts: PackedVector2Array, a: Color, b: Color) -> void:
		var lo := INF
		var hi := -INF
		for p in pts:
			lo = minf(lo, p.y)
			hi = maxf(hi, p.y)
		var cols := PackedColorArray()
		for p in pts:
			cols.append(a.lerp(b, (p.y - lo) / maxf(hi - lo, 0.001)))
		draw_polygon(pts, cols)

	func _grow(pts: PackedVector2Array, d: float) -> PackedVector2Array:
		var m := Geometry2D.offset_polygon(pts, d, Geometry2D.JOIN_ROUND)
		return m[0] if m.size() > 0 else pts

	func _line(pts: PackedVector2Array, c: Color, w: float) -> void:
		var closed := pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, c, w, true)
