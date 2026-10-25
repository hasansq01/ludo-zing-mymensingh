extends "res://tests/test_suite.gd"
## Phase 1 C-A components: CoinAmount text comes from Fmt, Meter clamps, TabStrip select / picked, LevelBadge,
## Toast wrapping and one-at-a-time.

func run() -> void:
	# ---- CoinAmount: the text is Fmt's ----
	var c := CoinAmount.new(5300, "md", "chip")
	check("coin: short form", c.text() == Fmt.coins(5300) and c.text() == "5.3K", c.text())
	c.set_amount(999)
	check("coin: set_amount", c.text() == "999" and c.amount == 999, c.text())
	c.set_amount(1250000, true)                  # not in the tree: no tween, shown at once
	check("coin: animate outside the tree is instant", c.text() == "1.3M", c.text())
	var f := CoinAmount.new(5300, "sm", "plain", "", true)
	check("coin: full form", f.text() == Fmt.coins_full(5300) and f.text() == "5,300", f.text())
	var g := CoinAmount.new(200, "xs", "price", "+")
	check("coin: prefix", g.text() == "+200", g.text())
	var bad := CoinAmount.new(10, "huge", "neon")
	check("coin: unknown size / look fall back", bad.size_name == "sm" and bad.look == "plain", [bad.size_name, bad.look])
	var night := CoinAmount.new(12500, "lg", "night")
	check("coin: night look", night.text() == "12.5K" and night.coin != null)
	for n in [c, f, g, bad, night]:
		n.free()

	# ---- Meter: clamps, fraction, numbers ----
	var m := Meter.new("xp", 18, true, "XP")
	m.set_value(45, 150)
	check("meter: fraction", is_equal_approx(m.fraction(), 0.3), m.fraction())
	check("meter: numbers", m.label_text() == "45 / 150 XP", m.label_text())
	m.set_value(400, 150)
	check("meter: clamps above max", m.value == 150.0 and is_equal_approx(m.fraction(), 1.0), m.value)
	m.set_value(-20, 150)
	check("meter: clamps below 0", m.value == 0.0 and m.fraction() == 0.0, m.value)
	m.set_value(5, 0)
	check("meter: max 0 is an empty bar", m.fraction() == 0.0 and m.value == 0.0, [m.value, m.max_value])
	m.set_value(1200, 5000, true)                # not in the tree: no tween
	check("meter: grouped numbers, instant outside the tree", m.label_text() == "1,200 / 5,000 XP" and is_equal_approx(m.shown_fraction(), 0.24), m.label_text())
	var plain := Meter.new("night", 9)
	check("meter: no numbers by default", plain.label_text() == "" and plain.custom_minimum_size.y == 9.0)
	var teal := Meter.new("teal", 10, true)
	check("meter: numbers need 16 px", m.custom_minimum_size.y == 18.0 and teal.custom_minimum_size.y == 16.0)
	teal.free()
	m.set_text("Max level")
	check("meter: text override", m.label_text() == "Max level")
	m.free()
	plain.free()

	# ---- TabStrip ----
	var items := [{key = "rooms", text = "Rooms", cat = "rooms"}, {key = "dice", text = "Dice", cat = "dice"},
		{key = "badges", text = "Badges", cat = "badges"}]
	var t := TabStrip.new(items, "dice")
	var got: Array = []
	t.picked.connect(func(k: String) -> void: got.append(k))
	check("tabs: initial selection", t.selected == "dice")
	t.select("badges")
	check("tabs: select() changes it without picked", t.selected == "badges" and got.is_empty(), got)
	t.select("nope")
	check("tabs: unknown key ignored", t.selected == "badges")
	t.tap("rooms")
	check("tabs: tap emits picked", t.selected == "rooms" and got == ["rooms"], got)
	t.tap("rooms")
	check("tabs: tapping the selected tab doesn't emit", got == ["rooms"], got)
	t.set_count("badges", 3)
	check("tabs: count", t.get_count("badges") == 3)
	# a real press + release on the second tab (sound off: haptic only, no audio in the headless run)
	t.sound = ""
	t.size = Vector2(366, TabStrip.H_ON)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = Vector2(366.0 / 3.0 * 1.5, 30)
	t._gui_input(down)
	var up := down.duplicate() as InputEventMouseButton
	up.pressed = false
	t._gui_input(up)
	check("tabs: press + release picks the tab under the finger", t.selected == "dice" and got == ["rooms", "dice"], got)
	check("tabs: every tab has an icon (cat_ fallback)", t._tex.all(func(x) -> bool: return x != null))
	var bad_start := TabStrip.new(items, "missing", "folder")
	check("tabs: missing start key selects the first; folder look", bad_start.selected == "rooms" and bad_start.look == "folder")
	check("tabs: pane styles", TabStrip.pane_style("folder") is StyleBoxFlat and TabStrip.pane_style("gtabs") is StyleBoxEmpty)
	var seven := TabStrip.new([{key = "rooms", text = "Rooms"}, {key = "scenes", text = "Scenes"}, {key = "dice", text = "Dice"},
		{key = "avatars", text = "Avatars"}, {key = "frames", text = "Frames"}, {key = "plates", text = "Plates"},
		{key = "badges", text = "Badges"}], "dice")
	seven.size = Vector2(366, TabStrip.H_ON)
	check("tabs: 7 shop tabs fit 366 px without scrolling", not seven.scrolls())
	for n in [t, bad_start, seven]:
		n.free()

	# ---- LevelBadge ----
	var lb := LevelBadge.new(2, "md")
	check("level: size preset", lb.px == 36.0 and lb.custom_minimum_size == Vector2(36, 36))
	lb.set_level(12)
	check("level: set_level", lb.level == 12 and lb.number_size() >= UIKit.FS.small)
	var tiny := LevelBadge.new(150, 24)
	check("level: digits never under 12 px", tiny.number_size() >= UIKit.FS.small, tiny.number_size())
	var meter := Meter.new("night", 12)
	var row := LevelBadge.row(lb, meter)
	check("level: row overlaps the meter", row.get_theme_constant("separation") < 0 and meter.inset_left > 0.0)
	row.free()
	tiny.free()

	# ---- Toast ----
	var font := UIKit.font_body(900)
	var w := Toast.wrap_text("You need 2.5K more coins for this room.", font, 16, 150.0)
	check("toast: wraps long text", w.split("\n").size() >= 2 and w.replace("\n", " ") == "You need 2.5K more coins for this room.", w)
	check("toast: short text stays on one line", Toast.wrap_text("Saved", font, 16, 300.0) == "Saved")
	var root := (Engine.get_main_loop() as SceneTree).root
	var a := Toast.show(root, "first")
	var b := Toast.show(root, "second", null, 1.8, "good")
	check("toast: returns the pill", a is PanelContainer and b is PanelContainer)
	var layer := root.get_meta("toast_layer") as CanvasLayer
	check("toast: newest wins (one at a time)", layer != null and layer.get_child(0).get_meta("latest") == b)
	var loose := Node.new()
	check("toast: off-tree host returns null", Toast.show(loose, "x") == null)
	loose.free()
	check("toast: good kind has an icon", (b.get_child(0) as HBoxContainer).get_child_count() == 2)
	check("toast: no insets off mobile", OS.has_feature("mobile") or Toast.safe_insets(root.get_viewport()) == Vector2.ZERO)
	# the deferred attach runs a frame later: the card it sits under (or the layer) may be freed by then
	var lroot := layer.get_child(0) as Control if layer else null
	var gone_card := Control.new()
	gone_card.free()
	var p1 := PanelContainer.new()
	p1.set_meta("toast", true)
	if lroot:
		lroot.set_meta("latest", p1)
	Toast._attach(lroot, p1, gone_card, 0.5)
	check("toast: attach with a freed card (no bad-argument error)", not is_instance_valid(p1) or p1.get_parent() == lroot)
	var gone_root := Control.new()
	gone_root.free()
	var p2 := PanelContainer.new()
	Toast._attach(gone_root, p2, null, 0.5)
	check("toast: attach with a freed layer drops the pill", not is_instance_valid(p2))
	if lroot:
		lroot.set_meta("latest", b)               # the deferred attach of "second" still shows it

	# ---- UIKit.font_caps: a flat variation at the asked weight (a nested one rendered at the default weight) ----
	var caps := UIKit.font_caps(900, 1) as FontVariation
	var wght := TextServerManager.get_primary_interface().name_to_tag("wght")
	check("caps font: weight 900 on the Nunito file", caps != null and not (caps.base_font is FontVariation)
		and int(caps.variation_opentype.get(wght, 0)) == 900 and caps.spacing_glyph == 1)

	# ---- touch targets: every button preset is at least 48 px tall (xs / sm draw a smaller face inside) ----
	var short_btns := []
	for k in ["xs", "sm", "md", "lg"]:
		var kb := UIKit.btn("Claim", "honey", k)
		if kb.get_combined_minimum_size().y < UIKit.TAP:
			short_btns.append([k, kb.get_combined_minimum_size().y])
		kb.free()
	var bw := UIKit.button_with("Spin", UIKit.icon("coin", 20), "honey", "sm")
	if bw.get_combined_minimum_size().y < UIKit.TAP:
		short_btns.append(["button_with sm", bw.get_combined_minimum_size().y])
	bw.free()
	check("buttons: 48 px tap height for every size", short_btns.is_empty(), short_btns)

	# ---- one section-label style; caps only for eyebrows ----
	var cap := UIKit.caption("Your colour")
	var eb := UIKit.eyebrow("Ludo room")
	check("caption: sentence case, 14 px", cap.text == "Your colour" and cap.get_theme_font_size("font_size") == UIKit.FS.label, cap.text)
	check("eyebrow: caps", eb.text == "LUDO ROOM", eb.text)
	cap.free()
	eb.free()

	# ---- TabStrip.tap: selects and emits like a real tap ----
	var tt := TabStrip.new([{key = "rooms", text = "Rooms"}, {key = "dice", text = "Dice"}], "rooms")
	var got_tap := []
	tt.picked.connect(func(k): got_tap.append(k))
	tt.tap("dice")
	tt.tap("dice")
	check("tabs: tap selects + emits once", tt.selected == "dice" and got_tap == ["dice"], got_tap)
	tt.free()
