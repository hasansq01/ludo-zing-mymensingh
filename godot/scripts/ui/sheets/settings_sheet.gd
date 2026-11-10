class_name SettingsSheet
extends Sheet
## Settings, in the game look: a full screen like the Profile (Sheet.make_page(bg, false): the café-brown ground with
## its warm glow, the big outlined "SETTINGS" title, the round red X in the corner, over Home's bar). A screen and
## not a popup: four pages of rows read better at full width with big type than squeezed into a scrolling card, and
## it is somewhere the player goes, not a question. Four tabs (PAGES, wood tiles like the Shop's, the picked one
## orange), each page about one screen: General (Language, Sound & vibration, Accessibility), Game (Game, Camera
## view, House rules; what a match opens on), Alerts (Notifications, Friends), More (Account, Help, Reset progress,
## the version line). The sections:
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
##   Friends        Invites from players (Save.prefs.invites, default on; the server keeps it, through Social: off,
##                  nobody can invite you, and they can't tell)
##   Accessibility  Colour-blind symbols (colorblind), Reduce motion (reduce_motion)
##   Help           How to play, Credits, Rate Ludo Zing (the Play Store page), Privacy policy, Delete my account,
##                  Support (URLS), Privacy choices (only where the ads consent says the player can change them)
##   Reset progress (a red button; confirm first), then the version line and the Support ID (the player ID; nothing
##   else uses it offline, so it lives here instead of on the Profile).
## Every change is written to Save.prefs at once (Save.save() debounces the file write), sound changes reach the
## Sound autoload immediately, and prefs_changed fires so the game can re-read speed / camera / rules.
## Rows: one wood tile each (GameUI's tile colours), the label left in white Nunito 900 17 with an optional cream note
## under it, the control right, at least ROW_H tall; section heads in outlined gold (Lilita One). Switches are the
## game's chunky switch (a dark track that fills teal when on, a raised cream knob; a 72 x 48 target) and a tap on a
## switch row's label toggles it too. Sliders: a gold fill and a gold knob on a dark track. Choices: ShopSheet's
## filter buttons (the picked one a cream face). Help rows are links: teal text and a teal chevron.

signal prefs_changed
signal language_picked(pref: String)     ## "auto" | "en" | "bn" (main switches the language and reopens Settings)
signal probe_requested                   ## PROBE_TAPS taps on the version line: the graphics leak test (LeakProbe)

## The pages, as tabs. l10n-keys: text
const PAGES := [
	{key = "general", text = "General", icon = "res://assets/ui/home/hi_gear.svg", cat = "scenes"},
	{key = "game", text = "Game", icon = "cat_dice", cat = "dice"},
	{key = "alerts", text = "Alerts", icon = "ic_bell", cat = "coins"},
	{key = "more", text = "More", icon = "ic_info", cat = "emotes"},
]
const MAX_H := 680.0                     ## (the old popup's height; the screen now fills the phone)

const VERSION_LINE := "Ludo Zing · v%s · Flipfold Studio"
const PROBE_TAPS := 7                    ## taps on the version line that start the graphics leak test (testers)
## Web pages for the Help rows. A row shows only when its URL is set (no dead "Coming soon" rows).
const URLS := {
	privacy = "https://ludo-zing-rooms.flipfold.workers.dev/privacy",
	delete = "https://ludo-zing-rooms.flipfold.workers.dev/delete-account",
	support = "mailto:Hello@oclasp.com?subject=Ludo%20Zing",
}
const ROW_H := 60.0
const SEG_W := 176.0                     ## two choices right of a row's label (Relaxed / Fast)
const SEG_W_SHORT := 132.0               ## two short choices (3D / Top): the long row labels keep one line
const SEG_H := 44.0
const TAP_SLOP := 12.0
const GAP := 8                           ## between rows
const FS_ROW := 17                       ## a row's label
const FS_NOTE := 13                      ## the cream note under it

var _width := 360.0
var _probe_taps := 0
var _list: VBoxContainer                 # the page being built
var _tabs: PageTabs
var _pages := {}                         # key -> its column of rows
var page := "general"                    ## the page showing
var _switch: Switch                      # the Sound switch (previews flip it)
var _vol_lines: Array[Control] = []
var _gfx_note: Label                     # Graphics: "... on next launch" when the pick needs one
var _notif_note: Label                   # Notifications: what a tap does while the phone doesn't allow them
var _notif_master: Switch
var _notif_lines: Array[Control] = []    # the four kinds (dimmed while the master switch is off)
var _last_note: Label                    # the note label the last _label_box() made


func _init(width: float = UIKit.W.form) -> void:
	super("", width, true, LOOK_PM)
	_width = width
	make_page(ShopSheet._page_bg(), false)
	body.add_theme_constant_override("separation", 12)
	# SETTINGS, left; the room on the right is the X's (the page's own close button, in the corner)
	var head := UIKit.hbox(8)
	head.custom_minimum_size.y = 46
	var title := GameUI.outlined(L10n.t("Settings").to_upper(), 34, GameUI.GOLD, 3)
	title.name = "PageTitle"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(title)
	var x_room := Control.new()
	x_room.custom_minimum_size.x = 52
	x_room.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(x_room)
	body.add_child(head)
	var tabs: Array = []
	for t: Dictionary in PAGES:
		var tt := t.duplicate()
		tt.text = L10n.t(t.text)
		tabs.append(tt)
	_tabs = PageTabs.new(tabs, page)
	_tabs.name = "SettingsTabs"
	_tabs.picked.connect(show_page)
	body.add_child(_tabs)
	add_scroll_body(0)
	_build()


## Show a page ("general" | "game" | "alerts" | "more"), from its top. Every page stays built: only one shows.
func show_page(key: String) -> void:
	if not _pages.has(key):
		return
	page = key
	_tabs.select(key)
	for k: String in _pages:
		(_pages[k] as Control).visible = k == key
	scroll_box.scroll_vertical = 0

## The next rows go on this page.
func _start_page(key: String) -> void:
	_list = UIKit.vbox(GAP)
	_list.name = "Page_" + key
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_body.add_child(_list)
	_pages[key] = _list

func _build() -> void:
	for c in scroll_body.get_children():
		scroll_body.remove_child(c)
		c.queue_free()
	_pages.clear()
	_vol_lines.clear()
	_notif_lines.clear()
	var vol: Dictionary = Save.prefs.get("vol", {})
	var sound_on := bool(Save.prefs.get("sound", true))

	# --- General: language, sound, accessibility
	_start_page("general")
	# --- Language
	_caption(tr("Language"))
	_list.add_child(_language_line())

	# --- Sound
	_caption(tr("Sound & vibration"))
	_switch = Switch.new(sound_on)
	_switch.toggled.connect(_on_sound)
	_list.add_child(_line(tr("Sound"), "", _switch, _switch))
	for v: Array in [["music", tr("Music"), Sound.DEFAULT_MUSIC], ["sfx", tr("Effects"), Sound.DEFAULT_EFFECTS]]:
		var line := _vol_line(v[0], v[1], int(vol.get(v[0], v[2])))
		_vol_lines.append(line)
		_list.add_child(line)
	var vib := Switch.new(bool(Save.prefs.get("vibrate", true)))
	vib.toggled.connect(_on_vibrate)
	_list.add_child(_line(tr("Vibration"), "", vib, vib))
	_dim_volumes(sound_on)

	# --- Accessibility
	_caption(tr("Accessibility"))
	_list.add_child(_switch_line(tr("Colour-blind symbols"), tr("Shapes on pawns and players."), "colorblind"))
	_list.add_child(_switch_line(tr("Reduce motion"), tr("Fewer animations, no shaking."), "reduce_motion"))

	# --- Game: how it plays and looks
	_start_page("game")
	# --- Game
	_caption(tr("Game"))
	_list.add_child(_line(tr("Game speed"), "", _seg([[1.0, tr("Relaxed")], [0.55, tr("Fast")]], float(Save.prefs.get("speed", 1.0)),
			func(v): _set_pref("speed", v))))
	_list.add_child(_graphics_line())

	# --- Camera view (one block, one row per game)
	_caption(tr("Camera view"))
	_list.add_child(_line(tr("Ludo"), "", _seg([["3d", tr("3D")], ["top", tr("Top")]], str(Save.prefs.get("cam", "top")),
			func(v): _set_pref("cam", v), SEG_W_SHORT)))
	_list.add_child(_line(tr("Snakes & Ladders"), "", _seg([["3d", tr("3D")], ["top", tr("Top")]], str(Save.prefs.get("sl_cam", "top")),
			func(v): _set_pref("sl_cam", v), SEG_W_SHORT)))

	# --- House rules
	_caption(tr("House rules"))
	_list.add_child(_switch_line(tr("Ask before pairing"), tr("Choose each time your pawns could pair."), "pair_ask"))
	_list.add_child(_switch_line(tr("Need a 1 to start"), tr("Snakes & Ladders: only a 1 enters."), "sl_need_one"))

	# --- Alerts: notifications and invites
	_start_page("alerts")
	# --- Notifications (the master switch, then what to be told about)
	_caption(tr("Notifications"))
	var master := Switch.new(_notif_shown())
	_notif_master = master
	master.toggled.connect(_on_notif)
	var master_line := _line(tr("Notifications"), " ", master, master)
	_notif_note = _last_note
	_list.add_child(master_line)
	for k: Array in [["notif_rewards", tr("Rewards"), tr("Daily reward, free spin and free coins.")],
			["notif_reminders", tr("Reminders"), tr("A nudge when you have been away.")],
			["notif_game", tr("Game alerts"), tr("Your turn and friends joining a room.")],
			["notif_offers", tr("News & offers"), tr("Gifts and updates from Ludo Zing.")]]:
		var line := _switch_line(k[1], k[2], k[0])
		_notif_lines.append(line)
		_list.add_child(line)
	_refresh_notif()
	var notifs := Notifications.instance()
	if notifs != null and not notifs.permission_changed.is_connected(_refresh_notif):
		notifs.permission_changed.connect(_refresh_notif)

	# --- Friends: who may invite you (the server keeps it: Social)
	_caption(tr("Friends"))
	var inv := Switch.new(bool(Save.prefs.get("invites", true)))
	inv.name = "Invites"
	inv.toggled.connect(_on_invites)
	_list.add_child(_line(tr("Invites from players"), tr("People you played with or who added you can invite you to a game."), inv, inv))

	# --- More: the account, help, reset, the version
	_start_page("more")
	# --- Account (only where there is one): Guest / the Google name, opens the Profile
	var acc := Account.instance()
	if acc != null and acc.enabled:
		_caption(tr("Account"))
		_list.add_child(_account_line(acc))

	# --- Help
	_caption(tr("Help"))
	_list.add_child(_link_line(tr("How to play"), _open_howto))
	_list.add_child(_link_line(tr("Credits"), _open_credits))
	var rate := _link_line(tr("Rate Ludo Zing"), func(): AppRating.open_store())
	rate.name = "RateGame"
	_list.add_child(rate)
	for k: Array in [["privacy", tr("Privacy policy")], ["delete", tr("Delete my account")], ["support", tr("Support")]]:
		var url := str(URLS.get(k[0], ""))
		if url != "":
			_list.add_child(_link_line(k[1], func(): OS.shell_open(url)))
	# Privacy choices (ads consent): only where the consent form says the player can change them
	var ad := Ads.instance()
	if ad != null and ad.privacy_options_required():
		var pc := _link_line(tr("Privacy choices"), func(): ad.show_privacy_options())
		pc.name = "PrivacyChoices"
		_list.add_child(pc)

	# --- Reset progress: a red button, apart from the links
	var reset := GameUI.button(tr("Reset progress"), "red", "md")
	reset.name = "ResetProgress"
	GameUI.fit_button_text(reset, 14)
	reset.pressed.connect(_confirm_reset)
	_list.add_child(UIKit.margin(reset, 0, 14, 0, 0))

	var ver := str(ProjectSettings.get_setting("application/config/version", ""))
	var foot := GameUI.text(VERSION_LINE % (ver if ver != "" else "0.1.0"), FS_NOTE, GameUI.SUB, HORIZONTAL_ALIGNMENT_CENTER)
	foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var id := str(Save.profile.get("id", ""))
	if id != "":
		foot.text += "\n" + tr("Support ID %s") % id
	foot.name = "VersionLine"
	foot.mouse_filter = Control.MOUSE_FILTER_PASS    # (taps still scroll the list)
	foot.gui_input.connect(_on_version_tap)
	_list.add_child(UIKit.margin(foot, 0, 6, 0, 18))
	show_page(page)

# Testers: PROBE_TAPS taps on the version line close Settings and start the graphics leak test.
func _on_version_tap(e: InputEvent) -> void:
	var tap: bool = (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) \
		or (e is InputEventScreenTouch and e.pressed)
	if not tap or e is InputEventMouseButton and DisplayServer.is_touchscreen_available() and e.device == -1:
		return                               # (an emulated mouse click of a touch: counted once, as the touch)
	_probe_taps += 1
	if _probe_taps >= PROBE_TAPS:
		_probe_taps = 0
		probe_requested.emit()
		close()


# ---------- pieces ----------

## A section head above its rows: outlined gold Lilita One (the Profile's "My table").
func _caption(text: String) -> void:
	var l := GameUI.outlined(text, 20, GameUI.GOLD, 2)
	l.name = "Section"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_list.add_child(UIKit.margin(l, 2, 10 if _list.get_child_count() > 0 else 2, 0, 0))

## Label (and an optional note under it) on the left, `control` on the right, on its own wood tile. toggle: a Switch
## that a tap on the label side also flips.
func _line(text: String, note: String, control: Control, toggle: Switch = null) -> Control:
	var row := Row.new()
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

## The label (white) and its note (cream) in a column; the note is kept in _last_note.
func _label_box(text: String, note: String, color := GameUI.TEXT) -> VBoxContainer:
	var v := UIKit.vbox(1)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := UIKit.label(text, FS_ROW, color, UIKit.font_body(900))
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size.x = 60          # (a wrapping label with no width yet asks for one glyph per line)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(t)
	_last_note = null
	if note != "":
		var s := GameUI.text(note, FS_NOTE, GameUI.SUB)
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		s.custom_minimum_size.x = 60
		v.add_child(s)
		_last_note = s
	return v

## The Account row: "Guest" or the Google name with its state under it; a tap opens the Profile, where signing in lives.
func _account_line(acc: Account) -> Control:
	var row := Row.new()
	row.name = "AccountLine"
	row.pressable = true
	var h := UIKit.hbox(UIKit.SPACE.md)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(h)
	var title := tr("Guest")
	var note := tr("Your progress is saved on our server.")
	if not acc.is_guest():
		title = acc.google_name() if acc.google_name() != "" else "Google Play Games"
		note = tr("Signed in with Google Play Games")
	elif not acc.has_session():
		title = tr("Guest · offline")
		note = tr("Your progress will sync when you’re back online.")
	h.add_child(_label_box(title, note))
	if not acc.is_guest():
		var ok := UIKit.hbox(UIKit.SPACE.xs)
		ok.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ok.add_child(UIKit.glyph("ic_check", 16, Palette.GL_BTN_TEAL_HI))
		var sl := UIKit.caps_label(tr("Synced"), Palette.GL_BTN_TEAL_HI)
		sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ok.add_child(sl)
		h.add_child(ok)
	h.add_child(Chevron.new())
	row.tapped.connect(func():
		UIKit.press_fx()
		var main := get_tree().root.get_node_or_null("Main") if is_inside_tree() else null
		if main and main.has_method("_on_tab"):
			# the Profile opens over this screen (main closes the screens it replaces: not this one), and Settings is
			# back when it closes, as before
			as_page = false
			main.call("_on_tab", "profile")
			as_page = true)
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
			"ask": _notif_note.text = tr("Tap to allow notifications on this phone.")
			"denied": _notif_note.text = tr("Off in your phone settings. Tap to open them.")
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

## A link row (Help): teal text and a teal chevron; a tap runs on_tap.
func _link_line(text: String, on_tap: Callable) -> Control:
	var row := Row.new()
	row.pressable = true
	var h := UIKit.hbox(UIKit.SPACE.md)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(h)
	h.add_child(_label_box(text, "", Palette.GL_BTN_TEAL_HI))
	h.add_child(Chevron.new())
	row.tapped.connect(func():
		UIKit.press_fx()
		on_tap.call())
	return row

## Graphics: the label (and the note under it) over a full-width Auto / Low / Medium / High choice; Auto names the
## tier this phone gets (Quality.cap()), the tiers above it are greyed out and the note says they aren't available.
func _graphics_line() -> Control:
	var row := Row.new()
	row.name = "Graphics"
	var v := UIKit.vbox(UIKit.SPACE.sm)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(v)
	var box := _label_box(tr("Graphics"), " ")
	_gfx_note = box.get_child(1) as Label
	v.add_child(box)
	var opts := [["auto", tr("Auto (%s)") % tr(Quality.cap().capitalize())], ["low", tr("Low")], ["medium", tr("Medium")], ["high", tr("High")]]
	var seg := game_seg(opts, Quality.saved_pref(), _on_quality)
	seg.name = "QualitySeg"
	for b: Button in seg.get_children():
		if not Quality.allowed(str(b.get_meta("value"))):
			seg_disable(b)                        # more than this phone can run: it would close the game
	seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIKit.fit_segmented(seg, 12)                  # the four labels share one size; "Auto (Medium)" gets the room it needs
	v.add_child(seg)
	_gfx_hint(Quality.saved_pref())
	return row

## Language: Auto (the phone's language, named in itself) / English / বাংলা, the full row wide. Each language is
## named in its own script, so it can be found whatever the interface shows now.
func _language_line() -> Control:
	var row := Row.new()
	row.name = "Language"
	var opts := [["auto", tr("Auto (%s)") % L10n.NATIVE[L10n.phone()]], ["en", L10n.NATIVE.en], ["bn", L10n.NATIVE.bn]]
	var seg := game_seg(opts, str(Save.prefs.get("lang", "auto")), _on_language)
	seg.name = "LanguageSeg"
	seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UIKit.fit_segmented(seg, 12)
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

## The note under Graphics: which tiers this phone can't run (above Quality.cap()), and when the pick changes
## something read at startup (Quality.needs_restart).
func _gfx_hint(t: String) -> void:
	if _gfx_note == null:
		return
	var lines: Array[String] = []
	match Quality.cap():
		"low": lines.append(tr("Medium and High are too heavy for this phone."))
		"medium": lines.append(tr("High is too heavy for this phone."))
	if Quality.needs_restart(t):
		lines.append(tr("Texture detail applies on next launch."))
	_gfx_note.text = " ".join(lines)
	_gfx_note.visible = _gfx_note.text != ""

func _on_quality(t: Variant) -> void:
	Quality.set_tier(str(t))                 # saves Save.prefs.quality, re-applies the main view and its SubViewports
	_gfx_hint(str(t))
	prefs_changed.emit()

## Two compact choices, right of the row's label.
func _seg(options: Array, selected: Variant, on_pick: Callable, width := SEG_W) -> Control:
	var seg := game_seg(options, selected, on_pick)
	seg.custom_minimum_size.x = width
	seg.size_flags_horizontal = Control.SIZE_SHRINK_END
	return seg

## A row of choices where exactly one is picked, from ShopSheet.filter_button (the picked one a cream face with a
## tan lip, the others an outline on the wood). options: [[value, text], ...]; on_pick(value) runs when the pick
## changes. Each Button carries its value as meta "value" (as UIKit.segmented's).
static func game_seg(options: Array, selected: Variant, on_pick: Callable, h := SEG_H, fs := 16) -> HBoxContainer:
	var row := UIKit.hbox(6)
	var group := ButtonGroup.new()
	for o: Array in options:
		var b := ShopSheet.filter_button(str(o[1]), group, h, fs)
		b.set_pressed_no_signal(o[0] == selected)
		var value: Variant = o[0]
		b.toggled.connect(func(on_: bool):
			if on_:
				on_pick.call(value))
		b.set_meta("value", value)
		UIKit.wire_press(b)
		row.add_child(b)
	return row

## Greys out one choice of a game_seg() row: it can't be picked, its label fades.
static func seg_disable(b: Button) -> void:
	b.disabled = true
	b.add_theme_stylebox_override("disabled", b.get_theme_stylebox("normal"))
	b.add_theme_color_override("font_disabled_color", Color(GameUI.SUB, 0.35))
	b.mouse_default_cursor_shape = Control.CURSOR_ARROW

## Label, a 0-100 slider and its value as a percent ("70%").
func _vol_line(key: String, text: String, value: int) -> Control:
	var row := Row.new()
	var h := UIKit.hbox(UIKit.SPACE.md)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(h)
	var l := UIKit.label(text, FS_ROW, GameUI.TEXT, UIKit.font_body(900))
	l.custom_minimum_size = Vector2(70, 0)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	var s := VolSlider.new()
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(s)
	var out := GameUI.outlined(Fmt.pct(value / 100.0), 17, GameUI.TEXT, 2, HORIZONTAL_ALIGNMENT_RIGHT)
	out.custom_minimum_size = Vector2(48, 0)
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

## "Invites from players": Save.prefs.invites, and the server through Social (sent later when offline).
func _on_invites(on: bool) -> void:
	var s := Social.instance()
	if s != null:
		s.set_invites(on)
	else:
		Save.prefs.invites = on
		Save.prefs.invites_sync = true
		Save.save()
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
	var yes := await Sheet.confirm(self, tr("Reset all progress?"),
			tr("Your coins, level, stats and items start over. Sound settings stay. This can’t be undone."),
			tr("Reset"), tr("Cancel"), true)
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
	Toast.show(self, tr("Progress reset."))


# ---------- widgets ----------

## A settings row on its own wood tile (the game look's rows): lays out its one child (an HBox or a column) and reports
## a tap (press and release without dragging, so the list still scrolls). pressable: the wood lightens while held
## (link rows).
class Row extends GamePanel:
	signal tapped
	var pressable := false
	var _down := false
	var _at := Vector2.ZERO

	func _init() -> void:
		super()
		mode = 1
		mid = 0.5
		radius = 16.0
		border = 2.0
		border_color = Palette.GL_TILE_RIM
		_tint(false)
		var st := StyleBoxEmpty.new()            # (GamePanel's own pad is the same on every side)
		st.content_margin_left = 16; st.content_margin_right = 12
		st.content_margin_top = 9; st.content_margin_bottom = 9
		add_theme_stylebox_override("panel", st)
		custom_minimum_size.y = SettingsSheet.ROW_H
		mouse_filter = Control.MOUSE_FILTER_PASS

	func _gui_input(e: InputEvent) -> void:
		var press := e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
		if press and e.pressed:
			_down = true
			_at = e.position
			_held(true)
		elif press and not e.pressed and _down:
			_down = false
			_held(false)
			if e.position.distance_to(_at) <= SettingsSheet.TAP_SLOP and Rect2(Vector2.ZERO, size).has_point(e.position):
				tapped.emit()
		elif e is InputEventMouseMotion and _down and e.position.distance_to(_at) > SettingsSheet.TAP_SLOP:
			_down = false                    # a drag: the list scrolls, no tap
			_held(false)

	func _held(on: bool) -> void:
		if pressable:
			_tint(on)

	func _tint(on: bool) -> void:
		var top := Palette.GL_CARD_GLOW if on else Palette.GL_TILE_HI
		c0 = top
		c1 = top.lerp(Palette.GL_TILE_LO, 0.5)
		c2 = Palette.GL_TILE_LO


## A link's chevron: a teal ">" in a dark disc (the Help rows, the Account row).
class Chevron extends Control:
	const D := 30.0

	func _init() -> void:
		custom_minimum_size = Vector2(D, D)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size / 2.0
		draw_circle(c, D / 2.0, Palette.GL_CHIP_BG, true, -1.0, true)
		draw_arc(c, D / 2.0 - 1.0, 0.0, TAU, 40, Palette.GL_TEAL_LIP, 2.0, true)
		var k := 5.0
		draw_polyline(PackedVector2Array([c + Vector2(-k * 0.5, -k), c + Vector2(k * 0.6, 0), c + Vector2(-k * 0.5, k)]),
			Palette.GL_BTN_TEAL_HI, 3.2, true)


## The game's on / off switch: a dark rimmed track that fills teal when on, and a raised cream knob (a darker lip under
## it and a soft shadow) that slides across. The button is a 72 x 48 target around the 62 x 34 track.
class Switch extends Button:
	const TRACK := Vector2(62, 34)
	const KNOB := 28.0
	var t := 0.0
	var _tw: Tween
	static var _track: StyleBoxFlat
	static var _shade: StyleBoxFlat

	func _init(on: bool) -> void:
		toggle_mode = true
		button_pressed = on
		t = 1.0 if on else 0.0
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(72, UIKit.TAP)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
			add_theme_stylebox_override(st, StyleBoxEmpty.new())
		if _track == null:
			_track = UIKit.box(Palette.GL_CHIP_BG, int(TRACK.y / 2.0), 2, Palette.GL_WOOD)
			_shade = UIKit.box(Color(0, 0, 0, 0), int(TRACK.y / 2.0))      # the inset shadow along the top
			_shade.draw_center = false
			_shade.border_width_top = 4
			_shade.border_color = Color(0, 0, 0, 0.32)
			_shade.border_blend = true
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
		var r := Rect2(((size - TRACK) / 2.0).round(), TRACK)
		_track.bg_color = Palette.GL_CHIP_BG.lerp(Palette.GL_BTN_TEAL_LO, t)
		_track.border_color = Palette.GL_WOOD.lerp(Palette.GL_TEAL_LIP2, t)
		draw_style_box(_track, r)
		draw_style_box(_shade, r.grow(-2.0))
		var pad := (TRACK.y - KNOB) / 2.0
		var rad := KNOB / 2.0
		var cx := lerpf(r.position.x + pad + rad, r.end.x - pad - rad, t)
		var cy := r.position.y + TRACK.y / 2.0 - 1.0
		draw_circle(Vector2(cx, cy + 3.0), rad, Color(0, 0, 0, 0.35), true, -1.0, true)       # shadow
		draw_circle(Vector2(cx, cy + 1.5), rad, Palette.GL_CREAM_LIP, true, -1.0, true)       # the lip
		draw_circle(Vector2(cx, cy - 0.5), rad - 1.0, Palette.GL_CREAM_LO, true, -1.0, true)  # the face
		draw_circle(Vector2(cx, cy - 2.0), rad - 4.0, Palette.GL_CREAM_HI, true, -1.0, true)  # its light top


## A 0-100 slider (step 1): a dark rimmed track, a gold fill and a raised gold knob with a cream rim, a 48 px tall
## target.
class VolSlider extends HSlider:
	const KNOB := 30.0

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
		var track := UIKit.box(Palette.GL_CHIP_BG, 7, 2, Palette.GL_WOOD)
		track.content_margin_top = 6; track.content_margin_bottom = 6
		track.content_margin_left = 0; track.content_margin_right = 0
		var fill := UIKit.box(Palette.GL_BTN_GOLD_LO, 7, 0)
		fill.content_margin_top = 6; fill.content_margin_bottom = 6
		fill.border_width_top = 3
		fill.border_color = Palette.GL_BTN_GOLD_HI
		fill.border_blend = true
		var fill_hi := fill.duplicate() as StyleBoxFlat
		fill_hi.bg_color = Palette.GL_GOLD
		add_theme_stylebox_override("slider", track)
		add_theme_stylebox_override("grabber_area", fill)
		add_theme_stylebox_override("grabber_area_highlight", fill_hi)
		value_changed.connect(func(_v: float): queue_redraw())

	func _draw() -> void:
		var ratio := 0.0 if max_value <= min_value else (value - min_value) / (max_value - min_value)
		var r := KNOB / 2.0
		var cx := ratio * (size.x - KNOB) + r
		var cy := size.y / 2.0 - 1.0
		draw_circle(Vector2(cx, cy + 3.0), r, Color(0, 0, 0, 0.35), true, -1.0, true)
		draw_circle(Vector2(cx, cy + 1.5), r, Palette.GL_GOLD_LIP, true, -1.0, true)
		draw_circle(Vector2(cx, cy - 0.5), r - 1.0, Palette.GL_CREAM_RIM, true, -1.0, true)
		draw_circle(Vector2(cx, cy - 0.5), r - 4.0, Palette.GL_BTN_GOLD_LO, true, -1.0, true)
		draw_circle(Vector2(cx, cy - 1.5), r - 6.0, Palette.GL_BTN_GOLD_HI, true, -1.0, true)


## The page tabs: wood tiles with an icon and the page's name, the picked one orange with a cream rim and a little
## taller (the Shop's section tiles).
class PageTabs extends HBoxContainer:
	signal picked(key: String)
	var selected := ""
	var _tiles := {}          # key -> {panel, label}

	func _init(items: Array, sel: String) -> void:
		selected = sel
		add_theme_constant_override("separation", 8)
		custom_minimum_size.y = 72
		for it: Dictionary in items:
			var key: String = it.key
			var p := GamePanel.vertical(Palette.GL_WOOD, Palette.GL_TILE_LO)
			p.name = "Tab_" + key
			p.radius = 16.0
			p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			p.size_flags_vertical = Control.SIZE_SHRINK_END
			var col := UIKit.vbox(2)
			col.alignment = BoxContainer.ALIGNMENT_CENTER
			col.mouse_filter = Control.MOUSE_FILTER_IGNORE
			p.add_child(col)
			var ic := UIKit.icon(str(it.get("icon", "")), 28)
			ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			col.add_child(ic)
			var l := UIKit.label(str(it.text), 14, GameUI.SUB, UIKit.font_display(), HORIZONTAL_ALIGNMENT_CENTER)
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			l.clip_text = true
			l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			l.add_theme_color_override("font_outline_color", GameUI.INK)
			col.add_child(l)
			var b := Button.new()
			b.flat = true
			b.focus_mode = Control.FOCUS_NONE
			for k in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
				b.add_theme_stylebox_override(k, StyleBoxEmpty.new())
			b.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			b.pressed.connect(func():
				if key != selected:
					select(key)
					picked.emit(key))
			UIKit.wire_press(b)
			p.add_child(b)
			add_child(p)
			_tiles[key] = {panel = p, label = l}
		select(sel)

	func select(key: String) -> void:
		selected = key
		for k: String in _tiles:
			var on := k == key
			var p: GamePanel = _tiles[k].panel
			var l: Label = _tiles[k].label
			p.c0 = Palette.GL_ORANGE_HI if on else Palette.GL_WOOD
			p.c1 = Palette.GL_ORANGE_HI.lerp(Palette.GL_ORANGE, 0.5) if on else Palette.GL_TILE_HI
			p.c2 = Palette.GL_ORANGE if on else Palette.GL_TILE_LO
			p.border = 3.0 if on else 0.0
			p.border_color = Palette.GL_CREAM_RIM
			p.lip = 5.0 if on else 4.0
			p.lip_color = Palette.GL_ORANGE_LIP if on else Palette.GL_CHIP_BG
			p.custom_minimum_size.y = 72.0 if on else 64.0
			l.add_theme_color_override("font_color", Color.WHITE if on else GameUI.SUB)
			l.add_theme_constant_override("outline_size", 4 if on else 0)
			l.add_theme_font_size_override("font_size", 15 if on else 14)


## Credits (Settings > Help > Credits): who made the game and the third-party parts with their licences. A game-look
## popup: each part on a wood tile, its name in white display type and the line under it in cream.
class CreditsSheet extends Sheet:
	## Names of the game, people, fonts and licences stay as they are; titles and sentences are translated.
	func _items() -> Array:
		return [
			["Ludo Zing", tr("Made by Flipfold Studio.")],
			["Godot Engine", tr("Built with Godot. © Juan Linietsky, Ariel Manzur and contributors. MIT licence.")],
			[tr("Sounds"), tr("Kenney (kenney.nl), CC0 licence. The music and some effects are original to this game.")],
			[tr("Fonts"), tr("Lilita One, Nunito, Baloo Da 2 and Noto Sans Bengali, SIL Open Font License 1.1.")],
		]

	func _init() -> void:
		super(L10n.t("Credits"), UIKit.W.form, true, LOOK_GAME)
		var list := add_scroll_body(SettingsSheet.GAP)
		for it: Array in _items():
			var v := UIKit.vbox(3)
			v.add_child(GameUI.outlined(str(it[0]), 19, GameUI.TEXT, 2))
			var p := GameUI.text(str(it[1]), 15, GameUI.SUB)
			p.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			p.custom_minimum_size.x = 60
			v.add_child(p)
			var tile := GameUI.tile(16.0, 14.0)
			tile.add_child(v)
			list.add_child(tile)
