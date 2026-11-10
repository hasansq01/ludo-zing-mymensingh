class_name UpdateSheet
extends Sheet
## The update sheets (AppUpdate, server/PROTOCOL.md "App versions"), one game-look popup for both (the dark café card,
## the round red X in its corner). On top, the game's own launcher icon (assets/icon, unchanged) in a gold-rimmed
## tile with a badge: a green up-arrow on the offer, a red "!" when an update is required. Under it the title in big
## outlined gold (it wraps rather than cut, clear of the X), then:
## - "Update required" (required = true): the blocking screen that stands in for online play (quick match, friend
##   rooms, joining by invite) when this version is below the server's minimum (AppUpdate.gate). An ONLINE PLAY chip
##   with a lock says what is blocked, the reason in cream, the big gold UPDATE (with a download mark) runs Play's
##   immediate update (the store page where Play can't). The X goes back to Home, where Vs Computer and Pass & Play
##   still work, and a wood tile with their icons says so.
## - "New version available" (required = false): the soft offer on a quiet Home. Gold UPDATE runs Play's full-screen
##   update (AppUpdate.accept_offer; the store page where Play can't); cream LATER puts that version off for two days
##   (decline_offer), and so does closing it (the X, Back: AppUpdate's `closed` hook). No version numbers: AppUpdate
##   knows only version codes (Play's / the server's), not the new version's name.
##
##   UpdateSheet.new(app_update).open(layer)           # required
##   UpdateSheet.new(app_update, false).open(layer)    # the offer

const ICON := "res://assets/icon/icon_512.png"   ## the launcher icon (brand art: shown as it is)
const HERO := 104.0                               ## the icon tile's size
## The offer's line: what Update leads to is Play's own update screen, or the store page where Play can't run it.
const OFFER_TEXT := "Get the latest fixes and features. The update comes from Google Play."  # l10n

var update_button: Button
var later_button: Button                 ## the offer only
var note_label: Label
var required := true
var _u: AppUpdate


func _init(u: AppUpdate = null, required_ := true) -> void:
	_u = u
	required = required_
	super("", UIKit.W.form, true, Sheet.LOOK_GAME)
	dismissable = true
	body.add_theme_constant_override("separation", 14)
	# the header: the icon tile, centred (the X keeps its corner)
	header.custom_minimum_size.y = HERO + 8.0
	var hero := Hero.new(required)
	hero.name = "Hero"
	header.add_child(hero)
	hero.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	hero.offset_left = -HERO / 2.0
	hero.offset_right = HERO / 2.0
	hero.offset_top = 4.0
	hero.offset_bottom = 4.0 + HERO
	# the title, the full card wide under the icon: it wraps instead of being cut
	title_label = GameUI.outlined(L10n.t("Update required") if required else L10n.t("New version available"), 28, GameUI.GOLD, 3,
		HORIZONTAL_ALIGNMENT_CENTER)
	title_label.name = "Title"
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.custom_minimum_size.x = 60
	body.add_child(title_label)
	if required:
		var chip := _chip(tr("Online play"))
		chip.name = "Kicker"
		body.add_child(chip)
	var intro := GameUI.text(tr("This version of Ludo Zing is too old to play online. Update to play with friends and in quick match.")
		if required else tr(OFFER_TEXT), UIKit.FS.body_l, GameUI.SUB, HORIZONTAL_ALIGNMENT_CENTER)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size.x = 60
	intro.name = "Intro"
	body.add_child(intro)
	update_button = GameUI.button(tr("Update"), "gold", "lg", "res://assets/ui/ic_download.svg")
	update_button.name = "Update"
	GameUI.fit_button_text(update_button, 16)
	update_button.pressed.connect(func() -> void:
		if _u == null:
			return
		if required:
			_u.update_now()
		else:
			_u.accept_offer())                   # (it closes this sheet as the state moves on)
	body.add_child(UIKit.margin(update_button, 0, 4, 0, 0))
	if required:
		note_label = GameUI.text(tr("Playing against the computer or passing the phone around still works."), 14,
			GameUI.SUB)
		note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note_label.custom_minimum_size.x = 60
		note_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		note_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		note_label.name = "Note"
		var row := UIKit.hbox(10)
		var icons := UIKit.hbox(2)
		icons.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		for ic in ["res://assets/ui/home/hi_cpu.svg", "res://assets/ui/home/hi_pass_play.svg"]:
			icons.add_child(UIKit.icon(ic, 30))
		row.add_child(icons)
		row.add_child(note_label)
		var tile := GameUI.tile(16.0, 12.0)
		tile.name = "OfflineTile"
		tile.add_child(row)
		body.add_child(tile)
	else:
		later_button = GameUI.button(tr("Later"), "cream", "md")
		later_button.name = "Later"
		GameUI.fit_button_text(later_button, 14)
		later_button.pressed.connect(func() -> void:
			if _u != null:
				_u.decline_offer()               # at once (the X / Back: AppUpdate's `closed` hook, after the fade)
			close())
		body.add_child(later_button)
	fit()


## A dark pill with a gold rim, a lock and the text in caps (what the update blocks: online play).
static func _chip(t: String) -> Control:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := UIKit.box(Palette.GL_CHIP_BG, 16, 2, Palette.GL_CHIP_RIM)
	st.content_margin_left = 10; st.content_margin_right = 14; st.content_margin_top = 4; st.content_margin_bottom = 5
	p.add_theme_stylebox_override("panel", st)
	var h := UIKit.hbox(6)
	h.add_child(UIKit.icon("ic_lock", 20))
	var l := UIKit.label(t.to_upper(), 14, Palette.GL_CREAM_RIM, UIKit.font_body(900))
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	p.add_child(h)
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return p


## The launcher icon in a gold-rimmed tile with a 3D lip, and its badge on the bottom-right corner (offer: a green disc
## with a white up-arrow; required: a red disc with a white "!").
class Hero extends Control:
	const R := 24.0
	var required := true
	static var _rim: StyleBoxFlat
	static var _lip: StyleBoxFlat

	func _init(required_: bool) -> void:
		required = required_
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(UpdateSheet.HERO, UpdateSheet.HERO)
		if _rim == null:
			_rim = UIKit.box(Palette.GL_CHIP_RIM, int(R), 0, Color.TRANSPARENT, 12, Color(0, 0, 0, 0.45))
			_rim.shadow_offset = Vector2(0, 6)
			_lip = UIKit.box(Palette.GL_GOLD_LIP2, int(R))
		# the icon, clipped to the tile's rounded square (the mask is the rounded panel itself)
		var mask := Panel.new()
		mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mask.add_theme_stylebox_override("panel", UIKit.box(Color.WHITE, int(R - 4.0)))
		mask.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
		add_child(mask)
		mask.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mask.offset_left = 4.0; mask.offset_top = 4.0; mask.offset_right = -4.0; mask.offset_bottom = -8.0
		var t := TextureRect.new()
		t.texture = load(UpdateSheet.ICON)
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_SCALE
		t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mask.add_child(t)
		t.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var badge := Badge.new(required)
		add_child(badge)
		badge.position = Vector2(UpdateSheet.HERO - Badge.D + 10.0, UpdateSheet.HERO - Badge.D + 4.0)

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(_lip, r)
		draw_style_box(_rim, Rect2(r.position, r.size - Vector2(0, 4.0)))


class Badge extends Control:
	const D := 40.0
	var required := true

	func _init(required_: bool) -> void:
		required = required_
		size = Vector2(D, D)
		custom_minimum_size = size
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := Vector2(D / 2.0, D / 2.0)
		var r := D / 2.0
		var face := Palette.GL_BTN_RED_LO if required else Palette.GL_GREEN_LO
		var lip := Palette.GL_RED_LIP if required else Palette.GL_GREEN_LIP
		draw_circle(c + Vector2(0, 3), r, Color(0, 0, 0, 0.35), true, -1.0, true)
		draw_circle(c, r, Palette.GL_CREAM_HI, true, -1.0, true)            # the cream ring
		draw_circle(c + Vector2(0, 1), r - 3.0, lip, true, -1.0, true)
		draw_circle(c - Vector2(0, 1), r - 4.0, face, true, -1.0, true)
		var w := Color.WHITE
		if required:                                                       # "!"
			draw_line(c + Vector2(0, -9), c + Vector2(0, 3), w, 5.0, true)
			draw_circle(c + Vector2(0, 9), 2.8, w, true, -1.0, true)
		else:                                                              # an up-arrow
			draw_line(c + Vector2(0, 9), c + Vector2(0, -8), w, 5.0, true)
			draw_polyline(PackedVector2Array([c + Vector2(-7.5, -1), c + Vector2(0, -8.5), c + Vector2(7.5, -1)]), w, 5.0, true)
