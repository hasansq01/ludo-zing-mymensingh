extends "res://tests/test_suite.gd"
## In-app updates (res://scripts/net/app_update.gd): the version code (and that the project setting equals every export
## preset's version/code), the soft offer through a fake Play plugin (offer, download progress, Update ready, Restart,
## Later for 2 days, the immediate-only case, a failed start), the fallback where Play can't answer (the server's
## `latest`, the store page), the required update (gate, the sheet's immediate flow, the server's refusals), the
## banner and the sheet, and what goes on the wire (`app` in hellos, X-App-Version, the 426 / update_required errors).
## Nothing here writes the save, opens a socket or opens a store page.

## Stands in for the Kotlin plugin singleton: the update methods and signals, answering as `answer` says.
class FakePlugin extends RefCounted:
	signal update_info(info: Dictionary)
	signal update_state(state: Dictionary)
	signal update_failed(code: String)

	var code := 10
	var calls: Array = []
	## what update_check() answers: an update_info dictionary, or {} = update_failed("check:fake")
	var info := {}
	func version_code() -> int:
		return code
	func update_check() -> void:
		calls.append("check")
		if info.is_empty():
			update_failed.emit("check:fake")
		else:
			update_info.emit(info)
	func update_start(immediate: bool) -> void:
		calls.append("start:%s" % immediate)
	func update_complete() -> void:
		calls.append("complete")

## A plugin build from before updates: other methods only.
class OldPlugin extends RefCounted:
	func share(_t: String, _p: String) -> bool:
		return true

class FakeApp extends Node:
	var sheet_layer := Control.new()
	var ui_root := Control.new()
	var screen := "home"
	var safe_top := 0.0
	var app_update: AppUpdate
	var online: Online

	func _init() -> void:
		sheet_layer.size = Vector2(390, 844)
		ui_root.size = Vector2(390, 844)
		add_child(ui_root)
		add_child(sheet_layer)

	func close_all_sheets() -> void:
		for c in sheet_layer.get_children():
			c.queue_free()

const OFFER := {available = true, in_progress = false, version_code = 11, staleness_days = 3, priority = 0, flexible = true,
	immediate = true, status = "unknown"}

var _sp: Dictionary
var _spf: Dictionary
var _urls: Array = []
var _clock := 1_000_000


func run() -> void:
	_sandbox()
	AppUpdate.plugin = null
	AppUpdate.code_override = 0
	_version()
	_stub_and_fallback()
	_soft_flow()
	_later()
	_immediate_only()
	_failed_start()
	_required()
	_ui()
	await _wire()
	_online()
	AppUpdate.plugin = null
	AppUpdate.code_override = 0
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

## An AppUpdate without UI, the fake plugin (or none) wired, the server saying min_online / latest.
func make(pg: Object, min_online := 0, latest := 10, code := 10, parent: Node = null) -> AppUpdate:
	AppUpdate.plugin = pg
	AppUpdate.code_override = code
	var u := AppUpdate.new()
	u.no_ui = true
	u.clock = func() -> int: return _clock
	u.config_fn = func() -> Dictionary: return {ok = true, min_online = min_online, latest = latest}
	u.open_url_fn = func(url: String) -> int:
		_urls.append(url)
		return OK
	_urls = []
	Save.prefs.erase("update_later")
	(parent if parent != null else (Engine.get_main_loop() as SceneTree).root).add_child(u)
	return u

func done(u: AppUpdate) -> void:
	u.free()
	AppUpdate.plugin = null
	AppUpdate.code_override = 0


# ---------- the version code ----------

func _version() -> void:
	AppUpdate.code_override = 0
	AppUpdate.plugin = null
	var setting := int(ProjectSettings.get_setting("application/config/version_code", 0))
	var cfg := ConfigFile.new()
	var ok := cfg.load("res://export_presets.cfg") == OK
	var codes: Array = []
	if ok:
		for sec in cfg.get_sections():
			if sec.ends_with(".options") and cfg.has_section_key(sec, "version/code"):
				codes.append(int(cfg.get_value(sec, "version/code")))
	check("version: export_presets.cfg has a version/code per preset", ok and codes.size() >= 1, codes)
	check("version: the project setting equals every preset's version/code (bump them together)",
		codes.all(func(c: int) -> bool: return c == setting), [setting, codes])
	check("version: off Android it is the project setting", AppUpdate.version_code() == setting, AppUpdate.version_code())
	var pg := FakePlugin.new()
	pg.code = 42
	AppUpdate.plugin = pg
	check("version: on Android the installed package's (the plugin)", AppUpdate.version_code() == 42)
	AppUpdate.plugin = OldPlugin.new()
	check("version: a plugin without version_code falls back to the setting", AppUpdate.version_code() == setting)
	AppUpdate.code_override = 7
	check("version: the test / dev override wins", AppUpdate.version_code() == 7)
	AppUpdate.code_override = 0
	AppUpdate.plugin = null


# ---------- no plugin: the fallback ----------

func _stub_and_fallback() -> void:
	var u := make(null, 0, 12, 10)
	check("stub: no plugin, no native", AppUpdate.native() == null)
	AppUpdate.plugin = OldPlugin.new()
	check("stub: an older plugin without the update methods is no native either", AppUpdate.native() == null)
	AppUpdate.plugin = null
	u.refresh_policy()
	check("policy: min_online and latest are read", u.min_online == 0 and u.latest == 12 and u.newer_on_server())
	u._ask()
	check("fallback: the server's latest is newer -> a dialog is due (state fallback)", u.state == "fallback" and not u.play_ok and u.last_error == "check:no_plugin", [u.state, u.last_error])
	u.open_store()
	check("fallback: Update opens the market:// page", _urls == [AppUpdate.STORE_URL] and u.last_url.begins_with("market://details?id=com.flipfold.ludozing"), _urls)
	check("fallback: the web page is the other way", AppUpdate.WEB_URL == "https://play.google.com/store/apps/details?id=com.flipfold.ludozing")
	done(u)
	u = make(null, 0, 10, 10)
	u.refresh_policy()
	u._ask()
	check("fallback: latest is not newer -> nothing is shown", u.state == "none" and not u.newer_on_server())
	done(u)
	u = make(null, 0, 12, 10)
	u.refresh_policy()
	u.postpone(12)
	u._ask()
	check("fallback: a version put off with Later stays quiet", u.state == "none")
	done(u)
	# a policy fetch that fails keeps what we had
	u = make(null, 0, 12, 10)
	u.refresh_policy()
	u.config_fn = func() -> Dictionary: return {ok = false}
	u.refresh_policy()
	check("policy: offline keeps the last policy", u.latest == 12)
	done(u)


# ---------- the soft flow through Play ----------

func _soft_flow() -> void:
	var pg := FakePlugin.new()
	pg.info = OFFER
	var u := make(pg, 0, 10, 10)
	u._ask()
	check("soft: Play has a newer version -> the offer", u.state == "offer" and u.version == 11 and u.via == "flexible" and u.play_ok, [u.state, u.version])
	check("soft: asked once per session", pg.calls == ["check"])
	u._ask()
	check("soft: a second ask in the same session does nothing", pg.calls == ["check"])
	u.accept_offer()
	check("soft: Update starts the flexible flow and shows the download", pg.calls == ["check", "start:false"] and u.state == "downloading", pg.calls)
	pg.update_state.emit({status = "downloading", bytes = 5, total = 20, error = ""})
	check("soft: progress is kept", u.state == "downloading" and u.bytes == 5 and u.total == 20)
	check("soft: the banner text is a percentage", UpdateBanner.progress_text(5, 20) == "25%" and UpdateBanner.progress_text(0, 0) == "You can keep playing.")
	pg.update_state.emit({status = "downloaded", bytes = 20, total = 20, error = ""})
	check("soft: downloaded -> Update ready", u.state == "ready")
	u.restart()
	check("soft: Restart completes the update", pg.calls.back() == "complete")
	pg.update_state.emit({status = "installed", bytes = 0, total = 0, error = ""})
	check("soft: installed clears it", u.state == "none")
	done(u)

	# a download that finished while the app was away: Play's resume report, or the next check
	pg = FakePlugin.new()
	u = make(pg, 0, 10, 10)
	pg.update_state.emit({status = "downloaded", bytes = 0, total = 0, error = ""})
	check("soft: a download finished in the background -> Update ready", u.state == "ready")
	u.hide_ready()
	check("soft: Later on Update ready keeps it down for the session", u._ready_hidden and u.state == "ready")
	done(u)
	pg = FakePlugin.new()
	pg.info = {available = false, in_progress = false, version_code = 11, staleness_days = -1, flexible = true, immediate = true, status = "downloaded"}
	u = make(pg, 0, 10, 10)
	u._ask()
	check("soft: the check finds an update downloaded before this launch -> Update ready", u.state == "ready")
	done(u)

	# nothing newer / a version we already are / failures
	pg = FakePlugin.new()
	pg.info = {available = false, in_progress = false, version_code = 10, staleness_days = -1, flexible = false, immediate = false, status = "unknown"}
	u = make(pg, 0, 10, 10)
	u._ask()
	check("soft: no update -> nothing", u.state == "none" and u.play_ok)
	done(u)
	pg = FakePlugin.new()
	pg.info = OFFER.merged({version_code = 10}, true)
	u = make(pg, 0, 10, 10)
	u._ask()
	check("soft: an \"available\" version that is not above ours is ignored", u.state == "none")
	done(u)
	pg = FakePlugin.new()
	pg.info = OFFER.merged({in_progress = true}, true)
	u = make(pg, 0, 10, 10)
	u._ask()
	check("soft: an immediate update in progress is the plugin's to resume, not an offer", u.state == "none")
	done(u)

	# the player backs out of Play's screen / the download fails
	pg = FakePlugin.new()
	pg.info = OFFER
	u = make(pg, 0, 10, 10)
	u._ask()
	u.accept_offer()
	pg.update_state.emit({status = "cancelled", bytes = 0, total = 0, error = ""})
	check("soft: cancelled in Play -> back to none and put off", u.state == "none" and u._postponed(11))
	done(u)
	pg = FakePlugin.new()
	pg.info = OFFER
	u = make(pg, 0, 10, 10)
	u._ask()
	u.accept_offer()
	pg.update_state.emit({status = "failed", bytes = 0, total = 0, error = "install_error_-6"})
	check("soft: a failed download -> none, the error kept", u.state == "none" and u.last_error == "install_error_-6")
	done(u)

	# Play can't answer: the plugin is there but the check fails (not installed from Play): the fallback
	pg = FakePlugin.new()
	u = make(pg, 0, 12, 10)
	u.refresh_policy()
	u._ask()
	check("fallback: a failed Play check uses the server's latest", u.state == "fallback" and not u.play_ok, [u.state, u.play_ok])
	done(u)
	pg = FakePlugin.new()
	u = make(pg, 0, 10, 10)
	u.refresh_policy()
	u._ask()
	check("fallback: a failed Play check with latest == ours shows nothing", u.state == "none" and not u.play_ok)
	done(u)


func _later() -> void:
	var pg := FakePlugin.new()
	pg.info = OFFER
	var u := make(pg, 0, 10, 10)
	u._ask()
	u.decline_offer()
	check("later: hides the offer", u.state == "none")
	check("later: that version is put off for 2 days", u._postponed(11) and int(Save.prefs.update_later.until) == _clock + 2 * 86400, Save.prefs.get("update_later"))
	_clock += 2 * 86400 - 10
	check("later: still put off just before 2 days", u._postponed(11))
	var u2 := make(pg, 0, 10, 10)
	Save.prefs.update_later = {v = 11, until = _clock + 10}
	u2._asked = false
	u2._ask()
	check("later: a new session within the 2 days is not offered the same version", u2.state == "none")
	done(u2)
	_clock += 20
	check("later: offered again after 2 days", not u._postponed(11))
	check("later: a newer version is offered at once", not u._postponed(12))
	Save.prefs.update_later = {v = 11, until = _clock + 100}
	check("later: a newer version than the put-off one", u._postponed(11) and not u._postponed(12))
	done(u)
	_clock = 1_000_000


func _immediate_only() -> void:
	var pg := FakePlugin.new()
	pg.info = OFFER.merged({flexible = false}, true)
	var u := make(pg, 0, 10, 10)
	u._ask()
	check("immediate-only: offered as the immediate flow", u.state == "offer" and u.via == "immediate")
	u.accept_offer()
	check("immediate-only: Update runs Play's immediate screen", pg.calls.back() == "start:true" and u.state == "none", pg.calls)
	done(u)
	pg = FakePlugin.new()
	pg.info = OFFER.merged({flexible = false, immediate = false}, true)
	u = make(pg, 0, 10, 10)
	u._ask()
	check("neither flow allowed: no offer", u.state == "none")
	done(u)


func _failed_start() -> void:
	var pg := FakePlugin.new()
	pg.info = OFFER
	var u := make(pg, 0, 10, 10)
	u._ask()
	u.accept_offer()
	pg.update_failed.emit("start:ERROR_APP_NOT_OWNED")
	check("failed start: back to none and the store page opens", u.state == "none" and _urls == [AppUpdate.STORE_URL], _urls)
	done(u)


# ---------- required ----------

func _required() -> void:
	var u := make(null, 11, 12, 10)
	check("required: default policy blocks nobody", not make_required(0, 10) and not make_required(0, 10))
	u.refresh_policy()
	check("required: below min_online", u.required() and u.min_online == 11)
	check("required: at min_online it is fine", not make_required(11, 11))
	check("required: above min_online it is fine", not make_required(11, 12))
	check("required: min_online 0 never blocks (not even an old version)", not make_required(0, 1))
	done(u)

	# the sheet's Update: Play's immediate flow when allowed, else the store
	var pg := FakePlugin.new()
	pg.info = OFFER
	u = make(pg, 11, 11, 10)
	u.refresh_policy()
	u.update_now()
	check("required: Update runs Play's immediate flow", pg.calls == ["check", "start:true"] and _urls.is_empty(), pg.calls)
	done(u)
	pg = FakePlugin.new()
	pg.info = OFFER.merged({immediate = false}, true)
	u = make(pg, 11, 11, 10)
	u.update_now()
	check("required: Play can't do immediate -> the store page", pg.calls == ["check"] and _urls == [AppUpdate.STORE_URL], [pg.calls, _urls])
	done(u)
	pg = FakePlugin.new()                          # the check fails (not installed from Play)
	u = make(pg, 11, 11, 10)
	u.update_now()
	check("required: Play unavailable -> the store page, and no soft offer on top", _urls == [AppUpdate.STORE_URL] and u.state == "none", [_urls, u.state])
	done(u)
	u = make(null, 11, 11, 10)
	u.update_now()
	check("required: no plugin -> the store page", _urls == [AppUpdate.STORE_URL])
	done(u)

	# a server refusal makes it required without the policy
	u = make(null, 0, 10, 10)
	check("refused: not required before", not u.required())
	u.note_refused(11)
	check("refused: the server's update_required makes it required", u.required() and u.min_online == 11)
	u.refresh_policy()
	check("refused: the policy later says min 0 and we are fine again", not u.required())
	done(u)


func make_required(min_online: int, code: int) -> bool:
	var u := make(null, min_online, 10, code)
	u.min_online = min_online
	var r := u.required()
	done(u)
	return r


# ---------- banner and sheet ----------

func _ui() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var app := FakeApp.new()
	tree.root.add_child(app)
	var pg := FakePlugin.new()
	pg.info = OFFER
	var u := make(pg, 0, 10, 10, app)
	u.no_ui = false
	u.app = app
	u.min_online = 11
	app.app_update = u
	u._ask()
	u._sync()
	var b := u.banner
	check("banner: the offer shows on a quiet Home", b != null and b.mode == "offer" and b.title_label.text == "A new version is available"
		and b.later_button.text == "Later" and b.action_button.text == "Update" and b.buttons.visible and not b.bar.visible, [b != null and b.mode])
	check("banner: 48 px high buttons", b.action_button.get_combined_minimum_size().y >= 44.0, b.action_button.get_combined_minimum_size())
	check("banner: sits under the invite banner's z (over sheets)", b.z_index == UpdateBanner.Z)
	app.screen = "ludo"
	u._sync()
	check("banner: never in a match", u.banner == null or u.banner.is_queued_for_deletion() or u.banner._gone)
	app.screen = "home"
	u.banner = null
	u._sync()
	b = u.banner
	check("banner: back on Home it comes back", b != null)
	var sh := Sheet.new("Some sheet")
	sh.open(app.sheet_layer)
	u._sync()
	check("banner: never over a sheet", not u.can_show() and (u.banner == null or u.banner._gone))
	sh.close()
	app.close_all_sheets()
	u.banner = null
	u._sync()
	b = u.banner
	b.update_pressed.emit()
	check("banner: Update -> downloading mode with a bar", u.state == "downloading" and b.mode == "downloading" and b.bar.visible and not b.buttons.visible, [u.state, b.mode])
	pg.update_state.emit({status = "downloading", bytes = 10, total = 40, error = ""})
	u._sync()
	check("banner: the percentage", b.sub_label.text == "25%", b.sub_label.text)
	pg.update_state.emit({status = "downloaded", bytes = 40, total = 40, error = ""})
	u._sync()
	check("banner: Update ready with Restart", b.mode == "ready" and b.title_label.text == "Update ready" and b.action_button.text == "Restart" and b.buttons.visible, [b.mode, b.action_button.text])
	b.restart_pressed.connect(func() -> void: pass)
	b.action_button.pressed.emit()
	check("banner: Restart calls completeUpdate", pg.calls.back() == "complete", pg.calls)
	# the required sheet
	var s := u.open_required()
	check("sheet: Update required", s is UpdateSheet and (s as UpdateSheet).title_label.text == "Update required" and u.gate(), s)
	check("sheet: only one at a time", u.open_required() == s)
	var us := s as UpdateSheet
	check("sheet: Update is a 48 px target", us.update_button.get_combined_minimum_size().y >= UIKit.TAP, us.update_button.get_combined_minimum_size())
	check("sheet: says the offline modes still work", us.note_label.text.contains("computer"), us.note_label.text)
	pg.calls.clear()
	us.update_button.pressed.emit()
	check("sheet: Update asks Play, then runs the immediate flow", pg.calls == ["check", "start:true"], pg.calls)
	# the fallback dialog
	app.close_all_sheets()
	u.state = "none"
	u.version = 11
	u._set_state("fallback")
	check("dialog: the fallback offer is a confirm dialog", Sheet.top_sheet(app.sheet_layer) != null and Sheet.top_sheet(app.sheet_layer).has_meta("confirm"))
	var yes := Sheet.top_sheet(app.sheet_layer).find_child("Yes", true, false) as Button
	check("dialog: Update / Later", yes != null and yes.text == "Update", yes.text if yes else "none")
	u._dialog.answered.emit(true)
	check("dialog: Update opens the store page", _urls.back() == AppUpdate.STORE_URL, _urls)
	app.free()                               # now, inside the sandbox: freeing the dialog answers "Later" and saves
	AppUpdate.plugin = null
	AppUpdate.code_override = 0


# ---------- on the wire ----------

func _wire() -> void:
	AppUpdate.code_override = 11
	var room := NetFake.Room.new("SNRM22", 9)
	var a := NetClient.new()
	a.use_save = false
	a.prefs = {}
	a.url_base = "ws://fake"
	a.session_fn = func() -> String: return "s-Ana"
	a.profile_fn = func() -> Dictionary: return {name = "Ana", avatar = "pawn-blue", frame = "classic"}
	a.make_transport = room.transport_factory()
	a.http_fn = room.http
	a.join("SNRM22")
	for k in 3:
		a._process(0.0)
	var hellos: Array = a.log_sent.filter(func(m: Dictionary) -> bool: return m.t == "hello")
	check("wire: the room hello carries the app's version code", hellos.size() == 1 and hellos[0].get("app") == 11, hellos)
	a.free()
	var hub := NetFake.Hub.new(3)
	var c := NetClient.new()
	c.use_save = false
	c.prefs = {}
	c.url_base = "ws://fake"
	c.session_fn = func() -> String: return "s-Bo"
	c.profile_fn = func() -> Dictionary: return {name = "Bo", avatar = "pawn-blue", frame = "classic"}
	c.make_transport = hub.transport_factory()
	c.http_fn = hub.http
	var q := NetQuick.new(c)
	q.search("ludo", 2)
	for k in 3:
		c._process(0.0)
		q._process(0.0)
	var qh: Array = q.log_sent.filter(func(m: Dictionary) -> bool: return m.t == "hello")
	check("wire: the quick-match hello carries it too", qh.size() >= 1 and qh[0].get("app") == 11, qh)
	q.free()
	c.free()
	check("wire: update_required reads as \"Update Ludo Zing to play online.\"", NetClient.error_text("update_required") == "Update Ludo Zing to play online.")
	check("wire: update_required is a fatal hello error (room and queue)", "update_required" in NetClient.FATAL and "update_required" in NetQuick.FATAL)
	var c2 := NetClient.new()
	c2.use_save = false
	c2.prefs = {}
	c2.http_fn = func(_method: int, _path: String) -> Dictionary:
		return {status = 200, data = {motd = "hi", maintenance = false, min_online = 11, latest = 12}}
	var cfg: Dictionary = await c2.fetch_config()
	check("wire: fetch_config carries min_online and latest", cfg.get("ok") == true and cfg.min_online == 11 and cfg.latest == 12, cfg)
	c2.http_fn = func(_method: int, _path: String) -> Dictionary:
		return {status = 200, data = {motd = "", maintenance = false}}
	cfg = await c2.fetch_config()
	check("wire: an older server's config has no policy (0 = nobody blocked)", cfg.min_online == 0 and cfg.latest == 0, cfg)
	c2.http_fn = func(_method: int, _path: String) -> Dictionary:
		return {status = 426, data = {error = "update_required", msg = "old", min = 11}}
	var r: Dictionary = await c2.create_room()
	check("wire: POST /v1/rooms 426 -> update_required with min", r.get("error") == "update_required" and int(r.get("min", 0)) == 11, r)
	c2.free()
	AppUpdate.code_override = 0


# ---------- Online: the gate and the refusals ----------

func _online() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var hub := NetFake.Hub.new(5)
	var app := FakeApp.new()
	tree.root.add_child(app)
	var u := make(null, 11, 11, 10, app)
	u.no_ui = false
	u.app = app
	app.app_update = u
	u.min_online = 11
	var c := NetClient.new()
	c.use_save = false
	c.prefs = {}
	c.url_base = "ws://fake"
	c.session_fn = func() -> String: return "s-Ana"
	c.profile_fn = func() -> Dictionary: return {name = "Ana", avatar = "pawn-blue", frame = "classic"}
	c.make_transport = hub.transport_factory()
	c.http_fn = hub.http
	var o := Online.new(app, c)
	o.coins_fn = func() -> int: return 5000
	o.level_fn = func() -> int: return 3
	app.online = o
	app.add_child(o)
	o.open_quick("ludo")
	check("online: Quick match below the minimum shows Update required, not the picker", o.quick_sheet == null and Sheet.top_sheet(app.sheet_layer) is UpdateSheet and o.state == "idle")
	app.close_all_sheets()
	o.open_friends("ludo")
	check("online: Play with friends too", o.friends == null and Sheet.top_sheet(app.sheet_layer) is UpdateSheet)
	app.close_all_sheets()
	o.join_code("K7QX2M")
	check("online: joining by code / invite too", o.state == "idle" and Sheet.top_sheet(app.sheet_layer) is UpdateSheet)
	app.close_all_sheets()
	check("online: a kept room is not resumed", not o.try_resume())
	# fine at or above the minimum
	u.min_online = 10
	o.open_quick("ludo")
	check("online: at the minimum the picker opens", o.quick_sheet != null and not (Sheet.top_sheet(app.sheet_layer) is UpdateSheet))
	app.close_all_sheets()
	# the server refuses a client that thought it was fine
	o.quick_sheet = null
	u.min_online = 0
	o.state = "joining"
	o._on_error({code = "update_required", min = 12})
	check("online: the server's update_required -> Update required, idle, required from now on", o.state == "idle" and u.required()
		and Sheet.top_sheet(app.sheet_layer) is UpdateSheet, [o.state, u.required()])
	app.close_all_sheets()
	u.min_online = 0
	u._forced = false
	o.state = "resuming"
	o._on_error({code = "update_required", min = 12})
	check("online: refused while only resuming a room: quiet, but required next time", o.state == "idle" and u.required() and Sheet.top_sheet(app.sheet_layer) == null)
	app.close_all_sheets()
	u._forced = false
	o.state = "searching"
	o.quick_q.fail_info = {min = 12}
	o._on_quick_failed("update_required", "old")
	check("online: the quick queue's update_required too", o.state == "idle" and u.required() and Sheet.top_sheet(app.sheet_layer) is UpdateSheet)
	app.free()                               # now, inside the sandbox: freeing the dialog answers "Later" and saves
	AppUpdate.plugin = null
	AppUpdate.code_override = 0
