extends "res://tests/test_suite.gd"
## Notifications wrapper (res://scripts/net/notifier.gd): the stub everywhere the Android plugin is missing
## (desktop / headless: "unsupported", schedule calls recorded in stub_scheduled, push answers "unavailable",
## always later than the call), the mapping onto the plugin (through a fake singleton with the Kotlin plugin's
## methods and signals: a tap is delivered once, push data normalised), the push settings (empty = push off) and
## the export plugin (manifest snippet, Maven dependency).

const N := preload("res://scripts/net/notifier.gd")
const Export := preload("res://addons/notifications/export_plugin.gd")

## Stands in for the Kotlin NotificationsPlugin singleton: same method and signal names, answers synchronously.
class FakePlugin extends RefCounted:
	signal permission_result(granted: bool)
	signal opened(data: Dictionary)
	signal push_token(token: String)
	signal push_failed(code: String)
	signal push_received(data: Dictionary)

	var permission := "ask"
	var items: Dictionary = {}
	var launch: Dictionary = {}
	var calls: Array = []

	func permission_state() -> String:
		return permission
	func open_settings() -> void:
		calls.append("open_settings")
	func request_permission() -> void:
		calls.append("request_permission")
		permission = "granted"
		permission_result.emit(true)
	func schedule(id: String, at_unix: int, channel: String, title: String, body: String, link: String) -> void:
		calls.append("schedule:%s:%d:%s" % [id, at_unix, channel])
		items[id] = [at_unix, channel, title, body, link]
	func cancel(id: String) -> void:
		items.erase(id)
	func cancel_all() -> void:
		items.clear()
	func scheduled() -> PackedStringArray:
		return PackedStringArray(items.keys())
	func take_launch_data() -> Dictionary:
		var d := launch
		launch = {}
		return d
	func get_status() -> Dictionary:
		return {sdk_int = 35, permission = permission, scheduled = items.size(), push_ready = false, push_saved = false}
	func push_init(project_id: String, app_id: String, api_key: String, sender_id: String) -> void:
		calls.append("push_init:%s:%s:%s:%s" % [project_id, app_id, api_key, sender_id])
		if api_key == "bad":
			push_failed.emit("error:FIS_AUTH_ERROR")
		else:
			push_token.emit("tok-" + project_id)
	func push_subscribe(topic: String) -> void:
		calls.append("push_subscribe:" + topic)
	func push_unsubscribe(topic: String) -> void:
		calls.append("push_unsubscribe:" + topic)
	func push_delete_token() -> void:
		calls.append("push_delete_token")
	## a tap while the game runs: the Kotlin side keeps it for take_launch_data() and signals it
	func tap(data: Dictionary) -> void:
		launch = data
		opened.emit(data)

var _log: Array = []

func run() -> void:
	_stub()
	_stub_is_deferred()
	_stub_launch_and_permission()
	_plugin_local()
	_plugin_opened_once()
	_plugin_push()
	_settings()
	_export()

## Records every wrapper signal into _log as [name, args...].
func watch(n: N) -> void:
	_log = []
	n.permission_result.connect(func(g): _log.append(["permission_result", g]))
	n.opened.connect(func(d): _log.append(["opened", d]))
	n.push_token.connect(func(t): _log.append(["push_token", t]))
	n.push_failed.connect(func(c): _log.append(["push_failed", c]))
	n.push_received.connect(func(d): _log.append(["push_received", d]))

func _stub() -> void:
	check("stub: no NotificationsPlugin singleton on desktop / headless", not Engine.has_singleton(N.SINGLETON))
	check("singleton name never shadows the class_name Notifier", N.SINGLETON != "Notifier")
	var n := N.new(null, false)
	watch(n)
	check("stub: not available", not n.is_available())
	check("stub: permission unsupported", n.permission_state() == "unsupported", n.permission_state())
	check("stub: status says unavailable", n.status() == {available = false}, n.status())
	n.schedule("daily", 1_800_000_000, "rewards", "Daily reward", "Your daily reward is ready", "daily")
	n.schedule("back1", 1_800_100_000, "nope", "Ludo Zing", "Come back", "home")
	check("stub: schedule recorded in stub_scheduled (unknown channel -> reminders)", n.stub_scheduled == {
		daily = {id = "daily", at = 1_800_000_000, channel = "rewards", title = "Daily reward",
			body = "Your daily reward is ready", link = "daily"},
		back1 = {id = "back1", at = 1_800_100_000, channel = "reminders", title = "Ludo Zing", body = "Come back",
			link = "home"}}, n.stub_scheduled)
	n.schedule("daily", 1_800_000_500, "rewards", "Daily reward", "Later", "daily")
	check("stub: the same id replaces", n.stub_scheduled.size() == 2 and n.stub_scheduled.daily.at == 1_800_000_500,
		n.stub_scheduled)
	check("stub: scheduled() lists the ids", n.scheduled() == ["back1", "daily"], n.scheduled())
	n.cancel("back1")
	check("stub: cancel", n.scheduled() == ["daily"], n.scheduled())
	n.cancel_all()
	check("stub: cancel_all", n.scheduled().is_empty() and n.stub_scheduled.is_empty(), n.stub_scheduled)
	check("stub: no launch data", n.take_launch_data() == {})
	n.open_settings()
	check("stub: open_settings is counted (nothing to open)", n.stub_settings_opened == 1 and _log.is_empty(), _log)
	n.request_permission()
	check("stub: request_permission -> permission_result(false)", _log == [["permission_result", false]], _log)
	_log.clear()
	n.push_init_from_settings(); n.push_init("p", "a", "k", "s"); n.push_subscribe("promos")
	n.push_unsubscribe("promos"); n.push_delete_token()
	check("stub: every push call -> push_failed(unavailable)", _log == [["push_failed", "unavailable"],
		["push_failed", "unavailable"], ["push_failed", "unavailable"], ["push_failed", "unavailable"],
		["push_failed", "unavailable"]], _log)
	n.free()

func _stub_is_deferred() -> void:
	var n := N.new()
	watch(n)
	n.request_permission()
	n.push_init_from_settings()
	n.push_subscribe("promos")
	check("stub (default): answers are deferred, never inside the call", _log.is_empty(), _log)
	n.free()

func _stub_launch_and_permission() -> void:
	var n := N.new(null, false)
	watch(n)
	n.stub_launch = {link = "spin", source = "local"}
	check("stub: stub_launch comes back once, with every key", n.take_launch_data() == {link = "spin", cid = "",
		source = "local"} and n.take_launch_data() == {}, n.stub_launch)
	n.stub_permission = "ask"
	n.stub_grant = true
	n.request_permission()
	check("stub: ask + grant -> permission_result(true), state granted",
		_log == [["permission_result", true]] and n.permission_state() == "granted", [_log, n.permission_state()])
	n.stub_permission = "ask"
	n.stub_grant = false
	_log.clear(); n.request_permission()
	check("stub: ask + refuse -> permission_result(false), state denied",
		_log == [["permission_result", false]] and n.permission_state() == "denied", [_log, n.permission_state()])
	n.free()

func _plugin_local() -> void:
	var fake := FakePlugin.new()
	var n := N.new(fake, false)
	watch(n)
	check("plugin: available", n.is_available())
	check("plugin: status passes through", n.status().sdk_int == 35 and n.status().available == true, n.status())
	check("plugin: permission state passes through", n.permission_state() == "ask", n.permission_state())
	n.request_permission()
	check("plugin: request_permission -> permission_result(true)",
		_log == [["permission_result", true]] and fake.calls == ["request_permission"], [_log, fake.calls])
	check("plugin: then granted", n.permission_state() == "granted")
	n.open_settings()
	check("plugin: open_settings passes through", fake.calls.back() == "open_settings", fake.calls)
	n.schedule("free", 9_000_000_000, "rewards", "Free coins", "Free coins are ready", "free")
	check("plugin: schedule passes everything (64-bit time)", fake.calls.back() == "schedule:free:9000000000:rewards"
		and fake.items.free == [9_000_000_000, "rewards", "Free coins", "Free coins are ready", "free"], fake.items)
	check("plugin: nothing in stub_scheduled", n.stub_scheduled.is_empty())
	n.schedule("back3", 1_800_000_000, "reminders", "Ludo Zing", "Your pawns miss you", "home")
	var ids := n.scheduled()
	ids.sort()
	check("plugin: scheduled() is an Array of ids", typeof(n.scheduled()) == TYPE_ARRAY and ids == ["back3", "free"],
		ids)
	n.cancel("free")
	check("plugin: cancel", n.scheduled() == ["back3"], n.scheduled())
	n.cancel_all()
	check("plugin: cancel_all", n.scheduled().is_empty())
	n.free()

func _plugin_opened_once() -> void:
	var fake := FakePlugin.new()
	var n := N.new(fake, false)
	watch(n)
	fake.launch = {link = "daily", cid = "", source = "local"}
	check("plugin: cold start tap from take_launch_data, once", n.take_launch_data() == {link = "daily", cid = "",
		source = "local"} and n.take_launch_data() == {})
	fake.tap({link = "room:ABCD", cid = "c42", source = "push"})
	check("plugin: tap while running -> opened", _log == [["opened", {link = "room:ABCD", cid = "c42",
		source = "push"}]], _log)
	check("plugin: ...and not again from take_launch_data", n.take_launch_data() == {})
	# the game asked take_launch_data() (e.g. on resume) before the opened handler ran: delivered there, not twice
	_log.clear()
	fake.launch = {link = "shop"}
	var got := n.take_launch_data()
	fake.opened.emit({link = "shop"})
	check("plugin: a tap already taken is not signalled again",
		got == {link = "shop", cid = "", source = "local"} and _log.is_empty(), [got, _log])
	n.free()

func _plugin_push() -> void:
	var fake := FakePlugin.new()
	var n := N.new(fake, false)
	watch(n)
	n.push_init("ludo-zing", "1:123:android:abc", "AIzaKey", "123")
	check("plugin: push_init -> push_token", _log == [["push_token", "tok-ludo-zing"]]
		and fake.calls.back() == "push_init:ludo-zing:1:123:android:abc:AIzaKey:123", [_log, fake.calls])
	_log.clear(); n.push_init("ludo-zing", "1:123:android:abc", "bad", "123")
	check("plugin: push_init failure -> push_failed(code)", _log == [["push_failed", "error:FIS_AUTH_ERROR"]], _log)
	n.push_subscribe("promos"); n.push_unsubscribe("promos"); n.push_delete_token()
	check("plugin: topic and token calls pass through", fake.calls.slice(-3) == ["push_subscribe:promos",
		"push_unsubscribe:promos", "push_delete_token"], fake.calls)
	_log.clear()
	fake.push_received.emit({title = "Your turn", body = "Rina is waiting for you in room ABCD", link = "room:ABCD",
		kind = "turn"})
	check("plugin: push_received normalised (every key a string)", _log == [["push_received", {title = "Your turn",
		body = "Rina is waiting for you in room ABCD", link = "room:ABCD", cid = "", kind = "turn"}]], _log)
	fake.push_token.emit("tok-refreshed")
	check("plugin: token refresh -> push_token", _log.back() == ["push_token", "tok-refreshed"], _log)
	if not N.push_configured():
		var before := fake.calls.size()
		_log.clear(); n.push_init_from_settings()
		check("plugin: push settings empty -> push_failed(not_configured), plugin never asked",
			_log == [["push_failed", "not_configured"]] and fake.calls.size() == before, [_log, fake.calls])
	n.free()

func _settings() -> void:
	var s := N.push_settings()
	check("settings: the four ludo_zing/push/* keys", s.size() == 4
		and ["project_id", "app_id", "api_key", "sender_id"].all(func(k): return s.has(k)), s)
	check("settings: same keys as the export plugin registers", N.PUSH_SETTINGS.values() == Export.PUSH_SETTINGS,
		N.PUSH_SETTINGS)
	check("settings: the Ludo Zing Firebase project is configured (push on)", N.push_configured()
		and s.project_id == "ludo-zing-a1b7c" and str(s.app_id).begins_with("1:%s:android:" % s.sender_id), s)
	check("channels: the contract's four", N.CHANNELS == ["rewards", "reminders", "game", "offers"], N.CHANNELS)

func _export() -> void:
	var m := Export.manifest_contents()
	check("export: FirebaseInitProvider removed (no google-services.json)",
		m.contains("com.google.firebase.provider.FirebaseInitProvider") and m.contains("tools:node=\"remove\""), m)
	check("export: firebase-messaging dependency pinned",
		Export.FIREBASE_MESSAGING_DEPENDENCY.begins_with("com.google.firebase:firebase-messaging:")
		and Export.FIREBASE_MESSAGING_DEPENDENCY.get_slice(":", 2).split(".").size() == 3,
		Export.FIREBASE_MESSAGING_DEPENDENCY)
	check("export: built AARs present", FileAccess.file_exists("res://addons/notifications/bin/debug/Notifications-debug.aar")
		and FileAccess.file_exists("res://addons/notifications/bin/release/Notifications-release.aar"))
