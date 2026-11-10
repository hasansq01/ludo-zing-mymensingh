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
	super(L10n.t(str(d.get("name", "Pawns"))), MAX_W, true, LOOK_GAME)
	pawn_id = pawn_id_
	body.add_theme_constant_override("separation", UIKit.SPACE.sm)
	var well := PanelContainer.new()
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ws := UIKit.box(Palette.WOOD_DEEP, UIKit.R.lg, UIKit.BW.line, Palette.WOOD_RIM)
	UIKit.pad(ws, 0)
	well.add_theme_stylebox_override("panel", ws)
	# the skin's baked row (the four colours, as on the cards), each pawn bobbing on its own beat: no live 3D here.
	# A transparent, multisampled SubViewport inside a clipped well made the whole screen flicker on some phones
	# (only the café showed in alternate frames); the live stage is only the fallback for a skin without a bake.
	if Thumbnailer.has_baked("pawnrow", pawn_id):
		var stage_box := Control.new()
		stage_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stage_box.clip_contents = true        # a plain scissor clip (not clip_children: that's what flickered on phones)
		stage_box.add_child(ShopSheet.rarity_stage("pawn", pawn_id))
		var row := _baked_row()
		stage_box.add_child(row)
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		stage_box.custom_minimum_size = Vector2(0, STAGE_H)
		well.add_child(stage_box)
	else:
		well.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
		stage = PawnStage.new(pawn_id, PawnStage.FOUR)
		stage.custom_minimum_size = Vector2(0, STAGE_H)
		well.add_child(stage)
	body.add_child(well)
	var kind := UIKit.caption(tr("Pawn skin · Ludo and Snakes & Ladders"))
	kind.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kind.add_theme_color_override("font_color", Palette.G_GOLD)
	body.add_child(kind)
	var desc := UIKit.paragraph(tr(str(d.get("desc", ""))), UIKit.FS.body_l, Palette.G_SUB, HORIZONTAL_ALIGNMENT_CENTER)
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
	var err: String = await ShopSheet._purchase("pawn", pawn_id)
	_busy = false
	if not is_instance_valid(self) or _closing:
		return
	if err == "":
		Sound.sfx("buy")
		Haptics.success()
		ShopSheet.reveal(self, "pawn", pawn_id, title)
		changed.emit()
	else:
		Sound.sfx("error")
		Haptics.error()
		Toast.show(self, err, card, 2.2, "bad")
	refresh()


static func _wallet() -> bool:
	return Account.wallet_active() and is_same(Catalog.profile(), Save.profile)



## The four pawns from the skin's baked row, side by side, each bobbing gently. Each pawn sits in a holder the layout
## places; the bob moves the pawn inside it (0 to -6 px), so a resize never leaves the bob on a stale height.
func _baked_row() -> Control:
	var box := Control.new()
	box.name = "Pawns"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.custom_minimum_size = Vector2(0, STAGE_H)
	var holders: Array[Control] = []
	var pawns: Array[TextureRect] = []
	for c in 4:
		var cell := Thumbnailer.pawn_cell(pawn_id, c)
		var at := AtlasTexture.new()
		at.atlas = cell[0]
		at.region = cell[1]
		var holder := Control.new()
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(holder)
		var t := TextureRect.new()
		t.texture = at
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(t)
		holders.append(holder)
		pawns.append(t)
	var lay := func() -> void:
		var w := box.size.x / 4.0
		var h := minf(box.size.y - 20.0, w * float(Thumbnailer.PAWN_CELL.y) / float(Thumbnailer.PAWN_CELL.x))
		for i in 4:
			holders[i].position = Vector2(i * w, (box.size.y - h) / 2.0 + 3.0)
			holders[i].size = Vector2(w, h)
			pawns[i].size = Vector2(w, h)
	box.resized.connect(lay)
	box.ready.connect(func() -> void:
		if Sheet.reduce_motion():
			return
		for i in 4:          # each loop lasts 1.94 s; the pawns start 0.18 s apart
			var tw := pawns[i].create_tween().set_loops()
			if i > 0:
				tw.tween_interval(0.18 * i)
			tw.tween_property(pawns[i], "position:y", -6.0, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			tw.tween_property(pawns[i], "position:y", 0.0, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			if i < 3:
				tw.tween_interval(0.54 - 0.18 * i))
	return box
