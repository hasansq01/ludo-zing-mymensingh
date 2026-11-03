#!/bin/sh
# Builds the Android debug APK from the Godot project (prebuilt export templates, no Gradle).
#
# Usage: tools/android-build.sh [--emulator] [--install] [--run] [--device SERIAL] [--project DIR] [--out APK]
#   --emulator      use the "Android Emulator" preset: same app, but launched with
#                   --rendering-method gl_compatibility (the macOS Android emulator's Vulkan
#                   path presents a black screen with the Mobile renderer). Real phones: omit.
#   --install       adb install -r the APK on the connected emulator/device
#   --run           launch the app after installing (implies --install)
#   --device SERIAL target a specific adb device (default: $ANDROID_SERIAL or the only device)
#   --project DIR   Godot project directory (default: <repo>/godot)
#   --out APK       output path (default: <repo>/build/android/ludo-zing-debug.apk,
#                   or ludo-zing-emulator-debug.apk with --emulator)
#
# Env: GODOT (default: godot), ANDROID_HOME / ANDROID_SDK_ROOT (default: ~/Library/Android/sdk).
# Needs: Godot 4.7.2 Android export templates in
#   ~/Library/Application Support/Godot/export_templates/4.7.2.stable/
# and the SDK / JDK / debug keystore paths set in the Godot editor settings
# (export/android/android_sdk_path, java_sdk_path, debug_keystore[_user|_pass]).
set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-godot}"
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
ADB="$SDK/platform-tools/adb"
PACKAGE="com.flipfold.ludozing"
ACTIVITY="com.godot.game.GodotAppLauncher"   # launcher alias in the Godot 4.7 template manifest
PROJECT="$REPO/godot"
OUT=""
PRESET="Android"
INSTALL=0
RUN=0
DEVICE="${ANDROID_SERIAL:-}"

while [ $# -gt 0 ]; do
	case "$1" in
		--emulator) PRESET="Android Emulator" ;;
		--install) INSTALL=1 ;;
		--run) INSTALL=1; RUN=1 ;;
		--device) DEVICE="$2"; shift ;;
		--project) PROJECT="$(cd "$2" && pwd)"; shift ;;
		--out) OUT="$2"; shift ;;
		-h|--help) sed -n '2,21p' "$0"; exit 0 ;;
		*) echo "android-build: unknown option $1" >&2; exit 2 ;;
	esac
	shift
done

if [ -z "$OUT" ]; then
	if [ "$PRESET" = "Android" ]; then OUT="$REPO/build/android/ludo-zing-debug.apk"
	else OUT="$REPO/build/android/ludo-zing-emulator-debug.apk"; fi
fi
case "$OUT" in /*) ;; *) OUT="$PWD/$OUT" ;; esac
mkdir -p "$(dirname "$OUT")"

VERSION="$("$GODOT" --version | sed -E 's/^([0-9.]+\.[a-z]+).*/\1/')"
TPL="$HOME/Library/Application Support/Godot/export_templates/$VERSION"
if [ ! -f "$TPL/android_debug.apk" ]; then
	echo "android-build: missing export templates for $VERSION in $TPL" >&2
	exit 1
fi

echo "== import ($PROJECT)"
"$GODOT" --headless --path "$PROJECT" --import >/dev/null 2>&1 || true

# refuse to build when a script doesn't compile: boot the real main scene headless for a few frames
CHECK="$("$GODOT" --headless --path "$PROJECT" --quit-after 120 2>&1 || true)"
if printf '%s\n' "$CHECK" | grep -E "SCRIPT ERROR|Parse Error|Compile Error" >/dev/null; then
  printf '%s\n' "$CHECK" | grep -E -A1 "SCRIPT ERROR|Parse Error|Compile Error" | head -20 >&2
  echo "== script errors: not building" >&2
  exit 1
fi

echo "== export debug ($PRESET) -> $OUT"
rm -f "$OUT"
"$GODOT" --headless --path "$PROJECT" --export-debug "$PRESET" "$OUT"
if [ ! -s "$OUT" ]; then
	echo "android-build: export failed (no APK written)" >&2
	exit 1
fi
ls -lh "$OUT" | awk '{print "== built " $NF " (" $5 ")"}'

[ "$INSTALL" -eq 1 ] || exit 0

# Godot may shut the adb server down when it exits (editor setting
# export/android/shutdown_adb_on_exit); restart it and give devices a moment to reconnect.
"$ADB" start-server >/dev/null 2>&1
i=0
while [ $i -lt 15 ] && ! "$ADB" devices | awk 'NR>1 && $2=="device" {f=1} END {exit !f}'; do
	sleep 1; i=$((i + 1))
done
if [ -z "$DEVICE" ]; then
	DEVICE="$("$ADB" devices | awk 'NR>1 && $2=="device" {print $1; exit}')"
	[ -n "$DEVICE" ] || { echo "android-build: no adb device/emulator connected" >&2; exit 1; }
fi
echo "== install on $DEVICE"
"$ADB" -s "$DEVICE" install -r "$OUT" </dev/null

[ "$RUN" -eq 1 ] || exit 0

echo "== launch $PACKAGE"
"$ADB" -s "$DEVICE" shell am force-stop "$PACKAGE"
if ! "$ADB" -s "$DEVICE" shell am start -W -n "$PACKAGE/$ACTIVITY" | grep -q "Status: ok"; then
	"$ADB" -s "$DEVICE" shell monkey -p "$PACKAGE" -c android.intent.category.LAUNCHER 1 >/dev/null
fi
echo "== logs: $ADB -s $DEVICE logcat -s godot:V GodotApp:V AndroidRuntime:E"
