extends "res://tests/test_suite.gd"
## The guided first match (Tutorial): its staged board and scripted dice must teach what each step says, under the
## real rules (enter on a 6, a capture, the safe star, an exact roll home, a pair), then Mocha's one turn lands on
## your star without capturing you and hands the turn back. Also the copy rules for its captions.

const Tut := preload("res://scripts/game/tutorial.gd")

func run() -> void:
	var cfg: Dictionary = Tut.config()
	check("config: a tutorial vs one easy computer", cfg.tutorial == true and cfg.bot_level == "easy" and cfg.players == ["human", "off", "cpu", "off"] and cfg.teams == false, cfg)
	var s: Dictionary = Tut.new_state()
	check("staged board: your turn first, Mocha is the computer", s.turn == Tut.YOU and s.players[Tut.BOT] == "cpu" and Ludo.pname(s, Tut.BOT) == "Mocha", [s.turn, s.names])
	check("staged board: nothing paired, pairing is automatic", s.pairs.is_empty() and s.pair_ask == false)

	var sixes := 0
	var ok_all := true
	for n in Tut.STEPS.size():
		var st: Dictionary = Tut.STEPS[n]
		if st.has("roll"):
			var ok: bool = s.turn == Tut.YOU and s.phase == "roll"
			var ev := Ludo.apply_roll(s, int(st.roll))
			sixes = sixes + 1 if st.roll == 6 else 0
			ok = ok and s.phase == "choose" and not ev.any(func(e): return e.type in ["stuck", "three_sixes"])
			check("step %d: the roll of %d gives you a move" % [n + 1, st.roll], ok, [s.phase, ev])
			ok_all = ok_all and ok
			continue
		var k := int(st.move)
		if st.has("mark") and str(st.mark).begins_with("pawn:"):
			var key := int(str(st.mark).substr(5))
			check("step %d: the marked pawn is out on the board" % [n + 1], s.tok[key / 4][key % 4] >= 0, key)
		var u := Ludo.unit_for_token(s, k)
		check("step %d: pawn %d can move" % [n + 1, k], not u.is_empty(), Ludo.units(s))
		var before: int = s.tok[Tut.YOU][k]
		var ev := Ludo.move(s, int(u.get("token", k)))
		var types := ev.map(func(e): return e.type)
		var ok := false
		match str(st.get("expect", "")):
			"enter":
				ok = before == -1 and s.tok[Tut.YOU][k] == 0
			"capture":
				ok = types.has("capture") and s.tok[Tut.BOT][0] == -1
			"star":
				ok = s.tok[Tut.YOU][k] == Tut.STAR and Ludo.STARS.has(Ludo.abs_index(Tut.YOU, Tut.STAR))
			"home":
				ok = s.tok[Tut.YOU][k] == Ludo.GOAL and types.has("home")
			"pair":
				ok = types.has("pair_formed") and not Ludo.pair_of(s, Tut.YOU, k).is_empty()
		check("step %d: the move does what it teaches (%s)" % [n + 1, st.get("expect", "")], ok, ev)
		ok_all = ok_all and ok
		if n < Tut.STEPS.size() - 1:
			check("step %d: you keep the turn (extra roll)" % [n + 1], s.turn == Tut.YOU and s.phase == "roll", [s.turn, s.phase])
	check("every step played as scripted", ok_all)
	check("never three 6s in a row", sixes < 3)
	check("after the lesson: Mocha's turn", s.turn == Tut.BOT and s.phase == "roll", [s.turn, s.phase])

	# Mocha's one scripted turn: onto your star, no capture
	for v in Tut.BOT_ROLLS:
		Ludo.apply_roll(s, v)
		var mv := Ludo.units(s)
		check("Mocha's roll of %d has one move (Easy picks it for sure)" % v, mv.size() == 1, mv)
		var ev := Ludo.move(s, Ludo.pick_ai(s, mv.map(func(u): return u.token), null, "easy"))
		check("Mocha lands on your star and captures nothing", not ev.any(func(e): return e.type == "capture") and Ludo.abs_index(Tut.BOT, s.tok[Tut.BOT][1]) == Ludo.abs_index(Tut.YOU, Tut.STAR), ev)
	check("your pawn is still on the star", s.tok[Tut.YOU][0] == Tut.STAR)
	check("then your turn again (the closing card)", s.turn == Tut.YOU and s.phase == "roll", [s.turn, s.phase])

	# the dice hooks
	var t = Tut.new()
	var rolls := []
	for st in Tut.STEPS:
		if st.has("roll"):
			rolls.append(t.roll_for(Tut.YOU))
			t.i += 1                          # (the move step)
	check("roll_for gives your scripted rolls in order", rolls == Tut.STEPS.filter(func(x): return x.has("roll")).map(func(x): return x.roll), rolls)
	check("roll_for: random once the lesson is over", t.roll_for(Tut.YOU) == 0)
	check("roll_for gives Mocha's scripted roll, then random", t.roll_for(Tut.BOT) == Tut.BOT_ROLLS[0] and t.roll_for(Tut.BOT) == 0)
	t.free()

	# copy: sentence case, typographic apostrophes, "pawn" not "token"
	var texts := []
	for st in Tut.STEPS:
		texts.append(st.text)
		if st.has("sub"):
			texts.append(st.sub)
	texts.append_array(Tut.PAIR_NOTE + Tut.SAFE_NOTE + [Tut.READY_TITLE, Tut.READY_TEXT, Tut.READY_PLAY, Tut.READY_HOME,
		Tut.SKIP_TITLE, Tut.SKIP_TEXT, Tut.SKIP_YES, Tut.SKIP_NO])
	check("ready card: all four pawns (spelled out)", Tut.READY_TEXT.contains("all four pawns") and not Tut.READY_TEXT.contains("4 pawns"))
	check("skip asks first and says where to replay it", Tut.SKIP_TEXT.contains("How to play") and Tut.SKIP_TITLE.ends_with("?"))
	check("held notes stay long enough to read", Tut.NOTE_SEC >= 4.5)
	var t2 = Tut.new()
	check("nothing held before the lesson starts", not t2.holding())
	t2.free()
	var bad := texts.filter(func(x: String): return x.contains("'") or x.to_lower().contains("token") or x[0] != x[0].to_upper() or x.length() > 48 and x != Tut.READY_TEXT)
	check("captions: sentence case, ’ apostrophes, pawn, short", bad.is_empty(), bad)
	var sentences := []
	for x in texts:
		sentences.append_array(Array(x.split(". ")))
	var title_case := sentences.filter(func(x: String):
		var w := Array(x.split(" "))
		return w.size() > 2 and w.slice(1).filter(func(y: String): return y.length() > 3 and y[0] == y[0].to_upper() and y[0] != y[0].to_lower() and y != "Mocha" and y != "Mocha’s").size() > 0)
	check("captions: no Title Case", title_case.is_empty(), title_case)
