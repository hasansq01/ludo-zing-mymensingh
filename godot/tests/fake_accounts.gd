extends RefCounted
## A fake of the server's accounts / wallet / leaderboard HTTP API (server/ONLINE_V2.md "as implemented"), for the
## Account, sheet and flow tests: Account.http_fn = fake.http. Answers are synchronous (nothing awaits for real), so
## a test can call a coroutine and have its answer in the same frame.

const SESSION := "acc1.4102444800.sig"

var calls: Array = []                    ## every request: {method, path, body, session}
var online := true                       ## false: status 0 (no connection)
var profile: Dictionary = {}
var account := {id = "acc1", guest = true, google_name = null, created_at = 1, imported = false, online_wins = 0, completed_matches = 0, version = 0}
var imports: Array = []                  ## the import bodies the guest route saw
var claim_ids: Dictionary = {}           ## claim id -> its first answer
var limit_next := ""                     ## the next claim answer is limited with this reason ("" = paid in full)
var refresh_session := ""                ## when set, authed answers carry it as the X-Session header
var google_status := 200
var google_body: Dictionary = {}
var resolve_body: Dictionary = {}
var drop_session := false                ## authed calls answer 401 unauthorized
var board := {top = [], me = null, min_matches = 3}
var prices := {room_neon = 3000, dice_gold = 900, emotes_pawns = 2500, emotes_friends = 4000, emotes_game = 3500}
var daily_taken := false
var broke_taken := false
var rewards_next := {daily = 1793000000, spin = 1793000000, free = 1793003600}   ## GET /v1/rewards next_at per reward
var push_tokens := {}                    ## token -> {session, prefs, tz_offset_min}: POST / DELETE /v1/push/token
var push_opens: Array = []               ## the cids POST /v1/push/opened saw
# Economy v1
const PACKS := [[10, 1000], [50, 5500], [120, 14000]]    ## gems -> coins, POST /v1/gems/exchange {pack}
const GEM_PRODUCTS := {gems_80 = 80, gems_220 = 220, gems_500 = 500, gems_1200 = 1200}
var ads_left := {reroll = 3, refill = 2, double = 2, gems = 1}   ## GET /v1/ads/today
var ads_nonces := {}                     ## nonce -> {kind, polls}: the ads POST /v1/ads/start handed out
var ads_pending_polls := 0               ## how many GET /v1/ads/status answers say "pending" before "granted"
var ads_final := "granted"               ## what the status becomes after those polls: granted | expired | rejected
var iap_results := {}                    ## token -> "pending" | "invalid" | "unavailable": what /v1/iap/verify says (default: grants)
var iap_tokens := {}                     ## token -> gems: granted purchases (a second verify answers duplicate)

func _init() -> void:
	profile = base_profile()

static func base_profile() -> Dictionary:
	return {name = "You", id = "LZM-TEST-0001", coins = 5000, gems = 0, rerolls = 0, xp = 0,
		stats = {played = 0, wins = 0, losses = 0, streak = 0, bestStreak = 0, coinsEarned = 0, pairsFormed = 0, ppGames = 0, slPlayed = 0, slWins = 0},
		rooms = ["night", "cafe"], room = "night", dice_owned = ["classic"], dice = "classic", emote_sets = ["starter"], emote_set = "starter", scenes = ["jungle"], scene = "jungle",
		daily = {}, last_spin = "", last_free = 0, avatar = "pawn-red", av_owned = [], frame = "classic", plate = "plain", badge = "", claimed = []}

func count(path: String) -> int:
	var n := 0
	for c in calls:
		if str(c.path).split("?")[0] == path:
			n += 1
	return n

func last(path: String) -> Dictionary:
	for k in range(calls.size() - 1, -1, -1):
		if str(calls[k].path).split("?")[0] == path:
			return calls[k]
	return {}

func _ok(data: Dictionary, status := 200) -> Dictionary:
	var out := {status = status, data = data}
	if refresh_session != "" and status < 300:
		out.session = refresh_session
	return out

func _prof() -> Dictionary:
	return profile.duplicate(true)

func http(method: int, path: String, body: Variant, session: String) -> Dictionary:
	calls.append({method = method, path = path, body = body, session = session})
	if not online:
		return {status = 0}
	var b: Dictionary = body if body is Dictionary else {}
	var route := path.split("?")[0]
	if route != "/v1/auth/guest" and route != "/v1/leaderboard":
		if drop_session or session == "":
			return {status = 401, data = {error = "unauthorized"}}
	match route:
		"/v1/auth/guest":
			if b.has("import"):
				imports.append(b.import)
				var imp: Dictionary = b.import
				profile.coins = int(imp.get("coins", profile.coins))
				profile.xp = int(imp.get("xp", profile.xp))
				if str(imp.get("name", "You")) != "You":
					profile.name = imp.name
				account.imported = true
			return {status = 200, data = {account = account, session = SESSION, profile = _prof(), created = true,
				import = {ok = true, notes = []} if b.has("import") else null}}
		"/v1/me":
			if method == HTTPClient.METHOD_PATCH:
				for k in ["name", "avatar", "frame", "plate", "badge"]:
					if b.has(k):
						profile[k] = b[k]
				return _ok({ok = true, profile = _prof()})
			return _ok({account = account, profile = _prof(), session = SESSION})
		"/v1/rewards":
			return _ok({today = "2026-10-25", now = 1793000000, daily = {state = {}, next_at = rewards_next.daily},
				spin = {available = true, next_at = rewards_next.spin, prizes = []}, free = {available = true, next_at = rewards_next.free, amount = 300}})
		"/v1/push/token":
			if method == HTTPClient.METHOD_DELETE:
				push_tokens.erase(str(b.get("token", "")))
			else:
				push_tokens[str(b.get("token", ""))] = {session = session, prefs = b.get("prefs"), tz_offset_min = b.get("tz_offset_min")}
			return _ok({ok = true})
		"/v1/push/opened":
			push_opens.append(str(b.get("cid", "")))
			return _ok({ok = true})
		"/v1/shop/buy":
			var key := "%s_%s" % [b.get("kind"), b.get("id")]
			var price := int(prices.get(key, -1))
			if price < 0:
				return _ok({error = "unknown"}, 404)
			if str(b.get("currency", "coins")) == "gems":
				price = (price + 99) / 100
				if int(profile.gems) < price:
					return _ok({error = "gems", short = price - int(profile.gems)}, 409)
				profile.gems = int(profile.gems) - price
			elif int(profile.coins) < price:
				return _ok({error = "coins", short = price - int(profile.coins)}, 409)
			else:
				profile.coins = int(profile.coins) - price
			if b.kind == "room":
				profile.rooms.append(b.id)
				profile.room = b.id
			elif b.kind == "emotes":
				profile.emote_sets.append(b.id)
				profile.emote_set = b.id
			else:
				profile.dice_owned.append(b.id)
			return _ok({ok = true, profile = _prof(), price = price, currency = str(b.get("currency", "coins"))})
		"/v1/shop/equip":
			profile[("emote_set" if b.kind == "emotes" else str(b.kind))] = b.id
			return _ok({ok = true, profile = _prof()})
		"/v1/rewards/daily":
			if daily_taken:
				return _ok({error = "claimed", next_at = 1}, 409)
			daily_taken = true
			profile.coins = int(profile.coins) + 100
			profile.daily = {cycle = 0, streak = 1, last = "2026-10-24"}
			return _ok({ok = true, profile = _prof(), coins = 100, dice = null, char = null, day = 1, cycle = 0, next_at = 1})
		"/v1/rewards/spin":
			profile.coins = int(profile.coins) + 500
			profile.last_spin = "2026-10-24"
			return _ok({ok = true, profile = _prof(), index = 3, prize = 500, next_at = 1})
		"/v1/rewards/free":
			profile.coins = int(profile.coins) + 300
			return _ok({ok = true, profile = _prof(), coins = 300, next_at = 1})
		"/v1/achievements/claim":
			profile.coins = int(profile.coins) + 200
			profile.gems = int(profile.gems) + 10
			profile.claimed.append(b.id)
			return _ok({ok = true, profile = _prof(), coins = 200, gems = 10})
		"/v1/gems/exchange":
			var pk := int(b.get("pack", -1))
			if pk < 0 or pk >= PACKS.size():
				return _ok({error = "invalid"}, 400)
			if int(profile.gems) < int(PACKS[pk][0]):
				return _ok({error = "gems", short = int(PACKS[pk][0]) - int(profile.gems)}, 409)
			profile.gems = int(profile.gems) - int(PACKS[pk][0])
			profile.coins = int(profile.coins) + int(PACKS[pk][1])
			return _ok({ok = true, profile = _prof(), gems = PACKS[pk][0], coins = PACKS[pk][1]})
		"/v1/tables":
			var tl := []
			for t in [["practice", 0, 1], ["t100", 100, 1], ["t500", 500, 3], ["t2k", 2000, 6], ["t10k", 10000, 10], ["t50k", 50000, 15]]:
				tl.append({id = t[0], entry = t[1], level = t[2], unlocked = int(t[2]) <= 3, affordable = int(profile.coins) >= int(t[1])})
			return _ok({tables = tl, fee_pct = 10, level = 3, broke = int(profile.coins) < 100,
				broke_bonus = {available = int(profile.coins) < 100 and not broke_taken, next_at = 1793000000, amount = 300}})
		"/v1/rewards/broke":
			if int(profile.coins) >= 100:
				return _ok({error = "not_broke"}, 409)
			if broke_taken:
				return _ok({error = "claimed", next_at = 1793000000}, 409)
			broke_taken = true
			profile.coins = int(profile.coins) + 300
			return _ok({ok = true, profile = _prof(), coins = 300, next_at = 1793000000})
		"/v1/ads/today":
			var total := 0
			for k in ads_left:
				total += int(ads_left[k])
			return _ok({left = ads_left.duplicate(), total_left = total})
		"/v1/ads/start":
			var kind := str(b.get("kind", ""))
			if not ads_left.has(kind):
				return _ok({error = "invalid"}, 400)
			if int(ads_left[kind]) <= 0:
				return _ok({error = "cap", next_at = 1793000000}, 409)
			if kind == "refill" and int(profile.coins) >= 100:
				return _ok({error = "not_eligible"}, 409)
			var nonce := "n%d" % (ads_nonces.size() + 1)
			ads_nonces[nonce] = {kind = kind, polls = 0, ref = str(b.get("ref", ""))}
			return _ok({ok = true, nonce = nonce, user_id = account.id, custom_data = nonce, left = ads_left.duplicate()})
		"/v1/ads/status":
			var nn := path.get_slice("nonce=", 1)
			if not ads_nonces.has(nn):
				return _ok({error = "not_found"}, 404)
			var ad: Dictionary = ads_nonces[nn]
			ad.polls = int(ad.polls) + 1
			if int(ad.polls) <= ads_pending_polls:
				return _ok({status = "pending", kind = ad.kind})
			if ads_final != "granted":
				return _ok({status = ads_final, kind = ad.kind})
			var amount := 1
			if not ad.get("granted", false):
				ad.granted = true
				ads_left[ad.kind] = int(ads_left[ad.kind]) - 1
				match str(ad.kind):
					"reroll": profile.rerolls = int(profile.rerolls) + 1
					"refill":
						profile.coins = int(profile.coins) + 500
						amount = 500
					"gems":
						profile.gems = int(profile.gems) + 2
						amount = 2
					"double":
						profile.coins = int(profile.coins) + 200
						amount = 200
			else:
				amount = int(ad.get("amount", 1))
			ad.amount = amount
			return _ok({status = "granted", kind = ad.kind, amount = amount, profile = _prof()})
		"/v1/iap/products":
			var pl := []
			for pid in GEM_PRODUCTS:
				pl.append({id = pid, gems = GEM_PRODUCTS[pid]})
			return _ok({products = pl})
		"/v1/iap/verify":
			var tok := str(b.get("token", ""))
			var pid := str(b.get("product_id", ""))
			if not GEM_PRODUCTS.has(pid):
				return _ok({error = "invalid"}, 409)
			if iap_tokens.has(tok):
				return _ok({ok = true, duplicate = true, gems = iap_tokens[tok], profile = _prof()})
			match str(iap_results.get(tok, "")):
				"pending": return _ok({error = "pending"}, 409)
				"invalid": return _ok({error = "invalid"}, 409)
				"unavailable": return _ok({error = "unavailable"}, 503)
			iap_tokens[tok] = GEM_PRODUCTS[pid]
			profile.gems = int(profile.gems) + int(GEM_PRODUCTS[pid])
			return _ok({ok = true, gems = GEM_PRODUCTS[pid], profile = _prof()})
		"/v1/claims":
			var id := str(b.get("id", ""))
			if id.length() < 8:
				return _ok({error = "invalid", detail = "id"}, 400)
			if claim_ids.has(id):
				var dup: Dictionary = claim_ids[id].duplicate()
				dup.duplicate = true
				dup.profile = _prof()
				return _ok(dup)
			var ans := {ok = true, id = id, limited = false, granted = true, coins = 150 if b.get("result") == "win" else 20, xp = 100}
			if limit_next != "":
				ans.limited = true
				ans.reason = limit_next
				ans.coins = 0
				ans.xp = 0
				ans.would = {coins = 150, xp = 100}
				limit_next = ""
			profile.coins = int(profile.coins) + int(ans.coins)
			claim_ids[id] = ans.duplicate()
			ans.profile = _prof()
			return _ok(ans)
		"/v1/auth/google":
			if google_status == 200:
				account.guest = false
				account.google_name = "Zing Player"
				return _ok({account = account, session = SESSION, profile = _prof(), linked = true})
			return _ok(google_body, google_status)
		"/v1/auth/google/resolve":
			return _ok(resolve_body.duplicate(true), 200)
		"/v1/leaderboard":
			var d := board.duplicate(true)
			d.board = path.get_slice("board=", 1).get_slice("&", 0)
			d.period = path.get_slice("period=", 1)
			return _ok(d)
	return {status = 404, data = {error = "not_found"}}


## A fake PlayGames object with the wrapper's signals.
class FakePG extends Node:
	signal signed_in(player: Dictionary)
	signal sign_in_failed(code: String)
	signal signed_out
	signal server_auth_code(code: String)
	signal server_auth_code_failed(code: String)
	var available := true
	var is_signed_in := false
	var sign_in_error := ""
	var code_error := ""
	var code := "CODE-1"
	var asked_codes := 0

	func is_available() -> bool:
		return available

	func sign_in() -> void:
		if sign_in_error != "":
			sign_in_failed.emit(sign_in_error)
			return
		is_signed_in = true
		signed_in.emit({display_name = "Zing Player", player_id = "p1"})

	func check_signed_in() -> void:
		if is_signed_in:
			signed_in.emit({display_name = "Zing Player", player_id = "p1"})
		else:
			signed_out.emit()

	func request_server_auth_code(_web := "", _force := false) -> void:
		asked_codes += 1
		if code_error != "":
			server_auth_code_failed.emit(code_error)
		else:
			server_auth_code.emit(code)
