extends "res://tests/test_suite.gd"
## Notifications (scripts/net/notifications.gd): launch / opened routing of every link, the cid count, a foreground
## push as a tappable toast, the reminders handed to the plugin on pause and taken back on resume, the away signal to
## a room, the soft permission prompt and its re-ask rules, push registration through the account (token, prefs, time
## zone, promos topic, DELETE on an account switch), the Settings switches, and the Save defaults. A fake plugin
## stands behind the real Notifier wrapper; the fake server answers (tests/fake_accounts.gd, scripts/net/net_fake.gd).
## Save is swapped for a throwaway profile with its debounced write cut, so user://save.json is never touched.

const Fake := preload("res://tests/fake_accounts.gd")
const SaveScript := preload("res://scripts/core/save.gd")
const NOW := 1793000000
const ROOM := "K7QX2M"

var _done := false
var _sp: Dictionary
var _spf: Dictionary
var _root: Node

func run() -> void:
	_root = (Engine.get_main_loop() as SceneTree).root
	_sandbox()
	_all()
	_restore()
	check("notifications: the suite ran to the end", _done)

func _sandbox() -> void:
	_sp = Save.profile
	_spf = Save.prefs
	Save.profile = Fake.base_profile()
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

func _all() -> void:
	_save_defaults()
	_should_ask()
	_routing()
	await _opens_and_toasts()
	_reminders()
	await _away_and_rewards()
	await _soft_prompt()
	await _push()
	_settings()
	_done = true


# ---------- harness ----------

## The Android plugin's side of Notifier: the methods and signals the wrapper uses, with what was asked recorded.
class FakePlugin extends RefCounted:
	signal permission_result(granted: bool)
	signal opened(data: Dictionary)
	signal push_token(token: String)
	signal push_failed(code: String)
	signal push_received(data: Dictionary)
	var permission := "granted"
	var grant := true
	var requests := 0
	var items := {}                       # id -> {at, channel, title, body, link}
	var cancel_alls := 0
	var launch := {}
	var inits := 0
	var token := "TOK1"
	var topic_calls: Array = []           # ["sub" | "unsub", topic]

	func permission_state() -> String:
		return permission
	func request_permission() -> void:
		requests += 1
		permission = "granted" if grant else "denied"
		permission_result.emit(grant)
	func schedule(id: String, at: int, channel: String, title: String, body: String, link: String) -> void:
		items[id] = {at = at, channel = channel, title = title, body = body, link = link}
	func cancel(id: String) -> void:
		items.erase(id)
	func cancel_all() -> void:
		cancel_alls += 1
		items.clear()
	func scheduled() -> Array:
		return items.keys()
	func take_launch_data() -> Dictionary:
		var d := launch
		launch = {}
		return d
	func push_init(_p: String, _a: String, _k: String, _s: String) -> void:
		inits += 1
		push_token.emit(token)
	func push_subscribe(t: String) -> void:
		topic_calls.append(["sub", t])
	func push_unsubscribe(t: String) -> void:
		topic_calls.append(["unsub", t])
	func push_delete_token() -> void:
		pass
	func get_status() -> Dictionary:
		return {}
	## A notification tapped while the game runs.
	func tap(d: Dictionary) -> void:
		launch = d
		opened.emit(d)

class FakeShop extends RefCounted:
	var tabs: Array = []
	func show_tab(t: String) -> void:
		tabs.append(t)

## main.gd's side: the screen, the layers, the tabs; every call recorded. Named "Main" so Sheet.confirm finds its layer.
class FakeApp extends Node:
	var sheet_layer := Control.new()
	var ui_root := Control.new()
	var screen := "home"
	var account: Account
	var online: Online
	var calls: Array = []
	var top: Object = null

	func _init() -> void:
		name = "Main"
		sheet_layer.size = Vector2(390, 844)
		ui_root.size = Vector2(390, 844)
		add_child(sheet_layer)
		add_child(ui_root)

	func close_all_sheets() -> void:
		calls.append("close")
	func _on_tab(t: String) -> void:
		calls.append("tab:" + t)
		if t == "shop":
			top = FakeShop.new()
	func go_home() -> void:
		screen = "home"
	func _top_sheet() -> Variant:
		return top if top != null else Sheet.top_sheet(sheet_layer)

## An app with a notifier on the fake plugin, a clock, and (when `hub` / `fake` are given) an Online and an Account.
func rig(fake: Fake = null, hub: NetFake.Hub = null) -> Dictionary:
	var app := FakeApp.new()
	_root.add_child(app)
	var plugin := FakePlugin.new()
	var notifier := Notifier.new(plugin, false)
	var r := {app = app, plugin = plugin, notifier = notifier}
	if fake != null:
		var a := Account.new()
		a.url_base = "ws://fake"
		a.http_fn = fake.http
		_root.add_child(a)
		app.account = a
		r.acc = a
	if hub != null:
		var c := NetClient.new()
		c.use_save = false
		c.prefs = {}
		c.url_base = "ws://fake"
		c.session_fn = func() -> String: return "s-ana"
		c.profile_fn = func() -> Dictionary: return {name = "Ana", avatar = "pawn-blue", frame = "classic"}
		c.make_transport = hub.transport_factory()
		c.http_fn = hub.http
		var o := Online.new(app, c)
		o.reveal_fast = true
		app.add_child(o)
		app.online = o
		r.online = o
	return r

func start(r: Dictionary) -> Notifications:
	var n := Notifications.new(r.app, r.notifier)
	n.clock = func() -> int: return NOW
	r.app.add_child(n)
	r.n = n
	return n

func drop(r: Dictionary) -> void:
	if r.has("acc"):
		_root.remove_child(r.acc)
		Account.set_instance(null)
		r.acc.free()
	r.app.free()

func pump(o: Online, times := 4) -> void:
	for k in times:
		o.net._process(0.0)
		o.quick_q._process(0.0)

func reset_prefs() -> void:
	Save.prefs = {}
	Save.normalize()


# ---------- Save defaults ----------

func _save_defaults() -> void:
	var sv: Node = SaveScript.new()
	sv.profile = {}
	sv.prefs = {}
	sv._ensure()
	check("save: every notification switch is on by default, nothing asked yet",
		SaveScript.NOTIF_KEYS.all(func(k): return sv.prefs[k] == true) and sv.prefs.notif_asked == 0 and sv.prefs.notif_asked_at == 0, sv.prefs)
	check("save: the keys are the contract's", SaveScript.NOTIF_KEYS == ["notif", "notif_rewards", "notif_reminders", "notif_game", "notif_offers"])
	sv.prefs = {notif = false, notif_game = false, notif_asked = 2, notif_asked_at = 5, notif_offers = "junk"}
	sv._ensure()
	check("save: saved choices are kept, damage falls back to on",
		sv.prefs.notif == false and sv.prefs.notif_game == false and sv.prefs.notif_rewards == true and sv.prefs.notif_asked == 2 and sv.prefs.notif_asked_at == 5, sv.prefs)
	sv.reset_progress()
	check("save: Reset progress keeps the notification choices and the ask count",
		sv.prefs.notif == false and sv.prefs.notif_game == false and sv.prefs.notif_asked == 2, sv.prefs)
	sv.free()


# ---------- the soft prompt's rules ----------

func _should_ask() -> void:
	var day := Notifications.ASK_GAP_SEC
	check("ask rules: the first win asks", Notifications.should_ask({}, "ask", NOW))
	check("ask rules: only while the phone has not been asked", not Notifications.should_ask({}, "granted", NOW) and not Notifications.should_ask({}, "denied", NOW) and not Notifications.should_ask({}, "unsupported", NOW))
	check("ask rules: not with notifications off", not Notifications.should_ask({notif = false}, "ask", NOW))
	check("ask rules: not again within 3 days", not Notifications.should_ask({notif_asked = 1, notif_asked_at = NOW - day + 1}, "ask", NOW))
	check("ask rules: again after 3 days", Notifications.should_ask({notif_asked = 1, notif_asked_at = NOW - day}, "ask", NOW))
	check("ask rules: the third ask is the last", Notifications.should_ask({notif_asked = 2, notif_asked_at = 1}, "ask", NOW) and not Notifications.should_ask({notif_asked = 3, notif_asked_at = 1}, "ask", NOW))


# ---------- routing ----------

func _routing() -> void:
	var hub := NetFake.Hub.new(5)
	hub.add_room(ROOM)
	var r := rig(null, hub)
	var n := start(r)
	var app: FakeApp = r.app
	check("launch: nothing waiting, no launch route", not n.take_launch())
	check("launch: the plugin was told to drop every scheduled reminder", r.plugin.cancel_alls == 1)
	for link in ["daily", "spin", "free", "leaderboard"]:
		app.calls.clear()
		check("route %s: its sheet opens on Home" % link, n.route(link) and app.calls == ["close", "tab:" + link], app.calls)
	app.calls.clear()
	app.top = null
	check("route shop: the Shop", n.route("shop") and app.calls == ["close", "tab:shop"] and app.top.tabs == [], app.calls)
	for pair in [["shop:dice:gold", "dice"], ["shop:room:neon", "rooms"], ["shop:scene:frost", "scenes"], ["shop:emotes:friends", "emotes"], ["shop:nothing:x", "rooms"]]:
		app.top = null
		n.route(pair[0])
		check("route %s: the Shop on its tab" % pair[0], app.top != null and app.top.tabs == [pair[1]], app.top.tabs if app.top else null)
	app.top = null
	app.calls.clear()
	check("route home / unknown / empty: nothing to open", not n.route("home") and not n.route("") and not n.route("nowhere:1") and app.calls.is_empty())
	check("route: a game on screen is never left", _in_game(app, n))
	var o: Online = r.online
	check("route room: rejoins through the online flow", n.route("room:" + ROOM) and o.state in ["joining", "lobby"], o.state)
	pump(o, 6)
	check("route room: we are in that room", o.net.code == ROOM and o.net.in_room(), o.net.code)
	app.calls.clear()
	check("route room: already in a room: another room is ignored, ours is fine", not n.route("room:ABCDEF") and n.route("room:" + ROOM) and app.calls.is_empty(), app.calls)
	check("route room: a bad code opens nothing", not n.route("room:"))
	o.net.leave()
	drop(r)

func _in_game(app: FakeApp, n: Notifications) -> bool:
	app.screen = "ludo"
	app.calls.clear()
	var ok := not n.route("daily") and not n.route("room:" + ROOM) and app.calls.is_empty()
	app.screen = "home"
	return ok


# ---------- opens, cid, toasts ----------

func _opens_and_toasts() -> void:
	var fake := Fake.new()
	var hub := NetFake.Hub.new(5)
	hub.add_room(ROOM)
	var r := rig(fake, hub)
	var acc: Account = r.acc
	await acc.sign_in_guest()
	r.plugin.launch = {link = "spin", cid = "c-launch", source = "push"}
	var n := start(r)
	var app: FakeApp = r.app
	check("launch: the notification that started the app is routed once", n.take_launch() and app.calls == ["close", "tab:spin"] and not n.take_launch(), app.calls)
	check("launch: a campaign's cid is counted on the server", fake.push_opens == ["c-launch"], fake.push_opens)
	# tapped while the game runs
	app.calls.clear()
	r.plugin.tap({link = "daily", cid = "", source = "local"})
	check("opened: a local reminder tapped while running goes to its link, nothing counted", app.calls == ["close", "tab:daily"] and fake.push_opens == ["c-launch"], app.calls)
	app.calls.clear()
	r.plugin.tap({link = "leaderboard", cid = "c2", source = "push"})
	check("opened: a campaign push is counted and routed", app.calls == ["close", "tab:leaderboard"] and fake.push_opens == ["c-launch", "c2"], fake.push_opens)
	# before Home: held until take_launch
	app.screen = "welcome"
	app.calls.clear()
	r.plugin.tap({link = "free", cid = "c3", source = "push"})
	check("opened: before Home it waits (the cid is counted at once)", app.calls.is_empty() and fake.push_opens.has("c3"))
	app.screen = "home"
	check("opened: Home up -> take_launch routes it", n.take_launch() and app.calls == ["close", "tab:free"], app.calls)
	# foreground pushes
	app.calls.clear()
	r.plugin.push_received.emit({title = "Weekly result", body = "You finished #4 on last week's board!", link = "leaderboard", cid = "", kind = "weekly"})
	var pill := n.last_toast
	check("push received: a toast with the title and the text, that takes taps", pill != null and pill.mouse_filter == Control.MOUSE_FILTER_STOP, pill)
	var tap := InputEventMouseButton.new()
	tap.button_index = MOUSE_BUTTON_LEFT
	tap.pressed = true
	if pill:
		pill.gui_input.emit(tap)
	check("push received: tapping the toast opens its link", app.calls == ["close", "tab:leaderboard"], app.calls)
	# a turn for the room on screen is ignored
	var o: Online = r.online
	o.join_code(ROOM)
	pump(o, 6)
	r.plugin.push_received.emit({title = "Your turn", body = "Zed is waiting for you in room " + ROOM, link = "room:" + ROOM, cid = "", kind = "turn"})
	check("push received: a turn for the room we are in shows nothing", n.last_toast == null)
	r.plugin.push_received.emit({title = "Your turn", body = "Zed is waiting for you in room ABCDEF", link = "room:ABCDEF", cid = "", kind = "turn"})
	check("push received: a turn for another room is a toast", n.last_toast != null)
	r.plugin.push_received.emit({title = "Friend joined", body = "Zed joined room " + ROOM, link = "room:" + ROOM, cid = "", kind = "joined"})
	check("push received: other kinds for our room are toasts", n.last_toast != null)
	r.plugin.push_received.emit({title = "", body = "", link = "home", cid = "", kind = "x"})
	check("push received: an empty push shows nothing", n.last_toast == null)
	o.net.leave()
	Toast.clear(app.ui_root)
	drop(r)


# ---------- reminders ----------

func _reminders() -> void:
	reset_prefs()
	var r := rig()
	var n := start(r)
	var p: FakePlugin = r.plugin
	var tz := Notifications.tz_offset_s()
	var want := NotifPlan.plan(NOW, tz, n.plan_state(NOW))
	check("reminders: a fresh profile has something to schedule", want.size() >= 3, want.size())
	n._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	check("reminders: pausing schedules the plan (cancel_all first, then each)", p.items.size() == want.size() and p.cancel_alls == 2
		and want.all(func(w): return p.items.has(w.id) and p.items[w.id].at == w.at and p.items[w.id].link == w.link and p.items[w.id].channel == w.channel), [p.items, want])
	n._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	check("reminders: resuming takes them all back", p.items.is_empty() and p.cancel_alls == 3)
	n._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	check("reminders: closing schedules them too", p.items.size() == want.size())
	n.schedule_now()
	check("reminders: scheduling twice leaves one set", p.items.size() == want.size())
	# the switches
	Save.prefs.notif_rewards = false
	n.schedule_now()
	check("reminders: Rewards off leaves only the come-backs", p.items.keys().all(func(k): return k.begins_with("cb")) and p.items.size() == 3, p.items.keys())
	Save.prefs.notif_rewards = true
	Save.prefs.notif_reminders = false
	n.schedule_now()
	check("reminders: Reminders off leaves only the rewards", p.items.keys().all(func(k): return k.begins_with("rw")) and not p.items.is_empty(), p.items.keys())
	Save.prefs.notif_reminders = true
	Save.prefs.notif = false
	n.schedule_now()
	check("reminders: the master switch off schedules nothing (and clears)", p.items.is_empty())
	Save.prefs.notif = true
	# the phone's permission
	for state in ["ask", "denied", "unsupported"]:
		p.permission = state
		n.schedule_now()
		check("reminders: permission '%s' schedules nothing" % state, p.items.is_empty())
	p.permission = "granted"
	# the reward times: the profile's, then the server's
	Save.profile.last_spin = NotifPlan.day_key(NOW, tz)
	var st := n.plan_state(NOW)
	check("reminders: a spin used today is ready at the next local midnight", st.ready.spin == NotifPlan.day_start(NOW, tz) + 86400 and st.ready.daily == NOW, st.ready)
	check("reminders: the plan state carries the switches and the close time", st.enabled and st.rewards and st.reminders and st.last_play == NOW)
	drop(r)
	Save.profile.last_spin = ""


func _away_and_rewards() -> void:
	reset_prefs()
	var fake := Fake.new()
	var hub := NetFake.Hub.new(5)
	var room := hub.add_room(ROOM)
	var r := rig(fake, hub)
	var acc: Account = r.acc
	await acc.sign_in_guest()
	var n := start(r)
	var o: Online = r.online
	n._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	check("away: not in a room: nothing sent", room.aways.is_empty())
	o.net.join(ROOM)
	pump(o, 6)
	check("away: connected to the room", o.net.is_open(), o.net.status)
	n._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	pump(o)
	check("away: pausing says {away, on: true}", room.aways.size() == 1 and room.aways[0].on == true, room.aways)
	n._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	pump(o)
	check("away: resuming says {away, on: false}", room.aways.size() == 2 and room.aways[1].on == false, room.aways)
	check("away: the fake room took it quietly (no error)", o.net.status != "error")
	# the server's reward times
	check("rewards: the account's times are used while signed in (fetched on resume)", fake.count("/v1/rewards") == 1 and acc.rewards_at == fake.rewards_next, [acc.rewards_at, fake.rewards_next])
	var st := n.plan_state(NOW)
	check("rewards: the plan reads the server's next_at", st.ready.daily == fake.rewards_next.daily and st.ready.free == fake.rewards_next.free, st.ready)
	await acc.free_coins()
	check("rewards: a claim's next_at replaces the old time", acc.rewards_at.free == 1, acc.rewards_at)
	acc.enabled = false
	check("rewards: the account off: the offline rules again", n.plan_state(NOW).ready.free != 1)
	acc.enabled = true
	acc.reset_identity()
	check("rewards: a new identity forgets them", acc.rewards_at.is_empty())
	o.net.leave()
	drop(r)


# ---------- the soft prompt ----------

func _soft_prompt() -> void:
	reset_prefs()
	var r := rig()
	var n := start(r)
	var p: FakePlugin = r.plugin
	var app: FakeApp = r.app
	p.permission = "ask"
	n.note_win()
	check("prompt: a win with the phone not asked wants the prompt", n._ask_wanted)
	n._ask()
	var sheet := Sheet.top_sheet(app.sheet_layer)
	check("prompt: the sheet asks the contract's question", sheet != null and sheet.has_meta("confirm") and _texts(sheet).has(Notifications.ASK_TEXT), _texts(sheet) if sheet else null)
	check("prompt: counted as asked at once", Save.prefs.notif_asked == 1 and Save.prefs.notif_asked_at == NOW)
	var no := sheet.find_child("No", true, false) as Button
	check("prompt: the buttons say Not now / Yes", no.text == "Not now" and (sheet.find_child("Yes", true, false) as Button).text == "Yes")
	no.pressed.emit()
	check("prompt: Not now does not ask the phone", p.requests == 0)
	purge(app)
	n.note_win()
	check("prompt: ... and not again at the next win straight away", not n._ask_wanted)
	Save.prefs.notif_asked_at = NOW - Notifications.ASK_GAP_SEC - 1
	n.note_win()
	check("prompt: 3 days later a win asks again", n._ask_wanted)
	n._ask()
	sheet = Sheet.top_sheet(app.sheet_layer)
	check("prompt: second ask counted", Save.prefs.notif_asked == 2)
	(sheet.find_child("Yes", true, false) as Button).pressed.emit()
	purge(app)
	check("prompt: Yes asks the phone (the system dialog)", p.requests == 1 and p.permission == "granted")
	n.note_win()
	check("prompt: granted: never again", not n._ask_wanted)
	# the third and last
	p.permission = "ask"
	Save.prefs.notif_asked = 2
	Save.prefs.notif_asked_at = 1
	n.note_win()
	n._ask()
	Sheet.top_sheet(app.sheet_layer).find_child("No", true, false).pressed.emit()
	purge(app)
	Save.prefs.notif_asked_at = 1
	n.note_win()
	check("prompt: three asks in all", Save.prefs.notif_asked == 3 and not n._ask_wanted)
	# a sheet already open: no prompt over it
	reset_prefs()
	p.permission = "ask"
	n.note_win()
	app.top = FakeShop.new()
	n._ask()
	check("prompt: not over another sheet (and not counted)", Save.prefs.notif_asked == 0 and Sheet.top_sheet(app.sheet_layer) == null)
	app.top = null
	# notifications off
	Save.prefs.notif = false
	n.note_win()
	check("prompt: notifications off: no prompt", not n._ask_wanted)
	Save.prefs.notif = true
	check("prompt: the permission shown to Settings is the phone's", Notifications.permission() == "ask")
	drop(r)

## Closed sheets stay in the layer until their animation ends: take them out.
func purge(app: FakeApp) -> void:
	for c in app.sheet_layer.get_children():
		c.free()

func _texts(n: Node) -> Array:
	var out := []
	if n is Label:
		out.append((n as Label).text)
	for c in n.get_children():
		out.append_array(_texts(c))
	return out


# ---------- push ----------

func _push() -> void:
	reset_prefs()
	var keys := {project_id = "p", app_id = "a", api_key = "k", sender_id = "s"}
	var old := {}
	for k in Notifier.PUSH_SETTINGS:
		var key: String = Notifier.PUSH_SETTINGS[k]
		old[k] = ProjectSettings.get_setting(key) if ProjectSettings.has_setting(key) else null   # (null removes it again)
		ProjectSettings.set_setting(Notifier.PUSH_SETTINGS[k], keys[k])
	var fake := Fake.new()
	var r := rig(fake)
	var acc: Account = r.acc
	var p: FakePlugin = r.plugin
	var n := start(r)
	check("push: no session yet: Firebase is not started", p.inits == 0 and fake.push_tokens.is_empty())
	await acc.sign_in_guest()
	check("push: the account is up: Firebase starts, the token is registered with both prefs on and the zone",
		p.inits == 1 and fake.push_tokens.has("TOK1") and fake.push_tokens.TOK1.prefs == {game = true, offers = true}
		and fake.push_tokens.TOK1.tz_offset_min == Notifications.tz_offset_s() / 60 and fake.last("/v1/push/token").body.platform == "android", fake.push_tokens)
	check("push: the promos topic is subscribed", p.topic_calls == [["sub", "promos"]], p.topic_calls)
	var posts := fake.count("/v1/push/token")
	n.prefs_changed()
	check("push: a change that is none sends nothing", fake.count("/v1/push/token") == posts and p.topic_calls.size() == 1)
	Save.prefs.notif_offers = false
	n.prefs_changed()
	check("push: News & offers off: the prefs follow and the topic is left", fake.push_tokens.TOK1.prefs == {game = true, offers = false} and p.topic_calls.back() == ["unsub", "promos"], [fake.push_tokens, p.topic_calls])
	Save.prefs.notif_offers = true
	Save.prefs.notif_game = false
	n.prefs_changed()
	check("push: Game alerts off: game false, the topic back on", fake.push_tokens.TOK1.prefs == {game = false, offers = true} and p.topic_calls.back() == ["sub", "promos"], [fake.push_tokens, p.topic_calls])
	Save.prefs.notif = false
	n.prefs_changed()
	check("push: the master switch off turns both off", fake.push_tokens.TOK1.prefs == {game = false, offers = false} and p.topic_calls.back() == ["unsub", "promos"])
	Save.prefs.notif = true
	Save.prefs.notif_game = true
	n.prefs_changed()
	# a token refresh
	p.push_token.emit("TOK2")
	check("push: a refreshed token is registered", fake.push_tokens.has("TOK2") and fake.push_tokens.TOK2.prefs == {game = true, offers = true})
	# another account on this phone: the old one lets go of the token first
	var calls_before := fake.calls.size()
	acc.account = {id = "acc2", guest = true}
	acc._set_session("sess-two")
	acc.account_changed.emit()
	var seq := fake.calls.slice(calls_before).filter(func(c): return c.path == "/v1/push/token").map(func(c): return c.method)
	check("push: an account switch: DELETE (the old session) then POST (the new one)", seq == [HTTPClient.METHOD_DELETE, HTTPClient.METHOD_POST], seq)
	check("push: the token now belongs to the new session", fake.push_tokens.get("TOK2", {}).get("session", "") == "sess-two", fake.push_tokens)
	var del := fake.calls.slice(calls_before).filter(func(c): return c.method == HTTPClient.METHOD_DELETE)
	check("push: the DELETE named the token and used the session it was registered under", del.size() == 1 and del[0].body.token == "TOK2" and del[0].session == Fake.SESSION, del)
	# Firebase failures
	p.push_failed.emit("subscribe:boom")
	check("push: a topic failure does not restart Firebase", n._push_started)
	p.push_failed.emit("error:SERVICE_NOT_AVAILABLE")
	check("push: a start failure allows another try", not n._push_started)
	# the plugin's own push_configured is off without the settings
	for k in old:
		ProjectSettings.set_setting(Notifier.PUSH_SETTINGS[k], old[k])
	check("push: without the project settings it stays off", not Notifier.push_configured())
	drop(r)
	var r2 := rig(fake)
	var n2 := start(r2)
	await r2.acc.sign_in_guest()
	check("push: off (no settings): Firebase is never started", r2.plugin.inits == 0)
	drop(r2)


# ---------- the Settings sheet ----------

func _settings() -> void:
	reset_prefs()
	var plain := SettingsSheet.new()
	check("settings: without Notifications the section is built and quiet", plain._notif_lines.size() == 4 and not plain._notif_note.visible)
	plain.free()
	var r := rig()
	var n := start(r)
	var p: FakePlugin = r.plugin
	p.permission = "granted"
	var s := SettingsSheet.new()
	var changed := [0]
	s.prefs_changed.connect(func(): changed[0] += 1)
	check("settings: the master switch and four kinds", s._notif_lines.size() == 4 and not s._notif_note.visible and s._notif_lines.all(func(l): return l.modulate.a == 1.0))
	s._on_notif(false)
	check("settings: master off saves, dims the kinds, tells the game", Save.prefs.notif == false and s._notif_lines.all(func(l): return l.modulate.a < 1.0) and changed[0] == 1)
	p.permission = "ask"
	s._on_notif(true)
	check("settings: master on while the phone has not been asked: the system dialog", p.requests == 1 and Save.prefs.notif == true and p.permission == "granted")
	p.permission = "granted"
	s._on_notif(false)
	s._on_notif(true)
	check("settings: master on with permission granted asks nothing", p.requests == 1)
	p.permission = "denied"
	s._on_notif(false)
	check("settings: denied with the master off: no hint", not s._notif_note.visible)
	s._on_notif(true)
	check("settings: denied with the master on: the one-line hint", s._notif_note.visible and s._notif_note.text == "Turn on notifications for Ludo Zing in your phone settings" and p.requests == 1, s._notif_note.text)
	p.permission = "granted"
	n.permission_changed.emit("granted")
	check("settings: the hint goes when the phone says yes", not s._notif_note.visible)
	var ids := ["notif_rewards", "notif_reminders", "notif_game", "notif_offers"]
	var sw: Array = []
	for line in s._notif_lines:
		sw.append(_find_switch(line))
	check("settings: each kind is a switch on its own pref", sw.size() == 4 and sw.all(func(x): return x != null))
	sw[2].button_pressed = false
	check("settings: a kind's switch writes its pref and tells the game", Save.prefs.notif_game == false and changed[0] > 2 and Save.prefs.notif_rewards == true)
	s.free()
	drop(r)

func _find_switch(n: Node) -> SettingsSheet.Switch:
	if n is SettingsSheet.Switch:
		return n
	for c in n.get_children():
		var f: SettingsSheet.Switch = _find_switch(c)
		if f != null:
			return f
	return null
