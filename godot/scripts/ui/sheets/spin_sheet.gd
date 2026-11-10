class_name SpinSheet
extends Sheet
## Lucky Draw (index.html #spinSheet, buildWheel and the #spinGo handler) in the .pm sheet look (Sheet "pm" with the
## "Lucky Draw" RibbonTitle; the 48 px X is the only dismiss control): the 8-segment prize wheel in the player
## colours with a purple jackpot wedge ("1K" and a star), rim pegs, the coral pointer and the gold hub; one free
## spin per local day, more with a video (the server grants them: Rewards.extra_spins), the chances shown. Spin picks the prize first (Rewards.spin: saved at once, so closing mid-spin can't give a
## second spin), then the wheel turns and eases onto that segment (~4 s, cubic-bezier(.12,.75,.15,1); 1.4 s with
## Reduce motion) with a soft tick per segment, a light haptic every second tick and a pointer flick.
## On landing: the segment pulses, Haptics.success(), "You won 250 coins!" pops in, the coins fly to the home coin
## counter (or burst out of the wheel with a Toast when there is no counter on screen) and the button turns into
## a quiet "Next spin in 13h 20m" (live countdown).
##
##   var s := SpinSheet.new(); s.spun.connect(func(prize): ...); s.open(layer)

signal spun(prize: int)

const TURNS := 5
const SPIN_SEC := 4.2
const TURNS_REDUCED := 2
const SPIN_SEC_REDUCED := 1.4
## The jackpot segment index (Rewards.PRIZES 1000).
const JACKPOT := 5
## What the jackpot pays on top of its coins (server ECON_V1.jackpot_gems).
const JACKPOT_GEMS := 5

var profile: Dictionary
var rng := RandomNumberGenerator.new()
var _day_override := ""
var _width := float(UIKit.W.form)
var wheel: Wheel
var _note: Label
var _go: Button
var _again: Button
var flow: AdFlow
var _no_more := false                     # today's videos for a draw are used
var _spinning := false
var _result := {}
var _ticks := 0


## p: the profile to read and change (default: Save.profile). today: a fixed day key (previews), "" = the real day.
func _init(p: Dictionary = {}, today := "", width := float(UIKit.W.form)) -> void:
	super(L10n.t("Lucky Draw"), width, true, LOOK_GAME)
	profile = p if not p.is_empty() else Save.profile
	_day_override = today
	_width = width
	rng.randomize()
	wheel = Wheel.new()
	wheel.ticked.connect(_on_tick)
	body.add_child(UIKit.margin(wheel, 0, UIKit.SPACE.sm, 0, 0))
	_note = UIKit.label("", UIKit.FS.h2, Palette.G_TEXT, UIKit.font_display(), HORIZONTAL_ALIGNMENT_CENTER)
	_note.add_theme_constant_override("outline_size", 6)
	_note.add_theme_color_override("font_outline_color", Palette.G_OUTLINE)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size.y = 28   # reserved: the card doesn't jump when the result shows
	_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	body.add_child(_note)
	_go = UIKit.button(tr("Spin"), "honey", "lg")
	_go.name = "Spin"
	_go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_go.clip_text = true
	_go.pressed.connect(_spin)
	_go.resized.connect(_fit_go_text)
	body.add_child(_go)
	_again = UIKit.button(tr("Draw again with a video"), "teal", "md")
	_again.name = "Again"
	_again.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_again.visible = false
	UIKit.fit_text(_again, 13)
	_again.pressed.connect(_watch)
	body.add_child(_again)
	# fair and open: what you can win, and the chances
	var odds := UIKit.label(tr("Every wedge has the same chance. The jackpot: %s coins and %d gems.") % [Fmt.coins_full(Rewards.PRIZES.max()), JACKPOT_GEMS], UIKit.FS.small, Palette.G_SUB, UIKit.font_body(800), HORIZONTAL_ALIGNMENT_CENTER)
	odds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(odds)
	if AdFlow.available() and is_same(profile, Save.profile):
		flow = AdFlow.new()
		flow.name = "AdFlow"
		flow.done.connect(_on_watched)
		add_child(flow)
	_render()


func _ready() -> void:
	get_viewport().size_changed.connect(_fit)
	_fit()
	var t := Timer.new()
	t.wait_time = 1.0
	t.timeout.connect(func():
		if not _spinning:
			_render())
	add_child(t)
	t.start()

func _exit_tree() -> void:
	if _spinning:   # closed mid-spin: the prize is already saved; let the HUD show it now
		_spinning = false
		Rewards.commit(profile)

func _day() -> String:
	return _day_override if _day_override != "" else Rewards.day_key()

## Width (Sheet rule) and a wheel that fits the card and the screen height.
func _fit() -> void:
	if not is_inside_tree():
		return
	var vp := get_viewport_rect().size
	var cw := minf(_width, vp.x - 2.0 * UIKit.GUTTER)
	card.custom_minimum_size.x = cw
	var d := minf(290.0, cw - 2.0 * (UIKit.PAD.pane + 4) - 8.0)
	d = minf(d, vp.y - 340.0)   # short screens: a smaller wheel
	wheel.custom_minimum_size = Vector2(d, d)
	_fit_go_text()

## The button text at the largest size that fits (Spin 24; the countdown 20 down to 14).
func _fit_go_text() -> void:
	var room := _go.size.x
	if room <= 0.0:
		room = card.custom_minimum_size.x - 2.0 * (UIKit.PAD.pane + 4)
	room -= 2.0 * float(UIKit.BTN.lg.pad)
	var f := UIKit.font_display()
	var fs := int(UIKit.BTN.lg.fs) if not _go.disabled or _spinning else UIKit.FS.h2
	while fs > UIKit.FS.label and f.get_string_size(_go.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > room:
		fs -= 1
	if fs != _go.get_theme_font_size("font_size"):
		_go.add_theme_font_size_override("font_size", fs)


# ---------- state ----------

func _render() -> void:
	var ready_now := Rewards.can_spin(profile, _day())
	if ready_now or _spinning:
		if _go.get_meta("kit_kind", "") != "honey":
			UIKit.style_button(_go, "honey", "lg")
		_go.text = tr("Spin")
		_go.disabled = _spinning
	else:
		if _go.get_meta("kit_kind", "") != "off":
			UIKit.style_button(_go, "off", "lg")
			_go.add_theme_color_override("font_disabled_color", Palette.SUB)
		_go.text = tr("Next spin in %s") % Fmt.until(Rewards.sec_to_midnight())
		_go.disabled = true
	_again.visible = flow != null and not ready_now and not _spinning and not _no_more
	_fit_go_text()
	_note.visible = ready_now or _spinning or not _result.is_empty()   # no empty gap once today's spin is used
	if _spinning:
		return
	_note.text = (tr("You won %s coins!") % Fmt.coins_full(int(_result.prize))) if not _result.is_empty() else ""

func _spin() -> void:
	if _spinning or _closing:
		return
	if not Rewards.can_spin(profile, _day()):
		Haptics.error()
		Sound.sfx("error")
		_render()
		return
	var r: Dictionary
	if Account.wallet_active() and is_same(profile, Save.profile):
		_spinning = true                                   # the server draws the prize; the wheel waits for it
		_go.disabled = true
		r = await Account.instance().spin(false)
		if not is_instance_valid(self) or _closing:
			return
		if not r.get("ok", false):
			_spinning = false
			Haptics.error()
			Sound.sfx("error")
			Toast.show(self, Account.error_text(str(r.get("error", "")), "spin"), card, 2.4, "bad")
			_render()
			return
	else:
		r = Rewards.spin(profile, rng, _day(), false)
		if not r.ok:
			return
	_spinning = true
	_result = {}
	_ticks = 0
	_render()
	_note.text = ""
	var k: int = r.index
	var want := posmod(-(k * 45.0 + 22.5) - wheel.angle, 360.0)
	var dur := SPIN_SEC * clampf(float(Save.prefs.get("speed", 1.0)), 0.75, 1.0)   # Fast keeps some suspense
	var turns := TURNS
	if Sheet.reduce_motion():
		dur = SPIN_SEC_REDUCED
		turns = TURNS_REDUCED
	wheel.spin_to(wheel.angle + 360.0 * turns + want, dur, func(): _landed(r))

## A segment edge passed the pointer: a soft tick, a light haptic every second tick.
func _on_tick() -> void:
	_ticks += 1
	Sound.sfx("tick")
	if _ticks % 2 == 0:
		Haptics.light()

func _landed(r: Dictionary) -> void:
	_spinning = false
	_result = r
	if int(r.prize) > 0:
		DailySheet.hold_home_coins(self)   # the commit fires Save.changed: the home counter waits for the fly
	Rewards.commit(profile)
	_render()
	wheel.flash(int(r.index))
	Haptics.success()
	UIKit.pop_in(_note, 0.3)
	var prize := int(r.prize)
	if DailySheet.coin_target(self):
		DailySheet.reward_coins(self, wheel.segment_center(int(r.index)), prize, false, int(profile.get("coins", -1)))
	else:   # no counter on screen: the coins burst out of the hub
		DailySheet.reward_coins(self, wheel.get_global_rect().get_center(), prize)
		Toast.show(self, tr("%s coins") % Fmt.gain(prize), card, 1.8, "coin")
	if int(r.index) == JACKPOT or prize >= 1000:
		Celebrate.run(self, "burst", 0.6)
	if int(r.get("gems", 0)) > 0:
		Toast.show(self, tr("+%d gems") % int(r.gems), card, 2.2, "gem")
	spun.emit(prize)


## index.html's CSS timing curve cubic-bezier(x1, y1, x2, y2) at progress x (0-1).
func _watch() -> void:
	if flow == null or flow.busy:
		return
	_again.disabled = true
	flow.watch("spin")


func _on_watched(ok: bool, info: Dictionary) -> void:
	if not is_instance_valid(_again):
		return
	_again.disabled = false
	_result = {}
	if ok:
		Sound.sfx("buy")
	else:
		_no_more = str(info.get("error", "")) == "cap"
		Toast.show(self, str(info.get("text", tr(AdFlow.NO_FILL_TEXT))), card, 2.4, "bad")
	_render()


static func bezier_ease(x: float, x1: float, y1: float, x2: float, y2: float) -> float:
	if x <= 0.0:
		return 0.0
	if x >= 1.0:
		return 1.0
	var lo := 0.0
	var hi := 1.0
	var t := x
	for i in 30:   # x(t) only grows, so halving finds t
		t = (lo + hi) / 2.0
		if _bez(t, x1, x2) < x:
			lo = t
		else:
			hi = t
	return _bez(t, y1, y2)

static func _bez(t: float, p1: float, p2: float) -> float:
	var u := 1.0 - t
	return 3.0 * u * u * t * p1 + 3.0 * u * t * t * p2 + t * t * t


## The wheel (index.html #wheel SVG, viewBox -110..110): 8 segments in the player colours (the jackpot purple with
## a star) with white separators and upright prize labels, the gold rim with white pegs, the hub, a soft drop
## shadow; the coral pointer at the top.
class Wheel extends Control:
	signal ticked
	const JACKPOT_K := 5
	## Segment faces clockwise from the top: red, yellow, green, blue, red, jackpot, green, blue.
	const SEG := [Palette.PLAYER[0], Palette.PLAYER[2], Palette.PLAYER[1], Palette.PLAYER[3],
		Palette.PLAYER[0], Palette.INFO, Palette.PLAYER[1], Palette.PLAYER[3]]
	## Rotation in degrees, clockwise (like the CSS rotate()).
	var angle := 0.0
	var _from := 0.0
	var _to := 0.0
	var _t := 0.0
	var _dur := 0.0
	var _done: Callable
	var _seg := -1
	var _kick := 0.0
	var _flash_k := -1
	var _flash_t := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(280, 280)
		size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(false)

	func spin_to(target: float, dur: float, done: Callable) -> void:
		_from = angle
		_to = target
		_t = 0.0
		_dur = maxf(0.2, dur)
		_done = done
		_seg = _segment_at_pointer()
		_flash_k = -1
		set_process(true)

	func flash(k: int) -> void:
		_flash_k = k
		_flash_t = 0.0
		set_process(true)

	## The global centre of segment k's label at the current angle (where the prize coins start).
	func segment_center(k: int) -> Vector2:
		var d := minf(size.x, size.y)
		var a := deg_to_rad(k * 45.0 + 22.5 + angle)
		return get_global_transform() * (size / 2.0 + Vector2(sin(a), -cos(a)) * 62.0 * d / 220.0)

	## Which segment is under the pointer at the current angle.
	func _segment_at_pointer() -> int:
		return int(floor(posmod(-angle, 360.0) / 45.0)) % 8

	func _process(delta: float) -> void:
		_kick = maxf(0.0, _kick - delta * 7.0)
		if _flash_k >= 0:
			_flash_t += delta
		if _dur > 0.0:
			_t += delta
			var x := clampf(_t / _dur, 0.0, 1.0)
			angle = lerpf(_from, _to, SpinSheet.bezier_ease(x, 0.12, 0.75, 0.15, 1.0))
			var seg := _segment_at_pointer()
			if seg != _seg:
				_seg = seg
				_kick = 1.0
				ticked.emit()
			if x >= 1.0:
				_dur = 0.0
				angle = fposmod(_to, 360.0)
				if _done.is_valid():
					_done.call()
		elif _kick <= 0.0 and (_flash_k < 0 or _flash_t > 1.8):
			set_process(false)
		queue_redraw()

	func _seg_points(k: int, r: float) -> PackedVector2Array:
		var pts := PackedVector2Array([Vector2.ZERO])
		for j in 25:
			var a := deg_to_rad(k * 45.0 - 90.0 + j * 45.0 / 24.0)
			pts.append(Vector2(cos(a), sin(a)) * r)
		return pts

	## The 3D-rendered parts (tools/frames/ui_art.blend.py), each laid on the wheel's 220-unit square.
	static var _art := {}
	static func art(name: String) -> Texture2D:
		if not _art.has(name):
			var path := "res://assets/ui3d/%s.webp" % name
			_art[name] = load(path) if ResourceLoader.exists(path) else null
		return _art[name]

	## Which of the 16 rim bulbs are lit now: while spinning a fast chase (every fourth bulb), at rest every other one.
	func _bulb_lit(k: int) -> bool:
		if _dur > 0.0:
			return (k + int(_t * 14.0)) % 4 == 0
		if _flash_k >= 0:
			return (k + int(_flash_t * 6.0)) % 2 == 0
		return k % 2 == 0

	func _draw() -> void:
		var d := minf(size.x, size.y)
		var s := d / 220.0
		var c := size / 2.0
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		# soft drop shadow (filter: drop-shadow(0 8px 16px rgba(110,60,90,.28)))
		for i in 8:
			draw_circle(c + Vector2(0, 8 * s), (104.0 + i * 1.6) * s, Palette.shadow(0.045), true, -1.0, true)
		var rot := deg_to_rad(angle)
		var face := art("wheel_face")
		var full := Rect2(-Vector2(110, 110) * s, Vector2(220, 220) * s)
		draw_set_transform(c, rot)
		var r := 99.0 * s
		var pulse := 0.0
		if _flash_k >= 0:   # three soft pulses, then it stays lit a little
			pulse = 0.5 - 0.5 * cos(minf(_flash_t, 1.8) / 0.6 * TAU)
			pulse = maxf(pulse, clampf((_flash_t - 1.5) / 0.3, 0.0, 1.0) * 0.35)
		if face:
			draw_texture_rect(face, full, false)
		for k in 8:
			var pts := _seg_points(k, r)
			if not face:
				draw_colored_polygon(pts, SEG[k])
			if _flash_k >= 0 and k != _flash_k:     # the others step back
				draw_colored_polygon(pts, Color(Palette.INK, 0.3 * minf(1.0, _flash_t / 0.25)))
			if k == _flash_k:
				draw_colored_polygon(pts, Color(1, 1, 1, 0.38 * pulse))
		if _flash_k >= 0:   # the winning segment's gold outline
			var o := _seg_points(_flash_k, r - 2.0 * s)
			o.append(o[0])
			draw_polyline(o, Color(Palette.GOLD_HI, minf(1.0, _flash_t / 0.2)), 4.0 * s, true)
		draw_set_transform(Vector2.ZERO)
		_draw_labels(c, s, rot)
		# the fixed gold rim with its bulbs, lit by the game
		var rim := art("wheel_rim")
		if rim:
			draw_texture_rect(rim, Rect2(c + full.position, full.size), false)
		for k in 16:
			if _bulb_lit(k):
				var a := deg_to_rad(k * 22.5 - 90.0)
				var p := c + Vector2(cos(a), sin(a)) * 103.4 * s
				draw_circle(p, 7.0 * s, Color(1.0, 0.85, 0.45, 0.35), true, -1.0, true)
				draw_circle(p, 3.6 * s, Color(1.0, 0.97, 0.8, 0.95), true, -1.0, true)
		var hub := art("wheel_hub")
		if hub:
			var hw := 47.0 * s
			draw_texture_rect(hub, Rect2(c - Vector2(hw, hw) / 2.0, Vector2(hw, hw)), false)
		_draw_pointer(Vector2(size.x / 2.0, -8.0 * s), s)

	## Prize labels, tangential and always upright to the viewer (labels past the sides flip, never upside down).
	func _draw_labels(c: Vector2, s: float, rot: float) -> void:
		var f := UIKit.font_display()
		var fs := int(round(21.0 * s))
		for k in 8:
			var a := deg_to_rad(k * 45.0 + 22.5) + rot
			var up := fposmod(a, TAU)
			var tr := a + (PI if up > PI / 2.0 and up < PI * 1.5 else 0.0)
			var at := c + Vector2(sin(a), -cos(a)) * 64.0 * s
			draw_set_transform(at, tr)
			var txt := Fmt.coins(int(Rewards.PRIZES[k]))
			var base := (f.get_ascent(fs) - f.get_descent(fs)) / 2.0
			var y := base
			if k == JACKPOT_K:
				var out := -1.0 if tr == a else 1.0   # local "toward the rim"
				_draw_star(Vector2(0, out * fs * 0.66), 8.5 * s)
				y = base - out * fs * 0.18
			draw_string_outline(f, Vector2(-60, y), txt, HORIZONTAL_ALIGNMENT_CENTER, 120, fs, int(round(5.0 * s)), Color(Palette.INK, 0.35))
			draw_string(f, Vector2(-60, y), txt, HORIZONTAL_ALIGNMENT_CENTER, 120, fs, Color.WHITE)
		draw_set_transform(Vector2.ZERO)

	func _draw_star(c: Vector2, r: float) -> void:
		var pts := PackedVector2Array()
		for i in 10:
			var a := -PI / 2.0 + i * PI / 5.0
			pts.append(c + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.45))
		draw_colored_polygon(pts, Palette.GOLD_HI)
		pts.append(pts[0])
		draw_polyline(pts, Palette.GOLD_DEEP, 1.0, true)

	## The coral pointer (.pointer: 28 × 26 px with a white edge), flicked sideways when a segment edge passes it.
	func _draw_pointer(top: Vector2, s: float) -> void:
		var kick := -0.32 * sin(_kick * PI) * _kick
		var ptr := art("wheel_pointer")
		if ptr:                                    # the jewelled pointer, swinging on a pivot above its tip
			var pw := 40.0 * s
			var pivot := top + Vector2(0, 2.0 * s)
			draw_set_transform(pivot, kick)
			draw_texture_rect(ptr, Rect2(Vector2(-pw / 2.0, -pw * 0.3), Vector2(pw, pw)), false)
			draw_set_transform(Vector2.ZERO)
			return
		var k := clampf(s, 0.8, 1.3)
		var pts := PackedVector2Array([Vector2(-15, -2), Vector2(15, -2), Vector2(0, 26)])
		var x := Transform2D(kick, top)
		var sh := PackedVector2Array()
		var rim := PackedVector2Array()
		var tri := PackedVector2Array()
		for p in pts:
			sh.append(x * (p * k) + Vector2(0, 3))
			rim.append(x * (p * k * 1.0))
			tri.append(x * (p * k * 0.8 + Vector2(0, -0.4)))
		draw_colored_polygon(sh, Palette.shadow(0.35))
		draw_colored_polygon(rim, Color.WHITE)
		rim.append(rim[0])
		draw_polyline(rim, Color.WHITE, 2.0, true)
		draw_colored_polygon(tri, Palette.CORAL)
		tri.append(tri[0])
		draw_polyline(tri, Palette.CORAL, 1.0, true)
		draw_circle(x * Vector2(0, 2 * k), 3.2 * k, Palette.GLOSS, true, -1.0, true)
