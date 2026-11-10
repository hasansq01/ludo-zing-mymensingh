class_name MissionsSheet
extends Sheet
## Daily missions: three small goals a day from the server (GET /v1/missions: it counts them from the matches it has
## checked), each paying coins once; all three open a chest. New ones every day. A game-look popup: each mission a wood
## tile with a gold progress bar, what it pays in outlined numbers, a chunky gold Claim, a teal tick once claimed.
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
	super(L10n.t("Daily missions"), UIKit.W.form, true, LOOK_GAME)
	_list = add_scroll_body(UIKit.SPACE.sm + 2)
	_list.add_child(GameUI.text(tr("Loading…"), 16, GameUI.SUB, HORIZONTAL_ALIGNMENT_CENTER))
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
		var off := GameUI.text(tr("Connect to the internet to see today’s missions."), 16, GameUI.SUB, HORIZONTAL_ALIGNMENT_CENTER)
		off.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(off)
		return
	for m: Dictionary in data.missions:
		_list.add_child(_row(m))
	_list.add_child(_chest(data.get("chest", {})))


## A mission: a wood tile (gold rim while its Claim waits), the goal in outlined white over a gold progress bar on a
## dark track, and on the right what it pays / Claim / the tick.
func _row(m: Dictionary) -> Control:
	var h := UIKit.hbox(UIKit.SPACE.md)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := UIKit.vbox(6)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := GameUI.outlined(L10n.t(str(TEXT.get(str(m.id), m.id))), 19, GameUI.TEXT, 2)
	t.clip_text = true
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(t)
	var bar := Meter.new("game_teal" if bool(m.claimed) else "game", 20, true)
	bar.set_value(int(m.value), int(m.goal))
	bar.set_text("%d / %d" % [int(m.value), int(m.goal)])
	col.add_child(bar)
	h.add_child(col)
	h.add_child(_action(m, str(m.id), bool(m.done), bool(m.claimed), int(m.coins), 0))
	return _tile(h, bool(m.done) and not bool(m.claimed), bool(m.claimed))


## The chest: a gift on a purple disc, what opens it, and its coins and gems.
func _chest(c: Dictionary) -> Control:
	var h := UIKit.hbox(UIKit.SPACE.md)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(RewardsSheet.disc(HomeScreen.HI % "gift", "purple", 50.0, 34.0))
	var col := UIKit.vbox(0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := GameUI.outlined(tr("Mission chest"), 19, GameUI.GOLD, 2)
	t.clip_text = true
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(t)
	var n := GameUI.text(tr("Finish all three to open it"), 13)
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(n)
	h.add_child(col)
	var ready_ := bool(c.get("ready", false))
	var claimed := bool(c.get("claimed", false))
	h.add_child(_action(c, "chest", ready_, claimed, int(c.get("coins", 0)), int(c.get("gems", 0)), true))
	return _tile(h, ready_ and not claimed, claimed)


## A row's wood tile; `lit`: a Claim waits (the gold rim); `done`: claimed (quieter).
func _tile(content: Control, lit: bool, done: bool) -> GamePanel:
	var p := GameUI.tile(16.0, 0.0)
	if lit:
		p.border = 3.0
		p.border_color = Palette.GL_TITLE
	p.custom_minimum_size.y = 72
	p.add_child(UIKit.margin(content, 12, 10, 12, 10))
	if done:
		content.modulate = Color(1, 1, 1, 0.75)
	return p


## What a row offers: what it pays (the coin / gem art with outlined numbers), Claim when it's done, a teal tick once
## claimed. stacked: the coins over the gems (the chest).
func _action(_m: Dictionary, id: String, done: bool, claimed: bool, coins: int, gems: int, stacked := false) -> Control:
	if claimed:
		var tick := GamePanel.vertical(Palette.GL_BTN_TEAL_HI, Palette.GL_BTN_TEAL_LO)
		tick.name = "Done"
		tick.radius = 19.0
		tick.lip = 3.0
		tick.lip_color = Palette.GL_TEAL_LIP
		tick.custom_minimum_size = Vector2(38, 41)
		tick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var cc := CenterContainer.new()
		cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cc.add_child(UIKit.glyph("ic_check", 22, Color.WHITE))
		tick.add_child(cc)
		return tick
	if not done:
		var pay: BoxContainer = UIKit.vbox(0) if stacked else UIKit.hbox(4)
		pay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pay.add_child(RewardsSheet.amount(CoinAmount.new(coins, "lg", "plain")))
		if gems > 0:
			pay.add_child(RewardsSheet.amount(CoinAmount.gems(gems, "lg", "plain", "+")))
		pay.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		return pay
	var b := GameUI.button(tr("Claim"), "gold", "sm")
	b.name = "Claim_" + id
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.custom_minimum_size.x = 84
	RewardsSheet.fit_game(b, 12)
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
