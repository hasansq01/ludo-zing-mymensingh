class_name SpinSheet
extends Sheet
## Lucky Draw (index.html #spinSheet, buildWheel and the #spinGo handler) in the game look (Sheet LOOK_GAME: the dark
## café card, "LUCKY DRAW" in big outlined gold, the round red X is the only dismiss control): the 3D-rendered prize
## wheel (face, gold rim with chasing bulbs, hub, jewelled pointer) on a stage of warm light rays turning slowly
## behind it (still with Reduce motion); the chunky gold SPIN, and once today's spin is used the teal "Draw again
## with a video" (when videos are on) with the time to the next free spin as a dark chip; the chances under it.
## One free spin per local day, more with a video (the server grants them: Rewards.extra_spins). Spin picks the
## prize first (Rewards.spin: saved at once, so closing mid-spin can't give a second spin), then the wheel turns and
## eases onto that segment (~4 s, cubic-bezier(.12,.75,.15,1); 1.4 s with Reduce motion) with a soft tick per
## segment, a light haptic every second tick and a pointer flick.
## On landing (the purchase reveal's style): the segment pulses, the rays flare, Haptics.success(), "YOU WON!" on a
## dark chip and the amount in big outlined type pop in over the wheel, the coins fly to the home coin counter (or
## burst out of the wheel with a Toast when there is no counter on screen) and the time to the next spin shows.
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
const RAY_TURN_SEC := 90.0               ## one turn of the light rays
const RAYS := 0.45                       ## the rays' strength at rest (they flare on a win)
const POINTER_ROOM := 26.0               ## px above the wheel for its pointer (and the rays)
const STAGE_BOTTOM := 16.0               ## px under the wheel (the rays; the rim chip hangs into it)
const BTN_H := 76.0                      ## the action slot (SPIN / the video button / the countdown)

var profile: Dictionary
var rng := RandomNumberGenerator.new()
var _day_override := ""
var _width := float(UIKit.W.form)
var wheel: Wheel
var stage: Control                       ## the rays, the wheel, the prize and the rim chip
var rays: GamePanel
var _prize: VBoxContainer                ## YOU WON! + the amount, over the wheel
var _pool: GamePanel                     ## a soft dark pool behind the prize (the wheel's labels step back)
var _note: Label                         ## the amount ("+500")
var _gems_row: HBoxContainer
var _gems_l: Label
var _slot: Control
var _go: GameUI.GameButton
var _again: GameUI.GameButton
var _wait: PanelContainer                ## "Next spin in 13h 20m" in the slot (no video to offer)
var _wait_l: Label
var _rim_wait: PanelContainer            ## the same on the wheel's rim, above the video button
var _rim_wait_l: Label
var flow: AdFlow
var _no_more := false                     # today's videos for a draw are used
var _spinning := false
var _result := {}
var _ticks := 0


## p: the profile to read and change (default: Save.profile). today: a fixed day key (previews), "" = the real day.
func _init(p: Dictionary = {}, today := "", width := float(UIKit.W.form)) -> void:
	super(L10n.t("Lucky Draw").to_upper(), width, true, LOOK_GAME)
	profile = p if not p.is_empty() else Save.profile
	_day_override = today
	_width = width
	rng.randomize()
	header.custom_minimum_size.y = 48.0
	if title_label:
		title_label.add_theme_font_size_override("font_size", 34)
		title_label.add_theme_constant_override("outline_size", 10)
	body.add_theme_constant_override("separation", UIKit.SPACE.md)
	# the stage: light rays, the wheel, the prize over it, the countdown chip on its rim
	stage = Control.new()
	stage.name = "Stage"
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.resized.connect(_layout_stage)
	body.add_child(stage)
	rays = GamePanel.radial(Color(Palette.GL_TITLE, 1.0), Color(Palette.GL_BTN_GOLD_LO, 0.7), Color(Palette.GL_BTN_GOLD_LO, 0.0))
	rays.name = "Rays"
	rays.mid = 0.72
	rays.radius = 0.0
	rays.rays = RAYS
	rays.ray_count = 18.0
	rays.ray_width = 0.42
	rays.ray_center = Vector2(0.5, 0.5)
	rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(rays)
	wheel = Wheel.new()
	wheel.ticked.connect(_on_tick)
	stage.add_child(wheel)
	_pool = GamePanel.radial(Color(Palette.GL_INK, 0.95), Color(Palette.GL_INK, 0.88), Color(Palette.GL_INK, 0.0))
	_pool.name = "PrizePool"
	_pool.center = Vector2(0.5, 0.5)
	_pool.reach = Vector2(0.5, 0.5)
	_pool.mid = 0.62
	_pool.radius = 0.0
	_pool.visible = false
	stage.add_child(_pool)
	_prize = VBoxContainer.new()
	_prize.name = "Prize"
	_prize.alignment = BoxContainer.ALIGNMENT_CENTER
	_prize.add_theme_constant_override("separation", -2)
	_prize.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prize.visible = false
	var won := PanelContainer.new()
	won.mouse_filter = Control.MOUSE_FILTER_IGNORE
	won.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var ws := UIKit.box(Palette.GL_INK, 12, 2, Palette.GL_CHIP_RIM)
	ws.content_margin_left = 14; ws.content_margin_right = 14 - 3
	ws.content_margin_top = 2; ws.content_margin_bottom = 3
	won.add_theme_stylebox_override("panel", ws)
	won.add_child(UIKit.label(L10n.t("You won!").to_upper(), 15, GameUI.GOLD, OfferSheet.spaced_display(3)))   # l10n
	_prize.add_child(won)
	var amount := UIKit.hbox(6)
	amount.alignment = BoxContainer.ALIGNMENT_CENTER
	amount.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var coin := UIKit.icon("coin", 46)
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	amount.add_child(coin)
	_note = GameUI.outlined("", 60, GameUI.TEXT, 5)
	_note.name = "Amount"
	_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	amount.add_child(_note)
	_prize.add_child(amount)
	_gems_row = UIKit.hbox(6)
	_gems_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_gems_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gem := UIKit.icon("gem", 30)
	gem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_gems_row.add_child(gem)
	_gems_l = GameUI.outlined("", 34, GameUI.TEXT, 4)
	_gems_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_gems_row.add_child(_gems_l)
	_gems_row.visible = false
	_prize.add_child(_gems_row)
	stage.add_child(_prize)
	var rw := _wait_chip(17)
	_rim_wait = rw[0]
	_rim_wait_l = rw[1]
	_rim_wait.name = "RimWait"
	_rim_wait.visible = false
	stage.add_child(_rim_wait)
	# the action slot: one fixed height for SPIN, the video button and the countdown (the card never jumps)
	_slot = Control.new()
	_slot.name = "Actions"
	_slot.custom_minimum_size.y = BTN_H
	_slot.resized.connect(_layout_slot)
	body.add_child(_slot)
	_go = GameUI.button(tr("Spin"), "gold", "lg")
	_go.name = "Spin"
	_go.label.add_theme_font_size_override("font_size", 38)
	_go.label.add_theme_constant_override("outline_size", 0)
	_go.pressed.connect(_spin)
	_slot.add_child(_go)
	_again = GameUI.button(tr("Draw again with a video"), "teal", "lg")
	_again.name = "Again"
	_again.visible = false
	_again.label.get_parent().add_child(PlayGlyph.new())
	_again.label.get_parent().move_child(_again.label.get_parent().get_child(-1), 0)
	_again.pressed.connect(_watch)
	_slot.add_child(_again)
	var w := _wait_chip(21)
	_wait = w[0]
	_wait_l = w[1]
	_wait.name = "Wait"
	_wait.visible = false
	_slot.add_child(_wait)
	# fair and open: what you can win, and the chances
	var odds := GameUI.text(tr("Every wedge has the same chance. The jackpot: %s coins and %d gems.") % [Fmt.coins_full(Rewards.PRIZES.max()), JACKPOT_GEMS], 15, GameUI.SUB, HORIZONTAL_ALIGNMENT_CENTER)
	odds.name = "Odds"
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
	if not Sheet.reduce_motion():               # the rays turn slowly; the bulbs chase at rest
		var tw := rays.create_tween().set_loops()
		tw.tween_property(rays, "ray_angle", TAU / rays.ray_count, RAY_TURN_SEC / rays.ray_count).from(0.0)
		wheel.idle_chase = true

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
	var inner := cw - 40.0                                   # GameUI.card_style() side margins
	var d := minf(280.0, inner - 40.0)                       # room each side for the light rays
	d = minf(d, vp.y - 440.0)   # short screens: a smaller wheel
	d = maxf(d, 160.0)
	stage.custom_minimum_size = Vector2(inner, d + POINTER_ROOM + STAGE_BOTTOM)
	wheel.custom_minimum_size = Vector2(d, d)
	_layout_stage()
	_fit_texts()

## The stage's parts: the wheel centred under its pointer room, the rays a square of the card's width around it, the
## prize over the wheel's lower half, the chip on the rim's bottom.
func _layout_stage() -> void:
	var w := stage.size.x
	var d := wheel.custom_minimum_size.x
	wheel.size = Vector2(d, d)
	wheel.position = Vector2(roundf((w - d) / 2.0), POINTER_ROOM)
	var c := wheel.position + Vector2(d, d) / 2.0
	# the rays: the card's inner width, from the stage's top (never over the title) as far below the wheel's centre
	var rw := card.custom_minimum_size.x - 6.0
	rays.size = Vector2(rw, 2.0 * c.y)
	rays.position = Vector2((w - rw) / 2.0, 0.0)
	rays.center = Vector2(0.5, 0.5)
	rays.reach = Vector2(0.5, 0.5)
	rays.ray_center = Vector2(0.5, 0.5)
	rays.ray_reach = maxf(rw, 2.0 * c.y) / 2.0
	rays.pivot_offset = rays.size / 2.0
	var pm := _prize.get_combined_minimum_size()
	_prize.size = Vector2(d, pm.y)
	_prize.position = Vector2(wheel.position.x, c.y + d * 0.24 - pm.y / 2.0)
	_prize.pivot_offset = _prize.size / 2.0
	_pool.size = Vector2(d * 1.05, pm.y + 70.0)
	_pool.position = _prize.position + (_prize.size - _pool.size) / 2.0
	var rm := _rim_wait.get_combined_minimum_size()
	_rim_wait.size = rm
	_rim_wait.position = Vector2(roundf((w - rm.x) / 2.0), c.y + d * 0.5 - rm.y / 2.0 - 2.0)

func _layout_slot() -> void:
	var s := _slot.size
	for b: Control in [_go, _again]:
		b.position = Vector2.ZERO
		b.size = s
	var wm := _wait.get_combined_minimum_size()
	_wait.size = Vector2(minf(s.x, maxf(wm.x, s.x * 0.8)), wm.y)
	_wait.position = Vector2(roundf((s.x - _wait.size.x) / 2.0), roundf((s.y - 6.0 - wm.y) / 2.0))
	_fit_texts()

## The video button's text and the countdowns at the largest size that fits.
func _fit_texts() -> void:
	var room := _slot.size.x
	if room <= 0.0:
		room = card.custom_minimum_size.x - 40.0
	var f := UIKit.font_display()
	var fs := 24
	while fs > 15 and f.get_string_size(_again.label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > room - 20.0 - 40.0 - 8.0:
		fs -= 1
	if fs != _again.label.get_theme_font_size("font_size"):
		_again.label.add_theme_font_size_override("font_size", fs)
	for pair: Array in [[_wait_l, 21, room - 40.0], [_rim_wait_l, 17, room - 60.0]]:
		var l: Label = pair[0]
		var n: int = pair[1]
		while n > 13 and f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, n).x + 30.0 > pair[2]:
			n -= 1
		if n != l.get_theme_font_size("font_size"):
			l.add_theme_font_size_override("font_size", n)

## A dark chip with a gold rim, a small clock and the time to the next free spin: [chip, label].
func _wait_chip(fs: int) -> Array:
	var c := PanelContainer.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := UIKit.box(Palette.GL_CHIP_BG, 40, 2, Palette.GL_CHIP_RIM)
	st.content_margin_left = 12; st.content_margin_right = 16
	st.content_margin_top = 6 if fs > 18 else 3; st.content_margin_bottom = 7 if fs > 18 else 4
	st.shadow_color = Color(0, 0, 0, 0.35)
	st.shadow_size = 6
	st.shadow_offset = Vector2(0, 3)
	c.add_theme_stylebox_override("panel", st)
	var h := UIKit.hbox(8)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var clock := ClockGlyph.new()
	clock.custom_minimum_size = Vector2(fs + 2, fs + 2)
	clock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(clock)
	var l := UIKit.label("", fs, GameUI.SUB, UIKit.font_display())
	l.name = "Text"
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(l)
	c.add_child(h)
	return [c, l]


# ---------- state ----------

func _render() -> void:
	var ready_now := Rewards.can_spin(profile, _day())
	var video := flow != null and not ready_now and not _spinning and not _no_more
	_go.visible = ready_now or _spinning
	_go.disabled = _spinning
	_go.text = tr("Spin")
	_dim_face(_go, _spinning)                  # the face greys while the wheel turns
	_again.visible = video
	var wait_txt := tr("Next spin in %s") % Fmt.until(Rewards.sec_to_midnight())
	_wait.visible = not _go.visible and not video
	_rim_wait.visible = video
	_wait_l.text = wait_txt
	_rim_wait_l.text = wait_txt
	_fit_texts()
	if is_inside_tree():
		_layout_slot.call_deferred()
		_layout_stage.call_deferred()
	if _spinning:
		_prize.visible = false
		_pool.visible = false
		return
	_prize.visible = not _result.is_empty()
	_pool.visible = _prize.visible
	_note.text = Fmt.gain(int(_result.prize)) if not _result.is_empty() else ""
	var gems := int(_result.get("gems", 0))
	_gems_row.visible = gems > 0
	_gems_l.text = "+%d" % gems

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
	_reveal()
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

## A GameButton greyed (or back): its face greys through GameButton's own disabled modulate (GamePanel honours
## modulate since 200d40f); only the label is softened here.
static func _dim_face(b: GameUI.GameButton, dim: bool) -> void:
	b.label.modulate = Color(1, 1, 1, 0.7) if dim else Color.WHITE

## The win (the purchase reveal's moment): the rays flare and settle a little brighter, the prize pops in.
func _reveal() -> void:
	_layout_stage()
	if Sheet.reduce_motion():
		rays.rays = RAYS * 1.6
		UIKit.pop_in(_prize, 0.2)
		return

	var tw := rays.create_tween()
	tw.tween_property(rays, "rays", RAYS * 3.0, 0.16).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(rays, "scale", Vector2(1.08, 1.08), 0.16).set_ease(Tween.EASE_OUT)
	tw.tween_property(rays, "rays", RAYS * 1.6, 0.9).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(rays, "scale", Vector2.ONE, 0.9).set_trans(Tween.TRANS_SINE)
	_prize.scale = Vector2(0.6, 0.6)
	_prize.modulate.a = 0.0
	var pt := _prize.create_tween()
	pt.tween_property(_prize, "scale", Vector2.ONE, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pt.parallel().tween_property(_prize, "modulate:a", 1.0, 0.14)


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
	rays.rays = RAYS
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
	## At rest the bulbs chase slowly (off with Reduce motion: SpinSheet sets it).
	var idle_chase := false:
		set(v):
			idle_chase = v
			if v:
				set_process(true)
	var _idle_t := 0.0
	var _idle_step := 0

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
		elif idle_chase and _kick <= 0.0 and (_flash_k < 0 or _flash_t > 1.8):
			_idle_t += delta                           # at rest: redraw only when the bulbs step
			var step := int(_idle_t * 2.5)
			if step != _idle_step:
				_idle_step = step
				queue_redraw()
			return
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

	## Which of the 16 rim bulbs are lit now: while spinning a fast chase (every fourth bulb), on a win a quick
	## blink, at rest every other one (stepping round slowly when idle_chase).
	func _bulb_lit(k: int) -> bool:
		if _dur > 0.0:
			return (k + int(_t * 14.0)) % 4 == 0
		if _flash_k >= 0 and _flash_t <= 1.8:
			return (k + int(_flash_t * 6.0)) % 2 == 0
		return (k + _idle_step) % 2 == 0

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
			draw_string_outline(f, Vector2(-60, y), txt, HORIZONTAL_ALIGNMENT_CENTER, 120, fs, int(round(6.0 * s)), Color(Palette.GL_INK, 0.8))
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


## The video button's mark: a white disc with a teal play triangle.
class PlayGlyph extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(32, 32)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0
		draw_circle(c + Vector2(0, 2), r, Color(Palette.GL_TEAL_LIP2, 0.6), true, -1.0, true)
		draw_circle(c, r, Color.WHITE, true, -1.0, true)
		var t := r * 0.46
		draw_colored_polygon(PackedVector2Array([c + Vector2(-t * 0.7, -t), c + Vector2(t, 0), c + Vector2(-t * 0.7, t)]), Palette.GL_TEAL_LIP)


## The countdown chip's clock: a gold ring, two hands.
class ClockGlyph extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0 - 1.0
		var w := maxf(2.0, r * 0.22)
		draw_circle(c, r, Palette.GL_TITLE, true, -1.0, true)
		draw_circle(c, r - w, Palette.GL_CHIP_BG, true, -1.0, true)
		draw_line(c, c + Vector2(0, -(r - w) * 0.72), Palette.GL_TITLE, w * 0.8, true)
		draw_line(c, c + Vector2((r - w) * 0.55, 0), Palette.GL_TITLE, w * 0.8, true)
		draw_circle(c, w * 0.6, Palette.GL_TITLE, true, -1.0, true)
