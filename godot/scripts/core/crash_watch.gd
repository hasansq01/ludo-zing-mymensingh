class_name CrashWatch
extends Node
## Crash / unexpected-exit reporting (the pure rules: CrashReport, scripts/core/crash_report.gd). main.gd owns one
## (`crash_watch`), created first thing in its _ready.
##
## Breadcrumbs: a small "session" record in user://diag/session.json (never inside save.json): app version, a session
## id, start time, the device (model, Android version, CPU count, GPU renderer / vendor / GL version, screen, RAM,
## quality tier, the plugin's facts), the screen and match on screen (main's diag_context()), the last few events
## (crumbs: screen changes, sheets, pause / resume, memory warnings) and a sample every SAMPLE_SEC and on each
## screen change (RSS and peak RSS from /proc/self/status, Godot's static and video memory, FPS, objects, nodes, draw
## calls, the phone's free RAM, foreground or not). Writes are small (a few KB), atomic (tmp + rename) and at most one
## per MIN_WRITE_GAP_MS.
## A clean end: a quit, or going to the background (Android may kill a backgrounded app; that is not a crash). The
## record says `ended` and whether the app was in the foreground at its last sample; coming back clears `ended`.
##
## Next launch (begin(): the old record moves to prev.json; check_previous(), after the splash): CrashReport.decide()
## with the plugin's exit records (Android 11+: ApplicationExitInfo reason / importance / PSS / RSS / description,
## the trace of a native crash or ANR, and the session id this run handed over with diag_set_state) says whether the
## last run died. Then ONE report (CrashReport.build: the record, the exit, the previous run's user://logs tail,
## scrubbed) is kept in pending.json and POSTed to /v1/diag/crash a few seconds later through Account (the session
## when there is one), again once RETRY_SEC later when offline, and on later launches for up to 3 days / 4 tries.
## At most CrashReport.MAX_PER_DAY reports a day. Nothing here blocks the game, and every failure is silent.
##
## The plugin (NotificationsPlugin: diag_info(since_ms, max_exits) -> JSON text, diag_set_state(text)) is optional:
## off Android `native` is null and the record alone decides ("unclean").

const DIR := "user://diag"
const LOG_DIR := "user://logs"
const SESSION := "session.json"
const PREV := "prev.json"
const STATE := "state.json"
const PENDING := "pending.json"
const SINGLETON := "NotificationsPlugin"
const SAMPLE_SEC := 15.0
const MIN_WRITE_GAP_MS := 2000
const SAMPLES_KEPT := 20                 # 5 minutes at SAMPLE_SEC
const CRUMBS_KEPT := 40
const EXITS_ASKED := 5
const SEND_DELAY_SEC := 6.0              # after check_previous: the guest session is usually back by then
const RETRY_SEC := 60.0
const PENDING_MAX_AGE_MS := 3 * 86400 * 1000
const PENDING_MAX_TRIES := 4
const MB := 1048576.0

static var _inst: CrashWatch = null

var enabled := true                      ## false: does nothing at all (editor runs without --diag)
var dir := DIR                           ## tests: a scratch folder
var log_dir := LOG_DIR
var native: Object = null                ## the plugin, or a fake with diag_info / diag_set_state (null: none)
var context_fn := Callable()             ## () -> {screen, match, paused}: what is on screen (main.diag_context)
var clock := Callable()                  ## () -> unix ms (tests; the system clock by default)
var send_fn := Callable()                ## (body) -> {ok, status}: tests; Account.request by default
var send_delay_sec := SEND_DELAY_SEC
var retry_sec := RETRY_SEC
var sample_sec := SAMPLE_SEC
var write_gap_ms := MIN_WRITE_GAP_MS     ## tests: 0 (every write lands at once)
var proc_status_path := "/proc/self/status"
var session: Dictionary = {}             ## this run's record (what session.json holds)
var info: Dictionary = {}                ## the plugin's facts for this launch (diag_info), {} off Android
var last_decision: Dictionary = {}       ## check_previous's CrashReport.decide() answer (tests, logs)
var _started := false
var _t0 := 0
var _last_write := -1000000
var _write_soon := false
var _screen_noted := ""                  # the last screen set_screen() recorded
var _sending := false
var _timer: Timer


func _init(native_: Object = null) -> void:
	native = native_
	process_mode = Node.PROCESS_MODE_ALWAYS

func _enter_tree() -> void:
	_inst = self

func _exit_tree() -> void:
	if _started and not bool(session.get("ended", false)):
		mark_ended("exit")                       # the tree is going away: a quit
	if _inst == self:
		_inst = null

## The watch of this run, or null.
static func instance() -> CrashWatch:
	return _inst if is_instance_valid(_inst) else null

## Exported builds always watch; editor runs only with --diag (they would report every stop in the debugger).
static func should_run(args: PackedStringArray) -> bool:
	if args.has("--no-diag"):
		return false
	return args.has("--diag") or not OS.has_feature("editor")

func _ready() -> void:
	if enabled and not _started:
		begin()


# ---------- the session record ----------

## Starts this run's record: the last run's moves to prev.json (kept if an earlier unchecked one died there), the
## plugin is asked for its facts and given the session id, the first sample is written and the timer started.
func begin(start_timer := true) -> void:
	if not enabled or _started:
		return
	_started = true
	_t0 = Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var cur := _read(SESSION)
	if not cur.is_empty():
		var old := _read(PREV)
		if old.is_empty() or bool(old.get("ended", false)):
			_write_json(PREV, cur)
		_remove(SESSION)
	if native == null and Engine.has_singleton(SINGLETON):
		native = Engine.get_singleton(SINGLETON)
	info = _native_info(int(_read(STATE).get("last_exit_at", 0)))
	var now := _now()
	var sid := "%x%s" % [now, Crypto.new().generate_random_bytes(4).hex_encode()]
	session = {v = CrashReport.VERSION, sid = sid, app = CrashReport.app_of(info), device = device_facts(info),
		started_at = now, last_at = now, ended = false, end = "", fg = true, screen = "", match = null,
		samples = [], crumbs = []}
	if native != null and native.has_method("diag_set_state"):
		native.call("diag_set_state", sid)
	note("start", "%s %s" % [session.app.name, session.app.code])
	sample()
	if start_timer:
		_timer = Timer.new()
		_timer.wait_time = sample_sec
		_timer.timeout.connect(sample)
		add_child(_timer)
		_timer.start()

## The device as the report shows it: Godot's view plus the plugin's facts (Android).
static func device_facts(native_info: Dictionary = {}) -> Dictionary:
	var headless := DisplayServer.get_name() == "headless"
	var scr: Vector2i = DisplayServer.screen_get_size() if not headless else Vector2i.ZERO
	var ram := Quality.meminfo_total()
	if ram <= 0.0:
		ram = float(OS.get_memory_info().get("physical", 0))
	var d := {
		model = OS.get_model_name(), os = OS.get_name(), os_version = OS.get_version(),
		cpu_count = OS.get_processor_count(), cpu = OS.get_processor_name(),
		gpu = RenderingServer.get_video_adapter_name(), gpu_vendor = RenderingServer.get_video_adapter_vendor(),
		gpu_api = RenderingServer.get_video_adapter_api_version(),
		screen = "%dx%d" % [scr.x, scr.y], ram_gb = snappedf(ram / 1073741824.0, 0.01), tier = Quality.tier(),
	}
	for k in ["sdk", "manufacturer", "brand", "device", "hardware", "soc", "abi", "fingerprint", "installer",
			"low_ram_device", "mem_class_mb", "large_mem_class_mb", "ram_total_mb"]:
		if native_info.has(k):
			d[k] = native_info[k]
	if native_info.has("release"):
		d.os_version = str(native_info.release)
	if str(native_info.get("model", "")) != "":
		d.model = "%s %s" % [str(native_info.get("manufacturer", "")), str(native_info.model)] if \
			not str(native_info.model).to_lower().begins_with(str(native_info.get("manufacturer", "")).to_lower()) \
			else str(native_info.model)
	return d

## One event for the record (kept to the last CRUMBS_KEPT). Not written by itself: the next sample or screen
## change carries it.
func note(event: String, detail := "") -> void:
	if not _started:
		return
	var c: Array = session.crumbs
	c.append({t = _t(), e = event, d = detail.left(80)})
	if c.size() > CRUMBS_KEPT:
		session.crumbs = c.slice(-CRUMBS_KEPT)

## The screen changed (main._set_screen): an event and a fresh sample, written soon.
func set_screen(s: String) -> void:
	if not _started or s == _screen_noted:
		return
	_screen_noted = s
	note("screen", s)
	sample()

## A sample of memory / FPS / objects with the context, then a (rate-limited) write.
func sample() -> void:
	if not _started:
		return
	_context()
	var s := take_sample()
	var list: Array = session.samples
	list.append(s)
	if list.size() > SAMPLES_KEPT:
		session.samples = list.slice(-SAMPLES_KEPT)
	write()

func take_sample() -> Dictionary:
	var s := {
		t = _t(), fg = bool(session.get("fg", true)), screen = str(session.get("screen", "")),
		fps = int(Performance.get_monitor(Performance.TIME_FPS)),
		static_mb = snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / MB, 0.1),
		vmem = snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / MB, 0.1),
		objects = int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		nodes = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		draws = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
	}
	var ps := proc_status(proc_status_path)
	if ps.has("rss"):
		s.mem = ps.rss                           # what low-memory kills look at (release builds track no static)
		s.mem_peak = ps.get("hwm", ps.rss)
	else:
		s.mem = s.static_mb
	var avail := float(OS.get_memory_info().get("available", -1))
	if avail > 0.0:
		s.avail = snappedf(avail / MB, 1.0)
	return s

## VmRSS / VmHWM of /proc/self/status in MB ({} where there is no /proc: macOS, Windows).
static func proc_status(path := "/proc/self/status") -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ) if path != "" else null
	if f == null:
		return {}
	var out := {}
	var text := f.get_as_text()
	for line in text.split("\n"):
		for pair: Array in [["VmRSS:", "rss"], ["VmHWM:", "hwm"]]:
			if line.begins_with(pair[0]):
				out[pair[1]] = snappedf(float(line.substr(6).strip_edges().split(" ")[0]) / 1024.0, 0.1)
	return out

## Back from the background: live again.
func resumed() -> void:
	if not _started:
		return
	session.ended = false
	session.end = ""
	session.fg = true
	note("resume")
	sample()

## A clean end: "background" (the app went away; Android may kill it there), "quit", "exit".
func mark_ended(why: String) -> void:
	if not _started:
		return
	session.ended = true
	session.end = why
	session.fg = false
	note(why)
	_context()
	session.samples.append(take_sample())
	if session.samples.size() > SAMPLES_KEPT:
		session.samples = (session.samples as Array).slice(-SAMPLES_KEPT)
	write(true)

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED:
			mark_ended("background")
		NOTIFICATION_APPLICATION_RESUMED:
			resumed()
		NOTIFICATION_WM_CLOSE_REQUEST:
			mark_ended("quit")
		NOTIFICATION_OS_MEMORY_WARNING:
			note("memory_warning")
			sample()

func _context() -> void:
	if not context_fn.is_valid():
		return
	var c: Variant = context_fn.call()
	if c is Dictionary:
		session.screen = str((c as Dictionary).get("screen", ""))
		var m: Variant = (c as Dictionary).get("match")
		session.match = m if m is Dictionary and not (m as Dictionary).is_empty() else null

## Writes session.json now (force) or within MIN_WRITE_GAP_MS of the last write.
func write(force := false) -> void:
	if not _started:
		return
	var gap := Time.get_ticks_msec() - _last_write
	if not force and gap < write_gap_ms:
		if not _write_soon and is_inside_tree():
			_write_soon = true
			get_tree().create_timer((write_gap_ms - gap) / 1000.0 + 0.05, true).timeout.connect(func():
				_write_soon = false
				write(true))
		return
	session.last_at = _now()
	_last_write = Time.get_ticks_msec()
	_write_json(SESSION, session)


# ---------- the previous run ----------

## After the splash: did the last run die? If so, one report goes into pending.json and is sent shortly (a
## coroutine until then; main calls it deferred and never waits).
func check_previous() -> void:
	if not _started:
		return
	var prev := _read(PREV)
	var st := _read(STATE)
	var exits: Array = info.get("exits", []) if info.get("exits") is Array else []
	var now := _now()
	var d := CrashReport.decide(prev, exits, st, now)
	last_decision = d
	st.last_exit_at = CrashReport.newest_exit(exits, int(st.get("last_exit_at", 0)))
	if d.send:
		var pid := _pid(st)
		var body := CrashReport.build(prev, d, info, CrashReport.log_tail(CrashReport.previous_log(log_dir)), pid)
		_write_json(PENDING, {body = body, made_at = now, tries = 0})
		st = CrashReport.count_one(st, now)
		var ex: Dictionary = d.exit
		print("CrashWatch: the last run ended unexpectedly (%s%s): report queued" % [d.why,
			", " + str(ex.get("reason", "")) if not ex.is_empty() else ""])
	elif d.why not in ["clean", ""]:
		print("CrashWatch: last run: %s" % d.why)
	_write_json(STATE, st)
	_remove(PREV)
	await send_pending()

## Sends pending.json (if any): after send_delay_sec, and once more retry_sec later when there was no answer. Gone
## after a 2xx or a 4xx (a refusal is not retried), or once too old / tried too often.
func send_pending() -> void:
	if not _started or _sending:
		return
	var p := _read(PENDING)
	if p.is_empty():
		return
	if _now() - int(p.get("made_at", 0)) > PENDING_MAX_AGE_MS or int(p.get("tries", 0)) >= PENDING_MAX_TRIES \
			or not p.get("body") is Dictionary:
		_remove(PENDING)
		return
	_sending = true
	for attempt in 2:
		var wait := send_delay_sec if attempt == 0 else retry_sec
		if wait > 0.0:
			await get_tree().create_timer(wait, true).timeout
		if not is_inside_tree():
			break
		p.tries = int(p.get("tries", 0)) + 1
		_write_json(PENDING, p)
		var body: Dictionary = p.body
		var acc := Account.instance()
		if not body.has("account_id") and acc != null and str(acc.account.get("id", "")) != "":
			body.account_id = str(acc.account.id)
		var r: Dictionary = await _send(body)
		var st := int(r.get("status", 0))
		if bool(r.get("ok", false)) or (st >= 400 and st < 500):
			print("CrashWatch: report %s (%d)" % ["sent" if r.get("ok", false) else "refused", st])
			_remove(PENDING)
			break
		if int(p.tries) >= PENDING_MAX_TRIES:
			_remove(PENDING)
			break
	_sending = false

func _send(body: Dictionary) -> Dictionary:
	if send_fn.is_valid():
		var out: Variant = await send_fn.call(body)
		return out if out is Dictionary else {ok = false, status = 0}
	var acc := Account.instance()
	if acc == null or not acc.enabled:
		return {ok = false, status = 0}
	return await acc.request(HTTPClient.METHOD_POST, CrashReport.PATH, body, acc.has_session())


# ---------- helpers ----------

func _native_info(since_ms: int) -> Dictionary:
	if native == null or not native.has_method("diag_info"):
		return {}
	var raw: Variant = native.call("diag_info", since_ms, EXITS_ASKED)
	var parsed: Variant = raw if raw is Dictionary else JSON.parse_string(str(raw))
	return parsed if parsed is Dictionary else {}

## The device id: the network one (Save.prefs.net_pid) when there is one, else our own (kept in state.json).
func _pid(st: Dictionary) -> String:
	var save := get_node_or_null("/root/Save")
	var p := str(save.prefs.get("net_pid", "")) if save != null and save.get("prefs") is Dictionary else ""
	if p.length() >= 16:
		return p
	if str(st.get("did", "")).length() < 16:
		st.did = Crypto.new().generate_random_bytes(12).hex_encode()
	return str(st.did)

func _t() -> float:
	return snappedf((Time.get_ticks_msec() - _t0) / 1000.0, 0.1)

func _now() -> int:
	return int(clock.call()) if clock.is_valid() else int(Time.get_unix_time_from_system() * 1000.0)

func _path(f: String) -> String:
	return dir.path_join(f)

func _read(f: String) -> Dictionary:
	var p := _path(f)
	if not FileAccess.file_exists(p):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
	return parsed if parsed is Dictionary else {}

func _write_json(f: String, d: Dictionary) -> void:
	var p := _path(f)
	var tmp := p + ".tmp"
	var fa := FileAccess.open(tmp, FileAccess.WRITE)
	if fa == null:
		return
	fa.store_string(JSON.stringify(d))
	fa.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(p))

func _remove(f: String) -> void:
	var p := _path(f)
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
