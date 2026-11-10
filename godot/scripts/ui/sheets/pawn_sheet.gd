class_name PawnSheet
extends OfferSheet
## The Shop's offer of a pawn skin (OfferSheet): the skin's baked pair of pawns large on the rarity card, bobbing
## gently (still with Reduce motion; a live PawnStage turntable only for a skin without a bake), its line
## (Catalog.PAWNS desc) and "All 4 colours", then the price: coins (with "or N gems") or, for the gem-only skins,
## gems. Buy / Use go through the server wallet (Account) when there is one, else the local rules (previews, tests),
## exactly as the Shop card.
##   var s := PawnSheet.new("crown"); s.changed.connect(refresh_shop); s.open(layer)

const BOB_PX := 6.0
const BOB_SEC := 0.9

var pawn_id: String:
	get: return item_id
var stage: PawnStage                     ## the live fallback (a skin without a bake)


func _init(pawn_id_ := "classic") -> void:
	super("pawn", pawn_id_, str(Catalog.pawn(pawn_id_).get("name", "Pawns")))


## The baked pair (as on the Shop card), bobbing inside a holder the layout sizes.
func _make_art() -> Control:
	var holder := Control.new()
	holder.name = "Pawns"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var p := OfferSheet.pawn_pair(item_id)
	if p is PawnStage:
		stage = p
	holder.add_child(p)
	p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.ready.connect(func() -> void:
		if Sheet.reduce_motion() or stage != null:
			return
		var tw := p.create_tween().set_loops()
		tw.tween_property(p, "position:y", -BOB_PX, BOB_SEC).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(p, "position:y", 0.0, BOB_SEC).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT))
	return holder

func _fact_list() -> Array:
	var d := Catalog.pawn(item_id)
	var out: Array = []
	if str(d.get("desc", "")) != "":
		out.append(tr(str(d.desc)))
	out.append(tr("All 4 colours"))
	return out
