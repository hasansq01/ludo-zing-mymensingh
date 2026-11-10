class_name UpdateBanner
extends PanelContainer
## The in-app update banner (AppUpdate): the game look's popup card (GameUI.card_style: dark café with a warm glow, a
## gold rim, a 3D lip), at most W_MAX wide with the 12 px gutters, sliding down from the top edge under the safe area,
## z over the sheets. The title in outlined white, the line in cream, the bar gold on a dark track (Meter "game"),
## chunky Later (cream) / Update or Restart (gold) buttons.
## Three modes, set with set_mode():
##   "offer"        "A new version is available" and Later / Update
##   "downloading"  "Downloading the update…" with a progress bar (and "You can keep playing."), no buttons
##   "ready"        "Update ready" and Later / Restart
##
##   var b := UpdateBanner.new("offer")
##   b.update_pressed.connect(...); b.later_pressed.connect(...); b.restart_pressed.connect(...)
##   app.ui_root.add_child(b); b.show_in(app.safe_top)
##   b.set_mode("downloading", bytes, total)   # progress; "ready" when it is done
##   b.dismiss()                               # slides away and frees itself

signal update_pressed
signal later_pressed
signal restart_pressed

const W_MAX := 380.0
const Z := 40                            ## over the sheets (10) and the splash (20), under the coin flights (50)
const IN_SEC := 0.28

var mode := ""
var title_label: Label
var sub_label: Label
var bar: Meter
var later_button: Button
var action_button: Button                ## Update (offer) or Restart (ready)
var buttons: HBoxContainer

var _top := 0.0
var _gone := false


func _init(mode_ := "offer") -> void:
	name = "UpdateBanner"
	z_index = Z
	mouse_filter = Control.MOUSE_FILTER_STOP
	var st := GameUI.card_style()
	st.content_margin_left = 16; st.content_margin_right = 16; st.content_margin_top = 14
	st.content_margin_bottom = 14 + GameUI.CardStyle.LIP
	add_theme_stylebox_override("panel", st)
	var col := UIKit.vbox(UIKit.SPACE.sm)
	add_child(col)
	var text := UIKit.vbox(0)
	title_label = GameUI.outlined("", 19, GameUI.TEXT, 2)
	title_label.name = "Title"
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(title_label)
	sub_label = GameUI.text("", UIKit.FS.label, GameUI.SUB)
	sub_label.name = "Sub"
	sub_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(sub_label)
	col.add_child(text)
	bar = Meter.new("game", 12.0)
	bar.name = "Progress"
	col.add_child(bar)
	buttons = UIKit.hbox(UIKit.SPACE.sm)
	later_button = GameUI.button(L10n.t("Later"), "cream", "md")
	later_button.name = "Later"
	action_button = GameUI.button(L10n.t("Update"), "gold", "md")
	action_button.name = "Action"
	for b: Button in [later_button, action_button]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		GameUI.fit_button_text(b as GameUI.GameButton, 13)
		buttons.add_child(b)
	later_button.pressed.connect(func() -> void:
		if not _gone:
			later_pressed.emit())
	action_button.pressed.connect(func() -> void:
		if _gone:
			return
		if mode == "ready":
			restart_pressed.emit()
		else:
			update_pressed.emit())
	col.add_child(buttons)
	set_mode(mode_)
	minimum_size_changed.connect(func() -> void: _shrink.call_deferred())

## The texts and parts of a mode. "downloading" shows bytes / total as the bar (and a percentage once the size is known).
func set_mode(mode_: String, bytes := 0, total := 0) -> void:
	mode = mode_ if mode_ in ["offer", "downloading", "ready"] else "offer"
	match mode:
		"offer":
			title_label.text = L10n.t("A new version is available")
			sub_label.text = L10n.t("It downloads while you keep playing.")
			action_button.text = L10n.t("Update")
		"downloading":
			title_label.text = L10n.t("Downloading the update…")
			sub_label.text = progress_text(bytes, total)
		"ready":
			title_label.text = L10n.t("Update ready")
			sub_label.text = L10n.t("Restart Ludo Zing to finish updating.")
			action_button.text = L10n.t("Restart")
	bar.visible = mode == "downloading"
	buttons.visible = mode != "downloading"
	if mode == "downloading":
		bar.set_value(float(bytes), float(total) if total > 0 else 1.0, true)
	if is_inside_tree():
		_place()

## "You can keep playing." until the size is known, then "42%".
static func progress_text(bytes: int, total: int) -> String:
	if total <= 0:
		return L10n.t("You can keep playing.")
	return "%d%%" % clampi(int(round(100.0 * bytes / total)), 0, 100)

## Slide in below `safe_top` (UI px), centred, at most W_MAX wide.
func show_in(safe_top := 0.0) -> void:
	_top = safe_top + UIKit.SPACE.sm
	_place()
	var vp := get_viewport()
	if vp and not vp.size_changed.is_connected(_place):
		vp.size_changed.connect(_place)
	var end_y := position.y
	position.y = -size.y - 8.0
	if Sheet.reduce_motion():
		position.y = end_y
		return
	var tw := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "position:y", end_y, IN_SEC)

func _place() -> void:
	var host := get_parent() as Control
	var w := (host.size.x if host else get_viewport_rect().size.x)
	var bw := minf(W_MAX, w - 2.0 * UIKit.GUTTER)
	custom_minimum_size.x = bw
	size = Vector2(bw, 0)
	reset_size()
	position.x = (w - size.x) / 2.0
	if _top > 0.0 and position.y >= 0.0:
		position.y = _top
	_shrink.call_deferred()

## The wrapping lines are measured one glyph wide until the card has its width, which made the first height far too
## tall (a Control never gives height back on its own): once laid out, the card takes its real height.
func _shrink() -> void:
	if is_inside_tree() and not _gone:
		size = Vector2(size.x, get_combined_minimum_size().y)

## Slide away and free.
func dismiss() -> void:
	if _gone:
		return
	_gone = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not is_inside_tree() or Sheet.reduce_motion():
		queue_free()
		return
	var tw := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "position:y", -size.y - 8.0, 0.2)
	tw.tween_callback(queue_free)
