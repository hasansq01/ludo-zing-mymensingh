extends "res://tests/test_suite.gd"
## Phase 1 C-B components: GameTopBar message rules (events readable >= 1.6 s, idle fallback, no stale text),
## PlayerTile slot side and states, ResultScreen copy, CoinFly counts, TapLog / Autoplay gates.

func run() -> void:
	# ---- GameTopBar ----
	var bar := GameTopBar.new()
	bar.set_idle("Your turn — tap the dice")
	check("bar: idle shows", bar.current() == "Your turn — tap the dice", bar.current())
	bar.say("[b]Mocha[/b] captured your pawn!", 0.5, "event")
	check("bar: event replaces idle", bar.current() == "[b]Mocha[/b] captured your pawn!", bar.current())
	bar.say("[b]Biscotti[/b] rolled 2.", 1.0, "info")
	check("bar: info waits for a fresh event", bar.current() == "[b]Mocha[/b] captured your pawn!", bar.current())
	bar._process(1.0)
	check("bar: event still up at 1.0 s (min 1.6)", bar.current() == "[b]Mocha[/b] captured your pawn!", bar.current())
	bar._process(0.7)
	check("bar: the waiting info follows the event", bar.current() == "[b]Biscotti[/b] rolled 2.", bar.current())
	bar._process(1.1)
	check("bar: back to idle after expiry", bar.current() == "Your turn — tap the dice", bar.current())
	bar.say("A", 1.6, "event")
	bar.say("B", 1.6, "event")
	check("bar: a new event replaces an event", bar.current() == "B", bar.current())
	bar.clear()
	check("bar: clear leaves nothing", bar.current() == "", bar.current())
	bar.set_turn(2)
	check("bar: bold names tinted", bar._tint("[b]Yellow[/b]").contains("[color=#"), bar._tint("[b]Yellow[/b]"))
	check("bar: who()", GameTopBar.who("Mocha", 1).begins_with("[b][color=#"))
	bar.set_mode("back")
	check("bar: back mode", bar.mode == "back" and bar.left_button != null)
	bar.set_idle("Your turn — tap the dice")
	check("bar: a short line is one line at 16 px", bar.line_size() == UIKit.FS.status and not bar.wrapped(), [bar.line_size(), bar.wrapped()])
	bar.say("Biscotti rolled three 6s. Turn lost.", 1.6, "event")
	check("bar: a long line shrinks (>= 14 px) before it wraps", bar.line_size() >= GameTopBar.FS_MIN and bar.line_size() < UIKit.FS.status, [bar.line_size(), bar.wrapped()])
	bar.say("[b]Espresso[/b] is done! A 6 lets them help [b]Biscotti[/b] and then everyone else at the table too.", 1.6, "event")
	check("bar: only a very long line wraps, at 14 px", bar.wrapped() and bar.line_size() == GameTopBar.FS_MIN, [bar.line_size(), bar.wrapped()])
	bar.say("[b]Biscotti[/b] got a pawn home!", 2.2, "event")
	bar.cancel_message()
	check("bar: cancel_message drops the event for the idle line", bar.current() == "Your turn — tap the dice", bar.current())
	bar.free()

	# ---- PlayerTile ----
	var l := PlayerTile.new(0, "left")
	var r := PlayerTile.new(1, "right")
	check("tile: slot towards the centre (left tile)", l.dice_slot_local().position.x > PlayerTile.AVA, l.dice_slot_local())
	check("tile: slot towards the centre (right tile)", r.dice_slot_local().position.x < PlayerTile.PAD + 1.0, r.dice_slot_local())
	r.set_player("Mocha", "cpu", "mocha")
	r.set_state(true, false, 2, 0.426, "Help your teammate")
	check("tile: whole percent", r._pct.text == "43%", r._pct.text)
	check("tile: chip shown", r._chip_pill.visible and r._chip.text == "Help your teammate")
	check("tile: cpu tag", r._cpu_tag.visible)
	check("tile: pips", (r._pips[1] as PlayerTile.Pip).filled and not (r._pips[2] as PlayerTile.Pip).filled)
	r.set_state(false, false, -1, 0.47, "")
	r.set_note("Square 47")
	check("tile: note replaces percent", r._pct.text == "Square 47" and not r._pips[0].visible, r._pct.text)
	check("tile: mascot by name", PlayerTile.mascot_texture("Espresso") != null)
	check("tile: unknown cpu name falls back", PlayerTile.mascot_texture("Zed", 2) != null)
	l.set_player("You", "you")
	check("tile: you has no cpu tag", not l._cpu_tag.visible)
	check("tile: framed in the player colour (lighter while waiting)", l._sb_card.border_color == PlayerTile.frame_color(0, false)
		and l._sb_card_on.border_color == Palette.PLAYER[0] and PlayerTile.frame_color(0, false) != Color.WHITE)
	check("tile: nameplate tinted with the player colour", (r._name_pill.get_theme_stylebox("panel") as StyleBoxFlat).bg_color != Color.WHITE)
	r.set_chip_colors([1, 3])
	r.set_state(false, false, 0, 0.1, "Rivals")
	check("tile: team chip leads with the two team colour dots", r._chip_dots.visible and r._chip_dots.get_child_count() == 2
		and (r._chip_dots.get_child(1) as PlayerTile.Pip).color == Palette.PLAYER[3], r._chip_dots.get_child_count())
	r.set_progress_visible(false)
	r.set_state(false, false, 0, 0.27, "")
	check("tile: progress pill can hide (tutorial)", not r._prog_pill.visible)
	l.free()
	r.free()

	# ---- LudoHUD team chips ----
	var ts := LudoRules.new_game(["human", "cpu", "cpu", "cpu"], true)
	check("hud: team chips say who is with whom", LudoHUD.team_chip(ts, 0) == "With Yellow" and LudoHUD.team_chip(ts, 2) == "With you"
		and LudoHUD.team_chip(ts, 1) == "Rivals" and LudoHUD.team_chip(ts, 3) == "Rivals", [0, 1, 2, 3].map(func(c): return LudoHUD.team_chip(ts, c)))
	check("hud: no team chip outside Teams", LudoHUD.team_chip(LudoRules.new_game(["human", "cpu", "cpu", "cpu"]), 0) == "")

	# ---- ResultScreen copy ----
	var st := [{color = 1, name = "Mocha", kind = "cpu", place = 1, finished = true, progress = 1.0},
		{color = 0, name = "You", kind = "you", place = 2, finished = false, progress = 0.8}]
	var lose := ResultScreen.new({game = "ludo", standings = st, human_won = false, reward = 0, xp_before = 30, xp_after = 70})
	check("result: a loss is headlined from your side", lose.title_text() == "You finished 2nd", lose.title_text())
	check("result: the loss line says who won (XP only once, in the card)", lose.sub_text() == "Mocha won", lose.sub_text())
	check("result: no confetti on a loss", not lose.celebrates())
	check("result: the hero shows you on a loss, no crown", lose.hero_rows().size() == 1 and lose.hero_rows()[0].kind == "you"
		and not (lose.find_child("Crown", true, false) as Control).visible, lose.hero_rows())
	lose.free()
	var lose_c := ResultScreen.new({game = "ludo", standings = st, human_won = false, reward = LudoRules.PLAY_REWARD, xp_before = 30, xp_after = 70})
	check("result: a loss with the participation reward shows coins and XP", lose_c.coins != null and lose_c.xp_meter != null)
	lose_c.free()
	var st2 := [{color = 0, name = "You", kind = "you", place = 1, finished = true, progress = 1.0},
		{color = 2, name = "Biscotti", kind = "cpu", place = 1, finished = true, progress = 1.0},
		{color = 1, name = "Mocha", kind = "cpu", place = 2, finished = false, progress = 0.6},
		{color = 3, name = "Espresso", kind = "cpu", place = 2, finished = false, progress = 0.4}]
	var team := ResultScreen.new({game = "ludo", standings = st2, human_won = true, reward = 200, xp_before = 0, xp_after = 100})
	check("result: teams detected", team.is_teams())
	check("result: your team title", team.title_text() == "Your team wins!", team.title_text())
	check("result: confetti on a win", team.celebrates())
	check("result: one crown (the hero), none in the rows", team.find_children("*", "TextureRect", true, false).filter(func(x): return (x as TextureRect).texture == UIKit.svg("ic_crown")).size() == 1)
	team.free()
	var st2l := [{color = 1, name = "Mocha", kind = "cpu", place = 1, finished = true, progress = 1.0},
		{color = 3, name = "Espresso", kind = "cpu", place = 1, finished = true, progress = 1.0},
		{color = 0, name = "You", kind = "you", place = 2, finished = false, progress = 0.6},
		{color = 2, name = "Biscotti", kind = "cpu", place = 2, finished = false, progress = 0.4}]
	var team_l := ResultScreen.new({game = "ludo", standings = st2l, human_won = false, reward = 20, xp_before = 0, xp_after = 40})
	check("result: a team loss from your side", team_l.title_text() == "Your team finished 2nd" and team_l.sub_text() == "Team Green + Blue won", [team_l.title_text(), team_l.sub_text()])
	check("result: the team-loss hero shows you and your teammate", team_l.hero_rows().size() == 2)
	team_l.free()
	var st3 := [{color = 1, name = "Green", kind = "human", place = 1, finished = true, progress = 1.0},
		{color = 3, name = "Blue", kind = "human", place = 1, finished = true, progress = 1.0},
		{color = 0, name = "Red", kind = "human", place = 2, finished = false, progress = 0.5},
		{color = 2, name = "Yellow", kind = "human", place = 2, finished = false, progress = 0.5}]
	var pp := ResultScreen.new({game = "ludo", standings = st3, human_won = true, reward = 0})
	check("result: team by colours", pp.title_text() == "Team Green + Blue wins!", pp.title_text())
	check("result: teams copy says teammates", pp.sub_text() == "Both teammates got all four pawns home!", pp.sub_text())
	pp.free()
	var sl := ResultScreen.new({game = "sl", title = "", standings = [{color = 0, name = "You", kind = "you", place = 1, finished = true, progress = 1.0}], human_won = true})
	check("result: sl win copy", sl.title_text() == "You win!" and sl.sub_text() == "First to square 100!", [sl.title_text(), sl.sub_text()])
	sl.free()
	# finished rows: a check + "Finished" (no caps HOME / SQ 100 tag); place badges gold / silver / bronze
	var fin := ResultScreen.new({game = "ludo", standings = st2, human_won = true, reward = 0})
	var fin_l := fin.find_children("Finished", "Label", true, false)
	check("result: finished rows say Finished", fin_l.size() == 2 and (fin_l[0] as Label).text == "Finished", fin_l.size())
	var caps_home := fin.find_children("*", "Label", true, false).filter(func(l): return l.text == "HOME" or l.text == "SQ 100")
	check("result: no HOME tag", caps_home.is_empty())
	fin.free()
	check("place badge: gold / silver / bronze", PlayerTile.PlaceBadge.face_color(1) == Palette.GOLD
		and PlayerTile.PlaceBadge.face_color(2) == Palette.SILVER and PlayerTile.PlaceBadge.face_color(3) == Palette.BRONZE)
	check("result: ordinals", ResultScreen.ordinal(1) == "1st" and ResultScreen.ordinal(2) == "2nd" and ResultScreen.ordinal(3) == "3rd" and ResultScreen.ordinal(4) == "4th" and ResultScreen.ordinal(11) == "11th")

	# ---- CoinFly, TapLog, Autoplay ----
	check("coinfly: 6..10 coins", CoinFly.count_for(20) == 6 and CoinFly.count_for(200) == 7 and CoinFly.count_for(5000) == 10)
	check("taplog: debug builds only", TapLog.enabled() == OS.is_debug_build())
	check("autoplay: rotation", Autoplay.kind_of("all", 1) == "ludo" and Autoplay.kind_of("all", 2) == "teams" and Autoplay.kind_of("all", 3) == "sl" and Autoplay.kind_of("sl", 5) == "sl")
