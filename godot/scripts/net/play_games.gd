class_name PlayGames
extends Node
## Google Play Games Services v2 (server/ONLINE_V2.md section 7): a thin wrapper over the "PlayGamesPlugin" Android
## plugin singleton (godot/android/plugins/play_games). Everywhere the plugin is missing (desktop, headless, web,
## the non-Gradle "Android Emulator" preset) or disabled (empty ludo_zing/play_games/app_id at export, no Play
## services) it is a safe stub: is_available() is false and every request answers with its failure signal and
## the code "unavailable". Results always arrive later (deferred), never inside the call that asked.
##
##   var pg := PlayGames.new(); add_child(pg)     # initializes, then checks the automatic sign-in
##   pg.signed_in.connect(...)                     # {display_name, player_id}; for UI only (the server derives ids)
##   pg.sign_in()                                  # the manual "Sign in with Play Games" button
##   pg.request_server_auth_code()                 # -> server_auth_code(code) for POST /v1/auth/google
##   pg.submit_score(board_id, value); pg.show_leaderboards()
##
## Error codes: "unavailable" (stub or disabled), "canceled", "not_signed_in", "no_web_client_id",
## "api:<CommonStatusCodes>", "error:<message>", "busy" (a sign-in is already running).

## The automatic sign-in check (launch) or a manual sign_in() succeeded and the player info is in `player`.
signal signed_in(player: Dictionary)
## sign_in() failed: "canceled", "unavailable", "api:<n>", ...
signal sign_in_failed(code: String)
## The automatic check found no signed-in player (show the manual button). Not an error.
signal signed_out
signal server_auth_code(code: String)
signal server_auth_code_failed(code: String)
signal score_submitted(board_id: String, ok: bool, error: String)
signal achievement_unlocked(achievement_id: String, ok: bool, error: String)
## A Play Games screen (leaderboards / achievements) could not be shown.
signal ui_failed(kind: String, error: String)
## A Play Games screen that was shown has been closed (the game can refresh).
signal ui_closed(kind: String)

## Not "PlayGames": an Engine singleton of that name would shadow this class_name in every script.
const SINGLETON := "PlayGamesPlugin"
const WEB_CLIENT_SETTING := "ludo_zing/play_games/web_client_id"
const UNAVAILABLE := "unavailable"

## Signed-in player {display_name, player_id}, or {} when not signed in.
var player: Dictionary = {}
var is_signed_in := false
## Why it is unavailable: "" (available) | "no_plugin" | "no_app_id" | "no_play_services:<n>" | "error:<m>".
var reason := "no_plugin"
## Check the automatic sign-in when entering the tree (launch). Off in tests.
var auto_check := true

var _pg: Object = null
var _deferred := true
var _enabled := false
var _signing_in := false        # a sign-in (automatic check or manual) is waiting for the player info
var _manual := false            # ...and it was the manual button (failures go to sign_in_failed)

## `singleton`: the Android plugin object; null = Engine.get_singleton("PlayGamesPlugin") when it exists. Tests pass a
## fake with the same methods and signals, and `deferred` false to get the answers inside the call.
func _init(singleton: Object = null, deferred := true) -> void:
	_deferred = deferred
	if singleton == null and Engine.has_singleton(SINGLETON):
		singleton = Engine.get_singleton(SINGLETON)
	_pg = singleton
	if _pg == null:
		return
	_connect("auth_checked", _on_auth_checked)
	_connect("sign_in_completed", _on_sign_in_completed)
	_connect("server_auth_code_completed", _on_server_auth)
	_connect("player_info_completed", _on_player_info)
	_connect("score_submitted", _on_score)
	_connect("achievement_unlocked", _on_achievement)
	_connect("ui_completed", _on_ui)
	_connect("ui_closed", _on_ui_closed)
	_enabled = bool(_pg.call("initialize"))
	if _enabled:
		reason = ""
	else:
		var st: Dictionary = _pg.call("getStatus")
		reason = str(st.get("error", ""))
		if reason.is_empty():
			reason = "no_app_id" if not st.get("app_id_set", false) else "disabled"

func _ready() -> void:
	if auto_check:
		check_signed_in()

## True on Android with the plugin built in, an APP_ID configured and Play services usable.
func is_available() -> bool:
	return _enabled

## The plugin's raw status (Android) or {available = false, reason = "no_plugin"}.
func status() -> Dictionary:
	var st: Dictionary = {}
	if _pg != null:
		st = _pg.call("getStatus")
	st.available = _enabled
	st.reason = reason
	return st

## The SDK signs in by itself at launch: ask for the result. -> signed_in(player) or signed_out.
func check_signed_in() -> void:
	if not _enabled:
		_later(signed_out.emit)
		return
	if _signing_in:
		return
	_signing_in = true
	_manual = false
	_pg.call("isAuthenticated")

## Manual sign-in (button). -> signed_in(player) or sign_in_failed(code).
func sign_in() -> void:
	if not _enabled:
		_later(sign_in_failed.emit.bind(UNAVAILABLE))
		return
	if _signing_in:
		if _manual:
			_later(sign_in_failed.emit.bind("busy"))
			return
		_manual = true                       # the automatic check is running: its result answers the button
		return
	_signing_in = true
	_manual = true
	_pg.call("signIn")

## One-time server auth code for the game server. `web_client_id` "" = the project setting
## ludo_zing/play_games/web_client_id. -> server_auth_code(code) or server_auth_code_failed(code).
func request_server_auth_code(web_client_id := "", force_refresh_token := false) -> void:
	if not _enabled:
		_later(server_auth_code_failed.emit.bind(UNAVAILABLE))
		return
	var id := web_client_id if web_client_id != "" else str(ProjectSettings.get_setting(WEB_CLIENT_SETTING, ""))
	if id.strip_edges().is_empty():
		_later(server_auth_code_failed.emit.bind("no_web_client_id"))
		return
	_pg.call("requestServerSideAccess", id.strip_edges(), force_refresh_token)

## -> score_submitted(board_id, ok, error).
func submit_score(board_id: String, value: int) -> void:
	if not _enabled:
		_later(score_submitted.emit.bind(board_id, false, UNAVAILABLE))
		return
	_pg.call("submitScore", board_id, value)

## The Play Games screen with every leaderboard (or one, with `board_id`). -> ui_failed / ui_closed.
func show_leaderboards(board_id := "") -> void:
	var kind := "leaderboards" if board_id.is_empty() else "leaderboard"
	if not _enabled:
		_later(ui_failed.emit.bind(kind, UNAVAILABLE))
		return
	if board_id.is_empty():
		_pg.call("showAllLeaderboards")
	else:
		_pg.call("showLeaderboard", board_id)

func show_achievements() -> void:
	if not _enabled:
		_later(ui_failed.emit.bind("achievements", UNAVAILABLE))
		return
	_pg.call("showAchievements")

## -> achievement_unlocked(achievement_id, ok, error).
func unlock_achievement(achievement_id: String) -> void:
	if not _enabled:
		_later(achievement_unlocked.emit.bind(achievement_id, false, UNAVAILABLE))
		return
	_pg.call("unlockAchievement", achievement_id)


# ---------- plugin signals ----------

func _on_auth_checked(authenticated: bool, error: String) -> void:
	if authenticated:
		_pg.call("getPlayerInfo")
		return
	_finish_sign_in(false, "not_signed_in" if error.is_empty() else _code(error))

func _on_sign_in_completed(ok: bool, error: String) -> void:
	if ok:
		_pg.call("getPlayerInfo")
	else:
		_finish_sign_in(false, _code(error))

func _on_player_info(ok: bool, info: Dictionary, error: String) -> void:
	if ok:
		player = {display_name = str(info.get("display_name", "")), player_id = str(info.get("player_id", ""))}
		is_signed_in = true
		_signing_in = false
		_manual = false
		signed_in.emit(player)
	else:
		_finish_sign_in(false, _code(error))

func _on_server_auth(ok: bool, code: String, error: String) -> void:
	if ok:
		server_auth_code.emit(code)
	else:
		server_auth_code_failed.emit(_code(error))

func _on_score(id: String, ok: bool, error: String) -> void:
	score_submitted.emit(id, ok, _code(error))

func _on_achievement(id: String, ok: bool, error: String) -> void:
	achievement_unlocked.emit(id, ok, _code(error))

func _on_ui(kind: String, ok: bool, error: String) -> void:
	if not ok:
		ui_failed.emit(kind, _code(error))

func _on_ui_closed(kind: String) -> void:
	ui_closed.emit(kind)

func _finish_sign_in(_ok: bool, code: String) -> void:
	var manual := _manual
	_signing_in = false
	_manual = false
	is_signed_in = false
	player = {}
	if manual:
		sign_in_failed.emit(code)
	else:
		signed_out.emit()


# ---------- helpers ----------

func _connect(sig: String, fn: Callable) -> void:
	if _pg.has_signal(sig):
		# plugin signals arrive on the main loop already; deferred keeps every answer out of the asking call
		_pg.connect(sig, fn, CONNECT_DEFERRED if _deferred else 0)
	else:
		push_warning("PlayGames: plugin has no signal %s" % sig)

func _code(error: String) -> String:
	return UNAVAILABLE if error == "disabled" else error

func _later(fn: Callable) -> void:
	if _deferred:
		fn.call_deferred()
	else:
		fn.call()
