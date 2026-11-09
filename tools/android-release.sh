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
# R8 shrinks the Java side of the release build (ads, Play, Firebase: ~9.5 -> 5 MB in the download). godot/android/build
# is the editor's Android build template (not in git), so switch it on there every time; the rules are in git.
GRADLE="$REPO/godot/android/build/build.gradle"
[ -f "$GRADLE" ] || { echo "no Android build template at godot/android/build (install it from the editor)" >&2; exit 1; }
if ! grep -q "r8-rules.pro" "$GRADLE"; then
	python3 - "$GRADLE" <<'EOF'
import sys
p = sys.argv[1]; s = open(p).read()
old = "        release {\n            // Signing and zip-aligning"
new = ("        release {\n"
       "            // Ludo Zing: R8 shrinks the Java side (ads, Play, Firebase); rules in godot/android/r8-rules.pro (tools/android-release.sh adds this).\n"
       "            minifyEnabled true\n"
       "            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), '../r8-rules.pro'\n"
       "            // Signing and zip-aligning")
if s.count(old) != 1:
    sys.exit("android-release: can't find the release build type in " + p)
open(p, "w").write(s.replace(old, new))
EOF
	echo "== R8 switched on in godot/android/build/build.gradle"
fi
"$REPO/tools/android-engine.sh" status || true      # Ludo Zing's own engine or the official one (tools/android-engine.sh)
"${GODOT:-godot}" --headless --path "$REPO/godot" --export-release "Android Release" "$REPO/build/android/ludo-zing-release.aab"
"$JAVA_HOME/bin/jarsigner" -verify "$REPO/build/android/ludo-zing-release.aab" | tail -1
echo "== built $REPO/build/android/ludo-zing-release.aab"
