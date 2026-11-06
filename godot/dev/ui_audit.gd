extends Node
## Dev: screenshots of the Shop, the Inventory and Settings for design work, through the 1080x1920 launcher:
##   STORE_SCENE=ui_audit godot --path . --resolution 1080x1920 res://dev/store_shots.tscn -- <out_dir>
## Sound off, Save.writes_off on: nothing reaches user://save.json.

var out := "/tmp"
var main: Node

func _ready() -> void:
	Save.writes_off = true
	MatchStore.enabled = false
	AudioServer.set_bus_mute(0, true)
	var args := OS.get_cmdline_user_args()
	if args.size():
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	if OS.get_environment("UI_LANG") != "":
		Save.prefs.lang = OS.get_environment("UI_LANG")
	Save.prefs.welcome_seen = true
	Save.prefs.tutorial_done = true
	Save.prefs.erase("net_room")
	Save.profile.coins = 12450
	Save.profile.gems = 120
	for pair in [["dice_owned", ["crema", "gold"]], ["pawns_owned", ["kitty", "trim"]]]:
		for id in pair[1]:
			if not (Save.profile[pair[0]] as Array).has(id):
				(Save.profile[pair[0]] as Array).append(id)
	Rewards.daily_data(Save.profile).auto_on = Time.get_date_string_from_system()
	Quality.force("high")
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _until(func(): return main.screen == "home", 60)
	await _sleep(2.5)
	main.close_all_sheets()
	await _sleep(0.5)
	for tab: String in ["rooms", "scenes", "pawns", "dice", "emotes", "text", "avatars", "frames", "plates", "badges"]:
		var s := ShopSheet.new(tab)
		s.open(main.sheet_layer)
		await _sleep(1.6)
		await shot("shop_" + tab)
		main.close_all_sheets()
		await _sleep(0.4)
	for tab: String in ["rooms", "dice", "pawns", "avatars"]:
		var s := ShopSheet.new(tab, 400.0, true, true)
		s.open(main.sheet_layer)
		await _sleep(1.4)
		await shot("inv_" + tab)
		main.close_all_sheets()
		await _sleep(0.4)
	var item := ItemSheet.new("dice", "galaxy")
	item.open(main.sheet_layer)
	await _sleep(1.2)
	await shot("item_dice")
	main.close_all_sheets()
	await _sleep(0.4)
	var set_s := SettingsSheet.new()
	set_s.open(main.sheet_layer)
	await _sleep(1.0)
	for key: String in ["general", "game", "alerts", "more"]:
		set_s.show_page(key)
		await _sleep(0.5)
		await shot("settings_" + key)
		print(key, " content ", set_s.scroll_body.size.y, " view ", set_s.scroll_box.size.y)
	get_tree().quit()

func _process(_d: float) -> void:
	Save._dirty = false

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_png("%s/%s.png" % [out, name])

func _sleep(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _until(f: Callable, timeout: float) -> void:
	var t0 := Time.get_ticks_msec()
	while not f.call() and (Time.get_ticks_msec() - t0) / 1000.0 < timeout:
		await get_tree().process_frame
