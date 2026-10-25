#!/bin/sh
# Times the app's startup on an Android device / emulator: the first launch after a fresh install (no shader cache,
# no save: the welcome comes up) and then warm launches (force-stopped, data kept).
#
# Usage: tools/boot-time.sh SERIAL [APK] [--runs N] [--no-install]
#   SERIAL        adb serial (emulator-5554, or a phone's serial from `adb devices`)
#   APK           the APK to time (default: build/android/ludo-zing-debug.apk). It is installed fresh: the app is
#                 uninstalled first, so run 1 is a true first launch (its save is lost: test devices only).
#   --runs N      launches in all (default 3: 1 cold + 2 warm)
#   --no-install  time the app already installed (run 1 is then whatever state it is in)
# The app is force-stopped at the end. Measure one emulator at a time: two running emulators share the host GPU.
#
# Per launch it prints the time from `am start` to the first bright frame (the splash is dark plum; the welcome and
# Home are bright), polled with screencap (~0.2-0.5 s resolution), and the app's own `[boot]` trace from logcat: debug
# builds always print it, release builds when /sdcard/Android/data/<package>/files/boot-trace exists (created here;
# `adb shell rm` it to go quiet again; uninstalling removes it).
#
# Phone (e.g. the Galaxy S22), release build:
#   godot --headless --path godot --export-release "Android" ../build/android/LudoZing-le1.apk   # (signing env vars)
#   tools/boot-time.sh <phone serial> build/android/LudoZing-le1.apk
set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
ADB="$SDK/platform-tools/adb"
[ -x "$ADB" ] || ADB=adb
PACKAGE="com.flipfold.ludozing"
ACTIVITY="com.godot.game.GodotAppLauncher"
SERIAL="${1:-}"
[ -n "$SERIAL" ] || { sed -n '2,20p' "$0"; exit 2; }
shift
APK="$REPO/build/android/ludo-zing-debug.apk"
RUNS=3
INSTALL=1
while [ $# -gt 0 ]; do
	case "$1" in
		--runs) RUNS="$2"; shift ;;
		--no-install) INSTALL=0 ;;
		-h|--help) sed -n '2,20p' "$0"; exit 0 ;;
		*) APK="$1" ;;
	esac
	shift
done
A() { "$ADB" -s "$SERIAL" "$@"; }

if [ "$INSTALL" = 1 ]; then
	[ -f "$APK" ] || { echo "boot-time: no APK at $APK" >&2; exit 1; }
	echo "== fresh install of $APK on $SERIAL"
	A uninstall "$PACKAGE" >/dev/null 2>&1 || true
	A install --user 0 "$APK" >/dev/null
fi
A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
# release builds print the [boot] trace only when this file exists (scripts/core/boot_trace.gd); the app creates
# the directory on its first start, so make sure it is there
A shell "mkdir -p /sdcard/Android/data/$PACKAGE/files && touch /sdcard/Android/data/$PACKAGE/files/boot-trace" >/dev/null 2>&1 || true

# mean brightness (0..255) of the middle of the screen, from a raw screencap on stdin
LUMA='
import sys
d = sys.stdin.buffer.read()
w = int.from_bytes(d[0:4], "little"); h = int.from_bytes(d[4:8], "little")
off = 16 if len(d) >= 16 + w * h * 4 else 12
s = n = 0
for y in range(h // 4, h * 3 // 4, max(1, h // 40)):
    row = off + y * w * 4
    for x in range(w // 8, w * 7 // 8, max(1, w // 30)):
        i = row + x * 4
        s += (d[i] * 3 + d[i + 1] * 6 + d[i + 2]) // 10; n += 1
print(s // max(n, 1))
'
now_ms() { python3 -c 'import time; print(int(time.time() * 1000))'; }
focused() { A shell dumpsys window 2>/dev/null | grep "mCurrentFocus" | grep -q "$PACKAGE"; }

i=1
while [ "$i" -le "$RUNS" ]; do
	A shell am force-stop "$PACKAGE"
	sleep 2
	A logcat -c
	t0="$(now_ms)"
	A shell am start -n "$PACKAGE/$ACTIVITY" >/dev/null
	dark=""
	bright=""
	while :; do
		t="$(now_ms)"
		[ $((t - t0)) -gt 180000 ] && break
		l="$(A exec-out screencap 2>/dev/null | python3 -c "$LUMA" 2>/dev/null || echo 0)"
		l="${l:-0}"
		if [ -z "$dark" ]; then                 # the launcher is bright too: wait for the app's window, then the splash
			if [ "$l" -lt 60 ] && focused; then
				dark=$((t - t0))
			fi
		elif [ "$l" -gt 110 ] && focused; then
			bright=$((t - t0)); break
		fi
	done
	kind="warm"
	[ "$i" = 1 ] && [ "$INSTALL" = 1 ] && kind="cold (first launch)"
	sec() { python3 -c "print('%.1f' % ($1 / 1000))"; }
	if [ -n "$bright" ]; then
		echo "== run $i, $kind: splash up after $(sec "$dark") s, first bright frame after $(sec "$bright") s"
	else
		echo "== run $i, $kind: no bright frame within 180 s (splash seen: ${dark:-no})"
	fi
	sleep 1
	A logcat -d 2>/dev/null | grep -E "\[boot\]|SCRIPT ERROR" | sed 's/^.*\(\[boot\]\)/   \1/' || true
	i=$((i + 1))
done
A shell am force-stop "$PACKAGE"            # leave the device idle (a running app slows other emulators down)
