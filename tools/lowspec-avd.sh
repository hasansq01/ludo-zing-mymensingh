#!/bin/sh
# Creates (once) and boots the low-spec emulator "LowSpec_720p_API35" on port 5556 (adb serial emulator-5556):
# 2 CPU cores, 2 GB RAM, a 720 x 1600 / 320 dpi screen (a Galaxy A04 / Redmi 12C class phone), 256 MB VM heap,
# host GPU. Reuses the installed android-35 google_apis_playstore arm64 image (no download).
# The emulator's GPU is the Mac's, so only CPU / memory / screen are "low": compare draw calls, memory and the look.
#
# Usage: tools/lowspec-avd.sh [--create-only] [--wipe]
# Then:  tools/android-build.sh --emulator --device emulator-5556 --install
#        tools/lowspec-capture.sh            (perf numbers + screenshots per tier)
set -eu

SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
NAME="LowSpec_720p_API35"
IMAGE="system-images;android-35;google_apis_playstore;arm64-v8a"
PORT=5556
CREATE_ONLY=0
WIPE=""
for a in "$@"; do
	case "$a" in
		--create-only) CREATE_ONLY=1 ;;
		--wipe) WIPE="-wipe-data" ;;
		-h|--help) sed -n '2,9p' "$0"; exit 0 ;;
		*) echo "lowspec-avd: unknown option $a" >&2; exit 2 ;;
	esac
done

CFG="$HOME/.android/avd/$NAME.avd/config.ini"
if [ ! -f "$CFG" ]; then
	echo "== create $NAME"
	echo no | "$SDK/cmdline-tools/latest/bin/avdmanager" create avd -n "$NAME" -k "$IMAGE" -d pixel >/dev/null
fi
# the low-spec hardware (re-applied every time, so the AVD can't drift)
sed -i '' \
	-e 's/^hw.cpu.ncore=.*/hw.cpu.ncore=2/' \
	-e 's/^hw.ramSize=.*/hw.ramSize=2048M/' \
	-e 's/^hw.lcd.width=.*/hw.lcd.width=720/' \
	-e 's/^hw.lcd.height=.*/hw.lcd.height=1600/' \
	-e 's/^hw.lcd.density=.*/hw.lcd.density=320/' \
	-e 's/^hw.lcd.depth=.*/hw.lcd.depth=32/' \
	-e 's/^vm.heapSize=.*/vm.heapSize=256M/' \
	-e 's/^hw.gpu.enabled=.*/hw.gpu.enabled=yes/' \
	-e 's/^hw.gpu.mode=.*/hw.gpu.mode=host/' \
	-e 's/^disk.dataPartition.size=.*/disk.dataPartition.size=6G/' \
	-e 's/^showDeviceFrame=.*/showDeviceFrame=no/' \
	"$CFG"
[ "$CREATE_ONLY" -eq 0 ] || exit 0

echo "== boot $NAME as emulator-$PORT"
nohup "$SDK/emulator/emulator" -avd "$NAME" -port "$PORT" -no-snapshot-save -no-boot-anim -gpu host -no-audio $WIPE \
	>"${TMPDIR:-/tmp}/lowspec-emulator.log" 2>&1 &
"$SDK/platform-tools/adb" -s "emulator-$PORT" wait-for-device
until [ "$("$SDK/platform-tools/adb" -s "emulator-$PORT" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do
	sleep 2
done
echo "== emulator-$PORT ready ($("$SDK/platform-tools/adb" -s "emulator-$PORT" shell wm size | tr -d '\r'))"
