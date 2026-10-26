#!/usr/bin/env bash
# Validation gate: sound and music checks (the committed audio matches tools/sfx.py and
# tools/music.py), asset import, project check (touch-first and landscape rules +
# strict script compile) and its violation fixtures, palette check (every colour from
# art/palette.hex) and its fixtures, content tests (data/SCHEMA.md invariants, art
# included), headless gameplay tests, headless run of the main scene. Exits non-zero on the first failure and points at
# the log that explains it. Every Godot call is killed after GODOT_TIMEOUT seconds.
# Env: GODOT (Godot binary), GODOT_TIMEOUT (default 300), RUN_FRAMES (headless run length, default 120).
set -euo pipefail
cd "$(dirname "$0")/.."

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
GODOT_TIMEOUT="${GODOT_TIMEOUT:-300}"
LOG_DIR=build/logs
mkdir -p "$LOG_DIR"

fail() {
  echo "FAIL $1 (log: $2)" >&2
  grep -E "ERROR|WARNING|check_project|check_palette|test_content|test_gameplay|run_main|sfx|music" "$2" >&2 || true
  exit 1
}

# Runs Godot with a hard timeout (macOS has no coreutils `timeout`; perl's alarm
# kills the process with SIGALRM, exit status 142). Usage: godot <log> <args...>
godot() {
  local log="$1"
  shift
  local status=0
  perl -e 'alarm shift @ARGV; exec @ARGV or die "exec failed: $!\n"' "$GODOT_TIMEOUT" "$GODOT" "$@" >"$log" 2>&1 || status=$?
  if [ "$status" -eq 142 ]; then
    echo "ERROR: timed out after ${GODOT_TIMEOUT}s" >>"$log"
  fi
  return "$status"
}

# Runs a Godot --script and requires exit status 0, its explicit OK line and a log
# free of ERROR/WARNING. Usage: run_script <name> <log> <extra godot args...>
run_script() {
  local name="$1" log="$2"
  shift 2
  # Godot exits 0 even when a --script fails to compile, so status 0 alone proves
  # nothing: a run passes only with status 0 and its explicit OK line (a crash or
  # signal after the OK line still fails).
  local status=0
  godot "$log" --headless --path huntfrenzy "$@" --script "$PWD/tools/$name.gd" || status=$?
  if [ "$status" -ne 0 ]; then
    fail "$name exited with status $status" "$log"
  fi
  if ! grep -q "^$name: OK" "$log" || grep -qE "ERROR|WARNING" "$log"; then
    fail "$name" "$log"
  fi
}

# The sound effects must be byte-identical to their synth (tools/sfx.py), and the music
# loops must match their recorded render, MP3 bytes and loop flags (tools/music.lock.json;
# neither check needs an encoder).
if ! python3 tools/sfx.py --check >"$LOG_DIR/sfx.log" 2>&1 || ! grep -q "^sfx: OK" "$LOG_DIR/sfx.log"; then
  fail "sound check" "$LOG_DIR/sfx.log"
fi
if ! python3 tools/music.py --check >"$LOG_DIR/music.log" 2>&1 || ! grep -q "^music: OK" "$LOG_DIR/music.log"; then
  fail "music check" "$LOG_DIR/music.log"
fi

# On a fresh clone (no import cache), and in an existing checkout after new or changed
# assets arrive (a pull, a branch switch), the first import can report errors for
# resources loaded at startup (a project font or theme, a scene's texture or sound) before
# they are imported. A priming import fills the cache; the checked import below then must
# be clean. Only cache-miss errors (a not-yet-imported file and the loads that fail because
# of it) are tolerated there; any other problem (a script or scene parse error) still fails.
CACHE_MISS="Cannot open file 'res://\.godot/imported/|Unable to open file: res://\.godot/imported/|Failed loading resource: res://|referenced non-existent resource at: res://|Error loading custom project (font|theme) 'res://"

# Prints why the import cache is stale and returns 0 when it is: no cache at all, or a
# tracked asset (a file with a committed .import) whose imported file is missing or older
# than the asset itself. Returns 1 when every asset's import is in place and up to date.
import_cache_stale() {
  if [ ! -d huntfrenzy/.godot/imported ]; then
    echo "no import cache"
    return 0
  fi
  local import source dest
  while IFS= read -r -d '' import; do
    source="${import%.import}"
    [ -f "$source" ] || continue
    while IFS= read -r dest; do
      dest="huntfrenzy/${dest#res://}"
      if [ ! -f "$dest" ]; then
        echo "${source#huntfrenzy/} is not imported yet"
        return 0
      fi
      if [ "$source" -nt "$dest" ]; then
        echo "${source#huntfrenzy/} is newer than its import"
        return 0
      fi
    done < <(sed -n 's/^dest_files=\[\(.*\)\]$/\1/p' "$import" | tr ',' '\n' | sed -n 's/^ *"\(res:\/\/[^"]*\)"$/\1/p')
  done < <(find huntfrenzy -path huntfrenzy/.godot -prune -o -name '*.import' -type f -print0)
  return 1
}

if stale="$(import_cache_stale)"; then
  echo "Import cache is stale ($stale): running the priming import"
  godot "$LOG_DIR/import_prime.log" --headless --path huntfrenzy --import || true
  if grep -E "ERROR|WARNING" "$LOG_DIR/import_prime.log" | grep -qvE "$CACHE_MISS"; then
    fail "priming import reported problems besides import-cache misses" "$LOG_DIR/import_prime.log"
  fi
fi
godot "$LOG_DIR/import.log" --headless --path huntfrenzy --import || fail "import exited non-zero" "$LOG_DIR/import.log"
if grep -qE "ERROR|WARNING" "$LOG_DIR/import.log"; then fail "import reported problems" "$LOG_DIR/import.log"; fi

run_script check_project "$LOG_DIR/check.log"

# check_project.gd against the tiny projects in tools/check_fixtures/ (outside the game,
# so they never ship): each <case>/expected.txt lists the violation lines that case must
# report (each line a prefix of one reported violation), and nothing else; a case without
# expected.txt (allowed input use) must pass. Engine ERROR/WARNING lines fail a case,
# except in a case whose expected_engine_errors.txt lists them (the strict-compile case:
# a script that fails to compile makes Godot log its parse error): each listed line must
# appear, and every ERROR/WARNING line must contain one of them.
fixtures=0
for fixture in tools/check_fixtures/*/; do
  case_name="$(basename "$fixture")"
  log="$LOG_DIR/check_fixture_$case_name.log"
  godot "$log" --headless --path "$fixture" --script "$PWD/tools/check_project.gd" || true
  engine_errors="$fixture/expected_engine_errors.txt"
  if [ -f "$engine_errors" ]; then
    while IFS= read -r line; do
      grep -qF "$line" "$log" || fail "check_project fixture $case_name did not log the expected engine error: $line" "$log"
    done <"$engine_errors"
    if grep -E "ERROR|WARNING" "$log" | grep -qvF -f "$engine_errors"; then
      fail "check_project fixture $case_name reported unexpected engine problems" "$log"
    fi
  elif grep -qE "ERROR|WARNING" "$log"; then
    fail "check_project fixture $case_name reported engine problems" "$log"
  fi
  if [ -f "$fixture/expected.txt" ]; then
    while IFS= read -r line; do
      grep -qF "check_project: $line" "$log" || fail "check_project fixture $case_name did not report: $line" "$log"
    done <"$fixture/expected.txt"
    expected="$(grep -c . "$fixture/expected.txt")"
    grep -qxF "check_project: FAILED with $expected violation(s)" "$log" || fail "check_project fixture $case_name must report exactly $expected violation(s)" "$log"
  elif ! grep -q "^check_project: OK" "$log"; then
    fail "check_project fixture $case_name (allowed input use) must pass" "$log"
  fi
  fixtures=$((fixtures + 1))
done
# check_palette.gd: every colour in the art (SVG), the scenes, the scripts, the UI Theme and
# project.godot is one of art/palette.hex's (only the alpha may differ). Each case in
# tools/palette_fixtures/ (a tiny project, outside the game) must report exactly the
# violation lines its expected.txt lists (each a prefix), and nothing else; a case without
# expected.txt must pass. No case may log an engine ERROR/WARNING.
run_script check_palette "$LOG_DIR/palette.log"
palette_fixtures=0
for fixture in tools/palette_fixtures/*/; do
  case_name="$(basename "$fixture")"
  log="$LOG_DIR/palette_fixture_$case_name.log"
  godot "$log" --headless --path "$fixture" --script "$PWD/tools/check_palette.gd" || true
  if grep -qE "ERROR|WARNING" "$log"; then
    fail "check_palette fixture $case_name reported engine problems" "$log"
  fi
  if [ -f "$fixture/expected.txt" ]; then
    while IFS= read -r line; do
      grep -qF "check_palette: $line" "$log" || fail "check_palette fixture $case_name did not report: $line" "$log"
    done <"$fixture/expected.txt"
    expected="$(grep -c . "$fixture/expected.txt")"
    grep -qxF "check_palette: FAILED with $expected violation(s)" "$log" || fail "check_palette fixture $case_name must report exactly $expected violation(s)" "$log"
  elif ! grep -q "^check_palette: OK" "$log"; then
    fail "check_palette fixture $case_name (palette colours only) must pass" "$log"
  fi
  palette_fixtures=$((palette_fixtures + 1))
done
# The data first: every data/SCHEMA.md invariant on the real data, and each one firing on
# a malformed copy.
run_script test_content "$LOG_DIR/content.log"
run_script test_gameplay "$LOG_DIR/test.log" --fixed-fps 60
summary="$(grep "^sfx: OK" "$LOG_DIR/sfx.log"); $(grep "^music: OK" "$LOG_DIR/music.log"); $(grep "^check_project: OK" "$LOG_DIR/check.log"); check fixtures: $fixtures; $(grep "^check_palette: OK" "$LOG_DIR/palette.log"); palette fixtures: $palette_fixtures; $(grep "^test_content: OK" "$LOG_DIR/content.log"); $(grep "^test_gameplay: OK" "$LOG_DIR/test.log")"
# The main scene (the title) runs 120 frames (2 s at 60 fixed fps) by default; run_main
# requires the flow state to match the running scene.
RUN_FRAMES="${RUN_FRAMES:-120}" run_script run_main "$LOG_DIR/run.log" --fixed-fps 60

echo "PASS validate ($summary)"
