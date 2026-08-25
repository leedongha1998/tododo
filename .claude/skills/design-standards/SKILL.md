---
name: design-standards
description: 설계 문서(design.md) 작성 기준과 템플릿
---

# 설계 문서 기준

`docs/specs/<feature>/design.md`를 작성할 때 이 기준을 따른다.

## 다루는 것 / 다루지 않는 것
- spec.md에 있는 요구사항의 화면 구성, API 계약(RPC/테이블), 데이터 흐름만 다룬다.
- spec.md에 없는 요구사항을 새로 만들어내지 않는다. 빠진 부분이 있으면 "## 결정 필요"에 질문으로 남긴다.
- 실제 구현 순서, 파일 목록, 커밋 계획은 다루지 않는다 — plan.md(개발자) 영역이다.

## design.md 템플릿

```markdown
# <feature-name> 설계

## 참고
spec.md: [TODO: 링크 또는 경로]

## 화면
[TODO: 화면 목록과 각 화면의 상태(빈 상태/로딩/에러 포함)]

## 데이터 흐름
[TODO: 사용자 액션 → provider/repository → DB(RPC/RLS) → 화면 반영]

## API 계약
[TODO: RPC 이름, 파라미터, 반환값 / 테이블 select-eq 패턴]
CLAUDE.md 도메인 규칙(대결 상태 전이, 판정 로직 위치)과 충돌하지 않는지 확인한다.

## 결정 필요
[TODO — 없으면 "없음"]
```

## 근거
- 세부 표기법(다이어그램 형식 등)은 [검토 필요] — 프로젝트 진행하며 채울 것.
