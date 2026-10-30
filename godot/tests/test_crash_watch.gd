extends "res://tests/test_suite.gd"
## Crash / unexpected-exit reporting: CrashReport's rules (when a run counts as died, which exit record belongs to
## it, the daily cap, the report body, the log tail and its scrubbing) and CrashWatch's record (begin / samples /
## a clean end on background or quit / back again, the old record kept for the next launch, one report per dead
## run, sent once, kept while offline, dropped on a refusal), with a fake plugin and a fake sender. Everything is
## written under a scratch user:// folder (never save.json) that is removed at the end.

const R := preload("res://scripts/core/crash_report.gd")
const W := preload("res://scripts/core/crash_watch.gd")

const DAY_MS := 86400000
const NOW := 1761800000000               # 2025-10-30 (any fixed time)

## Stands in for NotificationsPlugin's diag methods (Diag.kt): diag_info(since_ms, max_exits) -> JSON text.
class FakeNative extends RefCounted:
	var exits: Array = []
	var states: Array = []
	var asked_since: Array = []
	func diag_info(since_ms: int, max_exits: int) -> String:
		asked_since.append(since_ms)
		return JSON.stringify({sdk = 36, release = "16", manufacturer = "INFINIX", model = "Infinix X6880",
			version_code = 9, version_name = "0.2.1", installer = "com.android.vending", low_ram_device = false,
			mem_class_mb = 256, exits = exits.slice(0, max_exits)})
	func diag_set_state(s: String) -> void:
		states.append(s)

var _root: Node
var _dir := ""
var _sent: Array = []
var _answer := {ok = true, status = 200}

func run() -> void:
	_root = (Engine.get_main_loop() as SceneTree).root
	_dir = "user://test_diag_%d" % (Time.get_ticks_usec() % 1000000)
	_decide_tests()
	_build_tests()
	_log_tests()
	await _watch_tests()
	_wiring_tests()
	_rm_tree(_dir)


# ---------- CrashReport.decide ----------

func _decide_tests() -> void:
	var live := {sid = "s1", started_at = NOW - 600000, ended = false}
	var ended := {sid = "s1", started_at = NOW - 600000, ended = true}
	var d := R.decide(live, [], {}, NOW)
	check("decide: a run that never ended is reported (unclean)", d.send and d.trigger == "unclean", d)
	d = R.decide(ended, [], {}, NOW)
	check("decide: a run that ended (quit / background) is not", not d.send and d.why == "clean", d)
	d = R.decide({}, [], {}, NOW)
	check("decide: no previous record, no exit: nothing", not d.send, d)
	var crash := {reason = "crash_native", at = NOW - 1000, importance = 100}
	d = R.decide(ended, [crash], {}, NOW)
	check("decide: a native crash after going to the background still counts", d.send and d.trigger == "exit_reason" and d.exit.reason == "crash_native", d)
	d = R.decide(ended, [{reason = "anr", at = NOW - 1000, importance = 100}], {}, NOW)
	check("decide: an ANR counts", d.send and d.trigger == "exit_reason", d)
	d = R.decide(ended, [crash], {last_exit_at = NOW - 1000}, NOW)
	check("decide: an exit handled at an earlier launch is not reported again", not d.send and d.exit.is_empty(), d)
	d = R.decide(ended, [{reason = "crash", at = NOW - 700000}], {}, NOW)
	check("decide: an exit from before the session began is not this run's", not d.send, d)
	d = R.decide(ended, [{reason = "low_memory", at = NOW - 1000, importance = 400}], {}, NOW)
	check("decide: a low-memory kill of a cached (background) app is normal: not reported", not d.send and d.why == "clean:low_memory", d)
	d = R.decide(ended, [{reason = "low_memory", at = NOW - 1000, importance = 100}], {}, NOW)
	check("decide: a low-memory kill in the foreground is reported", d.send and d.trigger == "exit_reason", d)
	d = R.decide(live, [{reason = "low_memory", at = NOW - 1000, importance = 400}], {}, NOW)
	check("decide: a low-memory kill while the record was live is reported", d.send and d.exit.reason == "low_memory", d)
	for r in ["user_requested", "user_stopped", "package_updated"]:
		d = R.decide(live, [{reason = r, at = NOW - 1000}], {}, NOW)
		check("decide: %s is not a crash, even unclean" % r, not d.send and d.why == "benign:" + r, d)
	d = R.decide(live, [{reason = "signaled", at = NOW - 1000}], {}, NOW)
	check("decide: unclean + another reason (signaled) is reported as unclean", d.send and d.trigger == "unclean" and d.exit.reason == "signaled", d)
	var today := {day = R.day_of(NOW), count = R.MAX_PER_DAY}
	d = R.decide(live, [crash], today, NOW)
	check("decide: at most MAX_PER_DAY reports a day", not d.send and d.why == "cap", d)
	d = R.decide(live, [crash], {day = R.day_of(NOW - DAY_MS), count = 9}, NOW)
	check("decide: yesterday's count does not hold today back", d.send, d)
	var e_old := {reason = "crash", at = NOW - 5000, summary = "s1"}
	var e_new := {reason = "low_memory", at = NOW - 1000, summary = "s2"}
	check("pick_exit: the record carrying the session id wins", R.pick_exit(live, [e_new, e_old], 0) == e_old)
	check("pick_exit: otherwise the newest since the session began", R.pick_exit({sid = "zz", started_at = NOW - 9000}, [e_new, e_old], 0) == e_new)
	check("newest_exit: the latest time, or the old mark", R.newest_exit([e_old, e_new], 7) == NOW - 1000 and R.newest_exit([], 7) == 7)
	var s1 := R.count_one({}, NOW)
	var s2 := R.count_one(s1, NOW)
	var s3 := R.count_one(s2, NOW + DAY_MS)
	check("count_one: counts per day", s2.count == 2 and s3.count == 1 and s3.day == R.day_of(NOW + DAY_MS), [s2, s3])


# ---------- CrashReport.build / scrub ----------

func _build_tests() -> void:
	var prev := {sid = "abc", app = {code = 8, name = "0.2.0"}, device = {model = "Infinix X6880", gpu = "Mali-G57 MC2",
		gpu_api = "OpenGL ES 3.2"}, started_at = NOW - 60000, last_at = NOW - 2000, ended = false, fg = true,
		screen = "ludo", match = {game = "ludo", mode = "cpu", minutes = 4.5}, samples = [], crumbs = [{t = 0, e = "start", d = ""}]}
	for i in 50:
		prev.samples.append({t = i * 15, mem = 200.0 + i, mem_peak = 260.0})
	var ex := {reason = "crash_native", at = NOW - 1000, pss_kb = 250000, rss_kb = 300000,
		description = "crash by user@example.com", trace = "#00 pc 0000000000a1b2c3  libgodot_android.so (BuildId: 270121fef88100c19643517c328b5868e01d345c)"}
	var d := {send = true, trigger = "exit_reason", exit = ex}
	var log := "start\nAuthorization: Bearer abc.def.ghi\nsession=" + "q".repeat(40) + "\nmail me at a.b@c.com\nend"
	var b := R.build(prev, d, {version_code = 9, version_name = "x"}, log, "p".repeat(24), "acc_1")
	check("build: the contract's fields", b.v == 1 and b.pid == "p".repeat(24) and b.sid == "abc" and b.trigger == "exit_reason" \
		and b.screen == "ludo" and b.foreground and not b.ended and b.match.mode == "cpu" and b.account_id == "acc_1", b)
	check("build: the app version of the dead run (not this one's)", b.app.code == 8 and b.app.name == "0.2.0", b.app)
	check("build: the last 40 samples", (b.samples as Array).size() == R.SAMPLES_MAX and b.samples[-1].t == 49 * 15, (b.samples as Array).size())
	check("build: the exit with its pss / rss", b.exit.reason == "crash_native" and b.exit.pss_kb == 250000 and b.exit.rss_kb == 300000, b.exit)
	check("build: the trace keeps its BuildId", str(b.exit.trace).contains("270121fef88100c19643517c328b5868e01d345c"), b.exit.trace)
	check("build: the description is scrubbed", not str(b.exit.description).contains("@"), b.exit.description)
	var lg := str(b.log)
	check("build: the log loses bearer tokens, session values and e-mails", not lg.contains("abc.def") and not lg.contains("qqqq") \
		and not lg.contains("a.b@c.com") and lg.begins_with("start") and lg.ends_with("end"), lg)
	var bare := R.build({}, {trigger = "exit_reason", exit = {reason = "anr", at = 5}}, {version_code = 9, version_name = "0.2.1",
		model = "X", release = "16", sdk = 36}, "", "p".repeat(20))
	check("build: no record: the app and device from the plugin, a sid from the exit", bare.app.code == 9 and bare.device.model == "X" \
		and bare.device.os_version == "16" and bare.sid == "x5" and bare.match == null and not bare.has("account_id"), bare)
	check("scrub: a JWT", R.scrub("t=eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.sig ok") == "t=[redacted] ok", R.scrub("t=eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.sig ok"))
	check("scrub: a JSON token field", not R.scrub("{\"purchase_token\":\"abcd1234\",\"x\":1}").contains("abcd1234"), R.scrub("{\"purchase_token\":\"abcd1234\",\"x\":1}"))
	check("scrub: a long opaque string", R.scrub("id " + "Ab3".repeat(15)) == "id [redacted]")
	check("scrub: ordinary log lines stay", R.scrub("[ludo] game over: winner Red reward=50 res://scripts/main.gd:120") \
		== "[ludo] game over: winner Red reward=50 res://scripts/main.gd:120")


# ---------- the log ----------

func _log_tests() -> void:
	var logs := _dir.path_join("logs")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(logs))
	var lines: PackedStringArray = []
	for i in 500:
		lines.append("line %d" % i)
	_put(logs.path_join("godot2026-10-29T10.00.00.log"), "old run")
	_put(logs.path_join("godot2026-10-30T09.00.00.log"), "\n".join(lines) + "\n")
	_put(logs.path_join("godot.log"), "this run")
	var prev := R.previous_log(logs)
	check("previous_log: the newest copy, not this run's godot.log", prev.ends_with("godot2026-10-30T09.00.00.log"), prev)
	var tail := R.log_tail(prev)
	var tl := tail.strip_edges().split("\n")
	check("log_tail: the last 200 lines", tl.size() == R.LOG_TAIL_LINES and tl[-1] == "line 499" and tl[0] == "line 300", [tl.size(), tl[0], tl[-1]])
	var small := R.log_tail(prev, 100).strip_edges().split("\n")
	check("log_tail: only the last bytes, the cut line dropped", small[-1] == "line 499" and small[0].begins_with("line ") and tail.length() > 100 and small.size() < 15, small)
	check("log_tail / previous_log: nothing there -> \"\"", R.log_tail("") == "" and R.previous_log(_dir.path_join("none")) == "")


# ---------- CrashWatch ----------

func _watch(native: Object, now: int) -> W:
	var w := W.new(native)
	w.dir = _dir.path_join("w")
	w.log_dir = _dir.path_join("logs")
	w.clock = func() -> int: return now
	w.send_fn = _fake_send
	w.send_delay_sec = 0.0
	w.retry_sec = 0.0
	w.write_gap_ms = 0
	w.proc_status_path = ""
	w.context_fn = func() -> Dictionary: return {screen = "ludo", match = {game = "ludo", mode = "cpu", minutes = 1.0}}
	return w

func _fake_send(body: Dictionary) -> Dictionary:
	_sent.append(body)
	return _answer

func _file(name: String) -> Dictionary:
	var p := _dir.path_join("w").path_join(name)
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(p)) if FileAccess.file_exists(p) else null
	return v if v is Dictionary else {}

func _watch_tests() -> void:
	var nat := FakeNative.new()
	var w := _watch(nat, NOW)
	w.begin(false)
	_root.add_child(w)
	var rec := _file(W.SESSION)
	check("begin: session.json with app, device and a first sample", rec.get("sid", "") == w.session.sid and rec.app.code == 9 \
		and rec.device.model == "Infinix X6880" and rec.device.os_version == "16" and (rec.samples as Array).size() == 1 \
		and rec.started_at == NOW and not rec.ended, rec)
	check("begin: the session id goes to the plugin (it comes back with the exit record)", nat.states == [w.session.sid], nat.states)
	check("begin: the device has the GPU strings", rec.device.has("gpu") and rec.device.has("gpu_vendor") and rec.device.has("gpu_api"), rec.device.keys())
	check("begin: the record is small", FileAccess.get_file_as_string(_dir.path_join("w").path_join(W.SESSION)).length() < 4000)
	w.set_screen("ludo")
	w.note("sheet", "PauseSheet")
	w.sample()
	rec = _file(W.SESSION)
	check("set_screen / sample: the event, the context and the samples", rec.screen == "ludo" and rec.match.mode == "cpu" \
		and (rec.crumbs as Array).any(func(c): return c.e == "screen" and c.d == "ludo") and (rec.samples as Array).size() == 3, rec)
	var smp: Dictionary = rec.samples[-1]
	check("sample: memory, fps, objects, nodes, foreground", smp.has("mem") and smp.has("vmem") and smp.has("fps") \
		and smp.has("objects") and smp.has("nodes") and smp.fg == true, smp)
	for i in 30:
		w.sample()
	check("sample: only the last SAMPLES_KEPT are kept", (w.session.samples as Array).size() == W.SAMPLES_KEPT)
	w._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	rec = _file(W.SESSION)
	check("background: the record ends cleanly, not in the foreground", rec.ended and rec.end == "background" and not rec.fg \
		and rec.samples[-1].fg == false, [rec.ended, rec.end, rec.fg])
	w._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	rec = _file(W.SESSION)
	check("resume: live again", not rec.ended and rec.fg and (rec.crumbs as Array)[-1].e == "resume", [rec.ended, rec.fg])
	# the app dies here (no end): the next launch finds the record and reports it
	var dead_sid: String = w.session.sid
	_die(w)
	_put(_dir.path_join("logs").path_join("godot2026-10-30T09.00.00.log"), "boot\nERROR: Out of memory\n")
	nat.exits = [{reason = "low_memory", at = NOW + 1000, importance = 100, pss_kb = 400000, rss_kb = 450000, summary = dead_sid}]
	var w2 := _watch(nat, NOW + 5000)
	w2.begin(false)
	_root.add_child(w2)
	check("next launch: the dead record moved to prev.json", _file(W.PREV).get("sid", "") == dead_sid)
	await w2.check_previous()
	check("check_previous: reported once, with the exit and the log", _sent.size() == 1 and _sent[0].sid == dead_sid \
		and _sent[0].exit.reason == "low_memory" and str(_sent[0].log).contains("Out of memory") and _sent[0].screen == "ludo", _sent)
	check("check_previous: the plugin is asked for exits newer than the last handled one", nat.asked_since == [0, 0], nat.asked_since)
	check("check_previous: prev.json and pending.json gone, the exit marked handled, one counted", _file(W.PREV).is_empty() \
		and _file(W.PENDING).is_empty() and _file(W.STATE).last_exit_at == NOW + 1000 and _file(W.STATE).count == 1, _file(W.STATE))
	# a clean quit: nothing next time
	w2.mark_ended("quit")
	_root.remove_child(w2)
	w2.free()
	var w3 := _watch(nat, NOW + 9000)
	w3.begin(false)
	_root.add_child(w3)
	check("next launch: asked for exits after the handled one", nat.asked_since[-1] == NOW + 1000, nat.asked_since)
	await w3.check_previous()
	check("after a clean quit: no report (and the old exit is not reported again)", _sent.size() == 1 and not w3.last_decision.send, w3.last_decision)
	# offline: kept, tried twice in this run, sent at a later launch
	_die(w3)
	_answer = {ok = false, status = 0}
	var w4 := _watch(nat, NOW + 20000)
	w4.begin(false)
	_root.add_child(w4)
	await w4.check_previous()
	check("offline: tried twice (now and once later), kept for next time", _sent.size() == 3 and _file(W.PENDING).get("tries", 0) == 2, [_sent.size(), _file(W.PENDING)])
	_answer = {ok = true, status = 200}
	await w4.send_pending()
	check("back online: sent, then gone", _sent.size() == 4 and _file(W.PENDING).is_empty())
	check("the account id is attached when there is one, never a session token", not JSON.stringify(_sent[-1]).contains("Bearer"))
	# a refusal (429 / 400) is not retried
	_die(w4)
	_answer = {ok = false, status = 429}
	var w5 := _watch(nat, NOW + 30000)
	w5.begin(false)
	_root.add_child(w5)
	await w5.check_previous()
	check("refused (429): tried once, dropped", _sent.size() == 5 and _file(W.PENDING).is_empty(), _sent.size())
	# the daily cap: the fourth dead run of the day is not reported
	_die(w5)
	_answer = {ok = true, status = 200}
	var w6 := _watch(nat, NOW + 40000)
	w6.begin(false)
	_root.add_child(w6)
	await w6.check_previous()
	check("cap: a fourth report the same day is not made", _sent.size() == 5 and w6.last_decision.why == "cap", [_sent.size(), w6.last_decision])
	w6.mark_ended("quit")
	_root.remove_child(w6)
	w6.free()
	var off := W.new()
	off.enabled = false
	off.dir = _dir.path_join("off")
	off.begin()
	off.sample()
	check("disabled: writes nothing", not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(off.dir)))
	off.free()
	var ps := _dir.path_join("status")
	_put(ps, "Name:\tgodot\nVmHWM:\t  512000 kB\nVmRSS:\t  409600 kB\nThreads:\t40\n")
	var st := W.proc_status(ps)
	check("proc_status: RSS and peak RSS in MB", is_equal_approx(float(st.rss), 400.0) and is_equal_approx(float(st.hwm), 500.0), st)
	check("proc_status: no /proc -> {}", W.proc_status(_dir.path_join("nope")).is_empty())
	check("should_run: exported builds yes; editor runs only with --diag; --no-diag off",
		W.should_run(PackedStringArray(["--diag"])) and not W.should_run(PackedStringArray(["--diag", "--no-diag"])) \
		and W.should_run(PackedStringArray()) == (not OS.has_feature("editor")))


# ---------- wiring ----------

func _wiring_tests() -> void:
	var main_src := FileAccess.get_file_as_string("res://scripts/main.gd")
	check("main: the watch is made first and gets the context", main_src.contains("crash_watch = CrashWatch.new()") \
		and main_src.contains("crash_watch.context_fn = diag_context"))
	check("main: screens, the previous run and the quit reach the watch", main_src.contains("crash_watch.set_screen(s)") \
		and main_src.contains("crash_watch.check_previous.call_deferred()") and main_src.contains("crash_watch.mark_ended(\"quit\")"))
	check("project: file logging on for phones, flushed on every print (the tail survives a kill)",
		FileAccess.get_file_as_string("res://project.godot").contains("file_logging/enable_file_logging.mobile=true") \
		and bool(ProjectSettings.get_setting("application/run/flush_stdout_on_print", false)))
	var kt := FileAccess.get_file_as_string("res://android/plugins/notifications/src/main/java/com/flipfold/ludozing/notifications/NotificationsPlugin.kt")
	check("plugin: diag_info(sinceMs, maxExits) and diag_set_state(summary)", kt.contains("fun diag_info(sinceMs: Long, maxExits: Int): String") \
		and kt.contains("fun diag_set_state(summary: String)"))


# ---------- helpers ----------

## The process is killed: no quit, no background, no _exit_tree end (the record stays live on disk).
func _die(w: Node) -> void:
	w.set("_started", false)
	_root.remove_child(w)
	w.free()

func _put(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()

func _rm_tree(path: String) -> void:
	var da := DirAccess.open(path)
	if da == null:
		return
	for f in da.get_files():
		da.remove(f)
	for d in da.get_directories():
		_rm_tree(path.path_join(d))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
