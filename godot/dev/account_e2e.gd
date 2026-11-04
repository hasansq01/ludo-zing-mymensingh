extends SceneTree
## Dev: the account client against a real server (guest -> import -> buy -> daily -> spin -> free -> claims ->
## leaderboard -> Google). Prints PASS / FAIL per step and exits 1 on any failure. Never touches user://save.json
## (the Account here keeps its own prefs and profile) and never writes a save.
##   cd server && npx wrangler d1 migrations apply ludo-zing-admin --local && npx wrangler dev --port 8792 --ip 127.0.0.1
##   godot --headless --path godot -s res://dev/account_e2e.gd -- [--net=ws://127.0.0.1:8792]

var _pass := 0
var _fail := 0

func _check(name: String, ok: bool, got: Variant = null) -> void:
	if ok:
		_pass += 1
		print("PASS  ", name)
	else:
		_fail += 1
		print("FAIL  ", name, "  got ", JSON.stringify(got))

func _initialize() -> void:
	_run()

func _run() -> void:
	await process_frame
	var url := "ws://127.0.0.1:8792"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--net="):
			url = a.trim_prefix("--net=")
	print("server: ", url)
	var acc := Account.new()
	acc.use_save = false
	acc.prefs = {}
	acc.profile_own = {name = "E2E %d" % (randi() % 1000), coins = 8000, xp = 300, stats = {played = 4, wins = 2, bestStreak = 2},
		rooms = ["night", "cafe"], dice_owned = ["classic"]}
	acc.url_base = url
	root.add_child(acc)
	var changed := [0]
	acc.changed.connect(func(_p: Dictionary): changed[0] += 1)

	var ok: bool = await acc.sign_in_guest()
	_check("guest: signs in (POST /v1/auth/guest)", ok and acc.has_session() and Account.session() == acc._session, acc.account)
	_check("guest: the account is a guest", acc.is_guest() and str(acc.account.get("id", "")) != "", acc.account)
	_check("guest: the local profile was imported once", int(acc.profile_own.get("coins", 0)) == 8000 and int(acc.profile_own.get("xp", 0)) == 300 and bool(acc.prefs.get("net_imported", false)), acc.profile_own)
	_check("guest: the server profile has the full shape", acc.profile_own.get("rooms") is Array and acc.profile_own.get("daily") is Dictionary and acc.profile_own.has("last_free"), acc.profile_own.keys())
	var sess1: String = acc._session

	var room := _cheapest_room(int(acc.profile_own.coins))
	var before := int(acc.profile_own.coins)
	var r: Dictionary = await acc.buy("room", room.id)
	_check("shop: buy %s for %d" % [room.id, room.price], r.get("ok", false) and int(acc.profile_own.coins) == before - int(room.price)
		and (acc.profile_own.rooms as Array).has(room.id), r)
	r = await acc.buy("room", room.id)
	_check("shop: buying it again is refused (owned)", not r.get("ok", false) and r.get("error") == "owned", r)
	r = await acc.equip("room", "cafe")
	_check("shop: equip a free room", r.get("ok", false) and acc.profile_own.room == "cafe", r)

	before = int(acc.profile_own.coins)
	r = await acc.daily()
	_check("daily: claim", r.get("ok", false) and int(r.coins) > 0 and int(acc.profile_own.coins) >= before + int(r.coins) - 0 and int(r.day) == 1, r)
	r = await acc.daily()
	_check("daily: a second claim is refused (claimed)", not r.get("ok", false) and r.get("error") == "claimed", r)
	before = int(acc.profile_own.coins)
	r = await acc.spin()
	_check("spin: the server draws a prize", r.get("ok", false) and int(r.prize) > 0 and int(r.index) >= 0 and int(r.index) < 8 and int(acc.profile_own.coins) == before + int(r.prize), r)
	before = int(acc.profile_own.coins)
	r = await acc.free_coins()
	_check("free coins: claim", r.get("ok", false) and int(acc.profile_own.coins) == before + int(r.coins), r)
	r = await acc.free_coins()
	_check("free coins: cooldown", not r.get("ok", false) and r.get("error") == "cooldown", r)

	# claims: an offline Ludo win, replayed with the same id, then an S&L loss
	before = int(acc.profile_own.coins)
	var id := acc.report_match({game = "ludo", mode = "cpu", result = "win", players = ["human", "cpu", "cpu", "cpu"], duration_s = 300, pairs = 1})
	await _until(func(): return acc.pending().is_empty(), 5.0)
	_check("claims: a Ludo win is paid (+%d)" % LudoRules.WIN_REWARD, int(acc.last_claim.get("coins", -1)) == LudoRules.WIN_REWARD and int(acc.profile_own.coins) == before + LudoRules.WIN_REWARD and acc.last_claim.get("id") == id, acc.last_claim)
	var coins_now := int(acc.profile_own.coins)
	acc.pending().append({id = id, game = "ludo", mode = "cpu", result = "win", players = ["human", "cpu", "cpu", "cpu"], duration_s = 300})
	await acc.flush_claims()
	_check("claims: the same id again is a duplicate (no second payment)", acc.last_claim.get("duplicate") == true and int(acc.profile_own.coins) == coins_now, acc.last_claim)
	acc.report_match({game = "ludo", mode = "cpu", result = "loss", players = ["human", "cpu", "cpu", "cpu"], duration_s = 10})
	await _until(func(): return acc.pending().is_empty(), 5.0)
	_check("claims: a 10 s match is limited (too_short)", acc.last_claim.get("limited") == true and acc.last_claim.get("reason") == "too_short" and Account.claim_note(acc.last_claim) == "Too short to count", acc.last_claim)
	acc.report_match({game = "sl", mode = "cpu", result = "loss", players = 2, duration_s = 120, rolls = [1, 2, 3], need_one = true})
	await _until(func(): return acc.pending().is_empty(), 5.0)
	_check("claims: an S&L loss is accepted", acc.last_claim.get("ok") == true and acc.last_claim.get("limited") == false, acc.last_claim)

	# the profile name goes through PATCH /v1/me
	r = await acc.push_identity({name = "E2E Zed"})
	_check("identity: PATCH /v1/me renames", r.get("ok", false) and acc.profile_own.name == "E2E Zed", r)
	ok = await acc.refresh_me()
	_check("me: GET /v1/me returns the account and profile", ok and acc.account.has("completed_matches"), acc.account)

	# leaderboards
	for combo in [["xp", "all"], ["xp", "week"], ["wins", "all"], ["wins", "week"]]:
		r = await acc.leaderboard(combo[0], combo[1])
		_check("leaderboard %s / %s: ok with rows array and my row" % combo, r.get("ok", false) and r.get("top") is Array and r.get("me") is Dictionary, r)
	r = await acc.leaderboard("xp", "all")
	var me: Dictionary = r.get("me", {})
	_check("leaderboard: my row says listed / not listed", me.has("listed") and int(r.get("min_matches", 0)) == 3, me)

	# Google: the Play Games stub is unavailable here; the server answers 503 without its secrets
	r = await acc.link_google()
	_check("google: unavailable off Android", r.get("error") == "unavailable", r)
	var g: Dictionary = await acc.request(HTTPClient.METHOD_POST, "/v1/auth/google", {server_auth_code = "x"})
	_check("google: the server says not configured (503) or rejects the code (401)", int(g.status) in [503, 401, 502], g)

	# sessions: unchanged unless the server renewed it; a bad one is refused and dropped
	_check("session: kept across the run", acc._session == sess1 or acc._session.begins_with(str(acc.account.id)), acc._session)
	acc._session = "bogus.1.sig"
	r = await acc.buy("room", "nope")
	_check("session: a bad session is refused and cleared", not r.get("ok", false) and not acc.has_session(), r)
	ok = await acc.sign_in_guest()
	_check("session: the same device signs in again to the same account", ok and acc.has_session() and int(acc.profile_own.coins) > 0, acc.account)
	_check("wallet: the profile changed %d times along the way" % changed[0], changed[0] >= 10, changed)

	print("E2E: %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func _cheapest_room(coins: int) -> Dictionary:
	var best := {}
	for rm: Dictionary in Catalog.rooms():
		var price := int(rm.get("price", 0))
		if price > 0 and price <= coins and (best.is_empty() or price < int(best.price)):
			best = {id = str(rm.id), price = price}
	return best

func _until(cond: Callable, sec: float) -> void:
	var t := 0.0
	while t < sec and not cond.call():
		await create_timer(0.1).timeout
		t += 0.1
