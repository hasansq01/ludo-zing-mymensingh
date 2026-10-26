extends SceneTree
## Runs every rule test suite headless and exits with 1 when any check fails:
##   godot --headless --path godot -s res://tests/run_tests.gd
## (or tools/godot-test.sh from the repo root).

const SUITES := [
	"res://tests/test_pair_rules.gd",
	"res://tests/test_team_rules.gd",
	"res://tests/test_pair_capture_split.gd",
	"res://tests/test_snakes_ladders.gd",
	"res://tests/test_sl_rewards.gd",
	"res://tests/test_ludo_flow.gd",
	"res://tests/test_ludo_standings.gd",
	"res://tests/test_play_on.gd",
	"res://tests/test_play_on_client.gd",
	"res://tests/test_bot_levels.gd",
	"res://tests/test_tutorial.gd",
	"res://tests/test_save_prefs.gd",
	"res://tests/test_shop.gd",
	"res://tests/test_rewards.gd",
	"res://tests/test_collection.gd",
	"res://tests/test_sl_scenes.gd",
	"res://tests/test_info.gd",
	"res://tests/test_match_store.gd",
	"res://tests/test_fmt.gd",
	"res://tests/test_components_a.gd",
	"res://tests/test_components_b.gd",
	"res://tests/test_lobby.gd",
	"res://tests/test_home.gd",
	"res://tests/test_thumbs.gd",
	"res://tests/test_quality.gd",
	"res://tests/test_state_hash.gd",
	"res://tests/test_sl_state_hash.gd",
	"res://tests/test_net.gd",
	"res://tests/test_net_ui.gd",
	"res://tests/test_net_online.gd",
	"res://tests/test_net_ping.gd",
	"res://tests/test_play_games.gd",
	"res://tests/test_notifier.gd",
	"res://tests/test_billing.gd",
	"res://tests/test_ads.gd",
	"res://tests/test_account.gd",
	"res://tests/test_account_ui.gd",
	"res://tests/test_econ_wallet.gd",
	"res://tests/test_emote_art.gd",
	"res://tests/test_emote_shop.gd",
	"res://tests/test_emote_sfx.gd",
	"res://tests/test_emotes_hud.gd",
	"res://tests/test_notif_plan.gd",
	"res://tests/test_back_online.gd",
	"res://tests/test_coin_tables.gd",
	"res://tests/test_reroll.gd",
	"res://tests/test_notifications.gd",
]

## Suites whose run() is a coroutine that the runner waits for (the others run to their first wait, as before).
const ASYNC_SUITES := ["res://tests/test_reroll.gd"]

func _initialize() -> void:
	await process_frame                       # the info-bubble checks need a live scene tree
	var failed := 0
	var total := 0
	for path in SUITES:
		var suite = load(path).new()
		if path in ASYNC_SUITES:
			await suite.run()                  # (waits for frames: the live match tests)
		else:
			suite.run()
		var bad: Array = suite.results.filter(func(r): return not r.ok)
		total += suite.results.size()
		failed += bad.size()
		print("%s: %d passed, %d failed" % [path.get_file(), suite.results.size() - bad.size(), bad.size()])
		for r in bad:
			print("  FAIL %s  got %s" % [r.name, r.got])
	print("TOTAL: %d passed, %d failed" % [total - failed, failed])
	quit(1 if failed else 0)
