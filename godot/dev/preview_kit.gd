extends Control
## Dev preview of the UI kit (phase 0 tokens and primitives): every button kind and size, pressed / disabled /
## legacy forms, the close buttons, segmented controls, tags, captions, badges, icon buttons, surfaces and the
## assets/ui icons, on a cream background. Saves page screenshots, then quits:
##   godot --path . --resolution 390x844 res://dev/preview_kit.tscn -- <out_dir>

const PAGE_H := 844.0
var out := "/tmp"
var content: VBoxContainer

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size():
		out = args[0]
	theme = UIKit.theme()
	var bg := ColorRect.new()
	bg.color = Palette.CARD
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	content = UIKit.vbox(UIKit.SPACE.md)
	content.position = Vector2(16, 16)
	content.custom_minimum_size = Vector2(358, 0)
	content.resized.connect(func(): if content.size.x > 358.5: push_warning("preview content too wide: %d" % content.size.x))
	add_child(content)
	_buttons()
	_others()
	_icons()
	_shoot()

func _section(t: String) -> void:
	content.add_child(UIKit.caption(t))

func _row(items: Array, gap := 8) -> HBoxContainer:
	var r := UIKit.hbox(gap)
	for i in items:
		r.add_child(i)
	content.add_child(r)
	return r

func _buttons() -> void:
	_section("Buttons: xs / sm / md per kind")
	for kind in ["honey", "gold", "teal", "red", "ghost", "white", "off"]:
		var md := UIKit.btn(kind.capitalize(), kind, "md")
		md.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_row([UIKit.btn("Buy", kind, "xs"), UIKit.btn("Retry", kind, "sm"), md])
	_section("lg (the one forward action)")
	var lg := UIKit.btn("Start game", "honey", "lg")
	content.add_child(lg)
	var two := [UIKit.btn("Home", "ghost", "lg"), UIKit.btn("Play again", "teal", "lg")]
	for b: Button in two:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row(two, UIKit.SPACE.md)
	_section("Pressed, disabled, legacy (22 / 56), with coin")
	var held := UIKit.btn("Held", "honey", "md")
	held.toggle_mode = true
	held.button_pressed = true
	var dis := UIKit.btn("Need 2.5K", "honey", "md")
	dis.disabled = true
	var dis2 := UIKit.btn("Claimed", "teal", "md")
	dis2.disabled = true
	_row([held, dis, dis2])
	var legacy := UIKit.button("Legacy", "honey", 22)
	legacy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var coin := UIKit.button_with(Fmt.coins(1200), UIKit.icon("coin", 22), "gold", "md")
	coin.custom_minimum_size.x = 120
	_row([legacy, coin])
	var lobby := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Palette.PLUM_NIGHT
	st.set_corner_radius_all(UIKit.R.lg)
	UIKit.pad(st, 10)
	lobby.add_theme_stylebox_override("panel", st)
	var mr := UIKit.hbox(UIKit.SPACE.md)
	mr.add_child(UIKit.mode_button("vs Computer", "honey", "robot"))
	mr.add_child(UIKit.mode_button("Pass & Play", "teal", "two_pawns"))
	lobby.add_child(mr)
	content.add_child(lobby)

func _others() -> void:
	_section("Close buttons: red 48 / held / soft")
	var card := UIKit.panel("card")
	card.custom_minimum_size = Vector2(358, 96)
	var corner := Control.new()
	card.add_child(corner)
	var x1 := UIKit.close_button()
	x1.position = Vector2(30, 10)
	var x2 := UIKit.close_button()
	x2.position = Vector2(110, 10)
	x2.toggle_mode = true
	x2.button_pressed = true
	var x3 := UIKit.close_button("soft", 44)
	x3.position = Vector2(190, 12)
	for x in [x1, x2, x3]:
		corner.add_child(x)
	content.add_child(card)
	_section("Segmented: md / sm / legacy 17")
	content.add_child(UIKit.segmented([[false, "Individual"], [true, "Teams (2 v 2)"]], false, func(_v): pass))
	content.add_child(UIKit.segmented([[0, "Slow"], [1, "Normal"], [2, "Fast"]], 2, func(_v): pass, "sm"))
	content.add_child(UIKit.segmented([[1, "1"], [2, "2"], [3, "3"]], 2, func(_v): pass, 17))
	_section("Tags, caps, badge")
	var tags := []
	for look in ["white", "gold", "teal", "ink", "red", "honey"]:
		tags.append(UIKit.tag({white = "Owned", gold = "In use", teal = "Free", ink = "CPU", red = "New", honey = "x2"}[look], look))
	var badge_host := Control.new()
	badge_host.custom_minimum_size = Vector2(26, 24)
	badge_host.add_child(UIKit.notify_badge("3", false))
	tags.append(badge_host)
	_row(tags, 6).add_theme_color_override("font_color", Palette.INK)
	var grey := ColorRect.new()
	grey.color = Palette.MUTED
	grey.custom_minimum_size = Vector2(1, 1)
	_row([UIKit.caps_label("Claimed", Palette.TEAL_INK), UIKit.caps_label("Locked", Palette.SUB), UIKit.label("Label 14", UIKit.FS.label), UIKit.label("Small 12", UIKit.FS.small, Palette.MUTED)], 12)
	content.add_child(UIKit.bullet_row("A bullet line wraps under itself when it is too long for one row of the card."))
	_section("Icon buttons: glass / night")
	var night := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Palette.PLUM_NIGHT
	st.set_corner_radius_all(UIKit.R.md)
	UIKit.pad(st, 6)
	night.add_theme_stylebox_override("panel", st)
	var nr := UIKit.hbox(8)
	nr.add_child(UIKit.icon_button("ic_gear", "night", 56))
	night.add_child(nr)
	_row([UIKit.icon_button("ic_pause"), UIKit.icon_button("ic_gear"), UIKit.icon_button("res://assets/ui/ic_back.svg"), night])
	_section("Surfaces: row / tile / pane / item / item on")
	var surf := []
	for k in [["row", false], ["tile", false], ["pane", false], ["item", false], ["item", true]]:
		var p := UIKit.panel(k[0], UIKit.label(k[0], 12), k[1])
		surf.append(p)
	_row(surf, 6)

func _icons() -> void:
	_section("Icons (assets/ui)")
	var g := UIKit.grid(8, 6)
	var names := []
	for f in DirAccess.get_files_at("res://assets/ui"):
		if (f.begins_with("ic_") or f.begins_with("sym_")) and f.ends_with(".svg"):
			names.append(f.get_basename())
	names.append_array(["coin", "lock"])
	for n in names:
		var bgc := Palette.RED if n in ["ic_close", "ic_check"] else Palette.SURFACE_2
		var cell := PanelContainer.new()
		var st := UIKit.box(bgc, 8)
		UIKit.pad(st, 4)
		cell.add_theme_stylebox_override("panel", st)
		cell.add_child(UIKit.icon(n, 32))
		g.add_child(cell)
	content.add_child(g)
	var tiny := UIKit.hbox(6)
	for n in ["ic_gear", "ic_star", "ic_crown", "ic_lock", "ic_info", "ic_trophy", "ic_eye", "ic_hand"]:
		tiny.add_child(UIKit.icon(n, 18))
	for c in 4:
		tiny.add_child(UIKit.symbol(c, 18))
	content.add_child(tiny)

func _shoot() -> void:
	for i in 3:
		await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout
	var total := content.get_combined_minimum_size().y + 32
	var pages := ceili(total / PAGE_H)
	for p in pages:
		content.position.y = 16 - p * (PAGE_H - 40)
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := "%s/kit_%d.png" % [out, p + 1]
		get_viewport().get_texture().get_image().save_png(path)
		print("saved ", path)
	get_tree().quit()
