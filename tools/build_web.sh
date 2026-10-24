#!/usr/bin/env bash
# Full release pipeline: validate, clean single-threaded web export to
# build/web/, Playwright smoke test (desktop, mobile landscape, mobile portrait,
# keyboard), then build/huntfrenzy.zip for itch.io
# (index.html at the zip root, no macOS metadata).
# Env: GODOT (Godot binary).
set -euo pipefail
cd "$(dirname "$0")/.."

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
LOG_DIR=build/logs
export GODOT

tools/validate.sh

rm -rf build/web
mkdir -p build/web "$LOG_DIR"
if ! "$GODOT" --headless --path huntfrenzy --export-release Web "$PWD/build/web/index.html" >"$LOG_DIR/export.log" 2>&1 \
  || grep -qE "ERROR|WARNING" "$LOG_DIR/export.log"; then
  echo "FAIL export (log: $LOG_DIR/export.log)" >&2
  grep -E "ERROR|WARNING" "$LOG_DIR/export.log" >&2 || true
  exit 1
fi
for file in index.html index.js index.wasm index.pck; do
  [ -s "build/web/$file" ] || { echo "FAIL export is missing build/web/$file" >&2; exit 1; }
done

node tools/smoke_web.mjs build/web

rm -f build/huntfrenzy.zip
(cd build/web && zip -X -q ../huntfrenzy.zip index.*)
echo "PASS build: build/huntfrenzy.zip ($(du -h build/huntfrenzy.zip | cut -f1))"
