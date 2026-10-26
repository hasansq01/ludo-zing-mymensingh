extends Node
## Dev: renders the BrandLogo (as supplied, real Lilita One lettering and gold shader) on transparent background
## into a PNG for the Play feature graphic (matted from a black and a white render, since the window has no alpha):
##   godot --path . --resolution 1080x1000 res://dev/store_logo.tscn -- <out_dir>
## Writes <out_dir>/logo_black.png and logo_white.png. Touches no save.

func _ready() -> void:
	var out := "/tmp"
	var args := OS.get_cmdline_user_args()
	if args.size():
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var logo := BrandLogo.new()
	logo.size = Vector2(300, 249)
	logo.position = Vector2(45, 60)
	add_child(logo)
	for pair in [["black", Color.BLACK], ["white", Color.WHITE]]:
		bg.color = pair[1]
		for i in 6:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/logo_%s.png" % [out, pair[0]])
	get_tree().quit()
