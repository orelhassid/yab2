#!/bin/bash
# Incremental follow-up to the completed main/candidate comparison.
set -euo pipefail
cd "$(dirname "$0")/../.."
[ "${YAB_FARM_WORKER:-}" = 1 ] || exit 2
base=${1:?main revision}
out=${YAB_FARM_OUT:?}
projection="$out/main-source"
for job in "${@:2}"; do
  previous="$HOME/.local/state/yab-farm/work/fast-apps/farm-$job"
  for kept in "$previous/out" "$previous"; do
    if [ -d "$kept/main-source/.build" ] && [ "$(cat "$kept/main-commit.txt" 2>/dev/null)" = "$base" ]; then
      projection="$kept/main-source"
      break 2
    fi
  done
done
if [ ! -f "$projection/Package.swift" ]; then
  mkdir -p "$projection"
  git archive "$base" Package.swift Sources Resources Tests/MailCoreFakes Tests/MailCoreTests \
    Tests/FastTests/ChatMotionTests.swift Tests/FastTests/ChatLiveTests.swift Tests/FastTests/ChatTests.swift \
    Tests/FastTests/ChatProblemTests.swift Tests/FastTests/ResultCardTests.swift | tar -x -C "$projection"
fi
mkdir -p "$projection/Tests/FastTests"
candidate=Sources/Fast/Components/Chat/ChatTranscript/ChatTranscript.swift
base_transcript="$projection/$candidate"
[ -f "$base_transcript" ] || base_transcript="$projection/Sources/Fast/ChatTranscript.swift"
cp Tests/FastTests/ChatStreamStabilityTests.swift Tests/FastTests/TestScreen.swift "$projection/Tests/FastTests/"
cp "$candidate" "$base_transcript"
git rev-parse "$base" > "$out/main-commit.txt"
shasum -a 256 "$candidate" Tests/FastTests/ChatStreamStabilityTests.swift > "$out/source-sha256.txt"
(cd "$projection" && CHAT_STABILITY_PHASE=after YAB_PROBE=chat-stability-after YAB_HISTORY=own swift test --jobs 2 --filter 'ChatStreamStabilityTests|ChatMotionTests|ChatLiveTests|ChatTests|ChatProblemTests|ResultCardTests') 2>&1 | tee "$out/after-tests.log"
python3 - "$out" <<'PY'
import json, pathlib, sys
out=pathlib.Path(sys.argv[1])
log=(out/'after-tests.log').read_text(errors='replace')
for name in ('cardsStayAtTheirFinalPositionWhileKnownTextIsWrittenOut', 'acknowledgingTheSentMessageKeepsTheSameTypingView', 'resultCardsWaitForTheFinalBubble'):
    assert 'Test '+name+'() passed' in log, 'native check skipped or failed: '+name
(out/'followup.json').write_text(json.dumps({'candidate_passed': True, 'main_commit': (out/'main-commit.txt').read_text().strip(), 'baseline_job': '0f0911b6b09d47bc', 'scope': 'incremental follow-up; same actual main projection plus ChatTranscript.swift'},indent=2)+'\n')
PY
