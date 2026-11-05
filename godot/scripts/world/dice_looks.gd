class_name DiceLooks
extends RefCounted
## What each dice skin (Catalog.DICE) is made of, for the die's one shader (Dice3D.SHADER): see LOOKS. Catalog keeps the
## economy and the four base colours; this is the material. Patterns are small textures painted once per skin (at most
## PATTERN_PX square, in milliseconds), kept for the session: a die only ever paints its own.
##
##   Dice3D.wear(id)          puts a skin on a die
##   DiceLooks.pattern(name)  -> Texture2D, null for a skin without one

const PATTERN_PX := 128

## pat, pat_k (how much of it shows), pat_shift (1: every face a different part; for patterns that tile), pat_glow,
## metal (the body is polished metal) in metal_tint, pip_metal (pips inlaid in metal), pip_rim (a ring round each pip,
## alpha = strength), pip_glow, band (a line framing each face, alpha = strength), band_metal, rim (a glow at grazing
## angles, alpha = strength), rough, spec, edge_k (polished corners take on the edge colour this much), shine (a band of
## light crosses the die while it waits, and when it lands: the premium skins), flash (the landing's colour).
const LOOKS := {
	classic = {rough = 0.16, spec = 0.6, edge_k = 0.5, pat = "ivory", pat_k = 1.0, pat_shift = 1.0, flash = "#ffe9b0"},
	crema = {pat = "latte", pat_k = 1.0, pat_shift = 1.0, rough = 0.2, spec = 0.55, edge_k = 0.4, pip_rim = "#fff1d6cc", flash = "#ffe0ae"},
	espresso = {pat = "roast", pat_k = 1.0, pat_shift = 1.0, rough = 0.1, spec = 0.75, edge_k = 0.65, pip_metal = 1.0, metal_tint = "#f4bd3c",
		band = "#f4bd3cff", band_metal = 1.0, shine = 0.5, flash = "#f4bd3c"},
	gold = {metal = 1.0, metal_tint = "#f7c63e", pat = "filigree", pat_k = 1.0, rough = 0.16, spec = 0.8, edge_k = 0.0, pip_rim = "#7a4a0ad0", shine = 1.0, flash = "#ffd76a"},
	rosewood = {pat = "wood", pat_k = 1.0, pat_shift = 1.0, rough = 0.28, spec = 0.5, edge_k = 0.35, band = "#d9a441ff", band_metal = 1.0, metal_tint = "#d9a441", flash = "#d9a441"},
	marble = {pat = "stone", pat_k = 1.0, pat_shift = 1.0, rough = 0.08, spec = 0.8, edge_k = 0.3, pip_metal = 1.0, metal_tint = "#f4bd3c", shine = 0.5, flash = "#fff1c4"},
	rickshaw = {pat = "rickshaw", pat_k = 1.0, rough = 0.18, spec = 0.6, edge_k = 0.6, pip_rim = "#0f8f5cff", flash = "#ffd23f"},
	emerald = {pat = "facets", pat_k = 1.0, rough = 0.05, spec = 0.9, edge_k = 0.5, pip_metal = 1.0, metal_tint = "#fff0c0", rim = "#7dffc450", shine = 0.9, flash = "#7dffc4"},
	neon = {pat = "grid", pat_k = 1.0, pat_glow = 0.9, rough = 0.2, spec = 0.5, edge_k = 0.8, pip_glow = 1.5, band = "#39f5ffff", band_glow = 1.3, rim = "#39f5ff70", shine = 0.6, flash = "#39f5ff"},
	galaxy = {pat = "nebula", pat_k = 1.0, pat_shift = 1.0, pat_glow = 0.55, rough = 0.12, spec = 0.7, edge_k = 0.5, pip_glow = 0.8, rim = "#8a7bff90", shine = 0.8, flash = "#b7a8ff"},
}

static var _tex := {}

static func look(id: String) -> Dictionary:
	return LOOKS.get(id, LOOKS.classic)

static func pattern(name: String) -> Texture2D:
	if name == "":
		return null
	if not _tex.has(name):
		var img := _paint(name)
		img.generate_mipmaps()
		_tex[name] = ImageTexture.create_from_image(img)
	return _tex[name]

## A seamless noise, 0..1, PATTERN_PX square.
static func _noise(seed_: int, freq: float, octaves := 3, kind := FastNoiseLite.TYPE_SIMPLEX_SMOOTH) -> PackedByteArray:
	var n := FastNoiseLite.new()
	n.seed = seed_
	n.noise_type = kind
	n.frequency = freq
	n.fractal_octaves = octaves
	var im := n.get_seamless_image(PATTERN_PX, PATTERN_PX)
	im.convert(Image.FORMAT_L8)
	return im.get_data()

static func _paint(name: String) -> Image:
	var n := PATTERN_PX
	var data := PackedByteArray()
	data.resize(n * n * 4)
	match name:
		"ivory":
			var a := _noise(5, 0.012, 2)
			_each(data, func(x: int, y: int, u: float, v: float) -> Color:
				var g: float = a[y * n + x] / 255.0
				var band := 0.5 + 0.5 * sin((v * 2.0 + g * 1.4) * TAU)
				return Color("#fffaf0").lerp(Color("#f6ead4"), band * 0.55))
		"latte":                                     # steamed milk folded into coffee: soft, wide swirls
			var a := _noise(11, 0.012, 2)
			_each(data, func(x: int, y: int, u: float, v: float) -> Color:
				var g: float = a[y * n + x] / 255.0
				var w := 0.5 + 0.5 * sin((u + v * 2.0) * TAU + g * 5.0)
				return Color("#f8e6c8").lerp(Color("#d9a974"), smoothstep(0.42, 0.96, w) * 0.85))
		"roast":
			var a := _noise(23, 0.014, 2)
			_each(data, func(x: int, y: int, u: float, v: float) -> Color:
				var g: float = a[y * n + x] / 255.0
				var w := absf(sin((u * 2.0 + v) * TAU + g * 4.0))
				var c := Color("#2a150a").lerp(Color("#4f2c17"), g)
				return c.lerp(Color("#b57f4c"), pow(1.0 - w, 9.0) * 0.5))
		"stone":
			var a := _noise(31, 0.014, 2)
			_each(data, func(x: int, y: int, u: float, v: float) -> Color:
				var g: float = a[y * n + x] / 255.0
				var w := absf(sin((u * 2.0 + v * 3.0) * TAU + g * 3.5))
				var w2 := absf(sin((u * 3.0 - v) * TAU + g * 5.0))
				var c := Color("#fcfbf8").lerp(Color("#e8e5df"), (1.0 - g) * 0.7)
				c = c.lerp(Color("#55504f"), pow(1.0 - w, 11.0) * 0.85)
				return c.lerp(Color("#c99a3c"), pow(1.0 - w2, 22.0) * 0.9))
		"wood":
			var a := _noise(41, 0.02, 2)
			_each(data, func(x: int, y: int, u: float, v: float) -> Color:
				var g: float = a[y * n + x] / 255.0
				var rings := 0.5 + 0.5 * sin((u * 7.0 + g * 2.6) * TAU)
				var c := Color("#6b2c17").lerp(Color("#3d170c"), pow(rings, 2.0))
				return c.lerp(Color("#8d4322"), pow(1.0 - rings, 8.0) * 0.6))
		"nebula":
			var a := _noise(53, 0.018, 4)
			var b := _noise(59, 0.024, 3)
			var r := RandomNumberGenerator.new()
			r.seed = 7
			_each(data, func(x: int, y: int, u: float, v: float) -> Color:
				var g: float = a[y * n + x] / 255.0
				var h: float = b[y * n + x] / 255.0
				var c := Color("#0d0830").lerp(Color("#3c1a8c"), smoothstep(0.42, 0.72, g))
				c = c.lerp(Color("#d43f9e"), smoothstep(0.58, 0.82, h) * 0.75)
				var s := r.randf()
				if s > 0.992:
					return Color.WHITE
				return c.lerp(Color("#bcd2ff"), 0.9) if s > 0.975 else c)
		"facets":                                   # a cut stone: wedges from the middle, each its own shade
			_each(data, func(_x: int, _y: int, u: float, v: float) -> Color:
				var d := Vector2(u - 0.5, v - 0.5)
				var a := fposmod(atan2(d.y, d.x) / TAU + 0.0625, 1.0)
				var box := maxf(absf(d.x), absf(d.y)) * 2.0
				var ring := 2 if box > 0.72 else (1 if box > 0.36 else 0)
				var wedge := int(a * 8.0)
				var k := 0.5 + 0.5 * sin(float(wedge * 5 + ring * 3) * 1.7)
				var c := Color("#033423").lerp(Color("#0fa268"), k * k)
				return c.lerp(Color("#7dffc9"), 0.22 if (wedge + ring) % 5 == 0 else 0.0))
		"grid":
			_each(data, func(_x: int, _y: int, u: float, v: float) -> Color:
				var gx := absf(fposmod(u * 4.0, 1.0) - 0.5)
				var gy := absf(fposmod(v * 4.0, 1.0) - 0.5)
				var line := smoothstep(0.44, 0.5, maxf(gx, gy))
				return Color("#0b0d22").lerp(Color("#1f6fff"), line * 0.55))
		"filigree":                                  # a fine engraved double frame, a scroll in each corner
			_each(data, func(_x: int, _y: int, u: float, v: float) -> Color:
				var d := Vector2(absf(u - 0.5), absf(v - 0.5))
				var ink := 0.0
				var box := maxf(d.x, d.y)
				ink = maxf(ink, 1.0 - smoothstep(0.002, 0.008, absf(box - 0.452)))
				ink = maxf(ink, 1.0 - smoothstep(0.001, 0.006, absf(box - 0.43)))
				var c := d - Vector2(0.43, 0.43)
				var r := c.length()
				var ang := atan2(-c.y, -c.x)
				if ang > 0.0 and ang < PI / 2.0:             # inside the frame's corner: a little fan
					ink = maxf(ink, 1.0 - smoothstep(0.002, 0.007, absf(r - 0.09)))
					ink = maxf(ink, 1.0 - smoothstep(0.002, 0.006, absf(r - 0.055)))
					if r < 0.09:
						ink = maxf(ink, (1.0 - smoothstep(0.0, 0.05, absf(fposmod(ang * 8.0 / PI, 1.0) - 0.5))) * smoothstep(0.02, 0.03, r))
				return Color(0.42, 0.22, 0.03, ink * 0.85))
		"rickshaw":                                  # rickshaw art: painted flowers and leaves in the corners, a dotted frame
			_each(data, func(_x: int, _y: int, u: float, v: float) -> Color:
				var d := Vector2(absf(u - 0.5), absf(v - 0.5))
				var mid := Vector2(u - 0.5, v - 0.5)
				var petals := 0.27 + 0.1 * absf(cos(atan2(mid.y, mid.x) * 4.0))     # a big painted flower behind the pips, tone on tone
				var col := Color("#b5112c") if mid.length() < petals and mid.length() > 0.12 else Color("#d81f3c")
				if absf(mid.length() - petals) < 0.008:
					col = Color("#ffd23f")
				var box := maxf(d.x, d.y)
				if absf(box - 0.455) < 0.02:
					col = Color("#ffd23f")
				var along := minf(d.x, d.y)
				if absf(box - 0.415) < 0.012 and fposmod(along * 18.0, 1.0) < 0.5:
					col = Color("#1aa6e8")
				var f := d - Vector2(0.385, 0.385)
				var r := f.length()
				var ang := atan2(f.y, f.x)
				if r < 0.052 + 0.024 * cos(ang * 5.0):
					col = Color("#ff8fc0")
				if r < 0.022:
					col = Color("#ffd23f")
				var lf := Vector2(d.x - 0.25, d.y - 0.405)
				var lf2 := Vector2(d.x - 0.405, d.y - 0.25)
				if lf.x * lf.x / 0.0035 + lf.y * lf.y / 0.0006 < 1.0 or lf2.x * lf2.x / 0.0006 + lf2.y * lf2.y / 0.0035 < 1.0:
					col = Color("#17a56b")
				return col)
	return Image.create_from_data(n, n, false, Image.FORMAT_RGBA8, data)

## Fills data pixel by pixel: fn(x, y, u, v) -> Color.
static func _each(data: PackedByteArray, fn: Callable) -> void:
	var n := PATTERN_PX
	for y in n:
		for x in n:
			var c: Color = fn.call(x, y, (x + 0.5) / n, (y + 0.5) / n)
			var i := (y * n + x) * 4
			data[i] = c.r8
			data[i + 1] = c.g8
			data[i + 2] = c.b8
			data[i + 3] = c.a8
