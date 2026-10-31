class_name SettingsSheet
extends Sheet
## Settings (index.html #settingsSheet; PM look with the "Settings" ribbon and the single close X). Sections:
##   Language       Auto (<the phone's>) / English / বাংলা (Save.prefs.lang; Main.set_language switches and rebuilds
##                  the screen, this sheet included)
##   Sound & vibration  Sound on / off, Music / Effects volume ("70%"), Vibration on / off (no master slider: Save
##                      folded the old master level into the two channels once, Save.prefs.vol.master stays 100)
##   Game           Game speed (Relaxed / Fast), Graphics (Auto (<detected>) / Low / Medium / High: Save.prefs.quality,
##                  applied at once through Quality.set_tier; a note says when part of it waits for the next launch)
##   Camera view    Ludo (3D / Top), Snakes & Ladders (3D / Top)
##   House rules    Ask before pairing (pair_ask), Snakes & Ladders: Need a 1 to start (sl_need_one)
##   Notifications  a master switch, on only while the player wants them AND the phone allows them (turning it on asks
##                  the phone, or opens its settings once it can't ask any more), and Rewards, Reminders, Game alerts,
##                  News & offers (Save.prefs notif, notif_rewards, notif_reminders, notif_game, notif_offers); a note
##                  under the master says what a tap will do while the phone doesn't allow them
##   Accessibility  Colour-blind symbols (colorblind), Reduce motion (reduce_motion)
##   Help           How to play, Credits, Privacy policy, Delete my account, Support (URLS)
##   Reset progress (confirm first), then the version line and the Support ID (the player ID; nothing else uses it
##   offline, so it lives here instead of on the Profile).
## Every change is written to Save.prefs at once (Save.save() debounces the file write), sound changes reach the
## Sound autoload immediately, and prefs_changed fires so the game can re-read speed / camera / rules.
## Rows: label left (Nunito 800 16, an optional 12 px note under it), control right, 56 px tall, grouped in
## UIKit.surface("row") cards under section labels (UIKit.caption). Switches are 48 px targets; a tap on a switch row's
## label toggles it too.

signal prefs_changed
signal language_picked(pref: String)     ## "auto" | "en" | "bn" (main switches the language and reopens Settings)

const VERSION_LINE := "Ludo Zing Mymensingh · v%s · Flipfold Studio"
## Web pages for the Help rows. A row shows only when its URL is set (no dead "Coming soon" rows).
const URLS := {
	privacy = "https://ludo-zing-rooms.flipfold.workers.dev/privacy",
	delete = "https://ludo-zing-rooms.flipfold.workers.dev/delete-account",
	support = "mailto:Hello@oclasp.com?subject=Ludo%20Zing",
}
const ROW_H := 56.0
const SEG_W := 132.0
const SEG_W_SHORT := 112.0              ## two short choices (3D / Top): the long row labels keep one line
const TAP_SLOP := 12.0

var _width := 360.0
var _list: VBoxContainer
var _switch: Switch                      # the Sound switch (previews flip it)
var _vol_lines: Array[Control] = []
var _gfx_note: Label                     # Graphics: "... on next launch" when the pick needs one
var _notif_note: Label                   # Notifications: what a tap does while the phone doesn't allow them
var _notif_master: Switch
var _notif_lines: Array[Control] = []    # the four kinds (dimmed while the master switch is off)


func _init(width: float = UIKit.W.form) -> void:
	super("Settings", width, true, LOOK_PM)
	_width = width
	_list = add_scroll_body(UIKit.SPACE.sm)
	_build()


func _build() -> void:
	for c in _list.get_children():
		c.queue_free()
	_vol_lines.clear()
	_notif_lines.clear()
	var vol: Dictionary = Save.prefs.get("vol", {})
	var sound_on := bool(Save.prefs.get("sound", true))

	# --- Account (only where there is one): Guest / the Google name, opens the Profile
	var acc := Account.instance()
	if acc != null and acc.enabled:
		_caption("Account")
		_group().add_child(_account_line(acc))

	# --- Language
	_caption("Language")
	_group().add_child(_language_line())

	# --- Sound
	_caption("Sound & vibration")
	var snd := _group()
	_switch = Switch.new(sound_on)
	_switch.toggled.connect(_on_sound)
	snd.add_child(_line("Sound", "", _switch, _switch))
	for v: Array in [["music", "Music", Sound.DEFAULT_MUSIC], ["sfx", "Effects", Sound.DEFAULT_EFFECTS]]:
		var line := _vol_line(v[0], v[1], int(vol.get(v[0], v[2])))
		_vol_lines.append(line)
		snd.add_child(_divider())
		snd.add_child(line)
	snd.add_child(_divider())
	var vib := Switch.new(bool(Save.prefs.get("vibrate", true)))
	vib.toggled.connect(_on_vibrate)
	snd.add_child(_line("Vibration", "", vib, vib))
	_dim_volumes(sound_on)

	# --- Game
	_caption("Game")
	var g := _group()
	g.add_child(_line("Game speed", "", _seg([[1.0, "Relaxed"], [0.55, "Fast"]], float(Save.prefs.get("speed", 1.0)),
			func(v): _set_pref("speed", v))))
	g.add_child(_divider())
	g.add_child(_graphics_line())

	# --- Camera view (one block, one row per game)
	_caption("Camera view")
	var cam := _group()
	cam.add_child(_line("Ludo", "", _seg([["3d", "3D"], ["top", "Top"]], str(Save.prefs.get("cam", "top")),
			func(v): _set_pref("cam", v), SEG_W_SHORT)))
	cam.add_child(_divider())
	cam.add_child(_line("Snakes & Ladders", "", _seg([["3d", "3D"], ["top", "Top"]], str(Save.prefs.get("sl_cam", "top")),
			func(v): _set_pref("sl_cam", v), SEG_W_SHORT)))

	# --- House rules
	_caption("House rules")
	var h := _group()
	h.add_child(_switch_line("Ask before pairing", "Choose each time your pawns could pair.", "pair_ask"))
	h.add_child(_divider())
	h.add_child(_switch_line("Need a 1 to start", "Snakes & Ladders: only a 1 enters.", "sl_need_one"))

	# --- Notifications (the master switch, then what to be told about)
	_caption("Notifications")
	var nt := _group()
	var master := Switch.new(_notif_shown())
	_notif_master = master
	master.toggled.connect(_on_notif)
	var master_line := _line("Notifications", " ", master, master)
	_notif_note = master_line.get_child(0).get_child(0).get_child(1) as Label
	nt.add_child(master_line)
	for k: Array in [["notif_rewards", "Rewards", "Daily reward, free spin and free coins."],
			["notif_reminders", "Reminders", "A nudge when you have been away."],
			["notif_game", "Game alerts", "Your turn and friends joining a room."],
			["notif_offers", "News & offers", "Gifts and updates from Ludo Zing."]]:
		nt.add_child(_divider())
		var line := _switch_line(k[1], k[2], k[0])
		_notif_lines.append(line)
		nt.add_child(line)
	_refresh_notif()
	var notifs := Notifications.instance()
	if notifs != null and not notifs.permission_changed.is_connected(_refresh_notif):
		notifs.permission_changed.connect(_refresh_notif)

	# --- Accessibility
	_caption("Accessibility")
	var a := _group()
	a.add_child(_switch_line("Colour-blind symbols", "Shapes on pawns and players.", "colorblind"))
	a.add_child(_divider())
	a.add_child(_switch_line("Reduce motion", "Fewer animations, no shaking.", "reduce_motion"))

	# --- Help
	_caption("Help")
	var hp := _group()
	hp.add_child(_link_line("How to play", _open_howto))
	hp.add_child(_divider())
	hp.add_child(_link_line("Credits", _open_credits))
	for k: Array in [["privacy", "Privacy policy"], ["delete", "Delete my account"], ["support", "Support"]]:
		var url := str(URLS.get(k[0], ""))
		if url != "":
			hp.add_child(_divider())
			hp.add_child(_link_line(k[1], func(): OS.shell_open(url)))
	# Privacy choices (ads consent): only where the consent form says the player can change them
	var ad := Ads.instance()
	if ad != null and ad.privacy_options_required():
		hp.add_child(_divider())
		var pc := _link_line("Privacy choices", func(): ad.show_privacy_options())
		pc.name = "PrivacyChoices"
		hp.add_child(pc)

	# --- Reset progress
	var gap := Control.new()
	gap.custom_minimum_size.y = UIKit.SPACE.sm
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list.add_child(gap)
	var rs := _group()
	rs.add_child(_link_line("Reset progress", _confirm_reset, true))

	var ver := str(ProjectSettings.get_setting("application/config/version", ""))
	var foot := UIKit.label(VERSION_LINE % (ver if ver != "" else "0.1.0"), UIKit.FS.small, Palette.SUB, UIKit.font_body(800), HORIZONTAL_ALIGNMENT_CENTER)
	foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var id := str(Save.profile.get("id", ""))
	if id != "":
		foot.text += "\nSupport ID " + id
	_list.add_child(UIKit.margin(foot, 0, UIKit.SPACE.xs, 0, UIKit.SPACE.xs))


# ---------- pieces ----------

## A section label above a group (UIKit.caption, the one section-label style).
func _caption(text: String) -> void:
	var l := UIKit.caption(text)
	l.name = "Section"
	_list.add_child(UIKit.margin(l, UIKit.SPACE.xs, UIKit.SPACE.sm if _list.get_child_count() > 0 else 0, 0, 0))

## A row card (UIKit.surface("row")) holding lines; returns the lines' column.
func _group() -> VBoxContainer:
	var st := UIKit.surface("row").duplicate() as StyleBoxFlat
	st.content_margin_top = 0
	st.content_margin_bottom = UIKit.LIP.md - UIKit.BW.line
	st.content_margin_left = 14
	st.content_margin_right = 10
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", st)
	var col := UIKit.vbox(0)
	p.add_child(col)
	_list.add_child(p)
	return col

func _divider() -> ColorRect:
	var d := ColorRect.new()
	d.color = Palette.ROW_EDGE
	d.custom_minimum_size = Vector2(0, 2)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return d

## Label (and an optional note under it) on the left, `control` on the right, ROW_H tall. toggle: a Switch that a tap
## on the label side also flips.
func _line(text: String, note: String, control: Control, toggle: Switch = null) -> Control:
	var row := Row.new()
	row.custom_minimum_size.y = ROW_H
	var h := UIKit.hbox(UIKit.SPACE.md)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(h)
	h.add_child(_label_box(text, note))
	if control:
		control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(control)
	if toggle:
		row.tapped.connect(func(): toggle.button_pressed = not toggle.button_pressed)
	return row

func _label_box(text: String, note: String, color := Palette.INK) -> VBoxContainer:
	var v := UIKit.vbox(1)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := UIKit.label(text, UIKit.FS.body_l, color, UIKit.font_body(800))
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(t)
	if note != "":
		var s := UIKit.paragraph(note, UIKit.FS.small, Palette.SUB)
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(s)
	return v

## The Account row: "Guest" or the Google name with its state under it; a tap opens the Profile, where signing in lives.
func _account_line(acc: Account) -> Control:
	var row := Row.new()
	row.name = "AccountLine"
	row.custom_minimum_size.y = ROW_H
	row.pressable = true
	var h := UIKit.hbox(UIKit.SPACE.md)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(h)
	var title := "Guest"
	var note := "Your progress is saved on our server."
	if not acc.is_guest():
		title = acc.google_name() if acc.google_name() != "" else "Google Play Games"
		note = "Signed in with Google Play Games"
	elif not acc.has_session():
		title = "Guest · offline"
		note = "Your progress will sync when you’re back online."
	h.add_child(_label_box(title, note))
	if not acc.is_guest():
		var ok := UIKit.hbox(UIKit.SPACE.xs)
		ok.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ok.add_child(UIKit.glyph("ic_check", 16, Palette.TEAL_INK))
		var sl := UIKit.caps_label("Synced", Palette.TEAL_INK)
		sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ok.add_child(sl)
		h.add_child(ok)
	var chev := UIKit.icon("ic_back", 18)
	chev.flip_h = true
	chev.modulate = Color(1, 1, 1, 0.7)
	chev.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(UIKit.margin(chev, 0, 0, 4, 0))
	row.tapped.connect(func():
		UIKit.press_fx()
		var main := get_tree().root.get_node_or_null("Main") if is_inside_tree() else null
		if main and main.has_method("_on_tab"):
			main.call("_on_tab", "profile"))
	return row

## A switch row for a boolean pref.
func _switch_line(text: String, note: String, key: String) -> Control:
	var sw := Switch.new(bool(Save.prefs.get(key, false)))
	sw.toggled.connect(func(on: bool): _set_pref(key, on))
	return _line(text, note, sw, sw)

## The master switch as shown: on only while the player wants notifications and the phone allows them ("unsupported":
## desktop, the player's choice alone).
static func _notif_shown() -> bool:
	return bool(Save.prefs.get("notif", true)) and Notifications.permission() in ["granted", "unsupported"]

## The master switch follows the phone (a dialog answered, settings changed while away), the note under it says what a
## tap will do while the phone doesn't allow them, and the kinds dim while it is off.
func _refresh_notif(_state: Variant = null) -> void:
	var on := _notif_shown()
	if _notif_master != null and _notif_master.button_pressed != on:
		_notif_master.set_pressed_no_signal(on)
		_notif_master._set_t(1.0 if on else 0.0)
	if _notif_note != null:
		match Notifications.permission():
			"ask": _notif_note.text = "Tap to allow notifications on this phone."
			"denied": _notif_note.text = "Off in your phone settings. Tap to open them."
			_: _notif_note.text = ""
		_notif_note.visible = _notif_note.text != ""
	for l in _notif_lines:
		l.modulate.a = 1.0 if on else 0.4

## On: the player wants them, and the phone is asked (the system dialog) or, when it can't ask any more, its settings
## open; the switch shows the phone's answer when it comes. Off: the player's choice.
func _on_notif(on: bool) -> void:
	Save.prefs.notif = on
	Save.save()
	var notifs := Notifications.instance()
	if on and notifs != null:
		match Notifications.permission():
			"ask": notifs.ask_permission()
			"denied": notifs.open_settings()
	_refresh_notif()
	prefs_changed.emit()

## A tappable row with a chevron (Help) or a red text row (danger).
func _link_line(text: String, on_tap: Callable, danger := false) -> Control:
	var row := Row.new()
	row.custom_minimum_size.y = ROW_H
	row.pressable = true
	var h := UIKit.hbox(UIKit.SPACE.md)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(h)
	if danger:
		var ic := UIKit.glyph("ic_reset", 22, Palette.DANGER)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(ic)
	h.add_child(_label_box(text, "", Palette.DANGER if danger else Palette.INK))
	if not danger:
		var chev := UIKit.icon("ic_back", 18)
		chev.flip_h = true
		chev.modulate = Color(1, 1, 1, 0.7)
		chev.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(UIKit.margin(chev, 0, 0, 4, 0))
	row.tapped.connect(func():
		UIKit.press_fx()
		on_tap.call())
	return row

## Graphics: the label (and the launch note under it) over a full-width Auto / Low / Medium / High choice; Auto names
## the tier this phone gets (Quality.detected()).
func _graphics_line() -> Control:
	var row := Row.new()
	row.name = "Graphics"
	row.custom_minimum_size.y = ROW_H
	var v := UIKit.vbox(UIKit.SPACE.xs)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(v)
	var box := _label_box("Graphics", " ")
	_gfx_note = box.get_child(1) as Label
	v.add_child(box)
	var opts := [["auto", "Auto (%s)" % Quality.detected().capitalize()], ["low", "Low"], ["medium", "Medium"], ["high", "High"]]
	var seg := UIKit.segmented(opts, Quality.saved_pref(), _on_quality, "sm")
	seg.name = "QualitySeg"
	seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIKit.fit_segmented(seg)                      # the four labels share one size; "Auto (Medium)" gets the room it needs
	v.add_child(seg)
	_gfx_hint(Quality.saved_pref())
	return row

## Language: Auto (the phone's language, named in itself) / English / বাংলা, the full row wide. Each language is
## named in its own script, so it can be found whatever the interface shows now.
func _language_line() -> Control:
	var row := Row.new()
	row.name = "Language"
	row.custom_minimum_size.y = ROW_H
	var opts := [["auto", "Auto (%s)" % L10n.NATIVE[L10n.phone()]], ["en", L10n.NATIVE.en], ["bn", L10n.NATIVE.bn]]
	var seg := UIKit.segmented(opts, str(Save.prefs.get("lang", "auto")), _on_language, "sm")
	seg.name = "LanguageSeg"
	seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UIKit.fit_segmented(seg)
	row.add_child(seg)
	return row

## Main switches the language and opens Settings again; on its own (previews) the sheet switches and rebuilds itself.
func _on_language(v: Variant) -> void:
	if language_picked.get_connections().size():
		language_picked.emit(str(v))
		return
	Save.prefs.lang = str(v)
	Save.save()
	L10n.apply(v)
	_build()

## The launch note under Graphics: only when the pick changes something read at startup (Quality.needs_restart).
func _gfx_hint(t: String) -> void:
	if _gfx_note == null:
		return
	_gfx_note.text = "Texture detail applies on next launch." if Quality.needs_restart(t) else ""
	_gfx_note.visible = _gfx_note.text != ""

func _on_quality(t: Variant) -> void:
	Quality.set_tier(str(t))                 # saves Save.prefs.quality, re-applies the main view and its SubViewports
	_gfx_hint(str(t))
	prefs_changed.emit()

## Two compact choices (UIKit.segmented "sm"), right-aligned.
func _seg(options: Array, selected: Variant, on_pick: Callable, width := SEG_W) -> Control:
	var seg := UIKit.segmented(options, selected, on_pick, "sm")
	seg.custom_minimum_size.x = width
	seg.size_flags_horizontal = Control.SIZE_SHRINK_END
	return seg

## Label, a 0-100 slider and its value as a percent ("70%").
func _vol_line(key: String, text: String, value: int) -> Control:
	var row := Row.new()
	row.custom_minimum_size.y = ROW_H - 4.0
	var h := UIKit.hbox(UIKit.SPACE.md)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(h)
	var l := UIKit.label(text, UIKit.FS.body_l, Palette.INK, UIKit.font_body(800))
	l.custom_minimum_size = Vector2(66, 0)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	var s := VolSlider.new()
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(s)
	var out := UIKit.label(Fmt.pct(value / 100.0), UIKit.FS.label, Palette.SUB, UIKit.font_body(900, true), HORIZONTAL_ALIGNMENT_RIGHT)
	out.custom_minimum_size = Vector2(44, 0)
	out.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(out)
	s.value_changed.connect(func(v: float):
		out.text = Fmt.pct(v / 100.0)
		_set_volume(key, int(v)))
	if key == "sfx":
		s.drag_ended.connect(func(_changed: bool): Sound.sfx("select"))   # hear the new effects level
	return row


# ---------- changes ----------

func _on_sound(on: bool) -> void:
	Save.prefs.sound = on
	Save.save()
	Sound.set_enabled(on)
	_dim_volumes(on)
	if on:
		Sound.sfx("select")
	prefs_changed.emit()

func _on_vibrate(on: bool) -> void:
	Save.prefs.vibrate = on
	Save.save()
	if on:
		Haptics.light()                      # feel it once
	prefs_changed.emit()

func _set_volume(key: String, v: int) -> void:
	var vol: Dictionary = Save.prefs.get("vol", {})
	vol[key] = v
	Save.prefs.vol = vol
	Save.save()
	Sound.set_volumes(int(vol.get("master", 100)), int(vol.get("music", Sound.DEFAULT_MUSIC)), int(vol.get("sfx", Sound.DEFAULT_EFFECTS)))
	prefs_changed.emit()

func _set_pref(key: String, v: Variant) -> void:
	Save.prefs[key] = v
	Save.save()
	prefs_changed.emit()

func _dim_volumes(on: bool) -> void:
	for l in _vol_lines:
		l.modulate.a = 1.0 if on else 0.4

func _open_howto() -> void:
	var layer := get_parent() as Control
	if layer:
		await HowToSheet.new().open(layer)

func _open_credits() -> void:
	var layer := get_parent() as Control
	if layer:
		await CreditsSheet.new().open(layer)

func _confirm_reset() -> void:
	var yes := await Sheet.confirm(self, "Reset all progress?",
			"Your coins, level, stats and items start over. Sound settings stay. This can’t be undone.",
			"Reset", "Cancel", true)
	if not yes or not is_inside_tree():
		return
	Save.reset_progress()
	var acc := Account.instance()
	if acc != null:
		acc.reset_identity()                  # a reset starts a new guest account (the old one keeps its progress)
	Sound.set_enabled(bool(Save.prefs.get("sound", true)))
	_build()
	prefs_changed.emit()
	Haptics.medium()
	Toast.show(self, "Progress reset.")


# ---------- widgets ----------

## A settings row: lays out its one child (an HBox) and reports a tap (press and release without dragging, so the
## list still scrolls). pressable: shows a soft pressed tint while held (link rows).
class Row extends PanelContainer:
	signal tapped
	var pressable := false
	var _down := false
	var _at := Vector2.ZERO
	static var _sb_none: StyleBoxEmpty
	static var _sb_down: StyleBoxFlat

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		if _sb_none == null:
			_sb_none = StyleBoxEmpty.new()
			_sb_none.content_margin_top = 6; _sb_none.content_margin_bottom = 6
			_sb_down = UIKit.box(Color(Palette.ROW_EDGE, 0.6), UIKit.R.sm)
			_sb_down.expand_margin_left = 8; _sb_down.expand_margin_right = 4
			_sb_down.expand_margin_top = -4; _sb_down.expand_margin_bottom = -4
			_sb_down.content_margin_top = 6; _sb_down.content_margin_bottom = 6
		add_theme_stylebox_override("panel", _sb_none)

	func _gui_input(e: InputEvent) -> void:
		var press := e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
		if press and e.pressed:
			_down = true
			_at = e.position
			_tint(true)
		elif press and not e.pressed and _down:
			_down = false
			_tint(false)
			if e.position.distance_to(_at) <= SettingsSheet.TAP_SLOP and Rect2(Vector2.ZERO, size).has_point(e.position):
				tapped.emit()
		elif e is InputEventMouseMotion and _down and e.position.distance_to(_at) > SettingsSheet.TAP_SLOP:
			_down = false                    # a drag: the list scrolls, no tap
			_tint(false)

	func _tint(on: bool) -> void:
		if pressable:
			add_theme_stylebox_override("panel", _sb_down if on else _sb_none)


## The on / off switch (index.html .switch without the ON / OFF text): TEAL track when on, TAN_DEEP when off, a white
## knob that slides across. The button is a 56 x 48 target around the 52 x 30 track.
class Switch extends Button:
	const TRACK := Vector2(52, 30)
	const KNOB := 24.0
	var t := 0.0
	var _tw: Tween
	static var _knob: StyleBoxFlat
	static var _track: StyleBoxFlat
	static var _inset: StyleBoxFlat

	func _init(on: bool) -> void:
		toggle_mode = true
		button_pressed = on
		t = 1.0 if on else 0.0
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(56, UIKit.TAP)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
			add_theme_stylebox_override(st, StyleBoxEmpty.new())
		if _knob == null:
			_track = UIKit.box(Palette.TAN_DEEP, int(TRACK.y / 2.0))
			_track.shadow_size = 0
			_inset = UIKit.box(Color(0, 0, 0, 0), int(TRACK.y / 2.0), 2, Color(Palette.INK, 0.12))
			_inset.draw_center = false
			_knob = UIKit.box(Color.WHITE, int(KNOB / 2.0), 0, Color.TRANSPARENT, 3, Palette.shadow(0.35))
			_knob.shadow_offset = Vector2(0, 1)
		toggled.connect(_on_toggled)
		UIKit.wire_press(self)

	func _on_toggled(on: bool) -> void:
		if _tw:
			_tw.kill()
		if Sheet.reduce_motion() or not is_inside_tree():
			_set_t(1.0 if on else 0.0)
			return
		_tw = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_tw.tween_method(_set_t, t, 1.0 if on else 0.0, 0.16)

	func _set_t(v: float) -> void:
		t = v
		queue_redraw()

	func _draw() -> void:
		var r := Rect2((size - TRACK) / 2.0, TRACK)
		_track.bg_color = Palette.TAN_DEEP.lerp(Palette.TEAL, t)
		draw_style_box(_track, r)
		draw_style_box(_inset, r)
		var pad := (TRACK.y - KNOB) / 2.0
		var kx := lerpf(r.position.x + pad, r.end.x - KNOB - pad, t)
		draw_style_box(_knob, Rect2(kx, r.position.y + pad, KNOB, KNOB))


## A 0-100 slider (step 1): TRACK track, HONEY fill and a honey knob with a white rim, a 48 px tall target.
class VolSlider extends HSlider:
	const KNOB := 26.0
	static var _knob: StyleBoxFlat
	static var _dot: StyleBoxFlat

	func _init() -> void:
		min_value = 0
		max_value = 100
		step = 1                         # folded levels (Save.fold_master) are any whole percent
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(80, UIKit.TAP)
		var img := Image.create(int(KNOB), int(KNOB), false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var blank := ImageTexture.create_from_image(img)   # sizes the grab area; the knob itself is drawn below
		for ic in ["grabber", "grabber_highlight", "grabber_disabled"]:
			add_theme_icon_override(ic, blank)
		var track := UIKit.box(Palette.TRACK, 6, 0)
		track.content_margin_top = 5; track.content_margin_bottom = 5
		track.content_margin_left = 0; track.content_margin_right = 0
		var fill := track.duplicate() as StyleBoxFlat
		fill.bg_color = Palette.HONEY
		var fill_hi := track.duplicate() as StyleBoxFlat
		fill_hi.bg_color = Palette.GOLD
		add_theme_stylebox_override("slider", track)
		add_theme_stylebox_override("grabber_area", fill)
		add_theme_stylebox_override("grabber_area_highlight", fill_hi)
		if _knob == null:
			_knob = UIKit.box(Palette.HONEY, int(KNOB / 2.0), 3, Color.WHITE, 3, Palette.shadow(0.3))
			_dot = UIKit.box(Palette.HONEY_LIP, 3)
			_dot.shadow_size = 0
		value_changed.connect(func(_v: float): queue_redraw())

	func _draw() -> void:
		var ratio := 0.0 if max_value <= min_value else (value - min_value) / (max_value - min_value)
		var cx := ratio * (size.x - KNOB) + KNOB / 2.0
		var cy := size.y / 2.0
		draw_style_box(_knob, Rect2(cx - KNOB / 2.0, cy - KNOB / 2.0, KNOB, KNOB))
		draw_style_box(_dot, Rect2(cx - 3.0, cy - 3.0, 6.0, 6.0))


## Credits (Settings > Help > Credits): who made the game and the third-party parts with their licences.
class CreditsSheet extends Sheet:
	const ITEMS := [
		["Ludo Zing Mymensingh", "Made by Flipfold Studio."],
		["Godot Engine", "Built with Godot. © Juan Linietsky, Ariel Manzur and contributors. MIT licence."],
		["Sounds", "Kenney (kenney.nl), CC0 licence. The music and some effects are original to this game."],
		["Fonts", "Lilita One and Nunito, SIL Open Font License 1.1."],
	]

	func _init() -> void:
		super("Credits", UIKit.W.form, true, LOOK_PM)
		var list := add_scroll_body(UIKit.SPACE.sm)
		for it: Array in ITEMS:
			var v := UIKit.vbox(2)
			v.add_child(UIKit.label(str(it[0]), UIKit.FS.body_l, Palette.INK, UIKit.font_body(900)))
			v.add_child(UIKit.paragraph(str(it[1]), UIKit.FS.body, Palette.SUB))
			list.add_child(UIKit.panel("row", v))
