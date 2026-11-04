extends SceneTree
## Renders the Android launcher icon PNGs from the SVG sources in res://assets/icon/.
## Run from the repo root:
##   godot --headless --path godot --script res://tools/make_icons.gd
## Outputs (referenced by the "Android" preset in export_presets.cfg):
##   icon_192.png                  launcher_icons/main_192x192
##   icon_foreground_432.png       launcher_icons/adaptive_foreground_432x432
##   icon_background_432.png       launcher_icons/adaptive_background_432x432
##   icon_monochrome_432.png       launcher_icons/adaptive_monochrome_432x432

const DIR := "res://assets/icon/"
const JOBS := [
	["icon.svg", "icon_192.png", 192],
	["icon_foreground.svg", "icon_foreground_432.png", 432],
	["icon_background.svg", "icon_background_432.png", 432],
	["icon_monochrome.svg", "icon_monochrome_432.png", 432],
	["icon.svg", "icon_512.png", 512],  # store listing / preview
]


func _init() -> void:
	var failed := false
	for job in JOBS:
		failed = not _render(job[0], job[1], job[2]) or failed
	quit(1 if failed else 0)


func _render(src: String, dst: String, size: int) -> bool:
	var svg := FileAccess.get_file_as_string(DIR + src)
	if svg.is_empty():
		push_error("make_icons: cannot read %s" % (DIR + src))
		return false
	# The SVGs declare width/height (512 or 432); scale so the output is exactly `size`.
	var base := 512.0 if src == "icon.svg" else 432.0
	var img := Image.new()
	var err := img.load_svg_from_string(svg, size / base)
	if err != OK:
		push_error("make_icons: SVG load failed for %s (%s)" % [src, error_string(err)])
		return false
	if img.get_width() != size:
		img.resize(size, size, Image.INTERPOLATE_LANCZOS)
	err = img.save_png(ProjectSettings.globalize_path(DIR + dst))
	if err != OK:
		push_error("make_icons: save failed for %s (%s)" % [dst, error_string(err)])
		return false
	print("make_icons: %s -> %s (%dx%d)" % [src, dst, img.get_width(), img.get_height()])
	return true
