class_name AppRating
extends Node
## Asking for a Play Store rating: Google Play In-App Review (NotificationsPlugin.review_request(), Review.kt) and the
## Settings row "Rate Ludo Zing". main.gd owns one (`app_rating`).
##
## When the card is asked for: back on Home right after a win (main: note_win() at the result, back_home() in
## go_home), once Home has been quiet for QUIET_SEC (no sheet, the daily reward or the notifications question first),
## and only when due(): MIN_WINS wins and MIN_DAYS days since the first launch, then at most once every GAP_DAYS and
## MAX_ASKS times in all, never again after the player opened the store page from Settings. No question of our own
## comes first (Play's policy: nothing like "Do you like the game?" before the card). Play decides whether its card
## really shows (its own quota) and never says whether the player rated, so an ask counts once it is sent.
##
## The record lives in Save.prefs.rate = {first, wins, asks, last, rated} (unix seconds).
##
##   app_rating.note_win()            # the human won a match
##   app_rating.back_home()           # Home again: asks when due (a coroutine; nobody waits for it)
##   AppRating.open_store()           # Settings: the Play Store page (and no more asking)
## Tests: `plugin` (a fake with review_request), clock, quiet_fn, wait_sec, open_url_fn.

const SINGLETON := "NotificationsPlugin"
const MIN_WINS := 3
const MIN_DAYS := 2
const GAP_DAYS := 30
const MAX_ASKS := 3
const QUIET_SEC := 1.5
const WAIT_SEC := 60.0                   ## gives up when Home is not quiet for QUIET_SEC within this long
const DAY := 86400

static var plugin: Object = null         ## tests: the plugin (null = Engine.get_singleton(SINGLETON) on Android)
static var open_url_fn := Callable()     ## tests: (url) -> Error instead of OS.shell_open
static var last_url := ""                ## tests: what open_store() opened

var clock := Callable()                  ## () -> unix seconds (tests; the system clock by default)
var quiet_fn := Callable()               ## () -> "quiet" | "busy" | "gone": Home with nothing over it / something over it / not Home
var wait_sec := WAIT_SEC
var quiet_sec := QUIET_SEC
var asked := false                       ## tests: review_request went out in this run
var _won := false                        # the last match was a win (cleared by back_home)
var _waiting := false


func _ready() -> void:
	record()                                 # the first launch's time goes in at once

func now() -> int:
	return int(clock.call()) if clock.is_valid() else int(Time.get_unix_time_from_system())

## Save.prefs.rate, made whole (a missing or broken record starts now).
func record() -> Dictionary:
	var r: Variant = Save.prefs.get("rate")
	var d: Dictionary = r if r is Dictionary else {}
	var changed := not r is Dictionary
	for k in ["first", "wins", "asks", "last"]:
		if not (d.get(k) is int or d.get(k) is float):
			d[k] = now() if k == "first" else 0
			changed = true
		else:
			d[k] = int(d[k])
	if not d.get("rated") is bool:
		d.rated = false
		changed = true
	Save.prefs.rate = d
	if changed:
		Save.save()
	return d

## Whether a rating card may be asked for now (the pure rule).
static func due(r: Dictionary, now_: int) -> bool:
	if bool(r.get("rated", false)) or int(r.get("asks", 0)) >= MAX_ASKS or int(r.get("wins", 0)) < MIN_WINS:
		return false
	if now_ - int(r.get("first", now_)) < MIN_DAYS * DAY:
		return false
	return int(r.get("last", 0)) <= 0 or now_ - int(r.get("last", 0)) >= GAP_DAYS * DAY

## The human won a match (any game or mode but the tutorial).
func note_win() -> void:
	var r := record()
	r.wins = int(r.wins) + 1
	Save.save()
	_won = true

## Home again after a match: right after a win, and when due, waits for a quiet Home, then asks Play.
func back_home() -> void:
	if not _won:
		return
	_won = false
	if _waiting or not due(record(), now()) or native() == null:
		return
	_waiting = true
	var ok := await _wait_quiet()
	_waiting = false
	if ok:
		ask()

# Home with nothing over it for quiet_sec in a row (true), or false once Home is left / wait_sec passed.
func _wait_quiet() -> bool:
	var start := Time.get_ticks_msec()
	var since := -1
	while is_inside_tree() and Time.get_ticks_msec() - start < int(wait_sec * 1000.0):
		var q := str(quiet_fn.call()) if quiet_fn.is_valid() else "quiet"
		if q == "gone":
			return false
		if q != "quiet":
			since = -1
		elif since < 0:
			since = Time.get_ticks_msec()
		elif Time.get_ticks_msec() - since >= int(quiet_sec * 1000.0):
			return true
		await get_tree().process_frame
	return false

## Sends the review request (counted as an ask). False without the plugin.
func ask() -> bool:
	var p := native()
	if p == null:
		return false
	var r := record()
	r.asks = int(r.asks) + 1
	r.last = now()
	Save.save()
	asked = true
	if p.has_signal("review_done") and not p.is_connected("review_done", _on_done):
		p.connect("review_done", _on_done)
	p.call("review_request")
	return true

func _on_done(ok: bool, error: String) -> void:
	if not ok:
		print("AppRating: Play's review flow did not run (%s)" % error)

## The plugin when it can ask Play for a review, else null.
static func native() -> Object:
	var p := plugin
	if p == null and Engine.has_singleton(SINGLETON):
		p = Engine.get_singleton(SINGLETON)
	if p == null:
		return null
	# a JNISingleton (the real plugin) answers has_java_method; a fake has the method itself
	var can := p.has_method("review_request") or (p.has_method("has_java_method") and bool(p.call("has_java_method", "review_request")))
	return p if can else null

## Settings "Rate Ludo Zing": the game's Play Store page (the web page when the Play app can't open it). The player
## went to rate, so the card is never asked for again.
static func open_store() -> void:
	var r: Variant = Save.prefs.get("rate")
	var d: Dictionary = r if r is Dictionary else {}
	d.rated = true
	Save.prefs.rate = d
	Save.save()
	last_url = AppUpdate.STORE_URL
	if open_url_fn.is_valid():
		open_url_fn.call(last_url)
		return
	if OS.shell_open(last_url) != OK:
		last_url = AppUpdate.WEB_URL
		OS.shell_open(last_url)
