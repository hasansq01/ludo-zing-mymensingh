#!/bin/sh
# Builds Ludo Zing's own Godot Android export template: the same Godot release as the editor (same commit, same
# compiler settings as the official template: production=yes), minus engine features the game never uses. The
# official arm64 libgodot_android.so is 71 MB installed / 24 MB downloaded; this one is ~49 MB / ~17 MB.
#
# Left out (nothing in scripts/, scenes, resources or addons/ uses them; checked by `test` below):
#   vulkan=no          the Vulkan renderer: the game runs only the Compatibility renderer (OpenGL ES 3,
#                      project.godot rendering_method[.mobile]="gl_compatibility"); swappy=no goes with it (Swappy
#                      frame pacing is only used by the Vulkan driver)
#   disable_xr         OpenXR / mobile VR / WebXR
#   disable_navigation_2d/3d, disable_physics_2d, module_jolt_physics (3D physics stays: GodotPhysics3D, as CSG's
#                      collision code needs it to link in 4.7.2)
#   modules: text_server_fb (the game uses text_server_adv, needed for Bangla), gltf, fbx, theora, enet,
#            multiplayer, webrtc, upnp, jsonrpc, mp3, gridmap, interactive_music, camera, vhacd, xatlas_unwrap,
#            raycast (occlusion culling), visual_shader, objectdb_profiler
# Kept on purpose: 3D, CSG (rooms.gd), noise (pawn_skins.gd), regex, svg, webp, ogg/vorbis, websocket + mbedtls,
# brotli (WOFF2 fonts), freetype, msdfgen, every image codec (etcpak/astcenc/bcdec/basis: VRAM textures).
#
# Usage: tools/android-engine.sh <command>
#   build      fetch the source (cache), build arm64 + arm32 (~5 min each), make the AAR and the symbols
#   install    put this engine into godot/android/build (the official AAR is kept in the cache)
#   official   put the official engine back (rollback)
#   status     which engine godot/android/build has (exit 0: this one)
#   mac        build a macOS debug template with the same switches (for `test`)
#   test       run the test suite and the class check on that macOS template
# Then tools/android-release.sh as usual (it says which engine the AAB got), and tools/android-symbols.sh packs this
# engine's symbols (it checks the BuildIds). Godot upgrade: change TAG and COMMIT, build, mac, test.
# Env: LZ_CACHE (default ~/.cache/ludo-zing), ANDROID_HOME, GODOT (default godot), JOBS.
set -eu

TAG="4.7.2-stable"
COMMIT="ed1daf0bf001b61586d9930840f2f1394092c079"
NDK_VERSION="29.0.14206865"
FLAGS="production=yes swappy=no vulkan=no disable_xr=yes disable_navigation_2d=yes disable_navigation_3d=yes
disable_physics_2d=yes module_jolt_physics_enabled=no module_text_server_fb_enabled=no module_gltf_enabled=no
module_fbx_enabled=no module_theora_enabled=no module_enet_enabled=no module_multiplayer_enabled=no
module_webrtc_enabled=no module_upnp_enabled=no module_jsonrpc_enabled=no module_mp3_enabled=no
module_gridmap_enabled=no module_interactive_music_enabled=no module_camera_enabled=no module_vhacd_enabled=no
module_xatlas_unwrap_enabled=no module_raycast_enabled=no module_visual_shader_enabled=no
module_objectdb_profiler_enabled=no"
ABIS="arm64-v8a armeabi-v7a"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="${LZ_CACHE:-$HOME/.cache/ludo-zing}"
SRC="$CACHE/godot-src"
OUT="$CACHE/engine/$TAG"
ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export ANDROID_HOME
BIN="$(ls -d "$ANDROID_HOME/ndk/$NDK_VERSION"/toolchains/llvm/prebuilt/*/bin 2>/dev/null | head -1)"
JOBS="${JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || nproc)}"
VER="$(echo "$TAG" | tr - .)"                                     # 4.7.2.stable
TEMPLATES="$HOME/Library/Application Support/Godot/export_templates/$VER"
INSTALLED="$REPO/godot/android/build/libs/release/godot-lib.template_release.aar"
IDS="$REPO/tools/engine-buildids.txt"

buildid() { "$BIN/llvm-readelf" -n "$1" | sed -n 's/.*Build ID: *\([0-9a-f]*\).*/\1/p'; }
aar_ids() {   # "abi buildid" lines of an AAR's libgodot_android.so
	t="$(mktemp -d)"
	for abi in $ABIS; do
		if unzip -q -o "$1" "jni/$abi/libgodot_android.so" -d "$t" 2>/dev/null; then
			echo "$abi $(buildid "$t/jni/$abi/libgodot_android.so")"
		fi
	done
	rm -rf "$t"
}

source_ready() {
	if [ ! -d "$SRC/.git" ]; then
		git clone --depth 1 --branch "$TAG" https://github.com/godotengine/godot.git "$SRC"
	fi
	[ "$(git -C "$SRC" rev-parse HEAD)" = "$COMMIT" ] || { echo "android-engine: $SRC is not $TAG ($COMMIT)" >&2; exit 1; }
	git -C "$SRC" diff --quiet || { echo "android-engine: $SRC has local changes" >&2; exit 1; }
	editor="$("${GODOT:-godot}" --version)"
	case "$editor" in *"$(echo "$COMMIT" | cut -c1-9)"*) ;;
		*) echo "android-engine: the editor ($editor) is not $TAG ($COMMIT)" >&2; exit 1 ;; esac
	[ -x "$CACHE/venv/bin/scons" ] || { python3 -m venv "$CACHE/venv" && "$CACHE/venv/bin/pip" install -q scons; }
}

cmd_build() {
	[ -n "$BIN" ] || { echo "android-engine: NDK $NDK_VERSION not found (sdkmanager --install \"ndk;$NDK_VERSION\")" >&2; exit 1; }
	source_ready
	for arch in arm64 arm32; do
		echo "== building $arch (log: $CACHE/engine-$arch.log)"
		(cd "$SRC" && "$CACHE/venv/bin/scons" platform=android target=template_release arch=$arch \
			debug_symbols=yes separate_debug_symbols=yes $FLAGS -j"$JOBS") > "$CACHE/engine-$arch.log" 2>&1 \
			|| { tail -20 "$CACHE/engine-$arch.log" >&2; exit 1; }
	done
	rm -rf "$OUT" && mkdir -p "$OUT/symbols" "$OUT/aar"
	unzip -q -o "$TEMPLATES/android_source.zip" libs/release/godot-lib.template_release.aar -d "$OUT/official"
	cp "$OUT/official/libs/release/godot-lib.template_release.aar" "$OUT/godot-lib.template_release.aar"
	libs="$SRC/platform/android/java/lib/libs/release"
	for abi in $ABIS; do
		mkdir -p "$OUT/symbols/$abi" "$OUT/aar/jni/$abi"
		cp "$libs/$abi/libgodot_android.so" "$OUT/symbols/$abi/"                 # full debug info (Play symbols)
		"$BIN/llvm-strip" --strip-unneeded "$libs/$abi/libgodot_android.so" -o "$OUT/aar/jni/$abi/libgodot_android.so"
		"$BIN/llvm-strip" --strip-unneeded "$libs/$abi/libc++_shared.so" -o "$OUT/aar/jni/$abi/libc++_shared.so"
	done
	# the official Java side, this engine's native libraries; no x86 / x86_64 (the release preset exports ARM only)
	zip -q -d "$OUT/godot-lib.template_release.aar" 'jni/*'
	(cd "$OUT/aar" && zip -q -r "$OUT/godot-lib.template_release.aar" jni)
	aar_ids "$OUT/godot-lib.template_release.aar" > "$IDS"
	echo "== $OUT/godot-lib.template_release.aar"
	sed 's/^/   /' "$IDS"
	echo "== tools/engine-buildids.txt updated: commit it with the release that ships this engine"
}

cmd_install() {
	[ -f "$OUT/godot-lib.template_release.aar" ] || { echo "android-engine: not built yet (tools/android-engine.sh build)" >&2; exit 1; }
	[ -f "$INSTALLED" ] || { echo "android-engine: no Android build template at godot/android/build (install it from the editor)" >&2; exit 1; }
	[ "$(aar_ids "$OUT/godot-lib.template_release.aar")" = "$(cat "$IDS")" ] \
		|| { echo "android-engine: the built AAR is not the engine in tools/engine-buildids.txt" >&2; exit 1; }
	cp "$OUT/godot-lib.template_release.aar" "$INSTALLED"
	cmd_status
}

cmd_official() {
	unzip -q -o "$TEMPLATES/android_source.zip" libs/release/godot-lib.template_release.aar -d "$OUT/official"
	cp "$OUT/official/libs/release/godot-lib.template_release.aar" "$INSTALLED"
	cmd_status || true
}

# exit status 0: Ludo Zing's engine is installed, 1: another one (the official template, or an older build)
cmd_status() {
	if [ "$(aar_ids "$INSTALLED")" = "$(cat "$IDS")" ]; then
		echo "== godot/android/build: Ludo Zing's engine ($TAG, tools/engine-buildids.txt)"
	else
		echo "== godot/android/build: the official engine or another build (not tools/engine-buildids.txt):"
		aar_ids "$INSTALLED" | sed 's/^/   /'
		return 1
	fi
}

cmd_mac() {   # (disable_path_overrides=no: production builds refuse --path, which `test` needs)
	source_ready
	(cd "$SRC" && "$CACHE/venv/bin/scons" platform=macos target=template_debug arch=arm64 metal=no \
		$(echo $FLAGS | sed 's/swappy=no//') disable_path_overrides=no -j"$JOBS") > "$CACHE/engine-macos.log" 2>&1 \
		|| { tail -20 "$CACHE/engine-macos.log" >&2; exit 1; }
	ls -l "$SRC/bin/godot.macos.template_debug.arm64"
}

cmd_test() {
	T="$SRC/bin/godot.macos.template_debug.arm64"
	[ -x "$T" ] || { echo "android-engine: run tools/android-engine.sh mac first" >&2; exit 1; }
	# a copy under another name: its own user:// (a test run that stops halfway can't touch the real save), without
	# the suites of the editor export plugins (EditorExportPlugin is editor-only: no template has it)
	COPY="$CACHE/engine-test-project"
	rsync -a --delete --exclude 'android/build' --exclude 'android/plugins/*/build' "$REPO/godot/" "$COPY/"
	sed -i.bak 's/^config\/name=.*/config\/name="LZ Engine Test"/' "$COPY/project.godot" && rm -f "$COPY/project.godot.bak"
	only="$(grep -oE '"res://tests/test_[a-z0-9_]+\.gd"' "$COPY/tests/run_tests.gd" | sort -u | tr -d '"' \
		| sed 's|res://tests/||; s|\.gd$||' | grep -vE '^test_(ads|billing|notifier|play_games)$' | paste -sd, -)"
	"$T" --headless --path "$COPY" -s tests/run_tests.gd -- --only="$only"
}

case "${1:-}" in
	build) cmd_build ;;
	install) cmd_install ;;
	official) cmd_official ;;
	status) cmd_status ;;
	mac) cmd_mac ;;
	test) cmd_test ;;
	*) sed -n '2,30p' "$0"; exit 2 ;;
esac
