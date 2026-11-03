extends Node
## Dev preview of the Ludo game screen (W2a): drives LudoMatch + LudoHUD + the 3D board directly (this node plays
## main.gd's part: speed, paused, sheet_layer, _top_sheet()). Screenshots of the HUD states, juice moments and a
## soak test of full computer-only games (stall detection). The real save and match file are backed up and restored.
##   godot --path . --resolution 390x844 res://dev/preview_ludo.tscn -- <out_dir> [page ...]
## pages: start hand choose miss pairs pair_ask capture cpu home top teams colorblind result store soak (default:
##   all but soak). soak [n] [speed]: n all-computer games (and one with you on autoplay) at a fast pace.

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

func _top_sheet() -> Node:
	for k in range(sheet_layer.get_child_count() - 1, -1, -1):
		var c := sheet_layer.get_child(k)
		if c is Sheet and not c.is_queued_for_deletion():
			return c
	return null

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size():
		out = args[0]
	var pages: Array = Array(args.slice(1)) if args.size() > 1 else ["start", "hand", "choose", "miss", "pairs", "pair_ask", "capture", "cpu", "home", "top", "teams", "colorblind", "result", "store"]
	if FileAccess.file_exists("user://save.json"):
		_backup = FileAccess.get_file_as_string("user://save.json")
	if FileAccess.file_exists(MatchStore.PATH):
		_match_backup = FileAccess.get_file_as_string(MatchStore.PATH)
	_prefs_backup = Save.prefs.duplicate(true)
	Save._timer.paused = true                # nothing this preview does reaches the real save
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
	ludo.finished.connect(func(r): print("[preview] finished: ", r))
	world.board.speed = speed
	Save.prefs.cam = "3d"
	Save.prefs.colorblind = false
	Save.prefs.pair_ask = false
	var i := 0
	while i < pages.size():
		var p := str(pages[i])
		i += 1
		match p:
			"start": await _page_start()
			"hand": await _page_hand()
			"choose": await _page_choose()
			"miss": await _page_miss()
			"pairs": await _page_pairs()
			"pair_ask": await _page_pair_ask()
			"capture": await _page_capture()
			"cpu": await _page_cpu()
			"home": await _page_home()
			"top": await _page_top()
			"teams": await _page_teams()
			"colorblind": await _page_colorblind()
			"result": await _page_result()
			"lose": await _page_lose()
			"store": await _page_store()
			"soak":
				var n := 3
				if i < pages.size() and str(pages[i]).is_valid_int():
					n = int(pages[i]); i += 1
				var sp := 0.2
				if i < pages.size() and str(pages[i]).is_valid_float():
					sp = float(pages[i]); i += 1
				await _page_soak(n, sp)
	_restore()
	get_tree().quit()

# ---------------------------------------------------------------------------------------------------------------

func _new(players := ["human", "cpu", "cpu", "cpu"], teams := false, opts := {}) -> void:
	ludo.stop()
	ludo.save_matches = false
	ludo.start(players, teams, opts)
	await _sleep(0.1)

func _put(tok: Array, pairs := []) -> void:
	ludo.S.tok = tok
	ludo.S.pairs = pairs
	world.board.relayout(ludo.S)
	hud.update(ludo.S, ludo.S.turn)

func _settle(sec := 1.6) -> void:
	await _sleep(sec)

func _page_start() -> void:
	await _new()
	await _settle(2.4)
	await _shot("ludo_start")

func _page_hand() -> void:
	await _sleep(3.0)
	await _shot("ludo_hand_hint")

func _page_choose() -> void:
	await _new()
	await _settle(2.0)
	_put([[-1, 5, 12, 30], [3, -1, -1, 20], [-1, 9, 33, 44], [-1, -1, 8, -1]])
	ludo.roll(6)
	await _sleep(1.4)
	await _shot("ludo_choose")
	print("[preview] idle: ", hud.top.current())

func _page_miss() -> void:
	ludo.tap(Vector2(195, 330))
	await _sleep(0.15)
	await _shot("ludo_miss")
	await _sleep(1.6)

func _page_pairs() -> void:
	await _new()
	await _settle(2.0)
	_put([[10, 10, 22, -1], [3, -1, -1, 20], [-1, 9, 33, 44], [-1, -1, 8, -1]], [{c = 0, a = 0, b = 1}])
	ludo.roll(4)
	await _sleep(1.4)
	await _shot("ludo_pairs_glow")

func _page_pair_ask() -> void:
	await _new(["human", "cpu", "cpu", "cpu"], false, {pair_ask = true})
	await _settle(2.0)
	_put([[10, 14, 30, -1], [3, -1, -1, 20], [-1, 9, 33, 44], [-1, -1, 8, -1]])
	ludo.roll(4)
	await _sleep(1.3)
	ludo.move(0)
	await _sleep(1.6)
	await _shot("ludo_pair_ask")
	TapLog.point(hud.pair_yes)
	hud.pair_yes.pressed.emit()
	await _sleep(0.8)
	await _shot("ludo_pair_formed")
	await _sleep(1.0)

func _page_capture() -> void:
	await _new()
	await _settle(2.0)
	# red at 13 (its abs 13); a green pawn at green progress 3 = abs 16 (not safe): a 3 captures it
	_put([[13, -1, -1, -1], [3, 30, -1, -1], [-1, -1, -1, -1], [-1, -1, -1, -1]])
	ludo.roll(3)
	await _sleep(1.2)
	print("[preview] capture phase ", ludo.S.phase, " units ", LudoRules.units(ludo.S))
	await _sleep(0.55)
	await _shot("ludo_capture_puff")
	await _sleep(0.35)
	await _shot("ludo_capture_after")
	await _sleep(1.2)

func _page_cpu() -> void:
	await _new()
	await _settle(1.6)
	ludo.S.turn = 1
	ludo._begin_turn()
	await _sleep(0.2)
	await _shot("ludo_cpu_turn")
	await _sleep(0.5)
	await _shot("ludo_cpu_turn_settled")
	await _sleep(2.0)

func _page_home() -> void:
	await _new()
	await _settle(2.0)
	_put([[53, 56, -1, -1], [3, -1, -1, 20], [-1, 9, 33, 44], [-1, -1, 8, -1]])
	ludo.roll(3)
	await _sleep(1.6)
	await _shot("ludo_home_pop")
	await _sleep(1.2)

func _page_top() -> void:
	Save.prefs.cam = "top"
	await _new()
	await _settle(2.4)
	_put([[-1, 5, 12, 30], [3, -1, -1, 20], [-1, 9, 33, 44], [-1, -1, 8, -1]])
	ludo.roll(6)
	await _sleep(1.6)
	await _shot("ludo_top_view")
	Save.prefs.cam = "3d"

func _page_teams() -> void:
	await _new(["human", "cpu", "cpu", "cpu"], true)
	await _sleep(0.5)
	await _shot("ludo_teams_start")
	await _sleep(3.0)
	_put([[56, 56, 56, 56], [3, -1, -1, 20], [-1, 9, 33, 44], [-1, -1, 8, -1]])
	await _sleep(0.3)
	await _shot("ludo_teams_mid")

func _page_colorblind() -> void:
	Save.prefs.colorblind = true
	await _new()
	await _settle(2.0)
	_put([[-1, 5, 12, 30], [3, -1, -1, 20], [-1, 9, 33, 44], [-1, -1, 8, -1]])
	await _sleep(0.8)
	await _shot("ludo_colorblind")
	Save.prefs.colorblind = false

func _page_result() -> void:
	await _new()
	await _settle(1.6)
	_put([[56, 56, 56, 53], [3, -1, -1, 20], [-1, 9, 33, 44], [-1, -1, 8, -1]])
	ludo.roll(3)
	var r: Dictionary = await ludo.finished
	print("[preview] result payload: ", JSON.stringify(r))
	await _sleep(0.3)
	await _shot("ludo_over_hud_hidden")
	var rs := ResultScreen.new(r)
	rs.open(sheet_layer)
	await _sleep(2.5)
	await _shot("ludo_result_screen")
	rs.close()
	await _sleep(0.4)

## A real loss: Mocha (Green) rolls its last pawn home; the result is headlined from your side with the
## participation coins.
func _page_lose() -> void:
	await _new()
	await _settle(1.6)
	_put([[56, 30, 12, -1], [56, 56, 56, 53], [44, 50, 20, 8], [5, -1, -1, -1]])
	ludo.S.turn = 1
	ludo.roll(3)
	var r: Dictionary = await ludo.finished
	print("[preview] lose payload: ", r.title, " | ", r.sub, " | reward ", r.reward)
	var rs := ResultScreen.new(r)
	rs.open(sheet_layer)
	await _sleep(2.8)
	await _shot("ludo_lose_result_real")
	rs.close()
	await _sleep(0.4)

func _page_store() -> void:
	MatchStore.enabled = true
	await _new()
	ludo.save_matches = true
	await _settle(1.8)
	_put([[10, 14, -1, -1], [3, -1, -1, 20], [-1, 9, 33, 44], [-1, -1, 8, -1]], [])
	ludo._begin_turn()
	await _sleep(0.3)
	print("[preview] store has_saved=", MatchStore.has_saved(), " peek=", MatchStore.peek())
	var st := MatchStore.load()
	var same: bool = JSON.stringify(st.S.tok) == JSON.stringify(ludo.S.tok)
	print("[preview] store tok types int=", typeof(st.S.tok[0][0]) == TYPE_INT, " same=", same)
	ludo.stop()
	print("[preview] after stop has_saved=", MatchStore.has_saved())
	MatchStore.save("ludo", st, "test")
	var st2 := MatchStore.load()
	ludo.resume(st2)
	await _sleep(1.5)
	print("[preview] resumed phase=", ludo.S.phase, " turn=", ludo.S.turn, " tok=", ludo.S.tok)
	await _shot("ludo_resumed")
	ludo.stop()
	MatchStore.clear()

## Full games with no human (and one with you on autoplay) at a fast pace; a stall = no turn change for 20 s.
func _page_soak(n: int, sp: float) -> void:
	speed = sp
	Engine.time_scale = 4.0                  # game time runs 4x (stall check below is in real time)
	for g in n + 1:
		var auto := g == n
		var t0 := Time.get_ticks_msec()
		ludo.stop()
		ludo.save_matches = false
		ludo.autoplay = auto
		var teams := g % 2 == 1
		var pl: Array = ["human", "cpu", "cpu", "cpu"] if auto else ["cpu", "cpu", "cpu", "cpu"]
		var done := [false]
		var cb := func(_r): done[0] = true
		ludo.finished.connect(cb, CONNECT_ONE_SHOT)
		ludo.start(pl, teams, {pair_ask = auto, bot_level = ["easy", "normal", "hard"][g % 3]})
		var last_sig := ""
		var last_change := Time.get_ticks_msec()
		var turns := 0
		while not done[0]:
			await _sleep(0.25)
			if ludo.S.is_empty():
				break
			var sig := "%s|%s|%s" % [ludo.S.turn, ludo.S.phase, JSON.stringify(ludo.S.tok)]
			if sig != last_sig:
				last_sig = sig
				last_change = Time.get_ticks_msec()
				turns += 1
			elif Time.get_ticks_msec() - last_change > 20000:
				print("[soak] STALL game %d: phase=%s turn=%d busy=%s tok=%s" % [g, ludo.S.phase, ludo.S.turn, ludo._busy, ludo.S.tok])
				break
		print("[soak] game %d teams=%s auto=%s: %s in %.1f s (%d state changes)" % [g, teams, auto, "done" if done[0] else "NOT done", (Time.get_ticks_msec() - t0) / 1000.0, turns])
		if ludo.finished.is_connected(cb):
			ludo.finished.disconnect(cb)
	ludo.autoplay = false
	Engine.time_scale = 1.0
	speed = 0.55

# ---------------------------------------------------------------------------------------------------------------

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
	if _match_backup != "":
		var g := FileAccess.open(MatchStore.PATH, FileAccess.WRITE)
		g.store_string(_match_backup)
		g.close()
	elif FileAccess.file_exists(MatchStore.PATH):
		MatchStore.enabled = true
		MatchStore.clear()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		Save._dirty = false
