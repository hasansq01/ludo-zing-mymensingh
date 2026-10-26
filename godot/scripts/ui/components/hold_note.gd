class_name HoldNote
extends PanelContainer
## A small pill under the board's top tiles while another player may re-roll: "Rahim may roll again…" (the next player's
## dice wait for the hold, server/ECONOMY_V1.md section 4). Same look as the Reconnecting… pill.

var label: Label


func _init() -> void:
	name = "HoldNote"
	var bs := UIKit.box(Palette.HONEY_TINT, UIKit.R.pill, UIKit.BW.line, Color.WHITE)
	UIKit.shade(bs, "sm")
	UIKit.pad(bs, UIKit.SPACE.md, UIKit.SPACE.xs)
	add_theme_stylebox_override("panel", bs)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := UIKit.hbox(UIKit.SPACE.sm)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label = UIKit.label("", UIKit.FS.label, Palette.ON_HONEY, UIKit.font_body(900))
	label.name = "Text"
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	add_child(row)
	visible = false

## "Rahim may roll again…" for `who`'s name ("" hides it).
func set_who(who: String) -> void:
	label.text = "%s may roll again…" % who if who != "" else ""
	visible = who != ""
