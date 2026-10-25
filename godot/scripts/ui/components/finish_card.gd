class_name FinishCard
extends PanelContainer
## Play on: the compact, non-blocking card shown when YOUR side finishes and the game goes on (online), above the
## bottom of the game screen like the pair prompt: your place badge, "You finished 1st!" (Teams: "Your team
## finished 1st!"), a line that the others play on, and two buttons: Keep watching (closes the card; the board stays
## live under it) and Home (online: leave the room; your result is granted at the end anyway). The board stays
## visible and tappable around it.
##
##   var card := FinishCard.new()
##   card.watch_pressed.connect(...); card.home_pressed.connect(...)
##   hud.add_child(card)
##   card.present(2, false)          # shows itself (pop in); place_bottom / the HUD positions it

signal watch_pressed
signal home_pressed

const BADGE := 34.0

var place := 0
var title: Label
var sub: Label
var watch_button: Button
var home_button: Button
var _badge_slot: Control
var _badge: Control

func _init() -> void:
	name = "FinishCard"
	var st := UIKit.surface("card", false, true).duplicate() as StyleBoxFlat
	UIKit.pad(st, UIKit.SPACE.md, UIKit.SPACE.sm)
	add_theme_stylebox_override("panel", st)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var col := UIKit.vbox(UIKit.SPACE.xs)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	var head := UIKit.hbox(UIKit.SPACE.sm)
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	_badge_slot = Control.new()
	_badge_slot.custom_minimum_size = Vector2(BADGE, BADGE)
	_badge_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_badge_slot)
	title = UIKit.label("", UIKit.FS.h3, Palette.INK_STRONG, UIKit.font_display())
	title.name = "Title"
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(title)
	col.add_child(head)
	sub = UIKit.label("The others play on for the next places.", UIKit.FS.label, Palette.SUB, UIKit.font_body(800), HORIZONTAL_ALIGNMENT_CENTER)
	sub.name = "Sub"
	col.add_child(sub)
	var row := UIKit.hbox(UIKit.SPACE.sm)
	watch_button = UIKit.button("Keep watching", "honey", "sm")
	watch_button.name = "Watch"
	home_button = UIKit.button("Home", "ghost", "sm")
	home_button.name = "Home"
	for b in [watch_button, home_button]:
		b.custom_minimum_size.x = 128
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	watch_button.pressed.connect(func():
		visible = false
		watch_pressed.emit())
	home_button.pressed.connect(func(): home_pressed.emit())
	col.add_child(row)
	add_child(col)
	visible = false

## Shows the card for place n (1-based); team: your team finished; home: offer Home (off: only Keep watching).
func present(n: int, team := false, home := true) -> void:
	place = n
	title.text = ("Your team finished %s!" if team else "You finished %s!") % ResultScreen.ordinal(n)
	if _badge:
		_badge.queue_free()
	_badge = PlayerTile.PlaceBadge.make(n, BADGE)
	_badge_slot.add_child(_badge)
	home_button.visible = home
	visible = true
	size = get_combined_minimum_size()
	UIKit.pop_in(self)
