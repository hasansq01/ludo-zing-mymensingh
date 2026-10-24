class_name Tutorial
extends Node
## The guided first match (ON-01): you (Red) against one Easy computer (Mocha, Yellow) on a staged board, with
## forced dice that script the lesson: tap the dice, a 6 brings a pawn out, a 6 means another roll, a capture,
## a safe star, an exact roll home, a pair (it forms by itself, Decision 3) and the star keeping you safe from
## Mocha. Each of your decisions gets a coach mark (CoachMarks): the scrim cuts out the dice or the one pawn to
## tap. About a minute; "Skip tutorial" is always there (it asks first: Sheet.confirm). Finishing or skipping sets
## Save.prefs.tutorial_done; the "You’re ready!" card then starts a real game (or goes home). How to play has a
## "Replay tutorial" row (main.start_ludo(Tutorial.config())).
## One voice: while it runs the HUD's event line is quiet (LudoHUD.tutorial) and the coach bubble is the only
## instruction. The two explanations (the pair, the safe star) stay until tapped ("Tap to continue"; at most
## NOTE_SEC), and the game waits for them and for the skip question (holding(): LudoMatch.wait checks it).
##
## Start it with LudoMatch.start_tutorial(), or main.start_ludo(Tutorial.config()) (LudoMatch.start sees
## opts.tutorial). LudoMatch asks this node for the dice values (roll_for), which pawns may move (allowed) and
## tells it about turns, rolls, moves and events (on_turn, on_rolled, on_moved, on_event). Never saved to
## MatchStore.

signal ended(how: String)                # "done" (the card was reached) | "skip" | "left"

const YOU := 0
const BOT := 2
const PLAYERS := ["human", "off", "cpu", "off"]
## The staged board: your pawns 0 and 1 at base, pawn 2 out on square 4, pawn 3 one square from home; Mocha's
## pawns on squares 2 (in front of your start) and 5 (abs). Progress per colour (LudoRules): Yellow 28 = abs 2,
## 31 = abs 5, 34 = abs 8 (your star).
const START_TOK := [[-1, -1, 4, 55], [-1, -1, -1, -1], [28, 31, -1, -1], [-1, -1, -1, -1]]
const STAR := 8                          # your first star square (progress = abs for Red)

## The lesson, one entry per decision of yours. roll: what your next dice tap shows. move: your pawn the step lets
## you tap (only it glows); mark: what else the cut-out shows ("pawn:<key>" = colour * 4 + index, "square:<p>",
## "goal"); expect: what the move must do (checked by tests/test_tutorial.gd).
const STEPS := [
	{roll = 6, text = "Tap the dice to roll"},
	{move = 0, text = "A 6 brings a pawn out", sub = "Tap the glowing pawn", expect = "enter"},
	{roll = 2, text = "A 6 means you roll again"},
	{move = 0, mark = "pawn:8", text = "Capture Mocha’s pawn", sub = "Land on it to send it back to base", expect = "capture"},
	{roll = 6, text = "A capture earns an extra roll"},
	{move = 0, mark = "square:8", text = "Stars are safe squares", sub = "No one can capture a pawn on a star", expect = "star"},
	{roll = 1, text = "Another 6, another roll"},
	{move = 3, mark = "goal", text = "Get this pawn home", sub = "It needs exactly a 1", expect = "home"},
	{roll = 6, text = "Getting home earns an extra roll"},
	{move = 1, text = "Bring out another pawn", expect = "enter"},
	{roll = 4, text = "Roll once more"},
	{move = 1, mark = "pawn:2", text = "Land on your own pawn", sub = "Two pawns on one square make a pair", expect = "pair"},
]
## Mocha's dice: one turn, its pawn on abs 5 moves onto your star (abs 8) and can't capture you there.
const BOT_ROLLS := [3]
const FIRST_DELAY := 1.0                 # s before the first coach mark (the camera flies to the board)

const NOTE_SEC := 8.0                    # a held note closes by itself after this (a tap closes it sooner)
const PAIR_NOTE := ["You made a pair!", "Pairs move on even rolls and block rivals"]
const SAFE_NOTE := ["Your pawn on the star is safe", "Mocha landed there too but can’t capture it"]
const READY_TITLE := "You’re ready!"
const READY_TEXT := "Get all four pawns home first to win. Roll 6s, capture rivals and use stars to stay safe."
const READY_PLAY := "Play a real game"
const READY_HOME := "Back to home"
const SKIP_TITLE := "Skip the tutorial?"
const SKIP_TEXT := "You can replay it from How to play."
const SKIP_YES := "Skip"
const SKIP_NO := "Keep learning"

var match_: Node                         # the LudoMatch
var marks: CoachMarks
var i := 0                               # the next STEPS entry
var _bot := 0                            # the next BOT_ROLLS entry
var _over := false
var _closing := false
var _asking := false                     # the skip question is open
var _confetti: Control


## The start config for main.start_ludo (LudoMatch.start sees `tutorial`). then: the mode the player picked
## ("cpu" | "local"), where "Play a real game" leads afterwards.
static func config(then := "cpu") -> Dictionary:
	return {game = "ludo", players = PLAYERS.duplicate(), teams = false, bot_level = "easy", tutorial = true, then = then}

## The rules state the tutorial starts from.
static func new_state() -> Dictionary:
	var s := LudoRules.new_game(PLAYERS.duplicate(), false, {pair_ask = false})
	s.tok = START_TOK.duplicate(true)
	return s

## True once the tutorial was finished or skipped (or the player is a returning one: Save fills it in).
static func done() -> bool:
	return bool(Save.prefs.get("tutorial_done", false))

static func mark_done() -> void:
	if not done():
		Save.prefs.tutorial_done = true
		Save.save()


func _init(match_node: Node = null) -> void:
	match_ = match_node
	name = "Tutorial"

## Puts the coach marks over the HUD.
func attach(hud: Control) -> void:
	marks = CoachMarks.new()
	marks.name = "CoachMarks"
	hud.add_child(marks)
	if "coach" in hud:
		hud.set("coach", marks)
	marks.set_dice(hud.get("dice"))
	marks.skip.connect(_on_skip)
	_place_skip.call_deferred()
	if hud.has_signal("resized"):
		hud.resized.connect(_place_skip)

func _place_skip() -> void:
	if not is_instance_valid(marks):
		return
	var hud := marks.get_parent()
	var top: Variant = hud.get("top") if hud else null
	var y := 60.0
	if top is Object and (top as Object).has_method("bottom"):
		y = float(top.call("bottom")) + UIKit.SPACE.sm
	marks.set_safe_top(y)

func step() -> Dictionary:
	return STEPS[i] if i < STEPS.size() else {}

func active() -> bool:
	return not _over

## The game should wait: a held note is up or the skip question is open.
func holding() -> bool:
	return _asking or (is_instance_valid(marks) and marks.holding())


# ---------- hooks (LudoMatch) ----------

## The dice value for colour c's roll now (0 = random: the lesson is over).
func roll_for(c: int) -> int:
	if _over:
		return 0
	if c == YOU:
		var st := step()
		if st.has("roll"):
			i += 1
			return int(st.roll)
		return 0
	if _bot < BOT_ROLLS.size():
		_bot += 1
		return int(BOT_ROLLS[_bot - 1])
	return 0

## A turn begins (after the HUD shows it). Returns true when the tutorial takes the turn over (the closing card):
## the match must not continue it.
func on_turn(c: int) -> bool:
	if _over or not is_instance_valid(marks):
		return false
	if c != YOU:
		marks.hide_step()
		return false
	var st := step()
	if st.has("roll"):
		if i == 0:
			_first_step.call_deferred()      # once the camera has settled on the board
		else:
			_dice_step()
		return false
	if st.is_empty():
		_finish()
		return true
	_bail()                                  # (the board went off script: end the lesson)
	return true

func _dice_step() -> void:
	var st := step()
	marks.step(CoachMarks.around_control(match_.hud.dice), st.text, str(st.get("sub", "")))

func _first_step() -> void:
	await get_tree().create_timer(FIRST_DELAY).timeout
	if not _over and i == 0 and is_instance_valid(marks) and match_.S.get("phase", "") == "roll" and not match_.get("_busy"):
		_dice_step()

## Your dice tap went through: the scrim lifts while the die rolls.
func on_rolled(c: int) -> void:
	if not _over and c == YOU and is_instance_valid(marks):
		marks.hide_step()

## Your choice after a roll: the pawns (your colour's indices) that may move now; [] = the normal rules (not in
## the lesson). Shows the coach mark on the pawn.
func allowed(c: int) -> Array:
	if _over or c != YOU:
		return []
	var st := step()
	if not st.has("move"):
		_bail()
		return []
	var k := int(st.move)
	if LudoRules.unit_for_token(match_.S, k).is_empty():
		_bail()
		return []
	var key := YOU * 4 + k
	var board: LudoBoard = match_.board
	var cam: Camera3D = match_.world.camera
	var target := CoachMarks.around_point(func() -> Vector2: return cam.unproject_position(board.pawn_point(key)))
	marks.step(target, st.text, str(st.get("sub", "")), _mark_of(str(st.get("mark", ""))))
	return [k]

## Your move went through.
func on_moved(c: int) -> void:
	if _over or c != YOU:
		return
	if step().has("move"):
		i += 1
	if is_instance_valid(marks):
		marks.hide_step()

## Rules events while the lesson runs: the pair gets its short explanation.
func on_event(e: Dictionary) -> void:
	if _over or not is_instance_valid(marks):
		return
	if e.get("type", "") == "pair_formed" and int(e.get("c", -1)) == YOU:
		var key := YOU * 4 + int(e.get("a", 0))
		var at := _pawn_rect(key)
		marks.note(PAIR_NOTE[0], PAIR_NOTE[1], at, NOTE_SEC, true)

## Leaving the match (Home, a new game) while the lesson runs counts as skipping it.
func cancel() -> void:
	if not _over:
		_over = true
		mark_done()
		ended.emit("left")
	_drop_confetti()
	if is_instance_valid(marks):
		marks.clear()
		marks.queue_free()


# ---------- the end ----------

## The lesson is over: the star note, then the card (tutorial_done is set as it shows).
func _finish() -> void:
	if _closing:
		return
	_closing = true
	match_.set("_busy", true)
	match_.hud.dice.set_active(false)
	match_.hud.idle("")
	while is_instance_valid(marks) and marks.noting():    # let the pair note finish first
		await get_tree().process_frame
	if not is_inside_tree() or _over:
		return
	var a_key := YOU * 4 + 0
	var star_ok: bool = int(match_.S.tok[YOU][0]) == STAR
	if star_ok:
		await marks.note(SAFE_NOTE[0], SAFE_NOTE[1], _pawn_rect(a_key), NOTE_SEC, true)
	if not is_inside_tree() or _over:
		return
	_over = true
	mark_done()
	Sound.sfx("win")
	Haptics.success()
	var parent := marks.get_parent() as Control
	if parent:
		_confetti = Celebrate.run(parent, "burst", 0.45)
	var what := await marks.card(READY_TITLE, READY_TEXT, READY_PLAY, READY_HOME)
	_drop_confetti()                          # before the next screen: no confetti over the real game
	if not is_inside_tree():
		return
	ended.emit("done")
	_exit(what)

## "Skip tutorial": asks first (the lesson waits meanwhile), then a real game.
func _on_skip() -> void:
	if _over or _asking:
		return
	_asking = true
	var host: Node = marks if is_instance_valid(marks) else self
	var yes: bool = await Sheet.confirm(host, SKIP_TITLE, SKIP_TEXT, SKIP_YES, SKIP_NO)
	_asking = false
	if not yes or _over or not is_inside_tree():
		return
	_over = true
	mark_done()
	ended.emit("skip")
	_exit("play")

func _drop_confetti() -> void:
	if is_instance_valid(_confetti):
		var p := _confetti.get_parent()
		if p:
			p.remove_child(_confetti)
		_confetti.queue_free()
	_confetti = null

## Off script (should not happen): close the lesson quietly with the card.
func _bail() -> void:
	push_warning("Tutorial: off script at step %d" % i)
	i = STEPS.size()
	_finish.call_deferred()

## "play": a real game vs the computer (main.start_ludo when there is one); "home": back home.
func _exit(what: String) -> void:
	if is_instance_valid(marks):
		marks.clear()
	_drop_confetti()
	if match_ and match_.has_method("tutorial_exit"):
		match_.call("tutorial_exit", what)


# ---------- targets ----------

func _pawn_rect(key: int, d := CoachMarks.PAWN_HOLE) -> Callable:
	var board: LudoBoard = match_.board
	var cam: Camera3D = match_.world.camera
	return CoachMarks.around_point(func() -> Vector2: return cam.unproject_position(board.pawn_point(key)), d)

func _square_rect(c: int, p: int, d := CoachMarks.MARK_HOLE) -> Callable:
	var board: LudoBoard = match_.board
	var cam: Camera3D = match_.world.camera
	var g := LudoBoard.grid_of(c, p, 0)
	if p >= LudoRules.GOAL:
		g = Vector2(LudoBoard.FIN[c].x, LudoBoard.FIN[c].y)       # the middle of the colour's home triangle
	var at := LudoBoard.to_world(g)
	return CoachMarks.around_point(func() -> Vector2: return cam.unproject_position(board.to_global(at)), d)

func _mark_of(m: String) -> Callable:
	if m.begins_with("pawn:"):
		return _pawn_rect(int(m.substr(5)), CoachMarks.MARK_HOLE)
	if m.begins_with("square:"):
		return _square_rect(YOU, int(m.substr(7)))
	if m == "goal":
		return _square_rect(YOU, LudoRules.GOAL, 56.0)
	return Callable()
