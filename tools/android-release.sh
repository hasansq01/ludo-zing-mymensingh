#!/bin/sh
# Builds the signed Play Store App Bundle: build/android/ludo-zing-release.aab (Gradle build, "Android Release"
# preset). The upload key lives outside the repo: ~/.android/ludo-zing-release/upload-key.properties
# (keystore=, alias=, password=). Bump version/code in godot/export_presets.cfg before every Play upload.
set -eu
REPO="$(cd "$(dirname "$0")/.." && pwd)"
KEY="${LUDO_UPLOAD_KEY:-$HOME/.android/ludo-zing-release/upload-key.properties}"
[ -f "$KEY" ] || { echo "upload key settings not found: $KEY" >&2; exit 1; }
prop() { sed -n "s/^$1=//p" "$KEY"; }
export JAVA_HOME="${JAVA_HOME:-/Applications/Android Studio.app/Contents/jbr/Contents/Home}"
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$(prop keystore)"
export GODOT_ANDROID_KEYSTORE_RELEASE_USER="$(prop alias)"
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="$(prop password)"
mkdir -p "$REPO/build/android"
"${GODOT:-godot}" --headless --path "$REPO/godot" --export-release "Android Release" "$REPO/build/android/ludo-zing-release.aab"
"$JAVA_HOME/bin/jarsigner" -verify "$REPO/build/android/ludo-zing-release.aab" | tail -1
echo "== built $REPO/build/android/ludo-zing-release.aab"
