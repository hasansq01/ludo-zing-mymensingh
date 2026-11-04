extends Node
## Dev: screenshots of the notification UI at 390x844: Settings' Notifications section (on, master off, the "phone
## settings" hint) and the soft permission prompt. Offline (no server); Save is a throwaway: its debounced write is
## unhooked and nothing is flushed, so user://save.json is never written.
##   godot --path godot --resolution 390x844 res://dev/notif_shots.tscn -- <out_dir>

var out := "/tmp"
var main: Node
var n := 0

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size():
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	if Save._timer and Save._timer.timeout.is_connected(Save.flush):
		Save._timer.timeout.disconnect(Save.flush)
	Save.prefs.welcome_seen = true
	Save.prefs.tutorial_done = true
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _until(func(): return main.screen == "home", 60)
	await _sleep(1.5)
	main.close_all_sheets()
	var nt: Notifications = main.notifications
	nt.notifier.stub_permission = "granted"

	main.open_settings()
	await _sleep(0.9)
	var s: SettingsSheet = main._top_sheet()
	await _show_section(s)
	await shot("settings_notifications_on")
	s._on_notif(false)
	await _sleep(0.3)
	await shot("settings_notifications_master_off")
	nt.notifier.stub_permission = "denied"
	s._on_notif(true)
	await _sleep(0.3)
	await shot("settings_notifications_denied_hint")
	s.scroll_box.scroll_vertical = 0
	await _sleep(0.2)
	await shot("settings_top")
	main.close_all_sheets()
	await _sleep(0.4)

	nt.notifier.stub_permission = "ask"
	Save.prefs.notif = true
	Save.prefs.notif_asked = 0
	nt.note_win()
	nt._ask()
	await _sleep(0.9)
	await shot("soft_prompt")
	main.close_all_sheets()
	Save._dirty = false
	get_tree().quit()

func _show_section(s: SettingsSheet) -> void:
	for c in s.find_children("Section", "Label", true, false):
		if (c as Label).text.to_lower() == "notifications":
			s.scroll_box.ensure_control_visible(c)
			s.scroll_box.scroll_vertical += 260
	await _sleep(0.4)

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	n += 1
	get_viewport().get_texture().get_image().save_png("%s/%02d_%s.png" % [out, n, name])
	print("shot ", name)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		Save._dirty = false

func _sleep(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _until(cond: Callable, timeout: float) -> void:
	var t0 := Time.get_ticks_msec()
	while not cond.call() and (Time.get_ticks_msec() - t0) / 1000.0 < timeout:
		await get_tree().process_frame
