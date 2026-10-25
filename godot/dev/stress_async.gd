extends Node
## Dev: hammers the async UI paths (sheets closed while their timers / tweens / deferred calls / background builds are
## still pending) to flush out "Cannot call method ... on a null value" / "previously freed" script errors.
## godot --path . --resolution 390x844 res://dev/stress_async.tscn -- [rounds=6] [seed=1]
## Prints "STRESS DONE rounds=N" at the end; grep the output for SCRIPT ERROR (any is a failure).
## Like dev/tour: runs on a throwaway profile (the debounced flush is unhooked, the save is restored at the end).

var main: Node
var rounds := 6
var rng := RandomNumberGenerator.new()
var _backup := ""

func _ready() -> void:
	rng.seed = 1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("rounds="):
			rounds = int(a.trim_prefix("rounds="))
		elif a.begins_with("seed="):
			rng.seed = int(a.trim_prefix("seed="))
	if FileAccess.file_exists("user://save.json"):
		_backup = FileAccess.get_file_as_string("user://save.json")
	if Save._timer and Save._timer.timeout.is_connected(Save.flush):
		Save._timer.timeout.disconnect(Save.flush)      # dev run: nothing reaches user://save.json
	Save.prefs.welcome_seen = true
	Save.prefs.tutorial_done = true
	Save.profile.coins = 50000
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _until(func(): return main.screen == "home", 60)
	await _sleep(1.5)
	main.close_all_sheets()
	for r in rounds:
		print("stress round ", r)
		await _inventory_flows()
		await _preview_flows()
		await _coin_toast_flows()
		await _reward_sheets()
		await _shop_tabs()
		await _info_and_setup()
	await _sleep(1.5)                            # let every pending timer / tween fire after the last close
	print("STRESS DONE rounds=", rounds)
	_restore()
	get_tree().quit()

func _jitter(hi := 0.35) -> void:
	var k := rng.randi_range(0, 3)
	if k == 0:
		return                                    # same frame
	if k == 1:
		await get_tree().process_frame
		return
	await _sleep(rng.randf_range(0.0, hi))

## Inventory -> "Open shop" (the shop_requested lambda), closed at random moments, twice in a row, and cleared by
## close_all_sheets while the Inventory is still fading out.
func _inventory_flows() -> void:
	for i in 4:
		main._on_tab("inventory")
		await _jitter()
		var inv: Sheet = main._top_sheet()
		if inv and inv.has_signal("shop_requested"):
			inv._show_all()                       # "Open shop"
			if i % 2 == 0:
				inv._show_all()                   # a double tap
		await _jitter()
		if i == 3:
			main.go_home()
		else:
			main.close_all_sheets()
		await _jitter(0.2)
	main._on_tab("inventory")
	await get_tree().process_frame
	main.close_all_sheets()                       # removed on the same frame it opened
	await _sleep(0.3)

## PreviewSheet: closed before / during / after its live 3D build (room and scene kinds), and replaced by another.
func _preview_flows() -> void:
	for d in [0.0, 0.1, 0.3, 0.5, 0.9, 1.6]:
		var pv := PreviewSheet.new("dream" if rng.randf() < 0.5 else "night")
		pv.open(main.sheet_layer)
		await _sleep(d)
		if rng.randf() < 0.5:
			pv.close()
		else:
			main.close_all_sheets()
		await _jitter(0.2)
	for d in [0.05, 0.6, 1.4]:
		var id := str(SLScenes.LIST[rng.randi_range(0, SLScenes.LIST.size() - 1)].id)
		var pv := PreviewSheet.new(id, "scene")
		pv.open(main.sheet_layer)
		await _sleep(d)
		main.close_all_sheets()
		await _jitter(0.2)
	# a Shop with a preview over it, both cleared mid-build
	var s := ShopSheet.new("rooms")
	main._wire_shop(s)
	s.open(main.sheet_layer)
	await _sleep(0.4)
	var pv2 := PreviewSheet.new("dream")
	pv2.open(main.sheet_layer)
	await _sleep(0.45)
	main.close_all_sheets()
	await _sleep(0.6)

## CoinFly into a counter that goes away, a Toast anchored to a card that is freed before the toast attaches.
func _coin_toast_flows() -> void:
	for i in 3:
		var s := ShopSheet.new("rooms")
		main._wire_shop(s)
		s.open(main.sheet_layer)
		await _jitter(0.2)
		Toast.show(s, "stress toast %d" % i, s.card, 0.6, "good")
		if i == 1:
			Toast.show(s, "replaced", s.card, 0.6, "bad")
		if i == 2:
			s.free()                              # gone before the deferred attach
		else:
			main.close_all_sheets()
		await _jitter(0.2)
	var target: Control = main._home_coins()
	if target:
		CoinFly.run(main.ui_root, main.ui_root.size * 0.5, target, 200, func(): pass, int(Save.profile.coins))
		await _sleep(0.3)
		main._on_tab("inventory")
		await _sleep(0.2)
		main.close_all_sheets()
	# a CoinFly over a sheet that is freed mid-flight (its overlay goes with the sheet)
	var sh := ShopSheet.new("rooms")
	main._wire_shop(sh)
	sh.open(main.sheet_layer)
	await _sleep(0.2)
	if is_instance_valid(sh._balance):
		CoinFly.run(sh, sh.get_global_rect().get_center(), sh._balance, 100, func(): sh.refresh())
	await _sleep(0.25)
	main.close_all_sheets()
	main._on_tab("free")                          # the free-coins toast / flight
	await _jitter(0.3)
	main._on_tab("inventory")
	await _jitter(0.3)
	main.close_all_sheets()
	await _sleep(0.8)

## Daily calendar / spin: claimed and spun, then closed before their auto-close / spin-end callbacks fire.
func _reward_sheets() -> void:
	for t in ["daily", "spin", "daily", "spin"]:
		main._on_tab(t)
		await _sleep(0.5)
		var s: Sheet = main._top_sheet()
		if s is DailySheet and s.has_method("_claim"):
			s._claim()
		elif s is SpinSheet and s.has_method("_spin"):
			s._spin()
		await _jitter(0.6)
		main.close_all_sheets()
		await _jitter(0.3)
	await _sleep(1.0)

## The Shop's tab strip tapped quickly (thumbnails start loading), Owned filter flips, then closed.
func _shop_tabs() -> void:
	var s := ShopSheet.new("rooms", float(UIKit.W.catalog), true)
	main._wire_shop(s)
	s.open(main.sheet_layer)
	await _sleep(0.3)
	for t in ["scenes", "dice", "rooms", "avatars", "frames", "plates", "badges", "coins", "scenes"]:
		if is_instance_valid(s) and s.get("_tabs"):
			s._tabs.tap(t)
		await _jitter(0.12)
	if is_instance_valid(s) and s.has_method("set_owned_only"):
		s.set_owned_only(false)
	await _jitter(0.2)
	main.close_all_sheets()
	main._on_tab("scenes")
	await _jitter(0.2)
	main._on_tab("coins")                         # opens Get coins deferred over the Shop
	main.close_all_sheets()                       # ... which runs after the Shop is gone
	await _sleep(0.4)

## Info bubbles and setup sheets closed under each other; settings and how-to opened and cleared.
func _info_and_setup() -> void:
	main._open_setup("ludo", "cpu")
	await _sleep(0.3)
	Info.open_key("team")
	await _jitter(0.2)
	main.close_all_sheets()
	Info.close()
	main.open_settings()
	await _jitter(0.2)
	main.close_all_sheets()
	HowToSheet.new().open(main.sheet_layer)
	await _jitter(0.2)
	main._on_tab("profile")
	await _jitter(0.2)
	main.close_all_sheets()
	await _sleep(0.3)

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

func _sleep(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _until(f: Callable, timeout: float) -> void:
	var t0 := Time.get_ticks_msec()
	while not f.call() and (Time.get_ticks_msec() - t0) / 1000.0 < timeout:
		await get_tree().process_frame
