class_name Notifier
extends Node
## Local and push notifications (server/NOTIFICATIONS.md "N-PLUG"): a thin wrapper over the "NotificationsPlugin"
## Android plugin singleton (godot/android/plugins/notifications). Everywhere the plugin is missing (desktop,
## headless, web, the non-Gradle "Android Emulator" preset) it is a safe stub: is_available() is false,
## permission_state() is "unsupported", schedule / cancel only update `stub_scheduled` (for tests) and every push call
## answers push_failed("unavailable"). Signal answers always arrive later (deferred), never inside the call that asked.
##
##   var n := Notifier.new(); add_child(n)
##   n.opened.connect(route)                     # a notification tapped while the game runs: {link, cid, source}
##   route(n.take_launch_data())                 # ...or the one that started the game ({} = none); each tap comes once,
##                                               # either here or as opened, never both
##   if n.permission_state() == "ask": n.request_permission()     # -> permission_result(granted)
##   n.cancel_all(); n.schedule("daily", at_unix, "rewards", "Daily reward", "Your daily reward is ready", "daily")
##   if n.push_configured(): n.push_init_from_settings()          # -> push_token(token) or push_failed(code)
##   n.push_subscribe("promos"); n.push_received.connect(toast)   # a push while the game is on screen
##
## Channels: "rewards", "reminders", "game", "offers" (an unknown one becomes "reminders"). Links: see the contract
## ("home", "daily", "spin", "free", "shop[:kind:id]", "room:CODE", "leaderboard"); unknown = home.
## permission_state(): "granted" | "denied" (show the "turn them on in your phone settings" hint) | "ask" (the system
## dialog can be shown: never asked, or refused once on Android 13+, which allows a second ask) | "unsupported".
## push_failed codes: "unavailable" (stub), "not_configured" (a ludo_zing/push/* setting is empty),
## "no_play_services:<n>", "not_initialized" (a push call before push_init), "error:<m>" (no token: FCM's message,
## e.g. "SERVICE_NOT_AVAILABLE"), "subscribe:<m>", "unsubscribe:<m>", "delete:<m>".

## Answer to request_permission(): true when notifications can now be shown.
signal permission_result(granted: bool)
## A notification was tapped while the game was running: {link, cid, source ("local" | "push")}.
signal opened(data: Dictionary)
## The FCM token after push_init(), and again whenever FCM refreshes it (send it to POST /v1/push/token).
signal push_token(token: String)
signal push_failed(code: String)
## A push arrived while the game is in the foreground (the phone showed nothing): {title, body, link, cid, kind}.
signal push_received(data: Dictionary)

const SINGLETON := "NotificationsPlugin"
const CHANNELS := ["rewards", "reminders", "game", "offers"]
## The Firebase project's values (Project Settings > Ludo Zing > Push); all four set = push on.
const PUSH_SETTINGS := {project_id = "ludo_zing/push/project_id", app_id = "ludo_zing/push/app_id",
	api_key = "ludo_zing/push/api_key", sender_id = "ludo_zing/push/sender_id"}
const UNAVAILABLE := "unavailable"

## Stub only (no plugin): what schedule() / cancel() did, id -> {id, at, channel, title, body, link}.
var stub_scheduled: Dictionary = {}
## Stub only: what take_launch_data() returns once (tests of the routing), and the permission it reports. With
## "ask", request_permission() answers `stub_grant` and moves the state to "granted" / "denied".
var stub_launch: Dictionary = {}
var stub_permission := "unsupported"
var stub_grant := false

var _pg: Object = null
var _deferred := true

## `singleton`: the Android plugin object; null = Engine.get_singleton("NotificationsPlugin") when it exists. Tests
## pass a fake with the same methods and signals, and `deferred` false to get the answers inside the call.
func _init(singleton: Object = null, deferred := true) -> void:
	_deferred = deferred
	if singleton == null and Engine.has_singleton(SINGLETON):
		singleton = Engine.get_singleton(SINGLETON)
	_pg = singleton
	if _pg == null:
		return
	_connect("permission_result", _on_permission)
	_connect("opened", _on_opened)
	_connect("push_token", _on_push_token)
	_connect("push_failed", _on_push_failed)
	_connect("push_received", _on_push_received)

## True on Android with the plugin built in (local notifications work; push also needs push_init).
func is_available() -> bool:
	return _pg != null

## The plugin's status {sdk_int, permission, scheduled, push_ready, push_saved} (Android) plus `available`.
func status() -> Dictionary:
	var st: Dictionary = {}
	if _pg != null:
		st = _pg.call("get_status")
	st.available = _pg != null
	return st

## "granted" | "denied" | "ask" | "unsupported" (see the top of the file).
func permission_state() -> String:
	if _pg == null:
		return stub_permission
	return str(_pg.call("permission_state"))

## Android 13+: the system dialog (call it after a soft prompt, never at launch). -> permission_result(granted).
func request_permission() -> void:
	if _pg == null:
		if stub_permission == "ask":
			stub_permission = "granted" if stub_grant else "denied"
		_later(permission_result.emit.bind(stub_permission == "granted"))
		return
	_pg.call("request_permission")

## A local notification at `at_unix` (seconds), replacing one with the same id. Android may show it some minutes
## late (inexact alarm); it survives a reboot (dropped if its time passed meanwhile).
func schedule(id: String, at_unix: int, channel: String, title: String, body: String, link: String) -> void:
	if _pg == null:
		stub_scheduled[id] = {id = id, at = at_unix, channel = channel if channel in CHANNELS else "reminders",
			title = title, body = body, link = link}
		return
	_pg.call("schedule", id, at_unix, channel, title, body, link)

## Cancels a local notification (also takes it out of the shade if it was shown).
func cancel(id: String) -> void:
	if _pg == null:
		stub_scheduled.erase(id)
		return
	_pg.call("cancel", id)

## Every local notification; push notifications are not touched.
func cancel_all() -> void:
	if _pg == null:
		stub_scheduled.clear()
		return
	_pg.call("cancel_all")

## Ids of the local notifications still to come.
func scheduled() -> Array:
	if _pg == null:
		var ids := stub_scheduled.keys()
		ids.sort()
		return ids
	return Array(_pg.call("scheduled"))

## {link, cid, source} of the notification that opened the game (cold start or brought back), once; then {}.
func take_launch_data() -> Dictionary:
	if _pg == null:
		var d := stub_launch
		stub_launch = {}
		return _launch(d) if not d.is_empty() else {}
	var data: Dictionary = _pg.call("take_launch_data")
	return _launch(data) if not data.is_empty() else {}

## {project_id, app_id, api_key, sender_id} from the project settings ("" when unset).
static func push_settings() -> Dictionary:
	var s := {}
	for k in PUSH_SETTINGS:
		s[k] = str(ProjectSettings.get_setting(PUSH_SETTINGS[k], "")).strip_edges()
	return s

## True when all four ludo_zing/push/* settings are set (push is off until the Firebase project exists).
static func push_configured() -> bool:
	return push_settings().values().all(func(v): return not str(v).is_empty())

## push_init() with the project settings. -> push_token(token) or push_failed("unavailable" | "not_configured" | ...).
func push_init_from_settings() -> void:
	if _pg == null:
		_later(push_failed.emit.bind(UNAVAILABLE))
		return
	if not push_configured():
		_later(push_failed.emit.bind("not_configured"))
		return
	var s := push_settings()
	push_init(s.project_id, s.app_id, s.api_key, s.sender_id)

## Initialises Firebase and fetches the FCM token. -> push_token(token) or push_failed(code).
func push_init(project_id: String, app_id: String, api_key: String, sender_id: String) -> void:
	if _pg == null:
		_later(push_failed.emit.bind(UNAVAILABLE))
		return
	_pg.call("push_init", project_id, app_id, api_key, sender_id)

## Topic subscription (the admin's "everyone" campaigns go to "promos"). Only failures answer: push_failed.
func push_subscribe(topic: String) -> void:
	if _pg == null:
		_later(push_failed.emit.bind(UNAVAILABLE))
		return
	_pg.call("push_subscribe", topic)

func push_unsubscribe(topic: String) -> void:
	if _pg == null:
		_later(push_failed.emit.bind(UNAVAILABLE))
		return
	_pg.call("push_unsubscribe", topic)

## Sign-out / account switch: this phone's token stops working (push_init again for a new one).
func push_delete_token() -> void:
	if _pg == null:
		_later(push_failed.emit.bind(UNAVAILABLE))
		return
	_pg.call("push_delete_token")


# ---------- plugin signals ----------

func _on_permission(granted: bool) -> void:
	permission_result.emit(granted)

func _on_opened(data: Dictionary) -> void:
	# the plugin also keeps the tap for take_launch_data(): take it here, so it is delivered once. Already taken
	# (the game asked take_launch_data() on resume before this deferred call ran) = already delivered.
	var pending: Dictionary = _pg.call("take_launch_data")
	if pending.is_empty():
		return
	opened.emit(_launch(data))

func _on_push_token(token: String) -> void:
	push_token.emit(token)

func _on_push_failed(code: String) -> void:
	push_failed.emit(code)

func _on_push_received(data: Dictionary) -> void:
	var d := {}
	for k in ["title", "body", "link", "cid", "kind"]:
		d[k] = str(data.get(k, ""))
	push_received.emit(d)


# ---------- helpers ----------

func _launch(data: Dictionary) -> Dictionary:
	return {link = str(data.get("link", "")), cid = str(data.get("cid", "")), source = str(data.get("source", "local"))}

func _connect(sig: String, fn: Callable) -> void:
	if _pg.has_signal(sig):
		# plugin signals arrive on the main loop already; deferred keeps every answer out of the asking call
		_pg.connect(sig, fn, CONNECT_DEFERRED if _deferred else 0)
	else:
		push_warning("Notifier: plugin has no signal %s" % sig)

func _later(fn: Callable) -> void:
	if _deferred:
		fn.call_deferred()
	else:
		fn.call()
