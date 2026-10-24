extends Node
## Dev preview of a Snakes & Ladders match without main.gd: SLScenes + SLBoard + SLMatch (+ SLLanding) on a stand-in
## app. Saves the landing, the match start, a mid-game 3D View and Top View for each scene, then (option "soak")
## autoplays full 4-player games and reports stalls. The real save is backed up and restored.
##   godot --path . --resolution 390x844 res://dev/preview_sl_match.tscn -- <out_dir> [scene ...] [soak] [games=N] [noshots]

var out := "/tmp"
var app: FakeApp
var scenes: SLScenes
var board: SLBoard
var sl: SLMatch
var landing: SLLanding
var baker: TexBaker
var _backup := ""
var _results := []

class FakeApp extends Control:
	var safe_top := 0.0
	var safe_bottom := 0.0
	var speed := 0.55
	var paused := false
	var ui_root: Control
	var sheet_layer: Control
	func _top_sheet() -> Node:
		return null

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() and args[0].begins_with("/"):
		out = args[0]
	MatchStore.enabled = false                  # never touch a kept match
	if FileAccess.file_exists("user://save.json"):
		_backup = FileAccess.get_file_as_string("user://save.json")
	var ids := []
	var games := 2
	for a in args:
		if SLScenes.SCENES.has(a):
			ids.append(a)
		if a.begins_with("games="):
			games = int(a.substr(6))
	if ids.is_empty():
		ids = ["jungle"]
	baker = TexBaker.new()
	add_child(baker)
	scenes = SLScenes.new()
	add_child(scenes)
	board = SLBoard.new()
	scenes.attach_board(board)
	await board.build(baker)
	var cl := CanvasLayer.new()
	add_child(cl)
	app = FakeApp.new()
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	app.mouse_filter = Control.MOUSE_FILTER_IGNORE
	app.theme = UIKit.theme()
	cl.add_child(app)
	app.ui_root = app
	sl = SLMatch.new(app, null, board)
	add_child(sl)
	sl.scenes = scenes
	sl.build_hud(app)
	sl.hud.visible = false
	landing = SLLanding.new()
	app.add_child(landing)
	landing.visible = false
	app.sheet_layer = Control.new()
	app.add_child(app.sheet_layer)
	sl.finished.connect(func(r: Dictionary): _results.append(r))
	scenes.camera.make_current()
	Save.prefs.sl_need_one = "need1" in args
	if not "noshots" in args:
		for id in ids:
			await _scene_shots(id)
	if "resume" in args:
		await _resume_test()
	if "soak" in args:
		await _soak(games)
	_restore()
	get_tree().quit()

func _scene_shots(id: String) -> void:
	await scenes.set_scene(baker, id)
	# landing
	sl.stop()
	sl.hud.visible = false
	landing.visible = true
	landing.set_scene_name(SLScenes.info(id).name)
	board.setup_players([])
	scenes.play(false)
	scenes.reduced_motion = true
	await _settle(1.0)
	await _shot(id + "_landing")
	# match start, vs computer, 4 players
	landing.visible = false
	sl.hud.visible = true
	Save.prefs.sl_cam = "3d"
	sl.start({game = "sl", mode = "cpu", n = 4, color = 0})
	await _settle(1.2)
	await _shot(id + "_start")
	# mid-game: put pawns around the board, your turn
	sl.stop()
	sl.G = SnakesLaddersRules.new_game("cpu", 4, 0)
	var spots := [47, 63, 23, 88]
	for k in 4:
		sl.G.players[k].pos = spots[k]
	sl.G.players[3].pos = 0
	sl._id += 1
	board.setup_players([0, 1, 2, 3])
	board.place(sl._positions())
	scenes.play(true, "3d")
	sl._build_tiles()
	sl._refresh_tiles()
	sl._layout()
	sl._begin()
	await _settle(5.0)                           # past the idle hint: the hand shows
	await _shot(id + "_mid3d")
	scenes.set_view("top")
	await _settle(1.5)
	await _shot(id + "_midtop")
	scenes.set_view("3d")
	# a ladder and a snake, mid-animation
	sl.G.players[0].pos = 24
	board.place(sl._positions())
	sl.roll(4)                                   # 24 + 4 = 28: the ladder to 84
	await _until(func(): return board.pawns[0].anim and board.pawns[0].node.position.z < 0.0, 6.0)
	await _shot(id + "_ladder")
	await _until(func(): return not sl._busy, 8.0)
	sl.stop()

func _soak(games: int) -> void:
	sl.autoplay = true
	app.speed = 0.35
	landing.visible = false
	sl.hud.visible = true
	await scenes.set_scene(baker, "jungle")
	for gi in games:
		var t0 := Time.get_ticks_msec()
		var before := _results.size()
		sl.start({game = "sl", mode = "cpu", n = 4, color = gi % 4})
		var last_turn := -1
		var last_change := Time.get_ticks_msec()
		var rolls := 0
		while _results.size() == before:
			await get_tree().process_frame
			if sl.G.is_empty():
				break
			var sig := int(sl.G.turn) * 1000 + int(sl.G.players[sl.G.turn].rolls.size())
			if sig != last_turn:
				last_turn = sig
				last_change = Time.get_ticks_msec()
				rolls += 1
			if Time.get_ticks_msec() - last_change > 8000:
				print("[soak] STALL in game %d: turn %d phase %s busy %s" % [gi, sl.G.turn, sl.G.phase, sl._busy])
				break
			if Time.get_ticks_msec() - t0 > 600000:
				print("[soak] TIMEOUT game %d" % gi)
				break
		var secs := (Time.get_ticks_msec() - t0) / 1000.0
		if _results.size() > before:
			var r: Dictionary = _results[-1]
			print("[soak] game %d done in %.1f s, %d rolls: %s | %s" % [gi, secs, rolls, r.title, r.standings.map(func(e): return "%d.%s@%d" % [e.place, e.name, e.pos])])
			if gi == 0:
				await _shot("soak_end")
		await get_tree().create_timer(0.5).timeout
	sl.autoplay = false

## Plays a few turns, round-trips the kept state through JSON (as MatchStore does) and resumes it to the end.
func _resume_test() -> void:
	sl.autoplay = true
	app.speed = 0.3
	landing.visible = false
	sl.hud.visible = true
	await scenes.set_scene(baker, "jungle")
	sl.start({game = "sl", mode = "cpu", n = 3, color = 1})
	await _until(func(): return sl.G.players[0].rolls.size() >= 4 and not sl._busy, 60.0)
	var kept := {game = "sl", cfg = sl.setup.duplicate(true), G = sl.G.duplicate(true)}
	var back: Dictionary = MatchStore.ints(JSON.parse_string(JSON.stringify(kept)))
	var before: Array = sl._positions()
	sl.stop()
	var n := _results.size()
	sl.resume(back)
	await get_tree().process_frame
	print("[resume] positions before %s after %s turn %d" % [before, sl._positions(), sl.G.turn])
	await _until(func(): return _results.size() > n, 300.0)
	print("[resume] finished: %s" % (_results[-1].title if _results.size() > n else "NO"))
	sl.autoplay = false

func _settle(sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - t0) / 1000.0 < sec:
		scenes.snap_camera()
		await get_tree().process_frame

func _until(f: Callable, timeout: float) -> void:
	var t0 := Time.get_ticks_msec()
	while not f.call() and (Time.get_ticks_msec() - t0) / 1000.0 < timeout:
		await get_tree().process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("shot ", name)

func _restore() -> void:
	Save._dirty = false
	if _backup != "":
		var f := FileAccess.open("user://save.json", FileAccess.WRITE)
		f.store_string(_backup)
		f.close()
		Save.load_data()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_restore()
