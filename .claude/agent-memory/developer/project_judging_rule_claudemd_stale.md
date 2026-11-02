---
name: project-judging-rule-claudemd-stale
description: CLAUDE.md 도메인 규칙의 "판정은 AI 심판이 한다"는 낡았다 — 2026-09-18 mutual-judge가 판정 주체를 참가자 상호 판정으로 대체했고 그것이 구현·배포된 상태다
metadata:
  type: project
---

CLAUDE.md "도메인 규칙"은 `docs/specs/ai-judge/spec.md` 기준으로 쓰여 있어 **"판정은 참가자가 아니라
AI 심판이 한다. 사용자끼리 서로의 증거를 승인/이의제기하는 절차는 없다"**고 적혀 있다. 그러나
2026-09-18 오너가 확정한 `docs/specs/mutual-judge/spec.md`가 **판정 주체와 마감 기간 조항만 대체**했다:

- 두 유형 모두 마감(또는 양쪽 제출) 뒤 `judging` 창에서 **참가자가 서로를 판정**하고, 판정이 갈리면
  그때만 AI가 확정한다(AI 호출 비용·한도가 동기). 미판정은 승인으로 간주된다.
- 기간은 1분~7일 커스텀(`duration_minutes`)이다. 1일/3일/7일 고정이 아니다.
- 기준 생성·증거 규칙·동의·점수·한도·모집 매칭·포기·탈퇴는 ai-judge 그대로 유효하다.

구현도 끝나 있다(`judgment_rules.dart`, `judgment_section.dart`, `submit_judgment` RPC, 커밋
`eb5ce4e` "mutual-judge 3단계 원격 적용 완료"). 상태 전이도 CLAUDE.md와 달라 **속도전도 `judging`을 거친다.**

**Why:** 이 어긋남을 "spec vs CLAUDE.md 충돌"로 읽고 작업을 멈추면, 이미 오너가 결정하고 배포한 구조를
다시 묻는 헛걸음이 된다(2026-10-30 mobile-ux M1에서 실제로 판단이 필요했다). 반대로 CLAUDE.md만 믿고
"상호 판정은 범위 밖"이라고 지우면 동작 중인 기능을 깬다.

**How to apply:** 판정·마감 관련 작업에서 CLAUDE.md와 코드가 어긋나면 **mutual-judge 쪽이 최신**이라고
보고 진행하되, 그 사실을 plan.md와 보고에 적는다. CLAUDE.md 본문 수정은 오너 몫이므로 임의로 고치지 않는다.
