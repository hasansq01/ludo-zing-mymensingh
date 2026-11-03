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
## watched = earned + closed | early = closed without the reward | fail = show failed
var show_result := "watched"
var privacy := true

func initialize() -> void:
	calls.append("initialize")

func request_consent(_test_device: String) -> void:
	calls.append("request_consent")
	consent_done.emit(true, privacy)

func show_privacy_options() -> void:
	calls.append("show_privacy_options")

func load_rewarded(_unit_id: String) -> void:
	calls.append("load_rewarded")
	ready = true
	rewarded_loaded.emit()

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
		_:
			rewarded_show_failed.emit(0, "internal error")
