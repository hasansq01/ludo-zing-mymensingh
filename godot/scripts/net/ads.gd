class_name Ads
extends Node
## Rewarded ads (server/ECONOMY_V1.md section 5): a thin wrapper over one ads Android plugin singleton, "LevelPlay"
## (godot/android/plugins/levelplay, Unity LevelPlay mediation) or "AdMob" (godot/android/plugins/admob). Both have
## the same methods and signals (and the same UMP consent form). Which one: the project setting ludo_zing/ads/provider,
## "auto" (default) = LevelPlay when its plugin is in the build, else AdMob; "levelplay" / "admob" = only that one
## (see pick()). Everywhere no plugin is there (desktop, headless, web, the non-Gradle "Android Emulator" preset) it
## is a safe stub: available() is false, is_ready() is false, nothing is ever shown, and the asking calls answer
## later (deferred) with consent_done(false, false) / failed(-1, "unavailable") / show_failed(-1, "unavailable").
## Answers never arrive inside the call that asked.
##
## How the UI is expected to use it (rewarded only, never without a tap):
##   var ads := Ads.new(); add_child(ads)                  # once, e.g. in main.gd; keep it for the whole run
##   ads.request_consent()                                 # at first launch; -> consent_done(can_request, privacy_opts)
##   ads.consent_done.connect(func(can, _p): if can: ads.load_rewarded())
##   if ads.privacy_options_required(): show a "Privacy choices" row in Settings -> ads.show_privacy_options()
##   # An ad button (Rewards sheet, broke popup, coin-table result card) is enabled only while ads.available() and
##   # ads.is_ready() (listen to `loaded` / `closed` to refresh it). On tap:
##   #   1. POST /v1/ads/start {kind, ref?} -> {nonce, user_id, custom_data}   (server checks the daily cap first)
##   #   2. ads.show_rewarded(user_id, custom_data)   (AdMob: SSV options; LevelPlay: custom_uid / custom_nonce)
##   #   3. `earned` = the player watched enough; only now start polling GET /v1/ads/status?nonce= (every 1.5 s, up
##   #      to 20 s) and show the reward when the server says "granted". Nothing is granted from `earned` alone.
##   #   4. `closed` = the ad is gone (after `earned`, or the player quit early: no reward). `show_failed` = no ad
##   #      was shown (not loaded, SDK error): tell the player, the start nonce just expires.
##   # `earned` can come before `closed`; treat closed without earned as "no reward".
## A new ad is loaded by itself after one closes or fails to load / show, with backoff: 5 s, 15 s, 60 s (then 60 s
## again) between failures; a successful load starts the sequence over. Only once load_rewarded() has been called
## (so no ad traffic before consent) and only while the plugin exists. A load that fails with "consent" (code -2)
## is retried the same way, so the first ad comes as soon as the consent form has been answered.
##
## `failed` is about LOADING (code = the network's error code; -1 no activity, -2 consent not given yet, -3 LevelPlay
## has no app key); `show_failed` is about showing (code -1: nothing loaded or already showing).

## The consent form was answered (or not needed). can_request_ads false = no ads (consent refused / unavailable).
signal consent_done(can_request_ads: bool, privacy_options_required: bool)
## A rewarded ad is loaded: is_ready() is true.
signal loaded
signal failed(code: int, message: String)
## The player earned the reward (type, amount from the ad unit; the server decides what is really granted).
signal earned(type: String, amount: int)
## The ad was closed (watched or skipped).
signal closed
## show_rewarded() could not show an ad.
signal show_failed(code: int, message: String)

## The plugin singletons (never "Ads": that would shadow this class_name).
const LEVELPLAY := "LevelPlay"
const ADMOB := "AdMob"
## "auto" | "levelplay" | "admob" (godot/addons/levelplay registers it).
const PROVIDER_SETTING := "ludo_zing/ads/provider"
const UNIT_SETTING := "ludo_zing/ads/rewarded_unit"
const LEVELPLAY_UNIT_SETTING := "ludo_zing/ads/levelplay_rewarded_unit"
## Dev only: LevelPlay's integration test suite opens once the SDK is ready (never on in a committed project.godot).
const TEST_SUITE_SETTING := "ludo_zing/ads/levelplay_test_suite"
## Optional: a UMP test device hashed id (logcat prints it), to force the consent form in dev. Empty = none.
const TEST_DEVICE_SETTING := "ludo_zing/ads/test_device"
## AdMob: phones that get test ads from the real units (comma-separated hashed ids from the SDK's log line).
## (LevelPlay test devices are set in the LevelPlay dashboard.)
const TEST_ADS_SETTING := "ludo_zing/ads/test_ad_devices"
const UNAVAILABLE := "unavailable"
## Seconds before the next automatic load, by number of failures in a row (the last one repeats).
const BACKOFF := [5.0, 15.0, 60.0]

## Seconds until the pending automatic load, -1 when none is waiting (tests read it; a timer runs it in the tree).
var reload_in := -1.0
## Failures in a row since the last good load (drives BACKOFF).
var failures := 0
## The plugin in use: LEVELPLAY, ADMOB, or "" (the stub).
var provider := ""

static var _inst: Ads = null

var _pg: Object = null
var _deferred := true
var _wanted := false            # load_rewarded() was called: keep an ad ready
var _privacy := false
var _timer: SceneTreeTimer = null

## `singleton`: the Android plugin object; null = the one pick() chooses among the singletons that exist. Tests pass a
## fake with the same methods and signals (`kind` = which plugin it plays, default AdMob), and `deferred` false to
## get the answers inside the call.
func _init(singleton: Object = null, deferred := true, kind := "") -> void:
	_deferred = deferred
	var real := singleton == null
	if real:
		kind = pick(str(ProjectSettings.get_setting(PROVIDER_SETTING, "auto")), Engine.has_singleton(LEVELPLAY),
			Engine.has_singleton(ADMOB))
		if kind != "":
			singleton = Engine.get_singleton(kind)
	elif kind == "":
		kind = ADMOB
	_pg = singleton
	if _pg == null:
		return
	provider = kind
	# (an Android plugin singleton answers has_method false for its methods: the real plugins always have these)
	var test_ads := str(ProjectSettings.get_setting(TEST_ADS_SETTING, "")).strip_edges()
	if provider == ADMOB and test_ads != "" and (real or _pg.has_method("set_test_devices")):
		_pg.call("set_test_devices", test_ads)
	if provider == LEVELPLAY and bool(ProjectSettings.get_setting(TEST_SUITE_SETTING, false)) \
			and (real or _pg.has_method("set_test_suite")):
		_pg.call("set_test_suite", true)
	_connect("consent_done", _on_consent)
	_connect("rewarded_loaded", _on_loaded)
	_connect("rewarded_failed", _on_failed)
	_connect("rewarded_earned", _on_earned)
	_connect("rewarded_closed", _on_closed)
	_connect("rewarded_show_failed", _on_show_failed)

func _enter_tree() -> void:
	_inst = self

func _exit_tree() -> void:
	if _inst == self:
		_inst = null

## The Ads node of this run (main owns it), or null (tests, previews).
static func instance() -> Ads:
	return _inst if is_instance_valid(_inst) else null

## Tests: make this the current Ads (null clears it).
static func set_instance(a: Ads) -> void:
	_inst = a

## True on Android with an ads plugin built in.
func available() -> bool:
	return _pg != null

## Which plugin to drive: `setting` "auto" (or anything else) = LevelPlay when it is there, else AdMob; "levelplay" /
## "admob" = only that one. "" = none (the stub).
static func pick(setting: String, has_levelplay: bool, has_admob: bool) -> String:
	match setting.strip_edges().to_lower():
		"levelplay":
			return LEVELPLAY if has_levelplay else ""
		"admob":
			return ADMOB if has_admob else ""
	if has_levelplay:
		return LEVELPLAY
	return ADMOB if has_admob else ""

## The rewarded ad unit id of a provider (project settings: the LevelPlay unit, or the AdMob unit).
static func unit_id(kind := ADMOB) -> String:
	var key := LEVELPLAY_UNIT_SETTING if kind == LEVELPLAY else UNIT_SETTING
	return str(ProjectSettings.get_setting(key, "")).strip_edges()

## Starts the ads SDK when consent allows (request_consent / load_rewarded do it too; rarely needed).
func initialize() -> void:
	if _pg != null:
		_pg.call("initialize")

## UMP consent: shows the form where required (EEA / UK). -> consent_done(can_request_ads, privacy_options_required).
func request_consent() -> void:
	if _pg == null:
		_later(consent_done.emit.bind(false, false))
		return
	_pg.call("request_consent", str(ProjectSettings.get_setting(TEST_DEVICE_SETTING, "")).strip_edges())

## True when the consent flow says Settings should offer "Privacy choices" (known after consent_done).
func privacy_options_required() -> bool:
	return _privacy

## The UMP privacy options form (the "Privacy choices" row in Settings).
func show_privacy_options() -> void:
	if _pg != null:
		_pg.call("show_privacy_options")

## Loads a rewarded ad (the project's unit) and keeps one ready from now on (see the top). -> loaded / failed.
func load_rewarded() -> void:
	_wanted = true
	if _pg == null:
		_later(failed.emit.bind(-1, UNAVAILABLE))
		return
	_cancel_reload()
	_pg.call("load_rewarded", unit_id(provider))

## True when an ad is loaded and can be shown right now.
func is_ready() -> bool:
	return _pg != null and bool(_pg.call("is_rewarded_ready"))

## Shows the loaded ad with the server-side verification options from POST /v1/ads/start (`user_id` = account id,
## `custom_data` = nonce). -> earned, closed; or show_failed. Call it only from a tap.
func show_rewarded(user_id: String, custom_data: String) -> void:
	if _pg == null:
		_later(show_failed.emit.bind(-1, UNAVAILABLE))
		return
	_pg.call("show_rewarded", user_id, custom_data)

## Seconds to wait before the automatic load after `n` failures in a row (n >= 1).
static func backoff(n: int) -> float:
	return BACKOFF[clampi(n, 1, BACKOFF.size()) - 1]


# ---------- plugin signals ----------

func _on_consent(can: bool, privacy: bool) -> void:
	_privacy = privacy
	consent_done.emit(can, privacy)

func _on_loaded() -> void:
	failures = 0
	_cancel_reload()
	loaded.emit()

func _on_failed(code: int, message: String) -> void:
	failures += 1
	failed.emit(code, message)
	_schedule_reload(backoff(failures))

func _on_earned(type: String, amount: int) -> void:
	earned.emit(type, amount)

func _on_closed() -> void:
	closed.emit()
	# a fresh ad for the next tap: the first delay, as the player may want another one soon (not a failure)
	failures = 0
	_schedule_reload(backoff(1))

func _on_show_failed(code: int, message: String) -> void:
	show_failed.emit(code, message)
	# "already showing" must not queue a load under the ad on screen; anything else means this ad is gone
	if message != "already showing":
		failures += 1
		_schedule_reload(backoff(failures))


# ---------- reload ----------

func _schedule_reload(delay: float) -> void:
	if not _wanted or _pg == null or reload_in >= 0.0:
		return
	reload_in = delay
	if is_inside_tree():
		_timer = get_tree().create_timer(delay)
		_timer.timeout.connect(_on_reload_timer)

## The automatic load is due (the timer's timeout; tests call it).
func _on_reload_timer() -> void:
	_timer = null
	reload_in = -1.0
	if _wanted and _pg != null and not is_ready():
		_pg.call("load_rewarded", unit_id(provider))

func _cancel_reload() -> void:
	reload_in = -1.0
	if _timer != null and _timer.timeout.is_connected(_on_reload_timer):
		_timer.timeout.disconnect(_on_reload_timer)
	_timer = null


# ---------- helpers ----------

func _connect(sig: String, fn: Callable) -> void:
	if _pg.has_signal(sig):
		# plugin signals arrive on the main loop already; deferred keeps every answer out of the asking call
		_pg.connect(sig, fn, CONNECT_DEFERRED if _deferred else 0)
	else:
		push_warning("Ads: plugin has no signal %s" % sig)

func _later(fn: Callable) -> void:
	if _deferred:
		fn.call_deferred()
	else:
		fn.call()
