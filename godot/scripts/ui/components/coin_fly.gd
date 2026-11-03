class_name CoinFly
extends Control
## Coins fly to a counter (juice spec: 6–10 coins, staggered, eased arcs, a clink + light haptic per arrival).
## A full-rect overlay over `host` that frees itself when the last coin lands.
##
##   CoinFly.run(ui_root, button.get_global_rect().get_center(), home.coin_chip, 200)
##   CoinFly.run(host, from, counter, 200, func(): print("done"), new_total)
##
## On the first arrival the target counts up: a CoinAmount (duck-typed: set_amount(n, animate) / flash()) gets
## set_amount(target_total, true) (target_total < 0: its current amount + amount, read from `amount` or
## get_amount()), then flash() on the last coin. Any other Control just gets a little bump.
## Respects Save.prefs.reduce_motion (3 coins, no arc wobble).

const COIN_PX := 30.0
const FLIGHT := 0.62
const STAGGER := 0.045
const BURST := 0.16

var _target: Control
var _amount := 0
var _total := -1
var _done: Callable
var _left := 0
var _first := true

## Starts the flight; returns the overlay (already running).
static func run(host: Control, from_global: Vector2, to: Control, amount: int, on_done := Callable(), target_total := -1) -> CoinFly:
	var f := CoinFly.new()
	f._target = to
	f._amount = amount
	f._total = target_total
	f._done = on_done
	f.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	f.z_index = 50
	host.add_child(f)
	f._launch(from_global)
	return f

## Where coins land on a target: a CoinAmount's coin icon (coin_center()), else the centre of the Control.
static func target_point(t: Control, fallback: Vector2) -> Vector2:
	if not is_instance_valid(t):
		return fallback
	if t.has_method("coin_center"):
		return t.call("coin_center")
	return t.get_global_rect().get_center()

## How many coins fly for an amount (6 for small gains, up to 10).
static func count_for(amount: int) -> int:
	return clampi(6 + int(amount / 150.0), 6, 10)

func _launch(from_global: Vector2) -> void:
	var inv := get_global_transform().affine_inverse()
	var from := inv * from_global
	var to := inv * target_point(_target, from_global)
	var reduce := PlayerTile._pref("reduce_motion")
	var n := 3 if reduce else count_for(_amount)
	_left = n
	var tex := UIKit.svg("coin")
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in n:
		var c := TextureRect.new()
		c.texture = tex
		c.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		c.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		c.size = Vector2(COIN_PX, COIN_PX)
		c.pivot_offset = c.size / 2.0
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.position = from - c.size / 2.0
		c.scale = Vector2(0.3, 0.3)
		c.modulate.a = 0.0
		add_child(c)
		var ang := TAU * i / n + rng.randf_range(-0.4, 0.4)
		var spread := Vector2(cos(ang), sin(ang)) * rng.randf_range(26.0, 46.0) * (0.4 if reduce else 1.0)
		var p0 := from + spread
		var side := 1.0 if (i % 2 == 0) else -1.0
		var mid := (p0 + to) / 2.0
		var normal := (to - p0).orthogonal().normalized()
		var ctrl := mid + normal * side * rng.randf_range(40.0, 90.0) * (0.0 if reduce else 1.0) + Vector2(0, -40)
		var delay := i * STAGGER
		var tw := create_tween()
		tw.tween_interval(delay)
		tw.tween_property(c, "modulate:a", 1.0, 0.08)
		tw.parallel().tween_property(c, "scale", Vector2(1.1, 1.1), BURST).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(c, "position", p0 - c.size / 2.0, BURST).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_interval(0.05 + (n - i) * 0.012)
		var fly := func(t: float) -> void:
			var a := p0.lerp(ctrl, t)
			var b := ctrl.lerp(to, t)
			c.position = a.lerp(b, t) - c.size / 2.0
			var k := lerpf(1.1, 0.7, t)
			c.scale = Vector2(k, k)
			c.rotation = sin(t * PI) * 0.5 * side
		tw.tween_method(fly, 0.0, 1.0, FLIGHT).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tw.tween_callback(_arrive.bind(c))

func _arrive(c: Control) -> void:
	c.queue_free()
	_left -= 1
	UIKit.sfx("coin", _amount if _first else 0)
	Haptics.light()
	if is_instance_valid(_target):
		if _first:
			_first = false
			if _target.has_method("set_amount"):
				var total := _total
				if total < 0:
					var cur: Variant = _target.call("get_amount") if _target.has_method("get_amount") else _target.get("amount")
					total = (int(cur) if cur != null else 0) + _amount
				_target.call("set_amount", total, true)
		_bump(_target)
	if _left <= 0:
		if is_instance_valid(_target) and _target.has_method("flash"):
			_target.call("flash")
		if _done.is_valid():
			_done.call()
		queue_free()

## A small squash on the counter per coin (skipped while the target animates its own scale).
static func _bump(t: Control) -> void:
	if t.has_meta("coinfly_tw"):
		var old: Variant = t.get_meta("coinfly_tw")
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()
	t.pivot_offset = t.size / 2.0
	var tw := t.create_tween()
	tw.tween_property(t, "scale", Vector2(1.08, 1.08), 0.05)
	tw.tween_property(t, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.set_meta("coinfly_tw", tw)
