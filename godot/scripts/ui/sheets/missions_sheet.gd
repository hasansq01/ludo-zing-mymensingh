class_name MissionsSheet
extends Sheet
## Daily missions: three small goals a day from the server (GET /v1/missions: it counts them from the matches it has
## checked), each paying coins once; all three open a chest. New ones every day.
##
##   MissionsSheet.new().open(layer)

## Mission id -> what to do; shown through L10n.t, goal in %d where there is one.
# l10n:begin
const TEXT := {
	play1 = "Play a game",
	ludo1 = "Play a game of Ludo",
	sl1 = "Play Snakes & Ladders",
	play3 = "Play 3 games",
	earn500 = "Earn 500 coins",
	win1 = "Win a game",
	win2 = "Win 2 games",
}
# l10n:end

var data := {}                           ## the last answer
var fetch_fn := Callable()               ## tests: () -> {ok, missions, chest}
var claim_fn := Callable()               ## tests: (id) -> {ok, coins, gems}
var _list: VBoxContainer
var _busy := false


func _init() -> void:
	super(L10n.t("Daily missions"), UIKit.W.form, true, LOOK_PM)
	_list = add_scroll_body(UIKit.SPACE.sm)
	_list.add_child(UIKit.label(tr("Loading…"), UIKit.FS.body, Palette.SUB, UIKit.font_body(800), HORIZONTAL_ALIGNMENT_CENTER))
	fit()


func _ready() -> void:
	load_all()


func load_all() -> void:
	var r: Dictionary = (await fetch_fn.call()) if fetch_fn.is_valid() else (await Account.instance().missions())
	if not is_instance_valid(self):
		return
	data = r
	_render()
	fit()


func _render() -> void:
	for c in _list.get_children():
		c.queue_free()
	if not data.get("ok", false) or not data.get("missions") is Array:
		_list.add_child(UIKit.paragraph(tr("Connect to the internet to see today’s missions."), UIKit.FS.body, Palette.SUB))
		return
	for m: Dictionary in data.missions:
		_list.add_child(_row(m))
	_list.add_child(_chest(data.get("chest", {})))


func _row(m: Dictionary) -> Control:
	var h := UIKit.hbox(UIKit.SPACE.md)
	var col := UIKit.vbox(UIKit.SPACE.xs)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(UIKit.label(L10n.t(str(TEXT.get(str(m.id), m.id))), UIKit.FS.h3, Palette.INK, UIKit.font_body(900)))
	var bar := Meter.new("teal", 16, true)
	bar.set_value(int(m.value), int(m.goal))
	bar.set_text("%d / %d" % [int(m.value), int(m.goal)])
	col.add_child(bar)
	h.add_child(col)
	h.add_child(_action(m, str(m.id), bool(m.done), bool(m.claimed), int(m.coins), 0))
	return UIKit.list_row(h)


func _chest(c: Dictionary) -> Control:
	var h := UIKit.hbox(UIKit.SPACE.md)
	h.add_child(UIKit.icon(HomeScreen.HI % "gift", 44))
	var col := UIKit.vbox(0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(UIKit.label(tr("Mission chest"), UIKit.FS.h3, Palette.INK, UIKit.font_body(900)))
	col.add_child(UIKit.label(tr("Finish all three to open it"), UIKit.FS.small, Palette.SUB, UIKit.font_body(800)))
	h.add_child(col)
	h.add_child(_action(c, "chest", bool(c.get("ready", false)), bool(c.get("claimed", false)), int(c.get("coins", 0)), int(c.get("gems", 0))))
	return UIKit.list_row(h)


## What a row offers: what it pays, Claim when it's done, a tick once claimed.
func _action(_m: Dictionary, id: String, done: bool, claimed: bool, coins: int, gems: int) -> Control:
	if claimed:
		return UIKit.glyph("ic_check", 22, Palette.TEAL_INK)
	var pay := HBoxContainer.new()
	pay.add_child(CoinAmount.new(coins, "sm", "plain"))
	if gems > 0:
		pay.add_child(CoinAmount.gems(gems, "sm", "plain", "+"))
	if not done:
		pay.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		return pay
	var b := UIKit.button(tr("Claim"), "honey", "sm")
	b.name = "Claim_" + id
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(_claim.bind(id, b))
	return b


func _claim(id: String, b: Button) -> void:
	if _busy:
		return
	_busy = true
	b.disabled = true
	var from := b.get_global_rect().get_center()
	DailySheet.hold_home_coins(self)
	var r: Dictionary = (await claim_fn.call(id)) if claim_fn.is_valid() else (await Account.instance().claim_mission(id))
	if not is_instance_valid(self):
		return
	_busy = false
	if r.get("ok", false):
		Sound.sfx("buy")
		Haptics.success()
		if id == "chest":
			Celebrate.run(self, "", 0.6)
		DailySheet.reward_coins(self, from, int(r.get("coins", 0)), false, int(Save.profile.get("coins", -1)))
		if int(r.get("gems", 0)) > 0:
			Toast.show(self, tr("+%d gems") % int(r.gems), card, 2.0, "gem")
	else:
		Sound.sfx("error")
		Toast.show(self, Account.error_text(str(r.get("error", "")), "claim"), card, 2.4, "bad")
	await load_all()
