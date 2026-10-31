extends "res://tests/test_suite.gd"
## The lobby pieces of the re-audit round (R-M1): Pass & Play seat names (SetupSheet + main.setup_config), the
## daily calendar's "TOMORROW" status, the home switch's two-line fallback, the Meter's numbers fitting and the
## sentence-case titles. Pure helpers only: nothing here writes the save.

func run() -> void:
	var main_gd: Script = load("res://scripts/main.gd")

	# ---- Pass & Play seats and names (cfg.names: [4] by colour) ----
	check("ludo seats: 2 sit opposite", SetupSheet.seat_colors("ludo", 2) == [0, 2], SetupSheet.seat_colors("ludo", 2))
	check("ludo seats: 3 and 4", SetupSheet.seat_colors("ludo", 3) == [0, 1, 2] and SetupSheet.seat_colors("ludo", 4) == [0, 1, 2, 3])
	check("s&l seats: the first n colours", SetupSheet.seat_colors("sl", 3) == [0, 1, 2], SetupSheet.seat_colors("sl", 3))
	check("default names: Player 2...", SetupSheet.default_name(1) == "Player 2" and SetupSheet.default_name(3) == "Player 4")
	check("names are trimmed and capped", SetupSheet.clean_name("  Rafi   the   Great Khan ") == "Rafi the Gre", SetupSheet.clean_name("  Rafi   the   Great Khan "))
	var n2 := SetupSheet.names_by_color("ludo", 2, ["Ana", "  Bo "])
	check("ludo 2 players: names by colour (Red, Yellow)", n2 == ["Ana", "", "Bo", ""], n2)
	var n3 := SetupSheet.names_by_color("ludo", 3, ["Ana", "", "Cy", "ignored"])
	check("an empty name gets its seat's default", n3[0] == "Ana" and n3[1] == "Player 2" and n3[2] == "Cy" and n3[3] == "", n3)
	var nsl := SetupSheet.names_by_color("sl", 2, [])
	check("s&l: names by colour, defaults filled", nsl[1] == "Player 2" and nsl[2] == "" and nsl[3] == "" and nsl[0] != "", nsl)

	var lc: Dictionary = main_gd.setup_config("ludo", "local", {count = 2, names = ["Ana", "Bo"]})
	check("Play again: Ludo Pass & Play keeps the names", lc.players == ["human", "off", "human", "off"] and lc.names == ["Ana", "", "Bo", ""], lc)
	var sc: Dictionary = main_gd.setup_config("sl", "local", {count = 3, names = ["", "Bo", "Cy"]})
	check("Play again: S&L Pass & Play keeps the names", sc.n == 3 and sc.names[1] == "Bo" and sc.names[2] == "Cy" and sc.names[0] != "", sc)
	var cc: Dictionary = main_gd.setup_config("sl", "cpu", {count = 2})
	check("vs computer: no names", not cc.has("names"), cc)
	var old: Dictionary = main_gd.setup_config("ludo", "local", {count = 4})
	check("an old setup without names: the defaults", old.names[1] == "Player 2" and old.names[3] == "Player 4", old)
	var kept: Dictionary = main_gd._ludo_cfg_of({S = {players = ["human", "off", "human", "off"], names = ["Ana", "", "Bo", ""], teams = false}})
	check("a resumed Pass & Play match keeps its names for Restart", kept.get("names") == ["Ana", "", "Bo", ""], kept)

	# ---- the daily calendar: TOMORROW on day + 1, no status on later days ----
	var list := []
	for k in 7:
		list.append({status = "claimed" if k < 2 else ("today" if k == 2 else "locked")})
	check("claimable today (day 3): tomorrow is day 4", DailySheet.tomorrow_index({claimable = true, today = 2, claimed = 2, rewards = list}) == 3)
	for k in 7:
		list[k].status = "claimed" if k < 3 else "locked"
	check("claimed today (day 3): tomorrow is day 4", DailySheet.tomorrow_index({claimable = false, today = -1, claimed = 3, rewards = list}) == 3)
	for k in 7:
		list[k].status = "claimed"
	check("the week is done: no tomorrow tile", DailySheet.tomorrow_index({claimable = false, today = -1, claimed = 7, rewards = list}) == -1)
	check("status lines", DailySheet.status_text("today", false) == "TODAY" and DailySheet.status_text("claimed", false) == "CLAIMED"
		and DailySheet.status_text("locked", true) == "TOMORROW" and DailySheet.status_text("locked", false) == "")

	# ---- Home: the switch's two-line fallback; the meter's numbers never overflow ----
	check("switch label on two lines", HomeScreen._two_lines("Snakes & Ladders") == "Snakes &\nLadders" and HomeScreen._two_lines("Ludo") == "Ludo")
	var f := UIKit.font_body(900, true)
	check("meter numbers: as is when they fit", Meter.fitted_text("140 / 150", f, 12, 200.0) == "140 / 150")
	var tight := f.get_string_size("140/150", HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 1.0
	check("meter numbers: compact when tight", Meter.fitted_text("140 / 150 XP", f, 12, tight) == "140/150", Meter.fitted_text("140 / 150 XP", f, 12, tight))
	check("meter numbers: none when nothing fits", Meter.fitted_text("140 / 150", f, 12, 10.0) == "")

	# ---- copy: sentence case titles; the Rewards rows read like their sheets ----
	var src := FileAccess.get_file_as_string("res://scripts/ui/setup_sheet.gd")
	check("setup title: Play vs computer", src.contains("\"Play vs computer\"") and not src.contains("\"Play vs Computer\""))
	var spin := FileAccess.get_file_as_string("res://scripts/ui/sheets/spin_sheet.gd")
	var daily := FileAccess.get_file_as_string("res://scripts/ui/sheets/daily_sheet.gd")
	check("sheet titles: Daily spin / Daily reward", spin.contains("\"Daily spin\"") and daily.contains("\"Daily reward\"") and not daily.contains("\"LOCKED\""))
	var rewards := FileAccess.get_file_as_string("res://scripts/ui/sheets/rewards_sheet.gd")
	check("rewards sheet rows read like their sheets: Daily spin / Daily reward", rewards.contains("daily = [\"Daily reward\"") and rewards.contains("spin = [\"Daily spin\""))
	var main_src := FileAccess.get_file_as_string("res://scripts/main.gd")
	check("free coins: Fmt.until, never the ticking clock", main_src.contains("\"Free coins in %s\") % Fmt.until(left)"))
	check("home switch drives the backdrop", main_src.contains("home.game_switched.connect(_on_game_switched)") and not main_src.contains("SLLanding.new()"))
