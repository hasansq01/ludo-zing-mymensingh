class_name Autoplay
extends RefCounted
## On-device soak test (debug builds only): when user://autoplay.txt exists, games play back to back by
## themselves and every result is printed. The file holds "ludo", "teams", "sl" or "all" (rotates the three).
##
##   main.gd: if Autoplay.requested(): skip the welcome / daily ...;  Autoplay.maybe_start(self)
##
## app (main.gd) needs: ludo, sl (with `autoplay` flags and `finished` signals), world.board.speed, speed,
## start_ludo(cfg), start_sl(cfg), sheet_layer, _top_sheet().

const FILE := "user://autoplay.txt"
const SPEED := 0.35

## True in a debug build with the autoplay file present.
static func requested() -> bool:
	return OS.is_debug_build() and FileAccess.file_exists(FILE)

## What to play ("ludo" | "teams" | "sl" | "all"); "" when not requested.
static func what() -> String:
	if not requested():
		return ""
	var t := FileAccess.get_file_as_string(FILE).strip_edges().to_lower()
	return t if t in ["ludo", "teams", "sl", "all"] else "all"

## Starts the loop when requested (a coroutine that runs for the app's life; don't await it). Returns whether it
## started.
static func maybe_start(app: Node) -> bool:
	var kind := what()
	if kind == "":
		return false
	_run(app, kind)
	return true

## The kind of game number n (1-based) for a request.
static func kind_of(request: String, n: int) -> String:
	return request if request != "all" else ["ludo", "teams", "sl"][(n - 1) % 3]

static func _run(app: Node, request: String) -> void:
	app.ludo.autoplay = true
	app.sl.autoplay = true
	app.speed = SPEED
	app.world.board.speed = SPEED
	var games := 0
	await app.get_tree().create_timer(2.0).timeout
	while is_instance_valid(app) and app.is_inside_tree():
		games += 1
		var kind := kind_of(request, games)
		print("[auto] game %d: %s" % [games, kind])
		if kind == "sl":
			app.start_sl({game = "sl", mode = "cpu", n = 4, color = games % 4})
			await app.sl.finished
		else:
			app.start_ludo({game = "ludo", players = ["human", "cpu", "cpu", "cpu"], teams = kind == "teams"})
			await app.ludo.finished
		if not is_instance_valid(app):
			return
		await app.get_tree().create_timer(1.5).timeout
		_close_results(app)
		await app.get_tree().create_timer(0.5).timeout

## Closes the top sheet and any result screen.
static func _close_results(app: Node) -> void:
	var top: Variant = app.call("_top_sheet") if app.has_method("_top_sheet") else null
	if top != null and is_instance_valid(top):
		top.close()
	var layer: Variant = app.get("sheet_layer")
	if layer is Node:
		for ch in (layer as Node).get_children():
			if ch is ResultScreen:
				(ch as ResultScreen).close()
