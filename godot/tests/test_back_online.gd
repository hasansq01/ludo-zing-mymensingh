extends "res://tests/test_suite.gd"
## Coming back to an online match (server/NOTIFICATIONS.md, the "It's your turn" tap): the app back in front means the
## player is back, so the seat a bot took over while the phone was away is taken back without an "I’m back" tap, and
## main.gd opens no pause menu over an online board. Snakes & Ladders' match with a fake connection (Ludo's
## app_resumed / _net_badges are the same code).

## Records what the match sends.
class FakeNet extends RefCounted:
	var sent: Array = []
	var member_id := "1"
	func send_msg(m: Dictionary) -> bool:
		sent.append(m)
		return true

func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree

func _fake_app() -> Node:
	var s := GDScript.new()
	s.source_code = "extends Node\nvar safe_top := 0.0\nvar safe_bottom := 0.0\nvar paused := false\nvar speed := 1.0\nvar ludo: Variant = null\nvar sl: Variant = null\nvar screen := \"sl\"\n"
	s.reload()
	return s.new()

func backs(n: FakeNet) -> int:
	return n.sent.filter(func(m): return m.t == "back").size()

func run() -> void:
	var app := _fake_app()
	_tree().root.add_child(app)
	var parent := Control.new()
	parent.size = Vector2(390, 844)
	app.add_child(parent)
	var m := SLMatch.new(app, null, null)
	app.add_child(m)
	m.build_hud(parent)
	m.emotes.mute = true
	m.G = SnakesLaddersRules.new_game("cpu", 2, 0)
	m._build_tiles()
	var net := FakeNet.new()
	m.net = net
	m.online = true
	m.ns = NetSL.new()
	m.ns.S = m.G
	m.ns.me = int(m.G.players[0].c)
	m.G.players[0].you = true
	m.G.players[0].cpu = true                     # a bot plays your seat (you were away)

	m._net_badges()
	check("away: the prompt with I’m back, nothing sent by itself", m.away_box.visible and backs(net) == 0)
	m.app_resumed()
	check("back in the app: the seat is asked back at once", backs(net) == 1)
	m._net_badges()
	check("... and a bot still on the seat (acts not caught up) is sent away once, no prompt", backs(net) == 2 and not m.away_box.visible)
	m._net_badges()
	check("... only once", backs(net) == 2)
	m._show_away(false)
	m._back_until = Time.get_ticks_msec() + SLMatch.BACK_WINDOW_MS
	m.G.players[0].cpu = false
	m._net_badges()
	check("the seat already yours: nothing sent, no prompt", backs(net) == 2 and not m.away_box.visible)
	m._back_until = 0
	m.G.players[0].cpu = true                     # idle on screen later: missed turns, a bot again
	m._net_badges()
	check("a bot later, while you are on screen: the I’m back prompt as before", m.away_box.visible and backs(net) == 2)
	m.online = false
	m.app_resumed()
	check("offline games send nothing", backs(net) == 2)

	var main_src := FileAccess.get_file_as_string("res://scripts/main.gd")
	check("main: an online match opens no pause menu when the app goes to the background",
		main_src.contains("if screen in [\"ludo\", \"sl\"] and not _online_match():\n\t\t\t\topen_pause()"))
	check("main: back in front during an online match -> app_resumed()", main_src.contains(".app_resumed()"))
	m.free()
	app.queue_free()
	_tree().root.remove_child(app)
