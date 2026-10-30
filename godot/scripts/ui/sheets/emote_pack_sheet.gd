class_name EmotePackSheet
extends Sheet
## The Shop's "View" on an emote pack: the pack's name on the ribbon, its six emotes playing their animation
## (EmoteArt.frames) with their names, and one action: Buy (price), "Need 2.5K", Use, or the "In use" pill.
## Buy / Use go through the server wallet (Account) when there is one, else the local rules (previews, tests).
## Three of the 24 animations loop seamlessly (SEAMLESS); the others are not, so they replay with a short pause.
##   var s := EmotePackSheet.new("pawns"); s.changed.connect(refresh_shop); s.open(layer)

signal changed                           ## the pack was bought or put in use
signal store_requested                   ## "Open Store" after "not enough gems" (the Shop passes it on to Main)

const SEAMLESS := ["happy", "party", "cheer"]
const PAUSE_SEC := 0.9                   ## held on the last frame between two plays of a non-looping emote
const MAX_W := 400.0

var pack_id := ""
var _buy: Button
var _need: Button
var _use: Button
var _on_pill: PanelContainer
var _gem: Button                         # "or [gem] N": the same second price as the Shop card
var _cells: Array[EmoteCell] = []
var _busy := false


func _init(pack_id_ := "starter") -> void:
	var pk := Emotes.pack(pack_id_)
	super(str(pk.get("name", "Emotes")), MAX_W, true, LOOK_PM)
	pack_id = pack_id_
	var list := add_scroll_body(UIKit.SPACE.md)
	var g := UIKit.grid(2, UIKit.SPACE.sm)
	g.name = "Grid"
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var k := 0
	for eid: String in pk.get("emotes", []):
		var cell := EmoteCell.new(eid, float(k) * 0.22)
		_cells.append(cell)
		g.add_child(cell)
		k += 1
	list.add_child(g)
	var slot := MarginContainer.new()
	slot.custom_minimum_size.y = UIKit.TAP + 4
	slot.add_theme_constant_override("margin_top", UIKit.SPACE.sm)
	_buy = UIKit.button_with("Buy", CoinAmount.new(int(pk.get("price", 0)), "md", "plain"), "gold", "md")
	_buy.name = "Buy"
	var row := _buy.get_node("Content") as HBoxContainer
	row.move_child(row.get_child(0), -1)
	_need = UIKit.btn("", "off", "md")
	_need.name = "Need"
	_use = UIKit.btn("Use", "teal", "md")
	_use.name = "Use"
	for b: Button in [_buy, _need, _use]:
		b.pressed.connect(_on_act)
		slot.add_child(b)
	_on_pill = ShopSheet.in_use_pill()
	_on_pill.custom_minimum_size.y = UIKit.H.md
	slot.add_child(_on_pill)
	body.add_child(slot)
	if int(pk.get("price", 0)) > 0:
		_gem = ShopSheet.gem_option(Catalog.gem_price(int(pk.price)))
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
	var pk := Emotes.pack(pack_id)
	var own := Catalog.owns_emotes(pack_id)
	var on := own and Catalog.emotes_in_use() == pack_id
	var short := int(pk.get("price", 0)) - Catalog.coins()
	_buy.visible = not own and short <= 0
	_need.visible = not own and short > 0
	_need.text = Fmt.shortfall(short)
	_use.visible = own and not on
	_on_pill.visible = on
	if _gem:
		_gem.visible = not own


## Buy with gems: the Shop's flow.
func _on_gems() -> void:
	if _busy or _closing or Catalog.owns_emotes(pack_id):
		return
	_busy = true
	var res: String = await ShopSheet.buy_with_gems(self, "emotes", pack_id, str(Emotes.pack(pack_id).get("name", "")))
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
	var pk := Emotes.pack(pack_id)
	if pk.is_empty():
		return
	if Catalog.owns_emotes(pack_id):
		if Catalog.emotes_in_use() == pack_id:
			return
		_busy = true
		var ok := false
		var why := Collection.SAVE_FAILED_EQUIP
		if _wallet():
			var r: Dictionary = await Account.instance().equip("emotes", pack_id)
			ok = bool(r.get("ok", false))
			if not ok:
				why = Account.error_text(str(r.get("error", "")), "equip")
		else:
			ok = Catalog.equip_emotes(pack_id)
		_busy = false
		if not is_instance_valid(self) or _closing:
			return
		if ok:
			Sound.sfx("select")
			Toast.show(self, "%s is in use" % pk.name, card, 1.6, "good")
			changed.emit()
		else:
			Sound.sfx("error")
			Haptics.error()
			Toast.show(self, why, card, 2.2, "bad")
		refresh()
		return
	var price := int(pk.price)
	var short := price - Catalog.coins()
	if short > 0:
		Sound.sfx("error")
		Haptics.error()
		Toast.show(self, "Need %s more coins" % Fmt.coins(short), card, 1.8, "bad")
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
	var yes: bool = await Sheet.confirm(self, "Buy %s?" % pk.name, "%s coins. You’ll have %s left." % [Fmt.coins(price), Fmt.coins(Catalog.coins() - price)], "Buy")
	if not yes or not is_instance_valid(self) or _closing:
		_busy = false
		return
	var err := ""
	if _wallet():
		var r: Dictionary = await Account.instance().buy("emotes", pack_id)
		if not r.get("ok", false):
			err = Catalog.need_text(int(r.short)) if r.get("error", "") == "coins" and int(r.get("short", 0)) > 0 else Account.error_text(str(r.get("error", "")), "buy")
	else:
		err = Catalog.buy_emotes(pack_id)
	_busy = false
	if not is_instance_valid(self) or _closing:
		return
	if err == "":
		Sound.sfx("buy")
		Haptics.success()
		Toast.show(self, "%s is yours!" % pk.name, card, 1.8, "good")
		changed.emit()
	else:
		Sound.sfx("error")
		Haptics.error()
		Toast.show(self, err, card, 2.2, "bad")
	refresh()


static func _wallet() -> bool:
	return Account.wallet_active() and is_same(Catalog.profile(), Save.profile)


## One emote: its animation on a tinted well and its name under it. Plays through, and for the emotes that don't
## loop seamlessly rests on the last frame for PAUSE_SEC before the next play. Plays only while it is on screen.
class EmoteCell extends VBoxContainer:
	var emote_id := ""
	var _rect: TextureRect
	var _frames: SpriteFrames
	var _t := 0.0
	var _seamless := false

	func _init(id: String, offset_sec := 0.0) -> void:
		emote_id = id
		name = "Emote_%s" % id
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_theme_constant_override("separation", 2)
		_seamless = SEAMLESS.has(id)
		_frames = EmoteArt.frames(id)
		_t = offset_sec
		var well := PanelContainer.new()
		well.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var st := UIKit.box(Palette.SURFACE_2, UIKit.R.md)
		UIKit.pad(st, UIKit.SPACE.xs)
		well.add_theme_stylebox_override("panel", st)
		_rect = TextureRect.new()
		_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_rect.custom_minimum_size = Vector2(0, 84)
		_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_rect.texture = EmoteArt.icon(id)
		well.add_child(_rect)
		add_child(well)
		var nm := str(EmoteArt.info(id).get("name", id))
		var l := UIKit.label(nm, UIKit.FS.label, Palette.INK, UIKit.font_body(900), HORIZONTAL_ALIGNMENT_CENTER)
		l.name = "Name"
		add_child(l)
		_show(0.0)

	## Seconds of one play (frames / fps).
	func play_sec() -> float:
		if _frames == null or not _frames.has_animation("default"):
			return 0.0
		var fps := _frames.get_animation_speed("default")
		return float(_frames.get_frame_count("default")) / fps if fps > 0.0 else 0.0

	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		_t += delta
		_show(_t)

	## The frame at time t: a seamless loop wraps; the others play once, hold on the last frame, then start over.
	func frame_at(t: float) -> int:
		if _frames == null:
			return 0
		var n := _frames.get_frame_count("default")
		var d := play_sec()
		if n == 0 or d <= 0.0:
			return 0
		var cyc := d if _seamless else d + PAUSE_SEC
		var u := fposmod(t, cyc)
		return mini(int(u / d * n), n - 1)

	func _show(t: float) -> void:
		if _frames == null:
			return
		var n := _frames.get_frame_count("default")
		if n > 0:
			_rect.texture = _frames.get_frame_texture("default", frame_at(t))
