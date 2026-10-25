class_name ResultScreen
extends Control
## The full-screen game result over the (blurred, dimmed) board, always headlined from the player's side: on a
## win the winner's avatar with a crown in a burst of gold rays; on a loss your own avatar with your place badge
## ("You finished 3rd", soft rays), the .pm card with the title ribbon, the finish order (1st–4th: place badges, avatars, names, a teal check + "Finished"
## or the progress of the unfinished), the rewards (coins counting up, XP filling the Meter, "Level up!") and the
## buttons Play again (honey, lg) and Home (ghost). Back = Home. Confetti only when the human (or their team) won.
##
##   var r := ResultScreen.new({
##       game = "ludo",                     # "ludo" | "sl"
##       title = "",                        # "" = derived ("You win!", "You finished 3rd", "Your team finished 2nd",
##                                          #   "Mocha wins!" when there is no "you": Pass & Play)
##       sub = "",                          # "" = derived ("All four pawns home!", "Mocha won"); never the XP (the
##                                          #   card shows it once)
##       standings = [{color, name, kind ("you"|"cpu"|"human"), cpu_id, place, finished, progress, pos}],
##       teams = false,                     # optional; derived from shared places
##       human_won = true, reward = 200,
##       xp_before = 120, xp_after = 220,   # total XP before / after this game
##       level_before = 2, level_after = 3, # optional (derived from the XP)
##       coin_target = home_coin_amount,    # optional Control (CoinAmount): coins fly there after the count-up
##       coin_total = 5500,                 # optional: the new balance for that target
##   })
##   r.play_again.connect(...); r.home.connect(...)
##   r.open(app.sheet_layer)
## The screen closes itself after a button (or Back); `closed` fires when it is gone.
## Online (data.online = true, data.host = you host the room): rows carry the friends' own avatars (e.avatar,
## e.frame); Play again is the host's rematch (the screen stays until the server starts it: the app closes it),
## for everyone else a disabled "Waiting for host…" (set_host() when the host changes).

signal play_again
signal home
signal closed

const CARD_W := 358.0
const AVA_HERO := 92.0
const AVA_ROW := 40.0
const ROW_H := 52.0

var data := {}
var dismissable := false                 # Sheet-like: main's back handler must not just close it
var card: PanelContainer
var title_ribbon: Control
var content: VBoxContainer
var again_button: Button
var home_button: Button
var coins: CoinAmount
var xp_meter: Meter
var level_badge: LevelBadge

var _backdrop: ColorRect
var _hero: Control
var _rays: Rays
var _title: Label
var _sub: Label
var _rows: Array[Control] = []
var _rewards: Control
var _body: VBoxContainer
var _claim_note: Label
var _level_up: Control
var _buttons: VBoxContainer
var _closing := false
var _done := false

static var _blur: Shader


func _init(data_: Dictionary = {}) -> void:
	data = data_
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UIKit.theme()
	_build()

## Shows the screen on `layer` (the app's sheet layer) and plays the reveal. Coroutine; callers may ignore it.
func open(layer: Control) -> ResultScreen:
	layer.add_child(self)
	await get_tree().process_frame
	_layout()
	_play()
	return self

## Fades out and frees; emits `closed`. Coroutine.
func close() -> void:
	if _closing:
		return
	_closing = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_inside_tree():
		var tw := create_tween()
		tw.tween_property(self, "modulate:a", 0.0, 0.16)
		await tw.finished
	closed.emit()
	queue_free()

## Back (Android) = Home.
func on_back() -> void:
	_pick("home")

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel") and not _closing:
		get_viewport().set_input_as_handled()
		on_back()


# ---------------------------------------------------------------------------------------------------------------
# Copy
# ---------------------------------------------------------------------------------------------------------------

## The ordinal: 1 -> "1st", 2 -> "2nd" ...
static func ordinal(n: int) -> String:
	var suf := "th"
	if n % 100 < 11 or n % 100 > 13:
		match n % 10:
			1: suf = "st"
			2: suf = "nd"
			3: suf = "rd"
	return "%d%s" % [n, suf]

func standings() -> Array:
	var st: Array = data.get("standings", [])
	var out := st.duplicate()
	out.sort_custom(func(a, b): return int(a.get("place", 9)) < int(b.get("place", 9)) if int(a.get("place", 9)) != int(b.get("place", 9)) else int(a.get("color", 0)) < int(b.get("color", 0)))
	return out

func is_teams() -> bool:
	if data.has("teams"):
		return bool(data.teams)
	var seen := {}
	for e in data.get("standings", []):
		var p := int(e.get("place", 0))
		if seen.has(p):
			return true
		seen[p] = true
	return false

func winners() -> Array:
	return standings().filter(func(e): return int(e.get("place", 0)) == 1)

func you() -> Dictionary:
	for e in data.get("standings", []):
		if str(e.get("kind", "")) == "you":
			return e
	return {}

## Confetti: data.celebrate, else when the human (or their team) won, or in Pass & Play (everyone at the table is
## a human, so somebody here won).
func celebrates() -> bool:
	if data.has("celebrate"):
		return bool(data.celebrate)
	if bool(data.get("human_won", false)):
		return true
	var st: Array = data.get("standings", [])
	return not st.is_empty() and st.all(func(e): return str(e.get("kind", "")) == "human")

func xp_gain() -> int:
	return maxi(0, int(data.get("xp_after", 0)) - int(data.get("xp_before", 0)))

## You lost (you played, and neither you nor your team won).
func you_lost() -> bool:
	return not you().is_empty() and not bool(data.get("human_won", false)) and not winners().is_empty()

## The title: data.title, else from your side ("You win!", "Your team wins!", "You finished 3rd", "Your team finished
## 2nd"), or with no "you" the winner ("Team Red + Yellow wins!", "Mocha wins!").
func title_text() -> String:
	var t := str(data.get("title", ""))
	if t != "":
		return t
	var w := winners()
	if w.is_empty():
		return "Game over"
	if you_lost():
		var place := ordinal(maxi(int(you().get("place", 2)), 2))
		return ("Your team finished %s" if is_teams() else "You finished %s") % place
	if is_teams():
		if w.any(func(e): return str(e.get("kind", "")) == "you"):
			return "Your team wins!"
		var cols := w.map(func(e): return int(e.color))
		cols.sort()
		return "Team %s wins!" % " + ".join(cols.map(func(c): return Palette.NAMES[c]))
	if str(w[0].get("kind", "")) == "you":
		return "You win!"
	return "%s wins!" % str(w[0].get("name", Palette.NAMES[int(w[0].color)]))

## The line under the title: data.sub, else what happened ("All four pawns home!") or, for a loss, who won
## ("Mocha won", "Team Green + Blue won"). The XP is not repeated here (the card shows it).
func sub_text() -> String:
	var s := str(data.get("sub", ""))
	if s != "":
		return s
	if you_lost():
		return "%s won" % winner_label()
	if str(data.get("game", "ludo")) == "sl":
		return "First to square 100!"
	if is_teams():
		return "Both teammates got all four pawns home!"
	return "All four pawns home!"

## "Mocha" / "Team Green + Blue": who won, for the copy.
func winner_label() -> String:
	var w := winners()
	if w.is_empty():
		return ""
	if is_teams():
		var cols := w.map(func(e): return int(e.color))
		cols.sort()
		return "Team " + " + ".join(cols.map(func(c): return Palette.NAMES[c]))
	return str(w[0].get("name", Palette.NAMES[int(w[0].color)]))

## Whose avatars the hero shows: the winners, or on a loss you (and your teammate).
func hero_rows() -> Array:
	if not you_lost():
		return winners()
	var me := you()
	var out := []
	for e: Dictionary in standings():
		if int(e.get("place", 0)) == int(me.get("place", 0)) and (str(e.get("kind", "")) == "you" or is_teams()):
			out.append(e)
	return out


# ---------------------------------------------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------------------------------------------

func _build() -> void:
	_backdrop = ColorRect.new()
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop.material = _blur_material()
	add_child(_backdrop)
	var won := bool(data.get("human_won", false))
	content = UIKit.vbox(0)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(content)
	# hero: rays + winner avatar(s) + crown
	_hero = Control.new()
	_hero.custom_minimum_size = Vector2(CARD_W, AVA_HERO + 72)
	_hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(_hero)
	_rays = Rays.new()
	_rays.gold = won or you().is_empty()
	if _rays.gold:
		var add := CanvasItemMaterial.new()
		add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_rays.material = add
	_hero.add_child(_rays)
	var w := hero_rows()
	var lost := you_lost()
	var n := clampi(w.size(), 1, 2)
	var ava_px := AVA_HERO if n == 1 else AVA_HERO - 12.0
	var avs := Control.new()
	avs.name = "Avatars"
	avs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hero.add_child(avs)
	for i in n:
		var e: Dictionary = w[i] if i < w.size() else {}
		var mount := _avatar_mount(e, ava_px)
		mount.position = Vector2(i * (ava_px + 10.0), 0)
		avs.add_child(mount)
		if lost:                             # your place on your avatar instead of the winner's crown
			var pb := PlayerTile.PlaceBadge.make(int(e.get("place", 2)), 34)
			pb.name = "Place%d" % i
			pb.position = Vector2(-12, -12)
			mount.add_child(pb)
	avs.size = Vector2(n * ava_px + (n - 1) * 10.0, ava_px)
	var crown := UIKit.icon("ic_crown", 52)
	crown.name = "Crown"
	crown.size = Vector2(52, 52)
	avs.add_child(crown)
	crown.position = Vector2(avs.size.x / 2.0 - 26.0, -38.0)
	crown.pivot_offset = Vector2(26, 40)
	crown.rotation = deg_to_rad(-8.0)
	crown.visible = not lost
	content.add_child(_gap(6))
	# card: ribbon title, sub line, standings, rewards
	card = PanelContainer.new()
	card.add_theme_stylebox_override("panel", Sheet.PMStyle.new())
	var pm := card.get_theme_stylebox("panel")
	pm.content_margin_left = 14; pm.content_margin_right = 14
	pm.content_margin_top = 34; pm.content_margin_bottom = 16
	card.custom_minimum_size = Vector2(CARD_W, 0)
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(card)
	var body := UIKit.vbox(UIKit.SPACE.sm)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(body)
	_body = body
	_sub = UIKit.label(sub_text(), UIKit.FS.body_l, Palette.INK, UIKit.font_body(800), HORIZONTAL_ALIGNMENT_CENTER)
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_sub)
	var list := UIKit.vbox(UIKit.SPACE.xs + 2)
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(list)
	var teams := is_teams()
	var last_place := -1
	for e: Dictionary in standings():
		if teams and int(e.get("place", 0)) != last_place:
			var cap := UIKit.caption(_team_caption(e))
			cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			list.add_child(UIKit.margin(cap, 6, 2 if last_place < 0 else 4, 0, 0))
		last_place = int(e.get("place", 0))
		var row := _row(e)
		list.add_child(row)
		_rows.append(row)
	_rewards = _rewards_row()
	body.add_child(_rewards)
	title_ribbon = RibbonTitle.new(title_text())
	title_ribbon.name = "Ribbon"
	add_child(title_ribbon)
	_title = (title_ribbon as RibbonTitle).label
	content.add_child(_gap(UIKit.SPACE.lg))
	_buttons = UIKit.vbox(UIKit.SPACE.sm)
	_buttons.custom_minimum_size = Vector2(CARD_W - 20.0, 0)
	_buttons.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	again_button = UIKit.btn("Play again", "honey", "lg")
	again_button.pressed.connect(_pick.bind("again"))
	_buttons.add_child(again_button)
	home_button = UIKit.btn("Home", "ghost", "md")
	home_button.pressed.connect(_pick.bind("home"))
	_buttons.add_child(home_button)
	content.add_child(_buttons)
	if is_online():
		set_host(bool(data.get("host", false)))
	resized.connect(_layout)

## A quiet line under the rewards when the server cut the payout of an offline match ("Daily limit reached"; see
## Account.claim_note). Safe to call late or twice; "" removes it.
func set_claim_note(text: String) -> void:
	if _body == null:
		return
	if text == "":
		if _claim_note:
			_claim_note.queue_free()
			_claim_note = null
		return
	if _claim_note == null:
		_claim_note = UIKit.label(text, UIKit.FS.small, Palette.MUTED, UIKit.font_body(800), HORIZONTAL_ALIGNMENT_CENTER)
		_claim_note.name = "ClaimNote"
		_claim_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_claim_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_body.add_child(_claim_note)
	_claim_note.text = text

func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

func _team_caption(e: Dictionary) -> String:
	var mates := standings().filter(func(x): return int(x.get("place", 0)) == int(e.get("place", 0)))
	var cols := mates.map(func(x): return int(x.color))
	cols.sort()
	var label := " + ".join(cols.map(func(c): return Palette.NAMES[c]))
	return "%s · %s" % [ordinal(int(e.get("place", 1))), label]

## An avatar in a white mount ring in the player's colour (hero).
func _avatar_mount(e: Dictionary, px: float) -> Control:
	var c := int(e.get("color", 0))
	var holder := Panel.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.size = Vector2(px, px)
	var st := UIKit.box(Color.WHITE, int(px * 0.3) + 4, UIKit.BW.card, Palette.PLAYER[c])
	st.shadow_size = 12
	st.shadow_color = Color(Palette.SHADOW_DEEP, 0.35)
	st.shadow_offset = Vector2(0, 6)
	st.expand_margin_left = 5; st.expand_margin_right = 5; st.expand_margin_top = 5; st.expand_margin_bottom = 5
	holder.add_theme_stylebox_override("panel", st)
	var a := _make_avatar(e, px)
	a.size = Vector2(px, px)
	holder.add_child(a)
	return holder

## A row's / the hero's avatar: an online friend's own avatar, else PlayerTile's (you, a mascot, a pawn tile).
static func _make_avatar(e: Dictionary, px: float) -> Control:
	var c := int(e.get("color", 0))
	var id := str(e.get("avatar", ""))
	if str(e.get("kind", "")) == "human" and id != "" and not Collection.avatar(id).is_empty():
		return Collection.make_avatar_of(id, str(e.get("frame", "classic")) if str(e.get("frame", "")) != "" else "classic", px)
	return PlayerTile.make_avatar(c, str(e.get("kind", "cpu")), px, str(e.get("cpu_id", e.get("name", ""))))

func is_online() -> bool:
	return bool(data.get("online", false))

## Online: the host may start the rematch; everyone else waits for them.
func set_host(on: bool) -> void:
	data.host = on
	if again_button == null:
		return
	var waiting := is_online() and not on
	again_button.text = "Waiting for host…" if waiting else "Play again"
	UIKit.set_kind(again_button, "off" if waiting else "honey")
	again_button.disabled = waiting or home_button.disabled   # (home is enabled once the screen has played in)

func _row(e: Dictionary) -> Control:
	var c := int(e.get("color", 0))
	var place := int(e.get("place", 0))
	var first := place == 1
	var mine := str(e.get("kind", "")) == "you"
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := UIKit.box(Palette.HONEY_TINT if first else Color.WHITE, UIKit.R.md, UIKit.BW.line,
		Palette.GOLD if first else (Palette.PLAYER[c] if mine else Palette.ROW_EDGE))
	st.border_width_bottom = UIKit.LIP.sm
	UIKit.pad(st, 8, 4)
	st.content_margin_bottom = 4 + UIKit.LIP.sm - UIKit.BW.line
	p.add_theme_stylebox_override("panel", st)
	p.custom_minimum_size = Vector2(0, ROW_H)
	var row := UIKit.hbox(UIKit.SPACE.sm)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(row)
	var badge := PlayerTile.PlaceBadge.make(place, 28)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(badge)
	var a := _make_avatar(e, AVA_ROW)
	a.custom_minimum_size = Vector2(AVA_ROW, AVA_ROW)
	a.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(a)
	var name_box := UIKit.hbox(UIKit.SPACE.xs + 2)
	name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nm := UIKit.label(str(e.get("name", Palette.NAMES[c])), UIKit.FS.h3, PlayerTile.name_color(c) if not mine else Palette.INK, UIKit.font_body(900))
	nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var tw_ := UIKit.font_body(900).get_string_size(nm.text, HORIZONTAL_ALIGNMENT_LEFT, -1, UIKit.FS.h3).x + 2.0
	nm.custom_minimum_size.x = minf(tw_, 118.0)       # a trimmed Label reports no width of its own
	name_box.add_child(nm)
	if str(e.get("kind", "")) == "cpu":
		var tag := UIKit.tag("CPU", "ink")
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		name_box.add_child(tag)
	row.add_child(name_box)
	row.add_child(_result_cell(e))
	return p

## Right side of a row: a teal check + "Finished" (home in Ludo, square 100 in S&L) or the progress of the unfinished.
func _result_cell(e: Dictionary) -> Control:
	var sl := str(data.get("game", "ludo")) == "sl"
	var box := UIKit.hbox(UIKit.SPACE.xs + 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if bool(e.get("finished", false)):
		box.add_theme_constant_override("separation", UIKit.SPACE.xs)
		box.add_child(_check_disc(18.0))
		var f := UIKit.label("Finished", UIKit.FS.label, Palette.TEAL_INK, UIKit.font_body(900), HORIZONTAL_ALIGNMENT_RIGHT)
		f.name = "Finished"
		f.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		box.add_child(f)
		return box
	var prog := float(e.get("progress", 0.0))
	var m := Meter.new("teal", 8)
	m.custom_minimum_size = Vector2(56, 8)
	m.set_value(prog, 1.0)
	m.size_flags_horizontal = Control.SIZE_SHRINK_END
	box.add_child(m)
	var txt := ("Sq %d" % int(e.get("pos", roundi(prog * 100.0)))) if sl else Fmt.pct(prog)
	var l := UIKit.label(txt, UIKit.FS.label, Palette.SUB, UIKit.font_body(900, true), HORIZONTAL_ALIGNMENT_RIGHT)
	l.custom_minimum_size.x = 40 if not sl else 46
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(l)
	return box

## A teal disc with the white check (a finished player).
func _check_disc(px: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(px, px)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var check := UIKit.svg("ic_check")
	c.draw.connect(func() -> void:
		var m := c.size / 2.0
		c.draw_circle(m, px / 2.0, Palette.TEAL, true, -1.0, true)
		if check:
			var g := px * 0.68
			c.draw_texture_rect(check, Rect2(m - Vector2(g, g) / 2.0, Vector2(g, g)), false))
	return c

func _rewards_row() -> Control:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 0)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(_gap(UIKit.SPACE.xs))
	var row := UIKit.hbox(UIKit.SPACE.sm)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(row)
	var reward := int(data.get("reward", 0))
	if reward > 0:
		var tile := _reward_tile()
		tile.custom_minimum_size.x = 112
		var v := UIKit.vbox(2)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cap := UIKit.eyebrow("Coins")
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(cap)
		coins = CoinAmount.new(0, "lg", "plain", "+")
		coins.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(coins)
		tile.add_child(v)
		row.add_child(tile)
	if xp_gain() <= 0:                      # Pass & Play without XP, or nothing earned: no empty bar
		row.visible = reward > 0
		_level_up = Control.new()
		_level_up.visible = false
		wrap.add_child(_level_up)
		xp_meter = null
		return wrap
	var xt := _reward_tile()
	xt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var xv := UIKit.vbox(4)
	xv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var head := UIKit.hbox(UIKit.SPACE.xs)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cap2 := UIKit.eyebrow("Experience")
	cap2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(cap2)
	var gain := UIKit.label("+%d XP" % xp_gain(), UIKit.FS.label, Palette.TEAL_INK, UIKit.font_body(900, true))
	head.add_child(gain)
	xv.add_child(head)
	var lb := _levels()
	level_badge = LevelBadge.new(int(lb.x), "md")
	xp_meter = Meter.new("xp", 18, true, "XP")
	var info := Collection.level_info(int(data.get("xp_before", 0)))
	xp_meter.set_value(float(info.into), float(info.need))
	xv.add_child(LevelBadge.row(level_badge, xp_meter))
	xt.add_child(xv)
	row.add_child(xt)
	_level_up = UIKit.tag("Level up!", "gold", UIKit.FS.label)
	_level_up.visible = false
	_level_up.top_level = false
	xt.add_child(_level_up)
	return wrap

func _reward_tile() -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := UIKit.box(Palette.PANE, UIKit.R.md, UIKit.BW.line, Palette.ROW_EDGE)
	UIKit.pad(st, 10, 8)
	p.add_theme_stylebox_override("panel", st)
	p.custom_minimum_size.y = 74
	return p

## (level before, level after).
func _levels() -> Vector2i:
	var b := int(data.get("level_before", Collection.level_info(int(data.get("xp_before", 0))).level))
	var a := int(data.get("level_after", Collection.level_info(int(data.get("xp_after", 0))).level))
	return Vector2i(b, a)


# ---------------------------------------------------------------------------------------------------------------
# Layout and reveal
# ---------------------------------------------------------------------------------------------------------------

func _layout() -> void:
	var vp := size if size.x > 0 else get_viewport_rect().size
	var cw := minf(CARD_W, vp.x - 2.0 * UIKit.SCREEN_GUTTER)
	card.custom_minimum_size.x = cw
	_buttons.custom_minimum_size.x = cw - 20.0
	_hero.custom_minimum_size.x = cw
	content.size = Vector2(cw, 0)
	var need := content.get_combined_minimum_size()
	var safe_top := float(data.get("safe_top", 0.0))
	var safe_bottom := float(data.get("safe_bottom", 0.0))
	var avail := vp.y - safe_top - safe_bottom - 24.0
	var k := minf(1.0, avail / maxf(need.y, 1.0))
	content.scale = Vector2(k, k)
	content.size = Vector2(cw, need.y)
	content.position = Vector2((vp.x - cw * k) / 2.0, safe_top + 12.0 + maxf(0.0, (avail - need.y * k) / 2.0))
	_rays.size = Vector2(cw, _hero.custom_minimum_size.y)
	_rays.position = Vector2.ZERO
	var avs := _hero.get_node("Avatars") as Control
	avs.position = Vector2((cw - avs.size.x) / 2.0, 46.0)
	_rays.center = avs.position + avs.size / 2.0
	_place_ribbon.call_deferred()

func _place_ribbon() -> void:
	if not is_instance_valid(card):
		return
	var rt := title_ribbon as RibbonTitle
	rt.fit_to(card.size.x)
	rt.scale = content.scale
	var top := content.position + card.position * content.scale
	rt.position = top + Vector2((card.size.x * content.scale.x - rt.size.x * rt.scale.x) / 2.0, -RibbonTitle.H * 0.5 * content.scale.y)
	rt.modulate = card.modulate
	if _level_up.visible:
		_level_up.position = Vector2(_level_up.get_parent_control().size.x - _level_up.size.x - 6, -14)

func _process(_d: float) -> void:
	_place_ribbon()

func _play() -> void:
	var reduce := Sheet.reduce_motion()
	_backdrop.modulate.a = 0.0
	for c: Control in [_hero, card, _buttons]:
		c.modulate.a = 0.0
	for r in _rows:
		r.modulate.a = 0.0
	again_button.disabled = true
	home_button.disabled = true
	var tw := create_tween()
	tw.tween_property(_backdrop, "modulate:a", 1.0, 0.25)
	await tw.finished
	if not _alive():
		return
	_hero.pivot_offset = Vector2(_hero.size.x / 2.0, _hero.size.y * 0.6)
	_hero.scale = Vector2(0.6, 0.6) if not reduce else Vector2.ONE
	var t2 := create_tween().set_parallel(true)
	t2.tween_property(_hero, "modulate:a", 1.0, 0.18)
	t2.tween_property(_hero, "scale", Vector2.ONE, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if celebrates():
		Celebrate.run(self)
		Haptics.success()
	var crown := _hero.get_node("Avatars/Crown") as Control
	if not reduce and crown.visible:
		crown.position.y -= 30
		crown.modulate.a = 0.0
		var t3 := create_tween()
		t3.tween_interval(0.25)
		t3.tween_property(crown, "modulate:a", 1.0, 0.1)
		t3.parallel().tween_property(crown, "position:y", crown.position.y + 30, 0.35).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	await _wait(0.2)
	var cy := card.position.y
	card.position.y = cy + (24 if not reduce else 0)
	var t4 := create_tween().set_parallel(true)
	t4.tween_property(card, "modulate:a", 1.0, 0.22)
	t4.tween_property(card, "position:y", cy, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	set_process(true)
	await _wait(0.18)
	for r in _rows:
		if not _alive():
			return
		var x := r.position.x
		r.position.x = x - (18 if not reduce else 0)
		var tr := create_tween().set_parallel(true)
		tr.tween_property(r, "modulate:a", 1.0, 0.16)
		tr.tween_property(r, "position:x", x, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		await _wait(0.07)
	var tb := create_tween()
	tb.tween_property(_buttons, "modulate:a", 1.0, 0.2)
	await _wait(0.15)
	if not _alive():
		return
	home_button.disabled = false
	again_button.disabled = is_online() and not bool(data.get("host", false))
	await _count_rewards()
	_done = true

func _count_rewards() -> void:
	var reward := int(data.get("reward", 0))
	if coins and reward > 0:
		coins.tick = true
		coins.set_amount(reward, true)
		await _wait(CoinAmount.COUNT_SEC)
		if not _alive():
			return
		coins.flash()
	if xp_meter == null:
		_after_rewards(reward)
		return
	var lv := _levels()
	var before := Collection.level_info(int(data.get("xp_before", 0)))
	var after := Collection.level_info(int(data.get("xp_after", 0)))
	if lv.y > lv.x:
		xp_meter.set_value(float(before.need), float(before.need), true)
		await _wait(Meter.SEC + 0.05)
		if not _alive():
			return
		level_badge.set_level(lv.y, true)
		_level_up.visible = true
		_level_up.size = _level_up.get_combined_minimum_size()
		_place_ribbon()
		UIKit.pop_in(_level_up, 0.3)
		Haptics.medium()
		UIKit.sfx("six")
		xp_meter.set_value(0.0, float(after.need))
		xp_meter.set_value(float(after.into), float(after.need), true)
	else:
		xp_meter.set_value(float(after.into), float(after.need), true)
	_after_rewards(reward)

func _after_rewards(reward: int) -> void:
	var target: Variant = data.get("coin_target", null)
	if reward > 0 and target is Control and is_instance_valid(target):
		await _wait(0.25)
		if _alive():
			CoinFly.run(self, coins.coin_center(), target, reward, Callable(), int(data.get("coin_total", -1)))

func _wait(sec: float) -> void:
	if is_inside_tree():
		await get_tree().create_timer(sec).timeout

func _alive() -> bool:
	return is_inside_tree() and not _closing

func _pick(what: String) -> void:
	if _closing:
		return
	if what == "again":
		play_again.emit()
		if is_online():
			again_button.disabled = true       # the server's start closes the screen
			again_button.text = "Starting…"
			return
	else:
		home.emit()
	close()


# ---------------------------------------------------------------------------------------------------------------
# Art
# ---------------------------------------------------------------------------------------------------------------

## The backdrop: the game behind, blurred (13 taps over two rings) and dimmed with the scrim colour.
static func _blur_material() -> ShaderMaterial:
	if _blur == null:
		_blur = Shader.new()
		_blur.code = """shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float radius = 7.0;
uniform vec4 tint : source_color = vec4(0.16, 0.08, 0.15, 0.55);
void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE * radius;
	vec3 acc = textureLod(screen_tex, SCREEN_UV, 2.0).rgb * 2.0;
	float w = 2.0;
	for (int i = 0; i < 6; i++) {
		float a = float(i) * 1.0472;
		vec2 d = vec2(cos(a), sin(a));
		acc += textureLod(screen_tex, SCREEN_UV + d * px, 2.0).rgb;
		acc += textureLod(screen_tex, SCREEN_UV + d.yx * vec2(-1.0, 1.0) * px * 2.2, 2.5).rgb;
		w += 2.0;
	}
	vec3 c = acc / w;
	float g = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(g), 0.25);
	COLOR = vec4(mix(c, tint.rgb, tint.a), 1.0);
}"""
	var m := ShaderMaterial.new()
	m.shader = _blur
	m.set_shader_parameter("tint", Color(Palette.SHADOW_DEEP, 0.55))
	return m


## A slowly turning sunburst behind the winner (gold on a win, soft cream otherwise) with a glow disc.
class Rays extends Control:
	var gold := true
	var center := Vector2.ZERO
	var _a := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(d: float) -> void:
		if not Sheet.reduce_motion():
			_a += d * 0.25
		queue_redraw()

	func _draw() -> void:
		var r := 150.0
		var col := Color(Palette.GOLD, 0.30) if gold else Color(Palette.CARD, 0.12)
		var n := 14
		for i in n:
			var a0 := _a + TAU * i / n
			var a1 := a0 + TAU / n * 0.45
			var pts := PackedVector2Array([center, center + Vector2(cos(a0), sin(a0)) * r, center + Vector2(cos(a1), sin(a1)) * r])
			draw_colored_polygon(pts, col)
		var glow := Color(Palette.GOLD, 0.30) if gold else Color(Palette.CARD, 0.14)
		for k in 4:
			draw_circle(center, 70.0 - k * 10.0, Color(glow, glow.a * (0.25 + k * 0.18)), true, -1.0, true)
