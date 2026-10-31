extends "res://tests/test_suite.gd"
## Recent players, friends and invites, client side (Social, FriendsSheet, InviteBanner, LongPress, the lobby, HUD and
## leaderboard hooks) against the in-process fakes (NetFake.SocialServer for /v1/social, NetFake.Hub for the rooms):
## the lists and their states (loading, offline with Try again, empty, rows), add / remove friends (the long-press
## question), Invite into the room you are in and into a new room when you are in none (its lobby opens), a ghost's and
## an invites-off person's answers being those of anyone, the banner (Join accepts and joins, Not now declines, an
## expired invite or one for your own room never shows), the invite push in the foreground, Settings' switch (sent
## again after being offline) and the pure texts. Nothing here writes the save or opens a socket.

var layer: Control
var _sp: Dictionary
var _spf: Dictionary


class App extends Node:
	var sheet_layer := Control.new()
	var ui_root := Control.new()
	var online: Online
	var screen := "home"
	var safe_top := 0.0

	func _init() -> void:
		sheet_layer.size = Vector2(390, 844)
		ui_root.size = Vector2(390, 844)
		add_child(ui_root)
		add_child(sheet_layer)

	func close_all_sheets() -> void:
		for c in sheet_layer.get_children():
			c.queue_free()


func run() -> void:
	_sandbox()
	var tree := Engine.get_main_loop() as SceneTree
	layer = Control.new()
	layer.size = Vector2(390, 844)
	tree.root.add_child(layer)
	_pure()
	await _long_press()
	await _lists()
	await _sheet()
	await _ask_friend()
	await _invite_flow()
	await _banner()
	await _prefs()
	_hooks()
	layer.queue_free()
	Social.set_instance(null)
	_restore()

func _sandbox() -> void:
	_sp = Save.profile
	_spf = Save.prefs
	Save.prefs = {}
	Save.normalize()
	if Save._timer.timeout.is_connected(Save.flush):
		Save._timer.timeout.disconnect(Save.flush)

func _restore() -> void:
	Save._dirty = false
	Save.profile = _sp
	Save.prefs = _spf
	if not Save._timer.timeout.is_connected(Save.flush):
		Save._timer.timeout.connect(Save.flush)

func frames(n := 3) -> void:
	for k in n:
		await (Engine.get_main_loop() as SceneTree).process_frame

const NOW := 1_800_000_000

## A Social on the fake (no timer, the fake's fixed clock), in the tree.
func social_on(fake: NetFake.SocialServer, app: Node = null) -> Social:
	var s := Social.new(app)
	s.poll_sec = 0.0
	s.http_fn = fake.http
	if fake.now == 0:
		fake.now = NOW
	s.clock = func() -> int: return fake.now
	layer.add_child(s)
	return s

func client(hub: NetFake.Hub, name: String) -> NetClient:
	var c := NetClient.new()
	c.use_save = false
	c.prefs = {}
	c.url_base = "ws://fake"
	c.session_fn = func() -> String: return "s-" + name
	c.profile_fn = func() -> Dictionary: return {name = name, avatar = "pawn-blue", frame = "classic"}
	c.make_transport = hub.transport_factory()
	c.http_fn = hub.http
	return c

func opump(o: Online, times := 4) -> void:
	for k in times:
		o.net._process(0.0)

## Pumps the room sockets while a coroutine runs (Online's joins), up to n frames or until done says so.
func pump_until(o: Online, done: Callable, n := 60) -> void:
	for k in n:
		opump(o)
		await frames(1)
		if done.call():
			return

## Waits up to n steps of 20 ms (real time: headless frames are very short) for f() to say true.
func until(f: Callable, n := 90) -> void:
	for k in n:
		if f.call():
			return
		await (Engine.get_main_loop() as SceneTree).create_timer(0.02).timeout

func confirm_yes(host: Node) -> bool:
	for k in 10:
		await frames(1)
		var q := _confirm_in((Engine.get_main_loop() as SceneTree).root)
		if q != null:
			(q.find_child("Yes", true, false) as Button).pressed.emit()
			await frames(4)
			return true
	return false

func _confirm_in(n: Node) -> Sheet:
	for c in n.get_children():
		if c is Sheet and (c as Sheet).has_meta("confirm") and not (c as Sheet)._closing:
			return c
		var d := _confirm_in(c)
		if d != null:
			return d
	return null


# ---------- pure ----------

func _pure() -> void:
	var now := NOW
	check("ago: minutes, hours, yesterday, days", Fmt.ago(now - 30, now) == "just now" and Fmt.ago(now - 300, now) == "5 min ago"
		and Fmt.ago(now - 7200, now) == "2h ago" and Fmt.ago(now - 90000, now) == "yesterday" and Fmt.ago(now - 4 * 86400, now) == "4 days ago")
	check("sub text: recent says the game and when", FriendsSheet.sub_text({game = "sl", played_at = now - 600}, "recent", now) == "10 min ago · Snakes & Ladders")
	check("sub text: a friend never played with says when added",
		FriendsSheet.sub_text({added_at = now - 3 * 86400, played_at = null, game = null}, "friends", now) == "Added 3 days ago")
	check("banner sub: game and spaced room", InviteBanner.sub_text({game = "ludo", code = "K7QX2M"}) == "Ludo · Room K7Q X2M")
	check("invite errors: person rate names them, total rate doesn't",
		Social.invite_error_text("rate", "person") % "Rafi" == "You invited Rafi a moment ago." and not "%s" in Social.invite_error_text("rate", "total"))
	check("invite errors: every code has words", Social.invite_error_text("offline") != Social.invite_error_text("room_full")
		and Social.invite_error_text("started") != "" and Social.invite_error_text("not_found") != "")
	check("save: Invites from players is on by default", Save.prefs.get("invites") == true)


# ---------- long press ----------

func _press(c: Control, down: bool, at := Vector2(10, 10)) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = at
	c.gui_input.emit(e)

func _long_press() -> void:
	var c := Control.new()
	c.size = Vector2(100, 40)
	layer.add_child(c)
	var held := [0]
	LongPress.attach(c, func(): held[0] += 1, 0.15)
	var ig := Control.new()
	ig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	LongPress.attach(ig, func(): pass)
	check("long press: attached; a control that ignored the mouse now passes presses on", LongPress.has(c) and ig.mouse_filter == Control.MOUSE_FILTER_PASS)
	ig.free()
	_press(c, true)
	await (Engine.get_main_loop() as SceneTree).create_timer(0.3).timeout
	check("long press: held long enough fires once", held[0] == 1, held)
	_press(c, false)
	_press(c, true)
	await (Engine.get_main_loop() as SceneTree).create_timer(0.05).timeout
	_press(c, false)
	await (Engine.get_main_loop() as SceneTree).create_timer(0.25).timeout
	check("long press: a tap doesn't", held[0] == 1, held)
	_press(c, true)
	var m := InputEventMouseMotion.new()
	m.position = Vector2(10, 40)
	c.gui_input.emit(m)
	await (Engine.get_main_loop() as SceneTree).create_timer(0.25).timeout
	check("long press: a drag (scrolling) doesn't", held[0] == 1, held)
	_press(c, false)
	_press(c, true)
	_press(c, true)                       # a touch and its emulated mouse press: one gesture
	await (Engine.get_main_loop() as SceneTree).create_timer(0.3).timeout
	check("long press: a touch with its emulated click fires once", held[0] == 2, held)
	check("long press: fire() for tests", LongPress.fire(c) and held[0] == 3 and not LongPress.fire(Control.new()))
	c.queue_free()


# ---------- the lists ----------

func _lists() -> void:
	var fake := NetFake.SocialServer.sample(NOW)
	var s := social_on(fake)
	var seen := [0]
	s.changed.connect(func(): seen[0] += 1)
	fake.prefs.invites = false
	var r := await s.refresh()
	check("lists: read", r.ok and s.state == "ok" and s.recent.size() == 5 and s.friends.size() == 2, [r, s.recent.size(), s.friends.size()])
	check("lists: newest first, friends marked", str(s.recent[0].name) == "Rafi" and bool(s.recent[0].friend) and not bool(s.recent[1].friend))
	check("lists: the server's invites setting wins", Save.prefs.invites == false)
	check("lists: changed was said", seen[0] >= 1)
	var calls := fake.calls.size()
	await s.refresh()
	check("lists: a fresh cache answers without a call", fake.calls.size() == calls)
	await s.refresh(true)
	check("lists: force reads again", fake.calls.size() == calls + 1)
	# add from Recent, remove
	var mitu: Dictionary = s.recent[1]
	var a := await s.add_friend(mitu)
	check("friends: add", a.ok and s.is_friend(str(mitu.uid)) and bool(s.recent[1].friend) and s.friends.size() == 3 and str(s.friends[1].uid) == str(mitu.uid), a)
	check("friends: the new friend keeps the last match together", str(s.friends[1].get("game")) == "sl" and int(s.friends[1].get("played_at", 0)) > 0)
	var rm := await s.remove_friend(str(mitu.uid))
	check("friends: remove", rm.ok and not s.is_friend(str(mitu.uid)) and not bool(s.recent[1].friend) and fake.friends.size() == 2)
	# offline: the state says so; a failed refresh keeps what is shown
	fake.offline = true
	await s.refresh(true)
	check("lists: a failed refresh keeps the lists", s.state == "ok" and s.recent.size() == 5)
	var s2 := social_on(fake)
	await s2.refresh()
	check("lists: offline from the start", s2.state == "offline" and s2.recent.is_empty())
	var add_off := await s2.add_friend(mitu)
	check("friends: offline add says offline", not add_off.ok and add_off.error == "offline")
	fake.offline = false
	Save.prefs.invites = true
	s.queue_free()
	s2.queue_free()

func _sheet() -> void:
	var fake := NetFake.SocialServer.sample(NOW)
	var s := social_on(fake)
	Social.set_instance(s)
	var f := FriendsSheet.new("ludo")
	f.social = s
	f.open(layer)
	check("sheet: opens on Room, with Create and Join as before", f.tab == "room" and f.create_button != null and f.join_button != null and f._panes.room.visible)
	f.show_tab("recent")
	await frames(4)
	var rows: Array = (f.lists.recent as Node).get_children().filter(func(n: Node) -> bool: return n.name.begins_with("Row_"))
	check("sheet recent: a row per person with the hint above", rows.size() == 5 and (f.lists.recent as Node).get_child(0).name == "Hint", rows.size())
	var first: Control = rows[0]
	check("sheet recent: name, game and when, a star on a friend", (first.find_child("Name", true, false) as Label).text == "Rafi"
		and (first.find_child("Sub", true, false) as Label).text == "4 min ago · Ludo" and first.find_child("Friend", true, false) != null
		and (rows[1] as Control).find_child("Friend", true, false) == null)
	check("sheet recent: rows long-press and Invite is a 48 px target", LongPress.has(first)
		and (first.find_child("Invite", true, false) as Button).get_combined_minimum_size().y >= UIKit.TAP)
	f.show_tab("friends")
	await frames(2)
	var frows: Array = (f.lists.friends as Node).get_children().filter(func(n: Node) -> bool: return n.name.begins_with("Row_"))
	check("sheet friends: both friends, the one never played with says when added", frows.size() == 2
		and ((frows[1] as Control).find_child("Sub", true, false) as Label).text == "Added 6 days ago", frows.size())
	f.close()
	# empty and offline
	var empty := NetFake.SocialServer.at(NOW)
	var s2 := social_on(empty)
	var g := FriendsSheet.new("sl", true)
	g.social = s2
	g.open(layer)
	await frames(4)
	check("sheet invite mode: Friends and Recent only, titled Invite friends", g.tab == "friends" and not g._panes.has("room") and g.create_button == null
		and g.title_label.text.to_lower().contains("invite"))
	check("sheet: empty friends says how to add", g.list_state == "list" and (g.lists.friends as Node).get_node_or_null("Empty") != null)
	g.show_tab("recent")
	await frames(2)
	check("sheet: empty recent says how people get there", (g.lists.recent as Node).get_node_or_null("Empty") != null)
	g.close()
	empty.offline = true
	var s3 := social_on(empty)
	var h := FriendsSheet.new("ludo")
	h.social = s3
	h.open(layer)
	h.show_tab("friends")
	await frames(4)
	var st: Node = (h.lists.friends as Node).get_node_or_null("State")
	check("sheet: offline says so with Try again", h.list_state == "offline" and st != null and st.find_child("Retry", true, false) != null)
	empty.offline = false
	(st.find_child("Retry", true, false) as Button).pressed.emit()
	await frames(4)
	check("sheet: Try again reads the lists", h.list_state == "list")
	h.close()
	for x in [s, s2, s3]:
		x.queue_free()
	await frames(2)

func _ask_friend() -> void:
	var fake := NetFake.SocialServer.sample(NOW)
	var s := social_on(fake)
	Social.set_instance(s)
	await s.refresh()
	var f := FriendsSheet.new("ludo")
	f.social = s
	f.open(layer)
	f.show_tab("recent")
	await frames(4)
	var mitu_row: Control = (f.lists.recent as Node).get_children().filter(func(n: Node) -> bool: return n.name.begins_with("Row_"))[1]
	LongPress.fire(mitu_row)
	var yes1 := await confirm_yes(layer)
	await until(func() -> bool: return s.last_toast != "")
	check("long-press a row: Add to friends? then added", yes1 and s.is_friend(str(s.recent[1].uid)) and s.last_toast == "Mitu added to friends", [yes1, s.last_toast, s.friends.size()])
	var rafi_row: Control = (f.lists.recent as Node).get_children().filter(func(n: Node) -> bool: return n.name.begins_with("Row_"))[0]
	LongPress.fire(rafi_row)
	s.last_toast = ""
	var yes2 := await confirm_yes(layer)
	await until(func() -> bool: return s.last_toast != "")
	check("long-press a friend: Remove? then removed", yes2 and not s.is_friend(str(s.recent[0].uid)) and s.last_toast == "Rafi removed from friends", s.last_toast)
	f.close()
	s.queue_free()
	await frames(2)


# ---------- invites ----------

func _invite_flow() -> void:
	var hub := NetFake.Hub.new(21)
	var app := App.new()
	layer.add_child(app)
	var o := Online.new(app, client(hub, "Ana"))
	o.coins_fn = func() -> int: return 5000
	o.level_fn = func() -> int: return 3
	app.add_child(o)
	app.online = o
	var fake := NetFake.SocialServer.sample(NOW)
	fake.hub = hub
	var s := social_on(fake, app)
	Social.set_instance(s)
	await s.refresh()
	var rafi: Dictionary = s.recent[0]
	# in no room: one is made, its lobby opens, then the invite goes
	var out := {}
	var go := func(): out.r = await s.invite(rafi, "sl")
	go.call()
	await pump_until(o, func() -> bool: return out.has("r"))
	check("invite in no room: a room is made, its lobby opens, the invite goes", out.has("r") and out.r.ok and o.state == "lobby"
		and is_instance_valid(o.lobby_sheet) and fake.sent.size() == 1 and fake.sent[0].code == o.net.code, [out, o.state])
	check("invite: the new room has the sheet's game", hub.rooms[o.net.code].settings.game == "sl")
	check("invite: the row says Invited, and Rafi is told nothing more here", s.was_invited(str(rafi.uid)) and s.last_toast == "Invite sent to Rafi", s.last_toast)
	# again within 10 minutes: the server's per-person limit, said kindly
	var again := await s.invite(rafi)
	check("invite again: per person, once per 10 minutes", not again.ok and again.error == "rate" and again.scope == "person"
		and s.last_toast == "You invited Rafi a moment ago.", [again, s.last_toast])
	# a ghost and someone with invites off: the very same answers
	var ghost: Dictionary = s.recent[4]
	var off: Dictionary = s.recent[3]
	fake.quiet[str(ghost.uid)] = true
	fake.quiet[str(off.uid)] = true
	var rg := await s.invite(ghost)
	var ro := await s.invite(off)
	var rm := await s.invite(s.recent[1])
	check("invite: a ghost, invites off and a person: the same answer", rg == ro and ro == rm and rm.ok, [rg, ro, rm])
	check("invite: (only the fake knows who it reached)", fake.reached.size() == 2 and fake.sent.size() == 4)
	# in a match: not now
	o._set_state("match")
	var busy := await s.invite(s.recent[2])
	check("invite during a match: Finish this game first", not busy.ok and busy.error == "busy" and s.last_toast == "Finish this game first.")
	o._set_state("lobby")
	# the lobby's Invite opens the lists in invite mode; long-press a member asks to add them
	o.lobby_sheet.invite_pressed.emit()
	await frames(2)
	var inv_sheet: FriendsSheet = null
	for c in app.sheet_layer.get_children():
		if c is FriendsSheet:
			inv_sheet = c
	check("lobby Invite: the lists, invite mode", inv_sheet != null and inv_sheet.invite_mode)
	if inv_sheet:
		inv_sheet.close()
	o.leave()
	await frames(2)
	app.queue_free()
	s.queue_free()
	await frames(2)

func _banner() -> void:
	var hub := NetFake.Hub.new(23)
	var app := App.new()
	layer.add_child(app)
	var o := Online.new(app, client(hub, "Ana"))
	app.add_child(o)
	app.online = o
	var fake := NetFake.SocialServer.sample(NOW)
	fake.hub = hub
	var s := social_on(fake, app)
	Social.set_instance(s)
	# a friend's room with them in its lobby
	var room := hub.add_room("K7QX2M")
	var host := client(hub, "Rafi")
	layer.add_child(host)
	host.join("K7QX2M")
	for k in 6:
		host._process(0.0)
	var rafi := NetFake.SocialServer.person("Rafi", "ch-rafi", 12, "gold")
	fake.add_invite(rafi, "ZZZZZ2", "ludo", -5)          # expired: never shows
	var inv := fake.add_invite(rafi, "K7QX2M", "ludo")
	s.poll()
	await frames(3)
	check("banner: the newest live invite shows", is_instance_valid(s.banner) and s.banner.get_parent() == app.ui_root
		and s.banner.title_label.text == "Rafi invited you" and s.banner.sub_label.text == "Ludo · Room K7Q X2M" and s.pending.is_empty())
	check("banner: Join and Not now are 48 px targets", s.banner.join_button.get_combined_minimum_size().y >= UIKit.TAP
		and s.banner.later_button.get_combined_minimum_size().y >= UIKit.TAP)
	check("banner: above the sheets", s.banner.z_index > 10)
	s.poll()
	await frames(2)
	check("banner: the same invite isn't queued twice", s.pending.is_empty())
	s.banner.join_button.pressed.emit()
	await pump_until(o, func() -> bool: return o.state == "lobby")
	check("banner Join: accepted, then the usual join of that room", fake.accepted == [inv.id] and o.state == "lobby" and o.net.code == "K7QX2M"
		and room.members.size() == 2, [fake.accepted, o.state])
	await frames(10)
	check("banner Join: the banner is gone", not is_instance_valid(s.banner))
	# an invite for the room you are in never shows; Not now declines
	fake.add_invite(rafi, "K7QX2M", "ludo")
	var other := fake.add_invite(NetFake.SocialServer.person("Mitu", "ch-mim", 8), "QQQQQ2", "sl")
	s.poll()
	await frames(3)
	check("banner: not for the room you are in", is_instance_valid(s.banner) and s.banner.invite.id == other.id)
	s.banner.later_pressed.emit()
	await frames(10)
	check("banner Not now: declined, gone", fake.declined == [other.id] and not is_instance_valid(s.banner))
	# only on Home, not over a match
	app.screen = "ludo"
	var third := fake.add_invite(NetFake.SocialServer.person("Nusrat"), "QQQQQ3")
	s.poll()
	await frames(3)
	check("banner: waits while a game is on screen", not is_instance_valid(s.banner) and s.pending.size() == 1)
	app.screen = "home"
	s.show_next()
	await frames(2)
	check("banner: shown back on Home", is_instance_valid(s.banner) and s.banner.invite.id == third.id)
	# it leaves by itself when the invite runs out
	s.banner.left_sec = 0.01
	await (Engine.get_main_loop() as SceneTree).create_timer(0.35).timeout   # (headless frames are short: real time)
	check("banner: an expired invite leaves by itself", not is_instance_valid(s.banner), [is_instance_valid(s.banner), s.banner.left_sec if is_instance_valid(s.banner) else -1.0, s.banner.invite if is_instance_valid(s.banner) else {}])
	# an invite push with the app open: the list is read at once (no toast)
	var fourth := fake.add_invite(NetFake.SocialServer.person("Sakib"), "QQQQQ4")
	var n := Notifications.new(app, null)
	n.notifier = FakeNotifier.new()
	layer.add_child(n)
	n._on_push_received({kind = "invite", link = "room:QQQQQ4", title = "Game invite", body = "Sakib invited you"})
	await frames(3)
	check("invite push in the foreground: the banner, not a toast", n.last_toast == null and is_instance_valid(s.banner) and s.banner.invite.id == fourth.id)
	n.queue_free()
	# accept of a gone room: said kindly, nothing joined
	o.leave()
	await frames(2)
	room.playing = true
	s._hide_banner()
	var fifth := fake.add_invite(rafi, "K7QX2M")
	s.poll()
	await frames(3)
	s.banner.join_button.pressed.emit()
	await frames(4)
	check("banner Join of a room that started: That invite has ended.", s.last_toast == "That invite has ended." and o.state == "idle" and fake.accepted.size() == 1, [s.last_toast, fifth.id])
	host.queue_free()
	app.queue_free()
	s.queue_free()
	await frames(2)

## Notifier stand-in: the signals Notifications connects to and the calls it makes (no plugin).
class FakeNotifier extends Node:
	signal opened(data)
	signal push_received(data)
	signal push_token(token)
	signal push_failed(code)
	signal permission_result(granted)
	func cancel_all() -> void:
		pass
	func take_launch_data() -> Dictionary:
		return {}
	func push_configured() -> bool:
		return false
	func permission_state() -> String:
		return "unsupported"

func _prefs() -> void:
	var fake := NetFake.SocialServer.sample(NOW)
	var s := social_on(fake)
	await s.set_invites(false)
	check("prefs: off is sent and kept", fake.prefs.invites == false and Save.prefs.invites == false and not Save.prefs.has("invites_sync"))
	fake.offline = true
	await s.set_invites(true)
	check("prefs: offline, kept to send later", Save.prefs.invites == true and bool(Save.prefs.get("invites_sync", false)) and fake.prefs.invites == false)
	fake.offline = false
	await s.refresh(true)
	await frames(2)
	check("prefs: sent with the next lists; the local choice wins over the server's old one", fake.prefs.invites == true and Save.prefs.invites == true
		and not Save.prefs.has("invites_sync"))
	s.queue_free()


# ---------- hooks: lobby, HUD, leaderboard ----------

func _hooks() -> void:
	var ls := LobbySheet.new("K7QX2M", "m1")
	ls.update({code = "K7QX2M", host = "m1", settings = {teams = false, game = "ludo"}, members = [
		{id = "m1", name = "Ana", avatar = "pawn-red", level = 3, online = true, color = 0},
		{id = "m2", name = "Bo", avatar = "pawn-blue", level = 5, online = true, color = 2}]}, true)
	var rows := ls._list.get_children()
	var asked := []
	var held := []
	ls.invite_pressed.connect(func(): asked.append(true))
	ls.member_held.connect(func(id: String, n: String): held.append([id, n]))
	var inv := (rows[-1] as Node).find_child("Invite", true, false) as Button
	check("lobby: the open seat has Invite", inv != null)
	if inv:
		inv.pressed.emit()
	check("lobby: Invite asks", asked.size() == 1)
	check("lobby: your own row has no long-press, the others do", not LongPress.has(rows[0]) and LongPress.has(rows[1]))
	LongPress.fire(rows[1])
	check("lobby: long-press says who", held == [["m2", "Bo"]], held)
	ls.free()
	var hud := LudoHUD.new()
	hud.size = Vector2(390, 844)
	layer.add_child(hud)
	var seats := [{color = 0, id = "1", name = "Ana", avatar = "pawn-green", frame = "classic", bot = false, online = true},
		{color = 2, id = "2", name = "Bo", avatar = "pawn-blue", frame = "classic", bot = false, online = true}]
	var ns := NetLudo.new()
	ns.begin({n = 0, seats = seats, state = LudoRules.new_game(["human", "off", "human", "off"])}, "2")
	hud.set_online(true, ns.me, ns.seats)
	hud.setup(ns.S)
	hud.update(ns.S, 0)
	var tiles := []
	hud.tile_held.connect(func(c: int): tiles.append(c))
	LongPress.fire(hud.tiles[2])
	LongPress.fire(hud.tiles[0])
	LongPress.fire(hud.tiles[1])
	check("hud: long-press another person's tile (not yours, not an empty seat)", tiles == [0], tiles)
	hud.queue_free()
	var lb := LeaderboardSheet.new()
	lb.auto_load = false
	var row := lb._row({rank = 4, uid = "0123456789abcdef", name = "Rafi", avatar = "ch-rafi", frame = "classic", level = 12, value = 900}, "xp")
	var plain := lb._row({rank = 5, name = "Old", avatar = "pawn-red", frame = "classic", level = 2, value = 800}, "xp")
	var mine := lb._row({rank = 6, uid = "fedcba9876543210", name = "Me", level = 2, value = 700}, "xp", 6)
	check("leaderboard: rows with a handle long-press (not yours)", LongPress.has(row) and not LongPress.has(plain) and not LongPress.has(mine))
	for x in [row, plain, mine]:
		x.free()
	lb.free()
