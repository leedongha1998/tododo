# notification-inbox 구현 계획

> 입력: `docs/specs/notification-inbox/spec.md`(오너 확정 6항목), `docs/specs/notification-inbox/design.md`(구현의 기준),
> `CLAUDE.md`, `dev-standards` 스킬.
>
> 이 문서는 **작업 순서와 검증 방법**만 적는다. 무엇을 만드는지의 근거는 전부 design.md에 있고 여기서 다시 고르지 않는다.

## 0. 충돌 검토 결과 — 없음

`CLAUDE.md`·dev-standards와 spec/design이 어긋나는 곳은 없다. **어긋나 보이지만 design이 이미 정리해 둔 세 곳**만 적어 둔다
(구현을 멈출 이유가 아니라, 구현과 함께 문서를 고치는 작업이 5단계에 들어 있다는 뜻이다).

| 어긋나 보이는 것 | 실제 | 처리 |
|---|---|---|
| CLAUDE.md "에러는 삼키지 않는다" ↔ 읽음 찍기·배지 조회 실패를 `debugPrint`만 남김 | design 흐름 3이 **새 예외**로 명시하고 "CLAUDE.md 예외 목록에 한 줄 적는다"고 함께 지시했다(홈 위젯 캐시·기한 알림과 같은 성격) | 5단계에서 CLAUDE.md에 추가 |
| CLAUDE.md "사용자에게 보이는 문자열은 `strings.dart`" ↔ 푸시 문구는 서버 `notification_text.ts` | 이미 있는 예외다(푸시는 앱이 종료돼 있어도 시스템이 그린다). 알림함 줄은 예외가 아니라 **원칙 쪽**이다 | 5단계에서 세 자리(CLAUDE.md·strings.dart·notification_text.ts)에 출처 규칙 한 줄 |
| CLAUDE.md "현재 단계" 배포 전 feature 목록에 `notification-inbox`가 없다 | 2026-11-13 오너 확정으로 배포 전 범위에 들어왔다(spec 결정 1) | 5단계에서 CLAUDE.md 범위·디렉토리 구조에 추가 |

**이 작업에서 하지 않는 것**: 원격 DB 적용(`supabase db push`/`migration up`/대시보드), 커밋. 둘 다 오너·메인 세션 몫이다.
옛 마이그레이션 파일은 한 글자도 고치지 않는다(원격 적용본과 어긋난다) — 바꿀 것은 전부 새 마이그레이션에 쓴다.

## 1. 순서 (design 8.3을 그대로, 커밋 경계를 덧붙여)

`design.md` 8.3의 5단계를 그대로 따른다. "새 화면 하나 = 새 커밋 하나"(CLAUDE.md)를 지키려고 3·4를 가르는 것도 그대로다.
각 단계는 **그 단계만으로 `flutter analyze`·`flutter test`가 통과**해야 다음으로 넘어간다.

### 1단계 — 스키마와 RPC (커밋 경계 ①, 원격 적용은 오너)

| 파일 | 작업 |
|---|---|
| `supabase/migrations/20261113120000_notification_inbox.sql` (신규) | ① `notification_outbox_recipient_idx` 인덱스 ② `comment on table public.notification_outbox` 갱신(design 9) ③ `notification_reads` 테이블 + 주석 + RLS 켜고 **정책 없음** ④ RPC 3개(`list_notifications`/`has_new_notifications`/`mark_notifications_seen`) + `revoke ... from public, anon` / `grant ... to authenticated` ⑤ `delete_account` 재정의(`20261106120000_remove_battle_limits.sql`의 정의를 **그대로 복사**하고 7단계에 `delete from public.notification_reads where user_id = v_user_id;` 한 줄만 끼운다) |
| `supabase/tests/notification_inbox_smoke.sql` (신규) | design 10.1의 체크 목록 전부. 기존 틀대로 마지막에 일부러 예외를 던져 롤백 |

- 적재 함수 6곳(`join_battle`·`finalize_battle`·`void_battle`·`accept_submission`·`open_judging_window`)은 **건드리지 않는다**.
  `delete_account`만 재정의하는 이유는 묘비 때문에 cascade가 돌지 않아서다(design 1.2).
- `kind` 체크 제약·`notification_outbox` 컬럼·정책은 변경 없음.
- **검증**: 원격 적용 전이라 SQL을 돌릴 수 없다. 사람 눈 검증 항목을 아래 3장에 남긴다.

### 2단계 — 모델·레포지토리·provider·문구 매핑 (커밋 경계 ②, 앱 동작 변화 없음)

| 파일 | 작업 |
|---|---|
| `lib/core/strings.dart` | design 4장 "strings.dart에 더하는 문구" 16개 + `notificationTime(...)`. 알림 절 주석을 출처 규칙으로 고치는 것은 5단계에서 함께 |
| `lib/core/theme/app_icons.dart` | `bell`·`bellOutlined`·`judge` 세 개(design 8.2) |
| `test/core/theme/app_icons_test.dart` | 상수 목록에 세 개 추가 + 개수 37 → 40 |
| `lib/features/notification/data/notification_item.dart` (신규) | `NotificationItem`(id, kind, battleId, payload, createdAt) + `fromMap` + `isNewSince(DateTime? seenAt)` |
| `lib/features/notification/data/notification_inbox.dart` (신규) | `NotificationInbox{seenAt, items}` + `fromMap` |
| `lib/features/notification/data/notification_repository.dart` (신규) | RPC 3개 호출(`list` / `hasNew` / `markSeen`) |
| `lib/features/notification/domain/notification_line.dart` (신규) | `NotificationLine{text, title, icon}` + 순수 함수 `notificationLine(kind, payload)`. design 4장 매핑 표가 정답 |
| `lib/features/notification/domain/notification_providers.dart` (신규) | `notificationRepositoryProvider`, `notificationInboxProvider`, `hasNewNotificationsProvider`(둘 다 `FutureProvider.autoDispose`) |
| `test/features/notification/domain/notification_line_test.dart` (신규) | design 10.2 전부 |
| `test/features/notification/data/notification_item_test.dart` (신규) | `fromMap` + `isNewSince` 경계(`seen_at`과 **같은** 시각은 새 알림이 아니다 — 서버의 `>` 비교와 같게) |

- `isNewSince`를 presentation이 아니라 모델에 두는 이유: dev-standards "상태 전이 조건을 위젯에 직접 쓰지 않는다".
- 시각 서식(`AppStrings.notificationTime`)의 경계(자정 12시·정오 12시·분 한 자리)는 문구 테스트가 덮는다.

### 3단계 — 알림함 화면 (커밋 경계 ③)

| 파일 | 작업 |
|---|---|
| `lib/features/notification/presentation/notification_inbox_screen.dart` (신규) | design 5.2·5.3. 로딩/빈/실패/목록 네 갈래, 카드 한 줄, 탭 → `fetchBattle` 선확인 → 상세 push / 실패 시 토스트, 첫 성공 로드에서 `seen_at` 붙잡고 `mark_notifications_seen` 1회 |

- 당겨서 새로고침·삭제·메뉴를 두지 않는다(design 5.2, 11장).

### 4단계 — 공용 종 버튼과 배지 갱신 계기 (커밋 경계 ④)

| 파일 | 작업 |
|---|---|
| `lib/features/notification/presentation/notification_bell.dart` (신규) | design 5.1. `Badge(smallSize: 8, isLabelVisible: hasNew)` + `IconButton`, 실패·로딩이면 점 없음 |
| `my_battles_screen.dart` / `battle_recruits_screen.dart` / `todo_list_screen.dart` / `profile_screen.dart` | 각각 `AppBar(..., actions: const [NotificationBell()])` 한 줄 |
| `lib/core/navigation/main_shell.dart` | ① 탭 전환 리스너에 `ref.invalidate(hasNewNotificationsProvider)`(탭을 가리지 않는다) ② `AppLifecycleListener(onResume:)`로 앱 재개 때 invalidate |
| `lib/core/push/push_service.dart` | `_handleForegroundMessage`에 `hasNewNotificationsProvider`·`notificationInboxProvider` invalidate |
| `test/features/notification/notification_inbox_test.dart` (신규) | design 10.3의 배지 세 갈래 + 알림함 빈/실패/목록/읽음 한 번/탭 실패 (파일 하나로 합쳤다 — 둘이 같은 가짜를 쓴다) |
| `test/features/notification/notification_fakes.dart` (신규) | 가짜 레포지토리 + 공용 override 목록(기존 위젯 테스트 10개가 함께 쓴다) |
| `test/widget_test.dart` | 네 탭을 오가며 종 아이콘이 모두 보이는지(design 10.3 마지막 항목) |

- 10.3은 MVP에서 강제되지 않지만(CLAUDE.md) **배선이 네 화면에 퍼지므로** 값싼 범위에서 쓴다.

### 5단계 — 문서 정합 (커밋 경계 ⑤, design 9장)

| 파일 | 작업 |
|---|---|
| `docs/specs/push-notification/spec.md:118` | 기존 문장을 **지우지 않고** 뒤집힌 근거 한 줄 추기 |
| `docs/specs/push-notification/design.md:166` | 같은 방식으로 한 줄 추기 |
| `CLAUDE.md` | ① 코딩 규칙에 문구 출처 규칙 ② "에러는 삼키지 않는다" 예외에 읽음·배지 실패 ③ "현재 단계" 배포 전 feature 목록 + 디렉토리 구조에 `notification/` |
| `lib/core/strings.dart` 알림 절 주석 | "푸시 본문은 서버, 앱 안 알림함 줄은 여기"로 고침 |
| `supabase/functions/_shared/notification_text.ts` 머리 주석 | 같은 뜻 한 줄 |

- 개인정보처리방침·`DEPLOY.md`의 보유 기간 서술은 **오너 몫**이다(저장소 밖, push 7단계에 배정됨). 보고에 적는다.

## 2. 순서를 바꿀 때의 기록

이 순서를 구현 중 바꾸게 되면 **왜 바꿨는지를 이 절에 적는다**(CLAUDE.md 작업 방식).

- (2026-11-13) `strings.dart`·`app_icons.dart` 추가를 2단계 맨 앞으로 옮겼다. design 8.3은 그것들을 단계별로 나누지 않았는데,
  문구와 아이콘이 없으면 2단계의 `notification_line.dart`가 컴파일되지 않는다. 같은 단계 안의 순서 조정이라 단계 경계는 그대로다.
- (2026-11-13) `notification_item.dart`에 `isNewSince`를 두기로 했다. design 5.2는 판정식(`created_at.isAfter(_seenAtAtOpen)`)만
  적고 어디 둘지는 적지 않았다 — dev-standards("상태 조건을 위젯에 직접 쓰지 않는다")와 "배지 판정은 유닛 테스트 필수"를
  함께 만족하는 자리가 모델이다.
- (2026-11-13) `list_notifications`의 질의를 design 3.1의 snippet과 **두 곳 다르게** 썼다. (a) 하위 질의의
  컬럼 별칭 `as row`를 쓰지 않는다 — `ROW`는 Postgres 예약어라 그대로 쓰면 함수 생성이 실패한다.
  (b) `jsonb_agg(... order by created_at desc, id desc)`로 **집계 안에서 정렬을 한 번 더** 적는다 —
  하위 질의의 `order by`는 `limit`과 짝이 되어 "어느 50건인가"를 정하지만, 그 순서가 집계로 그대로
  넘어온다는 보장은 없다. 앱이 받은 순서를 그대로 쓰므로(다시 정렬하지 않는다) 순서가 계약이다.
  돌려주는 키·상한·필터는 design 그대로다.
- (2026-11-13) 알림함 화면이 "첫 성공 로드"를 잡는 방법을 `ref.listen(fireImmediately: true)`에서
  **build 안의 직접 호출**로 바꿨다. riverpod 3의 `WidgetRef.listen`에는 `fireImmediately` 인자가 아예 없고
  (`listenManual`에만 있다), 인자 없이 `listen`만 걸면 **이미 data인 provider에는 콜백이 한 번도 불리지 않는다**
  — 화면을 닫았다 바로 다시 열면 캐시가 살아 있어 그 경로에서 읽음이 찍히지 않는다. 같은 provider를 `watch`하고
  있으므로 build 안에서 부르면 두 경우가 모두 덮인다. design 5.2·흐름 3의 동작("첫 성공 로드에서 한 번만")은 그대로다.
- (2026-11-13) 4단계에 `main_shell.dart`의 앱 재개 리스너를 넣을 때 `AppLifecycleListener`를 `_MainShellState`가 직접 들고
  `initState`/`dispose`에서 만들고 거둔다(선례: `time_ticker.dart`). design 흐름 2는 "MainShell에 둔다"까지만 적었다.

- (2026-11-13) 4단계에 **계획에 없던 일**이 하나 붙었다: 종 아이콘이 네 탭 앱바에 들어가면서, 그 화면들을
  띄우는 기존 위젯 테스트 10개가 `notificationRepositoryProvider`를 필요로 하게 됐다(없으면 초기화되지 않은
  Supabase를 만져 provider가 예외를 던지고, 그 스택이 테스트 출력을 2만 줄 가까이 덮어 실제 실패를 가린다).
  그래서 `test/features/notification/notification_fakes.dart`(가짜 + 공용 override 목록)를 만들고 각
  `ProviderScope`에 한 줄씩 끼웠다. 이 저장소의 기존 관례(테스트가 필요한 레포지토리를 `implements` 가짜로
  override)를 그대로 따른 것이고, 프로덕션 코드는 바뀌지 않았다. `recruit_browse_test`의 "X 버튼" 테스트는
  `find.byType(IconButton)`이 종 버튼까지 잡아 모호해져 검색 필드 안으로 좁혔다.
- (2026-11-13) 손댄 기존 파일에 `dart format`을 돌리지 않았다. 이 저장소의 파일은 **건드리지 않은 것까지
  전부** `dart format --set-exit-if-changed`에서 "Changed"로 나오므로(포맷터 판이 달라졌다는 뜻), 돌리면
  이 기능과 무관한 diff가 폭발한다. 새로 만든 파일만 포맷된 상태다(편집 훅이 자동으로 한다).

## 3. 검증 방법

### 3.1 자동 (이 작업에서 돌린다)

- `flutter analyze` — **No issues found!** (2026-11-13 확인)
- `flutter test` — **804개 전부 통과**(이 기능이 더한 것: `test/features/notification/` 44개 +
  `widget_test.dart`의 네 탭 종 아이콘 1개). 필수 유닛 테스트는
  `notification_line_test.dart`(문구 매핑 7종·점수 조각·금지 키·남은 시간 미표기·시각 서식)와
  `notification_item_test.dart`(배지 판정 경계 — 읽은 시각과 **같은** 시각은 새 알림이 아니다).
- `deno test supabase/functions/_shared/` — **62개 통과**. 이 작업은 Edge Function 로직을 바꾸지 않는다(주석 한 줄만).

### 3.2 SQL (원격 적용 뒤 오너·메인 세션)

```
supabase db query --linked -f supabase/tests/notification_inbox_smoke.sql
```
`SMOKE RESULT ok=true`면 통과. 확인 항목은 design 10.1 그대로(격리·목록 내용·배지 판정·탈퇴·cascade).

### 3.3 사람 눈 (적용 전에 할 수 있는 것)

- 새 마이그레이션이 **옛 파일을 고치지 않았다**: `git diff --stat supabase/migrations/` 에 신규 파일 하나만.
- `delete_account` 재정의가 `20261106120000`의 정의와 **한 줄만** 다르다: 두 본문을 `diff`로 비교.
- 세 함수 모두 `security definer set search_path = public` + 첫 줄 `auth.uid() is null` 가드 + `revoke`/`grant` 쌍.
- `list_notifications`가 돌려주는 키가 `id, kind, battle_id, payload, created_at` 다섯뿐이다.

### 3.4 실기기 (오너, design 10.4)

알림 권한을 거부한 계정으로 한 바퀴 / 두 기기 배지 / 알림함을 열어 둔 채 상대 제출.

---

## 4. 6단계 — 누른 줄은 목록에서 사라진다 (2026-11-16 오너 추가)

> 입력: `spec.md` 맨 끝 **"## 추가 (2026-11-16 오너)"**(확정·범위 밖·수용 기준이 거기 있다).
> 설계는 메인 세션이 확정했다(원장은 건드리지 않고, 치운 사실을 따로 적고, 읽기는 RPC로만) —
> 이 절은 **순서와 검증**만 적고 다시 고르지 않는다.
>
> 1~5단계는 이미 끝나 **원격 DB까지 적용됐다**(2026-11-16). 이번 작업은 그 위의 작은 추가다.

### 4.0 충돌 검토 — 멈출 충돌 없음

문서끼리 어긋나 보이는 자리가 둘 있다. 어떻게 읽었는지만 적어 둔다.

| 어긋나 보이는 것 | 실제 | 처리 |
|---|---|---|
| `design.md` 11장 "범위 밖(재확인)"에 **삭제**가 들어 있다 ↔ spec의 2026-11-16 추가 | spec이 더 나중(오너)이고 그 문서가 범위 밖 항목에 취소선을 긋고 **무엇이 뒤집혔는지(누른 줄 하나)와 무엇이 그대로인지(스와이프·전체 지우기·undo·원장 행 삭제)**를 직접 적었다. 즉 **spec이 상위**이고 design은 아직 그 사실을 모른다 | 11장을 고쳐 쓰지 않고 **12장을 덧붙여** 어느 항목이 어떻게 좁혀졌는지 적는다(5-③). 임의로 한쪽을 택한 것이 아니라 spec에 적힌 범위를 옮기는 일이라 멈추지 않았다 |
| CLAUDE.md "에러는 삼키지 않는다" ↔ 치우기 실패를 `debugPrint`만 남김 | 그 줄에 이미 같은 성격의 예외가 둘(읽음 표시·배지 조회) 있다. 치우기도 관문이 아니고(치워지지 않아도 대결 진행·판정·결과가 똑같다) 사용자가 할 수 있는 일은 다시 누르는 것뿐이다 | 그 예외 줄에 **치우기를 함께 적어** 규칙을 지킨다(6-②). 메인 세션의 지시와 같다 |

**이 작업에서 하지 않는 것**: 원격 DB 적용(`supabase db push`/`db query`/대시보드), 커밋. 둘 다 오너·메인 세션 몫이다.
옛 마이그레이션 파일(`20261113120000_notification_inbox.sql` 포함)은 한 글자도 고치지 않는다 — 이미 적용됐다.

### 4.1 순서

| 순서 | 파일 | 작업 | 스키마 |
|---|---|---|---|
| ① | `supabase/migrations/20261116120000_notification_dismiss.sql` (신규) | ⓐ `notification_dismissals` 테이블(user_id→profiles, notification_id→notification_outbox on delete cascade, 기본키 둘, `notification_id` FK 인덱스, RLS 켜고 **정책 없음**) + 원장에 컬럼을 더하지 않은 이유를 테이블 주석에 ⓑ `dismiss_notification(p_notification_id bigint)` RPC(내 몫만, 아니면 조용히 무시, 멱등) ⓒ `list_notifications`·`has_new_notifications`를 `create or replace`로 갱신(치운 줄 제외, **50건은 치운 것을 뺀 뒤의 수**) ⓓ `delete_account` 재정의 — `20261113120000`의 정의를 **그대로 복사**하고 `delete from public.notification_dismissals ...` 한 줄만 더한다 ⓔ `revoke ... from public, anon` + `grant ... to authenticated` | **있음** |
| ② | `supabase/tests/notification_inbox_smoke.sql` | 기존 `do` 블록 **안에** 7절을 더한다(기존 항목·기대값은 한 글자도 바꾸지 않는다) | — |
| ③ | `lib/features/notification/data/notification_repository.dart` | `dismiss(int id)` 한 메서드 | — |
| ④ | `lib/features/notification/presentation/notification_inbox_screen.dart` | 줄 탭 = **치우기 → 기존 열기 흐름**(열 수 있든 없든 치운다). 치운 뒤 `notificationInboxProvider` invalidate. 치우기 실패는 `debugPrint`만 남기고 줄은 그대로 둔다 | — |
| ⑤ | `test/features/notification/notification_fakes.dart`, `notification_inbox_test.dart` | 가짜에 `dismissedIds`·`dismissError`를 두고(치운 줄을 실제로 빼는 가짜) 위젯 테스트 추가 | — |
| ⑥ | `CLAUDE.md`, `docs/specs/notification-inbox/design.md` | ② 에러 예외 줄에 치우기 추기 ③ design에 **12장** 하나 | — |

순서의 근거: 서버 계약(①)이 먼저 정해져야 앱이 부를 이름이 생기고, 스모크(②)는 그 계약과 같은 자리에서
적는 편이 어긋나지 않는다. 앱은 레포지토리(③) → 화면(④) → 테스트(⑤)의 기존 순서를 따른다. 문서(⑥)는
코드가 확정된 뒤 적는다. **새 화면이 없어 커밋 경계는 하나다**(커밋은 메인 세션 몫).

### 4.2 지킨 규칙 (CLAUDE.md)

- 이번 변경은 **판정에 한 줄도 닿지 않는다.** 알림함은 읽기 전용 거울이고 치움은 "내 목록에서 빼는 사실"
  하나다 — 승부·점수·상태 전이·cron·AI 호출·적재 함수에 변경이 없다. 그래서 "판정 로직은 DB에서"와
  "테스트 없이 판정 로직 수정 금지"에 해당하는 변경이 아니다(그럼에도 SQL 스모크와 위젯 테스트로 덮는다).
- 새 테이블의 사용자 FK는 `auth.users`가 아니라 `public.profiles`. 탈퇴가 묘비를 남겨 cascade가 돌지 않으니
  `delete_account`가 명시적으로 지운다.
- RLS는 테이블을 만들 때 함께 켠다. **정책을 두지 않는 것**이 선례다(`notification_reads`·`notification_outbox`) —
  쓰기 경로는 RPC 하나뿐이고 화면이 이 테이블의 값을 직접 쓸 일이 없다.
- 새 RPC: `security definer set search_path = public`, 첫 줄 `auth.uid() is null` 가드,
  `revoke execute ... from public, anon` + `grant execute ... to authenticated`.
- 스키마 변경은 마이그레이션 파일로만. 새 패키지 없음.

### 4.3 범위 밖(만들지 않는다)

스와이프 삭제·길게 눌러 메뉴·되돌리기(undo)·전체 지우기·"치운 알림 다시 보기"·원장 행 삭제·발송 상태 노출.
치움을 위한 새 kind·새 상태·행별 읽음 구조도 만들지 않는다(spec "여전히 범위 밖").

### 4.4 순서를 바꾼 기록

- (2026-11-16) ⑤에서 **치우기 성공 뒤 상세가 열리는 경로**를 보는 테스트에 `battleDetailProvider`
  override를 하나 더 끼웠다. 그 경로는 `BattleDetailScreen`을 실제로 띄우는데, 알림함 테스트의 가짜
  대결 레포지토리는 `noSuchMethod`로 막혀 있어 상세가 그대로는 그려지지 않는다. 선례(`battle_detail_load_test`)대로
  상세 provider를 실패로 덮어 "상세가 열렸다"만 확인한다 — 상세 화면의 내용은 이 테스트의 관심이 아니다.
- (2026-11-16) ②를 "파일 끝에 새 `do` 블록을 붙이기"가 아니라 **기존 블록 안에 7절을 더하기**로 했다.
  기존 블록은 마지막에 일부러 예외를 던져 롤백하므로, 뒤에 붙인 블록은 **트랜잭션이 끊겨 영원히 돌지 않는다.**
  기존 항목·기대값은 건드리지 않고 선언·7절·결과표에만 줄을 더했다.

### 4.5 검증

- `flutter analyze` / `flutter test` — 결과는 보고에 숫자로 적는다. 치우기 동작(누르면 사라진다,
  실패하면 남는다, 열 수 없는 대결의 줄도 사라진다)은 위젯 테스트로 덮는다.
- SQL은 원격 적용 뒤 오너·메인 세션이 돌린다:
  `supabase db query --linked -f supabase/tests/notification_inbox_smoke.sql` → `SMOKE RESULT ok=true`.
  7절이 확인하는 것: 남의 알림 id는 치워지지 않는다 / 치운 줄이 목록과 배지에서 빠진다 / 두 번 쳐도 한 행 /
  50건이 치운 것을 뺀 뒤의 수 / 탈퇴하면 치운 기록도 지워진다 / 원장 행이 사라지면 cascade.
- 사람 눈: 새 마이그레이션이 옛 파일을 고치지 않았는지(`git diff --stat supabase/migrations/`에 신규 하나),
  `delete_account` 재정의가 `20261113120000`의 정의와 **한 줄만** 다른지 `diff`로 비교.
- (2026-11-16) ①에 **메인 세션이 적어 준 목록에 없던 것 하나**를 더했다: `notification_id`에 FK
  인덱스(`notification_dismissals_notification_idx`). 기본키의 선두 축이 `user_id`라 **원장 행이
  지워질 때 도는 cascade**가 인덱스를 못 쓰고 전체 훑기가 된다(탈퇴는 내 수신 원장 행을 통째로
  지운다). 설계 판단을 바꾼 것이 아니라 같은 모양에 인덱스 하나를 붙인 것이고, 컬럼·제약·정책·
  RPC 계약은 적어 준 그대로다.
