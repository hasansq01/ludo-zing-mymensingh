extends SceneTree
## Dev: a headless end-to-end run of online play against a real server (`wrangler dev` in server/, or production).
##   godot --headless --path godot -s res://dev/net_e2e.gd -- --net=ws://127.0.0.1:8793 [--game=ludo|sl]
##       [--players=2|3|4] [--teams] [--ask] [--quick] [--humans=1] [--timeout=600] [--fake] [--verbose]
## Friend room (default): client A creates a room (POST /v1/rooms) and joins it, the others check it
## (GET /v1/rooms/<code>) and join, A picks the game (settings {game}) and starts, and every client plays its own
## turns from its own replica (NetLudo / NetSL) the moment its turn comes (Ludo: auto-move or a varied unit, pair
## prompts yes; S&L: roll) until `over`. Checks a guest's start is refused and a stale request too.
## --quick: `humans` clients (default 1) queue on GET /v1/quick/ws?game=&players= (NetQuick); the server seats them
## at a `players` table and fills the rest with its own players; each joins the room with its token (no lobby,
## welcome.host -1) and plays to `over`. Checks every seat looks like a person (players "human", bot false, online,
## the same keys) and that the server's players act.
## Every act's hash is checked on every client; a mismatch is a failure (it still sends sync_req and goes on).
## Play on: every `finished` event (the game goes on after the first finish) and the server's {k: "end"} are logged.
## Sessions: each client signs in as a guest (POST /v1/auth/guest {pid}) with a fixed pid per name, so repeated runs
## reuse the same few accounts (the server never rate-limits an existing pid). The session goes in every hello.
## --fake: the in-process NetFake hub instead of a server (a self-check of this script; no network).
## Exit code 0 = PASS. Never touches the Save autoload's file (clients keep their prefs in memory).

var clients: Array = []                  # [{net, quick, ns, inbox, sent_n, over, name, session, matched}]
var hub: NetFake.Hub
var failures: Array = []
var url := "ws://127.0.0.1:8793"
var game := "ludo"
var players := 2
var humans := 1
var teams := false
var ask := false
var quick := false
var limit_sec := 600.0
var stale_checked := false
var acts_seen := 0
var finishes: Array = []                 # play on: the colours that finished before `over` (client A's view)
var verbose := false
var t_start := 0
const PACE_MS := 120                     # at most ~8 requests a second per client (the server allows 20 messages)
const NAMES := ["Ana", "Bo", "Cy", "Di"]


func _initialize() -> void:
	var fake := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--net="):
			url = a.trim_prefix("--net=").trim_suffix("/")
		elif a.begins_with("--game="):
			game = "sl" if a.trim_prefix("--game=") == "sl" else "ludo"
		elif a.begins_with("--players="):
			players = clampi(int(a.trim_prefix("--players=")), 2, 4)
		elif a.begins_with("--humans="):
			humans = clampi(int(a.trim_prefix("--humans=")), 1, 4)
		elif a == "--teams":
			teams = true
		elif a == "--ask":
			ask = true
		elif a == "--quick":
			quick = true
		elif a.begins_with("--timeout="):
			limit_sec = float(a.trim_prefix("--timeout="))
		elif a == "--verbose":
			verbose = true
		elif a == "--fake":
			fake = true
	if fake:
		hub = NetFake.Hub.new(17)
	if teams:
		players = 4
	if quick:
		players = 4 if players > 2 else 2
		humans = mini(humans, players)
	_run.call_deferred()

func _client(name: String) -> Dictionary:
	var n := NetClient.new()
	n.use_save = false
	n.prefs = {net_pid = "e2e_conline_%s_v1" % name.to_lower()}
	n.url_base = url
	n.profile_fn = func() -> Dictionary: return {name = name, avatar = "pawn-green", frame = "classic"}
	if hub:
		n.make_transport = hub.transport_factory()
		n.http_fn = hub.http
	root.add_child(n)
	var c := {net = n, quick = null, ns = null, inbox = [], sent_n = -1, over = false, name = name, started = false,
		next_at = 0, session = "", matched = {}, welcome = {}}
	n.session_fn = func() -> String: return str(c.session)
	n.message.connect(func(m: Dictionary):
		if verbose and m.get("t") != "pong":
			print("[e2e] %s <- %s" % [name, JSON.stringify(m).substr(0, 160)])
		(c.inbox as Array).append(m))
	clients.append(c)
	return c

func _say(t: String) -> void:
	print("[e2e %5.1fs] %s" % [(Time.get_ticks_msec() - t_start) / 1000.0, t])

func _fail(t: String) -> void:
	failures.append(t)
	push_error("[e2e] FAIL " + t)

## Waits until cond() or `sec` passes; false on timeout.
func _until(cond: Callable, sec: float) -> bool:
	var until := Time.get_ticks_msec() + int(sec * 1000.0)
	while Time.get_ticks_msec() < until:
		if cond.call():
			return true
		await process_frame
	return bool(cond.call())

func _frames(sec: float) -> void:
	var until := Time.get_ticks_msec() + int(sec * 1000.0)
	while Time.get_ticks_msec() < until:
		await process_frame

func _has(c: Dictionary, t: String) -> bool:
	return (c.inbox as Array).any(func(m): return m.get("t") == t)

func _last(c: Dictionary, t: String) -> Dictionary:
	for k in range((c.inbox as Array).size() - 1, -1, -1):
		if c.inbox[k].get("t") == t:
			return c.inbox[k]
	return {}

## A guest session for client c (POST /v1/auth/guest {pid}); the fake hub takes any session.
func _sign_in(c: Dictionary) -> bool:
	if hub:
		c.session = "fake-" + str(c.name)
		return true
	var req := HTTPRequest.new()
	req.timeout = 10.0
	root.add_child(req)
	var body := JSON.stringify({pid = NetClient.ensure_pid(c.net.prefs)})
	var err := req.request(NetClient.http_base(url) + "/v1/auth/guest", PackedStringArray(["Content-Type: application/json"]),
		HTTPClient.METHOD_POST, body)
	if err != OK:
		req.queue_free()
		return false
	var res: Array = await req.request_completed
	req.queue_free()
	var text := (res[3] as PackedByteArray).get_string_from_utf8()
	var d: Variant = JSON.parse_string(text) if text != "" else null
	if int(res[1]) == 200 and d is Dictionary and str((d as Dictionary).get("session", "")) != "":
		c.session = str(d.session)
		return true
	_say("guest sign-in for %s failed: %d %s" % [c.name, int(res[1]), text.substr(0, 120)])
	return false

func _run() -> void:
	t_start = Time.get_ticks_msec()
	_say("server %s, %s, %s, %d players%s%s%s" % ["(fake hub)" if hub else url, game, "quick match (%d human%s)" % [humans, "" if humans == 1 else "s"] if quick else "friend room",
		players, " teams" if teams else "", " ask" if ask else "", ""])
	var count := humans if quick else players
	for k in count:
		_client(NAMES[k])
	for c: Dictionary in clients:
		if not await _sign_in(c):
			if quick:
				_fail("%s has no session (quick match needs one)" % c.name)
				_finish()
				return
	if quick:
		await _run_quick()
	else:
		await _run_room()

func _run_room() -> void:
	var a: Dictionary = clients[0]
	var cr: Dictionary = await (a.net as NetClient).create_room()
	if not bool(cr.get("ok", false)):
		_fail("create room: %s" % str(cr))
		_finish()
		return
	var code := str(cr.code)
	_say("room %s" % code)
	a.net.join(code)
	if not await _until(func(): return a.net.is_open(), 10.0):
		_fail("A never got welcome")
		_finish()
		return
	for k in range(1, clients.size()):
		var c: Dictionary = clients[k]
		var ck: Dictionary = await (c.net as NetClient).check_room(code)
		if not bool(ck.get("ok", false)) or not bool(ck.get("open", false)):
			_fail("check room from %s: %s" % [c.name, str(ck)])
		c.net.join(code)
		if not await _until(func(): return c.net.is_open(), 10.0):
			_fail("%s never got welcome" % c.name)
			_finish()
			return
	if not await _until(func(): return int((_last(a, "lobby").get("members", []) as Array).size()) == players, 10.0):
		_fail("lobby never showed %d members: %s" % [players, str(_last(a, "lobby"))])
	if not a.net.is_host():
		_fail("the creator is not host")
	if clients.size() > 1:
		clients[1].net.send_msg({t = "start"})
		if not await _until(func(): return _has(clients[1], "error"), 5.0) or _last(clients[1], "error").get("code") != "not_host":
			_fail("a guest's start was not refused with not_host")
	a.net.send_msg({t = "settings", teams = teams, pair_ask = ask, game = game})
	if not await _until(func(): return str((_last(a, "lobby").get("settings", {}) as Dictionary).get("game", "")) == game, 5.0):
		_fail("the lobby never said game %s: %s" % [game, str(_last(a, "lobby").get("settings"))])
	a.net.send_msg({t = "start"})
	if not await _until(func(): return clients.all(func(c): return _has(c, "start")), 10.0):
		_fail("not every client got start")
		_finish()
		return
	var st := _last(a, "start")
	if str(st.get("game", "ludo")) != game:
		_fail("start.game is %s, not %s" % [str(st.get("game")), game])
	_say("started (%s)" % str(st.get("game", "ludo")))
	await _play()
	_summary()
	_finish()

func _run_quick() -> void:
	for c: Dictionary in clients:
		var q := NetQuick.new(c.net)
		root.add_child(q)
		c.quick = q
		q.matched.connect(func(code: String, tok: String): c.matched = {code = code, token = tok})
		q.failed.connect(func(code: String, msg: String): _fail("%s: queue failed %s %s" % [c.name, code, msg]))
		q.queued.connect(func(pos: int, eta: int): _say("%s queued: position %d, eta %d s" % [c.name, pos, eta]))
		q.search(game, players)
	if hub:
		await _until(func(): return hub.mm.queue(game, players).size() == clients.size(), 5.0)
		hub.mm.fill(game, players)
	if not await _until(func(): return clients.all(func(c): return not (c.matched as Dictionary).is_empty()) or not failures.is_empty(), 120.0):
		_fail("not every client was matched: %s" % str(clients.map(func(c): return c.quick.status)))
		_finish()
		return
	if not failures.is_empty():
		_finish()
		return
	var code := str(clients[0].matched.code)
	_say("matched into room %s (%s)" % [code, ", ".join(clients.map(func(c): return "%s %s" % [c.name, str(c.matched.code)]))])
	for c: Dictionary in clients:
		if str(c.matched.code) != code:
			_fail("%s was matched into another room (%s)" % [c.name, str(c.matched.code)])
		c.net.join(str(c.matched.code), str(c.matched.token), true)
	if not await _until(func(): return clients.all(func(c): return c.net.is_open()), 15.0):
		_fail("not every client was welcomed into the quick room")
		_finish()
		return
	for c: Dictionary in clients:
		var w := _last(c, "welcome")
		if int(w.get("host", 0)) != -1:
			_fail("%s: welcome.host is %s in a quick room (want -1)" % [c.name, str(w.get("host"))])
	if not await _until(func(): return clients.all(func(c): return _has(c, "start")), 20.0):
		_fail("the quick match never started")
		_finish()
		return
	var st := _last(clients[0], "start")
	_check_seats(st)
	clients[0].net.send_msg({t = "settings", game = "ludo"})
	await _until(func(): return _has(clients[0], "error"), 5.0)
	if _last(clients[0], "error").get("code") != "bad_action":
		_fail("settings in a quick room was not refused with bad_action: %s" % str(_last(clients[0], "error")))
	_say("started (%s, %d seats: %s)" % [str(st.get("game")), (st.seats as Array).size(),
		", ".join((st.seats as Array).map(func(s): return "%s L%d" % [str(s.name), int(s.get("level", 0))]))])
	await _play()
	if clients.any(func(c): return _has(c, "lobby")):
		_fail("a quick room sent a lobby message")
	_summary()
	_finish()

## Every seat of a quick match looks like a person: same keys, not a bot, online, "human" / cpu false in the state.
func _check_seats(st: Dictionary) -> void:
	var seats: Array = st.get("seats", [])
	if seats.size() != players:
		_fail("the quick table has %d seats, want %d" % [seats.size(), players])
	var keys: Array = (seats[0] as Dictionary).keys() if not seats.is_empty() else []
	keys.sort()
	var s: Dictionary = st.get("state", {})
	for seat: Dictionary in seats:
		var k := seat.keys()
		k.sort()
		var c := int(seat.get("color", -1))
		var cpu := false
		if game == "sl":
			for p in s.get("players", []):
				if int(p.c) == c:
					cpu = bool(p.cpu)
		else:
			cpu = s.players[c] != "human"
		if k != keys or bool(seat.get("bot", true)) or not bool(seat.get("online", false)) or cpu or str(seat.get("name", "")) == "":
			_fail("a seat that doesn't look like a person: %s" % str(seat))

## Plays until every client got `over` (or the time limit).
func _play() -> void:
	var t0 := Time.get_ticks_msec()
	var read := {}
	for c in clients:
		read[c.name] = 0
	var others := 0
	var last_n := -1
	var last_report := 0
	while Time.get_ticks_msec() - t0 < int(limit_sec * 1000.0):
		await process_frame
		if hub:
			for r: NetFake.Room in hub.rooms.values():
				if r.playing and Engine.get_process_frames() % 6 == 0:
					if r.step():
						others += 1
					elif r.playing and not clients.any(func(c): return c.ns != null and (c.ns as NetReplica).me == r.turn_color()):
						r.timeout()
		for c: Dictionary in clients:
			_drain(c, read)
		if clients.all(func(c): return c.over):
			break
		for c: Dictionary in clients:
			_act(c)
		var ns0: NetReplica = clients[0].ns
		if ns0 and Time.get_ticks_msec() - last_report > 15000:
			last_report = Time.get_ticks_msec()
			if ns0.n != last_n:
				_say("n=%d, turn %d" % [ns0.n, ns0.turn_color()])
				last_n = ns0.n

## Plays every message that arrived for client c through its replica.
func _drain(c: Dictionary, read: Dictionary) -> void:
	var box: Array = c.inbox
	for k in range(int(read[c.name]), box.size()):
		var m: Dictionary = box[k]
		match str(m.get("t", "")):
			"start":
				c.ns = NetReplica.for_game(m.get("game", "ludo"))
				(c.ns as NetReplica).begin(m, c.net.member_id)
				c.started = true
				c.sent_n = -1
			"act", "sync", "over":
				if c.ns != null:
					(c.ns as NetReplica).push(m)
			"error":
				if m.get("code") == "stale":
					stale_checked = true
				if m.get("code") in ["rate", "bad_action", "not_your_turn"]:
					c.sent_n = -1                       # refused: try again (paced)
				if not m.get("code") in ["not_host", "stale", "rate", "bad_action"]:
					_say("%s: error %s" % [c.name, str(m)])
	read[c.name] = box.size()
	var ns: NetReplica = c.ns
	while ns != null:
		var x := ns.next()
		if x.is_empty():
			break
		match str(x.t):
			"act":
				acts_seen += 1
				var ev := ns.apply_rules(x.get("a", {}))
				if not ns.verify(x):
					_fail("%s: hash mismatch at n=%d (%s)" % [c.name, int(x.n), str(x.a)])
					c.net.send_msg({t = "sync_req"})
				if c == clients[0]:                     # play on: every finish (and the server's end), once
					for e in ev:
						if e.type == "finished":
							finishes.append(int(e.c))
							_say("finished: colour %d place %d at n=%d%s" % [int(e.c), int(e.place), int(x.n), " (team %s)" % str(e.team) if e.has("team") else ""])
					if str((x.get("a", {}) as Dictionary).get("k", "")) == "end":
						_say("the server ended the match ({k: end}) at n=%d" % int(x.n))
			"need_sync":
				_fail("%s: gap in n before %d" % [c.name, ns.n])
				c.net.send_msg({t = "sync_req"})
			"sync":
				ns.begin(x, c.net.member_id)
			"over":
				c.over = true
				_say("%s: over, winner %s, finished %s, standings %d" % [c.name, str(x.get("winner")), str(x.get("finished")),
					(x.get("standings", []) as Array).size()])

## Client c's own move, once per step.
func _act(c: Dictionary) -> void:
	var ns: NetReplica = c.ns
	if not c.started or c.over or ns == null or not ns.my_turn() or c.sent_n == ns.n or Time.get_ticks_msec() < int(c.next_at):
		return
	c.next_at = Time.get_ticks_msec() + PACE_MS
	if not stale_checked and not c.get("stale_sent", false):
		c.stale_sent = true
		c.net.send_msg({t = "roll", n = 999})       # a stale n must be refused (once, on the first own turn)
	var msg := ns.auto_request(0)
	if verbose and not msg.is_empty():
		print("[e2e] %s -> %s" % [c.name, JSON.stringify(msg)])
	if not msg.is_empty() and c.net.send_msg(msg):
		c.sent_n = ns.n

func _summary() -> void:
	var hashes := {}
	for c: Dictionary in clients:
		var ns: NetReplica = c.ns
		if ns == null:
			_fail("%s never started" % c.name)
			continue
		if not c.over:
			_fail("%s never got over (n=%d, phase %s)" % [c.name, ns.n, str(ns.S.get("phase", "?"))])
		if not ns.S.is_empty():
			hashes[ns.state_hash()] = true
		if ns.mismatches > 0:
			_fail("%s saw %d hash mismatches" % [c.name, ns.mismatches])
	if hashes.size() != 1:
		_fail("the replicas ended on different states: %s" % str(hashes.keys()))
	if not stale_checked:
		_fail("a stale request was never refused with stale")
	var ns0: NetReplica = clients[0].ns
	_say("acts applied (all clients): %d, actions in the match: %d, final hash %s" % [acts_seen, ns0.n if ns0 else 0,
		str(hashes.keys())])

func _finish() -> void:
	for c: Dictionary in clients:
		if c.quick:
			(c.quick as NetQuick).cancel()
		c.net.leave()
	await _frames(0.3)
	if failures.is_empty():
		print("[e2e] PASS")
		quit(0)
	else:
		print("[e2e] FAILED (%d)" % failures.size())
		for f in failures:
			print("  - " + f)
		quit(1)
