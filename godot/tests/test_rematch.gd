extends "res://tests/test_suite.gd"
## Play again in friend rooms, client side (server/PROTOCOL.md "Play again"): the fake room's vote (NetFake: anyone
## asks, the answers to everyone, Leave = no, a newcomer = yes, a member back with the token is still asked; the close:
## "go" with the yes-sayers, "few" back to the lobby, Teams falling back to free-for-all, several asking at once,
## rematch_out for the others), Online (Play again sends rematch, the vote kept and handed to the app, the prompt sheet
## when nothing else shows it, the yes-sayer back in the lobby after "few", rematch_out -> home), the result screen's
## vote card (the prompt, the ticks, waiting, starting, ffa) and the lobby sheet's marks. Nothing here writes the save
## or opens a socket.

func run() -> void:
	_fake_vote()
	_fake_close()
	_online()
	_result()
	_lobby()


# ---------- harness ----------

func client(room: NetFake.Room, name: String) -> NetClient:
	var c := NetClient.new()
	c.use_save = false
	c.prefs = {}
	c.url_base = "ws://fake"
	c.profile_fn = func() -> Dictionary: return {name = name, avatar = "pawn-blue", frame = "classic"}
	c.make_transport = room.transport_factory()
	c.http_fn = room.http
	var log := []
	c.set_meta("log", log)
	c.message.connect(func(m: Dictionary): log.append(m))
	return c

func pump(cs: Array, times := 3) -> void:
	for k in times:
		for c: NetClient in cs:
			c._process(0.0)

func got(c: NetClient, t: String) -> Array:
	return (c.get_meta("log") as Array).filter(func(m): return m.get("t") == t)

func last(c: NetClient, t: String) -> Dictionary:
	var a := got(c, t)
	return a[-1] if not a.is_empty() else {}

func free_all(cs: Array) -> void:
	for c: NetClient in cs:
		if is_instance_valid(c):
			c.free()

## name -> answer in a `rematch` message.
static func votes(m: Dictionary) -> Dictionary:
	var out := {}
	for p: Dictionary in m.get("players", []):
		out[str(p.name)] = str(p.vote)
	return out

## The fake match ends now (the server's `over`, then the lobby with status "over").
static func force_over(room: NetFake.Room) -> void:
	room.S.phase = "over"
	room.S.winner = room.turn_color()
	room.playing = false
	room.finished_once = true
	room._broadcast(room._over_msg())
	room._lobby()

## A friend room of these people (the first hosts) whose first match has just ended: [room, clients].
func played(names: Array, teams := false) -> Array:
	var room := NetFake.Room.new("K7QX2M", 3)
	var cs := []
	for n: String in names:
		var c := client(room, n)
		c.join(room.code)
		cs.append(c)
		pump(cs)
	if teams:
		cs[0].send_msg({t = "settings", teams = true})
	cs[0].send_msg({t = "start"})
	pump(cs)
	force_over(room)
	pump(cs)
	return [room, cs]


# ---------- the fake room's vote ----------

func _fake_vote() -> void:
	var p := played(["Ana", "Bo", "Cy"])
	var room: NetFake.Room = p[0]
	var cs: Array = p[1]
	var a: NetClient = cs[0]
	var b: NetClient = cs[1]
	var c: NetClient = cs[2]
	b.send_msg({t = "rematch"})                    # not the host
	pump(cs)
	var v := last(a, "rematch")
	check("fake vote: anyone may ask; everyone hears who and the answers", NetClient.id_str(v.get("by")) == b.member_id
		and votes(v) == {Ana = "wait", Bo = "yes", Cy = "wait"} and not v.has("result") and int(v.until) - int(v.now) > 29000, v)
	check("vote_of / vote_by_name", Online.vote_of(v, b.member_id) == "yes" and Online.vote_of(v, a.member_id) == "wait"
		and Online.vote_of(v, "99") == "" and Online.vote_by_name(v) == "Bo")
	b.send_msg({t = "rematch"})                    # a double tap changes nothing
	pump(cs)
	check("fake vote: a repeat is ignored", got(a, "rematch").size() == 1)
	c.leave()
	pump(cs)
	check("fake vote: Leave is a no for the others", votes(last(a, "rematch")) == {Ana = "wait", Bo = "yes", Cy = "no"}, last(a, "rematch"))
	var d := client(room, "Di")
	d.join(room.code)
	pump([a, b, d])
	check("fake vote: joining meanwhile is a yes", votes(last(d, "rematch")) == {Ana = "wait", Bo = "yes", Cy = "no", Di = "yes"}
		and votes(last(a, "rematch")).get("Di") == "yes", last(d, "rematch"))
	var a2 := client(room, "Ana")                  # Ana's phone again (her seat's token): still asked
	a2.join(room.code, a.token)
	pump([a2, b, d])
	check("fake vote: back with the token, still asked (sync, over, lobby, the vote)", a2.member_id == a.member_id
		and not last(a2, "over").is_empty() and Online.vote_of(last(a2, "rematch"), a2.member_id) == "wait")
	a2.send_msg({t = "rematch"})
	pump([a2, b, d])
	var done := last(b, "rematch")
	check("fake vote: nobody deciding -> go", str(done.get("result", "")) == "go" and room.playing and room.vote.is_empty(), done)
	var st := last(d, "start")
	check("fake vote: the next match with the yes-sayers in join order", st.seats.map(func(x): return NetClient.id_str(x.id))
		== [a2.member_id, b.member_id, d.member_id], st.get("seats"))
	free_all([a, b, c, d, a2])

func _fake_close() -> void:
	# the window runs out: the silent one is out, the one who said yes waits in the lobby
	var p := played(["Ana", "Bo"])
	var room: NetFake.Room = p[0]
	var cs: Array = p[1]
	var a: NetClient = cs[0]
	var b: NetClient = cs[1]
	b.send_msg({t = "rematch"})
	pump(cs)
	room.vote_timeout()
	pump(cs)
	check("fake close: fewer than 2 -> few", str(last(b, "rematch").get("result", "")) == "few")
	check("fake close: the silent one gets rematch_out and stops (not in the room, no reconnect)",
		last(a, "error").get("code") == "rematch_out" and not a.in_room() and a.status == "idle" and NetClient.saved_room(a.prefs).is_empty())
	var l := last(b, "lobby")
	check("fake close: the yes-sayer is back in the lobby, as host", l.status == "lobby" and l.members.size() == 1
		and NetClient.id_str(l.host) == b.member_id and b.is_host() and not room.playing)
	free_all(cs)
	# Teams with three yes: free-for-all
	p = played(["Ana", "Bo", "Cy", "Di"], true)
	room = p[0]
	cs = p[1]
	for k in 3:
		(cs[k] as NetClient).send_msg({t = "rematch"})
	pump(cs)
	(cs[3] as NetClient).leave()
	pump(cs)
	var done := last(cs[0], "rematch")
	check("fake close: Teams with 3 yes -> go, ffa, the setting off", done.get("result") == "go" and done.get("ffa") == true
		and not bool(room.settings.teams) and last(cs[0], "start").state.teams == false
		and last(cs[0], "start").state.players == ["human", "human", "human", "off"], done)
	free_all(cs)
	# everyone at the same moment
	p = played(["Ana", "Bo"])
	cs = p[1]
	for x: NetClient in cs:
		x.send_msg({t = "rematch"})
	pump(cs)
	check("fake close: Play again at once from both -> one vote, one start each", got(cs[0], "start").size() == 2
		and got(cs[1], "start").size() == 2 and got(cs[0], "error").is_empty() and got(cs[1], "error").is_empty())
	free_all(cs)


# ---------- Online ----------

class FakeMatch extends Node:
	var online := false
	var got: Array = []

	func start_online(_m: Dictionary, _net: Object) -> void:
		online = true

	func net_push(m: Dictionary) -> void:
		got.append(str(m.get("t", "")))

	func net_error(_m: Dictionary) -> void:
		pass

	func net_status(_s: String) -> void:
		pass

class FakeApp extends Node:
	var sheet_layer := Control.new()
	var ui_root := Control.new()
	var ludo := FakeMatch.new()
	var sl := FakeMatch.new()
	var screen := "home"
	var homes := 0
	var closed := 0
	var shows := true                    ## what online_vote answers (a result shows it / will)
	var votes_seen: Array = []

	func _init() -> void:
		sheet_layer.size = Vector2(390, 844)
		add_child(sheet_layer)
		add_child(ui_root)
		add_child(ludo)
		add_child(sl)

	func start_online(m: Dictionary, n: Object) -> void:
		screen = "ludo"
		ludo.start_online(m, n)

	func go_home() -> void:
		homes += 1
		screen = "home"
		ludo.online = false

	func online_vote(v: Dictionary) -> bool:
		votes_seen.append(v)
		return shows

	func online_closed() -> void:
		closed += 1

func opump(o: Online, others: Array, times := 4) -> void:
	for k in times:
		o.net._process(0.0)
		for c: NetClient in others:
			c._process(0.0)

func _online() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var room := NetFake.Room.new("K7QX2M", 5)
	var app := FakeApp.new()
	tree.root.add_child(app)
	var o := Online.new(app, client(room, "Ana"))
	app.add_child(o)
	o._connect(room.code)
	var b := client(room, "Bo")
	b.join(room.code)
	opump(o, [b])
	check("online: in the lobby", o.state == "lobby" and is_instance_valid(o.lobby_sheet))
	o.net.send_msg({t = "start"})
	opump(o, [b])
	force_over(room)
	opump(o, [b])
	check("online: over; anyone in the room can Play again", o.state == "over" and o.can_rematch())
	# someone else asks: the vote goes to the app (the result shows it)
	b.send_msg({t = "rematch"})
	opump(o, [b])
	check("online: the vote is kept and handed to the app", Online.vote_of(o.vote, o.net.member_id) == "wait"
		and app.votes_seen.size() == 1 and not is_instance_valid(o._prompt))
	o.rematch()
	opump(o, [b])
	check("online: Play again sends rematch (a yes) -> go -> the match", o.net.log_sent.any(func(m): return m.get("t") == "rematch")
		and o.state == "match" and o.vote.is_empty() and str(app.votes_seen[-1].get("result", "")) == "go")
	# nothing on screen shows it: the prompt sheet, whose Play answers
	force_over(room)
	opump(o, [b])
	app.shows = false
	b.send_msg({t = "rematch"})
	opump(o, [b])
	var pr := o._prompt
	check("online: elsewhere, a prompt sheet asks (Play / Leave)", is_instance_valid(pr) and pr.title_label.text.contains("Bo wants to play again"),
		pr.title_label.text if is_instance_valid(pr) else null)
	(pr.find_child("Yes", true, false) as Button).pressed.emit()
	opump(o, [b])
	check("online: the prompt's Play is a yes -> the match", o.state == "match")
	# you ask, the other leaves: fewer than 2 -> back in the lobby
	force_over(room)
	opump(o, [b])
	app.shows = true
	o.rematch()
	opump(o, [b])
	var homes := app.homes
	b.leave()
	opump(o, [b])
	check("online: few -> home, the lobby again (as host), its note says why", o.state == "lobby" and app.homes == homes + 1
		and is_instance_valid(o.lobby_sheet) and o.net.is_host() and o.vote.is_empty() and o.lobby_sheet.note.text.begins_with("Not enough players"),
		o.lobby_sheet.note.text if is_instance_valid(o.lobby_sheet) else null)
	# a newcomer during someone's vote sees the marks in the lobby; left out at the close: home
	var c := client(room, "Cy")
	c.join(room.code)
	opump(o, [c])
	o.net.send_msg({t = "start"})
	opump(o, [c])
	force_over(room)
	opump(o, [c])
	c.send_msg({t = "rematch"})
	opump(o, [c])
	room.vote_timeout()
	opump(o, [c])
	check("online: left out (rematch_out) -> idle, out of the room, home", o.state == "idle" and not o.net.in_room() and app.closed == 1
		and o.vote.is_empty(), [o.state, app.closed])
	tree.root.remove_child(app)
	app.free()
	free_all([b, c])


# ---------- the result screen ----------

func _vote(result := "", mine := "wait", ffa := false) -> Dictionary:
	var v := {t = "rematch", by = 1, until = 31000, now = 1000, players = [
		{id = 1, name = "Rafi", avatar = "ch-rafi", frame = "classic", vote = "yes"},
		{id = 2, name = "Shihab", avatar = "pawn-red", frame = "classic", vote = mine},
		{id = 3, name = "Mitu", avatar = "", frame = "", vote = "no"}]}
	if result != "":
		v.result = result
	if ffa:
		v.ffa = true
	return v

func _result() -> void:
	var st := [
		{color = 0, name = "You", kind = "you", place = 1, finished = true, progress = 1.0},
		{color = 2, name = "Rafi", kind = "human", place = 2, finished = false, progress = 0.4},
	]
	var r := ResultScreen.new({game = "ludo", online = true, host = true, me = "2", standings = st, human_won = true, reward = 0,
		xp_before = 10, xp_after = 110})
	r._revealed = true
	r._sync_buttons()
	check("result: no vote yet: Play again / Home, no card", not r.vote_card.visible and r.again_button.text == "Play again"
		and not r.again_button.disabled and r.home_button.text == "Home")
	r.set_vote(_vote())
	var names: Array = r.vote_card.find_child("Names", true, false).get_children()
	check("result: asked: the prompt (who asked), Play / Leave", r.vote_card.visible and r._vote_title.text == "Rafi wants to play again"
		and r.again_button.text == "Play" and not r.again_button.disabled and r.home_button.text == "Leave", [r._vote_title.text, r.again_button.text])
	check("result: everyone asked, with their answer (you as You)", names.size() == 3 and names.map(func(x): return x.get_meta("vote")) == ["yes", "wait", "no"]
		and (names[1].find_children("*", "Label", true, false)[0] as Label).text == "You")
	check("result: the countdown", r._vote_timer.text == "0:30" and r._vote_timer.get_parent().visible, r._vote_timer.text)
	r.set_vote(_vote("", "yes"))
	check("result: after your yes: waiting (Play again off), Leave", r._vote_title.text == "Waiting for the others…"
		and r.again_button.text == "Waiting…" and r.again_button.disabled and r.home_button.text == "Leave")
	r.set_vote(_vote("go", "yes", true))
	check("result: go: starting, no countdown, the free-for-all line", r._vote_title.text == "Starting a new game…" and r.again_button.text == "Starting…"
		and not r._vote_timer.get_parent().visible and r._vote_sub.visible and r._vote_sub.text.contains("everyone for themselves"))
	r.set_vote(_vote("go", "wait"))
	check("result: closed without you: no card (rematch_out follows)", not r.vote_card.visible)
	r.set_vote({})
	check("result: no vote: as before", not r.vote_card.visible and r.again_button.text == "Play again" and r.home_button.text == "Home")
	r.free()
	var r2 := ResultScreen.new({game = "ludo", online = true, host = true, me = "2", standings = st, human_won = true, vote = _vote()})
	check("result: a vote that opened before the screen shows at once", r2.vote_card.visible and r2.again_button.text == "Play")
	r2.free()


# ---------- the lobby sheet ----------

func _lobby() -> void:
	var s := LobbySheet.new("K7QX2M", "3", "ludo")
	s.update({code = "K7QX2M", host = 1, settings = {teams = false, game = "ludo"}, members = [
		{id = 1, name = "Rafi", avatar = "ch-rafi", level = 4, online = true, color = 0},
		{id = 2, name = "Mitu", avatar = "", level = 2, online = true, color = 1},
		{id = 3, name = "Cy", avatar = "", level = 1, online = true, color = 2}]}, false)
	s.set_vote({t = "rematch", by = 1, until = 2, now = 1, players = [
		{id = 1, name = "Rafi", vote = "yes"}, {id = 2, name = "Mitu", vote = "wait"}, {id = 3, name = "Cy", vote = "yes"}]})
	var rows := s._list.get_children()
	check("lobby: joined during a vote: ticks and Deciding…, the note", rows[0].find_child("In", true, false) != null
		and rows[1].find_child("Deciding", true, false) != null and rows[2].find_child("In", true, false) != null
		and s.note.text.contains("deciding"), s.note.text)
	s.set_vote({t = "rematch", by = 1, until = 2, now = 1, result = "go", players = []})
	rows = s._list.get_children()
	check("lobby: a closed vote clears the marks", rows[0].find_child("In", true, false) == null and not s.note.text.contains("deciding"))
	s.free()
