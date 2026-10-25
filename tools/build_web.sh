#!/usr/bin/env bash
# Full release pipeline: validate, clean single-threaded web export to
# build/web/, Playwright smoke test (desktop, mobile landscape, mobile portrait,
# keyboard), then build/huntfrenzy.zip for itch.io
# (index.html at the zip root, no macOS metadata).
# The export is killed after GODOT_TIMEOUT seconds and the smoke test after
# SMOKE_TIMEOUT seconds, as in validate.sh.
# Env: GODOT (Godot binary), GODOT_TIMEOUT (default 300), SMOKE_TIMEOUT (default 900).
set -euo pipefail
cd "$(dirname "$0")/.."

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
GODOT_TIMEOUT="${GODOT_TIMEOUT:-300}"
SMOKE_TIMEOUT="${SMOKE_TIMEOUT:-900}"
LOG_DIR=build/logs
export GODOT GODOT_TIMEOUT

# Runs a command with a hard timeout (macOS has no coreutils `timeout`; perl's alarm
# kills the process with SIGALRM, exit status 142). Usage: timed <seconds> <command...>
timed() {
  local seconds="$1"
  shift
  perl -e 'alarm shift @ARGV; exec @ARGV or die "exec failed: $!\n"' "$seconds" "$@"
}

tools/validate.sh

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
echo "PASS build: build/huntfrenzy.zip ($(du -h build/huntfrenzy.zip | cut -f1))"
