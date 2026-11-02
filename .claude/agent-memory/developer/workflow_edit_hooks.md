---
name: workflow-edit-hooks
description: 이 저장소의 PostToolUse 훅은 편집한 Dart 파일마다 dart format + dart analyze를 돌리는데, 저장소가 기본 폭(80칸) 포맷을 애초에 통과하지 않아 포맷 실패는 거의 항상 거짓 경보다
metadata:
  type: project
---

파일을 고칠 때마다 `.claude/hooks/lint-after-edit.sh`가 그 파일에
`dart format --output=none --set-exit-if-changed` + `dart analyze`를 돌린다.

**포맷 실패는 대개 내 변경 탓이 아니다.** 이 저장소는 100칸 안팎의 코드 스타일로 쓰여 있는데
포맷 폭 설정(`analysis_options.yaml`의 `formatter: page_width:`)이 없어서 `dart format`이 기본 80칸으로
판단한다. 그래서 `lib/core/strings.dart`, `battle_providers.dart` 등은 **HEAD 상태에서도** 포맷 검사에
실패한다(2026-10-30 stash 후 확인). 기존 파일을 통째로 재포맷하면 작업과 무관한 거대한 diff가 생긴다.

`--output=none`이므로 **훅은 파일을 고치지 않는다**(예전 메모의 "이미 포맷되어 저장된다"는 틀렸다).

여러 Edit을 연달아 보내면 중간 상태에서 "isn't defined / unused_local_variable" 같은 analyze 오류가
함께 보고되는데, 이는 뒤이은 Edit이 아직 적용되지 않아서다. **analyze 오류는 진짜일 때가 많으니
포맷 실패와 구별해서 읽는다.**

**Why:** 훅이 편집 단위로 돌기 때문에 완성 전 상태가 매번 검사되고, 포맷 기준은 저장소 현실과 어긋나
있다. 보고를 그대로 믿고 되돌리거나 전체 재포맷으로 "고치면" 멀쩡한 변경을 망친다.

**How to apply:** ① 포맷 실패가 나면 `git stash` 후 같은 명령을 돌려 HEAD에서도 실패하는지 확인하고,
그렇다면 무시한다. ② 새로 만드는 파일과 새로 쓰는 코드 줄만 80칸에 맞춰 두면 그 파일은 훅을 통과한다
(파일 전체가 내 것이면 `dart format <파일>`을 한 번 돌려도 안전하다). ③ 최종 판단은 모든 편집이 끝난 뒤
`flutter analyze`(이슈 0) + `flutter test`로 한다. 관련: [[todododo-toolchain-paths]]
