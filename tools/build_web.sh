#!/usr/bin/env bash
# Full release pipeline: validate, clean single-threaded web export to
# build/web/, Playwright smoke test (desktop, mobile landscape, mobile portrait,
# keyboard), then build/huntfrenzy.zip for itch.io
# (index.html at the zip root, no macOS metadata). Reports the size of the audio
# (huntfrenzy/audio, at most AUDIO_MAX_BYTES) and of the zip (at most ZIP_MAX_BYTES, itch's
# limit for an HTML game) and fails when either is over.
# The export is killed after GODOT_TIMEOUT seconds and the smoke test after
# SMOKE_TIMEOUT seconds, as in validate.sh.
# Env: GODOT (Godot binary), GODOT_TIMEOUT (default 300), SMOKE_TIMEOUT (default 900).
set -euo pipefail
cd "$(dirname "$0")/.."

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
GODOT_TIMEOUT="${GODOT_TIMEOUT:-300}"
SMOKE_TIMEOUT="${SMOKE_TIMEOUT:-900}"
LOG_DIR=build/logs
AUDIO_MAX_BYTES=$((8 * 1024 * 1024))
ZIP_MAX_BYTES=$((50 * 1024 * 1024))
export GODOT GODOT_TIMEOUT

# Runs a command with a hard timeout (macOS has no coreutils `timeout`; perl's alarm
# kills the process with SIGALRM, exit status 142). Usage: timed <seconds> <command...>
timed() {
  local seconds="$1"
  shift
  perl -e 'alarm shift @ARGV; exec @ARGV or die "exec failed: $!\n"' "$seconds" "$@"
}

tools/validate.sh

# The music and sound effects as shipped (the committed MP3 and WAV files).
audio_bytes="$(find huntfrenzy/audio -type f \( -name '*.mp3' -o -name '*.wav' \) -exec cat {} + | wc -c | tr -d ' ')"
echo "Audio: $audio_bytes bytes (limit $AUDIO_MAX_BYTES)"
if [ "$audio_bytes" -gt "$AUDIO_MAX_BYTES" ]; then
  echo "FAIL the audio is $audio_bytes bytes, over $AUDIO_MAX_BYTES" >&2
  exit 1
fi

rm -rf build/web
mkdir -p build/web "$LOG_DIR"
status=0
timed "$GODOT_TIMEOUT" "$GODOT" --headless --path huntfrenzy --export-release Web "$PWD/build/web/index.html" >"$LOG_DIR/export.log" 2>&1 || status=$?
if [ "$status" -eq 142 ]; then
  echo "ERROR: timed out after ${GODOT_TIMEOUT}s" >>"$LOG_DIR/export.log"
fi
if [ "$status" -ne 0 ] || grep -qE "ERROR|WARNING" "$LOG_DIR/export.log"; then
  echo "FAIL export, exit status $status (log: $LOG_DIR/export.log)" >&2
  grep -E "ERROR|WARNING" "$LOG_DIR/export.log" >&2 || true
  exit 1
fi
for file in index.html index.js index.wasm index.pck; do
  [ -s "build/web/$file" ] || { echo "FAIL export is missing build/web/$file" >&2; exit 1; }
done

status=0
timed "$SMOKE_TIMEOUT" node tools/smoke_web.mjs build/web || status=$?
if [ "$status" -eq 142 ]; then
  echo "FAIL smoke test timed out after ${SMOKE_TIMEOUT}s (screenshots: build/smoke-*.png)" >&2
  exit 1
elif [ "$status" -ne 0 ]; then
  echo "FAIL smoke test, exit status $status" >&2
  exit 1
fi

rm -f build/huntfrenzy.zip
(cd build/web && zip -X -q ../huntfrenzy.zip index.*)
zip_bytes="$(wc -c <build/huntfrenzy.zip | tr -d ' ')"
if [ "$zip_bytes" -gt "$ZIP_MAX_BYTES" ]; then
  echo "FAIL build/huntfrenzy.zip is $zip_bytes bytes, over $ZIP_MAX_BYTES" >&2
  exit 1
fi
echo "PASS build: build/huntfrenzy.zip ($zip_bytes bytes, limit $ZIP_MAX_BYTES; audio $audio_bytes bytes, limit $AUDIO_MAX_BYTES)"
