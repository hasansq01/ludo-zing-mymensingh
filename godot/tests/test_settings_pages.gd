extends "res://tests/test_suite.gd"
## SettingsSheet: four pages behind tabs, every option on one of them, one showing at a time.

func _ok_page(s: SettingsSheet, name_: String, page: String) -> bool:
	var n := s.find_child(name_, true, false)
	var pg := s.scroll_body.find_child("Page_" + page, true, false)
	return n != null and pg != null and pg.is_ancestor_of(n)

var _root: Node

func run() -> void:
	_root = (Engine.get_main_loop() as SceneTree).root
	var s := SettingsSheet.new()
	_root.add_child(s)
	check("settings: four pages", SettingsSheet.PAGES.map(func(p: Dictionary) -> String: return p.key) == ["general", "game", "alerts", "more"] and s._pages.size() == 4)
	check("settings: opens on General, the others hidden", s.page == "general" and s._pages.general.visible and not s._pages.game.visible and not s._pages.alerts.visible and not s._pages.more.visible)
	check("settings: Graphics is on Game", _ok_page(s, "Graphics", "game"))
	check("settings: Rate and the version line are on More", _ok_page(s, "RateGame", "more") and _ok_page(s, "VersionLine", "more"))
	s.show_page("alerts")
	check("settings: a tab shows its page alone", s.page == "alerts" and s._pages.alerts.visible and not s._pages.general.visible and s._tabs.selected == "alerts")
	s.show_page("nope")
	check("settings: an unknown page changes nothing", s.page == "alerts")
	s._build()
	check("settings: rebuilt (a new language): the same page stays", s.page == "alerts" and s._pages.alerts.visible and not s._pages.general.visible)
	s.free()
