#!/bin/sh
# Makes the native debug symbols zip for Play Console (Crashes & ANRs symbolication of native crashes) for the
# "Android Release" export: build/android/native-debug-symbols-<version code>.zip.
#
# The game runs on the official Godot export template, whose libgodot_android.so ships stripped, so Gradle's
# ndk.debugSymbolLevel cannot produce useful symbols. Godot publishes the matching symbols with each release
# (Godot_native_debug_symbols.<version>.template_release.android.zip, ~780 MB, every ABI). This script downloads it
# once into a cache outside the repo, checks the arm64 library's BuildId against the template the export uses
# (godot/android/build/libs/release/godot-lib.template_release.aar), and packs only the ABIs the preset exports,
# with the ABI folders at the zip root as Play expects.
#
# Usage: tools/android-symbols.sh [--symtab] [--abi <abi>]
#   --symtab     strip DWARF, keep the symbol table: function names but no file / line numbers (54 MB for both ABIs
#                instead of 367 MB; Play reportedly refuses symbol files over 300 MB).
#   --abi <abi>  only this ABI (e.g. arm64-v8a: full symbols ~195 MB), default: every ABI the preset exports.
# Upload: Play Console > Test and release > App bundle explorer (or Latest releases and bundles) > the bundle with
# this version code > Downloads > Assets > Native debug symbols > upload. Once per uploaded AAB (every version code).
# Env: GODOT (default godot), LZ_CACHE (default ~/.cache/ludo-zing), ANDROID_HOME (for llvm-objcopy with --symtab).
set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="${LZ_CACHE:-$HOME/.cache/ludo-zing}"
SYMTAB=0
ONLY=""
while [ $# -gt 0 ]; do
	case "$1" in
		--symtab) SYMTAB=1 ;;
		--abi) shift; ONLY="${1:-}" ;;
		-h|--help) sed -n '2,20p' "$0"; exit 0 ;;
		*) echo "android-symbols: unknown option $1" >&2; exit 2 ;;
	esac
	shift
done

VER="$("${GODOT:-godot}" --version | cut -d. -f1-4)"          # e.g. 4.7.2.stable
case "$VER" in *.*.*.*) ;; *) VER="$("${GODOT:-godot}" --version | cut -d. -f1-3)" ;; esac
TAG="$(echo "$VER" | sed 's/\.\([a-z][a-z0-9]*\)$/-\1/')"      # 4.7.2-stable
NAME="Godot_native_debug_symbols.$VER.template_release.android.zip"
URL="https://github.com/godotengine/godot/releases/download/$TAG/$NAME"
mkdir -p "$CACHE"
if [ ! -s "$CACHE/$NAME" ] || ! unzip -tq "$CACHE/$NAME" >/dev/null 2>&1; then
	echo "== downloading $URL (~780 MB, once)"
	curl -fL --retry 3 -C - -o "$CACHE/$NAME.part" "$URL"
	mv "$CACHE/$NAME.part" "$CACHE/$NAME"
fi

# the Android Release preset: its version code and exported ABIs
PRESET="$REPO/godot/export_presets.cfg"
OPTS="$(awk '/^name="Android Release"$/{p=1} p&&/^\[preset\.[0-9]+\.options\]$/{o=1;next} o&&/^\[preset/{exit} o{print}' "$PRESET")"
CODE="$(echo "$OPTS" | sed -n 's/^version\/code=//p')"
ABIS="$(echo "$OPTS" | sed -n 's/^architectures\/\(.*\)=true$/\1/p')"
[ -n "$CODE" ] && [ -n "$ABIS" ] || { echo "android-symbols: could not read the Android Release preset" >&2; exit 1; }
if [ -n "$ONLY" ]; then
	echo "$ABIS" | grep -qx "$ONLY" || { echo "android-symbols: $ONLY is not exported (preset: $(echo $ABIS))" >&2; exit 2; }
	ABIS="$ONLY"
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
for abi in $ABIS; do
	unzip -q "$CACHE/$NAME" "$abi/*" -d "$TMP/syms"
done

# the BuildId of the symbols must be the template's (else Play cannot match them to the crashes)
buildid() { file -b "$1" | sed -n 's/.*BuildID\[[a-z0-9]*\]=\([0-9a-f]*\).*/\1/p'; }
AAR="$REPO/godot/android/build/libs/release/godot-lib.template_release.aar"
if [ -f "$AAR" ]; then
	for abi in $ABIS; do
		unzip -q -o "$AAR" "jni/$abi/libgodot_android.so" -d "$TMP/aar" 2>/dev/null || continue
		want="$(buildid "$TMP/aar/jni/$abi/libgodot_android.so")"
		got="$(buildid "$TMP/syms/$abi/libgodot_android.so")"
		if [ "$want" != "$got" ]; then
			echo "android-symbols: $abi BuildId mismatch (template $want, symbols $got): wrong Godot version?" >&2
			exit 1
		fi
		echo "== $abi BuildId $got matches the export template"
	done
else
	echo "== (no installed Android build template at godot/android/build: BuildId not checked)"
fi

if [ "$SYMTAB" -eq 1 ]; then
	ANDROID_HOME="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
	OBJCOPY="$(ls "$ANDROID_HOME"/ndk/*/toolchains/llvm/prebuilt/*/bin/llvm-objcopy 2>/dev/null | tail -1)"
	[ -x "$OBJCOPY" ] || { echo "android-symbols: llvm-objcopy not found under $ANDROID_HOME/ndk" >&2; exit 1; }
	for so in "$TMP"/syms/*/*.so; do "$OBJCOPY" --strip-debug "$so"; done
fi

OUT="$REPO/build/android/native-debug-symbols-$CODE.zip"
mkdir -p "$REPO/build/android"
rm -f "$OUT"
(cd "$TMP/syms" && zip -q -r -9 "$OUT" .)
ls -l "$OUT" | awk '{print "== " $NF " (" int($5 / 1048576) " MB) for version code '"$CODE"'"}'
if [ "$(wc -c < "$OUT")" -gt 314572800 ]; then
	echo "== over 300 MB: Play may refuse it; use --symtab, or --abi arm64-v8a for full symbols of 64-bit phones only"
fi
echo "== upload it to the bundle with version code $CODE: Play Console > App bundle explorer > Downloads > Native debug symbols"
