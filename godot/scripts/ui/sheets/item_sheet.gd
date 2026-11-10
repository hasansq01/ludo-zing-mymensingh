class_name ItemSheet
extends OfferSheet
## The Shop's offer for what has no live preview of its own: dice (a large die), characters (a large portrait),
## frames (your picture in the frame) and nameplates, on the offer card (OfferSheet: rarity colours, the chunky price,
## "or N gems", Use / In use / the lock).
##   var s := ItemSheet.new("dice", "gold"); s.changed.connect(...); s.open(layer)


func _init(kind_ := "dice", id := "classic") -> void:
	var n := ""
	match kind_:
		"dice": n = str(Catalog.dice(id).get("name", id))
		"frame": n = str(Collection.frame(id).get("name", id))
		"plate": n = str(Collection.plate(id).get("name", id))
		_: n = str(Collection.character(id).get("name", id))
	super(kind_, id, n)
