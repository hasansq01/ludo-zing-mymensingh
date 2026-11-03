#!/bin/sh
# Low-spec capture: runs the installed DEBUG build on an emulator / phone at each quality tier and saves, per tier and
# scene, the perf overlay's numbers ("[perf] ..." log lines), the app's memory (dumpsys meminfo) and two screenshots
# (with the overlay, and clean). Scenes: home, ludo3d, ludotop (an autoplay Ludo match with the 3D / Top camera), sl
# (an autoplay Snakes & Ladders match).
#
# Usage: tools/lowspec-capture.sh [--serial SERIAL] [--out DIR] [--tiers "low medium high"] [--scenes "home ludo3d ..."]
#   --serial  adb device (default: emulator-5556, the low-spec AVD "LowSpec_720p_API35")
#   --out     where to write <tier>_<scene>.png / _clean.png / .log and summary.txt (default: build/lowspec)
#
# It overwrites the app's own save on the DEVICE (files/save.json: welcome and tutorial done, no daily pop-up, the
# camera per scene) and writes files/debug_args.txt (--perf --quality=<tier>) and files/autoplay.txt; it removes the
# last two at the end. Debug builds only (run-as needs a debuggable APK; release builds ignore both files).
# The emulator's GPU is the host Mac's: compare draw calls, memory, CPU-side times and the look, not the fps.
set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
ADB="$SDK/platform-tools/adb"
PKG="com.flipfold.ludozing"
ACT="com.godot.game.GodotAppLauncher"
SERIAL="emulator-5556"
OUT="$REPO/build/lowspec"
TIERS="low medium high"
SCENES="home ludo3d ludotop sl"

while [ $# -gt 0 ]; do
	case "$1" in
		--serial) SERIAL="$2"; shift ;;
		--out) OUT="$2"; shift ;;
		--tiers) TIERS="$2"; shift ;;
		--scenes) SCENES="$2"; shift ;;
		-h|--help) sed -n '2,15p' "$0"; exit 0 ;;
		*) echo "lowspec-capture: unknown option $1" >&2; exit 2 ;;
	esac
	shift
done
mkdir -p "$OUT"
A() { "$ADB" -s "$SERIAL" "$@"; }

# put a local file into the app's files/ (via /data/local/tmp: run-as can read it there)
put() {
	A push "$1" "/data/local/tmp/lz_$2" >/dev/null
	A shell chmod 644 "/data/local/tmp/lz_$2"
	A shell run-as "$PKG" cp "/data/local/tmp/lz_$2" "files/$2"
	A shell rm -f "/data/local/tmp/lz_$2"
}

TMP="$OUT/.tmp"
mkdir -p "$TMP"
TODAY="$(A shell date +%Y-%m-%d | tr -d '\r')"
SUMMARY="$OUT/summary.txt"
: > "$SUMMARY"

for tier in $TIERS; do
	for scene in $SCENES; do
		cam=top; play=""
		case "$scene" in
			ludo3d) cam=3d; play=ludo ;;
			ludotop) play=ludo ;;
			sl) play=sl ;;
		esac
		echo "== $tier / $scene"
		A shell am force-stop "$PKG"
		printf '{"v":1,"profile":{"name":"Tester","daily":{"auto_on":"%s"}},"prefs":{"defaults_v3":true,"welcome_seen":true,"tutorial_done":true,"cam":"%s","sl_cam":"top","quality":"auto"}}' "$TODAY" "$cam" > "$TMP/save.json"
		put "$TMP/save.json" save.json
		printf -- '--perf --quality=%s\n' "$tier" > "$TMP/debug_args.txt"
		put "$TMP/debug_args.txt" debug_args.txt
		if [ -n "$play" ]; then
			printf '%s\n' "$play" > "$TMP/autoplay.txt"
			put "$TMP/autoplay.txt" autoplay.txt
		else
			A shell run-as "$PKG" rm -f files/autoplay.txt
		fi
		A logcat -c
		A shell am start -n "$PKG/$ACT" >/dev/null
		i=0
		until A logcat -d -s godot:I | grep -q "splash gone"; do
			sleep 1; i=$((i + 1))
			[ $i -lt 90 ] || { echo "lowspec-capture: no 'splash gone' after 90 s" >&2; break; }
		done
		# Home: let it settle; a match: autoplay starts it 2 s after Home, then a few turns
		if [ -n "$play" ]; then sleep 16; else sleep 9; fi
		A exec-out screencap -p > "$OUT/${tier}_${scene}.png"
		A logcat -d -s godot:I > "$OUT/${tier}_${scene}.log"
		A shell dumpsys meminfo "$PKG" | grep -E "TOTAL PSS|TOTAL RSS|Graphics:|GL mtrack|EGL mtrack|Native Heap:" >> "$OUT/${tier}_${scene}.log" || true
		A shell input keyevent 133            # F3: hide the overlay for the clean picture
		sleep 1
		A exec-out screencap -p > "$OUT/${tier}_${scene}_clean.png"
		perf="$(grep '\[perf\] fps' "$OUT/${tier}_${scene}.log" | tail -1 | sed 's/.*\[perf\] //')"
		pss="$(grep 'TOTAL PSS' "$OUT/${tier}_${scene}.log" | head -1 | awk '{print $3}')"
		printf '%-7s %-8s pss_kb=%s | %s\n' "$tier" "$scene" "${pss:-?}" "$perf" | tee -a "$SUMMARY"
	done
done
A shell am force-stop "$PKG"
A shell run-as "$PKG" rm -f files/autoplay.txt files/debug_args.txt
rm -f "$TMP/save.json" "$TMP/debug_args.txt" "$TMP/autoplay.txt"
rmdir "$TMP" 2>/dev/null || true
echo "== summary: $SUMMARY"
