extends "res://tests/test_suite.gd"
## Rewarded ads wrapper (res://scripts/net/ads.gd): the stub everywhere the AdMob plugin is missing (desktop /
## headless: nothing available or ready, answers deferred), the mapping onto the plugin through a fake singleton
## with the Kotlin plugin's methods and signals, the automatic reload with backoff (5 s, 15 s, 60 s), the project
## settings and the export plugin (manifest snippet, dependencies).

const A := preload("res://scripts/net/ads.gd")
const Export := preload("res://addons/admob/export_plugin.gd")

## Stands in for the Kotlin AdMobPlugin singleton: same method and signal names, answers synchronously.
class FakePlugin extends RefCounted:
	signal consent_done(can_request_ads: bool, privacy_options_required: bool)
	signal rewarded_loaded
	signal rewarded_failed(code: int, message: String)
	signal rewarded_earned(type: String, amount: int)
	signal rewarded_closed
	signal rewarded_show_failed(code: int, message: String)

	var ready := false
	var calls: Array = []
	## what the next load_rewarded() does: "ok" | "fail" | "hold" (no answer yet)
	var load_result := "ok"
	var privacy := true

	func initialize() -> void:
		calls.append("initialize")
	func request_consent(test_device: String) -> void:
		calls.append("request_consent:" + test_device)
		consent_done.emit(true, privacy)
	func show_privacy_options() -> void:
		calls.append("show_privacy_options")
	func load_rewarded(unit_id: String) -> void:
		calls.append("load_rewarded:" + unit_id)
		match load_result:
			"ok":
				ready = true
				rewarded_loaded.emit()
			"fail":
				rewarded_failed.emit(3, "No fill")
	func is_rewarded_ready() -> bool:
		return ready
	func show_rewarded(user_id: String, custom_data: String) -> void:
		calls.append("show_rewarded:%s:%s" % [user_id, custom_data])
		if not ready:
			rewarded_show_failed.emit(-1, "not loaded")
			return
		ready = false
		rewarded_earned.emit("coins", 10)
		rewarded_closed.emit()

var _log: Array = []

func run() -> void:
	_stub()
	_stub_is_deferred()
	_plugin_mapping()
	_plugin_show_failed()
	_reload_backoff()
	_no_reload_unasked()
	_settings_and_export()

func watch(a: A) -> void:
	_log = []
	a.consent_done.connect(func(c, p): _log.append(["consent_done", c, p]))
	a.loaded.connect(func(): _log.append(["loaded"]))
	a.failed.connect(func(c, m): _log.append(["failed", c, m]))
	a.earned.connect(func(t, n): _log.append(["earned", t, n]))
	a.closed.connect(func(): _log.append(["closed"]))
	a.show_failed.connect(func(c, m): _log.append(["show_failed", c, m]))

func _stub() -> void:
	check("stub: no AdMob singleton on desktop / headless", not Engine.has_singleton(A.SINGLETON))
	check("singleton name never shadows the class_name Ads", A.SINGLETON != "Ads")
	var a := A.new(null, false)
	watch(a)
	check("stub: not available, not ready, no privacy options", not a.available() and not a.is_ready()
		and not a.privacy_options_required())
	a.initialize()
	a.show_privacy_options()
	check("stub: initialize / show_privacy_options do nothing", _log.is_empty(), _log)
	a.request_consent()
	check("stub: request_consent -> consent_done(false, false)", _log == [["consent_done", false, false]], _log)
	_log.clear()
	a.load_rewarded()
	check("stub: load_rewarded -> failed(-1, unavailable), no reload queued",
		_log == [["failed", -1, "unavailable"]] and a.reload_in < 0.0, [_log, a.reload_in])
	_log.clear()
	a.show_rewarded("acc", "nonce")
	check("stub: show_rewarded -> show_failed(-1, unavailable), never earned",
		_log == [["show_failed", -1, "unavailable"]], _log)
	a.free()

func _stub_is_deferred() -> void:
	var a := A.new()
	watch(a)
	a.request_consent()
	a.load_rewarded()
	a.show_rewarded("a", "n")
	check("stub (default): answers are deferred, never inside the call", _log.is_empty(), _log)
	a.free()

func _plugin_mapping() -> void:
	var fake := FakePlugin.new()
	var a := A.new(fake, false)
	watch(a)
	check("plugin: available, not ready yet", a.available() and not a.is_ready())
	a.initialize()
	a.request_consent()
	check("plugin: request_consent passes through; consent_done relayed, privacy flag kept",
		fake.calls == ["initialize", "request_consent:"] and _log == [["consent_done", true, true]]
		and a.privacy_options_required(), [fake.calls, _log])
	a.show_privacy_options()
	check("plugin: show_privacy_options passes through", fake.calls.back() == "show_privacy_options", fake.calls)
	_log.clear()
	a.load_rewarded()
	check("plugin: load_rewarded uses the project's unit id -> loaded, ready",
		fake.calls.back() == "load_rewarded:" + A.unit_id() and A.unit_id() == Export.DEFAULTS[A.UNIT_SETTING]
		and _log == [["loaded"]] and a.is_ready(), [fake.calls, _log])
	_log.clear()
	a.show_rewarded("acc-1", "nonce-9")
	check("plugin: show_rewarded passes user id + custom data; earned then closed",
		fake.calls.back() == "show_rewarded:acc-1:nonce-9"
		and _log == [["earned", "coins", 10], ["closed"]] and not a.is_ready(), [fake.calls, _log])
	check("plugin: a closed ad queues the next load after the first delay (5 s)", a.reload_in == 5.0, a.reload_in)
	a.free()

func _plugin_show_failed() -> void:
	var fake := FakePlugin.new()
	var a := A.new(fake, false)
	watch(a)
	a.show_rewarded("a", "n")
	check("plugin: show_failed relayed (nothing loaded), no earned",
		_log == [["show_failed", -1, "not loaded"]], _log)
	a.free()

func _reload_backoff() -> void:
	check("backoff: 5, 15, 60, then 60 again", A.backoff(1) == 5.0 and A.backoff(2) == 15.0 and A.backoff(3) == 60.0
		and A.backoff(4) == 60.0 and A.backoff(9) == 60.0)
	var fake := FakePlugin.new()
	var a := A.new(fake, false)
	watch(a)
	fake.load_result = "fail"
	a.load_rewarded()
	check("reload: first failure -> failed relayed, next load in 5 s", _log == [["failed", 3, "No fill"]]
		and a.reload_in == 5.0 and a.failures == 1, [_log, a.reload_in])
	a._on_reload_timer()
	check("reload: the timer loads again; the second failure waits 15 s",
		fake.calls.count("load_rewarded:" + A.unit_id()) == 2 and a.reload_in == 15.0, [fake.calls, a.reload_in])
	a._on_reload_timer()
	check("reload: third failure waits 60 s", a.reload_in == 60.0, a.reload_in)
	a._on_reload_timer()
	check("reload: and stays at 60 s", a.reload_in == 60.0 and a.failures == 4, [a.reload_in, a.failures])
	fake.load_result = "ok"
	a._on_reload_timer()
	check("reload: a good load resets the sequence and queues nothing", a.is_ready() and a.failures == 0
		and a.reload_in < 0.0, [a.failures, a.reload_in])
	# a failure after a good load starts at 5 s again
	a.show_rewarded("a", "n")
	check("reload: after a close, 5 s", a.reload_in == 5.0, a.reload_in)
	# one pending reload at a time: a second failure while one waits doesn't stack
	fake.load_result = "fail"
	a._on_reload_timer()
	check("reload: failed reload after a close -> 5 s again (failures = 1)", a.reload_in == 5.0 and a.failures == 1,
		[a.reload_in, a.failures])
	# the timer finds an ad already loaded (the player called load_rewarded themselves): no extra load
	fake.load_result = "ok"
	a.load_rewarded()
	var n := fake.calls.size()
	a._on_reload_timer()
	check("reload: nothing is loaded twice", fake.calls.size() == n and a.is_ready(), fake.calls)
	# a failed show also reloads
	fake.ready = false
	a.show_rewarded("a", "n")
	check("reload: a failed show queues a reload (backoff step 1)", a.reload_in == 5.0 and a.failures == 1,
		[a.reload_in, a.failures])
	a.free()

func _no_reload_unasked() -> void:
	var fake := FakePlugin.new()
	var a := A.new(fake, false)
	fake.rewarded_closed.emit()
	fake.rewarded_failed.emit(0, "x")
	check("reload: nothing is queued before load_rewarded() was called", a.reload_in < 0.0, a.reload_in)
	a.free()

func _settings_and_export() -> void:
	check("settings: project ids are Google's test ids",
		str(ProjectSettings.get_setting(A.UNIT_SETTING, "")).begins_with("ca-app-pub-")
		and str(ProjectSettings.get_setting(Export.APP_ID_SETTING, "")).contains("~"),
		[ProjectSettings.get_setting(A.UNIT_SETTING, ""), ProjectSettings.get_setting(Export.APP_ID_SETTING, "")])
	var m := Export.manifest_contents("ca-app-pub-3940256099942544~3347511713")
	check("export: manifest meta-data carries the app id", m.contains(
		"android:name=\"com.google.android.gms.ads.APPLICATION_ID\"") and m.contains(
		"android:value=\"ca-app-pub-3940256099942544~3347511713\""), m)
	check("export: dependencies are the Ads + UMP SDKs", Export.ADS_DEPENDENCY.begins_with(
		"com.google.android.gms:play-services-ads:") and Export.UMP_DEPENDENCY.begins_with(
		"com.google.android.ump:user-messaging-platform:"))
	check("export: AARs exist", FileAccess.file_exists("res://addons/admob/bin/debug/AdMob-debug.aar")
		and FileAccess.file_exists("res://addons/admob/bin/release/AdMob-release.aar"))
