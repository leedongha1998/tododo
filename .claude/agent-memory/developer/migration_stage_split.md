---
name: migration-stage-split
description: 단계를 나눈 마이그레이션 두 파일을 같은 작업에서 만들면 supabase db push가 둘을 한 번에 적용한다 — 되돌릴 수 없는 뒤 단계는 보고에 "폴더 밖에 두고 앞 단계만 push"를 적는다
metadata:
  type: project
---

이 저장소는 원격 적용을 `supabase db push`로 하고(로컬 Docker 없음), `db push`는 **대기 중인 마이그레이션을
전부** 적용한다. design이 "A 적용·검증 → 오너 확인 → B 적용"처럼 단계를 나눠도, developer가 두 파일을 같은 작업에서
`supabase/migrations/`에 만들어 두면 메인 세션의 한 번의 push로 함께 돈다.

**Why:** nickname(2026-11-24)의 B는 기존 사용자 이름을 덮는 **되돌릴 수 없는** 단계라 오너 확인을 두 번 받아야
했다. 파일을 만들기만 해도 그 확인 지점이 구조적으로 사라질 뻔했다.

**How to apply:** 단계를 나눈 마이그레이션을 한 번에 만들 때 plan.md "적용 순서"와 보고 맨 앞에 "뒤 단계 파일을 잠시
폴더 밖에 두고 `db push --dry-run`으로 목록 확인 후 앞 단계만 적용"을 적는다. 참고: [[sql-smoke-test-now-frozen]]
