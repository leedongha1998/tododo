# ui-restructure 설계

## 참고

spec.md: **없음.** 이번 건은 pm 단계 spec.md 없이 진행됐다. 사용자가 실기기로 MVP 전체 흐름을 돌려본 뒤 "UI를 먼저 바꿔야겠다"고 판단했고, 설계 논의 과정에서 확정한 결정이 이 문서의 입력이다. 따라서 아래 "확정된 결정"이 spec.md 역할을 한다 — 여기에 없는 요구사항은 만들어내지 않았고, 판단이 필요했던 지점은 "## 결정 필요"에 남겼다.

기존 화면/코드: `lib/features/todo/presentation/todo_list_screen.dart`, `lib/features/battle/presentation/*`, `lib/features/profile/presentation/profile_screen.dart`, `lib/core/theme/app_theme.dart`.

### 확정된 결정

1. 홈 하나에 "내 대결 + 할 일"을 2:3으로 나눠 담던 구조를 폐기하고 **하단 탭바 4탭**으로 분리한다.
2. 탭 이름·순서: **`내 대결` / `대결 찾기` / `할 일` / `프로필`.** 대결 관련 탭이 둘이므로 명사가 아닌 동사로 갈랐다.
3. `내 대결`은 **`active`/`judging`만** 보여준다. `finished`/`disputed`는 프로필 전적에서만 본다.
4. `대결 만들기` 확장형 FAB는 **`대결 찾기` 탭**에 둔다(등록 결과가 그 화면에 바로 보이므로).
5. 로그아웃·계정 삭제는 **프로필 탭 하단 `계정` 섹션**으로 모은다. 앱바 아이콘 3종은 전부 사라진다.
6. 할 일 항목에 "대결 중" 배지는 **만들지 않는다**(근거: "## 범위 밖" 참고). 할 일 탭 상단 대결 요약 스트립도 폐기 — `내 대결`이 독립 탭이 되어 불필요하다.
7. 기간은 2~3일. 스토어 스크린샷 4장 재촬영을 감수한다.

### 이 작업이 건드리지 않는 것

**판정 로직, RPC, DB 스키마, RLS는 한 줄도 바뀌지 않는다.** 이번 변경은 전부 presentation 레이어 + 목록 조회 조건 한 줄이다. 대결 상태 전이(`pending → active → judging → finished | disputed | cancelled`), 승패 계산 위치(DB), speed/quality 구분 규칙은 CLAUDE.md 그대로다.

---

## 화면

### 셸: `MainShell` (신규)

앱 루트가 `TodoListScreen`에서 `MainShell`로 바뀐다. `NavigationBar`(M3) + `IndexedStack` 조합.

| # | 라벨 | 아이콘(미선택 / 선택) | 본문 | FAB |
|---|---|---|---|---|
| 0 | `내 대결` | `sports_kabaddi` | `MyBattlesTab` | 없음 |
| 1 | `대결 찾기` | `search` / `search`(강조색) | `FindBattleTab` | 확장형 `대결 만들기` |
| 2 | `할 일` | `check_circle_outline` / `check_circle` | `TodoTab` | `+` |
| 3 | `프로필` | `person_outline` / `person` | `ProfileTab` | 없음 |

- 첫 진입 탭은 0(`내 대결`) — 앱을 열자마자 이 앱이 무엇인지 보이게 한다.
- 각 탭은 자기 `AppBar`를 갖고 제목은 탭 라벨과 동일하다. 앱바 액션 아이콘은 어느 탭에도 두지 않는다.
- 대결 상세(`BattleDetailScreen`)와 대결 만들기(`CreateBattleScreen`)는 **루트 Navigator에 push**해 탭바를 덮는다. 탭별 중첩 Navigator는 MVP에 과하므로 쓰지 않는다.
- `IndexedStack`이므로 네 탭 위젯이 모두 살아 있다 → 스크롤 위치·입력 중 텍스트가 탭 전환에도 보존된다. 대신 provider 캐시가 자동으로 비지 않으므로 아래 "데이터 흐름"의 재선택 무효화가 필수다.

### 탭 0 — `내 대결` (`MyBattlesTab`)

기존 `HomeBattleSection`이 `Expanded(flex: 2)` 껍데기를 벗고 탭 본문으로 승격된 것이다. 목록 항목 자체는 `BattleSummaryList` 재사용.

| 상태 | 표시 |
|---|---|
| 로딩 | 중앙 `CircularProgressIndicator` |
| 에러 | `battleLoadListFailed` + `다시 시도` 버튼(`ref.invalidate(myBattlesProvider)`). 기존에는 문구만 있고 재시도 경로가 없었다 |
| 빈 상태 | `진행 중인 대결이 없어요.` + `대결 찾기` 탭으로 이동시키는 버튼 + `지난 대결은 프로필에서 볼 수 있어요.` 안내 한 줄 |
| 데이터 | 대결 카드 목록(최신순, 기존 정렬 유지) |

- **빈 상태에서도 당겨 새로고침이 되어야 한다.** 현재는 `RefreshIndicator`가 비어있지 않은 경우만 감싸고 있어(`home_battle_section.dart:25-30`) 대결이 0건이면 새로고침이 불가능하다 — 이번에 `RefreshIndicator`가 세 상태를 모두 감싸도록 고친다.
- 카드 한 장의 정보 위계(현재는 `상대이름 · 속도전 · 판정중`이 전부 같은 회색 한 줄):
  - 1행: 대결 제목 (`titleMedium`, 강조)
  - 2행: 상대 이름 + 유형 배지(`속도전`/`품질전`)
  - 3행 우측: 상태 칩 — `진행중`(`active`) / `판정중`(`judging`). 이 탭에는 이 두 값만 온다.
  - `판정중`이면서 내가 아직 상대 증거를 판정하지 않았다면 "내 차례" 성격의 강조가 유용하지만, `BattleSummary`가 참가자 `decision`을 담고 있지 않아 지금 payload로는 판별할 수 없다 → "## 범위 밖" 참고.
- 탭하면 대결 상세로 push. 상세 화면 내부는 **C1(메인 세션에서 진행 중)에서 이미 다루므로 이 문서에서 재설계하지 않는다.**

### 탭 1 — `대결 찾기` (`FindBattleTab`)

기존 `BattleRecruitsScreen`의 2단 구성(`모집 중인 대결` / `내가 등록한 모집`)을 그대로 옮긴다. 앱바에서 진입하던 것이 탭이 될 뿐이라 내부 구조는 유지한다.

| 영역 | 상태별 표시 |
|---|---|
| `모집 중인 대결` | 로딩: 인디케이터 / 에러: `battleLoadRecruitsFailed` + 재시도 / 빈 상태: `battleRecruitsEmpty` + "직접 만들어 상대를 기다려보세요" 유도 / 데이터: 제목·등록자·유형 + `참가하기` |
| `내가 등록한 모집` | 로딩·에러 동일 / 빈 상태: `battleRecruitsEmpty` / 데이터: 제목·유형 + `취소` |

- 확장형 FAB `대결 만들기` → `CreateBattleScreen` push. 등록에 성공하면 화면이 닫히면서 `내가 등록한 모집`에 즉시 나타난다(이미 `openRecruitsProvider`/`myRecruitsProvider`를 invalidate하고 있다).
- 참가 성공 시 스낵바(`battleJoined`)는 유지하되, **매칭된 대결은 `내 대결` 탭으로 옮겨간 상태**이므로 사용자가 그 사실을 알 수 있어야 한다. 스낵바에 `내 대결` 탭으로 보내는 액션 버튼을 붙인다.
- 이 탭 전체를 `RefreshIndicator`로 감싼다(두 목록 동시 갱신). 현재 모집함에는 당겨 새로고침이 없어 남의 모집이 새로 올라와도 갱신 경로가 화면 재진입뿐이다.

### 탭 2 — `할 일` (`TodoTab`)

기존 `todo_list_screen.dart`의 하단 절반이 탭 전체가 된다. 목록 항목(체크박스 / 제목 / 삭제 아이콘)과 추가·수정 다이얼로그 동작은 그대로.

- FAB `+`를 누르면 **바로 할 일 입력 다이얼로그**가 뜬다. 선택 바텀시트(`_openAddMenu`)와 `_AddChoice` enum은 삭제한다 — 대결 만들기가 자기 탭의 FAB로 옮겨가 분기가 필요 없어졌다.
- 상태 표시: 로딩 인디케이터 / 에러 `loadTodosFailed` + 재시도 / 빈 상태 `emptyTodos`(문구의 "오른쪽 아래 버튼" 안내는 여전히 유효) / 데이터 목록.
- 이 탭은 당겨 새로고침을 두지 않는다(내 데이터만 다루고 다른 기기에서 바뀔 일이 사실상 없다). 기존과 동일.

### 탭 3 — `프로필` (`ProfileTab`)

기존 `ProfileScreen` 구성(표시 이름 → 집계 줄 → 전적 목록 → 계정 삭제)을 유지하고, 하단을 `계정` 섹션으로 정리한다.

| 영역 | 표시 |
|---|---|
| 표시 이름 | 로딩 인디케이터 / 에러 `profileLoadFailed` / 데이터 `titleLarge` |
| 전적 집계 | `속도전 N승 M패 · 품질전 K종료 L미결`(기존 계산 그대로) |
| 전적 목록 | 빈 상태 `profileRecordEmpty` / 에러 `profileLoadRecordFailed` / 데이터: 제목·상대·유형 + 결과 라벨(`승`/`패`/`종료`/`미결`) |
| `계정` 섹션 | 구분선 + 섹션 제목 `계정` → `로그아웃`(중립 색) → `계정 삭제`(error 색, 기존 확인 다이얼로그 그대로) |

- `내 대결`에서 종료·미결 대결이 빠지므로 **이 화면이 지난 대결을 볼 수 있는 유일한 경로**가 된다. 전적 목록 항목을 탭하면 대결 상세로 push해 증거와 결과를 다시 볼 수 있게 한다(`BattleRecord`가 `battle.id`를 갖고 있어 추가 조회 없이 가능하다).
- 로그아웃은 앱바 아이콘에서 여기로 이동한다. `authRepositoryProvider.signOut()` 호출부만 옮기는 것이고 동작은 동일하다.
- 계정 삭제 경로가 "프로필 탭 → 스크롤"로 2단계 안에 있어 Play 정책(앱 내 계정 삭제 경로 제공)을 계속 충족한다.

### 테마 (`app_theme.dart`)

현재는 `ColorScheme.fromSeed(seedColor: Colors.deepOrange)` 한 줄뿐이라 모든 화면이 Flutter 기본값으로 그려진다. 이번에 정의할 것:

- 시드 색을 런처/스토어 아이콘 색과 맞추고, `NavigationBarThemeData`(선택 인디케이터·라벨 표시 규칙), `CardTheme`, `ListTileTheme`, `SegmentedButtonTheme`, `FilledButtonTheme`, `TextTheme`(제목/본문/캡션 위계)를 채운다.
- 유형 배지(`속도전`/`품질전`)와 상태 칩(`진행중`/`판정중`/`종료`/`미결`)의 색·모양 규칙을 테마 안에 상수로 둔다 — 대결 카드, 상세, 전적 목록 세 곳이 같은 규칙을 써야 한다.
- 다크 모드는 이번 범위 밖이다(현재 `light`만 정의돼 있고 MVP에서 늘리지 않는다).

### 필요한 신규 문자열

전부 `lib/core/strings.dart`에 추가한다. **단, 이 파일은 C1 작업(메인 세션)이 동시에 편집 중이므로 이번 작업의 C3 이후 커밋에서 추가한다.**

`tabMyBattles`(`내 대결`), `tabFindBattle`(`대결 찾기`), `tabTodo`(`할 일`), `tabProfile`(`프로필`), `battleMyBattlesEmptyHint`(`지난 대결은 프로필에서 볼 수 있어요.`), `battleFindBattleCta`(`대결 찾으러 가기`), `battleGoToMyBattles`(`내 대결 보기`), `profileAccountSection`(`계정`).

기존 `battleMyBattlesEmpty`(`진행 중인 대결이 없어요.`)는 문구가 새 조회 조건과 정확히 맞아떨어져 그대로 쓴다.

---

## 데이터 흐름

### 조회 조건 변경 (유일한 비-UI 변경)

`BattleRepository.fetchMyBattles`(`battle_repository.dart:65-74`)

```dart
// 변경 전
.not('status', 'in', '(pending,cancelled)')   // active, judging, finished, disputed
// 변경 후
.inFilter('status', ['active', 'judging'])
```

- 종료·미결 대결은 프로필 전적에서만 보인다. 전적은 이미 `finished`/`disputed`만 다루므로(수동 테스트 7-3) 기록이 사라지거나 중복되지 않는다.
- `pending`(내가 등록한 모집)은 종전대로 `fetchMyRecruits`가 담당하므로 `내 대결` 탭에 섞이지 않는다. 따라서 `battleStatusLabel`(`battle_summary_list.dart:12-25`)이 `내 대결` 탭에서 만나는 값은 `active`/`judging` 둘뿐이다.
- **부작용:** 판정이 끝나는 순간 대결이 `내 대결` 탭에서 사라진다. 그래서 결과를 제대로 보여주는 C1(대결 상세 상태 표현)이 이 변경보다 먼저 배포돼야 하고, 빈 상태에 `지난 대결은 프로필에서 볼 수 있어요.` 안내를 둔다.

### 탭 전환과 캐시

`openRecruitsProvider` / `myRecruitsProvider` / `myBattlesProvider` / `battleDetailProvider`는 모두 `autoDispose`이고, 주석(`battle_providers.dart:14-15`)이 밝히듯 **"화면을 떠나면 캐시를 비운다"**는 전제로 최신성을 확보해왔다. `IndexedStack`은 탭 위젯을 살려두므로 이 전제가 깨진다 — 탭을 오가도 dispose되지 않아 상대의 참가·제출·판정이 영영 반영되지 않을 수 있다.

그래서 **탭이 다시 선택되는 순간에만 해당 탭의 provider를 1회 무효화**한다.

| 탭 | 재선택 시 무효화 |
|---|---|
| `내 대결` | `myBattlesProvider` |
| `대결 찾기` | `openRecruitsProvider`, `myRecruitsProvider` |
| `할 일` | 없음(내 데이터만, 다른 주체가 바꾸지 않는다) |
| `프로필` | `myProfileProvider`, `battleRecordsProvider` |

- 이미 선택된 탭을 다시 탭한 경우도 같은 무효화를 태운다(사용자가 새로고침 의도로 누르는 흔한 제스처).
- 스크롤 위치는 `IndexedStack`이 유지하므로 무효화해도 목록이 맨 위로 튀지 않는다.
- 당겨 새로고침(`RefreshIndicator`)은 세 탭 모두 그대로 남는다 — 자동 무효화는 탭 전환 시점에만 걸리므로 같은 탭에 머무는 동안의 갱신 수단이 필요하다.
- 프로필 탭 무효화가 없으면 수동 테스트 7-4("대결을 하나 더 끝낸 뒤 프로필을 다시 열면 즉시 반영")가 `IndexedStack` 도입만으로 깨진다.

### 액션 → 반영 경로 (기존과 동일, 확인용)

| 액션 | 경로 |
|---|---|
| 할 일 추가/수정/완료/삭제 | `todoRepositoryProvider` → `todos` 테이블 직접 조작(RLS) → `todosProvider` invalidate |
| 대결 만들기 | `battleRepositoryProvider.createBattle` → `battles` insert(RLS) → `openRecruitsProvider`/`myRecruitsProvider` invalidate |
| 모집 참가 | `join_battle` RPC → `openRecruitsProvider`/`myBattlesProvider` invalidate |
| 모집 취소 | `cancel_battle` RPC → `myRecruitsProvider` invalidate |
| 증거 제출 / 판정 | `submit_evidence` / `decide_evidence` RPC → `battleDetailProvider`/`myBattlesProvider` invalidate |

승패·상태 전이는 전부 RPC 안에서 결정되고 화면은 `status`/`winner_id`를 읽기만 한다. 이번 재구성으로 이 경계는 바뀌지 않는다.

---

## API 계약

**신규 RPC 없음. 기존 RPC 시그니처 변경 없음. 마이그레이션 없음. RLS 변경 없음.**

변경되는 계약은 클라이언트 측 조회 조건 하나뿐이다.

```
battles select
  .or('creator_id.eq.{myId},opponent_id.eq.{myId}')
  .inFilter('status', ['active', 'judging'])     // ← 변경점
  .order('created_at', ascending: false)
```

그 외 select-eq 패턴(`fetchOpenRecruits`: `status = 'pending' and creator_id <> me`, `fetchMyRecruits`: `status = 'pending' and creator_id = me`, `fetchParticipants`: `battle_id = ?`)은 그대로다.

### CLAUDE.md 도메인 규칙과의 충돌 여부

| 규칙 | 이번 설계 |
|---|---|
| 상태 전이 `pending → active → judging → finished/disputed/cancelled` | 전이 자체 불변. `내 대결` 탭이 `active`/`judging`만 **표시**할 뿐이고 다른 상태의 대결이 사라지거나 접근 불가가 되지 않는다(프로필 전적 → 상세로 도달) |
| 판정 로직은 DB/Edge Function에서 | presentation만 바뀐다. 클라이언트 승패 계산 없음 |
| speed/quality 구분 | 유형 배지로 시각화만 추가. 규칙·필수 증거·결과 판정은 불변 |
| 대결은 2인, 주제 모집 방식 | 4탭 구조가 2인·모집 모델을 그대로 반영(`대결 찾기` = 모집 목록, opponent 지목 UI 없음) |
| 사용자 FK는 `profiles` | 스키마 미변경 |
| 탈퇴 시 묘비 | 프로필 전적에 `탈퇴한 사용자`가 그대로 표시된다(변경 없음) |

---

## 기존 파일 변경 요약

| 파일 | 변경 |
|---|---|
| `lib/main.dart`(또는 AuthGate 하위) | 로그인 후 루트를 `TodoListScreen` → `MainShell`로 교체 |
| `lib/core/navigation/main_shell.dart` (신규) | `NavigationBar` + `IndexedStack`, 탭 인덱스 상태, 탭 재선택 무효화 |
| `lib/features/todo/presentation/todo_list_screen.dart` | 상단 `HomeBattleSection`/`Divider`/`Expanded` 분할 제거, 앱바 액션 3종 제거, `_openAddMenu`·`_AddChoice` 삭제, FAB는 입력 다이얼로그 직행. 사실상 `TodoTab`으로 축소 |
| `lib/features/battle/presentation/home_battle_section.dart` | `내 대결` 탭 본문으로 승격(`MyBattlesTab`). `RefreshIndicator`가 빈 상태·에러까지 감싸도록 수정, 에러에 재시도 추가, 빈 상태에 `대결 찾기` 유도 |
| `lib/features/battle/presentation/battle_summary_list.dart` | 카드 정보 위계 재구성(제목/상대·유형 배지/상태 칩). `battleStatusLabel`은 유지(전적 목록에서 `finished`/`disputed`를 계속 쓴다) |
| `lib/features/battle/presentation/battle_recruits_screen.dart` | `대결 찾기` 탭 본문으로 전환, 확장형 FAB 추가, 전체를 `RefreshIndicator`로, 참가 스낵바에 `내 대결 보기` 액션 |
| `lib/features/battle/presentation/create_battle_screen.dart` | 변경 없음(push 진입점만 바뀜) |
| `lib/features/battle/data/battle_repository.dart` | `fetchMyBattles` 조회 조건 한 줄 |
| `lib/features/profile/presentation/profile_screen.dart` | `프로필` 탭 본문으로 전환, 하단 `계정` 섹션(로그아웃 추가), 전적 항목 탭 → 대결 상세 push |
| `lib/core/theme/app_theme.dart` | 테마 정의 확장 |
| `lib/core/strings.dart` | 탭 라벨 등 신규 문자열 (**C1과 충돌하므로 C3 이후에 손댄다**) |
| `lib/features/battle/presentation/battle_detail_screen.dart` | **이번 작업 범위 밖 — C1(메인 세션)에서 처리 중** |

### 문서 영향

- `docs/manual-test-plan.md` **6-3의 기대값이 뒤집힌다**: "`종료`/`미결` 대결은 `내 대결`에 계속 보인다" → "`종료`/`미결` 대결은 `내 대결` 탭에서 사라지고 프로필 전적에서만 보인다". 같은 항목의 "사라지는 건 취소된 모집과 아직 매칭 안 된 모집" 문장도 함께 손봐야 한다.
- 같은 문서에서 앱바 아이콘을 경유하는 절차 표현(1-3 "우상단 사람 아이콘", 1-4 "우상단 로그아웃 아이콘", 3-3 "상단 메일 아이콘")을 탭 기준으로 고친다.
- 7-4(프로필 즉시 반영)는 탭 재선택 무효화가 있어야 유지되므로 회귀 확인 항목으로 남긴다.
- `store/screenshots/*.png` 4장은 재촬영한다. `tool/screenshot_seed.sql`로 시드가 자동화돼 있어 비용이 낮다. 탭이 4개가 되었으므로 촬영 화면도 `내 대결` / `대결 찾기` / 대결 상세 / 프로필로 재구성한다.

---

## 작업 순서 (커밋 단위)

> design-standards는 구현 순서·커밋 계획을 plan.md 영역으로 두지만, 이번 건은 **"중간에 멈춰도 배포 가능해야 한다"**가 설계 제약 자체이므로 여기에 남긴다. 파일별 세부 분해는 plan.md에서 한다.

| # | 내용 | 멈춰도 배포 가능한가 |
|---|---|---|
| C1 | 대결 상세 상태 표현(상태 칩, 제출 시각 노출, 결과 배너 강조, 앱바 제목=대결 제목) — **메인 세션 진행 중** | 예. 독립 화면 하나 |
| C2 | `fetchMyBattles`를 `active`/`judging`만으로 + `manual-test-plan.md` 6-3 수정 + 빈 상태 안내 | 예. C1 이후여야 결과 정보 손실이 없다 |
| C3a | `MainShell` 도입: `NavigationBar` + `IndexedStack`으로 4탭을 만들고 기존 화면을 그대로 꽂는다. 앱바 아이콘은 **아직 남겨둔다** | 예. 탭바와 앱바 아이콘이 잠시 중복되지만 기능은 온전하다 |
| C3b | 홈 분할 해체(할 일 탭 단독화), 대결 만들기 FAB를 `대결 찾기` 탭으로, `_openAddMenu` 삭제, 앱바 아이콘 3종 제거, 로그아웃을 프로필 `계정` 섹션으로, 탭 재선택 무효화 | 예. 여기서 화면 구조가 완성된다 |
| C4 | 테마 정의 + 대결 카드/할 일 행 시각 위계 + 유형 배지·상태 칩 규칙 | 예. 구조 확정 후에 칠해야 재작업이 없다 |
| C5 | 스크린샷 4장 재촬영 + 스토어 자산 교체 | 예 |

각 커밋마다 `flutter analyze` 이슈 0, `flutter test` 통과가 완료 조건이다. C2가 유일하게 데이터 접근 코드를 건드리므로 관련 테스트가 있으면 함께 갱신한다. 판정 로직은 어느 커밋도 건드리지 않으므로 판정 유닛 테스트는 그대로 통과해야 한다 — 깨지면 범위를 벗어난 것이다.

---

## 범위 밖 (백로그로 밀어낸 것)

- **할 일 항목의 "대결 중" 배지.** 대결 제목은 자유 입력이고 `todos`와 연결 컬럼이 없다. 제목 문자열 일치로 이으면 "아침 7시 기상하기" vs "7시 기상"에서 어긋나 오탐·누락이 생기고, 사용자가 직접 지정하게 하려면 `todos.battle_id` 같은 컬럼이 필요해 "스키마 불변" 전제와 충돌한다. → `TODO_BACKLOG.md`에 "할 일과 대결 연결(todos.battle_id) — 배지·자동 완료 처리" 한 줄로 남긴다.
- **`내 대결` 카드의 "내 차례" 강조/배지.** `BattleSummary`가 참가자 `decision`을 담지 않아 목록 조회만으로는 판별할 수 없다. 추가하려면 `fetchMyBattles`가 `battle_participants`를 조인해야 하므로 이번 범위 밖. → 백로그.
- 탭 배지(미판정 건수), 다크 모드, 애니메이션 전환, 탭별 중첩 Navigator, 대결 정렬/필터 옵션.
- AI 심판·푸시 알림·랭킹은 MVP 범위 밖이므로 UI에 자리도 만들지 않는다.

---

## 결정 필요

1. **`대결 찾기` 탭 아이콘.** `Icons.search`로 잡아뒀는데 이 탭은 검색이 아니라 "모집 목록 + 등록"이라 의미가 반만 맞는다. `Icons.campaign`(모집·공고) 또는 `Icons.groups`가 후보다. 아이콘 상수 한 줄이라 구현 중 사용자 확인 없이 바꿔도 되는 수준이지만, 4탭 중 유일하게 의미가 애매한 자리라 적어둔다.
2. **프로필 전적 항목 → 대결 상세 push를 이번에 넣을지.** `내 대결`에서 종료 대결이 빠지므로 지난 대결의 증거를 다시 볼 경로가 이것뿐이 된다. 넣는 쪽이 맞다고 보고 위 설계에 포함했지만, 전적 목록이 지금은 순수 표시용이라 C2/C4 중 어느 커밋에 얹을지는 plan.md에서 정한다. 사용자가 "지난 대결 상세는 안 봐도 된다"고 판단하면 빼도 무방하다.
