class_name NetClient
extends Node
## The online rooms client (server/PROTOCOL.md v1): one room socket at a time, plus the two HTTP helpers.
##
##   var net := NetClient.new(); add_child(net)
##   var r := await net.create_room()            # {ok, code} | {ok = false, error}
##   var c := await net.check_room("K7QX2M")     # {ok, code, open, members, started} | {ok = false, error}
##   net.join("K7QX2M")                          # connects, says hello, keeps the room token
##   net.lobby.connect(...); net.act.connect(...) ...
##   net.send_msg({t = "roll", n = 12})
##   net.leave()
##
## Identity: a random player id kept in Save.prefs.net_pid, plus the account session (Account.session(), sent as
## `session` in every hello when there is one: rewards, bans and level follow the account; without one the server
## falls back to the pid). The room token from `welcome` is kept in memory and in Save.prefs.net_room {code, token,
## quick, game}, so a dropped socket (and an app restart, resume()) takes back the same seat. Quick-match rooms
## (join(code, token, true) after NetQuick's `matched`) work the same; quick says so (no lobby, no host).
## A dropped socket reconnects by itself with backoff (BACKOFF) while you are in a room; status says where it is:
## "idle" (no room), "connecting" (first join), "open" (welcomed), "reconnecting". A first join that never connects
## gives up after JOIN_TRIES with error {code = "no_connection"}; a room that is gone (404) stops the retries with
## error {code = "not_found"}. Pings every PING_SEC; pong.now gives the round trip (rtt_ms) and the server clock
## (server_now()). A silent socket (no frame for SILENCE_SEC) counts as dropped.
##
## Server URL: the --net=ws://host:port command line argument (debug builds), else Save.prefs.net_url, else
## PROD_URL. HTTP goes to the same host (ws -> http, wss -> https).
## Tests: set prefs / persist / profile_fn / session_fn / make_transport / http_fn before use (NetFake provides a
## room and a matchmaker).

signal status_changed(status: String)
signal message(msg: Dictionary)          ## every server message, after the typed signal
signal welcome(msg: Dictionary)
signal lobby(msg: Dictionary)
signal start(msg: Dictionary)
signal act(msg: Dictionary)
signal sync(msg: Dictionary)
signal turn(msg: Dictionary)
signal presence(msg: Dictionary)
signal over(msg: Dictionary)
signal error(msg: Dictionary)
signal emote(msg: Dictionary)            ## another member's emote {c, id} (lobby: c = -1, member); see server/EMOTES.md

const PROD_URL := "wss://ludo-zing-rooms.flipfold.workers.dev"
const VERSION := 1
const PING_SEC := 20.0
const SILENCE_SEC := 50.0                ## no frame at all for this long (two pings unanswered): reconnect
const CONNECT_SEC := 8.0                 ## a socket that hasn't opened by then is dropped and retried
const BACKOFF := [0.5, 1.0, 2.0, 4.0, 8.0, 15.0]
const JOIN_TRIES := 3                    ## a first join gives up after this many failed connects
const CHECK_EVERY := 3                   ## while reconnecting, ask GET /v1/rooms/<code> every few failures
const CODE_LEN := 6
const ALPHABET := "23456789ABCDEFGHJKMNPQRSTUVWXYZ"
const FATAL := ["version", "not_found", "full", "started", "banned"]   ## errors that end the connection attempt
const REMOVED := ["kicked", "banned"]    ## an admin removed us from the room (even mid-match): never reconnect
const NAME_MAX := 16

var url_base := ""                       ## ws(s)://host[:port], no trailing slash (resolve_url() when empty)
var use_save := true                     ## false: prefs / persist / profile_fn are the caller's (tests, dev)
var prefs: Dictionary = {}               ## Save.prefs by default
var persist := Callable()                ## saves prefs (Save.save by default)
var profile_fn := Callable()             ## () -> {name, avatar, frame} (the Save profile by default)
var make_transport := Callable()         ## () -> NetTransport (NetTransport.WS by default)
var http_fn := Callable()                ## (method: int, path: String) -> {status: int, data} (coroutine)
var session_fn := Callable()             ## () -> String: the account session ("" = none; Account.session() by default)

var status := "idle"
var code := ""                           ## the room joined (or being joined)
var token := ""
var member_id := ""                      ## your member id (welcome.id)
var host_id := ""
var last_lobby := {}
var quick := false                       ## the room is a quick-match room (no lobby, no host, no rematch)
var rtt_ms := -1
var clock_offset_ms := 0.0               ## server clock - local clock
var log_sent: Array = []                 ## the last messages sent (tests, debugging)

var transport: NetTransport
var _want := false                       ## we want to be in the room (reconnect when the socket drops)
var _ever_open := false                  ## this join was welcomed at least once
var _hello_sent := false
var _welcomed := false
var _connect_left := 0.0
var _retry := 0
var _retry_left := -1.0
var _ping_left := PING_SEC
var _ping_at := 0.0                      ## unix ms of the last ping
var _silence := 0.0
var _checking := false
var _defaults_done := false


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	_defaults()

func _defaults() -> void:
	if _defaults_done:
		return
	_defaults_done = true
	var save := _save_node() if use_save else null
	if save and save.get("prefs") is Dictionary:
		prefs = save.get("prefs")
	if not persist.is_valid() and save and save.has_method("save"):
		persist = Callable(save, "save")
	if url_base == "":
		url_base = resolve_url(prefs, OS.get_cmdline_user_args() if OS.is_debug_build() else PackedStringArray())


# =====================================================================================================================
# Pure helpers (tested)
# =====================================================================================================================

## The server URL: --net=<url> (debug builds pass their user args), else prefs.net_url, else PROD_URL.
static func resolve_url(p: Dictionary, args: PackedStringArray = PackedStringArray()) -> String:
	for a in args:
		if a.begins_with("--net="):
			return a.trim_prefix("--net=").strip_edges().trim_suffix("/")
	var u := str(p.get("net_url", "")).strip_edges()
	if u != "":
		return u.trim_suffix("/")
	return PROD_URL

## ws://host -> http://host, wss://host -> https://host.
static func http_base(ws_url: String) -> String:
	var u := ws_url.strip_edges().trim_suffix("/")
	if u.begins_with("wss://"):
		return "https://" + u.substr(6)
	if u.begins_with("ws://"):
		return "http://" + u.substr(5)
	return u

## What a typed or pasted room code becomes: upper case, only the code alphabet (no 0 O 1 I L), at most 6.
static func clean_code(t: String) -> String:
	var out := ""
	for ch in t.to_upper():
		if ALPHABET.contains(ch):
			out += ch
			if out.length() == CODE_LEN:
				break
	return out

static func valid_code(t: String) -> bool:
	return t.length() == CODE_LEN and clean_code(t) == t

## The player id kept on the device (created once).
static func ensure_pid(p: Dictionary) -> String:
	var pid := str(p.get("net_pid", ""))
	if pid.length() < 16:
		pid = Crypto.new().generate_random_bytes(12).hex_encode()
		p.net_pid = pid
	return pid

## The room to take back after an app restart: {code, token, quick} or {}.
static func saved_room(p: Dictionary) -> Dictionary:
	var r: Variant = p.get("net_room", {})
	if r is Dictionary and valid_code(str((r as Dictionary).get("code", ""))) and str((r as Dictionary).get("token", "")) != "":
		return {code = str(r.code), token = str(r.token), quick = bool((r as Dictionary).get("quick", false))}
	return {}

## The account session for hellos ("" when there is none): the Account of this run (scripts/net/account.gd).
static func account_session() -> String:
	return Account.session()

## A name the server accepts (1–16 characters, trimmed); the profile's placeholder "You" goes out as "Player".
static func wire_name(n: String) -> String:
	var t := " ".join(n.strip_edges().split(" ", false))
	if t == "" or t == "You":
		t = "Player"
	return t.substr(0, NAME_MAX)

## Friendly copy for an error code (toasts).
static func error_text(code_: String) -> String:
	match code_:
		"not_found":
			return "We couldn’t find that room. Check the code."
		"full":
			return "That room is full."
		"started":
			return "That game has already started."
		"no_connection":
			return "No connection. Check your internet and try again."
		"version":
			return "Update Ludo Zing to play online."
		"too_few":
			return "You need at least 2 players to start."
		"teams_need_4":
			return "Teams need exactly 4 players."
		"not_host":
			return "Only the host can do that."
		"rate":
			return "Slow down a little."
		"server":
			return "The game server isn’t answering. Try again soon."
		"maintenance":
			return "Online play is down for maintenance. Try again soon."
		"banned":
			return "You can’t play online right now."
		"kicked":
			return "You were removed from the room."
		"session":
			return "We couldn’t sign you in. Check your internet and try again."
		"replaced":
			return "You started a search on another device."
		"busy":
			return "You’re already being matched on another device."
	return "Something went wrong. Please try again."


# =====================================================================================================================
# HTTP
# =====================================================================================================================

## POST /v1/rooms: {ok = true, code} or {ok = false, error ("no_connection" | "server")}.
func create_room() -> Dictionary:
	var r: Dictionary = await _http(HTTPClient.METHOD_POST, "/v1/rooms")
	var d: Variant = r.get("data")
	if int(r.get("status", 0)) == 200 and d is Dictionary and valid_code(str((d as Dictionary).get("code", ""))):
		return {ok = true, code = str(d.code)}
	if int(r.get("status", 0)) == 503 and d is Dictionary and str((d as Dictionary).get("error", "")) == "maintenance":
		return {ok = false, error = "maintenance", msg = str((d as Dictionary).get("msg", ""))}   # admin: maintenance mode
	return {ok = false, error = "no_connection" if int(r.get("status", 0)) == 0 else "server"}

## GET /v1/config: {ok = true, motd, maintenance} (the admin console's message of the day) or {ok = false}.
func fetch_config() -> Dictionary:
	var r: Dictionary = await _http(HTTPClient.METHOD_GET, "/v1/config")
	var d: Variant = r.get("data")
	if int(r.get("status", 0)) == 200 and d is Dictionary:
		return {ok = true, motd = str((d as Dictionary).get("motd", "")).strip_edges().left(140),
			maintenance = bool((d as Dictionary).get("maintenance", false))}
	return {ok = false}

## GET /v1/rooms/<code>: {ok = true, code, open, members, started} or {ok = false, error ("not_found" |
## "no_connection" | "server")}.
func check_room(code_: String) -> Dictionary:
	var c := clean_code(code_)
	if not valid_code(c):
		return {ok = false, error = "not_found"}
	var r: Dictionary = await _http(HTTPClient.METHOD_GET, "/v1/rooms/" + c)
	var st := int(r.get("status", 0))
	var d: Variant = r.get("data")
	if st == 404:
		return {ok = false, error = "not_found"}
	if st == 200 and d is Dictionary:
		return {ok = true, code = c, open = bool(d.get("open", true)), members = int(d.get("members", 0)),
			started = bool(d.get("started", false))}
	return {ok = false, error = "no_connection" if st == 0 else "server"}

func _http(method: int, path: String) -> Dictionary:
	_defaults()
	if http_fn.is_valid():
		var out: Variant = await http_fn.call(method, path)
		return out if out is Dictionary else {status = 0}
	var req := HTTPRequest.new()
	req.timeout = 8.0
	add_child(req)
	var body := "{}" if method == HTTPClient.METHOD_POST else ""
	var err := req.request(http_base(url_base) + path, PackedStringArray(["Content-Type: application/json"]), method, body)
	if err != OK:
		req.queue_free()
		return {status = 0}
	var res: Array = await req.request_completed       # [result, response_code, headers, body]
	req.queue_free()
	if int(res[0]) != HTTPRequest.RESULT_SUCCESS:
		return {status = 0}
	var text := (res[3] as PackedByteArray).get_string_from_utf8()
	return {status = int(res[1]), data = JSON.parse_string(text) if text != "" else null}


# =====================================================================================================================
# The room socket
# =====================================================================================================================

## Join a room (the creator too). token: the seat to take back ("" = the kept one for this code, if any).
## quick_: a quick-match room (token from `matched`).
func join(code_: String, token_ := "", quick_ := false) -> void:
	_defaults()
	close_socket()
	code = clean_code(code_)
	var kept := saved_room(prefs)
	token = token_ if token_ != "" else (str(kept.token) if kept.get("code", "") == code else "")
	quick = quick_ or (token_ == "" and kept.get("code", "") == code and bool(kept.get("quick", false)))
	member_id = ""
	host_id = ""
	last_lobby = {}
	_want = true
	_ever_open = false
	_retry = 0
	_open_socket()

## Take back the room kept in Save.prefs.net_room (after an app restart). False when there is none.
func resume() -> bool:
	_defaults()
	var r := saved_room(prefs)
	if r.is_empty():
		return false
	join(r.code, r.token, bool(r.get("quick", false)))
	_ever_open = true                         # a seat we had: keep trying like a dropped socket
	return true

## Leave the room for good (lobby: frees the seat; match: a bot takes it) and forget it.
func leave() -> void:
	if _welcomed:
		send_msg({t = "leave"})
		if transport:
			transport.poll()                  # flush the frame before closing
	_want = false
	close_socket()
	forget_room()
	code = ""
	token = ""
	member_id = ""
	host_id = ""
	last_lobby = {}
	quick = false
	_set_status("idle")

## Forget the kept room (Save.prefs.net_room).
func forget_room() -> void:
	if prefs.has("net_room"):
		prefs.erase("net_room")
		_persist()

func close_socket() -> void:
	if transport:
		transport.close()
	transport = null
	_hello_sent = false
	_welcomed = false
	_retry_left = -1.0

func in_room() -> bool:
	return _want and code != ""

func is_open() -> bool:
	return _welcomed

func is_host() -> bool:
	return member_id != "" and member_id == host_id

## The server's clock now (unix ms), from the last pong.
func server_now() -> float:
	return Time.get_unix_time_from_system() * 1000.0 + clock_offset_ms

## Send one message (adds nothing; requests carry their own n). False when the socket isn't open.
func send_msg(msg: Dictionary) -> bool:
	log_sent.append(msg)
	if log_sent.size() > 64:
		log_sent.pop_front()
	if transport == null or not _hello_sent:
		return false
	return transport.send(JSON.stringify(msg)) == OK

## An emote for the others in the room ({t: "emote", id}; the server checks the pack and the rate and relays it).
func send_emote(id: String) -> bool:
	return send_msg({t = "emote", id = id})

func _open_socket() -> void:
	transport = make_transport.call() if make_transport.is_valid() else NetTransport.make()
	_hello_sent = false
	_welcomed = false
	_connect_left = CONNECT_SEC
	_silence = 0.0
	var err := transport.open("%s/v1/rooms/%s/ws" % [url_base, code])
	_set_status("reconnecting" if _ever_open else "connecting")
	if err != OK:
		_on_closed()

func _hello() -> void:
	var p: Dictionary = profile_fn.call() if profile_fn.is_valid() else _profile()
	var m := {t = "hello", v = VERSION, pid = ensure_pid(prefs), name = wire_name(str(p.get("name", ""))),
		avatar = str(p.get("avatar", "")).substr(0, 32), frame = str(p.get("frame", "")).substr(0, 32)}
	if token != "":
		m.token = token
	var sess := session()
	if sess != "":
		m.session = sess
	_hello_sent = true
	if prefs.get("net_pid") != null:
		_persist()
	send_msg(m)

## The session sent in hellos now ("" = none).
func session() -> String:
	return str(session_fn.call()) if session_fn.is_valid() else (account_session() if use_save else "")

func _profile() -> Dictionary:
	var save := _save_node() if use_save else null
	var p: Dictionary = save.get("profile") if save and save.get("profile") is Dictionary else {}
	return {name = str(p.get("name", "")), avatar = Collection.equipped("avatar", p) if not p.is_empty() else "",
		frame = Collection.equipped("frame", p) if not p.is_empty() else ""}

func _process(delta: float) -> void:
	if _retry_left >= 0.0:
		_retry_left -= delta
		if _retry_left < 0.0 and _want:
			_open_socket()
		return
	if transport == null:
		return
	transport.poll()
	var st := transport.state()
	if st == WebSocketPeer.STATE_OPEN and not _hello_sent:
		_hello()
	if transport == null:
		return
	for text in transport.receive():
		_silence = 0.0
		var parsed: Variant = JSON.parse_string(str(text))
		if parsed is Dictionary:
			handle(MatchStore.ints(parsed))       # JSON numbers are floats: ids, colours, n back to ints
		if transport == null:
			return
	if st == WebSocketPeer.STATE_CONNECTING:
		_connect_left -= delta
		if _connect_left <= 0.0:
			transport.close()
			_on_closed()
		return
	if st == WebSocketPeer.STATE_CLOSED:
		_on_closed()
		return
	if _welcomed:
		_silence += delta
		_ping_left -= delta
		if _ping_left <= 0.0:
			ping()
		if _silence > SILENCE_SEC:
			transport.close()
			_on_closed()

func ping() -> void:
	_ping_left = PING_SEC
	_ping_at = Time.get_unix_time_from_system() * 1000.0
	send_msg({t = "ping"})

## The socket is gone: retry with backoff while we want the room.
func _on_closed() -> void:
	transport = null
	_hello_sent = false
	_welcomed = false
	if not _want:
		_set_status("idle")
		return
	_retry += 1
	if not _ever_open and _retry >= JOIN_TRIES:
		_want = false
		_set_status("idle")
		_emit_error({t = "error", code = "no_connection", msg = "no connection"})
		return
	_retry_left = float(BACKOFF[mini(_retry - 1, BACKOFF.size() - 1)]) * randf_range(0.85, 1.15)
	_set_status("reconnecting")
	if _retry % CHECK_EVERY == 0:
		_check_gone()

## While reconnecting: is the room still there? A 404 stops the retries.
func _check_gone() -> void:
	if _checking or code == "":
		return
	_checking = true
	var c := code
	var r := await check_room(c)
	_checking = false
	if c == code and _want and not _welcomed and not bool(r.get("ok", true)) and r.get("error") == "not_found":
		_want = false
		close_socket()
		forget_room()
		_set_status("idle")
		_emit_error({t = "error", code = "not_found", msg = "room gone"})

## A member id as text, whatever the wire used (the server sends numbers; 1.0 and 1 are the same id).
static func id_str(v: Variant) -> String:
	if v is float and is_finite(v) and float(v) == floorf(v):
		return str(int(v))
	return "" if v == null else str(v)

## One server message (the socket's frames come here; tests inject them directly).
func handle(msg: Dictionary) -> void:
	var t := str(msg.get("t", ""))
	match t:
		"welcome":
			token = str(msg.get("token", token))
			member_id = id_str(msg.get("id", ""))
			host_id = id_str(msg.get("host", host_id))
			if str(msg.get("code", "")) != "":
				code = clean_code(str(msg.code))
			_welcomed = true
			_ever_open = true
			_retry = 0
			_ping_left = PING_SEC
			prefs.net_room = {code = code, token = token, quick = quick}
			_persist()
			_set_status("open")
			ping()                                # the round trip and the server clock, early
			welcome.emit(msg)
		"lobby":
			last_lobby = msg
			host_id = id_str(msg.get("host", host_id))
			lobby.emit(msg)
		"start":
			start.emit(msg)
		"act":
			act.emit(msg)
		"sync":
			sync.emit(msg)
		"turn":
			turn.emit(msg)
		"presence":
			presence.emit(msg)
		"over":
			over.emit(msg)
		"emote":
			emote.emit(msg)
		"pong":
			var now := Time.get_unix_time_from_system() * 1000.0
			if _ping_at > 0.0:
				rtt_ms = int(now - _ping_at)
				clock_offset_ms = float(msg.get("now", now)) - (_ping_at + rtt_ms / 2.0)
				_ping_at = 0.0
		"error":
			var c := str(msg.get("code", ""))
			if (c in FATAL and not _welcomed) or c in REMOVED:
				_want = false
				close_socket()
				if c != "version":
					forget_room()
				_set_status("idle")
			_emit_error(msg)
			return
	message.emit(msg)

func _emit_error(msg: Dictionary) -> void:
	error.emit(msg)
	message.emit(msg)

func _set_status(s: String) -> void:
	if s == status:
		return
	status = s
	status_changed.emit(s)

func _persist() -> void:
	if persist.is_valid():
		persist.call()

static func _save_node() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("Save") if tree and tree.root else null
