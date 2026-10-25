class_name ShaderWarmUp
extends Node
## Compiles a hidden 3D world's shaders in the background, a few materials per frame, without showing it: the first
## Snakes & Ladders match then doesn't freeze while its shaders compile (PERF: ~1.2 s), and the splash doesn't wait
## for it either. The Compatibility renderer compiles a shader the first time something draws with it, for the
## lights that touch that thing, so the world is drawn for real, with its own lights and environment, into a small
## SubViewport sharing the main World3D:
##   - for one frame per step, the world's nodes move to render layers the main camera doesn't see (WARM: drawn this
##     step, HIDE: not yet), its lights light only WARM, and the café's lights skip both;
##   - the step's group of instances (one material kind) goes to WARM, one frame is drawn, and everything is put back.
## Between steps the caller waits for a quiet moment (main.gd: Home idle, no sheet, no animation).
##
##   var w := ShaderWarmUp.new(); main.add_child(w)
##   w.prepare(sl_scenes, sl_scenes.camera, get_viewport())
##   while not w.finished(): await <quiet>; await w.step(world, world.camera)
##   w.queue_free()

const HIDE := 1 << 18                     ## render layer 19
const WARM := 1 << 19                     ## render layer 20

var _root: Node3D
var _vp: SubViewport
var _cam: Camera3D
var _groups: Array = []                   # [[GeometryInstance3D, ...], ...], one material kind each
var _geo: Array = []                      # every GeometryInstance3D under the root
var _lights: Array = []                   # every Light3D under the root
var _next := 0

## Collect the world's instances (grouped by material kind) and set up the offscreen view: `cam`'s framing and
## environment, the main viewport's aspect and 3D scaling (they decide the shader variants).
func prepare(root: Node3D, cam: Camera3D, main_vp: Viewport) -> void:
	_root = root
	var kinds := {}
	_collect(root, kinds)
	for k in kinds:
		_groups.append(kinds[k])
	var full := main_vp.get_visible_rect().size
	_vp = SubViewport.new()
	_vp.name = "ShaderWarmUp"
	_vp.size = Vector2i(maxi(8, int(full.x / 8.0)), maxi(8, int(full.y / 8.0)))
	_vp.scaling_3d_mode = main_vp.scaling_3d_mode
	_vp.scaling_3d_scale = main_vp.scaling_3d_scale
	_vp.msaa_3d = main_vp.msaa_3d
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_cam = Camera3D.new()
	_cam.cull_mask = ~HIDE & 0xFFFFF
	_cam.keep_aspect = cam.keep_aspect
	_cam.environment = cam.environment
	_cam.projection = cam.projection
	_cam.fov = cam.fov
	_cam.size = cam.size
	_cam.frustum_offset = cam.frustum_offset
	_cam.near = cam.near
	_cam.far = cam.far
	_vp.add_child(_cam)
	add_child(_vp)
	_cam.global_transform = cam.global_transform
	_cam.current = true

func finished() -> bool:
	return _next >= _groups.size()

func steps() -> int:
	return _groups.size()

## Draw the next group for one frame (coroutine). `cafe` / `cafe_cam`: the world on screen and its camera, kept out
## of the hidden world's light and view. Everything is restored before it returns, so it can stop between any two
## steps; root.visible is restored only when nobody else changed it meanwhile.
func step(cafe: Node3D, cafe_cam: Camera3D) -> void:
	if finished() or not is_instance_valid(_root):
		_next = _groups.size()
		return
	var group: Array = _groups[_next]
	_next += 1
	var saved_layers := {}
	for g: GeometryInstance3D in _geo:
		if is_instance_valid(g):
			saved_layers[g] = g.layers
			g.layers = HIDE
	for g: GeometryInstance3D in group:
		if is_instance_valid(g):
			g.layers = WARM
	var saved_masks := {}
	for l: Light3D in _lights:
		if is_instance_valid(l):
			saved_masks[l] = l.light_cull_mask
			l.light_cull_mask = WARM
	var cafe_lights := []
	_find_lights(cafe, cafe_lights)
	for l: Light3D in cafe_lights:
		saved_masks[l] = l.light_cull_mask
		l.light_cull_mask &= ~(HIDE | WARM)
	var cam_mask := cafe_cam.cull_mask if is_instance_valid(cafe_cam) else 0
	if is_instance_valid(cafe_cam):
		cafe_cam.cull_mask = cam_mask & ~(HIDE | WARM)
	var was_visible := _root.visible
	_root.visible = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	if is_instance_valid(_root) and _root.visible:
		_root.visible = was_visible
	for g in saved_layers:
		if is_instance_valid(g):
			g.layers = saved_layers[g]
	for l in saved_masks:
		if is_instance_valid(l):
			l.light_cull_mask = saved_masks[l]
	if is_instance_valid(cafe_cam):
		cafe_cam.cull_mask = cam_mask

## The world on screen, under an opaque splash: its first draw compiles every material it shows in one frame (on a
## slow GL compiler the splash bar then stands still for that long). Draws it a material kind per frame instead:
## everything starts on HIDE (`cam` skips it), each frame one group gets its layers back. `progress(f)` gets 0..1.
## Coroutine; the same total work, spread so no single frame holds it all.
static func reveal_in_steps(root: Node3D, cam: Camera3D, progress: Callable) -> void:
	var w := ShaderWarmUp.new()
	var kinds := {}
	w._collect(root, kinds)
	var groups: Array = kinds.values()
	w.free()
	var saved := {}
	for grp: Array in groups:
		for g: GeometryInstance3D in grp:
			saved[g] = g.layers
			g.layers = HIDE
	var mask := cam.cull_mask
	cam.cull_mask = mask & ~HIDE
	for i in groups.size():
		for g: GeometryInstance3D in groups[i]:
			if is_instance_valid(g):
				g.layers = saved[g]
		await RenderingServer.frame_post_draw
		progress.call(float(i + 1) / groups.size())
	for g in saved:                          # (anything a group missed)
		if is_instance_valid(g) and g.layers == HIDE:
			g.layers = saved[g]
	if is_instance_valid(cam):
		cam.cull_mask = mask

func _collect(n: Node, kinds: Dictionary) -> void:
	if n is Light3D:
		_lights.append(n)
	elif n is GeometryInstance3D:
		var g := n as GeometryInstance3D
		_geo.append(g)
		var k := _kind(g)
		if not kinds.has(k):
			kinds[k] = []
		kinds[k].append(g)
	for c in n.get_children():
		if not c is Viewport:
			_collect(c, kinds)

## A material kind: what makes the renderer generate a different shader (roughly), so each group compiles ~one.
static func _kind(g: GeometryInstance3D) -> String:
	var m: Material = g.material_override
	if m == null and g is MeshInstance3D and (g as MeshInstance3D).mesh and (g as MeshInstance3D).mesh.get_surface_count() > 0:
		m = (g as MeshInstance3D).get_active_material(0)
	if m is ShaderMaterial:
		return "shader:%d" % ((m as ShaderMaterial).shader.get_instance_id() if (m as ShaderMaterial).shader else 0)
	if m is BaseMaterial3D:
		var b := m as BaseMaterial3D
		return "%s|%d|%d|%d|%d|%d|%d|%d|%d|%s|%s|%s|%s" % [g.get_class(), b.shading_mode, b.transparency, b.blend_mode,
			b.cull_mode, b.depth_draw_mode, b.billboard_mode, b.texture_filter, b.specular_mode, b.albedo_texture != null,
			b.vertex_color_use_as_albedo, b.emission_enabled, b.disable_fog]
	return g.get_class()

static func _find_lights(n: Node, out: Array) -> void:
	if not is_instance_valid(n):
		return
	if n is Light3D:
		out.append(n)
	for c in n.get_children():
		if not c is Viewport:
			_find_lights(c, out)
