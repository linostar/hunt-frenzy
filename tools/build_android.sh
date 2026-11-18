#!/usr/bin/env bash
# Android build: validate, then export through the "Android" (APK, itch.io) and "Android Play"
# (AAB through the Gradle build, Google Play) presets, and check each file with the SDK's tools.
#   tools/build_android.sh debug     -> build/android/huntfrenzy-debug.apk and -debug.aab,
#                                       signed with the editor's debug keystore
#   tools/build_android.sh release   -> build/android/huntfrenzy.apk and huntfrenzy.aab, signed
#                                       with the release key
# Release signing comes from the environment, never from the repo (it is public):
#   ANDROID_KEYSTORE   path to the release keystore
#   ANDROID_KEY_ALIAS  the key's alias
#   the password is asked for (not shown) unless GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD is set.
# Env: GODOT (Godot binary), ANDROID_SDK (default ~/Library/Android/sdk), SKIP_VALIDATE=1.
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="${1:-debug}"
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
ANDROID_SDK="${ANDROID_SDK:-$HOME/Library/Android/sdk}"
BUILD_TOOLS="$(ls -d "$ANDROID_SDK"/build-tools/* | sort -V | tail -1)"
OUT=build/android
LOG_DIR=build/logs
# Google Play's limit for an app bundle's download; itch.io's for an upload is far larger.
SIZE_LIMIT=$((150 * 1024 * 1024))
mkdir -p "$OUT" "$LOG_DIR"

fail() { echo "FAIL $1" >&2; exit 1; }

case "$MODE" in
  debug) EXPORT=--export-debug; SUFFIX=-debug ;;
  release)
    EXPORT=--export-release; SUFFIX=""
    [ -n "${ANDROID_KEYSTORE:-}" ] && [ -f "$ANDROID_KEYSTORE" ] || fail "release: set ANDROID_KEYSTORE to the release keystore file"
    [ -n "${ANDROID_KEY_ALIAS:-}" ] || fail "release: set ANDROID_KEY_ALIAS to the key's alias"
    if [ -z "${GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD:-}" ]; then
      read -r -s -p "Password of $ANDROID_KEYSTORE: " GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD
      echo
    fi
    export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$ANDROID_KEYSTORE"
    export GODOT_ANDROID_KEYSTORE_RELEASE_USER="$ANDROID_KEY_ALIAS"
    export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD
    ;;
  *) fail "usage: tools/build_android.sh debug|release" ;;
esac

if [ "${SKIP_VALIDATE:-}" != 1 ]; then
  tools/validate.sh || fail "validate"
fi

APK="$OUT/huntfrenzy$SUFFIX.apk"
AAB="$OUT/huntfrenzy$SUFFIX.aab"
rm -f "$APK" "$AAB"
"$GODOT" --headless --path huntfrenzy "$EXPORT" "Android" "$PWD/$APK" >"$LOG_DIR/android_apk.log" 2>&1 \
  || fail "APK export (log: $LOG_DIR/android_apk.log)"
# The Gradle build (the AAB) needs Godot's Android build template in the project (git-ignored,
# huntfrenzy/android/). --install-android-build-template works only with an export: on its
# own it just runs the game.
TEMPLATE=()
[ -f huntfrenzy/android/build/build.gradle ] || TEMPLATE=(--install-android-build-template)
"$GODOT" --headless --path huntfrenzy ${TEMPLATE[@]+"${TEMPLATE[@]}"} "$EXPORT" "Android Play" "$PWD/$AAB" >"$LOG_DIR/android_aab.log" 2>&1 \
  || fail "AAB export (log: $LOG_DIR/android_aab.log)"
for file in "$APK" "$AAB"; do
  [ -s "$file" ] || fail "$file was not written"
  size=$(stat -f %z "$file" 2>/dev/null || stat -c %s "$file")
  [ "$size" -le "$SIZE_LIMIT" ] || fail "$file is $size bytes (limit $SIZE_LIMIT)"
done

# The APK: package, version, target SDK, CPU types, permissions and its signature.
"$BUILD_TOOLS/aapt2" dump badging "$APK" | grep -E "^package:|targetSdkVersion|native-code|uses-permission" | sed 's/^/  /'
"$BUILD_TOOLS/apksigner" verify --print-certs "$APK" | grep -E "Signer #1 certificate DN" | sed 's/^/  /' \
  || fail "the APK's signature does not verify"
# The AAB is signed like a JAR, in a release build only (Gradle leaves a debug AAB unsigned;
# Google Play never takes one).
if [ "$MODE" = release ]; then
  JARSIGNER="$(/usr/libexec/java_home -v 17 2>/dev/null)/bin/jarsigner"
  "$JARSIGNER" -verify "$AAB" 2>&1 | grep -q "jar verified" || fail "the AAB's signature does not verify"
fi

echo "PASS android $MODE: $APK ($(stat -f %z "$APK" 2>/dev/null || stat -c %s "$APK") bytes), $AAB ($(stat -f %z "$AAB" 2>/dev/null || stat -c %s "$AAB") bytes)"
