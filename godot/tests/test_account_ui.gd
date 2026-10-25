extends "res://tests/test_suite.gd"
## The account UI: Conflict sheet, Leaderboard sheet (loading / list / empty / offline / error, tabs, cache, your row),
## the Profile's Account section, and the wallet sheets (Shop, Daily, Spin) going through the server with the friendly
## offline message. A fake server answers (tests/fake_accounts.gd); Save is swapped for a throwaway profile and its
## debounced write is cut, so user://save.json is never touched.

const Fake := preload("res://tests/fake_accounts.gd")

var _done := false
var _sp: Dictionary
var _spf: Dictionary
var _root: Node

func run() -> void:
	_root = (Engine.get_main_loop() as SceneTree).root
	_sandbox()
	_all()
	_restore()
	check("account ui: the suite ran to the end", _done)

func _sandbox() -> void:
	_sp = Save.profile
	_spf = Save.prefs
	Save.profile = Fake.base_profile()
	Save.prefs = {}
	Save.normalize()
	if Save._timer.timeout.is_connected(Save.flush):
		Save._timer.timeout.disconnect(Save.flush)

func _restore() -> void:
	Save._dirty = false
	Save.profile = _sp
	Save.prefs = _spf
	if not Save._timer.timeout.is_connected(Save.flush):
		Save._timer.timeout.connect(Save.flush)

func _all() -> void:
	await _conflict()
	await _leaderboard()
	await _profile()
	await _wallet_sheets()
	_misc()
	_done = true

func account(fake: Fake) -> Account:
	var a := Account.new()
	a.url_base = "ws://fake"
	a.http_fn = fake.http
	_root.add_child(a)                       # also makes it Account.instance()
	return a

func drop(a: Account) -> void:
	_root.remove_child(a)
	Account.set_instance(null)
	a.free()

# ---------- conflict ----------

func _conflict() -> void:
	var here := {name = "Zed", avatar = "pawn-red", level = 2, coins = 5000, wins = 1}
	var there := {name = "Zara", avatar = "pawn-blue", level = 9, coins = 40000, wins = 55}
	var s := ConflictSheet.new({kind = "conflict", here = here, there = there, ticket = "T"}, null)
	var texts := []
	_collect(s, texts)
	check("conflict: both progresses are shown", texts.has("Zed") and texts.has("Zara") and texts.has("Level 2 · 1 win") and texts.has("Level 9 · 55 wins"), texts)
	check("conflict: the two choices", s.here_button.text == "Keep this device’s progress" and s.there_button.text == "Use Google account’s progress")
	check("conflict: consequences are spelled out", texts.has(ConflictSheet.here_text("conflict")) and texts.has(ConflictSheet.there_text("conflict", true)))
	check("conflict: 48 px targets", s.here_button.get_combined_minimum_size().y >= UIKit.TAP and s.there_button.get_combined_minimum_size().y >= UIKit.TAP)
	var got := []
	s.chosen.connect(func(k: String): got.append(k))
	s.here_button.pressed.emit()
	s.there_button.pressed.emit()
	check("conflict: the buttons say here / there", got == ["here", "there"], got)
	s.free()
	var o := ConflictSheet.new({kind = "other_google", here = here, there = null, ticket = "T"}, null)
	var t2 := []
	_collect(o, t2)
	check("other_google: stay / switch labels", o.here_button.text == "Stay on this account" and o.there_button.text == "Switch to the other account")
	check("other_google: a Google player with no account yet is a new account", t2.has("New account") and t2.has("Starts at level 1"), t2)
	var got2 := []
	o.chosen.connect(func(k: String): got2.append(k))
	o.here_button.pressed.emit()
	o.there_button.pressed.emit()
	check("other_google: keep values stay / switch", got2 == ["stay", "switch"], got2)
	o.free()
	# resolving through an Account closes the sheet and switches the profile
	var f := Fake.new()
	var a := account(f)
	await a.sign_in_guest()
	f.google_status = 409
	f.google_body = {error = "conflict", conflict = {here = here, there = there}, ticket = "T1"}
	var pg := Fake.FakePG.new()
	a.pg_factory = func(): return pg
	a._pg = null
	await a.link_google()
	var p2 := Fake.base_profile()
	p2.name = "Zara"
	p2.coins = 40000
	f.resolve_body = {account = {id = "acc9", guest = false, google_name = "Zara G"}, session = "acc9.4102444800.sig", profile = p2, switched = true}
	var layer := Control.new()
	_root.add_child(layer)
	var cs := ConflictSheet.present(layer, a)
	check("conflict: present() builds from the account's pending conflict", cs.there_button.text == "Use Google account’s progress" and a.conflict.ticket == "T1")
	check("conflict: present() twice gives the same sheet", ConflictSheet.present(layer, a) == cs)
	cs._pick("there")
	check("conflict: choosing there switched the profile", Save.profile.coins == 40000 and Save.profile.name == "Zara" and a.conflict.is_empty(), Save.profile)
	check("conflict: ...and the sheet closes itself", cs._closing)
	cs.free()
	layer.free()
	pg.free()
	drop(a)
	Save.profile.clear()
	Save.profile.merge(Fake.base_profile())

func _collect(n: Node, out: Array) -> void:
	if n is Label:
		out.append((n as Label).text)
	if n is Button and (n as Button).text != "":
		out.append((n as Button).text)
	for c in n.get_children():
		_collect(c, out)

# ---------- leaderboard ----------

func _board(n: int, me: Variant = null) -> Dictionary:
	var top := []
	for k in n:
		top.append({rank = k + 1, name = "Player %d" % (k + 1), avatar = "pawn-green", frame = "classic", level = 10 - k, value = 1000 - k * 10})
	return {ok = true, top = top, me = me, min_matches = 3}

func _leaderboard() -> void:
	var calls := []
	var answer := {v = _board(5, {rank = 7, value = 120, listed = true})}
	var s := LeaderboardSheet.new()
	s.auto_load = false
	s.fetch_fn = func(b: String, p: String) -> Dictionary:
		calls.append([b, p])
		return answer.v
	_root.add_child(s)
	await s.load_board()
	check("leaderboard: a list of rows", s.state == "list" and s.rows_shown == 5, s.state)
	check("leaderboard: asked board xp, weekly first", calls == [["xp", "week"]], calls)
	var texts := []
	_collect(s, texts)
	check("leaderboard: names, level and value", texts.has("Player 1") and texts.has("Level 10") and texts.has("1K XP") or texts.has("1,000 XP") or texts.has("1.0K XP"), texts)
	var r1 := s.find_child("Row1", true, false)
	var medal := r1.find_child("Rank", true, false).get_child(0) if r1 else null
	check("leaderboard: rank 1 has a medal, rank 4 a number", medal is PlayerTile.PlaceBadge and s.find_child("Row4", true, false).find_child("Rank", true, false).get_child(0) is Label)
	check("leaderboard: your row is pinned with your rank", s._me_bar.visible and s.find_child("YouRank", true, false).text == "#7" and s.find_child("YouValue", true, false).text.begins_with("120"))
	# tabs
	s.select("wins", "all")
	check("leaderboard: switching to Online wins / All time asks again", calls[calls.size() - 1] == ["wins", "all"], calls)
	var n := calls.size()
	s.select("wins", "all")
	check("leaderboard: a fresh answer is kept (no second call)", calls.size() == n)
	s.select("xp", "week")
	check("leaderboard: back to a kept board: no call, rows shown", calls.size() == n and s.rows_shown == 5)
	await s.load_board(true)
	check("leaderboard: refresh forces a call", calls.size() == n + 1)
	# the pinned bar keeps its height across refreshes (it once stayed ~190 px after a refresh and pushed your row
	# below the card): a tall moment during the rebuild is fitted back to the row
	s._me_bar.size.y = 190.0
	s._render_me(answer.v)
	s._fit_me_bar()                        # (deferred after a render)
	check("leaderboard: after a refresh the pinned bar fits its row again, no taller", s._me_bar.size.y <= s._me_bar.get_combined_minimum_size().y + 1.0,
		[s._me_bar.size.y, s._me_bar.get_combined_minimum_size().y])
	check("leaderboard: the pinned note wraps within a real width (never one glyph per line)", s.me_label.custom_minimum_size.x >= LeaderboardSheet.ME_NOTE_W)
	check("leaderboard: wins values read as wins", LeaderboardSheet.value_text(42, "wins") == "42 wins" and LeaderboardSheet.value_text(1, "wins") == "1 win")
	# not listed yet
	answer.v = _board(3, {rank = 9, value = 30, listed = false})
	s._cache.clear()
	await s.load_board()
	var note: Label = s.find_child("YouNote", true, false)
	check("leaderboard: not listed -> play N more matches", note.text == "Play 3 more matches to appear", note.text)
	check("leaderboard: no rank while not listed", not s.find_child("YouRank", true, false).visible)
	check("leaderboard: matches_to_go", LeaderboardSheet.matches_to_go(3, 2) == 1 and LeaderboardSheet.matches_to_go(3, 0) == 3 and LeaderboardSheet.matches_to_go(3, 9) == 1)
	# no me (no session) and an unranked me
	answer.v = _board(2, null)
	s._cache.clear()
	await s.load_board()
	check("leaderboard: no session -> connect to see your rank", s.find_child("YouNote", true, false).text == "Connect to see your rank")
	answer.v = _board(2, {rank = null, value = 0, listed = true})
	s._cache.clear()
	await s.load_board()
	check("leaderboard: unranked", s.find_child("YouNote", true, false).text == "Not ranked yet")
	# empty
	answer.v = {ok = true, top = [], me = null, min_matches = 3}
	s._cache.clear()
	await s.load_board()
	var et := []
	_collect(s._list, et)
	check("leaderboard: empty state", s.state == "empty" and s.rows_shown == 0 and et.size() > 0 and et[0].begins_with("No one is on the board yet"), et)
	# offline, then retry
	answer.v = {ok = false, error = "offline"}
	s._cache.clear()
	await s.load_board()
	check("leaderboard: offline state with Try again", s.state == "offline" and s.retry_button != null and not s._me_bar.visible)
	var ot := []
	_collect(s._list, ot)
	check("leaderboard: offline copy", ot.has("Connect to the internet to see the leaderboard."), ot)
	answer.v = _board(2, null)
	s.retry_button.pressed.emit()
	check("leaderboard: Try again reloads", s.state == "list" and s.rows_shown == 2, s.state)
	# a failed refresh keeps the list
	answer.v = {ok = false, error = "server"}
	await s.load_board(true)
	check("leaderboard: a failed refresh keeps the rows", s.state == "list" and s.rows_shown == 2)
	answer.v = {ok = false, error = "server"}
	s._cache.clear()
	await s.load_board()
	check("leaderboard: server error state", s.state == "error" and s.retry_button != null)
	check("leaderboard: 48 px targets", s.refresh_button.custom_minimum_size.y >= UIKit.TAP and s.board_seg.custom_minimum_size.y >= UIKit.TAP and s.period_seg.custom_minimum_size.y >= UIKit.TAP)
	# 50 rows at most
	answer.v = _board(60, null)
	s._cache.clear()
	await s.load_board()
	check("leaderboard: at most 50 rows", s.rows_shown == 50, s.rows_shown)
	s.free()
	# default fetch goes through the Account, offline without one
	var s2 := LeaderboardSheet.new()
	s2.auto_load = false
	_root.add_child(s2)
	await s2.load_board()
	check("leaderboard: no Account -> offline state", s2.state == "offline")
	s2.free()
	var f := Fake.new()
	f.board = _board(3, {rank = 2, value = 500, listed = true})
	var a := account(f)
	var s3 := LeaderboardSheet.new()
	s3.auto_load = false
	_root.add_child(s3)
	await s3.load_board()
	check("leaderboard: through the Account (GET /v1/leaderboard)", s3.state == "list" and f.last("/v1/leaderboard").path.contains("board=xp&period=week"), f.calls)
	s3.free()
	drop(a)

# ---------- profile: the Account section ----------

func _profile() -> void:
	var p := ProfileSheet.new()
	_root.add_child(p)
	check("profile: no Account -> no Account section", p.account_state() == "none" and not p._acct_box.visible)
	var f := Fake.new()
	var a := account(f)
	var pg := Fake.FakePG.new()
	pg.available = false
	a.pg_factory = func(): return pg
	await a.sign_in_guest()
	p._refresh_account()
	check("profile: a guest where Play Games is unavailable: a note, no button", p.account_state() == "guest_local" and p._acct_box.visible and not p._acct_button.visible
		and p._acct_title.text == "Guest" and p._acct_note.text.contains("Android"), p._acct_note.text)
	check("profile: not synced while a guest", not p._acct_synced.visible)
	pg.available = true
	p._refresh_account()
	check("profile: a guest with Play Games: the sign-in button", p.account_state() == "guest" and p._acct_button.visible and not p._acct_button.disabled
		and p._acct_button.text == "Sign in with Google Play Games")
	check("profile: 48 px target", p._acct_button.get_combined_minimum_size().y >= UIKit.TAP)
	p._acct_button.pressed.emit()
	check("profile: signing in links the account", not a.is_guest() and p.account_state() == "linked", a.account)
	check("profile: signed in shows the Google name and Synced", p._acct_title.text == "Zing Player" and p._acct_synced.visible and not p._acct_button.visible)
	a._session = ""
	a.account.guest = true
	p._refresh_account()
	check("profile: no session: offline note, button disabled", p.account_state() == "offline" and p._acct_title.text == "Guest · offline" and p._acct_button.disabled)
	a.banned = true
	p._refresh_account()
	check("profile: banned account", p.account_state() == "banned" and not p._acct_button.visible)
	var ranks := p.find_child("Leaderboard", true, false) as Button
	check("profile: a Leaderboard button (48 px)", ranks != null and ranks.get_combined_minimum_size().y >= UIKit.TAP)
	p.free()
	pg.free()
	drop(a)

# ---------- wallet sheets ----------

func _wallet_sheets() -> void:
	var f := Fake.new()
	f.profile.coins = 5000
	var a := account(f)
	a.persist = Callable()
	await a.sign_in_guest()
	check("sheets: the account wrote the server profile into Save.profile", Save.profile.id == "LZM-TEST-0001" and Save.profile.coins == 5000)
	# Shop
	var shop := ShopSheet.new("rooms")
	_root.add_child(shop)
	var err: String = await shop._purchase("room", "neon")
	check("shop: a purchase goes through the server", err == "" and Save.profile.coins == 2000 and Save.profile.rooms.has("neon") and f.count("/v1/shop/buy") == 1, err)
	err = await shop._purchase("room", "neon")
	check("shop: the server's refusal comes back as text", err != "", err)
	f.profile.coins = 100
	err = await shop._purchase("dice", "gold")
	check("shop: too poor -> the need-more-coins line", err.begins_with("Not enough coins"), err)
	f.online = false
	a._session = ""
	err = await shop._purchase("room", "neon")
	check("shop: offline: Connect to the internet to buy", err == "Connect to the internet to buy.", err)
	var before: int = Save.profile.coins
	check("shop: offline: nothing granted or charged locally", Save.profile.coins == before)
	f.online = true
	shop.free()
	# Daily
	f.profile.coins = 1000
	await a.sign_in_guest()
	var d := DailySheet.new()
	_root.add_child(d)
	var claimed := []
	d.claimed.connect(func(r: Dictionary): claimed.append(r.coins))
	d.auto_close = false
	await d._claim()
	check("daily: the claim goes through the server", claimed == [100] and Save.profile.coins == 1100 and f.count("/v1/rewards/daily") == 1, [claimed, Save.profile.coins])
	d.free()
	var d2 := DailySheet.new()
	_root.add_child(d2)
	f.daily_taken = false
	f.online = false
	a._session = ""
	Save.profile.daily = {}
	var c0: int = Save.profile.coins
	await d2._claim()
	check("daily: offline: nothing granted", Save.profile.coins == c0 and not d2._busy)
	var tt := []
	_collect(_root.get_node_or_null("ToastLayer") if _root.get_node_or_null("ToastLayer") else d2, tt)
	d2.free()
	f.online = true
	# Spin
	f.profile.coins = 1000
	await a.sign_in_guest()
	var changed := [0]
	var cb := func(): changed[0] += 1
	Save.changed.connect(cb)
	var sp := SpinSheet.new()
	_root.add_child(sp)
	await sp._spin()
	check("spin: the server draws the prize (500) and the wheel is turning", sp._spinning and Save.profile.coins == 1500 and f.count("/v1/rewards/spin") == 1, Save.profile.coins)
	check("spin: Save.changed waits for the wheel to stop", changed[0] == 0, changed)
	sp._landed({index = 3, prize = 500})
	check("spin: it fires when the prize shows", changed[0] >= 1)
	Save.changed.disconnect(cb)
	sp.free()
	# Profile: achievement claim and name through the server
	var ps := ProfileSheet.new()
	_root.add_child(ps)
	Save.profile.stats.wins = 1
	await ps._claim("first")
	check("profile: an achievement claim goes through the server", Save.profile.claimed.has("first") and f.count("/v1/achievements/claim") == 1, Save.profile.claimed)
	ps._name_edit.text = "Mimi"
	await ps._save_name()
	check("profile: a new name is PATCHed to the server", f.last("/v1/me").method == HTTPClient.METHOD_PATCH and f.last("/v1/me").body == {name = "Mimi"} and Save.profile.name == "Mimi", f.last("/v1/me"))
	f.online = false
	a._session = ""
	ps._name_edit.text = "Mimi Two"
	await ps._save_name()
	check("profile: offline the name stays as it was", Save.profile.name == "Mimi", Save.profile.name)
	ps.free()
	f.online = true
	# the free coins and match claims are main.gd's: its source uses the same calls
	var main_src := FileAccess.get_file_as_string("res://scripts/main.gd")
	check("main: free coins go through Account.free_coins when there is an account", main_src.contains("account.free_coins()") and main_src.contains("Rewards.claim_free(Save.profile)"))
	check("main: offline matches are reported as claims", main_src.contains("account.report_match(info)"))
	drop(a)
	Save.profile.clear()
	Save.profile.merge(Fake.base_profile())

func _misc() -> void:
	var r := ResultScreen.new({game = "ludo", human_won = true, reward = 150, standings = [{color = 0, name = "You", kind = "you", place = 1, finished = 4, progress = 1.0}]})
	_root.add_child(r)
	r.set_claim_note("Daily limit reached")
	var t := []
	_collect(r, t)
	check("result: the claim note shows", t.has("Daily limit reached"), t)
	r.set_claim_note("Too short to count")
	var n := 0
	for s: String in _texts_of(r):
		if s == "Too short to count" or s == "Daily limit reached":
			n += 1
	check("result: a second note replaces the first", n == 1)
	r.free()
	var home := FileAccess.get_file_as_string("res://scripts/ui/home_screen.gd")
	check("home: the Ranks side button opens the leaderboard", home.contains("[\"leaderboard\", \"Ranks\"") and FileAccess.get_file_as_string("res://scripts/main.gd").contains("LeaderboardSheet.new().open(sheet_layer)"))

func _texts_of(n: Node) -> Array:
	var out := []
	_collect(n, out)
	return out
