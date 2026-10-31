class_name LudoMatch
extends Node
## Runs one Ludo game: feeds dice rolls and taps to LudoRules, animates the events on the board, plays the
## computer players and writes the event line (index.html: beginTurn, roll, move, gameOver).
## All waits count only unpaused time, so computer turns hold while the pause menu is open (and while the tutorial
## holds a note).
##
## Pace (× the speed pref; a tap during a computer's turn fast-forwards ×FF until your next turn):
##   computer roll wait 0.35 s, computer move wait 0.25 s, your auto-move 0.15 s, pawn step 0.11 s (0.22 s out of
##   the base), pause after a turn 0.3 s (0.5 s before an extra turn), "no move" / three 6s hold 0.9 s.
## Moves (Decision 3): every legal unit glows; a tap on any glowing pawn moves its unit (a paired pawn moves the
## pair). Pairs form by themselves; with the house rule "Ask before pairing" an inline prompt asks (your turn only).
## The match is saved after every turn (MatchStore) and can be resumed (resume()); save_match() saves it now.
## The guided first match (Tutorial): start_tutorial(), or start(..., {tutorial = true}); it feeds the dice and
## narrows the moves through the hooks below (tut.*) and is never saved. While it runs the HUD is in its tutorial
## mode (a quiet event line: the coach bubble is the one voice) and the game waits while a coach note is held or the
## skip question is open (tut.holding()).
##
## Online (friend rooms, server/PROTOCOL.md): start_online(start_or_sync, net). The server is authoritative and
## this match is a replica: your dice tap sends `roll`, a pawn tap `move`, the pair prompt `pair` (nothing is
## applied locally); every `act` from the server (yours, a friend's, a bot's) is queued (NetLudo) and played in
## order through the same path as offline play (the dice tumble, then LudoRules.apply_roll / move / answer_pair,
## then _after_roll / _after_move animate the events), faster while acts are waiting. After each act the state
## hash is checked; a mismatch (or a gap) sends sync_req and the `sync` replaces the state and re-lays the board.
## No local AI or dice, no pause (the server keeps time), no MatchStore save; the HUD shows the server's turn timer,
## offline / bot badges, "Reconnecting…" and, when a bot took your seat, the "I’m back" prompt.
##
## Re-roll (server/ECONOMY_V1.md section 4, RerollFlow): after your bad roll `reroll_offer` shows the HUD's "Roll again"
## (3 s ring, "Free" or the gem price; a tap sends {t: "reroll", n}, then a spinner until `rerolled` or an error);
## `hold {c, until}` keeps the next player's dice asleep until `until` ("Rahim may roll again…"; a roll the server
## refused with `error hold` is sent again at `until`); `rerolled` toasts "<name> rolled again" for everyone. The `sync`
## that follows (the state before the bad roll) replaces the board at once, even while the bad roll's dice or turn
## animation is still running (net_push drops the acts waiting before it, ends the old animation and re-lays the
## board); then the new roll's `act` animates as usual.
##
## Play on (LudoRules header): when a side finishes and the game goes on, its place pops over the centre ("Red
## finished 1st!" / "You finished 1st!"), its tile shows the place badge and dims, its pawns stay home and the turn
## order skips it (the rules do; computers and timers only ever see the next unfinished side). Your own finish online:
## the FinishCard (Keep watching / Home = leave the room; the server still grants your place at the end). The result
## screen at the end shows the full standings; rewards follow your place (1st = the win reward). The server's
## {k: "end"} act (online: only ghosts / leavers left to finish) ends the game the same way.
##
## Emotes (server/EMOTES.md, the HUD's EmotePicker / EmoteLayer): the sender is the only human vs the computer, the
## player to move in Pass & Play (whoever holds the phone) and your seat online. A pick shows at once on the sender's
## seat; online it also goes to the server ({t: "emote", id}) and the others' arrive through net_emote ({t: "emote",
## c, id}; quick-match ghosts' too). Offline the computers react now and then to captures, finishes and the end
## (EmoteLayer.react_*, throttled). Purely visual: no state, rule, turn or hash is touched.

signal finished(result: Dictionary)
## result (ResultScreen-ready): {game "ludo", title, sub, standings [{color, name, kind "you"|"cpu"|"human", cpu_id,
##   place, finished, progress}], human_won, reward, teams, color (the winner), winners, xp_before, xp_after}

const CPU_ROLL_WAIT := 0.35
const BACK_WINDOW_MS := 30_000            # app_resumed(): how long a bot on your seat is still "you were away"
const CPU_MOVE_WAIT := 0.25
const AUTO_MOVE_WAIT := 0.15
const AFTER_TURN := 0.3
const AFTER_EXTRA := 0.5
const HOLD := 0.9                         # "no move" / three 6s / need a 6
const FF := 0.35                          # fast-forward factor after a tap during a computer's turn
const DICE_SEC := 0.75                    # Dice3D.roll's length at speed 1
const HIT_STOP := 0.08                    # s of stillness when a capture lands (real time)
const SHAKE_PX := 5.0
const ELEVATION := 70.0                   # 3D view camera elevation (degrees; TableWorld's default is 62)
const BOARD_GUTTER := 4.0                 # px kept free at the screen sides in the 3D view (by the coloured
const BOARD_FIT := 8.0                    # board's corners: half side 7.5 plus a little of the frame, 8.4)

var app: Node                            # main.gd: sheet layer, paused flag, speed
var board: LudoBoard
var world: TableWorld
var hud: LudoHUD
var S := {}
var players := []
var teams := false
var opts := {}                           # {bot_level, pair_ask}
var _id := 0
var _busy := false                       # an animation or prompt is running: ignore taps and dice
var rng := RandomNumberGenerator.new()
var autoplay := false                   # debug builds only (user://autoplay.txt): humans play like computers
var save_matches := true                 # MatchStore after every turn (off for autoplay / previews)
var _ff := 1.0
var _view := {on = false, zoom = 1.0, y = 0.0}   # the 3D view framing for this screen size
var _view_key := ""
var _shake_tw: Tween
var tut: Tutorial                        # the guided first match while it runs (null otherwise)
# online (start_online)
const NET_CATCHUP := 0.45                 # pace while server acts are queued behind the one playing
const NET_XP_WIN := 100                   # online XP (NetReplica.ONLINE_REWARDS: the server grants coins + XP)
const NET_XP_PLAY := 40
var online := false
var net: Object                           # NetClient (anything with send_msg(Dictionary) -> bool)
var ns: NetLudo
var _net_pumping := false
var _net_info := {}                       # the move's info, kept for the pair answer that follows it
var _net_sent := -1                       # n of our last request (one request per step: no double taps)
var _net_prompt := -1                     # n the pair prompt was opened at (-1: none)
var _ended := false
var _net_ready := false                   # the board is up: queued acts may play
var _net_turn := {}                       # the server's last `turn` {c, end (ticks ms), total}: shown once the acts before it played
var _my_place := 0                        # play on: the place your side finished in while the game went on (0: not yet)
var _my_away := false                     # online: a bot was playing your seat when your side finished
var _back_until := 0                      # online: back in the app until then (ticks ms): a bot on your seat is sent away
var rr := RerollFlow.new()                # online: the re-roll offer and hold
var _rr_wait := false                     # online: a re-roll was paid: the dice sleep until the new roll's act
var aborts := 0                           # online: animations ended by a mid-turn `sync` (tests, debugging)
var _over_msg := {}                       # online: the server's `over` (match_id, the coin table's payouts)

## Old callers (device tests): true when tap points are printed. Use TapLog.enabled().
static func tap_log() -> bool:
	return TapLog.enabled()

func _init(app_: Node, world_: TableWorld, hud_: LudoHUD) -> void:
	app = app_
	world = world_
	board = world_.board
	hud = hud_

func _ready() -> void:
	rng.randomize()
	hud.dice_pressed.connect(_on_dice)
	if hud.has_signal("away_pressed"):
		hud.away_pressed.connect(_net_back)
	if hud.has_signal("reroll_pressed"):
		hud.reroll_pressed.connect(_net_reroll_tap)
	if hud.has_signal("finish_home_pressed"):
		hud.finish_home_pressed.connect(_finish_home)
	if hud.get("emote_picker") != null:
		hud.emote_picker.picked.connect(_emote_send)
		hud.emote_picker.guard = func() -> bool: return app.paused or _sheet_open()
		hud.emotes.is_cpu_fn = func(c: int) -> bool: return not online and not S.is_empty() and S.players[c] == "cpu"
		hud.emotes.is_human_fn = func(c: int) -> bool: return not S.is_empty() and S.players[c] == "human"

## A dice tap counts only on a human's turn, while nothing is animating and no sheet is open.
func _on_dice() -> void:
	if S.is_empty() or S.phase != "roll" or _busy or autoplay or app.paused or _sheet_open():
		return
	if not LudoRules.is_human(S, S.turn) or (online and not ns.my_turn()):
		return
	if online and (rr.holds(ns.me) or _rr_wait):
		return                               # the last player may still roll again: the dice wait for the hold
	roll()

## Colour c is you (online: your seat; offline: the only human at the table).
func _you(c: int) -> bool:
	return NetLudo.you(S, c)

## Loud sounds and haptics for this colour's actions (offline: humans; online: you).
func _loud(c: int) -> bool:
	return c == ns.me if online else LudoRules.is_human(S, c)

func _sheet_open() -> bool:
	return app.has_method("_top_sheet") and app._top_sheet() != null

func live(id: int) -> bool:
	return id == _id and not S.is_empty() and is_inside_tree()

func _speed() -> float:
	return float(app.speed) * _ff

## Seconds of unpaused time, scaled by the game speed (and the fast-forward).
func wait(sec: float) -> void:
	var left: float = sec * _speed()
	while left > 0.0 and is_inside_tree():
		await get_tree().process_frame
		if (online or not app.paused) and not _held():   # online the server keeps time: no pause
			left -= get_process_delta_time()

## The board walk's hold (offline: the pause menu holds pawns mid-walk).
func _holding() -> bool:
	return app.paused and not online

## The tutorial holds the game (a coach note to read, the skip question).
func _held() -> bool:
	return tut != null and is_instance_valid(tut) and tut.holding()

## A new game. opts: {bot_level ("easy" | "normal" | "hard"), pair_ask} (default: the Settings prefs);
## {tutorial = true (, then = "cpu" | "local")}: the guided first match instead (start_tutorial).
func start(players_: Array, teams_ := false, opts_ := {}) -> void:
	if bool(opts_.get("tutorial", false)):
		await start_tutorial(str(opts_.get("then", "cpu")))
		return
	_end_tutorial()
	_offline()
	hud.tutorial = false
	opts = {
		bot_level = str(opts_.get("bot_level", Save.prefs.get("bot_level", "normal"))),
		pair_ask = bool(opts_.get("pair_ask", Save.prefs.get("pair_ask", true))),
	}
	players = players_.duplicate()
	var s := LudoRules.new_game(players, teams_, {pair_ask = opts.pair_ask})
	var nm: Variant = opts_.get("names")                 # Pass & Play: the names typed in setup, by colour
	if nm is Array and (nm as Array).size() == 4 and players.count("human") > 1:
		for c in 4:
			if players[c] == "human" and str(nm[c]) != "":
				s.names[c] = str(nm[c])
	await _open(s, true)

## The guided first match (Tutorial): you vs one Easy computer on a staged board with scripted dice and coach
## marks. `then`: where "Play a real game" leads afterwards ("cpu": a game vs the computer; "local": the Pass &
## Play setup).
func start_tutorial(then := "cpu") -> void:
	_end_tutorial()
	_offline()
	opts = {bot_level = "easy", pair_ask = false, then = then}
	players = Tutorial.PLAYERS.duplicate()
	hud.tutorial = true
	tut = Tutorial.new(self)
	add_child(tut)
	tut.attach(hud)
	await _open(Tutorial.new_state(), true)

## The tutorial's way out: "play" (a real game) or "home". Uses main's start_ludo / setup / go_home when there.
func tutorial_exit(what: String) -> void:
	var then := str(opts.get("then", "cpu"))
	_end_tutorial()
	if what == "home":
		if app.has_method("go_home"):
			app.go_home()
		else:
			stop()
		return
	if then == "local" and app.has_method("_open_setup"):
		if app.has_method("go_home"):
			app.go_home()
		app.call("_open_setup", "ludo", "local")
		return
	var cfg := {game = "ludo", players = ["human", "cpu", "cpu", "cpu"], teams = false,
		bot_level = str(Save.prefs.get("bot_level", "normal"))}
	if app.has_method("setup_config"):
		var all: Variant = Save.prefs.get("last_setup", {})
		var per: Variant = (all as Dictionary).get("ludo", {}) if all is Dictionary else {}
		var d: Variant = (per as Dictionary).get("cpu", {}) if per is Dictionary else {}
		cfg = app.call("setup_config", "ludo", "cpu", d if d is Dictionary else {})
	if app.has_method("start_ludo"):
		app.call("start_ludo", cfg)
	else:
		stop()
		start(cfg.players, bool(cfg.teams), {bot_level = cfg.bot_level})

func _end_tutorial() -> void:
	if tut:
		tut.cancel()
		tut.queue_free()
	tut = null
	if hud:
		hud.tutorial = false
		hud.coach = null

## Continues a saved match (MatchStore.load()): {S, players, teams, opts}, or a bare rules state.
func resume(state: Dictionary) -> void:
	_end_tutorial()
	_offline()
	hud.tutorial = false
	var s: Dictionary = state.get("S", state)
	if s.is_empty() or not s.has("tok") or s.get("phase", "") == "over":
		MatchStore.clear("ludo")
		return
	s = MatchStore.ints(s)
	players = state.get("players", s.players).duplicate()
	var o: Dictionary = state.get("opts", {})
	opts = {bot_level = str(o.get("bot_level", Save.prefs.get("bot_level", "normal"))), pair_ask = bool(s.get("pair_ask", false))}
	if not s.has("finished"):
		s.finished = []
	await _open(s, false)

func _open(s: Dictionary, fresh: bool) -> void:
	_id += 1
	var id := _id
	_net_prompt = -1
	hud.cancel_pair()
	S = s
	teams = S.teams
	_ff = 1.0
	_ended = false
	_my_place = LudoHUD.done_place(S, ns.me) if online and ns != null and ns.me >= 0 else 0
	_my_away = false
	_busy = true                             # nothing is tappable until the first turn begins
	board.cancel_all()
	board.speed = _speed()
	board.set_movable([])
	board.relayout(S)
	hud.setup(S)
	_emote_sync()
	hud.dice.set_active(false)
	_view_key = ""
	_frame_view(true)
	world.view_game(S.view, Save.prefs.cam == "top")
	_apply_view()
	if S.teams and fresh:
		hud.say(tr("Teams: Red + Yellow vs Green + Blue"), 2.2, "info")
		await wait(1.0)
		if not live(id):
			return
	if online:
		_net_open(id)
		return
	match str(S.phase):
		"choose", "pick":                    # (matches are saved at the start of a turn; older states may differ)
			S.phase = "choose"
			S.pick = ""
			_busy = false
			hud.update(S, S.turn)
			await _choose(id, S.turn)
		"pair_ask":                          # the move is kept; the pawns stay single
			await _after_move(id, S.turn, LudoRules.answer_pair(S, false), {})
		_:
			S.phase = "roll"
			_begin_turn()

## Leaving the game (main: Home, a new game): the saved match goes too.
func stop() -> void:
	if not S.is_empty() and tut == null and not online:
		MatchStore.clear("ludo")
	_end_tutorial()
	_offline()
	_id += 1
	S = {}
	_busy = false
	_ff = 1.0
	hud.cancel_pair()
	board.cancel_all()
	board.set_movable([])
	_emote_sync()
	if hud.get("emotes") != null:
		hud.emotes.clear()

# ---------- the 3D view framing ----------

## The 3D view (not Top View): a more top-down camera (ELEVATION) with the board's corners BOARD_GUTTER px from
## the screen sides, centred in the band between the tile rows and clear of the tiles. Applied every frame, so it
## also holds when Settings switches the camera back from Top View.
func _process(_d: float) -> void:
	if S.is_empty():
		return
	_frame_view(false)
	_apply_view()

func _apply_view() -> void:
	if not _view.on or Save.prefs.cam == "top" or world.orbit:
		return
	world.cam_target_el = deg_to_rad(ELEVATION)
	world.cam_target_zoom = _view.zoom
	world.view_target_y = _view.y

func _frame_view(force: bool) -> void:
	var vp := world.get_viewport().get_visible_rect().size
	var key := "%d:%d:%d:%d" % [int(vp.x), int(vp.y), int(hud.safe_top), int(S.get("view", 0))]
	if key == _view_key and not force:
		return
	_view_key = key
	var band := hud.board_band()
	world.top_band = band.size.y
	if band.size.y <= 0:
		_view.on = false
		return
	var cam := world.camera
	var saved := [world.cam_az, world.cam_el, world.cam_zoom, world.cam_roll, world.view_y]
	var seat := TableWorld.seat_az(int(S.view))
	world.cam_az = seat
	world.cam_el = deg_to_rad(ELEVATION)
	world.cam_roll = 0.0
	var rects: Array = hud.tile_rects()
	var fits := func(zoom: float) -> Array:   # [fits, view_y]
		world.cam_zoom = zoom
		world.view_y = 0.0
		world._update_camera(true)
		var bb := _board_box(cam)
		var c := Vector3(0, LudoBoard.TOP, 0)
		var ppu := (cam.unproject_position(c) - cam.unproject_position(c + cam.global_transform.basis.y)).length()
		var vy := ((band.position.y + band.size.y / 2.0) - bb.get_center().y) / maxf(ppu, 0.001)
		world.view_y = vy
		world._update_camera(true)
		bb = _board_box(cam)
		var ok := bb.position.x >= BOARD_GUTTER and bb.end.x <= vp.x - BOARD_GUTTER and bb.size.y <= band.size.y + 60.0
		if ok:
			for p in _board_outline(cam):
				for r: Rect2 in rects:
					if r.has_point(p):
						ok = false
		return [ok, vy]
	var lo := 0.6
	var hi := 2.2
	for it in 22:
		var mid := (lo + hi) / 2.0
		if fits.call(mid)[0]:
			hi = mid
		else:
			lo = mid
	var res: Array = fits.call(hi)
	_view = {on = true, zoom = hi, y = res[1]}
	world.cam_az = saved[0]; world.cam_el = saved[1]; world.cam_zoom = saved[2]; world.cam_roll = saved[3]; world.view_y = saved[4]
	world._update_camera(true)

## Screen box of the board (half side BOARD_FIT) as the camera sees it now.
func _board_box(cam: Camera3D) -> Rect2:
	var r := Rect2()
	var pts := _board_outline(cam)
	for k in pts.size():
		r = Rect2(pts[k], Vector2.ZERO) if k == 0 else r.expand(pts[k])
	return r

func _board_outline(cam: Camera3D) -> Array:
	var out := []
	var h := BOARD_FIT
	var corners := [Vector3(-h, 0, -h), Vector3(h, 0, -h), Vector3(h, 0, h), Vector3(-h, 0, h)]
	for k in 4:
		var a: Vector3 = corners[k]
		var b: Vector3 = corners[(k + 1) % 4]
		for j in 12:
			out.append(cam.unproject_position(a.lerp(b, j / 12.0) + Vector3(0, LudoBoard.TOP, 0)))
	return out

# ---------- turns ----------

## A turn this device plays by itself (a computer, or autoplay). Never online: the server plays bots.
func _cpu_turn(c: int) -> bool:
	if online:
		return false
	return not LudoRules.is_human(S, c) or autoplay

## The idle line for the current phase, so the bar never shows stale text.
func _idle_line() -> void:
	if S.is_empty() or S.phase == "over":
		return
	var c: int = S.turn
	if online and not ns.my_turn():
		hud.idle(_net_wait_line(c))
		return
	if _cpu_turn(c) and not autoplay:
		hud.idle(tr("[b]%s[/b] is thinking…") % _pn(c))
		return
	var you := _you(c)
	match str(S.phase):
		"roll":
			if LudoRules.waiting_six(S, c):
				if you:
					hud.idle(tr("Roll a 6 to help %s") % _name_of(LudoRules.mate_of(c)))
				else:
					hud.idle(tr("[b]%s[/b]: roll a 6 to help %s") % [_pn(c), _name_of(LudoRules.mate_of(c))])
			elif you:
				hud.idle(tr("Your turn — tap the dice"))
			else:
				hud.idle(tr("[b]%s[/b]’s turn — tap the dice") % _pn(c))
		"choose":
			hud.idle(tr("Tap a glowing pawn"))
		"pair_ask":
			hud.idle("")                     # the inline prompt asks the question itself
		_:
			hud.idle("")

func _name_of(c: int) -> String:
	return GameTopBar.who(LudoRules.pname(S, c), c)

## Colour c's name as shown ("You" / a colour in the interface language, a bot's or player's own name as it is).
func _pn(c: int) -> String:
	return L10n.seat_name(LudoRules.pname(S, c))

## The place word: 1st / 2nd / 3rd / 4th in the interface language.
static func _place(n: int) -> String:
	match n:
		1: return L10n.t("1st")
		2: return L10n.t("2nd")
		3: return L10n.t("3rd")
		4: return L10n.t("4th")
	return ResultScreen.ordinal(n)

## "Red + Yellow" / "Green + Blue" (the colours in the interface language).
static func _team_label(c: int) -> String:
	var m := LudoRules.mate_of(c)
	return "%s + %s" % [L10n.seat_name(LudoRules.COLOR_NAMES[mini(c, m)]), L10n.seat_name(LudoRules.COLOR_NAMES[maxi(c, m)])]

## A stuck reason from the rules (English, also sent by the server) in the interface language.
static func _reason_text(r: String) -> String:
	if not L10n.is_bn():
		return r                              # the rules' own English
	if r == "No move. Roll again.":
		return L10n.t("No move. Roll again.")
	if r == "No move this time.":
		return L10n.t("No move this time.")
	if r == "A pair needs an even roll.":
		return L10n.t("A pair needs an even roll.")
	var tail := ""
	var base := r
	if base.ends_with(" Roll again."):
		base = base.trim_suffix(" Roll again.")
		tail = " " + L10n.t("Roll again.")
	if base == "Blocked by your pair.":
		return L10n.t("Blocked by your pair.") + tail
	if base.begins_with("Blocked by ") and base.ends_with("'s pair."):
		var who := base.trim_prefix("Blocked by ").trim_suffix("'s pair.")
		return L10n.t("Blocked by %s’s pair.") % L10n.seat_name(who) + tail
	return r

func _begin_turn() -> void:
	var id := _id
	var c: int = S.turn
	_busy = false
	if LudoRules.is_human(S, c) and not autoplay and not online:
		_ff = 1.0                            # your turn: back to the normal pace
	board.speed = _speed()
	board.set_movable([])
	hud.update(S, c)
	_idle_line()
	_emote_sync()
	if online:
		return                               # the server says who rolls; nothing is played here
	_save()
	if tut and tut.on_turn(c):
		return                               # the tutorial's closing card holds the turn
	if _cpu_turn(c):
		await wait(CPU_ROLL_WAIT)
		if live(id) and S.phase == "roll":
			roll()

## Roll the dice for the player whose turn it is (the human's dice tap, or a computer turn).
func roll(forced := 0) -> void:
	if S.is_empty() or S.phase != "roll" or _busy or app.paused:
		return
	if online:
		_net_request("roll")                 # the server rolls; its act plays the dice (_net_act)
		return
	var id := _id
	var c: int = S.turn
	_busy = true
	hud.dice.set_active(false)
	if forced <= 0 and tut:
		forced = tut.roll_for(c)
		tut.on_rolled(c)
	var v := forced if forced > 0 else rng.randi_range(1, 6)
	await _tumble(c, v)
	if not live(id):
		return
	var ev := LudoRules.apply_roll(S, v)
	await _after_roll(id, c, v, ev)   # stays busy until the next turn begins or a human has to choose

## The dice tumble to v for colour c (sound, a haptic on loud rolls).
func _tumble(c: int, v: int) -> void:
	var soft := not _loud(c)
	var k := _speed()
	var dur := DICE_SEC * maxf(k, 0.05)
	Sound.sfx("roll", {dur = dur, soft = soft})
	if not soft:
		get_tree().create_timer(dur * Sound.IMPACT_AT).timeout.connect(func(): Haptics.light())
	await hud.dice.roll(v, k)

func _after_roll(id: int, c: int, v: int, ev: Array) -> void:
	var soft := not _loud(c)
	var you := _you(c)
	var who := "[b]%s[/b]" % _pn(c)
	for e in ev:
		match e.type:
			"three_sixes":
				Sound.sfx("error", {soft = soft})
				if _loud(c):
					Haptics.error()
				hud.say(tr("You rolled three 6s. Turn lost.") if you else tr("%s rolled three 6s. Turn lost.") % who, HOLD * 2.0, "event")
				await wait(HOLD)
			"need_six":
				hud.say((tr("You need a 6 to help %s.") % _name_of(LudoRules.mate_of(c))) if you else (tr("%s needs a 6 to help %s.") % [who, _name_of(LudoRules.mate_of(c))]), HOLD * 2.0)
				await wait(HOLD)
			"free_hand":
				print("[ludo] free hand: %s now moves %s" % [LudoRules.pname(S, c), LudoRules.pname(S, e.mate)])
				Sound.sfx("six", {soft = soft})
				hud.say((tr("Six! You now move %s.") % _name_of(e.mate)) if you else (tr("Six! %s now moves %s.") % [who, _name_of(e.mate)]), 2.0, "event")
			"stuck":
				hud.say((tr("You rolled %d. %s") % [v, _reason_text(e.reason)]) if you else (tr("%s rolled %d. %s") % [who, v, _reason_text(e.reason)]), HOLD * 2.0)
				await wait(HOLD)
			"turn":
				if live(id):
					_begin_turn()
				return
			"pick", "choose":
				if v == 6:
					Sound.sfx("six", {soft = soft})
				await _choose(id, c)
				return
		if not live(id):
			return

## Phase "choose": computers pick a move; for you every legal unit glows (or the only sensible move goes by itself).
func _choose(id: int, c: int) -> void:
	var mc := LudoRules.mover_of(S, c)
	_busy = false                            # move() takes over; dice taps stay ignored (phase "choose")
	if _cpu_turn(c):
		_idle_line()
		await wait(CPU_MOVE_WAIT)
		if live(id) and S.phase == "choose":
			await move(LudoRules.pick_ai(S, LudoRules.units(S).map(func(u): return u.token), rng, opts.get("bot_level", "normal") if not LudoRules.is_human(S, c) else "normal"))
		return
	if online and not ns.my_turn():
		_idle_line()                         # someone else chooses: their move comes from the server
		return
	var only: Array = tut.allowed(c) if tut else []
	if not only.is_empty():                  # the tutorial: just the lesson's pawn glows (no auto-move)
		board.set_movable(only.map(func(j): return mc * 4 + j), mc)
		_idle_line()
		return
	var auto := LudoRules.auto_move_token(S)
	if auto >= 0:
		await wait(AUTO_MOVE_WAIT)
		if live(id) and S.phase == "choose":
			await move(auto)
		return
	var keys := []
	for u in LudoRules.units(S):
		for j in u.tokens:
			keys.append(mc * 4 + j)
	board.set_movable(keys, mc)
	_idle_line()
	if TapLog.enabled():                     # device tests: where to tap, in screen pixels
		for key in keys:
			TapLog.point(board.pawn_target(key), world.camera)

## The human answered the old Single / Pair question (legacy; the step no longer appears).
func choose_pick(kind: String) -> void:
	if S.is_empty() or _busy or app.paused or not LudoRules.choose_pick(S, kind):
		return
	await _choose(_id, S.turn)

## A tap on the board: move the tapped glowing pawn's unit. During a computer's turn: fast-forward. A miss on your
## turn: "Tap a glowing pawn", an error buzz, and the glowing pawns pulse once.
func tap(screen_pos: Vector2) -> bool:
	if S.is_empty() or app.paused or _sheet_open() or S.phase == "over":
		return false
	if online and (not ns.my_turn() or _net_sent == ns.n):
		return false                         # not your move (or already sent): nothing to fast-forward online
	if _cpu_turn(S.turn) and not autoplay:
		if _ff > FF:
			_ff = FF
			board.speed = _speed()
		return true
	if S.phase != "choose" or _busy or autoplay:
		return false
	var mc := LudoRules.mover_of(S, S.turn)
	var key := board.pick(world.camera, screen_pos)
	if key >= 0 and key / 4 == mc and board.movable.has(key):
		var u := LudoRules.unit_for_token(S, key % 4)
		if not u.is_empty():
			move(int(u.token))
			return true
	var own := board.pick_any(world.camera, screen_pos, mc)
	if own >= 0:
		hud.say(tr("That pawn can’t move with a %d.") % int(S.dice), 1.4)
	else:
		hud.say(tr("Tap a glowing pawn"), 1.2)
	Haptics.error()
	Sound.sfx("tap")
	board.pulse_movable()
	return true

## Move token i of the player whose pawns the roll moves; animates every event the rules return.
func move(i: int) -> void:
	if S.is_empty() or _busy or i < 0:
		return
	if online:
		if ns.my_turn() and S.phase == "choose":
			board.set_movable([])
			_net_request("move", {i = i})    # the server's act moves the pawn (_net_act)
		return
	var id := _id
	var roller: int = S.turn
	var ev := LudoRules.move(S, i)
	if ev.is_empty():
		return
	if tut:
		tut.on_moved(roller)
	_busy = true
	board.set_movable([])
	await _after_move(id, roller, ev, {})

func _after_move(id: int, roller: int, ev: Array, info: Dictionary) -> void:
	_busy = true
	var soft := not _loud(roller)
	var you := _you(roller)
	var human := _loud(roller)
	var k := 0
	while k < ev.size():
		var e: Dictionary = ev[k]
		k += 1
		match e.type:
			"move":
				info.to = e.to
				info.pair = e.pair
				info.c = e.c
				board.speed = _speed()
				await board.walk(e.c, e.tokens, e.from, e.to, e.pair, func(_q): Sound.sfx("step", {soft = soft}), _holding)
			"capture":
				info.victims = e.victims
				await _capture(e.c, e.victims, soft, roller)
			"split":
				info.split = "lane" if e.where == "lane" else "start"
				Sound.sfx("split", {soft = soft})
			"pair_offer":
				board.relayout(S)
				hud.update(S, roller)
				_idle_line()
				if online:                   # the answer is a request; the server's `pair` act plays it
					_busy = false
					if ns.my_turn():
						_net_pair_prompt()
					return
				var yes := await _ask_pair()
				if not live(id):
					return
				ev.append_array(LudoRules.answer_pair(S, yes))
			"pair_formed":
				print("[ludo] pair formed: %s" % LudoRules.pname(S, e.c))
				info.paired = true
				Sound.sfx("pair", {soft = soft})
				board.relayout(S)
				board.link_glow(LudoBoard.to_world(LudoBoard.grid_of(e.c, S.tok[e.c][e.a], e.a)))
				if human:
					Haptics.light()
				if e.human and tut == null and (not online or roller == ns.me):
					Save.profile.stats.pairsFormed += 1
					Save.save()
				if tut:
					tut.on_event(e)
			"home":
				info.home = true
				Sound.sfx("home", {soft = soft})
				var at := LudoBoard.to_world(LudoBoard.grid_of(e.c, LudoRules.GOAL, 0))
				board.home_burst(at, Palette.PLAYER[e.c])
				if not ev.slice(k).any(func(x): return x.type == "finished"):   # (a side's last pawn: its place pops instead)
					hud.pop(tr("Home!"), _screen(at + Vector3(0, 1.2, 0)), Palette.HONEY, 30, true)
				hud.update(S, roller)
				hud.bump_tile(e.c)
				if human:
					Haptics.success()
			"all_home":
				info.finished = e.c              # Teams: four home, the partner still playing (Free Hand)
			"finished":
				info.done = e                    # play on: this side has its place
				await _side_finished(e, roller, ev.slice(k).any(func(x): return x.type == "game_over"))
			"game_over":
				board.relayout(S)
				hud.update(S, S.winner)
				_busy = false
				_game_over()
				return
			"turn":
				board.relayout(S)
				var extra: bool = e.again
				_turn_message(roller, info, extra)
				await wait(AFTER_EXTRA if extra else AFTER_TURN)
				if live(id):
					_begin_turn()
				return
		if not live(id):
			return
	_busy = false

## Play on: a side just finished ({c, place, team?}). Its tile gets the place badge (hud.update); while the game
## goes on its place pops over the centre, and your own side's finish gets a small celebration and, online, the
## FinishCard (Pass & Play has no "you": every finish just pops). ending: this move ends the game (the result says it).
func _side_finished(e: Dictionary, roller: int, ending: bool) -> void:
	var c := int(e.c)
	var place := int(e.place)
	var team: bool = e.has("team")
	var mine := (e.get("team", [c]) as Array).any(func(x): return _you(int(x)))
	if mine:
		_my_place = place
		_my_away = online and ns.me >= 0 and S.players[ns.me] == "cpu"
	hud.update(S, roller)
	var text := _finish_text(e, false, false)
	print("[ludo] %s%s" % ["%s finished %s!" % [_finish_who(e, false), ResultScreen.ordinal(place)], " (game over)" if ending else ""])
	if ending:
		return
	var at := LudoBoard.to_world(LudoBoard.grid_of(c, LudoRules.GOAL, 0))
	hud.pop(text, _screen(at + Vector3(0, 1.6, 0)), Palette.GOLD_HI if place == 1 else Palette.HONEY, 30, true)
	if not online and tut == null and hud.get("emotes") != null:
		hud.emotes.react_finish(c)
	Sound.sfx("win", {soft = not mine})
	if mine:
		Haptics.success()
		Celebrate.run(hud, "burst", 0.45)
		if online:
			hud.show_finish(place, team)
	await wait(0.6)

## Who finished, for the pop / the event line: "You" / "Your team", else the name ("Mocha", "Red") or the team
## ("Team Red + Yellow"); bold = the event line's bold name.
## "<who> finished <place>!" (tail: " The others play on." too) in the interface language.
func _finish_text(e: Dictionary, bold: bool, tail: bool) -> String:
	var c := int(e.c)
	var pl := _place(int(e.place))
	if (e.get("team", [c]) as Array).any(func(x): return _you(int(x))):
		if e.has("team"):
			return (tr("Your team finished %s! The others play on.") if tail else tr("Your team finished %s!")) % pl
		return (tr("You finished %s! The others play on.") if tail else tr("You finished %s!")) % pl
	var nm := (tr("Team %s") % _team_label(c)) if e.has("team") else _pn(c)
	if bold:
		nm = "[b]%s[/b]" % nm
	return (tr("%s finished %s! The others play on.") if tail else tr("%s finished %s!")) % [nm, pl]

func _finish_who(e: Dictionary, bold: bool) -> String:
	var c := int(e.c)
	if (e.get("team", [c]) as Array).any(func(x): return _you(int(x))):
		return "Your team" if e.has("team") else "You"
	var nm := ("Team " + LudoRules.team_label(S, c)) if e.has("team") else LudoRules.pname(S, c)
	return "[b]%s[/b]" % nm if bold else nm

## The finish card's Home: online, leave the room (your place is granted at the end); offline it isn't offered.
func _finish_home() -> void:
	if online and app.has_method("leave_online_match"):
		app.call("leave_online_match")

## The capture moment: hit-stop, a puff of the victim's colour, a small shake, the victim arcs home, "+1 roll".
func _capture(c: int, victims: Array, soft: bool, roller: int) -> void:
	var id := _id
	var at: Vector3 = board.toks[victims[0][0]][victims[0][1]].node.position
	await get_tree().create_timer(HIT_STOP).timeout        # hit-stop: real time, not scaled
	if not live(id):
		return
	Sound.sfx("capture", {soft = soft})
	var hit_you := victims.any(func(v): return _you(v[0]))
	if _loud(roller) or hit_you:
		Haptics.medium()
	_shake()
	hud.pop(tr("+1 roll"), _screen(at + Vector3(0, 1.3, 0)), Palette.HONEY, 28, true)
	if not online and tut == null and hud.get("emotes") != null:
		hud.emotes.react_capture(roller, victims.map(func(v): return int(v[0])))
	await board.send_home(victims)

func _shake() -> void:
	if PlayerTile._pref("reduce_motion"):
		return
	var cam := world.camera
	var c := Vector3(0, LudoBoard.TOP, 0)
	var ppu := (cam.unproject_position(c) - cam.unproject_position(c + cam.global_transform.basis.x)).length()
	var amp := SHAKE_PX / maxf(ppu, 0.001)
	if _shake_tw:
		_shake_tw.kill()
	_shake_tw = create_tween()
	_shake_tw.tween_method(func(k: float):
		cam.h_offset = sin(k * TAU * 4.0) * amp * (1.0 - k), 0.0, 1.0, 0.2)
	_shake_tw.tween_callback(func(): cam.h_offset = 0.0)

func _screen(p: Vector3) -> Vector2:
	return world.camera.unproject_position(p)

## One message for the whole move, readable until the next roll (CL-07).
func _turn_message(roller: int, info: Dictionary, extra: bool) -> void:
	var c: int = info.get("c", roller)
	var you := _you(roller)
	var who := "[b]%s[/b]" % _pn(roller)
	var again := (" " + tr("Roll again.")) if you or (LudoRules.is_human(S, roller) and not online) else ""
	var msg := ""
	var kind := "event"
	var victims: Array = info.get("victims", [])
	if victims.size() == 2:
		var vc: int = victims[0][0]
		if you:
			msg = tr("You broke a pair!") + again
		elif _you(vc):
			msg = tr("%s broke your pair!") % who
		else:
			msg = tr("%s broke %s’s pair!") % [who, _name_tinted(vc)]
	elif victims.size() == 1:
		var vc: int = victims[0][0]
		if you:
			msg = tr("You captured a pawn!") + again
		elif _you(vc):
			msg = tr("%s captured your pawn!") % who
		else:
			msg = tr("%s captured %s’s pawn!") % [who, _name_tinted(vc)]
	elif info.has("done"):
		var d: Dictionary = info.done            # play on: a side finished, the others go on
		msg = _finish_text(d, true, true)
	elif info.has("finished"):
		var f: int = info.finished
		if _you(f):
			msg = tr("All four home! Roll a 6 to help %s.") % _name_of(LudoRules.mate_of(f))
		else:
			msg = tr("%s is done! A 6 lets them help %s.") % [_name_of(f), _name_of(LudoRules.mate_of(f))]
	elif info.get("home", false):
		var pr: bool = info.get("pair", false)
		if you or again != "":
			msg = (tr("Pair home!") if pr else tr("Pawn home!")) + again
		else:
			msg = (tr("%s got a pair home!") if pr else tr("%s got a pawn home!")) % who
	elif info.get("paired", false):
		msg = (tr("You made a pair.") if you else tr("%s made a pair.") % who) + (again if extra else "")
		kind = "info"
	elif info.has("split"):
		var lane: bool = info.split == "lane"
		if _you(c):
			msg = tr("Your pair split in the home lane.") if lane else tr("Your pair split on the start square.")
		else:
			msg = (tr("[b]%s[/b]’s pair split in the home lane.") if lane else tr("[b]%s[/b]’s pair split on the start square.")) % _pn(c)
		msg += again if extra else ""
		kind = "info"
	elif extra:
		msg = tr("Six! Roll again.") if (you or (LudoRules.is_human(S, roller) and not online)) else tr("Six! %s rolls again.") % who
		hud.turn_pop(tr("+1 roll"), Palette.HONEY, 26)
	if msg != "":
		hud.say(msg, 2.2 if kind == "event" else 1.6, kind)

## The victim's name in its own colour (the "’s" follows in the message).
func _name_tinted(c: int) -> String:
	return "[b][color=#%s]%s[/color][/b]" % [PlayerTile.name_color(c).to_html(false), _pn(c)]

## House rule "Ask before pairing": the inline prompt (your own turn only). Autoplay answers at random.
func _ask_pair() -> bool:
	if autoplay:
		return rng.randf() < 0.6
	if TapLog.enabled():
		_log_pair_button.call_deferred()
	var yes := await hud.ask_pair()
	_idle_line()
	return yes

func _log_pair_button() -> void:
	await get_tree().process_frame
	if hud.pair_box.visible:
		TapLog.point(hud.pair_yes)

# ---------- saving ----------

## Saves the live match now (main: the app goes to the background). Never the tutorial.
func save_match() -> void:
	_save()

func _save() -> void:
	if not save_matches or autoplay or online or S.is_empty() or S.phase == "over" or tut != null:
		return
	MatchStore.save("ludo", {S = S, players = players, teams = teams, opts = opts}, _summary())

## "Ludo vs Computer · 35%" / "Ludo Teams (2 v 2) · 35%" / "Ludo Pass & Play".
func _summary() -> String:
	var mode := "Pass & Play" if not S.players.has("cpu") else ("Teams (2 v 2)" if S.teams else "vs Computer")
	var me: int = S.players.find("human")
	var t := "Ludo " + mode
	if S.players.has("cpu") and me >= 0:
		t += " · " + Fmt.pct(LudoRules.progress(S, me))
	return t

# ---------- the end ----------

func _game_over() -> void:
	if _ended:
		return
	_ended = true
	if online:
		await _net_game_over()
		return
	var id := _id
	MatchStore.clear("ludo")
	var winners := LudoRules.winners(S)
	if tut == null and hud.get("emotes") != null:
		hud.emotes.react_win(winners, [0, 1, 2, 3].filter(func(k): return LudoRules.active(S, k)))
	var human_won := winners.any(func(k): return LudoRules.is_human(S, k))
	var vs_cpu: bool = S.players.has("cpu")
	Sound.sfx("win" if human_won else "lose")
	var reward := LudoRules.win_reward(S)
	if reward <= 0:
		reward = LudoRules.play_reward(S)    # a finished game you lost vs the computer: a small participation reward
	var w: int = S.winner
	var copy := result_copy(S)
	var title: String = copy.title
	var sub: String = copy.sub
	print("[ludo] game over: winner %s team=%s human_won=%s reward=%d" % [LudoRules.pname(S, w), S.teams, human_won, reward])
	var xp_before := int(Save.profile.get("xp", 0))
	Save.record_ludo(players, human_won)
	var xp_after := int(Save.profile.get("xp", 0))
	if reward > 0:
		Save.add_coins(reward)
	hud.hide_for_result()
	var standings := []
	for e in LudoRules.standings(S):
		var c: int = e.color
		var kind := "you" if LudoRules.is_you(S, c) else ("cpu" if S.players[c] == "cpu" else "human")
		var nm := LudoRules.pname(S, c)
		standings.append({color = c, name = "You" if kind == "you" else nm, kind = kind,
			cpu_id = nm.to_lower() if kind == "cpu" and PlayerTile.CPU_IDS.has(nm.to_lower()) else "",
			place = e.place, finished = e.finished, progress = e.progress})
	await wait(0.35)
	if not live(id):
		return
	finished.emit({game = "ludo", title = title, sub = sub, standings = standings, human_won = human_won,
		reward = reward, teams = S.teams, color = w, winners = winners, vs_cpu = vs_cpu,
		xp_before = xp_before, xp_after = xp_after})

func _home_count(c: int) -> int:
	return LudoMatch.home_count(S, c)

static func home_count(s: Dictionary, c: int) -> int:
	var n := 0
	for p in s.tok[c]:
		if p >= LudoRules.GOAL:
			n += 1
	return n

## The result's headline, always from your side (vs the computer): {title, sub}.
##   you won:   "You win!" / "All four pawns home!"   Teams: "Your team wins!" / "You and Biscotti got all 8 pawns home!"
##   you lost:  "You finished 3rd" / "Mocha won · 2 of 4 pawns home"
##              Teams: "Your team finished 2nd" / "Team Green + Blue won · 5 of 8 pawns home"
##   no you (Pass & Play): "Mocha wins!" / "All four pawns home!"   Teams: "Team Red + Yellow wins!" / "Both teammates…"
## The XP is not repeated here: the result screen shows it once, in its card.
static func result_copy(s: Dictionary) -> Dictionary:
	var w: int = s.winner
	var winners := LudoRules.winners(s)
	var me := -1
	for k in 4:
		if LudoRules.active(s, k) and NetLudo.you(s, k):
			me = k
	var you_won := me >= 0 and winners.has(me)
	var place := 0
	if me >= 0:
		for e in LudoRules.standings(s):
			if int(e.color) == me:
				place = int(e.place)
	if LudoRules.team_on(s):
		if me < 0:
			return {title = L10n.t("Team %s wins!") % _team_label(w), sub = L10n.t("Both teammates got all four pawns home!")}
		var mate := LudoRules.mate_of(me)
		if you_won:
			return {title = L10n.t("Your team wins!"), sub = L10n.t("You and %s got all 8 pawns home!") % L10n.seat_name(LudoRules.pname(s, mate))}
		var n := home_count(s, me) + home_count(s, mate)
		var won_by := L10n.t("Team %s won") % _team_label(w)
		return {title = L10n.t("Your team finished %s") % _place(maxi(place, 2)),
			sub = (L10n.t("%s · %d of 8 pawns home") % [won_by, n]) if n > 0 else won_by}
	if me < 0:
		return {title = L10n.t("%s wins!") % L10n.seat_name(LudoRules.pname(s, w)), sub = L10n.t("All four pawns home!")}
	if you_won:
		return {title = L10n.t("You win!"), sub = L10n.t("All four pawns home!")}
	var k := home_count(s, me)
	var won := L10n.t("%s won") % L10n.seat_name(LudoRules.pname(s, w))
	var sub := won
	if k == 4:
		sub = L10n.t("%s · you got all four home") % won
	elif k > 0:
		sub = L10n.t("%s · %d of 4 pawns home") % [won, k]
	return {title = L10n.t("You finished %s") % _place(maxi(place, 2)), sub = sub}


# ---------- emotes ----------

## Who sends from this phone: your seat online; vs the computer the only human; Pass & Play the player to move
## (whoever holds the phone). -1: nobody (watching online, a table of computers, no game).
func emote_sender() -> int:
	return emote_sender_of(S, (ns.me if ns != null else -1) if online else -2)

## emote_sender() for a state: me = your colour online (-1: watching), -2 offline.
static func emote_sender_of(s: Dictionary, me := -2) -> int:
	if s.is_empty() or s.get("phase", "") == "over":
		return -1
	if me != -2:
		return me if me >= 0 and LudoRules.active(s, me) else -1
	var hs := [0, 1, 2, 3].filter(func(k): return LudoRules.is_human(s, k))
	if hs.size() == 1:
		return int(hs[0])
	if LudoRules.is_human(s, int(s.turn)):
		return int(s.turn)
	return int(hs[0]) if not hs.is_empty() else -1

## The emote button shows while someone here may send (never in the tutorial or after the game).
func _emote_sync() -> void:
	if hud.has_method("set_emotes"):
		hud.set_emotes(tut == null and not autoplay and emote_sender() >= 0)

## A pick from the picker: shown on the sender's seat at once (online the server relays it to the others).
func _emote_send(id: String) -> void:
	var c := emote_sender()
	if c < 0:
		return
	if online:
		_net_send({t = "emote", id = id})
	hud.emotes.show_emote(c, id)

# ---------- online (friend rooms and quick match: every seat that isn't a bot is a person) ----------

## An online match from the server's `start` (or a `sync` when joining one in progress). net: the NetClient.
func start_online(msg: Dictionary, net_: Object) -> void:
	_end_tutorial()
	hud.tutorial = false
	online = true
	net = net_
	_net_turn = {}
	ns = NetLudo.new()
	ns.begin(msg, str(net_.get("member_id")) if net_ else "")
	players = ns.S.players.duplicate()
	opts = {bot_level = "normal", pair_ask = bool(ns.S.get("pair_ask", false))}
	_net_sent = -1
	_net_info = {}
	_net_pumping = false
	_net_ready = false
	_over_msg = {}
	_rr_wait = false
	rr.clear()
	_net_hud()
	await _open(ns.S, int(msg.get("n", 0)) == 0 and str(msg.get("t", "start")) == "start")

## Back to an offline match: no replica, the HUD's online parts off.
func _offline() -> void:
	if not online:
		return
	online = false
	net = null
	_net_pumping = false
	_net_prompt = -1
	rr.clear()
	_rr_wait = false
	if hud.has_method("set_online"):
		hud.set_online(false)

## The HUD's online parts: you, the seats (names, avatars, badges), the away prompt.
func _net_hud() -> void:
	if hud.has_method("set_online"):
		hud.set_online(true, ns.me, ns.seats)

## _open's last step online: show the phase the state is in, then play what the server sent meanwhile.
func _net_open(id: int) -> void:
	_busy = false
	_net_ready = true
	_net_apply_hold()
	hud.update(S, S.turn)
	_net_badges()
	match str(S.phase):
		"choose":
			_choose(id, S.turn)
		"pair_ask":
			board.relayout(S)
			_idle_line()
			if ns.my_turn():
				_net_pair_prompt()
		"over":
			_game_over()
			return
		_:
			_begin_turn()
	_net_kick()

## A server message for the match: act / sync / over (queued, played in order).
func net_push(msg: Dictionary) -> void:
	if not online or ns == null:
		return
	ns.push(msg)
	match str(msg.get("t", "")):
		"over":
			_over_msg = msg
		"sync":
			if _net_pumping:
				_net_abort()                       # a snapshot mid-turn: end the animation now, the sync plays next
	_net_kick()

## A `sync` arrived while an act was animating: that animation is obsolete (the snapshot replaces the state). The
## match's generation moves on (every running animation unwinds at its next live() check), the board's walks stop, a
## tumbling die lands, and the pump is free to take the sync.
func _net_abort() -> void:
	aborts += 1
	_id += 1
	_net_pumping = false
	_busy = false
	board.cancel_all()
	hud.dice.finish_roll()
	hud.cancel_pair()
	_net_prompt = -1

## Plays the queue, one message at a time, each to the end of its animation.
func _net_kick() -> void:
	if _net_pumping or not online or S.is_empty() or not _net_ready:
		return
	_net_pumping = true
	var id := _id
	while live(id) and online:
		var m := ns.next()
		if m.is_empty():
			break
		_ff = NET_CATCHUP if ns.pending() > 0 else 1.0     # behind the server: catch up
		board.speed = _speed()
		match str(m.get("t", "")):
			"need_sync":
				_net_send({t = "sync_req"})
			"sync":
				_net_pumping = false
				_net_resync(m)
				return                             # _open plays the rest of the queue
			"over":
				_net_end(m)
			"act":
				await _net_act(id, m)
	if id == _id:
		_net_pumping = false
		_ff = 1.0
		board.speed = _speed()
		_net_show_turn()
		_net_reroll_show()

## One server action through the offline animation path.
func _net_act(id: int, m: Dictionary) -> void:
	var a: Dictionary = m.get("a", {})
	var c := int(a.get("c", S.turn))
	if not rr.offer.is_empty() and int(m.get("n", 0)) >= int(rr.offer.n):
		_net_reroll_close()                    # any action after the offer's roll closes it
	match str(a.get("k", "")):
		"roll":
			_rr_wait = false                   # (the re-rolled roll is here)
			_net_apply_hold()
			_busy = true
			hud.hold_dice = false
			hud.dice.set_active(false)
			await _tumble(c, int(a.get("v", 1)))
			if not live(id):
				return
			var ev := ns.apply_rules(a)
			_net_check(m)
			await _after_roll(id, c, int(a.get("v", 1)), ev)
		"move":
			var roller: int = S.turn
			_busy = true
			board.set_movable([])
			var ev := ns.apply_rules(a)
			_net_check(m)
			_net_info = {}
			if ev.is_empty():
				_busy = false
				return
			await _after_move(id, roller, ev, _net_info)
		"pair":
			if _net_prompt >= 0:
				_net_prompt = -1
				hud.cancel_pair()                  # answered (by you, or by the server's timer)
			var roller: int = S.turn
			_busy = true
			var ev := ns.apply_rules(a)
			_net_check(m)
			await _after_move(id, roller, ev, _net_info)
		"end":                                 # the server ends the match (only bots / ghosts left to finish)
			var ev := ns.apply_rules(a)
			_net_check(m)
			if not ev.is_empty():
				board.relayout(S)
				hud.update(S, S.winner)
				_game_over()
		"mode":
			ns.apply_rules(a)
			_net_check(m)
			players = S.players.duplicate()
			_net_badges()
			hud.update(S, S.turn)
			_idle_line()
			if c == ns.me and S.phase == "choose" and ns.my_turn():
				_choose(id, c)                     # back in the middle of your move
			elif c == ns.me and S.phase == "pair_ask" and ns.my_turn():
				_net_pair_prompt()

## After an act's rules step: the hash. A mismatch asks for a snapshot.
func _net_check(m: Dictionary) -> void:
	if _net_sent >= 0 and _net_sent < ns.n:
		_net_sent = -1                         # our request was answered (or overtaken)
	if not ns.verify(m):
		push_warning("[net] hash mismatch at n=%d: sync_req" % int(m.get("n", -1)))
		_net_send({t = "sync_req"})

## A full snapshot: replace the state, re-lay the board and go on from there.
func _net_resync(m: Dictionary) -> void:
	ns.begin(m, str(net.get("member_id")) if net else "")
	players = ns.S.players.duplicate()
	_net_sent = -1
	_net_info = {}
	_net_ready = false
	_net_hud()
	await _open(ns.S, false)

## `over`: the result (the last move's events usually got there first).
func _net_end(m: Dictionary) -> void:
	if _ended:
		return
	if S.phase != "over":
		S.phase = "over"
		S.winner = int(m.get("winner", S.winner))
		if m.get("finished") is Array:
			S.finished = MatchStore.ints(m.finished)
		board.relayout(S)
		hud.update(S, S.winner)
	_game_over()

## A request for the current step (at most one per step).
func _net_request(t: String, fields := {}) -> void:
	if not online or not ns.my_turn() or _net_sent == ns.n:
		return
	if t == "roll" and (rr.holds(ns.me) or _rr_wait):
		_net_roll_later(maxf(rr.hold_left_ms(), 250.0))   # the last player may roll again: send ours when it ends
		return
	if _net_send(ns.request(t, fields)):
		_net_sent = ns.n
		if t == "roll":
			hud.hold_dice = true
			hud.dice.set_active(false)

func _net_send(msg: Dictionary) -> bool:
	return net != null and bool(net.call("send_msg", msg))

## The pair prompt for your move; the answer goes to the server (the `pair` act plays it).
func _net_pair_prompt() -> void:
	var at := ns.n
	if _net_prompt == at:
		return
	_net_prompt = at
	var yes := await _ask_pair()
	if _net_prompt != at or not online or ns.n != at:
		return                                 # answered by the server's timer meanwhile
	_net_prompt = -1
	_net_request("pair", {yes = yes})

## turn {c, deadline, now}: the server's clock for the current step, on that player's tile; kept until the acts
## before it have played (so it never shows on the next player while the last move still animates).
func net_turn(msg: Dictionary) -> void:
	if not online or not hud.has_method("set_timer"):
		return
	var left := maxf(0.0, float(msg.get("deadline", 0)) - float(msg.get("now", 0)))
	var total := maxf(left, NetLudo.phase_sec(str(S.get("phase", "roll"))) * 1000.0)
	_net_turn = {c = int(msg.get("c", -1)), end = Time.get_ticks_msec() + int(left), total = total}
	if not _net_pumping:
		_net_show_turn()

func _net_show_turn() -> void:
	if not online or not hud.has_method("set_timer"):
		return
	if _net_turn.is_empty() or S.is_empty() or S.phase == "over":
		hud.set_timer(-1, 0.0, 1.0)
		return
	hud.set_timer(int(_net_turn.c), float(int(_net_turn.end) - Time.get_ticks_msec()), float(_net_turn.total))

## presence {id, online}: the offline badge.
func net_presence(msg: Dictionary) -> void:
	if not online:
		return
	ns.set_online(NetClient.id_str(msg.get("id", "")), bool(msg.get("online", true)))
	_net_badges()

## A request the server refused (stale, not your turn, bad action): let the player try again.
func net_error(msg: Dictionary) -> void:
	if not online:
		return
	var code := str(msg.get("code", ""))
	if RerollFlow.is_error(code):
		_net_reroll_error(code, msg)
		return
	push_warning("[net] request refused: %s" % code)
	_net_sent = -1
	hud.hold_dice = false
	if not S.is_empty():
		hud.update(S, S.turn)
		if ns.my_turn() and S.phase == "choose" and not _busy:
			_choose(_id, S.turn)

## NetClient.status: the "Reconnecting…" banner.
func net_status(st: String) -> void:
	if online and hud.has_method("set_banner"):
		hud.set_banner("Reconnecting…" if st in ["reconnecting", "connecting"] else "")

## {t: "emote", c, id}: another seat's reaction (a friend, a quick-match player); the lobby's (c = -1) and your
## own colour are left out.
func net_emote(msg: Dictionary) -> void:
	if not online or S.is_empty() or hud.get("emotes") == null:
		return
	var got := EmoteLayer.incoming(msg, ns.me, func(c: int) -> bool: return LudoRules.active(S, c))
	if not got.is_empty():
		hud.emotes.show_emote(int(got[0]), str(got[1]))

## "I’m back": your seat is yours again (the server answers with a `mode human` act).
func _net_back() -> void:
	if online:
		_net_send({t = "back"})

# ---------- online: re-roll and hold (RerollFlow) ----------

## reroll_offer {n, until, now, free, gems, cost}: your bad roll may be rolled again. The button shows once the bad
## roll has played (the offer is for the state at n).
func net_reroll_offer(msg: Dictionary) -> void:
	if not online or ns == null:
		return
	rr.on_offer(msg)
	if not _net_pumping:
		_net_reroll_show()

## The "Roll again" button, when an offer is open for the state shown and nothing is animating.
func _net_reroll_show() -> void:
	if not online or ns == null or S.is_empty() or not hud.has_method("show_reroll"):
		return
	if S.phase == "over" or _net_pumping or not rr.offer_open(ns.n):
		return
	if hud.reroll_button.visible:
		return
	hud.show_reroll(rr.offer_left_ms(), float(rr.offer.total), rr.is_free(), int(rr.offer.cost))

## A tap on "Roll again": {t: "reroll", n}; the button spins until `rerolled` (or an error).
func _net_reroll_tap() -> void:
	if not online or ns == null or not rr.offer_open(ns.n):
		return
	if _net_send({t = "reroll", n = int(rr.offer.n)}):
		rr.mark_sent()
		hud.reroll_button.set_busy(true)

## The offer is over (an action followed it, the re-roll was paid, an error): no button.
func _net_reroll_close() -> void:
	rr.clear_offer()
	if hud.has_method("hide_reroll"):
		hud.hide_reroll()

## hold {c, until}: the next roll waits for colour c's re-roll. Your dice sleep if the roll is yours; everyone else
## but c sees "<name> may roll again…".
func net_hold(msg: Dictionary) -> void:
	if not online or ns == null:
		return
	rr.on_hold(msg, _net_server_now())
	_net_apply_hold()

func _net_server_now() -> float:
	return float(net.call("server_now")) if net != null and net.has_method("server_now") else -1.0

## The dice and the note follow the hold: asleep while a hold on another colour's re-roll runs (or a paid re-roll waits
## for its roll), awake again when it ends.
func _net_apply_hold() -> void:
	if not online or ns == null or not hud.has_method("set_hold"):
		return
	var holding := rr.holds(ns.me)
	hud.roll_locked = holding or _rr_wait
	hud.set_hold(_pn(int(rr.hold.c)) if holding and not S.is_empty() and int(rr.hold.c) >= 0 else "")
	hud.refresh_roll()
	if holding:
		var token: float = rr.hold.end
		await get_tree().create_timer(rr.hold_left_ms() / 1000.0 + 0.03).timeout
		if online and not rr.hold.is_empty() and float(rr.hold.end) == token:
			rr.clear_hold()
			_net_apply_hold()

## Your roll goes out `ms` from now (the hold ends), when it is still yours to roll.
func _net_roll_later(ms: float) -> void:
	var at := ns.n
	var id := _id
	await get_tree().create_timer(ms / 1000.0 + 0.05).timeout
	if live(id) and online and ns != null and ns.n == at and ns.my_turn() and S.phase == "roll" and _net_sent != ns.n and not _busy:
		_net_request("roll")

## rerolled {c, paid}: "<name> rolled again" for everyone; the sync and the new roll follow.
func net_rerolled(msg: Dictionary) -> void:
	if not online or ns == null or S.is_empty():
		return
	var c := int(msg.get("c", -1))
	_net_reroll_close()
	rr.clear_hold()
	_rr_wait = true                            # the dice stay asleep until the new roll's act
	_net_apply_hold()
	Toast.show(hud, tr("You rolled again") if c == ns.me else tr("%s rolled again") % _pn(c), null, 1.8, "info")
	get_tree().create_timer(4.0).timeout.connect(func():
		if _rr_wait:                           # failsafe: the roll never came
			_rr_wait = false
			if online and ns != null:
				_net_apply_hold())

## error hold / reroll_used / reroll_closed / gems.
func _net_reroll_error(code: String, msg: Dictionary) -> void:
	if code == "hold":
		_net_sent = -1
		hud.hold_dice = false
		rr.on_hold({c = -2, until = msg.get("until", 0)}, _net_server_now())
		_net_apply_hold()
		_net_roll_later(maxf(rr.hold_left_ms(), 250.0))
		return
	var text := RerollFlow.error_text(code)
	if text != "":
		Toast.show(hud, text, null, 2.0, "bad")
	_net_reroll_close()

## The app came back to the front during an online match: the player is here, so the seat is theirs again without
## an "I’m back" tap (now, and when the bot that took it over while the phone was away shows up in the next acts).
func app_resumed() -> void:
	if not online:
		return
	_back_until = Time.get_ticks_msec() + BACK_WINDOW_MS
	_net_back()                              # (the server ignores it while the seat is still yours)

## Offline / bot badges on the tiles, and the away prompt when a bot plays for you.
func _net_badges() -> void:
	if not online or not hud.has_method("set_badges"):
		return
	var b := ["", "", "", ""]
	for c in 4:
		if not LudoRules.active(S, c):
			continue
		var st := ns.seat(c)
		if S.players[c] == "cpu":
			b[c] = "bot"
		elif c != ns.me and not st.is_empty() and not bool(st.get("online", true)):   # (you are here)
			b[c] = "offline"
	hud.set_badges(b)
	var botted: bool = ns.me >= 0 and S.players[ns.me] == "cpu" and S.phase != "over"
	if botted and Time.get_ticks_msec() < _back_until:
		_back_until = 0                      # just back in the app: take the seat back (once)
		_net_back()
		botted = false
	hud.show_away(botted)

## The event line while someone else plays: "Ana’s turn", "Ana is choosing…", a bot "Ana (bot) is thinking…".
func _net_wait_line(c: int) -> String:
	var nm := "[b]%s[/b]" % _pn(c)
	if c == ns.me:
		return tr("A bot is playing for you")
	if S.players[c] == "cpu":
		return tr("%s is away. A bot is playing…") % nm
	match str(S.phase):
		"choose":
			return tr("%s is choosing a pawn…") % nm
		"pair_ask":
			return tr("%s is deciding on a pair…") % nm
	return tr("%s’s turn") % nm

## The online result: what the match earns (NetReplica.online_reward: the server grants it into your account at
## `over` and Online refreshes the profile; without an account the XP is kept locally and there are no coins); the
## other players' own names, avatars and levels.
func _net_game_over() -> void:
	var id := _id
	_net_prompt = -1
	hud.cancel_pair()
	if hud.has_method("show_away"):
		hud.show_away(false)
	var winners := LudoRules.winners(S)
	var won := winners.has(ns.me)
	Sound.sfx("win" if won else "lose")
	var copy := result_copy(S)
	# the server's outcome: fixed when your side was ranked (play on: finished earlier, then maybe left / watched)
	var away: bool = _my_away if _my_place > 0 else (ns.me >= 0 and S.players[ns.me] == "cpu")
	var outcome := "" if ns.me < 0 else ("left" if away else ("win" if won else "finish"))
	if _over_msg.is_empty() and net != null and bool(net.get("quick")):
		for _k in 120:                         # (the `over` carries the coin table's payouts: a moment at most)
			if not _over_msg.is_empty() or not live(id):
				break
			await get_tree().process_frame
	var table := NetReplica.table_result(_over_msg, ns.me)
	var rw := NetReplica.online_reward("ludo", outcome)
	var xp_before := int(Save.profile.get("xp", 0))
	var xp_after := xp_before
	var reward := 0
	if NetReplica.server_rewards():
		reward = int(table.payout) + int(table.get("bonus", 0)) if int(table.get("entry", 0)) > 0 else NetReplica.online_coins("ludo", outcome, table)
		xp_after = xp_before + int(rw.xp)
	elif int(rw.xp) > 0:
		Save.profile.xp = xp_before + int(rw.xp)
		Save.save()
		Save.changed.emit()
		xp_after = int(Save.profile.get("xp", 0))
	hud.hide_for_result()
	var standings := []
	for e in LudoRules.standings(S):
		var c: int = e.color
		var st := ns.seat(c)
		var mine := c == ns.me
		standings.append({color = c, name = "You" if mine else str(st.get("name", LudoRules.pname(S, c))),
			kind = "you" if mine else "human", cpu_id = "", avatar = str(st.get("avatar", "")),
			frame = str(st.get("frame", "")), level = int(st.get("level", 1)), place = e.place, finished = e.finished,
			progress = e.progress})
	await wait(0.35)
	if not live(id):
		return
	finished.emit({game = "ludo", title = copy.title, sub = copy.sub, standings = standings, human_won = won,
		reward = reward, teams = S.teams, color = S.winner, winners = winners, vs_cpu = false, online = true,
		xp_before = xp_before, xp_after = xp_after, table = table})
