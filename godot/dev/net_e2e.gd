extends SceneTree
## Dev: a headless end-to-end run of a friends room against a real server (`npm run dev` / `wrangler dev` in server/).
##   godot --headless --path godot -s res://dev/net_e2e.gd -- --net=ws://localhost:8787 [--players=2|3|4] [--teams]
##       [--ask] [--timeout=600] [--fake]
## Client A creates a room (POST /v1/rooms) and joins it, the others check it (GET /v1/rooms/<code>) and join, A
## starts, and every client plays its own turns from its own replica (NetLudo) the moment its turn comes (auto-move
## or a varied unit; pair prompts yes) until `over`. Every act's hash is checked on every client; a mismatch is a
## failure (it still sends sync_req and goes on, to see how far it gets). Checks a stale request is refused too.
## --fake: the in-process NetFake room instead of a server (a self-check of this script; no network).
## --verbose prints every message. Exit code 0 = PASS. Never touches the Save autoload's file (clients keep their prefs in memory).

var clients: Array = []                  # [{net, ns, inbox, sent_n, over, name}]
var fake: NetFake.Room
var failures: Array = []
var url := "ws://localhost:8787"
var players := 2
var teams := false
var ask := false
var limit_sec := 600.0
var stale_checked := false
var acts_seen := 0
var verbose := false
const PACE_MS := 120                     # at most ~8 requests a second per client (the server allows 20 messages)


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--net="):
			url = a.trim_prefix("--net=").trim_suffix("/")
		elif a.begins_with("--players="):
			players = clampi(int(a.trim_prefix("--players=")), 2, 4)
		elif a == "--teams":
			teams = true
		elif a == "--ask":
			ask = true
		elif a.begins_with("--timeout="):
			limit_sec = float(a.trim_prefix("--timeout="))
		elif a == "--verbose":
			verbose = true
		elif a == "--fake":
			fake = NetFake.Room.new("E2EAB2", 17)
	if teams:
		players = 4
	_run.call_deferred()

func _client(name: String) -> Dictionary:
	var n := NetClient.new()
	n.use_save = false
	n.prefs = {}
	n.url_base = url
	n.profile_fn = func() -> Dictionary: return {name = name, avatar = "pawn-green", frame = "classic"}
	if fake:
		n.make_transport = fake.transport_factory()
		n.http_fn = fake.http
	root.add_child(n)
	var c := {net = n, ns = NetLudo.new(), inbox = [], sent_n = -1, over = false, name = name, started = false, next_at = 0}
	n.message.connect(func(m: Dictionary):
		if verbose and m.get("t") != "pong":
			print("[e2e] %s <- %s" % [name, JSON.stringify(m).substr(0, 160)])
		(c.inbox as Array).append(m))
	clients.append(c)
	return c

func _say(t: String) -> void:
	print("[e2e] " + t)

func _fail(t: String) -> void:
	failures.append(t)
	push_error("[e2e] FAIL " + t)

func _frames(sec: float) -> void:
	var until := Time.get_ticks_msec() + int(sec * 1000.0)
	while Time.get_ticks_msec() < until:
		await process_frame

## Waits until cond() or `sec` passes; false on timeout.
func _until(cond: Callable, sec: float) -> bool:
	var until := Time.get_ticks_msec() + int(sec * 1000.0)
	while Time.get_ticks_msec() < until:
		if cond.call():
			return true
		await process_frame
	return bool(cond.call())

func _has(c: Dictionary, t: String) -> bool:
	return (c.inbox as Array).any(func(m): return m.get("t") == t)

func _last(c: Dictionary, t: String) -> Dictionary:
	for k in range((c.inbox as Array).size() - 1, -1, -1):
		if c.inbox[k].get("t") == t:
			return c.inbox[k]
	return {}

func _run() -> void:
	_say("server %s, %d players%s%s%s" % ["(fake room)" if fake else url, players, " teams" if teams else "", " ask" if ask else "", ""])
	var a := _client("Ana")
	for k in range(1, players):
		_client(["Ana", "Bo", "Cy", "Di"][k])
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
	a.net.send_msg({t = "settings", teams = teams, pair_ask = ask})
	a.net.send_msg({t = "start"})
	if not await _until(func(): return clients.all(func(c): return _has(c, "start")), 10.0):
		_fail("not every client got start")
		_finish()
		return
	_say("started")
	var t0 := Time.get_ticks_msec()
	var read := {}
	for c in clients:
		read[c.name] = 0
	while Time.get_ticks_msec() - t0 < int(limit_sec * 1000.0):
		await process_frame
		if fake:
			fake.step()
		for c: Dictionary in clients:
			_drain(c, read)
		if clients.all(func(c): return c.over):
			break
		for c: Dictionary in clients:
			_act(c)
	_summary()
	_finish()

## Plays every message that arrived for client c through its replica.
func _drain(c: Dictionary, read: Dictionary) -> void:
	var ns: NetLudo = c.ns
	var box: Array = c.inbox
	for k in range(int(read[c.name]), box.size()):
		var m: Dictionary = box[k]
		match str(m.get("t", "")):
			"start":
				ns.begin(m, c.net.member_id)
				c.started = true
				c.sent_n = -1
			"act", "sync", "over":
				ns.push(m)
			"error":
				if m.get("code") == "stale":
					stale_checked = true
				if m.get("code") in ["rate", "bad_action", "not_your_turn"]:
					c.sent_n = -1                       # refused: try again (paced)
				if m.get("code") in ["stale", "rate"]:
					pass
				elif not m.get("code") in ["not_host"]:
					_say("%s: error %s" % [c.name, str(m)])
	read[c.name] = box.size()
	while true:
		var x := ns.next()
		if x.is_empty():
			break
		match str(x.t):
			"act":
				acts_seen += 1
				if not ns.play(x):
					_fail("%s: hash mismatch at n=%d (%s)" % [c.name, int(x.n), str(x.a)])
					c.net.send_msg({t = "sync_req"})
			"need_sync":
				_fail("%s: gap in n before %d" % [c.name, ns.n])
				c.net.send_msg({t = "sync_req"})
			"sync":
				ns.begin(x, c.net.member_id)
			"over":
				c.over = true
				_say("%s: over, winner %s, finished %s" % [c.name, str(x.get("winner")), str(x.get("finished"))])

## Client c's own move, once per step.
func _act(c: Dictionary) -> void:
	var ns: NetLudo = c.ns
	if not c.started or c.over or not ns.my_turn() or c.sent_n == ns.n or Time.get_ticks_msec() < int(c.next_at):
		return
	c.next_at = Time.get_ticks_msec() + PACE_MS
	if not stale_checked and ns.n == 0:
		c.net.send_msg({t = "roll", n = 999})       # a stale n must be refused
	var msg := {}
	match str(ns.S.phase):
		"roll":
			msg = ns.request("roll")
		"choose":
			var i := LudoRules.auto_move_token(ns.S)
			if i < 0:
				var us := LudoRules.units(ns.S)
				i = int(us[(ns.n * 7 + 3) % us.size()].token)
			msg = ns.request("move", {i = i})
		"pair_ask":
			msg = ns.request("pair", {yes = true})
	if verbose and not msg.is_empty():
		print("[e2e] %s -> %s" % [c.name, JSON.stringify(msg)])
	if not msg.is_empty() and c.net.send_msg(msg):
		c.sent_n = ns.n

func _summary() -> void:
	var hashes := {}
	for c: Dictionary in clients:
		var ns: NetLudo = c.ns
		if not c.over:
			_fail("%s never got over (n=%d, phase %s)" % [c.name, ns.n, str(ns.S.get("phase", "?"))])
		if not ns.S.is_empty():
			hashes[StateHash.of(ns.S)] = true
		if ns.mismatches > 0:
			_fail("%s saw %d hash mismatches" % [c.name, ns.mismatches])
	if hashes.size() != 1:
		_fail("the replicas ended on different states: %s" % str(hashes.keys()))
	if not stale_checked:
		_fail("a stale request was never refused with stale")
	_say("acts applied (all clients): %d, actions in the match: %d" % [acts_seen, (clients[0].ns as NetLudo).n])

func _finish() -> void:
	for c: Dictionary in clients:
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
