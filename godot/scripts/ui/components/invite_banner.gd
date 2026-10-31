class_name InviteBanner
extends PanelContainer
## The in-app game invite (Social, server/PROTOCOL.md "Recent players, friends and invites"): the sender's avatar in
## its frame with their level, "<Name> invited you", the game and the room, and Not now / Join. It slides down from
## the top edge (under the safe area, above every sheet: z Z) and leaves by itself when the invite expires (`expired`).
## A card in the sheets' cream with a gold rim and the large shadow, at most W_MAX wide with the 12 px gutters.
##
##   var b := InviteBanner.new(invite, now)   # invite: {id, from: {name, avatar, frame, level}, code, game, expires_at}
##   b.join_pressed.connect(...); b.later_pressed.connect(...); b.expired.connect(...)
##   app.ui_root.add_child(b); b.show_in(app.safe_top)
##   b.dismiss()                               # slides away and frees itself

signal join_pressed
signal later_pressed
## The invite ran out while it was showing (it then leaves by itself).
signal expired

const W_MAX := 380.0
const AVA := 48.0
const Z := 40                            ## over the sheets (10) and the splash (20), under the coin flights (50)
const IN_SEC := 0.28

var invite: Dictionary
var title_label: Label
var sub_label: Label
var join_button: Button
var later_button: Button
var left_sec := 0.0                      ## until it expires

var _top := 0.0
var _gone := false


func _init(invite_: Dictionary = {}, now := 0) -> void:
	invite = invite_
	var from: Dictionary = invite.get("from", {}) if invite.get("from") is Dictionary else {}
	var t := now if now > 0 else int(Time.get_unix_time_from_system())
	left_sec = maxf(0.0, float(int(invite.get("expires_at", t + 600)) - t))
	name = "InviteBanner"
	z_index = Z
	mouse_filter = Control.MOUSE_FILTER_STOP
	var st := UIKit.row_style("on").duplicate() as StyleBoxFlat
	st.bg_color = Palette.CARD
	UIKit.shade(st, "lg")
	add_theme_stylebox_override("panel", st)
	var col := UIKit.vbox(UIKit.SPACE.sm)
	add_child(col)
	var top := UIKit.hbox(UIKit.SPACE.md)
	col.add_child(top)
	var av := Control.new()
	av.custom_minimum_size = Vector2(AVA, AVA)
	av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	av.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var a := Collection.make_avatar_of(str(from.get("avatar", "pawn-red")), str(from.get("frame", "classic")), AVA)
	a.mouse_filter = Control.MOUSE_FILTER_IGNORE
	av.add_child(a)
	var lv := LevelBadge.new(maxi(1, int(from.get("level", 1))), "xs")
	lv.position = Vector2(-3.0, AVA - lv.px + 3.0)
	lv.size = Vector2(lv.px, lv.px)
	av.add_child(lv)
	top.add_child(av)
	var text := UIKit.vbox(0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_label = UIKit.label(tr("%s invited you") % L10n.seat_name(str(from.get("name", "Player"))), UIKit.FS.h3, Palette.INK, UIKit.font_body(900))
	title_label.name = "Title"
	title_label.clip_text = true                # one line (names are at most 16 characters): a wrap would size the card for 60 px
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_child(title_label)
	sub_label = UIKit.label(sub_text(invite), UIKit.FS.small, Palette.SUB, UIKit.font_body(800))
	sub_label.name = "Sub"
	sub_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	sub_label.clip_text = true
	text.add_child(sub_label)
	top.add_child(text)
	var row := UIKit.hbox(UIKit.SPACE.sm)
	later_button = UIKit.btn(tr("Not now"), "ghost", "sm")
	later_button.name = "Later"
	join_button = UIKit.btn(tr("Join"), "honey", "sm")
	join_button.name = "Join"
	for b: Button in [later_button, join_button]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UIKit.fit_text(b, 12)
		row.add_child(b)
	later_button.pressed.connect(func():
		if not _gone:
			later_pressed.emit())
	join_button.pressed.connect(func():
		if not _gone:
			join_pressed.emit())
	col.add_child(row)

## "Ludo · Room K7Q X2M".
static func sub_text(inv: Dictionary) -> String:
	var g := L10n.t("Snakes & Ladders") if str(inv.get("game", "ludo")) == "sl" else L10n.t("Ludo")
	return "%s · %s" % [g, L10n.t("Room %s") % LobbySheet.spaced(str(inv.get("code", "")))]

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
	position = Vector2((w - size.x) / 2.0, _top)

func _process(delta: float) -> void:
	if _gone:
		return
	left_sec -= delta
	if left_sec <= 0.0:
		expired.emit()
		dismiss()

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
