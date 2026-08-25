#!/usr/bin/env bash
# PostToolUse(Edit|Write) 훅 — developer 에이전트 전용. 수정한 .dart 파일을 포맷/분석 검사한다.
# 서브에이전트 프론트매터(hooks:)에서만 로드되므로 developer 실행 중에만 적용된다.
set -uo pipefail

input="$(cat)"

file_path="$(node -e '
let data = "";
process.stdin.on("data", (d) => { data += d; });
process.stdin.on("end", () => {
  try {
    const json = JSON.parse(data);
    process.stdout.write((json.tool_input && json.tool_input.file_path) || "");
  } catch (e) {
    process.stdout.write("");
  }
});
' <<< "$input")"

if [ -z "$file_path" ]; then
  exit 0
fi

case "$file_path" in
  *.dart) ;;
  *) exit 0 ;;
esac

if [ ! -f "$file_path" ]; then
  exit 0
fi

format_output="$(dart format --output=none --set-exit-if-changed "$file_path" 2>&1)"
format_status=$?

analyze_output="$(dart analyze "$file_path" 2>&1)"
analyze_status=$?

if [ "$format_status" -ne 0 ] || [ "$analyze_status" -ne 0 ]; then
  {
    echo "린트/포맷 검사 실패: $file_path"
    [ "$format_status" -ne 0 ] && echo "--- dart format ---" && echo "$format_output"
    [ "$analyze_status" -ne 0 ] && echo "--- dart analyze ---" && echo "$analyze_output"
  } >&2
  exit 2
fi

exit 0
