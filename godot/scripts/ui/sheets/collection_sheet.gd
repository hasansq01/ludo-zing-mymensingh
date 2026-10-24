class_name CollectionSheet
extends ShopSheet
## Forwarder (PLAN decision 4): the Collection is the Shop on the Avatars / Frames / Plates / Badges tabs. Opens with
## the "Owned" filter on (equipping), except the old Characters tab, which was for buying (all items).
## Same signals as ShopSheet; `changed` fires after anything is bought or put in use.
##   CollectionSheet.new("frames").open(layer)   ==   ShopSheet.new("frames", 400, true).open(layer)


func _init(start_tab := "avatars", width := 400.0) -> void:
	super(start_tab, width, start_tab != "chars")
