# recruit-browse 작업 순서 (developer)

기준 문서: `spec.md`(오너 결정 4건 포함), `design.md`(오너 결정 3건 포함). 이 계획은 design.md의
순서를 그대로 따르고, 설계가 다루지 않아 구현에서 메워야 했던 지점만 아래 "설계와 달라진 점"에 남긴다.

## CLAUDE.md / dev-standards 충돌 점검
충돌 없음. 확인한 항목:
- 판정·점수·한도·매칭 로직을 건드리지 않는다(이 기능은 목록 조회 함수 하나와 화면 배치만 바꾼다).
- 걸러내기(검색·필터·정렬·페이징)는 전부 서버. 클라이언트는 조건을 만들어 보내고 받은 묶음을 그대로 그린다.
- 새 RPC는 드롭·재생성 뒤 `revoke execute ... from public, anon` + `grant execute ... to authenticated`.
- SECURITY DEFINER 첫 줄 로그인 가드 유지(사용자 호출 함수라 cron 예외에 해당하지 않는다).
- 사용자 문구는 `lib/core/strings.dart`에 한국어로, 에러는 `debugPrint` + 스낵바.
- 새 색·새 컴포넌트 계열 없음. 필터는 `SegmentedButton`(테마에 `chipTheme`이 없어 `ChoiceChip`은 금지).

## 순서

1. **이 계획서(plan.md) 작성.**
2. **마이그레이션 1건** — `supabase/migrations/20261028120000_recruit_browse.sql`
   ① 옛 0-인자 `list_open_recruits()` 드롭 ② 6-인자 새 함수 생성(+`comment`)
   ③ `revoke`/`grant` 두 줄 ④ 부분 인덱스 `battles_open_recruit_feed_idx`. 그 밖은 손대지 않는다.
3. **SQL 스모크** — `supabase/tests/recruit_browse_smoke.sql`(design "필수 케이스" 전부).
   기존 `custom_duration_smoke.sql`·`join_battle_smoke.sql`에는 기본값 20건 가정 주석을 남긴다.
4. **Dart 도메인 순수 함수** — `lib/features/battle/domain/recruit_query.dart`
   (`RecruitTypeFilter`, `RecruitDurationBand`, `RecruitQuery`, `recruitEmptyKind`).
5. **Dart 데이터 계층** — `lib/features/battle/data/open_recruit_page.dart`
   (`RecruitCursor`, `OpenRecruitPage.fromRows`) + `BattleRepository.fetchOpenRecruits(...)` 교체
   + `fetchOpenRecruitBattle(id)` 추가(아래 D-1).
6. **provider** — `recruitFilterProvider`, `openRecruitFeedProvider`(`AsyncNotifier`),
   `openRecruitsProvider` 삭제. 호출처(생성·기준 수정·동의 철회·상세 시트) 갈아끼우기.
7. **문자열** — `lib/core/strings.dart` 추가/삭제(design "문자열" 표 그대로).
8. **화면**
   - `battle_recruits_screen.dart` 재작성(고정 조작 영역 + 무한 스크롤 목록 + 빈 상태 3종 + 모집 중 배너).
   - `my_battles_screen.dart`에 구역 A(내가 등록한 모집) / 구역 B(진행 중) 분리,
     `battle_summary_list.dart`는 스크롤 뷰 중첩을 피해 카드 목록을 돌려주는 형태로.
   - `create_battle_screen.dart` 성공 후 내 대결 탭 전환.
   - `main_shell.dart` 탭 진입 리스너 두 줄 추가.
9. **테스트**
   - 기존 4개 파일(`widget_test.dart`, `ai_consent_test.dart`, `battle_join_vs_intro_test.dart`,
     `recruit_sheet_test.dart`)의 `openRecruitsProvider`/`myRecruitsProvider` override 제거,
     가짜 repository가 `OpenRecruitPage`를 돌려주게 고친다.
   - 새 유닛: `recruit_query_test.dart`, `open_recruit_page_test.dart`, `open_recruit_feed_test.dart`.
   - 새 위젯: `recruit_browse_test.dart`(검색 디바운스·필터·꼬리 로딩·재시도·빈 상태 3종·조건 지우기),
     `my_battles_sections_test.dart`(두 구역).
10. **`flutter analyze` + `flutter test`** 통과 확인(기준선 304개 이상).

## 설계와 달라진 점 (구현 중 결정, 이유 포함)

- **D-1. 모집 상세 시트의 기준 다시 읽기 경로.** 설계는 `openRecruitsProvider` 삭제만 적고
  `recruit_detail_sheet.dart`의 `_refreshCriteria`(참가 직전에 기준이 바뀌었을 때
  `ref.refresh(openRecruitsProvider.future)`로 목록을 다시 읽어 그 모집을 찾던 코드)를 다루지 않았다.
  피드로 그대로 옮기면 **첫 묶음만 다시 읽으므로 두 번째 묶음 이후의 모집은 "사라졌다"로 오인해
  시트가 그냥 닫힌다.** 그래서 목록이 아니라 그 대결 한 행만 다시 읽는
  `BattleRepository.fetchOpenRecruitBattle(id)`(`battles` 직접 select + `maybeSingle`)를 추가했다.
  모집 중 대결은 RLS `anyone can view open recruiting battles`로 누구나 읽을 수 있고, 매칭·취소된 뒤에는
  그 정책이 더 이상 맞지 않아 null이 돌아온다 — 그 null이 곧 "사라졌다"는 신호다. 판정·승패와 무관한
  단순 조회라 RPC가 아니라 직접 CRUD로 둔다(dev-standards의 RPC/CRUD 구분).
  생성자 전적 카드(`creator`)는 기준 변경과 무관하므로 시트가 들고 있던 값을 그대로 쓴다.
- **D-2. `join_battle_smoke.sql`의 `recruits_count` 기대값.** 이 스모크는
  `list_open_recruits()` 전체를 모아 "스모크가 만든 모집 1건"을 기대한다. 원격에는 더미 모집 30건이
  이미 있어 이 기대는 **내 변경과 무관하게 이미 깨져 있고**, 기본 묶음이 20건이 되면서 뜻도 흐려진다.
  그래서 집계를 스모크가 만든 생성자 id로 한정하고 `p_limit`을 명시해 사전 존재 행에 영향받지 않게 했다.
  검사 의도("내 모집은 빠지고 생성자 전적이 함께 온다")는 그대로다.
- **D-3. `edit_recruit_criteria_screen.dart`의 피드 무효화 제거.** 내 모집은 애초에 남의 모집 목록
  (`creator_id <> auth.uid()`)에 들어가지 않으므로 기준을 수정해도 피드는 바뀌지 않는다. 같은 화면에
  두 목록이 있던 시절의 잔재라 지운다(설계의 "모집을 만들어도 피드는 무효화하지 않는다"와 같은 이유).
- **D-4. 피드 상태에 `moreFailed` 한 칸을 더했다.** 설계의 상태는 `moreErrorCount`(토스트 신호)만
  가지고 있었다. 그 값만으로는 "지금 실패한 상태인지"를 알 수 없어(한 번 실패하면 영원히 >0)
  ① 꼬리의 `다시 시도`를 성공 뒤에도 계속 띄우거나 ② 스크롤이 끝에 닿을 때마다 자동으로 다시
  불러 실패를 되풀이한다. `moreFailed`는 실패 직후 true, 재시도 시작·성공 시 false가 되어 두 문제를
  동시에 막는다. `moreErrorCount`는 설계대로 토스트를 한 번만 띄우는 신호로 남겼다.
- **D-5. `battleStatusPending`('모집 중') 문자열을 추가했다.** 설계는 내 대결 탭 구역 A에
  `PixelTag(모집 중, ...)`을 쓰라고 했지만 문자열 표에 그 값이 없었고, `battleStatusLabel`에도
  `pending` 분기가 없어 그대로 두면 사용자에게 영문 `pending`이 보인다. 공용 매핑에 분기를 더해
  다른 화면도 같은 라벨을 쓰게 했다(모양만 고르는 함수라 판정과 무관하다).
- **D-6. 당겨서 새로고침이 한도(`myLimitsProvider`)도 함께 읽는다.** 찾기 탭의 안내 배너와 FAB 분기가
  `hasPending`에 걸려 있는데, 그 값은 서버에서 바뀐다. 목록만 새로 받으면 배너가 낡은 채로 남는다.
  내 대결 탭의 새로고침도 모집·한도를 함께 무효화한다(구역 A가 그 둘로 그려진다).
  또 두 화면 모두 새로고침 실패를 잡아 `debugPrint`만 남긴다 — 다시 던지면 당겨서 새로고침 제스처가
  그대로 터지고, 실패는 이미 화면의 오류 안내가 말한다.
- **D-7. 새 테스트의 가짜 repository는 `noSuchMethod` 전달을 쓴다.** `BattleRepository`는 멤버가 많고
  이번 테스트가 쓰는 것은 두세 개뿐이다. 쓰지 않는 멤버를 60줄씩 세 번 베껴 쓰는 대신 선언하지 않고
  두어, 예상 밖 호출이면 `UnimplementedError`로 바로 드러나게 했다(mocking 패키지는 쓰지 않았다 —
  dev-standards 유지). 기존 테스트 파일의 전체 구현형 가짜는 그대로 뒀다.
- **D-8. 찾기 탭 위젯 테스트는 `ProviderContainer(retry: ...)`로 Riverpod의 자동 재시도를 끈다.**
  Riverpod 3은 실패한 provider를 스스로 지연 재호출하는데, 그 타이머가 테스트 종료 시점에 남아
  "Timer is still pending"으로 터진다. 제품 코드의 재시도 동작은 그대로 두고 테스트에서만 끈다.

## 실제 진행 순서
위 1~10 순서를 그대로 따랐다. 바꾼 지점은 하나다 — **7단계(문자열)를 4단계(도메인 순수 함수)보다
먼저 했다.** 필터 enum의 `label`이 `AppStrings` 상수를 참조하므로 문자열이 없으면 컴파일되지 않는다.

## 리뷰 반영 (2026-10-29)
reviewer 지적 7건(필수 2 + 권고 5)을 모두 고쳤다. 마이그레이션과 커서 SQL은 결함 없음으로 확인돼 손대지 않았다.

- **C-1 (필수) 조건 변경·새로고침 중에 걸린 `loadMore()`가 목록 중간을 빠뜨리던 결함.**
  `build()` 첫 줄에서 `_generation++`을 하므로 **build가 먼저 시작된 뒤에 걸린** loadMore는 새 세대 번호를
  잡아 가드를 통과했다. 그래서 옛 커서로 받은 묶음이 새 첫 묶음 뒤에 붙고 그 사이 20건이 조용히 사라졌다.
  고친 방법은 세 겹이다. ① `loadMore()` 첫 줄 `if (state.isLoading) return;`(첫 묶음을 다시 받는 중에는
  끼어들지 않는다) ② `RecruitFeed`에 **그 목록을 만든 조건(`query`)** 을 담고, 시작 시점과 응답을 쓰기
  직전에 `적용된 조건 == 상태의 조건`을 확인(`_isStale`) — 세대 번호보다 뜻이 분명하고, "조건이 바뀐 뒤
  rebuild가 오기 전에 loadMore가 걸리는" 순서까지 막는다 ③ 기존 세대 번호 비교는 같은 조건으로
  무효화된 경우를 위해 남겼다. **테스트(`open_recruit_feed_test.dart`)로 박았고, 가드를 임시로 지우면
  리뷰어가 본 그대로 20건이 아니라 40건이 되어 실패하는 것까지 확인했다.**
- **C-2 (필수) 이전 값이 남아 있을 때 피드 실패가 어디에도 안 보이던 경로.**
  riverpod은 실패해도 직전 값을 들고 있어 `feed == null && hasError` 분기에 들어가지 않았다. 고친 뒤:
  ① 본문 분기를 `feedAsync.hasError`로 바꿔 **옛 결과를 결과인 척 보여 주지 않는다**(새 검색어 + 옛 목록이
  같이 보이는 것이 실패를 숨기는 것보다 나쁘다) ② `ref.listen`에서 `hasError`가 켜지는 순간 토스트를
  한 번 띄운다(조건 변경·당겨서 새로고침 실패를 모두 덮는다) ③ 새로고침 catch는 `debugPrint`만 남긴다
  (다시 던지면 제스처가 터지고, 사용자 통지는 ①②가 맡는다). plan.md D-6의 "실패는 화면이 말한다"는
  절반이 틀렸던 것이고 이 문장으로 대체한다. 또 안내 한 칸을 그리는 동안에는 꼬리(이어 불러오기 상태)를
  띄우지 않는다.
- **W-1** `_shownMoreErrors` 필드를 없애고 `ref.listen`의 `previous`와 비교한다 — 새로고침으로 횟수가 0으로
  돌아간 뒤의 두 번째 실패도 알린다(위젯 테스트 추가).
- **W-2** 내 대결 탭 모집 구역도 `hasError`를 먼저 본다. 모집은 취소·매칭으로 사라지는 것이라 낡은 값을
  그대로 두면 없는 모집에 기준 수정을 시도하게 된다(위젯 테스트 추가).
- **W-3** "조건이 바뀌는 사이에 걸린 이어 불러오기가 새 목록을 오염시키지 않는다" 테스트 추가(C-1 참고).
  `autoDispose`라 조건 변경 뒤 상태를 보려면 `container.listen`을 먼저 걸어야 한다.
- **W-4** 스모크의 `default_limit`을 `count(*) <= 20`(항상 참) 대신 **`min(20, 볼 수 있는 모집 수)`와 정확히
  같다**로 바꾸고, `p_limit=20` 호출과 같은 행·같은 순서인지(`default_same_as_20`) 한 칸 더 뒀다.
- **W-5** 인자 검증 여섯 건의 `hint`를 `get stacked diagnostics ... pg_exception_hint`로 모아
  `BAD_PAGE_REQUEST` 여섯 개인지 확인한다(계약은 문구 + hint 두 짝이고 클라이언트가 읽는 값은 hint다).
- **W-6** 기존 두 스모크의 가정이 **건수가 아니라 `created_at` 순서**(같은 트랜잭션의 now()로 찍혀 늘 최신)에
  기댄다는 것을 주석으로 적었다.

리뷰어가 타당하다고 본 D-1(상세 시트 단건 재조회)은 그대로 뒀다.
테스트: `flutter analyze` 0 이슈, `flutter test` **351개** 통과(리뷰 전 346 → +5).
