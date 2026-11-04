extends Control
## Dev preview of the Sheet looks (phase 1, C-C): a CARD sheet, a PM sheet with its ribbon and close button, the
## confirm dialog (normal and danger), long scrolling sheets in both looks and a stacked sheet. One screenshot each:
##   godot --path . --resolution 390x844 res://dev/preview_sheet_c.tscn -- <out_dir> [suffix]

var out := "/tmp"
var suffix := ""
var layer: Control

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size():
		out = args[0]
	if args.size() > 1:
		suffix = "_" + args[1]
	theme = UIKit.theme()
	# a stand-in "home" behind the sheets so the scrim and the card edges read
	var bg := TextureRect.new()
	var g := Gradient.new()
	g.colors = PackedColorArray([Color("#3d2f70"), Color("#c98a6a")])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_to = Vector2(0, 1)
	bg.texture = gt
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var home := UIKit.vbox(16)
	home.position = Vector2(24, 80)
	home.add_child(UIKit.halo_label("Home behind the sheet", 22))
	for i in 3:
		home.add_child(UIKit.btn("Button %d" % (i + 1), "honey", "md"))
	add_child(home)
	layer = Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layer)
	_run()

func _run() -> void:
	await get_tree().process_frame
	# 1. CARD look: title, close, text, one primary action
	var a := Sheet.new("Snakes & Ladders", UIKit.W.form)
	a.add_text("Climb the ladders, dodge the snakes, and be the first to reach square 100.")
	a.add_button("Start game", "honey", func(): pass, "lg")
	await _show(a, "card")
	# 2. PM look: ribbon + close, a pane of rows
	var b := Sheet.new("Settings", UIKit.W.form, true, Sheet.LOOK_PM)
	var pane := UIKit.panel("pane", UIKit.vbox(10))
	for t in ["Sound", "Vibration", "Game speed", "Camera view"]:
		var row := UIKit.panel("row", UIKit.label(t, UIKit.FS.label, Palette.INK, UIKit.font_body(800)))
		pane.get_child(0).add_child(row)
	b.body.add_child(pane)
	b.add_button("How to play", "honey", func(): pass, "md")
	await _show(b, "pm")
	# 3. confirm, normal and danger
	await _show(Sheet.make_confirm("Restart this game?", "Everyone goes back to the start and this match's progress is lost.", "Restart", "Keep playing"), "confirm")
	await _show(Sheet.make_confirm("Leave this game?", "This game won't be saved.", "Leave", "Keep playing", true), "confirm_danger")
	# 4. long scrolling sheets (CARD and PM)
	for look in [Sheet.LOOK_CARD, Sheet.LOOK_PM]:
		var c := Sheet.new("How to play", UIKit.W.form, true, look)
		var list := c.add_scroll_body()
		for i in 14:
			var v := UIKit.vbox(4)
			v.add_child(UIKit.label("Rule %d" % (i + 1), UIKit.FS.h3, Palette.INK, UIKit.font_display()))
			v.add_child(UIKit.bullet_row("Roll a 6 to bring a pawn out. A 6 also gives you another roll."))
			list.add_child(UIKit.panel("row", v))
		await _show(c, "long_" + look)
	# 5. a long title in the ribbon, PM without a close button, stacked over a CARD sheet
	var d := Sheet.new("Player Profile", UIKit.W.wide)
	d.add_text("The sheet underneath.")
	d.add_button("Edit profile", "honey", func(): pass, "md")
	d.open(layer)
	await _sleep(0.3)
	var e := Sheet.new("A very long ribbon title that must shrink", UIKit.W.dialog, false, Sheet.LOOK_PM)
	e.add_text("A PM dialog without a close button, stacked on another sheet.")
	e.add_button("OK", "honey", func(): e.close(), "md")
	await _show(e, "stacked")
	d.close()
	await _sleep(0.3)
	# 6. Back closes the top dismissable sheet; confirm returns its answer
	var f := Sheet.new("Back test", UIKit.W.dialog)
	f.open(layer)
	await _sleep(0.3)
	print("back handled: ", Sheet.back(layer))
	await _sleep(0.3)
	print("sheets left after back: ", layer.get_child_count())
	_answer_later(true)
	print("confirm answered: ", await Sheet.confirm(layer, "Buy Pastel Dream Room for 3K?", "", "Buy", "Cancel"))
	_answer_later(false)
	print("confirm answered: ", await Sheet.confirm(layer, "Reset progress?", "Coins, rooms and stats go back to the start.", "Reset", "Cancel", true))
	get_tree().quit()

func _answer_later(yes: bool) -> void:
	await _sleep(0.5)
	var top := Sheet.top_sheet(layer)
	if top:
		(top.find_child("Yes" if yes else "No", true, false) as Button).pressed.emit()

func _show(s: Sheet, name: String) -> void:
	s.open(layer)
	await _sleep(0.55)
	await RenderingServer.frame_post_draw
	var path := "%s/sheet_%s%s.png" % [out, name, suffix]
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
	if name != "stacked":
		s.close()
		await _sleep(0.3)

func _sleep(t: float) -> void:
	await get_tree().create_timer(t).timeout
