extends "res://tests/test_suite.gd"
## Nothing in a match redraws every frame (GlowPulse): the active Ludo tile (PlayerTile and the HUD's Tile), the
## active S&L tile and the S&L dice pad breathe by alpha / scale / position only, and a running countdown redraws its
## own disc a step at a time (~10 a second), never the card. Each redraw of a StyleBoxFlat or polygon makes new GPU
## buffers in the GL Compatibility renderer, and Mali drivers keep native memory for every one (the app was killed after
## ~20-30 minutes on an Infinix X6886 and an OPPO CPH2251). Counts each control's `draw` signal over FRAMES frames.

const FRAMES := 30

func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree

func _frames(n: int) -> void:
	for k in n:
		await _tree().process_frame

## How many times each canvas item in `cs` draws in FRAMES frames over at least half a second, once the cards'
## own short tweens (the turn's scale, the card opening) are done.
func _count(cs: Array) -> Array:
	await _tree().create_timer(0.6).timeout
	var n := []
	for c: CanvasItem in cs:
		n.append(0)
	for i in cs.size():
		var k := i
		(cs[i] as CanvasItem).draw.connect(func(): n[k] += 1)
	var t0 := Time.get_ticks_msec()
	var f := 0
	while f < FRAMES or Time.get_ticks_msec() - t0 < 500:
		await _tree().process_frame
		f += 1
	return n

func run() -> void:
	var root := _tree().root
	var sp: Dictionary = Save.prefs
	Save.prefs = sp.duplicate(true)
	Save.prefs.reduce_motion = false

	var pt := PlayerTile.new(0, "left")
	pt.set_player("You", "you")
	root.add_child(pt)
	pt.set_state(true, false, 1, 0.3)
	var glow := pt.find_child("Glow", false, false) as GlowPulse
	var a0 := glow.modulate.a
	var n: Array = await _count([pt, glow])
	check("PlayerTile, active: the card doesn't redraw every frame (glow breathes)", n[0] <= 1 and n[1] <= 1, n)
	check("…the glow is showing and breathing (alpha / scale change)", glow.visible and (glow.modulate.a != a0 or glow.scale != Vector2.ONE), [glow.modulate.a, glow.scale])
	pt.set_state(false, false, 1, 0.3)
	await _frames(2)
	check("PlayerTile, waiting: no glow, no processing", not glow.visible and not pt.is_processing())
	pt.free()

	var ht := LudoHUD.Tile.new(1, "right")
	ht.set_player("Mocha", "cpu", "mocha")
	root.add_child(ht)
	ht.set_state(true, false, 0, 0.1)
	var hg := ht.find_child("Glow", false, false) as GlowPulse
	n = await _count([ht, hg])
	check("HUD tile, active: no redraw a frame once open", n[0] <= 1 and n[1] <= 1, n)
	check("…the glow sits round the open card at full strength", is_equal_approx(hg.strength, 1.0) and hg.visible, [hg.strength, hg.visible])
	await _tree().create_timer(0.4).timeout
	ht.timer_end = Time.get_ticks_msec() + 15000
	ht.timer_total = 15000.0
	var disc := ht.find_child("TimerDisc", false, false) as Control
	var nd := [0, 0]
	ht.draw.connect(func(): nd[0] += 1)
	disc.draw.connect(func(): nd[1] += 1)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 600:
		ht.tick_timer()
		await _tree().process_frame
	check("HUD tile countdown: the disc redraws a step at a time (~10 a second), the card not at all", nd[0] <= 1 \
		and nd[1] >= 3 and nd[1] <= 9, nd)
	ht.free()

	var st := SLMatch.SLTile.new(2, "Biscotti", "cpu", "biscotti")
	st.set_width(96.0)
	root.add_child(st)
	st.set_state(true)
	var sg := st.find_child("Glow", false, false) as GlowPulse
	var ptr := st.find_child("Pointer", false, false) as Control
	var y0 := ptr.position.y
	n = await _count([st, sg, ptr])
	check("S&L tile, active: no redraw a frame (glow, pointer)", n[0] <= 1 and n[1] <= 1 and n[2] <= 1, n)
	check("…the pointer bobs by position", ptr.visible and ptr.position.y != y0, [ptr.visible, y0, ptr.position.y])
	st.free()

	var pad := SLMatch.DicePad.new()
	pad.size = Vector2(70, 70)
	root.add_child(pad)
	pad.set_color(3, true)
	pad.hint = true
	var pg := pad.find_child("Glow", false, false) as GlowPulse
	var face := pad.find_child("Face", false, false) as Node2D
	n = await _count([pad, pg, face])
	check("S&L dice pad, your turn with the hint: no redraw a frame", n[0] <= 1 and n[1] <= 1 and n[2] <= 1, n)
	check("…it still bounces (its face's scale) and glows", face.scale != Vector2.ONE and pg.visible, [face.scale, pg.visible])
	pad.free()

	Save.prefs = sp
	Save._dirty = false
