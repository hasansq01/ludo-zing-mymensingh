class_name WelcomeSheet
extends Sheet
## What greets a player who comes back: today's gifts in one place, before anything else (a game-look popup: the
## RewardsSheet rows as wood tiles, a chunky gold Collect, a teal video button). Daily reward and Free coins go
## into the wallet with one big Collect button (the coins fly); then the Lucky Draw and the Daily missions are one tap
## away, and today's reward can be doubled with a video. Opened by main at launch when anything is waiting.
##
##   var s := WelcomeSheet.new(); s.picked.connect(main._on_tab); s.open(layer)

signal picked(id: String)                ## "spin" | "missions"

var flow: AdFlow
var _collect: Button
var _double: Button
var _note: Label
var _busy := false
var _rows := {}


func _init() -> void:
	super(L10n.t("Welcome back!"), UIKit.W.form, true, LOOK_GAME)
	var list := add_scroll_body(UIKit.SPACE.sm + 2)
	_note = GameUI.text("", 16, GameUI.SUB, HORIZONTAL_ALIGNMENT_CENTER)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.add_child(UIKit.margin(_note, 0, 0, 0, 2))
	for r: Array in [["daily", "gift", tr("Daily reward")], ["free", "coins", tr("Free coins")], ["spin", "spin", tr("Lucky Draw")], ["missions", "again", tr("Daily missions")]]:
		var row := RewardsSheet.Row.new(r[0], r[2], HomeScreen.HI % r[1], tr("Go") if r[0] in ["spin", "missions"] else tr("Ready"), row_note(r[0]))
		row.pressed.connect(_tap.bind(str(r[0])))
		list.add_child(row)
		_rows[r[0]] = row
	var gap := Control.new()                 # a little air above the big buttons
	gap.custom_minimum_size.y = 2
	list.add_child(gap)
	_collect = GameUI.button(tr("Collect"), "gold", "lg")
	_collect.name = "Collect"
	_collect.pressed.connect(collect)
	list.add_child(_collect)
	_double = GameUI.button(tr("Double today’s reward with a video"), "teal", "lg")
	_double.name = "Double"
	_double.visible = false
	RewardsSheet.fit_game(_double, 14)
	_double.pressed.connect(_watch)
	list.add_child(_double)
	var room := Control.new()                # (the big button's lip clears the scroll's edge)
	room.custom_minimum_size.y = 6
	list.add_child(room)
	if AdFlow.available():
		flow = AdFlow.new()
		flow.name = "AdFlow"
		flow.done.connect(_on_watched)
		add_child(flow)
	fit()


func _ready() -> void:
	Save.changed.connect(refresh)
	refresh()


static func row_note(id: String) -> String:
	match id:
		"daily":
			var st := Rewards.daily_state(Save.profile)
			var day := int(st.today) + 1 if bool(st.get("claimable", false)) else int(Rewards.daily_data(Save.profile).get("streak", 1))
			return L10n.t("Day %d of your streak") % maxi(1, day)
		"free":
			return L10n.t("%s coins") % Fmt.gain(Rewards.FREE_AMOUNT)
		"spin":
			return L10n.t("Win up to %s coins") % Fmt.coins_full(Rewards.PRIZES.max())
	return L10n.t("Three goals, then a chest")


## What's in the Collect button right now.
static func collectable(p: Dictionary) -> Array:
	var out := []
	if bool(Rewards.daily_state(p).get("claimable", false)):
		out.append("daily")
	if Rewards.free_left_sec(p) <= 0:
		out.append("free")
	return out


func refresh() -> void:
	var st := HomeScreen.reward_states(Save.profile)
	for id: String in _rows:
		var ready_now := bool(st[id].ready) if st.has(id) else true
		(_rows[id] as RewardsSheet.Row).set_state(ready_now, str(st[id].wait) if st.has(id) else "")
	var left := collectable(Save.profile)
	_collect.visible = not left.is_empty()
	_collect.disabled = _busy
	_note.text = tr("Your gifts are waiting!") if not left.is_empty() else tr("All collected. Have a great game!")
	if not is_instance_valid(flow):
		_double.visible = false
	elif not bool(Rewards.daily_state(Save.profile).get("claimable", false)) and _double.get_meta("used", false) == false:
		_double.visible = true


func _tap(id: String) -> void:
	if id in ["daily", "free"]:
		collect()
		return
	picked.emit(id)


## Claims everything that's ready, one after the other.
func collect() -> void:
	if _busy:
		return
	_busy = true
	refresh()
	var from := _collect.get_global_rect().get_center()
	var got := 0
	DailySheet.hold_home_coins(self)
	if bool(Rewards.daily_state(Save.profile).get("claimable", false)):
		var r: Dictionary = (await Account.instance().daily()) if Account.wallet_active() else _local_daily()
		if not is_instance_valid(self):
			return
		if r.get("ok", false):
			got += int(r.get("coins", 0))
			if str(r.get("dice", "")) != "" or str(r.get("char", "")) != "":
				Toast.show(self, DailySheet.reward_text(r), card, 2.4, "good")
		else:
			_say_error(r)
	if Rewards.free_left_sec(Save.profile) <= 0:
		var r2: Dictionary = (await Account.instance().free_coins()) if Account.wallet_active() else _local_free()
		if not is_instance_valid(self):
			return
		if r2.get("ok", false):
			got += int(r2.get("coins", 0))
		else:
			_say_error(r2)
	_busy = false
	if got > 0:
		Sound.sfx("buy")
		Haptics.success()
		Celebrate.run(self, "burst", 0.5)
		DailySheet.reward_coins(self, from, got, false, int(Save.profile.get("coins", -1)))
	refresh()


func _local_daily() -> Dictionary:
	var r: Dictionary = Rewards.claim_daily(Save.profile)
	return r

func _local_free() -> Dictionary:
	var n := Rewards.claim_free(Save.profile)
	return {ok = n > 0, coins = n, error = "cooldown"}

func _say_error(r: Dictionary) -> void:
	Sound.sfx("error")
	Toast.show(self, Account.error_text(str(r.get("error", "")), "claim"), card, 2.4, "bad")


func _watch() -> void:
	if flow == null or flow.busy:
		return
	_double.disabled = true
	flow.watch("gift")


func _on_watched(ok: bool, info: Dictionary) -> void:
	if not is_instance_valid(_double):
		return
	_double.disabled = false
	if ok:
		_double.set_meta("used", true)
		_double.visible = false
		var n := int(info.get("amount", 0))
		Sound.sfx("buy")
		Haptics.success()
		Celebrate.run(self, "burst", 0.5)
		DailySheet.reward_coins(self, _double.get_global_rect().get_center(), n, false, int(Save.profile.get("coins", -1)))
	else:
		if str(info.get("error", "")) == "cap":
			_double.set_meta("used", true)
			_double.visible = false
		Toast.show(self, str(info.get("text", tr(AdFlow.NO_FILL_TEXT))), card, 2.4, "bad")
