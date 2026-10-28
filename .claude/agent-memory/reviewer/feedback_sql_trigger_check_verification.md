---
name: feedback_sql_trigger_check_verification
description: 로컬 Postgres 없이 SQL 트리거/CHECK 제약의 정합성을 검토할 때는 경계값을 직접 대입해 논리적으로 검산한다
metadata:
  type: feedback
---

이 프로젝트는 로컬에 Docker가 없어 `supabase/migrations/*.sql`을 실행 검증할 수 없다(CLAUDE.md에
명시된 환경 제약). 그렇다고 SQL 변경을 "실행해볼 수 없으니 통과"로 넘기면 안 된다 — 트리거가 만드는
값이 같은 마이그레이션 세트의 CHECK 제약을 실제로 만족하는지는 코드만 보고도 경계값 대입으로 검증
가능하다.

**검증 방법**: 트리거/함수가 만들어내는 값에 대해 다음 경계 케이스를 하나씩 손으로 대입해본다.
- 입력이 비어있거나 공백뿐인 경우 (하한 위반 가능성)
- 입력이 길이 상한을 정확히 넘거나 걸치는 경우, 특히 자르는 지점(`left(...)` 등)이 공백/특수문자와
  겹치는 경우 (상한 위반, 트림 불일치 가능성)
- 여러 변환 함수가 중첩된 경우(`trim(left(coalesce(nullif(...))))`) 안쪽부터 바깥쪽까지 순서대로
  값을 치환하며 최종 결과가 CHECK의 모든 조건절을 만족하는지 확인

실제 사례: `handle_new_user` 트리거의 `trim(left(coalesce(nullif(trim(full_name), ''), email), 30))`가
CHECK `display_name = trim(display_name) and char_length(display_name) between 1 and 30`을
만족하는지, "트림된 문자열의 첫 글자는 공백이 아니므로 `left()`로 자른 뒤 바깥쪽 `trim()`이 앞부분을
먹는 일은 없다"는 논리로 하한(≥1)을 검산했다. 이런 식으로 실제 실행 없이도 결함을 찾거나(라운드 1에서
발견한 Critical/Warning) 수정이 실제로 맞는지(라운드 2에서 확인) 판단할 수 있다.

**Why**: 로컬 Postgres 부재라는 환경 제약 때문에 SQL 마이그레이션 리뷰의 엄밀성을 낮추면, 판정/상태
전이와 무관한 필드라도 회원가입처럼 되돌리기 어려운 실패(CLAUDE.md CHECK 위반 시 insert 롤백)를
놓칠 수 있다.

**How to apply**: SQL 마이그레이션 diff를 검토할 때, "실행 검증 불가"라는 이유로 로직 검토를 생략하지
말고 경계값 대입 검산을 리뷰 코멘트에 명시적으로 남긴다.
