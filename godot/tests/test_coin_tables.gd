extends "res://tests/test_suite.gd"
## Coin tables in quick match (server/ECONOMY_V1.md section 3): the prize maths, the picker's rows (locked, greyed out,
## the remembered table), the queue URL with `table`, the queue's own errors (locked / coins) against the fake
## matchmaker, the entry taken and given back, the "Out of coins" popup (when it opens, the daily bonus, the video, the
## way to Practice) and the coin table's result card (prize, "Entry 100 lost", "Double it with a video").
## Nothing here writes the save or opens a socket.

class FakeAcc extends RefCounted:
	var tables := {ok = true, tables = [], broke_bonus = {available = true, next_at = 0, amount = 300}}
	var claims := 0
	var claim_answer := {ok = true, coins = 300, next_at = 0}
	func fetch_tables() -> Dictionary:
		return tables
	func claim_broke() -> Dictionary:
		claims += 1
		return claim_answer

## An AdFlow that doesn't show anything: watch() answers at once.
class FakeFlow extends AdFlow:
	var asked: Array = []
	var answer := {ok = true, info = {kind = "double", amount = 180}}
	func watch(kind: String, ref := "") -> void:
		asked.append([kind, ref])
		done.emit(bool(answer.ok), answer.info)

func run() -> void:
	_math()
	_rows()
	_sheet()
	_url_and_queue()
	_online()
	_broke()
	_result()


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree

func _math() -> void:
	check("tables: the six of ECONOMY_V1.md", CoinTables.TABLES.map(func(t): return [t.id, t.entry, t.level]) ==
		[["practice", 0, 1], ["t100", 100, 1], ["t500", 500, 3], ["t2k", 2000, 6], ["t10k", 10000, 10], ["t50k", 50000, 15]])
	check("prize: 100 table, 2 players: the pot 200 minus 10% = 180", CoinTables.prize(100, 2) == 180 and CoinTables.pool(100, 2) == 180)
	check("prize: 500 table, 4 players: 1st 1,350, 2nd 450", CoinTables.prize(500, 4, 1) == 1350 and CoinTables.prize(500, 4, 2) == 450
		and CoinTables.prize(500, 4, 3) == 0)
	check("prize: 4 players, 1st 75% of the pool and 2nd the remainder (the pool is never exceeded)", [100, 500, 2000, 10000, 50000].all(
		func(e): return CoinTables.prize(e, 4, 1) + CoinTables.prize(e, 4, 2) == CoinTables.pool(e, 4)))
	check("prize: 2 players pay 1st only", CoinTables.prize(2000, 2, 2) == 0 and CoinTables.prize(2000, 2) == 3600)
	check("broke: below 100 coins", CoinTables.is_broke(99) and not CoinTables.is_broke(100) and CoinTables.is_broke(0))
	check("valid ids", CoinTables.valid("t2k") and not CoinTables.valid("t3") and not CoinTables.valid(""))

func _rows() -> void:
	var rows := CoinTables.rows(2, 1, 2500)
	check("rows: level 1, 2,500 coins: Practice and 100 playable, the rest locked", rows.map(func(r): return r.ok) == [true, true, false, false, false, false]
		and rows[2].locked and rows[2].level == 3 and rows[2].affordable)
	check("rows: the prize per player count (2 players 180, 4 players 270 at the 100 table, 1,350 at 500)", rows[1].prize == 180
		and CoinTables.rows(4, 1, 2500)[1].prize == 270 and CoinTables.rows(4, 5, 2500)[2].prize == 1350)
	var poor := CoinTables.rows(2, 20, 150)
	check("rows: high level, 150 coins: only Practice and 100 can be paid", poor.map(func(r): return r.affordable) == [true, true, false, false, false, false]
		and poor.map(func(r): return r.locked) == [false, false, false, false, false, false])
	var srv := {tables = [{id = "t100", unlocked = true, affordable = false}, {id = "t500", unlocked = true, affordable = true}]}
	var over := CoinTables.rows(2, 1, 2500, srv)
	check("rows: the server's flags win over ours", not over[1].affordable and over[2].ok and not over[2].locked and over[0].ok)
	check("pick: the remembered table when playable, else Practice", CoinTables.pick("t100", rows) == "t100" and CoinTables.pick("t500", rows) == "practice"
		and CoinTables.pick("nope", rows) == "practice")
	check("lost text", CoinTables.lost_text(100) == "Entry 100 lost" and CoinTables.lost_text(2000) == "Entry 2,000 lost" and CoinTables.lost_text(0) == "")

func _sheet() -> void:
	var s := QuickSheet.new("ludo", 2, "t100")
	s.set_wallet(1, 2500)
	check("picker: the six rows, the remembered 100 table picked", s.table_rows.size() == 6 and s.table == "t100" and s.row_of("t100").on)
	check("picker: 100 shows its entry and 'Win 180'", s.row_of("t100").title.text == "100" and s.row_of("t100").prize_label.text == "Win 180")
	check("picker: Practice is Free", s.row_of("practice").title.text == "Practice" and s.row_of("practice").prize_label.text == "Free")
	check("picker: a locked table shows its level", s.row_of("t500").prize_label.text == "Level 3" and s.row_of("t500").modulate.a < 1.0)
	s.picker.get_child(1).pressed.emit()
	s.players = 4
	s._refresh_rows()
	check("picker: 4 players: 'Win 270' at the 100 table", s.row_of("t100").prize_label.text == "Win 270")
	s.set_wallet(5, 2500)
	check("picker: 4 players at 500: 'Win 1,350'", s.row_of("t500").prize_label.text == "Win 1,350" and s.row_of("t500").modulate.a == 1.0)
	var picked := []
	s.table_changed.connect(func(id): picked.append(id))
	s._on_row("t500")
	check("picker: a tap on a playable table picks it", s.table == "t500" and picked == ["t500"] and s.row_of("t500").on and not s.row_of("t100").on)
	s.set_wallet(1, 2500)
	check("picker: the level dropping out of reach puts the pick back on Practice", s.table == "practice" and picked.back() == "practice")
	s._on_row("t2k")
	check("picker: a locked table says what unlocks it and stays unpicked", s.table == "practice" and s.note_label.visible and s.note_label.text.contains("level 6"), s.note_label.text)
	s.set_wallet(20, 300)
	s._on_row("t500")
	check("picker: a table you can't pay says what it costs", s.table == "practice" and s.note_label.text.contains("500 coins"), s.note_label.text)
	var broke := []
	s.broke_requested.connect(func(): broke.append(1))
	s.set_wallet(20, 40)
	s._on_row("t100")
	check("picker: under 100 coins a table you can't pay asks for the broke popup", broke.size() == 1)
	var found := []
	s.find.connect(func(n): found.append(n))
	s.find_button.pressed.emit()
	check("picker: Find players on Practice", found == [4] and s.table == "practice", found)
	s.set_tables({ok = true, level = 20, tables = [{id = "t100", unlocked = true, affordable = true}]})
	check("picker: the server's answer unlocks the 100 table for a poor local copy", s.row_of("t100").modulate.a == 1.0)
	s.select_table("t100")
	check("picker: …and it can be picked", s.table == "t100")
	s.free()
	var s2 := QuickSheet.new("sl", 2, "t10k")
	s2.set_wallet(1, 99999)
	check("picker: a remembered table that is still locked falls back to Practice", s2.table == "practice")
	s2.free()
	check("copy: coins / locked queue errors", QuickSheet.fail_text("coins").contains("Not enough coins") and QuickSheet.fail_text("locked", {level = 6}).contains("level 6")
		and QuickSheet.fail_text("maintenance").contains("maintenance"))

func _url_and_queue() -> void:
	check("url: Practice is the default and has no table", NetQuick.queue_url("wss://x.dev/", "sl", 4) == "wss://x.dev/v1/quick/ws?game=sl&players=4"
		and NetQuick.queue_url("wss://x.dev", "sl", 4, "practice") == "wss://x.dev/v1/quick/ws?game=sl&players=4")
	check("url: a coin table", NetQuick.queue_url("wss://x.dev/", "ludo", 2, "t500") == "wss://x.dev/v1/quick/ws?game=ludo&players=2&table=t500")
	check("url: an unknown table is left out", NetQuick.queue_url("wss://x.dev", "ludo", 2, "t3") == "wss://x.dev/v1/quick/ws?game=ludo&players=2")
	var hub := NetFake.Hub.new(5)
	var c := _client(hub, "Ana")
	var q := NetQuick.new(c)
	var fails := []
	q.failed.connect(func(code, msg): fails.append([code, msg]))
	_tree().root.add_child(c)
	_tree().root.add_child(q)
	q.search("ludo", 2, "t100")
	_pump([c, q])
	check("queue: the table goes in the socket's URL and the entry is taken at hello", q.table == "t100" and (q.transport as NetFake.Pipe).url.ends_with("&table=t100")
		and hub.mm.coins == 4900 and hub.mm.queue("ludo", 2, "t100").size() == 1 and q.status == "queued")
	check("queue: another table's queue is separate", hub.mm.queue("ludo", 2).is_empty())
	q.cancel()
	_pump([c, q])
	check("queue: leaving the queue gives the entry back", hub.mm.coins == 5000 and hub.mm.refunds == 1)
	hub.mm.player_level = 1
	q.search("ludo", 2, "t500")
	_pump([c, q])
	check("queue: error locked comes back with its level (and no entry is taken)", fails.size() == 1 and fails[0][0] == "locked" and q.fail_info.get("level") == 3
		and hub.mm.coins == 5000 and q.status == "failed", [fails, q.fail_info])
	hub.mm.player_level = 5
	hub.mm.coins = 60
	q.search("ludo", 2, "t100")
	_pump([c, q])
	check("queue: error coins comes back with what is short", fails.size() == 2 and fails[1][0] == "coins" and q.fail_info.get("short") == 40 and hub.mm.coins == 60, [fails, q.fail_info])
	hub.mm.coins = 5000
	q.search("ludo", 2)
	_pump([c, q])
	check("queue: Practice takes no entry", q.status == "queued" and hub.mm.coins == 5000)
	q.cancel()
	q.free()
	c.free()

func _client(hub: Variant, name: String) -> NetClient:
	var c := NetClient.new()
	c.use_save = false
	c.prefs = {}
	c.url_base = "ws://fake"
	var sess := "s-" + name
	c.session_fn = func() -> String: return sess
	c.profile_fn = func() -> Dictionary: return {name = name, avatar = "pawn-blue", frame = "classic"}
	c.make_transport = hub.transport_factory()
	c.http_fn = hub.http
	return c

func _pump(cs: Array, times := 4) -> void:
	for k in times:
		for c in cs:
			c._process(0.0)

## Online's flow: the broke popup, the picker, the errors.
class FakeApp extends Node:
	var sheet_layer := Control.new()
	var ui_root := Control.new()
	var screen := "home"
	func _init() -> void:
		sheet_layer.size = Vector2(390, 844)
		add_child(sheet_layer)
		add_child(ui_root)
	func go_home() -> void:
		screen = "home"

func _online() -> void:
	var hub := NetFake.Hub.new(9)
	var app := FakeApp.new()
	_tree().root.add_child(app)
	var c := _client(hub, "Ana")
	var o := Online.new(app, c)
	var coins := [50]
	o.coins_fn = func() -> int: return coins[0]
	o.level_fn = func() -> int: return 1
	app.add_child(o)
	o.open_quick("ludo")
	check("broke: under 100 coins Quick match opens the 'Out of coins' sheet first", is_instance_valid(o.broke_sheet) and o.quick_sheet == null and o.broke_sheet.title_label.text == "Out of coins")
	o.broke_sheet.practice_pressed.emit()
	check("broke: Play Practice instead opens the picker on Practice", is_instance_valid(o.quick_sheet) and o.quick_sheet.table == "practice")
	o.quick_sheet.close()
	o.quick_sheet = null
	o.broke_sheet.queue_free()
	o.broke_sheet = null
	coins[0] = 100
	o.open_quick("ludo")
	check("broke: 100 coins is enough: the picker opens", o.broke_sheet == null and is_instance_valid(o.quick_sheet))
	check("online: the picker is told your coins and level", o.quick_sheet.coins == 100 and o.quick_sheet.level == 1)
	o.quick_sheet.select_table("t100")
	o.quick_sheet.find.emit(2)
	_pump([c, o.quick_q])
	check("online: the picked table is queued, remembered and kept for Play again", o.state == "searching" and o.quick_q.table == "t100"
		and o.net.prefs.quick_table == "t100" and o.quick_cfg == {game = "ludo", players = 2, table = "t100"} and hub.mm.coins == 4900)
	o.cancel_quick()
	_pump([c, o.quick_q])
	check("online: Cancel gives the entry back", hub.mm.coins == 5000 and o.state == "idle")
	# the table refuses us: coins
	hub.mm.coins = 60
	coins[0] = 60
	o.quick_sheet.set_wallet(1, 5000)
	o.quick_sheet.set_error("")
	o.quick_sheet.select_table("t100")
	o.quick_sheet.find.emit(2)
	_pump([c, o.quick_q], 6)
	check("online: error coins: the picker says so, the table greys out and the broke popup opens", o.state == "idle" and o.quick_sheet.stage == "error"
		and o.quick_sheet.note_label.text.contains("Not enough coins") and o.quick_sheet.table == "practice" and is_instance_valid(o.broke_sheet))
	o.broke_sheet.queue_free()
	o.broke_sheet = null
	hub.mm.player_level = 1
	coins[0] = 5000
	hub.mm.coins = 5000
	o.quick_sheet.set_wallet(9, 5000)                     # (our copy thinks level 9: the server knows better)
	o.quick_sheet.select_table("t500")
	o.quick_sheet.find.emit(2)
	_pump([c, o.quick_q], 6)
	check("online: error locked: 'unlocks at level 3' in the picker", o.quick_sheet.stage == "error" and o.quick_sheet.note_label.text.contains("level 3"), o.quick_sheet.note_label.text)
	o.quick_sheet.close()
	app.queue_free()
	_tree().root.remove_child(app)

func _broke() -> void:
	var acc := FakeAcc.new()
	var s := BrokeSheet.new()
	s.acc_fn = func(): return acc
	s.ad_ok_fn = func() -> bool: return false
	s.coins_fn = func() -> int: return 40
	s.refresh()
	check("broke: 'Daily bonus +300' is on", not s.bonus_button.disabled and s._bonus_text.text == "Daily bonus +300")
	check("broke: no video when none can run here", not s.video_button.visible)
	s.set_bonus({available = false, next_at = int(Time.get_unix_time_from_system()) + 5 * 3600 + 120, amount = 300})
	check("broke: used today: disabled with the time left", s.bonus_button.disabled and s._bonus_text.text.contains("5h"), s._bonus_text.text)
	s.set_bonus({available = true, next_at = 0, amount = 300})
	var balance := [40]
	s.coins_fn = func() -> int: return balance[0]
	var topped := []
	s.topped_up.connect(func(c): topped.append(c))
	s.bonus_button.pressed.emit()
	check("broke: the claim goes to the server", acc.claims == 1 and not bool(s.bonus.available))
	check("broke: still short: the sheet stays (the other ways are open)", topped.is_empty())
	s.set_bonus({available = true, next_at = 0, amount = 300})
	balance[0] = 340
	s.bonus_button.pressed.emit()
	check("broke: 100 coins or more after a top-up: topped_up(coins)", topped == [340], topped)
	s.set_bonus({available = true, next_at = 0, amount = 300})
	acc.claim_answer = {ok = false, error = "claimed", next_at = int(Time.get_unix_time_from_system()) + 7200}
	s.bonus_button.pressed.emit()
	check("broke: 'already claimed' turns the button off", s.bonus_button.disabled and not bool(s.bonus.available))
	var pr := []
	s.practice_pressed.connect(func(): pr.append(1))
	s.practice_button.pressed.emit()
	check("broke: Play Practice instead", pr.size() == 1)
	var s2 := BrokeSheet.new()
	s2.ad_ok_fn = func() -> bool: return true
	s2.refresh()
	check("broke: the video button when ads can run", s2.video_button.visible)
	check("broke: its words", s2.body.find_child("Video", true, false) != null and _all_text(s2.video_button).contains("Watch a video: +500 coins"))
	s2.free()
	s.free()
	# a video that is granted
	var s3 := BrokeSheet.new()
	var fl := FakeFlow.new()
	fl.answer = {ok = true, info = {kind = "refill", amount = 500}}
	s3.flow = fl
	s3.add_child(fl)
	s3.ad_ok_fn = func() -> bool: return true
	var bal := [30]
	s3.coins_fn = func() -> int: return bal[0]
	var t3 := []
	s3.topped_up.connect(func(c): t3.append(c))
	_tree().root.add_child(s3)
	bal[0] = 530
	s3.video_button.pressed.emit()
	check("broke: the refill video asks AdFlow for 'refill' and tops up", fl.asked == [["refill", ""]] and t3 == [530], [fl.asked, t3])
	s3.queue_free()

func _all_text(n: Node) -> String:
	var t := ""
	if n is Label:
		t += (n as Label).text + " "
	if n is Button:
		t += (n as Button).text + " "
	for ch in n.get_children():
		t += _all_text(ch)
	return t

func _result() -> void:
	var st := [
		{color = 0, name = "You", kind = "you", place = 1, finished = true, progress = 1.0},
		{color = 2, name = "Bo", kind = "human", avatar = "pawn-green", frame = "classic", place = 2, finished = false, progress = 0.4},
	]
	var base := {game = "ludo", online = true, host = true, standings = st, human_won = true, xp_before = 10, xp_after = 110, ads = true}
	var win := base.duplicate()
	win.reward = 180
	win.table = {tier = "t100", entry = 100, payout = 180, match_id = "K7QX2M-1"}
	var r := ResultScreen.new(win)
	check("result: a coin-table prize shows as the coins tile 'Prize'", r.is_coin_table() and r.table_payout() == 180 and r.coins != null and r.table_note == null
		and _all_text(r._rewards).to_lower().contains("prize"))
	check("result: a prize and a video: 'Double it with a video'", r.double_button != null and r.double_button.text == "Double it with a video")
	var fl := FakeFlow.new()
	r.flow = fl
	var extra := []
	r.doubled.connect(func(n): extra.append(n))
	r.double_button.pressed.emit()
	check("result: the double asks AdFlow for 'double' with the match id", fl.asked == [["double", "K7QX2M-1"]], fl.asked)
	check("result: …a granted video says Doubled! with the extra coins", r.double_button.text == "Doubled!" and r.double_button.disabled and extra == [180], [r.double_button.text, extra])
	r.free()
	var r2 := ResultScreen.new(win)
	var fl2 := FakeFlow.new()
	fl2.answer = {ok = false, info = {kind = "double", error = "no_fill", text = "No video right now, try again in a minute."}}
	r2.flow = fl2
	r2.double_button.pressed.emit()
	check("result: a video that didn't run: the button comes back", not r2.double_button.disabled and r2.double_button.text == "Double it with a video")
	r2.free()
	var noads := win.duplicate(true)
	noads.ads = false
	var r3 := ResultScreen.new(noads)
	check("result: no video available: no double button", r3.double_button == null and r3.coins != null)
	r3.free()
	var lost := base.duplicate(true)
	lost.reward = 0
	lost.human_won = false
	lost.table = {tier = "t100", entry = 100, payout = 0, match_id = "K7QX2M-1"}
	var r4 := ResultScreen.new(lost)
	check("result: a loss says 'Entry 100 lost', no coins tile, no double", r4.table_note != null and r4.table_note.text == "Entry 100 lost" and r4.coins == null and r4.double_button == null)
	r4.free()
	var prac := base.duplicate(true)
	prac.reward = 50
	prac.table = {tier = "practice", entry = 0, payout = 0, match_id = "K7QX2M-1"}
	var r5 := ResultScreen.new(prac)
	check("result: Practice as before (Coins tile, no table lines)", not r5.is_coin_table() and r5.coins != null and r5.double_button == null and r5.table_note == null
		and _all_text(r5._rewards).to_lower().contains("coins"))
	r5.free()
	var friends := base.duplicate(true)
	friends.reward = 150
	var r6 := ResultScreen.new(friends)
	check("result: a friends' room has no table", not r6.is_coin_table() and r6.double_button == null)
	r6.free()
