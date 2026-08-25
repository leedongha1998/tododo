#!/usr/bin/env bash
# PreToolUse(Write) 훅 — pm/designer 에이전트가 docs/specs/ 밖에 쓰는 것을 막는다.
# 서브에이전트 프론트매터(hooks:)에서만 로드되므로 해당 에이전트 실행 중에만 적용된다.
set -euo pipefail

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

normalized="${file_path//\\//}"

case "$normalized" in
  */docs/specs/*|docs/specs/*)
    exit 0
    ;;
  *)
    echo "차단됨: 이 에이전트는 docs/specs/ 아래에만 쓸 수 있습니다 (요청 경로: $file_path)" >&2
    exit 2
    ;;
esac
