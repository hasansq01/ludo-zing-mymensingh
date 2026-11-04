class_name PreviewSheet
extends Sheet
## The Shop's live 3D preview (index.html Preview / #pvSheet / .pv) of a Ludo room or a Snakes & Ladders scene, in
## the PM look: the item's name on the ribbon, the live view, then what it is ("LUDO ROOM" / "S&L SCENE"), its
## description and one action (Buy with its price, "Need 2.5K", Use, or the "In use" pill).
##   room   a SubViewport rendering the app's own World3D (the café, with this room switched in for the preview)
##          through its own orbit camera; drag to turn, pinch / wheel to zoom, the reset button goes back to the start
##          view. Closing switches the café back to the room in use.
##   scene  a SubViewport with its OWN World3D holding a fresh SLScenes + SLBoard (as Thumbnailer builds them, the
##          positional shadow atlas off: scenes cast none), on its landing view: the table turns, the scenery sways;
##          drag spins the table. Nothing in the app's worlds changes; the viewport and its world go on close.
## The sheet opens at once on the item's static snapshot (Thumbnailer.baked: the pre-baked picture shipped in
## assets/thumbs/, else the cached / rendered thumbnail). The live view is built in the background after the open
## animation, then crossfades in once it has drawn its first frame; only then do the drag (and the reset button and
## the drag hint) work. On the "low" quality tier (Quality.tier()) it stays on the snapshot with a "Tap to view in
## 3D" chip that builds the live view on demand. If the view can't start, the snapshot stays with Retry. The
## SubViewport (and, for scenes, its world) is freed when the sheet closes.
## Nothing about the player changes until Buy (asks first, then owns it and puts it in use) or Use. The X is the only
## dismiss control (Back and a backdrop tap too).
##   var pv := PreviewSheet.new("dream"); pv.room_changed.connect(app.apply_room); pv.open(layer)
##   var pv := PreviewSheet.new("frost", "scene"); pv.scene_changed.connect(app.apply_scene); pv.open(layer)

signal room_changed(id: String)          ## room: Buy or Use, the room is in use now
signal scene_changed(id: String)         ## scene: Buy or Use, the scene is in use now
signal bought(id: String)                ## Buy: the item is owned now
signal store_requested                   ## "Open Store" after "not enough gems" (the Shop passes it on to Main)

## Orbit limits, ray-checked on the web in all five rooms so no furniture comes between the camera and the table.
const LIM := {az = [0.3, 0.9], el = [0.0, 0.62], zoom = [0.45, 1.0]}
const HOME := {az = 0.72, el = 0.0, zoom = 1.0}
const LOOK := Vector3(-2, 3, -2)
const MAX_W := 440.0
const LOAD_TIMEOUT := 25.0
const HINT_SEC := 2.0                    # "Drag to look around" fades after this (or on the first drag)
## l10n-keys: room, scene
const KIND_TEXT := {room = "Ludo room", scene = "S&L scene"}
const SPIN_PER_PX := 0.012               # scene: table turn (radians) per dragged px

## Tests: make the 3D start fail (shows the fallback + Retry).
static var debug_fail := false
## The room the café should show and whether a switch is running (shared, so a switch outlives a closed sheet).
static var _want := ""
static var _busy := false

var kind := "room"                       ## "room" | "scene"
var room_id := ""                        ## the item's id (a room id or a scene id)
var ready_3d := false                    # the 3D view is drawing
var failed := false
var o := {}                              # orbit now (eases towards goal)
var goal := {}
var _run := 0
var _loading := false
var _load_t := 0.0
var _ended := false
var _hint_faded := false
var _asking := false                     # the Buy confirm is showing
var _world: TableWorld
var _baker: TexBaker
var _vp: SubViewport
var _cam: Camera3D
var _scenes: SLScenes                    # scene kind: the preview's own S&L world
var _sign_vp := Vector2.ZERO             # the viewport size the scene's sign was last shrunk for
var _tex: TextureRect
var _clip: PanelContainer
var _view: Control
var _fallback: Control
var _hint: Label
var _chip: Button                        # low tier: "Tap to view in 3D"
var _live_tw: Tween
var _tools: Control                      # the reset button
var _msg: PanelContainer
var _info: VBoxContainer
var _kind_l: Label
var _name_l: Label                       ## the ribbon's label (the item's name)
var _desc_l: Label
var _act: Button                         # the action showing now (Buy / Need / Use), null when in use
var _buy: Button
var _need: Button
var _use: Button
var _on_pill: PanelContainer
var _gem: Button                         # "or [gem] N": the same second price as the Shop card
var _busy_gems := false
var _pts := {}                           # pointer id -> last position (touch index, or MOUSE for the mouse)
const MOUSE := 1000


func _init(id: String, kind_ := "room") -> void:
	super(L10n.t(str(_item_of(id, kind_).get("name", ""))), 390.0, true, LOOK_PM)
	kind = "scene" if kind_ == "scene" else "room"
	room_id = id
	_name_l = title_label
	goal = HOME.duplicate()
	o = {az = goal.az, el = goal.el + 0.3, zoom = goal.zoom * 0.8}   # glides in once drawing (inside the limits)
	body.add_theme_constant_override("separation", UIKit.SPACE.md)
	_clip = PanelContainer.new()
	var cs := UIKit.box(Palette.CHIP, UIKit.R.lg)
	UIKit.pad(cs, 0)
	_clip.add_theme_stylebox_override("panel", cs)
	_clip.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	_clip.add_child(_build_view())
	body.add_child(_clip)
	body.add_child(_build_panel())
	process_priority = 10                # after the scene world's own _process (the sign is shrunk after its refit)
	closed.connect(_end)
	tree_exiting.connect(_end)


func _ready() -> void:
	get_viewport().size_changed.connect(_fit)
	_fit()
	_panel()
	_place()
	if low_tier():
		_chip.visible = true                 # the snapshot stays; the live view only on request
		_place()
	else:
		_start_later()

## The live view starts once the open animation has played (never blocking it), a frame apart from it.
func _start_later() -> void:
	await get_tree().create_timer(IN_SEC + 0.05).timeout
	await get_tree().process_frame
	if is_instance_valid(self) and not _ended and not _closing:
		start_3d()

## The static picture of an item, at once: Thumbnailer.baked(kind, id) (pre-baked, shipped in assets/thumbs/) when
## Thumbnailer has it, else assets/thumbs/<kind>_<id>.webp when that file exists, else null.
static func baked(k: String, id: String) -> Texture2D:
	var sc: GDScript = Thumbnailer
	for m: Dictionary in sc.get_script_method_list():
		if m.get("name", "") == "baked":
			var t: Variant = sc.call("baked", k, id)
			if t is Texture2D:
				return t
			break
	var path := "res://assets/thumbs/%s_%s.webp" % [k, id]
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null

## The "low" quality tier (Quality.tier(), when the project has that class): no live 3D unless asked for.
static func low_tier() -> bool:
	for c: Dictionary in ProjectSettings.get_global_class_list():
		if str(c.get("class", "")) == "Quality":
			var q := load(str(c.get("path", ""))) as GDScript
			if q:
				for m: Dictionary in q.get_script_method_list():
					if m.get("name", "") == "tier":
						return str(q.call("tier")) == "low"
			return false
	return false

## The catalogue entry: Catalog.room(id) or SLScenes.info(id).
func _item() -> Dictionary:
	return _item_of(room_id, kind)

static func _item_of(id: String, k: String) -> Dictionary:
	return SLScenes.info(id) if k == "scene" else Catalog.room(id)

## The view's overlays at their corners, sized now that their fonts are known.
func _place() -> void:
	if not is_inside_tree():
		return
	var put := func(c: Control, ax: float, ay: float, dx: float, dy: float) -> void:
		var m := c.get_combined_minimum_size()
		c.anchor_left = ax; c.anchor_right = ax; c.anchor_top = ay; c.anchor_bottom = ay
		c.offset_left = dx - m.x * ax
		c.offset_top = dy - m.y * ay
		c.offset_right = c.offset_left + m.x
		c.offset_bottom = c.offset_top + m.y
	put.call(_hint, 0.0, 1.0, 12.0, -14.0)
	_hint.visible = _view.size.x >= 200.0 and ready_3d and not _hint_faded
	put.call(_chip, 0.5, 1.0, 0.0, -12.0)
	put.call(_tools, 1.0, 1.0, -10.0, -10.0)
	put.call(_msg, 0.5, 0.5, 0.0, 0.0)


# ---------- building ----------

func _build_view() -> Control:
	_view = Control.new()
	_view.clip_contents = true
	_view.mouse_filter = Control.MOUSE_FILTER_STOP
	_view.mouse_default_cursor_shape = Control.CURSOR_DRAG
	_view.gui_input.connect(_view_input)
	_view.resized.connect(_size_vp)
	_view.resized.connect(_place)
	var snap := baked(kind, room_id)
	if snap:
		var tr := TextureRect.new()
		tr.texture = snap
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fallback = tr
	else:
		_fallback = Thumbnailer.view(kind, room_id, 0)        # square: the card's clip rounds it
	_fallback.name = "Snapshot"
	_fallback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view.add_child(_fallback)
	_tex = TextureRect.new()
	_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tex.stretch_mode = TextureRect.STRETCH_SCALE
	_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tex.modulate.a = 0.0
	_view.add_child(_tex)
	# "Drag to look around" (fades after a few seconds or on the first drag)
	_hint = UIKit.label(tr("Drag to spin the board") if kind == "scene" else tr("Drag to look around"), UIKit.FS.label, Color.WHITE, UIKit.font_body(800))
	var hs := UIKit.box(Palette.TOAST, UIKit.R.pill)
	UIKit.pad(hs, 12, 4)
	_hint.add_theme_stylebox_override("normal", hs)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.visible = false
	_view.add_child(_hint)
	# low tier: the live view on request
	_chip = UIKit.button_with(tr("Tap to view in 3D"), UIKit.icon("ic_eye", 20), "white", "sm")
	_chip.name = "View3D"
	_chip.custom_minimum_size.x = 196
	_chip.visible = false
	_chip.pressed.connect(func():
		_chip.visible = false
		start_3d())
	_view.add_child(_chip)
	# back to the start view (pinch / wheel zoom, drag turns)
	var reset := UIKit.icon_button("ic_reset", "glass", UIKit.TAP, 24)
	reset.name = "Reset"
	reset.tooltip_text = tr("Reset view")
	reset.pressed.connect(_reset_view)
	_tools = reset
	_tools.visible = false
	_view.add_child(_tools)
	# the failure message + Retry
	_msg = PanelContainer.new()
	_msg.add_theme_stylebox_override("panel", UIKit.surface("bubble"))
	var mv := UIKit.vbox(UIKit.SPACE.sm)
	mv.add_child(UIKit.label(tr("The 3D preview couldn’t load."), UIKit.FS.body, Palette.INK, UIKit.font_body(800), HORIZONTAL_ALIGNMENT_CENTER))
	var retry := UIKit.btn(tr("Retry"), "honey", "sm")
	retry.name = "Retry"
	retry.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	retry.custom_minimum_size.x = 120
	retry.pressed.connect(start_3d)
	mv.add_child(retry)
	_msg.add_child(mv)
	_msg.visible = false
	_view.add_child(_msg)
	return _view

func _build_panel() -> Control:
	_info = UIKit.vbox(UIKit.SPACE.xs)
	_kind_l = UIKit.eyebrow(L10n.t(KIND_TEXT[kind]))
	_kind_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.add_child(UIKit.margin(_kind_l, UIKit.SPACE.xs, 0, UIKit.SPACE.xs, 0))
	_desc_l = UIKit.paragraph("", UIKit.FS.body, Palette.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_info.add_child(UIKit.margin(_desc_l, UIKit.SPACE.xs, 0, UIKit.SPACE.xs, 0))
	var slot := MarginContainer.new()
	slot.custom_minimum_size.y = UIKit.TAP + 4
	slot.add_theme_constant_override("margin_top", UIKit.SPACE.sm)
	var price := int(_item().get("price", 0))
	_buy = UIKit.button_with(tr("Buy"), CoinAmount.new(price, "md", "plain"), "gold", "md")
	_buy.name = "Buy"
	var row := _buy.get_node("Content") as HBoxContainer
	row.move_child(row.get_child(0), -1)  # "Buy  (coin) 3K"
	_need = UIKit.btn("", "off", "md")
	_need.name = "Need"
	_use = UIKit.btn(tr("Use"), "teal", "md")
	_use.name = "Use"
	for b: Button in [_buy, _need, _use]:
		b.pressed.connect(_on_act)
		slot.add_child(b)
	_on_pill = ShopSheet.in_use_pill()
	_on_pill.custom_minimum_size.y = UIKit.H.md
	slot.add_child(_on_pill)
	_info.add_child(slot)
	if price > 0:                            # the Shop card's "or [gem] N" line
		_gem = ShopSheet.gem_option(Catalog.gem_price(price))
		_gem.pressed.connect(_on_gems)
		_info.add_child(_gem)
	return _info


# ---------- layout ----------

## Width min(440, screen - 2 x GUTTER); the view square, at most 58% of the screen height and 440 px, giving way so
## the whole card fits; short screens drop the kicker and description.
func _fit() -> void:
	if not is_inside_tree():
		return
	var vp := get_viewport_rect().size
	_desc_l.visible = vp.y >= 520.0
	_kind_l.visible = vp.y >= 520.0
	var w := minf(MAX_W, vp.x - 2.0 * UIKit.GUTTER)
	card.custom_minimum_size.x = w
	var st := card.get_theme_stylebox("panel")
	var vw := w - st.get_margin(SIDE_LEFT) - st.get_margin(SIDE_RIGHT)
	var vh := minf(vw, minf(0.58 * (vp.y - 24.0), 440.0))
	var other := (_info.get_combined_minimum_size().y + header.get_combined_minimum_size().y + st.get_margin(SIDE_TOP)
		+ st.get_margin(SIDE_BOTTOM) + 2.0 * UIKit.SPACE.md + 24.0 - RIBBON_TOP)
	vh = clampf(minf(vh, vp.y - other), minf(140.0, vw), vw)
	_view.custom_minimum_size = Vector2(0, roundf(vh))

## The SubViewport renders in device pixels (the UI is scaled to the screen), so the view stays sharp.
func _size_vp() -> void:
	if _vp == null or _view.size.x < 2 or _view.size.y < 2:
		return
	var k := get_viewport().get_screen_transform().get_scale()
	var px := Vector2i((_view.size * k).round())
	px = px.clamp(Vector2i(2, 2), Vector2i(2048, 2048))
	if _vp.size != px:
		_vp.size = px


# ---------- details + Buy / Use ----------

func _owns() -> bool:
	return SLScenes.owns_scene(room_id) if kind == "scene" else Catalog.owns_room(room_id)

func _in_use() -> String:
	return SLScenes.scene_in_use() if kind == "scene" else Catalog.room_in_use()

func _panel() -> void:
	var r := _item()
	if r.is_empty():
		return
	var own := _owns()
	var on := own and _in_use() == room_id
	var short := int(r.price) - Catalog.coins()
	if ribbon and ribbon.label.text != L10n.t(str(r.name)):
		ribbon.set_text(L10n.t(str(r.name)))
	_desc_l.text = L10n.t(r.desc)
	_buy.visible = not own and short <= 0
	_need.visible = not own and short > 0
	_need.text = Fmt.shortfall(short)
	_use.visible = own and not on
	_on_pill.visible = on
	if _gem:
		_gem.visible = not own
	_act = _buy if _buy.visible else _need if _need.visible else _use if _use.visible else null
	for b: Button in [_buy, _use]:
		b.disabled = _loading and kind == "room"   # no room switch while the preview is still building this one

## Buy with gems: the Shop's flow (wallet checks, confirm, purchase, toast).
func _on_gems() -> void:
	var r := _item()
	if r.is_empty() or _busy_gems or _asking or _closing or _owns():
		return
	_busy_gems = true
	_asking = true
	var res: String = await ShopSheet.buy_with_gems(self, "scene" if kind == "scene" else "room", room_id, L10n.t(str(r.name)))
	_asking = false
	_busy_gems = false
	if not is_instance_valid(self) or _closing:
		return
	if res == "store":
		store_requested.emit()
	elif res == "bought":
		bought.emit(room_id)
		_changed()
	_panel()
	_fit()

func _on_act() -> void:
	var r := _item()
	if r.is_empty() or (_loading and kind == "room") or _asking or _closing:
		return
	if _owns():
		if _in_use() == room_id:
			return
		var ok := SLScenes.equip_scene(room_id) if kind == "scene" else Catalog.equip_room(room_id)
		if ok:
			Sound.sfx("select")
			Toast.show(self, tr("%s is in use") % L10n.t(r.name), card, 1.6, "good")
			_changed()
		else:
			Sound.sfx("error")
			Haptics.error()
			Toast.show(self, L10n.t(Catalog.SAVE_FAILED), card, 2.2, "bad")
		_panel()
		return
	var price := int(r.price)
	var short := price - Catalog.coins()
	if short > 0:
		Sound.sfx("error")
		Haptics.error()
		Toast.show(self, tr("Need %s more coins") % Fmt.coins(short), card, 1.8, "bad")
		return
	_asking = true
	var yes: bool = await Sheet.confirm(self, tr("Buy %s?") % L10n.t(r.name), tr("%s coins. You’ll have %s left.") % [Fmt.coins(price), Fmt.coins(Catalog.coins() - price)], tr("Buy"))
	_asking = false
	if not yes or not is_instance_valid(self) or _closing:
		return
	var err := SLScenes.buy_scene(room_id, true) if kind == "scene" else Catalog.buy_room(room_id, true)
	if err == "":
		Sound.sfx("buy")
		Haptics.success()
		Toast.show(self, tr("%s is yours!") % L10n.t(r.name), card, 1.8, "good")
		bought.emit(room_id)
		_changed()
	else:
		Sound.sfx("error")
		Haptics.error()
		Toast.show(self, err, card, 2.2, "bad")
	_panel()

func _changed() -> void:
	if kind == "scene":
		scene_changed.emit(room_id)
	else:
		room_changed.emit(room_id)


# ---------- the 3D view ----------

## Start drawing the item (Retry calls this again). Room: switch the café to the previewed room. Scene: build the
## preview's own S&L world.
func start_3d() -> void:
	_run += 1
	ready_3d = false
	failed = false
	_msg.visible = false
	_fallback.visible = true                 # the thumbnail until the live view draws
	_tex.modulate.a = 0.0
	_tools.visible = false
	if kind == "scene":
		_start_scene()
		return
	var app := _app()
	_world = app.get("world") if app else null
	_baker = app.get("baker") if app else null
	if debug_fail or _world == null or _baker == null or _world.rooms == null or not _can_render():
		_fail()
		return
	_make_vp()
	_loading = true
	_load_t = 0.0
	_panel()
	_want = room_id if Rooms.MOOD.has(room_id) else Rooms.DEFAULT
	_sync(_world, _baker)

func _app() -> Node:
	var root := get_tree().root
	var app := root.get_node_or_null("Main")
	if app == null:
		app = root.find_child("Main", true, false)
	return app if app and "world" in app and "baker" in app else null

static func _can_render() -> bool:
	return DisplayServer.get_name() != "headless" and RenderingServer.get_video_adapter_name() != ""

func _make_vp() -> void:
	if _vp:
		return
	_vp = SubViewport.new()
	_vp.name = "PreviewView"
	_vp.world_3d = _world.get_viewport().find_world_3d()
	_vp.msaa_3d = Viewport.MSAA_4X
	Thumbnailer.shadow_atlas(_vp)        # the café's key spot: one slot, like the main view
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.size = Vector2i(256, 256)
	_cam = Camera3D.new()
	_cam.fov = 50.0                      # three.js PerspectiveCamera(50): vertical
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_cam.near = 0.5
	_cam.far = 500.0
	_vp.add_child(_cam)
	_view.add_child(_vp)
	_cam.current = true
	_size_vp()
	_tex.texture = _vp.get_texture()

## Scene: a SubViewport with its own World3D, a TexBaker, SLScenes and SLBoard (Thumbnailer._render_scene's set-up).
func _start_scene() -> void:
	if debug_fail or not _can_render() or SLScenes.info(room_id).is_empty():
		_fail()
		return
	_drop_vp()
	var run := _run
	_loading = true
	_load_t = 0.0
	_panel()
	_vp = SubViewport.new()
	_vp.name = "ScenePreview"
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.transparent_bg = false
	_vp.audio_listener_enable_3d = false
	Thumbnailer.shadow_atlas(_vp, false)  # the scenes' lights cast no positional shadows: no atlas at all
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.size = Vector2i(256, 256)
	if not is_instance_valid(_baker):
		_baker = TexBaker.new()
		_baker.name = "PreviewBaker"
		add_child(_baker)
	_scenes = SLScenes.new()
	_scenes.name = "PreviewScenes"
	_scenes.reduced_motion = Sheet.reduce_motion()
	_vp.add_child(_scenes)
	_view.add_child(_vp)
	_size_vp()
	var board := SLBoard.new()
	board.name = "PreviewSLBoard"
	_scenes.attach_board(board)
	await board.build(_baker)
	if run != _run or not is_instance_valid(_scenes):
		return
	board.setup_players([])
	await _scenes.set_scene(_baker, room_id)
	if run != _run or not is_instance_valid(_scenes) or _scenes.current != room_id:
		if run == _run and not _ended:
			_fail()
		return
	_scenes.play(false)
	_scenes.snap_camera()
	_shrink_sign()
	_scenes.camera.make_current()
	_tex.texture = _vp.get_texture()
	_go_ready()

## The landing sign is hung at 82% of a phone screen's width; in the near-square view it shrinks (around its anchor,
## high in the frame) like the Shop thumbnails. Again whenever the scene refits to a new view size.
func _shrink_sign() -> void:
	if not is_instance_valid(_scenes) or _scenes._sign == null:
		return
	_sign_vp = _scenes._vp
	var sign: Node3D = _scenes._sign
	sign.basis = sign.basis.scaled_local(Vector3.ONE * Thumbnailer.SIGN_SCALE)
	sign.position.y += Thumbnailer.SIGN_LIFT

func _drop_vp() -> void:
	if _vp:
		_tex.texture = null
		_vp.queue_free()
		_vp = null
		_cam = null
		_scenes = null

func _fail() -> void:
	_loading = false
	ready_3d = false
	failed = true
	_drop_vp()
	_tex.modulate.a = 0.0
	_fallback.visible = true
	_msg.visible = true
	_hint.visible = false
	_tools.visible = false
	_chip.visible = false
	if is_inside_tree():
		_panel()

## The live view draws: once its first frame is rendered it crossfades over the snapshot, and only then can it be
## dragged (reset button, drag hint).
func _go_ready() -> void:
	_loading = false
	var run := _run
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_update_cam(0.0)
	_panel()
	for i in 2:                              # the first frame rendered into the texture
		await RenderingServer.frame_post_draw
		if run != _run or not is_instance_valid(self) or _vp == null:
			return
	ready_3d = true
	_tools.visible = kind == "room"          # a scene's camera is the scene's own: nothing to reset
	_place()
	if _live_tw:
		_live_tw.kill()
	_live_tw = create_tween()
	_live_tw.tween_property(_tex, "modulate:a", 1.0, 0.1 if Sheet.reduce_motion() else 0.3)
	_live_tw.tween_callback(func(): _fallback.visible = not ready_3d)
	if not _hint_faded:
		get_tree().create_timer(HINT_SEC).timeout.connect(_hint_gone)

func _reset_view() -> void:
	goal = HOME.duplicate()
	_clamp()

## One switch at a time; it keeps going until the café shows `_want` (which may change meanwhile, e.g. the sheet closed).
static func _sync(world: TableWorld, baker: TexBaker) -> void:
	if _busy:
		return
	_busy = true
	while is_instance_valid(world) and is_instance_valid(baker) and world.rooms and world.rooms.current != _want:
		await world.rooms.set_room(baker, _want)
	_busy = false

func _process(delta: float) -> void:
	if _loading:
		_load_t += delta
		if kind == "scene":
			if _load_t > LOAD_TIMEOUT:
				_run += 1
				_fail()
		elif not is_instance_valid(_world) or not is_instance_valid(_baker):
			_fail()
		elif not _busy and _world.rooms.current == _want:
			_go_ready()
		elif _load_t > LOAD_TIMEOUT:
			_fail()
		return
	if ready_3d:
		if kind == "scene":
			if is_instance_valid(_scenes) and _scenes._vp != _sign_vp:
				_shrink_sign()
		else:
			_update_cam(delta)

func _update_cam(delta: float) -> void:
	if _cam == null:
		return
	var k := 1.0 - exp(-minf(delta, 0.1) * 7.0) if delta > 0 else 0.0
	for n in ["az", "el", "zoom"]:
		o[n] += (goal[n] - o[n]) * k
	var asp := _view.size.x / maxf(_view.size.y, 1.0)
	# portrait boxes step back so the table and the room's corner stay in view
	var d: float = 50.0 * o.zoom * pow(maxf(1.0, 0.82 / asp), 0.4)
	var el: float = 0.42 + o.el
	var az: float = o.az
	var pos := LOOK + Vector3(sin(az) * cos(el) * d, sin(el) * d, cos(az) * cos(el) * d)
	_cam.look_at_from_position(pos, LOOK, Vector3.UP)

func _clamp() -> void:
	for n in ["az", "el", "zoom"]:
		goal[n] = clampf(goal[n], LIM[n][0], LIM[n][1])

## The sheet closed (or was removed): the room in use comes back (rooms); the scene's own world goes (scenes).
func _end() -> void:
	if _ended:
		return
	_ended = true
	_run += 1
	_loading = false
	ready_3d = false
	_pts.clear()
	_drop_vp()
	if kind == "room" and is_instance_valid(_world) and is_instance_valid(_baker):
		_want = Catalog.room_in_use()
		_sync(_world, _baker)


# ---------- camera input: drag to turn, pinch / wheel to zoom ----------

func _view_input(e: InputEvent) -> void:
	if not ready_3d:                         # the snapshot: nothing to turn yet
		_pts.clear()
		return
	if e is InputEventScreenTouch:
		if e.pressed:
			_pts[e.index] = e.position
			_hint_gone()
		else:
			_pts.erase(e.index)
		_view.accept_event()
	elif e is InputEventScreenDrag:
		_drag(e.index, e.position)
		_view.accept_event()
	elif e is InputEventMouseButton and e.device != InputEvent.DEVICE_ID_EMULATION:
		match e.button_index:
			MOUSE_BUTTON_LEFT:
				if e.pressed:
					_pts[MOUSE] = e.position
					_hint_gone()
				else:
					_pts.erase(MOUSE)
			MOUSE_BUTTON_WHEEL_UP:
				if e.pressed:
					goal.zoom *= exp(-0.12 * maxf(e.factor, 1.0)); _clamp()
			MOUSE_BUTTON_WHEEL_DOWN:
				if e.pressed:
					goal.zoom *= exp(0.12 * maxf(e.factor, 1.0)); _clamp()
		_view.accept_event()
	elif e is InputEventMouseMotion and e.device != InputEvent.DEVICE_ID_EMULATION:
		if _pts.has(MOUSE):
			_drag(MOUSE, e.position)
			_view.accept_event()
	elif e is InputEventMagnifyGesture:
		goal.zoom /= maxf(e.factor, 0.01); _clamp()

func _drag(id: int, pos: Vector2) -> void:
	if not _pts.has(id):
		return
	var p: Vector2 = _pts[id]
	if kind == "scene":                   # the table (and the board on it) turns under the finger
		if _pts.size() == 1 and is_instance_valid(_scenes) and _scenes._table:
			_scenes._table.rotation.y += (pos.x - p.x) * SPIN_PER_PX
		_pts[id] = pos
		return
	var touches := _pts.keys().filter(func(k: int) -> bool: return k != MOUSE)
	if _pts.size() == 1:
		goal.az -= (pos.x - p.x) * 0.008
		goal.el += (pos.y - p.y) * 0.005
	elif touches.size() == 2 and id != MOUSE:
		var other: Vector2 = _pts[touches[0] if touches[1] == id else touches[1]]
		var before := p.distance_to(other)
		var after := pos.distance_to(other)
		if before > 10.0 and after > 10.0:
			goal.zoom *= before / after
	_pts[id] = pos
	_clamp()

func _hint_gone() -> void:
	if _hint_faded:
		return
	_hint_faded = true
	create_tween().tween_property(_hint, "modulate:a", 0.0, 0.4)
