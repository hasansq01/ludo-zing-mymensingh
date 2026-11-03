extends "res://tests/test_suite.gd"
## Sheet stacking (sheet.gd): a pm sheet opened over another covers it (the lower card fades out and hides, its
## backdrop goes, it is inert) and closing it uncovers the lower one as it was (same scroll); chains of three close
## back one at a time; a sheet closed while covered, or freed without close(), leaves the stack right; a confirm
## over a pm sheet keeps that sheet's card but not its backdrop. At every frame the game is dimmed by one SCRIM.
## Runs on a throwaway layer in the live tree; the save is never read or written.

var layer: Control
var dims: Array[float] = []              # the game's dim per frame while sampling

func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree

func run() -> void:
	layer = Control.new()
	layer.name = "StackTestLayer"
	layer.size = Vector2(360, 780)
	_tree().root.add_child(layer)
	await _chain_of_three()
	await _close_while_covered()
	await _freed_without_close()
	await _confirm_over_pm()
	await _same_frame()
	await _remove_all()
	await _reduced()
	await _z_order()
	await _clamped_width()
	layer.free()

func pm(title: String, rows := 0) -> Sheet:
	var s := Sheet.new(title, 340.0, true, "pm")
	if rows > 0:
		var list := s.add_scroll_body()
		for k in rows:
			var l := Label.new()
			l.text = "Row %d" % k
			l.custom_minimum_size.y = 40
			list.add_child(l)
	return s

## The dim over the game now: every visible sheet's backdrop, stacked.
func dim() -> float:
	var clear := 1.0
	for c in layer.get_children():
		if c is Sheet and (c as Sheet).visible:
			clear *= 1.0 - Palette.SCRIM.a * (c as Sheet).modulate.a * (c as Sheet).backdrop.modulate.a
	return 1.0 - clear

func visible_cards() -> int:
	var n := 0
	for c in layer.get_children():
		if c is Sheet and (c as Sheet).card.visible and (c as Sheet).card.modulate.a > 0.01 and not (c as Sheet)._closing:
			n += 1
	return n

func scrims() -> int:
	var n := 0
	for c in layer.get_children():
		if c is Sheet and (c as Sheet).visible and (c as Sheet).modulate.a * (c as Sheet).backdrop.modulate.a > 0.01:
			n += 1
	return n

## Wait `sec`, sampling the dim every frame (the worst drift from one SCRIM is checked by the caller).
func settle(sec := 0.4) -> void:
	var until := Time.get_ticks_msec() + int(sec * 1000.0)
	while Time.get_ticks_msec() < until:
		await _tree().process_frame
		dims.append(dim())

func drift() -> float:
	var worst := 0.0
	for d in dims:
		worst = maxf(worst, absf(d - Palette.SCRIM.a))
	dims.clear()
	return worst

func shows(s: Sheet) -> bool:
	return s.card.visible and is_equal_approx(s.card.modulate.a, 1.0) and s.card.scale.is_equal_approx(Vector2.ONE)

func inert(s: Sheet) -> bool:
	return s.mouse_behavior_recursive == Control.MOUSE_BEHAVIOR_DISABLED and s.focus_behavior_recursive == Control.FOCUS_BEHAVIOR_DISABLED


func _chain_of_three() -> void:
	var a := pm("A", 40)
	a.open(layer)
	await settle()
	dims.clear()
	a.scroll_box.scroll_vertical = 120
	await _tree().process_frame
	var scrolled := a.scroll_box.scroll_vertical
	var b := pm("B")
	b.open(layer)
	await _tree().process_frame
	await _tree().process_frame
	var mid := a.card.visible and a.card.modulate.a < 1.0
	check("stack: mid-cover the lower card is fading", mid, a.card.modulate.a)
	await settle()
	check("stack: pm over pm: the lower sheet is covered and hidden", a._cover == "hide" and not a.card.visible and b._cover == "", [a._cover, a.visible])
	check("stack: covered card shrinks to COVER_SCALE (or stays 1 with Reduce motion)",
		a.card.scale.is_equal_approx(Vector2.ONE * (1.0 if Sheet.reduce_motion() else Sheet.COVER_SCALE)), a.card.scale)
	check("stack: only the top backdrop dims", is_zero_approx(a.backdrop.modulate.a) and is_equal_approx(b.backdrop.modulate.a, 1.0) and scrims() == 1)
	check("stack: the covered sheet is inert, the top is not", inert(a) and not inert(b))
	check("stack: only the top shows its close button", not a.close_btn.visible and b.close_btn.visible)
	var c := pm("C")
	c.open(layer)
	await settle()
	check("stack: chain of three: one card shows", visible_cards() == 1 and a._cover == "hide" and b._cover == "hide" and not b.card.visible, visible_cards())
	check("stack: chain of three: one scrim", scrims() == 1)
	check("stack: Back goes to the top", Sheet.top_sheet(layer) == c and Sheet.back(layer))
	await settle()
	check("stack: closing C uncovers B (A stays hidden)", not is_instance_valid(c) and shows(b) and b._cover == "" and not a.card.visible and not inert(b) and b.close_btn.visible)
	check("stack: B owns the scrim again", is_equal_approx(b.backdrop.modulate.a, 1.0) and scrims() == 1)
	b.close()
	await settle()
	check("stack: closing B uncovers A as it was", not is_instance_valid(b) and shows(a) and a._cover == "" and not inert(a) and a.close_btn.visible)
	check("stack: A keeps its scroll position", a.scroll_box.scroll_vertical == scrolled and scrolled > 0, [scrolled, a.scroll_box.scroll_vertical])
	check("stack: one SCRIM over the game at every frame (open, close, chain)", drift() < 0.02)
	a.close()
	await settle()
	check("stack: all closed", Sheet.top_sheet(layer) == null and layer.get_child_count() == 0)
	dims.clear()

func _close_while_covered() -> void:
	var a := pm("A")
	a.open(layer)
	await settle()
	dims.clear()
	var b := pm("B")
	b.open(layer)
	await settle()
	a.close()                                 # programmatic, from under B
	await settle()
	check("stack: a sheet closed while covered goes; the top stays as it is", not is_instance_valid(a) and shows(b) and b._cover == ""
		and is_equal_approx(b.backdrop.modulate.a, 1.0))
	check("stack: …and nothing is dimmed twice on the way", drift() < 0.02)
	b.close()
	await settle()
	dims.clear()

func _freed_without_close() -> void:
	var a := pm("A")
	a.open(layer)
	await settle()
	dims.clear()
	var b := pm("B")
	b.open(layer)
	await settle()
	b.queue_free()
	await settle()
	check("stack: a top sheet freed without close() uncovers the one below", shows(a) and a._cover == "" and a.close_btn.visible and not inert(a))
	check("stack: …which takes the scrim at once", is_equal_approx(a.backdrop.modulate.a, 1.0) and scrims() == 1)
	a.close()
	await settle()
	dims.clear()

func _confirm_over_pm() -> void:
	var a := pm("A")
	a.open(layer)
	await settle()
	dims.clear()
	var q := Sheet.make_confirm("Sure?", "Really.", "Yes")
	q.open(layer)
	await settle()
	check("stack: a confirm over a pm sheet: its card still shows", a._cover == "dim" and shows(a) and inert(a))
	check("stack: …but only the confirm's backdrop dims", is_zero_approx(a.backdrop.modulate.a) and is_equal_approx(q.backdrop.modulate.a, 1.0) and scrims() == 1)
	check("stack: …one SCRIM at every frame", drift() < 0.02)
	var b := pm("B")                          # a pm sheet over the confirm hides both
	b.open(layer)
	await settle()
	check("stack: pm over confirm over pm: one card", visible_cards() == 1 and a._cover == "hide" and q._cover == "hide")
	b.close()
	await settle()
	check("stack: back to the confirm over the pm sheet", q._cover == "" and a._cover == "dim" and shows(a) and shows(q) and scrims() == 1)
	var answer := [null]
	q.answered.connect(func(v: bool): answer[0] = v)
	q.on_back()
	await settle()
	check("stack: the confirm answered no and A is the top again", answer[0] == false and a._cover == "" and not inert(a) and is_equal_approx(a.backdrop.modulate.a, 1.0))
	check("stack: confirm close: one SCRIM at every frame", drift() < 0.02)
	a.close()
	await settle()
	dims.clear()

func _same_frame() -> void:
	var a := pm("A")
	var b := pm("B")
	a.open(layer)
	b.open(layer)                             # before A's pop has started
	await settle()
	check("stack: opened in one frame: the lower one is hidden, not popped", a._cover == "hide" and not a.card.visible and shows(b) and scrims() == 1)
	b.close()
	await settle()
	check("stack: …and comes back on close", shows(a) and is_equal_approx(a.backdrop.modulate.a, 1.0))
	a.close()
	await settle()
	dims.clear()

func _remove_all() -> void:
	var a := pm("A")
	a.open(layer)
	var b := pm("B")
	b.open(layer)
	await settle()
	for c in layer.get_children():            # main.close_all_sheets()
		layer.remove_child(c)
		c.queue_free()
	await settle()
	check("stack: close all: the layer is empty and nothing is left covered", layer.get_child_count() == 0 and Sheet.top_sheet(layer) == null)
	dims.clear()

func _reduced() -> void:
	var save: Node = _tree().root.get_node_or_null("Save")
	if save == null or not (save.get("prefs") is Dictionary):
		return
	var prefs: Dictionary = save.get("prefs")
	var keep: Variant = prefs.get("reduce_motion", false)
	prefs.reduce_motion = true                # in memory only
	var a := pm("A")
	a.open(layer)
	await settle()
	dims.clear()
	var b := pm("B")
	b.open(layer)
	await settle()
	check("stack: Reduce motion: covered by a fade only (no shrink)", a._cover == "hide" and not a.card.visible and a.card.scale.is_equal_approx(Vector2.ONE))
	b.close()
	await settle()
	check("stack: Reduce motion: uncovered as it was, one SCRIM throughout", shows(a) and drift() < 0.02)
	a.close()
	await settle()
	dims.clear()
	prefs.reduce_motion = keep


## The absolute z of a CanvasItem (z_index summed up the tree while z_as_relative).
func eff_z(n: CanvasItem) -> int:
	var z := 0
	var c: Node = n
	while c is CanvasItem:
		z += (c as CanvasItem).z_index
		if not (c as CanvasItem).z_as_relative:
			break
		c = c.get_parent()
	return z

func max_z(n: Node, acc := -1000000) -> int:
	if n is CanvasItem:
		acc = maxi(acc, eff_z(n))
	for k in n.get_children():
		acc = max_z(k, acc)
	return acc

## SH-01: nothing in a lower sheet (a folder tab strip, a level star row, a stray raised child) draws above the sheet
## stacked over it.
func _z_order() -> void:
	var low := pm("Profile")
	var stack := UIKit.vbox(0)
	low.body.add_child(stack)
	var tabs := TabStrip.new([{key = "a", text = "Me", icon = "tab_profile"}, {key = "b", text = "More", icon = "ic_trophy"}], "a", "folder")
	var pane := PanelContainer.new()
	pane.add_theme_stylebox_override("panel", TabStrip.pane_style("folder"))
	tabs.bind_pane(pane)
	stack.add_child(tabs)
	stack.add_child(pane)
	var meter := Meter.new("xp", 18, true, "XP")
	var lvl := LevelBadge.new(12, "sm")
	pane.add_child(LevelBadge.row(lvl, meter))
	var stray := Control.new()
	stray.z_index = 1
	low.body.add_child(stray)
	low.open(layer)
	await _tree().process_frame
	var up := pm("Leaderboard")
	up.open(layer)
	for i in 4:
		await _tree().process_frame
	check("z: folder tabs have no z_index", tabs.z_index == 0)
	check("z: the level star has no z_index", lvl.z_index == 0 and meter.show_behind_parent)
	check("z: the upper sheet sits above the lower sheet's raised child", eff_z(up) > max_z(low), "%d vs %d" % [eff_z(up), max_z(low)])
	check("z: the upper sheet sits above the lower sheet", eff_z(up) > eff_z(low))
	check("pane: both top corners rounded", (pane.get_theme_stylebox("panel") as TabStrip.FolderPaneStyle).face.corner_radius_top_left == UIKit.R.lg and (pane.get_theme_stylebox("panel") as TabStrip.FolderPaneStyle).face.corner_radius_top_right == UIKit.R.lg)
	up.close()
	await _tree().create_timer(0.3).timeout
	low.close()
	await _tree().create_timer(0.3).timeout

## SH-04: content with a wide minimum can't make the card wider than the sheet's width; SH-07: two-digit levels get a
## star of at least 28 px.
func _clamped_width() -> void:
	var s := pm("Wide")
	var wide := Control.new()
	wide.custom_minimum_size = Vector2(900, 20)
	s.body.add_child(wide)
	s.fit()
	s.open(layer)
	for i in 4:
		await _tree().process_frame
	check("clamp: a 900 px child doesn't widen the card", s.card.size.x <= 340.5, str(s.card.size.x))
	s.close()
	await _tree().create_timer(0.3).timeout
	check("badge: level 12 never below 28 px", LevelBadge.new(12, "xs").px == 28.0 and LevelBadge.new(9, "xs").px == 24.0)
