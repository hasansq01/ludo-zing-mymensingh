extends Node
## Every dice skin in one picture, its corner view above its 1 and 5 faces (designing skins without baking):
##   godot --path . res://dev/dice_preview.tscn -- <out.png> [ids ...]         (needs a GPU: not --headless)
## Never saves the player's game.

const S := 280
const COLS := 5

func _ready() -> void:
	if Save._timer and Save._timer.timeout.is_connected(Save.flush):
		Save._timer.timeout.disconnect(Save.flush)
	var args := OS.get_cmdline_user_args()
	var ids: Array = args.slice(1) if args.size() > 1 else Thumbnailer.ids("dice")
	var rows := ceili(ids.size() / float(COLS))
	var cell := Vector2i(S + 10, S + S / 2 + 18)
	var sheet := Image.create(COLS * cell.x + 10, rows * cell.y + 10, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("#f7e8d0"))
	for i in ids.size():
		var at := Vector2i(10 + (i % COLS) * cell.x, 10 + (i / COLS) * cell.y)
		_put(sheet, await _shot(ids[i], 0, S), at)
		_put(sheet, await _shot(ids[i], 1, S / 2), at + Vector2i(0, S))
		_put(sheet, await _shot(ids[i], 5, S / 2), at + Vector2i(S / 2, S))
	sheet.save_png(args[0])
	get_tree().quit()

func _put(sheet: Image, img: Image, at: Vector2i) -> void:
	sheet.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), at)

## face 0: the corner view.
func _shot(id: String, face: int, px: int) -> Image:
	var host := SubViewport.new()
	host.transparent_bg = true
	host.disable_3d = true
	host.size = Vector2i(900, 900)
	host.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(host)
	var die := Dice3D.new()
	die.position = Vector2(250, 250)
	die.size = Vector2(400, 400)
	host.add_child(die)
	die.wear(id)
	if face > 0:
		die.show_face(face)
	else:
		die.show_showcase()
	die.view.modulate = Color.WHITE
	die.set_process(false)
	die._layout()
	for f in 5:
		await RenderingServer.frame_post_draw
	var img := die.viewport.get_texture().get_image()
	host.queue_free()
	img.convert(Image.FORMAT_RGBA8)
	# the die fills the middle of its padded view: cut that out
	var side := mini(img.get_width(), img.get_height()) * 62 / 100
	var cut := img.get_region(Rect2i((img.get_width() - side) / 2, (img.get_height() - side) * 58 / 100, side, side))
	cut.resize(px, px, Image.INTERPOLATE_LANCZOS)
	return cut
