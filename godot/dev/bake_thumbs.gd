extends Node
## Dev tool: pre-bakes the Shop / PreviewSheet pictures of every catalogue item that has 3D art, so the game never
## renders them live (Thumbnailer.baked):
##   rooms   res://assets/thumbs/room_<id>.webp    Thumbnailer's corner camera, 720 x 540
##   scenes  res://assets/thumbs/scene_<id>.webp   the scene's landing view (sign shrunk like the Shop's), 720 x 540
##   dice    res://assets/thumbs/dice_<id>.webp    a Dice3D at rest on face 5, its padded rect, 3x an 84 px die
##   pawns   res://assets/thumbs/pawn_<id>.webp    PawnStage's CARD pair (a red and a blue pawn in the skin), 360 x 270
## Rooms, scenes and pawns render at 2x the picture size with 4x MSAA and are scaled down (Lanczos): clean edges. Lossy
## WebP (quality QUALITY) with a matching .import (lossy, no mipmaps, never VRAM-compressed: crisp UI, small download).
##   godot --path . res://dev/bake_thumbs.tscn [-- room|scene|dice|pawn ...]     (needs a GPU: not --headless)
## then `godot --headless --import` (tools/godot-test.sh does it) so the new files get imported.
## The real save is never written (the flush timer is unhooked; the file is restored at the end anyway).

const QUALITY := 0.85
const SUPERSAMPLE := 2

var _backup := ""
var _had_save := false


func _ready() -> void:
	_had_save = FileAccess.file_exists("user://save.json")
	if _had_save:
		_backup = FileAccess.get_file_as_string("user://save.json")
	if Save._timer and Save._timer.timeout.is_connected(Save.flush):
		Save._timer.timeout.disconnect(Save.flush)
	var want: Array = OS.get_cmdline_user_args()
	if want.is_empty():
		want = Thumbnailer.BAKED_KINDS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(Thumbnailer.BAKED_DIR))
	var total := 0
	var t0 := Time.get_ticks_msec()
	if "room" in want or "scene" in want:
		var w := Thumbnailer.new()
		w.manual = true
		w.render_size = Thumbnailer.BAKE_SIZE * SUPERSAMPLE
		add_child(w)
		for kind in ["room", "scene"]:
			if not kind in want:
				continue
			for id: String in Thumbnailer.ids(kind):
				var tex: Texture2D
				if kind == "room":
					tex = await w._render_room(id)
				else:
					tex = await w._render_scene(id)
				if tex == null or w.last_image == null:
					push_error("bake_thumbs: %s %s failed" % [kind, id])
					continue
				var img := w.last_image
				img.resize(Thumbnailer.BAKE_SIZE.x, Thumbnailer.BAKE_SIZE.y, Image.INTERPOLATE_LANCZOS)
				total += _save(img, kind, id)
				w.last_image = null
		w._teardown()
		w.queue_free()
	if "dice" in want:
		for id: String in Thumbnailer.ids("dice"):
			var img := await _render_die(id)
			if img:
				total += _save(img, "dice", id)
	if "pawn" in want:
		for id: String in Thumbnailer.ids("pawn"):
			var img := await _render_pawn(id)
			if img:
				total += _save(img, "pawn", id)
	print("bake_thumbs: %d KB in %s (%.1f s)" % [total / 1024, Thumbnailer.BAKED_DIR, (Time.get_ticks_msec() - t0) / 1000.0])
	_restore()
	for i in 3:                              # let the freed worlds go before quitting
		await get_tree().process_frame
	get_tree().quit()

## A Dice3D on face DICE_FACE, laid out at DICE_SIZE UI px inside a host viewport stretched DICE_SCALE times (so the
## die renders at that pixel density, as on a phone), and its own render target read back (straight from the die's
## viewport, so its alpha is exactly what the live die shows).
func _render_die(id: String) -> Image:
	var d := Catalog.dice(id)
	var s := Thumbnailer.DICE_SIZE
	var pad := Dice3D.PAD
	var rect := Vector2(s * (1.0 + pad.x + pad.z), s * (1.0 + pad.y + pad.w))
	var host := SubViewport.new()
	host.transparent_bg = true
	host.disable_3d = true
	host.size = Vector2i(ceili(rect.x * Thumbnailer.DICE_SCALE), ceili(rect.y * Thumbnailer.DICE_SCALE))
	host.size_2d_override = Vector2i(ceili(rect.x), ceili(rect.y))
	host.size_2d_override_stretch = true
	host.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(host)
	var die := Dice3D.new()
	die.position = Vector2(pad.x * s, pad.y * s)
	die.size = Vector2(s, s)
	host.add_child(die)
	die.set_skin(d.bg, d.edge, d.pip, d.one)
	die.show_face(Thumbnailer.DICE_FACE)
	die.view.modulate = Color.WHITE
	die.set_process(false)                  # no pulse / glow: the resting die
	die._layout()
	for i in Thumbnailer.SETTLE_FRAMES + 1:
		await RenderingServer.frame_post_draw
	var img := die.viewport.get_texture().get_image()
	host.queue_free()
	if img == null or img.is_empty():
		push_error("bake_thumbs: dice %s failed" % id)
		return null
	img.convert(Image.FORMAT_RGBA8)
	return img

## A PawnStage CARD (transparent background) rendered at SUPERSAMPLE x Thumbnailer.PAWN_SIZE, read back from its own
## viewport and scaled down.
func _render_pawn(id: String) -> Image:
	var st := PawnStage.new(id, PawnStage.CARD)
	st.keep_drawing = true
	st.size = Vector2(Thumbnailer.PAWN_SIZE * SUPERSAMPLE)
	st.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(st)
	st.size = Vector2(Thumbnailer.PAWN_SIZE * SUPERSAMPLE)
	for i in Thumbnailer.SETTLE_FRAMES + 2:
		await RenderingServer.frame_post_draw
	var img := st.viewport.get_texture().get_image()
	st.queue_free()
	if img == null or img.is_empty():
		push_error("bake_thumbs: pawn %s failed" % id)
		return null
	img.convert(Image.FORMAT_RGBA8)
	img.resize(Thumbnailer.PAWN_SIZE.x, Thumbnailer.PAWN_SIZE.y, Image.INTERPOLATE_LANCZOS)
	return img

## Writes the WebP and its .import (lossy, no mipmaps, no VRAM compression). Returns the file size in bytes.
func _save(img: Image, kind: String, id: String) -> int:
	var path := Thumbnailer.baked_path(kind, id)
	var err := img.save_webp(path, true, QUALITY)
	if err != OK:
		push_error("bake_thumbs: can't save %s (%d)" % [path, err])
		return 0
	_write_import(path)
	var f := FileAccess.open(path, FileAccess.READ)
	var n := f.get_length() if f else 0
	print("  %s  %dx%d  %d KB" % [path.get_file(), img.get_width(), img.get_height(), n / 1024])
	return n

## The import settings for a UI picture: Lossy (the WebP is stored as WebP: small on disk, decoded to RGB(A)8 in
## VRAM: crisp, no block artefacts), no mipmaps (shown at most ~2x smaller than baked), never auto-switched to VRAM
## compression. An existing .import keeps its uid (the file is re-imported because it changed).
func _write_import(path: String) -> void:
	var ip := path + ".import"
	var uid := ""
	if FileAccess.file_exists(ip):
		for line in FileAccess.get_file_as_string(ip).split("\n"):
			if line.begins_with("uid="):
				uid = line
	var txt := "[remap]\n\nimporter=\"texture\"\ntype=\"CompressedTexture2D\"\n"
	if uid != "":
		txt += uid + "\n"
	txt += "\n[deps]\n\nsource_file=\"%s\"\n\n[params]\n\n" % path
	txt += "\n".join([
		"compress/mode=1", "compress/high_quality=false", "compress/lossy_quality=%.2f" % QUALITY,
		"compress/uastc_level=0", "compress/rdo_quality_loss=0.0", "compress/hdr_compression=1",
		"compress/normal_map=0", "compress/channel_pack=0", "mipmaps/generate=false", "mipmaps/limit=-1",
		"roughness/mode=0", "roughness/src_normal=\"\"", "process/channel_remap/red=0",
		"process/channel_remap/green=1", "process/channel_remap/blue=2", "process/channel_remap/alpha=3",
		"process/fix_alpha_border=true", "process/premult_alpha=false", "process/normal_map_invert_y=false",
		"process/hdr_as_srgb=false", "process/hdr_clamp_exposure=false", "process/size_limit=0",
		"detect_3d/compress_to=0"]) + "\n"
	var f := FileAccess.open(ip, FileAccess.WRITE)
	if f:
		f.store_string(txt)

func _restore() -> void:
	if _had_save:
		var cur := FileAccess.get_file_as_string("user://save.json")
		if cur != _backup:
			var f := FileAccess.open("user://save.json", FileAccess.WRITE)
			if f:
				f.store_string(_backup)
