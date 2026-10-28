# recruit-browse 설계

## 참고
- spec.md: `docs/specs/recruit-browse/spec.md`. **이 설계의 유일한 요구사항이다.** 특히 "## 결정 완료 (오너, 2026-10-28)" 4건(내 모집은 떼어낸 구역 / 검색은 제목만 / 기간대 필터 P0 / 최신순 고정)을 전제로 한다. spec의 "## 결정 필요" 4건은 그 결정으로 모두 답이 났으므로 이 설계에서 다시 묻지 않는다.
- 선례로 읽은 것: `docs/specs/mutual-judge/design.md`(문서 구성, 순수 함수 분리, 오류 코드 표, 테스트 전략 표), `docs/specs/ai-judge/design.md`(모집 목록 RPC가 `{battle, creator}` 두 덩어리를 한 번에 돌려주는 이유).
- 근거로 읽은 현재 구현: `supabase/migrations/20260921120100_custom_duration.sql`(현재 `list_open_recruits()` 정의), `20260917120000_join_and_player_cards.sql`(그 함수의 최초 정의와 GRANT), `20260916130000_ai_criteria.sql`(모집 1개 부분 유니크 인덱스), `lib/features/battle/presentation/{battle_recruits_screen,my_battles_screen,battle_summary_list,battle_chips,create_battle_screen,judgment_section}.dart`, `lib/features/battle/data/{battle_repository,open_recruit,battle,criteria_check_result}.dart`, `lib/features/battle/domain/{battle_providers,criteria_rules}.dart`, `lib/core/navigation/{main_shell,app_tab}.dart`, `lib/core/theme/app_theme.dart`, `lib/core/widgets/{pixel_frame,pixel_tag,pixel_loader,status_message}.dart`, `lib/core/strings.dart`, `supabase/tests/{custom_duration_smoke,join_battle_smoke}.sql`, `test/**`.
- 전제: mutual-judge 1~5단계가 원격에 적용되어 돌고 있다. 로컬 Docker가 없어 마이그레이션은 원격에 적용하며 **적용 전 오너 확인**을 받는다(적용은 메인 세션).

## 설계 원칙

1. **걸러내는 일은 전부 서버가 한다.** 검색·유형·기간대·정렬·묶음 끊기는 한 번의 RPC 호출 안에서 결정된다. 클라이언트는 받은 묶음을 **한 건도 걸러내지 않는다**(spec: "받은 일부를 앱이 걸러내면 조건에 맞는 모집이 조용히 빠진다"). 화면이 하는 판단은 "어떤 조건으로 요청할지"와 "이 상태를 어떤 문구로 말할지"뿐이다.
2. **페이징은 위치가 아니라 값에 고정한다.** 오프셋이 아니라 `(created_at, id)` 커서(keyset)를 쓴다. 목록이 최신순이라 묶음을 받는 사이에 새 모집이 맨 위에 끼어들고, 누군가 참가하면 중간 행이 사라지기 때문이다(아래 "왜 오프셋이 아닌가").
3. **판정·점수·한도·매칭 규칙을 한 줄도 건드리지 않는다.** 이 기능은 모집을 **읽는 방식**만 바꾼다. 상태 전이, 승패, `criteria_version`, 하루 1대결·모집 1개 한도, "생성자가 한도를 쓴 모집도 숨기지 않는다"는 모두 그대로다.
4. **새 시각 언어를 만들지 않는다.** 검색 입력은 테마의 `InputDecorationTheme`, 필터는 `SegmentedButton`(`segmentedButtonTheme`), 목록 끝 로딩·빈 상태·실패는 `StatusMessage`, 구역은 `PixelFrame`, 칩은 `PixelTag`/`BattleTypeBadge`로 해결한다. **`ChoiceChip`·`FilterChip`은 쓰지 않는다** — 이 테마에는 `chipTheme`이 없어서 둥근 Material 칩이 그대로 드러난다(`custom-duration`이 유형·기간 선택에 `SegmentedButton`을 쓴 이유 그대로).
5. **마이그레이션은 1건.** 함수 교체 + 인덱스 하나가 전부다. 테이블·컬럼·정책·cron은 손대지 않는다.

## CLAUDE.md 도메인 규칙 대조

| 조항 | 이 설계에서 |
|---|---|
| 판정 로직은 DB/Edge, 화면은 표시만 | 유지. 이 기능은 판정 함수를 하나도 건드리지 않는다. 목록 조회 함수 하나만 교체한다 |
| 클라이언트에서 승패 계산 금지 | 유지. 새로 생기는 클라이언트 계산은 "커서를 어디까지 받았나"와 "어떤 빈 상태 문구인가"뿐이다 |
| 주제 모집 자동 매칭, 2인만 | 유지. 생성자 이름 검색을 넣지 않는 이유 중 하나가 이것이다(spec 본문) |
| 모집 중 대결은 사용자당 1개 | 유지. 그래서 내 대결 탭의 새 구역은 **항상 0건 또는 1건**이다 |
| 생성자가 오늘 한도를 쓴 모집도 목록에서 숨기지 않는다 | 유지. 필터 축에 "지금 참가 가능한 것만"을 두지 않는다 |
| 내 모집에는 내가 참가할 수 없다 | 유지. 서버가 `creator_id <> auth.uid()`로 목록에서 빼는 것도 그대로다 |
| 랭킹·임의 사용자 전적 조회 금지 | 유지. 생성자 점수·전적은 필터·정렬 축이 아니고, 목록 카드에도 올라오지 않는다(상세 시트에서만 본다) |
| 새 RPC는 `revoke ... from public, anon` + `grant to authenticated`, SECURITY DEFINER 첫 줄 로그인 가드 | 교체되는 `list_open_recruits`에 그대로 적용한다 |
| 사용자에게 보이는 문자열은 한국어, `lib/core/strings.dart`에 모은다 | 새 문구 전부 그 파일에 둔다(아래 "문자열") |

---

## 기간대 구간

실제 범위는 `battles.duration_minutes` 1~10080분이다. 구간은 **3개 + 전체**이고 경계는 서버가 소유한다.

| 키(서버 인자) | 라벨 | 범위(분) | 사용자가 읽는 뜻 |
|---|---|---|---|
| (null) | 전체 | 1~10080 | 기본값 |
| `quick` | `1시간 안` | 1 ≤ d ≤ 60 | 지금 바로 사진을 찍을 수 있을 때만 |
| `day` | `하루 안` | 60 < d ≤ 1440 | 오늘 안에 해내면 된다 |
| `multi` | `며칠` | 1440 < d ≤ 10080 | 며칠 여유가 있다 |

- **경계를 숫자로 말하는 라벨을 쓴 이유**: "짧은 대결"은 얼마가 짧은지 사용자가 다시 추측해야 한다. spec이 요구한 것은 "분 단위 숫자를 환산하지 않아도 되는 구간 이름"이고, `1시간 안`/`하루 안`은 환산 없이 경계를 그대로 말한다.
- 경계값은 큰 쪽이 아니라 **작은 구간에 포함**된다(60분 → `quick`, 1440분 → `day`). 생성 화면의 빠른 선택(30분·1시간·1일·3일·7일)이 구간마다 적어도 하나씩 떨어지고, 오너가 깔아 본 더미(5분~7일)도 세 구간에 모두 걸린다.
- 구간은 서로 겹치지 않는다. `1시간 안`을 고른 사용자에게 하루짜리가 보이지 않는 것은 의도된 것이다 — 이 필터의 목적이 "지금 할 수 있나"를 가르는 것이기 때문이다.
- **경계 숫자는 서버 함수 안에만 있다.** 클라이언트는 키(`quick`/`day`/`multi`)와 라벨만 안다. 분 단위 비교를 Dart에 복제하면 서버와 어긋날 수 있고, 클라이언트가 목록을 걸러내는 길도 열린다.

---

## 서버 함수 새 계약

### 교체 대상과 교체 방식

지금 함수는 인자가 없다(`list_open_recruits()` → `setof jsonb`, 행마다 `{battle, creator}`). 인자가 생기므로 **드롭 후 재생성**한다. `create or replace`로는 인자를 추가할 수 없고, 옛 0-인자 함수를 남기면 오버로드가 둘이 되어 `list_open_recruits()` 호출이 모호해진다(`function is not unique`). 드롭하면 GRANT도 사라지므로 `revoke`/`grant`를 다시 쓴다(`custom_duration`의 `create_battle` 선례와 같은 함정).

### 시그니처

```sql
create function public.list_open_recruits(
  p_limit             integer     default 20,
  p_cursor_created_at timestamptz default null,
  p_cursor_id         uuid        default null,
  p_query             text        default null,
  p_type              text        default null,   -- 'speed' | 'quality' | null
  p_duration_band     text        default null    -- 'quick' | 'day' | 'multi' | null
) returns setof jsonb
```

- **반환 모양은 바꾸지 않는다.** 지금처럼 `setof jsonb`이고 행마다 `{battle: {...}, creator: {...}}` 두 덩어리, 키도 그대로다. `OpenRecruit.fromMap`·`PlayerCard`·모집 상세 시트가 손대지 않고 그대로 쓰인다. 묶음 메타(커서·더 있는지)를 담은 포장 객체로 바꾸지 않는 이유는, 커서로 쓸 값(`battle.created_at`, `battle.id`)이 **이미 행 안에 있어** 같은 사실을 두 번 적는 셈이 되기 때문이다.
- **기본값을 두는 이유**: 인자 없이 부르면 "최신 20건"이 된다. 기존 SQL 스모크 두 개(`custom_duration_smoke.sql`, `join_battle_smoke.sql`)가 `list_open_recruits()`를 그대로 부르고 있고 둘 다 모집이 몇 건뿐이라 기본값으로 계속 통과한다(둘 중 어느 것도 반환 순서에 기대지 않는다 — 하나는 제목으로 다시 정렬하고 하나는 id로 찾는다). 기본값이 20이라 "인자를 잊으면 전체가 쏟아지는" 방향으로는 틀리지 않는다.
- 앱은 **항상 여섯 인자를 모두 넘긴다**(기본값에 기대지 않는다).

### 인자 검증과 오류

| 조건 | 결과 |
|---|---|
| `auth.uid() is null` | `raise exception '로그인이 필요합니다.'`(CLAUDE.md 가드) |
| `p_limit` null 또는 1~50 밖 | `message = '목록 요청이 올바르지 않습니다.', hint = 'BAD_PAGE_REQUEST'` |
| `p_type`이 null도 `speed`도 `quality`도 아님 | 같은 오류 |
| `p_duration_band`가 null도 `quick`/`day`/`multi`도 아님 | 같은 오류 |
| 커서 두 인자 중 하나만 채워짐 | 같은 오류 |

상한 50은 "한 번에 전부 받는" 옛 동작으로 되돌아갈 수 없게 하는 못이다. 이 오류는 사용자의 조작으로는 발생하지 않는 **프로그래밍 오류**이므로 사용자 문구를 따로 분기하지 않고 목록 불러오기 실패와 같은 안내를 쓴다.

### 본문(조건과 정렬)

```sql
where b.status = 'pending'
  and b.opponent_id is null
  and b.creator_id <> v_user
  and (p_cursor_created_at is null
       or (b.created_at, b.id) < (p_cursor_created_at, p_cursor_id))
  and (v_query is null or strpos(lower(b.title), lower(v_query)) > 0)
  and (p_type is null or b.type = p_type)
  and (p_duration_band is null or case p_duration_band
         when 'quick' then b.duration_minutes <= 60
         when 'day'   then b.duration_minutes > 60 and b.duration_minutes <= 1440
         else              b.duration_minutes > 1440
       end)
order by b.created_at desc, b.id desc
limit p_limit
```

`v_query := nullif(btrim(coalesce(p_query, '')), '')` — 앞뒤 공백을 떼고, 빈 문자열은 "조건 없음"과 같게 만든다.

- **`ilike '%' || p_query || '%'`를 쓰지 않는 이유**: 사용자가 입력한 `%`나 `_`가 와일드카드로 해석되어 `%` 한 글자만 쳐도 전체가 결과가 된다. 막으려면 `escape`와 수동 이스케이프가 필요하다. `strpos(lower(title), lower(query)) > 0`은 **순수 부분 문자열**이라 이스케이프할 것이 없고, 한국어 제목("설거지하기"에서 "거지") 중간 일치가 그대로 된다. `lower()`는 영문 제목의 대소문자 차이를 없애기 위한 것이다(한국어에는 대소문자가 없다).
- 제목 안쪽 공백은 **다듬지 않는다**. 제목 그대로의 부분 일치가 spec의 요구다.
- 정렬은 `created_at desc` + **`id desc` 동률 타이브레이커**다. 타이브레이커 없이는 같은 `created_at`을 가진 두 모집의 순서가 호출마다 달라져 커서 페이징이 깨진다(같은 행이 두 묶음에 들어오거나 빠진다).

### 왜 오프셋이 아닌가 (중복·누락이 없다는 근거)

| 묶음 사이에 일어나는 일 | 오프셋(`offset 20 limit 20`) | 커서(`(created_at, id) < (c1, c2)`) |
|---|---|---|
| 새 모집이 올라온다(최신순이라 **맨 위**에 들어온다) | 전체가 한 칸 밀려 **이미 본 행이 다음 묶음에 다시 나온다**(중복) | 새 행은 커서보다 **위**라 조건 `< 커서`에 걸리지 않는다. 다음 묶음에 들어오지 않는다 |
| 누군가 참가해 모집이 사라진다 / 생성자가 취소한다 | 뒤의 행이 한 칸 앞으로 당겨져 **아직 못 본 행이 건너뛰어진다**(누락) | 사라진 행만 결과에 없고 나머지 행의 조건값은 그대로다. 건너뛰어지는 행이 없다 |
| 조건(검색어·필터)이 바뀐다 | 오프셋이 다른 집합을 가리켜 뜻이 없다 | 커서를 버리고 첫 묶음부터 다시 시작한다(아래 provider 설계) |

커서는 "몇 번째"가 아니라 "어느 값 다음"을 가리키므로, 묶음 사이에 집합이 흔들려도 이미 받은 마지막 행보다 **엄격히 작은** 행만 다음 묶음에 들어온다. 중복과 누락은 여기서 구조적으로 사라진다.

**남는 성질 하나(의도된 것)**: 스크롤을 시작한 뒤에 올라온 모집은 그 스크롤 세션 동안 목록에 나타나지 않는다. 목록은 "내가 보기 시작한 시점의 모집 목록"이고, 새 모집을 보는 길은 **당겨서 새로고침**이다. spec의 트레이드오프 "최신순 + 무한 스크롤의 어긋남"이 가리킨 지점이고, 중복·누락과 달리 사용자가 손으로 되돌릴 수 있는 어긋남이다.

### 인덱스

```sql
create index battles_open_recruit_feed_idx
  on public.battles (created_at desc, id desc)
  where status = 'pending' and opponent_id is null;
```

정렬과 커서 탐색(행 비교)을 이 부분 인덱스가 받는다. 검색어(`strpos`)와 기간대(`case`)는 인덱스를 타지 않고 남은 모집 행에 필터로 걸린다 — 모집 중 대결은 사용자당 1개라 이 테이블의 `pending` 행 수는 **사용자 수를 넘지 않고**, 지금은 수십 건이다. `pg_trgm`/GIN은 **지금 만들지 않는다**(CLAUDE.md "미래 대비 추상화 금지"). 필요해지는 시점은 `pending` 행이 수만 건이 된 뒤다.

### 권한

```sql
revoke execute on function public.list_open_recruits(integer, timestamptz, uuid, text, text, text) from public, anon;
grant  execute on function public.list_open_recruits(integer, timestamptz, uuid, text, text, text) to authenticated;
```

`security definer set search_path = public` + 첫 줄 로그인 가드는 그대로 유지한다(모집 목록은 로그인한 사용자만 본다는 기존 선).

### 마이그레이션 1건에 들어가는 것

`supabase/migrations/<ts>_recruit_browse.sql`: ① 옛 `list_open_recruits()` 드롭, ② 새 함수 생성 + `comment`, ③ `revoke`/`grant`, ④ 위 부분 인덱스. **이게 전부다.** 테이블·컬럼·RLS·cron·다른 함수는 건드리지 않는다.

---

## 화면

기존 패턴(`AsyncValue.when`, 실패 시 `debugPrint` + 스낵바, 당겨서 새로고침)을 따른다. 문자열은 전부 `lib/core/strings.dart`.

### 1. 대결 찾기 탭 (`battle_recruits_screen.dart` 재작성)

앱바(`대결 찾기`)와 `대결 만들기` FAB는 그대로. 본문은 **고정 조작 영역 + 스크롤 목록** 두 층이다.

**고정 조작 영역** (앱바 바로 아래, 스크롤되지 않는다 — spec: "지금 어떤 필터가 걸려 있는지 목록을 보는 동안 보인다")

| 줄 | 위젯 | 내용 |
|---|---|---|
| 1 | `TextField` | `hintText: 제목으로 찾기`, `prefixIcon: PixelIcon(PixelIcons.search)`, 입력이 있으면 `suffixIcon: IconButton(PixelIcons.close)`(누르면 즉시 지우고 전체 목록으로), `textInputAction: TextInputAction.search`, `onSubmitted` → 즉시 적용 + 포커스 해제 |
| 2 | `SegmentedButton<RecruitTypeFilter>` | `전체 / 속도전 / 품질전`, `showSelectedIcon: false` |
| 3 | `SegmentedButton<RecruitDurationBand>` | `전체 / 1시간 안 / 하루 안 / 며칠`, `showSelectedIcon: false` |
| 4 | `TextButton`(오른쪽 정렬) | **조건이 하나라도 걸려 있을 때만** 보이는 `조건 지우기`(`PixelIcons.close`). 검색어와 두 축을 한 번에 되돌린다(spec "필터는 한 번에 풀 수 있어야 한다") |

- `showSelectedIcon: false`는 선택 사항이 아니다. 테마가 `selectedIcon: PixelIcon(check)`를 주므로 그대로 두면 4칸 기간대 줄에서 체크 아이콘이 라벨 폭을 먹고 글자가 잘린다(`create_battle_screen`·`judgment_section`의 선례와 같은 처리).
- 조작 영역 아래 경계는 `main_shell`이 쓰는 방식과 같은 2dp `ColoredBox(color: RetroPalette.ink)` 한 줄로 긋는다. 새 컴포넌트를 만들지 않는다.

**스크롤 목록**(`RefreshIndicator` 안, `ListView.builder`, `physics: AlwaysScrollableScrollPhysics`, `keyboardDismissBehavior: onDrag`, 아래 패딩 96으로 FAB가 마지막 카드를 가리지 않게)

| 슬롯 | 내용 |
|---|---|
| 맨 앞(조건부) | **모집 중 안내 배너** — `myLimits.hasPending`일 때만. `PixelFrame.tone(tone: PixelTone.info)` + 문구 + `내 모집 보기` 버튼(누르면 `selectedTabProvider`로 내 대결 탭 전환). 목록 안에 두므로 스크롤하면 올라간다 |
| 본문 | `_OpenRecruitCard`(현재 코드 그대로: 제목 · 유형 배지 · 기간 태그 · 기준 미리보기 2줄). 카드 → 상세 시트 → 참가 → VS 인트로 → 내 대결 탭 흐름 **변경 없음** |
| 꼬리 | 이어 불러오는 중이면 `StatusMessage.loading()`, 이어 불러오기가 실패했으면 `StatusMessage.error(message: 다음 목록을 불러오지 못했어요, action: TextButton(다시 시도))`, 더 없으면 **아무것도 두지 않는다**(spec: 끝을 알리는 요란한 장치 없음) |

**목록이 비었을 때 — 세 가지를 다른 화면으로 구분한다.** 배너 슬롯은 그대로 두고 본문 자리에 `StatusMessage`를 놓는다.

| 상태 | 위젯과 내용 |
|---|---|
| 첫 묶음 로딩(이전 값 없음) | `StatusMessage.loading()` |
| 모집 0건 + **조건 없음** | `StatusMessage.empty(icon: battle, message: '아직 올라온 모집이 없어요.', detail: '내가 먼저 걸어 두면 누군가 참가할 수 있어요.', action: FilledButton('대결 만들기'))`. 단 `hasPending`이면 그 버튼 대신 `TextButton('내 모집 보기')` — 막힌 버튼을 권하지 않는다 |
| 0건 + **조건 있음** | `StatusMessage.empty(message: '조건에 맞는 모집이 없어요.', detail: '검색어나 필터를 바꿔 보세요.', action: FilledButton('조건 지우기'))`. **여기서 `대결 만들기`를 권하지 않는다**(spec) |
| 첫 묶음 실패 | `StatusMessage.error(message: AppStrings.battleLoadRecruitsFailed, action: TextButton(다시 시도))` |

함정: `StatusMessage(fill: true)`는 내부가 기본 physics의 `SingleChildScrollView`라 **당겨서 새로고침이 먹지 않는다.** 세 빈 상태 모두 `fill: false`로 두고 `AlwaysScrollableScrollPhysics`를 가진 스크롤 뷰 안에 넣는다(`my_battles_screen`의 `_ScrollableMessage`가 같은 이유로 존재한다). spec 수용 기준 "세 가지 상태 모두에서 당겨서 새로고침이 동작한다"가 이것이다.

**없어지는 것**: `모집 중인 대결` 섹션 헤더(목록이 하나뿐이고 앱바가 이미 `대결 찾기`다), `내가 등록한 모집` 섹션과 그 안의 기준 수정·모집 취소 버튼(내 대결 탭으로 이동), `_cancel` 핸들러(같이 이동).

### 2. 내 대결 탭 (`my_battles_screen.dart` 변경)

본문은 하나의 스크롤 뷰(`RefreshIndicator` → `ListView`)이고 두 구역이 **위아래로 떨어져** 있다.

**구역 A — 내가 등록한 모집** (0건 또는 1건, 0건이면 구역 자체가 없다)

- `PixelFrame.flat(title: '내가 등록한 모집')`으로 감싼다. 제목 띠가 있는 창이 "여기부터 다른 성격"을 말하므로 구분선을 따로 긋지 않는다.
- 안쪽: 제목(bodyLarge w600, 2줄) + `BattleTypeBadge` + `PixelTag(모집 중, battleStatusTagStyle('pending'))`(점선 = 빈 자리) + `기간` 태그 + 보조 한 줄 `아직 아무도 참가하지 않았어요.` + 오른쪽 아래 `기준 수정`(OutlinedButton → `EditRecruitCriteriaScreen`) / `모집 취소`(TextButton).
- 보조 한 줄을 두는 이유: spec이 "'아직 아무도 안 들어왔다'는 사실 자체가 그 구역의 의미"라고 적었고, 진행 중 카드의 상태 줄과 같은 자리에 같은 역할로 들어간다. 새 기능이 아니라 이 구역의 설명이다.
- 상태: 로딩이고 이전 값이 없으면 구역 자리에 `StatusMessage.loading()`, 실패면 `StatusMessage.error(message: AppStrings.battleLoadRecruitsFailed, action: TextButton(다시 시도))`. 진행 중 목록은 그와 무관하게 그려진다(한 구역의 실패가 다른 구역을 가리지 않는다).
- `모집 취소` 성공 → `myRecruitsProvider`·`myLimitsProvider` 무효화 → 구역이 사라지고 새 모집을 만들 수 있는 상태가 된다(현재 찾기 탭 핸들러를 그대로 옮긴 것, 문구도 그대로).

**구역 B — 진행 중인 대결**

- 현재 `BattleSummaryList`의 카드들을 그대로 쓴다. 상대·유형·상태 칩·상태 한 줄·상세 진입 모두 변경 없음. `BattleSummaryList`는 자체 `ListView`였으므로 바깥 스크롤 뷰 안에 들어가도록 **카드 목록을 돌려주는 형태로 바꾼다**(스크롤 뷰 중첩 금지). 머리글은 두지 않는다 — 탭 이름이 이미 `내 대결`이고, 이 목록이 지금과 똑같이 보이는 것이 변화가 가장 적다.
- 빈 상태 규칙:
  - 진행 중 0건 **+ 모집도 0건** → 지금 문구·행동 그대로(`battleMyBattlesEmpty` + `battleFinishedInProfile` + `대결 찾기` 버튼).
  - 진행 중 0건 **+ 모집 1건** → "비었다"가 아니다(spec). CTA 없는 한 줄 `진행 중인 대결은 아직 없어요.`(bodySmall, 흐린 글자)만 둔다. 모집 구역이 이미 "기다리는 중"을 말하고 있으므로 찾기 탭으로 보내는 버튼을 두 번 권하지 않는다.
- 당겨서 새로고침은 **두 provider를 함께** 갱신한다(`myBattlesProvider`, `myRecruitsProvider`).
- **대결 만들기 진입점을 이 탭에는 두지 않는다.** spec이 설계에 맡긴 선택이고, 두면 한도 안내(동의·모집 1개·하루 1대결)를 두 자리에서 똑같이 해야 한다. "마음에 드는 모집이 없다"는 판단은 목록을 보는 자리에서 나오므로 진입점은 찾기 탭 FAB 하나로 둔다.

### 3. 모집을 만든 직후 / 만들기가 막혔을 때

- **만든 직후**: `create_battle_screen`이 성공하면 `myRecruitsProvider`·`myLimitsProvider`를 무효화하고 → `Navigator.pop()` → **`selectedTabProvider`를 내 대결 탭으로 전환** → 기존 스낵바(`battleRecruitSubmitted`). 순서가 중요하다(pop 뒤에 탭을 바꿔야 push된 화면이 남지 않는다). 참가 성공 뒤에 내 대결 탭으로 보내는 기존 흐름(`_openRecruit`)과 같은 모양이고, "올린 모집이 어느 화면에도 보이지 않는 구간"을 0으로 만든다. 찾기 탭의 검색어·필터·스크롤 위치는 `IndexedStack` 덕에 그대로 남는다. 모집을 만드는 것은 남의 모집 목록을 바꾸지 않으므로 **피드는 무효화하지 않는다**(지금 코드가 `openRecruitsProvider`를 무효화하던 것은 내 모집 섹션이 같은 화면에 있었기 때문이다).
- **막혔을 때(이미 모집 중)**: 두 겹으로 알린다. ① 찾기 탭 목록 맨 앞의 안내 배너(상시, `hasPending`일 때) — 이유와 `내 모집 보기` 버튼. ② FAB를 눌렀을 때 `myLimits`가 이미 `hasPending`이면 생성 화면으로 보내지 않고 그 자리에서 스낵바(사유 + `보러 가기` 액션 → 탭 전환)를 띄운다. 다른 사유(동의 없음·하루 한도·기준 생성 횟수)는 지금처럼 생성 화면의 사전 안내(`createBattleBlockMessage`)가 맡는다 — 그 사유들은 "내 모집이 어디 있나"와 무관하다.

---

## 데이터 흐름

### provider 구성

| provider | 종류 | 역할 |
|---|---|---|
| `recruitFilterProvider` | `NotifierProvider.autoDispose<RecruitFilter, RecruitQuery>` | **적용된** 조건 하나(`query`, `type`, `band`). `setQuery`/`setType`/`setBand`/`reset` |
| `openRecruitFeedProvider` | `AsyncNotifierProvider.autoDispose<OpenRecruitFeed, RecruitFeed>` | `build()`에서 `ref.watch(recruitFilterProvider)` → 첫 묶음. `loadMore()` 하나만 더 공개 |
| `myRecruitsProvider` | 그대로(`FutureProvider.autoDispose<List<Battle>>`) | 읽는 방식 변경 없음(spec). 보는 화면만 내 대결 탭으로 바뀐다 |
| `myLimitsProvider` | 그대로 | 배너·FAB 분기에 쓴다 |
| `openRecruitsProvider` | **삭제** | 피드 provider로 대체 |

```dart
class RecruitFeed {
  final List<OpenRecruit> items;
  final RecruitCursor? cursor;   // 마지막으로 받은 행의 커서(서버가 준 문자열 그대로)
  final bool hasMore;
  final bool loadingMore;
  final int moreErrorCount;      // 이어 불러오기 실패 횟수(토스트 한 번만 띄우는 신호)
}
```

- **조건이 바뀌면 `build()`가 다시 돈다** → 커서·목록이 통째로 버려지고 첫 묶음부터 시작한다. "검색어를 지우면 전체 목록으로 돌아온다", "필터 결과도 무한 스크롤로 이어진다"가 이 한 줄에서 나온다.
- `when()`의 기본값(`skipLoadingOnRefresh: true`)에 기대, 조건을 바꾸는 동안에는 **이전 목록을 그대로 두고** 전체 로더로 갈아타지 않는다. 타이핑마다 목록이 사라지는 깜빡임을 막는다. 전체 로더는 이전 값이 없는 첫 진입에서만 보인다.
- `moreErrorCount`가 늘어나는 것을 화면이 `ref.listen`으로 보고 스낵바를 한 번 띄운다(CLAUDE.md "에러는 삼키지 않는다": `debugPrint` + 토스트 + 꼬리의 재시도). notifier에서 직접 스낵바를 띄울 수 없어 신호를 상태에 둔다.
- **이어 불러오기 실패에 `AsyncError`를 쓰지 않는다.** `state = AsyncError(...)`로 두면 `when`의 error 갈래로 떨어져 이미 본 목록이 통째로 사라진다 — spec이 "가장 나쁜 결과"로 지목한 것이다. 실패는 `AsyncData`를 유지한 채 `moreErrorCount`만 올린다.

### 흐름 1. 첫 묶음

1. 화면이 `openRecruitFeedProvider`를 `watch` → `build()`가 `recruitFilterProvider`를 읽고 `BattleRepository.fetchOpenRecruits(limit: 20, cursor: null, query·type·band)` 호출.
2. RPC `list_open_recruits` → 최신 20건.
3. `OpenRecruitPage`(아래 "API 계약") → `RecruitFeed(items, cursor: 마지막 행의 커서, hasMore: rows.length == 20)`.

### 흐름 2. 이어 불러오기

1. `ListView.builder`의 `itemBuilder`가 `index >= items.length - 3`인 항목을 만들 때 `loadMore()`를 **예약**한다(`Future.microtask`). 빌드 중에 상태를 바꾸면 Flutter가 터지므로 동기 호출하지 않는다. 스크롤 리스너 대신 `itemBuilder`를 쓰는 이유는 카드 높이가 제목·기준 길이에 따라 달라 픽셀 기준 임계값이 불안정하기 때문이다.
2. `loadMore()`는 `loadingMore`거나 `hasMore`가 false면 즉시 돌아온다(수용 기준 "더 불러올 모집이 없으면 같은 요청을 반복하지 않는다").
3. `loadingMore = true` → 같은 조건 + 커서로 RPC → 성공 시 **이미 있는 `battle.id`를 건너뛰며** 뒤에 붙이고 커서·`hasMore` 갱신.
4. 실패: `loadingMore = false`, `moreErrorCount++`. **목록·커서는 그대로** 두므로 꼬리의 `다시 시도`가 같은 커서로 다시 부른다.
5. 세대 가드: `build()`가 돌 때마다 `_generation++`하고, `loadMore()`는 호출 시점의 세대를 잡아 응답을 쓰기 전에 비교한다. 당겨서 새로고침이 날아온 사이에 돌아온 옛 묶음이 새 목록을 덮지 않게 한다(`AsyncNotifier`는 무효화돼도 같은 인스턴스에서 `build()`만 다시 돈다). ③의 id 중복 건너뛰기는 그 방어의 두 번째 겹이다.

### 흐름 3. 검색어 입력 (호출 빈도)

1. `TextEditingController`는 **화면(`ConsumerStatefulWidget`)의 State**에 둔다. 지금 입력 중인 글자는 provider에 넣지 않는다 — 글자마다 피드가 다시 돌면 안 된다.
2. `onChanged` → 화면의 `Timer`를 300ms로 다시 건다(`dart:async`만 쓴다, 새 패키지 없음). 타이머가 끝나면 `recruitFilterProvider.setQuery(text)`.
3. `setQuery`는 `btrim`한 값이 **지금 적용된 값과 같으면 아무것도 하지 않는다.** 한글 IME는 자모 조합 중에도 `onChanged`를 쏘므로(한 글자에 2~3번) 이 비교가 호출을 한 번으로 줄인다. 서버도 `btrim`을 하므로 공백만 더한 입력은 새 요청이 되지 않는다.
4. 즉시 적용하는 두 경우: 키보드 검색 버튼(`onSubmitted`) → 타이머 취소 후 바로 적용, `X` 버튼 → 바로 빈 조건으로.
5. `dispose()`에서 타이머를 취소한다.

**결과적인 호출 빈도**: "설거지"(3글자)를 또박또박 입력하면 입력이 멈춘 뒤 **1회**. 중간에 멈춰 가며 치면 멈춘 횟수만큼. 글자마다 부르지 않는다.

### 흐름 4. 수명 (`IndexedStack` 때문에 생기는 것)

탭은 `IndexedStack`이라 `BattleRecruitsScreen`이 계속 살아 있고, 그래서 `autoDispose`는 **로그아웃으로 셸이 내려갈 때까지 아무것도 버리지 않는다.** 결정은 이렇다.

| 상태 | 어디에 | 언제 버려지나 | 근거 |
|---|---|---|---|
| 입력 중인 검색어 | 화면 State의 컨트롤러 | 로그아웃(셸 해제) | 탭을 오가도 입력이 남는 것이 `IndexedStack`을 쓴 의도다(셸 주석) |
| 적용된 조건 | `recruitFilterProvider` | 피드와 함께(로그아웃) | 조건과 목록이 따로 버려지면 "조건은 걸려 있는데 목록은 전체"가 된다 |
| 받은 묶음·커서 | 피드 provider의 상태 | 로그아웃, 당겨서 새로고침, 조건 변경, 참가 성공 | 아래 |
| 스크롤 위치 | `ListView` | 같음 | |

- **찾기 탭에 들어올 때 피드를 자동으로 다시 읽지 않는다.** 스크롤을 다섯 묶음까지 내려둔 사용자가 다른 탭을 들렀다 왔을 때 목록이 첫 묶음으로 되감기면 보던 자리를 잃는다. 새 모집을 받는 길은 **당겨서 새로고침**이고, 오너가 오늘 그 길을 넣은 이유도 같다. (`myBattlesProvider`는 지금처럼 탭 진입마다 무효화한다 — 그쪽은 페이징이 없고 "지금 내가 해야 할 일"이 바뀌어 있을 수 있다.)
- **`main_shell`의 탭 진입 리스너에 두 줄을 더한다**: `myBattles` 진입 시 `myRecruitsProvider`도 무효화(내가 자리를 비운 사이 모집이 매칭돼 구역 A → 구역 B로 옮겨가 있을 수 있다), `find` 진입 시 `myLimitsProvider` 무효화(배너·FAB 분기가 `hasPending`에 걸려 있고, 그 값은 서버에서 바뀐다). 피드는 포함하지 않는다.
- 참가 성공(`_openRecruit`) 뒤에는 피드를 무효화한다. 참가한 모집은 사라졌어야 하고, 사용자는 곧바로 내 대결 탭으로 이동하므로 첫 묶음으로 되감겨도 잃는 것이 없다.

---

## API 계약

### RPC

| 함수 | 파라미터 | 반환 | 조치 |
|---|---|---|---|
| `list_open_recruits` | `p_limit integer, p_cursor_created_at timestamptz, p_cursor_id uuid, p_query text, p_type text, p_duration_band text`(모두 기본값 있음) | `setof jsonb`, 행마다 `{battle, creator}`(**키 변경 없음**) | **드롭 후 재생성** + 부분 인덱스 |
| 그 밖의 모든 RPC | - | - | **변경 없음** |

### Dart 데이터 계층

```dart
const openRecruitPageSize = 20;

class RecruitCursor {        // 서버가 준 문자열을 그대로 보관한다
  final String createdAt;    // battle.created_at (ISO 문자열 원문)
  final String id;
}

class OpenRecruitPage {
  final List<OpenRecruit> items;
  final RecruitCursor? nextCursor;
  final bool hasMore;
}

Future<OpenRecruitPage> fetchOpenRecruits({
  int limit = openRecruitPageSize,
  RecruitCursor? cursor,
  String? query,            // 비었으면 null로 보낸다
  String? type,             // RecruitTypeFilter.serverValue
  String? durationBand,     // RecruitDurationBand.serverValue
});
```

- **커서는 `DateTime`으로 파싱하지 않는다.** 서버가 보낸 `created_at` 문자열을 날 것 그대로 들고 있다가 그대로 되돌려 보낸다. `DateTime`을 거치며 초 단위로 깎이거나 포맷이 바뀌면 `(created_at, id) < (커서)` 비교의 경계가 흔들려 **그 사이 행이 조용히 빠지거나 두 번 나온다.** 이것이 이 기능에서 가장 조용하게 깨지는 지점이다(`Battle.createdAt`은 화면 표시용으로 그대로 파싱해 쓰고, 커서로는 쓰지 않는다).
- `hasMore = rows.length == limit`. 마지막 묶음이 정확히 20건이면 다음 호출이 0건을 받고 그때 `hasMore = false`가 된다 — 빈 요청 한 번이 드는 대신 서버가 `count`를 세거나 한 건을 더 읽는 일을 하지 않는다. 중복·누락과는 무관하다.
- `OpenRecruit`·`PlayerCard`·`Battle`은 **변경 없음**.

### 도메인(순수 함수 — 유닛 테스트 대상)

| 이름 | 내용 |
|---|---|
| `enum RecruitTypeFilter { all, speed, quality }` | `serverValue`(all → null), `label` |
| `enum RecruitDurationBand { all, quick, day, multi }` | `serverValue`(all → null), `label`. **분 경계는 담지 않는다**(서버 소유) |
| `class RecruitQuery` | `query`/`type`/`band`, `hasAnyCondition`, `==`/`hashCode`(불필요한 재조회를 막는 비교에 쓴다) |
| `RecruitEmptyKind recruitEmptyKind({required bool hasItems, required bool hasAnyCondition})` | `none`(빈 상태 아님) / `noRecruits` / `noMatches` — 빈 상태 3종 중 둘을 고르는 분기(세 번째는 `AsyncValue.error`가 고른다) |
| `OpenRecruitPage.fromRows(List rows, int limit)` | 행 파싱 + 커서 추출 + `hasMore` 계산 |

### 오류

새 사용자용 오류 코드는 만들지 않는다. `BAD_PAGE_REQUEST`는 클라이언트 버그에서만 나오므로 `criteriaErrorMessage`의 기본 갈래(`battleErrorUnknown`)에 맡기고, 목록 불러오기 실패는 지금처럼 `battleLoadRecruitsFailed`(첫 묶음) / 새 문구(이어 불러오기)로 말한다.

---

## 문자열 (`lib/core/strings.dart`)

| 추가 | 값 |
|---|---|
| `battleSearchHint` | `제목으로 찾기` |
| `battleFilterAll` | `전체` |
| `battleDurationBandQuick` / `...Day` / `...Multi` | `1시간 안` / `하루 안` / `며칠` |
| `battleFilterClear` | `조건 지우기` |
| `battleRecruitsEmptyNone` / `...NoneHint` | `아직 올라온 모집이 없어요.` / `내가 먼저 걸어 두면 누군가 참가할 수 있어요.` |
| `battleRecruitsEmptyFiltered` / `...FilteredHint` | `조건에 맞는 모집이 없어요.` / `검색어나 필터를 바꿔 보세요.` |
| `battleRecruitsLoadMoreFailed` | `다음 목록을 불러오지 못했어요.` |
| `battleMyRecruitWaiting` | `아직 아무도 참가하지 않았어요.` |
| `battleMyRecruitGo` | `내 모집 보기` |
| `battleMyRecruitBlocked` | `이미 모집 중인 대결이 있어요. 취소하거나 매칭된 뒤에 새로 올릴 수 있어요.` |
| `battleNoActiveBattlesYet` | `진행 중인 대결은 아직 없어요.` |

| 없어지는 것 | 이유 |
|---|---|
| `battleOpenRecruits`(`모집 중인 대결`) | 찾기 탭이 목록 하나가 되어 섹션 헤더가 없다 |
| `battleRecruitsEmpty`(`모집 중인 대결이 없어요.`) | 빈 상태가 셋으로 갈려 이 문구를 쓰는 자리가 없다 |

`battleMyRecruits`(`내가 등록한 모집`)는 내 대결 탭 구역 A의 제목으로 **그대로** 쓴다. 기존 오류·한도 문구(`battleErrorPendingExists` 등)는 손대지 않는다.

---

## 테스트 전략

| 무엇 | 어디서 | 수단 |
|---|---|---|
| 커서 페이징의 중복·누락 없음, 제목 부분 일치, 유형·기간대 필터, 정렬, 인자 검증, 권한 | **DB** | `supabase/tests/recruit_browse_smoke.sql`(원격 `supabase db query --linked -f`, 마지막에 예외로 롤백 — 기존 스모크와 같은 형식) |
| 조건 → 서버 인자 매핑, 라벨, 빈 상태 분기, 커서 추출·`hasMore` | Dart 순수 함수 | `flutter test` 유닛 |
| 피드 notifier 동작(첫 묶음·이어 붙이기·끝에서 멈춤·실패 시 목록 보존·중복 id 무시·조건 변경 시 되감기·세대 가드) | Dart | `flutter test` + `ProviderContainer` + 가짜 `BattleRepository` |
| 검색 디바운스(글자마다 부르지 않음), 필터 조작, 꼬리 로딩·재시도, 빈 상태 3종, 조건 지우기, 내 대결 탭 두 구역 | Dart 위젯 | `flutter test`(`battleRepositoryProvider` 가짜 + `tester.pump(Duration(milliseconds: 300))`) |
| 30건 스크롤 체감, 실기기 키보드·IME | 실기기 | 오너 수동 확인 |

**SQL 테스트가 필요한 이유**: 중복·누락 없음은 "묶음 사이에 행이 생기고 사라지는" 상황에서만 드러나고, 그 상황을 만들 수 있는 곳은 DB뿐이다. Dart 쪽 가짜 repository로는 커서 비교의 정확성을 확인할 수 없다.

### `recruit_browse_smoke.sql` 필수 케이스

- **중복**: 모집 5건 → 2건 받고, 그 사이 새 모집 1건 insert → 커서로 다음 2건 → 두 묶음에 같은 id가 없고, 새 모집은 두 묶음 어디에도 없다.
- **누락**: 2건 받고, 아직 안 본 행 하나를 `join_battle`로 매칭시킨 뒤 다음 묶음 → 남은 행이 전부 나온다(건너뛴 행 0).
- **동률**: `created_at`이 같은 두 행을 넣고 묶음 크기 1로 두 번 받아 → 두 행이 한 번씩, `id desc` 순서로 나온다.
- **정렬**: 최신 모집이 첫 행이다.
- **검색**: 중간 글자("설거지하기"에서 `거지`), 앞뒤 공백(`  설거지  `), 영문 대소문자(`Gym` vs `gym`), **`%`·`_`를 넣은 검색어가 와일드카드로 작동하지 않는다**(`%`만 입력 → 0건), 기준 문구·생성자 이름으로는 찾히지 않는다.
- **유형**: `speed`/`quality`/null 각각의 건수.
- **기간대 경계**: 60·61·1440·1441 그리고 하한 1·상한 10080이 `quick`/`day`/`multi`에 정확히 한 번씩 들어간다.
- **조합**: 검색어 + 유형 + 기간대를 함께 걸어도 세 조건이 모두 적용된다(검색이 필터를 풀지 않는다).
- **내 모집 제외**: 내가 만든 `pending` 모집은 어떤 조건에서도 나오지 않는다.
- **인자 검증**: `p_limit` 0·51·null, `p_type = 'speedy'`, `p_duration_band = 'week'`, 커서 한쪽만 채움 → 각각 예외.
- **권한**: `anon` 롤로 호출하면 `insufficient_privilege`. 옛 0-인자 오버로드가 남아 있지 않다(인자 없는 호출이 기본값으로 새 함수에 붙어 20건을 돌려준다).

### 기존 테스트에 생기는 영향(그대로 두면 깨진다)

- `supabase/tests/custom_duration_smoke.sql`·`join_battle_smoke.sql`은 `list_open_recruits()`를 인자 없이 부르고 반환 순서에 기대지 않으므로 **기본값 덕에 그대로 통과한다.** 다만 두 파일 모두 모집이 20건 미만일 때만 그렇다는 사실을 주석으로 남긴다.
- `test/widget_test.dart`, `test/features/battle/{ai_consent_test,battle_join_vs_intro_test,recruit_sheet_test}.dart`는 `openRecruitsProvider`/`myRecruitsProvider`를 override해 `BattleRecruitsScreen`을 띄운다. provider가 없어지므로 **준비 코드를 함께 고쳐야 한다.** 가장 적은 변화는 provider override를 지우고 가짜 `BattleRepository.fetchOpenRecruits`가 빈 `OpenRecruitPage`를 돌려주게 하는 것이다(그러면 피드가 실제 notifier를 거쳐 페이징·빈 상태까지 같은 테스트에서 돈다). 찾기 탭은 더 이상 내 모집을 읽지 않으므로 그 화면 테스트에서 `myRecruitsProvider` override는 필요 없어진다.

---

## 오너가 손수 해야 할 일

1. 마이그레이션 1건의 **원격 적용 승인**(적용은 메인 세션, `supabase db push` 또는 `db query`). 적용 전까지 앱의 새 호출은 전부 실패한다 — 적용과 앱 변경은 같은 단계에 묶인다.
2. 적용 후 `supabase db query --linked -f supabase/tests/recruit_browse_smoke.sql`로 스모크 확인.
3. 실기기에서 더미 30건으로 확인할 것: 두 번째 묶음이 이어지는지, 한글 IME로 검색할 때 목록이 덜컥거리지 않는지, 기간대 4칸 세그먼트 라벨이 잘리지 않는지.

새 시크릿·새 Edge Function·새 cron·새 패키지는 없다.

---

## 결정 완료 (오너, 2026-10-28)
메인 세션이 오너에게 직접 물어 받은 답이다. 구현은 이 결론을 전제로 한다. 아래 "결정 필요"는 기록으로만 남긴다.

1. **모집 생성 직후 내 대결 탭으로 전환한다.** 설계안 그대로. 찾기 탭에서 내 모집이 사라진 것처럼 느끼는 구간을 만들지 않는 쪽이 우선이다.
2. **기간대는 3구간**(`quick ≤60분` / `day 60<d≤1440` / `multi >1440`, 라벨 "1시간 안·하루 안·며칠"). 30분 이하를 떼는 4구간은 하지 않는다 — 필터 축이 둘뿐인 화면에서 선택지를 늘리면 결과 0건이 늘어난다.
3. **찾기 탭 진입 시 자동 갱신하지 않는다.** 스크롤 위치와 검색·필터 조건을 보존한다. 새 모집은 당겨서 새로고침으로 받는다(그 수단은 2026-10-28에 넣었다 — 없을 때는 새 모집이 영영 안 보이는 버그였다).

---

## 결정 필요

1. **모집을 만든 직후 내 대결 탭으로 자동 전환해도 되는가?**
   설계는 전환하기로 했다(참가 성공 흐름과 같은 모양이고, "올린 모집이 어디에도 안 보이는 구간"을 0으로 만든다). 대신 사용자가 찾기 탭에서 하던 일(검색 조건은 남지만 보던 화면은 아님)이 끊긴다. 전환 대신 **찾기 탭에 머물면서 스낵바 + 배너로만** 알리는 쪽을 원하면 그렇게 바꾼다 — 그때는 "어느 화면에도 안 보이는 구간"이 사용자가 탭을 옮기기 전까지 남는다.

2. **기간대를 3구간(`1시간 안` / `하루 안` / `며칠`)으로 두는 데 동의하는가?**
   spec은 축을 둘로 제한했지만 구간 수와 경계는 설계에 맡겼다. 설계는 60분·1440분을 경계로 3구간을 택했다. 더미 데이터에 5분·30분짜리가 많았으므로 "지금 당장(30분 이내)"을 따로 떼어 4구간으로 하는 선택도 있다 — 다만 세그먼트가 5칸이 되어 한 줄에 들어가지 않고, 구간이 좁아질수록 결과 0건이 늘어난다.

3. **찾기 탭에 들어올 때 목록을 자동으로 다시 읽지 않는 데 동의하는가?**
   설계는 자동 갱신을 넣지 않았다(스크롤 위치와 조건을 지키고, 새 모집은 당겨서 새로고침으로 받는다). "탭에 들어올 때마다, 단 조건이 없고 스크롤이 맨 위일 때만 자동 갱신"처럼 조건부로 넣을 수는 있다. 자동 갱신이 없으면 앱을 켜 둔 채 탭만 오가는 동안에는 새 모집이 보이지 않는다.
