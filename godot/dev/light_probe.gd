extends Node
## Is Light3D.light_color treated as sRGB (converted to linear) by this renderer? Renders a white plane lit by
## a directional light of colour #808080 at energy 1 with no ambient, and prints the pixel value.
func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.BLACK
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new(); we.environment = env; add_child(we)
	var m := StandardMaterial3D.new(); m.albedo_color = Color.WHITE; m.roughness = 1.0; m.specular = 0.0
	var pl := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(10, 10); pl.mesh = pm; pl.material_override = m; add_child(pl)
	var l := DirectionalLight3D.new(); l.light_color = Color("#808080"); l.light_energy = 1.0; add_child(l)
	l.look_at_from_position(Vector3(0, 5, 0), Vector3.ZERO, Vector3.FORWARD)
	var cam := Camera3D.new(); add_child(cam); cam.look_at_from_position(Vector3(0, 4, 0.01), Vector3.ZERO)
	for k in 5:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	print("PROBE light #808080 on white -> ", img.get_pixel(img.get_width() / 2, img.get_height() / 2))
	l.light_color = Color.WHITE; l.light_energy = 0.5
	for k in 3:
		await RenderingServer.frame_post_draw
	img = get_viewport().get_texture().get_image()
	print("PROBE white x0.5 -> ", img.get_pixel(img.get_width() / 2, img.get_height() / 2))
	get_tree().quit()
