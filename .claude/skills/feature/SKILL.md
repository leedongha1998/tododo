---
name: feature
description: pm → designer → developer → reviewer로 이어지는 기능 개발 파이프라인. spec.md 작성부터 구현, 리뷰까지 진행하고 사용자 승인 지점에서 멈춘다.
disable-model-invocation: true
argument-hint: <feature-name>
---

# /feature 파이프라인

인자로 받은 `$ARGUMENTS`를 기능 이름(feature-name)으로 사용한다. 값이 없으면 사용자에게 물어보고 진행하지 않는다.

서브에이전트(pm/designer/developer/reviewer)는 이 대화의 이전 맥락을 전혀 보지 못한다. 모든 공유 상태는
`docs/specs/$ARGUMENTS/` 아래 파일로만 전달한다. 서브에이전트는 AskUserQuestion을 쓸 수 없으므로, 사용자
판단이 필요한 지점은 각 문서의 "## 결정 필요" 섹션에 남기고, 이 스킬(메인 대화)이 사용자에게 직접 묻는다.

## 단계

### 1. 디렉터리 준비
`docs/specs/$ARGUMENTS/` 디렉터리를 만든다. 이미 있으면 그대로 사용한다(재실행 가능해야 함).

### 2. 기획 (pm)
`pm` 에이전트에 위임해 `docs/specs/$ARGUMENTS/spec.md`를 작성하게 한다.
요청에는 기능 이름과, 사용자가 이번에 전달한 요구사항 원문을 그대로 포함해 전달한다(pm은 이 대화를 못 보므로).

### 3. spec.md 승인
spec.md 내용을 사용자에게 보여준다.

- "## 결정 필요" 섹션이 비어 있지 않으면(= "없음"이 아니면), 그 항목들을 AskUserQuestion으로 하나씩 사용자에게 묻는다.
  받은 답을 spec.md의 해당 섹션에 반영해 갱신한다.
- 이후 사용자에게 spec.md 승인 여부를 확인한다. **승인 전에는 절대 4단계로 넘어가지 않는다.**
- 사용자가 수정을 요구하면 pm 에이전트를 다시 resume하거나 재위임해 spec.md를 고친 뒤 다시 이 단계를 반복한다.

### 4. 설계 (designer)
`designer` 에이전트에 위임해 spec.md를 읽고 `docs/specs/$ARGUMENTS/design.md`를 작성하게 한다.

design.md도 3단계와 동일하게: "## 결정 필요" 항목을 AskUserQuestion으로 묻고 반영 → 사용자 승인.
**승인 전에는 절대 5단계로 넘어가지 않는다.**

### 5. 구현 (developer)
`developer` 에이전트에 위임한다. spec.md와 design.md를 먼저 읽고 `docs/specs/$ARGUMENTS/plan.md`(작업 순서)를
작성한 뒤 구현하도록 요청에 명시한다.

developer가 "기준과 spec이 충돌해 멈췄다"고 보고하면, 그 내용을 사용자에게 그대로 전달하고 사용자 결정을 받은
뒤에만 developer를 resume한다. 임의로 대신 결정하지 않는다.

### 6. 검토 (reviewer)
`reviewer` 에이전트에 위임해 `git diff` 기준으로 검토하게 한다.

- Critical 항목이 있으면: developer 에이전트를 **resume**해서(새로 spawn하지 않는다 — 맥락 유지를 위해) 수정하게 하고,
  다시 reviewer로 검토한다.
- 이 반복은 최대 2회까지. 2회 후에도 Critical이 남아 있으면 반복을 멈추고 사용자에게 남은 Critical 항목을 보고한다.

### 7. 최종 보고
다음을 3줄 내외로 요약해 사용자에게 보고한다:
- 변경된 파일 목록
- 기준(CLAUDE.md/dev-standards) 이탈 항목 (Warning/Suggestion 중 남은 것)
- 미결 사항 (2회 반복 후에도 남은 Critical, 또는 developer가 보고한 미해결 충돌)
