class_name StoreSheet
extends Sheet
## The Store (server/ECONOMY_V1.md section 6): your coins and gems on top, the gem packs (Google Play: titles and prices
## come from the store), and below them swapping gems for coins (10 -> 1,000, 50 -> 5,500, 120 -> 14,000).
##
## Packs: tap a price -> Play's sheet -> GemStore verifies with the server -> "+80 gems". A slow payment shows
## "Payment pending…" until it goes through (GemStore keeps it and retries at launch). Off Android (no Play Billing) the
## packs are replaced by "Gem packs are available in the Android app". Swapping asks first and goes through the server.
## Opening the sheet verifies what is still unverified and asks Play for purchases it still holds (GemStore.check).
## A game-look popup: the balances on dark wallet chips, each pack and swap a wood tile with the art and outlined
## figures, chunky gold price buttons and teal Swap buttons (a quiet wood "Need 40" while gems are short).
##
##   var s := StoreSheet.new(); s.open(layer)               # GemStore.instance() (main owns it); tests pass their own

## gems -> coins, in the order of the server's pack index (POST /v1/gems/exchange {pack}).
const PACKS := [[10, 1000], [50, 5500], [120, 14000]]
const ROW_H := 64.0

var store: GemStore
var coins_chip: CoinAmount
var gems_chip: CoinAmount
var _pack_box: VBoxContainer
var _pending: PanelContainer
var _pack_buttons := {}                  # product id -> Button
var _swap_buttons: Array[Button] = []
var _busy := false


func _init(store_: GemStore = null) -> void:
	super(L10n.t("Store"), UIKit.W.form, true, LOOK_GAME)
	store = store_ if store_ != null else GemStore.instance()
	var list := add_scroll_body(UIKit.SPACE.sm + 2)
	# your balances: two dark wallet chips with a gold rim (the Shop's)
	var bal := UIKit.hbox(UIKit.SPACE.sm + 2)
	coins_chip = CoinAmount.new(int(Save.profile.get("coins", 0)), "lg", "plain")      # short form, as Home and the Shop
	coins_chip.name = "Coins"
	gems_chip = CoinAmount.gems(int(Save.profile.get("gems", 0)), "lg", "plain")
	gems_chip.name = "Gems"
	for c: CoinAmount in [coins_chip, gems_chip]:
		bal.add_child(_wallet(c))
	list.add_child(bal)
	# Payment pending…
	_pending = _pending_card()
	list.add_child(_pending)
	# the gem packs
	list.add_child(UIKit.margin(GameUI.outlined(tr("Gem packs"), 17, GameUI.GOLD, 2), 4, UIKit.SPACE.sm, 0, 0))
	_pack_box = UIKit.vbox(UIKit.SPACE.sm + 2)
	_pack_box.name = "Packs"
	list.add_child(_pack_box)
	# gems -> coins
	list.add_child(UIKit.margin(GameUI.outlined(tr("Swap gems for coins"), 17, GameUI.GOLD, 2), 4, UIKit.SPACE.sm, 0, 0))
	for i in PACKS.size():
		list.add_child(_swap_row(i))
	fit()


func _ready() -> void:
	Save.changed.connect(refresh)
	if store != null:
		store.changed.connect(refresh)
		store.granted.connect(_on_granted)
		store.rejected.connect(_on_rejected)
		store.check()
	refresh()


## Re-read the balances, the packs and the swap rows.
func refresh() -> void:
	if not is_instance_valid(coins_chip):
		return
	var p: Dictionary = Save.profile
	coins_chip.set_amount(int(p.get("coins", 0)))
	gems_chip.set_amount(int(p.get("gems", 0)))
	_pending.visible = store != null and store.payment_pending()
	_build_packs()
	var have := int(p.get("gems", 0))
	for i in _swap_buttons.size():
		var b := _swap_buttons[i] as GameUI.GameButton
		var need := int(PACKS[i][0]) - have
		b.text = tr("Swap") if need <= 0 else tr("Need %d") % need
		RewardsSheet.relook(b, "teal" if need <= 0 else "wood")   # too few gems: the quiet wood face
		RewardsSheet.refit(b)


# ---------- gem packs ----------

func _build_packs() -> void:
	var sig := _pack_signature()
	if _pack_box.get_meta("sig", "") == sig:
		_set_pack_state()
		return
	_pack_box.set_meta("sig", sig)
	for c in _pack_box.get_children():
		_pack_box.remove_child(c)
		c.queue_free()
	_pack_buttons.clear()
	if store == null or not store.available():
		_pack_box.add_child(_note_card(tr("Gem packs are available in the Android app.")))
		return
	for id: String in Billing.PRODUCT_IDS:
		var pr := store.product(id)
		var price := str(pr.get("price", ""))
		var row := _pack_row(id, GemStore.gems_of(id), price)
		_pack_box.add_child(row)
	_set_pack_state()

func _pack_signature() -> String:
	if store == null or not store.available():
		return "off"
	var parts: Array = []
	for id: String in Billing.PRODUCT_IDS:
		parts.append(str(store.product(id).get("price", "")))
	return "|".join(parts)

## The price buttons: off while Play is answering or a purchase is under way.
func _set_pack_state() -> void:
	if store == null:
		return
	for id in _pack_buttons:
		var b: Button = _pack_buttons[id]
		var has_price := not store.product(id).is_empty()
		b.disabled = not has_price or store.buying or store.verifying > 0

func _pack_row(id: String, gems: int, price: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UIKit.SPACE.md)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := UIKit.icon("gem", 46)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	var col := UIKit.vbox(-1)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := GameUI.outlined(tr("%s gems") % Fmt.coins_full(gems), 22, GameUI.TEXT, 3)
	t.clip_text = true
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(t)
	var b := GameUI.button(price if price != "" else "…", "gold", "md")
	b.name = id
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	b.custom_minimum_size.x = 112
	RewardsSheet.fit_game(b, 12)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func(): _on_pack(id))
	row.add_child(col)
	row.add_child(b)
	_pack_buttons[id] = b
	var p := _tile(row)
	p.name = "Pack_" + id
	return p

## A row's wood tile (the game look).
func _tile(content: Control) -> GamePanel:
	var p := GameUI.tile(16.0, 0.0)
	p.custom_minimum_size.y = ROW_H
	var m := UIKit.margin(content, 12, 8, 12, 8)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(m)
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	return p

## A balance: the art and outlined white figures on a dark wallet chip with a gold rim.
func _wallet(a: CoinAmount) -> PanelContainer:
	RewardsSheet.amount(a)
	a.alignment = BoxContainer.ALIGNMENT_CENTER
	var c := PanelContainer.new()
	c.name = str(a.name) + "Chip"
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var st := UIKit.box(Palette.GL_CHIP_BG, 20, 2, Palette.GL_CHIP_RIM)
	st.content_margin_top = 5; st.content_margin_bottom = 5
	c.add_theme_stylebox_override("panel", st)
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.add_child(a)
	c.add_child(cc)
	return c

func _on_pack(id: String) -> void:
	if _busy or _closing or store == null:
		return
	if not Account.wallet_active():
		_toast(Account.error_text("offline", "store"), "bad")
		return
	Haptics.tap()
	store.buy(id)

func _on_granted(gems: int, _id: String) -> void:
	Sound.sfx("buy")
	Haptics.success()
	_toast(tr("+%s gems") % Fmt.coins_full(gems), "gem")
	refresh()

func _on_rejected(_id: String) -> void:
	_toast(Account.error_text("invalid"), "bad")

func _pending_card() -> PanelContainer:
	var v := UIKit.vbox(2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(GameUI.outlined(tr("Payment pending…"), 19, GameUI.GOLD, 2))
	var l := GameUI.text(tr("The gems arrive as soon as your payment goes through."), 14)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(l)
	var p := PanelContainer.new()
	p.name = "Pending"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := UIKit.box(Palette.GL_CHIP_BG, 16, 2, Palette.GL_TITLE)
	UIKit.pad(st, UIKit.SPACE.md + 2, UIKit.SPACE.sm + 2)
	p.add_theme_stylebox_override("panel", st)
	p.add_child(v)
	p.visible = false
	return p

func _note_card(text: String) -> Control:
	var l := GameUI.text(text, 15, GameUI.SUB, HORIZONTAL_ALIGNMENT_CENTER)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.name = "Note"
	return _tile(l)


# ---------- gems -> coins ----------

func _swap_row(i: int) -> Control:
	var gems: int = PACKS[i][0]
	var coins: int = PACKS[i][1]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UIKit.SPACE.sm)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := HBoxContainer.new()
	col.add_theme_constant_override("separation", UIKit.SPACE.xs)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_BEGIN
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var g := RewardsSheet.amount(CoinAmount.gems(gems, "lg", "plain"))
	g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_child(g)
	var arrow := GameUI.outlined("→", 20, GameUI.SUB, 2)
	arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_child(arrow)
	var c := RewardsSheet.amount(CoinAmount.new(coins, "lg", "plain"))
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_child(c)
	row.add_child(col)
	var b := GameUI.button(tr("Swap"), "teal", "md")
	b.name = "Swap%d" % i
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	b.custom_minimum_size.x = 100
	RewardsSheet.fit_game(b, 12)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func(): _on_swap(i))
	row.add_child(b)
	_swap_buttons.append(b)
	var p := _tile(row)
	p.name = "SwapRow%d" % i
	return p

## Swap: too few gems -> says how many are missing; else confirm -> POST /v1/gems/exchange -> "+1,000 coins".
func _on_swap(i: int) -> void:
	if _busy or _closing:
		return
	var gems: int = PACKS[i][0]
	var coins: int = PACKS[i][1]
	var have := int(Save.profile.get("gems", 0))
	if gems > have:
		Sound.sfx("error")
		Haptics.error()
		_toast(tr("Not enough gems — you need %s more.") % Fmt.coins_full(gems - have), "bad")
		return
	if not Account.wallet_active():
		Sound.sfx("error")
		_toast(Account.error_text("offline", "store"), "bad")
		return
	_busy = true
	var yes: bool = await Sheet.confirm(self, tr("Swap gems for coins?"), tr("%s gems for %s coins.") % [Fmt.coins_full(gems), Fmt.coins_full(coins)], tr("Swap"))
	if not yes or not is_instance_valid(self) or _closing:
		_busy = false
		return
	var r: Dictionary = await Account.instance().exchange(i)
	_busy = false
	if not is_instance_valid(self) or _closing:
		return
	if r.get("ok", false):
		Sound.sfx("coin", coins)
		Haptics.success()
		_toast(tr("+%s coins") % Fmt.coins_full(int(r.get("coins", coins))), "coin")
	else:
		Sound.sfx("error")
		Haptics.error()
		var short := int(r.get("short", 0))
		_toast((tr("Not enough gems — you need %s more.") % Fmt.coins_full(short)) if str(r.get("error", "")) == "gems" and short > 0
			else Account.error_text(str(r.get("error", "")), "store"), "bad")
	refresh()

func _toast(text: String, kind: String) -> void:
	Toast.show(self, text, card, 2.0, kind)
