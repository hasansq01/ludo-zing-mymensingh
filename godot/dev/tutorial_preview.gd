extends Node
## Dev preview of the guided first match (Tutorial + CoachMarks) on the real Ludo screen: plays the whole lesson by
## tapping inside each cut-out (real input events, so the blocking and the pass-through are exercised), with one
## blocked tap, and saves a screenshot per coach step, the notes and the closing card. This node plays main.gd's
## part (speed, paused, sheet_layer, _top_sheet, the board tap). The real save and match file are backed up and
## restored; tutorial_done is put back.
##   godot --path . --resolution 390x844 res://dev/tutorial_preview.tscn -- <out_dir> [skip] [top] [slow]

var out := "/tmp"
var speed := 0.55
var paused := false
var sheet_layer: Control
var ui_root: Control
var world: TableWorld
var hud: LudoHUD
var ludo: LudoMatch
var _backup := ""
var _match_backup := ""
var _prefs_backup := {}
var _t0 := 0

func _top_sheet() -> Node:
	return null

func _ready() -> void:
	var args := Array(OS.get_cmdline_user_args())
	if args.size():
		out = args[0]
	if FileAccess.file_exists("user://save.json"):
		_backup = FileAccess.get_file_as_string("user://save.json")
	if FileAccess.file_exists(MatchStore.PATH):
		_match_backup = FileAccess.get_file_as_string(MatchStore.PATH)
	_prefs_backup = Save.prefs.duplicate(true)
	Save._timer.paused = true                # nothing this preview does reaches the real save
	MatchStore.enabled = false
	if args.has("slow"):
		speed = 1.0
	var baker := TexBaker.new()
	add_child(baker)
	world = TableWorld.new()
	add_child(world)
	await world.build_room(baker, func(_f): pass, str(Save.profile.room))
	var layer := CanvasLayer.new()
	add_child(layer)
	ui_root = Control.new()
	ui_root.theme = UIKit.theme()
	ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui_root)
	hud = LudoHUD.new()
	ui_root.add_child(hud)
	sheet_layer = Control.new()
	sheet_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sheet_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(sheet_layer)
	ludo = LudoMatch.new(self, world, hud)
	add_child(ludo)
	world.board.speed = speed
	Save.prefs.cam = "top" if args.has("top") else "3d"
	Save.prefs.tutorial_done = false
	if args.has("skip"):
		await _run_skip()
	else:
		await _run()
	_restore()
	get_tree().quit()

func _unhandled_input(e: InputEvent) -> void:      # main.gd's board tap
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		if ludo.tap(e.position):
			get_viewport().set_input_as_handled()

func _run() -> void:
	_t0 = Time.get_ticks_msec()
	ludo.start_tutorial()
	var marks: CoachMarks = null
	for n in Tutorial.STEPS.size():
		await _until(func(): return ludo.tut != null and ludo.tut.marks != null and ludo.tut.marks.blocking() and ludo.tut.marks.hole().size != Vector2.ZERO and ludo.tut.i == n, 20.0)
		marks = ludo.tut.marks
		await _sleep(0.55)                   # the fade and the caption entrance
		var st: Dictionary = Tutorial.STEPS[n]
		await _shot("tut_%02d_%s" % [n + 1, "roll%d" % st.roll if st.has("roll") else "move%d_%s" % [st.move, st.get("expect", "")]])
		if n == 1:                           # one tap outside the cut-out: blocked, nudged
			_click(Vector2(300, 600))
			await _sleep(0.08)
			await _shot("tut_02b_blocked_tap")
			await _sleep(0.5)
			print("[tut] after blocked tap: phase=%s i=%d" % [ludo.S.phase, ludo.tut.i])
		await _sleep(0.6)                    # a person reading the caption
		var h := marks.hole()
		_click(h.get_center())
		await _sleep(0.05)
		print("[tut] step %d tapped at %s -> i=%d phase=%s t=%.1fs" % [n + 1, h.get_center(), ludo.tut.i, ludo.S.phase, (Time.get_ticks_msec() - _t0) / 1000.0])
	# the pair note, Mocha's turn, the star note, the card
	await _sleep(1.3)
	await _shot("tut_13_pair_note")
	print("[tut] pair note holding=%s" % ludo.tut.holding())
	_click(Vector2(195, 460))                # "Tap to continue": the game waits for it
	await _until(func(): return ludo.S.tok[2][1] == 34, 15.0)
	await _sleep(0.6)
	await _shot("tut_14_bot_on_star")
	await _until(func(): return ludo.tut != null and ludo.tut.marks != null and ludo.tut.marks.noting() and ludo.tut.marks._title.text == Tutorial.SAFE_NOTE[0], 15.0)
	await _sleep(0.6)
	await _shot("tut_15_safe_note")
	_click(Vector2(195, 460))
	await _until(func(): return ludo.tut != null and is_instance_valid(ludo.tut.marks._card), 15.0)
	await _sleep(0.7)
	await _shot("tut_16_ready_card")
	print("[tut] card at %.1fs, tutorial_done=%s, match saved=%s" % [(Time.get_ticks_msec() - _t0) / 1000.0, Save.prefs.tutorial_done, MatchStore.has_saved()])
	var btn: Button = null
	for b in ludo.tut.marks._card.find_children("*", "Button", true, false):
		if (b as Button).text == Tutorial.READY_PLAY:
			btn = b
	_click(btn.get_global_rect().get_center())
	await _sleep(1.6)
	print("[tut] after Play: tut=%s players=%s phase=%s" % [ludo.tut, ludo.S.get("players"), ludo.S.get("phase")])
	await _shot("tut_17_real_game")
	ludo.stop()

func _run_skip() -> void:
	ludo.start_tutorial()
	await _until(func(): return ludo.tut != null and ludo.tut.marks != null and ludo.tut.marks.blocking(), 20.0)
	await _sleep(0.6)
	var sk: Button = ludo.tut.marks._skip
	_click(sk.get_global_rect().get_center())
	await _sleep(0.6)
	await _shot("tut_skip_confirm")
	var yes: Button = null
	for b in get_tree().root.find_children("Yes", "Button", true, false):
		yes = b
	print("[tut] skip asks first: confirm=%s holding=%s" % [yes != null, ludo.tut.holding() if ludo.tut else false])
	if yes:
		_click(yes.get_global_rect().get_center())
	await _sleep(1.4)
	print("[tut] skip: tutorial_done=%s tut=%s players=%s" % [Save.prefs.tutorial_done, ludo.tut, ludo.S.get("players")])
	await _shot("tut_skip_after")
	ludo.stop()

func _click(at: Vector2) -> void:
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = at
		e.global_position = at
		Input.parse_input_event(e)

func _until(cond: Callable, sec: float) -> void:
	var t := Time.get_ticks_msec()
	while not cond.call() and Time.get_ticks_msec() - t < sec * 1000.0:
		await get_tree().process_frame
	if not cond.call():
		print("[tut] TIMEOUT waiting (phase=%s turn=%s i=%s)" % [ludo.S.get("phase"), ludo.S.get("turn"), ludo.tut.i if ludo.tut else -1])

func _shot(name: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [out, name]
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)

func _sleep(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _restore() -> void:
	Save.prefs = _prefs_backup.duplicate(true) if not _prefs_backup.is_empty() else Save.prefs
	Save._dirty = false
	if _backup != "":
		var f := FileAccess.open("user://save.json", FileAccess.WRITE)
		f.store_string(_backup)
		f.close()
		Save.load_data()
	MatchStore.enabled = true
	if _match_backup != "":
		var g := FileAccess.open(MatchStore.PATH, FileAccess.WRITE)
		g.store_string(_match_backup)
		g.close()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		Save._dirty = false
