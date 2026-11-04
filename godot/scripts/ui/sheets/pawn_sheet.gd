class_name PawnSheet
extends Sheet
## The Shop's "View" on a pawn skin: the skin's name on the ribbon, the skin on all four seat colours turning slowly
## (PawnStage.FOUR: the colours stay apart in every skin), its line (Catalog.PAWNS desc) and one action: Buy (coins
## or, for the gem-only skins, gems), "Need 2.5K", Use, or the "In use" pill; a coin skin also has the Shop's "or
## [gem] N" line. Buy / Use go through the server wallet (Account) when there is one, else the local rules
## (previews, tests), exactly as the Shop card.
##   var s := PawnSheet.new("crown"); s.changed.connect(refresh_shop); s.open(layer)

signal changed                           ## the skin was bought or put in use
signal store_requested                   ## "Open Store" after "not enough gems" (the Shop passes it on to Main)

const MAX_W := 400.0
const STAGE_H := 190.0

var pawn_id := ""
var stage: PawnStage
var _buy: Button
var _need: Button
var _use: Button
var _on_pill: PanelContainer
var _gem: Button                         # "or [gem] N" under a coin skin's action
var _busy := false


func _init(pawn_id_ := "classic") -> void:
	var d := Catalog.pawn(pawn_id_)
	super(L10n.t(str(d.get("name", "Pawns"))), MAX_W, true, LOOK_PM)
	pawn_id = pawn_id_
	body.add_theme_constant_override("separation", UIKit.SPACE.sm)
	var well := PanelContainer.new()
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	var ws := UIKit.box((Palette.CAT.pawns as Array)[0].lerp(Color.WHITE, 0.72), UIKit.R.lg)
	UIKit.pad(ws, 0)
	well.add_theme_stylebox_override("panel", ws)
	stage = PawnStage.new(pawn_id, PawnStage.FOUR)
	stage.custom_minimum_size = Vector2(0, STAGE_H)
	well.add_child(stage)
	body.add_child(well)
	var kind := UIKit.caption(tr("Pawn skin · Ludo and Snakes & Ladders"))
	kind.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(kind)
	var desc := UIKit.paragraph(tr(str(d.get("desc", ""))), UIKit.FS.body_l, Palette.SUB, HORIZONTAL_ALIGNMENT_CENTER)
	desc.name = "Desc"
	body.add_child(desc)
	var slot := MarginContainer.new()
	slot.custom_minimum_size.y = UIKit.TAP + 4
	slot.add_theme_constant_override("margin_top", UIKit.SPACE.xs)
	var gems_only := Catalog.pawn_gems_only(pawn_id)
	var amount := CoinAmount.gems(Catalog.pawn_gems(pawn_id), "md", "plain") if gems_only else CoinAmount.new(int(d.get("price", 0)), "md", "plain")
	_buy = UIKit.button_with(tr("Buy"), amount, "gold", "md")
	_buy.name = "Buy"
	var row := _buy.get_node("Content") as HBoxContainer
	row.move_child(row.get_child(0), -1)
	_need = UIKit.btn("", "off", "md")
	_need.name = "Need"
	_use = UIKit.btn(tr("Use"), "teal", "md")
	_use.name = "Use"
	for b: Button in [_buy, _need, _use]:
		b.pressed.connect(_on_act)
		slot.add_child(b)
	_on_pill = ShopSheet.in_use_pill()
	_on_pill.custom_minimum_size.y = UIKit.H.md
	slot.add_child(_on_pill)
	body.add_child(slot)
	if int(d.get("price", 0)) > 0:
		_gem = ShopSheet.gem_option(Catalog.pawn_gems(pawn_id))
		_gem.pressed.connect(_on_gems)
		body.add_child(_gem)
	fit(0.92)


func _ready() -> void:
	Save.changed.connect(refresh)
	refresh()


## Re-read the profile: which action shows.
func refresh() -> void:
	if not is_instance_valid(_buy):
		return
	var own := Catalog.owns_pawn(pawn_id)
	var on := own and Catalog.pawn_in_use() == pawn_id
	var short := 0 if Catalog.pawn_gems_only(pawn_id) else int(Catalog.pawn(pawn_id).get("price", 0)) - Catalog.coins()
	_buy.visible = not own and short <= 0
	_need.visible = not own and short > 0
	_need.text = Fmt.shortfall(short)
	_use.visible = own and not on
	_on_pill.visible = on
	if _gem:
		_gem.visible = not own


## Buy with gems: the Shop's flow (a gem-only skin's Buy comes here too).
func _on_gems() -> void:
	if _busy or _closing or Catalog.owns_pawn(pawn_id):
		return
	_busy = true
	var res: String = await ShopSheet.buy_with_gems(self, "pawn", pawn_id, str(Catalog.pawn(pawn_id).get("name", "")))
	_busy = false
	if not is_instance_valid(self) or _closing:
		return
	if res == "store":
		store_requested.emit()
	elif res == "bought":
		changed.emit()
	refresh()


func _on_act() -> void:
	if _busy or _closing:
		return
	var d := Catalog.pawn(pawn_id)
	if d.is_empty():
		return
	if Catalog.owns_pawn(pawn_id):
		if Catalog.pawn_in_use() == pawn_id:
			return
		_busy = true
		var ok := false
		var why := Collection.SAVE_FAILED_EQUIP
		if _wallet():
			var r: Dictionary = await Account.instance().equip("pawn", pawn_id)
			ok = bool(r.get("ok", false))
			if not ok:
				why = Account.error_text(str(r.get("error", "")), "equip")
		else:
			ok = Catalog.equip_pawn(pawn_id)
		_busy = false
		if not is_instance_valid(self) or _closing:
			return
		if ok:
			Sound.sfx("select")
			Toast.show(self, tr("%s pawns are in use") % L10n.t(str(d.name)), card, 1.6, "good")
			changed.emit()
		else:
			Sound.sfx("error")
			Haptics.error()
			Toast.show(self, why, card, 2.2, "bad")
		refresh()
		return
	if Catalog.pawn_gems_only(pawn_id):
		await _on_gems()
		return
	var price := int(d.price)
	var short := price - Catalog.coins()
	if short > 0:
		Sound.sfx("error")
		Haptics.error()
		Toast.show(self, tr("Need %s more coins") % Fmt.coins(short), card, 1.8, "bad")
		return
	_busy = true
	if _wallet():
		var online: bool = await Account.instance().ensure_session()
		if not is_instance_valid(self) or _closing:
			return
		if not online:
			_busy = false
			Sound.sfx("error")
			Haptics.error()
			Toast.show(self, Account.error_text("offline", "buy"), card, 2.2, "bad")
			return
	var title := ShopSheet._title("pawn", str(d.name))
	var yes: bool = await Sheet.confirm(self, tr("Buy %s?") % title, tr("%s coins. You’ll have %s left.") % [Fmt.coins(price), Fmt.coins(Catalog.coins() - price)], tr("Buy"))
	if not yes or not is_instance_valid(self) or _closing:
		_busy = false
		return
	var err: String = await ShopSheet._purchase("pawn", pawn_id)
	_busy = false
	if not is_instance_valid(self) or _closing:
		return
	if err == "":
		Sound.sfx("buy")
		Haptics.success()
		Toast.show(self, tr("%s are yours!") % title, card, 1.8, "good")
		changed.emit()
	else:
		Sound.sfx("error")
		Haptics.error()
		Toast.show(self, err, card, 2.2, "bad")
	refresh()


static func _wallet() -> bool:
	return Account.wallet_active() and is_same(Catalog.profile(), Save.profile)
