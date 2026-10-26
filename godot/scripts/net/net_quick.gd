class_name NetQuick
extends Node
## The quick-match queue client (server/PROTOCOL.md "Quick match"): one socket to GET /v1/quick/ws?game=&players=,
## a hello with the account session, `queued {position, eta_s}` while waiting, then `matched {code, token}` (the
## server closes the socket; the caller joins room `code` with that token: NetClient.join(code, token, true)).
##
##   var q := NetQuick.new(net); add_child(q)     # url, pid, profile and transport come from the NetClient
##   q.queued.connect(...); q.matched.connect(func(code, token): net.join(code, token, true))
##   q.failed.connect(func(code, msg): ...)       # maintenance | banned | session | replaced | busy | version |
##                                                 # no_connection | bad_message | coins | locked (q.fail_info: {short} | {level})
##   q.search("sl", 2, "t100")                     # table: practice (default) | t100 | t500 | t2k | t10k | t50k
##   q.cancel()                                    # leaves the queue (also: closing the socket)
##
## The session: NetClient.session() (Account.session()). None yet: Account.ensure_session() first (a guest sign-in);
## an `error session` (expired) is answered once by a fresh guest sign-in and a new hello. A socket that drops while
## waiting reconnects (CONNECT_TRIES, the server keeps one entry per account); a socket that never opens fails with
## no_connection. status: "idle" | "connecting" | "queued" | "matched" | "failed".
## Tests: renew_fn (() -> String, a coroutine returning the new session or "") replaces the Account sign-in.

signal status_changed(status: String)
signal queued(position: int, eta_s: int)
signal matched(code: String, token: String)
signal failed(code: String, msg: String)
signal cancelled

const PING_SEC := 20.0
const CONNECT_SEC := 8.0
const CONNECT_TRIES := 3
const BACKOFF := [0.6, 1.5, 3.0]
const SIZES := [2, 4]
const GAMES := ["ludo", "sl"]
const FATAL := ["maintenance", "banned", "replaced", "busy", "version", "bad_message", "coins", "locked"]

var net: NetClient
var renew_fn := Callable()
var status := "idle"
var game := "ludo"
var players := 2
var table := "practice"                  ## the coin table of the search (CoinTables ids)
var fail_info := {}                      ## the last failure's extras: coins {short}, locked {level}
var position := 0
var eta_s := 0
var started_at := 0                      ## Time.get_ticks_msec() when the search began
var log_sent: Array = []

var transport: NetTransport
var _want := false
var _hello_sent := false
var _renewed := false
var _tries := 0
var _connect_left := 0.0
var _retry_left := -1.0
var _ping_left := PING_SEC
var _session := ""
var _gen := 0                            # bumps on every search / cancel (a late sign-in can't revive an old one)


func _init(net_: NetClient = null) -> void:
	net = net_
	process_mode = Node.PROCESS_MODE_ALWAYS

## The queue URL for a game and table size (and the coin table: Practice is the server's default, left out).
static func queue_url(base: String, g: String, n: int, table_ := "practice") -> String:
	var u := "%s/v1/quick/ws?game=%s&players=%d" % [base.trim_suffix("/"), g, n]
	if table_ != "practice" and CoinTables.valid(table_):
		u += "&table=" + table_
	return u

static func valid(g: String, n: int) -> bool:
	return g in GAMES and n in SIZES

func searching() -> bool:
	return status in ["connecting", "queued"]

## Seconds since the search began.
func elapsed() -> float:
	return (Time.get_ticks_msec() - started_at) / 1000.0 if started_at > 0 else 0.0

## Join the queue for game ("ludo" | "sl"), players (2 | 4) and coin table (the entry is taken at hello and given
## back when you leave the queue).
func search(g: String, n: int, table_ := "practice") -> void:
	close_socket()
	game = g if g in GAMES else "ludo"
	players = n if n in SIZES else 2
	table = table_ if CoinTables.valid(table_) else "practice"
	fail_info = {}
	position = 0
	eta_s = 0
	_want = true
	_renewed = false
	_tries = 0
	_gen += 1
	started_at = Time.get_ticks_msec()
	_set_status("connecting")
	var gen := _gen
	_session = net.session() if net else ""
	if _session == "":
		_session = await _renew()
		if gen != _gen or not _want:
			return
		if _session == "":
			_fail("session", "")
			return
	_open()

## Leave the queue (the socket's close leaves it too). Emits cancelled.
func cancel() -> void:
	var was := searching()
	_gen += 1
	_want = false
	if transport and _hello_sent:
		_send({t = "cancel"})
		transport.poll()
	close_socket()
	_set_status("idle")
	if was:
		cancelled.emit()

func close_socket() -> void:
	if transport:
		transport.close()
	transport = null
	_hello_sent = false
	_retry_left = -1.0

func _open() -> void:
	transport = net.make_transport.call() if net and net.make_transport.is_valid() else NetTransport.make()
	_hello_sent = false
	_connect_left = CONNECT_SEC
	_ping_left = PING_SEC
	var base := net.url_base if net else NetClient.PROD_URL
	if net and base == "":
		net._defaults()
		base = net.url_base
	if transport.open(queue_url(base, game, players, table)) != OK:
		_on_closed()

func _hello() -> void:
	var p: Dictionary = net.profile_fn.call() if net and net.profile_fn.is_valid() else (net._profile() if net else {})
	var pid := NetClient.ensure_pid(net.prefs) if net else ""
	var m := {t = "hello", v = NetClient.VERSION, session = _session, pid = pid,
		name = NetClient.wire_name(str(p.get("name", ""))), avatar = str(p.get("avatar", "")).substr(0, 32),
		frame = str(p.get("frame", "")).substr(0, 32)}
	_hello_sent = true
	_send(m)

func _send(m: Dictionary) -> bool:
	log_sent.append(m)
	if log_sent.size() > 32:
		log_sent.pop_front()
	if transport == null:
		return false
	return transport.send(JSON.stringify(m)) == OK

func _process(delta: float) -> void:
	if _retry_left >= 0.0:
		_retry_left -= delta
		if _retry_left < 0.0 and _want:
			_open()
		return
	if transport == null:
		return
	transport.poll()
	var st := transport.state()
	if st == WebSocketPeer.STATE_OPEN and not _hello_sent:
		_hello()
	for text in transport.receive():
		var parsed: Variant = JSON.parse_string(str(text))
		if parsed is Dictionary:
			handle(MatchStore.ints(parsed))
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
	if _hello_sent:
		_ping_left -= delta
		if _ping_left <= 0.0:
			_ping_left = PING_SEC
			log_sent.append({t = "ping"})
			if transport != null:
				transport.send('{"t":"ping"}')

## One matchmaker message (the socket's frames come here; tests inject them directly).
func handle(msg: Dictionary) -> void:
	match str(msg.get("t", "")):
		"queued":
			position = int(msg.get("position", 0))
			eta_s = int(msg.get("eta_s", 0))
			_tries = 0
			_set_status("queued")
			queued.emit(position, eta_s)
		"matched":
			var c := NetClient.clean_code(str(msg.get("code", "")))
			var tok := str(msg.get("token", ""))
			_want = false
			close_socket()
			_set_status("matched")
			matched.emit(c, tok)
		"cancelled":
			if _want:
				return
			close_socket()
		"error":
			var code := str(msg.get("code", ""))
			var why := str(msg.get("msg", ""))
			if code == "session" and not _renewed:
				_renewed = true                   # expired: a fresh guest sign-in, then hello again
				close_socket()
				var gen := _gen
				var s := await _renew(true)
				if gen != _gen or not _want:
					return
				if s == "":
					_fail("session", why)
					return
				_session = s
				_open()
				return
			if code == "session" or code in FATAL:
				fail_info = {}
				for k in ["short", "level"]:
					if msg.has(k):
						fail_info[k] = int(msg[k])
				_fail(code, why)

## A socket that closed before `matched`: try again a few times (backoff), then no_connection.
func _on_closed() -> void:
	transport = null
	_hello_sent = false
	if not _want:
		return
	_tries += 1
	if _tries > CONNECT_TRIES:
		_fail("no_connection", "")
		return
	_retry_left = float(BACKOFF[mini(_tries - 1, BACKOFF.size() - 1)])
	_set_status("connecting")

func _fail(code: String, msg: String) -> void:
	_want = false
	_gen += 1
	close_socket()
	_set_status("failed")
	failed.emit(code, msg)

## A session from the Account: an existing one, else a guest sign-in (force: sign in again for a fresh one).
func _renew(force := false) -> String:
	if renew_fn.is_valid():
		return str(await renew_fn.call())
	var acc := Account.instance()
	if acc == null:
		return ""
	var ok := false
	if force:
		ok = await acc.sign_in_guest()
	else:
		ok = await acc.ensure_session()
	return Account.session() if ok else ""

func _set_status(s: String) -> void:
	if s == status:
		return
	status = s
	status_changed.emit(s)
