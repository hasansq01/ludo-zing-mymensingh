extends Control
## Dev preview of the phase 1 C-A components: TabStrip (gtabs / folder), Toast, CoinAmount, Meter, LevelBadge, on the
## cream card background and on the dark night lobby background. Saves screenshots, then quits:
##   godot --path . --resolution 390x844 res://dev/preview_components_a.tscn -- <out_dir>

var out := "/tmp"
var page: Control
var content: VBoxContainer
var _card: PanelContainer
var _bal: CoinAmount
var _xp_anim: Meter

const SHOP7 := [
	{key = "rooms", text = "Rooms", cat = "rooms"},
	{key = "scenes", text = "Scenes", cat = "scenes"},
	{key = "dice", text = "Dice", cat = "dice"},
	{key = "avatars", text = "Avatars", cat = "avatars"},
	{key = "frames", text = "Frames", cat = "frames"},
	{key = "plates", text = "Plates", cat = "plates"},
	{key = "badges", text = "Badges", cat = "badges"},
]


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size():
		out = args[0]
	theme = UIKit.theme()
	await _cream_page()
	await _night_page()
	await _long_labels_page()
	get_tree().quit()


func _new_page(bg: Color, night := false) -> void:
	if page:
		page.queue_free()
		await get_tree().process_frame
	page = Control.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(page)
	if night:
		var g := Gradient.new()
		g.set_color(0, Palette.PLUM_NIGHT.lightened(0.12))
		g.set_color(1, Palette.PLUM_NIGHT.darkened(0.35))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill_from = Vector2(0.5, 0)
		gt.fill_to = Vector2(0.5, 1)
		var tr := TextureRect.new()
		tr.texture = gt
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		page.add_child(tr)
	else:
		var r := ColorRect.new()
		r.color = bg
		r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		page.add_child(r)
	content = UIKit.vbox(UIKit.SPACE.sm)
	content.position = Vector2(12, 12)
	content.custom_minimum_size = Vector2(366, 0)
	content.size = Vector2(366, 0)
	page.add_child(content)


func _cap(t: String, night := false) -> void:
	var l := UIKit.caption(t, Palette.PEACH if night else Palette.CREMA)
	l.clip_text = true
	l.custom_minimum_size.x = 1
	content.add_child(l)


func _row(items: Array, gap := 10) -> HBoxContainer:
	var r := UIKit.hbox(gap)
	r.alignment = BoxContainer.ALIGNMENT_BEGIN
	for i in items:
		r.add_child(i)
	content.add_child(r)
	return r


func _shoot(name: String) -> void:
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [out, name]
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)


# ---------------------------------------------------------------------------------------------------------------------

func _cream_page() -> void:
	await _new_page(Palette.CARD)
	_cap("TabStrip gtabs: 4 tabs (icon beside label)")
	var four := TabStrip.new([
		{key = "rooms", text = "Rooms", cat = "rooms"}, {key = "scenes", text = "Scenes", cat = "scenes"},
		{key = "dice", text = "Dice", cat = "dice"}, {key = "coins", text = "Coins", cat = "coins"}], "rooms")
	content.add_child(four)
	_cap("gtabs: 7 tabs in 366 px (icon above label), count badge")
	var seven := TabStrip.new(SHOP7, "dice")
	seven.set_count("badges", 2)
	content.add_child(seven)
	_cap("gtabs: 2 tabs (Profile / Achievements)")
	var two := TabStrip.new([{key = "profile", text = "Profile", icon = "tab_profile", cat = "coins"},
		{key = "ach", text = "Achievements", icon = "ic_trophy", cat = "badges"}], "profile")
	two.set_count("ach", 3)
	content.add_child(two)
	_cap("TabStrip folder + pane_style(\"folder\")")
	var fold := TabStrip.new([{key = "profile", text = "Profile", icon = "tab_profile"},
		{key = "ach", text = "Achievements", icon = "ic_trophy"}], "profile", "folder")
	fold.set_count("ach", 2)
	var fv := UIKit.vbox(0)
	fv.add_child(fold)
	var pane := PanelContainer.new()
	pane.add_theme_stylebox_override("panel", TabStrip.pane_style("folder"))
	fold.bind_pane(pane)
	pane.add_child(UIKit.label("Pane content sits here.", UIKit.FS.label, Palette.SUB))
	fv.add_child(pane)
	var pm := PanelContainer.new()
	var pst := UIKit.box(Palette.PM, UIKit.R.lg)
	UIKit.pad(pst, 8)
	pm.add_theme_stylebox_override("panel", pst)
	pm.add_child(fv)
	content.add_child(pm)

	_cap("CoinAmount sizes xs / sm / md / lg / hero (plain)")
	_row([CoinAmount.new(950, "xs"), CoinAmount.new(1200, "sm"), CoinAmount.new(5300, "md"), CoinAmount.new(12500, "lg")], 12)
	_row([CoinAmount.new(250, "hero", "plain", "+"), CoinAmount.new(1250000, "lg", "chip")], 12)
	_cap("chip / price / full / gain prefix / colours")
	var need := CoinAmount.new(2500, "sm", "plain")
	need.set_color(Palette.DANGER)
	var gain := CoinAmount.new(200, "sm", "plain", "+")
	gain.set_color(Palette.TEAL_INK)
	_row([CoinAmount.new(5300, "md", "chip"), CoinAmount.new(5300, "sm", "chip"), CoinAmount.new(3000, "sm", "price"), CoinAmount.new(800, "xs", "price")], 8)
	var buy := UIKit.button_with("", CoinAmount.new(3000, "xs", "plain"), "gold", "xs")
	buy.custom_minimum_size.x = 84
	_row([CoinAmount.new(5300, "sm", "plain", "", true), gain, need, buy], 10)
	Toast.show(self, "Pastel Dream Room is yours!", null, 5.0, "good")
	await get_tree().create_timer(0.5).timeout
	await _shoot("comp_cream")
	await _new_page(Palette.CARD)

	_cap("Meter xp / track / teal at 0, 30%, 100%")
	for lk in ["xp", "track", "teal"]:
		var m0 := Meter.new(lk, 10)
		m0.set_value(0, 100)
		var m1 := Meter.new(lk, 10)
		m1.set_value(30, 100)
		var m2 := Meter.new(lk, 10)
		m2.set_value(100, 100)
		_row([m0, m1, m2], 10)
	_cap("Meter with numbers 18 / 22 px, LevelBadge.row")
	var n1 := Meter.new("xp", 18, true, "XP")
	n1.set_value(45, 150)
	content.add_child(LevelBadge.row(LevelBadge.new(2, "md"), n1))
	var n0 := Meter.new("xp", 22, true, "XP")
	n0.set_value(0, 100)
	content.add_child(LevelBadge.row(LevelBadge.new(1, "lg"), n0))
	var ach := Meter.new("teal", 18, true)
	ach.set_value(3, 10)
	var ach2 := Meter.new("teal", 18, true)
	ach2.set_value(1200, 5000)
	_row([ach, ach2], 10)
	_cap("LevelBadge xs / sm / md / lg / xl, 2-3 digits")
	_row([LevelBadge.new(1, "xs"), LevelBadge.new(2, "sm"), LevelBadge.new(7, "md"), LevelBadge.new(12, "lg"), LevelBadge.new(5, "xl"), LevelBadge.new(99, "sm"), LevelBadge.new(150, "md")], 10)
	await get_tree().process_frame
	await _shoot("comp_cream2")


func _night_page() -> void:
	await _new_page(Palette.PLUM_NIGHT, true)
	_cap("Night lobby: home top bar mock", true)
	# the cream profile capsule (web .h-bar .profile) with LevelBadge + night meter, and the night coin balance
	var bar := UIKit.hbox(UIKit.SPACE.sm)
	var cap := PanelContainer.new()
	var cst := UIKit.box(Color(Palette.CARD, 0.92), UIKit.R.md, UIKit.BW.line, Color.WHITE)
	UIKit.pad(cst, 8, 6)
	cap.add_theme_stylebox_override("panel", cst)
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cv := UIKit.vbox(2)
	cv.add_child(UIKit.label("You", UIKit.FS.label, Palette.INK, UIKit.font_body(900)))
	var hm := Meter.new("night", 12)
	hm.set_value(40, 150)
	cv.add_child(LevelBadge.row(LevelBadge.new(2, "xs"), hm))
	cap.add_child(cv)
	bar.add_child(cap)
	_bal = CoinAmount.new(1200, "lg", "night")
	bar.add_child(_bal)
	bar.add_child(UIKit.icon_button("ic_gear", "night", 48))
	content.add_child(bar)
	_cap("CoinAmount night sm / md / lg; plain on night (white)", true)
	var white := CoinAmount.new(5300, "lg", "plain")
	white.set_color(Color.WHITE)
	_row([CoinAmount.new(950, "sm", "night"), CoinAmount.new(5300, "md", "night"), CoinAmount.new(12500, "lg", "night"), white], 10)
	_row([CoinAmount.new(5300, "md", "chip"), CoinAmount.new(3000, "sm", "price")], 10)
	_cap("Meter night 0 / 30% / 100%, with numbers", true)
	var m0 := Meter.new("night", 12)
	m0.set_value(0, 100)
	var m1 := Meter.new("night", 12)
	m1.set_value(30, 100)
	var m2 := Meter.new("night", 12)
	m2.set_value(100, 100)
	_row([m0, m1, m2], 10)
	_xp_anim = Meter.new("night", 20, true, "XP")
	_xp_anim.set_value(10, 150)
	content.add_child(LevelBadge.row(LevelBadge.new(3, "md"), _xp_anim))
	var mx := Meter.new("xp", 20, true, "XP")
	mx.set_value(0, 100)
	content.add_child(LevelBadge.row(LevelBadge.new(1, "md"), mx))
	_cap("Level badges on night", true)
	_row([LevelBadge.new(1, "xs"), LevelBadge.new(2, "sm"), LevelBadge.new(7, "md"), LevelBadge.new(12, "lg")], 10)
	_cap("A card on the lobby: gtabs 5 + folder", true)
	_card = UIKit.panel("card")
	var v := UIKit.vbox(UIKit.SPACE.md)
	var five := TabStrip.new([{key = "avatars", text = "Avatars"}, {key = "chars", text = "Characters", cat = "chars"},
		{key = "frames", text = "Frames"}, {key = "plates", text = "Plates"}, {key = "badges", text = "Badges"}], "frames")
	v.add_child(five)
	var f := TabStrip.new([{key = "sound", text = "Sound", icon = "ic_sound"}, {key = "game", text = "Game", icon = "ic_gear"},
		{key = "rules", text = "Rules", icon = "ic_info"}], "game", "folder")
	var fv := UIKit.vbox(0)
	fv.add_child(f)
	var pane := PanelContainer.new()
	pane.add_theme_stylebox_override("panel", TabStrip.pane_style("folder"))
	f.bind_pane(pane)
	pane.custom_minimum_size.y = 40
	fv.add_child(pane)
	v.add_child(fv)
	_card.add_child(v)
	content.add_child(_card)
	await get_tree().process_frame
	await get_tree().process_frame
	# animations: count the balance up, slide the XP fill, pop the coins and the level
	_bal.tick = true
	_bal.set_amount(5300, true)
	_xp_anim.set_value(120, 150, true)
	Toast.show(self, "Not enough coins yet. Win a game to earn more.", _card, 5.0, "coin")
	await get_tree().create_timer(0.62).timeout
	_bal.flash()
	await get_tree().create_timer(0.6).timeout
	await _shoot("comp_night")


func _long_labels_page() -> void:
	await _new_page(Palette.CARD)
	_cap("gtabs: long labels scroll sideways (drag); selected scrolled into view")
	var long := TabStrip.new([
		{key = "rooms", text = "Rooms"}, {key = "scenes", text = "Scenes"}, {key = "dice", text = "Dice"},
		{key = "avatars", text = "Avatars"}, {key = "chars", text = "Characters"}, {key = "frames", text = "Frames"},
		{key = "plates", text = "Nameplates"}, {key = "badges", text = "Badges"}], "plates")
	content.add_child(long)
	_cap("gtabs at 300 px (7 tabs)")
	var narrow := TabStrip.new(SHOP7, "rooms")
	narrow.custom_minimum_size.x = 300
	narrow.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	content.add_child(narrow)
	_cap("gtabs 3 tabs; folder 3 tabs")
	content.add_child(TabStrip.new([{key = "rooms", text = "Rooms"}, {key = "scenes", text = "Scenes"}, {key = "dice", text = "Dice"}], "scenes"))
	var f := TabStrip.new([{key = "a", text = "Sound", icon = "ic_sound"}, {key = "b", text = "Game", icon = "ic_gear"},
		{key = "c", text = "House rules", icon = "ic_info"}], "c", "folder")
	content.add_child(f)
	_cap("Toast kinds (one at a time: this is 'bad'; info has no icon)")
	var card := UIKit.panel("card")
	card.custom_minimum_size = Vector2(366, 120)
	card.add_child(UIKit.paragraph("A sheet card: a toast with near = card sits just under it.", UIKit.FS.body, Palette.INK))
	content.add_child(card)
	await get_tree().process_frame
	await get_tree().process_frame
	Toast.show(self, "first one (replaced)", card)
	Toast.show(self, "You need 2.5K more coins for this room.", card, 5.0, "bad")
	await get_tree().create_timer(0.5).timeout
	await _shoot("comp_long")
	Toast.show(self, "Free coins in 3h 52m", null, 5.0)
	await get_tree().create_timer(0.5).timeout
	await _shoot("comp_info")
