class_name HoldNote
extends PanelContainer
## A small pill under the board's top tiles while another player may re-roll: "Rahim may roll again…" (the next player's
## dice wait for the hold, server/ECONOMY_V1.md section 4). Same look as the Reconnecting… pill (MatchLook.note_pill:
## a dark café pill with a gold rim, cream text).

var label: Label


func _init() -> void:
	name = "HoldNote"
	add_theme_stylebox_override("panel", MatchLook.note_pill())
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := UIKit.hbox(UIKit.SPACE.sm)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label = MatchLook.note_label()
	label.name = "Text"
	row.add_child(label)
	add_child(row)
	visible = false

## "Rahim may roll again…" for `who`'s name ("" hides it).
func set_who(who: String) -> void:
	label.text = "%s may roll again…" % who if who != "" else ""
	visible = who != ""
