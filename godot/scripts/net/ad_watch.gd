class_name AdWatch
extends RefCounted
## One rewarded ad from a UI, as a plain awaitable: `var r := await AdWatch.run(flow, "refill")` -> {ok, info}. (AdFlow
## emits `done` when it ends, possibly before the caller could await it; this connects first.)
##   info: {kind, amount} on success, {kind, error, text} on failure (AdFlow).

static func run(flow: AdFlow, kind: String, ref := "") -> Dictionary:
	var out := []
	flow.done.connect(func(ok: bool, info: Dictionary): out.append({ok = ok, info = info}), CONNECT_ONE_SHOT)
	flow.watch(kind, ref)
	while out.is_empty():
		if not is_instance_valid(flow) or not flow.is_inside_tree():
			return {ok = false, info = {kind = kind, error = "closed", text = AdFlow.error_text("closed")}}
		await flow.get_tree().process_frame
	return out[0]
