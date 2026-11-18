#!/bin/bash
# Same actual ContentView key-routing tests on committed main and candidate.
# Reuses evals/feedback-472/unit_pair.sh's worker-only source swap pattern.
set -euo pipefail
cd "$(dirname "$0")/../.."
[ "${YAB_FARM_WORKER:-}" = 1 ] || { echo 'use the farm queue' >&2; exit 2; }
base="${1:?committed main base}"
out="${YAB_FARM_OUT:?}/chat-toggle-501"
mkdir -p "$out/candidate-source"
paths=(Sources/Fast/App.swift Sources/Fast/Components/Chat/ChatColumn/ChatColumn.swift Sources/Fast/Keymap.swift)
git rev-parse "$base" > "$out/main-commit"
for path in "${paths[@]}"; do
  mkdir -p "$out/candidate-source/$(dirname "$path")"
  cp "$path" "$out/candidate-source/$path"
done
shasum -a 256 Tests/FastTests/ChatToggleKeysTests.swift > "$out/test-sha256.txt"
restore() {
  for path in "${paths[@]}"; do cp "$out/candidate-source/$path" "$path"; done
}
trap restore EXIT
for path in "${paths[@]}"; do git show "$base:$path" > "$path"; done
# Assert every product source is actual main; the test is the only overlay.
git diff --quiet "$base" -- Sources Resources Package.swift build.sh yab.entitlements
run_tests() {
  local phase="$1"
  set +e
  YAB_PROBE="chat-toggle-501-${YAB_CHECK_WORLD:?}-$phase" swift test --filter ChatToggleKeysTests 2>&1 | tee "$out/$phase.log"
  local result="${PIPESTATUS[0]}"
  set -e
  printf '%s\n' "$result" > "$out/$phase.rc"
}
run_tests before
restore
run_tests after
python3 - "$out" <<'PY'
import json, pathlib, re, sys
out = pathlib.Path(sys.argv[1])
logs = {phase: (out/f'{phase}.log').read_text(errors='replace') for phase in ('before', 'after')}
codes = {phase: int((out/f'{phase}.rc').read_text()) for phase in ('before', 'after')}
compile_error = re.compile(r'\.swift:\d+:\d+: error:|error: emit-module|error: fatalError')
named = 'Test shiftEscapeOpensClosesAndReopensChat()'
before_failed = (codes['before'] != 0 and named in logs['before']
                 and 'Expectation failed' in logs['before'] and not compile_error.search(logs['before']))
after_passed = (codes['after'] == 0 and named in logs['after']
                and 'Test run with 3 tests' in logs['after'] and not compile_error.search(logs['after']))
report = {'main_commit': (out/'main-commit').read_text().strip(), 'before_rc': codes['before'],
          'after_rc': codes['after'], 'main_failed_at_runtime': before_failed,
          'candidate_passed': after_passed, 'status': 'pass' if before_failed and after_passed else 'blocked',
          'scope': 'Actual ContentView keyboard dispatch and chat model transitions; no rendered motion/focus acceptance'}
(out/'summary.json').write_text(json.dumps(report, indent=2)+'\n')
print(json.dumps(report))
sys.exit(0 if report['status'] == 'pass' else 2)
PY
