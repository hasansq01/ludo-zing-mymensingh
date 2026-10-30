class_name ProfileSheet
extends Sheet
## Profile (index.html #profilePage, the .pm look with the "Profile" ribbon). The red X on the corner is
## the only dismiss control. Folder tabs Me / Achievements (the Achievements tab carries a red count of rewards
## waiting to be claimed) over one framed pane; the card keeps one size for both tabs and only the pane scrolls.
##   Profile: the identity card (the equipped avatar in its frame, the name on its nameplate with the badge, level +
##     XP meter, coins, an "Inventory" button that opens the Inventory on Avatars; the player ID
##     lives in Settings as the Support ID, nothing uses it offline); the name (1-14 characters, trimmed, inner spaces collapsed; Save shows once it changed); the
##     stats in tiles (Ludo vs computer, Snakes & Ladders, Overall).
##   Achievements: a summary (earned count + coins), then every achievement with its medal, a teal progress meter
##     and its reward; Claim pays the coins once and they fly to the coin counter.
## Anything that changes the profile (a new name, a claim, an equip in the Shop) writes Save.profile, emits
## Save.changed (the HUD re-renders) and profile_changed.

signal profile_changed

const MAX_NAME := 14
const FIXED_H := 680.0                ## one card height for both tabs (web .pm min(100%, 720px))
const AVATAR_PX := 72.0
const AVATAR_PX_NARROW := 60.0
const MEDAL_PX := 52.0
## Economy v1: every achievement also pays this many gems (the server decides; shown only with an account).
const ACH_GEMS := 10
const TAB_CLEAR_X := 24               ## right inset of the folder tabs (the corner close X overhangs there)
## Loaded at run time (not by class name), so the Profile still compiles while the Shop is being changed.
const SHOP_SCRIPT := "res://scripts/ui/sheets/shop_sheet.gd"
const COLLECTION_SCRIPT := "res://scripts/ui/sheets/collection_sheet.gd"

var pane := "profile"
var _tabs: TabStrip
var _pane_box: PanelContainer
var _profile_pane: VBoxContainer
var _ach_pane: VBoxContainer
var _ava: Collection.AvatarView
var _plate: Collection.PlateView
var _level: LevelBadge
var _xp: Meter
var _coins: CoinAmount
var _name_edit: LineEdit
var _save_btn: Button
var _err: Label
var _stats_note: Label
var _stat_vals := {}                  # stat key -> value Label (or CoinAmount for coinsEarned)
var _ach_earned: Label
var _ach_coins: CoinAmount            # coins waiting to be claimed
var _ach_claim: Control
var _ach_updaters: Array[Callable] = []
var _claim_btns := {}                 # achievement id -> its Claim button
var _flying := 0                      # coin flights still landing (the counter counts up on its own meanwhile)
var _desat: Shader
var _acct_box: Control                 # the whole Account section (heading + card)
var _acct_title: Label
var _acct_note: Label
var _acct_synced: Control
var _acct_button: Button
var _acct_signing := false


func _init(width := 360.0) -> void:
	super("Profile", width, true, Sheet.LOOK_PM)
	var stack := UIKit.vbox(0)
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(stack)
	_tabs = TabStrip.new([
		{key = "profile", text = "Me", icon = "tab_profile"},
		{key = "ach", text = "Achievements", icon = "ic_trophy"},
	], pane, "folder")
	_tabs.picked.connect(show_pane)
	# the strip stops short of the corner X: the Achievements count badge sits clear of it
	stack.add_child(UIKit.margin(_tabs, 0, UIKit.SPACE.sm, TAB_CLEAR_X, 0))
	_pane_box = PanelContainer.new()
	var ps := TabStrip.pane_style("folder")
	ps.content_margin_left = UIKit.PAD.pane - 2
	ps.content_margin_right = UIKit.PAD.pane - 2
	ps.content_margin_top = UIKit.PAD.pane + TabStrip.F_EDGE     # under the pane's own top line
	ps.content_margin_bottom = UIKit.SPACE.sm
	_pane_box.add_theme_stylebox_override("panel", ps)
	_tabs.bind_pane(_pane_box)
	_pane_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(_pane_box)
	var list := add_scroll_body(UIKit.SPACE.md)
	var wrap := scroll_box.get_parent()               # the scroll area lives in the folder pane, under the tabs
	body.remove_child(wrap)
	_pane_box.add_child(wrap)
	_tint_fade(wrap)
	fit(0.88, FIXED_H)

	_profile_pane = UIKit.vbox(UIKit.SPACE.md)
	_profile_pane.add_child(UIKit.list_row(_build_identity()))
	_profile_pane.add_child(_section("Your name", _build_name()))
	_acct_box = _section("Account", _build_account())
	_acct_box.name = "AccountBox"
	_profile_pane.add_child(_acct_box)
	_profile_pane.add_child(_build_stats())
	list.add_child(_profile_pane)
	_ach_pane = UIKit.vbox(UIKit.SPACE.md)
	_build_ach()
	list.add_child(_ach_pane)
	narrow_changed.connect(_on_narrow)
	show_pane(pane)
	_refresh()


func _ready() -> void:
	Save.changed.connect(_refresh)
	var acc := Account.instance()
	if acc != null:
		acc.account_changed.connect(_refresh_account)
		acc.signed_in_changed.connect(_refresh_account)

## "profile" | "ach"
func show_pane(key: String) -> void:
	pane = key if key == "ach" else "profile"
	_tabs.select(pane)
	_profile_pane.visible = pane == "profile"
	_ach_pane.visible = pane == "ach"
	if scroll_box:
		scroll_box.scroll_vertical = 0

## The scroll fade blends into the pane's cream (Sheet draws it in the card face colour).
func _tint_fade(wrap: Node) -> void:
	var fade := wrap.get_node_or_null("Fade") as TextureRect
	if fade == null:
		return
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(Palette.PANE, 0.0), Palette.PANE])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 4
	gt.height = 32
	gt.fill_from = Vector2(0.5, 0.0)
	gt.fill_to = Vector2(0.5, 1.0)
	fade.texture = gt

func _on_narrow(nar: bool) -> void:
	var px := AVATAR_PX_NARROW if nar else AVATAR_PX
	_ava.custom_minimum_size = Vector2(px, px)


# =====================================================================================================================
# Inventory: the Shop on Avatars, owned items only (decision 4); the old Collection while the Shop can't filter yet
# =====================================================================================================================

func _customise() -> void:
	var s := _make_shop()
	if s == null:
		return
	var app := _app()
	if app and s.has_signal("room_changed"):           # rooms / dice / scenes put in use there apply at once
		if app.has_method("apply_shop_changes"):
			app.call("apply_shop_changes", s)
		elif app.has_method("_wire_shop"):
			app.call("_wire_shop", s)
	if s.has_signal("changed"):
		s.connect("changed", _on_look_changed)
	s.closed.connect(_on_look_changed)
	s.open(get_parent() if get_parent() else self)

## Forwarder (dev previews): the old name of _customise.
func _open_collection() -> void:
	_customise()

func _on_look_changed() -> void:
	if not is_instance_valid(self) or _closing:
		return
	_refresh()
	profile_changed.emit()

## ShopSheet.new("avatars", 400, owned_only = true) once the merged Shop takes the filter; until then the Collection.
static func _make_shop() -> Sheet:
	var sc := load(SHOP_SCRIPT) as GDScript
	if sc and sc.can_instantiate() and _init_arity(sc) >= 3:
		if _init_arity(sc) >= 4:                         # the Inventory variant: ribbon "Inventory", no All | Owned row
			return sc.new("avatars", float(UIKit.W.catalog), true, true) as Sheet
		return sc.new("avatars", float(UIKit.W.catalog), true) as Sheet
	var col := load(COLLECTION_SCRIPT) as GDScript
	if col and col.can_instantiate():
		return col.new("chars") as Sheet
	push_warning("ProfileSheet: neither the Shop nor the Collection can open")
	return null

static func _init_arity(sc: GDScript) -> int:
	for m: Dictionary in sc.get_script_method_list():
		if m.get("name", "") == "_init":
			return (m.get("args", []) as Array).size()
	return 0

func _app() -> Node:
	if not is_inside_tree():
		return null
	var app := get_tree().root.get_node_or_null("Main")
	return app if app else get_tree().root.find_child("Main", true, false)


# =====================================================================================================================
# Profile pane
# =====================================================================================================================

## The avatar in its frame; beside it the name on its plate (+ badge), level + XP and coins. Then Leaderboard and
## Inventory (one name for that place: the nav, this button and the sheet's ribbon).
func _build_identity() -> VBoxContainer:
	var v := UIKit.vbox(UIKit.SPACE.md)
	var head := UIKit.hbox(UIKit.SPACE.md)
	_ava = Collection.make_avatar(AVATAR_PX) as Collection.AvatarView
	_ava.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_ava)
	var right := UIKit.vbox(UIKit.SPACE.sm)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(right)
	_plate = Collection.make_plate("", Collection.DEFAULT_PLATE, "", UIKit.FS.h1, false, 150.0)
	_plate.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	right.add_child(_plate)
	_level = LevelBadge.new(1, "md")
	_xp = Meter.new("xp", 20, true, "XP")
	right.add_child(LevelBadge.row(_level, _xp))
	_xp.show_behind_parent = true            # the star stays over the bar by draw order
	_coins = CoinAmount.new(0, "md", "plain")
	_coins.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	right.add_child(_coins)
	v.add_child(head)

	var btns := UIKit.hbox(UIKit.SPACE.sm)         # Leaderboard (secondary) left, Inventory (primary) right
	var ranks := UIKit.btn("Leaderboard", "white", "sm")
	ranks.name = "Leaderboard"
	ranks.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIKit.fit_text(ranks, 13)
	ranks.pressed.connect(_open_leaderboard)
	btns.add_child(ranks)
	var look := UIKit.btn("Inventory", "honey", "sm")
	look.name = "Inventory"
	look.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIKit.fit_text(look, 13)
	look.pressed.connect(_customise)
	btns.add_child(look)
	v.add_child(btns)

	return v

## A section: its heading above (outside) the row card that holds `content`.
func _section(title: String, content: Control) -> VBoxContainer:
	var v := UIKit.vbox(UIKit.SPACE.sm)
	v.add_child(_heading(title))
	v.add_child(UIKit.list_row(content))
	return v

## The name field; Save appears once the name differs from the saved one; the inline error line.
func _build_name() -> VBoxContainer:
	var v := UIKit.vbox(UIKit.SPACE.sm)
	var row := UIKit.hbox(UIKit.SPACE.sm)
	_name_edit = LineEdit.new()
	_name_edit.max_length = MAX_NAME
	_name_edit.text = str(Save.profile.get("name", "You"))
	_name_edit.placeholder_text = "Your name"
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_name_edit.custom_minimum_size = Vector2(0, UIKit.TAP)
	_name_edit.select_all_on_focus = true
	_name_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
	_name_edit.add_theme_font_override("font", UIKit.font_body(800))
	_name_edit.text_changed.connect(func(_t: String): _validate(true))
	_name_edit.text_submitted.connect(func(_t: String): _save_name())
	row.add_child(_name_edit)
	_save_btn = UIKit.button("Save", "honey", "sm")
	_save_btn.custom_minimum_size.x = 84
	_save_btn.pressed.connect(_save_name)
	row.add_child(_save_btn)
	v.add_child(row)
	_err = UIKit.label("", UIKit.FS.small, Palette.DANGER, UIKit.font_body(800))
	_err.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_err)
	_validate(false)
	return v

## The Leaderboard over the Profile.
func _open_leaderboard() -> void:
	var layer := get_parent() as Control
	if layer == null or _closing:
		return
	LeaderboardSheet.new().open(layer)

## The Account section: "Guest" with the Google Play Games button, or the signed-in Google name with "Synced".
## Only shown where an Account exists (the game; not previews).
func _build_account() -> VBoxContainer:
	var v := UIKit.vbox(UIKit.SPACE.sm)
	var head := UIKit.hbox(UIKit.SPACE.sm)
	_acct_title = UIKit.label("Guest", UIKit.FS.h3, Palette.INK, UIKit.font_display())
	_acct_title.name = "AccountTitle"
	_acct_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_acct_title.clip_text = true
	_acct_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(_acct_title)
	_acct_synced = UIKit.hbox(UIKit.SPACE.xs)
	_acct_synced.name = "Synced"
	_acct_synced.add_child(UIKit.glyph("ic_check", 16, Palette.TEAL_INK))
	var sl := UIKit.caps_label("Synced", Palette.TEAL_INK)
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_acct_synced.add_child(sl)
	_acct_synced.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_acct_synced)
	v.add_child(head)
	_acct_note = UIKit.paragraph("", UIKit.FS.small, Palette.SUB)
	_acct_note.name = "AccountNote"
	v.add_child(_acct_note)
	_acct_button = UIKit.btn("Sign in with Google Play Games", "honey", "sm")
	_acct_button.name = "GoogleSignIn"
	UIKit.fit_text(_acct_button, 13)
	_acct_button.pressed.connect(_sign_in_google)
	UIKit.deny_disabled(_acct_button, func() -> String:
		return "You’re offline. Connect to sign in." if account_state() == "offline" else "")
	v.add_child(_acct_button)
	return v

## What the Account section shows now (Account.instance() absent: hidden).
func account_state() -> String:
	var acc := Account.instance()
	if acc == null or not acc.enabled:
		return "none"
	if acc.banned:
		return "banned"
	if not acc.is_guest():
		return "linked"
	if not acc.has_session():
		return "offline"
	return "guest" if acc.google_available() else "guest_local"

func _refresh_account() -> void:
	if _acct_box == null or not is_instance_valid(_acct_box):
		return
	var st := account_state()
	_acct_box.visible = st != "none"
	if st == "none":
		return
	var acc := Account.instance()
	_acct_synced.visible = st == "linked"
	_acct_button.visible = st in ["guest", "offline"] and acc.google_available()
	_acct_button.disabled = _acct_signing or st == "offline"
	_acct_button.text = "Signing in…" if _acct_signing else "Sign in with Google Play Games"
	match st:
		"linked":
			var g := acc.google_name()
			_acct_title.text = g if g != "" else "Google Play Games"
			_acct_note.text = "Signed in with Google Play Games. Your progress is saved to your account."
		"guest":
			_acct_title.text = "Guest"
			_acct_note.text = "Sign in to keep your progress if you change phones."
		"guest_local":
			_acct_title.text = "Guest"
			_acct_note.text = "Your progress is saved on our server. Sign-in with Google Play Games is available on Android."
		"offline":
			_acct_title.text = "Guest · offline"
			_acct_note.text = "You’re offline. Your progress will sync when you’re back online."
		"banned":
			_acct_title.text = "Account unavailable"
			_acct_note.text = "This account can’t play online right now."
			_acct_button.visible = false

func _sign_in_google() -> void:
	var acc := Account.instance()
	if acc == null or _acct_signing:
		return
	_acct_signing = true
	_refresh_account()
	var r: Dictionary = await acc.link_google()
	_acct_signing = false
	if not is_instance_valid(self) or _closing:
		return
	_refresh_account()
	if r.get("ok", false):
		Haptics.success()
		Toast.show(self, "Signed in as %s" % (acc.google_name() if acc.google_name() != "" else "your Google account"), card, 2.0, "good")
		profile_changed.emit()
		return
	var why := Account.google_error_text(str(r.get("error", "")))
	if why != "":
		Haptics.error()
		Toast.show(self, why, card, 2.4, "bad")

## A section label (UIKit.caption, the one section-label style).
func _heading(text: String) -> Label:
	var l := UIKit.caption(text)
	l.name = "Section"
	return l

## Stats in tidy tiles: Ludo vs computer (2 x 2), Snakes & Ladders, Overall (pairs, Pass & Play, coins earned).
func _build_stats() -> VBoxContainer:
	var v := UIKit.vbox(UIKit.SPACE.lg)
	_stats_note = UIKit.paragraph("Finish a game to start your stats.", UIKit.FS.body, Palette.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(_stats_note)
	v.add_child(_stat_group("Ludo vs computer", [["played", "Played"], ["wins", "Wins"], ["winRate", "Win rate"], ["bestStreak", "Best streak"]]))
	v.add_child(_stat_group("Snakes & Ladders", [["slPlayed", "Played"], ["slWins", "Wins"]]))
	var overall := _stat_group("Overall", [["pairsFormed", "Pairs formed"], ["ppGames", "Pass & Play games"]])
	overall.add_child(_coin_tile("coinsEarned", "Coins earned"))
	v.add_child(overall)
	return v

func _stat_group(title: String, items: Array) -> VBoxContainer:
	var v := UIKit.vbox(UIKit.SPACE.sm)
	v.add_child(_heading(title))
	var g := UIKit.grid(2, UIKit.SPACE.sm)
	for it: Array in items:
		var val := UIKit.label("0", UIKit.FS.h1, Palette.INK, UIKit.font_display(), HORIZONTAL_ALIGNMENT_CENTER)
		_stat_vals[it[0]] = val
		g.add_child(_tile(val, it[1]))
	v.add_child(g)
	return v

func _tile(value: Control, caption: String) -> PanelContainer:
	var tv := UIKit.vbox(0)
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.add_child(value)
	var lab := UIKit.label(caption, UIKit.FS.small, Palette.SUB, UIKit.font_body(800), HORIZONTAL_ALIGNMENT_CENTER)
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tv.add_child(lab)
	var tile := UIKit.panel("tile", tv)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.mouse_filter = Control.MOUSE_FILTER_PASS
	return tile

func _coin_tile(key: String, caption: String) -> PanelContainer:
	var amt := CoinAmount.new(0, "md", "plain")
	amt.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_stat_vals[key] = amt
	return _tile(amt, caption)


# =====================================================================================================================
# Achievements pane
# =====================================================================================================================

func _build_ach() -> void:
	var sum := UIKit.hbox(UIKit.SPACE.sm)
	_ach_earned = UIKit.label("", UIKit.FS.body, Palette.SUB, UIKit.font_body(800, true))
	_ach_earned.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ach_earned.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sum.add_child(_ach_earned)
	_ach_claim = UIKit.hbox(UIKit.SPACE.sm)               # the rewards still to claim (not the wallet)
	_ach_claim.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_ach_claim.add_child(UIKit.label("To claim", UIKit.FS.small, Palette.SUB, UIKit.font_body(800)))
	_ach_coins = CoinAmount.new(0, "sm", "chip")
	_ach_coins.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_ach_claim.add_child(_ach_coins)
	sum.add_child(_ach_claim)
	_ach_pane.add_child(sum)
	for a: Dictionary in Collection.ACH:
		_ach_pane.add_child(_ach_card(a))

## Medal | name, description, then the teal progress meter with the reward (in progress) or Claimed at its right;
## a finished, unclaimed one shows a full-width Claim button there instead.
func _ach_card(a: Dictionary) -> PanelContainer:
	var id: String = a.id
	var goal := int(a.goal)
	var top := UIKit.hbox(UIKit.SPACE.md)
	var well := PanelContainer.new()
	well.custom_minimum_size = Vector2(MEDAL_PX, MEDAL_PX)
	well.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var badge := Collection.make_badge(id, MEDAL_PX - 4.0)
	well.add_child(badge)
	top.add_child(well)

	var txt := UIKit.vbox(UIKit.SPACE.xxs)
	txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var t := UIKit.label(a.name, UIKit.FS.h3, Palette.INK, UIKit.font_display())
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	txt.add_child(t)
	var d := UIKit.paragraph(a.desc, UIKit.FS.small, Palette.MUTED)
	txt.add_child(d)
	var foot := UIKit.hbox(UIKit.SPACE.sm)
	var bar := Meter.new("teal", 18, true)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(bar)
	var reward := HBoxContainer.new()                      # the coins (and, with an account, the gems) it pays
	reward.add_theme_constant_override("separation", UIKit.SPACE.sm)
	reward.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	reward.add_child(CoinAmount.new(int(a.reward), "sm", "plain"))
	if Account.wallet_active():
		reward.add_child(CoinAmount.gems(ACH_GEMS, "sm", "plain", "+"))
	foot.add_child(reward)
	var claimed := UIKit.hbox(UIKit.SPACE.xs)
	claimed.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	claimed.add_child(UIKit.glyph("ic_check", 16, Palette.TEAL_INK))
	var cl := UIKit.caps_label("Claimed", Palette.TEAL_INK)
	cl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	claimed.add_child(cl)
	foot.add_child(claimed)
	var amt := HBoxContainer.new()
	amt.add_theme_constant_override("separation", UIKit.SPACE.sm)
	var amt_coins := CoinAmount.new(int(a.reward), "xs", "plain")
	amt_coins.set_color(Palette.ON_HONEY)
	amt.add_child(amt_coins)
	if Account.wallet_active():
		var amt_gems := CoinAmount.gems(ACH_GEMS, "xs", "plain", "+")
		amt_gems.name = "Gems"
		amt_gems.set_color(Palette.ON_HONEY)
		amt.add_child(amt_gems)
	var claim := UIKit.button_with("Claim", amt, "honey", "sm")
	claim.name = "Claim"
	claim.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	claim.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reorder_claim(claim)
	claim.custom_minimum_size.x = _claim_width(amt)
	claim.pressed.connect(func(): _claim(id))
	_claim_btns[id] = claim
	foot.add_child(claim)
	txt.add_child(UIKit.margin(foot, 0, UIKit.SPACE.xs, 0, 0))
	top.add_child(txt)
	var p := UIKit.list_row(top)
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	p.gui_input.connect(func(e: InputEvent) -> void:        # a tap on one not earned yet says what it asks for
		if Sheet._is_tap(e) and not bool(Collection.ach_progress(id, Save.profile).get("done", false)):
			UIKit.deny(self, "%s: %s" % [a.name, str(a.desc).trim_suffix(".")], p, 2.2))

	_ach_updaters.append(func():
		var pr := Collection.ach_progress(id, Save.profile)
		var done := bool(pr.get("done", false))
		var got := bool(pr.get("claimed", false))
		var v := int(pr.get("value", 0))
		bar.set_value(v, goal)
		bar.set_text(("%s / %s" % [Fmt.coins(v), Fmt.coins(goal)]) if goal >= 1000 else "%d / %d" % [v, goal])
		_medal_look(well, badge, done)
		claim.visible = done and not got
		claim.disabled = false
		bar.visible = not claim.visible           # a ready reward: the Claim button takes the row
		reward.visible = not done
		claimed.visible = got
		UIKit.set_row_state(p, "on" if done and not got else ""))
	return p

## "Claim" first, then the coin amount (button_with puts its child before the text).
static func _reorder_claim(b: Button) -> void:
	var row := b.get_node_or_null("Content")
	var text := row.get_node_or_null("Text") if row else null
	if text:
		row.move_child(text, 0)

## The Claim button's width: its padding, "Claim", the gap and the coin amount (button_with's content row is
## anchored inside the button, so the button doesn't grow with it by itself).
static func _claim_width(amt: Control) -> float:
	var p: Dictionary = UIKit.BTN.sm
	var tw := UIKit.font_display().get_string_size("Claim", HORIZONTAL_ALIGNMENT_LEFT, -1, int(p.fs)).x
	return ceilf(2.0 * float(p.pad) + tw + UIKit.SPACE.sm + amt.get_combined_minimum_size().x)

## Earned: full colour on a honey well with a gold ring. Not yet: a faded, desaturated medal on a dim well.
func _medal_look(well: PanelContainer, badge: Control, done: bool) -> void:
	var st := UIKit.box(Palette.HONEY_TINT if done else Palette.CHIP_DIM, UIKit.R.pill, UIKit.BW.line if done else 0, Palette.GOLD)
	UIKit.pad(st, 5)
	well.add_theme_stylebox_override("panel", st)
	if done:
		badge.material = null
		badge.modulate = Color.WHITE
		return
	if _desat == null:
		_desat = Shader.new()
		_desat.code = """shader_type canvas_item;
void fragment() {
	float g = dot(COLOR.rgb, vec3(0.2126, 0.7152, 0.0722));
	COLOR.rgb = mix(vec3(g), COLOR.rgb, 0.4);
}"""
	if not (badge.material is ShaderMaterial):
		var m := ShaderMaterial.new()
		m.shader = _desat
		badge.material = m
	badge.modulate = Color(1, 1, 1, 0.6)

## Pays the achievement once; the coins fly from its Claim button to the coin counter, which counts up.
func _claim(id: String) -> void:
	var btn: Button = _claim_btns.get(id, null)
	var from := btn.get_global_rect().get_center() if btn and btn.is_inside_tree() else Vector2.INF
	var target := _coin_target()
	var fly := from != Vector2.INF and target != null and is_inside_tree()
	if fly:
		_flying += 1                                     # before the grant: its Save.changed must not jump the counter
	var n := 0
	var gems := 0
	if Account.wallet_active() and is_same(Collection.profile(), Save.profile):
		if btn:
			btn.disabled = true
		var r: Dictionary = await Account.instance().claim_ach(id)
		if not is_instance_valid(self) or _closing:
			return
		n = int(r.get("coins", 0)) if r.get("ok", false) else 0
		gems = int(r.get("gems", 0)) if r.get("ok", false) else 0
		if n <= 0:
			if fly:
				_flying -= 1
			if btn:
				btn.disabled = false
			Haptics.error()
			Toast.show(self, Account.error_text(str(r.get("error", "")), "claim"), card, 2.2, "bad")
			_refresh()
			return
	else:
		n = Collection.claim_ach(id)
	if n <= 0:
		if fly:
			_flying -= 1
		return
	Haptics.success()
	if fly:
		var landed := func() -> void:
			_flying = maxi(0, _flying - 1)
			if _flying == 0 and is_instance_valid(_ava):
				_refresh()
		CoinFly.run(self, from, target, n, landed, Collection.coins())
		if gems > 0:
			Toast.show(self, "+%d gems" % gems, card, 1.8, "gem")
	else:
		Toast.show(self, "%s: %s coins%s" % [Collection.ach(id).name, Fmt.gain(n), (" +%d gems" % gems) if gems > 0 else ""], card, 1.8, "coin")
	_refresh()
	profile_changed.emit()

## The counter the coins fly to: the identity card's on the Profile tab (none on Achievements: a toast instead).
func _coin_target() -> Control:
	return _coins if _coins and _coins.is_visible_in_tree() else null


# =====================================================================================================================
# Data
# =====================================================================================================================

func _refresh() -> void:
	if not is_instance_valid(_ava):
		return
	var p: Dictionary = Save.profile
	_ava.refresh()
	_plate.set_look(str(p.get("name", "You")), Collection.equipped("plate", p), Collection.equipped("badge", p))
	var info: Dictionary = Save.level_info(int(p.get("xp", 0)))
	_level.set_level(int(info.level))
	_xp.set_value(float(info.into), float(info.need))
	var coins := int(p.get("coins", 0))
	if _flying == 0:
		_coins.set_amount(coins)
	var st: Dictionary = p.get("stats", {}) if p.get("stats") is Dictionary else {}
	var played := int(st.get("played", 0))
	var sl_played := int(st.get("slPlayed", 0))
	for k: String in _stat_vals:
		var c: Control = _stat_vals[k]
		if c is CoinAmount:
			(c as CoinAmount).set_amount(int(st.get(k, 0)))
			continue
		var lab := c as Label
		var text := str(int(st.get(k, 0)))
		match k:
			"winRate":
				text = Fmt.pct(float(st.get("wins", 0)) / played) if played > 0 else Fmt.EMPTY
			"wins", "bestStreak":
				if played == 0: text = Fmt.EMPTY
			"slWins":
				if sl_played == 0: text = Fmt.EMPTY
		lab.text = text
		lab.add_theme_color_override("font_color", Palette.MUTED if text == Fmt.EMPTY else Palette.INK)
	_stats_note.visible = played == 0 and sl_played == 0 and int(st.get("ppGames", 0)) == 0
	var earned := 0
	var waiting := 0
	for a: Dictionary in Collection.ACH:
		if Collection.ach_done(a.id, p):
			earned += 1
			if not bool(Collection.ach_progress(a.id, p).get("claimed", false)):
				waiting += int(a.reward)
	_ach_coins.set_amount(waiting)
	_ach_claim.visible = waiting > 0
	_ach_earned.text = "%d of %d earned" % [earned, Collection.ACH.size()]
	for u in _ach_updaters:
		u.call()
	_tabs.set_count("ach", Collection.claimable_count(p))
	if _name_edit and not _name_edit.has_focus():
		_validate(false)
	_refresh_account()

## Trimmed, inner runs of spaces collapsed to one.
static func clean_name(s: String) -> String:
	var parts := s.strip_edges().split(" ", false)
	return " ".join(parts)

## True when the typed name is valid. Save shows only when the name changed, disabled while it's invalid.
func _validate(show_err: bool) -> bool:
	var n := clean_name(_name_edit.text)
	var reserved := n.to_lower() == "you"           # (the game calls every player's own row "You")
	var ok := n.length() >= 1 and n.length() <= MAX_NAME and not reserved
	var changed := n != str(Save.profile.get("name", ""))
	_save_btn.visible = changed
	_save_btn.disabled = not ok or not changed
	_err.text = "" if not show_err or ok else "Pick another name: “You” is how the game shows you to yourself." if reserved \
		else "Enter a name of 1 to %d characters." % MAX_NAME
	_err.visible = _err.text != ""
	return ok

func _save_name() -> void:
	if not _validate(true) or _save_btn.disabled:
		return
	var n := clean_name(_name_edit.text)
	if Account.wallet_active():
		_save_btn.disabled = true
		var r: Dictionary = await Account.instance().push_identity({name = NetClient.wire_name(n)})
		if not is_instance_valid(self) or _closing:
			return
		if not r.get("ok", false):
			Haptics.error()
			Toast.show(self, Account.error_text(str(r.get("error", "")), "name"), card, 2.2, "bad")
			_validate(false)
			return
		n = str(Save.profile.get("name", n))
	else:
		Save.profile.name = n
		Save.save()
	_name_edit.text = n
	_name_edit.release_focus()
	Haptics.success()
	Save.changed.emit()      # also refreshes this sheet
	_validate(false)
	Toast.show(self, "Name saved", card, 1.4, "good")
	profile_changed.emit()
