extends "res://tests/test_suite.gd"
## Account (scripts/net/account.gd) against a fake server: guest auth and the one-time import, the session and its
## refresh, the wallet reconciling the local profile, offline messages, the claims queue (offline, flush, idempotent
## ids, limits), Google sign-in with both conflict flows, the leaderboard call, and Save's null-safe repair.
## Nothing here touches user://save.json or the network (Account.use_save is false, http_fn is the fake).

const Fake := preload("res://tests/fake_accounts.gd")

var _done := false

func run() -> void:
	_all()
	check("account: the suite ran to the end (nothing suspended for real)", _done)

func _all() -> void:
	await _guest()
	await _session()
	await _offline()
	await _wallet()
	await _claims()
	await _google()
	await _leaderboard()
	_save_repair()
	_text()
	_done = true

func make(fake: Fake, prefs := {}) -> Account:
	var a := Account.new()
	a.use_save = false
	a.prefs = prefs
	a.profile_own = {name = "Zed", coins = 8000, xp = 50, stats = {played = 3}}
	a.url_base = "ws://fake"
	a.http_fn = fake.http
	return a

func _guest() -> void:
	var f := Fake.new()
	var a := make(f)
	var changed := []
	a.changed.connect(func(p: Dictionary): changed.append(p.coins))
	var live := a.profile_own
	var ok: bool = await a.sign_in_guest()
	check("guest: signs in", ok and a.has_session() and Account.session() == "" and a._session == Fake.SESSION)
	var call: Dictionary = f.last("/v1/auth/guest")
	check("guest: POST with the device id and the local profile as import", call.method == HTTPClient.METHOD_POST and str(call.body.pid).length() >= 16
		and call.body.has("import") and call.body.import.coins == 8000 and call.body.import.name == "Zed", call.body)
	check("guest: the guest call carries no session", call.session == "")
	check("guest: session saved in prefs", a.prefs.net_session == Fake.SESSION and a.prefs.net_imported == true)
	check("guest: the server profile replaced the local one, in place", is_same(live, a.profile_own) and a.profile_own.coins == 8000 and a.profile_own.id == "LZM-TEST-0001", a.profile_own)
	check("guest: changed(profile) was emitted once", changed == [8000], changed)
	check("guest: the account record is kept and is a guest", a.is_guest() and a.account.id == "acc1")
	# a second launch: the same prefs, no import any more
	var a2 := make(f, a.prefs)
	a2.start()
	check("guest: the kept session is usable at once", a2.has_session())
	check("guest: the import goes once only", f.imports.size() == 1 and not f.last("/v1/auth/guest").body.has("import"), f.calls)
	check("guest: the same device id both times", f.calls[0].body.pid == f.calls[f.calls.size() - 1].body.pid)
	a.free()
	a2.free()

func _session() -> void:
	var f := Fake.new()
	var a := make(f)
	await a.sign_in_guest()
	var n := []
	a.signed_in_changed.connect(func(): n.append(Account._inst == null))
	f.refresh_session = "acc1.4102444801.new"
	var r: Dictionary = await a.buy("room", "neon")
	check("session: the X-Session header replaces the session", a._session == "acc1.4102444801.new" and a.prefs.net_session == "acc1.4102444801.new", a._session)
	check("session: signed_in_changed fired for it", n.size() == 1, n)
	check("session: wallet calls send the session as bearer", f.last("/v1/shop/buy").session == Fake.SESSION)
	await a.daily()
	check("session: the next call uses the fresh one", f.last("/v1/rewards/daily").session == "acc1.4102444801.new")
	# a rejected session is dropped and a guest sign-in is scheduled
	f.drop_session = true
	var d: Dictionary = await a.daily()
	check("session: 401 clears the session", not a.has_session() and not d.ok and d.error == "unauthorized", d)
	check("session: ...and a retry is scheduled", a._retry_left > 0.0)
	check("session: the room client sees no session", a._session == "")
	a.free()
	# Account.session() follows the current account
	var b := make(f)
	Account.set_instance(b)
	b._session = "x.1.y"
	check("session: Account.session() reads the current account", Account.session() == "x.1.y" and Account.wallet_active())
	Account.set_instance(null)
	check("session: no account: empty session, wallet inactive", Account.session() == "" and not Account.wallet_active())
	b.free()

func _offline() -> void:
	var f := Fake.new()
	f.online = false
	var a := make(f)
	var ok: bool = await a.sign_in_guest()
	check("offline: sign-in fails quietly", not ok and not a.has_session())
	check("offline: a retry with backoff is scheduled", a._retry_left == float(Account.BACKOFF[0]) and a._retry == 1, a._retry_left)
	await a.sign_in_guest()
	check("offline: the backoff grows", a._retry_left == float(Account.BACKOFF[1]), a._retry_left)
	var before := a.profile_own.duplicate(true)
	var r: Dictionary = await a.buy("room", "neon")
	check("offline: buy says offline", not r.ok and r.error == "offline", r)
	r = await a.daily()
	check("offline: daily says offline", not r.ok and r.error == "offline")
	r = await a.spin()
	check("offline: spin says offline", not r.ok and r.error == "offline")
	r = await a.free_coins()
	check("offline: free coins say offline", not r.ok and r.error == "offline")
	r = await a.claim_ach("first")
	check("offline: achievement claim says offline", not r.ok and r.error == "offline")
	r = await a.equip("room", "cafe")
	check("offline: equip says offline", not r.ok and r.error == "offline")
	check("offline: nothing was granted locally", a.profile_own == before, a.profile_own)
	check("offline: the friendly messages", Account.offline_text("claim") == "Connect to the internet to claim."
		and Account.offline_text("buy") == "Connect to the internet to buy." and Account.error_text("offline", "spin") == "Connect to the internet to spin.")
	# the connection returns: the next try signs in
	f.online = true
	ok = await a.sign_in_guest()
	check("offline: back online it signs in and the retry clears", ok and a._retry == 0 and a._retry_left < 0.0)
	a.free()

func _wallet() -> void:
	var f := Fake.new()
	var a := make(f)
	await a.sign_in_guest()
	var live := a.profile_own
	var r: Dictionary = await a.buy("room", "neon")
	check("wallet: buy ok", r.ok and r.price == 3000, r)
	check("wallet: the profile was reconciled in place", is_same(live, a.profile_own) and a.profile_own.coins == 5000 and a.profile_own.rooms.has("neon") and a.profile_own.room == "neon", a.profile_own)
	check("wallet: the buy body is {kind, id, currency}", f.last("/v1/shop/buy").body == {kind = "room", id = "neon", currency = "coins"})
	r = await a.buy("room", "nope")
	check("wallet: unknown item", not r.ok and r.error == "unknown")
	f.profile.coins = 100
	r = await a.buy("dice", "gold")
	check("wallet: too poor -> coins error with the shortfall", not r.ok and r.error == "coins" and int(r.short) == 800, r)
	check("wallet: the failed buy refreshed our copy (GET /v1/me)", a.profile_own.coins == 100, a.profile_own)
	r = await a.daily()
	check("wallet: daily gives the coins and normalises nulls", r.ok and r.coins == 100 and r.dice == "" and r.char == "" and r.day == 1, r)
	check("wallet: ...and the profile has them", a.profile_own.coins == 200 and a.profile_own.daily.streak == 1)
	r = await a.daily()
	check("wallet: a second daily is refused", not r.ok and r.error == "claimed")
	var seen := []
	a.changed.connect(func(p: Dictionary): seen.append(p.coins))
	r = await a.spin()
	check("wallet: spin returns the server's index and prize", r.ok and r.index == 3 and r.prize == 500, r)
	check("wallet: the spin's profile is applied", a.profile_own.coins == 700)
	r = await a.free_coins()
	check("wallet: free coins", r.ok and r.coins == 300 and a.profile_own.coins == 1000)
	r = await a.claim_ach("first")
	check("wallet: achievement claim", r.ok and a.profile_own.claimed.has("first") and a.profile_own.coins == 1200, r)
	r = await a.equip("room", "cafe")
	check("wallet: equip", r.ok and a.profile_own.room == "cafe")
	check("wallet: every answer with a profile emitted changed", seen.size() >= 4, seen)
	# identity: only what differs goes to PATCH /v1/me
	a.profile_own.name = "Zed Two"
	r = await a.push_identity()
	check("wallet: a new name is PATCHed", r.ok and f.last("/v1/me").method == HTTPClient.METHOD_PATCH and f.last("/v1/me").body == {name = "Zed Two"}, f.last("/v1/me"))
	var n := f.count("/v1/me")
	r = await a.push_identity()
	check("wallet: nothing changed, nothing sent", r.ok and f.count("/v1/me") == n)
	a.free()

func match_info(result := "win") -> Dictionary:
	return {game = "ludo", mode = "cpu", result = result, players = ["human", "cpu", "cpu", "cpu"], duration_s = 300, pairs = 2}

func _claims() -> void:
	# offline: queued, kept in prefs, played on reconnect
	var f := Fake.new()
	f.online = false
	var a := make(f, {net_imported = true})
	var answers := []
	a.claim_answered.connect(func(id: String, ans: Dictionary): answers.append([id, ans.coins]))
	var id1 := a.report_match(match_info())
	var id2 := a.report_match({game = "sl", mode = "cpu", result = "win", duration_s = 90, rolls = [1, 6, 3], need_one = true})
	check("claims: queued offline with ids", a.pending().size() == 2 and id1 != id2 and id1.length() >= 8 and a.prefs.pending_claims.size() == 2)
	check("claims: the id is URL-safe and 8-64 long", id1.length() <= 64 and id1.to_lower() == id1 and not id1.contains(" "), id1)
	check("claims: the S&L claim keeps rolls and need_one", a.pending()[1].rolls == [1, 6, 3] and a.pending()[1].need_one == true)
	check("claims: nothing sent without a connection", f.count("/v1/claims") == 0)
	f.online = true
	await a.sign_in_guest()
	check("claims: flushed on reconnect, oldest first", f.count("/v1/claims") == 2 and f.calls[f.calls.size() - 2].body.id == id1 and f.last("/v1/claims").body.id == id2, f.calls)
	check("claims: the queue is empty", a.pending().is_empty() and answers == [[id1, 150], [id2, 150]], answers)
	check("claims: the server profile includes the granted coins", a.profile_own.coins == 5300, a.profile_own)
	check("claims: the Ludo claim body", f.calls[f.calls.size() - 2].body.players == ["human", "cpu", "cpu", "cpu"] and f.calls[f.calls.size() - 2].body.result == "win")
	# a connection that drops mid-queue keeps the rest, and a retry reuses the id
	var f2 := Fake.new()
	var b := make(f2)
	await b.sign_in_guest()
	var id := b.report_match(match_info("loss"))
	check("claims: online it is sent at once", f2.count("/v1/claims") == 1 and b.pending().is_empty())
	f2.online = false
	var id3 := b.report_match(match_info())
	check("claims: a failed send stays queued", b.pending().size() == 1 and b.pending()[0].id == id3)
	f2.online = true
	await b.flush_claims()
	check("claims: the retry sends the same id", f2.last("/v1/claims").body.id == id3 and b.pending().is_empty())
	# idempotency: a lost answer, the same id again
	var coins_before := int(b.profile_own.coins)
	b.pending().append({id = id3, game = "ludo", mode = "cpu", result = "win", players = ["human", "cpu", "cpu", "cpu"], duration_s = 300})
	await b.flush_claims()
	check("claims: a repeated id is a duplicate: no second payment", b.profile_own.coins == coins_before and b.last_claim.get("duplicate") == true and b.pending().is_empty(), b.last_claim)
	# limits: the answer tells, the note is subtle
	f2.limit_next = "daily_coins"
	b.report_match(match_info())
	check("claims: a limited answer is kept", b.last_claim.limited == true and b.last_claim.reason == "daily_coins")
	check("claims: the note for a daily limit", Account.claim_note(b.last_claim) == "Daily limit reached")
	check("claims: other notes", Account.claim_note({limited = true, reason = "hourly"}) == "Too many matches this hour"
		and Account.claim_note({limited = true, reason = "too_short"}) == "Too short to count" and Account.claim_note({limited = false}) == "")
	# a malformed claim (400) is dropped, not retried forever
	b.pending().append({id = "bad", game = "ludo"})
	await b.flush_claims()
	check("claims: a rejected claim leaves the queue", b.pending().is_empty())
	# the queue is capped
	var c := make(Fake.new())
	c.enabled = false
	for k in Account.MAX_PENDING + 5:
		c.report_match(match_info())
	check("claims: the queue keeps the newest %d" % Account.MAX_PENDING, c.pending().size() == Account.MAX_PENDING)
	# claims queued before the first import are in the import: not sent twice
	var f3 := Fake.new()
	var d := make(f3)
	d.enabled = false
	d.report_match(match_info())
	d.enabled = true
	await d.sign_in_guest()
	check("claims: queued before the import: dropped once the import is accepted", f3.count("/v1/claims") == 0 and d.pending().is_empty(), f3.calls)
	a.free(); b.free(); c.free(); d.free()

func _google() -> void:
	var f := Fake.new()
	var a := make(f)
	var pg := Fake.FakePG.new()
	a.pg_factory = func(): return pg
	await a.sign_in_guest()
	check("google: available through the factory", a.google_available())
	var r: Dictionary = await a.link_google()
	check("google: signs in, asks a code, links", r.ok and r.linked and pg.asked_codes == 1 and f.last("/v1/auth/google").body.server_auth_code == "CODE-1", r)
	check("google: the account is no longer a guest and has the Google name", not a.is_guest() and a.google_name() == "Zing Player")
	check("google: the guest's device id goes with it", str(f.last("/v1/auth/google").body.pid).length() >= 16)
	# failures
	var f2 := Fake.new()
	var b := make(f2)
	var pg2 := Fake.FakePG.new()
	b.pg_factory = func(): return pg2
	await b.sign_in_guest()
	pg2.sign_in_error = "canceled"
	r = await b.link_google()
	check("google: backing out is quiet", not r.ok and r.error == "canceled" and Account.google_error_text(r.error) == "" and f2.count("/v1/auth/google") == 0, r)
	pg2.sign_in_error = ""
	pg2.code_error = "no_web_client_id"
	r = await b.link_google()
	check("google: no auth code, no call", not r.ok and r.error == "no_web_client_id" and f2.count("/v1/auth/google") == 0, r)
	pg2.code_error = ""
	f2.google_status = 503
	f2.google_body = {error = "google_not_configured"}
	r = await b.link_google()
	check("google: 503 google_not_configured", not r.ok and r.error == "google_not_configured" and Account.google_error_text(r.error).contains("isn’t switched on"), r)
	pg2.available = false
	r = await b.link_google()
	check("google: unavailable off Android", not r.ok and r.error == "unavailable")
	pg2.available = true
	# conflict: keep this device's progress
	var f3 := Fake.new()
	var c := make(f3)
	var pg3 := Fake.FakePG.new()
	c.pg_factory = func(): return pg3
	await c.sign_in_guest()
	var here := {name = "Zed", avatar = "pawn-red", level = 2, coins = 5000, wins = 1}
	var there := {name = "Zara", avatar = "pawn-blue", level = 9, coins = 40000, wins = 55}
	f3.google_status = 409
	f3.google_body = {error = "conflict", conflict = {here = here, there = there}, ticket = "T1"}
	var raised := []
	c.conflict_raised.connect(func(cf: Dictionary): raised.append(cf))
	r = await c.link_google()
	check("conflict: 409 raises the decision", not r.ok and r.error == "conflict" and raised.size() == 1 and raised[0].kind == "conflict"
		and raised[0].here.name == "Zed" and raised[0].there.level == 9 and raised[0].ticket == "T1", raised)
	c.report_match(match_info())
	f3.resolve_body = {account = {id = "acc1", guest = false, google_name = "Zing Player"}, session = Fake.SESSION, profile = Fake.base_profile(), linked = true, merged = "acc9"}
	r = await c.resolve_conflict("here")
	check("conflict: keep this device -> resolve with the ticket and keep=here", r.ok and f3.last("/v1/auth/google/resolve").body.keep == "here"
		and f3.last("/v1/auth/google/resolve").body.ticket == "T1" and c.conflict.is_empty(), f3.last("/v1/auth/google/resolve"))
	check("conflict: the account is linked now", not c.is_guest())
	# conflict: use the Google account's progress -> switched, queued claims are dropped
	var p2 := Fake.base_profile()
	p2.coins = 40000
	p2.name = "Zara"
	f3.google_status = 409
	await c.link_google()
	c.pending().append({id = "queued-claim-1", game = "ludo"})
	f3.resolve_body = {account = {id = "acc9", guest = false, google_name = "Zing Player"}, session = "acc9.4102444800.sig", profile = p2, switched = true, created = false}
	r = await c.resolve_conflict("there")
	check("conflict: use Google's -> the other account's session and profile", r.ok and r.switched and c._session == "acc9.4102444800.sig"
		and c.profile_own.coins == 40000 and c.profile_own.name == "Zara", c.profile_own)
	check("conflict: ...and this device's queued claims are dropped", c.pending().is_empty())
	check("conflict: nothing left to decide", c.conflict.is_empty())
	r = await c.resolve_conflict("here")
	check("conflict: resolving with nothing pending is refused", not r.ok and r.error == "no_conflict")
	# other_google: stay / switch
	f3.google_status = 409
	f3.google_body = {error = "other_google", conflict = {here = here, there = null}, ticket = "T2"}
	r = await c.link_google()
	check("other_google: 409 raises it, there may be null", r.error == "other_google" and c.conflict.kind == "other_google" and c.conflict.there == null and c.conflict.ticket == "T2", c.conflict)
	f3.resolve_body = {account = {id = "acc9", guest = false}, session = "acc9.4102444800.sig", profile = p2, stayed = true}
	r = await c.resolve_conflict("stay")
	check("other_google: stay changes nothing", r.ok and r.stayed and not r.switched and f3.last("/v1/auth/google/resolve").body.keep == "stay")
	# an expired ticket
	f3.google_body = {error = "other_google", conflict = {here = here, there = there}, ticket = "T3"}
	await c.link_google()
	f3.resolve_body = {}
	check("conflict: copy for an expired ticket", Account.google_error_text("bad_ticket") != "")
	# auto sign-in at launch: only with an existing Play Games sign-in, only for a guest
	var f4 := Fake.new()
	var d := make(f4)
	var pg4 := Fake.FakePG.new()
	pg4.is_signed_in = true
	d.pg_factory = func(): return pg4
	await d.sign_in_guest()
	check("auto: a signed-in Play Games player is linked at launch", f4.count("/v1/auth/google") == 1 and not d.is_guest(), f4.calls)
	var f5 := Fake.new()
	var e := make(f5)
	var pg5 := Fake.FakePG.new()
	e.pg_factory = func(): return pg5
	await e.sign_in_guest()
	check("auto: no Play Games sign-in, no sign-in screen at launch", f5.count("/v1/auth/google") == 0 and e.is_guest())
	for n in [pg, pg2, pg3, pg4, pg5]:
		n.free()
	a.free(); b.free(); c.free(); d.free(); e.free()

func _leaderboard() -> void:
	var f := Fake.new()
	f.board = {top = [{rank = 1, name = "Ana", avatar = "pawn-red", frame = "classic", level = 5, value = 900}], me = {rank = 7, value = 120, listed = true}, min_matches = 3}
	var a := make(f)
	var r: Dictionary = await a.leaderboard("xp", "week")
	check("leaderboard: rows and my row", r.ok and r.top.size() == 1 and r.me.rank == 7 and r.board == "xp" and r.period == "week", r)
	check("leaderboard: signs in first so `me` comes back", a.has_session() and f.last("/v1/leaderboard").session == Fake.SESSION)
	f.online = false
	r = await a.leaderboard("wins", "all")
	check("leaderboard: offline answers offline", not r.ok and r.error == "offline", r)
	a.free()

func _save_repair() -> void:
	var s: Node = load("res://scripts/core/save.gd").new()
	s.profile = {coins = null, xp = null, last_free = null, stats = null, name = null}
	s.prefs = {vol = {master = null, music = null, sfx = null}, speed = null}
	s._ensure()
	check("save: null coins / xp / last_free / stats no longer crash", s.profile.coins == 2500 and s.profile.xp == 0 and s.profile.last_free == 0 and s.profile.stats.played == 0, s.profile)
	s.profile = {coins = -50, xp = -3, stats = {wins = null, played = "7", losses = -2}}
	s._ensure()
	check("save: negative coins are clamped, text numbers read", s.profile.coins == 0 and s.profile.xp == 0 and s.profile.stats.wins == 0 and s.profile.stats.played == 7 and s.profile.stats.losses == 0, s.profile)
	s.profile = {coins = 12.0, xp = 99.0}
	s._ensure()
	check("save: JSON floats become ints", typeof(s.profile.coins) == TYPE_INT and s.profile.coins == 12)
	s.profile = {}
	s._ensure()
	check("save: a fresh profile has 2500 coins, 0 gems, 0 rerolls", s.profile.coins == 2500 and s.profile.gems == 0 and s.profile.rerolls == 0, s.profile)
	s.profile = {coins = 700, gems = -4, rerolls = 50}
	s._ensure()
	check("save: an existing save keeps its coins; gems >= 0, rerolls clamped to 9", s.profile.coins == 700 and s.profile.gems == 0 and s.profile.rerolls == 9, s.profile)
	s.profile = {gems = "12", rerolls = -3}
	s._ensure()
	check("save: gems read from text, negative rerolls become 0", s.profile.gems == 12 and s.profile.rerolls == 0, s.profile)
	check("catalog: gem_price is ceil(coins / 100), none for free", Catalog.gem_price(0) == 0 and Catalog.gem_price(1) == 1 and Catalog.gem_price(100) == 1 and Catalog.gem_price(101) == 2 and Catalog.gem_price(2500) == 25 and Catalog.gem_price(12000) == 120)
	check("save: as_int on junk", s.as_int([]) == 0 and s.as_int({}, 4) == 4 and s.as_int(null, 9) == 9 and s.as_int("x", 2) == 2)
	s.free()

func _text() -> void:
	for code in ["offline", "banned", "coins", "owned", "locked", "claimed", "spun", "cooldown", "busy", "unauthorized", "weird"]:
		check("copy: error_text(%s) is a sentence" % code, Account.error_text(code).length() > 8 and Account.error_text(code).ends_with("."))
	check("copy: should_start respects flags", not Account.should_start(PackedStringArray(["--offline"])) and Account.should_start(PackedStringArray(["--online"]))
		and Account.should_start(PackedStringArray(["--net=http://x"])))
