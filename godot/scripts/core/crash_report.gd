class_name CrashReport
extends RefCounted
## The pure half of crash / unexpected-exit reporting (CrashWatch, scripts/core/crash_watch.gd, is the live half):
## whether the previous run deserves a report, the report itself (POST /v1/diag/crash, server/src/diag.ts), the log
## tail and its scrubbing. No file writes, no clock, no network here: everything comes in as arguments (tests).
##
##   var d := CrashReport.decide(prev_session, exits, state, now_ms)   # {send, why, trigger, exit}
##   if d.send: var body := CrashReport.build(prev_session, d, info, CrashReport.log_tail(path), pid, account_id)
##
## When to report (decide):
##   - an exit record (Android 11+, ApplicationExitInfo via the plugin) newer than the last one handled says crash,
##     crash_native or anr: always ("exit_reason"); low_memory: when the process was not cached (importance < 400,
##     i.e. it was on screen or close to it) or the session was still live; a low-memory kill of a cached app in the
##     background is normal Android life and is not reported,
##   - otherwise the previous session never ended cleanly (no quit, no going to the background: the app died while
##     on screen) and the exit, if there is one, is not a benign one (the user / an update / a permission change),
##   - and fewer than MAX_PER_DAY reports were made today on this device.

const VERSION := 1
const PATH := "/v1/diag/crash"
const MAX_PER_DAY := 3
const LOG_TAIL_BYTES := 32768
const LOG_TAIL_LINES := 200
const TRACE_MAX := 65536
const SAMPLES_MAX := 40
const CRUMBS_MAX := 60
const CACHED_IMPORTANCE := 400           # ActivityManager.RunningAppProcessInfo.IMPORTANCE_CACHED
const BAD_REASONS := ["crash", "crash_native", "anr"]
const BENIGN_REASONS := ["user_requested", "user_stopped", "package_updated", "package_state_change",
	"permission_change"]
## An exit counts for a session when it happened after the session began (minus this slack, clock jitter).
const EXIT_SLACK_MS := 5000


# ---------- the decision ----------

## {send, why, trigger ("exit_reason" | "unclean" | ""), exit ({} when none)}. prev: the previous run's session
## record ({} when there was none); exits: the plugin's exit records, newest first; state: {day, count, last_exit_at}.
static func decide(prev: Dictionary, exits: Array, state: Dictionary, now_ms: int) -> Dictionary:
	var out := {send = false, why = "", trigger = "", exit = {}}
	var ex := pick_exit(prev, exits, int(state.get("last_exit_at", 0)))
	out.exit = ex
	var reason := str(ex.get("reason", ""))
	var unclean := not prev.is_empty() and not bool(prev.get("ended", false))
	if reason in BENIGN_REASONS:
		out.why = "benign:" + reason
		return out
	if reason in BAD_REASONS:
		out.trigger = "exit_reason"
	elif reason == "low_memory" and (unclean or int(ex.get("importance", CACHED_IMPORTANCE)) < CACHED_IMPORTANCE):
		out.trigger = "exit_reason"
	elif unclean:
		out.trigger = "unclean"
	else:
		out.why = "clean" if reason == "" else "clean:" + reason
		return out
	if sent_today(state, now_ms) >= MAX_PER_DAY:
		out.why = "cap"
		return out
	out.send = true
	out.why = out.trigger
	return out

## The exit record that belongs to the previous run: newer than `last_handled` (ms), the one carrying the previous
## session's id (setProcessStateSummary) if any, else the newest one since that session began ({} when none).
static func pick_exit(prev: Dictionary, exits: Array, last_handled: int) -> Dictionary:
	var sid := str(prev.get("sid", ""))
	var since := int(prev.get("started_at", 0)) - EXIT_SLACK_MS if not prev.is_empty() else 0
	var fresh: Array = []
	for e: Variant in exits:
		if e is Dictionary and int((e as Dictionary).get("at", 0)) > last_handled:
			fresh.append(e)
	if sid != "":
		for e: Dictionary in fresh:
			if str(e.get("summary", "")) == sid:
				return e
	for e: Dictionary in fresh:                      # newest first (the plugin's order)
		if int(e.get("at", 0)) >= since:
			return e
	return {}

## The newest exit time in `exits` (ms; `dflt` when none is newer): what the next launch has handled already.
static func newest_exit(exits: Array, dflt: int) -> int:
	var t := dflt
	for e: Variant in exits:
		if e is Dictionary:
			t = maxi(t, int((e as Dictionary).get("at", 0)))
	return t

## Reports made today (device-local day of `now_ms`).
static func sent_today(state: Dictionary, now_ms: int) -> int:
	return int(state.get("count", 0)) if str(state.get("day", "")) == day_of(now_ms) else 0

## `state` after one more report today.
static func count_one(state: Dictionary, now_ms: int) -> Dictionary:
	var s := state.duplicate()
	var d := day_of(now_ms)
	s.count = (int(s.get("count", 0)) if str(s.get("day", "")) == d else 0) + 1
	s.day = d
	return s

static func day_of(now_ms: int) -> String:
	return Time.get_date_string_from_unix_time(int(now_ms / 1000))


# ---------- the report ----------

## The POST /v1/diag/crash body. prev: the previous session record; d: decide()'s answer; info: the plugin's facts
## (diag_info, {} off Android); log: the previous run's log tail (scrubbed here again).
static func build(prev: Dictionary, d: Dictionary, info: Dictionary, log: String, pid: String,
		account_id := "") -> Dictionary:
	var ex: Dictionary = (d.get("exit", {}) as Dictionary).duplicate() if d.get("exit") is Dictionary else {}
	if ex.has("trace"):
		ex.trace = scrub(str(ex.trace), false).left(TRACE_MAX)   # (BuildIds are long hex: kept)
	if ex.has("description"):
		ex.description = scrub(str(ex.description)).left(2000)
	var app: Dictionary = prev.get("app", {}) if prev.get("app") is Dictionary else {}
	if app.is_empty() or int(app.get("code", 0)) == 0:
		app = app_of(info)
	var dev: Dictionary = prev.get("device", {}) if prev.get("device") is Dictionary else {}
	dev = dev.duplicate()
	for k in ["model", "os_version", "sdk"]:
		if not dev.has(k) or str(dev[k]) == "":
			var v: Variant = {model = info.get("model", ""), os_version = info.get("release", ""),
				sdk = info.get("sdk", 0)}[k]
			dev[k] = v
	var samples: Array = prev.get("samples", []) if prev.get("samples") is Array else []
	var crumbs: Array = prev.get("crumbs", []) if prev.get("crumbs") is Array else []
	var body := {
		v = VERSION,
		pid = pid.left(64),
		sid = str(prev.get("sid", "")) if str(prev.get("sid", "")) != "" else "x" + str(ex.get("at", 0)),
		trigger = str(d.get("trigger", "")),
		app = app,
		device = dev,
		started_at = int(prev.get("started_at", 0)),
		last_at = int(prev.get("last_at", 0)),
		ended = bool(prev.get("ended", false)),
		end = str(prev.get("end", "")),
		foreground = bool(prev.get("fg", true)),
		screen = str(prev.get("screen", "")),
		match = prev.get("match") if prev.get("match") is Dictionary and not (prev.match as Dictionary).is_empty() else null,
		samples = samples.slice(-SAMPLES_MAX),
		crumbs = crumbs.slice(-CRUMBS_MAX),
		exit = ex if not ex.is_empty() else null,
		log = scrub(log),
	}
	if account_id != "":
		body.account_id = account_id
	return body

## {code, name} from the plugin's facts ({code 0, name "dev"} off Android).
static func app_of(info: Dictionary) -> Dictionary:
	return {code = int(info.get("version_code", 0)), name = str(info.get("version_name", "dev"))}


# ---------- the log ----------

## The last `max_lines` lines of the file at `path` within its last `max_bytes` bytes ("" when unreadable). Reads only
## that tail, so a long log costs nothing.
static func log_tail(path: String, max_bytes := LOG_TAIL_BYTES, max_lines := LOG_TAIL_LINES) -> String:
	if path == "" or not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var size := f.get_length()
	var from := maxi(0, size - max_bytes)
	f.seek(from)
	var text := f.get_buffer(size - from).get_string_from_utf8()
	f.close()
	if from > 0:
		var nl := text.find("\n")
		text = text.substr(nl + 1) if nl >= 0 else text   # the first line was cut: drop it
	var lines := text.split("\n")
	if lines.size() > max_lines + 1:
		text = "\n".join(lines.slice(lines.size() - max_lines - 1))
	return text

## The previous run's log: Godot copies godot.log aside (with a time stamp in its name) when a run starts, so it is
## the newest of the other *.log files in `dir`. "" when there is none (first run, file logging off).
static func previous_log(dir := "user://logs", current := "godot.log") -> String:
	var da := DirAccess.open(dir)
	if da == null:
		return ""
	var best := ""
	for f in da.get_files():
		if f.get_extension() == "log" and f != current and f > best:
			best = f                                     # (the names sort by their time stamp)
	return dir.path_join(best) if best != "" else ""

static var _scrubbers: Array = []

## Removes what must never leave the phone: bearer / session tokens, JWTs, purchase tokens and other long opaque
## strings (unless `long_tokens` is false: a native trace's BuildIds), e-mail addresses, the values of token /
## session / password fields.
static func scrub(text: String, long_tokens := true) -> String:
	if text == "":
		return text
	if _scrubbers.is_empty():
		for p: Array in [
			["(?i)(bearer|authorization:?)(\\s+bearer)?\\s+[^\\s\"']+", "$1$2 [redacted]"],
			["(?i)(\"?(?:token|session|purchase_?token|password|secret|auth_?code|server_auth_code|id_token|access_token|refresh_token|email)\"?\\s*[:=]\\s*)\"?[^\\s\",}]+\"?", "$1[redacted]"],
			["eyJ[A-Za-z0-9_\\-]+\\.[A-Za-z0-9_\\-]+(\\.[A-Za-z0-9_\\-]*)?", "[redacted]"],
			["[A-Za-z0-9._%+\\-]+@[A-Za-z0-9.\\-]+\\.[A-Za-z]{2,}", "[email]"],
			["[A-Za-z0-9_\\-.]{32,}", "[redacted]"],
		]:
			var re := RegEx.new()
			re.compile(p[0])
			_scrubbers.append([re, p[1]])
	var out := text
	for i in _scrubbers.size():
		if i == _scrubbers.size() - 1 and not long_tokens:
			break
		out = (_scrubbers[i][0] as RegEx).sub(out, _scrubbers[i][1], true)
	return out
