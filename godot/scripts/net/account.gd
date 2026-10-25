class_name Account
extends Node
## The player's server account (server/ONLINE_V2.md sections 1, 2 and 4): a guest account made at launch, the
## session kept in Save.prefs.net_session, the server wallet (the server profile is the truth: every answer with a
## profile is written into Save.profile), offline match claims, Google Play Games sign-in and the leaderboard.
##
##   var acc := Account.new(); add_child(acc); acc.start()      # main owns one; Account.instance() finds it
##   Account.session()                                           # "" until signed in; for the room hello
##   Account.instance().signed_in_changed                        # a session was gained or lost
##   var r := await acc.buy("room", "neon")                       # {ok, error, ...}: wallet calls never grant locally
##   acc.report_match({game = "ludo", ...})                       # an offline match -> a queued, idempotent claim
##
## Offline-tolerant: nothing here blocks play. No connection: the game keeps using the local profile, guest auth
## retries with backoff (and when the app resumes), wallet calls answer {ok = false, error = "offline"} so the UI
## can say "Connect to claim", and claims wait in Save.prefs.pending_claims until a connection returns.
## Every wallet call is a coroutine; tests set http_fn (method, path, body, session) -> {status, data, session}.

## The server profile was written into the local one (Save.changed was emitted too, unless the caller held it).
signal changed(profile: Dictionary)
## A session was gained, lost or replaced (sign-in, expiry, switching Google account). Room clients re-read session().
signal signed_in_changed
## The account record changed: guest or Google-linked, the Google name, completed matches.
signal account_changed
## Google sign-in needs a decision: {kind: "conflict" | "other_google", here, there, ticket}.
signal conflict_raised(conflict: Dictionary)
## A queued or fresh claim was answered by the server (the body of POST /v1/claims, with the claim's id).
signal claim_answered(claim_id: String, answer: Dictionary)
## The queue of offline claims changed size.
signal pending_changed
signal _auth_done

const BACKOFF := [3.0, 8.0, 20.0, 45.0, 90.0]
const MAX_PENDING := 40
const TIMEOUT_SEC := 10.0
const GUEST_PATH := "/v1/auth/guest"
## Fields a name / look change (PATCH /v1/me) carries.
const IDENT_FIELDS := ["name", "avatar", "frame", "plate", "badge"]

static var _inst: Account = null

var enabled := true                      ## false: no network at all (dev runs on a throwaway profile)
var use_save := true                     ## false: prefs / profile are the caller's (tests)
var prefs: Dictionary = {}               ## Save.prefs by default
var profile_own: Dictionary = {}         ## the profile written to when use_save is false
var persist := Callable()                ## saves prefs (Save.save by default)
var url_base := ""                       ## ws(s)://host[:port] like NetClient (resolve_url() when empty)
var http_fn := Callable()                ## (method: int, path: String, body: Variant, session: String) -> {status, data, session}
var pg_factory := Callable()             ## () -> the PlayGames object (tests pass a fake with the same signals)
var account: Dictionary = {}             ## the server's account record {id, guest, google_name, completed_matches, ...}
var conflict: Dictionary = {}            ## a Google sign-in waiting for a decision (conflict_raised)
var banned := false
var last_claim: Dictionary = {}          ## the last claim answer ({id, limited, reason, coins, would, ...})
var rewards_at: Dictionary = {}          ## when each reward is next claimable by the server's clock {daily, spin, free: unix s}

var _session := ""
var _pg: Object = null
var _signing := false
var _flushing := false
var _auto_tried := false
var _retry := 0
var _retry_left := -1.0
var _defaults_done := false
var _server_ident := {}                  # name / look as the server last told us (push_identity compares)


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)

func _enter_tree() -> void:
	_inst = self

func _exit_tree() -> void:
	if _inst == self:
		_inst = null

## The account of this run, or null (tests, previews and dev tours without one use the local profile).
static func instance() -> Account:
	return _inst if is_instance_valid(_inst) else null

## Tests: make this the current account without a scene tree (pass null to clear).
static func set_instance(a: Account) -> void:
	_inst = a

## The session token for the room hello and quick match: "" when there is none.
static func session() -> String:
	var a := instance()
	return a._session if a != null else ""

## True when purchases and rewards go through the server (an Account exists and is enabled).
static func wallet_active() -> bool:
	var a := instance()
	return a != null and a.enabled

## Debug runs from the editor binary stay offline (they use a throwaway profile) unless asked for with --online or
## --net=<url>; exported builds (debug or release) always go online.
static func should_start(args: PackedStringArray) -> bool:
	if args.has("--offline"):
		return false
	if args.has("--online"):
		return true
	for a in args:
		if a.begins_with("--net="):
			return true
	return not OS.has_feature("editor")


# =====================================================================================================================
# State helpers
# =====================================================================================================================

func _defaults() -> void:
	if _defaults_done:
		return
	_defaults_done = true
	if use_save and not persist.is_valid():
		var s := _save_node()
		if s != null:
			persist = Callable(s, "save")
	if url_base == "":
		url_base = NetClient.resolve_url(P(), OS.get_cmdline_user_args() if OS.is_debug_build() else PackedStringArray())

static func _save_node() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("Save") if tree and tree.root else null

## The live preferences (Save.prefs is replaced by Save.reset_progress, so it is read each time).
func P() -> Dictionary:
	if use_save:
		var s := _save_node()
		if s != null and s.get("prefs") is Dictionary:
			return s.get("prefs")
	return prefs

## The profile that server answers are written into.
func prof() -> Dictionary:
	if use_save:
		var s := _save_node()
		if s != null and s.get("profile") is Dictionary:
			return s.get("profile")
	return profile_own

func _persist() -> void:
	if persist.is_valid():
		persist.call()

func has_session() -> bool:
	return _session != ""

func is_guest() -> bool:
	return bool(account.get("guest", true))

func google_name() -> String:
	var g: Variant = account.get("google_name")
	return str(g) if g != null else ""

func _set_session(s: String) -> void:
	if s == _session:
		return
	_session = s
	var pr := P()
	if s == "":
		pr.erase("net_session")
	else:
		pr.net_session = s
	_persist()
	signed_in_changed.emit()              # gained, lost or replaced (a switch): room clients re-read session()

func _load_session() -> void:
	var s := str(P().get("net_session", ""))
	if s != "" and _session == "":
		_session = s


# =====================================================================================================================
# HTTP
# =====================================================================================================================

## One call. {ok, status, data (a Dictionary, {} when the body wasn't JSON), error ("" when ok)}. `error` is the
## server's code, or "offline" (no answer), "server" (5xx without a code), "unauthorized" (the session is bad: it is
## dropped and a new guest session is asked for), "banned".
func request(method: int, path: String, body: Variant = null, authed := true) -> Dictionary:
	_defaults()
	var sess := _session if authed else ""
	var r: Dictionary
	if http_fn.is_valid():
		var out: Variant = await http_fn.call(method, path, body, sess)
		r = out if out is Dictionary else {status = 0}
	else:
		r = await _real_http(method, path, body, sess)
	var st := int(r.get("status", 0))
	var d: Variant = r.get("data")
	var data: Dictionary = d if d is Dictionary else {}
	var fresh := str(r.get("session", ""))
	if authed and fresh != "" and st >= 200 and st < 300 and fresh != _session:
		_set_session(fresh)                  # X-Session: the server renewed the session
	var res := {ok = st >= 200 and st < 300, status = st, data = data, error = ""}
	if not res.ok:
		res.error = _error_code(st, data)
		if st == 401 and res.error == "unauthorized" and authed:
			_lose_session()
		elif st == 403 and res.error == "banned":
			banned = true
			account_changed.emit()
	return res

## A number from a server answer (JSON floats; null) as an int.
static func _int(v: Variant, dflt := 0) -> int:
	return int(v) if v is int or v is float else dflt

static func _error_code(status: int, data: Dictionary) -> String:
	if status == 0:
		return "offline"
	var e := str(data.get("error", ""))
	if e != "":
		return e
	return "server" if status >= 500 else "rejected"

func _lose_session() -> void:
	_set_session("")
	_retry_soon()

func _real_http(method: int, path: String, body: Variant, sess: String) -> Dictionary:
	if not is_inside_tree():
		return {status = 0}
	var req := HTTPRequest.new()
	req.timeout = TIMEOUT_SEC
	add_child(req)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if sess != "":
		headers.append("Authorization: Bearer " + sess)
	var text := ""
	if method != HTTPClient.METHOD_GET:
		text = JSON.stringify(body if body != null else {})
	var err := req.request(NetClient.http_base(url_base) + path, headers, method, text)
	if err != OK:
		req.queue_free()
		return {status = 0}
	var res: Array = await req.request_completed       # [result, code, headers, body]
	req.queue_free()
	if int(res[0]) != HTTPRequest.RESULT_SUCCESS:
		return {status = 0}
	var s := ""
	for h: String in (res[2] as PackedStringArray):
		if h.to_lower().begins_with("x-session:"):
			s = h.substr(h.find(":") + 1).strip_edges()
	var raw := (res[3] as PackedByteArray).get_string_from_utf8()
	return {status = int(res[1]), data = JSON.parse_string(raw) if raw != "" else null, session = s}


# =====================================================================================================================
# Guest sign-in (launch)
# =====================================================================================================================

## Launch: take the kept session (the game is playable at once), then sign in as a guest in the background.
func start() -> void:
	_defaults()
	_load_session()
	if _session != "":
		signed_in_changed.emit()
	sign_in_guest()

## POST /v1/auth/guest {pid, import?}. The local profile is imported once, the first time (Save.prefs.net_imported).
## True when a session exists afterwards. Offline or a server hiccup: false, and a retry is scheduled.
func sign_in_guest() -> bool:
	if not enabled:
		return false
	if _signing:
		await _auth_done
		return has_session()
	_signing = true
	_defaults()
	var pr := P()
	var body := {pid = NetClient.ensure_pid(pr)}
	var importing := not bool(pr.get("net_imported", false))
	var queued := pending().size()
	if importing:
		body.import = prof().duplicate(true)
	_persist()
	var r: Dictionary = await request(HTTPClient.METHOD_POST, GUEST_PATH, body, false)
	var good: bool = r.ok and str(r.data.get("session", "")) != ""
	if good:
		_retry = 0
		_retry_left = -1.0
		set_process(false)
		if importing:
			P().net_imported = true
		var imp: Variant = r.data.get("import")
		if importing and imp is Dictionary and bool((imp as Dictionary).get("ok", false)) and queued > 0:
			var list := pending()
			for k in mini(queued, list.size()):
				list.pop_front()                 # those matches are in the imported totals already
		_set_session(str(r.data.session))
		if r.data.get("account") is Dictionary:
			account = r.data.account
			account_changed.emit()
		# what the player set while this request was in flight (the welcome screen's name and look) must survive the
		# server's copy, which may still hold the defaults
		var mine := {}
		for k in ["name", "avatar", "frame"]:
			mine[k] = str(prof().get(k, ""))
		var applied := false
		if not pending().is_empty():
			applied = await flush_claims()
		if not applied and r.data.get("profile") is Dictionary:
			apply_profile(r.data.profile)
		_persist()
		var keep := {}
		var server_name := str(prof().get("name", "")).strip_edges()
		if importing and mine.name.strip_edges() not in ["", "You"] and server_name in ["", "You", "Player"]:
			keep.name = NetClient.wire_name(mine.name)
		for k in ["avatar", "frame"]:
			if keep.has("name") and mine[k] != "" and mine[k] != str(prof().get(k, "")):
				keep[k] = mine[k]
		if not keep.is_empty():
			await push_identity(keep)
	else:
		if r.error == "banned":
			banned = true
			account_changed.emit()
		elif r.error != "accounts_disabled":
			_schedule_retry(r.error == "rate")
	_signing = false
	_auth_done.emit()
	if good:
		_auto_google()
	return good

## True when a session exists, signing in as a guest first when not (one try).
func ensure_session() -> bool:
	if has_session():
		return true
	if not enabled or banned:
		return false
	return await sign_in_guest()

func _schedule_retry(slow := false) -> void:
	var k := mini(_retry + (2 if slow else 0), BACKOFF.size() - 1)
	_retry_left = float(BACKOFF[k])
	_retry += 1
	set_process(is_inside_tree())

func _retry_soon() -> void:
	_retry_left = 0.5
	set_process(is_inside_tree())

func _process(delta: float) -> void:
	if _retry_left < 0.0:
		set_process(false)
		return
	_retry_left -= delta
	if _retry_left <= 0.0:
		_retry_left = -1.0
		set_process(false)
		sign_in_guest()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED and enabled and is_inside_tree():
		if not has_session():
			_retry_soon()
		elif not pending().is_empty():
			flush_claims()

## Back to a new guest (Settings "Reset progress"): the session, the device id and the import flag are forgotten.
func reset_identity() -> void:
	var pr := P()
	for k in ["net_session", "net_pid", "net_imported", "pending_claims"]:
		pr.erase(k)
	_session = ""
	account = {}
	conflict = {}
	_server_ident = {}
	rewards_at = {}
	_persist()
	signed_in_changed.emit()
	account_changed.emit()
	pending_changed.emit()
	if enabled:
		_retry_soon()


# =====================================================================================================================
# The profile
# =====================================================================================================================

## Writes a server profile into the local one (in place: sheets keep their reference to Save.profile), repairs it,
## saves, and tells the HUD (Save.changed) unless `notify` is false (the caller emits it when its animation ends).
func apply_profile(p: Dictionary, notify := true) -> void:
	var target := prof()
	var fresh := p.duplicate(true)
	target.clear()
	target.merge(fresh)
	_server_ident = {}
	for k in IDENT_FIELDS:
		_server_ident[k] = str(fresh.get(k, "")) if fresh.get(k) != null else ""
	var s := _save_node() if use_save else null
	if s != null:
		s.call("normalize")
		s.call("save")
		if notify:
			s.emit_signal("changed")
	changed.emit(target)

## The profile / account / session of any server answer.
func _take(d: Dictionary, notify := true) -> void:
	var sess := str(d.get("session", ""))
	if sess != "" and sess != _session:
		_set_session(sess)
	if d.get("account") is Dictionary:
		account = d.account
		account_changed.emit()
	if d.get("profile") is Dictionary:
		apply_profile(d.profile, notify)

## GET /v1/me: the account and profile as the server has them now. True when it worked.
func refresh_me() -> bool:
	if not has_session():
		return false
	var r: Dictionary = await request(HTTPClient.METHOD_GET, "/v1/me")
	if r.ok:
		_take(r.data)
	return r.ok

## PATCH /v1/me {name, avatar, frame, plate, badge}: only what differs from the server's copy. {ok, error}.
## The server profile comes back and replaces the local one.
func push_identity(fields: Dictionary = {}) -> Dictionary:
	var want := fields
	if want.is_empty():
		var p := prof()
		for k in IDENT_FIELDS:
			if not p.has(k) or p.get(k) == null:
				continue
			var v := str(p.get(k))
			if k == "name":
				v = NetClient.wire_name(v) if v.strip_edges() != "You" else ""
			if v == "" and k != "badge":
				continue
			if str(_server_ident.get(k, "")) != v:
				want[k] = v
	if want.is_empty():
		return {ok = true, error = ""}
	return await _write(HTTPClient.METHOD_PATCH, "/v1/me", want, true)


# =====================================================================================================================
# The wallet
# =====================================================================================================================

## What the UI says when an action needs a connection ("Connect to claim").
static func offline_text(action: String) -> String:
	match action:
		"buy":
			return "Connect to the internet to buy."
		"equip":
			return "Connect to the internet to change your look."
		"name":
			return "Connect to the internet to change your name."
		"spin":
			return "Connect to the internet to spin."
		"leaderboard":
			return "Connect to the internet to see the leaderboard."
	return "Connect to the internet to claim."

## Friendly copy for a wallet error code.
static func error_text(code: String, action := "claim") -> String:
	match code:
		"offline":
			return offline_text(action)
		"banned":
			return "This account can’t use the shop or rewards."
		"coins":
			return "Not enough coins."
		"owned":
			return "You already own that."
		"locked":
			return "That’s still locked."
		"reserved":
			return "Pick another name: “You” is how the game shows you to yourself."
		"claimed", "spun", "cooldown":
			return "Already claimed. Come back later."
		"busy", "server", "accounts_disabled", "rate":
			return "The server is busy. Try again in a moment."
		"unauthorized":
			return "Signing in… try again in a moment."
	return "Something went wrong. Please try again."

## A write that needs the server: signs in first when there is no session, plays queued claims first (so the
## server profile already counts them), then calls. Answers {ok, error, status, ...the answer's fields}.
func _write(method: int, path: String, body: Variant, notify := true) -> Dictionary:
	if banned:
		return {ok = false, error = "banned", status = 403}
	if not await ensure_session():
		return {ok = false, error = "offline", status = 0}
	if not pending().is_empty():
		await flush_claims()
	var r: Dictionary = await request(method, path, body)
	var out: Dictionary = r.data.duplicate()
	out.ok = r.ok
	out.status = r.status
	out.error = r.error
	if r.ok:
		_take(r.data, notify)
		out.erase("profile")
	elif r.error in ["claimed", "spun", "cooldown", "owned", "locked", "not_done", "coins"]:
		await refresh_me()                   # our copy was behind: sync it
	return out

## POST /v1/shop/buy. {ok, price, item} | {ok = false, error: coins | owned | locked | unknown | offline, short?}.
func buy(kind: String, id: String, notify := true) -> Dictionary:
	return await _write(HTTPClient.METHOD_POST, "/v1/shop/buy", {kind = kind, id = id}, notify)

## POST /v1/shop/equip.
func equip(kind: String, id: String) -> Dictionary:
	return await _write(HTTPClient.METHOD_POST, "/v1/shop/equip", {kind = kind, id = id})

## POST /v1/rewards/daily -> {ok, coins, dice, char, day, cycle, next_at}.
func daily(notify := true) -> Dictionary:
	var r: Dictionary = await _write(HTTPClient.METHOD_POST, "/v1/rewards/daily", {}, notify)
	if r.ok:
		r.dice = str(r.get("dice", "")) if r.get("dice") != null else ""
		r.char = str(r.get("char", "")) if r.get("char") != null else ""
		r.coins = _int(r.get("coins"), 0)
		r.day = _int(r.get("day"), 1)
	_note_next("daily", r)
	return r

## POST /v1/rewards/spin -> {ok, index, prize, next_at}. `notify` false holds Save.changed (the wheel is still turning).
func spin(notify := false) -> Dictionary:
	var r: Dictionary = await _write(HTTPClient.METHOD_POST, "/v1/rewards/spin", {}, notify)
	if r.ok:
		r.index = _int(r.get("index"), 0)
		r.prize = _int(r.get("prize"), 0)
	_note_next("spin", r)
	return r

## POST /v1/rewards/free -> {ok, coins, next_at}.
func free_coins(notify := true) -> Dictionary:
	var r: Dictionary = await _write(HTTPClient.METHOD_POST, "/v1/rewards/free", {}, notify)
	_note_next("free", r)
	return r

## Keeps the `next_at` of a reward answer (a claim, or the "already claimed" refusal) for the reminders.
func _note_next(key: String, r: Dictionary) -> void:
	var at := _int(r.get("next_at"), 0)
	if at > 0 and (r.get("ok", false) or r.get("error", "") in ["claimed", "spun", "cooldown"]):
		rewards_at[key] = at

## GET /v1/rewards: when the daily reward, the spin and Free Coins are next claimable ({daily, spin, free: unix s},
## empty when unknown). The reminders schedule from it while signed in. Does nothing without a session.
func fetch_rewards() -> Dictionary:
	if not has_session() or not enabled:
		return rewards_at
	var r: Dictionary = await request(HTTPClient.METHOD_GET, "/v1/rewards")
	if r.ok:
		for key: String in ["daily", "spin", "free"]:
			var part: Variant = r.data.get(key)
			var at := _int((part as Dictionary).get("next_at"), 0) if part is Dictionary else 0
			if at > 0:
				rewards_at[key] = at
	return rewards_at

## POST /v1/achievements/claim {id} -> {ok, coins, progress}.
func claim_ach(id: String, notify := true) -> Dictionary:
	return await _write(HTTPClient.METHOD_POST, "/v1/achievements/claim", {id = id}, notify)


# =====================================================================================================================
# Offline match claims
# =====================================================================================================================

## The queue of claims not yet answered (Save.prefs.pending_claims, saved with the preferences).
func pending() -> Array:
	var pr := P()
	if not pr.get("pending_claims") is Array:
		pr.pending_claims = []
	return pr.pending_claims

## A claim body from a finished offline match:
##   {game "ludo" | "sl", mode "cpu" | "pp" | "local", result "win" | "loss", players (Ludo: 4 seats), duration_s,
##    pairs (Ludo), rolls + need_one (S&L vs computer), placing (your final place, 1-based: the server pays by it)}.
## Gets an id (idempotent: a retry never pays twice), joins the queue and is sent when a connection exists.
## Returns the claim id.
func report_match(info: Dictionary) -> String:
	var c := info.duplicate(true)
	c.id = "m%d-%s" % [int(Time.get_unix_time_from_system() * 1000.0), Crypto.new().generate_random_bytes(4).hex_encode()]
	c.duration_s = maxi(0, int(c.get("duration_s", 0)))
	var list := pending()
	list.append(c)
	while list.size() > MAX_PENDING:
		list.pop_front()
	_persist()
	pending_changed.emit()
	if enabled:
		if has_session():
			flush_claims()
		elif not _signing:
			_retry_soon()
	return str(c.id)

## Sends the queued claims one by one, oldest first. Stops at the first connection failure (they stay queued).
## True when at least one answer was written into the profile.
func flush_claims() -> bool:
	if _flushing or not has_session() or not enabled:
		return false
	_flushing = true
	var applied := false
	while has_session():
		var list := pending()
		if list.is_empty():
			break
		var claim: Dictionary = list[0]
		var r: Dictionary = await request(HTTPClient.METHOD_POST, "/v1/claims", claim)
		var cur := pending()
		if r.ok:
			cur.erase(claim)
			_persist()
			var ans: Dictionary = r.data.duplicate()
			ans.id = str(claim.id)
			last_claim = ans
			_take(r.data)
			applied = true
			pending_changed.emit()
			claim_answered.emit(str(claim.id), ans)
		elif r.status == 400:                # malformed: it can never be accepted
			cur.erase(claim)
			_persist()
			pending_changed.emit()
		else:
			break
	_flushing = false
	return applied

## The subtle result-screen / toast note for a limited claim, "" when it was paid in full.
static func claim_note(ans: Dictionary) -> String:
	if not bool(ans.get("limited", false)):
		return ""
	match str(ans.get("reason", "")):
		"daily_coins", "daily_xp":
			return "Daily limit reached"
		"hourly":
			return "Too many matches this hour"
		"too_short":
			return "Too short to count"
		"replay":
			return "We couldn’t verify that win"
	return "Daily limit reached"


# =====================================================================================================================
# Push (server/NOTIFICATIONS.md "N-SRV")
# =====================================================================================================================

## POST /v1/push/token {token, platform, prefs: {game, offers}, tz_offset_min}: registers this phone's push token for
## the account (the server moves it over when another account had it). {ok, error}.
func push_register(token: String, game: bool, offers: bool, tz_offset_min: int) -> Dictionary:
	if not has_session():
		return {ok = false, error = "offline"}
	var r: Dictionary = await request(HTTPClient.METHOD_POST, "/v1/push/token", {token = token, platform = "android",
		prefs = {game = game, offers = offers}, tz_offset_min = tz_offset_min})
	return {ok = r.ok, error = r.error}

## DELETE /v1/push/token {token} with the session the token was registered under (the account may be gone from this
## phone already: sign-out, a switch). {ok, error}.
func push_delete(token: String, session_: String) -> Dictionary:
	if session_ == "" or not enabled:
		return {ok = false, error = "unauthorized"}
	_defaults()
	var r: Dictionary
	if http_fn.is_valid():
		var out: Variant = await http_fn.call(HTTPClient.METHOD_DELETE, "/v1/push/token", {token = token}, session_)
		r = out if out is Dictionary else {status = 0}
	else:
		r = await _real_http(HTTPClient.METHOD_DELETE, "/v1/push/token", {token = token}, session_)
	var st := int(r.get("status", 0))
	return {ok = st >= 200 and st < 300, error = "" if st >= 200 and st < 300 else _error_code(st, {})}

## POST /v1/push/opened {cid}: a campaign notification was opened (the session is optional). {ok, error, status}.
func push_opened(cid: String) -> Dictionary:
	if cid == "" or not enabled:
		return {ok = false, error = "offline", status = 0}
	var r: Dictionary = await request(HTTPClient.METHOD_POST, "/v1/push/opened", {cid = cid}, has_session())
	return {ok = r.ok, error = r.error, status = r.status}


# =====================================================================================================================
# Leaderboard
# =====================================================================================================================

## GET /v1/leaderboard. board "xp" | "wins", period "all" | "week". {ok, top, me, min_matches, ...} | {ok = false, error}.
## Works without an account (no `me` then). Tries to sign in first so the caller's own row comes back.
func leaderboard(board: String, period: String) -> Dictionary:
	_defaults()
	if not has_session() and enabled and not banned:
		await sign_in_guest()
	var r: Dictionary = await request(HTTPClient.METHOD_GET, "/v1/leaderboard?board=%s&period=%s" % [board, period], null, has_session())
	var out: Dictionary = r.data.duplicate()
	out.ok = r.ok
	out.error = r.error
	out.status = r.status
	if r.ok:
		if not out.get("top") is Array:
			out.top = []
	return out


# =====================================================================================================================
# Google Play Games
# =====================================================================================================================

## The PlayGames node (stub off Android), created on first use.
func play_games() -> Object:
	if _pg != null and is_instance_valid(_pg):
		return _pg
	if pg_factory.is_valid():
		_pg = pg_factory.call()
	else:
		var n := PlayGames.new()
		n.auto_check = false
		_pg = n
	if _pg is Node and (_pg as Node).get_parent() == null:
		add_child(_pg as Node)
	return _pg

## True where Play Games can sign in (Android with the plugin and an app id).
func google_available() -> bool:
	var pg := play_games()
	return pg != null and bool(pg.call("is_available"))

## Launch: when Play Games already has a signed-in player and this is still a guest account, link it quietly.
## A clash raises conflict_raised; every other failure stays silent.
func _auto_google() -> void:
	if _auto_tried or not is_guest() or not google_available():
		return
	_auto_tried = true
	await link_google(false)

## The Sign in with Google Play Games button: Play Games sign-in, a server auth code, POST /v1/auth/google.
## {ok, linked?, error?, conflict?}. error: unavailable | canceled | offline | google_not_configured | google_rejected
## | google_failed | conflict | other_google | ... ; conflict / other_google also raise conflict_raised.
## interactive false (launch): only an existing Play Games sign-in is used, no sign-in screen.
func link_google(interactive := true) -> Dictionary:
	var pg := play_games()
	if pg == null or not bool(pg.call("is_available")):
		return {ok = false, error = "unavailable"}
	if not await ensure_session():
		return {ok = false, error = "offline"}
	if not pending().is_empty():
		await flush_claims()                 # so the "this device" progress below counts them
	if not bool(pg.get("is_signed_in")):
		var w := Waiter.new()
		w.watch(pg, ["signed_in"], ["sign_in_failed", "signed_out"])
		if interactive:
			pg.call("sign_in")
		else:
			pg.call("check_signed_in")
		await w.wait(self, 120.0 if interactive else 20.0)
		if not w.ok:
			return {ok = false, error = str(w.value) if w.value != null and str(w.value) != "" else "signed_out"}
	var w2 := Waiter.new()
	w2.watch(pg, ["server_auth_code"], ["server_auth_code_failed"])
	pg.call("request_server_auth_code")
	await w2.wait(self, 20.0)
	if not w2.ok:
		return {ok = false, error = str(w2.value) if w2.value != null and str(w2.value) != "" else "timeout"}
	var r: Dictionary = await request(HTTPClient.METHOD_POST, "/v1/auth/google", {server_auth_code = str(w2.value), pid = NetClient.ensure_pid(P())})
	return _google_answer(r)

func _google_answer(r: Dictionary) -> Dictionary:
	if r.ok:
		conflict = {}
		_take(r.data)
		var out := {ok = true, linked = bool(r.data.get("linked", false)), switched = bool(r.data.get("switched", false))}
		return out
	if r.status == 409 and r.error in ["conflict", "other_google"]:
		var c: Variant = r.data.get("conflict")
		var cd: Dictionary = c if c is Dictionary else {}
		conflict = {kind = r.error, here = cd.get("here", {}), there = cd.get("there"), ticket = str(r.data.get("ticket", ""))}
		conflict_raised.emit(conflict)
		return {ok = false, error = r.error, conflict = conflict}
	return {ok = false, error = r.error}

## POST /v1/auth/google/resolve after conflict_raised. keep: "here" | "there" | "switch" | "stay".
## "there" / "switch" replace this device's progress with the other account's (queued claims are dropped);
## "here" moves the Google id to this account; "stay" changes nothing.
func resolve_conflict(keep: String) -> Dictionary:
	if conflict.is_empty():
		return {ok = false, error = "no_conflict"}
	var body := {keep = keep, pid = NetClient.ensure_pid(P())}
	if str(conflict.get("ticket", "")) != "":
		body.ticket = conflict.ticket
	var r: Dictionary = await request(HTTPClient.METHOD_POST, "/v1/auth/google/resolve", body)
	if not r.ok:
		if r.error == "bad_ticket":
			conflict = {}                    # expired: sign in again
		return {ok = false, error = r.error}
	conflict = {}
	if keep in ["there", "switch"] and bool(r.data.get("switched", false)):
		pending().clear()
		pending_changed.emit()
	_take(r.data)
	return {ok = true, keep = keep, switched = bool(r.data.get("switched", false)), stayed = bool(r.data.get("stayed", false))}

## Friendly copy for link_google / resolve_conflict errors ("" = nothing to say, e.g. the player backed out).
static func google_error_text(code: String) -> String:
	match code:
		"canceled", "conflict", "other_google", "signed_out":
			return ""
		"unavailable":
			return "Google Play Games sign-in is available on Android."
		"offline":
			return "Connect to the internet to sign in."
		"google_not_configured":
			return "Google sign-in isn’t switched on yet. Please try again later."
		"google_rejected", "google_failed":
			return "Google sign-in didn’t work. Please try again."
		"banned":
			return "This Google account can’t play online."
		"bad_ticket":
			return "That took too long. Please sign in again."
	return "Couldn’t sign in. Please try again."


## Waits for one of several signals of an object (a plugin answer) with a timeout; no lambdas, so nothing can be
## "freed while captured".
class Waiter extends RefCounted:
	signal done
	var finished := false
	var ok := false
	var value: Variant = null
	var _obj: Object
	var _ok_sigs: Array = []
	var _bad_sigs: Array = []

	func watch(obj: Object, ok_sigs: Array, bad_sigs: Array) -> void:
		_obj = obj
		_ok_sigs = ok_sigs
		_bad_sigs = bad_sigs
		for s in ok_sigs:
			obj.connect(s, win)
		for s in bad_sigs:
			obj.connect(s, lose)

	func win(v: Variant = null) -> void:
		_finish(true, v)

	func lose(v: Variant = null) -> void:
		_finish(false, v)

	func _finish(o: bool, v: Variant) -> void:
		if finished:
			return
		finished = true
		ok = o
		value = v
		if is_instance_valid(_obj):
			for s in _ok_sigs:
				if _obj.is_connected(s, win):
					_obj.disconnect(s, win)
			for s in _bad_sigs:
				if _obj.is_connected(s, lose):
					_obj.disconnect(s, lose)
		done.emit()

	## Await the answer (it may already be here); `host` gives the timer.
	func wait(host: Node, seconds: float) -> void:
		if finished:
			return
		if host != null and host.is_inside_tree():
			host.get_tree().create_timer(seconds).timeout.connect(lose.bind("timeout"))
		await done
