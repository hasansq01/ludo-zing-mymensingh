class_name CoinAmount
extends HBoxContainer
## A coin amount: the coin icon (assets/ui/coin.svg) + the amount as text, via Fmt.coins ("5.3K", the short web
## form) or Fmt.coins_full ("5,300", full = true). Replaces the coin + label pairs of the home balance, the shop
## balance chip, prices, rewards and claim buttons.
##   size  "xs" coin 16 / Nunito 900 14   (claim buttons, card captions)
##         "sm" coin 20 / Nunito 900 16   (prices on cards, rewards)
##         "md" coin 24 / Nunito 900 18   (balance chips, preview prices)
##         "lg" coin 30 / Lilita 22       (the home balance, result rewards)
##         "hero" coin 44 / Lilita 34     (big amounts: Earn coins hub, win reward)
##   look  "plain" coin + INK text, no background
##         "chip"  honey-tint balance chip (HONEY_TINT, 2 px HONEY_TINT_EDGE, pill), ON_HONEY text
##         "night" web .h-bar .coins: the coin overlapping a dark INK pill with cream text (on the night lobby)
##         "price" a white price tag pill with a cream lip (readable on art and cards)
##   prefix: shown before the number ("+" for gains: "+200").
## set_amount(n, animate) counts up / down over 0.5 s (optional tick sound); flash() pops it when coins land.
##
##   var bal := CoinAmount.new(Save.coins, "md", "chip")
##   bal.set_amount(Save.coins, true); bal.flash()

const SIZES := {
	xs = {coin = 16.0, fs = 14, display = false},
	sm = {coin = 20.0, fs = 16, display = false},
	md = {coin = 24.0, fs = 18, display = false},
	lg = {coin = 30.0, fs = 22, display = true},
	hero = {coin = 44.0, fs = 34, display = true},
}
const LOOKS := ["plain", "chip", "night", "price"]
const COUNT_SEC := 0.5

var amount := 0                      ## the amount shown once any count animation ends
var size_name := "sm"
var look := "plain"
var prefix := ""
var full := false
var tick := false                    ## play the "tick" sound while counting
var icon_name := "coin"              ## the art: "coin" (assets/ui/coin.svg) or "gem" (assets/ui/gem.svg, shown in full: "1,200")

var coin: TextureRect
var text_label: Label
var _shown := 0.0                    # the value on screen while counting
var _tw: Tween
var _flash_tw: Tween
var _bg: StyleBoxFlat
var _shade: StyleBoxFlat


func _init(n := 0, size_ := "sm", look_ := "plain", prefix_ := "", full_ := false, icon_ := "coin") -> void:
	icon_name = icon_
	if icon_name == "gem":
		full_ = true                      # gem counts are small: never "1.2K"
	size_name = size_ if SIZES.has(size_) else "sm"
	look = look_ if look_ in LOOKS else "plain"
	prefix = prefix_
	full = full_
	amount = n
	_shown = n
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	alignment = BoxContainer.ALIGNMENT_CENTER
	var p: Dictionary = SIZES[size_name]
	var cs: float = p.coin
	coin = UIKit.icon(icon_name, cs)
	coin.name = "Coin"
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(coin)
	var font: Font = UIKit.font_display() if p.display else UIKit.font_body(900, true)
	text_label = UIKit.label("", int(p.fs), Palette.INK, font)
	text_label.name = "Amount"
	text_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(text_label)
	_style()
	_render(n)


## A gem amount: the gem icon + the number in full ("30", "1,200").
static func gems(n := 0, size_ := "sm", look_ := "plain", prefix_ := "") -> CoinAmount:
	return CoinAmount.new(n, size_, look_, prefix_, true, "gem")


## The text for an amount (Fmt short form, or full; with the prefix).
func format(n: int) -> String:
	return prefix + (Fmt.coins_full(n) if full else Fmt.coins(n))


## The text on screen now.
func text() -> String:
	return text_label.text


## Show a new amount. animate: count from the shown value over 0.5 s (ticks when `tick` is on).
func set_amount(n: int, animate := false) -> void:
	amount = n
	if _tw and _tw.is_valid():
		_tw.kill()
	if not animate or not is_inside_tree() or int(round(_shown)) == n:
		_shown = n
		_render(n)
		return
	var from := _shown
	# keep the width steady while the digits change
	var f := text_label.get_theme_font("font")
	var fs := text_label.get_theme_font_size("font_size")
	text_label.custom_minimum_size.x = maxf(f.get_string_size(format(int(round(from))), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x,
		f.get_string_size(format(n), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	var last_tick := [0]
	_tw = create_tween()
	_tw.tween_method(func(v: float) -> void:
		_shown = v
		var shown := int(round(v))
		var t := format(shown)
		if t != text_label.text:
			text_label.text = t
			var now := Time.get_ticks_msec()
			if tick and now - int(last_tick[0]) > 70:
				last_tick[0] = now
				_sfx("tick"), from, float(n), COUNT_SEC).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tw.tween_callback(func() -> void:
		_shown = n
		_render(n))


## A scale pop (coins landed on this counter). Doesn't change the amount.
func flash() -> void:
	if not is_inside_tree():
		return
	if _flash_tw and _flash_tw.is_valid():
		_flash_tw.kill()
	pivot_offset = size / 2.0
	scale = Vector2.ONE
	_flash_tw = create_tween()
	_flash_tw.tween_property(self, "scale", Vector2(1.18, 1.18), 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_flash_tw.tween_property(self, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	coin.pivot_offset = coin.size / 2.0
	var spin := create_tween()
	spin.tween_property(coin, "rotation", deg_to_rad(-14.0), 0.08)
	spin.tween_property(coin, "rotation", 0.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Override the text colour (plain / price looks), e.g. Palette.TEAL_INK for a gain or Palette.DANGER for a shortfall.
func set_color(c: Color) -> void:
	text_label.add_theme_color_override("font_color", c)


## The global centre of the coin icon (where flying coins should land).
func coin_center() -> Vector2:
	return coin.get_global_rect().get_center()


# ---------------------------------------------------------------------------------------------------------------------

func _render(n: int) -> void:
	text_label.custom_minimum_size.x = 0.0
	text_label.text = format(n)


func _style() -> void:
	var p: Dictionary = SIZES[size_name]
	var fs: float = float(p.fs)
	var cs: float = p.coin
	var gap := clampf(roundf(cs * 0.22), 3.0, 8.0)
	add_theme_constant_override("separation", 0)                 # gaps live in the label's margins
	var lead := 0.0                                              # padding before the coin
	var lab := StyleBoxEmpty.new()
	lab.content_margin_left = gap
	match look:
		"chip", "price":
			if look == "chip":
				_bg = UIKit.box(Palette.HONEY_TINT, UIKit.R.pill, UIKit.BW.line, Palette.HONEY_TINT_EDGE)
				text_label.add_theme_color_override("font_color", Palette.ON_HONEY)
			else:
				_bg = UIKit.box(Color.WHITE, UIKit.R.pill, UIKit.BW.hair, Palette.LINE_SOLID)
				_bg.border_width_bottom = UIKit.LIP.sm
				_bg.border_color = Palette.LIP_CREAM
				_bg.shadow_size = 2; _bg.shadow_offset = Vector2(0, 1); _bg.shadow_color = Palette.shadow(0.14)
			lead = maxf(3.0, roundf(cs * 0.2))
			lab.content_margin_right = roundf(fs * 0.62)
			custom_minimum_size.y = cs + 2.0 * maxf(3.0, roundf(cs * 0.16))
		"night":
			# web .h-bar .coins: an INK pill from the coin's centre to the end, cream digits right-aligned
			_bg = StyleBoxFlat.new()
			_bg.bg_color = Palette.INK
			_bg.set_corner_radius_all(UIKit.R.pill)
			_bg.corner_detail = 10
			_bg.anti_aliasing = true
			_bg.set_border_width_all(1)                              # a faint light rim keeps it off dark rooms
			_bg.border_color = Color(1, 1, 1, 0.22)
			text_label.add_theme_color_override("font_color", Palette.CARD)
			text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			lab.content_margin_left = roundf(fs * 0.5)
			lab.content_margin_right = roundf(fs * 0.75)
			text_label.custom_minimum_size.y = roundf(maxf(cs * 0.74, fs + 6.0))
	text_label.add_theme_stylebox_override("normal", lab)
	if lead > 0.0:
		var sp := Control.new()
		sp.name = "Lead"
		sp.custom_minimum_size.x = lead
		sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(sp)
		move_child(sp, 0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN and _bg:
		queue_redraw()


func _draw() -> void:
	if _bg == null:
		return
	var r := Rect2(Vector2.ZERO, size)
	if look == "night":
		# the pill runs from the coin's centre to the end, its height a bit less than the coin
		var cr := coin.get_rect()
		var h := text_label.size.y
		r = Rect2(cr.get_center().x, (size.y - h) / 2.0, size.x - cr.get_center().x, h)
		draw_style_box(_bg, r)
		# inset top shade (web inset 0 2px 2px rgba(0,0,0,.35))
		if _shade == null:
			_shade = _bg.duplicate() as StyleBoxFlat
			_shade.bg_color = Color(0, 0, 0, 0)
			_shade.border_color = Color(0, 0, 0, 0.3)
			_shade.border_width_top = 2
			_shade.border_blend = true
		draw_style_box(_shade, r)
		return
	draw_style_box(_bg, r)


func _sfx(name_: String) -> void:
	UIKit.sfx(name_)
