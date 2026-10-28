---
name: workflow-edit-hooks
description: 이 저장소의 PostToolUse 훅은 편집한 Dart 파일마다 dart format + dart analyze를 돌리고, 포맷이 바뀌면 "실패"로 보고한다
metadata:
  type: project
---

파일을 고칠 때마다 `.claude/hooks/lint-after-edit.sh`가 그 파일에 `dart format`과 `dart analyze`를 돌린다.
포맷이 한 줄이라도 바뀌면 훅이 "린트/포맷 검사 실패"로 보고하지만, **파일은 이미 포맷된 상태로 저장된
뒤**다. 여러 Edit을 한 번에 보내면 중간 상태에서 "isn't defined / unused_element" 같은 오류가 함께
보고되는데, 이는 뒤이은 Edit이 아직 적용되지 않아서다.

**Why:** 훅이 편집 단위로 돌기 때문에, 한 변경을 여러 파일·여러 Edit으로 나누면 완성 전 상태가 매번
검사된다. 보고된 오류를 그대로 믿고 되돌리면 멀쩡한 변경을 두 번 일하게 된다.

**How to apply:** 훅 보고는 참고만 하고, 판단은 모든 Edit을 끝낸 뒤 `flutter analyze` 한 번으로 한다.
훅이 포맷을 이미 고쳐 두므로 같은 파일을 다시 포맷하러 갈 필요도 없다. 관련: [[todododo-toolchain-paths]]
