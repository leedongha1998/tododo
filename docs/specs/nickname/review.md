# nickname 리뷰 (2026-11-24)

대상: 커밋되지 않은 작업 트리 전체(`git status`의 nickname 관련 수정·신규 파일).
기준: `CLAUDE.md`, `docs/specs/nickname/{spec,design,plan}.md`(오너 결정 포함), dev-standards.

## 한 줄 결론

**차단(Critical) 없음.** 보안의 핵심인 쓰기 경로 닫기, `handle_new_user`, `delete_account` 재정의, B의 대상 선정은
읽기·원격 SELECT 검산으로 맞다. 다만 **원격 적용 직후 돌릴 SQL 검증 파일이 틀렸다** — `nickname_rules.sql`은
구현이 맞아도 6행이 `ok=false`로 나오고(거짓 실패), 풀 검증 행 2개는 함수를 실제로 부르지 않는다(공허한 통과).
"A 적용 → 스모크 전부 ok → B" 순서가 이 파일에 기대므로 **A 적용 전에 고칠 것**(경고 1·2).

## 검증한 방법

- `flutter analyze` 0건, `flutter test` 1028 통과(이 리뷰에서 다시 돌림).
- 원격은 **읽기 전용 SELECT만** 돌렸다(`supabase db query --linked -f`, 쓰기·DDL 없음). 확인한 사실:
  - `profiles` 정책은 `profiles are viewable by any authenticated user`(SELECT)와 `users can update their own profile`(UPDATE)
    둘뿐이다 — A의 `drop policy if exists` 이름이 맞다.
  - `profiles` 테이블 권한은 anon·authenticated·service_role에 `arwdDxtm` 전부. **컬럼 단위 ACL(`attacl`)은 전부 null**이라
    테이블 단위 `revoke`로 쓰기가 실제로 닫힌다(컬럼 grant가 남는 우회 없음). `profiles`를 참조하는 뷰 0개.
  - `profiles`를 쓰는 public 함수는 `delete_account`(definer)와 `handle_new_user`(definer) 둘뿐이다. `auth.users` 트리거는
    `on_auth_user_created` 하나(INSERT). 메타데이터 갱신 경로로 이름이 다시 들어올 길이 없다.
  - 소유자 `postgres`, `force row level security` 꺼짐, `postgres`는 `bypassrls` → invoker 내부 함수가 DEFINER 안에서
    RLS 0정책 테이블을 읽는 데 문제가 없다.
  - plan S1: `server_encoding` UTF8, Postgres **17.6**, NFD로 만든 `연습봇`이 `normalize(…, NFC)`로 `연습봇`이 된다.
  - plan S2: DB 콜레이션 en_US.UTF-8에서도 `[가-힣ㄱ-ㅣ]`는 코드 포인트 범위다 — U+3164·U+318D·U+1100 모두 불일치.
  - plan S3: `match`를 컬럼 이름으로 쓸 수 있다.
  - plan S8: `odd_tombstones` = 0, B 대상(`targets`) = 43, `@` 든 이름 = 1, 봇 행 1.
- `delete_account`: `20261116120000_notification_dismiss.sql:213`의 함수 본문과 A의 본문을 잘라 `git diff --no-index`로
  비교 — **차이는 `nickname_states` 삭제 2줄(주석 1 + 문장 1)뿐**이다. 그 뒤 마이그레이션(`20261120*`, `20261124120000`,
  `20261124130000`)에 재정의 없음.
- plpgsql 이름 충돌(S4): `check_nickname`의 OUT `term`/`code`/`normalized`와 겹치는 SQL 참조는 전부 `b.term`처럼
  한정돼 있고, `b`는 plpgsql 변수·블록 이름이 아니다. 충돌 없음.
- S5(권한 없으면 RLS 0행이 아니라 42501), S6(`'{}'` claims → `auth.uid()` null), S10(DO 블록 안 문장마다 새 스냅숏):
  읽어서 맞다.

---

## 경고 (Warning)

### 경고 1. `nickname_rules.sql`의 권한 표 6행이 구현이 맞아도 실패한다 — `concat_ws`는 불리언을 `t`/`f`로 쓴다

- 위치: `supabase/tests/nickname_rules.sql:204-208`(605), `:213-217`(607), `:219-225`(608), `:227-231`(609),
  `:233-237`(610), `:249-254`(612)
- 무엇이 틀렸나: `concat_ws('/', bool, bool, …)`는 타입 출력 함수(`boolout`)를 써서 `'t/f'`를 만든다. 기대값은
  `'false/false/false'`·`'true/true/true'`이다. **원격에서 확인함**: `concat_ws('/', true, false)` → `t/f`,
  `true::text` → `true`.
- 실패 시나리오: A를 올바르게 적용하고 plan 순서대로 `nickname_rules.sql`을 돌리면 `999 전체`가 `false`로 나온다.
  운영자는 (a) 멀쩡한 A를 의심해 B를 미루거나, (b) "권한 행은 원래 실패한다"고 익숙해져, **정말 권한이 열려 있을 때도**
  같은 모양의 실패를 무시하게 된다. 보안 검증 행이 정확히 이 6행이다.
- 고칠 방향: 각 불리언에 `::text`를 붙인다.
  ```sql
  concat_ws('/',
    has_table_privilege('authenticated', 'public.profiles', 'update')::text,
    has_table_privilege('authenticated', 'public.profiles', 'insert')::text,
    has_table_privilege('authenticated', 'public.profiles', 'delete')::text)
  ```
  (604·606·613처럼 이미 `::text`를 쓰는 행은 맞다. `nickname_flow_smoke.sql`은 불리언을 `::text`로만 이어 붙여 해당 없음.)

### 경고 2. 풀 검증 행 두 개는 `assert_nickname_pool_valid()`를 실제로 부르지 않는다 (항상 통과)

- 위치: `supabase/tests/nickname_rules.sql:165`(504), `supabase/tests/nickname_flow_smoke.sql:389`(`pool_ok_after_removal`).
  원인은 `supabase/migrations/20261124140000_nickname.sql:341`의 `stable` 선언.
- 무엇이 틀렸나: `(select 'ok' from (select public.assert_nickname_pool_valid()) x)` — 함수가 `stable`이라 플래너가
  FROM 서브질의를 끌어올리고(pull-up), 바깥이 그 열을 참조하지 않으니 호출식이 통째로 사라진다. volatile이면 끌어올리지
  않지만 stable은 끌어올린다. **원격에서 같은 모양으로 재현함**: 없는 설정을 읽어 오류를 내는 stable 함수
  `current_setting('nosuch.…')`를 직접 부르면 오류, `(select 'ok' from (select current_setting('nosuch.…')) x)`는 `ok`.
- 실패 시나리오: 504 행은 단어표·금칙어가 어떻게 바뀌어도 `ok`다. 지금은 마이그레이션 마지막 줄(`:703`, 최상위 `select`라
  실제로 실행됨)과 스모크의 양성 대조(`perform`, `:381`)가 진짜 검사를 하므로 **현재 결과는 안전**하지만, 테스트 표가
  "1,600 조합 전부 통과"를 보증한다고 적은 행이 아무것도 보증하지 않는다. 운영 규칙("금칙어를 바꾸는 마이그레이션 끝줄에
  assert")을 빼먹은 미래 마이그레이션 뒤에 이 표를 돌리면 거짓 안심을 준다.
- 고칠 방향(둘 다 권함):
  1. `assert_nickname_pool_valid()`를 `volatile`로 바꾼다(예외를 던지는 검사 함수라 의미상으로도 맞다). 그러면 끌어올리지
     않고 서브질의 열을 계산한다.
  2. 스모크는 이미 쓰는 모양으로 바꾼다:
     ```sql
     begin
       perform public.assert_nickname_pool_valid();
       v_pool_after := 'ok';
     exception when others then
       v_pool_after := sqlerrm;
     end;
     ```

### 경고 3. 허용 문자인 호환 자모 `ㅣ`·`ㅇ`로 영문 예약어를 흉내 낼 수 있다 (확신 중간 — 화면 모양은 실기기 확인 필요)

- 위치: `supabase/migrations/20261124140000_nickname.sql:218`(`nickname_compare_key`)
- 무엇이 틀렸나: design §2.3은 영문 혼동 문자(`0→o`, `1→i`, `l→i`)를 접어 `adm1n`·`T0D0DUDU`를 막는다. 그런데 허용 문자에
  호환 자모가 들어 있어 **같은 종류의 흉내가 자모로는 통한다.** `ㅣ`(U+3163)는 `I`/`l`, `ㅇ`(U+3147)은 `O`처럼 보인다.
  원격에서 확인함: `'ADMㅣN'`은 허용 문자 정규식을 통과하고 비교 키가 `admㅣn`이라 `admin` 포함 검사에 걸리지 않는다.
- 실패 시나리오: `ADMㅣN`, `ㅇFFㅣCㅣAL`, `TㅇDㅇDUDU`, `SYSTEM ㅇ`… 가 `set_nickname`을 통과해 모집 목록에 뜬다.
  spec P0-4가 막으려던 "운영자·앱 사칭"이 정확히 이것이다. 한글 자모는 전각 폭이라 `ADMㅣN`이 `ADM I N`처럼 간격이
  넓게 보일 수는 있어서 얼마나 그럴듯한지는 기기 폰트를 봐야 한다 — 그래서 차단이 아니라 경고로 둔다.
- 고칠 방향: 접기 목록에 두 글자를 더한다. 단어표는 완성형만이라 풀 검증에 영향이 없고, 금칙어의 초성(`ㅅㅂ`·`ㅆㅂ`·
  `ㅂㅅ`·`ㅄ`)에는 `ㅣ`·`ㅇ`이 없어 영향이 없다.
  ```sql
  select translate(lower(replace(coalesce(p_normalized, ''), ' ', '')), '01lㅣㅇ', 'oiiio')
  ```
  `nickname_rules.sql`에 `ADMㅣN`→RESERVED/admin, `TㅇDㅇDUDU`→RESERVED/tododudu 두 행을 더한다. (design §2.3의
  "한글의 비슷한 글자는 접지 않는다"는 한글끼리의 비슷함에 대한 말이고, 이 둘은 라틴 문자 흉내라 같은 문단의 0/1/l 접기와
  같은 종류다 — 오너에게 한 줄 알리면 된다.)

### 경고 4. 관문 조회 실패를 `debugPrint`만 하는 예외가 아직 CLAUDE.md에 없다

- 위치: `lib/features/profile/presentation/nickname_gate.dart:53`, `CLAUDE.md:172`("에러는 삼키지 않는다")
- 무엇이 틀렸나: 동작 자체는 오너 결정 1(a)대로다. 하지만 CLAUDE.md 예외 목록에 그 줄이 없어 **지금 트리는 규칙 위반 상태**다.
  plan은 "메인 세션 몫"이라고 적어 두었다.
- 실패 시나리오: 이 커밋만 들어가고 문서가 따라가지 않으면, 다음 리뷰·개발 세션이 이 `debugPrint`를 "삼킨 에러"로 보고
  토스트를 다는 쪽으로 "고친다" — 그러면 오프라인으로 켤 때마다 토스트가 뜨거나, 더 나쁘게는 관문을 막는 쪽으로 바뀐다.
- 고칠 방향: 관문 커밋과 **같은 커밋**에 CLAUDE.md 코딩 규칙 예외 한 줄(근거 `docs/specs/nickname/design.md` 결정 필요 1·7.1)과
  도메인 규칙 한 줄("표시 이름은 `set_nickname` 한 경로로만 바뀌는 별명이고, 사용자는 `profiles`를 직접 쓸 수 없다")을 넣는다.

### 경고 5. plan의 커밋 분할 권고가 "새 화면 하나 = 새 커밋 하나"를 어긴다

- 위치: `docs/specs/nickname/plan.md:229`(3·4를 한 커밋으로 묶자는 권고), `test/features/profile/nickname_gate_test.dart:259-334`
- 무엇이 틀렸나: 관문 화면과 바꾸기 화면을 한 커밋으로 묶자는 이유가 "테스트 파일 하나가 두 화면을 import한다"뿐이다.
  이건 파일을 나누면 풀리는 문제이고, plan 4-3도 원래 `nickname_edit_test.dart`를 따로 두려 했다.
- 고칠 방향: `프로필에서 별명 바꾸기` 묶음과 그 픽스처(`_pumpProfile`·가짜 레포지토리)를 `test/features/profile/nickname_edit_test.dart`로
  옮긴다(가짜 레포지토리 중복이 싫으면 `test/features/profile/profile_fakes.dart`로 뺀다). 그러면 3번 커밋만으로 analyze·test가
  통과하고 화면 단위 커밋이 지켜진다.

---

## 제안 (Suggestion)

### 제안 1. 풀 검증을 관례가 아니라 트리거로 강제한다 (가입이 깨지는 길)
- 위치: `supabase/migrations/20261124140000_nickname.sql:64-69, 85-90`(운영 규칙 주석), `:327`(`NICKNAME_POOL_EMPTY`)
- 지금은 "단어표·금칙어를 바꾸는 마이그레이션 끝줄에 assert를 둔다"는 **사람의 관례**가 `handle_new_user` 실패(=가입 불가)를
  막는 유일한 장치다. 금칙어 한 줄 `insert`를 넣으면서 끝줄을 빼먹으면, 그 단어가 일부 조합만 막을 때는 20번 재시도로 대개
  넘어가지만 형용사·명사 한쪽을 통째로 막는 단어(예: 모든 명사에 든 글자)가 들어가면 **모든 신규 가입이 실패**한다.
- 방향: `nickname_words`·`nickname_blocked_terms`에 `after insert or update or delete … for each statement` 트리거로
  `assert_nickname_pool_valid()`를 부른다. 그러면 관례를 잊어도 그 마이그레이션이 실패한다.

### 제안 2. B의 `update`에 `deleted_at is null`을 다시 건다
- 위치: `supabase/migrations/20261124140100_nickname_reset_existing.sql:45-47`
- B의 커서가 대상을 고른 뒤 같은 사용자가 그 사이에 `delete_account`를 커밋하면, READ COMMITTED의 재확인에서 `where id = r.id`는
  여전히 맞아 **묘비 이름을 무작위 별명으로 덮는다.** 사후 단언 "묘비 이름이 바뀌었습니다"가 잡아 B 전체가 되돌아가므로
  데이터는 안전하지만, 되돌릴 수 없는 단계를 다시 확인받아 돌려야 한다. 반대 순서(B가 먼저 행을 잠금)에서는 `delete_account`의
  `nickname_states` 삭제가 B의 미커밋 행을 못 봐 묘비에 `reset_at` 상태 행이 남는다(무해한 찌꺼기).
  사용자 43명이라 확률은 매우 낮다.
- 방향: `where id = r.id and deleted_at is null`. 0행이면 상태 행 insert도 건너뛴다(`if found then … end if`).

### 제안 3. 남은 혼동 모양 (spec이 받아들인 범위 — 기록만)
- `adrnin`(rn→m), `연습 BOT`·`연습 bot`(봇 이름의 영문 흉내)은 통과한다. spec 트레이드오프가 "목록은 뚫린다"를 받아들였으므로
  지금 고칠 필요는 없다. 사칭 신고가 들어오면 `bot`을 contains 예약어에 더하는 것부터 본다(`robot`이 함께 걸린다).

### 제안 4. `profiles`에 남는 REFERENCES·TRIGGER 권한
- 위치: `supabase/migrations/20261124140000_nickname.sql:684`
- anon·authenticated에 `references`, `trigger`가 남는다. PostgREST로는 DDL을 낼 수 없어 실제 우회는 아니지만, 의도가
  "읽기만"이면 `revoke all … from anon, authenticated; grant select … to authenticated;`가 더 정확하다.
  (anon의 select는 지금도 있지만 select 정책이 `to authenticated`라 0행이다 — 바꾸지 않아도 된다.)

### 제안 5. Dart 정규식의 보이지 않는 글자를 이스케이프로
- 위치: `lib/features/profile/domain/nickname_rules.dart:76` — `RegExp('[ \t\n\r  ]+')` 안에 NBSP(C2 A0)와 U+3000이
  리터럴로 들어 있다(바이트로 확인). 편집기에서 안 보여 지워지기 쉽다. `'[ \t\n\r 　]+'`로 쓴다.

### 제안 6. 계정 전환 때 래치가 넘어가지 않는다는 위젯 테스트
- 위치: `lib/features/auth/presentation/auth_gate.dart`의 `ValueKey(userId)`
- 구조(키로 새 State)는 맞지만 테스트가 없다. `authStateProvider`에 두 세션(id `a` 통과 → id `b` 미확정)을 흘려 두 번째에
  관문이 다시 서는지 한 건이면 된다.

### 제안 7. plan.md "적용 후 확인 필요" 갱신
- S1·S2·S3·S8은 이번 리뷰의 원격 SELECT로 확인됐다(위 "검증한 방법"). plan 표에 "확인됨(2026-11-24 리뷰)"과 값을 적어
  두면 적용 당일에 남은 추측이 S4~S7·S9·S10만으로 줄어든다(S4·S5·S6·S10은 읽어서 맞음).

---

## 확인했고 문제없는 것 (요청한 7항목)

1. **우회**: 테이블 쓰기 권한·UPDATE 정책·컬럼 ACL·뷰·다른 DEFINER 함수·`auth.users` 트리거 전부 확인 — 이름과 `deleted_at`을
   바꾸는 사용자 경로는 `set_nickname` 하나뿐이다. 정규화는 NFC → 공백류 통일 → 허용 목록이라 제로폭·결합 문자·NFD·전각·
   한글 채움 문자는 전부 CHARS로 떨어진다. 남는 것은 경고 3(자모 혼동)과 제안 3.
2. **가입**: `handle_new_user`가 던질 수 있는 길은 단어표가 비었을 때의 `NICKNAME_POOL_EMPTY` 하나이고, A 끝줄의 풀 검증이
   적용 시점에 막는다(제안 1은 그 관례를 강제로 바꾸자는 것). `nickname_states` PK 충돌·`profiles` 제약 위반 경로 없음
   (`display_name`에는 CHECK 제약이 없다). 검색 경로는 전부 `public.` 한정.
3. **B**: 묘비(`deleted_at is not null`)·봇(`id <> bot_user_id()`) 제외 확인, 두 번째 실행은 대상 0명, 사후 단언 다섯 개가
   정확하다(원격 사전 값으로 단언이 B와 무관하게 실패할 요인 없음 — odd_tombstones 0).
4. **`delete_account`**: 한 줄 차이 확인(위).
5. **권한**: 사용자 RPC 셋 모두 첫 줄 로그인 가드 + 탈퇴 거부 + `revoke public, anon` + `grant authenticated`. 내부 함수 다섯은
   `revoke public, anon, authenticated`(service_role은 Supabase 기본 ACL로 남는데 신뢰 롤이라 무방). 새 테이블 셋 RLS 켜고 정책 0개
   + `revoke all`.
6. **앱 관문**: 조회 실패·RPC 미존재·`ACCOUNT_DELETED` → 통과, 저장 실패 → 토스트 + 재시도, 로그아웃 출구 있음, 재조회 중
   이전 값 유지·오류 우선 판단으로 끌려 나가지 않음. 계정 전환은 `ValueKey(userId)` + `didUpdateWidget` 두 겹. 새 문구는 전부
   `strings.dart`.
7. **테스트**: Dart 쪽 래치·오류 우선 테스트는 래치를 빼면 실패하는 실질 테스트다. SQL 쪽은 경고 1·2.
