class_name ShaderSeed
extends RefCounted
## First-launch shader work, Compatibility renderer (GLES3). Godot 4.7 compiles a material shader the first time it
## is drawn, and then compiles all four of its modes at once (colour, colour + instancing, depth, depth +
## instancing) with the default specialization, although this game draws only the colour mode and never with that
## specialization: the used one is compiled on top. The café alone has ~10 such shaders, so a first launch compiled
## ~40 GL programs it never draws with (~15 s of the splash on the Android emulator, which can't keep program
## binaries).
## When user://shader_cache already has an entry for a shader (later launches), the engine loads that instead and
## only compiles what is really drawn. plant() writes such an entry, empty, for every shader the game is known to
## use (SEEDS) before anything is drawn: the first launch then compiles only the programs it draws, and the engine
## fills each entry with them (later launches load their binaries, as before). An entry that already exists is
## never touched. Unknown shaders (new materials) simply take the engine's usual path.
## Format (drivers/gles3/shader_gles3.cpp, cache_file_version 3): "GLSC", u32 3, u32 variant count, then per variant
## a u32 specialization count (0 here). The engine checks all three and ignores the file otherwise.
##
##   main.gd _ready, before the first frame: ShaderSeed.plant()
## Regenerate SEEDS after material changes with ShaderCensus (scripts/debug/shader_census.gd).

const ROOT := "user://shader_cache"
const CACHE_VERSION := 3

## Shader name -> [[version sha1, variant count], ...] (ShaderCensus on the Android emulator, Godot 4.7.2: every café room
## and S&L scene, a Ludo and an S&L match; the engine's own shaders are made before any script runs, so not here).
const SEEDS := {
	"CanvasShaderGLES3": [["4e52419ac64cfab6fb8a93496f99b707c4e7a9d1", 1], ["941fa93ce85cbf9149e0902465667612668ff612", 1]],
	"SceneShaderGLES3": [["032a2913f24954b7226a1db8f63cc31ef66ef7a0", 4], ["0a7539ae03a7603cf66fbe72c734ffc4fd87c797", 4],
		["13d9349a4d48c4e617a7e4e782bf1472015793c9", 4], ["2bf592f719820947d8d2c6ad6132f7c735cbd397", 4],
		["2e43eabb6b25f2e8bb7b7059b096ec53afe0ea5b", 4], ["316c9ede7a8ea270932a1f1d2d407f8855f5033e", 4],
		["4c33483731a51d8bbd8a8b4a79743459a37d5e94", 4], ["8dd6008c9b96dfab8d780bdc4e20d7690d3cda08", 4],
		["92720c0921e552f6b89567db0eb73a9549803c8e", 4], ["a39b923a4ac780e41ae81b96b40f69354e9e1084", 4],
		["b0e6260bfd1f33e8793aad75accac92638c59fd7", 4], ["bc445bfff3aef9afa5e05a5195c538f76af86371", 4],
		["bf00f890850cd021ebd2ee911bb437e96bd3107b", 4], ["c1a2c9d4f5b3734afe206ca46309f1398e9bb6a9", 4],
		["c9896bece58ff5f6a12e9882a6068abe0aae4636", 4], ["dd8a1afab7c77f8e5c78847a28220c2281348a30", 4],
		["e0271112562d2565464ff5c36c10f325d837cbe1", 4], ["e56884ad9ce971ce21bc414a22aebee31a91ac20", 4],
		["fa7b62523470356194bdf709eb2639ab149a07cc", 4]],
}

## Writes the missing entries into every cache folder of each known shader (the engine made the current one at start).
## Returns how many were written.
static func plant() -> int:
	if RenderingServer.get_current_rendering_method() != "gl_compatibility" or not DirAccess.dir_exists_absolute(ROOT):
		return 0
	var n := 0
	for shader: String in SEEDS:
		var dir := ROOT.path_join(shader)
		if not DirAccess.dir_exists_absolute(dir):
			continue
		for base in DirAccess.get_directories_at(dir):
			for e: Array in SEEDS[shader]:
				var path := dir.path_join(base).path_join(str(e[0]) + ".cache")
				if FileAccess.file_exists(path):
					continue
				var f := FileAccess.open(path, FileAccess.WRITE)
				if f == null:
					return n
				f.store_buffer("GLSC".to_ascii_buffer())
				f.store_32(CACHE_VERSION)
				f.store_32(int(e[1]))
				for v in int(e[1]):
					f.store_32(0)
				f.close()
				n += 1
	return n
