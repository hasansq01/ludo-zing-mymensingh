class_name EmoteLayer
extends Control
## The emote reactions over a game (Ludo and Snakes & Ladders; index.html `Emotes.show` / `spot` / `react`): a
## sticker (EmoteArt.frames, its own cream speech bubble) with a thin glow in the sender's colour pops in beside the
## sender's dice, holds ≈2.4 s while the character inside moves, then shrinks away. One at a time per player; the
## next ones wait (at most QUEUE). Purely visual: no game state, rule or turn is touched, and it never takes input.
##
## Placement comes from the owner, per colour: seat_fn(c) -> {card: Rect2 (the whole tile at its turn size), slot:
## Rect2 (the dice slot), inner: "right" | "left" | "center", low: bool (a bottom tile: the bubble goes above it),
## ceiling: float (optional, low tiles: the bubble stays above this y, e.g. a prompt over the tile row)}
## ({} = no such seat). Ludo corners: beside the dice on the inner side, just above the bottom tiles / just below the
## top ones, each on its own half of the screen and clear of avoid_fn() (the emote button). S&L ("center"): under the
## player's tile in the top row. Size: bubble_width() (116 px on a normal phone, smaller on a narrow screen).
##
## Computer players (offline): cpu_say() and the react_* rules: a reaction now and then (random chance), throttled
## (CPU_GAP s per computer, ANY_GAP s overall, never the same emote twice running), shown after a short delay.
## Time is driven by tick(dt) (from _process; tests call it); now_fn is the clock in ms (tests replace it).
## Reduce motion: the sticker fades in and out (no pop, no frame animation).

signal shown(c: int, id: String)

const LIFE := 2.4                        ## s on screen
const POP := 0.42                        ## the pop in (emPop)
const OUT_AT := 2.1                      ## the shrink away starts (emOut, 0.3 s)
const QUEUE := 2                         ## waiting per player
const BASE_W := 116.0
const MIN_W := 84.0
const ASPECT := 218.0 / 344.0            ## the sticker art (EmoteArt frames are 344 x 218)
const BGAP := 4.0                        ## px between the tile and the bubble
const BSIDE := 24.0                      ## px the bubble sits beyond the dice slot (at BASE_W)
const EDGE := 8.0
const CPU_GAP := 9000                    ## ms between two reactions of one computer
const ANY_GAP := 4000                    ## ms between two computer reactions at all
const CPU_DELAY := [0.35, 0.85]          ## s before a computer's reaction shows
const STARTER := ["happy", "laugh", "cool", "angry", "love", "party"]

var seat_fn := Callable()                ## (c: int) -> Dictionary (see above)
var avoid_fn := Callable()               ## () -> Rect2 (size 0: nothing to avoid)
var is_cpu_fn := Callable()              ## (c: int) -> bool: a computer player (offline)
var is_human_fn := Callable()            ## (c: int) -> bool: a person at this table
var now_fn := Callable()                 ## () -> int ms (Time.get_ticks_msec by default)
var rng := RandomNumberGenerator.new()
var still := -1                          ## reduce motion: -1 = the Settings pref, 0 / 1 = forced (tests)
var mute := false                        ## no sound (tests, previews)
var always := false                      ## tests: every chance hits (the throttles still apply)

var showing := {}                        ## colour -> Bubble
var queue := {}                          ## colour -> Array of emote ids waiting
var _later: Array = []                   ## [seconds left, colour, id]: computer reactions on their way
var _last_cpu := {}                      ## colour -> the last emote id a computer used
var _cpu_at := {}                        ## colour -> ms of its last reaction
var _any_at := -100000000
static var _glow: Shader


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rng.randomize()

func _process(delta: float) -> void:
	tick(delta)

## Shows colour c's reaction (or queues it while one is showing). False when it can't (no such seat or emote, a
## full queue).
func show_emote(c: int, id: String) -> bool:
	if EmoteArt.info(id).is_empty() or _seat(c).is_empty():
		return false
	if showing.has(c):
		var q: Array = queue.get(c, [])
		if q.size() >= QUEUE:
			return false
		q.append(id)
		queue[c] = q
		return true
	var b := Bubble.new(c, id, _still())
	b.material = _material(c)
	add_child(b)
	showing[c] = b
	_place(b)
	b.step(0.0)
	if not mute:
		_sound(id)
	shown.emit(c, id)
	return true

## The reaction after `sec` seconds (a computer's, so it doesn't land on the very frame of the event).
func show_later(c: int, id: String, sec: float) -> void:
	_later.append([sec, c, id])

## A new game (or leaving one): no bubbles, queues or computer cooldowns carried over.
func clear() -> void:
	for b in showing.values():
		if is_instance_valid(b):
			b.queue_free()
	showing.clear()
	queue.clear()
	_later.clear()
	_last_cpu.clear()
	_cpu_at.clear()
	_any_at = -100000000

## Time passes: bubbles animate and end (the next queued one follows), delayed reactions arrive.
func tick(dt: float) -> void:
	for k in range(_later.size() - 1, -1, -1):
		_later[k][0] -= dt
		if _later[k][0] <= 0.0:
			var l: Array = _later[k]
			_later.remove_at(k)
			show_emote(int(l[1]), str(l[2]))
	for c in showing.keys():
		var b: Bubble = showing[c]
		if not is_instance_valid(b):
			showing.erase(c)
			continue
		b.step(dt)
		_place(b)
		if b.t >= LIFE:
			showing.erase(c)
			b.queue_free()
			var q: Array = queue.get(c, [])
			if not q.is_empty():
				show_emote(c, str(q.pop_front()))

## The bubble's width for this screen: 116 px on a normal phone, down to 84 px on a small one.
func bubble_width() -> float:
	var s := size if size.x > 0 else Vector2(390, 844)
	return roundf(minf(BASE_W, maxf(MIN_W, minf(s.x * 0.3, s.y * 0.15))))

## Where colour c's bubble goes (its rect in this layer), or an empty rect when the seat isn't there.
func spot(c: int) -> Rect2:
	var st := _seat(c)
	if st.is_empty():
		return Rect2()
	var W := size.x if size.x > 0 else 390.0
	var H := size.y if size.y > 0 else 844.0
	var card: Rect2 = st.get("card", Rect2())
	var slot: Rect2 = st.get("slot", card)
	var inner := str(st.get("inner", "right"))
	var low := bool(st.get("low", false))
	var bw := bubble_width()
	if inner == "center":                    # S&L: under the tile, as wide as the tile pitch allows
		var pitch := float(st.get("pitch", bw))
		var w1 := roundf(minf(bw, maxf(pitch + 6.0, MIN_W * 0.9)))
		var h1 := roundf(w1 * ASPECT)
		var x1 := clampf(card.get_center().x - w1 / 2.0, EDGE, W - EDGE - w1)
		var y1 := clampf(card.end.y + BGAP, EDGE, H - EDGE - h1)
		return Rect2(x1, y1, w1, h1)
	# Ludo: each player's reaction stays on its own half (left and right ones never meet in the middle)
	var half := W / 2.0
	var right_side := inner == "left"        # a right-hand tile: the inner side is its left
	var min_l := half + 4.0 if right_side else EDGE
	var max_r := W - EDGE if right_side else half - 4.0
	var av := avoid_fn.call() as Rect2 if avoid_fn.is_valid() else Rect2()
	var floor_y := minf(card.position.y, float(st.get("ceiling", card.position.y)))   # a low bubble's bottom edge
	if low and av.size.x > 0.0:
		var narrow_l := min_l
		var narrow_r := max_r
		if not right_side and av.end.x < half:
			narrow_l = maxf(min_l, av.end.x + 6.0)
		elif right_side and av.position.x > half:
			narrow_r = minf(max_r, av.position.x - 6.0)
		if narrow_r - narrow_l >= bw * 0.85:
			min_l = narrow_l
			max_r = narrow_r
		elif narrow_l != min_l or narrow_r != max_r:
			floor_y = minf(floor_y, av.position.y)   # too narrow beside the button: above it instead
	var w := roundf(minf(bw, max_r - min_l))
	var h := roundf(w * ASPECT)
	var side := BSIDE * w / BASE_W
	var cx := slot.position.x - side if right_side else slot.end.x + side
	cx = clampf(cx, min_l + w / 2.0, max_r - w / 2.0)
	var cy := floor_y - BGAP - h / 2.0 if low else card.end.y + BGAP + h / 2.0
	cy = clampf(cy, h / 2.0 + EDGE, H - h / 2.0 - EDGE)
	return Rect2(roundf(cx - w / 2.0), roundf(cy - h / 2.0), w, h)


# ---------- computer players ----------

## A computer's occasional reaction: with `chance`, unless it spoke in the last CPU_GAP ms or any computer did in
## the last ANY_GAP ms; never the same emote twice running. True when one is on its way.
func cpu_say(c: int, ids: Array, chance: float) -> bool:
	if ids.is_empty() or not _is_cpu(c) or (not always and rng.randf() >= chance):
		return false
	var now := _now()
	if now - _any_at < ANY_GAP or now - int(_cpu_at.get(c, -100000000)) < CPU_GAP:
		return false
	var opts := ids.filter(func(x): return x != _last_cpu.get(c, ""))
	if opts.is_empty():
		opts = ids
	var id := str(opts[rng.randi() % opts.size()])
	_any_at = now
	_cpu_at[c] = now
	_last_cpu[c] = id
	show_later(c, id, rng.randf_range(CPU_DELAY[0], CPU_DELAY[1]))
	return true

## A capture: the victim (a computer hit by a person) sulks, else the capturing computer gloats over a person.
func react_capture(c: int, victim_colours: Array) -> bool:
	var owners := []
	for v in victim_colours:
		if not owners.has(int(v)):
			owners.append(int(v))
	if _is_human(c):
		for o in owners:
			if _is_cpu(o):
				return cpu_say(o, ["cry", "angry", "wow", "facepalm", "sad"], 0.4)
		return false
	if _is_cpu(c) and owners.any(func(o): return _is_human(int(o))):
		return cpu_say(c, ["laugh", "cool", "tease"], 0.35)
	return false

## The end: a winning computer celebrates, else a losing one congratulates (or sulks).
func react_win(winners: Array, seats: Array) -> bool:
	for w in winners:
		if _is_cpu(int(w)):
			return cpu_say(int(w), ["party", "crown", "happy"], 0.7)
	for o in seats:
		if _is_cpu(int(o)) and not winners.has(o):
			return cpu_say(int(o), ["cheer", "sad", "cry"], 0.5)
	return false

## Play on: a computer finished while the game goes on.
func react_finish(c: int) -> bool:
	return cpu_say(c, ["party", "happy", "champ"], 0.5)

## Snakes & Ladders: a computer slid down a snake (it sulks), or climbed a ladder (it shows off).
func react_snake(c: int) -> bool:
	return cpu_say(c, ["cry", "sad", "facepalm", "angry"], 0.35)

func react_ladder(c: int) -> bool:
	return cpu_say(c, ["cool", "happy", "champ"], 0.25)

## Online: an incoming {t: "emote", c, id} -> [c, id] to show, or [] (the lobby's c = -1, your own colour, a seat
## that isn't playing, an unknown emote).
static func incoming(m: Dictionary, me: int, seated: Callable) -> Array:
	var c := int(m.get("c", -1))
	var id := str(m.get("id", ""))
	if c < 0 or c > 3 or c == me or EmoteArt.info(id).is_empty():
		return []
	if seated.is_valid() and not bool(seated.call(c)):
		return []
	return [c, id]


# ---------- internals ----------

func _seat(c: int) -> Dictionary:
	if not seat_fn.is_valid():
		return {}
	var d: Variant = seat_fn.call(c)
	return d if d is Dictionary else {}

func _place(b: Bubble) -> void:
	var r := spot(b.c)
	if r.size.x <= 0.0:
		return
	b.base = r.position
	b.size = r.size
	b.apply()

func _is_cpu(c: int) -> bool:
	return is_cpu_fn.is_valid() and bool(is_cpu_fn.call(c))

func _is_human(c: int) -> bool:
	return is_human_fn.is_valid() and bool(is_human_fn.call(c))

func _now() -> int:
	return int(now_fn.call()) if now_fn.is_valid() else Time.get_ticks_msec()

func _still() -> bool:
	return still == 1 if still >= 0 else PlayerTile._pref("reduce_motion")

func _sound(id: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var snd: Node = tree.root.get_node_or_null("Sound") if tree and tree.root else null
	if snd == null:
		return
	if snd.has_method("emote"):
		snd.call("emote", id)
	elif snd.has_method("sfx"):
		snd.call("sfx", "tap")

## The thin glow in the sender's colour round the sticker, plus its soft shadow (the web's drop-shadow filter).
static func _material(c: int) -> ShaderMaterial:
	if _glow == null:
		_glow = Shader.new()
		_glow.code = """
shader_type canvas_item;
uniform vec4 glow : source_color = vec4(1.0);
uniform vec4 shade : source_color = vec4(0.31, 0.16, 0.12, 0.35);
uniform vec2 px = vec2(0.003, 0.005);      // one screen pixel in UV
varying vec4 tint;                         // the draw's own colour (COLOR in fragment() already holds the texture)
void vertex() {
	tint = COLOR;
}
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float a = 0.0;                             // a crisp ring, then a softer one outside it
	for (int k = 0; k < 12; k++) {
		float ang = float(k) * 0.5236;
		vec2 d = vec2(cos(ang), sin(ang)) * px;
		a = max(a, max(texture(TEXTURE, UV + d * 1.4).a, texture(TEXTURE, UV + d * 2.6).a * 0.5));
	}
	float s = 0.0;
	for (int k = 0; k < 8; k++) {
		float ang = float(k) * 0.7854;
		s += texture(TEXTURE, UV + vec2(cos(ang), sin(ang)) * px * 3.0 - vec2(0.0, 5.0) * px).a;
	}
	s = s / 8.0 * shade.a;
	vec4 under = vec4(shade.rgb, s);
	vec4 g = vec4(glow.rgb, a * glow.a);
	under = vec4(mix(under.rgb, g.rgb, g.a), g.a + under.a * (1.0 - g.a));
	vec4 o = vec4(mix(under.rgb, c.rgb, c.a), c.a + under.a * (1.0 - c.a));
	COLOR = o * tint;
}
"""
	var m := ShaderMaterial.new()
	m.shader = _glow
	m.set_shader_parameter("glow", Color(Palette.PLAYER[posmod(c, 4)], 0.95))
	m.set_shader_parameter("shade", Color(Palette.SHADOW_DEEP, 0.38))
	return m


## One reaction: the sticker's frames (looping), popping in and shrinking away around its centre.
class Bubble extends Control:
	const PAD := 8.0                      # px of room round the art for the glow and the shadow
	var c := 0
	var id := ""
	var t := 0.0
	var still := false
	var base := Vector2.ZERO
	var frames: SpriteFrames
	var frame := 0
	var _fps := 15.0
	var _count := 0
	var _icon: Texture2D

	func _init(c_: int, id_: String, still_: bool) -> void:
		c = c_
		id = id_
		still = still_
		name = "Emote_%d_%s" % [c_, id_]
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		frames = EmoteArt.frames(id_)
		if frames:
			_fps = maxf(frames.get_animation_speed("default"), 1.0)
			_count = frames.get_frame_count("default")
		_icon = EmoteArt.icon(id_)
		resized.connect(queue_redraw)

	func step(dt: float) -> void:
		t += dt
		var f := 0 if still or _count == 0 else int(floor(t * _fps)) % _count
		if f != frame or dt == 0.0:
			frame = f
			queue_redraw()

	## Position, scale and fade for the time now (emPop / emOut; reduce motion: emFade).
	func apply() -> void:
		pivot_offset = size / 2.0
		var k := 1.0
		var dy := 0.0
		var a := 1.0
		if still:
			var u := t / LIFE
			a = clampf(u / 0.1, 0.0, 1.0) if u < 0.1 else (1.0 if u < 0.85 else clampf((1.0 - u) / 0.15, 0.0, 1.0))
		elif t < POP:
			var u := t / POP
			if u < 0.55:
				var e := _ease(u / 0.55)
				k = lerpf(0.6, 1.07, e)
				dy = lerpf(8.0, -2.0, e)
				a = clampf(u / 0.4, 0.0, 1.0)
			elif u < 0.78:
				var e2 := (u - 0.55) / 0.23
				k = lerpf(1.07, 0.98, e2)
				dy = lerpf(-2.0, 0.0, e2)
			else:
				k = lerpf(0.98, 1.0, (u - 0.78) / 0.22)
		elif t >= OUT_AT:
			var u2 := clampf((t - OUT_AT) / (LIFE - OUT_AT), 0.0, 1.0)
			var e3 := u2 * u2
			k = lerpf(1.0, 0.96, e3)
			dy = lerpf(0.0, -6.0, e3)
			a = 1.0 - e3
		scale = Vector2(k, k)
		position = base + Vector2(0, dy)
		modulate.a = a

	static func _ease(u: float) -> float:
		return 1.0 - pow(1.0 - u, 3.0)

	func current() -> Texture2D:
		if still or frames == null or _count == 0:
			return _icon if _icon else (frames.get_frame_texture("default", 0) if frames and _count > 0 else null)
		return frames.get_frame_texture("default", frame)

	func _draw() -> void:
		var tex := current()
		if tex == null or size.x <= 0.0:
			return
		var ts := tex.get_size()
		var sx := ts.x / size.x
		var sy := ts.y / size.y
		var m := material as ShaderMaterial
		if m:
			m.set_shader_parameter("px", Vector2(1.0 / size.x, 1.0 / size.y))   # UV 0..1 spans the art's rect
		# drawn over a region a little larger than the art: the glow and the shadow have room past its edges (the
		# frames' borders are transparent, so the clamped samples outside them are empty)
		draw_texture_rect_region(tex, Rect2(-PAD, -PAD, size.x + 2.0 * PAD, size.y + 2.0 * PAD),
			Rect2(-PAD * sx, -PAD * sy, ts.x + 2.0 * PAD * sx, ts.y + 2.0 * PAD * sy), Color.WHITE, false, false)
