extends Control
## Dev preview: the logo and dice on a cream background; rolls the dice and saves screenshots, then quits.
## Screenshots go to the folder in the OUT environment variable (default user://).

const SKINS := [
	["#fdfaf2", "#e1d7c3", "#22263f", "#d8323a"], ["#f1d9b5", "#d2b183", "#5a3418", "#5a3418"],
	["#4a2c1a", "#2a170c", "#f3e3cc", "#f2b632"], ["#f6c945", "#c99a1c", "#3a2400", "#b3261e"],
]

var dice := []

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Palette.CREAM
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var logo := BrandLogo.new()
	logo.position = Vector2(45, 30)
	logo.size = Vector2(300, 250)
	logo.bob = true
	add_child(logo)
	var small := BrandLogo.new()
	small.position = Vector2(120, 300)
	small.size = Vector2(150, 125)
	add_child(small)
	var big := Dice3D.new()
	big.position = Vector2(153, 500)
	big.size = Vector2(84, 84)
	add_child(big)
	dice.append(big)
	for i in 4:
		var d := Dice3D.new()
		d.position = Vector2(30 + i * 90, 680)
		d.size = Vector2(60, 60)
		add_child(d)
		d.set_skin(Color(SKINS[i][0]), Color(SKINS[i][1]), Color(SKINS[i][2]), Color(SKINS[i][3]))
		d.show_face([1, 2, 3, 5][i])
		dice.append(d)
	big.set_active(true)
	dice[2].set_active(true)
	big.pressed.connect(func(): print("pressed"))
	_run()

func _run() -> void:
	var out := OS.get_environment("OUT")
	if out == "":
		out = "user://"
	var tag := OS.get_environment("TAG")
	await get_tree().create_timer(0.4).timeout
	for i in range(1, 5):
		dice[i].roll(randi_range(1, 6), 1.0)
	_shot_airborne(out + "/roll_mid%s.png" % tag)
	await dice[0].roll(4)
	await get_tree().create_timer(0.3).timeout
	await dice[0].roll(1, 0.6)
	await get_tree().create_timer(0.7).timeout
	await _shot(out + "/preview%s.png" % tag)
	_tap_test()
	await get_tree().create_timer(0.5).timeout
	get_tree().quit()

## One click and one touch on the big die: each should print "pressed" once.
func _tap_test() -> void:
	var at := Vector2(195, 542)
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.position = at
	mb.pressed = true
	Input.parse_input_event(mb)
	var up := mb.duplicate()
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().create_timer(0.3).timeout
	var t := InputEventScreenTouch.new()
	t.position = at
	t.pressed = true
	Input.parse_input_event(t)
	var tu := t.duplicate()
	tu.pressed = false
	Input.parse_input_event(tu)

func _shot_airborne(path: String) -> void:
	while dice[0]._height < 0.75:
		await get_tree().process_frame
	await _shot(path)

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
