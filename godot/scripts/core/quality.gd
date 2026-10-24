class_name Quality
extends RefCounted
## Graphics quality tiers for phones from low-end to flagship: "low" / "medium" / "high".
##
## Auto-detected once at startup from the device (RAM, CPU cores, the GPU's name / vendor, the screen size), unless the
## player picked one (Save.prefs.quality: "auto" (default) | "low" | "medium" | "high"; debug builds also take
## `-- --quality=low`). Quality.apply(get_viewport()) at the start of main.gd sets the 3D side of the main view:
##
##   tier     3D scale*  MSAA  aniso  shadow atlas**  match fps  menu fps  room extras***  live previews  textures
##   low      0.67       off   off    1024, 16-bit    30         30        off             on tap only    0.5
##   medium   0.85       2x    4x     2048, 16-bit    60         30        on              yes            0.75
##   high     1.0        4x    8x     2048            60         30        on              yes            1.0
##   *   capped further so the 3D buffer never exceeds MAX_3D_PIXELS on big screens (never below MIN_SCALE); the 2D
##       interface always draws at full resolution
##   **  0 (no atlas at all) while no light casts positional shadows (TableWorld.SHADOWS is off)
##   *** steam, light shafts, sways, particles: callers check Quality.extras()
##
## Others read: Quality.tier(), game_fps(), menu_fps(), extras(), live_previews(), texture_scale(), shadow_atlas_size(), and call
## apply_sub(vp) on their own 3D SubViewports (MSAA + atlas per tier). set_tier(t) (Settings) saves the choice and
## re-applies it to the viewport given to apply().

const TIERS := ["low", "medium", "high"]
const SETTINGS := {
	low = {scale = 0.67, msaa = Viewport.MSAA_DISABLED, aniso = Viewport.ANISOTROPY_DISABLED, atlas = 1024,
		atlas_16 = true, game_fps = 30, menu_fps = 30, extras = false, live = false, shadow_filter = 0, tex = 0.5},
	medium = {scale = 0.85, msaa = Viewport.MSAA_2X, aniso = Viewport.ANISOTROPY_4X, atlas = 2048,
		atlas_16 = true, game_fps = 60, menu_fps = 30, extras = true, live = true, shadow_filter = 1, tex = 0.75},
	high = {scale = 1.0, msaa = Viewport.MSAA_4X, aniso = Viewport.ANISOTROPY_8X, atlas = 2048,
		atlas_16 = false, game_fps = 60, menu_fps = 30, extras = true, live = true, shadow_filter = 2, tex = 1.0},
}
## The 3D buffer's pixel budget per tier (a 1080 x 2400 screen is 2.6 MP): big screens on weak GPUs scale further.
const MAX_3D_PIXELS := {low = 900000, medium = 1800000, high = 4000000}
const MIN_SCALE := 0.5

## Detection facts (filled by detect(); dev/perf_probe prints them).
static var info := {}
static var _tier := ""
static var _detected := ""
static var _vp: WeakRef


# ---------- the tier ----------

## The tier in use: the player's choice, else the detected one.
static func tier() -> String:
	if _tier == "":
		var p := pref()
		_tier = p if TIERS.has(p) else detected()
	return _tier

## The tier this device gets on "auto".
static func detected() -> String:
	if _detected == "":
		_detected = detect()
	return _detected

## The saved choice: "auto" | "low" | "medium" | "high" (debug builds: `--quality=<tier>` on the command line wins).
static func pref() -> String:
	if OS.is_debug_build():
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--quality="):
				return a.trim_prefix("--quality=")
	var save := _save()
	if save and save.prefs is Dictionary:
		var q := str((save.prefs as Dictionary).get("quality", "auto"))
		return q if TIERS.has(q) else "auto"
	return "auto"

## Settings: pick a tier ("auto" for the detected one), save it and apply it at once to the viewport given to apply().
static func set_tier(t: String) -> void:
	var save := _save()
	if save and save.prefs is Dictionary:
		save.prefs.quality = t if TIERS.has(t) else "auto"
		if save.has_method("save"):
			save.save()
	_tier = t if TIERS.has(t) else detected()
	var vp: Viewport = _vp.get_ref() if _vp else null
	if is_instance_valid(vp):
		apply(vp)

## Forces a tier for this run only (dev tools, tests); "" goes back to the saved choice / detection.
static func force(t: String) -> void:
	_tier = t if TIERS.has(t) else ""

static func settings(t := "") -> Dictionary:
	return SETTINGS[t if TIERS.has(t) else tier()]

static func game_fps() -> int:
	return int(settings().game_fps)

static func menu_fps() -> int:
	return int(settings().menu_fps)

## Animated room / scene extras (steam, light shafts, sways, particles) run.
static func extras() -> bool:
	return bool(settings().extras)

## The share of their nominal size the procedural textures (TexBaker) should be baked at: low 0.5 (a 2048 board
## becomes 1024: a quarter of the memory), medium 0.75, high 1. TexBaker can keep its painters' coordinates by
## rendering into vp.size = size * k with size_2d_override = size and size_2d_override_stretch = true.
static func texture_scale() -> float:
	return float(settings().tex)

## The Shop's PreviewSheet goes live by itself (low: it stays on the baked picture until tapped).
static func live_previews() -> bool:
	return bool(settings().live)


# ---------- applying ----------

## The main view (call once at startup, from main.gd's _ready): 3D resolution scale, MSAA, anisotropy, the positional
## shadow atlas and its filter. The frame cap stays main.gd's job (game_fps() / menu_fps()).
static func apply(viewport: Viewport) -> void:
	if viewport == null:
		return
	_vp = weakref(viewport)
	var t := tier()
	var s := settings(t)
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR   # the only mode the Compatibility renderer has
	viewport.scaling_3d_scale = render_scale(t, Vector2(viewport.get_visible_rect().size) if viewport is SubViewport else Vector2(DisplayServer.window_get_size()))
	viewport.msaa_3d = s.msaa
	viewport.anisotropic_filtering_level = s.aniso
	viewport.positional_shadow_atlas_size = shadow_atlas_size(t)
	viewport.positional_shadow_atlas_16_bits = bool(s.atlas_16)
	RenderingServer.positional_soft_shadow_filter_set_quality(int(s.shadow_filter) as RenderingServer.ShadowQuality)
	RenderingServer.directional_soft_shadow_filter_set_quality(int(s.shadow_filter) as RenderingServer.ShadowQuality)

## A 3D SubViewport of the interface (preview, dice, thumbnails): MSAA and anisotropy per tier (no extra scaling:
## those are small). shadows = false: no positional atlas (worlds whose lights cast none).
static func apply_sub(vp: SubViewport, shadows := true) -> void:
	var s := settings()
	vp.msaa_3d = s.msaa
	vp.anisotropic_filtering_level = s.aniso
	vp.positional_shadow_atlas_size = shadow_atlas_size() if shadows else 0
	vp.positional_shadow_atlas_16_bits = bool(s.atlas_16)

## The 3D render scale for a window of `px` pixels: the tier's scale, lowered until the 3D buffer fits the tier's
## pixel budget (never below MIN_SCALE).
static func render_scale(t := "", px := Vector2.ZERO) -> float:
	t = t if TIERS.has(t) else tier()
	var k := float(SETTINGS[t].scale)
	var n := px.x * px.y
	if n > 0.0:
		k = minf(k, sqrt(float(MAX_3D_PIXELS[t]) / n))
	return clampf(k, MIN_SCALE, 1.0)

## The positional shadow atlas size: 0 while no light casts positional shadows (TableWorld.SHADOWS off), else the
## tier's.
static func shadow_atlas_size(t := "") -> int:
	if not _shadows_on():
		return 0
	return int(settings(t).atlas)

static func _shadows_on() -> bool:
	return TableWorld.SHADOWS


# ---------- detection ----------

## low / medium / high from the device. Desktop: high (medium on an old integrated GPU). Phones: the weakest of the
## GPU class and the RAM class, and low with 4 or fewer cores.
static func detect() -> String:
	var mem: Dictionary = OS.get_memory_info()
	var ram_gb := float(mem.get("physical", -1)) / 1073741824.0
	var cores := OS.get_processor_count()
	var gpu := RenderingServer.get_video_adapter_name()
	var vendor := RenderingServer.get_video_adapter_vendor()
	var screen := DisplayServer.screen_get_size() if DisplayServer.get_name() != "headless" else Vector2i.ZERO
	var mobile := OS.has_feature("mobile")
	var g := gpu_class(gpu, vendor)
	var r := "high"
	if ram_gb > 0.0:
		r = "low" if ram_gb < 3.2 else ("medium" if ram_gb < 5.5 else "high")
	var t: String
	if not mobile:
		t = "medium" if g == "low" else "high"
	else:
		t = _min_tier(g if g != "" else "medium", r)
		if cores > 0 and cores <= 4:
			t = "low"
		# a mid GPU driving a 1440p+ panel: the pixel budget already scales the 3D down; nothing more here
	info = {ram_gb = snappedf(ram_gb, 0.1), cores = cores, gpu = gpu, vendor = vendor, screen = screen,
		mobile = mobile, gpu_class = g, ram_class = r, tier = t}
	return t

## The GPU's class from its name: "low" | "medium" | "high", "" when unknown.
static func gpu_class(gpu: String, vendor := "") -> String:
	var n := (gpu + " " + vendor).to_lower()
	var re := RegEx.new()
	if n.contains("adreno"):
		re.compile("adreno[^0-9]*([0-9]{3})")
		var m := re.search(n)
		if m == null:
			return "medium"
		var v := int(m.get_string(1))
		if v < 530:
			return "low"                         # 3xx, 4xx, 505-512
		if v < 620:
			return "medium"                      # 530-540, 610-619
		return "high"                            # 620+, 7xx, 8xx
	if n.contains("mali"):
		if n.contains("mali-4") or n.contains("mali-t") or n.contains("mali 4") or n.contains("mali t"):
			return "low"
		re.compile("mali[- ]?g([0-9]{2,3})")
		var m := re.search(n)
		if m == null:
			return "medium"
		var v := int(m.get_string(1))
		if v >= 100:                             # the 3-digit generation: G310 entry, G510 / G57x mid, G610+ high
			return "low" if v < 500 else ("medium" if v < 610 else "high")
		if v in [31, 51, 52]:
			return "low"
		if v in [57, 71, 72]:
			return "medium"
		return "high"                            # G68, G76-G78
	if n.contains("immortalis") or n.contains("xclipse") or n.contains("apple"):
		return "high"
	if n.contains("powervr"):
		return "low" if (n.contains("ge8") or n.contains("sgx") or n.contains("g6")) else "medium"
	if n.contains("intel") and (n.contains("hd graphics") or n.contains("uhd graphics 6")):
		return "low"
	if n.contains("llvmpipe") or n.contains("swiftshader") or n.contains("software"):
		return "low"
	return ""

static func _min_tier(a: String, b: String) -> String:
	return TIERS[mini(TIERS.find(a), TIERS.find(b))]

static func _save() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("Save") if tree and tree.root else null
