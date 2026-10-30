class_name Online
extends Node
## Online play end to end (server/PROTOCOL.md): friend rooms and quick match, for Ludo and Snakes & Ladders. Owns
## the NetClient (room socket) and the NetQuick (matchmaker socket), the Friends, Lobby and Quick match sheets, and
## routes the room's messages to the online match (LudoMatch or SLMatch, whichever `start.game` / `sync.game` says).
## main.gd creates one (`online`) and calls:
##   open_friends(game)      Home's "Play with friends" (game: the new room's game; the host may change it)
##   open_quick(game)        Home's "Quick match": the table picker (players and coin table; < 100 coins: the "Out of
##                           coins" sheet first), then "Finding players…", then the match
##   try_resume()            after launch: a room kept in Save.prefs.net_room is taken back (lobby or match)
##   leave()                 Leave match / Home from the result / Leave in the lobby
##   rematch()               the result's Play again: the host's rematch (friend rooms), queue again (quick match)
##   is_host()               the result may offer Play again (the host of a friend room; anyone in a quick room)
## and uses on main: start_online(msg, net) (Ludo: enter the Ludo screen with the server's start / sync),
## _enter_sl() + sl.start_online(msg, net) (Snakes & Ladders; start_online_sl(msg, net) when main has it),
## online_host_changed(can_rematch) and online_closed(). When main has a `home` with the quick_match /
## play_friends signals, Online listens to them itself.
## state: "idle" | "joining" | "resuming" | "lobby" | "searching" | "match" | "over".
## Quick match: the matchmaker's `matched` joins the room with its token (NetClient.join(code, token, true)); no lobby
## comes; at `start` the sheet reveals the players, then the match opens (room messages meanwhile are held and
## played in order). Every seat that isn't a bot is a person here: nothing tells ghost seats apart.
## Errors become friendly toasts (NetClient.error_text) or the quick sheet's message. Request errors during a match
## (stale, not_your_turn, bad_action) go to the match quietly: they are races, not mistakes.
## Coin tables (server/ECONOMY_V1.md 3): the queue takes `table=`; `error coins` / `locked` come back as the picker's
## message (and the broke sheet when you are down to < 100 coins). Re-rolls (ECONOMY_V1.md 4): reroll_offer / hold /
## rerolled go to the match (net_reroll_offer / net_hold / net_rerolled); the re-roll errors (hold, reroll_used,
## reroll_closed, gems) to its net_error.
## Emotes (server/EMOTES.md): another member's {t: "emote", c, id} goes to the match's net_emote while it is up
## (dropped while it opens: a reaction is only worth showing now); emote_locked / emote_rate are ignored quietly.

signal state_changed(state: String)

const QUIET := ["stale", "not_your_turn", "bad_action", "rate", "hold", "reroll_used", "reroll_closed", "gems"]
const QUIET_EMOTE := ["emote_locked", "emote_rate"]   ## a refused emote: nothing to say, nothing to retry
const REFRESH_AFTER := [1.5, 6.0]          ## s after `over`: GET /v1/me (the server grants the rewards at over)

var app: Node
var net: NetClient
var quick_q: NetQuick
var state := "idle"
var friends: FriendsSheet
var lobby_sheet: LobbySheet
var quick_sheet: QuickSheet
var game := "ludo"                         ## the game of the room we are in (or joining)
var quick_cfg := {}                        ## {game, players, table} of the last quick search (Play again queues it again)
var last_tables := {}                      ## the last GET /v1/tables answer (the picker's flags, the broke bonus)
var broke_sheet: BrokeSheet
var coins_fn := Callable()                 ## tests, dev: () -> int in place of Save.profile.coins (the broke check, the picker)
var level_fn := Callable()                 ## tests, dev: () -> int in place of your level
var reveal_fast := false                   ## tests: the players are revealed at once

var _created := false                      # this client just made the room (applies the host's choices once)
var _friends_game := "ludo"                # the game a room we create starts with
var _held: Array = []                      # [method, msg] for the match, held while it opens / the players reveal
var _holding := false
var _stopped_in_bg := false                # a search was stopped because the app went to the background

func _init(app_: Node = null, client: NetClient = null) -> void:
	app = app_
	net = client

func _ready() -> void:
	if net == null:
		net = NetClient.new()
		net.name = "Net"
	if net.get_parent() == null:
		add_child(net)
	quick_q = NetQuick.new(net)
	quick_q.name = "Quick"
	add_child(quick_q)
	net.welcome.connect(_on_welcome)
	net.lobby.connect(_on_lobby)
	net.start.connect(_on_start)
	net.sync.connect(_on_sync)
	net.act.connect(func(m: Dictionary): _deliver("net_push", m))
	net.over.connect(_on_over)
	net.turn.connect(func(m: Dictionary): _deliver("net_turn", m))
	net.presence.connect(func(m: Dictionary): _deliver("net_presence", m))
	net.emote.connect(_on_emote)
	net.reroll_offer.connect(func(m: Dictionary): _deliver("net_reroll_offer", m))
	net.hold.connect(func(m: Dictionary): _deliver("net_hold", m))
	net.rerolled.connect(func(m: Dictionary): _deliver("net_rerolled", m))
	net.error.connect(_on_error)
	net.status_changed.connect(_on_status)
	quick_q.queued.connect(_on_queued)
	quick_q.matched.connect(_on_matched)
	quick_q.failed.connect(_on_quick_failed)
	_wire_home.call_deferred()
	_show_motd.call_deferred()

## Home's buttons (when main hasn't wired them itself).
func _wire_home() -> void:
	var h: Variant = app.get("home") if app else null
	if not h is Object or not is_instance_valid(h):
		return
	var home: Object = h
	if home.has_signal("quick_match") and not home.is_connected("quick_match", open_quick):
		home.connect("quick_match", open_quick)
	if home.has_signal("play_friends") and not home.is_connected("play_friends", open_friends):
		home.connect("play_friends", open_friends)

func _set_state(s: String) -> void:
	if s != state:
		state = s
		state_changed.emit(s)

func in_match() -> bool:
	return state in ["match", "over"]

func in_quick() -> bool:
	return net.quick and net.in_room()

## The result may offer Play again: the host of a friend room, anyone in a quick room (it queues again).
func is_host() -> bool:
	return net.is_host() or net.quick


# ---------- friend rooms ----------

## Home's "Play with friends". Already in a room: its lobby again. game: the game a new room starts with.
func open_friends(game_ := "") -> void:
	if state == "lobby" and is_instance_valid(lobby_sheet):
		return
	if net.in_room() and state == "lobby":
		_open_lobby()
		return
	_friends_game = game_ if game_ in ["ludo", "sl"] else _home_game()
	friends = FriendsSheet.new(_friends_game)
	friends.create_room.connect(_create)
	friends.join_room.connect(_join)
	friends.open(_layer())

## A notification's link to a room (room:CODE): rejoin it, the lobby or the match, through the usual join. Nothing
## when we are in a room or searching already.
func join_code(code: String) -> void:
	var c := NetClient.clean_code(code)
	if state != "idle" or not NetClient.valid_code(c):
		return
	if NetClient.saved_room(net.prefs).get("code", "") == c and try_resume():
		return
	_join(c)

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
	toast(msg if msg != "" and code in ["banned", "maintenance"] else NetClient.error_text(code), "bad")

func _open_lobby() -> void:
	if is_instance_valid(friends):
		friends.close()
	friends = null
	if is_instance_valid(lobby_sheet) and not lobby_sheet.is_queued_for_deletion():
		return
	var g := str((net.last_lobby.get("settings", {}) as Dictionary).get("game", game)) if net.last_lobby.get("settings") is Dictionary else game
	lobby_sheet = LobbySheet.new(net.code, net.member_id, g)
	lobby_sheet.settings_changed.connect(func(t: bool): net.send_msg({t = "settings", teams = t}))
	lobby_sheet.game_changed.connect(func(g2: String): net.send_msg({t = "settings", game = g2}))
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


# ---------- quick match ----------

## Home's "Quick match" for game ("ludo" | "sl"): the table picker (the last choices preselected). With fewer than 100
## coins (the cheapest table) the "Out of coins" sheet comes first: its way out (a top-up, or Practice) opens the picker.
func open_quick(game_ := "") -> void:
	var g := game_ if game_ in ["ludo", "sl"] else _home_game()
	if state == "searching" and is_instance_valid(quick_sheet):
		return
	if net.in_room() and state in ["lobby", "match"]:
		toast("Leave this room first.", "info")
		return
	if CoinTables.is_broke(_coins()) and not is_instance_valid(broke_sheet):
		_open_broke(g)
		return
	_open_quick_sheet(g)

func _coins() -> int:
	return int(coins_fn.call()) if coins_fn.is_valid() else int(Save.profile.get("coins", 0))

func _level() -> int:
	return int(level_fn.call()) if level_fn.is_valid() else Save.level_info(int(Save.profile.get("xp", 0))).level

## "Out of coins": a top-up opens the picker, Practice opens it on the free table.
func _open_broke(g: String) -> BrokeSheet:
	var b := BrokeSheet.new(last_tables.get("broke_bonus", {}) if last_tables.get("broke_bonus") is Dictionary else {})
	b.coins_fn = _coins
	b.refresh()
	broke_sheet = b
	b.practice_pressed.connect(func():
		net.prefs.quick_table = CoinTables.PRACTICE
		if is_instance_valid(quick_sheet):
			quick_sheet.set_wallet(_level(), _coins())
			quick_sheet.select_table(CoinTables.PRACTICE)
		else:
			_open_quick_sheet(g))
	b.topped_up.connect(func(_c: int):
		if is_instance_valid(quick_sheet):
			quick_sheet.set_wallet(_level(), _coins())
		else:
			_open_quick_sheet(g))
	b.closed.connect(func():
		if broke_sheet == b:
			broke_sheet = null)
	b.open(_layer())
	return b

func _open_quick_sheet(g: String) -> QuickSheet:
	if is_instance_valid(quick_sheet):
		quick_sheet.close()
	var players := int(net.prefs.get("quick_players", 2))
	quick_sheet = QuickSheet.new(g, players, str(net.prefs.get("quick_table", CoinTables.PRACTICE)))
	quick_sheet.set_wallet(_level(), _coins())
	if reveal_fast:
		quick_sheet.step_sec = 0.0
		quick_sheet.hold_sec = 0.0
	quick_sheet.find.connect(func(n: int): search(g, n))
	quick_sheet.cancel_pressed.connect(cancel_quick)
	quick_sheet.broke_requested.connect(func():
		if not is_instance_valid(broke_sheet):
			_open_broke(g))
	var s := quick_sheet
	quick_sheet.closed.connect(func():
		if quick_sheet == s:
			quick_sheet = null
			if state == "searching" or (state == "joining" and net.quick):
				cancel_quick())
	quick_sheet.open(_layer())
	_fetch_tables(quick_sheet)
	return quick_sheet

## The server's flags for the picker (unlocked / affordable) and the broke bonus. Quietly nothing offline.
func _fetch_tables(sheet: QuickSheet) -> void:
	var acc := Account.instance()
	if acc == null or not Account.wallet_active() or not acc.has_session():
		return
	var r: Dictionary = await acc.fetch_tables()
	if not bool(r.get("ok", false)):
		return
	last_tables = r
	if is_instance_valid(sheet):
		sheet.set_tables(r)

## Queue for a quick match (the sheet shows the search). players: 2 | 4 and the coin table (the sheet's pick, else
## the remembered one, else Practice); both are remembered for next time.
func search(g: String, players: int, table := "") -> void:
	if not NetQuick.valid(g, players):
		return
	if net.in_room():
		net.leave()                            # (Play again: the finished quick room)
	var t := table
	if t == "":
		t = quick_sheet.table if is_instance_valid(quick_sheet) else str(net.prefs.get("quick_table", CoinTables.PRACTICE))
	if not CoinTables.valid(t):
		t = CoinTables.PRACTICE
	quick_cfg = {game = g, players = players, table = t}
	game = g
	if int(net.prefs.get("quick_players", 0)) != players or str(net.prefs.get("quick_table", "")) != t:
		net.prefs.quick_players = players
		net.prefs.quick_table = t
		net._persist()
	_stopped_in_bg = false
	_set_state("searching")
	if is_instance_valid(quick_sheet):
		quick_sheet.set_searching(players)
	quick_q.search(g, players, t)

## Stop searching (Cancel, the sheet closed, Back, the app went to the background). A table already found: the
## room is left before the match starts.
func cancel_quick() -> void:
	if quick_q.searching():
		quick_q.cancel()
	if net.quick and net.in_room() and state in ["joining", "searching"]:
		net.leave()
	_held.clear()
	_holding = false
	if state in ["searching", "joining"]:
		_set_state("idle")
	_host_changed()                            # a result under the sheet: Play again comes back

func _on_queued(position: int, eta_s: int) -> void:
	if is_instance_valid(quick_sheet):
		quick_sheet.set_queued(position, eta_s)

func _on_matched(code: String, token: String) -> void:
	if state != "searching":
		return
	_set_state("joining")
	if is_instance_valid(quick_sheet):
		quick_sheet.set_matched()
	net.join(code, token, true)

func _on_quick_failed(code: String, msg: String) -> void:
	if state not in ["searching", "joining"]:
		return
	_set_state("idle")
	var text := msg if msg != "" and code in ["banned", "maintenance"] else QuickSheet.fail_text(code, quick_q.fail_info)
	if is_instance_valid(quick_sheet):
		if code in ["coins", "locked"]:
			quick_sheet.set_wallet(_level(), _coins())       # the table that was refused greys out
		quick_sheet.set_error(text)
	else:
		toast(text, "bad")
	if code == "coins" and CoinTables.is_broke(_coins()) and not is_instance_valid(broke_sheet):
		_open_broke(game)                      # out of coins: the way back
	_host_changed()


# ---------- the room ----------

## Leave the room for good (lobby, match or result). A search stops too.
func leave() -> void:
	if quick_q.searching():
		quick_q.cancel()
	net.leave()
	_close_lobby()
	_held.clear()
	_holding = false
	_set_state("idle")

## The result's Play again: the host's rematch in a friend room; queue again with the same table in a quick room.
func rematch() -> void:
	if net.quick:
		var cfg := quick_cfg
		if cfg.is_empty():
			cfg = {game = game, players = int(net.prefs.get("quick_players", 2)), table = str(net.prefs.get("quick_table", CoinTables.PRACTICE))}
		net.leave()
		_set_state("idle")
		if app and app.has_method("go_home"):
			app.call("go_home")                # the search runs over Home (Cancel leaves you there)
		var tbl := str(cfg.get("table", CoinTables.PRACTICE))
		_open_quick_sheet(str(cfg.game))
		if not _table_playable(tbl, int(cfg.players)):
			return                             # can't pay or unlock that table now: the picker, to choose again
		search(str(cfg.game), int(cfg.players), tbl)
		return
	if net.is_host():
		net.send_msg({t = "start"})

## The table can be played now (level and coins, as the picker would say).
func _table_playable(id: String, size: int) -> bool:
	for r: Dictionary in CoinTables.rows(size, _level(), _coins(), last_tables):
		if r.id == id:
			return bool(r.ok)
	return false

## After launch: take back the room kept in Save.prefs.net_room (quietly; a room that's gone is forgotten).
func try_resume() -> bool:
	if state != "idle" or not net.resume():
		return false
	_set_state("resuming")
	return true

func _on_welcome(_m: Dictionary) -> void:
	pass                                       # the lobby / start / sync that follows says where we are

func _on_lobby(m: Dictionary) -> void:
	if m.get("settings") is Dictionary:
		game = str((m.settings as Dictionary).get("game", game))
	match state:
		"joining":
			_set_state("lobby")
			if _created and net.is_host():       # a new room starts from the host's choice of game ("Ask before
				_created = false                 # pairing" is everyone's own: each hello carries it)
				var st: Dictionary = m.get("settings", {}) if m.get("settings") is Dictionary else {}
				if str(st.get("game", "ludo")) != _friends_game:
					net.send_msg({t = "settings", teams = false, game = _friends_game})
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
	game = str(m.get("game", "ludo"))
	var revealing := is_instance_valid(quick_sheet) and net.quick and str(m.get("t", "start")) == "start"
	_set_state("match")
	_holding = true                            # room messages wait until the match is up
	if revealing:
		var s := quick_sheet
		await s.reveal(m.get("seats", []) if m.get("seats") is Array else [], NetReplica.color_of(m.get("seats", []), net.member_id))
		if state != "match":
			return                             # cancelled meanwhile
		if is_instance_valid(s):
			s.close()
	await _enter_match(m)

## Opens the match screen for the game the server says, then plays what arrived meanwhile.
func _enter_match(m: Dictionary) -> void:
	_holding = true
	if str(m.get("game", "ludo")) == "sl":
		if app and app.has_method("start_online_sl"):
			app.call("start_online_sl", m, net)
		elif app and app.has_method("_enter_sl") and app.get("sl") is Object:
			await app.call("_enter_sl")
			if str(app.get("screen")) == "sl" and state in ["match", "over"]:
				(app.get("sl") as Object).call("start_online", m, net)
	elif app and app.has_method("start_online"):
		app.call("start_online", m, net)
	_holding = false
	var held := _held
	_held = []
	for h: Array in held:
		_match_call(str(h[0]), h[1])

func _on_sync(m: Dictionary) -> void:
	if state in ["match", "over"] and (_match() != null or _holding):
		_deliver("net_push", m)
		return
	_on_start(m)                               # a resumed match (reconnect after a restart)

func _on_over(m: Dictionary) -> void:
	_deliver("net_push", m)
	_set_state("over")
	_host_changed()
	_refresh_profile()

## A message for the match: now, or held until the match is up.
func _deliver(method: String, m: Variant) -> void:
	if _holding:
		_held.append([method, m])
		return
	_match_call(method, m)

## Another member's emote: to the match on screen (lobby emotes, c = -1, aren't shown).
func _on_emote(m: Dictionary) -> void:
	if _holding or not in_match() or int(m.get("c", -1)) < 0:
		return
	_match_call("net_emote", m)

func _on_error(m: Dictionary) -> void:
	var code := str(m.get("code", ""))
	if code in QUIET_EMOTE:
		return
	match state:
		"joining":
			if net.quick:
				_on_quick_failed("no_connection" if code == "not_found" else code, str(m.get("msg", "")))
				return
			_join_failed(code, str(m.get("msg", "")))
			return
		"resuming":
			_set_state("idle")                 # the kept room is gone or full: forget it quietly
			return
	if code in QUIET:
		_match_call("net_error", m)
		return
	if code in NetClient.REMOVED and state in ["lobby", "match", "over"]:
		var why := str(m.get("msg", "")) if code == "banned" else ""
		toast(why if why != "" else NetClient.error_text(code), "bad")   # removed by an admin
		_close_lobby()
		_set_state("idle")
		_closed()
		return
	if code == "not_found" and state in ["lobby", "match", "over"]:
		var was := state
		if was != "over":                      # (a finished room may be deleted under the result: nothing to say)
			toast("The room has closed.", "bad")
		_close_lobby()
		_set_state("idle")
		if was != "over":
			_closed()
		return
	toast(NetClient.error_text(code), "bad")
	if state == "over":
		_host_changed()                        # a refused rematch: Play again comes back

func _on_status(s: String) -> void:
	if is_instance_valid(lobby_sheet):
		lobby_sheet.set_status(s)
	_match_call("net_status", s)

func _host_changed() -> void:
	if app and app.has_method("online_host_changed"):
		app.call("online_host_changed", is_host())

## The room is gone under us: back home (main.online_closed for Ludo; an S&L match goes home here when main
## doesn't know about it).
func _closed() -> void:
	if app and app.has_method("online_closed"):
		app.call("online_closed")
	var sl: Variant = app.get("sl") if app else null
	if sl is Object and is_instance_valid(sl) and bool((sl as Object).get("online")) and app.has_method("go_home"):
		app.call("go_home")

## The server granted this match's rewards at `over`: read the profile back (twice: the grant may land late).
func _refresh_profile() -> void:
	var acc := Account.instance()
	if acc == null or not acc.has_session() or not is_inside_tree():
		return
	for sec in REFRESH_AFTER:
		await get_tree().create_timer(sec).timeout
		if not is_instance_valid(acc) or not acc.has_session():
			return
		await acc.refresh_me()

## A quick search stops when the app goes to the background (the sheet goes back to the picker); a table that was
## already found is kept (the room reconnects).
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED and state == "searching":
		_stopped_in_bg = true
		cancel_quick()
		if is_instance_valid(quick_sheet):
			quick_sheet.set_error("The search stopped while the app was in the background.")


# ---------- helpers ----------

## The online match (LudoMatch or SLMatch whose `online` is on), or null.
func _match() -> Object:
	for key in ["ludo", "sl"]:
		var l: Variant = app.get(key) if app else null
		if l is Object and is_instance_valid(l) and bool((l as Object).get("online")):
			return l
	return null

func _match_call(method: String, arg: Variant) -> void:
	var l := _match()
	if l and l.has_method(method):
		l.call(method, arg)

func _home_game() -> String:
	var h: Variant = app.get("home") if app else null
	if h is Object and is_instance_valid(h) and str((h as Object).get("game")) in ["ludo", "sl"]:
		return str((h as Object).get("game"))
	return "ludo"

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
