class_name ItemSheet
extends Sheet
## The Shop's buy screen for what has no live preview of its own: dice (a large die), characters (a large portrait) and
## frames (your picture in the frame, large, under a spotlight).
## The item's name on the ribbon, its art, and one action, like PawnSheet: Buy with the price, "Need 2.5K", Use, or the
## "In use" pill, with the Shop's "or [gem] N" line under a price. Buy goes through the Shop's flow (server wallet,
## confirm, put in use).
##   var s := ItemSheet.new("dice", "gold"); s.changed.connect(...); s.open(layer)

signal changed                           ## bought or put in use
signal store_requested                   ## "Open Store" after "not enough gems" (the Shop passes it on to Main)

const MAX_W := 360.0
const ART_H := 190.0
const FRAME_ART_H := 236.0                ## a frame's crest and tassels need the room
const FRAME_AVA := 150.0

var kind := ""
var item_id := ""
var _name := ""
var _buy: Button
var _need: Button
var _use: Button
var _on_pill: PanelContainer
var _gem: Button
var _gems_only := false                  ## a premium frame: Buy pays gems (no coin price, no "or gems" line)
var _busy := false


func _init(kind_ := "dice", id := "classic") -> void:
	kind = kind_
	item_id = id
	match kind:
		"dice": _name = str(Catalog.dice(id).get("name", id))
		"frame": _name = str(Collection.frame(id).get("name", id))
		"plate": _name = str(Collection.plate(id).get("name", id))
		_: _name = str(Collection.character(id).get("name", id))
	super(L10n.t(_name), MAX_W, true, LOOK_PM)
	body.add_theme_constant_override("separation", UIKit.SPACE.sm)
	var well := PanelContainer.new()
	well.name = "Art"
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	var cat: Color = (Palette.CAT.dice if kind == "dice" else Palette.CAT.avatars)[0]
	var ws := UIKit.box(cat.lerp(Color.WHITE, 0.72), UIKit.R.lg)
	UIKit.pad(ws, 0)
	well.add_theme_stylebox_override("panel", ws)
	well.custom_minimum_size = Vector2(0, FRAME_ART_H if kind == "frame" else (150.0 if kind == "plate" else ART_H))
	if kind in ["frame", "plate"]:
		well.add_child(_spotlight())
	var c := CenterContainer.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.add_child(c)
	match kind:
		"dice": c.add_child(Thumbnailer.dice_art(id, 170))
		"frame": c.add_child(Collection.make_avatar_of(Collection.equipped("avatar"), id, FRAME_AVA))
		"plate": c.add_child(Collection.make_plate(str(Collection.profile().get("name", "You")), id, "", 30, true, 220.0))
		_: c.add_child(Collection.make_avatar_of(id, Collection.equipped("frame"), 136))
	body.add_child(well)
	var what := UIKit.caption({dice = tr("Dice · Ludo and Snakes & Ladders"), frame = tr("Frame · round your picture in every game"), plate = tr("Nameplate · under your name in every game")}.get(kind, tr("Character · your picture in every game")))
	what.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(what)
	var slot := MarginContainer.new()
	slot.custom_minimum_size.y = UIKit.TAP + 4
	slot.add_theme_constant_override("margin_top", UIKit.SPACE.xs)
	var price := ShopSheet._price(kind, id)
	_gems_only = ShopSheet._gems_only(kind, id)
	var tag: Control = CoinAmount.gems(ShopSheet._gems(kind, id), "md", "plain") if _gems_only else CoinAmount.new(price, "md", "plain")
	_buy = UIKit.button_with(tr("Buy"), tag, "gold", "md")
	_buy.name = "Buy"
	var row := _buy.get_node("Content") as HBoxContainer
	row.move_child(row.get_child(0), -1)
	_need = UIKit.btn("", "off", "md")
	_need.name = "Need"
	_use = UIKit.btn(tr("Use"), "teal", "md")
	_use.name = "Use"
	for b: Button in [_buy, _need, _use]:
		b.pressed.connect(_on_gems if b == _buy and _gems_only else _on_act)
		slot.add_child(b)
	_on_pill = ShopSheet.in_use_pill()
	_on_pill.custom_minimum_size.y = UIKit.H.md
	slot.add_child(_on_pill)
	body.add_child(slot)
	if price > 0:
		_gem = ShopSheet.gem_option(ShopSheet._gems(kind, id))
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
	var own := ShopSheet._owned(kind, item_id)
	var on := own and ShopSheet._in_use(kind, item_id)
	var short := 0 if _gems_only else ShopSheet._price(kind, item_id) - Catalog.coins()
	_buy.visible = not own and short <= 0
	_need.visible = not own and short > 0
	_need.text = Fmt.shortfall(short)
	_use.visible = own and not on
	_on_pill.visible = on
	if _gem:
		_gem.visible = not own


func _on_gems() -> void:
	if _busy or _closing or ShopSheet._owned(kind, item_id):
		return
	_busy = true
	var res: String = await ShopSheet.buy_with_gems(self, kind, item_id, _name)
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
	_busy = true
	var ok := false
	if ShopSheet._owned(kind, item_id):
		var why: String = await ShopSheet.equip_item(kind, item_id)
		if not is_instance_valid(self) or _closing:
			return
		ok = why == ""
		if not ok:
			Sound.sfx("error")
			Haptics.error()
			Toast.show(self, why, card, 2.2, "bad")
		else:
			Sound.sfx("select")
	else:
		ok = await ShopSheet.buy_with_coins(self, kind, item_id, _name)
		if not is_instance_valid(self) or _closing:
			return
	_busy = false
	if ok:
		changed.emit()
	refresh()


## Behind a frame: a warm spotlight on dark wood, so gold, gems and chrome read the way they were lit.
func _spotlight() -> TextureRect:
	var g := GradientTexture2D.new()
	g.width = 128; g.height = 128
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.42); g.fill_to = Vector2(1.05, 1.0)
	g.gradient = Gradient.new()
	g.gradient.set_color(0, Color("#7a4a2c"))
	g.gradient.set_color(1, Color("#2a160d"))
	var t := TextureRect.new()
	t.name = "Spotlight"
	t.texture = g
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return t
