# home-widget 1~3단계 리뷰 (reviewer, 2026-11-05)

대상: 커밋되지 않은 작업 트리(`git status` 기준). 기준 문서는 `spec.md`·`design.md`·`plan.md`·루트 `CLAUDE.md`.
범위는 구현된 1~3단계만이다(4~7단계는 "지금 코드가 그 단계를 막는가"만 봤다).

확인한 것: `flutter analyze` 이슈 0, `flutter test` 466개 통과(직접 실행). 네이티브는 실행하지 않았고
`visibleRows`의 Dart/Kotlin 규칙은 **전수 대조 스크립트**로 비교했다(아래 W1).

---

## 반드시 고칠 것

### C1. 정상 상태에서 위젯이 목록 대신 `null` 네 글자를 그린다 (`TodoWidgetProvider.kt:75`)

```kotlin
val centerText = payload.optString("centerText", "")
if (centerText.isNotEmpty()) { showCenter(views, centerText) } else { showRows(...) }
```

안드로이드(AOSP)의 `org.json`은 **upstream org.json과 다르게** 동작한다:

```java
public String optString(String name, String fallback) {
    Object object = opt(name);              // 명시적 null이면 JSONObject.NULL
    String result = JSON.toString(object);  // JSONObject.NULL -> "null" (String.valueOf)
    return result != null ? result : fallback;  // fallback은 "키가 아예 없을 때"만
}
```

즉 JSON이 `centerText` 자리에 명시적 null을 담고 있으면 `optString("centerText","")`는 빈 문자열이 아니라
**`null`이라는 네 글자 문자열**을 돌려준다. Dart는 상태 3(정상)·4(조회 실패, 목록 유지)·8(체크 실패)에서
그 자리를 null로 쓴다(`lib/features/todo/data/todo_widget_payload.dart:245`, `encode()`가 그대로 직렬화).
따라서 **할 일이 있는 정상 상태에서 줄이 하나도 그려지지 않고 가운데에 `null`이 뜬다.** 위젯의 주 경로가 깨진다.

- 같은 함정이 `pendingId`(`:123`)에도 있다. 지금은 `pendingAtMs`가 없어 `pendingFresh`가 false로 떨어져
  우연히 무해하지만, 6단계에서 `pendingAtMs`가 함께 실리면 "id가 `null`인 줄"을 찾다가 아무 줄도 pending이
  되지 않는 방식으로 조용히 틀린다.
- 고치는 길 둘(둘 다 하면 가장 안전):
  1. Dart `toJson()`에서 **null 키를 빼고** 쓴다(`fromJson`은 키가 없어도 null로 읽으므로 왕복 테스트는 그대로 통과한다).
  2. Kotlin에서 `if (payload.isNull("centerText")) "" else payload.optString("centerText", "")`로 읽는다.
- 실기기 확인 목록의 **첫 줄**로 올릴 것(지금 실기기에 올리면 바로 보인다).

### C2. 앱을 다시 켜면 홈 화면의 목록이 지워진다 — spec 상태 4가 성립하지 않는다

- `lib/core/navigation/main_shell.dart:40-47`이 **MainShell이 뜰 때마다** `publish(loading())`을 부른다.
  캐시는 그 자리에서 "할 일을 불러오는 중이에요"(items 빈 payload)로 **덮인다.**
- `TodoWidgetService._lastPublished`는 메모리에만 있다(`todo_widget_service.dart:19-23`). 프로세스가 새로
  시작하면 null이므로, 첫 조회가 실패하면 `fetchFailed(null)` → **상태 5**("할 일을 불러오지 못했어요")로 간다.
- 그래서 **"앱을 켰는데 네트워크가 없다"는 가장 흔한 경우에 지난 목록이 사라진다.** spec "P1. 상태별로 무엇을
  보여 주나" 2행(이전에 받아온 내용이 있으면 마지막 목록을 그대로 두고 낡았다는 사실을 한 줄로)과
  design 2.3 상태 4가 요구한 동작이 성립하지 않는다. design 2.3이 상태 2를 더한 이유는 "로그아웃 캐시가
  로그인한 사용자에게 보이는 것"을 막기 위함이었고, "앱 재시작마다 캐시를 비운다"는 뜻이 아니다.
- 증거 하나 더: 설계가 둔 `TodoWidgetHost.read()`(`todo_widget_host.dart:26-29`)를 **아무도 부르지 않는다**
  (`lib/`·`test/` 전수 grep). 기기 캐시를 "직전 목록"으로 되읽는 경로가 빠져 있다.
- 고치는 길: 서비스가 첫 발행 전에 `host.read()`로 `_lastPublished`를 채우고(실패는 로그만),
  `loading()`은 **읽어 온 캐시에 items가 없을 때만** 발행한다. 그러면 재시작 + 오프라인에서
  `지금은 못 불러왔어요 · 오전 9:14 기준`(상태 4)이 제대로 나온다.

---

## 고치면 좋은 것

### W1. Kotlin의 `moreCount`가 Dart `visibleRows`와 한 칸 어긋난다 (`TodoWidgetProvider.kt:121`)

전수 대조(줄 수 0~7 × 담긴 항목 0~8 × 전체 0~20, 1,700여 조합)에서 **어긋나는 조합은 한 종류뿐**이다:
`items`가 비었는데 `totalCount > rowCount`일 때 Kotlin은 줄 0개 + "그 외 N개"를, Dart는 0/0을 낸다.
Dart가 만드는 캐시로는 도달할 수 없다(items가 비면 `totalCount`가 0이고 `centerText`가 채워져 `showRows`가
아예 불리지 않는다). 그래도 규칙을 두 곳에 옮겨 적은 자리이므로 `shown > 0 &&`를 조건에 더해 완전히 같게
두는 쪽이 낫다.

도달 가능한 경계는 모두 일치했다(손 계산 + 스크립트):

| 미완료 | 줄 수 | 결과 |
|---|---|---|
| 0 | 1·2·4·6 | 줄 0 (centerText로 분기, `showRows` 미호출) |
| 1 | 4 | 1줄, 그 외 없음 |
| 6 | 6 | 6줄, 그 외 없음 |
| 7 | 6 | 5줄 + 그 외 2개 (5+2=7) |
| 8 | 4 | 3줄 + 그 외 5개 (3+5=8) |
| 9 | 6 | 5줄 + 그 외 4개 (5+4=9) |
| 9 | 2 | 1줄 + 그 외 8개 (1+8=9) |
| 9 | 1 | 1줄, 그 외 **없음**(추가 규칙 ④) |

규칙 ④("1줄 자리는 그 줄을 할 일에 쓴다")는 타당하다 — 유일한 줄을 안내로 바꾸면 할 일이 하나도 안 보인다.
대가는 4x1 위젯에서 "더 있다"를 알리지 못하는 것이고(spec "그 외 N개" 요구의 유일한 예외), note 줄은 남으므로
빈 사각형이 되지는 않는다. plan에 근거가 적혀 있고 Kotlin도 같은 규칙을 옮겼다.

### W2. "그릴 것이 없으면 반드시 대체 문구"(design 6.3)가 네이티브에 없다 (`TodoWidgetProvider.kt:75-83`)

`v`가 1이면서 items도 centerText도 note도 비어 있는 캐시를 읽으면 **빈 틀**이 그려진다(지금 Dart가 그런 캐시를
만들지는 않는다). `showRows` 뒤에 `shown == 0 && note.isEmpty()`면 `todo_widget_no_cache`로 떨어뜨리면
design이 "반드시"라고 적은 보장이 코드로도 성립한다.

### W3. 중복 발행 방지는 `fromTodos` 경로에서 거의 동작하지 않는다 (`todo_widget_service.dart:61-64`)

`publish`는 **JSON 전체**를 비교하는데 `fromTodos`는 매번 `now`를 찍는다
(`todo_widget_payload.dart:126,151-152`). 그래서 목록이 그대로여도 `todosProvider`가 데이터를 낼 때마다
`save` + 브로드캐스트가 다시 나간다. 틀리는 방향은 **안전한 쪽**이고(바뀐 것을 안 보내는 일은 없다)
⑤("성공한 발행만 직전으로 기억")도 같은 방향이라 기능 위험은 없다. 다만 plan ①이 적은 근거("중복 발행 판단이
무력해진다")는 절반만 맞다 — `fetchFailed`·`checkFailed`·`pending`에서는 되살아나지만 `fromTodos`는 여전히
매번 다르다. 이를 고정한 테스트(`todo_widget_publish_test.dart:24-35`)는 고정된 `now`를 넣어 통과하는 것이라
실제 동작을 대표하지 않는다. 진짜로 아끼려면 "항목·totalCount가 같으면 기준 시각과 note를 물려받는다"로
`fromTodos`를 바꿔야 한다(권고는 아니다 — 지금 비용은 브로드캐스트 몇 번이다).

### W4. `visibleRows` 경계 테스트 세 칸이 비어 있다 (`test/features/todo/todo_widget_payload_test.dart:244-284`)

지금 있는 것: (3,3,6)·(8,7,3)·(8,12,6)·(8,5,1)·(·,·,0). 공허하지 않다 — `rowCount - 1`을 `rowCount`로
바꾸면 256행이 깨지고, `rowCount == 1` 조항을 지우면 272행이 깨진다(규칙을 지우면 실패하는 테스트다).
빠진 것은 off-by-one이 가장 잘 나는 **`totalCount == rowCount`(6개/6줄)**, **`totalCount == rowCount + 1`
(7개/6줄)**, 그리고 **줄 수 2**다. 지금 값은 전수로 검산해 맞지만, 다음 사람이 규칙을 고칠 때 깨지는
자리가 바로 그 셋이다.

### W5. 같은 실패를 두 번 로그한다 (`main_shell.dart:103`)

`todosProvider error (widget cache): ...`는 `TodoListScreen`의 error 갈래가 이미 남기는 로그와 겹친다
(테스트 실행 출력에 두 줄이 같이 찍힌다). 하나로 줄이는 편이 낫다. 사용자 안내는 화면 쪽이 담당하므로
빠진 것은 없다.

### W6. 가짜의 미사용 갈래 (`test/features/todo/todo_widget_fakes.dart:116,121-133`)

`updateError`(브로드캐스트만 실패)와 `stored`/`read()`가 아직 아무 테스트에서도 쓰이지 않는다.
`read()`는 C2를 고치면 바로 쓰이고, `updateError`는 "캐시는 썼지만 다시 그리기가 실패했을 때
직전으로 기억하지 않는다"를 한 줄로 고정할 수 있는 갈래다(지금은 `save` 실패만 덮여 있다).

---

## 다음 단계로 넘길 것

- **`checkFailed`·`pending`은 죽은 코드가 아니라 6단계용이다.** 발행 지점이 6단계(체크 쓰기)이고, 지금
  부르는 자리를 만들면 아무도 읽지 않는 코드가 된다는 plan의 판단이 맞다(push 2단계 선례와 같다).
  `loggedOut`도 같은 뜻으로 4단계용이며 서비스 유닛 테스트로 덮여 있다.
- 다만 `checkFailed(null)`(`todo_widget_payload.dart:202-210`)은 `updatedAtMs: 0`을 쓴다 — 6단계에서
  이 갈래가 note를 갖게 되면 1970년 기준 시각(`오전 12:00 기준`)이 찍힐 수 있다. 또 이 갈래는 `centerText`만
  쓰고 `noteTone: danger`가 아무 데도 쓰이지 않는다. 6단계에서 함께 정리할 것.
- **⑦(앱 열기 PendingIntent를 2단계로 앞당김)은 타당하다.** Kotlin이 `todododo://widget/todo`를 상수로
  들고 있고(`TodoWidgetProvider.kt:209`) Dart `widgetTargetOf`가 이미 그 Uri를 해석하며 테스트도 있다
  (`todo_widget_payload_test.dart:325-336`). 5단계에 남는 것은 런치 Uri 수신·탭 이동뿐이라 막히는 것이 없다.
- **생성기 자기 검사가 없다.** `res/values/widget_resources.xml`은 생성물이지만 "소스와 어긋났는지"를 보는
  테스트가 없어 `AppStrings.widgetName`을 고치고 생성기를 안 돌리면 조용히 어긋난다. 지금은 문구 3개·색 7개가
  모두 일치함을 확인했다(`AppStrings`·`RetroPalette` 대조). 7단계(CLAUDE.md 개발 명령어에 생성기 추가) 때
  "생성 결과 == 지금 파일" 한 줄 테스트를 같이 넣으면 중복 정의가 영구히 막힌다.
- **glance-appwidget(남은 문제 ④) — 받아들일 비용이다.** 우리 코드가 Glance를 참조하지 않으므로 기능 위험이
  0이고, `home_widget`을 포크·교체하는 비용이 용량보다 크다. 단 `android/app/build.gradle.kts`에 R8 minify
  설정이 없어 release에서도 그 dex가 그대로 실린다 — 배포 전에 AAB 증가분을 한 번 재 보고 거슬리면
  minify를 켜는 쪽이 폰트를 포기한 것보다 큰 절약이 된다.

---

## 문서를 고쳐야 할 것

- **폰트 미적용(②)이 design에 반영되지 않았다.** 실측 `assets/fonts/galmuri/Galmuri11.ttf` = 5,376,428바이트
  (5.37MB) > design 2.5가 못 박은 2.5MB → **분기 자체는 설계가 미리 정한 대로이고 타당하다.** 그런데
  design.md에 다음 서술이 코드와 어긋난 채 남아 있다:
  - `design.md:161` (2.4 표의 폰트 행 — `res/font/galmuri11.ttf`)
  - `design.md:166,169,173` (2.5 제목 "폰트는 갈무리11 regular 한 벌", "`res/font/`에 둔다",
    `build.gradle.kts` 복사 과제)
  - `design.md:418` (9장 표의 `res/font/galmuri11.ttf` 행)
  → 2.5에 "**2026-11-04 구현: 실측 5.37MB로 한도 초과 → 폰트 미적용, 시스템 폰트 + 색만.**" 각주를 넣고
  2.4·9장 행이 그 각주를 가리키게 할 것. `spec.md`는 폰트를 한 번도 언급하지 않아 고칠 것이 없다(grep 확인).
- **사용자에게 어떻게 보이나**: 홈 화면에서 위젯만 시스템 폰트(Roboto)로 뜨고 종이색·2dp 테두리·줄 면만
  레트로다. 앱을 열면 전부 비트맵 폰트라 **같은 앱의 두 얼굴**이 된다 — 기능에는 영향이 없고 "장식이 기능을
  막지 않는다"는 원칙에 맞지만, 다음 사람이 버그로 오해하기 쉽다. 7단계 `DEPLOY.md` 실기기 체크리스트에
  "위젯 폰트는 앱과 다르다(의도, 용량 한도)" 한 줄을 넣을 것. 서브셋 폰트(상용 한글 수백 KB)는 배포 후
  재검토감이라 `TODO_BACKLOG.md` 한 줄 후보다.
- **plan.md:199-206(달라진 점 ①)의 근거를 한 줄 보정할 것** — W3 참고. "`fromTodos`는 발행 시각이 매번
  달라 여전히 매번 발행된다. 되살아난 것은 목록을 물려받는 발행(`fetchFailed`·`checkFailed`·`pending`)뿐이다."

---

## 확인했고 문제 없는 것 (근거)

- **달라진 점 ①(`updatedAtMs` = 목록 기준 시각)은 두 쪽에서 일관된다.** `fetchFailed`는 이전 목록과 함께
  `previous.updatedAtMs`를 **그대로 물려받고**(`todo_widget_payload.dart:191-197`) note도 그 시각으로 적는다
  → "낡았다"는 안내가 거짓이 되지 않는다. 테스트가 그것을 못 박았다(`todo_widget_payload_test.dart:109-126`:
  3시간 뒤에 실패해도 note는 `오전 9:14 기준`). `checkFailed`(:215)·`pending`(:231)도 같다. 새 JSON 키를
  더하지 않았고 design 2.2의 키 목록도 그대로다. 남은 티 하나: `fetchFailed`가 `previous.tapTarget`을
  물려받지 않는다(:192-197) — items가 있는 payload의 tapTarget은 항상 `todo`라 지금은 무해하다.
- **상태 8종의 도달 경로**: 1 `loggedOut`=4단계(서비스 유닛 테스트로만), 2 `loading`=`main_shell.dart:40-47`,
  3·6·7 `fromTodos`=`main_shell.dart:117-119`, 4·5 `fetchFailed`=`main_shell.dart:105-113`,
  8 `checkFailed`=6단계, "캐시 없음"=`TodoWidgetProvider.kt:68-72`. 도달 못 하는 상태는 없다.
- **⑥(isLoading일 때 발행하지 않음)이 로그인 직후 빈 위젯을 만들지 않는다.** `initState`가 먼저
  `loading()`을 발행하고, 첫 결과에서 `isLoading`이 false가 되어 `fromTodos`/`fetchFailed`가 발행된다.
  `test/widget_test.dart:899-910`이 `saved.first`=불러오는 중, `saved.last`=빈 목록 안내로 그 순서를 박아 뒀다.
  새로고침 중에 낡은 목록을 그대로 두는 것은 spec의 "갱신" 요구와 어긋나지 않는다.
- **도메인 경계(spec "P0. 도메인 경계") 위반 없음.** 위젯 경로의 import는 `core/strings.dart`와
  `features/todo/data/todo.dart`뿐이고(`todo_widget_payload.dart:11-14`) 대결·상대·승패·점수·판정이
  한 조각도 없다. `main_shell`의 새 블록은 `todosProvider`만 본다. 클라이언트 판정 계산도 없다.
  기기 시계를 쓰는 자리는 note의 시각 문장 하나이고 주석으로 그 이유가 박혀 있다(`:336-342`).
- **프라이버시 최소 수집.** 캐시에 담기는 것은 할 일 `id`·`title`(80자 자름)·미완료 개수·문구·시각·
  `pendingId`뿐이다 — 완료 여부·생성 시각·사용자 id·대결 정보는 담지 않는다(`toJson`, `:241-256`).
  로그에 할 일 제목이 찍히는 자리는 없다(`publish failed: $error`, `todosProvider error: $error`).
- **에러 처리의 예외가 위젯 발행에만 적용된다.** 삼키는 catch는 `TodoWidgetService.publish` 하나이고
  (`todo_widget_service.dart:72-74`, design 3.2의 의도된 예외), 조회 실패는 화면의 기존 `AsyncValue.error`
  갈래가 그대로 사용자에게 알린다. 쓰기(체크) 실패를 삼키는 코드는 아직 없다(6단계).
- **다른 세션과의 충돌 회피가 지켜졌다.** `lib/main.dart`·`lib/core/push/`·`supabase/` 미변경(`git status`),
  `pubspec.yaml`은 의존성 1줄 + 주석 2줄, `lib/core/strings.dart`는 파일 끝 새 구역(`:349-379`),
  `main_shell.dart`는 독립 블록 2곳(`initState` 1블록, `build`의 `ref.listen` 1블록).
- **dev-standards 적합**: `data/`에 모델·순수 함수·네이티브 래퍼, `domain/`에 provider·서비스,
  provider 이름 `todoWidgetHostProvider`·`todoWidgetServiceProvider`, 가짜는 `extends` +
  `overrideWithValue`, 테스트는 `test/features/todo/`에 미러링, 한국어 테스트 이름. 새 SQL·RPC가 없어
  RLS·`auth.uid()` 가드·`revoke execute` 규칙의 적용 지점이 없다.
