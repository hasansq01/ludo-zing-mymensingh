class_name InventorySheet
extends ShopSheet
## Forwarder (PLAN decision 4): the Inventory is the Shop with the "Owned" filter on. Same tabs, cards and signals
## (room_changed, dice_changed, scene_changed, changed) as ShopSheet.
##   InventorySheet.new("dice").open(layer)   ==   ShopSheet.new("dice", 400, true).open(layer)


func _init(start_tab := "rooms", width := 400.0) -> void:
	super(start_tab, width, true)
