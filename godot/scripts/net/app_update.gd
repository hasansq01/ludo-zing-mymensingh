class_name AppUpdate
extends Node
## In-app updates: Google Play's In-App Updates through the notifications plugin (godot/android/plugins/notifications/
## Updates.kt), the server's version policy, and the offer on Home. main.gd owns one (`app_update`).
##
## Soft updates (most releases): on Home, once per app session, Play is asked whether a newer version exists. If so a
## banner says "A new version is available" with Update / Later. Update downloads it in the background (flexible mode)
## while the player goes on; "Update ready" then offers Restart. Later hides the version for LATER_SEC (2 days). The
## banner only shows on Home, with no sheet open, no search or room, and no invite banner.
## Required updates (rare): the server's `min_online` (GET /v1/config, edited in the admin console) is the lowest
## version code allowed online. Below it, gate() shows the blocking "Update required" sheet instead of quick match,
## friend rooms and joins; its Update button runs Play's immediate flow. Offline play (vs Computer, Pass & Play) never
## asks. A server that refuses a hello / room (`update_required`) does the same (note_refused).
## Fallback: where Play can't answer (no plugin, not installed from Play, an emulator, any error) the update goes to
## the Play Store page (market://, else the web page); the soft offer is then a plain dialog, shown only when the
## server's `latest` is above this version code.
##
##   var u := AppUpdate.new(self); add_child(u); u.start()   # main, once Home is up; u.resume() when the app returns
##   if u.gate(): return                                     # before any online play: true = the sheet is showing
##   AppUpdate.version_code()                                # this app's: `app` in hellos, X-App-Version in HTTP
## The plugin methods are used through has_java_method like Share does; every plugin answer is a signal (update_info,
## update_state, update_failed), so a stub (no plugin) just takes the fallback path.
## Tests: AppUpdate.plugin (a fake singleton), AppUpdate.code_override, config_fn () -> {ok, min_online, latest},
## open_url_fn (url) -> Error, clock () -> unix s, no_ui (no banner / dialog / sheet: read state, offers).

## Something the UI shows changed (state, policy).
signal changed

const SINGLETON := "NotificationsPlugin"
const STORE_URL := "market://details?id=com.flipfold.ludozing"
const WEB_URL := "https://play.google.com/store/apps/details?id=com.flipfold.ludozing"
const LATER_SEC := 2 * 86400
const TICK_SEC := 1.0
const FIRST_SEC := 5.0                   ## after Home is up: let it settle before asking Play
const FALLBACK_CODE := 10                ## project setting application/config/version_code when the plugin can't say

## Tests: a fake with the plugin's methods and signals stands in for the singleton.
static var plugin: Object = null
## Tests, dev: this version code instead of the real one (0 = the real one).
static var code_override := 0
static var _code := 0

var app: Node                            ## main (screen, ui_root, sheet_layer, online, social)
var min_online := 0                      ## the server's lowest version code for online play (0 = nobody blocked)
var latest := 0                          ## the server's newest version code on Play (0 = not read yet)
var state := "none"                      ## "none" | "offer" | "fallback" (a dialog is due) | "downloading" | "ready"
var via := "flexible"                    ## the offer's Play flow: "flexible" | "immediate"
var version := 0                         ## the version the offer / download is for
var bytes := 0
var total := 0
var play: Dictionary = {}                ## the last update_info
var play_ok := true                      ## Play answered the last check (false: the fallback is in use)
var config_fn := Callable()
var open_url_fn := Callable()
var clock := Callable()
var no_ui := false
var banner: UpdateBanner
var last_url := ""                       ## the store URL last opened
var last_error := ""                     ## the last update_failed code

var _pg: Object
var _forced := false                     # the server refused a hello / room as too old
var _asked := false                      # Play was asked this session
var _now_flow := false                   # the required sheet's Update waits for Play's answer
var _ready_hidden := false               # "Update ready" was put off for this session
var _dialog: Sheet
var _required_sheet: Sheet
var _timer: Timer


func _init(app_: Node = null) -> void:
	app = app_

func _ready() -> void:
	_pg = native()
	if _pg != null:
		_connect("update_info", _on_info)
		_connect("update_state", _on_state)
		_connect("update_failed", _on_failed)
	_timer = Timer.new()
	_timer.wait_time = TICK_SEC
	_timer.timeout.connect(_sync)
	add_child(_timer)
	_timer.start()

func _connect(sig: String, fn: Callable) -> void:
	if _pg.has_signal(sig):
		_pg.connect(sig, fn)

## The plugin object when it can ask Play (a build with `update_check`), else null.
static func native() -> Object:
	var p := plugin
	if p == null and Engine.has_singleton(SINGLETON):
		p = Engine.get_singleton(SINGLETON)
	if p == null or not _can(p, "update_check"):
		return null
	return p

static func _can(p: Object, method: String) -> bool:
	# a JNISingleton (the real plugin) answers has_java_method; a fake or a script object has the method itself
	return p.has_method(method) or (p.has_method("has_java_method") and bool(p.call("has_java_method", method)))

## This app's version code (the Play Console's number): from the plugin on Android (the installed package's), else the
## project setting application/config/version_code, which a test keeps equal to export_presets.cfg's version/code.
static func version_code() -> int:
	if code_override > 0:
		return code_override
	if _code > 0 and plugin == null:
		return _code
	var p := plugin
	if p == null and Engine.has_singleton(SINGLETON):
		p = Engine.get_singleton(SINGLETON)
	var v := 0
	if p != null and _can(p, "version_code"):
		v = int(p.call("version_code"))
	if v <= 0:
		v = int(ProjectSettings.get_setting("application/config/version_code", FALLBACK_CODE))
	if plugin == null:
		_code = v
	return v

func now() -> int:
	return int(clock.call()) if clock.is_valid() else int(Time.get_unix_time_from_system())


# ---------- the server's policy ----------

## GET /v1/config: min_online and latest. Quiet when offline (the policy stays as it was).
func refresh_policy() -> void:
	var c: Dictionary = {}
	if config_fn.is_valid():
		c = await config_fn.call()
	else:
		var o: Variant = app.get("online") if app != null else null
		if o is Online and is_instance_valid(o) and (o as Online).net != null:
			c = await (o as Online).net.fetch_config()
	if not bool(c.get("ok", false)):
		return
	min_online = maxi(0, int(c.get("min_online", 0)))
	latest = maxi(0, int(c.get("latest", 0)))
	_forced = _forced and version_code() < maxi(min_online, 1)   # (the policy now says we are fine: believe it)
	changed.emit()

## The server's `latest` is above this version.
func newer_on_server() -> bool:
	return latest > version_code()

## Online play needs an update first: below the server's minimum, or the server just refused us.
func required() -> bool:
	return _forced or (min_online > 0 and version_code() < min_online)

## Before online play (quick match, friend rooms, joining): true when the "Update required" sheet came up instead.
func gate() -> bool:
	if not required():
		return false
	open_required()
	return true

## The server answered `update_required` (a hello, POST /v1/rooms): from now on gate() blocks until updated.
func note_refused(min_ := 0) -> void:
	_forced = true
	if min_ > min_online:
		min_online = min_
	changed.emit()


# ---------- the soft offer ----------

## Once Home is up: read the policy, wait for a quiet Home, then ask Play (once per session).
func start() -> void:
	await refresh_policy()
	if no_ui:
		_ask()
		return
	await get_tree().create_timer(FIRST_SEC).timeout
	while not can_show():
		await get_tree().create_timer(TICK_SEC * 2.0).timeout
	_ask()

## The app came back: the policy again (a rollout may have changed it). Play's own resume report arrives as update_state.
func resume() -> void:
	refresh_policy()

func _ask() -> void:
	if _asked:
		return
	_asked = true
	var p := _pg if _pg != null else native()
	if p == null:
		_on_failed("check:no_plugin")
		return
	p.call("update_check")

## Play's answer: {available, version_code, staleness_days, flexible, immediate, in_progress, priority, status}.
func _on_info(d: Dictionary) -> void:
	play = d
	play_ok = true
	if _now_flow:
		_now_flow = false
		if bool(d.get("available", false)) and bool(d.get("immediate", false)):
			_pg.call("update_start", true)
		else:
			open_store()                          # Play has nothing to install (yet): the store page
		return
	if bool(d.get("in_progress", false)):
		return                                    # an immediate update is going on: the plugin resumes it
	var status := str(d.get("status", ""))
	if status == "downloaded":
		_set_state("ready")
		return
	if status == "downloading":
		_set_state("downloading")
		return
	if not bool(d.get("available", false)):
		return
	var v := int(d.get("version_code", 0))
	if v <= version_code() or _postponed(v):
		return
	if bool(d.get("flexible", false)):
		via = "flexible"
	elif bool(d.get("immediate", false)):
		via = "immediate"
	else:
		return
	version = v
	_set_state("offer")

func _on_state(d: Dictionary) -> void:
	bytes = int(d.get("bytes", 0))
	total = int(d.get("total", 0))
	match str(d.get("status", "")):
		"pending", "downloading":
			_set_state("downloading")
		"downloaded":
			_set_state("ready")
		"installing", "installed":
			_set_state("none")
		"cancelled":
			if version > 0:
				postpone(version)                 # backed out of Play's screen: not again for a while
			_set_state("none")
		"failed":
			last_error = str(d.get("error", ""))
			_set_state("none")
			_toast(L10n.t("The update didn’t download. Try again later."), "bad")

## Play can't be used (check / start / complete): the check falls back to the server's `latest`; a start the player
## asked for goes to the store page.
func _on_failed(code: String) -> void:
	last_error = code
	if code.begins_with("check:"):
		play_ok = false
		play = {}
		print("AppUpdate: Play can't be used (%s): the fallback (the server's latest %d, this version %d)" % [code, latest, version_code()])
		if _now_flow:
			_now_flow = false
			open_store()
			return
		if newer_on_server() and not _postponed(latest):
			version = latest
			_set_state("fallback")
	else:
		_set_state("none")
		open_store()

## Update on the offer banner: the flexible download starts (progress on the banner), or Play's immediate screen.
func accept_offer() -> void:
	if state != "offer":
		return
	var p := _pg if _pg != null else native()
	if p == null:
		_set_state("none")
		open_store()
		return
	bytes = 0
	total = 0
	_set_state("none" if via == "immediate" else "downloading")
	p.call("update_start", via == "immediate")

## Later on the offer: hidden for this version for LATER_SEC.
func decline_offer() -> void:
	postpone(version)
	_set_state("none")

## Restart on "Update ready": Play installs the downloaded update and the app restarts.
func restart() -> void:
	var p := _pg if _pg != null else native()
	if state != "ready" or p == null:
		return
	p.call("update_complete")

## Later on "Update ready": hidden until the next launch (Play also installs it by itself some time after).
func hide_ready() -> void:
	_ready_hidden = true
	_sync()

func postpone(v: int) -> void:
	Save.prefs.update_later = {v = v, until = now() + LATER_SEC}
	Save.save()

func _postponed(v: int) -> bool:
	var l: Variant = Save.prefs.get("update_later")
	return l is Dictionary and int((l as Dictionary).get("v", 0)) >= v and int((l as Dictionary).get("until", 0)) > now()

func _set_state(s: String) -> void:
	if s == state:
		changed.emit()
		return
	state = s
	changed.emit()
	_sync()


# ---------- the required update ----------

## The "Update required" sheet (a blocking screen over Home; the offline modes stay on Home behind it).
func open_required() -> Sheet:
	if is_instance_valid(_required_sheet) and not _required_sheet.is_queued_for_deletion():
		return _required_sheet
	if no_ui:
		return null
	var s := UpdateSheet.new(self)
	_required_sheet = s
	var layer := _layer()
	if layer != null:
		s.open(layer)
	return s

## The sheet's Update: Play's immediate flow, or the store page when Play can't.
func update_now() -> void:
	var p := _pg if _pg != null else native()
	if p == null:
		open_store()
		return
	_now_flow = true
	p.call("update_check")

## The Play Store page: the store app (market://), else the web page.
func open_store() -> void:
	last_url = STORE_URL
	if open_url_fn.is_valid():
		open_url_fn.call(STORE_URL)
		return
	if OS.shell_open(STORE_URL) != OK:
		last_url = WEB_URL
		OS.shell_open(WEB_URL)


# ---------- what is on screen ----------

## Home is quiet: no match, no sheet, no search or room, no invite banner.
func can_show() -> bool:
	if app == null:
		return true
	if str(app.get("screen")) != "home":
		return false
	var layer := _layer()
	if layer != null and Sheet.top_sheet(layer) != null:
		return false
	var o: Variant = app.get("online")
	if o is Online and is_instance_valid(o) and (o as Online).state != "idle":
		return false
	var s := Social.instance()
	return not (s != null and is_instance_valid(s.banner))

func _layer() -> Control:
	if app != null and app.get("sheet_layer") is Control:
		return app.sheet_layer
	return null

func _host() -> Node:
	return app.get("ui_root") if app != null and app.get("ui_root") is Node else self

func _safe_top() -> float:
	var t: Variant = app.get("safe_top") if app != null else null
	return float(t) if t != null else 0.0

func _toast(text: String, kind := "info") -> void:
	if not no_ui:
		Toast.show(_host(), text, null, 2.4, kind)

## Banner and dialog follow the state and whether Home is quiet (every TICK_SEC and on every state change).
func _sync() -> void:
	if no_ui:
		return
	var show_banner := state in ["offer", "downloading", "ready"] and not (state == "ready" and _ready_hidden) and can_show()
	if show_banner:
		if not is_instance_valid(banner):
			banner = UpdateBanner.new(state)
			banner.update_pressed.connect(accept_offer)
			banner.later_pressed.connect(func() -> void:
				if state == "ready":
					hide_ready()
				else:
					decline_offer())
			banner.restart_pressed.connect(restart)
			var host := _host()
			host.add_child(banner)
			banner.show_in(_safe_top())
		banner.set_mode(state, bytes, total)
	elif is_instance_valid(banner):
		banner.dismiss()
		banner = null
	if state == "fallback" and can_show() and not is_instance_valid(_dialog):
		_open_dialog()

## The fallback offer: a plain dialog, Update opens the store page.
func _open_dialog() -> void:
	var layer := _layer()
	if layer == null:
		return
	_dialog = Sheet.make_confirm(L10n.t("Update Ludo Zing"), L10n.t("A new version is available. Update to get the latest fixes."),
		L10n.t("Update"), L10n.t("Later"))
	var v := version
	_dialog.answered.connect(func(yes: bool) -> void:
		_set_state("none")
		if yes:
			open_store()
		else:
			postpone(v))
	_dialog.open(layer)
