class_name Online
extends Node
## Friend rooms for Ludo, end to end: owns the NetClient, the Friends and Lobby sheets, and routes the room's
## messages to the app (main.gd) and the online LudoMatch. main.gd creates one (`online`) and calls:
##   open_friends()          Home's "Play with friends"
##   try_resume()            after launch: a room kept in Save.prefs.net_room is taken back (lobby or match)
##   leave()                 Leave match / Home from the result / Leave in the lobby
##   rematch()               the host's "Play again" on the result screen
## and implements on main: start_online(msg) (enter the Ludo screen with the server's start / sync), and
## online_host_changed(is_host) (the result screen's Play again).
## state: "idle" | "joining" | "resuming" | "lobby" | "match" | "over".
## Errors become friendly toasts (NetClient.error_text). Request errors during a match (stale, not_your_turn,
## bad_action) go to LudoMatch quietly: they are races, not mistakes.

signal state_changed(state: String)

const QUIET := ["stale", "not_your_turn", "bad_action", "rate"]

var app: Node
var net: NetClient
var state := "idle"
var friends: FriendsSheet
var lobby_sheet: LobbySheet


var _created := false                    # this client just made the room (applies the host's house rule once)

func _init(app_: Node = null, client: NetClient = null) -> void:
	app = app_
	net = client

func _ready() -> void:
	if net == null:
		net = NetClient.new()
		net.name = "Net"
	if net.get_parent() == null:
		add_child(net)
	net.welcome.connect(_on_welcome)
	net.lobby.connect(_on_lobby)
	net.start.connect(_on_start)
	net.sync.connect(_on_sync)
	net.act.connect(func(m: Dictionary): _to_match(m))
	net.over.connect(_on_over)
	net.turn.connect(func(m: Dictionary): _ludo_call("net_turn", m))
	net.presence.connect(func(m: Dictionary): _ludo_call("net_presence", m))
	net.error.connect(_on_error)
	_show_motd.call_deferred()
	net.status_changed.connect(_on_status)

func _set_state(s: String) -> void:
	if s != state:
		state = s
		state_changed.emit(s)

func in_match() -> bool:
	return state in ["match", "over"]

func is_host() -> bool:
	return net.is_host()


# ---------- the sheets ----------

## Home's "Play with friends". Already in a room: its lobby again.
func open_friends() -> void:
	if state == "lobby" and is_instance_valid(lobby_sheet):
		return
	if net.in_room() and state == "lobby":
		_open_lobby()
		return
	friends = FriendsSheet.new()
	friends.create_room.connect(_create)
	friends.join_room.connect(_join)
	friends.open(_layer())

func _create() -> void:
	if friends:
		friends.set_busy("create")
	var r: Dictionary = await net.create_room()
	if not bool(r.get("ok", false)):
		if str(r.get("error", "")) == "maintenance" and str(r.get("msg", "")) != "":
			if is_instance_valid(friends):
				friends.set_busy("")
			_set_state("idle")
			toast(str(r.msg), "bad")           # the admin's maintenance message
			return
		_join_failed(str(r.get("error", "no_connection")))
		return
	_created = true
	_connect(str(r.code))

func _join(code: String) -> void:
	if friends:
		friends.set_busy("join")
	var r: Dictionary = await net.check_room(code)
	if not bool(r.get("ok", false)):
		_join_failed(str(r.get("error", "no_connection")))
		return
	var mine: bool = NetClient.saved_room(net.prefs).get("code", "") == code   # our own seat: always welcome back
	if bool(r.get("started", false)) and not mine:
		_join_failed("started")
		return
	if int(r.get("members", 0)) >= LobbySheet.MAX and not mine:
		_join_failed("full")
		return
	_connect(code)

func _connect(code: String) -> void:
	_set_state("joining")
	net.join(code)

func _join_failed(code: String, msg := "") -> void:
	if is_instance_valid(friends):
		friends.set_busy("")
	_set_state("idle")
	toast(msg if msg != "" and code == "banned" else NetClient.error_text(code), "bad")

func _open_lobby() -> void:
	if is_instance_valid(friends):
		friends.close()
	friends = null
	if is_instance_valid(lobby_sheet) and not lobby_sheet.is_queued_for_deletion():
		return
	lobby_sheet = LobbySheet.new(net.code, net.member_id)
	lobby_sheet.settings_changed.connect(func(t: bool, p: bool): net.send_msg({t = "settings", teams = t, pair_ask = p}))
	lobby_sheet.start_pressed.connect(func(): net.send_msg({t = "start"}))
	lobby_sheet.leave_pressed.connect(_ask_leave_lobby)
	lobby_sheet.open(_layer())
	if not net.last_lobby.is_empty():
		lobby_sheet.update(net.last_lobby, net.is_host())
	lobby_sheet.set_status(net.status)

func _close_lobby() -> void:
	if is_instance_valid(lobby_sheet):
		lobby_sheet.close()
	lobby_sheet = null

func _ask_leave_lobby() -> void:
	if await Sheet.confirm(self, "Leave this room?", "Your friends can keep the room going.", "Leave", "Stay", true):
		leave()

## Leave the room for good (lobby, match or result).
func leave() -> void:
	net.leave()
	_close_lobby()
	_set_state("idle")

## The host's Play again after `over`.
func rematch() -> void:
	if net.is_host():
		net.send_msg({t = "start"})

## After launch: take back the room kept in Save.prefs.net_room (quietly; a room that's gone is forgotten).
func try_resume() -> bool:
	if state != "idle" or not net.resume():
		return false
	_set_state("resuming")
	return true


# ---------- messages ----------

func _on_welcome(_m: Dictionary) -> void:
	pass                                       # the lobby / sync that follows says where we are

func _on_lobby(m: Dictionary) -> void:
	match state:
		"joining":
			_set_state("lobby")
			if _created and net.is_host():       # a new room starts from the host's own house rule (Settings)
				_created = false
				var want := bool(net.prefs.get("pair_ask", true))
				if bool((m.get("settings", {}) as Dictionary).get("pair_ask", false)) != want:
					net.send_msg({t = "settings", teams = false, pair_ask = want})
			_open_lobby()
		"resuming":
			await get_tree().create_timer(0.4).timeout   # a match in progress sends its sync right behind
			if state != "resuming":
				return
			_set_state("lobby")
			if app == null or str(app.get("screen")) == "home":
				_open_lobby()                  # (elsewhere: "Play with friends" brings the lobby back)
		"over":
			_host_changed()
	if is_instance_valid(lobby_sheet):
		lobby_sheet.update(m, net.is_host())

func _on_start(m: Dictionary) -> void:
	_close_lobby()
	if is_instance_valid(friends):
		friends.close()
	_set_state("match")
	if app and app.has_method("start_online"):
		app.call("start_online", m, net)

func _on_sync(m: Dictionary) -> void:
	if state == "match" and _ludo_online():
		_to_match(m)
		return
	_on_start(m)                               # a resumed match (reconnect after a restart)

func _on_over(m: Dictionary) -> void:
	_to_match(m)
	_set_state("over")
	_host_changed()

func _to_match(m: Dictionary) -> void:
	_ludo_call("net_push", m)

func _on_error(m: Dictionary) -> void:
	var code := str(m.get("code", ""))
	match state:
		"joining":
			_join_failed(code, str(m.get("msg", "")))
			return
		"resuming":
			_set_state("idle")                 # the kept room is gone or full: forget it quietly
			return
	if code in QUIET:
		_ludo_call("net_error", m)
		return
	if code in NetClient.REMOVED and state in ["lobby", "match", "over"]:
		var why := str(m.get("msg", "")) if code == "banned" else ""
		toast(why if why != "" else NetClient.error_text(code), "bad")   # removed by an admin
		_close_lobby()
		_set_state("idle")
		if app and app.has_method("online_closed"):
			app.call("online_closed")
		return
	if code == "not_found" and state in ["lobby", "match", "over"]:
		toast("The room has closed.", "bad")
		_close_lobby()
		_set_state("idle")
		if app and app.has_method("online_closed"):
			app.call("online_closed")
		return
	toast(NetClient.error_text(code), "bad")
	if state == "over":
		_host_changed()                        # a refused rematch: Play again comes back

func _on_status(s: String) -> void:
	if is_instance_valid(lobby_sheet):
		lobby_sheet.set_status(s)
	_ludo_call("net_status", s)
	if s == "idle" and state in ["lobby", "match"] and not net.in_room():
		pass                                   # (leave() or a fatal error already moved the state on)

func _host_changed() -> void:
	if app and app.has_method("online_host_changed"):
		app.call("online_host_changed", net.is_host())


# ---------- helpers ----------

func _ludo_online() -> bool:
	var l: Variant = app.get("ludo") if app else null
	return l is Object and is_instance_valid(l) and bool((l as Object).get("online"))

func _ludo_call(method: String, arg: Variant) -> void:
	var l: Variant = app.get("ludo") if app else null
	if l is Object and is_instance_valid(l) and (l as Object).has_method(method) and _ludo_online():
		(l as Object).call(method, arg)

func _layer() -> Control:
	if app and app.get("sheet_layer") is Control:
		return app.sheet_layer
	return get_tree().root.get_child(0) as Control

## The admin console's message of the day: shown once per new message, on Home, a few seconds after launch.
func _show_motd() -> void:
	if app == null or Engine.is_editor_hint() or OS.has_feature("headless") or DisplayServer.get_name() == "headless":
		return
	await get_tree().create_timer(4.0).timeout
	var c: Dictionary = await net.fetch_config()
	var motd := str(c.get("motd", ""))
	if not bool(c.get("ok", false)) or motd == "" or str(net.prefs.get("motd_seen", "")) == motd:
		return
	while str(app.get("screen")) != "home":            # not over the splash, the welcome or a match
		await get_tree().create_timer(2.0).timeout
	net.prefs["motd_seen"] = motd
	if Engine.has_singleton("Save") or get_node_or_null("/root/Save"):
		get_node("/root/Save").save()
	var host: Node = app.get("ui_root") if app.get("ui_root") is Node else self
	Toast.show(host, motd, null, 5.0, "info")

func toast(text: String, kind := "info") -> void:
	var host: Node = app.get("ui_root") if app and app.get("ui_root") is Node else self
	Toast.show(host, text, null, 2.2, kind)
