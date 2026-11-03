#!/bin/sh
# Builds the notifications Godot Android plugin (godot/android/plugins/notifications, Kotlin) and copies
# the debug + release AARs to godot/addons/notifications/bin/, where the export plugin picks them up. The AARs are
# tracked in git, so this only needs to run after changing the Kotlin source or the dependency versions.
#
# Usage: tools/build-notifications-plugin.sh [--clean]
#
# Env: ANDROID_HOME / ANDROID_SDK_ROOT (default: ~/Library/Android/sdk),
#      JAVA_HOME (default: Android Studio's bundled JBR; needs JDK 17+).
# Gradle (wrapper 8.11.1, same as the Godot 4.7.2 build template) fetches AGP, Kotlin, org.godotengine:godot
# (compile only) and firebase-messaging from Google Maven / Maven Central on first run.
set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
PLUGIN_DIR="$REPO/godot/android/plugins/notifications"
BIN_DIR="$REPO/godot/addons/notifications/bin"
CLEAN=0

while [ $# -gt 0 ]; do
	case "$1" in
		--clean) CLEAN=1 ;;
		-h|--help) sed -n '2,11p' "$0"; exit 0 ;;
		*) echo "build-notifications-plugin: unknown option $1" >&2; exit 2 ;;
	esac
	shift
done

ANDROID_HOME="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
export ANDROID_HOME
if [ -z "${JAVA_HOME:-}" ]; then
	for j in "/Applications/Android Studio.app/Contents/jbr/Contents/Home" \
		"$(/usr/libexec/java_home -v 17+ 2>/dev/null || true)"; do
		if [ -n "$j" ] && [ -x "$j/bin/java" ]; then JAVA_HOME="$j"; break; fi
	done
fi
[ -n "${JAVA_HOME:-}" ] || { echo "build-notifications-plugin: set JAVA_HOME to a JDK 17+" >&2; exit 1; }
export JAVA_HOME
[ -d "$ANDROID_HOME/platforms" ] || { echo "build-notifications-plugin: no Android SDK at $ANDROID_HOME" >&2; exit 1; }

TASKS="assembleDebug assembleRelease"
[ "$CLEAN" -eq 1 ] && TASKS="clean $TASKS"

echo "== gradle $TASKS ($PLUGIN_DIR)"
# shellcheck disable=SC2086
(cd "$PLUGIN_DIR" && ./gradlew --no-daemon -q $TASKS)

OUT="$PLUGIN_DIR/build/outputs/aar"
mkdir -p "$BIN_DIR/debug" "$BIN_DIR/release"
cp "$OUT/Notifications-debug.aar" "$BIN_DIR/debug/Notifications-debug.aar"
cp "$OUT/Notifications-release.aar" "$BIN_DIR/release/Notifications-release.aar"
ls -l "$BIN_DIR/debug/Notifications-debug.aar" "$BIN_DIR/release/Notifications-release.aar" | awk '{print "== " $NF " (" $5 " bytes)"}'
