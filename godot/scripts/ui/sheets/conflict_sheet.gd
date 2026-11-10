class_name ConflictSheet
extends Sheet
## "Which progress do you want to keep?" (server/ONLINE_V2.md section 1, Policy b): Google Play Games sign-in found a
## clash. A game-look popup (the dark café card, the outlined gold title, the round red X) with two wood tiles, each
## a progress summary (avatar, name, level, coins, wins) under an outlined gold heading, a plain cream sentence on what
## happens and its own chunky button (gold: keep / stay, teal: the Google account / switch):
##   kind "conflict"     this device's guest progress vs the Google account's:
##                       "Keep this device’s progress" (keep "here": the Google account moves to this progress)
##                       "Use Google account’s progress" (keep "there": this device switches over)
##   kind "other_google" this device is linked to another Google account than the one just signed in:
##                       "Stay on this account" (keep "stay") / "Switch to the other account" (keep "switch";
##                       a new account when the other Google player has none yet)
## The sheet asks Account.resolve_conflict(keep) and closes on success; X / Back close it without a decision (nothing
## changes; signing in again asks again). `chosen(keep)` is emitted when a button is pressed.
##
##   ConflictSheet.present(app.sheet_layer, app.account)     # Main does this on Account.conflict_raised

signal chosen(keep: String)

var kind := "conflict"
var account_node: Account
var here_button: Button
var there_button: Button
var _info: Dictionary
var _busy := false
var _cards: Array[Control] = []


func _init(info: Dictionary = {}, acc: Account = null) -> void:
	super(L10n.t("Keep which progress?") if str(info.get("kind", "conflict")) == "conflict" else L10n.t("Other Google account"), UIKit.W.catalog, true, LOOK_GAME)
	_info = info
	account_node = acc
	kind = str(info.get("kind", "conflict"))
	var list := add_scroll_body(UIKit.SPACE.md)
	var intro := GameUI.text(intro_text(kind), UIKit.FS.body_l, GameUI.SUB, HORIZONTAL_ALIGNMENT_CENTER)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size.x = 60
	list.add_child(intro)
	var here: Dictionary = info.get("here", {}) if info.get("here") is Dictionary else {}
	var there: Variant = info.get("there")
	var is_conflict := kind == "conflict"
	here_button = GameUI.button(here_label(kind), "gold", "md")
	here_button.name = "Here"
	here_button.pressed.connect(func(): _pick("here" if is_conflict else "stay"))
	there_button = GameUI.button(there_label(kind), "teal", "md")
	there_button.name = "There"
	there_button.pressed.connect(func(): _pick("there" if is_conflict else "switch"))
	for b: GameUI.GameButton in [here_button, there_button]:
		GameUI.fit_button_text(b, 12)
	list.add_child(_option(here, tr("This device") if is_conflict else tr("This account"), here_text(kind), here_button))
	list.add_child(_option(there if there is Dictionary else {}, tr("Google account") if is_conflict else tr("Other Google account"),
		there_text(kind, there is Dictionary), there_button, not (there is Dictionary)))
	fit()


static func intro_text(k: String) -> String:
	if k == "conflict":
		return L10n.t("This Google account already has progress saved. Choose the one you want to keep playing with.")
	return L10n.t("This device is linked to a different Google account than the one you just signed in with.")

static func here_label(k: String) -> String:
	return L10n.t("Keep this device’s progress") if k == "conflict" else L10n.t("Stay on this account")

static func there_label(k: String) -> String:
	return L10n.t("Use Google account’s progress") if k == "conflict" else L10n.t("Switch to the other account")

static func here_text(k: String) -> String:
	if k == "conflict":
		return L10n.t("Your Google account will use this progress from now on. The progress saved on the Google account is retired.")
	return L10n.t("Nothing changes. This account stays linked to its own Google account.")

static func there_text(k: String, has_account: bool) -> String:
	if k == "conflict":
		return L10n.t("This device switches to the progress saved on your Google account. The progress on this device is left behind.")
	if has_account:
		return L10n.t("This device switches to the other Google account’s progress. Your current account stays linked to its own.")
	return L10n.t("This device starts a new account for the other Google player. Your current account stays linked to its own.")

## A progress summary {name, avatar, level, coins, wins}: the avatar, the name, "Level 9 · 55 wins", the coins.
## empty: the Google player has no account yet ("New account · starts at level 1"). Light text, for the wood tile.
static func summary_card(s: Dictionary, caption: String, empty := false) -> Control:
	var v := UIKit.vbox(UIKit.SPACE.sm)
	if caption != "":
		var cap := GameUI.outlined(caption, 18, GameUI.GOLD, 2)
		cap.name = "Caption"
		v.add_child(cap)
	var row := UIKit.hbox(UIKit.SPACE.md)
	var ava := Collection.make_avatar_of(str(s.get("avatar", "pawn-red")) if not empty else "pawn-red", str(s.get("frame", "classic")), 56.0)
	ava.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if empty:
		ava.modulate = Color(1, 1, 1, 0.45)
	row.add_child(ava)
	var col := UIKit.vbox(UIKit.SPACE.xxs)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var nm := GameUI.outlined(L10n.t("New account") if empty else str(s.get("name", L10n.t("Player"))), 21, GameUI.TEXT, 2)
	nm.name = "Name"
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(nm)
	var wins := int(s.get("wins", 0))
	var meta := L10n.t("Starts at level 1") if empty else L10n.tn("Level %d · %d win", "Level %d · %d wins", wins) % [maxi(1, int(s.get("level", 1))), wins]
	var ml := GameUI.text(meta, UIKit.FS.label, GameUI.SUB)
	ml.name = "Meta"
	col.add_child(ml)
	if not empty:
		var coins := CoinAmount.new(int(s.get("coins", 0)), "sm", "plain")
		coins.name = "Coins"
		coins.set_color(GameUI.TEXT)
		coins.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		col.add_child(coins)
	row.add_child(col)
	v.add_child(row)
	return v

func _option(s: Dictionary, caption: String, consequence: String, button: Button, empty := false) -> Control:
	var v := UIKit.vbox(UIKit.SPACE.sm)
	v.add_child(summary_card(s, "", empty))
	var note := GameUI.text(consequence, 13, GameUI.SUB)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 60
	note.name = "Consequence"
	v.add_child(note)
	v.add_child(button)
	var p := GameUI.tile(18.0, 14.0)
	p.add_child(v)
	_cards.append(p)
	var cap := GameUI.outlined(caption, 18, GameUI.GOLD, 2)   # the heading sits above its card
	cap.name = "Caption"
	var out := UIKit.vbox(UIKit.SPACE.sm)
	out.add_child(cap)
	out.add_child(p)
	return out

func _pick(keep: String) -> void:
	if _busy or _closing:
		return
	chosen.emit(keep)
	if account_node == null:
		return
	_set_busy(true)
	var r: Dictionary = await account_node.resolve_conflict(keep)
	if not is_instance_valid(self) or _closing:
		return
	if r.get("ok", false):
		Haptics.success()
		var msg := tr("Welcome back, %s!") % str(Save.profile.get("name", "")) if keep in ["there", "switch"] else tr("Progress saved to your Google account.")
		if keep == "stay":
			msg = tr("Staying on this account.")
		Toast.show(get_parent() if get_parent() else self, msg, null, 2.2, "good")
		close()
		return
	_set_busy(false)
	Haptics.error()
	var why := Account.google_error_text(str(r.get("error", "")))
	Toast.show(self, why if why != "" else tr("Couldn’t switch. Please try again."), card, 2.4, "bad")
	if str(r.get("error", "")) == "bad_ticket" or str(r.get("error", "")) == "no_conflict":
		close()

func _set_busy(b: bool) -> void:
	_busy = b
	here_button.disabled = b
	there_button.disabled = b

## Opens it once (a second raise while it's showing is ignored).
static func present(layer: Control, acc: Account) -> ConflictSheet:
	for c in layer.get_children():
		if c is ConflictSheet and not (c as ConflictSheet)._closing:
			return c
	var s := ConflictSheet.new(acc.conflict.duplicate(true), acc)
	s.open(layer)
	return s
