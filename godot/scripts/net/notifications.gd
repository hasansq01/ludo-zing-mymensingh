class_name Notifications
extends Node
## Notifications end to end (server/NOTIFICATIONS.md "N-GAME"): the local reminders, push registration, the opens and
## the permission question. main.gd owns one (`notifications`); sheets reach it through Notifications.instance().
##
##   take_launch()           after launch: the notification that started the app, routed (true when it was)
##   schedule_now()          the app is going away: cancel_all, then NotifPlan's reminders (also on pause / close)
##   prefs_changed()         a Settings switch moved: push preferences and the promos topic follow
##   ask_permission()        Settings' master switch turned on while the phone has not been asked
##   note_win() / maybe_ask() after a win: the soft prompt once the player is home (should_ask has the rules)
##   route(link)             open a deep link: home, daily, spin, free, shop[:kind:id], room:CODE, leaderboard
## Local reminders and the plugin come from Notifier (scripts/net/notifier.gd, a safe stub off Android); the account
## session and the push endpoints from Account; the room's `away` signal goes through Online's NetClient.
## Reminders go in on pause / close and out on resume / launch: while the player is here nothing is scheduled.

## The permission state changed (the answer to a request): "granted" | "denied" | "ask" | "unsupported".
signal permission_changed(state: String)

const PROMOS := "promos"
const ASK_GAP_SEC := 3 * 86400           # the soft prompt again after a "Not now": at least this long, ...
const ASK_MAX := 3                       # ... and three times in all
const ASK_TITLE := "Stay in the loop?"
const ASK_TEXT := "Get a heads-up when your free spin and daily reward are ready?"
const TOAST_SEC := 4.0

static var _inst: Notifications = null

var app: Node                            ## main (screen, sheet_layer, ui_root, account, online, _on_tab, go_home, ...)
var notifier: Node                       ## Notifier, or a fake with its methods and signals
var clock := Callable()                  ## () -> unix seconds (tests; the system clock by default)

var _launch := {}                        # the notification that opened the app, until routed
var _token := ""
var _reg_sig := ""                       # what the server last got: session, account, token, prefs, time zone
var _reg_account := ""                   # the account the token is registered for ...
var _reg_session := ""                   # ... and the session it was registered with (for the DELETE)
var _topic: Variant = null               # the promos topic as last set (null = not yet)
var _push_started := false
var _syncing := false
var _again := false                      # a change came in while the server was being told: tell it again
var _ask_wanted := false
var last_toast: Control = null           ## the toast the last foreground push put up (null: none; tests)


func _init(app_: Node = null, notifier_: Node = null) -> void:
	app = app_
	notifier = notifier_

func _enter_tree() -> void:
	_inst = self

func _exit_tree() -> void:
	if _inst == self:
		_inst = null

## The notifications of this run, or null (previews and tests without one).
static func instance() -> Notifications:
	return _inst if is_instance_valid(_inst) else null

## The phone's permission state ("unsupported" without a Notifications).
static func permission() -> String:
	var n := instance()
	return str(n.notifier.call("permission_state")) if n != null and n.notifier != null else "unsupported"

func _ready() -> void:
	if notifier == null:
		notifier = Notifier.new()
	if notifier.get_parent() == null:
		notifier.name = "Notifier"
		add_child(notifier)
	notifier.connect("opened", _on_opened)
	notifier.connect("push_received", _on_push_received)
	notifier.connect("push_token", _on_push_token)
	notifier.connect("push_failed", _on_push_failed)
	notifier.connect("permission_result", _on_permission_result)
	var acc := _account()
	if acc != null:
		acc.account_changed.connect(_on_account_changed)
		acc.signed_in_changed.connect(_on_signed_in)
	notifier.call("cancel_all")                      # the player is here: nothing waits to fire
	var d: Variant = notifier.call("take_launch_data")
	_launch = d if d is Dictionary else {}
	_start_push()


# ---------- clock, state ----------

func _now() -> int:
	return int(clock.call()) if clock.is_valid() else int(Time.get_unix_time_from_system())

static func tz_offset_s() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60

func _account() -> Account:
	var a: Variant = app.get("account") if app != null else null
	return a as Account if a is Account and is_instance_valid(a) else Account.instance()

func _online() -> Online:
	var o: Variant = app.get("online") if app != null else null
	return o as Online if o is Online and is_instance_valid(o) else null

func _pref(key: String) -> bool:
	return bool(Save.prefs.get(key, true))


# ---------- local reminders ----------

## The plan's input: the switches, the reward times (the offline rules on the profile; the server's next_at when the
## account has them) and the close time.
func plan_state(now: int) -> Dictionary:
	var ready := NotifPlan.ready_times(Save.profile, now, tz_offset_s())
	var acc := _account()
	if acc != null and acc.enabled and acc.has_session():
		for k: String in acc.rewards_at:
			ready[k] = int(acc.rewards_at[k])
	return {enabled = _pref("notif"), rewards = _pref("notif_rewards"), reminders = _pref("notif_reminders"),
		ready = ready, last_play = now}

## cancel_all, then schedule what NotifPlan says (only when the phone lets us notify).
func schedule_now() -> void:
	notifier.call("cancel_all")
	if str(notifier.call("permission_state")) != "granted":
		return
	var now := _now()
	for n: Dictionary in NotifPlan.plan(now, tz_offset_s(), plan_state(now)):
		notifier.call("schedule", n.id, n.at, n.channel, n.title, n.body, n.link)

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST:
			schedule_now()
			_away(true)
		NOTIFICATION_APPLICATION_RESUMED:
			notifier.call("cancel_all")
			_away(false)
			_refresh_rewards()
			permission_changed.emit(permission())
			_sync_push()

## Back in the app while signed in: the server's reward times, for the next time we leave.
func _refresh_rewards() -> void:
	var acc := _account()
	if acc != null and acc.enabled and acc.has_session():
		await acc.fetch_rewards()

## {t: "away", on} to the friend room we are connected to.
func _away(on: bool) -> void:
	var o := _online()
	if o != null and o.net != null:
		o.net.send_away(on)


# ---------- opens ----------

## Launch: the notification that started the app is routed (after home is up). True when there was one.
func take_launch() -> bool:
	if _launch.is_empty():
		return false
	var d := _launch
	_launch = {}
	_open(d)
	return true

func _on_opened(data: Variant) -> void:
	if data is Dictionary and not (data as Dictionary).is_empty():
		_open(data)

## A tapped notification (local or push): count the campaign open, then go where its link says.
func _open(d: Dictionary) -> void:
	var cid := str(d.get("cid", ""))
	var acc := _account()
	if cid != "" and acc != null:
		acc.push_opened(cid)
	if str(app.get("screen")) in ["splash", "welcome"]:
		_launch = d                                  # not yet: take_launch() routes it once Home is up
		return
	route(str(d.get("link", "home")))

## Opens a link on Home: daily / spin / free / shop[:kind:id] / leaderboard / room:CODE (anything else stays home).
## Not while a game is on screen. True when something opened.
func route(link: String) -> bool:
	if app == null or str(app.get("screen")) != "home":
		return false
	var parts := link.split(":")
	var o := _online()
	match parts[0]:
		"daily", "spin", "free", "leaderboard":
			app.call("close_all_sheets")
			app.call("_on_tab", parts[0])
		"shop":
			app.call("close_all_sheets")
			app.call("_on_tab", "shop")
			var top: Variant = app.call("_top_sheet")
			if parts.size() >= 2 and top is Object and top.has_method("show_tab"):
				top.call("show_tab", Notifications.shop_tab(parts[1]))
		"room":
			if o == null or parts.size() < 2:
				return false
			if o.state == "idle":
				app.call("close_all_sheets")
				o.join_code(parts[1])
			elif o.net.code != NetClient.clean_code(parts[1]):
				return false
		_:
			return false
	return true

## The Shop tab for a link's item kind (room / dice / scene / emotes / avatar ...; unknown: Rooms).
static func shop_tab(kind: String) -> String:
	return {room = "rooms", scene = "scenes", dice = "dice", emotes = "emotes", avatar = "avatars", frame = "frames",
		plate = "plates", badge = "badges", coins = "coins"}.get(kind, "rooms")

## A push while the game is in the foreground: a toast (a tap opens its link). Not a "your turn" for the room on screen.
func _on_push_received(data: Variant) -> void:
	if not data is Dictionary:
		return
	var d: Dictionary = data
	last_toast = null
	var link := str(d.get("link", ""))
	var o := _online()
	if str(d.get("kind", "")) == "turn" and link.begins_with("room:") and o != null and o.state != "idle" \
			and o.net.code == NetClient.clean_code(link.substr(5)):
		return
	var text := str(d.get("body", ""))
	if str(d.get("title", "")) != "":
		text = str(d.title) + ("\n" + text if text != "" else "")
	if text == "":
		return
	var host: Node = app.get("ui_root") if app != null and app.get("ui_root") is Node else self
	var pill := Toast.show(host, text, null, TOAST_SEC, "info")
	last_toast = pill
	if pill != null:
		pill.mouse_filter = Control.MOUSE_FILTER_STOP     # a toast lets taps through; this one is a button
		pill.gui_input.connect(_on_toast_input.bind(d, pill))

func _on_toast_input(e: InputEvent, d: Dictionary, pill: Control) -> void:
	if (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed):
		pill.mouse_filter = Control.MOUSE_FILTER_IGNORE   # one tap
		pill.accept_event()
		_open(d)


# ---------- the permission ----------

## Settings' master switch went on while the phone has not been asked: the system dialog.
func ask_permission() -> void:
	notifier.call("request_permission")

func _on_permission_result(_granted: Variant) -> void:
	permission_changed.emit(permission())

## The soft prompt's rules: notifications on, the phone has not been asked (or told no), fewer than ASK_MAX asks, and
## the last one at least ASK_GAP_SEC ago.
static func should_ask(prefs: Dictionary, state: String, now: int) -> bool:
	if not bool(prefs.get("notif", true)) or state != "ask":
		return false
	var asked := Save.as_int(prefs.get("notif_asked"), 0)
	if asked >= ASK_MAX:
		return false
	return asked == 0 or now - Save.as_int(prefs.get("notif_asked_at"), 0) >= ASK_GAP_SEC

## A match was won (any mode): maybe_ask() may ask once the player is home.
func note_win() -> void:
	_ask_wanted = should_ask(Save.prefs, str(notifier.call("permission_state")), _now())

## Asks the soft question once Home is quiet (no sheet over it; a daily reward may open first), for up to 25 s after a short wait. Yes
## opens the system dialog; either answer counts as one ask.
func maybe_ask() -> void:
	if not _ask_wanted:
		return
	await get_tree().create_timer(2.4).timeout       # the coins land and a daily reward opens first
	for i in 50:
		if not _ask_wanted or app == null or str(app.get("screen")) != "home":
			_ask_wanted = false
			return
		if app.call("_top_sheet") == null:
			break
		await get_tree().create_timer(0.5).timeout
	await _ask()

## The soft prompt itself (if the rules still allow it): counts as one ask whatever the answer.
func _ask() -> void:
	_ask_wanted = false
	if app.call("_top_sheet") != null or not should_ask(Save.prefs, str(notifier.call("permission_state")), _now()):
		return
	Save.prefs.notif_asked = Save.as_int(Save.prefs.get("notif_asked"), 0) + 1
	Save.prefs.notif_asked_at = _now()
	Save.save()
	if await Sheet.confirm(app, ASK_TITLE, ASK_TEXT, "Yes", "Not now"):
		notifier.call("request_permission")


# ---------- push ----------

## With the push settings present and an account: start Firebase (the token comes back as push_token).
func _start_push() -> void:
	var acc := _account()
	if _push_started or acc == null or not acc.has_session() or not bool(notifier.call("push_configured")):
		return
	_push_started = true
	notifier.call("push_init_from_settings")

func _on_signed_in() -> void:
	_start_push()

func _on_account_changed() -> void:
	_start_push()
	_sync_push()

func _on_push_token(token: Variant) -> void:
	_token = str(token)
	_sync_push()

func _on_push_failed(code: Variant) -> void:
	if not str(code).get_slice(":", 0) in ["subscribe", "unsubscribe", "delete"]:
		_push_started = false                        # Firebase did not start: the next sign-in / launch tries again

## A Settings switch moved (main's prefs_changed): the server's preferences and the promos topic follow.
func prefs_changed() -> void:
	_sync_push()

## Registers the token with the account and its preferences (game alerts, offers) and sets the promos topic. Only
## when something differs from what the server last got; a switch on the master turns every kind off.
func _sync_push() -> void:
	var acc := _account()
	var master := _pref("notif")
	var offers := master and _pref("notif_offers")
	if _token != "" and _topic != offers:
		_topic = offers
		notifier.call("push_subscribe" if offers else "push_unsubscribe", PROMOS)
	if acc == null or _token == "" or not acc.has_session() or str(acc.account.get("id", "")) == "":
		return
	if _syncing:
		_again = true
		return
	var id := str(acc.account.id)
	var game := master and _pref("notif_game")
	var tz_min := tz_offset_s() / 60
	var sig := "%s|%s|%s|%s|%s|%d" % [id, _token, game, offers, Account.session(), tz_min]
	if sig == _reg_sig:
		return
	_syncing = true
	if _reg_account != "" and _reg_account != id:    # another account on this phone now: the old one lets go of it
		await acc.push_delete(_token, _reg_session)
		_reg_account = ""
	var r: Dictionary = await acc.push_register(_token, game, offers, tz_min)
	_syncing = false
	if r.ok:
		_reg_sig = sig
		_reg_account = id
		_reg_session = Account.session()
	if _again:
		_again = false
		_sync_push()
