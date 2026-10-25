class_name Quality
extends RefCounted
## Graphics quality tiers for phones from low-end to flagship: "low" / "medium" / "high".
##
## Auto-detected once at startup from the device (RAM, CPU cores, the GPU's name / vendor, the screen size), unless the
## player picked one (Settings > Graphics: Save.prefs.quality "auto" (default) | "low" | "medium" | "high"; debug
## builds also take `--quality=low` on the command line or in user://debug_args.txt (ARGS_FILE; on Android, where the
## launch intent's extras don't reach the 4.7 template: `adb shell run-as com.flipfold.ludozing sh -c
## 'echo --quality=low > files/debug_args.txt'`, tools/lowspec-capture.sh does this).
## Quality.apply(get_viewport()) at the start of main.gd sets the 3D side of the main view:
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
## re-applies it at once to the viewport given to apply() and to every SubViewport under the root; only what was
## baked at launch (the procedural textures' size, texture_scale()) waits for the next launch (needs_restart()).
##
## Detection (classify(), a pure function of the device facts so the tests can feed it phones; detect() reads the
## real device): the weakest of the GPU class (gpu_class(): a table of mobile GPU families by their GL_RENDERER name,
## with the core count "MC2" / "MP4" where the family spans weak and strong parts and the driver names it), the RAM class (marketing size:
## <= 3 GB low, 4 GB medium, 6 GB+ high) and the CPU (4 cores or fewer: low). See docs in classify().

const TIERS := ["low", "medium", "high"]
const SETTINGS := {
	low = {scale = 0.67, msaa = Viewport.MSAA_DISABLED, aniso = Viewport.ANISOTROPY_DISABLED, atlas = 1024,
		atlas_16 = true, game_fps = 30, menu_fps = 30, extras = false, live = false, shadow_filter = 0, tex = 0.5},
	medium = {scale = 0.85, msaa = Viewport.MSAA_2X, aniso = Viewport.ANISOTROPY_4X, atlas = 2048,
		atlas_16 = true, game_fps = 60, menu_fps = 30, extras = true, live = true, shadow_filter = 1, tex = 0.75},
	high = {scale = 1.0, msaa = Viewport.MSAA_4X, aniso = Viewport.ANISOTROPY_8X, atlas = 2048,
		atlas_16 = false, game_fps = 60, menu_fps = 30, extras = true, live = true, shadow_filter = 2, tex = 1.0},
}
## The settings only read while the app starts (the procedural textures are baked once): once something has read
## them (texture_scale()), a tier that changes them shows "next launch" in Settings.
const LAUNCH_ONLY := ["tex"]
## The 3D buffer's pixel budget per tier (a 1080 x 2400 screen is 2.6 MP): big screens on weak GPUs scale further.
const MAX_3D_PIXELS := {low = 900000, medium = 1800000, high = 4000000}
const MIN_SCALE := 0.5
## RAM classes by the physical size the OS reports (a "3 GB" phone reports ~2.7-2.9 GB, "4 GB" ~3.5-3.8, "6 GB"
## ~5.4-5.8): below RAM_LOW_GB is a 2 / 3 GB phone, below RAM_HIGH_GB a 4 GB one.
const RAM_LOW_GB := 3.4
const RAM_HIGH_GB := 5.0
## A screen's short side from which a phone counts as a 1080p one (the guess for an unknown GPU, see classify()).
const FHD_SIDE := 1000
## Debug builds: extra command-line options read from this file (whitespace-separated), for phones where the launch
## command line can't be changed.
const ARGS_FILE := "user://debug_args.txt"

## Detection facts (filled by detect(); the perf overlay and dev/perf_probe print them).
static var info := {}
## Tests: a stand-in for the Save autoload (set_tier / pref read and write its prefs instead of the real save file).
static var save_node: Node
static var _tier := ""
static var _detected := ""
static var _launch := ""                 # the tier of the first apply() (what the launch-only settings were made at)
static var _vp: WeakRef
static var _file_args: Variant = null    # ARGS_FILE's options (read once)
static var _tex_used := false            # texture_scale() was read (textures were baked at the launch tier's size)


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
	var a := arg("quality")
	if TIERS.has(a):
		return a
	return saved_pref()

## Only the saved choice (Settings shows it; the command line doesn't change what the player picked).
static func saved_pref() -> String:
	var save := _save()
	if save and save.get("prefs") is Dictionary:
		var q := str((save.get("prefs") as Dictionary).get("quality", "auto"))
		return q if TIERS.has(q) else "auto"
	return "auto"

## A debug build's command-line option `--<name>=<value>` ("" when absent; release builds: always ""); a bare
## `--<name>` gives "1". Reads the user args (after `--`), the engine's own and ARGS_FILE's.
static func arg(name: String) -> String:
	if not OS.is_debug_build():
		return ""
	if _file_args == null:
		var txt := FileAccess.get_file_as_string(ARGS_FILE) if FileAccess.file_exists(ARGS_FILE) else ""
		_file_args = txt.replace("\n", " ").replace("\t", " ").split(" ", false)
	for a: String in OS.get_cmdline_user_args() + OS.get_cmdline_args() + (_file_args as PackedStringArray):
		if a == "--" + name:
			return "1"
		if a.begins_with("--" + name + "="):
			return a.trim_prefix("--" + name + "=")
	return ""

## Settings: pick a tier ("auto" for the detected one), save it and apply it at once to the viewport given to apply()
## and to the SubViewports under the root (the dice, an open preview).
static func set_tier(t: String) -> void:
	var save := _save()
	if save and save.get("prefs") is Dictionary:
		(save.get("prefs") as Dictionary).quality = t if TIERS.has(t) else "auto"
		if save.has_method("save"):
			save.save()
	_tier = t if TIERS.has(t) else detected()
	var vp: Viewport = _vp.get_ref() if _vp else null
	if is_instance_valid(vp):
		apply(vp)
		apply_subs(vp)

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
	_tex_used = true
	return float(settings().tex)

## The Shop's PreviewSheet goes live by itself (low: it stays on the baked picture until tapped).
static func live_previews() -> bool:
	return bool(settings().live)

## Tier `t` differs from the launch's in a setting that is only read at startup (LAUNCH_ONLY: the texture size, once
## something baked with texture_scale()), so part of it waits for the next launch.
static func needs_restart(t: String) -> bool:
	if not _tex_used:
		return false
	t = t if TIERS.has(t) else detected()
	var at := _launch if _launch != "" else tier()
	for k: String in LAUNCH_ONLY:
		if SETTINGS[t][k] != SETTINGS[at][k]:
			return true
	return false


# ---------- applying ----------

## The main view (call once at startup, from main.gd's _ready): 3D resolution scale, MSAA, anisotropy, the positional
## shadow atlas and its filter. The frame cap stays main.gd's job (game_fps() / menu_fps()).
static func apply(viewport: Viewport) -> void:
	if viewport == null:
		return
	_vp = weakref(viewport)
	var t := tier()
	if _launch == "":
		_launch = t
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

## Every SubViewport under `root` (the live ones: the HUD dice, an open preview, the thumbnailer's): apply_sub(),
## keeping a viewport without a shadow atlas without one. Returns how many it touched.
static func apply_subs(root: Node) -> int:
	var n := 0
	for c in root.find_children("*", "SubViewport", true, false):
		var vp := c as SubViewport
		apply_sub(vp, vp.positional_shadow_atlas_size > 0)
		n += 1
	return n

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

## low / medium / high from the real device (classify() of device_info()); the facts and the reasons land in `info`.
static func detect() -> String:
	info = classify(device_info())
	return str(info.tier)

## The facts detection uses: ram_gb (physical, as reported), cores, gpu (GL_RENDERER), vendor (GL_VENDOR), screen
## (pixels), mobile, model (the phone's model name, for the overlay / reports only).
static func device_info() -> Dictionary:
	var mem: Dictionary = OS.get_memory_info()
	var phys := float(mem.get("physical", -1))
	var ram := meminfo_total()               # Linux / Android: MemTotal (Godot's "physical" is unreliable there)
	if ram <= 0.0:
		ram = phys
	var headless := DisplayServer.get_name() == "headless"
	return {
		ram_gb = ram / 1073741824.0,
		ram_physical = phys,
		cores = OS.get_processor_count(),
		gpu = RenderingServer.get_video_adapter_name(),
		vendor = RenderingServer.get_video_adapter_vendor(),
		screen = DisplayServer.screen_get_size() if not headless else Vector2i.ZERO,
		mobile = OS.has_feature("mobile"),
		model = OS.get_model_name(),
	}

## The RAM size from /proc/meminfo's MemTotal in bytes (Linux / Android), -1 when unreadable. `path`: tests.
static func meminfo_total(path := "/proc/meminfo") -> float:
	var txt := ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f:
		# /proc files report a length of 0, so read a block (and don't trust eof_reached())
		txt = f.get_buffer(4096).get_string_from_utf8()
		if not txt.contains("MemTotal:"):
			f.seek(0)
			for i in 8:
				txt += f.get_line() + "\n"
	if not txt.contains("MemTotal:") and path.begins_with("/proc/") and OS.get_name() in ["Android", "Linux"]:
		var out := []
		if OS.execute("cat", [path], out) == 0 and out.size() > 0:   # Android: FileAccess can't open /proc
			txt = str(out[0])
	for l in txt.split("\n"):
		if l.begins_with("MemTotal:"):
			var kb := l.trim_prefix("MemTotal:").strip_edges().split(" ", false)
			return float(kb[0]) * 1024.0 if kb.size() > 0 else -1.0
	return -1.0

## The tier for a device (keys as device_info(); missing ones count as unknown). Returns the facts plus gpu_class,
## ram_class, tier and why (a short reason). Rules:
##   desktop: high (medium on an old integrated / software GPU)
##   phone:   the weakest of
##              GPU class   gpu_class(gpu, vendor); unknown or emulator: medium on a 1080p+ screen, low on a 720p
##                          one (nearly every 720p phone sold 2020-2026 has an entry GPU)
##              RAM class   < RAM_LOW_GB low (2-3 GB), < RAM_HIGH_GB medium (4 GB), else high; unknown: no limit
##              CPU         4 cores or fewer: low (Helio A22, Snapdragon 425, and the 2-core emulator)
static func classify(d: Dictionary) -> Dictionary:
	var ram_gb := float(d.get("ram_gb", -1.0))
	var cores := int(d.get("cores", 0))
	var gpu := str(d.get("gpu", ""))
	var vendor := str(d.get("vendor", ""))
	var screen: Vector2i = d.get("screen", Vector2i.ZERO)
	var mobile := bool(d.get("mobile", true))
	var emu := is_emulator(gpu, vendor)
	var g := "" if emu else gpu_class(gpu, vendor)
	var r := ""
	if ram_gb > 0.0:
		r = "low" if ram_gb < RAM_LOW_GB else ("medium" if ram_gb < RAM_HIGH_GB else "high")
	var t: String
	var why: String
	if not mobile and not emu:
		t = "medium" if g == "low" else "high"
		why = "desktop" + (" (weak GPU)" if g == "low" else "")
	else:
		var short := mini(screen.x, screen.y)
		var gg := g
		var note := ""
		if gg == "":
			gg = "medium" if short >= FHD_SIDE or short <= 0 else "low"
			note = " (%s, %d px screen)" % ["emulator" if emu else "unknown GPU", short]
		t = _min_tier(gg, r if r != "" else "high")
		why = "gpu %s%s, ram %s" % [gg, note, r if r != "" else "?"]
		if cores > 0 and cores <= 4 and t != "low":
			t = "low"
			why += ", %d cores" % cores
	var out := d.duplicate()
	out.ram_gb = snappedf(ram_gb, 0.1)
	out.merge({emulator = emu, gpu_class = g, ram_class = r, tier = t, why = why}, true)
	return out

## The Android emulator (or another translated GL): its GPU name is the host's, so it says nothing about the phone.
static func is_emulator(gpu: String, vendor := "") -> bool:
	var n := (gpu + " " + vendor).to_lower()
	return n.contains("emulator") or n.contains("translator") or n.contains("goldfish") or n.contains("ranchu")

## The GPU's class from its GL_RENDERER name (and vendor): "low" | "medium" | "high", "" when unknown. Native names
## ("Mali-G57 MC2", "PowerVR Rogue GE8320", "Adreno (TM) 610") and ANGLE ones ("ANGLE (Samsung Xclipse 920) on Vulkan
## 1.1.179", "ANGLE (ARM, Vulkan 1.3.278 (Mali-G52 MC2 (0x74021000)), ...)") both work. Families spanning weak and
## strong parts are split by the core count where the driver gives one: MediaTek's do ("Mali-G57 MC2"), Unisoc's,
## Exynos' and Tensor's never do ("Mali-G57" on a T606 / T612 is the MP1; "Mali-G68" on an Exynos 1280 / 1330 / 1380),
## so a bare "Mali-G57" counts as the weak MP1 and a bare "Mali-G68" as the mid one.
## Classes by GFXBench Manhattan 3.1 offscreen (notebookcheck medians, fps): low < ~20, medium ~20-50, high > ~50:
##   low     PowerVR GE8300 4.3 (Helio A22), GE8322 6.5 (SC9863A), GE8320 6.7 (Helio P35 / G25-G37); Adreno 506 6.4,
##           Adreno 610 13 (SD 662-685); Mali-G57 MP1 8.8 (Unisoc T606 / T612 / T616), G52 MP1 9.4 (Exynos 850),
##           G52 MC2 15 (Helio G70-G88), G72 MP3 (Exynos 9611), G71 MP2, G31 / G51 / G310, Mali-4xx / T-series
##   medium  Mali-G57 MC2 25 (Helio G99, Dimensity 700 / 6100+), G68 MP2 24 / MP4 42 / MP5 52, G76 under MC10 (Helio
##           G90-G95), G71 / G72 with 6+ cores, G510, G610 / G615 under MC4; Adreno 512-540, 612-629 (619: 34), 70x;
##           PowerVR GM9446 / BXM
##   high    Adreno 630-699 (642L: 57), 710+ (710: 53, 730: 143), 8xx; Mali-G76 MC10+, G77, G78 (MP20: 65), G610 /
##           G615 MC4+ (MC6: 163), G710+ (MP7: 97); Immortalis, Xclipse (530: 67, 920: 125), Apple, PowerVR DXT,
##           Maleoon
static func gpu_class(gpu: String, vendor := "") -> String:
	var n := (gpu + " " + vendor).to_lower()
	var re := RegEx.new()
	var cores := _gpu_cores(n)
	if n.contains("adreno"):
		re.compile("adreno[^0-9]*([0-9]{3})")
		var m := re.search(n)
		if m == null:
			return "medium"
		var v := int(m.get_string(1))
		if v < 512:
			return "low"                         # 3xx, 4xx, 504-510
		if v < 610:
			return "medium"                      # 512 (SD 660), 530, 540
		if v <= 611:
			return "low"                         # 610 (SD 662-685): between a Mali-G52 MP1 and MC2
		if v < 630:
			return "medium"                      # 612-629 (SD 4 Gen 1 / 480 / 695 / 720G / 765G)
		if v < 700:
			return "high"                        # 630-699
		if v < 710:
			return "medium"                      # 70x (entry parts)
		return "high"                            # 710+, 8xx
	if n.contains("immortalis") or n.contains("xclipse") or n.contains("apple") or n.contains("maleoon"):
		return "high"
	if n.contains("mali"):
		if n.contains("mali-4") or n.contains("mali-t") or n.contains("mali 4") or n.contains("mali t"):
			return "low"
		re.compile("mali[- ]?g([0-9]{2,3})")
		var m := re.search(n)
		if m == null:
			return "medium"
		var v := int(m.get_string(1))
		if v >= 100:                             # the 3-digit generation: G310 entry, G510 / G57x mid, G610+ high
			if v < 500:
				return "low"
			if v < 610:
				return "medium"
			if v < 700:
				return "high" if cores == 0 or cores >= 4 else "medium"   # G610 / G615 MC2 (Dimensity 7300) mid
			return "high"
		if v in [31, 51, 52]:
			return "low"
		if v == 57:
			return "medium" if cores >= 2 else "low"     # bare "Mali-G57": Unisoc's MP1
		if v in [71, 72]:
			return "medium" if cores >= 6 else "low"     # G72 MP3 (Exynos 9611, Helio P60 / P70), G71 MP2
		if v == 68:
			return "medium"
		if v == 76:
			return "high" if cores >= 10 else "medium"   # G76 MC4 (Helio G90 / G95) mid, MP10-12 (Exynos 9820 / 990)
		return "high"                            # G77, G78
	if n.contains("powervr") or n.contains("imagination"):
		if n.contains("dxt") or n.contains("cxt"):
			return "high"                        # D- / C-Series (Tensor G5)
		if n.contains("bxm") or n.contains("gm9") or n.contains("gt7"):
			return "medium"                      # B-Series (Dimensity 930 / 6020, moto g54 / g64), GM9446 (Helio P90)
		return "low"                             # Rogue GE8xxx, G6xxx, SGX
	if n.contains("intel") and (n.contains("hd graphics") or n.contains("uhd graphics 6")):
		return "low"
	if n.contains("llvmpipe") or n.contains("swiftshader") or n.contains("software"):
		return "low"
	return ""

## A Mali's core count from its name ("Mali-G57 MC2", "Mali-G78 MP14"), 0 when the name has none.
static func _gpu_cores(n: String) -> int:
	var re := RegEx.new()
	re.compile("\\b(?:mc|mp)\\s?([0-9]{1,2})\\b")
	var m := re.search(n)
	return int(m.get_string(1)) if m else 0

static func _min_tier(a: String, b: String) -> String:
	return TIERS[mini(TIERS.find(a), TIERS.find(b))]

static func _save() -> Node:
	if save_node:
		return save_node
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("Save") if tree and tree.root else null
