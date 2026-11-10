class_name Meter
extends Control
## A progress bar drawn in code: a rounded track with a rounded fill. At 0 no fill is drawn (the bare light track reads
## as "no progress yet"); any progress shows at least MIN_SHOWN of the bar (and a round dot), gold fills end in a
## glint. Looks:
##   "xp"     GOLD_FILL (glossy) on the light TRACK         (XP on cream cards: profile, result screen)
##   "night"  GOLD_FILL (glossy) on a dark INK track, inset (web .pxp / .xpbar: the home top bar)
##   "track"  PEACH on TRACK                                (neutral progress: steps, collection counts)
##   "teal"   TEAL_SOFT on TRACK                            (achievements, collection progress)
##   "game"   a gold gradient on a dark rimmed track, Lilita numbers in white (the game look: Profile)
##   "game_teal" the same with a teal fill (the game look's achievements)
## Optional centred numbers ("45 / 150 XP", Nunito 900, 12-14 px with an outline so they read on fill and track);
## numbers need a bar of at least 16 px (the height grows to 16 when they're on).
## inset_left: the length of the left end an overlapping LevelBadge covers (LevelBadge.row sets it). The fill starts
## behind the badge and the fraction counts on the part after it, so any progress comes out from under the star.
##
##   var xp := Meter.new("night", 12)              # home: no numbers
##   var xp2 := Meter.new("xp", 20, true, "XP")    # profile: "45 / 150 XP"
##   xp2.set_value(45, 150, true)

const LOOKS := ["xp", "night", "track", "teal", "game", "game_teal"]
## The game look: [track, rim, fill top, fill bottom] (mock-up: #1a0b05 / #6b3a20, #ffe27a -> #f7a928).
const GAME := {game = [Color("#1a0b05"), Color("#6b3a20"), Color("#ffe27a"), Color("#f7a928")],
	game_teal = [Color("#1a0b05"), Color("#6b3a20"), Color("#7fe8d4"), Color("#2fb39c")]}
const SEC := 0.5
const MIN_SHOWN := 0.06              ## the least fill any progress shows (a fraction of the bar)

var look := "xp"
var value := 0.0                     ## the value (clamped to 0..max_value)
var max_value := 1.0
var numbers := false                 ## draw "value / max unit" in the middle
var unit := ""                       ## after the numbers ("XP"); "" = none
var text_override := ""              ## when set, drawn instead of the numbers
var inset_left := 0.0

var _shown := 0.0                    # the fraction on screen (animates)
var _tw: Tween
var _sb := {}                        # cached styleboxes


func _init(look_ := "xp", height := 14.0, numbers_ := false, unit_ := "") -> void:
	look = look_ if look_ in LOOKS else "xp"
	numbers = numbers_
	unit = unit_
	var h := maxf(height, 16.0) if numbers else maxf(height, 6.0)
	custom_minimum_size = Vector2(40, h)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Set the value and maximum (value is clamped to 0..max; max <= 0 counts as an empty bar). animate: the fill slides
## from where it is over 0.5 s.
func set_value(v: float, max_v: float, animate := false) -> void:
	max_value = maxf(0.0, max_v)
	value = clampf(v, 0.0, max_value)
	var target := fraction()
	if _tw and _tw.is_valid():
		_tw.kill()
	if animate and is_inside_tree() and not is_equal_approx(_shown, target):
		_tw = create_tween()
		_tw.tween_method(func(f: float) -> void:
			_shown = f
			queue_redraw(), _shown, target, SEC).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		_shown = target
	queue_redraw()


## value / max_value in 0..1 (0 when max is 0).
func fraction() -> float:
	return clampf(value / max_value, 0.0, 1.0) if max_value > 0.0 else 0.0


## The fraction on screen right now (differs from fraction() while animating).
func shown_fraction() -> float:
	return _shown


## The centred text ("45 / 150 XP"), "" when numbers are off.
func label_text() -> String:
	if text_override != "":
		return text_override
	if not numbers:
		return ""
	var t := "%s / %s" % [Fmt.coins_full(int(round(value))), Fmt.coins_full(int(round(max_value)))]
	return t + (" " + unit if unit != "" else "")


## The label in the room there is: as is, then without the unit and the spaces ("45/150"), else "" (none).
static func fitted_text(t: String, font: Font, fs: int, room: float) -> String:
	if font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= room:
		return t
	var parts := t.split(" ", false)
	var short := t.replace(" ", "")
	if parts.size() >= 3 and parts[1] == "/":
		short = parts[0] + "/" + parts[2]
	if font.get_string_size(short, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= room:
		return short
	return ""


## Replace the numbers with a text of your own ("" = back to the numbers).
func set_text(t: String) -> void:
	text_override = t
	queue_redraw()


# ---------------------------------------------------------------------------------------------------------------------

func _box(key: String, bg: Color) -> StyleBoxFlat:
	if not _sb.has(key):
		var s := StyleBoxFlat.new()
		s.bg_color = bg
		s.set_corner_radius_all(UIKit.R.pill)
		s.corner_detail = 8
		s.anti_aliasing = true
		_sb[key] = s
	return _sb[key]


func _draw() -> void:
	if GAME.has(look):
		_draw_game()
		return
	var h := size.y
	var track := Rect2(Vector2.ZERO, size)
	var night := look == "night"
	var pad := clampf(roundf(h * 0.16), 2.0, 3.0) if night else 0.0
	var track_col := Palette.INK if night else Palette.TRACK
	draw_style_box(_box("track", track_col), track)
	# inset shade along the top of the track (web: inset 0 2px 3px)
	var shade := _box("shade", Color(0, 0, 0, 0))
	shade.border_width_top = 2
	shade.border_color = Color(0, 0, 0, 0.32) if night else Color(Palette.SHADOW, 0.12)
	shade.border_blend = true
	draw_style_box(shade, track)
	var inner := Rect2(track.position + Vector2(pad, pad), track.size - Vector2(2.0 * pad, 2.0 * pad))
	var vis := inner.size.x - inset_left               # the part of the bar after the badge
	if vis <= 0.0 or inner.size.y <= 0.0:
		return
	var w: float
	# any progress shows at least MIN_SHOWN of the bar (an XP bar early in a level shouldn't read as empty)
	var shown := maxf(_shown, MIN_SHOWN) if _shown > 0.001 else 0.0
	if inset_left > 0.0:                               # from behind the badge: at least half a dot shows past it
		w = inset_left + clampf(vis * shown, minf(inner.size.y * 0.5, vis), vis)
	else:
		w = clampf(inner.size.x * shown, minf(inner.size.y, inner.size.x), inner.size.x)   # never narrower than a round dot
	var fill := Rect2(inner.position, Vector2(w, inner.size.y))
	var fill_col: Color
	match look:
		"xp", "night": fill_col = Palette.GOLD_FILL
		"track": fill_col = Palette.PEACH
		_: fill_col = Palette.TEAL_SOFT
	var fb := _box("fill_" + look, fill_col)
	fb.bg_color = fill_col
	if not night:
		# a hairline darker rim so the fill reads on the light track
		fb.border_width_bottom = 1 if inner.size.y >= 8.0 else 0
		fb.border_color = fill_col.darkened(0.18)
	if _shown > 0.001:
		draw_style_box(fb, fill)
	# gloss: a soft white band over the top half (web linear-gradient(gold-hi, gold))
	if _shown > 0.001 and fill.size.y >= 6.0 and fill.size.x >= 6.0:
		var g := _box("gloss", Palette.GLOSS)
		var gh := roundf(fill.size.y * 0.42)
		var gr := Rect2(fill.position + Vector2(minf(3.0, fill.size.x * 0.25), 1.0), Vector2(maxf(0.0, fill.size.x - 2.0 * minf(3.0, fill.size.x * 0.25)), gh))
		if gr.size.x > 2.0:
			draw_style_box(g, gr)
		# a glint at the tip of a gold fill: the bar looks lit, and the tip reads as "you are here"
		if look in ["xp", "night"] and fill.size.x >= fill.size.y * 1.5:
			var gc := Vector2(fill.end.x - fill.size.y * 0.42, fill.position.y + fill.size.y * 0.36)
			draw_circle(gc, maxf(1.0, fill.size.y * 0.16), Color(1, 1, 1, 0.85))
			draw_circle(gc, maxf(1.5, fill.size.y * 0.3), Color(1, 1, 1, 0.22))
	var t := label_text()
	if t == "":
		return
	var fs := clampi(int(h) - 6, UIKit.FS.small, UIKit.FS.label)
	var font := UIKit.font_body(900, true)
	var area := Rect2(Vector2(inset_left, 0), Vector2(size.x - inset_left, h))
	t = fitted_text(t, font, fs, area.size.x - 8.0)
	if t == "":
		return                                       # too narrow for any form of the numbers: the bar alone
	var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos := Vector2(area.position.x + (area.size.x - tw) / 2.0, (h - font.get_height(fs)) / 2.0 + font.get_ascent(fs))
	var fg := Color.WHITE if night else Palette.INK
	var ol := Color(Palette.INK_STRONG, 0.75) if night else Color(Color.WHITE, 0.85)
	draw_string_outline(font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, ol)
	draw_string(font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, fg)


## The game look: a dark track with a 2 px rim, the fill a top-to-bottom gradient cut square at its end (the track's
## rounded ends clip it), the numbers in white Lilita One with a dark edge.
func _draw_game() -> void:
	var c: Array = GAME[look]
	var h := size.y
	var track := Rect2(Vector2.ZERO, size)
	var tb := _box("game_track", c[0])
	tb.bg_color = c[0]
	tb.set_border_width_all(2)
	tb.border_color = c[1]
	draw_style_box(tb, track)
	var inner := track.grow(-2.0)
	if _shown > 0.001 and inner.size.x > 2.0 and inner.size.y > 2.0:
		var shown := maxf(_shown, MIN_SHOWN)
		var w := inset_left + (inner.size.x - inset_left) * shown
		var cut := PackedVector2Array([inner.position, inner.position + Vector2(w, 0), inner.position + Vector2(w, inner.size.y),
			inner.position + Vector2(0, inner.size.y)])
		var parts := Geometry2D.intersect_polygons(_pill(inner), cut)
		if not parts.is_empty():
			var pts: PackedVector2Array = parts[0]
			var cols := PackedColorArray()
			for p in pts:
				cols.append((c[2] as Color).lerp(c[3], clampf((p.y - inner.position.y) / inner.size.y, 0.0, 1.0)))
			draw_polygon(pts, cols)
	var t := label_text()
	if t == "":
		return
	var font := UIKit.font_display()
	var fs := clampi(int(h) - 8, 11, 16)
	var area := Rect2(Vector2(inset_left, 0), Vector2(size.x - inset_left, h))
	t = fitted_text(t, font, fs, area.size.x - 8.0)
	if t == "":
		return
	var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos := Vector2(area.position.x + (area.size.x - tw) / 2.0, (h - font.get_height(fs)) / 2.0 + font.get_ascent(fs))
	draw_string_outline(font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0.23, 0.1, 0.05, 0.55))
	draw_string(font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)

## A pill (fully rounded ends) as a polygon.
static func _pill(r: Rect2) -> PackedVector2Array:
	var rad := minf(r.size.y, r.size.x) / 2.0
	var pts := PackedVector2Array()
	var cl := Vector2(r.position.x + rad, r.position.y + r.size.y / 2.0)
	var cr := Vector2(r.end.x - rad, cl.y)
	for i in 13:
		var a := PI / 2.0 + PI * i / 12.0
		pts.append(cl + Vector2(cos(a), sin(a)) * rad)
	for i in 13:
		var a := -PI / 2.0 + PI * i / 12.0
		pts.append(cr + Vector2(cos(a), sin(a)) * rad)
	return pts
