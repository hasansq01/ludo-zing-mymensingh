class_name AdFlow
extends Node
## One rewarded ad, start to finish (server/ECONOMY_V1.md section 5). Shared by the Rewards sheet, the broke popup, the
## coin-table result card and the re-roll offer:
##
##   var flow := AdFlow.new(); add_child(flow)
##   flow.done.connect(func(ok: bool, info: Dictionary): ...)    # info {kind, amount, error?, text?}
##   flow.watch("gems")                                          # kind: reroll | refill | double | gems; ref = match id for double
##   AdFlow.available()                                          # false off Android / without the plugin: hide the button
##
## watch() 1. checks an ad is loaded, 2. POST /v1/ads/start (the server checks the daily cap), 3. shows the ad with the
## server-side-verification options, 4. after `earned` + `closed` polls GET /v1/ads/status every 1.5 s for up to 20 s,
## 5. emits done(true, {kind, amount}); the returned profile is already in Save.profile (Account writes it). Nothing is
## granted from the game's word: only a "granted" answer counts.
## Failures: done(false, {kind, error, text}) with error: "unavailable" (no plugin), "no_fill" (nothing loaded or the
## ad couldn't be shown: "No video right now, try again in a minute"), "cap" / "not_eligible" / "offline" / ... (the
## server's code), "closed" (the video was closed before the reward), "rejected" (the server refused the reward) and
## "timeout" (still pending after 20 s: the reward arrives by itself, the profile refreshes). `text` is friendly copy.
## One watch at a time: a second call while `busy` is ignored (done is not emitted for it).

## The flow ended. info: {kind, amount (on success), error and text (on failure)}.
signal done(ok: bool, info: Dictionary)
signal _wake

const POLL_SEC := 1.5
const TIMEOUT_SEC := 20.0
const NO_FILL_TEXT := "No video right now, try again in a minute."  # l10n (show it as L10n.t(AdFlow.NO_FILL_TEXT))

var busy := false
var poll_sec := POLL_SEC
var timeout_sec := TIMEOUT_SEC
## Tests: (seconds) -> awaitable, in place of a scene-tree timer.
var sleep_fn := Callable()

var _ads: Ads = null
var _acc: Account = null
var _earned := false
var _closed := false
var _show_failed := false


## `ads` / `acc`: tests pass fakes; null = Ads.instance() / Account.instance() at the time of the call.
func _init(ads: Ads = null, acc: Account = null) -> void:
	_ads = ads
	_acc = acc

## True when rewarded ads can run here: the AdMob plugin is there and an Account (wallet) is active.
static func available() -> bool:
	var a := Ads.instance()
	return a != null and a.available() and Account.wallet_active()

func ads() -> Ads:
	return _ads if _ads != null else Ads.instance()

func account() -> Account:
	return _acc if _acc != null else Account.instance()

## Friendly copy for an error of `done`.
static func error_text(code: String) -> String:
	match code:
		"unavailable":
			return L10n.t("Videos aren’t available on this device.")
		"no_fill":
			return L10n.t(NO_FILL_TEXT)
		"closed":
			return L10n.t("Watch the whole video to get the reward.")
		"rejected":
			return L10n.t("We couldn’t confirm that video. Try another one in a minute.")
		"timeout":
			return L10n.t("Still checking your reward. It will show up soon.")
		"offline":
			return Account.offline_text("ads")
	return Account.error_text(code, "ads")

## Watches one ad for `kind` (see the top). Returns when done has been emitted.
func watch(kind: String, ref := "") -> void:
	if busy:
		return
	busy = true
	var res := await _run(kind, ref)
	busy = false
	var info: Dictionary = res.info
	if not info.has("text") and info.has("error"):
		info.text = error_text(str(info.error))
	done.emit(bool(res.ok), info)

func _run(kind: String, ref: String) -> Dictionary:
	var ad := ads()
	var acc := account()
	if ad == null or not ad.available() or acc == null or not acc.enabled:
		return _fail(kind, "unavailable")
	if not ad.is_ready():
		ad.load_rewarded()                         # (the next try finds one)
		return _fail(kind, "no_fill")
	var st: Dictionary = await acc.ads_start(kind, ref)
	if not is_instance_valid(self):
		return _fail(kind, "closed")
	if not st.get("ok", false):
		return _fail(kind, str(st.get("error", "server")))
	_earned = false
	_closed = false
	_show_failed = false
	ad.earned.connect(_on_earned)
	ad.closed.connect(_on_closed)
	ad.show_failed.connect(_on_show_failed)
	ad.show_rewarded(str(st.get("user_id", "")), str(st.get("custom_data", "")))
	while not _closed and not _show_failed:
		await _wake
		if not is_instance_valid(self):
			return _fail(kind, "closed")
	ad.earned.disconnect(_on_earned)
	ad.closed.disconnect(_on_closed)
	ad.show_failed.disconnect(_on_show_failed)
	if _show_failed:
		return _fail(kind, "no_fill")
	if not _earned:
		return _fail(kind, "closed")
	return await _poll(acc, kind, str(st.get("nonce", "")))

## GET /v1/ads/status every poll_sec until the answer is final or timeout_sec has passed.
func _poll(acc: Account, kind: String, nonce: String) -> Dictionary:
	var waited := 0.0
	while true:
		var r: Dictionary = await acc.ads_status(nonce)
		if not is_instance_valid(self):
			return _fail(kind, "closed")
		if r.get("ok", false):
			match str(r.get("status", "")):
				"granted":
					return {ok = true, info = {kind = kind, amount = Account._int(r.get("amount"), 0)}}
				"expired", "rejected":
					return _fail(kind, "rejected")
		if waited >= timeout_sec:
			break
		await _sleep(poll_sec)
		if not is_instance_valid(self):
			return _fail(kind, "closed")
		waited += poll_sec
	acc.refresh_me()                                # the reward may land a moment later: pick it up
	return _fail(kind, "timeout")

func _fail(kind: String, error: String) -> Dictionary:
	return {ok = false, info = {kind = kind, error = error, text = error_text(error)}}

func _sleep(sec: float) -> void:
	if sleep_fn.is_valid():
		await sleep_fn.call(sec)
	else:
		await Engine.get_main_loop().create_timer(sec).timeout

func _on_earned(_type: String, _amount: int) -> void:
	_earned = true

func _on_closed() -> void:
	_closed = true
	_wake.emit()

func _on_show_failed(_code: int, _message: String) -> void:
	_show_failed = true
	_wake.emit()
