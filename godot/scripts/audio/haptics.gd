class_name Haptics
extends RefCounted
## Short vibrations for touch feedback (static, no autoload): Haptics.tap() on every UIKit button press,
## light() for small game events (a pawn step lands, a toggle), medium() for a capture or a ladder, heavy() for a
## snake / losing a pawn, success() for a win or a reward, error() for a refused action.
##
## Uses Input.vibrate_handheld(ms, amplitude) (amplitude 0..1 works on Android 8+; older phones ignore it).
## Does nothing on desktop / web / headless, and when the player turned Vibration off (Save.prefs.vibrate, default
## true; read only when the Save autoload exists). Rapid repeats are throttled (MIN_GAP_MS) so a burst of
## events can't turn into a buzz. The Android export needs permissions/vibrate=true (set in export_presets.cfg).

## [duration ms, amplitude 0..1] per effect.
const TAP := [10, 0.30]
const LIGHT := [16, 0.40]
const MEDIUM := [28, 0.65]
const HEAVY := [45, 1.0]
const MIN_GAP_MS := 35

## The last effect asked for ("tap", "success" ...), recorded even where the device can't vibrate. For tests.
static var last := ""
static var _last_ms := -100000

static func tap() -> void:
	_buzz("tap", TAP)

static func light() -> void:
	_buzz("light", LIGHT)

static func medium() -> void:
	_buzz("medium", MEDIUM)

static func heavy() -> void:
	_buzz("heavy", HEAVY)

## Two rising pulses.
static func success() -> void:
	if _buzz("success", LIGHT):
		_later(0.11, MEDIUM)

## Three quick firm pulses.
static func error() -> void:
	if _buzz("error", [22, 0.7]):
		_later(0.09, [22, 0.7])
		_later(0.18, [22, 0.7])

## True when this device vibrates and the player has not turned Vibration off.
static func enabled() -> bool:
	if not (OS.has_feature("android") or OS.has_feature("ios")):
		return false
	return pref_on()

## The Vibration preference (true when there is no Save autoload, e.g. in tools).
static func pref_on() -> bool:
	var save := _node("Save")
	if save == null:
		return true
	var prefs: Variant = save.get("prefs")
	return not (prefs is Dictionary) or bool((prefs as Dictionary).get("vibrate", true))


static func _buzz(name: String, fx: Array) -> bool:
	last = name
	if not enabled():
		return false
	var now := Time.get_ticks_msec()
	if now - _last_ms < MIN_GAP_MS:
		return false
	_last_ms = now
	Input.vibrate_handheld(int(fx[0]), float(fx[1]))
	return true

static func _later(sec: float, fx: Array) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	tree.create_timer(sec, true).timeout.connect(func():
		if enabled():
			Input.vibrate_handheld(int(fx[0]), float(fx[1])))

static func _node(n: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(n) if tree and tree.root else null
