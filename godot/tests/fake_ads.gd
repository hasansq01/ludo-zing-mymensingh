extends RefCounted
## A stand-in for the Kotlin AdMob plugin singleton (Ads' `singleton` argument), answers synchronous (build the Ads
## with deferred = false). `show_result` picks what show_rewarded() does.

signal consent_done(can_request_ads: bool, privacy_options_required: bool)
signal rewarded_loaded
signal rewarded_failed(code: int, message: String)
signal rewarded_earned(type: String, amount: int)
signal rewarded_closed
signal rewarded_show_failed(code: int, message: String)

var calls: Array = []
var ready := true
## watched = earned + closed | early = closed without the reward | fail = show failed | fail_once = fails, then watched
var show_result := "watched"
var privacy := true
## false: load_rewarded() fails (no fill) and nothing becomes ready
var load_fills := true

func initialize() -> void:
	calls.append("initialize")

func request_consent(_test_device: String) -> void:
	calls.append("request_consent")
	consent_done.emit(true, privacy)

func show_privacy_options() -> void:
	calls.append("show_privacy_options")

func load_rewarded(_unit_id: String) -> void:
	calls.append("load_rewarded")
	if not load_fills:
		rewarded_failed.emit(1158, "no fill")
		return
	ready = true
	rewarded_loaded.emit()

## LevelPlay's: drop the held ad, load a new one.
func reload_rewarded(unit_id: String) -> void:
	calls.append("reload_rewarded")
	ready = false
	load_rewarded(unit_id)

func is_rewarded_ready() -> bool:
	return ready

func show_rewarded(user_id: String, custom_data: String) -> void:
	calls.append("show_rewarded:%s:%s" % [user_id, custom_data])
	match show_result:
		"watched":
			ready = false
			rewarded_earned.emit("reward", 1)
			rewarded_closed.emit()
		"early":
			ready = false
			rewarded_closed.emit()
		"fail_once":                         # an expired ad: the show fails, the next ad plays
			show_result = "watched"
			ready = false
			rewarded_show_failed.emit(52200, "The ad has expired")
		_:
			rewarded_show_failed.emit(0, "internal error")
