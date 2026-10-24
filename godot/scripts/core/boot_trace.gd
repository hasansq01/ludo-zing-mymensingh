class_name BootTrace
extends RefCounted
## Startup timing: `[boot] <phase> <ms since the engine started> (+<ms since the previous mark>)` on stdout (logcat on
## Android, tag godot). On in debug builds; release builds stay quiet unless started with `--boot-trace` on the
## command line (desktop), or on Android when Android/data/<package>/files/boot-trace exists on the shared storage
## (tools/boot-time.sh creates it with adb: the launcher activity drops intent extras, so no command line there).
##
##   BootTrace.mark("room built")      # main.gd's splash phases
##   BootTrace.watch_frames(self)      # also report long frames (first-use shader compiles) until end()
##   BootTrace.end()                   # the home screen is up: later marks (TexBaker's bakes) stop

static var _on := -1
static var _last := 0
static var _done := false
static var _phase := "engine start"
static var _watcher: Node

static func on() -> bool:
	if _on < 0:
		_on = 1 if OS.is_debug_build() or OS.get_cmdline_args().has("--boot-trace") \
			or OS.get_cmdline_user_args().has("--boot-trace") or _android_flag() else 0
	return _on == 1

## /sdcard/Android/data/<package>/files/boot-trace (the app's own external files dir: readable without permissions).
static func _android_flag() -> bool:
	if not OS.has_feature("android"):
		return false
	var pkg := OS.get_user_data_dir().get_base_dir().get_file()      # /data/user/0/<package>/files
	return pkg != "" and FileAccess.file_exists("/storage/emulated/0/Android/data/%s/files/boot-trace" % pkg)

## Still booting (the splash is up) and tracing.
static func active() -> bool:
	return not _done and on()

static func mark(phase: String) -> void:
	if not active():
		return
	var now := Time.get_ticks_msec()
	print("[boot] %s %d (+%d)" % [phase, now, now - _last])
	_last = now
	_phase = phase

## Also report every frame longer than `ms` until end() (shader compiles show up as long frames). The watcher is a
## node under `parent`: its connection to RenderingServer.frame_post_draw goes away with it (end() frees it).
static func watch_frames(parent: Node, ms := 150) -> void:
	if not active() or is_instance_valid(_watcher):
		return
	var w := FrameWatch.new()
	w.name = "BootFrameWatch"
	w.limit = ms
	_watcher = w
	parent.add_child(w)

class FrameWatch extends Node:
	var limit := 150
	var _at := 0
	func _enter_tree() -> void:
		_at = Time.get_ticks_msec()
		RenderingServer.frame_post_draw.connect(_on_frame)
	func _exit_tree() -> void:
		if RenderingServer.frame_post_draw.is_connected(_on_frame):
			RenderingServer.frame_post_draw.disconnect(_on_frame)
	func _on_frame() -> void:
		var now := Time.get_ticks_msec()
		if now - _at > limit:
			print("[boot]   long frame %d ms (after: %s)" % [now - _at, BootTrace._phase])
		_at = now

static func end(phase := "home") -> void:
	mark(phase)
	_done = true
	if is_instance_valid(_watcher):
		_watcher.queue_free()
	_watcher = null
