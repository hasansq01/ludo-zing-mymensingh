extends "res://tests/test_suite.gd"
## Home ("One big Play", scripts/ui/home_screen.gd) and its Rewards sheet: the gift's count of the rewards ready now
## (HomeScreen.reward_states / ready_count, live with the profile), the Rewards sheet's rows (state, countdown, what a
## tap asks main for), the nav (Home / Shop / Ranks / Inventory), QUICK MATCH and the three modes for both games, the
## Continue match pill (MatchStore), and the layout at phone sizes (inside the gutters, 48 px targets, top to bottom
## without overlaps, a free band for the table). Nothing here writes the save: Save's flush is unhooked and the
## profile and prefs are put back.

const MATCH := "user://test_home_match.json"

var _sp: Dictionary
var _spf: Dictionary
var _root: Window


func run() -> void:
	_root = (Engine.get_main_loop() as SceneTree).root
	_sandbox()
	_states()
	_buttons()
	_badge()
	_continue()
	for sz in [Vector2(390, 844), Vector2(474, 844), Vector2(320, 640)]:   # (474 x 844: a 375 x 667 phone's UI)
		_layout(sz, Vector2.ZERO, false)
		_layout(sz, Vector2.ZERO, true)
	_layout(Vector2(390, 844), Vector2(47, 34), true)
	_rewards_sheet()
	_main_wiring()
	_restore()


func _sandbox() -> void:
	_sp = Save.profile
	_spf = Save.prefs
	Save.profile = _sp.duplicate(true)
	Save.prefs = _spf.duplicate(true)
	Save.prefs.home_game = "ludo"
	Save.prefs.reduce_motion = false
	if Save._timer.timeout.is_connected(Save.flush):
		Save._timer.timeout.disconnect(Save.flush)


func _restore() -> void:
	Save._dirty = false
	Save.profile = _sp
	Save.prefs = _spf
	if not Save._timer.timeout.is_connected(Save.flush):
		Save._timer.timeout.connect(Save.flush)


## Rewards ready now (in the sandbox profile): the free spin, the daily reward, the free coins.
func _ready_now(spin: bool, daily: bool, free: bool) -> void:
	var p: Dictionary = Save.profile
	var today := Rewards.day_key()
	p.last_spin = "" if spin else today
	var d := Rewards.daily_data(p)
	d.last = Rewards.add_days(today, -1) if daily else today
	d.streak = 2 if daily else 3
	p.last_free = 0 if free else int(Time.get_unix_time_from_system()) - 60


func _home(sz: Vector2, safe := Vector2.ZERO) -> HomeScreen:
	var frame := Control.new()
	frame.size = sz
	_root.add_child(frame)
	var h := HomeScreen.new()
	frame.add_child(h)
	h.safe_top = safe.x
	h.safe_bottom = safe.y
	_sort(h)
	return h


## Lay the home out and sort its rows now (the tests don't wait for a frame).
func _sort(h: HomeScreen) -> void:
	h._layout()
	for c: Container in [h._top, h._switch, h._switch.get_child(0), h._modes, h._tabs]:
		c.notification(Container.NOTIFICATION_SORT_CHILDREN)


func _drop(h: HomeScreen) -> void:
	var frame := h.get_parent()
	_root.remove_child(frame)
	frame.free()


# ---------- the reward states (the gift's count and the Rewards sheet) ----------

func _states() -> void:
	var p: Dictionary = Save.profile
	_ready_now(false, false, false)
	var st := HomeScreen.reward_states(p)
	check("rewards: nothing ready, nothing counted", HomeScreen.ready_count(p) == 0 and not st.spin.ready and not st.daily.ready and not st.free.ready, st)
	var midnight := Fmt.until(Rewards.sec_to_midnight())
	check("rewards: spin and daily count down to midnight", st.spin.wait == midnight and st.daily.wait == midnight, st)
	check("rewards: free coins count down on the clock", st.free.wait == Fmt.clock(Rewards.free_left_sec(p)) and str(st.free.wait).contains(":"), st)
	_ready_now(true, false, false)
	check("rewards: the spin ready counts 1", HomeScreen.ready_count(p) == 1 and HomeScreen.reward_states(p).spin.wait == "")
	_ready_now(true, true, false)
	check("rewards: + the daily reward counts 2", HomeScreen.ready_count(p) == 2)
	_ready_now(true, true, true)
	check("rewards: all three count 3", HomeScreen.ready_count(p) == 3 and HomeScreen.reward_states(p).free.wait == "")
	check("rewards: the same rules as Rewards", HomeScreen.reward_states(p).spin.ready == Rewards.can_spin(p)
		and HomeScreen.reward_states(p).daily.ready == bool(Rewards.daily_state(p).claimable) and HomeScreen.reward_states(p).free.ready == Rewards.free_ready(p))


# ---------- the buttons ----------

func _buttons() -> void:
	var h := _home(Vector2(390, 844))
	var log := []
	h.quick_match.connect(func(g: String): log.append("quick:" + g))
	h.play_friends.connect(func(g: String): log.append("friends:" + g))
	h.play_game.connect(func(g: String, m: String): log.append("%s:%s" % [g, m]))
	h.open_tab.connect(func(t: String): log.append("tab:" + t))
	var names := []
	for b: Button in h._modes.get_children():
		names.append([str(b.name), (b.find_child("Text", true, false) as Label).text])
	check("home: three compact modes: Friends, Computer, Pass & Play", names == [["Friends", "Friends"], ["Computer", "Computer"], ["PassPlay", "Pass & Play"]], names)
	check("home: Friends is the friends button", h.friends_button == h._modes.get_child(0))
	for g in ["ludo", "sl"]:
		h.select_game(g)
		h.quick_button.pressed.emit()
		for b: Button in h._modes.get_children():
			b.pressed.emit()
	check("home: QUICK MATCH and the three modes ask for the picked game (S&L too)", log == ["quick:ludo", "friends:ludo", "ludo:cpu", "ludo:local",
		"quick:sl", "friends:sl", "sl:cpu", "sl:local"], log)
	check("home: the switch keeps the pick", Save.prefs.home_game == "sl" and h.game == "sl")
	h.select_game("ludo")
	log.clear()
	var tabs := []
	for b: Button in h._tabs.get_children():
		tabs.append(str(b.name))
		b.pressed.emit()
	check("home: the nav is Home, Shop, Ranks, Inventory", tabs == ["Home", "Shop", "Ranks", "Inventory"], tabs)
	check("home: Ranks opens the leaderboard, Home stays", log == ["tab:shop", "tab:leaderboard", "tab:inventory"], log)
	log.clear()
	h.rewards_button.pressed.emit()
	check("home: the gift opens the Rewards sheet", log == ["tab:rewards"], log)
	check("home: reward coins fly from the gift", h.side_button("free") == h.rewards_button and h.side_button("spin") == h.rewards_button
		and h.side_button("leaderboard") == null)
	check("home: no Change scene, no feature tiles, no Play again", h.find_child("ChangeScene", true, false) == null
		and not "sides" in h and not h.has_signal("play_again"))
	_drop(h)


# ---------- the gift's count ----------

func _badge() -> void:
	_ready_now(false, false, false)
	var h := _home(Vector2(390, 844))
	check("gift: no count when nothing is ready", not h._gift_badge.visible)
	_ready_now(true, false, true)
	h.refresh()
	check("gift: the count of the rewards ready (2)", h._gift_badge.visible and h._gift_badge.text == "2", h._gift_badge.text)
	check("gift: the count pulses", h._badge_tw != null and h._badge_tw.is_valid())
	var coins := int(Save.profile.coins)
	check("gift: claiming the free coins drops the count to 1", Rewards.claim_free(Save.profile) > 0 and h._gift_badge.text == "1"
		and int(Save.profile.coins) == coins + Rewards.FREE_AMOUNT, h._gift_badge.text)
	h._refresh_rewards()                                    # (the second tick changes nothing)
	check("gift: the tick keeps the count", h._gift_badge.text == "1")
	Save.prefs.reduce_motion = true
	h._refresh_rewards()
	check("gift: Reduce motion: still, at its size", (h._badge_tw == null or not h._badge_tw.is_valid()) and h._gift_badge.scale == Vector2.ONE)
	Save.prefs.reduce_motion = false
	_ready_now(false, false, false)
	h._refresh_rewards()
	check("gift: all claimed: the count goes", not h._gift_badge.visible and (h._badge_tw == null or not h._badge_tw.is_valid()))
	_drop(h)


# ---------- Continue match ----------

func _continue() -> void:
	var was := MatchStore.path
	var on := MatchStore.enabled
	MatchStore.path = MATCH
	MatchStore.enabled = true
	MatchStore.clear()
	var h := _home(Vector2(390, 844))
	check("continue: no pill without a kept match", not h._quick.visible)
	var band0 := h.free_band()
	MatchStore.save("ludo", {x = 1}, "Ludo vs Computer · 35%")
	h.refresh()
	check("continue: the pill with the match", h._quick.visible and h._quick_sub.text.begins_with("Ludo vs Computer · 35%"), h._quick_sub.text)
	check("continue: the table's band ends above the pill", h.free_band().y <= h._quick.position.y and h.free_band().y < band0.y, [h.free_band(), h._quick.position])
	var asked := []
	h.continue_match.connect(func(): asked.append("continue"))
	h._quick.pressed.emit()
	check("continue: a tap resumes", asked == ["continue"], asked)
	MatchStore.clear()
	h.refresh()
	check("continue: the pill goes with the match", not h._quick.visible and h.free_band() == band0)
	_drop(h)
	MatchStore.enabled = on
	MatchStore.path = was


# ---------- layout ----------

func _layout(sz: Vector2, safe: Vector2, cont: bool) -> void:
	var h := _home(sz, safe)
	if cont:
		h._show_continue("Ludo vs Computer · 35%")
		_sort(h)
	var tag := "home %dx%d%s%s" % [sz.x, sz.y, " safe" if safe != Vector2.ZERO else "", " +continue" if cont else ""]
	var g := HomeScreen.G - 1.0
	var inside := func(c: Control) -> bool:
		var r := c.get_global_rect()
		return r.position.x >= g and r.end.x <= sz.x - g
	var rows: Array[Control] = [h._top, h._switch, h.quick_button, h._modes]
	if cont:
		rows.append(h._quick)
	var bad := []
	for c in rows:
		if not inside.call(c):
			bad.append([c.name, c.get_global_rect()])
	check(tag + ": the rows inside the gutters", bad.is_empty(), bad)
	var taps: Array[Control] = [h.quick_button, h.rewards_button, h._chip]
	taps.append_array(h._modes.get_children())
	taps.append_array(h._tabs.get_children())
	taps.append_array(h._switch_buttons.values())
	if cont:
		taps.append(h._quick)
	var small := []
	for c in taps:
		if c.size.y < UIKit.TAP or c.size.x < UIKit.TAP:
			small.append([c.name, c.size])
	check(tag + ": every button >= 48 px", small.is_empty(), small)
	# top to bottom: the bar, the logo, (the pill), the dock: switch, QUICK MATCH, the modes, the rule, the nav
	var order: Array[Control] = [h._top, h.logo]
	if cont:
		order.append(h._quick)
	order.append_array([h._dock, h._switch, h.quick_button, h._modes, h._rule, h._tabs])
	var overlaps := []
	for i in range(1, order.size()):
		var above := order[i - 1]
		var below := order[i]
		var gap := below.position.y - (above.position.y + above.size.y)
		if below == h._switch:
			gap = below.position.y - h._dock.position.y          # (the switch sits inside the dock)
		if gap < 0.0:
			overlaps.append([above.name, below.name, gap])
	check(tag + ": top to bottom, no overlaps", overlaps.is_empty(), overlaps)
	check(tag + ": the bar below the safe top, the nav above the safe bottom", h._top.position.y >= safe.x
		and h._tabs.position.y + h._tabs.size.y <= sz.y - maxf(safe.y, 8.0), [h._top.position, h._tabs.position, h._tabs.size])
	var band := h.free_band()
	check(tag + ": the free band runs from the logo to the dock (or the pill)", band.x >= h.logo.position.y + h.logo.size.y - 0.5
		and band.y <= (h._quick.position.y if cont else h._dock.position.y), band)
	if sz.y >= 844.0:
		check(tag + ": room for the table (>= 150 px)", band.y - band.x >= 150.0, band)
	check(tag + ": QUICK MATCH is the biggest button", h.quick_button.size.x > h.friends_button.size.x * 2.5
		and h.quick_button.size.y > h.friends_button.size.y, [h.quick_button.size, h.friends_button.size])
	check(tag + ": the switch labels fit their halves", _switch_fits(h), h._switch_buttons.values().map(func(b: Button) -> Vector2: return b.size))
	check(tag + ": the player chip shows the name when there is room", h._chip_text.visible == (sz.x >= 390.0))
	_drop(h)


func _switch_fits(h: HomeScreen) -> bool:
	for k in h._switch_parts:
		var part: Dictionary = h._switch_parts[k]
		var b: Button = h._switch_buttons[k]
		var l: Label = part.label
		var w := 0.0
		for ln in l.text.split("\n"):
			w = maxf(w, l.get_theme_font("font").get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size("font_size")).x)
		if (part.icon as Control).custom_minimum_size.x + float((part.row as HBoxContainer).get_theme_constant("separation")) + w > b.size.x:
			return false
	return true


# ---------- the Rewards sheet ----------

func _rewards_sheet() -> void:
	_ready_now(true, false, false)
	var holder := Control.new()
	_root.add_child(holder)
	var s := RewardsSheet.new()
	holder.add_child(s)
	var rows := []
	for c in s.scroll_body.get_children():
		rows.append(str(c.name))
	check("rewards sheet: Free spin, Daily reward, Free coins", rows == ["Spin", "Daily", "Free"], rows)
	var gc := RewardsSheet.new("Get coins", true)
	holder.add_child(gc)
	var gc_rows := []
	for c in gc.scroll_body.get_children():
		gc_rows.append(str(c.name))
	check("get coins: the same rows as Rewards plus the win info row", gc_rows == ["Spin", "Daily", "Free", "Wins"] and gc.title_label.text == "Get coins", gc_rows)
	check("get coins: the same state as Rewards (one shared row)", (gc.row("spin") as RewardsSheet.Row).go.visible == (s.row("spin") as RewardsSheet.Row).go.visible
		and (gc.row("free") as RewardsSheet.Row).wait_label.text == (s.row("free") as RewardsSheet.Row).wait_label.text)
	var spin: RewardsSheet.Row = s.row("spin")
	var daily: RewardsSheet.Row = s.row("daily")
	var free: RewardsSheet.Row = s.row("free")
	check("rewards sheet: the spin is ready: Spin", spin.go.visible and not spin.wait.visible and spin.go.text == "Spin")
	check("rewards sheet: the daily reward counts down to midnight", daily.wait.visible and not daily.go.visible
		and daily.wait_label.text == "in " + Fmt.until(Rewards.sec_to_midnight()), daily.wait_label.text)
	check("rewards sheet: the free coins count down on the clock", free.wait.visible and free.wait_label.text == "in " + Fmt.clock(Rewards.free_left_sec(Save.profile)), free.wait_label.text)
	var asked := []
	s.picked.connect(func(id: String): asked.append(id))
	for r: Button in [spin, daily, free]:
		r.pressed.emit()
	check("rewards sheet: a tap does the reward's own thing (main._on_tab)", asked == ["spin", "daily", "free"], asked)
	_ready_now(true, true, true)
	s.refresh()
	check("rewards sheet: ready: Spin / Claim / Claim", spin.go.visible and daily.go.visible and free.go.visible
		and daily.go.text == "Claim" and free.go.text == "Claim" and not free.wait.visible)
	Rewards.claim_free(Save.profile)                           # Save.changed: the row turns into the countdown
	check("rewards sheet: claimed: the free coins count down again", free.wait.visible and not free.go.visible
		and free.wait_label.text == "in " + Fmt.clock(Rewards.free_left_sec(Save.profile)), free.wait_label.text)
	check("rewards sheet: the rows are the buttons (>= 48 px, the action is drawn only)", spin.custom_minimum_size.y >= UIKit.TAP
		and spin.go.mouse_filter == Control.MOUSE_FILTER_IGNORE and s.row("leaderboard") == null)
	_root.remove_child(holder)
	holder.free()


## main.gd: the gift, Ranks and the Shop / Inventory tab for Snakes & Ladders (the real app: dev/home_variants_real.gd).
func _main_wiring() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/main.gd")
	check("main: the gift opens RewardsSheet, its rows go through _on_tab", src.contains("\"rewards\":") and src.contains("RewardsSheet.new()")
		and src.contains("s.picked.connect(_on_tab)"))
	check("main: Shop and Inventory open on Scenes with Snakes & Ladders picked (Change scene)", src.contains("return \"scenes\" if home and home.game == \"sl\" else \"rooms\"")
		and src.contains("ShopSheet.new(_home_shop_tab(), 400.0, true, true)"))
	check("main: free coins fly from the Rewards sheet's row", src.contains("if top is RewardsSheet:"))
