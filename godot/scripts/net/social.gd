class_name Social
extends Node
## Recent players, friends and game invites (server/PROTOCOL.md "Recent players, friends and invites"). main.gd owns
## one (`social`); sheets reach it through Social.instance().
##   - The lists the Friends sheet shows: GET /v1/social (kept CACHE_SEC), changed when they change.
##   - Friends are one-way (a favourites list: nobody is asked or told). Long-press a player (a list row, a lobby
##     member, a match tile, a leaderboard row) and ask_friend() asks "Add to friends?" / "Remove?".
##   - Invite (a list row's button) brings that person into the friend room you are in; in none, Online makes one
##     first and its lobby opens. The server pushes the invite to their phones.
##   - The invites to you: GET /v1/social/invites at launch and resume, every POLL_SEC while Home is idle, and at once
##     when an invite push arrives with the app open (Notifications hands it over instead of a toast). The newest one
##     not seen yet becomes the InviteBanner (Join: accept, then the usual join of that room; Not now: decline).
##   - Settings' "Invites from players" (Save.prefs.invites, default on), sent to the server; offline, it is sent again
##     with the next list (Save.prefs.invites_sync).
## Everything answers {ok, error, ...} and stays quiet offline: nothing here blocks play.
##
##   social.refresh()                   the lists (from the cache when fresh; force for a new read)
##   social.ask_friend(host, person)    the long-press question, then the call and a toast
##   social.ask_seat(host, code, id, n) the same for a room member (lobby, match tile: the server knows who sits there)
##   social.invite(person, game)        -> {ok, error}
##   social.poll()                      the pending invites -> the banner
##   social.set_invites(on)             Settings' switch
## Tests: http_fn (method, path, body) -> {ok, status, data, error} stands in for the Account (NetFake.Social.http),
## clock (() -> unix s) for the system clock.

## The lists (recent, friends) or the invites setting changed.
signal changed
## An invite was sent (uid): rows show "Invited".
signal invited(uid: String)

const CACHE_SEC := 30.0
const POLL_SEC := 30.0
const PATH := "/v1/social"

static var _inst: Social = null

var app: Node                            ## main (screen, ui_root, sheet_layer, online, hud, ludo, sl)
var http_fn := Callable()                ## tests, dev: (method, path, body) -> {ok, status, data, error}
var clock := Callable()                  ## tests: () -> unix seconds
var poll_sec := POLL_SEC                 ## 0: no timer (tests)
var recent: Array = []                   ## [{uid, name, avatar, frame, level, game, played_at, friend}]
var friends: Array = []                  ## [{uid, name, avatar, frame, level, added_at, game, played_at}]
var state := ""                          ## "" (never read) | "loading" | "ok" | "offline" | "error"
var invited_until := {}                  ## uid -> unix s until which its row says "Invited"
var pending: Array = []                  ## invites waiting for the banner (newest first)
var banner: InviteBanner
var last_toast := ""                     ## tests: the last thing said

var _loaded_ms := -1
var _loading := false
var _seen := {}                          # invite ids already shown (or answered)
var _polling := false
var _timer: Timer


func _init(app_: Node = null) -> void:
	app = app_

func _enter_tree() -> void:
	_inst = self

func _exit_tree() -> void:
	if _inst == self:
		_inst = null

## The Social of this run, or null (previews and tests without one).
static func instance() -> Social:
	return _inst if is_instance_valid(_inst) else null

## Tests: make this the current one without a scene tree (null clears it).
static func set_instance(s: Social) -> void:
	_inst = s

func _ready() -> void:
	if poll_sec > 0.0:
		_timer = Timer.new()
		_timer.wait_time = poll_sec
		_timer.timeout.connect(_on_tick)
		add_child(_timer)
		_timer.start()
	var acc := _account()
	if acc != null:
		acc.signed_in_changed.connect(_on_signed_in)
	_wire_matches.call_deferred()

## Unix seconds (the test clock when set): what "Invited" and the lists' "4 min ago" are measured against.
func now() -> int:
	return int(clock.call()) if clock.is_valid() else int(Time.get_unix_time_from_system())

func _account() -> Account:
	var a: Variant = app.get("account") if app != null else null
	return a as Account if a is Account and is_instance_valid(a) else Account.instance()

func _online() -> Online:
	var o: Variant = app.get("online") if app != null else null
	return o as Online if o is Online and is_instance_valid(o) else null

## Whether the server can be asked (an account, or the test's http_fn).
func available() -> bool:
	if http_fn.is_valid():
		return true
	var acc := _account()
	return acc != null and acc.enabled and not acc.banned

## One call: {ok, status, data, error} (error "offline" without an account or a connection).
func request(method: int, path: String, body: Variant = null) -> Dictionary:
	if http_fn.is_valid():
		var out: Variant = await http_fn.call(method, path, body)
		return out if out is Dictionary else {ok = false, status = 0, data = {}, error = "offline"}
	var acc := _account()
	if acc == null or not acc.enabled:
		return {ok = false, status = 0, data = {}, error = "offline"}
	if not await acc.ensure_session():
		return {ok = false, status = 0, data = {}, error = "offline"}
	return await acc.request(method, path, body)


# ---------- the lists ----------

## The lists (GET /v1/social): from the cache when it is fresh (unless force). {ok, error}.
func refresh(force := false) -> Dictionary:
	if not force and state == "ok" and _loaded_ms >= 0 and Time.get_ticks_msec() - _loaded_ms < CACHE_SEC * 1000.0:
		return {ok = true, error = ""}
	if _loading:
		while _loading:
			await get_tree().process_frame
		return {ok = state == "ok", error = "" if state == "ok" else state}
	_loading = true
	if state != "ok":
		state = "loading"
		changed.emit()
	var r: Dictionary = await request(HTTPClient.METHOD_GET, PATH)
	_loading = false
	if not r.ok:
		if state != "ok":                    # a failed refresh keeps what is on screen
			state = "offline" if r.error == "offline" else "error"
			changed.emit()
		return {ok = false, error = r.error}
	var d: Dictionary = r.data
	recent = (d.get("recent", []) as Array).duplicate(true) if d.get("recent") is Array else []
	friends = (d.get("friends", []) as Array).duplicate(true) if d.get("friends") is Array else []
	var prefs: Dictionary = d.get("prefs", {}) if d.get("prefs") is Dictionary else {}
	if bool(Save.prefs.get("invites_sync", false)):
		_send_invites_pref()                 # a change made offline goes now
	elif prefs.get("invites") is bool:
		Save.prefs.invites = bool(prefs.invites)
	state = "ok"
	_loaded_ms = Time.get_ticks_msec()
	changed.emit()
	return {ok = true, error = ""}

func is_friend(uid: String) -> bool:
	for f: Dictionary in friends:
		if str(f.get("uid", "")) == uid:
			return true
	return false

## Whether a row's Invite should say "Invited" now.
func was_invited(uid: String) -> bool:
	return int(invited_until.get(uid, 0)) > now()

func _set_recent_friend(uid: String, on: bool) -> void:
	for p: Dictionary in recent:
		if str(p.get("uid", "")) == uid:
			p.friend = on

func _took_friend(p: Dictionary) -> void:
	var uid := str(p.get("uid", ""))
	if uid == "" or is_friend(uid):
		return
	var f := {uid = uid, name = p.get("name", "Player"), avatar = p.get("avatar", ""), frame = p.get("frame", ""),
		level = p.get("level", 1), added_at = now(), game = null, played_at = null}
	for r: Dictionary in recent:                 # the last match together, as the server lists it
		if str(r.get("uid", "")) == uid:
			f.game = r.get("game")
			f.played_at = r.get("played_at")
	friends.push_front(f)
	# the server's order: the last match together (or when added), newest first
	var key := func(x: Dictionary) -> int: return _int(x.get("played_at"), _int(x.get("added_at"), 0))
	friends.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return key.call(a) > key.call(b))
	_set_recent_friend(uid, true)
	changed.emit()

## POST /v1/social/friends {uid}. {ok, error, friend}.
func add_friend(p: Dictionary) -> Dictionary:
	var r: Dictionary = await request(HTTPClient.METHOD_POST, PATH + "/friends", {uid = str(p.get("uid", ""))})
	if r.ok and r.data.get("friend") is Dictionary:
		_took_friend(r.data.friend)
	return {ok = r.ok, error = r.error, friend = r.data.get("friend", {})}

## POST /v1/social/friends {code, member}: the person at that member id of the room you are in.
func add_from_room(code: String, member: int) -> Dictionary:
	var r: Dictionary = await request(HTTPClient.METHOD_POST, PATH + "/friends", {code = code, member = member})
	if r.ok and r.data.get("friend") is Dictionary:
		_took_friend(r.data.friend)
	return {ok = r.ok, error = r.error, friend = r.data.get("friend", {})}

## DELETE /v1/social/friends {uid}.
func remove_friend(uid: String) -> Dictionary:
	var r: Dictionary = await request(HTTPClient.METHOD_DELETE, PATH + "/friends", {uid = uid})
	if r.ok:
		friends = friends.filter(func(f: Dictionary) -> bool: return str(f.get("uid", "")) != uid)
		_set_recent_friend(uid, false)
		changed.emit()
	return {ok = r.ok, error = r.error}

## The long-press question for a person with a handle: add them, or (a friend already) remove them; then a toast.
func ask_friend(host: Node, p: Dictionary) -> void:
	var uid := str(p.get("uid", ""))
	if uid == "" or not available():
		return
	var name := L10n.seat_name(str(p.get("name", "Player")))
	if is_friend(uid):
		if not await Sheet.confirm(host, tr("Remove from friends?"), tr("%s leaves your friends list. They aren’t told.") % name,
				tr("Remove"), tr("Keep"), true):
			return
		var r := await remove_friend(uid)
		toast(host, tr("%s removed from friends") % name if r.ok else _error_text(str(r.error)), "info" if r.ok else "bad")
		return
	if not await Sheet.confirm(host, tr("Add to friends?"), _add_text(name), tr("Add friend"), tr("Cancel")):
		return
	var r2 := await add_friend(p)
	_added_toast(host, name, r2)

## A row's star: a friend already -> the Remove question (as a long-press); else added at once (one tap), then a toast.
func star(host: Node, p: Dictionary) -> void:
	var uid := str(p.get("uid", ""))
	if uid == "" or not available():
		return
	if is_friend(uid):
		await ask_friend(host, p)
		return
	var r := await add_friend(p)
	_added_toast(host, L10n.seat_name(str(p.get("name", "Player"))), r)

## The same for someone in the room you are in (a lobby member, a match tile): the server finds who sits there.
func ask_seat(host: Node, code: String, member: int, name_: String) -> void:
	if code == "" or member < 1 or not available():
		return
	var name := L10n.seat_name(name_)
	if not await Sheet.confirm(host, tr("Add to friends?"), _add_text(name), tr("Add friend"), tr("Cancel")):
		return
	var r := await add_from_room(code, member)
	_added_toast(host, name, r)

func _add_text(name: String) -> String:
	return tr("Invite %s to your games from your friends list. They aren’t told you added them.") % name

func _added_toast(host: Node, name: String, r: Dictionary) -> void:
	if r.ok:
		toast(host, tr("%s added to friends") % name, "good")
	else:
		toast(host, _error_text(str(r.error)), "bad")

static func _error_text(code: String) -> String:
	match code:
		"offline":
			return L10n.t("Connect to the internet to add friends.")
		"friends_full":
			return L10n.t("Your friends list is full. Remove someone first.")
		"not_found":
			return L10n.t("That player can’t be added right now.")
	return L10n.t("Something went wrong. Please try again.")


# ---------- invites (sending) ----------

## Invite a person from the lists into your friend room. In no room: Online makes one first (its lobby opens), with
## `game` (default: Home's). {ok, error}: offline, busy (a match or a search is on), room (no room could be made),
## not_found, rate, not_in_room, room_full, started.
func invite(p: Dictionary, game := "") -> Dictionary:
	var uid := str(p.get("uid", ""))
	var name := L10n.seat_name(str(p.get("name", "Player")))
	var o := _online()
	if uid == "" or o == null or not available():
		return _invite_done({ok = false, error = "offline"}, name, uid)
	if o.state == "idle":
		if not await o.create_room(game):
			return {ok = false, error = "room"}     # (Online said why)
	elif o.state != "lobby" or o.net.quick or not o.net.in_room():
		return _invite_done({ok = false, error = "busy"}, name, uid)
	var r: Dictionary = await request(HTTPClient.METHOD_POST, PATH + "/invites", {uid = uid, code = o.net.code})
	var out := {ok = r.ok, error = r.error}
	if r.ok:
		invited_until[uid] = _int(r.data.get("expires_at"), now() + 600)
	elif r.error == "rate":
		out.scope = str(r.data.get("scope", "total"))
		if out.scope == "person":
			invited_until[uid] = _int(r.data.get("retry_at"), now() + 600)
	return _invite_done(out, name, uid)

func _invite_done(r: Dictionary, name: String, uid: String) -> Dictionary:
	var host := _toast_host()
	if r.ok:
		toast(host, tr("Invite sent to %s") % name, "good")
		invited.emit(uid)
		return r
	var scope := str(r.get("scope", ""))
	var text := invite_error_text(str(r.error), scope)
	if r.error == "rate" and scope == "person":
		text = text % name                       # "You invited Rafi a moment ago."
		invited.emit(uid)
	toast(host, text, "info" if r.error in ["rate", "busy"] else "bad")
	return r

static func invite_error_text(code: String, scope := "") -> String:
	match code:
		"offline":
			return L10n.t("Connect to the internet to invite friends.")
		"busy":
			return L10n.t("Finish this game first.")
		"rate":
			return L10n.t("You invited %s a moment ago.") if scope == "person" else L10n.t("That’s a lot of invites. Try again later.")
		"not_found":
			return L10n.t("You can invite players you’ve played with or added.")
		"room_full":
			return L10n.t("Your room is full.")
		"started":
			return L10n.t("Your game has started.")
		"not_in_room":
			return L10n.t("Make a room first.")
	return L10n.t("Something went wrong. Please try again.")


# ---------- invites (to you) ----------

func _on_tick() -> void:
	if app != null and str(app.get("screen")) == "home" and _app_focused():
		poll()

func _app_focused() -> bool:
	return app == null or not "_app_focused" in app or bool(app.get("_app_focused"))

func _on_signed_in() -> void:
	if Account.session() != "":
		poll()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED:
		poll.call_deferred()

## GET /v1/social/invites: the invites not seen yet go into `pending` (newest first); the banner shows the first.
func poll() -> void:
	if _polling or not available() or (not http_fn.is_valid() and Account.session() == ""):
		return
	_polling = true
	var r: Dictionary = await request(HTTPClient.METHOD_GET, PATH + "/invites")
	_polling = false
	if not r.ok or not r.data.get("invites") is Array:
		return
	var t := now()
	var mine := _room_code()
	for inv: Variant in r.data.invites:
		if not inv is Dictionary:
			continue
		var d: Dictionary = inv
		var id := str(d.get("id", ""))
		if id == "" or _seen.has(id) or _int(d.get("expires_at"), 0) <= t or str(d.get("code", "")) == mine:
			continue
		if pending.any(func(x: Dictionary) -> bool: return str(x.get("id", "")) == id):
			continue
		pending.append(d)
	pending.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _int(a.get("sent_at"), 0) > _int(b.get("sent_at"), 0))
	show_next()

## An invite push arrived while the app is open: read the list now (the banner, not a toast).
func on_push(_data: Dictionary) -> void:
	poll()

## The room of a tapped invite push (or any room link): its pending invite is accepted (quietly; the join is Online's).
func opened_room(code: String) -> void:
	if not available() or code == "":
		return
	for d: Dictionary in pending.duplicate():
		if str(d.get("code", "")) == code:
			_seen[str(d.get("id", ""))] = true
			pending.erase(d)
	if is_instance_valid(banner) and str(banner.invite.get("code", "")) == code:
		_hide_banner()
	request(HTTPClient.METHOD_POST, PATH + "/invites/accept", {code = code})

## Show the banner for the first pending invite when the app can (Home, not in a match or a search).
func show_next() -> void:
	if is_instance_valid(banner) or pending.is_empty() or not _can_show():
		return
	var t := now()
	while not pending.is_empty() and _int((pending[0] as Dictionary).get("expires_at"), 0) <= t:
		pending.pop_front()
	if pending.is_empty():
		return
	var d: Dictionary = pending.pop_front()
	_seen[str(d.get("id", ""))] = true
	banner = InviteBanner.new(d, t)
	banner.join_pressed.connect(_on_join.bind(d))
	banner.later_pressed.connect(_on_later.bind(d))
	banner.expired.connect(_on_banner_gone)
	var host := _banner_host()
	if host == null:
		banner = null
		return
	host.add_child(banner)
	banner.show_in(_safe_top())

func _can_show() -> bool:
	if app == null:
		return true
	if str(app.get("screen")) != "home":
		return false
	var o := _online()
	return o == null or o.state in ["idle", "lobby"]

func _room_code() -> String:
	var o := _online()
	return o.net.code if o != null and o.net != null and o.net.in_room() else ""

func _on_join(d: Dictionary) -> void:
	_hide_banner()
	var r: Dictionary = await request(HTTPClient.METHOD_POST, PATH + "/invites/accept", {id = str(d.get("id", ""))})
	if not r.ok:
		toast(_toast_host(), tr("That invite has ended.") if r.error == "gone" else invite_error_text(str(r.error)), "info")
		show_next()
		return
	var code := str(r.data.get("code", d.get("code", "")))
	var o := _online()
	if o == null:
		return
	if o.state == "lobby" and o.net.in_room():
		if not await Sheet.confirm(_toast_host(), tr("Leave this room?"), tr("You’ll join %s’s room instead.") % L10n.seat_name(str((d.get("from", {}) as Dictionary).get("name", "Player"))),
				tr("Join"), tr("Stay")):
			return
		o.leave()
	if app != null and app.has_method("close_all_sheets"):
		app.call("close_all_sheets")
	o.join_code(code)

func _on_later(d: Dictionary) -> void:
	_hide_banner()
	request(HTTPClient.METHOD_POST, PATH + "/invites/decline", {id = str(d.get("id", ""))})
	show_next()

func _on_banner_gone() -> void:
	banner = null
	show_next()

func _hide_banner() -> void:
	if is_instance_valid(banner):
		banner.dismiss()
	banner = null


# ---------- Settings: "Invites from players" ----------

## The switch moved: kept in Save.prefs.invites and sent to the server (again later when offline).
func set_invites(on: bool) -> void:
	Save.prefs.invites = on
	Save.prefs.invites_sync = true
	Save.save()
	if on == false:
		pending.clear()
		_hide_banner()
	await _send_invites_pref()

func _send_invites_pref() -> void:
	if not available():
		return
	var r: Dictionary = await request(HTTPClient.METHOD_POST, PATH + "/prefs", {invites = bool(Save.prefs.get("invites", true))})
	if r.ok:
		Save.prefs.erase("invites_sync")
		Save.save()
		changed.emit()


# ---------- wiring: lobby, matches ----------

## A lobby sheet came up (LobbySheet._ready): its Invite button and long-pressed members.
func wire_lobby(ls: LobbySheet) -> void:
	if not ls.invite_pressed.is_connected(open_invite_sheet):
		ls.invite_pressed.connect(open_invite_sheet)
	ls.member_held.connect(func(id: String, name_: String) -> void:
		ask_seat(ls, _room_code(), int(id) if id.is_valid_int() else -1, name_))

## The lobby's Invite: the friends and recent lists with an Invite button per person.
func open_invite_sheet() -> FriendsSheet:
	var o := _online()
	var g := "ludo"
	if o != null:
		g = o.game
	var s := FriendsSheet.new(g, true)
	s.open(_sheet_layer())
	return s

## The match tiles' long-press (Ludo HUD, S&L tiles): the seat's member, in the room you are in.
func _wire_matches() -> void:
	if app == null:
		return
	for key in ["hud", "sl"]:
		var o: Variant = app.get(key)
		if o is Object and is_instance_valid(o) and (o as Object).has_signal("tile_held") \
				and not (o as Object).is_connected("tile_held", _on_tile_held):
			(o as Object).connect("tile_held", _on_tile_held)

func _on_tile_held(c: int) -> void:
	var o := _online()
	if o == null or not o.in_match():
		return
	var m := _online_match()
	var ns: Variant = m.get("ns") if m != null else null
	if not ns is Object:
		return
	var st: Dictionary = (ns as Object).call("seat", c)
	var id := str(st.get("id", ""))
	if id == "" or id == str(o.net.member_id) or not id.is_valid_int():
		return
	ask_seat(_toast_host(), o.net.code, int(id), str(st.get("name", "Player")))


# ---------- helpers ----------

## A number from a server answer (JSON floats, null) as an int.
static func _int(v: Variant, dflt := 0) -> int:
	return int(v) if v is int or v is float else dflt

## The online match on screen (main's LudoMatch or SLMatch whose `online` is on), or null.
func _online_match() -> Object:
	for key in ["ludo", "sl"]:
		var l: Variant = app.get(key) if app != null else null
		if l is Object and is_instance_valid(l) and bool((l as Object).get("online")):
			return l
	return null

func _toast_host() -> Node:
	return app.get("ui_root") if app != null and app.get("ui_root") is Node else self

func _banner_host() -> Node:
	if app != null and app.get("ui_root") is Node:
		return app.get("ui_root")
	return self if is_inside_tree() else null

func _sheet_layer() -> Control:
	if app != null and app.get("sheet_layer") is Control:
		return app.get("sheet_layer")
	return get_tree().root.get_child(0) as Control

func _safe_top() -> float:
	return float(app.get("safe_top")) if app != null and app.get("safe_top") != null else 0.0

func toast(host: Node, text: String, kind := "info") -> void:
	last_toast = text
	if host != null and host.is_inside_tree():
		Toast.show(host, text, null, 2.2, kind)
