class_name SLLanding
extends Control
## RETIRED from the app: main.gd no longer builds it. Snakes & Ladders is picked on Home's game switch, which shows
## the equipped S&L scene as the lobby backdrop with a "Change scene" chip (the Shop's Scenes tab). Kept only for the
## standalone dev previews (dev/preview_sl_scenes.gd, dev/preview_sl_match.gd); don't use it in new code.
##
## The Snakes & Ladders landing over its 3D world (index.html #slPage.is-landing / #slLand): the title is the 3D
## hanging sign (SLScenes), so the overlay only holds the GameTopBar ("back" mode: Back, the scene's name in the
## bar, the gear), a "Change scene" shortcut (the Shop's Scenes tab) and the two mode buttons (VS COMPUTER /
## PASS & PLAY, UIKit.mode_button as on Home) near the bottom edge. The rest lets touches through.

signal play(mode: String)                # "cpu" | "local"
signal back
signal settings
signal change_scene                      # main may connect it; unconnected, the landing opens the Shop itself

const SHOP_SHEET := "res://scripts/ui/sheets/shop_sheet.gd"

var safe_top := 0.0
var safe_bottom := 0.0
var top: GameTopBar
var _scene_btn: Button
var _modes: HBoxContainer
var _scene_name := ""

func _init() -> void:
	name = "SLLanding"

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	top = GameTopBar.new("back")
	top.name = "TopBar"
	top.left_pressed.connect(func(): back.emit())
	top.gear_pressed.connect(func(): settings.emit())
	add_child(top)
	top.bar.minimum_size_changed.connect(_shrink_bar.call_deferred)
	_scene_btn = UIKit.button_with("Change scene", UIKit.icon("cat_scenes", 22), "white", "sm")
	_scene_btn.name = "ChangeScene"
	_scene_btn.pressed.connect(_on_change_scene)
	add_child(_scene_btn)
	_modes = UIKit.hbox(UIKit.SPACE.md)
	var cpu := UIKit.mode_button("VS COMPUTER", "honey", "robot")
	cpu.pressed.connect(func(): play.emit("cpu"))
	_modes.add_child(cpu)
	var loc := UIKit.mode_button("PASS & PLAY", "teal", "two_pawns")
	loc.pressed.connect(func(): play.emit("local"))
	_modes.add_child(loc)
	add_child(_modes)
	resized.connect(_layout)
	set_scene_name(SLScenes.info(SLScenes.scene_in_use()).get("name", ""))
	_layout()
	visibility_changed.connect(func():
		if is_visible_in_tree() and TapLog.enabled():
			TapLog.points([cpu, loc, _scene_btn]))

## The scene on show, named in the top bar; "" leaves the bar empty.
func set_scene_name(text: String) -> void:
	_scene_name = text
	if top == null:
		return
	if text == "":
		top.clear()
	else:
		top.set_idle("[b]%s[/b]" % text)

func set_safe_area(top_: float, bottom_: float) -> void:
	safe_top = top_
	safe_bottom = bottom_
	_layout()

func _on_change_scene() -> void:
	if change_scene.get_connections().size() > 0:
		change_scene.emit()
		return
	var main := _main()
	if main == null:
		return
	if ResourceLoader.exists(SHOP_SHEET) and "sheet_layer" in main:
		var script := load(SHOP_SHEET) as Script
		if script and script.can_instantiate():
			var s: Node = script.new("scenes")
			if main.has_method("apply_shop_changes"):
				main.call("apply_shop_changes", s)
			elif main.has_method("_wire_shop"):
				main.call("_wire_shop", s)
			s.call("open", main.get("sheet_layer"))
			return
	if main.has_method("_on_tab"):
		main.call("_on_tab", "shop")

## The event bar keeps the height it had at its first (narrow) layout; shrink it back to its text.
func _shrink_bar() -> void:
	if is_instance_valid(top) and top.bar:
		top.bar.size = Vector2(top.bar.size.x, 0)

## The app (main.gd): the first ancestor with the sheet layer (the root's "Main" in the game).
func _main() -> Node:
	var n := get_parent()
	while n != null:
		if n.has_method("_on_tab") or n.has_method("apply_shop_changes") or n.has_method("_wire_shop"):
			return n
		n = n.get_parent()
	return get_tree().root.get_node_or_null("Main")

func _layout() -> void:
	if _modes == null:
		return
	var w := size.x
	var h := size.y
	top.safe_top = safe_top
	_shrink_bar.call_deferred()
	var g: float = UIKit.SCREEN_GUTTER
	var mw := minf(w - 2.0 * g, 560.0)
	var mh: float = UIKit.H.xl
	_modes.size = Vector2(mw, mh)
	_modes.position = Vector2(round((w - mw) / 2.0), h - safe_bottom - UIKit.SPACE.xl - mh)
	var bs := _scene_btn.get_combined_minimum_size()
	var row := _scene_btn.get_node_or_null("Content") as Control
	if row:                                  # the content row isn't part of the button's minimum size
		bs.x = maxf(bs.x, row.get_combined_minimum_size().x + 2.0 * float(UIKit.BTN.sm.pad) + 8.0)
	_scene_btn.size = bs
	_scene_btn.position = Vector2(round((w - bs.x) / 2.0), _modes.position.y - UIKit.SPACE.md - bs.y)
