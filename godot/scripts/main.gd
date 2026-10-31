extends Node
## The app: builds the 3D café and the interface, runs the splash with real loading progress, and switches between
## the home screen, a Ludo game and a Snakes & Ladders game (index.html: start, setScreen, openSheet, pause menu).
##
## Flow: splash -> (first launch only) the welcome (name + free avatar) -> home. The daily reward opens by itself at
## most once a day: at launch on later days, or when the first game of a first day returns home (never on top of the
## welcome). A game ends on the full-screen ResultScreen (Play again / Home). A live match is kept by MatchStore, so
## Home offers "Continue match" after the app was closed or killed.
## Home's Ludo / Snakes & Ladders switch also picks the lobby's backdrop: the café, or the equipped S&L scene with its
## board (the Scenes tab of the Shop / Inventory changes it; with Snakes & Ladders picked both open on that tab).
## There is no separate S&L landing screen.
## Android's Back: closes the top sheet (Sheet.back), Home on a result, pauses a game, and asks before leaving the
## app on Home.
## Online (friend rooms, Ludo only): Home's Friends opens Online's Friends sheet; the room's `start` /
## `sync` comes back here as start_online(); the pause menu offers Leave match instead of Restart; the result's Play
## again is the host's rematch and Home leaves the room. A room kept from an earlier run is taken back at launch.

const GESTURE_DP := 20.0                # immersive mode hides the system bars but not the bottom swipe zone (PH-01)

var world: TableWorld
var baker: TexBaker
var sl_board: SLBoard
var sl_scenes: SLScenes                 # Snakes & Ladders worlds (jungle, frost...), shown instead of the café
var ui_root: Control
var screens: Control
var sheet_layer: Control
var home: HomeScreen
var hud: LudoHUD
var ludo: LudoMatch
var sl: SLMatch
var sl_hud: Control
var online: Online                      # friend rooms (scripts/net/online.gd)
var account: Account                    # the server account, wallet and claims (scripts/net/account.gd)
var notifications: Notifications        # reminders, push and the permission question (scripts/net/notifications.gd)
var ads: Ads                            # rewarded ads + the consent form (scripts/net/ads.gd; AdFlow shows them)
var gem_store: GemStore                 # the gem packs: Play Billing + server verification (scripts/net/gem_store.gd)
var crash_watch: CrashWatch             # breadcrumbs + the report of an unexpected exit (scripts/core/crash_watch.gd)
var screen := "splash"                  # splash | welcome | home | ludo | sl
var paused := false
var speed := 1.0
var safe_top := 0.0
var safe_bottom := 0.0
var last_ludo := {}                     # the config of the last Ludo / S&L game (Restart, Play again)
var last_sl := {}
var _pause_sheet: Sheet
var _result: ResultScreen
var _splash: Splash
var _xp_start := 0                      # Save.profile.xp when the current match began (the result's XP bar)
var _home_fly := 0                      # coins won in the last game: they fly to the home counter on "Home"
var _boost_until := 0                   # msec: Quality.game_fps() until then (sheet pops, drags, coin flights)
var _backdrop_id := 0                   # bumps on every Home backdrop change (a slow S&L scene build can't win late)
var _match_ms := 0                      # Time.get_ticks_msec() when the current offline match began (its claim duration)
var _pairs_start := 0                   # stats.pairsFormed when it began (the claim reports the pairs formed)
var _resumed := false                   # the match was continued from MatchStore (it began in an earlier session)
var _free_busy := false                 # a Free coins claim is waiting for the server
var _claim_id := ""                     # the claim of the match whose result is on screen
var _app_focused := true                # false while a system dialog / the notification shade has the focus
var _sl_seen := false                   # the S&L scene has been on screen (its shaders are compiled: no warm-up needed)


func _ready() -> void:
	crash_watch = CrashWatch.new()           # first: a crash while loading still leaves a record
	crash_watch.name = "CrashWatch"
	crash_watch.enabled = CrashWatch.should_run(OS.get_cmdline_user_args())
	crash_watch.context_fn = diag_context
	add_child(crash_watch)
	BootTrace.mark("main ready (%s tier)" % Quality.tier())
	BootTrace.watch_frames(self)
	var seeded := ShaderSeed.plant()          # first launch: no shader modes compiled that are never drawn
	if seeded:
		BootTrace.mark("shader cache seeded (%d)" % seeded)
	get_tree().set_auto_accept_quit(false)
	Quality.apply(get_viewport())            # low / medium / high: 3D scale, MSAA, filtering (auto per device)
	PerfOverlay.install(self)                # debug builds only: --perf / three-finger tap / F3
	Engine.max_fps = Quality.game_fps()      # the splash bar and the first frames run smooth
	speed = float(Save.prefs.speed)
	L10n.apply(Save.prefs.lang)              # the interface language (Settings; Auto: the phone's), before any text
	_apply_sound()
	account = Account.new()                  # guest sign-in, wallet, claims; started after the splash (_start_account)
	account.name = "Account"
	account.enabled = Account.should_start(OS.get_cmdline_user_args())
	add_child(account)
	account.conflict_raised.connect(_on_conflict)
	account.claim_answered.connect(_on_claim_answered)
	notifications = Notifications.new(self)
	notifications.name = "Notifications"
	add_child(notifications)
	ads = Ads.new()
	ads.name = "Ads"
	add_child(ads)
	gem_store = GemStore.new()
	gem_store.name = "GemStore"
	add_child(gem_store)
	gem_store.granted.connect(_on_gems_granted)
	baker = TexBaker.new()
	baker.name = "Baker"
	add_child(baker)
	world = TableWorld.new()
	world.name = "World"
	add_child(world)
	sl_board = SLBoard.new()
	sl_board.name = "SLBoard"
	sl_board.visible = false
	sl_scenes = SLScenes.new()
	sl_scenes.name = "SLScenes"
	sl_scenes.visible = false
	add_child(sl_scenes)
	sl_scenes.attach_board(sl_board)
	world.sl_board = sl_board
	var canvas := CanvasLayer.new()
	add_child(canvas)
	ui_root = Control.new()
	ui_root.name = "UI"
	ui_root.theme = UIKit.theme()
	ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(ui_root)
	screens = Control.new()
	screens.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screens.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(screens)
	sheet_layer = Control.new()
	sheet_layer.name = "Sheets"
	sheet_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sheet_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(sheet_layer)
	sheet_layer.z_index = 10                 # above anything a screen raises (the level star, z 1); CoinFly flies at 50
	sheet_layer.child_entered_tree.connect(func(n: Node):
		crash_watch.note("sheet", str(n.get_script().get_global_name()) if n.get_script() else str(n.name))
		boost(0.8))
	var splash := Splash.new()
	_splash = splash
	splash.z_index = 20
	ui_root.add_child(splash)
	_measure_safe_area()
	get_viewport().size_changed.connect(_on_resize)
	await get_tree().process_frame
	BootTrace.mark("first frame")
	splash.set_progress(0.08)
	await world.build_room(baker, func(f: float): splash.set_progress(0.08 + f * 0.72), str(Save.profile.room))
	BootTrace.mark("room built")
	splash.set_progress(0.9)                 # (the S&L board is painted by its scene: SLScenes.set_scene)
	_build_screens()
	apply_dice_skin()
	BootTrace.mark("screens built")
	await _warm_up()
	BootTrace.mark("warm-up done")
	if Quality.tier() == "low" and not (home.game == "sl" and bool(Save.prefs.welcome_seen)):
		world.view_home()                        # (go_home frames it the same way)
		await ShaderWarmUp.reveal_in_steps(world, world.camera, func(f: float): splash.set_progress(0.9 + 0.09 * f))
		BootTrace.mark("café drawn in steps")
	var first_run := not bool(Save.prefs.welcome_seen) and not Autoplay.requested()
	go_home()
	screen = "splash"                         # still loading: the home screen is ready underneath
	if first_run:
		home.visible = false                     # the welcome comes first, on the very first launch only
	await get_tree().process_frame
	splash.set_progress(1.0)
	Sound.play_music(true)
	BootTrace.mark("splash finishing")
	await splash.finish()
	_splash = null
	BootTrace.end("splash gone")
	_start_account()
	crash_watch.check_previous.call_deferred()   # did the last run die? (one report, sent a few seconds later)
	if ShaderCensus.requested():                # debug: draw every material once, list the shader cache
		home.visible = true
		_set_screen("home")
		ShaderCensus.run(self)
		return
	if Autoplay.maybe_start(self):
		_set_screen("home")
		return
	if not first_run:
		_set_screen("home")
		var opened := notifications.take_launch()    # the notification that started the app goes first
		if not online.try_resume() and not opened:   # a friends room kept from the last run comes back next
			_maybe_open_daily()
		notifications.maybe_ask()                   # the notifications question, once Home is quiet (if it is due)
		_bg_warm_up()
		return
	_set_screen("welcome")                      # (the S&L scene waits: _bg_warm_up after Home, if it is wanted at all)
	var w := Welcome.new()
	w.safe_top = safe_top
	w.safe_bottom = safe_bottom
	screens.add_child(w)
	await w.continued
	await w.leave()
	home.visible = true
	home.refresh()
	UIKit.pop_in(home)
	if account.enabled:
		account.push_identity()                 # the name and avatar picked on the welcome go to the server
	_set_screen("home")                         # no daily reward on top of the welcome: it waits for the first game
	notifications.maybe_ask()                   # the notifications question, right after the welcome
	_bg_warm_up()

## UPDATE_ONCE turns itself into UPDATE_DISABLED after its frame: the dice must go back to drawing while visible,
## or they freeze on their first frame for the rest of the session (no visible rolls).
func _restore_dice_updates(vps: Array[SubViewport]) -> void:
	for i in 2:
		await RenderingServer.frame_post_draw
	for vp in vps:
		if is_instance_valid(vp):
			vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE

## (Low tier, under the splash: the café's first draw compiles every material Home shows, in one frame: 10-30 s on
## the Android emulator, a few seconds on slow phones. ShaderWarmUp.reveal_in_steps draws it a material kind per
## frame, so the bar keeps moving.)
## Splash: draws the first-use shaders of what the first screen needs (PERF: shaders compile the first time they are
## drawn: ~0.1 s on the first Ludo roll for the dice). The S&L scene only when Home opens on it (Home's switch was
## left on Snakes & Ladders): otherwise _bg_warm_up() compiles it after Home is up.
func _warm_up() -> void:
	var dice_vps: Array[SubViewport] = []
	for d in [hud.dice, sl.dice]:
		if d and d.viewport:
			d.viewport.render_target_update_mode = SubViewport.UPDATE_ONCE   # draw once now, even while hidden
			dice_vps.append(d.viewport)
	_restore_dice_updates(dice_vps)
	if home.game == "sl" and bool(Save.prefs.welcome_seen):
		await sl_scenes.set_scene(baker, SLScenes.scene_in_use())
		BootTrace.mark("warm-up: S&L scene built")
		sl_board.visible = true
		_show_world(false)
		for i in 2:
			await RenderingServer.frame_post_draw
			BootTrace.mark("warm-up: S&L scene frame %d" % i)
		_show_world(true)
		sl_board.visible = false
	else:
		await get_tree().process_frame

## The S&L scene may be needed soon (a capable phone, or S&L was the last game played): build it and compile its
## shaders in the background once Home is quiet, a material kind per step (ShaderWarmUp: drawn offscreen, never
## shown), so the first S&L match doesn't freeze ~1.2 s while they compile. Stops when the scene is shown anyway.
func _bg_warm_up() -> void:
	var last := str((Save.prefs.get("last_played", {}) as Dictionary).get("game", "")) if Save.prefs.get("last_played") is Dictionary else ""
	if _sl_seen or not (Quality.tier() != "low" or last == "sl"):
		return
	var id := SLScenes.scene_in_use()
	await _until_quiet(1.0)
	if _sl_seen or not is_inside_tree():
		return
	var t0 := Time.get_ticks_msec()
	await sl_scenes.set_scene(baker, id)             # one texture per frame; the café stays up
	if _sl_seen or sl_scenes.current != id or not is_inside_tree():
		return
	var built := Time.get_ticks_msec()
	sl_board.setup_players([0, 1, 2, 3])            # (a match or Home's S&L backdrop sets its own)
	sl_scenes.play(true, str(Save.prefs.get("sl_cam", "3d")))
	_frame_sl_home()
	sl_scenes.snap_camera()
	sl_board.visible = true                          # (inside the hidden scene: drawn only by the warm-up)
	var w := ShaderWarmUp.new()
	w.name = "ShaderWarmUp"
	add_child(w)
	w.prepare(sl_scenes, sl_scenes.camera, get_viewport())
	var worst := 0
	while not w.finished():
		await _until_quiet(0.2)
		if _sl_seen or sl_scenes.current != id or not is_inside_tree():
			break
		var ts := Time.get_ticks_msec()
		await w.step(world, world.camera)
		worst = maxi(worst, Time.get_ticks_msec() - ts)
	if not sl_scenes.visible:
		sl_board.visible = false
	if BootTrace.on():
		print("[warm] S&L %s: built in %d ms, %d / %d shader steps (longest %d ms), done %d ms after Home was quiet" % [id,
			built - t0, mini(w._next, w.steps()), w.steps(), worst, Time.get_ticks_msec() - t0])
	w.queue_free()

## Waits until Home has been quiet (on screen, no sheet, no animation boost, no splash) for `sec` seconds.
func _until_quiet(sec: float) -> void:
	var since := -1
	while is_inside_tree():
		var quiet := screen == "home" and _splash == null and home.visible and home.game != "sl" \
			and _top_sheet() == null and not is_instance_valid(_result) and Time.get_ticks_msec() > _boost_until
		if not quiet:
			since = -1
		elif since < 0:
			since = Time.get_ticks_msec()
		elif Time.get_ticks_msec() - since >= int(sec * 1000.0):
			return
		await get_tree().process_frame

func _build_screens() -> void:
	_new_home()
	hud = LudoHUD.new()
	hud.name = "LudoHUD"
	hud.visible = false
	screens.add_child(hud)
	ludo = LudoMatch.new(self, world, hud)
	ludo.name = "LudoMatch"
	add_child(ludo)
	ludo.finished.connect(_on_finished.bind("ludo"))
	hud.pause_pressed.connect(open_pause)
	hud.settings_pressed.connect(open_settings)
	sl = SLMatch.new(self, world, sl_board)
	sl.name = "SLMatch"
	add_child(sl)
	sl.scenes = sl_scenes
	sl_hud = sl.build_hud(screens)
	sl_hud.visible = false
	sl.finished.connect(_on_finished.bind("sl"))
	sl.pause_pressed.connect(open_pause)
	sl.settings_pressed.connect(open_settings)
	online = Online.new(self)
	online.name = "Online"
	add_child(online)
	_on_resize()


## A fresh HomeScreen, wired, as `home` (the first one, or the one that replaces it in set_language).
func _new_home() -> void:
	home = HomeScreen.new()
	home.name = "Home"
	screens.add_child(home)
	home.open_tab.connect(_on_tab)
	home.play_game.connect(_open_setup)          # the game cards: (game "ludo" | "sl", mode "cpu" | "local") -> setup
	home.continue_match.connect(continue_match)
	home.game_switched.connect(_on_game_switched)  # Ludo / Snakes & Ladders: the backdrop follows


# ---------- layout, frame rate ----------

## Safe insets in UI px: the display cutout (top) and the gesture bar (bottom). The game runs in immersive mode, so
## Android reports no bottom inset although the bottom edge is still a swipe zone: keep at least GESTURE_DP clear.
## Debug builds can fake insets on desktop: `-- --safe=TOP,BOTTOM` (UI px).
func _measure_safe_area() -> void:
	var ins := insets()
	safe_top = ins.x
	safe_bottom = ins.y

func insets() -> Vector2:
	if OS.is_debug_build():
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--safe="):
				var p := a.trim_prefix("--safe=").split(",")
				return Vector2(float(p[0]), float(p[1]) if p.size() > 1 else 0.0)
	if not OS.has_feature("mobile"):
		return Vector2.ZERO
	var win := DisplayServer.window_get_size()
	if win.y <= 0:
		return Vector2.ZERO
	var safe := DisplayServer.get_display_safe_area()
	var vp := get_viewport().get_visible_rect().size
	var k := vp.y / float(win.y)
	var top := maxf(0.0, float(safe.position.y)) * k if safe.size.y > 0 else 0.0
	var bottom := maxf(0.0, float(win.y - safe.end.y)) * k if safe.size.y > 0 else 0.0
	var px_per_dp := maxf(1.0, DisplayServer.screen_get_dpi() / 160.0)
	return Vector2(top, maxf(bottom, GESTURE_DP * px_per_dp * k))

func _on_resize() -> void:
	_measure_safe_area()
	for c in [home, hud, sl_hud]:
		if c and "safe_top" in c:
			c.safe_top = safe_top
			c.safe_bottom = safe_bottom
	if hud:
		hud._layout()
		world.top_band = ui_root.size.y - safe_top - safe_bottom - 2 * (68.0 + 118.0) + 40.0   # between the card rows
	if sl and sl.hud:
		sl._layout()                             # (sets the match's board box: Home re-frames it below)
	if home:
		home._layout()
		_fit_home()

func _fit_home() -> void:
	await get_tree().process_frame
	var band := home.free_band()
	var k := maxf(home.table_width_factor, 0.1)   # Home may frame the table a little wider than the screen
	world.fit_home(band.x, band.y, Vector2(ui_root.size.x * k, ui_root.size.y))
	if screen == "home" and not sl_scenes.visible:
		world.view_home()
	if screen == "home" and home.game == "sl":
		_frame_sl_home()

## The S&L board framed in Home's free band (between the logo and the dock), at the match's 3D angle.
func _frame_sl_home() -> void:
	var band := home.free_band()
	var w := ui_root.size.x
	var side := minf(w * SLScenes.PLAY_FILL, 560.0)
	sl_scenes.set_board_box(Rect2((w - side) / 2.0, band.x, side, maxf(band.y - band.x, 80.0)))

## Switch the screen state: frame cap (30 on menus, 60 in games) and only the visible world's _process loops run.
func _set_screen(s: String) -> void:
	screen = s
	var cafe := world.visible
	world.set_process(cafe)
	world.board.set_process(cafe)                # pawns glide back to their bases on Home too
	sl_scenes.set_process(not cafe)
	sl_board.set_process(not cafe)
	home.set_process(home.visible)
	_apply_fps()
	crash_watch.set_screen(s)

func _apply_fps() -> void:
	var game := screen in ["ludo", "sl", "splash"]
	Engine.max_fps = Quality.game_fps() if game or Time.get_ticks_msec() < _boost_until else Quality.menu_fps()

## Run at 60 fps for a moment on a menu (a sheet popping in, a drag, coins flying), then back to 30.
func boost(sec := 0.8) -> void:
	var until := Time.get_ticks_msec() + int(sec * 1000.0)
	if until <= _boost_until:
		return
	var extend := Time.get_ticks_msec() < _boost_until
	_boost_until = until
	Engine.max_fps = Quality.game_fps()
	if extend:
		return                                   # the running timer re-checks when it fires
	while Time.get_ticks_msec() < _boost_until and is_inside_tree():
		await get_tree().create_timer((_boost_until - Time.get_ticks_msec()) / 1000.0 + 0.02).timeout
	_apply_fps()

func _input(e: InputEvent) -> void:
	if screen in ["ludo", "sl"]:
		return
	if e is InputEventScreenTouch or e is InputEventScreenDrag or (e is InputEventMouseButton and e.pressed) \
			or (e is InputEventMouseMotion and e.button_mask != 0):
		if Time.get_ticks_msec() + 600 > _boost_until:
			boost(1.2)


# ---------- screens ----------

## Close every sheet at once (starting or leaving a game: no prompt or result is left behind).
func close_all_sheets() -> void:
	for c in sheet_layer.get_children():
		sheet_layer.remove_child(c)
		c.queue_free()
	_pause_sheet = null
	_result = null

## The café world or a Snakes & Ladders scene world: only one is drawn, by its own camera.
func _show_world(cafe: bool) -> void:
	world.visible = cafe
	sl_scenes.visible = not cafe
	if cafe:
		world.camera.make_current()
	else:
		sl_scenes.camera.make_current()

func go_home() -> void:
	var from_game := screen in ["ludo", "sl"]
	close_all_sheets()
	Info.close()
	ludo.stop()
	sl.stop()
	paused = false
	home.visible = true
	home.refresh()
	hud.visible = false
	sl_hud.visible = false
	world.board.visible = true
	world.board.set_movable([])
	world.board.relayout(null)
	world.reduced_motion = false
	world.view_home()
	_set_screen("home")
	_home_backdrop()
	if from_game:
		var flying := _home_fly > 0 and _home_coins() != null
		_fly_winnings.call_deferred()
		_maybe_open_daily(1.6 if flying else 0.6)   # after the coins have landed
		notifications.maybe_ask()                   # back from a game: the notifications question, if it is due

## The coins won in the last game fly into the home counter (it counts up from the old balance).
func _fly_winnings() -> void:
	var n := _home_fly
	_home_fly = 0
	var target := _home_coins()
	if n <= 0 or target == null:
		return
	await get_tree().process_frame
	if screen != "home" or not is_instance_valid(target):
		return
	target.set_amount(int(Save.profile.coins) - n, false)
	boost(2.0)
	CoinFly.run(ui_root, ui_root.size * Vector2(0.5, 0.55), target, n, Callable(), int(Save.profile.coins))

## The reward calendar opens by itself once a day when a reward is waiting: at launch on later days, or when a game
## of the first day returns home. Never over the welcome, another sheet or a result.
func _maybe_open_daily(delay := 0.6) -> void:
	if Autoplay.requested() or not bool(Save.prefs.welcome_seen):
		return
	if not Rewards.should_auto_open(Save.profile):
		return
	await get_tree().create_timer(delay).timeout
	if screen == "home" and _top_sheet() == null and Rewards.should_auto_open(Save.profile):
		Rewards.mark_auto_open(Save.profile)
		_on_tab("daily")

## Puts the Ludo screen up (no match started yet).
func _enter_ludo() -> void:
	close_all_sheets()
	Info.close()
	ludo.stop()
	sl.stop()
	_backdrop_id += 1                        # a Home backdrop still building stays hidden
	_show_world(true)
	paused = false
	home.visible = false
	sl_hud.visible = false
	hud.visible = true
	world.board.visible = true
	sl_board.visible = false
	_set_screen("ludo")
	_show_bar("ludo")
	_xp_start = int(Save.profile.xp)
	_begin_match_clock()

func start_ludo(cfg: Dictionary) -> void:
	last_ludo = cfg.duplicate(true)
	var tutorial := bool(cfg.get("tutorial", false))
	if not tutorial:                          # the lesson is not a setup to remember
		Save.prefs.last_players = cfg.players
		Save.prefs.last_played = {game = "ludo", mode = "cpu" if (cfg.players as Array).has("cpu") else "local"}
		Save.save()
	_enter_ludo()
	var opts := {bot_level = str(cfg.get("bot_level", Save.prefs.get("bot_level", "normal"))),
		pair_ask = bool(Save.prefs.get("pair_ask", true)), tutorial = tutorial, then = str(cfg.get("then", "cpu"))}
	if cfg.get("names") is Array:
		opts.names = (cfg.names as Array).duplicate()   # Pass & Play: [4] by colour, "" = the default name
	ludo.start(cfg.players, bool(cfg.get("teams", false)), opts)

## An online match from the room's `start` (or a `sync` taking back a match in progress). net: Online's NetClient.
func start_online(msg: Dictionary, net: Object) -> void:
	if str(msg.get("game", "ludo")) == "sl":
		await _enter_sl()
		if screen == "sl":
			sl.start_online(msg, net)
		return
	_enter_ludo()
	ludo.start_online(msg, net)

## An online match is on screen (Ludo or Snakes & Ladders).
func _online_match() -> bool:
	return (screen == "ludo" and ludo.online) or (screen == "sl" and bool(sl.get("online")))

## The room's host changed (the result's Play again follows).
func online_host_changed(is_host: bool) -> void:
	if is_instance_valid(_result) and _result.has_method("set_host"):
		_result.set_host(is_host)

## The room closed under us (gone on the server): back home.
func online_closed() -> void:
	if _online_match():
		go_home()

## Puts the S&L game screen up in the equipped scene (no match started yet). Coroutine (the scene may build).
func _enter_sl() -> void:
	close_all_sheets()
	Info.close()
	ludo.stop()
	sl.stop()
	paused = false
	home.visible = false
	hud.visible = false
	sl_hud.visible = true
	_backdrop_id += 1
	_sl_seen = true
	_show_world(false)
	_set_screen("sl")
	_show_bar("sl")
	_xp_start = int(Save.profile.xp)
	_begin_match_clock()
	await sl_scenes.set_scene(baker, SLScenes.scene_in_use())
	sl_board.visible = true

func start_sl(cfg: Dictionary) -> void:
	var c := cfg.duplicate(true)
	c.need_one = bool(Save.prefs.get("sl_need_one", true))       # house rule "Need a 1 to start"
	last_sl = c
	Save.prefs.last_played = {game = "sl", mode = str(c.get("mode", "cpu"))}
	Save.save()
	await _enter_sl()
	if screen == "sl":
		sl.start(c)

## Home's switch changed: the café for Ludo, the equipped S&L scene for Snakes & Ladders.
func _on_game_switched(_game: String) -> void:
	if screen == "home":
		_fit_home()
		_home_backdrop()

## Home's backdrop for the game picked on the switch. Snakes & Ladders: the equipped scene (built on first use; the
## café stays up meanwhile) with its empty board framed in Home's free band. Coroutine; a newer call wins.
func _home_backdrop() -> void:
	_backdrop_id += 1
	var my := _backdrop_id
	if home.game != "sl":
		if sl_scenes.visible:
			_show_world(true)
			sl_board.visible = false
			world.view_home()
			_set_screen(screen)
		return
	await sl_scenes.set_scene(baker, SLScenes.scene_in_use())
	if my != _backdrop_id or screen not in ["home", "splash"] or home.game != "sl":
		return                                   # (a game started, or the switch moved on, while it built)
	_sl_seen = true
	sl_board.setup_players([])
	sl_board.visible = true
	sl_scenes.play(true, "3d")               # the match's 3D framing: the board fits the band, the table holds still
	_frame_sl_home()
	sl_scenes.snap_camera()
	_show_world(false)
	_set_screen(screen)

## (Kept for dev scripts: the S&L landing is gone.) Home with Snakes & Ladders picked on the switch.
func open_sl_landing() -> void:
	if screen != "home":
		go_home()
	home.select_game("sl")
	await _home_backdrop()

func _open_setup(game: String, mode: String) -> void:
	if mode == "online":
		if game == "ludo":
			online.open_friends()
		else:
			_home_toast(tr("Coming soon for Snakes & Ladders"), "bad")
			Haptics.error()
			Sound.sfx("error")
		return
	if game == "ludo" and not Tutorial.done():
		start_ludo(Tutorial.config(mode))       # the guided first match (mode: where "Play a real game" leads)
		return
	var s := SetupSheet.new(game, mode)
	s.start.connect(func(cfg: Dictionary):
		if str(cfg.get("game", game)) == "ludo":
			start_ludo(cfg)
		else:
			start_sl(cfg))
	s.open(sheet_layer)

## A start config from remembered setup choices {count, color, teams, bot_level, names} (as SetupSheet builds it;
## Pass & Play names are kept in seat order and passed on as cfg.names, [4] by colour; Save.prefs.last_setup).
static func setup_config(game: String, mode: String, d: Dictionary) -> Dictionary:
	var cpu := mode == "cpu"
	var count := clampi(int(d.get("count", 3 if cpu else 2)), 1 if cpu else 2, 3 if cpu else 4)
	var color := clampi(int(d.get("color", 0)), 0, 3) if cpu else 0
	var teams := bool(d.get("teams", false))
	var level := str(d.get("bot_level", Save.prefs.get("bot_level", "normal")))
	var names: Array = SetupSheet.names_by_color(game, count, d.get("names", []) if d.get("names") is Array else [])
	if game == "sl":
		var c := {game = "sl", mode = mode, n = count + 1 if cpu else count, color = color, bot_level = level}
		if not cpu:
			c.names = names
		return c
	var players := ["off", "off", "off", "off"]
	if cpu:
		players[color] = "human"
		for k in ([2] if count == 1 else ([1, 2] if count == 2 else [1, 2, 3])):
			players[(color + k) % 4] = "cpu"
		return {game = "ludo", players = players, teams = count == 3 and teams, bot_level = level}
	var seats: Array = [0, 2] if count == 2 else ([0, 1, 2] if count == 3 else [0, 1, 2, 3])
	for c in seats:
		players[c] = "human"
	return {game = "ludo", players = players, teams = count == 4 and teams, bot_level = level, names = names}

## Home's "Continue match": resumes the match MatchStore kept (Ludo, or S&L).
func continue_match() -> void:
	if not MatchStore.has_saved():
		home.refresh()
		return
	var game := MatchStore.game()
	var st := MatchStore.load()
	if st.is_empty() or game not in ["ludo", "sl"]:
		_home_toast(tr("This match can’t be continued."), "bad")
		MatchStore.clear()
		home.refresh()
		return
	if game == "sl":
		last_sl = _sl_cfg_of(st)
		await _enter_sl()
		if screen == "sl":
			_resumed = true
			sl.resume(st)
	else:
		last_ludo = _ludo_cfg_of(st)
		_enter_ludo()
		_resumed = true
		ludo.resume(st)

## The config of a kept Ludo match ({S, players, teams, opts}) for Restart / Play again (the bot level included).
static func _ludo_cfg_of(d: Dictionary) -> Dictionary:
	var s: Dictionary = d.get("S", d) if d.get("S", d) is Dictionary else {}
	var players: Array = d.get("players", s.get("players", ["human", "cpu", "cpu", "cpu"]))
	var o: Variant = d.get("opts", {})
	var level := str((o as Dictionary).get("bot_level", Save.prefs.get("bot_level", "normal"))) if o is Dictionary else str(Save.prefs.get("bot_level", "normal"))
	var cfg := {game = "ludo", players = players, teams = bool(d.get("teams", s.get("teams", false))), bot_level = level}
	if players.count("human") > 1 and s.get("names") is Array and (s.names as Array).size() == 4:
		cfg.names = (s.names as Array).duplicate()        # Pass & Play: Restart keeps the names
	return cfg

## The config of a kept S&L match: SLMatch.save_match() keeps {game, cfg, G}; older saves are a bare rules state.
static func _sl_cfg_of(d: Dictionary) -> Dictionary:
	var cfg: Variant = d.get("cfg")
	if cfg is Dictionary and (cfg as Dictionary).has("n"):
		return (cfg as Dictionary).duplicate(true)
	var g: Dictionary = d.get("G", d) if d.get("G", d) is Dictionary else {}
	var ps: Array = g.get("players", [])
	var col := 0
	for p in ps:
		if p is Dictionary and bool(p.get("you", false)):
			col = int(p.get("c", 0))
	return {game = "sl", mode = str(g.get("mode", "cpu")), n = maxi(2, ps.size()), color = col}

## Home's tabs and buttons (and the deep links of notifications: daily, spin, free, leaderboard, shop).
func _on_tab(tab: String) -> void:
	match tab:
		"home":
			if screen != "home":
				go_home()
		"ludo":
			if screen != "home":
				go_home()
		"sl", "snake":
			open_sl_landing()
		"scenes":                                       # the Shop's Scenes tab (Snakes & Ladders worlds)
			var s := ShopSheet.new("scenes")
			_wire_shop(s)
			s.open(sheet_layer)
		"store", "gems":
			open_store()
		"shop", "coins":
			var s := ShopSheet.new("coins" if tab == "coins" else _home_shop_tab())
			_wire_shop(s)
			s.open(sheet_layer)
		"inventory", "collection", "owned":                 # the nav's Inventory: what you own, ready to use
			var s := ShopSheet.new(_home_shop_tab(), 400.0, true, true)
			_wire_shop(s)
			s.shop_requested.connect(func(t: String):
				s.close()
				var shop := ShopSheet.new(t)
				_wire_shop(shop)
				shop.open(sheet_layer))
			s.open(sheet_layer)
		"rewards":                                      # Home's gift: Free spin / Daily reward / Free coins
			var s := RewardsSheet.new()
			s.picked.connect(_on_tab)                   # each row does what its own button does (spin / daily / free)
			s.closed.connect(home.refresh)
			s.open(sheet_layer)
		"spin":
			var s := SpinSheet.new()
			s.closed.connect(home.refresh)
			s.open(sheet_layer)
		"daily":
			var s := DailySheet.new()
			s.closed.connect(home.refresh)
			s.claimed.connect(func(_r: Dictionary):        # one tap: the calendar closes itself after the coin flight
				await get_tree().create_timer(0.8).timeout
				if is_instance_valid(s) and not s.is_queued_for_deletion():
					s.close())
			s.open(sheet_layer)
		"free":
			_claim_free()
		"leaderboard", "ranks":
			LeaderboardSheet.new().open(sheet_layer)
		"profile":
			var p := ProfileSheet.new()
			p.profile_changed.connect(home.refresh)
			p.open(sheet_layer)
		"settings":
			open_settings()
		"howto":
			HowToSheet.new().open(sheet_layer)

## The Shop / Inventory tab Home opens on: Scenes while Snakes & Ladders is picked (where its world is changed),
## else Rooms.
func _home_shop_tab() -> String:
	return "scenes" if home and home.game == "sl" else "rooms"

## Profile -> Shop and other sheets that open the Shop themselves call this on the sheet they open:
## rooms, dice and scenes put in use there reach the game at once, and Home refreshes when it closes.
func apply_shop_changes(sheet: Sheet) -> void:
	_wire_shop(sheet)

## (Kept for callers that still use the old name. Use apply_shop_changes.)

func _wire_shop(s: Sheet) -> void:
	if s.has_signal("room_changed"):
		s.connect("room_changed", func(id: String): apply_room(id))
	if s.has_signal("dice_changed"):
		s.connect("dice_changed", func(_id: String): apply_dice_skin())
	if s.has_signal("scene_changed"):
		s.connect("scene_changed", func(_id: String):
			if screen == "home" and home.game == "sl":
				_home_backdrop())
	if s.has_signal("store_requested"):
		s.connect("store_requested", open_store)
	s.closed.connect(home.refresh)

## Switch the café to a room theme (built on first use; the splash already built the equipped one).
func apply_room(id: String) -> void:
	await world.rooms.set_room(baker, id)
	_fit_home()

## The equipped dice skin on every die in the game.
func apply_dice_skin() -> void:
	var sk: Dictionary = Catalog.dice(str(Save.profile.dice))
	if sk.is_empty():
		return
	for d: Dice3D in [hud.dice, sl.dice]:
		if is_instance_valid(d):
			d.set_skin(sk.bg, sk.edge, sk.pip, sk.one)

## Free coins: claim them (coins fly from the Rewards sheet's row, else Home's gift, into the counter) or say when
## they are ready.
func _claim_free() -> void:
	var left := Rewards.free_left_sec(Save.profile)
	var from := _home_side("free")
	if left > 0:
		_home_toast(tr("Free coins in %s") % Fmt.until(left), "bad")
		if from and from.has_method("shake"):
			from.call("shake")
		Haptics.error()
		Sound.sfx("error")
		return
	var before := int(Save.profile.coins)
	var n := 0
	if Account.wallet_active():
		if _free_busy:
			return
		_free_busy = true
		home.hold_coins(2.5)                # the answer fires Save.changed: the counter waits for the coins to land
		var r: Dictionary = await account.free_coins()
		_free_busy = false
		if not r.get("ok", false):
			_home_toast(Account.error_text(str(r.get("error", "")), "claim"), "bad")
			Haptics.error()
			if from and from.has_method("shake"):
				from.call("shake")
			home.refresh()
			return
		n = int(r.get("coins", 0))
	else:
		n = Rewards.claim_free(Save.profile)
	if n <= 0:
		return
	Sound.sfx("coin", n)
	Haptics.success()
	home.refresh()
	var target := _home_coins()
	if target:
		target.set_amount(before, false)
		boost(2.0)
		var at: Vector2 = from.get_global_rect().get_center() if from else ui_root.size * 0.5
		CoinFly.run(ui_root, at, target, n, Callable(), int(Save.profile.coins))
	_home_toast(tr("%s coins") % Fmt.gain(n), "coin")

## A toast on Home: just above the dock (or the Continue pill), never over the play buttons; under the card of a
## sheet open on top (the Rewards sheet); elsewhere the usual place.
func _home_toast(text: String, kind := "info") -> void:
	var top := _top_sheet()
	if top and screen == "home":
		Toast.show(ui_root, text, top.card, 1.8, kind)
		return
	var over: Control = home.toast_anchor() if screen == "home" and home and home.visible else null
	if over:
		Toast.show_above(ui_root, text, over, 1.8, kind)
	else:
		Toast.show(ui_root, text, null, 1.8, kind)

## Home's coin counter (CoinAmount), or null.
func _home_coins() -> CoinAmount:
	return home.coin_amount if home and is_instance_valid(home.coin_amount) else null

## Where the coins of a reward ("spin" | "daily" | "free") fly from: its row in the Rewards sheet when that is the
## top sheet, else Home's gift (null for anything else).
func _home_side(id: String) -> Control:
	var top := _top_sheet()
	if top is RewardsSheet:
		var row := (top as RewardsSheet).row(id)
		if row:
			return row
	return home.side_button(id)

## A short message near the bottom of the screen (kept for older callers).
func toast(text: String) -> void:
	Toast.show(ui_root, text)

func open_settings() -> SettingsSheet:
	var s := SettingsSheet.new()
	s.prefs_changed.connect(_on_prefs_changed)
	s.language_picked.connect(set_language)
	if screen in ["ludo", "sl"]:               # opened from a game: computer turns wait
		paused = true
		s.closed.connect(func(): paused = _pause_sheet != null)
	s.open(sheet_layer)
	return s

## Settings' language switch (pref "auto" | "en" | "bn", Save.prefs.lang). Text made with tr() keeps the language
## it was made in, so what is on screen is built again: Home (a fresh HomeScreen in the old one's place) and the
## open sheets (all closed; Settings opens again, over the pause menu when in a game). Local notifications follow
## by themselves (they are written when the app goes away). In a match, the next status line, toasts and every
## sheet opened later are in the new language; the line on screen and the HUD's fixed labels (your seat's name,
## tags) change with the next turn / the next match.
func set_language(pref: String) -> void:
	Save.prefs.lang = pref if pref in L10n.LANGS else "auto"
	Save.save()
	var before := L10n.lang()
	if L10n.apply(Save.prefs.lang) == before:
		return
	var in_game := screen in ["ludo", "sl"]
	var had_pause := _pause_sheet != null
	close_all_sheets()
	Info.close()
	var old := home
	var at := old.get_index()
	old.name = "HomeOld"
	_new_home()
	screens.move_child(home, at)
	home.visible = old.visible
	old.queue_free()
	online._wire_home()
	_on_resize()
	_set_screen(screen)
	if in_game and had_pause:
		open_pause()
	open_settings()                              # (the Language row is near its top)

func _on_prefs_changed() -> void:
	speed = float(Save.prefs.speed)
	world.board.speed = speed
	_apply_sound()
	notifications.prefs_changed()
	if screen == "ludo":
		world.set_top_view(Save.prefs.cam == "top")
	elif screen == "sl":
		sl_scenes.set_view(Save.prefs.sl_cam)

func _apply_sound() -> void:
	var v: Dictionary = Save.prefs.vol
	Sound.set_enabled(bool(Save.prefs.sound))
	Sound.set_volumes(int(v.master), int(v.music), int(v.sfx))


# ---------- pause / result ----------

func _game_over() -> bool:
	return (screen == "ludo" and ludo.S.get("phase", "") == "over") or (screen == "sl" and sl.G.get("phase", "") == "over")

## The pause menu (PM look): Resume / Restart / Settings / Exit to home. Restart and Exit ask first.
func open_pause() -> void:
	if screen not in ["ludo", "sl"] or _pause_sheet != null or is_instance_valid(_result) or _game_over():
		return
	var top := _top_sheet()
	if top and not top.dismissable:
		return                                   # a question is open: it holds the game anyway
	paused = true
	var on := _online_match()
	var s := Sheet.new(tr("Menu") if on else tr("Paused"), UIKit.W.dialog, false, "pm")
	s.dismissable = true                         # Back / a backdrop tap = Resume
	_pause_sheet = s
	s.body.add_theme_constant_override("separation", UIKit.SPACE.md)
	if on:                                       # online the game goes on: no pause, no restart
		var note := s.add_text(tr("The game keeps going while this is open."), UIKit.FS.body)
		note.add_theme_color_override("font_color", Palette.SUB)
		s.add_button(tr("Back to game"), "honey", s.close, "lg")
		s.add_button(tr("Settings"), "ghost", open_settings, "md")
		s.add_button(tr("Leave match"), "ghost", _ask_leave_online, "md")
	else:
		s.add_button(tr("Resume"), "honey", s.close, "lg")
		s.add_button(tr("Restart"), "ghost", _ask_restart, "md")
		s.add_button(tr("Settings"), "ghost", open_settings, "md")
		s.add_button(tr("Exit to home"), "ghost", _ask_exit, "md")   # safe: the match is kept (Continue match)
	s.closed.connect(func():
		if _pause_sheet == s:
			_pause_sheet = null
		paused = _top_sheet() != null and screen in ["ludo", "sl"])
	s.open(sheet_layer)

## Online: leaving a match is for good (a bot takes your colour); ask first. Once your side has finished (play on)
## nothing is lost: your place stands and is granted at the end.
func _ask_leave_online() -> void:
	var done := _online_finished()
	var body := tr("Your place is kept: your reward comes when the game ends.") if done else tr("A bot plays your colour for the rest of the game.")
	if not await Sheet.confirm(self, tr("Leave this match?"), body, tr("Leave"), tr("Keep playing") if not done else tr("Keep watching"), true):
		return
	if not _online_match():
		return
	online.leave()
	go_home()

## The finish card's Home (play on: your side has finished, the others play on): leave the room for Home. The
## server keeps your place and grants it at the end.
func leave_online_match() -> void:
	if not _online_match():
		return
	online.leave()
	go_home()

## Your side has finished in the online match on screen (play on).
func _online_finished() -> bool:
	if screen == "ludo" and ludo.online and ludo.ns != null and ludo.ns.me >= 0 and not ludo.S.is_empty():
		return LudoHUD.done_place(ludo.S, ludo.ns.me) > 0
	if screen == "sl" and sl.online and sl.ns != null and not sl.G.is_empty():
		var k: int = sl.ns.index_of(sl.ns.me)
		return k >= 0 and SLMatch.done_place(sl.G, k) > 0
	return false

func _ask_restart() -> void:
	var game := screen
	if not await Sheet.confirm(self, tr("Restart this game?"), tr("Everyone goes back to the start."), tr("Restart"), tr("Keep playing"), true):
		return
	if screen != game:
		return
	_clear_match()
	_restart(game)

func _ask_exit() -> void:
	var game := screen
	if not await Sheet.confirm(self, tr("Leave this game?"), tr("Your progress in this match is saved."), tr("Leave"), tr("Keep playing")):
		return
	if screen != game:
		return
	_flush_match()
	var kept := MatchStore.load()            # the match as it was after the last turn
	var game_key := MatchStore.game()
	var summary := str(MatchStore.peek().get("summary", ""))
	go_home()                                # (stopping a match forgets it: put it back for "Continue match")
	if not kept.is_empty() and game_key == game:
		MatchStore.save(game_key, kept, summary)
		home.refresh()

func _restart(game: String) -> void:
	if game == "ludo":
		start_ludo(last_ludo)
	else:
		start_sl(last_sl)

## The game bar (GameTopBar) of a game's HUD, or null.
func _bar(game: String) -> Control:
	for h in ([hud] if game == "ludo" else [sl.get("hud"), sl]):
		if h is Object and is_instance_valid(h):
			for key in ["bar", "top"]:
				var b: Variant = h.get(key)
				if b is Control and is_instance_valid(b):
					return b
	return null

func _show_bar(game: String) -> void:
	var b := _bar(game)
	if b and b.has_method("show_bar"):
		b.call("show_bar")

## The match ended: the full-screen ResultScreen with the standings, coins and XP. Play again restarts the same
## setup; Home (or Back) goes home, where the coins won fly into the counter.
func _on_finished(result: Dictionary, game: String) -> void:
	if is_instance_valid(_result):
		return
	close_all_sheets()
	Info.close()
	var net_game := bool(result.get("online", false))
	if not net_game:
		_clear_match()                           # (online matches are never kept; a saved offline one stays)
	var b := _bar(game)
	if b and b.has_method("hide_for_result"):
		b.call("hide_for_result")
	var data := result.duplicate()
	data.game = game
	if not data.get("standings") is Array or (data.standings as Array).is_empty():
		data.standings = _standings(game)    # a match that sent no standings: built from its final state
	if not data.has("xp_before"):
		data.xp_before = _xp_start
	if not data.has("xp_after"):
		data.xp_after = int(Save.profile.xp)
	data.reward = int(data.get("reward", 0))
	data.human_won = bool(data.get("human_won", false))
	var target := _home_coins()
	if target and target.is_visible_in_tree():
		data.coin_target = target
	data.coin_total = int(Save.profile.coins)
	data.safe_top = safe_top
	data.safe_bottom = safe_bottom
	_home_fly = int(data.reward)
	_claim_id = ""
	if not net_game and account.enabled:
		var info := _claim_info(game, data)
		if not info.is_empty():
			_claim_id = account.report_match(info)   # the server reconciles the local reward (queued when offline)
	if net_game:
		data.host = online.is_host()
	var r := ResultScreen.new(data)
	_result = r
	if net_game:
		r.play_again.connect(online.rematch)     # the room's next `start` replaces this screen
		r.home.connect(func():
			online.leave()
			go_home())
	else:
		r.play_again.connect(func():
			_home_fly = 0
			_restart(game))
		r.home.connect(go_home)
	r.open(sheet_layer)

## Launch: the guest account (a kept session is used at once; offline the game just carries on locally).
func _start_account() -> void:
	if account.enabled:
		account.start()
		gem_store.launch_check()              # a payment an earlier run left unverified, and what Play still holds
		_ads_consent()

## The ads consent form (UMP) and the first rewarded ad, once Home is quiet: after the notifications question (its soft
## prompt and the system dialog under it), never over a sheet or a game. Asked every launch: the form only shows where
## it is needed (EEA / UK) and answers at once otherwise; that also tells us whether Settings offers "Privacy choices".
func _ads_consent() -> void:
	if not ads.available():
		return
	var since := -1
	while is_inside_tree():
		var quiet := screen == "home" and _splash == null and home.visible and _top_sheet() == null and _app_focused \
			and not bool(notifications.get("_ask_wanted")) and not is_instance_valid(_result)
		if not quiet:
			since = -1
		elif since < 0:
			since = Time.get_ticks_msec()
		elif Time.get_ticks_msec() - since >= 2500:
			break
		await get_tree().process_frame
	if not is_inside_tree():
		return
	ads.consent_done.connect(func(can: bool, _privacy: bool):
		if can:
			ads.load_rewarded(), CONNECT_ONE_SHOT)
	ads.request_consent()

## "+80 gems" after a purchase is verified (the Store sheet shows its own toast).
func _on_gems_granted(gems: int, _product: String) -> void:
	if _top_sheet() is StoreSheet:
		return
	if screen == "home":
		_home_toast(tr("+%s gems") % Fmt.coins_full(gems), "gem")
	home.refresh()

## The Store: gem packs and swapping gems for coins.
func open_store() -> void:
	var top := _top_sheet()
	if top is StoreSheet:
		return
	var s := StoreSheet.new(gem_store)
	s.closed.connect(home.refresh)
	s.open(sheet_layer)

func _begin_match_clock() -> void:
	_match_ms = Time.get_ticks_msec()
	_pairs_start = int(Save.profile.get("stats", {}).get("pairsFormed", 0))
	_resumed = false

## The claim for a finished offline match (POST /v1/claims body, without the id): {} when there is nothing to claim.
## A match continued from a saved one is credited the minimum duration (it began in an earlier session).
func _claim_info(game: String, data: Dictionary) -> Dictionary:
	var secs := int((Time.get_ticks_msec() - _match_ms) / 1000.0) + (60 if _resumed else 0)
	var result := "win" if bool(data.get("human_won", false)) else "loss"
	var placing := claim_placing(data.get("standings", []))   # play on: your final place decides the reward
	if game == "ludo":
		var seats: Array = (ludo.S.get("players", []) as Array).duplicate()
		if seats.size() != 4:
			return {}
		var pairs := maxi(0, int(Save.profile.get("stats", {}).get("pairsFormed", 0)) - _pairs_start)
		var info := {game = "ludo", mode = "cpu" if seats.has("cpu") else "pp", result = result, players = seats, duration_s = secs, pairs = pairs}
		if placing > 0:
			info.placing = placing
		return info
	var g: Dictionary = sl.G
	if g.is_empty():
		return {}
	var info := {game = "sl", mode = str(g.get("mode", "cpu")), result = result, players = (g.players as Array).size(), duration_s = secs}
	if placing > 0:
		info.placing = placing
	if info.mode == "cpu":
		var rolls := []
		for p: Dictionary in g.players:
			if bool(p.get("you", false)):
				for v in p.get("rolls", []):
					rolls.append(int(v))
		info.rolls = rolls
		info.need_one = bool(g.get("need_one", false))
	return info

## Your (your team's) final place in a result's standings (1-based; 0: no "you", e.g. Pass & Play): the claim's
## `placing`, which the server pays by (1 = the win reward, any other place the play reward).
static func claim_placing(standings: Variant) -> int:
	if standings is Array:
		for e in standings:
			if e is Dictionary and str(e.get("kind", "")) == "you":
				return int(e.get("place", 0))
	return 0

## The server answered a claim: a limited one is said quietly (the result screen, else a toast) and the coins that
## are still to fly to Home shrink to what was paid.
func _on_claim_answered(id: String, ans: Dictionary) -> void:
	var note := Account.claim_note(ans)
	if id == _claim_id and id != "":
		if bool(ans.get("limited", false)):
			_home_fly = mini(_home_fly, int(ans.get("coins", 0)))
		if note != "" and is_instance_valid(_result) and not _result.is_queued_for_deletion():
			_result.set_claim_note(note)
			return
	if note != "" and screen == "home":
		_home_toast(note)

## Google sign-in needs a decision (this device's progress or the Google account's).
func _on_conflict(_c: Dictionary) -> void:
	ConflictSheet.present(sheet_layer, account)

## Standings for the result from the finished match state (when the match didn't send its own).
func _standings(game: String) -> Array:
	var out := []
	if game == "ludo":
		var s: Dictionary = ludo.S
		if s.is_empty():
			return out
		for e: Dictionary in LudoRules.standings(s):
			var c := int(e.color)
			var kind := "you" if NetLudo.you(s, c) else ("human" if LudoRules.is_human(s, c) else "cpu")
			var row := e.duplicate()
			row.kind = kind
			row.name = "You" if kind == "you" else LudoRules.pname(s, c)
			row.cpu_id = LudoRules.pname(s, c)
			out.append(row)
	else:
		var g: Dictionary = sl.G
		if g.is_empty():
			return out
		for e: Dictionary in SnakesLaddersRules.standings(g):
			var p: Dictionary = g.players[int(e.idx)]
			var row := e.duplicate()
			row.kind = "you" if bool(p.get("you", false)) else ("cpu" if bool(p.get("cpu", false)) else "human")
			row.cpu_id = str(p.get("name", ""))
			out.append(row)
	return out

## Saves the live match now (the app is going to the background or losing focus, Back, or the player leaves it for
## later). SLMatch.save_match(); LudoMatch.save_match() once its owner adds it (until then its per-turn _save()).
## Both skip a finished match, autoplay and previews.
func _flush_match() -> void:
	if is_instance_valid(_result):
		return                                   # the match is over: nothing to keep
	match screen:
		"sl":
			sl.save_match()
		"ludo":
			if ludo.has_method("save_match"):
				ludo.call("save_match")
			elif ludo.has_method("_save"):
				ludo.call("_save")

## Forgets the kept match (restart, game over).
func _clear_match() -> void:
	MatchStore.clear()


# ---------- input, back button, app lifecycle ----------

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		if screen == "ludo" and _top_sheet() == null and not is_instance_valid(_result):
			if ludo.tap(e.position):
				get_viewport().set_input_as_handled()
	elif e.is_action_pressed("ui_cancel"):
		_back()
		get_viewport().set_input_as_handled()

func _top_sheet() -> Sheet:
	return Sheet.top_sheet(sheet_layer)

func _back() -> void:
	if _splash != null:
		return
	if Info.close():                         # Back closes an open ⓘ bubble first
		return
	if EmotePicker.close_open():             # then an open emote picker
		return
	if Sheet.back(sheet_layer):
		return
	if is_instance_valid(_result) and not _result.is_queued_for_deletion():
		_result.on_back()                    # Home
		return
	match screen:
		"ludo", "sl":
			open_pause()
		"home":
			_confirm_quit()
		"welcome":                           # nothing to confirm before the first screen is passed
			Save.flush()
			get_tree().quit()

func _confirm_quit() -> void:
	if await Sheet.confirm(self, tr("Quit Ludo Zing?"), tr("Your progress is saved."), tr("Quit"), tr("Stay"), true):
		notifications.schedule_now()
		Save.flush()
		crash_watch.mark_ended("quit")
		get_tree().quit()

## What CrashWatch records with each sample: the screen and, in a game, {game, mode, minutes, resumed}. mode: cpu |
## local (Pass & Play) | tutorial | friends (a friend room) | quick:<table> (quick match: practice, t100 ...).
func diag_context() -> Dictionary:
	var m := {}
	if screen in ["ludo", "sl"]:
		var mode := ""
		if _online_match():
			mode = ("quick:" + str(online.quick_cfg.get("table", "practice"))) if online.in_quick() else "friends"
		elif screen == "ludo" and bool(last_ludo.get("tutorial", false)):
			mode = "tutorial"
		else:
			var lp: Variant = Save.prefs.get("last_played")
			mode = str((lp as Dictionary).get("mode", "")) if lp is Dictionary else ""
		m = {game = screen, mode = mode, minutes = snappedf((Time.get_ticks_msec() - _match_ms) / 60000.0, 0.1),
			resumed = _resumed}
	return {screen = screen, match = m, paused = paused}

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_GO_BACK_REQUEST:
			_flush_match()
			_back()
		NOTIFICATION_WM_CLOSE_REQUEST:
			_flush_match()
			Save.flush()
			get_tree().quit()
		NOTIFICATION_APPLICATION_PAUSED:
			_flush_match()
			Save.flush()
			Sound.set_app_paused(true)
			if screen in ["ludo", "sl"] and not _online_match():
				open_pause()                        # (online the game goes on: coming back goes straight to the board)
		NOTIFICATION_APPLICATION_RESUMED:
			Sound.set_app_paused(false)
			if _online_match():
				(ludo if screen == "ludo" else sl).app_resumed()   # back in the app: the seat is yours again
		NOTIFICATION_APPLICATION_FOCUS_IN:
			_app_focused = true
		NOTIFICATION_APPLICATION_FOCUS_OUT:      # a call, the notification shade, the app switcher: keep the match
			_app_focused = false
			_flush_match()
