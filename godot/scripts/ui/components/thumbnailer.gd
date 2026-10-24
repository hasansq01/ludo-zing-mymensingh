class_name Thumbnailer
extends Node
## Thumbnails of the café rooms (Rooms), the Snakes & Ladders scenes (SLScenes) and the dice skins (Catalog.DICE) for
## the Shop cards and the PreviewSheet's first frame, instead of gradient swatches (index.html Rooms.thumb /
## Jungle.thumb).
##
## Pre-baked first: every catalogue item ships a picture in res://assets/thumbs/<kind>_<id>.webp (made by the dev
## tool `godot --path . res://dev/bake_thumbs.tscn`; tests/test_thumbs.gd fails when an item has none). baked() loads
## it at once (no SubViewport, no 3D world, no shader compile), and every entry point below returns it. Re-run the
## bake tool when room, scene or dice art changes.
##
## Live fallback (an item without a bake, e.g. a new room during development): rendered once, 480 x 360 (4:3) with 4x
## MSAA, from a fixed corner camera like the web Rooms.thumb (scenes: their landing view fitted to 4:3), then cached
## in memory and on disk at user://thumbs/<kind>_<id>_v<N>.png. Bump VERSION when room or scene art changes: older
## files are deleted on the next run.
##
## Rendering never touches the game: a hidden worker node (one at a time, under the tree root) builds its OWN copy of
## the café (TableWorld) or of the S&L world (SLScenes + SLBoard) in a SubViewport with its own World3D, so the room
## in use, the café on screen, PreviewSheet and Save.profile are left alone. Rooms and scenes are built one after
## the other (one render per few frames, freeing each room after its picture), never during a match, and the whole
## worker (its worlds, textures and viewport) is freed when the queue is empty. Headless / no GPU: placeholders only.
##
## API (all static):
##   Thumbnailer.baked(kind, id) -> Texture2D       the shipped picture ("room" | "scene" | "dice"), null if none
##   Thumbnailer.room(id) / scene(id) -> Texture2D   the baked / cached thumbnail, or a soft gradient placeholder (and
##                                                   the render is queued)
##   await Thumbnailer.room_async(id) / scene_async(id) -> Texture2D   the real thumbnail once ready (placeholder
##                                                   when it can't render)
##   Thumbnailer.view("room" | "scene", id, radius) -> Thumbnailer.View   a Control showing the baked picture at
##                                                   once, else a shimmer over the placeholder until the live render
##                                                   is ready, then fading it in
##   Thumbnailer.dice_art(id, size := 84) -> Control a die at rest on face 5, exactly where a Dice3D of that size
##                                                   draws it (the baked picture; a live Dice3D when there's no bake)
##   Thumbnailer.prewarm()                            queue every missing live thumbnail (e.g. after the splash)
##   Thumbnailer.is_ready(kind, id), has_disk(kind, id), clear(disk := false)

signal done(kind: String, id: String, tex: Texture2D)

const VERSION := 1
const SIZE := Vector2i(480, 360)
const DIR := "user://thumbs/"
const KINDS := ["room", "scene"]          # rendered live when there's no bake
const BAKED_KINDS := ["room", "scene", "dice"]
const BAKED_DIR := "res://assets/thumbs/"
## Baked picture sizes: 2x the largest on-screen size in UI px (the PreviewSheet's ~360 px wide view; Shop cards are
## ~170 px). Dice: the Dice3D's padded drawing rect (Dice3D.PAD) for an 84 px die, at 3x.
const BAKE_SIZE := Vector2i(720, 540)
const DICE_SIZE := 84.0
const DICE_SCALE := 3.0
const DICE_FACE := 5
## The room camera (web Rooms.thumb: a corner camera at angle .72, 50 out, 24 up, looking at the far corner), in
## TableWorld units (the same as the web's), with a vertical lens wide enough for 4:3.
const ROOM_CAM := {pos = Vector3(30.5, 21.0, 35.0), look = Vector3(-14, 5.0, -14), fov = 50.0}
## Scenes: the landing sign's size and lift (web units) on the 4:3 picture.
const SIGN_SCALE := 0.62
const SIGN_LIFT := -0.55
const SETTLE_FRAMES := 3                 # frames drawn before reading a picture back (shadows, lights settle)

## Tests / previews: never render (placeholders only).
static var disabled := false
## dev/perf_probe: false measures the live-render path (no baked pictures), with its own disk cache dir.
static var use_baked := true
static var dir := DIR
static var _mem := {}                    # "room_dream" -> Texture2D
static var _baked := {}                  # "room_dream" -> Texture2D, or null when there is no baked file
static var _ph := {}                     # placeholders
static var _queue: Array = []            # [[kind, id], ...]
static var _worker: Thumbnailer
static var _pruned := false

var _baker: TexBaker
var _room_vp: SubViewport
var _room_world: TableWorld
var _room_cam: Camera3D
var _scene_vp: SubViewport
var _scene_world: SLScenes
var _scene_board: SLBoard
var _running := false
var manual := false                      ## the bake tool drives this worker itself (no queue, no disk cache)
var render_size := SIZE                  ## the picture's size (the bake tool renders larger)


# =====================================================================================================================
# Public API
# =====================================================================================================================

## The pre-baked picture shipped in res://assets/thumbs/<kind>_<id>.webp (kind "room" | "scene" | "dice"), loaded
## once and kept. Null when the item has none (then the live render is the fallback).
static func baked(kind: String, id: String) -> Texture2D:
	if not use_baked:
		return null
	var key := _key(kind, id)
	if _baked.has(key):
		return _baked[key]
	var path := baked_path(kind, id)
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path) as Texture2D
	_baked[key] = t
	return t

static func baked_path(kind: String, id: String) -> String:
	return BAKED_DIR + "%s_%s.webp" % [kind, id.validate_filename()]

static func has_baked(kind: String, id: String) -> bool:
	return use_baked and ResourceLoader.exists(baked_path(kind, id))

static func room(id: String) -> Texture2D:
	return get_tex("room", id)

static func scene(id: String) -> Texture2D:
	return get_tex("scene", id)

static func room_async(id: String) -> Texture2D:
	return await get_async("room", id)

static func scene_async(id: String) -> Texture2D:
	return await get_async("scene", id)

## The thumbnail (memory or disk), else the placeholder; a missing one is queued for rendering.
static func get_tex(kind: String, id: String) -> Texture2D:
	var t := cached(kind, id)
	if t:
		return t
	request(kind, id)
	return placeholder(kind, id)

## The real thumbnail once rendered (coroutine). The placeholder when it can't be rendered here.
static func get_async(kind: String, id: String) -> Texture2D:
	var t := cached(kind, id)
	if t:
		return t
	if not request(kind, id):
		return placeholder(kind, id)
	var w := _worker
	while is_instance_valid(w):
		var got: Array = await w.done
		if got[0] == kind and got[1] == id:
			return got[2] if got[2] else placeholder(kind, id)
	return cached(kind, id) if cached(kind, id) else placeholder(kind, id)

## Baked, in memory or on disk (loaded into memory then). Null when it still has to be rendered.
static func cached(kind: String, id: String) -> Texture2D:
	var b := baked(kind, id)
	if b:
		return b
	var key := _key(kind, id)
	if _mem.has(key):
		return _mem[key]
	var path := disk_path(kind, id)
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img and not img.is_empty():
			if not img.has_mipmaps():
				img.generate_mipmaps()
			var tex := ImageTexture.create_from_image(img)
			_mem[key] = tex
			return tex
	return null

static func is_ready(kind: String, id: String) -> bool:
	return has_baked(kind, id) or _mem.has(_key(kind, id)) or has_disk(kind, id)

static func has_disk(kind: String, id: String) -> bool:
	return FileAccess.file_exists(disk_path(kind, id))

static func disk_path(kind: String, id: String) -> String:
	return dir + "%s_%s_v%d.png" % [kind, id.validate_filename(), VERSION]

## Every room, scene or dice id, in shop order.
static func ids(kind: String) -> Array:
	var out := []
	var list: Array = Rooms.LIST if kind == "room" else (SLScenes.LIST if kind == "scene" else Catalog.DICE)
	for r: Dictionary in list:
		out.append(str(r.id))
	return out

## Queue every thumbnail that isn't cached yet (low priority: the Shop's requests go first).
static func prewarm() -> void:
	for kind in KINDS:
		for id in ids(kind):
			if not is_ready(kind, id):
				request(kind, id, false)

## Queue a render. False when it can't render here (headless, no GPU, disabled). first: ahead of the queue.
static func request(kind: String, id: String, first := true) -> bool:
	if not can_render() or not (kind in KINDS) or not ids(kind).has(id):
		return false
	for q: Array in _queue:
		if q[0] == kind and q[1] == id:
			if first and _queue.find(q) > 0:
				_queue.erase(q)
				_queue.push_front(q)
			return true
	if first:
		_queue.push_front([kind, id])
	else:
		_queue.append([kind, id])
	_ensure_worker()
	return true

static func can_render() -> bool:
	return not disabled and DisplayServer.get_name() != "headless" and RenderingServer.get_video_adapter_name() != ""

## Forget the thumbnails in memory (and on disk).
static func clear(disk := false) -> void:
	_mem.clear()
	if disk and DirAccess.dir_exists_absolute(dir):
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".png"):
				DirAccess.remove_absolute(dir + f)

## A soft two-colour gradient in the item's colours (no glyph), shown until the real thumbnail is ready.
static func placeholder(kind: String, id: String) -> Texture2D:
	var key := _key(kind, id)
	if _ph.has(key):
		return _ph[key]
	var cols := [Palette.CHIP, Palette.TAB]
	if kind == "room" and Catalog.ROOM_GRADIENT.has(id):
		cols = Catalog.ROOM_GRADIENT[id]
	elif kind == "scene":
		var s := SLScenes.info(id)
		if s.has("g"):
			cols = s.g
	var g := Gradient.new()
	g.colors = PackedColorArray([cols[0], cols[1]])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 64
	gt.height = 48
	gt.fill_from = Vector2(0.0, 0.0)
	gt.fill_to = Vector2(1.0, 1.0)
	_ph[key] = gt
	return gt

static func _key(kind: String, id: String) -> String:
	return kind + "_" + id

## A Control for a shop card: the thumbnail cropped to fill (rounded corners), a shimmer over the placeholder while
## it renders, then a 0.25 s fade to the real picture. Size it yourself (e.g. custom_minimum_size or a ratio box).
## radius 0: square corners and no clip group of its own (for a view inside a card that already clips and rounds).
static func view(kind: String, id: String, radius: int = UIKit.R.md) -> View:
	return View.new(kind, id, radius)

## A die skin at rest on face DICE_FACE, for a Shop card: a Control of size x size whose picture overflows it exactly
## like a Dice3D's (Dice3D.PAD: room for the hop and the soft shadow), so it drops in for `Dice3D.new()` + set_skin +
## show_face. The baked picture when there is one (no SubViewport, nothing per frame); else a live Dice3D.
static func dice_art(id: String, size: float = DICE_SIZE) -> Control:
	var t := baked("dice", id)
	if t == null:
		var d := Catalog.dice(id)
		var die := Dice3D.new()
		die.custom_minimum_size = Vector2(size, size)
		die.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not d.is_empty():
			die.ready.connect(func():
				die.set_skin(d.bg, d.edge, d.pip, d.one)
				die.show_face(DICE_FACE)
				die.view.modulate = Color.WHITE, CONNECT_ONE_SHOT)
		return die
	var c := Control.new()
	c.custom_minimum_size = Vector2(size, size)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var r := TextureRect.new()
	r.texture = t
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pad := Dice3D.PAD
	r.position = Vector2(-pad.x * size, -pad.y * size)
	r.size = Vector2(size * (1.0 + pad.x + pad.z), size * (1.0 + pad.y + pad.w))
	c.add_child(r)
	return c


# =====================================================================================================================
# Thumbnailer.View
# =====================================================================================================================

class View extends PanelContainer:
	var kind := ""
	var id := ""
	var picture: TextureRect
	var _ph: TextureRect
	var _shine: Control
	var _t := 0.0

	func _init(kind_: String, id_: String, radius: int) -> void:
		kind = kind_
		id = id_
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		# rounded corners need a clip group; radius 0 (a view inside an already rounded, clipping card) must not
		# open a nested one
		clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW if radius > 0 else CanvasItem.CLIP_CHILDREN_DISABLED
		var st := StyleBoxFlat.new()
		st.bg_color = Palette.CHIP
		st.set_corner_radius_all(radius)
		st.corner_detail = 8
		st.anti_aliasing = true
		add_theme_stylebox_override("panel", st)
		var t := Thumbnailer.cached(kind, id)
		if t:                                # baked / cached: the picture at once, no placeholder or shimmer
			picture = _rect(t)
			add_child(picture)
			return
		_ph = _rect(Thumbnailer.placeholder(kind, id))
		add_child(_ph)
		picture = _rect(null)
		picture.modulate.a = 0.0
		add_child(picture)
		_shine = Control.new()
		_shine.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_shine.draw.connect(_draw_shine)
		add_child(_shine)
		_wait()

	static func _rect(t: Texture2D) -> TextureRect:
		var r := TextureRect.new()
		r.texture = t
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return r

	func _wait() -> void:
		var t: Texture2D = await Thumbnailer.get_async(kind, id)
		if is_instance_valid(self) and t and t != Thumbnailer.placeholder(kind, id):
			_show(t, true)
		elif is_instance_valid(self):
			_stop_shine()

	func _show(t: Texture2D, fade: bool) -> void:
		picture.texture = t
		_stop_shine()
		if fade and is_inside_tree() and not Sheet.reduce_motion():
			var tw := create_tween()
			tw.tween_property(picture, "modulate:a", 1.0, 0.25)
			tw.tween_callback(func(): if _ph: _ph.visible = false)
		else:
			picture.modulate.a = 1.0
			if _ph:
				_ph.visible = false

	func _stop_shine() -> void:
		set_process(false)
		if _shine:
			_shine.visible = false

	func _ready() -> void:
		set_process(_shine != null and _shine.visible and not Sheet.reduce_motion())

	func _process(delta: float) -> void:
		_t = fmod(_t + delta, 1.4)
		_shine.queue_redraw()

	## A soft diagonal light band sweeping across the placeholder every 1.4 s (skeleton shimmer).
	func _draw_shine() -> void:
		var s := _shine.size
		if s.x <= 0.0:
			return
		var band := s.x * 0.45
		var x := -band + (s.x + 2.0 * band) * clampf(_t / 1.1, 0.0, 1.0)
		var tilt := s.y * 0.35
		var steps := 8
		for k in steps:
			var a := sin(PI * (k + 0.5) / steps) * 0.22
			var x0 := x + band * k / steps
			var x1 := x + band * (k + 1) / steps
			_shine.draw_colored_polygon(PackedVector2Array([
				Vector2(x0 + tilt, 0), Vector2(x1 + tilt, 0), Vector2(x1 - tilt, s.y), Vector2(x0 - tilt, s.y)]),
				Color(1, 1, 1, a))


# =====================================================================================================================
# The worker
# =====================================================================================================================

static func _ensure_worker() -> void:
	if is_instance_valid(_worker):
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	_worker = Thumbnailer.new()
	_worker.name = "Thumbnailer"
	tree.root.add_child.call_deferred(_worker)

func _ready() -> void:
	_baker = TexBaker.new()
	_baker.name = "ThumbBaker"
	add_child(_baker)
	if manual:
		return
	_prune()
	_run()

func _exit_tree() -> void:
	# anyone still waiting gets the placeholder
	for q: Array in _queue:
		done.emit(q[0], q[1], null)
	if _worker == self:
		_worker = null

## Old versions' files go (art changed).
static func _prune() -> void:
	if _pruned:
		return
	_pruned = true
	DirAccess.make_dir_recursive_absolute(dir)
	var tail := "_v%d.png" % VERSION
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".png") and not f.ends_with(tail):
			DirAccess.remove_absolute(dir + f)

func _run() -> void:
	_running = true
	await get_tree().process_frame
	while not _queue.is_empty() and is_inside_tree():
		while _busy_app() and is_inside_tree():          # never during a match: no hitches in play
			await get_tree().create_timer(0.5).timeout
		if _queue.is_empty():
			break
		var q: Array = _queue.pop_front()
		var kind: String = q[0]
		var id: String = q[1]
		var tex := cached(kind, id)
		if tex == null:
			if kind == "room":
				tex = await _render_room(id)
			else:
				tex = await _render_scene(id)
			if tex:
				_mem[_key(kind, id)] = tex
		done.emit(kind, id, tex)
		await get_tree().process_frame
	_running = false
	_teardown()
	if _worker == self:
		_worker = null
	queue_free()

## The app is in a match (or loading): wait.
func _busy_app() -> bool:
	var app := get_tree().root.get_node_or_null("Main")
	if app == null or not ("screen" in app):
		return false
	return str(app.screen) in ["ludo", "sl", "splash"]

## Size a SubViewport's positional shadow atlas like the main view's (Quality.shadow_atlas_size(): the tier's atlas,
## or none at all while no light casts positional shadows; quadrant 0 a single slot, for the café's one shadowed spot
## light), instead of the SubViewport defaults (quadrant 0 split in 4, the others in 4 / 16 / 64), so a 3D view never
## claims extra slots or renders a coarser shadow. shadows = false: no positional atlas at all (worlds whose lights
## cast no positional shadows).
static func shadow_atlas(vp: Viewport, shadows := true) -> void:
	var n := Quality.shadow_atlas_size() if shadows else 0
	vp.positional_shadow_atlas_size = n
	if n <= 0:
		return
	vp.positional_shadow_atlas_16_bits = bool(Quality.settings().atlas_16)
	vp.positional_shadow_atlas_quad_0 = int(ProjectSettings.get_setting("rendering/lights_and_shadows/positional_shadow/atlas_quadrant_0_subdiv", Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_1)) as Viewport.PositionalShadowAtlasQuadrantSubdiv
	vp.positional_shadow_atlas_quad_1 = Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_DISABLED
	vp.positional_shadow_atlas_quad_2 = Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_DISABLED
	vp.positional_shadow_atlas_quad_3 = Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_DISABLED

func _make_vp(n: String) -> SubViewport:
	var vp := SubViewport.new()
	vp.name = n
	vp.own_world_3d = true
	vp.size = render_size
	vp.msaa_3d = Viewport.MSAA_4X
	vp.transparent_bg = false
	shadow_atlas(vp, n == "RoomThumbs")      # the café's key spot casts the room's one shadow; scenes cast none
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	vp.audio_listener_enable_3d = false
	add_child(vp)
	return vp

## Draw the viewport a few frames and read its picture back; saved to disk, returned mipmapped. The bake tool
## (manual) gets the picture in `last_image` and nothing is written to user://.
var last_image: Image

func _snap(vp: SubViewport, kind: String, id: String) -> Texture2D:
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for i in SETTLE_FRAMES:
		await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if img == null or img.is_empty():
		return null
	img.convert(Image.FORMAT_RGB8)
	if manual:
		last_image = img
		return ImageTexture.create_from_image(img)
	DirAccess.make_dir_recursive_absolute(dir)
	var err := img.save_png(disk_path(kind, id))
	if err != OK:
		push_warning("Thumbnailer: can't save %s (%d)" % [disk_path(kind, id), err])
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _render_room(id: String) -> Texture2D:
	if _room_world == null:
		_room_vp = _make_vp("RoomThumbs")
		_room_world = TableWorld.new()
		_room_world.name = "ThumbWorld"
		_room_vp.add_child(_room_world)
		_room_cam = Camera3D.new()
		_room_cam.fov = ROOM_CAM.fov
		_room_cam.keep_aspect = Camera3D.KEEP_HEIGHT
		_room_cam.near = 0.5
		_room_cam.far = 500.0
		_room_vp.add_child(_room_cam)
		_room_cam.look_at_from_position(ROOM_CAM.pos, ROOM_CAM.look, Vector3.UP)
		_room_cam.make_current()
		await _room_world.build_room(_baker, func(_f: float): pass, id)
		_room_world.home_cups()
	else:
		await _room_world.rooms.set_room(_baker, id)
	if not is_instance_valid(_room_world) or _room_world.rooms == null:
		return null
	_room_cam.make_current()
	var tex := await _snap(_room_vp, "room", id)
	_drop_room(id)                              # one room at a time in memory
	return tex

## Free a built room of the worker's café (rooms build on first use and are kept otherwise).
func _drop_room(id: String) -> void:
	var r := _room_world.rooms
	var n: Node = r._built.get(id)
	if n:
		r._built.erase(id)
		r._room_anims.erase(id)
		n.queue_free()
	if r.current == id:
		r.current = ""

func _render_scene(id: String) -> Texture2D:
	if _scene_world == null:
		_scene_vp = _make_vp("SceneThumbs")
		_scene_world = SLScenes.new()
		_scene_world.name = "ThumbScenes"
		_scene_vp.add_child(_scene_world)
		_scene_board = SLBoard.new()
		_scene_board.name = "ThumbSLBoard"
		_scene_world.attach_board(_scene_board)
		await _scene_board.build(_baker)
		_scene_board.setup_players([])
	await _scene_world.set_scene(_baker, id)
	if not is_instance_valid(_scene_world):
		return null
	_scene_world.play(false)
	_scene_world.reduced_motion = true
	_scene_world.snap_camera()
	# the landing sign is hung at 82% of the screen width: on a 4:3 picture that hides the scene, so it shrinks
	# (around its anchor, high in the frame) to about the share it has on the web's 3:4 thumbnails
	var sign: Node3D = _scene_world._sign
	if sign:
		sign.basis = sign.basis.scaled_local(Vector3.ONE * SIGN_SCALE)
		sign.position.y += SIGN_LIFT
	_scene_world.camera.make_current()
	return await _snap(_scene_vp, "scene", id)

func _teardown() -> void:
	for vp in [_room_vp, _scene_vp]:
		if is_instance_valid(vp):
			vp.queue_free()
	_room_vp = null
	_room_world = null
	_room_cam = null
	_scene_vp = null
	_scene_world = null
	_scene_board = null
