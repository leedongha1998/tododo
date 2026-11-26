# nickname 구현 계획

## 이 문서의 범위

`docs/specs/nickname/spec.md`(수용 기준 + 오너 결정 8건)와 `design.md`(13절 + 오너 결정 3건)를 읽고 쓴
작업 순서다. design §12의 단계 중 **로컬에서 할 수 있는 것 전부**를 한다 — DB-A·DB-B 마이그레이션
파일과 스모크(실행은 하지 않는다), 앱 P0·P1, `DEPLOY.md` 5절.

developer는 **원격 DB를 건드리지 않는다**(로컬 Docker 없음. `db push`·쓰기 섞인 `db query --linked`·
`functions deploy`·`secrets set` 전부 하지 않는다). 그래서 SQL은 **실행해 보지 못한 채** 남는다 —
추측으로 쓴 자리는 맨 아래 "## 적용 후 확인 필요"에 모았다. 커밋도 하지 않는다(메인 세션이 원격 적용
뒤 화면 단위로 커밋한다 — 분할 제안은 "## 커밋 분할 제안").

---

## 설계·기획과의 충돌 — 없음

CLAUDE.md 도메인 규칙·코딩 규칙, dev-standards, spec.md, design.md를 대조했고 **구현을 멈춰야 할 충돌은
없다.**

- "에러는 삼키지 않는다"의 예외 한 건(관문 상태 조회 실패 → 통과 + `debugPrint`)은 design 결정 필요 1을
  오너가 (a)로 확정했다. CLAUDE.md 예외 목록에 한 줄을 더하는 것은 메인 세션 몫이다(이 작업은 CLAUDE.md를
  건드리지 않는다).
- design의 "내부 함수는 DEFINER가 아니고 invoker" — CLAUDE.md의 "SECURITY DEFINER 첫 줄 가드"는 DEFINER
  함수에만 걸리는 규칙이고, 내부 함수는 사용자 롤에서 실행 권한을 전부 회수하므로 충돌이 아니다(design §6.2).
- `delete_account`는 **`20261116120000_notification_dismiss.sql:213`이 여전히 가장 늦은 정의다**(그 뒤
  `20261120*`·`20261124*` 네 파일을 grep해 재정의가 없음을 확인했다). 그 정의를 복사하고 7번 단계 끝에 한 줄만
  끼운다.
- `handle_new_user`는 `20260915120100_ai_judge_schema.sql:171`이 가장 늦은 정의다(그 뒤로는 권한 회수만 있다).

---

## 작업 순서

### 1단계 — DB-A 마이그레이션 (SQL, 실행하지 않음)

**파일**: `supabase/migrations/20261124140000_nickname.sql` (신규)

순서(앞이 뒤의 전제):

1. `nickname_words`·`nickname_blocked_terms`·`nickname_states` 테이블(+ RLS 켜고 정책 0개 + `revoke all`).
2. seed: 형용사 40·명사 40(§3.1), 예약어 21(§2.4)·금칙어 42(§2.5). 표를 글자 그대로 옮긴다.
3. 내부 함수 5개(invoker, `revoke … from public, anon, authenticated`):
   `normalize_nickname` → `nickname_compare_key` → `check_nickname` → `random_nickname` → `assert_nickname_pool_valid`.
4. 사용자 RPC 3개(DEFINER, 첫 줄 가드, `revoke … from public, anon` + `grant … to authenticated`):
   `get_my_nickname_state`·`set_nickname`·`suggest_nickname`.
5. `handle_new_user` 재정의(이름은 `random_nickname()`, `raw_user_meta_data`·`email`을 읽지 않음, `nickname_states` 행 추가)
   + 권한 회수 재기술.
6. `delete_account` 재정의(최신 정의 복사 + `nickname_states` 삭제 한 줄).
7. `profiles` UPDATE 정책 제거 + `insert, update, delete, truncate` 권한 회수.
8. 끝줄 `select public.assert_nickname_pool_valid();`.

**스모크**
- `supabase/tests/nickname_rules.sql` (신규, SELECT만) — design §11.1의 1~3.
- `supabase/tests/nickname_flow_smoke.sql` (신규, 쓰기 + 전체 롤백) — design §11.2의 1~9 + §11.1의 4(양성 대조).
- `supabase/tests/join_battle_smoke.sql` 픽스처 수정 — design §11.3.

### 2단계 — DB-B 마이그레이션 (SQL, 실행하지 않음, 되돌릴 수 없음)

**파일**: `supabase/migrations/20261124140100_nickname_reset_existing.sql` (신규) — design §5 블록 + 사후 단언.

### 3단계 — 앱 P0 (관문 + 별명 정하기 화면)

| # | 파일 | 한 일 |
|---|---|---|
| 3-1 | `lib/features/profile/data/nickname_state.dart`(신규) | `NicknameState` + `fromMap` |
| 3-2 | `lib/features/profile/data/profile_repository.dart` | `fetchMyNicknameState`·`setNickname`·`suggestNickname` |
| 3-3 | `lib/features/profile/domain/nickname_rules.dart`(신규) | `nicknameGateView`(오류 우선), `nicknameRejectionOf`, `nicknameRejectionMessage`, `nicknameDisplayLength`(P1-2) |
| 3-4 | `lib/features/profile/domain/profile_providers.dart` | `myNicknameStateProvider`(autoDispose·family(userId)·재시도 끔) |
| 3-5 | `lib/core/strings.dart` | design §9 문구 |
| 3-6 | `lib/features/profile/presentation/nickname_form.dart`(신규) | 공용 입력 칸(칸 + 오류 줄 + 안내·글자 수) + 저장 처리 mixin |
| 3-7 | `lib/features/profile/presentation/nickname_setup_screen.dart`(신규) | 관문 화면(안내 묶음·추천받기·확정·로그아웃) |
| 3-8 | `lib/features/profile/presentation/nickname_gate.dart`(신규) + `auth_gate.dart` | 관문 분기 + 래치. `AuthGate`의 data 갈래가 `NicknameGate(userId, child: MainShell())`을 그린다 |
| 3-9 | 테스트 | 유닛(`nickname_rules_test.dart`, `nickname_state_test.dart`) + 위젯(`nickname_gate_test.dart`) |

### 4단계 — 앱 P0-6 (프로필에서 별명 바꾸기)

| # | 파일 | 한 일 |
|---|---|---|
| 4-1 | `lib/features/profile/presentation/nickname_edit_screen.dart`(신규) | 바꾸기 화면 |
| 4-2 | `lib/features/profile/presentation/profile_screen.dart` | 이름 줄을 `Row[이름 · 연필]`로. 로딩·실패 중에는 연필을 숨긴다 |
| 4-3 | 테스트 | `nickname_edit_test.dart`(위젯) |

### 5단계 — P1 (추천받기·규칙 안내)

3단계 화면에 같이 넣는다(같은 화면이고 DB RPC는 1단계에 이미 있다). 위젯 테스트 1건씩.

### 6단계 — 문서

`DEPLOY.md` 5절(design §10). CLAUDE.md·`TODO_BACKLOG.md`·`todododo-legal`은 건드리지 않는다(메인 세션·오너 몫).

---

## 구현 결과 (2026-11-24)

1~6단계를 전부 구현했다. **원격 적용·커밋은 하지 않았다.**

- `flutter analyze`: 이슈 0
- `flutter test`: **1028 통과**(기준선 997 + 유닛 15 + 위젯 16). TypeScript는 건드리지 않아 `deno test`는 돌리지 않았다.
- 새 패키지 없음(네이티브 포함). 그래서 릴리스 빌드 검증 의무는 없다(배포 전 빌드에서 함께 본다).
- 전체 테스트 출력의 `You must initialize the supabase instance` 29건은 **이 작업 전(HEAD)에도 같은 29건**이다
  (`widget_test.dart`·`notification_tap_test.dart`, stash로 비교했다). 새 테스트 두 파일은 그 소음을 내지 않는다.

### 구현 중 순서·계획을 바꾼 곳

| 계획 | 바꾼 것 | 이유 |
|---|---|---|
| 3-9 `nickname_state_test.dart` 따로 | `nickname_rules_test.dart` 한 파일에 `NicknameState.fromMap` 묶음을 넣었다 | 두 줄짜리 파싱 테스트 하나에 파일을 따로 둘 이유가 없다 |
| 4-3 `nickname_edit_test.dart` 따로 | `nickname_gate_test.dart`의 `프로필에서 별명 바꾸기` 묶음 | 가짜 레포지토리를 두 파일이 똑같이 갖게 된다 |
| 3단계·5단계 순서 | P1(추천받기·안내·글자 수)을 3단계 화면을 만들 때 같이 넣었다 | 같은 화면·같은 위젯이고 RPC는 1단계에 이미 있다. 계획 5단계에 적은 대로다 |

### 설계와 다르게 한 것 (작은 것만, 전부 되돌리기 쉽다)

1. **양성 대조(design §11.1-4)를 `nickname_rules.sql`이 아니라 `nickname_flow_smoke.sql`에 넣었다.** 규칙 파일은
   선례(`bot_battle_rules.sql`)처럼 **SELECT만** 하는 표 테스트인데, 양성 대조는 금칙어 행을 넣어야 한다(쓰기).
   쓰기가 있는 파일은 전체 롤백으로 끝나는 흐름 스모크다.
2. **`drop policy`를 `drop policy if exists`로 쓰고, 바로 뒤에 "profiles에 select 아닌 정책이 남았으면 실패" 블록을
   더했다.** 정책 이름이 원격에서 다르면 `if exists`가 조용히 아무것도 안 지우는데, 그때 문이 열린 채 남지 않게
   마이그레이션을 멈춘다.
3. **2단계(B)의 사후 단언에 하나를 더했다** — 덮인 사용자의 이름이 전부 `check_nickname`을 통과하는지.
   `random_nickname`이 보장하지만 되돌릴 수 없는 단계라 한 번 더 본다.
4. **`nickname_rules.sql`에 스키마·권한 표(600~613)를 더했다** — RLS·정책 0개, profiles 쓰기 권한 없음, 내부 함수
   회수, RPC 허용, DEFINER/invoker 구분, `handle_new_user`가 메타데이터를 읽지 않는지, `delete_account`가
   상태 행을 지우는지. 흐름 스모크의 6번(실제 호출로 거부 확인)과 겹치지만 1단계만으로 싸게 돈다.
5. **관문 확정 성공 뒤 저장 중 표시를 내린다**(design 표는 "성공 → 관문이 바뀐다"까지만 적었다). 다시 읽은 상태가
   어떤 이유로든 미확정이면 같은 화면이 남아 버튼이 로더에 갇히기 때문이다. 다시 눌러도 같은 이름의 재확정이라
   무해하다.
6. **`AuthGate`가 `NicknameGate`에 `ValueKey(userId)`를 주고, `NicknameGate`도 `didUpdateWidget`에서 userId가
   바뀌면 래치를 푼다.** 래치가 계정을 넘어 살아남지 않게 하는 두 겹이다(design 7.1 "userId로 나눈다"의 화면 쪽).
7. 입력 칸은 `InputDecoration`의 `error`/`helper`/`counter` 위젯 자리를 썼다 — 오류 줄이 서면 안내 줄이 자리를
   비켜 준다(design 7.2 와이어의 "규칙 위반이면 errorText" + 7.4 안내 줄을 한 칸에서).
8. 프로필 바꾸기 화면의 저장 버튼 문구는 공용 `AppStrings.save`(`저장`)다(design 와이어 그대로, 새 상수 없음).

---

## 적용 후 확인 필요 (실행해 보지 못한 SQL — 추측으로 쓴 곳)

원격에 적용하기 전에는 아래가 맞는지 **확인할 수 없었다.** 대부분 스모크가 바로 잡는다.

| # | 추측 | 어디서 드러나나 |
|---|---|---|
| S1 | `normalize(text, NFC)`가 원격 Postgres에 있고 `server_encoding`이 UTF8이다 | 1단계 적용 자체(끝줄 `assert_nickname_pool_valid()`가 `check_nickname`→`normalize_nickname`을 실제로 돌린다). 미리 보려면 읽기 전용 `show server_encoding; select normalize('연습봇', NFD) <> '연습봇';` |
| S2 | 정규식 범위 `[가-힣ㄱ-ㅣ]`가 코드 포인트 기준으로 동작한다(정렬 규칙을 타지 않는다) | `nickname_rules.sql` 200~213(경계 문자) |
| S3 | `match`를 컬럼 이름으로 쓸 수 있다(비예약 키워드) | 1단계 적용 자체(`create table`) |
| S4 | `check_nickname`의 OUT 인자 `term`과 테이블 컬럼 `term`이 plpgsql에서 부딪히지 않는다(컬럼은 전부 `b.term`으로 한정했다) | 1단계 끝줄 검증이 함수를 실제로 돌리므로 **적용 시점에** 드러난다 |
| S5 | 테이블 권한이 없을 때 `update profiles`가 RLS 0행이 아니라 **권한 오류(42501)** 로 끝난다 | `nickname_flow_smoke.sql`의 `write_results` |
| S6 | `request.jwt.claims = '{}'`이면 `auth.uid()`가 null이다 | 흐름 스모크 `perm_nologin` |
| S7 | `raise … using detail = …`이 PostgREST 응답의 `details`로 실려 앱의 `PostgrestException.details`가 된다 | 실기기: 관문에 `공식왕`을 넣고 확정 → `…: 공식`이 보이는지. 안 보이면 일반 문구로 떨어진다(기능은 성립) |
| S8 | 원격 탈퇴 묘비의 이름이 전부 `탈퇴한 사용자`다 | **2단계 적용 전** 사전 확인 쿼리의 `odd_tombstones`(파일 머리 주석). 0이 아니면 B의 사후 단언이 B와 무관하게 실패한다 |
| S9 | 새 RPC 셋이 적용 직후 PostgREST 스키마 캐시에 잡힌다(Supabase는 DDL 뒤 자동으로 다시 읽는다) | 앱이 `get_my_nickname_state`를 못 찾으면 관문이 통과(fail-open)하므로 앱은 갇히지 않는다. 그래도 남으면 `notify pgrst, 'reload schema';` |
| S10 | `random_nickname()`의 "쓰이지 않은 조합 먼저"가 2단계 루프 안에서 앞 사람에게 준 이름을 본다(문장마다 새 스냅숏) | 2단계 뒤 읽기 전용 `select display_name, count(*) from profiles group by 1 having count(*) > 1;`(이름 값이 나오므로 오너 화면에서만) — 40명 남짓이면 0행이 기대값 |

**기존 스모크 회귀**: `display_name`/`handle_new_user` 결과에 기대는 스모크를 전부 grep했다. 이름 값을 단언하는 곳은
`join_battle_smoke.sql`(스모크A·스모크D) 하나뿐이었고 픽스처에서 postgres 권한으로 이름을 박아 두게 고쳤다.
나머지는 묘비 이름(`delete_account_smoke`·`push_token_smoke`), 봇 이름(`bot_battle_rules`), 제목 검색
(`recruit_browse_smoke`의 `'스모크'` — 제목·기준만 검색하므로 기대값 0은 그대로)이다. `auth.users`에 넣는 스모크
전부(design §11.3 목록)는 새 `handle_new_user`가 픽스처 가입에서 실패하지 않는지 보려고 다시 돌린다.

---

## 적용 순서 (메인 세션·오너)

1. **1단계(A)만 먼저 적용한다.** `supabase db push`는 대기 중인 마이그레이션을 **전부** 적용하므로, 두 파일이
   폴더에 함께 있으면 A와 B가 한 번에 돈다. A를 검증하기 전에 B가 돌지 않게 **B 파일
   (`20261124140100_nickname_reset_existing.sql`)을 잠시 폴더 밖에 두고** `supabase db push --dry-run`으로 목록을
   확인한다(그 앞의 `20261124120000`·`20261124130000`이 아직 원격에 없다면 그것도 함께 나온다).
2. A 적용 → `nickname_rules.sql`(전부 `ok = t`) → `nickname_flow_smoke.sql`(`SMOKE RESULT ok=t`) → 회귀 스모크
   (`join_battle_smoke.sql` 먼저, 그다음 design §11.3 목록, 특히 `delete_account_smoke.sql`).
3. **2단계(B) 사전 확인**(읽기 전용, B 파일 머리 주석의 쿼리) → 오너 1차 확인 → 적용 직전 "되돌릴 수 없다" 2차 확인
   → B 파일을 폴더에 되돌리고 `db push`. 사후 확인: `select count(*) from public.profiles where display_name like '%@%';` → 0.
4. **앱은 B 뒤에 낸다**(design §12 — 앱이 먼저 나가면 기존 사용자에게 안내 줄 없이 실명이 채워진 관문이 뜬다).
5. 문서: `CLAUDE.md`(도메인 규칙 한 줄 + 관문 조회 실패 예외 한 줄), `TODO_BACKLOG.md`(design §12 5단계 목록)는
   메인 세션, `todododo-legal` 두 문서는 오너.

---

## 커밋 분할 제안 (화면 하나 = 커밋 하나)

1. DB-A — `supabase/migrations/20261124140000_nickname.sql`, `supabase/tests/nickname_rules.sql`,
   `supabase/tests/nickname_flow_smoke.sql`, `supabase/tests/join_battle_smoke.sql`
   ```
   feat: 별명 규칙·무작위 별명·쓰기 경로를 서버 한 자리로 모은다

   별명 상태·단어표·예약어/금칙어 테이블(RLS 켜고 정책 0개)과 단어 80·예약어 21·
   금칙어 42행, 규칙 함수(check_nickname)와 무작위 별명, RPC 셋(get_my_nickname_state·
   set_nickname·suggest_nickname)을 만든다. 가입 트리거가 Google 이름·이메일 대신
   무작위 별명을 넣고, profiles의 UPDATE 정책과 쓰기 권한을 거둬 이름은 set_nickname
   한 경로로만 바뀐다. delete_account는 별명 상태 행도 지운다.

   docs/specs/nickname/design.md §1~§4·§6·§12 1단계
   ```
2. DB-B — `supabase/migrations/20261124140100_nickname_reset_existing.sql`
   ```
   feat: 기존 사용자의 이름을 무작위 별명으로 덮는다

   탈퇴 묘비·봇을 뺀 기존 사용자 전원의 이름을 무작위 별명으로 바꾸고 관문에
   안내 줄이 뜨게 표시한다. 원래 이름은 보관하지 않는다(되돌릴 수 없음, 오너 결정 2).

   docs/specs/nickname/design.md §5·§12 2단계
   ```
3. 관문 화면 — `nickname_state.dart`, `profile_repository.dart`, `nickname_rules.dart`, `profile_providers.dart`,
   `strings.dart`, `nickname_form.dart`, `nickname_setup_screen.dart`, `nickname_gate.dart`, `auth_gate.dart`,
   `test/features/profile/domain/nickname_rules_test.dart`, `test/features/profile/nickname_gate_test.dart`
   ```
   feat: 첫 로그인 별명 정하기 관문을 넣는다

   로그인 직후 본 화면 전에 서버가 채운 무작위 별명으로 별명 정하기 화면을 한 번
   띄운다. 규칙 위반은 서버 코드를 칸 아래 문구로 바꾸고, 저장 실패는 토스트로,
   로그아웃은 관문의 유일한 출구로 둔다. 다른 별명 추천받기와 규칙 안내·글자 수도
   같은 화면에 있다. 상태 조회가 실패하면 본 화면으로 통과시킨다(관문은 보안 장치가
   아니다 - 노출은 서버가 이미 끊었다).

   docs/specs/nickname/design.md §7.1·§7.2·§7.4·§9
   ```
   (`strings.dart`의 별명 바꾸기 문구 넷과 `nickname_gate_test.dart`의 프로필 묶음이 이 커밋에 함께 들어간다 —
   한 파일을 커밋 둘로 쪼개려면 부분 스테이징이 필요하다. 쪼개고 싶으면 4번에 `profile_screen.dart`·
   `nickname_edit_screen.dart`만 두면 된다. 그 경우 3번만으로도 analyze·test가 통과한다.)
4. 별명 바꾸기 화면 — `nickname_edit_screen.dart`, `profile_screen.dart`
   ```
   feat: 프로필에서 별명을 바꾸는 화면을 넣는다

   프로필 머리의 이름 옆 연필로 바꾸기 화면을 연다. 관문과 같은 RPC·같은 규칙이고
   횟수 제한이 없다. 저장하면 토스트와 함께 프로필을 다시 읽는다.

   docs/specs/nickname/design.md §7.3
   ```
   ※ 3번 커밋의 `nickname_gate_test.dart`가 `ProfileScreen`·`NicknameEditScreen`을 import하므로, 3·4를 나눠
   커밋하면 **3번 시점에는 그 테스트 파일이 컴파일되지 않는다.** 나눈다면 테스트 파일의 `프로필에서 별명 바꾸기`
   묶음을 4번으로 옮겨야 한다. 간단히 가려면 3·4를 한 커밋으로 묶는 쪽을 권한다(화면 둘이지만 같은 폼 위젯을
   쓰는 한 기능이다).
5. 문서 — `DEPLOY.md`, `docs/specs/nickname/{spec,design,plan}.md`
   ```
   docs: 별명 기능의 기획·설계·계획과 배포 체크리스트 수집 항목을 적는다
   ```

## 2026-11-24 — 리뷰 지적 수정 (메인 세션)

`review.md`의 차단 0건, 경고 5건을 전부 고쳤고 제안 2·4·5를 반영했다.

| 지적 | 고친 것 |
|---|---|
| 경고 1 | `nickname_rules.sql`의 권한 행 6개가 `concat_ws`에 불리언을 그대로 넣어 `t/f`가 되어 **구현이 맞아도 실패**했다. 각 불리언에 `::text` |
| 경고 2 | 풀 검증 두 행이 **항상 통과**했다(stable 함수의 참조 안 되는 호출을 플래너가 버린다). `assert_nickname_pool_valid`를 `volatile`로, 규칙 파일은 결과를 참조하게(`::text as r … where x.r is not null`), 흐름 스모크는 `perform` 블록으로 |
| 경고 3 | 호환 자모로 영문 예약어 흉내(`ADMㅣN`, `TㅇDㅇDUDU`). 비교 키가 `ㅣ→i`, `ㅇ→o`도 접는다. 규칙 행 124~127(흉내 2건 거부, 자모 이름 2건 통과) |
| 경고 4 | CLAUDE.md에 도메인 규칙 한 줄과 "관문 상태 조회 실패는 `debugPrint`" 예외 한 줄 |
| 경고 5 | 바꾸기 화면 테스트를 `nickname_edit_test.dart`로, 공유 가짜를 `nickname_fakes.dart`로 나눠 화면마다 커밋할 수 있게 |
| 제안 2 | B의 update에 `and deleted_at is null` + `if not found then continue` (루프 중 탈퇴한 사람의 묘비를 덮지 않는다) |
| 제안 4 | `profiles`는 `revoke all` 뒤 `grant select … to authenticated`만 |
| 제안 5 | Dart 정규식 안의 보이지 않는 NBSP·U+3000 리터럴을 ` 　`으로 |

탈퇴 확인 문구의 "표시 이름"을 "별명"으로 바꿨다.

"적용 후 확인 필요" 중 **S1·S2·S3·S8은 리뷰어가 원격 읽기 전용 조회로 확인했다**(UTF8·PG 17.6·NFC 동작, 정규식 범위가 코드 포인트 기준, `match` 컬럼명 사용 가능, 이상한 묘비 0). S4·S5·S6·S10은 읽어서 맞다. 남은 것은 S7(예약어 표시가 앱까지 오는지 — 실기기)과 S9(스키마 캐시)다.

## 2026-11-25 — 1단계(A) 원격 적용 (메인 세션)

오너 승인으로 `20261124140000_nickname.sql`을 원격에 적용했다. **2단계(B)는 아직 적용하지 않았다.**

절차: B 파일을 `supabase/migrations/` 밖으로 옮겨 `db push --dry-run`으로 대기 목록이 A 하나뿐임을
확인 → `begin;` + A + 테스트를 한 트랜잭션으로 보내 **롤백되는 드라이런** 2회(A+규칙 표, A+흐름 스모크)
→ 원격에 잔재가 없는지 확인(`to_regclass` 셋 다 null) → `db push` → B 파일 복구.

**드라이런이 잡은 것 2건** (둘 다 `nickname_rules.sql`의 테스트 버그. 마이그레이션은 무결했다):

| 행 | 문제 | 고친 것 |
|---|---|---|
| 605·607·608·609·610 | 경고 1 수정이 **덜 됐다**. `concat_ws(...)` 결과에 `::text`를 붙여 마지막 인자만 여전히 `t/f`로 나왔다(`false/false/f`) | `::text`를 각 인자 안쪽으로 옮겼다. 불리언을 잇는 자리는 **인자마다** 캐스팅해야 한다 |
| 315 | 입력 `Todododo123`이 **11자**라 `NICKNAME_LENGTH`가 먼저 걸려 예약어 `todododo`를 전혀 보지 못했다 | 입력을 `Todododo1`(9자)로 |

적용 후 결과:

- `nickname_rules.sql` 114케이스 전부 통과(999행 `ok=t`)
- `nickname_flow_smoke.sql` `SMOKE RESULT ok=t`
- 기존 스모크 21개 회귀 없음 — 흐름 스모크 19개 전부 `ok=t`,
  `bot_battle_rules` 35/35, `mutual_judge_rules` 39/39
- **S9 해결**: 익명 키로 `POST /rest/v1/rpc/suggest_nickname` → `42501 permission denied for function
  suggest_nickname`(404가 아니다). PostgREST가 새 RPC 셋을 이미 캐시에 잡았고 anon은 막혀 있다.
  `notify pgrst` 불필요
- 기존 사용자 이름은 그대로다(A는 건드리지 않는다)

**2단계(B) 사전 확인**(읽기 전용, 이름 값은 출력하지 않았다): `targets=43`, `tombstones=0`,
`emails=1`, `odd_tombstones=0`, 상태 행 없는 대상 `43`. 예상값과 맞고 사후 단언을 깨뜨릴 요소가 없다.
B를 적용하면 **기존 43명 전원의 이름이 무작위 별명으로 덮인다(되돌릴 수 없다)**.

## 2026-11-26 — 2단계(B) 원격 적용 (메인 세션)

오너 확인 2회(사전 확인 결과 → 적용 직전 "되돌릴 수 없다")를 받고
`20261124140100_nickname_reset_existing.sql`을 적용했다. **되돌릴 수 없다 — 기존 43명의 원래 이름
(실명·이메일 포함)은 어디에도 남지 않는다.**

적용 전 **B 전문을 그대로 돌리고 되돌리는 드라이런**으로 결과를 미리 봤다(`begin;` + B + 집계 후
`raise exception`). 드라이런 값과 실제 적용 후 값이 **전부 같았다**:

| 확인 | 값 |
|---|---|
| 덮은 사람 / 상태 행 | 43 / 43 |
| 이름에 `@`가 남은 프로필 | 0 (적용 전 1) |
| 덮은 이름 43개의 서로 다른 값 | 43 (겹침 없음 — 루프가 한 사람씩 돌아 `random_nickname`의 "안 쓰인 조합 먼저"가 이번 일괄 덮기 안에서도 작동했다) |
| 규칙에 걸리는 이름 | 0 |
| 상태 행 없는 사용자 | 0 |
| 봇 이름 / 묘비 | `연습 봇` / 0건 |
| `confirmed_at`이 있는 사람 | 0 — 43명 전원이 다음 실행에서 별명 관문을 한 번 본다 |

**회귀**: `supabase/tests/*.sql` 23개 전부 통과(흐름 스모크 20개 `ok=t`, `nickname_rules` 114/114,
`bot_battle_rules` 35/35, `mutual_judge_rules` 39/39).

남은 것: 앱 커밋·빌드와 S7(예약어·금칙어 안내가 실기기에서 보이는지), `todododo-legal`의 `privacy.html`
갱신(오너 몫, DEPLOY.md 5절).
