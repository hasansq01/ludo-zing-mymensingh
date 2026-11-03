extends "res://tests/test_suite.gd"
## Asking for a rating (res://scripts/net/app_rating.gd): the due() rule (wins, days since the first launch, the gap
## between asks, the most asks, never after the store page), the record in Save.prefs.rate, back_home() asking only
## right after a win and only once Home is quiet (gone from Home = no ask), the plugin found through has_java_method,
## and Settings' "Rate Ludo Zing" opening the store page. Nothing here writes the save or opens a store page.

## Stands in for NotificationsPlugin: review_request() answers review_done(true, "").
class FakePlugin extends RefCounted:
	signal review_done(ok: bool, error: String)
	var calls := 0
	func review_request() -> void:
		calls += 1
		review_done.emit(true, "")

## Answers like a JNISingleton: has_method false for the plugin's methods, has_java_method true.
class FakeJni extends RefCounted:
	func has_java_method(m: String) -> bool:
		return m == "review_request"

const T0 := 1_800_000_000
const D := AppRating.DAY

var _sp: Dictionary
var _spf: Dictionary
var _clock := T0


func run() -> void:
	_sandbox()
	_rule()
	_record()
	await _flow()
	_store()
	AppRating.plugin = null
	AppRating.open_url_fn = Callable()
	_restore()


func _sandbox() -> void:
	_sp = Save.profile
	_spf = Save.prefs
	Save.prefs = {}
	Save.normalize()
	if Save._timer.timeout.is_connected(Save.flush):
		Save._timer.timeout.disconnect(Save.flush)

func _restore() -> void:
	Save._dirty = false
	Save.profile = _sp
	Save.prefs = _spf
	if not Save._timer.timeout.is_connected(Save.flush):
		Save._timer.timeout.connect(Save.flush)

func make(quiet := "quiet") -> AppRating:
	var r := AppRating.new()
	r.clock = func() -> int: return _clock
	r.quiet_fn = func() -> String: return quiet
	r.quiet_sec = 0.05
	r.wait_sec = 0.5
	(Engine.get_main_loop() as SceneTree).root.add_child(r)
	return r

func frames(n: int) -> void:
	for k in n:
		await (Engine.get_main_loop() as SceneTree).process_frame

func wait(sec: float) -> void:
	await (Engine.get_main_loop() as SceneTree).create_timer(sec).timeout


func _rule() -> void:
	var ready := {first = T0 - 3 * D, wins = 3, asks = 0, last = 0, rated = false}
	check("due: 3 wins, 3 days in, never asked", AppRating.due(ready, T0))
	check("due: not before 3 wins", not AppRating.due(ready.merged({wins = 2}, true), T0))
	check("due: not in the first 2 days", not AppRating.due(ready.merged({first = T0 - D}, true), T0))
	check("due: not within 30 days of the last ask", not AppRating.due(ready.merged({asks = 1, last = T0 - 29 * D}, true), T0))
	check("due: again 30 days after the last ask", AppRating.due(ready.merged({asks = 1, last = T0 - 30 * D}, true), T0))
	check("due: never after 3 asks", not AppRating.due(ready.merged({asks = 3, last = T0 - 90 * D}, true), T0))
	check("due: never after the store page from Settings", not AppRating.due(ready.merged({rated = true}, true), T0))

func _record() -> void:
	Save.prefs.erase("rate")
	_clock = T0
	var r := make()
	check("record: the first launch's time goes in at once", Save.prefs.rate is Dictionary and int(Save.prefs.rate.first) == T0
		and int(Save.prefs.rate.wins) == 0 and Save.prefs.rate.rated == false, Save.prefs.get("rate"))
	Save.prefs.rate = {first = "x", wins = 2}
	var d := r.record()
	check("record: a broken record is mended, its good values kept", int(d.first) == T0 and int(d.wins) == 2 and int(d.asks) == 0, d)
	r.note_win()
	check("note_win: counts the win", int(Save.prefs.rate.wins) == 3)
	r.free()

func _flow() -> void:
	var pg := FakePlugin.new()
	AppRating.plugin = pg
	# not due yet (the first launch was just now): a win, then Home, asks nothing
	Save.prefs.rate = {first = T0, wins = 5, asks = 0, last = 0, rated = false}
	_clock = T0
	var r := make()
	r.note_win()
	await r.back_home()
	check("back_home: not due -> no ask", pg.calls == 0 and not r.asked)
	r.free()
	# due: a win, then a quiet Home -> Play's card is asked for, and counted
	_clock = T0 + 5 * D
	r = make()
	r.note_win()
	await r.back_home()
	check("back_home after a win, due, Home quiet: review_request once, counted", pg.calls == 1 and r.asked
		and int(Save.prefs.rate.asks) == 1 and int(Save.prefs.rate.last) == _clock, [pg.calls, Save.prefs.rate])
	r.free()
	# a loss: nothing
	_clock = T0 + 40 * D
	r = make()
	await r.back_home()
	check("back_home without a win: no ask", pg.calls == 1)
	r.free()
	# Home is left (a game started) before it was quiet: no ask
	r = make("gone")
	r.note_win()
	await r.back_home()
	check("back_home: Home left before it was quiet -> no ask", pg.calls == 1 and not r.asked)
	r.free()
	# a sheet stays over Home: gives up after wait_sec
	r = make("busy")
	r.note_win()
	await r.back_home()
	check("back_home: Home never quiet -> gives up, no ask", pg.calls == 1 and not r.asked)
	r.free()
	# within 30 days of the last ask: no ask
	Save.prefs.rate = {first = T0, wins = 9, asks = 1, last = T0 + 30 * D, rated = false}
	_clock = T0 + 45 * D
	r = make()
	r.note_win()
	await r.back_home()
	check("back_home: within 30 days of the last ask -> no ask", pg.calls == 1)
	r.free()
	# no plugin (off Android, an old build): nothing, and nothing counted
	AppRating.plugin = null
	_clock = T0 + 90 * D
	r = make()
	r.note_win()
	await r.back_home()
	check("no plugin: nothing asked, nothing counted", not r.asked and int(Save.prefs.rate.asks) == 1)
	r.free()
	AppRating.plugin = FakeJni.new()
	check("the real plugin (a JNISingleton) is found through has_java_method", AppRating.native() != null)
	AppRating.plugin = pg

func _store() -> void:
	var urls: Array = []
	AppRating.open_url_fn = func(u: String) -> int:
		urls.append(u)
		return OK
	Save.prefs.rate = {first = T0, wins = 9, asks = 0, last = 0, rated = false}
	var s := SettingsSheet.new()
	var row := s.find_child("RateGame", true, false)
	check("settings: Help has Rate Ludo Zing", row != null)
	AppRating.open_store()
	check("Rate Ludo Zing: opens the Play Store page", urls == [AppUpdate.STORE_URL], urls)
	check("Rate Ludo Zing: the card is never asked for again", Save.prefs.rate.rated == true and not AppRating.due(Save.prefs.rate, T0 + 90 * D))
	s.free()
