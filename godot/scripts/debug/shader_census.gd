class_name ShaderCensus
extends RefCounted
## Debug builds only: lists every GL shader version the app compiles, for ShaderSeed.SEEDS. Run on an Android debug
## build (the cache only exists where the driver keeps program binaries' entries: Android / iOS):
##   adb shell run-as com.flipfold.ludozing sh -c 'echo --shader-census --quality=high > files/debug_args.txt'
##   launch, wait for "[census] done" in `adb logcat -s godot`, paste the printed SEEDS into scripts/core/shader_seed.gd
##   adb shell run-as com.flipfold.ludozing rm files/debug_args.txt
## After Home is up it plays a short Ludo match, puts every café room up, then plays a short Snakes & Ladders match in
## every scene, so each material the game uses is drawn once; then it reads user://shader_cache. The save is not
## written meanwhile (the debounced flush is unhooked; the run's profile changes stay in memory).
##
##   main.gd: if ShaderCensus.requested(): ShaderCensus.run(self)

static func requested() -> bool:
	return OS.is_debug_build() and Quality.arg("shader-census") != ""

static func run(main: Node) -> void:
	var tree := main.get_tree()
	if Save._timer and Save._timer.timeout.is_connected(Save.flush):
		Save._timer.timeout.disconnect(Save.flush)
	var wait := func(sec: float) -> void:
		await tree.create_timer(sec).timeout
	print("[census] start")
	await wait.call(1.0)
	main.start_ludo({game = "ludo", players = ["human", "cpu", "cpu", "cpu"], teams = false, bot_level = "normal"})
	await wait.call(6.0)
	main.go_home()
	for r: Dictionary in Rooms.LIST:
		print("[census] room ", r.id)
		await main.apply_room(str(r.id))
		await wait.call(2.0)
	var owned: Array = Save.profile.get("scenes", []) if Save.profile.get("scenes") is Array else []
	for id: String in SLScenes.SCENES:
		if not owned.has(id):
			owned.append(id)
	Save.profile.scenes = owned
	for id: String in SLScenes.SCENES:
		print("[census] scene ", id)
		Save.profile.scene = id
		main.start_sl({game = "sl", mode = "cpu", n = 4, color = 0, bot_level = "normal"})
		await wait.call(5.0)
		main.go_home()
		await wait.call(0.5)
	print("[census] SEEDS := {")
	for line in listing():
		print("[census] \t", line)
	print("[census] }")
	print("[census] done")

## The shader versions in user://shader_cache: one `"<Shader>": [["<sha1>", <variants>], ...],` line per shader.
static func listing() -> Array:
	var out := []
	var root := "user://shader_cache"
	for shader in DirAccess.get_directories_at(root):
		var seen := {}
		for base in DirAccess.get_directories_at(root.path_join(shader)):
			for f in DirAccess.get_files_at(root.path_join(shader).path_join(base)):
				if not f.ends_with(".cache"):
					continue
				var fa := FileAccess.open(root.path_join(shader).path_join(base).path_join(f), FileAccess.READ)
				if fa == null or fa.get_length() < 12:
					continue
				fa.get_32()
				fa.get_32()
				seen[f.get_basename()] = fa.get_32()
		if not seen.is_empty():
			var items := []
			for k: String in seen:
				items.append('["%s", %d]' % [k, seen[k]])
			out.append('"%s": [%s],' % [shader, ", ".join(items)])
	return out
