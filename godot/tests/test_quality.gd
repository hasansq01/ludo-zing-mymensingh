extends "res://tests/test_suite.gd"
## Quality tiers: detection on the phones sold in Bangladesh / South Asia 2020-2026 (classify() fed each phone's
## GL_RENDERER, physical RAM as Android reports it, core count and screen), the GPU name table, the RAM classes,
## the emulator rule, the command-line override, Settings' Graphics row and set_tier (saved to a stand-in Save, never
## the real user://save.json), and the overlay's percentile.

## RAM as Android reports it (MemTotal) for a phone sold as N GB.
const GB := {2: 1.8, 3: 2.7, 4: 3.6, 6: 5.5, 8: 7.4, 12: 11.2}

## [phone (model code, SoC), GL_RENDERER as the driver reports it, CPU cores, RAM (marketing GB: the lowest common
## trim), screen, expected tier]. Specs: GSMArena; renderer strings: opengles.gpuinfo.org reports ("exp." where no
## report exists for that model and the string follows from a sibling device with the same SoC).
const PHONES := [
	# --- low: PowerVR GE83xx, Mali-G52, bare Mali-G57 (Unisoc MP1), Adreno 50x / 610, Mali-G72 MP3 ---
	["Samsung Galaxy A03 Core SM-A032F (SC9863A)", "PowerVR Rogue GE8322", 8, 2, Vector2i(720, 1600), "low"],
	["Samsung Galaxy A03 SM-A035F (Unisoc T606)", "Mali-G57", 8, 3, Vector2i(720, 1600), "low"],
	["Samsung Galaxy A03 SM-A035F 4 GB", "Mali-G57", 8, 4, Vector2i(720, 1600), "low"],
	["Samsung Galaxy A04 SM-A045F (Helio P35)", "PowerVR Rogue GE8320", 8, 4, Vector2i(720, 1600), "low"],
	["Samsung Galaxy A04e SM-A042F (Helio P35)", "PowerVR Rogue GE8320", 8, 3, Vector2i(720, 1600), "low"],
	["Samsung Galaxy A05 SM-A055F (Helio G85)", "Mali-G52 MC2", 8, 4, Vector2i(720, 1600), "low"],
	["Samsung Galaxy A05s SM-A057F (Snapdragon 680)", "Adreno (TM) 610", 8, 6, Vector2i(1080, 2400), "low"],
	["Samsung Galaxy A14 4G SM-A145F (Exynos 850)", "Mali-G52", 8, 4, Vector2i(1080, 2408), "low"],
	["Samsung Galaxy A14 4G SM-A145P (Helio G80)", "Mali-G52 MC2", 8, 6, Vector2i(1080, 2408), "low"],
	["Samsung Galaxy A12 (Helio P35)", "PowerVR Rogue GE8320", 8, 4, Vector2i(720, 1600), "low"],
	["Samsung Galaxy A51 (Exynos 9611)", "Mali-G72", 8, 6, Vector2i(1080, 2400), "low"],
	["Samsung Galaxy M02s (Snapdragon 450)", "Adreno (TM) 506", 8, 3, Vector2i(720, 1560), "low"],
	["Xiaomi Redmi 9A M2006C3LG (Helio G25)", "PowerVR Rogue GE8320", 8, 2, Vector2i(720, 1600), "low"],
	["Xiaomi Redmi 9C M2006C3MG (Helio G35)", "PowerVR Rogue GE8320", 8, 3, Vector2i(720, 1600), "low"],
	["Xiaomi Redmi 10A (Helio G25; exp.)", "PowerVR Rogue GE8320", 8, 3, Vector2i(720, 1600), "low"],
	["Xiaomi Redmi 10C 220333QAG (Snapdragon 680)", "Adreno (TM) 610", 8, 4, Vector2i(720, 1650), "low"],
	["Xiaomi Redmi 12C 22120RN86G (Helio G85)", "Mali-G52 MC2", 8, 4, Vector2i(720, 1650), "low"],
	["Xiaomi Redmi 13C 23100RN82L (Helio G85)", "Mali-G52 MC2", 8, 6, Vector2i(720, 1600), "low"],
	["Xiaomi Redmi 14C 2409BRN2CL (Helio G81 Ultra)", "Mali-G52 MC2", 8, 4, Vector2i(720, 1640), "low"],
	["Xiaomi Redmi A1 220733SG (Helio A22, 4 cores)", "PowerVR Rogue GE8300", 4, 2, Vector2i(720, 1600), "low"],
	["Xiaomi Redmi A2 23028RNCAG (Helio G36)", "PowerVR Rogue GE8320", 8, 3, Vector2i(720, 1600), "low"],
	["Xiaomi Redmi A3 23129RN51X (Helio G36)", "PowerVR Rogue GE8320", 8, 4, Vector2i(720, 1650), "low"],
	["Xiaomi Redmi Note 11 2201117TG (Snapdragon 680)", "Adreno (TM) 610", 8, 6, Vector2i(1080, 2400), "low"],
	["Xiaomi Redmi Note 12 4G 23021RAAEG (Snapdragon 685)", "Adreno (TM) 610", 8, 8, Vector2i(1080, 2400), "low"],
	["Xiaomi Redmi Note 13 4G 23129RAA4G (Snapdragon 685)", "Adreno (TM) 610", 8, 8, Vector2i(1080, 2400), "low"],
	["Xiaomi Helio G85 phone, old driver without the MC", "Mali-G52", 8, 4, Vector2i(720, 1600), "low"],
	["Realme C11 2021 RMX3231 (SC9863A)", "PowerVR Rogue GE8322", 8, 2, Vector2i(720, 1600), "low"],
	["Realme C21Y RMX3261 (Unisoc T610)", "Mali-G52", 8, 3, Vector2i(720, 1600), "low"],
	["Realme Narzo 50i RMX3235 (SC9863A)", "PowerVR Rogue GE8322", 8, 2, Vector2i(720, 1600), "low"],
	["Realme C30 RMX3581 (Unisoc T612; exp.)", "Mali-G57", 8, 2, Vector2i(720, 1600), "low"],
	["Realme C33 RMX3624 (Unisoc T612)", "Mali-G57", 8, 3, Vector2i(720, 1600), "low"],
	["Realme C51 RMX3830 (Unisoc T612)", "Mali-G57", 8, 4, Vector2i(720, 1600), "low"],
	["Realme C53 RMX3760 (Unisoc T612, 1080p, 6 GB)", "Mali-G57", 8, 6, Vector2i(1080, 2400), "low"],
	["Realme C55 RMX3710 (Helio G88)", "Mali-G52 MC2", 8, 6, Vector2i(1080, 2400), "low"],
	["Realme C55 on Android 15+ (ANGLE)", "ANGLE (ARM, Vulkan 1.3.278 (Mali-G52 MC2 (0x74021000)), Mali-G52 MC2-49.1.0)", 8, 6, Vector2i(1080, 2400), "low"],
	["Tecno Spark 8C KG5n (Unisoc T606)", "Mali-G57", 8, 3, Vector2i(720, 1612), "low"],
	["Tecno Spark 10 KI5q (Helio G37)", "PowerVR Rogue GE8320", 8, 4, Vector2i(720, 1612), "low"],
	["Tecno Spark 20 KJ5 (Helio G85)", "Mali-G52 MC2", 8, 4, Vector2i(720, 1612), "low"],
	["Tecno Pop 7 BF6 (SC9863A)", "PowerVR Rogue GE8322", 8, 2, Vector2i(720, 1612), "low"],
	["Infinix Hot 10 X682B (Helio G70)", "Mali-G52 MC2", 8, 4, Vector2i(720, 1640), "low"],
	["Infinix Hot 12 X6817 (Helio G85; exp.)", "Mali-G52 MC2", 8, 4, Vector2i(720, 1612), "low"],
	["Infinix Hot 30 X6831 (Helio G88)", "Mali-G52 MC2", 8, 8, Vector2i(1080, 2460), "low"],
	["Infinix Hot 40i X6528B (Unisoc T606)", "Mali-G57", 8, 4, Vector2i(720, 1612), "low"],
	["Infinix Smart 7 X6515 (Helio A22, 4 cores)", "PowerVR Rogue GE8300", 4, 3, Vector2i(720, 1612), "low"],
	["Infinix Smart 8 X6525 (Unisoc T606)", "Mali-G57", 8, 3, Vector2i(720, 1612), "low"],
	["vivo Y03 V2333 (Helio G85)", "Mali-G52 MC2", 8, 4, Vector2i(720, 1612), "low"],
	["vivo Y17s V2310 (Helio G85)", "Mali-G52 MC2", 8, 4, Vector2i(720, 1612), "low"],
	["Oppo A17k CPH2471 (Helio G35)", "PowerVR Rogue GE8320", 8, 3, Vector2i(720, 1612), "low"],
	["Symphony Z70 (Unisoc T606; exp.)", "Mali-G57", 8, 4, Vector2i(720, 1600), "low"],
	["Walton NEXG N6 (Unisoc T606; exp.)", "Mali-G57", 8, 8, Vector2i(720, 1600), "low"],
	["Old phone (Snapdragon 425)", "Adreno (TM) 308", 4, 2, Vector2i(720, 1280), "low"],
	["Galaxy J7-era phone (Exynos 7870)", "Mali-T830", 8, 2, Vector2i(720, 1280), "low"],
	# --- medium: Mali-G57 MC2, Mali-G68, Adreno 619 / 618, Mali-G76 MC4 ---
	["Samsung Galaxy A14 5G SM-A146B (Exynos 1330)", "Mali-G68", 8, 4, Vector2i(1080, 2408), "medium"],
	["Samsung Galaxy A14 5G SM-A146P (Dimensity 700)", "Mali-G57 MC2", 8, 4, Vector2i(1080, 2408), "medium"],
	["Samsung Galaxy M14 5G SM-M146B (Exynos 1330)", "Mali-G68", 8, 4, Vector2i(1080, 2408), "medium"],
	["Samsung Galaxy A15 SM-A155F (Helio G99)", "Mali-G57 MC2", 8, 4, Vector2i(1080, 2340), "medium"],
	["Samsung Galaxy A15 5G SM-A156B (Dimensity 6100+)", "Mali-G57 MC2", 8, 6, Vector2i(1080, 2340), "medium"],
	["Samsung Galaxy A16 4G SM-A165F (Helio G99)", "Mali-G57 MC2", 8, 4, Vector2i(1080, 2340), "medium"],
	["Samsung Galaxy A16 5G SM-A166P (Dimensity 6300)", "Mali-G57 MC2", 8, 4, Vector2i(1080, 2340), "medium"],
	["Samsung Galaxy A16 5G SM-A166U (Exynos 1330)", "Mali-G68", 8, 4, Vector2i(1080, 2340), "medium"],
	["Samsung Galaxy A25 SM-A256E (Exynos 1280)", "Mali-G68", 8, 6, Vector2i(1080, 2340), "medium"],
	["Samsung Galaxy A35 SM-A356B (Exynos 1380)", "Mali-G68", 8, 6, Vector2i(1080, 2340), "medium"],
	["Samsung Galaxy A34 (Dimensity 1080)", "Mali-G68 MC4", 8, 6, Vector2i(1080, 2340), "medium"],
	["Samsung Galaxy A52 (Snapdragon 720G)", "Adreno (TM) 618", 8, 4, Vector2i(1080, 2400), "medium"],
	["Xiaomi Redmi Note 12 5G (Snapdragon 4 Gen 1)", "Adreno (TM) 619", 8, 4, Vector2i(1080, 2400), "medium"],
	["Xiaomi Redmi Note 13 Pro 4G (Helio G99 Ultra)", "Mali-G57 MC2", 8, 8, Vector2i(1080, 2400), "medium"],
	["Xiaomi Redmi 13C 5G (Dimensity 6100+, 720p)", "Mali-G57 MC2", 8, 4, Vector2i(720, 1600), "medium"],
	["Xiaomi Redmi Note 10S (Helio G95)", "Mali-G76 MC4", 8, 6, Vector2i(1080, 2400), "medium"],
	["moto g54 (Dimensity 7020)", "PowerVR B-Series BXM-8-256", 8, 4, Vector2i(1080, 2400), "medium"],
	["Dimensity 7300 phone", "Mali-G615 MC2", 8, 8, Vector2i(1080, 2400), "medium"],
	["A strong GPU on a 4 GB phone", "Adreno (TM) 642L", 8, 4, Vector2i(1080, 2400), "medium"],
	["An Xclipse 920 with only 4 GB of RAM (RAM decides)", "ANGLE (Samsung Xclipse 920) on Vulkan 1.1.179", 8, 4, Vector2i(1080, 2340), "medium"],
	# --- high: flagships and upper mid ---
	["Samsung Galaxy A55 SM-A556B (Exynos 1480)", "ANGLE ((Samsung Xclipse 530) on Vulkan 1.3.279)", 8, 8, Vector2i(1080, 2340), "high"],
	["Samsung Galaxy S22 SM-S901B (Exynos 2200)", "ANGLE (Samsung Xclipse 920) on Vulkan 1.1.179", 8, 8, Vector2i(1080, 2340), "high"],
	["Samsung Galaxy S22 SM-S901U (Snapdragon 8 Gen 1)", "Adreno (TM) 730", 8, 8, Vector2i(1080, 2340), "high"],
	["Samsung Galaxy S23 SM-S911B (Snapdragon 8 Gen 2)", "Adreno (TM) 740", 8, 8, Vector2i(1080, 2340), "high"],
	["Samsung Galaxy S24 SM-S921B (Exynos 2400, 10 cores)", "ANGLE (Samsung Xclipse 940) on Vulkan 1.3.231", 10, 8, Vector2i(1080, 2340), "high"],
	["Samsung Galaxy S24 SM-S921U (Snapdragon 8 Gen 3)", "Adreno (TM) 750", 8, 8, Vector2i(1080, 2340), "high"],
	["Samsung Galaxy S24 FE (Android 17 ANGLE)", "ANGLE (Samsung Electronics Co. Ltd., Vulkan 1.3.304 (Samsung Xclipse 940 (0x02600200)), Samsung Proprietary driver-25.3.3)", 10, 8, Vector2i(1080, 2340), "high"],
	["Poco X6 Pro 2311DRK48G (Dimensity 8300 Ultra)", "Mali-G615 MC6", 8, 8, Vector2i(1220, 2712), "high"],
	["Google Pixel 6a (Tensor)", "Mali-G78", 8, 6, Vector2i(1080, 2400), "high"],
	["Google Pixel 7a (Tensor G2; exp.)", "Mali-G710", 8, 8, Vector2i(1080, 2400), "high"],
	["Google Pixel 8a (ANGLE)", "ANGLE (ARM, Vulkan 1.4.343 (Mali-G715 (0x...)), Mali-G715)", 9, 8, Vector2i(1080, 2400), "high"],
	["Snapdragon 778G phone (Galaxy A73)", "Adreno (TM) 642L", 8, 6, Vector2i(1080, 2400), "high"],
	["Snapdragon 7 Gen 1 / 7s Gen 2 phone", "Adreno (TM) 710", 8, 8, Vector2i(1080, 2400), "high"],
]


func run() -> void:
	var keep_tier: String = Quality._tier
	var keep_save: Node = Quality.save_node
	_phones()
	_gpus()
	_rules()
	_settings()
	_overlay()
	Quality.save_node = keep_save
	Quality._tier = keep_tier

static func phone(p: Array) -> Dictionary:
	return {gpu = p[1], vendor = "", cores = p[2], ram_gb = GB[p[3]], screen = p[4], mobile = true}

func _phones() -> void:
	var wrong := {}
	var tally := {low = 0, medium = 0, high = 0}
	for p: Array in PHONES:
		var r := Quality.classify(phone(p))
		tally[r.tier] += 1
		if r.tier != p[5]:
			wrong[p[0]] = "%s (want %s; %s)" % [r.tier, p[5], r.why]
	check("every phone in the table gets its tier", wrong.is_empty(), wrong)
	check("the table covers all three tiers", tally.low >= 40 and tally.medium >= 15 and tally.high >= 10, tally)
	var r := Quality.classify(phone(PHONES[0]))
	check("classify keeps the facts and gives the reason", r.has_all(["gpu", "ram_gb", "cores", "gpu_class", "ram_class", "tier", "why"]) and r.why != "", r)

func _gpus() -> void:
	var gpus := {
		# PowerVR: Rogue GE83xx / G6xxx low, GM9446 / BXM mid, DXT high
		"PowerVR Rogue GE8320": "low", "PowerVR Rogue GE8322": "low", "PowerVR Rogue GE8300": "low", "PowerVR Rogue GE8100": "low",
		"PowerVR Rogue G6200": "low", "PowerVR Rogue GM9446": "medium", "PowerVR B-Series BXM-8-256": "medium",
		"PowerVR D-Series DXT-48-1536": "high",
		# Adreno: 3xx-510 low, 512-540 mid, 610 low, 612-629 mid, 630-699 high, 70x mid, 710+ high
		"Adreno (TM) 306": "low", "Adreno (TM) 405": "low", "Adreno (TM) 505": "low", "Adreno (TM) 506": "low",
		"Adreno (TM) 508": "low", "Adreno (TM) 512": "medium", "Adreno (TM) 540": "medium", "Adreno (TM) 610": "low",
		"Adreno (TM) 612": "medium", "Adreno (TM) 613": "medium", "Adreno (TM) 618": "medium", "Adreno (TM) 619": "medium",
		"Adreno (TM) 620": "medium", "Adreno (TM) 630": "high", "Adreno (TM) 642L": "high", "Adreno (TM) 650": "high", "Adreno (TM) 702": "medium",
		"Adreno (TM) 710": "high", "Adreno (TM) 730": "high", "Adreno (TM) 830": "high",
		# Mali
		"Mali-400 MP": "low", "Mali-T830": "low", "Mali-G31 MP2": "low", "Mali-G51": "low", "Mali-G52": "low",
		"Mali-G52 MC2": "low", "Mali-G57": "low", "Mali-G57 MC1": "low", "Mali-G57 MC2": "medium", "Mali-G57 MC3": "medium",
		"Mali-G68": "medium", "Mali-G68 MP2": "medium", "Mali-G68 MC4": "medium", "Mali-G72": "low", "Mali-G72 MP3": "low",
		"Mali-G72 MP12": "medium", "Mali-G71 MP2": "low", "Mali-G76": "medium",
		"Mali-G76 MC4": "medium", "Mali-G76 MP12": "high", "Mali-G77 MC9": "high", "Mali-G78 MP14": "high",
		"Mali-G310": "low", "Mali-G510": "medium", "Mali-G610 MC6": "high", "Mali-G615 MC2": "medium",
		"Mali-G615 MC6": "high", "Mali-G710 MP7": "high", "Immortalis-G715": "high", "Immortalis-G925": "high",
		# others
		"Samsung Xclipse 920": "high", "ANGLE (Samsung Xclipse 920) on Vulkan 1.1.179": "high", "Apple M3 Pro": "high",
		"ANGLE (ARM, Vulkan 1.3.278 (Mali-G52 MC2 (0x74021000)), Mali-G52 MC2-49.1.0)": "low", "llvmpipe (LLVM 15.0.7, 256 bits)": "low",
		"Some Unknown GPU": "",
	}
	var wrong := {}
	for g: String in gpus:
		if Quality.gpu_class(g) != gpus[g]:
			wrong[g] = Quality.gpu_class(g)
	check("GPU classes (mobile families, core counts)", wrong.is_empty(), wrong)
	check("core count read from MC / MP", Quality._gpu_cores("mali-g78 mp14") == 14 and Quality._gpu_cores("mali-g57 mc2") == 2 and Quality._gpu_cores("mali-g57") == 0)

func _rules() -> void:
	var base := {gpu = "Adreno (TM) 730", vendor = "Qualcomm", cores = 8, ram_gb = GB[8], screen = Vector2i(1080, 2340), mobile = true}
	var with := func(extra: Dictionary) -> String:
		var d := base.duplicate()
		d.merge(extra, true)
		return str(Quality.classify(d).tier)
	check("flagship: high", with.call({}) == "high")
	check("RAM classes: 2 / 3 GB low, 4 GB medium, 6 GB high",
		with.call({ram_gb = GB[2]}) == "low" and with.call({ram_gb = GB[3]}) == "low" and with.call({ram_gb = GB[4]}) == "medium"
		and with.call({ram_gb = GB[6]}) == "high" and with.call({ram_gb = 5.4}) == "high",
		[with.call({ram_gb = GB[3]}), with.call({ram_gb = GB[4]}), with.call({ram_gb = GB[6]})])
	check("unknown RAM: the GPU decides", with.call({ram_gb = -1.0}) == "high")
	check("4 cores or fewer: low", with.call({cores = 4}) == "low" and with.call({cores = 2}) == "low" and with.call({cores = 6}) == "high")
	check("unknown core count: no limit", with.call({cores = 0}) == "high")
	check("unknown GPU: medium on a 1080p phone, low on a 720p one",
		with.call({gpu = "Vendor X GPU", vendor = ""}) == "medium" and with.call({gpu = "Vendor X GPU", vendor = "", screen = Vector2i(720, 1600)}) == "low")
	var emu := {gpu = "Android Emulator OpenGL ES Translator (Apple M3 Pro)", vendor = "Google (Apple)", mobile = true}
	var e := Quality.classify(emu.merged({cores = 2, ram_gb = 1.9, screen = Vector2i(720, 1600)}))
	check("emulator: the host GPU is ignored (2 cores / 2 GB / 720p: low)", e.tier == "low" and e.emulator and e.gpu_class == "", e)
	check("emulator with phone-like 1080p / 8 cores / 8 GB: medium, never high from the Mac's GPU",
		Quality.classify(emu.merged({cores = 8, ram_gb = 7.4, screen = Vector2i(1080, 2400)})).tier == "medium")
	check("is_emulator", Quality.is_emulator("Android Emulator OpenGL ES Translator (Apple M1)") and not Quality.is_emulator("Mali-G57 MC2"))
	check("desktop: high, medium on an old Intel HD",
		Quality.classify({gpu = "Apple M3 Pro", mobile = false, ram_gb = 18.0, cores = 11}).tier == "high"
		and Quality.classify({gpu = "Intel(R) HD Graphics 4000", mobile = false, ram_gb = 8.0, cores = 4}).tier == "medium")
	var mi := "user://_test_meminfo.txt"
	var f := FileAccess.open(mi, FileAccess.WRITE)
	f.store_string("MemTotal:        2022316 kB\nMemFree:          210160 kB\n")
	f.close()
	check("RAM from /proc/meminfo (Android reports no physical size)", is_equal_approx(Quality.meminfo_total(mi), 2022316.0 * 1024.0) and Quality.meminfo_total("user://_no_such_file") < 0.0, Quality.meminfo_total(mi))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(mi))
	check("detect() gives a known tier and fills info", Quality.TIERS.has(Quality.detect()) and Quality.info.has("why"), Quality.info)
	# command line: debug builds only, both `--quality=x` and a bare `--perf`
	check("arg(): absent options are empty", Quality.arg("no-such-option-zz") == "")
	# launch-only settings: the texture size differs between every two tiers
	var used: bool = Quality._tex_used
	Quality._launch = "medium"
	Quality._tex_used = false
	check("needs_restart: nothing baked with texture_scale(): every tier applies at once", not Quality.needs_restart("low") and not Quality.needs_restart("high"))
	Quality.texture_scale()
	check("needs_restart: textures baked at the launch tier: another tier's size waits for the next launch", Quality.needs_restart("low") and Quality.needs_restart("high") and not Quality.needs_restart("medium"))
	Quality._launch = ""
	Quality._tex_used = used

class FakeSave extends Node:
	var prefs := {}
	var saves := 0
	func save() -> void:
		saves += 1

func _settings() -> void:
	var fake := FakeSave.new()
	fake.prefs = {quality = "auto"}
	Quality.save_node = fake
	check("saved_pref reads the (stand-in) save", Quality.saved_pref() == "auto")
	fake.prefs.quality = "ultra"
	check("an unknown saved tier reads as auto", Quality.saved_pref() == "auto")
	var root := SubViewport.new()
	var dice := SubViewport.new()
	dice.positional_shadow_atlas_size = 0
	root.add_child(dice)
	Quality.force("high")
	Quality.apply(root)
	Quality.set_tier("low")
	check("set_tier saves the pick", fake.prefs.quality == "low" and fake.saves == 1, fake.prefs)
	check("set_tier applies at once (main view: no MSAA, low scale)", Quality.tier() == "low" and root.msaa_3d == Viewport.MSAA_DISABLED and root.scaling_3d_scale <= 0.67 + 0.001, [root.msaa_3d, root.scaling_3d_scale])
	check("set_tier reaches the SubViewports (no MSAA, still no atlas)", dice.msaa_3d == Viewport.MSAA_DISABLED and dice.positional_shadow_atlas_size == 0)
	Quality.set_tier("high")
	check("set_tier(high): MSAA 4x everywhere", root.msaa_3d == Viewport.MSAA_4X and dice.msaa_3d == Viewport.MSAA_4X and is_equal_approx(root.scaling_3d_scale, 1.0))
	Quality.set_tier("auto")
	check("set_tier(auto): saved as auto, the detected tier in use", fake.prefs.quality == "auto" and Quality.tier() == Quality.detected())
	check("apply_subs counts the SubViewports", Quality.apply_subs(root) == 1)
	# the Settings row (reads the stand-in save; a pick goes through set_tier)
	fake.prefs.quality = "medium"
	Quality.force("")
	var sheet := SettingsSheet.new()
	var row := sheet.find_child("Graphics", true, false)
	var seg := sheet.find_child("QualitySeg", true, false) as Container
	check("Settings has a Graphics row", row != null and seg != null)
	if seg:
		var texts: Array = seg.get_children().map(func(b: Button): return b.text)
		check("Graphics: Auto (detected) / Low / Medium / High", texts == ["Auto (%s)" % Quality.detected().capitalize(), "Low", "Medium", "High"], texts)
		var on: Array = seg.get_children().filter(func(b: Button): return b.button_pressed).map(func(b: Button): return b.get_meta("value"))
		check("Graphics shows the saved pick", on == ["medium"], on)
		Quality._launch = "medium"
		var used: bool = Quality._tex_used
		Quality._tex_used = true
		(seg.get_child(1) as Button).button_pressed = true          # Low
		check("picking Low in Settings saves and applies it", fake.prefs.quality == "low" and Quality.tier() == "low" and root.msaa_3d == Viewport.MSAA_DISABLED, fake.prefs)
		check("...and says the texture part waits for the next launch", sheet._gfx_note.visible and sheet._gfx_note.text.contains("next launch"), sheet._gfx_note.text)
		(seg.get_child(2) as Button).button_pressed = true          # Medium: the launch tier
		check("back to the launch tier: no launch note", not sheet._gfx_note.visible)
		Quality._tex_used = false
		(seg.get_child(3) as Button).button_pressed = true          # High, nothing baked with the tier's size
		check("no launch note while nothing uses the tier's texture size", not sheet._gfx_note.visible and Quality.tier() == "high")
		Quality._launch = ""
		Quality._tex_used = used
	sheet.free()
	root.free()
	fake.free()
	Quality.save_node = null
	Quality._vp = null
	Quality.force("")

func _overlay() -> void:
	check("percentile: p95 of 1..100 is 95", is_equal_approx(PerfOverlay.percentile(range(1, 101), 0.95), 95.0))
	check("percentile: empty is 0", PerfOverlay.percentile([], 0.95) == 0.0)
	var o := PerfOverlay.new()
	check("overlay: a top layer", o.layer >= 100)
	o.free()
