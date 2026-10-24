extends Node
## Dev: does this renderer add light passes in linear light? A white Lambert plane under ambient 0.3 plus one omni
## light worth ~0.3 should read linear 0.6 (sRGB 203); adding in sRGB space would read ~255. Printed for the main
## view and for SubViewports with and without MSAA.
## godot --path . --resolution 390x844 res://dev/blend_probe.tscn

var env: Environment
var omni: OmniLight3D
var spot: SpotLight3D

func _scene(parent: Node) -> void:
	var m := StandardMaterial3D.new(); m.albedo_color = Color.WHITE; m.roughness = 1.0; m.metallic_specular = 0.0
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	var pl := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(10, 10); pl.mesh = pm; pl.material_override = m
	parent.add_child(pl)
	var cam := Camera3D.new(); parent.add_child(cam); cam.look_at_from_position(Vector3(0, 4, 0.01), Vector3.ZERO)
	cam.current = true

func _ready() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.3
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var a := OS.get_cmdline_user_args()
	if "adjust" in a:
		env.adjustment_enabled = true
	if "glow" in a:
		env.glow_enabled = true; env.glow_intensity = 0.0; env.glow_bloom = 0.0; env.glow_hdr_threshold = 4.0
	if "hdr" in a:
		get_viewport().use_hdr_2d = true
	var we := WorldEnvironment.new(); we.environment = env; add_child(we)
	_scene(self)
	omni = OmniLight3D.new(); omni.omni_range = 100; omni.omni_attenuation = 0.0; omni.light_energy = 0.3
	omni.light_specular = 0.0
	omni.position = Vector3(0, 5, 0); add_child(omni)
	spot = SpotLight3D.new(); spot.spot_range = 100; spot.spot_attenuation = 0.0; spot.light_energy = 0.3
	spot.light_specular = 0.0; spot.spot_angle = 40
	spot.shadow_enabled = "shadow" in OS.get_cmdline_user_args()
	add_child(spot); spot.look_at_from_position(Vector3(0, 5, 0.001), Vector3.ZERO)
	if "dir" in OS.get_cmdline_user_args():
		spot.queue_free()
		spot = SpotLight3D.new()
		add_child(spot)
		spot.visible = false
		var d := DirectionalLight3D.new(); d.light_energy = 0.3; d.light_specular = 0.0; d.shadow_enabled = true
		d.rotation = Vector3(-PI / 2, 0, 0)
		add_child(d)
		set_meta("dir", d)
	var vps := {}
	for msaa in [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, 10]:
		var vp := SubViewport.new(); vp.size = Vector2i(64, 64); vp.msaa_3d = msaa % 10
		vp.use_hdr_2d = msaa == 10
		Thumbnailer.shadow_atlas(vp)
		vp.world_3d = get_viewport().find_world_3d()
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(vp)
		var c := Camera3D.new(); vp.add_child(c); c.look_at_from_position(Vector3(0, 4, 0.01), Vector3.ZERO); c.current = true
		vps[msaa] = vp
	for cfg in [["ambient", true, false, false], ["omni", false, true, false], ["spot", false, false, true], ["amb+omni", true, true, false], ["amb+spot", true, false, true], ["all", true, true, true]]:
		env.ambient_light_energy = 0.3 if cfg[1] else 0.0
		omni.visible = cfg[2]
		spot.visible = cfg[3]
		if has_meta("dir"):
			get_meta("dir").visible = cfg[3]
		for k in 4:
			await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var line := "BLEND %-9s main(msaa %d)=%.3f" % [cfg[0], get_viewport().msaa_3d, img.get_pixel(img.get_width() / 2, img.get_height() / 2).r]
		for msaa in vps:
			var vi: Image = vps[msaa].get_texture().get_image()
			line += "  sub(msaa %d)=%.3f" % [msaa, vi.get_pixel(32, 32).r]
		print(line, "   (sRGB values)")
	get_tree().quit()
