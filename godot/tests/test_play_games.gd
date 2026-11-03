extends "res://tests/test_suite.gd"
## Play Games wrapper (res://scripts/net/play_games.gd): the stub everywhere the Android plugin is missing
## (desktop / headless: every request answers "unavailable", always later than the call), the mapping of the
## plugin's signals onto the wrapper's (through a fake singleton with the Kotlin plugin's methods and signals),
## and the export plugin's manifest snippet (APP_ID escaping, disabled = SDK auto-init removed).

const PG := preload("res://scripts/net/play_games.gd")
const Export := preload("res://addons/play_games/export_plugin.gd")

## Stands in for the Kotlin PlayGamesPlugin singleton: same method and signal names, answers synchronously.
class FakePlugin extends RefCounted:
	signal initialized(enabled: bool, reason: String)
	signal auth_checked(authenticated: bool, error: String)
	signal sign_in_completed(success: bool, error: String)
	signal server_auth_code_completed(success: bool, code: String, error: String)
	signal player_info_completed(success: bool, info: Dictionary, error: String)
	signal score_submitted(leaderboard_id: String, success: bool, error: String)
	signal achievement_unlocked(achievement_id: String, success: bool, error: String)
	signal ui_completed(kind: String, success: bool, error: String)
	signal ui_closed(kind: String)

	var enabled := true
	var authenticated := false
	var sign_in_error := ""          # "" = the manual sign-in succeeds
	var calls: Array = []

	func initialize() -> bool:
		calls.append("initialize")
		initialized.emit(enabled, "" if enabled else "no_app_id")
		return enabled
	func isEnabled() -> bool:
		return enabled
	func getStatus() -> Dictionary:
		return {app_id_set = enabled, play_services = 0 if enabled else -1, initialized = enabled,
			error = "" if enabled else "", sdk_int = 35}
	func isAuthenticated() -> void:
		calls.append("isAuthenticated")
		auth_checked.emit(authenticated, "")
	func signIn() -> void:
		calls.append("signIn")
		if sign_in_error.is_empty():
			authenticated = true
		sign_in_completed.emit(sign_in_error.is_empty(), sign_in_error)
	func getPlayerInfo() -> void:
		calls.append("getPlayerInfo")
		if authenticated:
			player_info_completed.emit(true, {display_name = "Rina", player_id = "g123"}, "")
		else:
			player_info_completed.emit(false, {}, "not_signed_in")
	func requestServerSideAccess(web_client_id: String, force: bool) -> void:
		calls.append("requestServerSideAccess:%s:%s" % [web_client_id, force])
		server_auth_code_completed.emit(true, "4/code-for-" + web_client_id, "")
	func submitScore(id: String, score: int) -> void:
		calls.append("submitScore:%s:%d" % [id, score])
		score_submitted.emit(id, id != "bad", "" if id != "bad" else "api:26502")
	func showAllLeaderboards() -> void:
		calls.append("showAllLeaderboards")
		ui_completed.emit("leaderboards", true, "")
	func showLeaderboard(id: String) -> void:
		calls.append("showLeaderboard:" + id)
		ui_completed.emit("leaderboard", false, "disabled")
	func showAchievements() -> void:
		calls.append("showAchievements")
		ui_completed.emit("achievements", true, "")
	func unlockAchievement(id: String) -> void:
		calls.append("unlockAchievement:" + id)
		achievement_unlocked.emit(id, true, "")

var _log: Array = []

func run() -> void:
	_stub()
	_stub_is_deferred()
	_plugin_signed_in()
	_plugin_manual()
	_plugin_requests()
	_plugin_disabled()
	_export_manifest()

## Records every wrapper signal into _log as [name, args...].
func watch(pg: PG) -> void:
	_log = []
	pg.signed_in.connect(func(p): _log.append(["signed_in", p]))
	pg.sign_in_failed.connect(func(c): _log.append(["sign_in_failed", c]))
	pg.signed_out.connect(func(): _log.append(["signed_out"]))
	pg.server_auth_code.connect(func(c): _log.append(["server_auth_code", c]))
	pg.server_auth_code_failed.connect(func(c): _log.append(["server_auth_code_failed", c]))
	pg.score_submitted.connect(func(id, ok, e): _log.append(["score_submitted", id, ok, e]))
	pg.achievement_unlocked.connect(func(id, ok, e): _log.append(["achievement_unlocked", id, ok, e]))
	pg.ui_failed.connect(func(k, e): _log.append(["ui_failed", k, e]))
	pg.ui_closed.connect(func(k): _log.append(["ui_closed", k]))

func _stub() -> void:
	check("stub: no PlayGamesPlugin singleton on desktop / headless", not Engine.has_singleton(PG.SINGLETON))
	check("singleton name never shadows the class_name PlayGames", PG.SINGLETON != "PlayGames")
	var pg := PG.new(null, false)
	watch(pg)
	check("stub: not available", not pg.is_available())
	check("stub: reason no_plugin", pg.reason == "no_plugin", pg.reason)
	var st := pg.status()
	check("stub: status says unavailable", st.available == false and st.reason == "no_plugin", st)
	pg.sign_in()
	check("stub: sign_in -> sign_in_failed(unavailable)", _log == [["sign_in_failed", "unavailable"]], _log)
	check("stub: still signed out", not pg.is_signed_in and pg.player.is_empty())
	_log.clear(); pg.check_signed_in()
	check("stub: launch check -> signed_out", _log == [["signed_out"]], _log)
	_log.clear(); pg.request_server_auth_code("web-id")
	check("stub: server auth code -> failed(unavailable)", _log == [["server_auth_code_failed", "unavailable"]], _log)
	_log.clear(); pg.submit_score("board", 120)
	check("stub: submit_score -> score_submitted(false, unavailable)",
		_log == [["score_submitted", "board", false, "unavailable"]], _log)
	_log.clear(); pg.show_leaderboards(); pg.show_leaderboards("board"); pg.show_achievements()
	check("stub: Play Games screens -> ui_failed(unavailable)", _log == [["ui_failed", "leaderboards", "unavailable"],
		["ui_failed", "leaderboard", "unavailable"], ["ui_failed", "achievements", "unavailable"]], _log)
	_log.clear(); pg.unlock_achievement("ach")
	check("stub: unlock_achievement -> failed(unavailable)",
		_log == [["achievement_unlocked", "ach", false, "unavailable"]], _log)
	pg.free()

func _stub_is_deferred() -> void:
	var pg := PG.new()
	watch(pg)
	pg.sign_in()
	pg.request_server_auth_code()
	pg.submit_score("b", 1)
	check("stub (default): answers are deferred, never inside the call", _log.is_empty(), _log)
	pg.free()

func _plugin_signed_in() -> void:
	var fake := FakePlugin.new()
	fake.authenticated = true
	var pg := PG.new(fake, false)
	watch(pg)
	check("plugin: initialize called once on creation", fake.calls == ["initialize"], fake.calls)
	check("plugin: available", pg.is_available() and pg.reason == "", pg.reason)
	pg.check_signed_in()
	check("plugin: launch check signed in -> player info -> signed_in",
		_log == [["signed_in", {display_name = "Rina", player_id = "g123"}]], _log)
	check("plugin: player kept", pg.is_signed_in and pg.player.player_id == "g123", pg.player)
	check("plugin: calls isAuthenticated then getPlayerInfo",
		fake.calls == ["initialize", "isAuthenticated", "getPlayerInfo"], fake.calls)
	pg.free()

func _plugin_manual() -> void:
	var fake := FakePlugin.new()
	var pg := PG.new(fake, false)
	watch(pg)
	pg.check_signed_in()
	check("plugin: launch check not signed in -> signed_out (no error)", _log == [["signed_out"]], _log)
	fake.sign_in_error = "canceled"
	_log.clear(); pg.sign_in()
	check("plugin: manual sign-in canceled -> sign_in_failed(canceled)", _log == [["sign_in_failed", "canceled"]], _log)
	fake.sign_in_error = ""
	_log.clear(); pg.sign_in()
	check("plugin: manual sign-in ok -> signed_in", _log == [["signed_in", {display_name = "Rina", player_id = "g123"}]], _log)
	pg.free()

func _plugin_requests() -> void:
	var fake := FakePlugin.new()
	var pg := PG.new(fake, false)
	watch(pg)
	pg.request_server_auth_code("123-abc.apps.googleusercontent.com", true)
	check("plugin: server auth code for the given web client id",
		_log == [["server_auth_code", "4/code-for-123-abc.apps.googleusercontent.com"]], _log)
	check("plugin: forceRefreshToken passed", fake.calls.has("requestServerSideAccess:123-abc.apps.googleusercontent.com:true"), fake.calls)
	if str(ProjectSettings.get_setting(PG.WEB_CLIENT_SETTING, "")).is_empty():
		_log.clear(); pg.request_server_auth_code()
		check("plugin: no web client id configured -> failed(no_web_client_id)",
			_log == [["server_auth_code_failed", "no_web_client_id"]], _log)
	_log.clear(); pg.submit_score("board", 9000000000); pg.submit_score("bad", 1)
	check("plugin: scores (64-bit value) and API errors pass through",
		_log == [["score_submitted", "board", true, ""], ["score_submitted", "bad", false, "api:26502"]], _log)
	check("plugin: submitScore args", fake.calls.has("submitScore:board:9000000000"), fake.calls)
	_log.clear(); pg.show_leaderboards(); pg.show_leaderboards("one")
	check("plugin: screen opened is quiet; a refused one -> ui_failed (disabled -> unavailable)",
		_log == [["ui_failed", "leaderboard", "unavailable"]], _log)
	fake.ui_closed.emit("leaderboards")
	check("plugin: ui_closed passes through", _log.back() == ["ui_closed", "leaderboards"], _log)
	_log.clear(); pg.unlock_achievement("ach1")
	check("plugin: achievement", _log == [["achievement_unlocked", "ach1", true, ""]], _log)
	pg.free()

func _plugin_disabled() -> void:
	var fake := FakePlugin.new()
	fake.enabled = false
	var pg := PG.new(fake, false)
	watch(pg)
	check("plugin disabled (empty APP_ID): not available, reason no_app_id",
		not pg.is_available() and pg.reason == "no_app_id", pg.reason)
	pg.sign_in(); pg.check_signed_in(); pg.submit_score("b", 1)
	check("plugin disabled: unavailable answers, plugin never asked",
		_log == [["sign_in_failed", "unavailable"], ["signed_out"], ["score_submitted", "b", false, "unavailable"]]
		and fake.calls == ["initialize"], [_log, fake.calls])
	pg.free()

func _export_manifest() -> void:
	var off := Export.manifest_contents("")
	check("export: empty app id -> no APP_ID meta-data", not off.contains("games.APP_ID"), off)
	check("export: empty app id -> SDK auto-init provider removed",
		off.contains("PlayGamesInitProvider") and off.contains("tools:node=\"remove\""), off)
	var on := Export.manifest_contents("123456789012")
	check("export: APP_ID meta-data with the first digit escaped (kept a string by aapt)",
		on.contains("com.google.android.gms.games.APP_ID") and on.contains("android:value=\"\\u003123456789012\""), on)
	check("export: app id validation", Export.is_valid_app_id("123456789012") and not Export.is_valid_app_id("abc")
		and not Export.is_valid_app_id("-12") and not Export.is_valid_app_id(""))
	check("export: the project's Play Games app id is the numeric project id (or empty = disabled)", Export.app_id() == "" or Export.is_valid_app_id(Export.app_id()), Export.app_id())
