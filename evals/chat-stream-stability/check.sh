#!/bin/bash
# Actual main, then only this chat fix over the same sources and test build.
# Parallel edits in the submitting checkout are not built or altered.
set -euo pipefail
cd "$(dirname "$0")/../.."
[ "${YAB_FARM_WORKER:-}" = 1 ] || { echo 'run through farm' >&2; exit 2; }
base=${1:?main revision}
out=${YAB_FARM_OUT:?}
baseline="$out/main-source"
for job in "${@:2}"; do
  previous="$HOME/.local/state/yab-farm/work/fast-apps/farm-$job"
  for kept in "$previous/out" "$previous"; do
    if [ -d "$kept/main-source/.build" ] && [ "$(cat "$kept/main-commit.txt" 2>/dev/null)" = "$base" ]; then
      baseline="$kept/main-source"
      break 2
    fi
  done
done
mkdir -p "$baseline/Tests/FastTests"
git archive "$base" Package.swift Sources Resources Tests/MailCoreFakes Tests/MailCoreTests \
  Tests/FastTests/ChatMotionTests.swift Tests/FastTests/ChatLiveTests.swift Tests/FastTests/ChatTests.swift \
  Tests/FastTests/ChatProblemTests.swift Tests/FastTests/ResultCardTests.swift | tar -x -C "$baseline"
candidate=Sources/Fast/Components/Chat/ChatTranscript/ChatTranscript.swift
base_transcript="$baseline/$candidate"
[ -f "$base_transcript" ] || base_transcript="$baseline/Sources/Fast/ChatTranscript.swift"
cp Tests/FastTests/ChatStreamStabilityTests.swift Tests/FastTests/TestScreen.swift "$baseline/Tests/FastTests/"
git rev-parse "$base" > "$out/main-commit.txt"
cp "$candidate" "$out/candidate-ChatTranscript.swift"
cp "$base_transcript" "$out/main-ChatTranscript.swift"
shasum -a 256 "$out/candidate-ChatTranscript.swift" Tests/FastTests/ChatStreamStabilityTests.swift > "$out/source-sha256.txt"
trap 'cp "$out/main-ChatTranscript.swift" "$base_transcript"' EXIT
set +e
(cd "$baseline" && CHAT_STABILITY_PHASE=before YAB_PROBE=chat-stability-before YAB_HISTORY=own swift test --jobs 2 --filter ChatStreamStabilityTests) 2>&1 | tee "$out/before-tests.log"
before=${PIPESTATUS[0]}
set -e
grep -q 'Test run with' "$out/before-tests.log" || { echo 'baseline did not run; stop before candidate' >&2; exit 1; }
cp "$out/candidate-ChatTranscript.swift" "$base_transcript"
(cd "$baseline" && CHAT_STABILITY_PHASE=after YAB_PROBE=chat-stability-after YAB_HISTORY=own swift test --jobs 2 --filter 'ChatStreamStabilityTests|ChatMotionTests|ChatLiveTests|ChatTests|ChatProblemTests|ResultCardTests') 2>&1 | tee "$out/after-tests.log"
python3 - "$out" "$before" <<'PY'
import json, pathlib, sys
out = pathlib.Path(sys.argv[1])
before = (out/'before-tests.log').read_text(errors='replace')
after = (out/'after-tests.log').read_text(errors='replace')
result = {'main_commit': (out/'main-commit.txt').read_text().strip(),
          'before_exit': int(sys.argv[2]),
          'main_failed_assertions': 'Expectation failed' in before and 'Test run with' in before,
          'candidate_passed': 'Test run with' in after and 'passed' in after,
          'scope': 'actual main plus only ChatTranscript.swift; native SwiftUI views and isolated session acknowledgement'}
for name in ('cardsStayAtTheirFinalPositionWhileKnownTextIsWrittenOut', 'acknowledgingTheSentMessageKeepsTheSameTypingView', 'resultCardsWaitForTheFinalBubble'):
    assert 'Test '+name+'() passed' in after, 'regression was skipped or failed: '+name
(out/'result.json').write_text(json.dumps(result, indent=2)+'\n')
print(json.dumps(result))
assert result['before_exit'] != 0 and result['main_failed_assertions'], 'baseline must fail behavioral assertions'
assert result['candidate_passed'], 'candidate must run and pass'
PY
