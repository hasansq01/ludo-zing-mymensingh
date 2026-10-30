class_name BrokeSheet
extends Sheet
## "Out of coins": shown when you open quick match with fewer than 100 coins (the cheapest table), or a table is refused
## with `coins` (server/ECONOMY_V1.md section 0). Three ways on:
##   Daily bonus +300      once per day while broke (POST /v1/rewards/broke); used: disabled, with the time left
##   Watch a video: +500   the refill ad (AdFlow "refill"); hidden when no ad can run here
##   Play Practice instead the free table
## The server decides everything (the bonus, the ad's reward); this shows it. After a top-up that gets you to 100 coins
## the sheet closes and `topped_up(coins)` says so (Online then opens the table picker).
##
##   var s := BrokeSheet.new()
##   s.practice_pressed.connect(...); s.topped_up.connect(func(coins): ...)
##   s.open(layer)
## Tests / dev: acc_fn (() -> Account-like with fetch_tables() / claim_broke()), ad_ok_fn (() -> bool), flow (an AdFlow),
## coins_fn (() -> int, the balance).

signal practice_pressed
signal topped_up(coins: int)

const BONUS := 300
const REFILL := 500

var bonus_button: Button
var video_button: Button
var practice_button: Button
var note_label: Label
var bonus := {available = true, next_at = 0, amount = BONUS}
var acc_fn := Callable()
var ad_ok_fn := Callable()
var coins_fn := Callable()
var flow: AdFlow
var _busy := false
var _bonus_text: Label
var _tick := 0.0


func _init(bonus_ := {}) -> void:
	super("Out of coins", UIKit.W.form, true, Sheet.LOOK_PM)
	dismissable = true
	set_kicker("Coin tables")
	body.add_theme_constant_override("separation", UIKit.SPACE.md)
	var intro := UIKit.paragraph("", UIKit.FS.body, Palette.SUB, HORIZONTAL_ALIGNMENT_CENTER)
	intro.name = "Intro"
	body.add_child(intro)
	bonus_button = UIKit.button_with("Daily bonus +%d" % BONUS, UIKit.icon("coin", 28), "honey", "lg")
	bonus_button.name = "Bonus"
	_bonus_text = bonus_button.find_child("Text", true, false) as Label
	bonus_button.pressed.connect(_claim)
	UIKit.deny_disabled(bonus_button, func() -> String:           # the daily bonus is used: say when it is back
		if _busy or bool(bonus.available):
			return ""
		var left := int(bonus.next_at) - int(Time.get_unix_time_from_system())
		return "Daily bonus is back in %s." % Fmt.until(left) if left > 0 else "Daily bonus is back tomorrow.")
	body.add_child(bonus_button)
	video_button = UIKit.button_with("Watch a video: +%s coins" % Fmt.coins_full(REFILL), UIKit.icon("coin", 26), "teal", "md")
	video_button.name = "Video"
	narrow_changed.connect(func(narrow: bool):      # the long video line shrinks to fit a 320 px card
		(video_button.find_child("Text", true, false) as Label).add_theme_font_size_override("font_size", 15 if narrow else UIKit.BTN.md.fs))
	video_button.pressed.connect(_watch)
	body.add_child(video_button)
	note_label = UIKit.paragraph("", UIKit.FS.body, Palette.DANGER, HORIZONTAL_ALIGNMENT_CENTER)
	note_label.name = "Note"
	note_label.visible = false
	body.add_child(note_label)
	practice_button = UIKit.btn("Play Practice instead", "ghost", "md")
	practice_button.name = "Practice"
	practice_button.pressed.connect(func():
		practice_pressed.emit()
		close())
	body.add_child(practice_button)
	if not bonus_.is_empty():
		bonus = bonus_
	refresh()
	fit()
	set_process(true)

func _ready() -> void:
	_load.call_deferred()

## The balance now.
func balance() -> int:
	if coins_fn.is_valid():
		return int(coins_fn.call())
	return int(Save.profile.get("coins", 0)) if Engine.get_main_loop() is SceneTree and (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Save") != null else 0

func _acc() -> Object:
	if acc_fn.is_valid():
		return acc_fn.call()
	return Account.instance() if Account.wallet_active() else null

func _ads() -> bool:
	return bool(ad_ok_fn.call()) if ad_ok_fn.is_valid() else AdFlow.available()

## GET /v1/tables for the bonus state (without an account the bonus button stays as it is).
func _load() -> void:
	var acc := _acc()
	if acc == null or not acc.has_method("fetch_tables"):
		return
	var r: Dictionary = await acc.fetch_tables()
	if not is_instance_valid(self) or not bool(r.get("ok", false)):
		return
	if r.get("broke_bonus") is Dictionary:
		set_bonus(r.broke_bonus)

## {available, next_at (unix s), amount}: the daily bonus now.
func set_bonus(b: Dictionary) -> void:
	bonus = {available = bool(b.get("available", false)), next_at = int(b.get("next_at", 0)), amount = int(b.get("amount", BONUS))}
	refresh()

## Texts and states from the balance, the bonus and the ads.
func refresh() -> void:
	var intro := body.find_child("Intro", true, false) as Label
	intro.text = "You have %s coins. Tables start at %d. Top up, or play Practice for free." % [Fmt.coins_full(balance()), CoinTables.BROKE_BELOW]
	var avail := bool(bonus.available)
	bonus_button.disabled = _busy or not avail
	_bonus_kind("honey" if avail else "off")
	if avail:
		_bonus_text.text = "Daily bonus +%d" % int(bonus.amount)
	else:
		var left := int(bonus.next_at) - int(Time.get_unix_time_from_system())
		_bonus_text.text = "Daily bonus · %s" % (Fmt.until(left) if left > 0 else "tomorrow")
	video_button.visible = _ads()
	video_button.disabled = _busy
	practice_button.disabled = _busy

## The bonus button's kind with its text colours (button_with's label keeps the colours it was made with).
func _bonus_kind(kind: String) -> void:
	if bonus_button.get_meta("kit_kind", "") == kind:
		return
	UIKit.set_kind(bonus_button, kind)
	var k: Array = UIKit.KINDS[kind]
	_bonus_text.add_theme_color_override("font_color", k[2])
	_bonus_text.add_theme_color_override("font_outline_color", k[3])

func _process(d: float) -> void:
	_tick += d
	if _tick >= 20.0 and not bool(bonus.available):
		_tick = 0.0
		refresh()

func _say(text: String, kind := "bad") -> void:
	Toast.show(self, text, null, 2.2, kind)

func _claim() -> void:
	var acc := _acc()
	if _busy or not bool(bonus.available):
		return
	if acc == null:
		_say(Account.offline_text("claim"))
		return
	_busy = true
	refresh()
	var r: Dictionary = await acc.claim_broke()
	if not is_instance_valid(self):
		return
	_busy = false
	if bool(r.get("ok", false)):
		var got := int(r.get("coins", bonus.amount))
		bonus.available = false
		bonus.next_at = int(r.get("next_at", 0))
		_say("+%s coins" % Fmt.coins_full(got), "coin")
		_after_top_up()
		return
	var code := str(r.get("error", ""))
	if code == "claimed":
		bonus.available = false
		bonus.next_at = int(r.get("next_at", 0))
	_say(Account.error_text(code, "claim"))
	refresh()

func _watch() -> void:
	if _busy:
		return
	_busy = true
	refresh()
	if flow == null:
		flow = AdFlow.new()
		add_child(flow)
	var res: Dictionary = await AdWatch.run(flow, "refill")
	if not is_instance_valid(self):
		return
	_busy = false
	var info: Dictionary = res.info
	if bool(res.ok):
		_say("+%s coins" % Fmt.coins_full(int(info.get("amount", REFILL))), "coin")
		_after_top_up()
		return
	_say(str(info.get("text", AdFlow.NO_FILL_TEXT)))
	refresh()

## Back at 100 coins or more: on to the table picker. Still short: the other ways stay open.
func _after_top_up() -> void:
	refresh()
	var c := balance()
	if not CoinTables.is_broke(c):
		topped_up.emit(c)
		close()
