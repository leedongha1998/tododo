# nickname 설계

## 참고

- spec.md: `docs/specs/nickname/spec.md`. **이 설계의 유일한 요구사항이다.** 맨 끝 "오너 결정 (2026-11-24)" 8건이 전제다. 다시 선택지로 열지 않는다.
- 형식 참고: `docs/specs/bot-battle/design.md`
- 읽어서 확인한 현재 구현(추측이 아니다):
  - `supabase/migrations/20260818220000_profiles_and_todos.sql`: `profiles` DDL, 정책 두 개(select `using (true)` / **update `auth.uid() = id`, 컬럼 제한 없음**), 첫 `handle_new_user`.
  - `20260915120100_ai_judge_schema.sql:171`: **가장 늦은 `handle_new_user`**. `coalesce(raw_user_meta_data->>'full_name', email)`로 이름을 채우고 `player_stats` 행을 만든다. 그 뒤로는 재정의가 없다.
  - `20260902213000_delete_account.sql:18`: `profiles.id`의 `auth.users` FK를 해제했다. 그래서 묘비와 봇 행이 있을 수 있다.
  - `20261116120000_notification_dismiss.sql:213`: **가장 늦은 `delete_account`**. 8번 단계가 `display_name = '탈퇴한 사용자'`로 바꾼다.
  - `20261120120000_bot_battle_schema.sql:63`: 봇 profiles 행(`bot_user_id()`, `연습 봇`, `deleted_at` null, `player_stats` 없음). `bot_battle_topics`가 쓴 "RLS 켜고 정책 0개 + `revoke all`" 패턴을 이 설계도 쓴다.
  - 앱에서 `profiles`를 부르는 곳은 **select 세 곳뿐이다**: `profile_repository.dart:14`(`fetchMyProfile`), `:55`(`fetchDisplayNames`), `battle_repository.dart:103`(`fetchDisplayNames`). update·insert·delete는 **한 곳도 없다**. Edge Function(`supabase/functions/**`)은 `profiles`를 아예 부르지 않는다. 서버에서 `profiles`를 고치는 곳은 SECURITY DEFINER인 `delete_account` 하나다(§4.2).
  - 이름이 화면에 쓰이는 곳: `list_open_recruits`/`get_player_card`가 주는 `display_name`(모집 목록·상대 전적 카드), `battle_providers.dart`의 `fetchDisplayNames`(내 대결 목록·대결 상세), `profile_providers.dart`(지난 대결·프로필 머리), `vs_intro.dart`(`opponentName`/`myName`, 이름이 `나`/`상대`와 같으면 자리 이름을 숨긴다 — `vs_intro.dart:243`), `InitialBadge`(첫 글자).
  - 관문: `AuthGate`(`auth_gate.dart:145`)는 세션이 있으면 **바로** `MainShell`을 띄운다. AI 동의는 첫 실행 관문이 아니다. 사람 대결의 모집·참가 직전에 `ensureAiConsent`가 띄운다(`ai_consent_screen.dart:16`). 지금은 첫 실행에 걸리는 관문이 하나도 없다.
  - 오류 코드 관례: RPC가 `raise exception using message = '…', hint = 'CODE'`로 던지고, 앱은 `PostgrestException.hint`로 읽는다(`submission_rules.dart:9`).
  - `privacy.html`(`C:\workspaces\todododo-legal`, 읽기만 했다) 1-가·3·4절과 `DEPLOY.md` 5절의 지금 문구.
- 로컬 Docker가 없어 마이그레이션은 원격에 적용한다. **단계마다 오너가 확인한다**(§12).

---

## 설계 원칙 (5가지)

1. **규칙은 한 함수에만 있다.** 정규화와 검사는 `public.check_nickname()` 하나에 있고, 쓰기 네 경로가 전부 이 함수를 지난다. 네 경로는 관문 확정, 프로필에서 바꾸기, 새 계정의 기본 별명, 기존 사용자 일괄 덮기다. 앱은 규칙을 **재현하지 않는다**. P0에서 앱은 서버가 돌려준 코드를 문구로 바꾸기만 한다.
2. **쓰는 문은 하나다.** `profiles`의 UPDATE 정책을 없애고 테이블 쓰기 권한도 회수한다. 사용자가 이름을 바꾸는 길은 `set_nickname()` 하나다.
3. **단어표는 서버에만 있다.** 무작위 별명은 SQL 함수가 만든다. 앱에는 형용사·명사·예약어·금칙어 목록이 한 글자도 없다. 그래서 두 곳에 갈라질 일이 없다.
4. **남에게 보이면 안 되는 상태는 `profiles`에 두지 않는다.** `profiles`는 로그인한 누구나 **행 전체**를 읽는다. "언제 별명을 확정했나", "서버가 이름을 덮었나"를 거기에 두면 남의 변경 시점이 보인다. spec 범위 밖인 "변경 이력 보기"에 반쯤 해당한다. 그래서 본인만 RPC로 읽는 별도 테이블에 둔다(§1.2).
5. **관문은 편의이고 안전망은 서버다.** 실명 노출은 기본 별명(P0-1)과 일괄 덮기(P0-2)가 서버에서 끝낸다. 관문 화면이 실패해도 노출은 다시 생기지 않는다. 그래서 관문 조회가 실패하면 본 화면으로 통과시킨다(§7.1, 결정 필요 1).

---

## CLAUDE.md 도메인 규칙 대조

| 조항 | 판단 | 이 기능에서 |
|---|---|---|
| 판정 로직·상태 전이·점수 | 무관 | 대결 테이블·함수를 하나도 건드리지 않는다 |
| 사용자 FK는 `public.profiles` | 유지 | 새 테이블 `nickname_states.user_id` → `public.profiles(id) on delete cascade` |
| 탈퇴는 묘비(`탈퇴한 사용자`) | 유지 | `delete_account`의 묘비화를 그대로 둔다. 거기에 `nickname_states` 삭제 한 줄만 더한다(§6.3). 사람은 `탈퇴`가 든 이름을 쓸 수 없게 된다 |
| 봇은 `profiles` 한 행, 사람처럼 보이지 않는다 | 유지 + 강화 | 봇 행을 덮지 않는다. 사람은 `연습봇`이 든 이름을 쓸 수 없다 |
| RLS 정책은 테이블 만들 때 같이 | 유지 | 새 테이블 셋 모두 **RLS 켜고 정책 0개 + `revoke all`**이다. `bot_battle_topics`와 같은 모양이고, 읽는 길은 RPC뿐이다 |
| 새 RPC: `revoke … from public, anon` + `grant … to authenticated` | 유지 | §6.1 |
| SECURITY DEFINER 첫 줄 로그인 가드 | 유지 | 사용자 RPC 셋 모두. 내부 함수는 DEFINER가 아니고(invoker) 사용자 롤에서 실행 권한을 회수한다 |
| 에러는 삼키지 않는다 | **예외 1건 제안** | 관문 상태 조회 실패만 `debugPrint` 후 통과한다(결정 필요 1). 확정 실패·바꾸기 실패는 화면에 알린다 |
| 문구는 `strings.dart` | 유지 | §9 |
| 다국어 금지 | 유지 | 규칙은 한국어 사용자 기준 하나다(한글·영문·숫자) |
| 범위 밖 미래 대비 금지 | 유지 | 고유 핸들·변경 이력·검색 인덱스·신고 대상 구조를 만들지 않는다 |

---

## 1. 데이터 모델

### 1.1 `profiles` — 컬럼을 더하지 않는다

`display_name`이 그대로 "별명"이다. 컬럼 이름은 바꾸지 않는다. 바꾸면 옛 앱(`select()` 후 `row['display_name']`)과 RPC 셋(`list_open_recruits`·`get_player_card`·지난 대결)이 깨지기 때문이다. 컬럼을 하나도 더하지 않는 이유는 원칙 4다.

**컬럼 단위 select 권한(`grant select (id, display_name, …)`)으로 가리는 길은 쓸 수 없다.** 옛 앱은 `.select()`(= `select *`)로 읽으므로, 컬럼 권한을 거는 순간 옛 앱의 프로필 조회가 권한 오류로 죽는다. spec P0-2는 "옛 버전 앱 사용자도 이 순간"을 요구한다. 옛 앱이 계속 동작해야 한다.

### 1.2 `nickname_states` (신규)

```sql
create table public.nickname_states (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  confirmed_at timestamptz,   -- 사용자가 set_nickname으로 마지막에 확정한 시각. null이면 관문이 뜬다
  reset_at timestamptz        -- 서버가 사용자 대신 이름을 덮은 시각(§5 일괄 덮기). null이면 그런 적 없다
);
alter table public.nickname_states enable row level security;
-- 정책 0개. 읽는 길은 get_my_nickname_state() 하나, 쓰는 길은 handle_new_user·set_nickname·§5 마이그레이션뿐
revoke all on table public.nickname_states from anon, authenticated;
```

| 경우 | 행 | 관문 | 안내 줄 |
|---|---|---|---|
| 이 기능 이후 가입 | `handle_new_user`가 `(id, null, null)`로 만든다 | 뜬다 | 없음 |
| 기존 사용자(§5가 덮음) | §5가 `(id, null, now())`로 만든다 | 뜬다 | **있음** |
| 확정함 | `confirmed_at` 채워짐 | 안 뜬다 | — |
| 행이 없음(§5 적용 전의 기존 사용자, 또는 예상 밖) | — | 뜬다(미확정으로 본다) | 없음 |
| 봇·묘비 | 만들지 않는다(묘비는 `delete_account`가 지운다) | — (로그인 경로 없음) | — |

`confirmed_at`을 횟수 제한에 쓰지 않는다(오너 결정 7). 바꿀 때마다 `now()`로 덮는 이유는 "확정했는가"만 보면 되고 값 하나로 충분하기 때문이다. 이력은 남기지 않는다.

### 1.3 `nickname_words` (신규, seed)

```sql
create table public.nickname_words (
  kind text not null check (kind in ('adjective', 'noun')),
  word text not null check (word ~ '^[가-힣]+$'),
  primary key (kind, word),
  check ((kind = 'adjective' and char_length(word) between 2 and 5)
      or (kind = 'noun'      and char_length(word) between 1 and 4))
);
alter table public.nickname_words enable row level security;
revoke all on table public.nickname_words from anon, authenticated;
```

글자 수 상한 5+1(공백)+4 = **10**이다. 그래서 어떤 조합도 길이 규칙을 넘을 수 없다. 내용은 §3.1 표다.

### 1.4 `nickname_blocked_terms` (신규, seed)

```sql
create table public.nickname_blocked_terms (
  term text primary key,                                         -- 보이는 모양(사용자에게 보여 줄 수 있는 형태)
  category text not null check (category in ('reserved', 'banned')),
  match text not null check (match in ('exact', 'contains'))
);
alter table public.nickname_blocked_terms enable row level security;
revoke all on table public.nickname_blocked_terms from anon, authenticated;
```

- **보관 위치를 테이블로 정했다.** 함수 안 배열로 두면 단어 하나를 더할 때마다 검사 함수 전체를 `create or replace`해야 한다. 테이블이면 마이그레이션 한 줄(`insert`/`delete`)로 끝난다. "운영자가 마이그레이션으로만 넣는다"는 `bot_battle_topics`와 같은 운영 모양이다.
- **앱에 내려보내지 않는다.** 금칙어 목록을 APK에 넣을 이유가 없다(원칙 3).
- **운영 규칙**(테이블 주석에 적는다): 이 테이블이나 `nickname_words`를 바꾸는 마이그레이션은 **마지막 줄에 `select public.assert_nickname_pool_valid();`**를 둔다(§3.3). 새 금칙어가 기본 별명 조합과 겹치면 그 마이그레이션이 적용 시점에 실패한다. 가입 시점에 실패하지 않게 하려는 것이다.

---

## 2. 별명 규칙 (서버가 강제)

### 2.1 정규화 — `normalize_nickname(p_raw text) returns text`

순서대로 한다.

1. `coalesce(p_raw, '')`
2. **NFC 정규화** — `normalize(…, NFC)`. 조합형 한글 자모(U+1100대)로 친 `연습봇`은 화면에서 `연습봇`과 똑같이 보인다. 이 단계가 그것을 완성형으로 합친다. 합쳐지지 않고 남는 조합형 자모는 2.2의 허용 문자 검사가 거부한다.
3. **공백류 → 공백 한 칸**: `[ \t\n\r\u00A0\u3000]+`를 `' '`로 바꾼다. 탭·줄바꿈·NBSP·전각 공백은 눈에 공백으로 보이므로 공백으로 다룬다.
4. 앞뒤 공백 제거(`btrim(…, ' ')`).

**저장값은 이 결과다.** `'  수달   왕 '` → `'수달 왕'`(수용 기준 "앞뒤 공백 제거, 연속 공백은 하나로").

> 구현 메모: Postgres ARE는 대괄호 안에서 `\uXXXX`를 받는다. 원격 DB 인코딩이 UTF8인지(`show server_encoding`)와, `[가-힣]` 같은 범위가 코드 포인트 기준으로 동작하는지는 §11 스모크의 경계 문자 케이스로 확인한다.

### 2.2 검사 순서와 결과 — `check_nickname(p_raw text, out normalized text, out code text, out term text)`

정규화 뒤 아래를 **순서대로** 보고 처음 걸린 것 하나를 돌려준다. 다 통과하면 `code`는 null이다.

| # | 검사 | 실패 코드 | `term` |
|---|---|---|---|
| 1 | `char_length(normalized) between 2 and 10`(단어 사이 공백 포함. 빈 문자열·공백만 있는 입력도 여기서 걸린다) | `NICKNAME_LENGTH` | null |
| 2 | `normalized ~ '^[가-힣ㄱ-ㅣA-Za-z0-9]+( [가-힣ㄱ-ㅣA-Za-z0-9]+)*$'` | `NICKNAME_CHARS` | null |
| 3 | 예약어(`category='reserved'`) — §2.3 비교 키로 `exact`는 같음, `contains`는 포함 | `NICKNAME_RESERVED` | 걸린 `term`(보이는 모양) |
| 4 | 금칙어(`category='banned'`) — 같은 방식 | `NICKNAME_BANNED` | **null**(§2.6) |

허용 문자 범위를 정확히 적는다.

- 완성형 한글 `U+AC00–U+D7A3`(가–힣)
- 호환 자모 `U+3131–U+3163`(ㄱ–ㅣ). "자모 포함"(오너 결정 4)이 가리키는 것이 이 범위다. **`U+3164`(한글 채움 문자, 보이지 않는다)는 범위 밖**이고, 옛 자모 `U+3165–U+318E`도 뺐다.
- ASCII 영문 대소문자, 숫자 0–9
- 단어 사이 공백 `U+0020` 한 칸. 1의 정규화가 연속 공백을 이미 한 칸으로 만들었고, 정규식이 "단어 공백 단어" 모양만 받는다.

이 허용 목록 하나로 아래가 **전부 2번에서** 거부된다. 보이지 않는 문자(U+200B·U+200C·U+200D·U+2060·U+FEFF·U+3164·U+115F·U+1160·U+FFA0), 조합형 자모, 이모지, 전각 영문(`ＡＤＭＩＮ`), 특수문자(`@`·`.`·`_`·`-`·`★`)가 여기에 든다. 그래서 이메일·웹 주소 모양은 성립하지 않는다. 휴대폰 번호(`01012345678`, 11자)는 1번에서 거부된다.

### 2.3 비교 키 — `nickname_compare_key(p_normalized text) returns text`

```sql
translate(lower(replace(p_normalized, ' ', '')), '01l', 'oii')
```

- **공백을 전부 지운다.** `연습 봇`, `연습  봇`, `연습봇`이 같은 키가 된다.
- **소문자로 만든다.** `ADMIN`, `Admin`, `admin`이 같은 키가 된다. 허용 문자가 ASCII뿐이라 `lower`가 로캘을 타지 않는다.
- **ASCII 혼동 문자 세 개를 접는다**: `0→o`, `1→i`, `l→i`. 그래서 `adm1n`, `T0D0DUDU`, `officia1` 같은 흉내가 걸린다. 예약어·금칙어 쪽 키도 **같은 함수로** 만들어 비교하므로 양쪽이 어긋나지 않는다. 이 접기는 spec 트레이드오프("비슷한 글자로 흉내 내는 길")를 영문 쪽에서만 싸게 좁힌 것이다. 한글의 비슷한 글자는 접지 않는다. 그쪽은 뚫린다고 spec이 이미 받아들였다.
- 키는 **비교에만** 쓰고 저장하지 않는다.

### 2.4 예약어 표 (오너 승인용, 21개)

| 보이는 모양 `term` | 비교 | 막는 것 | 근거 |
|---|---|---|---|
| `나` | exact | `나` | 화면이 나를 부르는 말(VS 인트로·상세). 1자라 길이 규칙에도 걸리지만 의도를 표에 남긴다 |
| `상대` | exact | `상대`, `상 대` | 화면이 상대를 부르는 말. `vs_intro.dart:243`이 이 말과 같은 이름이면 자리 이름을 숨긴다 |
| `상대방` | exact | `상대방` | 위와 같은 뜻의 말 |
| `알 수 없음` | exact | `알수없음` | 이름을 못 읽었을 때 앱이 대신 쓰는 말(`battle_providers.dart:89`) |
| `연습봇` | contains | `연습 봇`, `연습봇`, `연습봇123` | 봇 이름 사칭 |
| `탈퇴` | contains | `탈퇴한 사용자`, `탈퇴한사용자`, `탈퇴회원` | 묘비 사칭 |
| `운영자` | contains | `투두두두 운영자` | 운영 사칭 |
| `운영진` | contains | | 〃 |
| `운영팀` | contains | | 〃 |
| `관리자` | contains | | 〃 |
| `고객센터` | contains | | 〃 |
| `개발자` | contains | | 〃 |
| `공식` | contains | `공식`, `공식계정` (`공식왕`도 걸린다. spec이 받아들인 대가) | 〃 |
| `시스템` | contains | | 〃 |
| `투두두두` | contains | | 앱 사칭 |
| `tododudu` | contains | `TODODUDU`, `Todo dudu`, `T0D0DUDU` | 앱 사칭(영문 앱 이름) |
| `todododo` | contains | | 앱 사칭(패키지 이름 `com.todododo`) |
| `admin` | contains | `ADMIN`, `adm1n` (`badminton`도 걸린다) | 운영 사칭 |
| `system` | contains | | 〃 |
| `official` | contains | | 〃 |
| `staff` | contains | | 〃 |

### 2.5 금칙어 표 (오너 승인용, 42개 — 전부 `contains`)

"대놓고 하는 욕"만 막는 작은 목록이다(오너 결정 6). 무해한 낱말이 자주 걸리는 말은 **일부러 뺐다**(아래 "뺀 것").

| 묶음 | 단어 |
|---|---|
| 욕설(한글, 23) | 씨발, 시발, 씨빨, 씨바, 병신, 븅신, 개새끼, 개색기, 개세끼, 좆, 존나, 지랄, 염병, 미친놈, 미친년, 썅, 니애미, 느금마, 엠창, 섹스, 창녀, 한남충, 김치녀 |
| 초성 욕설(4) | ㅅㅂ, ㅆㅂ, ㅂㅅ, ㅄ |
| 혐오 표현(5) | 틀딱, 맘충, 짱깨, 깜둥이, 쪽바리 |
| 영문(10) | fuck, shit, bitch, cunt, nigger, nigga, faggot, asshole, sex, porn |

- **알려진 오탐**: `시발점`(始發點)은 `시발`에, `Essex`는 `sex`에 걸린다. 별명으로 드물어서 받아들인다.
- **뺀 것과 이유**: `새끼`(`새끼고양이`), `보지`(`보지마`), `자지`(`자지마`), `미친`(`미친듯이`), `걸레`(`걸레질`), `ass`(`class`·`pass`), `dick`(이름), `애자`·`니미`(오탐 위험), `닥쳐`·`꺼져`(무례한 명령이지만 욕설·혐오는 아님). 오너가 넣고 싶으면 표에 더하면 된다. 넣을 때는 §3.3 검증이 같이 돈다.
- 금칙어는 **뚫린다**. 띄어쓰기(`ㅅ ㅂ`, `병 신`)는 비교 키가 막지만 `시1발`, `씌발`, `byungsin`은 빠져나간다. spec 트레이드오프가 이미 받아들인 공백이다. 강화는 신고 기능과 함께 본다(spec 백로그).

### 2.6 "어느 단어에 걸렸는지 알려 주는가" (spec P0-3이 design에 맡긴 것)

| 걸린 것 | 알려 주는 것 | 이유 |
|---|---|---|
| 예약어 | **걸린 말까지 보여 준다**(`… 쓸 수 없어요: 공식`) | 목록이 무해하고 사실상 공개된 것이나 다름없다(`운영자`·`admin`·`연습 봇`). 반면 억울함이 가장 큰 쪽이다(`공식왕`이 왜 안 되지?). 알려 줘도 우회 이득이 없다. 공백·대소문자·0/1/l은 키가 이미 막는다 |
| 금칙어 | **걸린 말을 보여 주지 않는다**(`쓸 수 없는 말이 들어 있어요.`) | 욕설을 화면에 그대로 되돌려 보여 주지 않는다. 금칙어는 "어디를 바꿔야 할지"가 본인에게 대개 분명하다 |

전달 방법: 예약어일 때만 `raise exception using …, hint = 'NICKNAME_RESERVED', detail = <term>`. 앱은 `PostgrestException.details`를 읽는다. 비어 있으면 term이 없는 문구로 떨어진다.

### 2.7 우회 시도 → 결과 (수용 기준 1:1, 스모크에 그대로 들어간다)

| 입력 | 정규화 | 결과 |
|---|---|---|
| `연습봇` / `연습  봇` / ` 연습 봇 ` | `연습봇` / `연습 봇` / `연습 봇` | RESERVED(`연습봇`) |
| `탈퇴한 사용자` / `탈퇴한사용자` | | RESERVED(`탈퇴`) |
| `나` | | LENGTH |
| `상대` / `상 대` | | RESERVED(`상대`) |
| `투두두두 운영자` | | RESERVED(먼저 걸린 것 하나. 표에서 `term` 오름차순 첫 행) |
| `ADMIN` / `Todo dudu` / `adm1n` | | RESERVED |
| `연습\u200B봇`, `연습\u3164봇`, `\uFEFF연습봇` | 그대로 | CHARS |
| NFD로 쓴 `연습봇` | NFC `연습봇` | RESERVED |
| `ＡＤＭＩＮ`(전각) | | CHARS |
| `a@b.co`, `todo.com` | | CHARS |
| `01012345678` | | LENGTH |
| `★민수★` | | CHARS |
| `"   "`(공백만) | `''` | LENGTH |
| `부지런한 수달` | | 통과 |

---

## 3. 무작위 별명

### 3.1 단어표 (오너 승인용) — 형용사 40 × 명사 40 = **1,600 조합**

**형용사 40** (관형형, 2–5자, 외모·나이·성별·지능을 평가하는 말 없음)

| | | | | |
|---|---|---|---|---|
| 부지런한 | 느긋한 | 용감한 | 씩씩한 | 재빠른 |
| 꼼꼼한 | 다정한 | 명랑한 | 차분한 | 성실한 |
| 엉뚱한 | 졸린 | 배고픈 | 신나는 | 반짝이는 |
| 든든한 | 상냥한 | 날쌘 | 끈질긴 | 수줍은 |
| 유쾌한 | 침착한 | 대담한 | 슬기로운 | 너그러운 |
| 포근한 | 말랑한 | 동글동글한 | 뿌듯한 | 힘찬 |
| 활기찬 | 우아한 | 의젓한 | 당당한 | 산뜻한 |
| 늠름한 | 듬직한 | 해맑은 | 행복한 | 즐거운 |

**명사 40** (동물, 1–4자. 욕으로 쓰이는 동물은 뺐다: 개·돼지·쥐·닭·원숭이·벌레·뱀·하이에나. 속어로 읽히는 물개·하마도 뺐다)

| | | | | |
|---|---|---|---|---|
| 수달 | 다람쥐 | 고양이 | 펭귄 | 판다 |
| 너구리 | 고슴도치 | 해달 | 부엉이 | 올빼미 |
| 거북이 | 토끼 | 코알라 | 기린 | 사슴 |
| 알파카 | 비버 | 햄스터 | 호랑이 | 사자 |
| 돌고래 | 고래 | 해마 | 오리 | 참새 |
| 까치 | 앵무새 | 두더지 | 곰 | 북극곰 |
| 사막여우 | 치타 | 얼룩말 | 카피바라 | 코끼리 |
| 낙타 | 미어캣 | 청설모 | 강아지 | 병아리 |

- 모양: `형용사 + 공백 + 명사`(예: `부지런한 수달`). 가장 긴 조합은 `동글동글한 고슴도치`·`동글동글한 카피바라`로 **10자**이고, 가장 짧은 조합은 `졸린 곰`·`날쌘 곰`·`힘찬 곰`으로 4자다.
- **숫자를 붙이지 않는다.** 붙이면 시스템이 붙인 번호표처럼 읽힌다(오너 결정 3이 버린 (b)의 대가). 겹침은 §3.2의 "쓰이지 않은 조합 먼저"로 낮춘다.
- 이 표의 모든 조합이 예약어·금칙어에 걸리지 않는지는 사람 눈이 아니라 `assert_nickname_pool_valid()`가 확인한다(§3.3).

### 3.2 생성 함수 — `random_nickname() returns text`

```sql
-- volatile, security invoker. 사용자 롤에서 실행 권한을 회수한다(§6.2)
for i in 1..20 loop
  select a.word || ' ' || n.word into v_candidate
  from (select word from public.nickname_words where kind = 'adjective' order by random() limit 1) a,
       (select word from public.nickname_words where kind = 'noun'      order by random() limit 1) n;
  exit when v_candidate is null;                                         -- 표가 비었다
  continue when (public.check_nickname(v_candidate)).code is not null;   -- 규칙에 안 맞는 조합은 버린다
  v_fallback := coalesce(v_fallback, v_candidate);
  if not exists (select 1 from public.profiles where display_name = v_candidate) then
    return v_candidate;                                                  -- 아무도 안 쓰는 조합을 먼저 고른다
  end if;
end loop;
if v_fallback is not null then return v_fallback; end if;               -- 겹쳐도 된다(오너 결정 5)
raise exception using message = '무작위 별명을 만들지 못했습니다.', hint = 'NICKNAME_POOL_EMPTY';
```

- 결과가 `check_nickname`을 **반드시** 통과한다. 그래서 기본 별명과 일괄 덮기에도 같은 규칙이 적용된다(spec P0-4 "같은 규칙이 모든 쓰기에").
- "쓰이지 않은 조합 먼저"는 강제가 아니라 선호다. 사용자 n명일 때 20번 모두 쓰인 조합만 뽑힐 확률은 약 (n/1600)^20이다. n=1,000에서도 약 0.008%다. 그래서 **약 1,000명까지는 사실상 겹치지 않는다.** 그 뒤에는 겹침이 늘어난다(허용). 사용자가 1,000명에 가까워지면 단어를 늘린다 → `TODO_BACKLOG.md` 한 줄(메인 세션).
- `profiles.display_name`에 인덱스를 두지 않는다. 지금 행 수에서는 순차 조회가 더 싸다. 이름 검색은 범위 밖이다.
- 마지막 `raise`는 표가 비었을 때만 닿는다. §3.3이 마이그레이션 시점에 그 상태를 막는다. 이 함수가 던지면 **가입 자체가 실패**하므로(`handle_new_user`) 그 경로를 마이그레이션 단계에서 닫는 것이 핵심이다.

### 3.3 풀 검증 — `assert_nickname_pool_valid() returns void`

```sql
-- 형용사·명사가 각각 1개 이상인지, 그리고 모든 조합(1,600)이 check_nickname을 통과하는지 본다.
-- 하나라도 실패하면 실패한 조합 몇 개를 메시지에 담아 raise한다.
```

- 마이그레이션 A의 **마지막 줄**에서 부른다. 앞으로 `nickname_words`·`nickname_blocked_terms`를 고치는 마이그레이션도 마지막 줄에서 부른다(§1.4 운영 규칙).
- 1,600 조합 × 예약어·금칙어 63개 비교라 마이그레이션 안에서 충분히 빠르다.

### 3.4 P1-1 "다른 별명 추천받기" — `suggest_nickname() returns text`

`random_nickname()`을 사용자 롤에 열어 주는 얇은 RPC다(로그인 가드 + 탈퇴 계정 거부). **DB 단계 A에 같이 넣는다.** P1 화면을 나중에 하더라도 DB 단계가 하나 더 생기지 않게 하려는 것이다. 이 RPC는 아무것도 쓰지 않는다. 현재 내 이름도 "쓰이는 조합"에 들어가므로 대개 다른 이름이 나온다.

---

## 4. 쓰기 경로 닫기 (결론 A, P0-5)

### 4.1 무엇을 하나

```sql
drop policy "users can update their own profile" on public.profiles;
-- 두 겹째: 정책이 다시 생겨도 테이블 권한이 없으면 쓰기가 안 된다. insert·delete 정책은 원래 없다.
revoke insert, update, delete, truncate on table public.profiles from anon, authenticated;
```

select 정책(`profiles are viewable by any authenticated user`)과 select 권한은 **그대로 둔다**(spec P0-5).

### 4.2 이 정책을 쓰는 곳이 정말 없는가 — 확인 결과

| 자리 | `profiles` 접근 | 영향 |
|---|---|---|
| `lib/**`(앱) | select 3곳(`profile_repository.dart:14·55`, `battle_repository.dart:103`). update·insert·delete 0곳 | 없음 |
| `supabase/functions/**`(Edge) | 0곳 | 없음 |
| `delete_account()` | `update profiles set display_name='탈퇴한 사용자', deleted_at=now()`. **SECURITY DEFINER**(소유자 postgres)라 RLS도 테이블 권한도 소유자 기준이다 | 없음 |
| `handle_new_user()` | insert. SECURITY DEFINER | 없음 |
| `20261120120000` 봇 seed | 마이그레이션(postgres) | 없음 |
| `test/**` | 0곳 | 없음 |
| `supabase/tests/*.sql` | postgres로 돈다(`supabase db query --linked`) | 없음. 단 픽스처가 이름을 기대하는 스모크 하나는 고쳐야 한다(§11.3) |

### 4.3 닫은 뒤 남는 쓰기 경로 (전수)

| 경로 | 누가 | 무엇을 | 규칙 |
|---|---|---|---|
| `set_nickname()` | 로그인한 본인 | 자기 `display_name` | `check_nickname` |
| `handle_new_user()` | 가입 트리거 | 새 행의 `display_name` | `random_nickname`(= `check_nickname` 통과) |
| 마이그레이션 B(§5) | 일회성 | 기존 사용자의 `display_name` | `random_nickname` |
| `delete_account()` | 탈퇴하는 본인 | 자기 행을 묘비로(`탈퇴한 사용자`, `deleted_at`) | 시스템 이름이다(사용자 규칙 밖, spec P0-4 마지막 줄) |

사용자가 `deleted_at`을 바꾸는 길은 없다. 남의 행, 봇 행, 묘비 행을 고치는 사용자 경로도 없다.

---

## 5. 기존 사용자 일괄 덮기 (P0-2, 마이그레이션 B)

**대상**: `deleted_at is null`이고, `id <> public.bot_user_id()`이고, **`nickname_states` 행이 없는** 프로필.

- "상태 행이 없음"이 정확히 **A 이전에 가입한 사람**을 가리킨다. A 이후 가입자는 이미 무작위 이름이고 상태 행도 있다. 그래서 B는 그들을 건드리지 않는다. B를 실수로 두 번 돌려도 두 번째 실행은 0명이다. 이미 확정한 별명을 덮는 일이 구조적으로 없다.
- 실명인지 이메일인지 가리지 않는다(오너 결정 2). 원래 이름은 어디에도 복사하지 않는다(되돌릴 수 없음, 오너 결정 2).

```sql
do $$
declare r record; v_count int := 0;
begin
  for r in
    select p.id from public.profiles p
    where p.deleted_at is null
      and p.id <> public.bot_user_id()
      and not exists (select 1 from public.nickname_states s where s.user_id = p.id)
    order by p.created_at
  loop
    -- 한 사람씩 갱신한다. plpgsql 안의 문장은 앞 문장의 결과를 보므로, random_nickname의
    -- "쓰이지 않은 조합 먼저"가 이번 일괄 덮기에서 앞 사람에게 준 이름까지 피한다
    -- (update 한 문장으로 하면 같은 스냅숏을 봐서 겹칠 수 있다).
    update public.profiles set display_name = public.random_nickname() where id = r.id;
    insert into public.nickname_states (user_id, reset_at) values (r.id, now());
    v_count := v_count + 1;
  end loop;
  raise notice 'nickname reset: % profiles', v_count;

  -- 사후 단언(하나라도 어긋나면 마이그레이션 전체가 되돌아간다)
  if exists (select 1 from public.profiles where display_name like '%@%') then
    raise exception '이름에 @가 남은 프로필이 있습니다.'; end if;
  if exists (select 1 from public.profiles p where p.deleted_at is null and p.id <> public.bot_user_id()
             and not exists (select 1 from public.nickname_states s where s.user_id = p.id)) then
    raise exception '상태 행이 없는 사용자가 남았습니다.'; end if;
  if (select display_name from public.profiles where id = public.bot_user_id()) is distinct from '연습 봇' then
    raise exception '봇 이름이 바뀌었습니다.'; end if;
  if exists (select 1 from public.profiles where deleted_at is not null and display_name <> '탈퇴한 사용자') then
    raise exception '묘비 이름이 바뀌었습니다.'; end if;
end $$;
```

- **오너 확인을 두 번 받는다**(spec 빌드·테스트 마지막 항목). 1차는 아래 사전 확인 결과를 보여 주고 받는다. 2차는 적용 직전에 "되돌릴 수 없다"를 다시 말하고 받는다.
- 사전 확인(읽기 전용, **이름 값은 출력하지 않는다**):
  `select count(*) filter (where deleted_at is null and id <> public.bot_user_id()) as targets, count(*) filter (where deleted_at is not null) as tombstones, count(*) filter (where display_name like '%@%') as emails from public.profiles;`
  2026-11-24 점검 기준으로 targets ≈ 44 − 묘비 수, emails = 1이 예상값이다.
- 사후 확인: 위 단언에 더해 수용 기준 그대로 `select count(*) from public.profiles where display_name like '%@%'` → 0.

---

## 6. API 계약

### 6.1 새 사용자 RPC (전부 `security definer set search_path = public`, 첫 줄 로그인 가드, `revoke execute … from public, anon` + `grant execute … to authenticated`)

| RPC | 인자 | 반환 | 하는 일 | 오류 |
|---|---|---|---|---|
| `get_my_nickname_state()` | 없음 | `jsonb` `{"nickname": text, "confirmed": bool, "was_reset": bool}` | 내 `display_name`과 내 `nickname_states`를 읽는다. 행이 없으면 `confirmed=false, was_reset=false`. `stable` | 로그인 가드 / 내 행이 없거나 묘비 → `ACCOUNT_DELETED` |
| `set_nickname(p_nickname text)` | 원문 그대로(앱이 다듬지 않는다) | `text` — **저장된 정규화 값** | 내 행을 `for update`로 잠근다 → `check_nickname` → `profiles.display_name` 갱신 → `nickname_states` upsert(`confirmed_at = now()`). 관문 확정과 프로필 바꾸기가 **같은 RPC**다 | 로그인 가드 / `ACCOUNT_DELETED` / `NICKNAME_LENGTH` / `NICKNAME_CHARS` / `NICKNAME_RESERVED`(+`detail`=term) / `NICKNAME_BANNED` |
| `suggest_nickname()` (P1-1) | 없음 | `text` | `random_nickname()`을 돌려준다. 아무것도 쓰지 않는다. `volatile` | 로그인 가드 / `ACCOUNT_DELETED` / `NICKNAME_POOL_EMPTY` |

- `set_nickname`이 **본인 행만** 고친다는 것은 `where id = auth.uid()`가 보장한다. 대상 id를 받는 인자가 없다.
- 탈퇴 계정 거부가 필요한 이유: `auth.users`가 지워진 뒤에도 이미 발급된 JWT는 만료(최대 1시간) 전까지 유효하다. 그 토큰으로 묘비 이름을 바꾸는 길을 막는다.
- 같은 이름으로 다시 확정해도 성공한다(멱등). 중복 검사는 없다(오너 결정 5). 횟수 제한도 없다(오너 결정 7).
- 서버 메시지는 로그용 한국어다(`'별명은 2~10자여야 합니다.'` 등). 화면 문구는 앱이 코드로 고른다.

### 6.2 내부 함수 (security invoker, `revoke execute … from public, anon, authenticated`, grant 없음)

| 함수 | 쓰는 곳 |
|---|---|
| `normalize_nickname(text) returns text` | `check_nickname` |
| `nickname_compare_key(text) returns text` | `check_nickname` |
| `check_nickname(text, out normalized text, out code text, out term text)` | `set_nickname`, `random_nickname`, `assert_nickname_pool_valid` |
| `random_nickname() returns text` | `handle_new_user`, `suggest_nickname`, 마이그레이션 B |
| `assert_nickname_pool_valid() returns void` | 마이그레이션 끝줄, 스모크 |

DEFINER가 아닌 이유: 이 함수들은 전부 DEFINER 함수(소유자 postgres) 안이나 마이그레이션·스모크(postgres)에서만 불린다. 그때 실행 주체가 이미 소유자다. 사용자 롤에 실행 권한이 없으므로 PostgREST로 직접 부를 수도 없다. 그래서 CLAUDE.md의 "DEFINER 첫 줄 가드"가 적용될 자리가 없다. 함수 주석에 이 이유를 적는다.

### 6.3 고치는 기존 함수 (둘)

| 함수 | 바꾸는 것 | 주의 |
|---|---|---|
| `handle_new_user()` | `display_name`을 `public.random_nickname()`으로 채운다. **`raw_user_meta_data`·`email`을 더 이상 읽지 않는다.** `player_stats` insert는 그대로 두고, `nickname_states (user_id)` insert를 더한다 | `20260915120100`의 정의가 기준이다. 끝에 `revoke execute … from public, anon, authenticated`를 다시 적는다. 카카오 로그인이 들어와도 같은 트리거를 지나므로 카카오 닉네임이 기본값이 될 길이 없다(spec "다른 기능과의 관계") |
| `delete_account()` | 7번 단계 끝에 `delete from public.nickname_states where user_id = v_user_id;` 한 줄 | **`20261116120000_notification_dismiss.sql:213`의 정의(가장 늦은 정의)를 그대로 복사하고 한 줄만 끼운다.** 열 번 넘게 재정의된 함수라 옛 정의를 베끼면 다른 삭제가 조용히 되살아나거나 사라진다. 묘비가 남는 탈퇴라 cascade가 돌지 않는다(`notification_dismissals`와 같은 이유) |

### 6.4 오류 코드 → 앱 문구

| `hint` | 보이는 자리 | 문구(§9) |
|---|---|---|
| `NICKNAME_LENGTH` | 입력 칸 아래 오류 줄 | `nicknameErrorLength` |
| `NICKNAME_CHARS` | 〃 | `nicknameErrorChars` |
| `NICKNAME_RESERVED` | 〃 | `details`가 있으면 `nicknameErrorReserved(term)`, 없으면 `nicknameErrorReservedGeneric` |
| `NICKNAME_BANNED` | 〃 | `nicknameErrorBanned` |
| 그 밖(`ACCOUNT_DELETED`·네트워크·알 수 없음) | **토스트**. 입력과 버튼은 그대로 다시 누를 수 있다 | `nicknameSaveFailed` |

규칙 위반은 사용자가 고칠 수 있는 것이라 칸 옆에 둔다. 사용자가 입력을 고치면 오류 줄이 사라진다. 저장 실패는 다시 시도할 일이라 토스트로 알린다(spec "저장 실패가 토스트로").

---

## 7. 화면

### 7.1 관문의 자리와 순서

```
앱 시작 → AuthGate
  ├─ 세션 없음 → LoginScreen
  └─ 세션 있음 → NicknameGate(userId)          ← 신규
        ├─ 상태 조회 중        → 전체 화면 로더(AuthGate의 loading과 같은 모양)
        ├─ confirmed = false → 별명 정하기 화면(7.2)
        ├─ confirmed = true  → MainShell
        └─ 조회 실패          → MainShell (debugPrint. 결정 필요 1)
MainShell 안: 사람 대결을 만들거나 참가할 때 → ensureAiConsent(지금 그대로)
```

- **별명 관문은 AI 동의보다 앞이다.** 동의는 지금처럼 첫 실행 경로에 없고, 사람 대결 직전에만 뜬다. 그래서 별명은 언제나 동의 전에 받는다. 별명이 AI로 갈 경로는 원래 없다(결론 C). 봇전은 동의 없이 되는 것도 그대로다.
- **`MainShell` 앞에 둔다.** 푸시 토큰 등록, 기한 알림 초기화, 위젯 캐시 되읽기는 `MainShell.initState`에서 시작한다. 그래서 관문을 지나기 전에는 이것들이 돌지 않는다. 받아들인다. 관문은 한 번만 뜨고, 한 번 누르면 지나간다. 홈 위젯 체크를 받는 포트는 `AuthGate`에 있으므로 영향이 없다.
- **`userId`로 나눈다.** 상태 provider를 `family(userId)` + `autoDispose`로 둔다. 로그아웃 뒤 다른 계정으로 들어오면 새로 읽는다(이전 사용자 값이 남는 `todosProvider` 같은 버그를 만들지 않는다). 토큰 갱신으로 `AuthGate`가 다시 그려져도 같은 키라 다시 조회하지 않는다.
- **한 번 `MainShell`로 보냈으면 그 세션 동안 되돌리지 않는다(래치).** Riverpod 3에는 실패한 provider를 자동으로 다시 시도하는 기본 동작이 있다. 래치가 없으면 조회 실패로 `MainShell`에 들어간 사용자가 몇 초 뒤 재시도 성공으로 관문 화면에 끌려 나갈 수 있다. 그래서 (1) 이 provider는 자동 재시도를 끈다(`retry: (_, _) => null` 꼴. 3.4.x의 정확한 시그니처는 developer가 확인한다). (2) `NicknameGate`가 "통과" 상태를 기억한다. 확정하지 않은 사용자는 다음 실행에 다시 관문을 본다(spec "확정하지 않고 끄면 다음 실행에 다시 묻는다").
- 판단은 순수 함수로 뺀다: `nicknameGateView(AsyncValue<NicknameState>) → loading | setup | shell`. **오류를 값보다 먼저 본다.** 재조회가 실패하면 `AsyncError`가 이전 값(미확정)을 들고 있어 값부터 보면 관문으로 되돌아가기 때문이다.
- **비용**: 앱을 켤 때마다 RPC를 한 번 기다린 뒤 본 화면이 뜬다. 확정한 사용자도 마찬가지다. 기기에 "확정함"을 캐시해 건너뛰는 길은 쓰지 않는다. spec이 "확정은 서버가 안다"를 요구하고, 실패하면 통과하므로 오프라인에서 막히지도 않는다.

### 7.2 별명 정하기 화면 (관문, 신규)

구성은 AI 동의 화면(`AiConsentScreen`)과 같은 문법을 따른다. `AppBar(title)` + `ListView` 가장자리 20 + 아래쪽 버튼이다. 뒤로 가기 화살표는 없다(`automaticallyImplyLeading: false`). 시스템 뒤로 가기는 평소처럼 앱을 닫는다.

```
┌ 별명 정하기 ──────────────────────┐
│ 대결 상대와 모집 목록에는 이 별명만   │  bodyMedium
│ 보여요. 실명과 이메일은 다른 사용자에 │
│ 게 보이지 않아요.                   │
│                                    │
│ ┌ 이름이 별명으로 바뀌었어요 ────────┐ │  was_reset일 때만. AppPanel.flat 하나
│ │ 실명이나 이메일 주소가 … 고칠 수   │ │  (줄마다 면을 두지 않는다 — 면은 이 하나뿐)
│ │ 있어요.                           │ │
│ └──────────────────────────────────┘ │
│                                    │
│ 별명                                │  TextField, 서버 기본 별명이 미리 채워짐
│ [부지런한 수달            ]          │  규칙 위반이면 errorText
│ (P1-2) 한글·영문·숫자 2~10자   6/10  │
│                                    │
│ (P1-1) ↻ 다른 별명 추천받기          │  TextButton.icon
│                                    │
│ [   이 별명으로 시작하기   ]          │  FilledButton, 진행 중 AppLoader.small
│ [   ⎋ 로그아웃             ]         │  OutlinedButton.icon
└────────────────────────────────────┘
```

| 상태 | 화면 |
|---|---|
| 처음 | 칸에 `nickname`(서버 기본 별명)이 채워져 있다. **자동 포커스는 하지 않는다.** 키보드가 안내와 버튼을 가리지 않게 하고, 그대로 누르는 사람이 대부분이기 때문이다 |
| 확정 중 | 확정 버튼은 로더, 칸·추천·로그아웃은 비활성 |
| 규칙 위반 | 칸 아래 오류 줄(§6.4). 칸 내용은 그대로 둔다. 입력이 바뀌면 오류 줄을 지운다 |
| 저장 실패 | 토스트 `nicknameSaveFailed`. 버튼이 다시 살아난다(spec "확정 실패 → 알리고 다시 시도") |
| 성공 | `myNicknameStateProvider(userId)`와 `myProfileProvider`를 무효화한다 → 관문이 `confirmed`를 읽고 `MainShell`로 바뀐다. 따로 토스트를 띄우지 않는다 |
| 로그아웃 | `authRepository.signOut()`. 실패하면 토스트 `logoutFailed`(지금 프로필의 로그아웃은 실패를 받지 않는다. 관문에서는 이것이 유일한 출구라 받는다) |
| 키보드 완료 | `onSubmitted` = 확정 버튼과 같다 |

입력 칸에는 `maxLength`를 걸지 않는다(P0). 앞뒤 공백까지 세는 칸 길이와 서버가 세는 길이가 다르기 때문이다. 길이는 서버가 말한다. P1-2의 글자 수 표시는 아래 7.4에서 다룬다.

### 7.3 프로필 — 별명 바꾸기 (P0-6, 신규 화면 1)

**진입점**: 프로필 탭 맨 위의 이름 줄을 `Row[이름(Expanded) · IconButton(AppIcons.edit, tooltip '별명 바꾸기')]`로 바꾼다. 메뉴 행(`_MenuRow`)을 하나 더 만들지 않는다. 바꾸는 대상(이름)의 바로 옆이 가장 짧은 길이고, 면이 있는 행을 더 늘리지 않는다(오너 취향). 프로필을 불러오는 중이거나 실패했으면 아이콘을 숨긴다. 채워 넣을 현재 이름이 없기 때문이다.

**화면**: `MaterialPageRoute`로 띄운다. 대화상자가 아니라 화면인 이유는 저장 실패 토스트가 대화상자 장벽 밑에 깔리지 않게 하려는 것이다. 이 화면이 7.2와 **같은 입력 위젯**(`NicknameForm`: 칸 + 오류 줄 + 주 버튼)을 쓴다.

```
┌ ← 별명 바꾸기 ─────────────────────┐
│ 바꾸면 모집 목록, 대결 상대의 화면,   │  bodyMedium
│ 지난 대결 기록에 새 별명이 보여요.    │
│                                    │
│ 별명                                │
│ [부지런한 수달            ]          │  현재 이름이 채워짐, 자동 포커스 함
│                                    │
│ [          저장           ]          │
└────────────────────────────────────┘
```

| 상태 | 화면 |
|---|---|
| 저장 중 | 버튼 로더, 칸 비활성 |
| 규칙 위반 | 칸 아래 오류 줄 |
| 저장 실패 | 토스트 `nicknameSaveFailed`(수용 기준 "저장 실패가 토스트로") |
| 성공 | `pop(true)` → 프로필이 토스트 `nicknameChanged`를 띄우고 `myProfileProvider`를 무효화한다 |

- 이 화면에는 "다른 별명 추천받기"를 두지 않는다. spec P1-1이 "첫 화면에서"라고 적었다.
- 횟수 제한·안내 없음(오너 결정 7).

### 7.4 P1 (빼도 성립한다)

- **P1-1 추천받기**: 7.2의 버튼이다. `suggest_nickname()` 결과로 칸을 덮고 오류 줄을 지운다. 실패하면 토스트 `nicknameSuggestFailed`를 띄우고 칸은 그대로 둔다.
- **P1-2 규칙 안내**: 칸 아래에 고정 안내 한 줄(`nicknameRuleHint`)과 글자 수 `n/10`을 둔다. 글자 수는 **앞뒤 공백을 지우고 연속 공백을 한 칸으로 줄인 뒤** 센 값이다. Dart 쪽 정규화는 이 표시에만 쓰고 판정은 하지 않는다. 입력을 막지도 않는다(`maxLengthEnforcement` 없음). 앱에 두는 것은 이 정규화와 글자 수까지다. 허용 문자·예약어 검사를 앱에 복제하지 않는다(원칙 1).

### 7.5 이름이 보이는 자리 — 바꾸지 않는다 (확인만)

| 자리 | 출처 | 변경 |
|---|---|---|
| 모집 목록·모집 상세 시트 | `list_open_recruits().creator.display_name` | 없음 |
| 상대 전적 카드 | `get_player_card().display_name` | 없음 |
| 내 대결 목록·대결 상세·VS 인트로 | `fetchDisplayNames` / `myProfileProvider` | 없음 |
| 지난 대결 | `profile_providers.dart`의 `fetchDisplayNames` | 없음 (결론 B: 지금 별명을 보여 준다) |
| 이니셜 칸 | `displayInitial(name)` | 없음. 별명 첫 글자. 자모로 시작하면 자모(`ㅋ`), 영문 소문자로 시작하면 대문자 |
| 푸시·알림함·위젯·AI 요청 | 이름을 넣지 않는다(`notification_events`·`notification_inbox` 스모크가 payload에 `display_name`이 없음을 이미 고정했고, Edge는 `profiles`를 읽지 않는다) | 없음 |

**길이**: 지금까지 이름 자리에 이메일(20자 이상)도 들어갔고, 그 자리들은 이미 말줄임 처리가 돼 있다(`player_card_view.dart:42`, `vs_intro.dart:379`). 10자 상한은 그보다 짧으므로 레이아웃은 고치지 않는다. `동글동글한 고슴도치`(10자)를 320dp·1.5배에서 눈으로 한 번 보고, 문제가 그 극단 조합에서만 보이면 보고만 한다.

**"즉시"의 뜻**: 서버 값은 `set_nickname`이 커밋되는 순간 바뀐다. 다른 사용자의 화면에는 그 화면이 다음에 다시 읽을 때 보인다. 목록 provider들은 `autoDispose`이고 탭 전환이나 당겨서 새로고침 때 다시 읽는다. 실시간 갱신은 만들지 않는다. 지금 이름이 바뀌는 다른 경로(탈퇴 묘비)도 같은 방식이다.

---

## 8. 데이터 흐름

**흐름 1 — 첫 로그인(새 사용자)**
1. Google 로그인 → `auth.users` insert → `handle_new_user`: `profiles(id, random_nickname())`, `player_stats(id)`, `nickname_states(id)`.
2. `AuthGate`에 세션이 생긴다 → `NicknameGate(userId)`가 `myNicknameStateProvider(userId)`를 본다 → `get_my_nickname_state()` → `{nickname: '부지런한 수달', confirmed: false, was_reset: false}`.
3. 별명 정하기 화면에서 그대로 확정하거나 고쳐서 확정한다 → `set_nickname(raw)` → 저장값을 돌려받는다.
4. `invalidate(myNicknameStateProvider(userId))`, `invalidate(myProfileProvider)` → `confirmed: true` → `MainShell`.

**흐름 2 — 기존 사용자(B 적용 뒤 새 앱을 처음 엶)**: 1을 건너뛰고 2부터 시작한다. 이때 `was_reset: true`라 안내 묶음이 보인다. 옛 앱을 쓰는 동안에는 관문이 없고 프로필에 무작위 별명이 보인다. 이 사용자는 업데이트하면 관문을 본다.

**흐름 3 — 확정하지 않고 앱을 끔**: 상태 행의 `confirmed_at`이 null로 남는다 → 다음 실행에 다시 관문이 뜬다. 그동안 남에게 보이는 이름은 기본 별명이다.

**흐름 4 — 프로필에서 바꾸기**: 연필 → 바꾸기 화면 → `set_nickname(raw)` → `pop(true)` → 토스트 + `invalidate(myProfileProvider)`. 다른 provider는 무효화하지 않는다. 내 이름을 캐시하는 provider는 `myProfileProvider` 하나다. VS 인트로는 그때그때 `myProfileProvider.future`를 읽고, 대결 상세의 `myName`은 상세를 열 때마다 새로 읽는다(`autoDispose`). 바꾸기 화면이 떠 있는 동안 상세 화면은 스택에 있을 수 없다. `myNicknameStateProvider(userId)`는 관문이 이미 `confirmed: true`로 들고 있다. 다시 읽어도 결과가 같으니 건드리지 않는다.

**흐름 5 — 관문 조회 실패**: `debugPrint('getMyNicknameState failed: …')` → `MainShell`(래치). 다음 실행에서 다시 묻는다.

**흐름 6 — 로그아웃(관문에서)**: `signOut()` → 세션이 사라짐 → `AuthGate`가 `LoginScreen`으로 바뀐다 → `NicknameGate`가 사라지고 `autoDispose`로 상태가 버려진다.

Dart 쪽 모양(이름은 developer가 바꿔도 된다):

| 층 | 무엇 |
|---|---|
| data | `NicknameState { String nickname; bool confirmed; bool wasReset }` + `fromMap`. `ProfileRepository`에 `fetchMyNicknameState()`, `setNickname(String raw) → Future<String>`, `suggestNickname() → Future<String>`(P1) |
| domain | `myNicknameStateProvider = FutureProvider.autoDispose.family<NicknameState, String>`(재시도 끔). 순수 함수 `nicknameGateView(...)`, `nicknameRejectionOf(Object error) → NicknameRejection(kind, term)?`(규칙 위반이 아니면 null), `nicknameRejectionMessage(...)` |
| presentation | `NicknameGate`(child 빌더를 받는다. 테스트가 `MainShell` 없이 돌 수 있게 한다), `NicknameSetupScreen`, `NicknameEditScreen`, 공용 `NicknameForm`. `AuthGate`의 data 갈래가 `MainShell()` 대신 `NicknameGate(userId: …, child: MainShell())`을 그린다 |

---

## 9. 문구 (`lib/core/strings.dart`에 들어갈 초안)

```dart
// 별명(nickname). 다른 사용자에게 보이는 이름은 별명 하나다 — 실명·이메일은 어디에도 보이지 않는다.
// 규칙 위반 문구는 서버 오류 코드(NICKNAME_*)에 1:1로 붙는다. 규칙 자체는 서버(check_nickname)에 있다.
static const nicknameSetupTitle = '별명 정하기';
static const nicknameSetupIntro = '대결 상대와 모집 목록에는 이 별명만 보여요. 실명과 이메일은 다른 사용자에게 보이지 않아요.';
static const nicknameResetNoticeTitle = '이름이 별명으로 바뀌었어요';
static const nicknameResetNoticeBody =
    '실명이나 이메일 주소가 다른 사용자에게 보이지 않도록 모든 사용자의 이름을 무작위 별명으로 바꿨어요. '
    '마음에 들지 않으면 지금 고칠 수 있어요.';
static const nicknameFieldLabel = '별명';
static const nicknameConfirm = '이 별명으로 시작하기';
static const nicknameEditTitle = '별명 바꾸기';
static const nicknameEditTooltip = '별명 바꾸기';
static const nicknameEditIntro = '바꾸면 모집 목록, 대결 상대의 화면, 지난 대결 기록에 새 별명이 보여요.';
static const nicknameChanged = '별명을 바꿨어요.';
static const nicknameSaveFailed = '별명을 저장하지 못했어요. 다시 시도해 주세요.';
static const nicknameErrorLength = '별명은 2~10자로 정해 주세요.';
static const nicknameErrorChars = '한글, 영문, 숫자와 띄어쓰기만 쓸 수 있어요.';
static String nicknameErrorReserved(String term) => '앱이나 운영자가 쓰는 말이라 별명에 넣을 수 없어요: $term';
static const nicknameErrorReservedGeneric = '앱이나 운영자가 쓰는 말이라 별명에 넣을 수 없어요.';
static const nicknameErrorBanned = '쓸 수 없는 말이 들어 있어요.';
static const logoutFailed = '로그아웃하지 못했어요. 다시 시도해 주세요.';
// P1-1·P1-2
static const nicknameSuggestAnother = '다른 별명 추천받기';
static const nicknameSuggestFailed = '새 별명을 받지 못했어요. 다시 시도해 주세요.';
static const nicknameRuleHint = '한글·영문·숫자 2~10자, 띄어쓰기는 한 칸씩';
static String nicknameLength(int length) => '$length/10';
```

- 예약어 문구 끝에 `: $term`을 붙여 조사(이/가) 문제를 피한다.
- 안내 묶음은 "원래 이름은 보관하지 않았다"를 따로 말하지 않는다. 사용자가 할 수 있는 일(지금 고치기)만 말한다. 예전 이름을 다시 쓰고 싶은 사람은 칸에 직접 적으면 된다(spec P0-3이 허용).

---

## 10. 고지(P0-7) — 사실 정리

spec은 "Google에서 이름을 계속 받는지 design·developer가 확인"을 요구한다. 확인 결과는 아래와 같다. `todododo-legal`은 오너가 손수 고친다(오너 결정 8). 이 저장소에서는 `DEPLOY.md` 5절만 developer가 고친다.

| 사실 | 근거 | 고지에 쓸 말 |
|---|---|---|
| **Google 이름을 계속 받는다.** Supabase Auth가 Google 로그인마다 받은 프로필 정보를 `auth.users.raw_user_meta_data`와 `auth.identities.identity_data`에 저장하고 갱신한다. 앱 코드가 아니라 Supabase Auth의 동작이다 | 로그인 경로(`signInWithOAuth(google)`)가 그대로고, 이 기능은 로그인 설정을 바꾸지 않는다(spec 범위 밖) | 1-가 "이름 — 다른 이용자에게 보이지 않습니다"(spec 문구 그대로) |
| 이 기능 뒤로는 앱·DB의 어떤 경로도 그 이름을 읽지 않는다 | `handle_new_user`가 `raw_user_meta_data`·`email`을 더 이상 읽지 않는다(§6.3). 앱은 `userMetadata`를 쓰지 않는다(grep 0건). `auth` 스키마는 클라이언트가 읽을 수 없다 | 3절 "실명도 공개되지 않습니다" |
| 별명은 이용자가 직접 입력한다 | `set_nickname` | 1-나에 "별명", 3절 "표시 이름" → "이용자가 정한 별명" |
| 탈퇴하면 Google에서 받은 정보는 `auth.users` 삭제와 함께 지워지고, 별명은 `탈퇴한 사용자`로 바뀐다 | `delete_account` 8·9단계 | 4절 표 "표시 이름 — Google 계정에서 받은 이름" → "별명 — 이용자가 정한 이름", 처리는 그대로 |
| AI에 이름(별명 포함)을 보내지 않는다 | Edge가 `profiles`를 읽지 않는다 | 지금 문구 그대로 |

**`DEPLOY.md` 5절 고칠 내용**(developer):
- 134행 "Google 계정 이메일·이름(프로필 표시용)" → "Google 계정 이메일·이름(로그인 시 Supabase Auth가 받는다. 다른 이용자에게 보이지 않는다), **이용자가 정한 별명**(다른 이용자에게 보이는 이름)"
- 150행 데이터 보안 양식 "수집: 이메일 주소, **이름**, …"은 **체크를 그대로 둔다.** Play의 "이름" 분류가 닉네임을 포함하고, Google 이름도 여전히 받기 때문이다. 메모에 "이름 = Google 이름(표시 안 함) + 별명(다른 이용자에게 표시)"을 덧붙인다.

**원격 확인(읽기 전용, developer가 실행 — 값이 아니라 키만 본다)**:
`select distinct jsonb_object_keys(raw_user_meta_data) from auth.users;`
이름 키(`full_name`/`name`)가 실제로 있는지, 그리고 **프로필 사진 주소(`avatar_url`/`picture`)가 함께 저장되는지** 확인한다. 후자는 결정 필요 3이다.

---

## 11. 테스트 계획

### 11.1 SQL — 순수 규칙: 신규 `supabase/tests/nickname_rules.sql` (롤백, 사용자 없음)

1. `normalize_nickname`: 앞뒤 공백, 연속 공백, 탭·줄바꿈·NBSP·U+3000 → 한 칸, NFD → NFC, null → `''`.
2. `check_nickname`: §2.7 표의 **모든 줄**을 기대 `code`/`term`과 함께 확인한다. 경계 문자로 `가`·`힣`·`ㄱ`·`ㅣ`·`ㅄ`는 통과, `U+3164`·`U+318D`·`U+1100`·`U+200B`·`U+FEFF`·`😀`는 CHARS인지 본다. 길이는 2자·10자 통과, 1자·11자 LENGTH를 본다. 단어 사이 공백은 1칸 통과, 정규화 후 2칸이 생길 수 없음을 확인한다. 예약어 21개 각각 exact/contains 대표 한 건, 금칙어는 묶음마다 한 건(한글·초성·혐오·영문, `sh1t` 포함)을 본다.
3. `assert_nickname_pool_valid()`가 예외 없이 끝난다. `random_nickname()` 200회가 전부 `check_nickname` 통과, 길이 ≤ 10, `형용사 명사` 모양인지 본다.
4. **양성 대조**: 트랜잭션 안에서 `nickname_blocked_terms`에 `수달`(banned, contains)을 넣으면 `assert_nickname_pool_valid()`가 **실패**하는지 본다(검증이 실제로 일하는지 확인). 끝나면 롤백한다.

### 11.2 SQL — 흐름: 신규 `supabase/tests/nickname_flow_smoke.sql` (가짜 사용자, 마지막에 롤백, `supabase db query --linked -f`)

1. **기본 이름**: `auth.users`에 `full_name='스모크실명'`, `email='nick-smoke@example.invalid'`로 넣는다 → `profiles.display_name`이 둘 다 아니고 `check_nickname` 통과, `@` 없음, `nickname_states` 행 `(null, null)`, `player_stats` 행이 있는지 본다.
2. **직접 쓰기 거부**(사용자 세션 흉내: `set local role authenticated` + `request.jwt.claims`): 자기 행의 `display_name` update, `deleted_at` update, 남의 행 update, `profiles` insert·delete가 전부 권한 오류이거나 0행이다. 같은 세션의 `select`는 모든 프로필을 읽는다(읽기 보존).
3. **`set_nickname`**: `'  수달   왕 '` → `'수달 왕'`을 반환하고 저장하며 `confirmed_at`이 채워진다. `get_my_nickname_state()`의 `confirmed`가 true가 된다. 같은 이름 재확정과 남이 쓰는 이름(중복)도 성공한다.
4. **거부 코드**: LENGTH / CHARS / RESERVED(`detail` = `연습봇`) / BANNED 각 한 건. 거부 뒤 이름과 `confirmed_at`이 그대로인지 본다.
5. **남·봇·묘비**: 3·4 뒤 다른 가짜 사용자의 이름, `연습 봇`, 묘비 이름이 그대로인지 본다. 묘비 uid로 만든 claims로 `set_nickname`·`get_my_nickname_state` → `ACCOUNT_DELETED`.
6. **권한**: anon으로 세 RPC 실행이 거부된다. 로그인 없이(claims 없음) 부르면 `'로그인이 필요합니다.'`. authenticated로 `check_nickname`·`random_nickname`·`normalize_nickname`·`nickname_compare_key`·`assert_nickname_pool_valid` 실행이 거부되고, `nickname_words`·`nickname_blocked_terms`·`nickname_states` 직접 select도 권한 오류다.
7. **탈퇴**: `delete_account()` → `display_name = '탈퇴한 사용자'`, `nickname_states` 행 0개, 기존 삭제 항목(투두·토큰·알림 등)도 그대로 지워진다. `delete_account_smoke.sql`을 같이 다시 돌린다.
8. **`suggest_nickname`**: 규칙 통과, 쓰기 없음(호출 전후 내 `display_name`·`confirmed_at`이 같음).
9. **B의 대상 규칙**(B 파일 자체는 일회성이라 스모크가 그 블록을 부르지 않는다. 대상 조건만 고정한다): 상태 행이 없는 가짜 프로필 하나와 상태 행이 있는 하나를 만들고, §5의 `where` 조건으로 고른 집합에 앞의 것만 드는지 본다.

### 11.3 기존 스모크 회귀

- **`join_battle_smoke.sql`은 고쳐야 한다.** 이 스모크는 `get_player_card`/`list_open_recruits`가 `full_name`(`스모크A`·`스모크D`)을 이름으로 돌려준다고 기대한다(210–212행). A 이후에는 기본 이름이 무작위라 깨진다. 픽스처에서 `auth.users` insert 뒤 **postgres 권한으로** `update public.profiles set display_name = '스모크A' …`처럼 이름을 박아 둔다. 스모크는 postgres로 돌므로 §4.1의 권한 회수와 무관하다. 기대값은 그대로 둔다.
- 그 밖에 `auth.users`에 넣는 스모크 전부(`ai_consent`·`bot_battle_flow`·`criteria`·`criteria_cache`·`custom_duration`·`deadline_reminder`·`delete_account`·`forfeit_battle`·`mutual_judge_flow`·`notification_events`·`notification_inbox`·`push_token`·`recruit_browse`·`resolve_battle`·`settle_expired_battles`·`ai_judge_flow`·`ai_rejudgment`)를 다시 돌린다. 새 `handle_new_user`가 모든 픽스처 가입에서 실패하지 않는지 보는 것이 목적이다. 이름 값을 단언하는 곳은 위 하나뿐임을 grep으로 확인했다(`delete_account`·`push_token`은 묘비 이름만 본다). `recruit_browse`의 `'스모크'` 검색은 제목 검색이라 무관하다.

### 11.4 Dart 유닛

- `NicknameState.fromMap`(키 누락·타입).
- `nicknameRejectionOf`: `PostgrestException(hint: NICKNAME_*)` 네 종류 → kind. RESERVED의 `details`가 문자열·빈 문자열·null일 때. 그 밖의 hint, 일반 예외 → null(= 저장 실패 토스트).
- `nicknameRejectionMessage`: 코드별 문구, term 유무.
- `nicknameGateView`: loading → loading, data(false) → setup, data(true) → shell, error → shell, **이전 값(false)을 든 error → shell**(오류 우선).
- (P1-2) 글자 수 정규화: `'  수달   왕 '` → 4.

### 11.5 Dart 위젯 (화면 테스트는 선택이지만, 관문은 모든 사용자가 지나는 길이라 아래는 만든다)

1. 관문: 미확정 → 설정 화면, 칸에 서버 이름이 채워져 있다. 확정 → 가짜 repository의 `setNickname`이 원문으로 불린다 → 다음 조회가 confirmed → child가 보인다.
2. `was_reset`일 때만 안내 묶음이 보인다.
3. 규칙 위반(RESERVED, details `공식`) → 칸 아래 `…: 공식`이 보이고, 칸 내용이 유지되고, 다시 입력하면 오류 줄이 사라진다.
4. 저장 실패(일반 예외) → 토스트가 뜨고 버튼이 다시 활성화된다.
5. 로그아웃 버튼 → `signOut` 호출. 실패하면 토스트.
6. 조회 실패 → child(본 화면)가 보이고, 그 뒤 provider가 미확정 값을 내도 child가 유지된다(래치).
7. 프로필: 연필 아이콘 → 바꾸기 화면(현재 이름이 채워짐) → 성공 → 화면이 닫히고 토스트, 프로필 머리가 새 이름. 프로필 로딩 실패 중에는 연필이 없다.

### 11.6 실기기 체크리스트(오너)

새 계정 첫 로그인 → 관문 → 그대로 확정 / 기존 계정(업데이트 설치) → 안내 묶음 확인 → 고쳐서 확정 / 관문에서 로그아웃 / 비행기 모드로 앱 시작 → 관문 없이 본 화면 / 프로필에서 바꾸기 → 다른 기기·계정의 모집 목록에서 새 이름 확인 / 320dp·1.5배에서 10자 이름(관문 칸, 프로필 머리, VS 인트로).

---

## 12. 구현 단계와 오너 확인 지점

파일 이름은 제안이다(타임스탬프는 developer가 정한다). 커밋 단위는 plan.md 몫이다.

| 단계 | 스키마 | 내용 | 적용 전 확인 | 적용 후 검증 |
|---|---|---|---|---|
| **1. DB-A** `…_nickname.sql` | **있음(오너 확인)** | 테이블 3개(+RLS 정책 0개 + `revoke all`) + 단어 80행 + 예약어 21행·금칙어 42행 seed + 내부 함수 5개 + RPC 3개(`get_my_nickname_state`·`set_nickname`·`suggest_nickname`) + `handle_new_user` 재정의 + `delete_account` 한 줄(최신 정의 복사) + **UPDATE 정책 제거·쓰기 권한 회수** + 끝줄 `assert_nickname_pool_valid()` | 오너가 §3.1·§2.4·§2.5 표를 승인했는지. 같은 단계에서 `join_battle_smoke.sql` 픽스처도 고친다 | `nickname_rules.sql`·`nickname_flow_smoke.sql` 전 항목 ok, §11.3 회귀 스모크 |
| **2. DB-B** `…_nickname_reset_existing.sql` | **있음(오너 확인 2회, 되돌릴 수 없음)** | §5의 일괄 덮기 + 사후 단언 | §5 사전 확인 쿼리 결과를 보여 준다. 원하면 같은 블록을 `begin; … rollback;`으로 미리 돌려 대상 수만 본다(이 미리 돌리기도 원격 쓰기라 오너 확인 뒤에 한다) | `@` 0개, 상태 행이 빠진 사용자 0명, 봇·묘비 이름 그대로 |
| **3. 앱 P0** | 없음 | 모델·repository·provider·순수 함수, `NicknameGate` + 별명 정하기 화면(커밋 1), 프로필 연필 + 바꾸기 화면(커밋 2), 문구, 유닛·위젯 테스트 | 1·2 적용 완료 | `flutter analyze` 0, `flutter test` 통과, §11.6. 새 패키지가 없으므로 릴리스 빌드 검증 의무는 없다. 그래도 배포 전 빌드에서 함께 본다 |
| **4. 앱 P1**(선택) | 없음 | 추천받기 버튼, 규칙 안내 줄과 글자 수 | 3 완료 | 위젯 테스트 1건씩 |
| **5. 문서** | 없음 | developer: `DEPLOY.md` 5절(§10). 메인 세션: `TODO_BACKLOG.md`의 [보안 점검 2026-11-24 중간] 두 줄 닫기 + spec 백로그 6줄 + "단어표 확장(사용자 1,000명 근처)" 한 줄, CLAUDE.md(도메인 규칙에 "표시 이름은 `set_nickname` 한 경로로만 바뀌는 별명" 한 줄 + 결정 필요 1의 에러 예외 한 줄). 오너: `todododo-legal` 두 문서(`bot-battle` 고지와 시행일을 맞춘다) | 결정 필요 1·3의 답 | 세 문서(방침·삭제 안내·DEPLOY)가 같은 사실을 말하는지 눈으로 대조 |

**순서를 지키는 이유**
- **A → B**: B가 `random_nickname`과 `nickname_states`를 쓴다.
- **B → 앱 배포**: 앱이 먼저 나가면 B 전의 기존 사용자에게 상태 행이 없다. 그러면 안내 묶음 없이 **실명이 미리 채워진** 관문이 뜬다. 그렇게 돼도 막히는 것은 없지만 spec의 "이유를 한 줄 알린다"가 빠진다.
- **A만 적용된 상태도 안전하다**: 옛 앱은 관문이 없으니 그대로 돈다. 새 가입자는 무작위 이름을 받는다. 직접 쓰기는 이미 닫혀 있다. 반대로 앱이 A보다 먼저 나가도 RPC가 없어 조회가 실패하고, 관문이 통과시킨다(fail-open). 그래서 앱이 갇히지 않는다.

---

## 13. 수용 기준 대조

| spec 수용 기준 | 어디서 |
|---|---|
| 새 사용자 기본 이름이 계정 정보와 무관 | §6.3 `handle_new_user`, 스모크 11.2-1 |
| 적용 직후 기존 사용자 전원 무작위(앱 업데이트 무관) | §5(서버 마이그레이션), 사후 단언 |
| `@` 든 프로필 0개 / 묘비·봇 그대로 | §5 사후 단언 |
| 화면 어디에도 실명·이메일 없음 | §7.5(모든 자리가 `display_name`을 읽고, 그 값이 별명뿐이다) |
| AI·푸시·알림함에 별명 없음 | §7.5 마지막 줄(기존 스모크가 고정) |
| 첫 로그인 관문 한 번 / 기존 사용자 안내 / 미리 채움 / 다시 안 물음(재설치·기기 변경) | §7.1·§7.2, `nickname_states.confirmed_at`(서버) |
| 확정 안 하고 끄면 다시 물음 | 흐름 3 |
| 규칙 위반 이유 표시 / 실패 알림·재시도 / 로그아웃 | §7.2 상태 표, §6.4 |
| 길이·문자 서버 강제, 공백 정리, 예약어 8종, 사칭, 보이지 않는 문자, 이메일·URL | §2, §2.7, 스모크 11.1-2 |
| 기본 별명이 규칙 만족 | §3.2·§3.3, 스모크 11.1-3 |
| 중복 허용 / 금칙어 동작 | §6.1, §2.5 |
| 직접 쓰기 거부, 한 경로, 남·봇·묘비 불가, 읽기 보존 | §4, 스모크 11.2-2·5 |
| 프로필에서 바꾸기, 같은 규칙, 즉시 반영, 제한 없음, 실패 토스트 | §7.3, §7.5 "즉시의 뜻" |
| 기존 흐름 보존, 탈퇴 묘비, 이니셜, 문구 위치 | §6.3, §7.5, §9 |
| 고지 | §10, 단계 5 |
| 유닛·서버 테스트, analyze/test, 단계별 오너 확인(B는 두 번) | §11, §12 |

---

## 결정 필요

1. **관문의 상태 조회가 실패하면(오프라인·서버 오류) 어떻게 할까?**
   - (a) **본 화면으로 통과시키고 `debugPrint`만 남긴다. 다음 실행에 다시 묻는다**(설계 추천). 근거는 셋이다. 관문은 보안 장치가 아니다. 노출은 이미 서버에서 끊겼다(원칙 5). 확정한 99%의 사용자에게 오프라인 시작이 "별명 오류 화면"이 되면 안 된다. 관문이 깨지면 아무도 못 들어오는 위험(spec 트레이드오프 마지막 항목)을 구조적으로 없앤다. 대가: CLAUDE.md "에러는 삼키지 않는다"에 예외 한 줄이 늘어난다(VS 인트로, 위젯, 알림함과 같은 성격: 관문이 아니고, 사용자가 할 수 있는 일이 없고, 다음 실행에서 저절로 맞는다). 미확정 사용자는 그 세션을 기본 별명으로 지낸다.
   - (b) 오류 화면에 `다시 시도`와 `로그아웃`을 둔다. 규칙 예외가 필요 없다. 대가: 오프라인으로 켜면 확정한 사용자도 매번 이 화면에 막힌다. RPC가 깨지면 전원이 막힌다.
   - **추천: (a).** (a)로 정해지면 메인 세션이 CLAUDE.md 코딩 규칙의 예외 목록에 한 줄을 더한다.

2. **단어표(§3.1, 형용사 40·명사 40)와 예약어(§2.4, 21개)·금칙어(§2.5, 42개) 표를 이대로 승인하는가?**
   - 오너 결정 3·6이 "표만 보고 승인"으로 정했다. 고치고 싶은 단어는 표에서 빼거나 더하면 된다. 어떻게 고쳐도 §3.3 검증이 마이그레이션 시점에 조합 충돌을 잡는다.
   - 특히 볼 곳: 금칙어의 "뺀 것"(§2.5: `새끼`·`보지`·`자지`·`미친`·`걸레` 등. 오탐 때문에 뺐다), 예약어 `contains`가 무해한 이름을 막는 경우(`공식왕`, `badminton`, `탈퇴`가 든 이름), ASCII 혼동 문자 접기(`0→o`, `1→i`, `l→i`).
   - **추천: 표 그대로.**

3. **(spec 밖에서 발견한 사실) Google 로그인으로 Supabase Auth가 이름 말고도 프로필 사진 주소를 저장하고 있을 가능성이 높은데, 개인정보처리방침 1-가에 그 항목이 없다.**
   - Supabase Auth는 Google 로그인 때 `raw_user_meta_data`에 `full_name`·`name`·`email`과 함께 보통 `avatar_url`·`picture`도 저장한다. 앱은 이 값을 쓰지 않고 다른 이용자에게 보이지도 않는다. 하지만 서버에 저장된다는 사실이 방침의 "로그인 시 Google로부터 전달받는 것"(이메일·이름·식별자) 목록에서 빠져 있다. spec P0-7의 "사실과 다른 쪽으로 쓰지 않는다"에 걸린다.
   - (a) **developer가 §10의 키 조회로 확인하고, 있으면 오너가 이번 방침 수정 때 1-가에 "프로필 사진 주소 — 앱에서 쓰지 않으며 다른 이용자에게 보이지 않습니다"를 더한다**(추천). 어차피 같은 문서를 같은 시행일로 고치는 중이다.
   - (b) 이 기능에서는 다루지 않고 `TODO_BACKLOG.md`로 넘긴다. 대가: 고지와 사실의 어긋남 하나가 남은 채 배포될 수 있다.
   - **추천: (a).** 법적 고지 문구라 오너가 정한다.

## 오너 결정 (2026-11-24)

1. 관문의 상태 조회가 실패하면 **(a) 본 화면으로 통과시키고 `debugPrint`만 남긴다**(다음 실행에 다시 묻는다). 메인 세션이 CLAUDE.md 예외 목록에 한 줄을 더한다.
2. 단어표(§3.1)·예약어(§2.4)·금칙어(§2.5)를 **표 그대로 승인**.
3. 확인 끝(메인 세션이 키 이름만 읽기 전용으로 조회): `raw_user_meta_data`에 `avatar_url`·`picture`·`name`·`full_name`·`email` 등이 실제로 저장돼 있다. 따라서 **(a)** — 오너가 이번 방침 수정 때 1-가에 프로필 사진 주소 한 줄을 더한다(`todododo-legal`, 오너 몫). developer는 다시 조회하지 않아도 된다.
