# home-widget 설계

## 참고

- spec.md: `docs/specs/home-widget/spec.md` (오너 승인 완료, 이 설계의 유일한 요구사항). 특히 "## 결정 기록"(안 D·체크 허용·제목 노출), "P0. 쓰기 동작", "P0. 갱신 주기와 시간 표시", "P1. 1단계 — 상태별로 무엇을 보여 주나", "P0. 도메인 경계", "P0. 홈 화면 노출", "## 범위 밖"이 기준이다.
- **이 설계는 1단계(투두 위젯)만 다룬다.** spec "2단계(조건부). 진행 중인 대결 위젯"은 **설계하지 않는다**(2026-11-04 오너, 안 D — 배포 전에 내는 것은 투두 위젯 하나).
- 선례로 읽은 문서: `docs/specs/push-notification/design.md`(네이티브 경계·권한·탭 라우팅·단계 분할·"알림은 관문이 아니다"는 실패 처리 태도), `docs/specs/recruit-browse/design.md`(문서 형식·순수 함수 분리·테스트 전략).
- 근거로 읽은 현재 구현: `lib/features/todo/{data/todo.dart,data/todo_repository.dart,domain/todo_providers.dart,presentation/todo_list_screen.dart}`, `lib/core/push/*`(5개), `lib/core/{strings.dart,app_links.dart,navigation/main_shell.dart,navigation/app_tab.dart,supabase/supabase_init.dart,theme/retro_palette.dart}`, `lib/features/auth/{data/auth_repository.dart,presentation/auth_gate.dart}`, `lib/main.dart`, `pubspec.yaml`, `android/{settings.gradle.kts,app/build.gradle.kts,app/src/main/AndroidManifest.xml,app/src/main/kotlin/.../MainActivity.kt,app/src/main/res/values/colors.xml}`, `supabase/migrations/20260818220000_profiles_and_todos.sql`.
- **패키지 소스까지 확인한 사실**(추측하지 않기 위해 pub-cache를 직접 읽었다. 1.1·4.2에서 근거로 쓴다):
  - `shared_preferences_android-2.4.27/lib/src/shared_preferences_android.dart:35` — 레거시 `SharedPreferences` API는 키에 `flutter.` 접두사를 붙인다.
  - 같은 패키지 `.../LegacySharedPreferencesPlugin.kt:36` + `SharedPreferencesPlugin.kt:33` — 레거시 API는 안드로이드 XML 파일 `FlutterSharedPreferences`를 쓰고, 신 API(`SharedPreferencesAsync`)는 **같은 이름의 DataStore**를 쓴다(둘은 다른 저장소다).
  - `supabase_flutter-2.17.2/lib/src/supabase.dart:128-137` — 세션은 `SharedPreferencesLocalStorage`에 `sb-<project-ref>-auth-token` 키로 저장된다(레거시 API 경유 = 위 XML 파일).
  - `supabase_flutter-2.17.2/lib/src/supabase_auth.dart:170-186` — 앱이 **resume될 때 로컬 저장소를 다시 읽지 않는다**. `startAutoRefresh()`만 부른다.
  - `gotrue-2.27.2/lib/src/gotrue_client.dart:1611-1633` — refresh가 `refresh_token_already_used`로 실패하면 **메모리 세션이 아직 만료되지 않았을 때만** 버티고, 만료된 뒤에는 `_removeSession()` + `signedOut`을 쏜다(= 사용자가 로그아웃된다).
- **확인한 선례의 한계**: `lib/core/push/`에는 **백그라운드 메시지 핸들러가 없다.** push 설계는 일부러 FCM `notification` 페이로드로 시스템이 직접 그리게 해서 백그라운드 isolate를 피했다(그 design.md "알림 문구" 절). 즉 **이 저장소에는 "백그라운드 Dart에서 Supabase를 쓴다"는 선례가 없고, 이 feature가 처음이다.** 그래서 4장이 이 설계에서 가장 긴 장이고, 가장 보수적으로 썼다.

---

## 설계 원칙 (전체를 관통하는 5가지)

1. **위젯은 개인 투두만 다룬다.** 대결 정보를 한 조각도 싣지 않고, 대결 테이블을 **읽지도 않는다**. 위젯 코드에서 `battles`·`battle_submissions`·`player_stats`·점수·전적에 닿는 경로를 만들지 않는다(spec "P0. 도메인 경계"). 그래서 이 설계에는 대결 상태 전이·판정·한도 이야기가 애초에 등장하지 않는다.
2. **네이티브는 그리기만 한다. 판단은 Dart가 한다.** 어떤 상태인지, 어떤 문구를 쓰는지, 몇 개까지 담는지, 기준 시각을 어떻게 적는지는 **전부 Dart의 순수 함수**가 정해 캐시에 적어 둔다. 네이티브(Kotlin)가 하는 판단은 "이 높이에 몇 줄이 들어가나"와 "숫자 하나를 서식에 끼운다"뿐이다. 테스트할 수 있는 쪽에 판단을 모으기 위함이다(CLAUDE.md "도메인 로직은 반드시 유닛 테스트", 네이티브는 테스트하지 않는다).
3. **위젯은 서버를 직접 부르지 않는다.** 위젯이 보여 주는 것은 **앱이 마지막으로 받아온 목록의 기기 캐시**다. 백그라운드에서 네트워크·인증을 쓰는 경로는 **체크(쓰기) 한 가지**뿐이다(3.1의 비교 참고). 읽기에서 백그라운드 인증을 없애는 것이 이 설계의 가장 큰 단순화다.
4. **실패는 삼키지 않지만, 위젯 때문에 앱이 망가지지도 않는다.** 체크 실패는 위젯 안 한 줄로 말한다(spec의 조건). 반대로 캐시 쓰기·위젯 갱신 실패는 `debugPrint`만 남기고 앱 동작을 막지 않는다 — 위젯은 관문이 아니다(push의 "알림은 관문이 아니다"와 같은 성격의 예외이고, CLAUDE.md 코딩 규칙의 예외 목록에 한 줄 더한다).
5. **앱의 인증(세션)을 건드리지 않는다.** 위젯 때문에 로그인이 끊기는 일은 어떤 경로로도 없어야 한다. 4.2가 이 원칙 하나로 결정됐다.

---

## CLAUDE.md 규칙 대조

| 규칙 | 이 설계에서 |
|---|---|
| 판정 로직은 클라이언트가 아니라 DB/Edge | 위젯은 판정에 닿지 않는다. 쓰는 것은 `todos.is_done` 하나뿐이다 |
| 클라이언트에서 승패 계산 금지 | 위젯에 승패·점수·전적이 없다 |
| 스키마 변경은 마이그레이션으로만 | **스키마 변경 없음**(11장). `todos` 테이블과 기존 RLS만 쓴다 |
| 사용자에게 보이는 문자열은 한국어, `lib/core/strings.dart`에 모은다 | 모든 위젯 문구를 `AppStrings`에 둔다. 네이티브가 쓰는 두 문자열은 **생성기가 `AppStrings`에서 뽑아** XML로 쓴다(2.3) — 두 곳에 손으로 적지 않는다 |
| 에러는 삼키지 않는다 | 체크 실패는 위젯 한 줄. 캐시 발행 실패는 로그만(원칙 4, 예외로 CLAUDE.md에 한 줄 추가) |
| 새 화면 하나 = 새 커밋 하나 | 13장의 단계가 그대로 커밋 단위다 |
| 새 패키지는 먼저 기존 패키지로 가능한지 확인하고, 추가하면 이유를 커밋 메시지에 | 1.1에서 `shared_preferences`만으로 되는 범위를 먼저 따졌다. `home_widget` 하나를 추가하고 이유를 커밋 메시지에 적는다 |
| iOS 대응·i18n·미래 대비 추상화 금지 | 안드로이드 전용 리시버 하나, 문구는 한국어 상수, 위젯 종류를 늘릴 것을 가정한 설정·추상화를 만들지 않는다(대결 위젯용 자리도 만들지 않는다) |
| 기존 코드 스타일을 따른다 | 네이티브 경계는 `PushMessaging`처럼 **얇은 래퍼 + provider**로 감싸 위젯 테스트에서 가짜로 바꾼다 |

---

## 1. 무엇으로 만드나

### 1.1 Dart → 네이티브 데이터 전달: `home_widget` 패키지를 추가한다

먼저 **현재 의존성만으로 되는지**를 따졌다(CLAUDE.md).

| 필요한 일 | 현재 의존성으로 되는가 |
|---|---|
| (a) Dart가 쓴 값을 Kotlin이 읽기 | **된다.** `shared_preferences`(레거시 API)는 안드로이드에서 XML 파일 `FlutterSharedPreferences`에 `flutter.<키>`로 저장하므로, Kotlin이 `context.getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE).getString("flutter.todo_widget_payload", null)`로 그대로 읽는다. 위 "참고"에서 패키지 소스로 확인했다. 단 **문자열 하나로 저장할 때만** 안전하다 — double·List<String>은 플러그인이 자기 접두사를 붙여 인코딩하므로 네이티브가 그대로 읽을 수 없다. 우리는 JSON 문자열 한 개만 쓰므로 조건을 만족한다 |
| (b) "데이터가 바뀌었으니 위젯을 다시 그려라"를 앱에서 일으키기 | **안 된다.** `AppWidgetManager.updateAppWidget`/브로드캐스트는 네이티브만 부를 수 있다. MethodChannel + Kotlin 코드를 직접 써야 한다 |
| (c) 위젯 버튼 탭으로 **앱이 꺼진 상태에서** Dart 코드를 깨우기 | **안 된다.** BroadcastReceiver에서 `FlutterEngine`을 만들고, `FlutterCallbackInformation`으로 Dart 콜백 핸들을 복원해 실행하고, 그 핸들을 저장·갱신하는 코드를 직접 써야 한다 |
| (d) 위젯 탭으로 앱을 열 때 "무엇을 눌렀는지"를 Dart에 전달(콜드 스타트 포함) | **안 된다.** Intent extras/data를 Dart가 읽는 길이 없다(현재 앱에 MethodChannel이 하나도 없다) |

(b)(c)(d)를 직접 만들면 Kotlin 200줄 남짓(BroadcastReceiver + FlutterEngine 수명 관리 + 콜백 핸들 영속화 + MethodChannel 3종)이고, 그 코드는 **이 앱의 도메인과 아무 상관이 없는 배관**이다. 틀려도 컴파일은 되고 실기기에서 "아무 일도 안 일어난다"로만 드러나는 종류라 1인 개발에서 가장 비싼 코드다.

**결론: `home_widget` 하나를 추가한다.** 그것이 대신 해 주는 것이 정확히 (a)~(d)다.

| `home_widget`이 주는 것 | 우리가 쓰는 API |
|---|---|
| 전용 prefs 파일(`HomeWidgetPreferences`)에 값 쓰기/읽기 | `HomeWidget.saveWidgetData<String>`, `getWidgetData<T>` |
| 위젯 다시 그리기 요청 | `HomeWidget.updateWidget(name: 'TodoWidgetProvider')` |
| 위젯 버튼 탭 → 백그라운드 Dart 콜백(앱이 꺼져 있어도) | Kotlin `HomeWidgetBackgroundIntent.getBroadcast(context, uri)` + Dart `HomeWidget.registerInteractivityCallback(fn)` |
| 위젯 탭 → 앱 열기 + 어떤 Uri로 열렸는지 | Kotlin `HomeWidgetLaunchIntent.getActivity(...)` + Dart `initiallyLaunchedFromHomeWidget()`(콜드) / `widgetClicked` 스트림(이미 떠 있을 때) |

- 커밋 메시지에 적을 이유(CLAUDE.md): "위젯 데이터 전달·갱신 브로드캐스트·위젯 탭의 백그라운드 Dart 콜백·런치 Uri 전달을 대신한다. `shared_preferences`로는 값 전달만 되고 나머지 셋은 Kotlin 배관을 직접 써야 한다."
- **검증 항목(구현 2단계)**: 이 저장소는 AGP 9.1.0 / Kotlin 2.4.0이다. `home_widget`의 안드로이드 모듈이 이 조합에서 빌드되는지, `minSdk` 요구치가 `flutter.minSdkVersion`보다 높은지를 **먼저** 확인한다(push 2단계에서 google-services 플러그인 버전으로 같은 종류의 함정을 겪었다). 빌드가 안 되면 후퇴 경로는 (a)만 `shared_preferences`로 하고 (b)(c)(d)를 직접 Kotlin으로 쓰는 것이다 — 위에서 확인한 파일 이름·접두사가 그때의 계약이 된다.
- `home_widget`의 iOS 전용 API(`setAppGroupId` 등)는 쓰지 않는다.

### 1.2 위젯을 그리는 수단: RemoteViews(XML) — 고정 줄 레이아웃. Glance도 `RemoteViewsFactory`도 쓰지 않는다

| 안 | 내용 | 판단 |
|---|---|---|
| A | **RemoteViews + 정적 XML에 줄을 N개 미리 선언하고 남는 줄은 `GONE`** | **채택** |
| B | RemoteViews + 컬렉션 위젯(`RemoteViewsService`/`RemoteViewsFactory`, `setPendingIntentTemplate` + `setOnClickFillInIntent`) | 기각 |
| C | Jetpack Glance(`androidx.glance:glance-appwidget`) | 기각 |

- **A를 고르는 이유.** 보여 줄 줄 수가 최대 6이고(6장) **스크롤이 필요 없다**(spec: 자리에 담기지 않으면 "그 외 N개"로 알린다). 줄 수가 고정이면 항목별 체크 버튼의 탭 처리가 `setOnClickPendingIntent(R.id.row1_check, pi1)`처럼 **줄마다 PendingIntent 하나**로 끝난다. 요청 코드를 줄 번호로 구분하면 `PendingIntent.getBroadcast(context, rowIndex, intent, FLAG_IMMUTABLE or FLAG_UPDATE_CURRENT)`만으로 충돌 없이 분기된다. 새 의존성·새 manifest 컴포넌트·새 빌드 설정이 **하나도 늘지 않는다**.
- **B를 기각하는 이유.** 항목별 클릭을 템플릿 + fill-in intent로 처리해야 하고, `RemoteViewsService`를 manifest에 등록하고 `notifyAppWidgetViewDataChanged`로 따로 깨워야 한다. 스크롤을 얻는 대가인데 우리는 스크롤을 쓰지 않기로 이미 정했다(spec). 얻는 것 없이 움직이는 부품이 셋 늘어난다.
- **C를 기각하는 이유.** Compose 런타임 의존성과 빌드 설정(Compose 컴파일러 플러그인·BOM·AGP/Kotlin 정렬)이 늘어난다. 이 저장소의 안드로이드 설정은 지금 Flutter 기본에서 거의 벗어나지 않은 상태이고(Glance를 넣으면 `settings.gradle.kts`·`app/build.gradle.kts`가 둘 다 바뀐다 — 그 두 파일 중 하나는 다른 세션과 겹칠 수 있는 영역에 가깝다), 배포 임박·1인 개발에서 **빌드가 깨질 가능성**이 가장 큰 변경이다. 얻는 것은 Kotlin 코드의 가독성뿐이고, 항목별 탭 처리는 Glance에서도 `actionRunCallback`이라는 또 다른 배관이 필요하다. 6줄짜리 목록에 Compose를 들이지 않는다.
- 결과: 안드로이드 쪽 변경은 **`res/` 파일 몇 개 + Kotlin 한 파일 + manifest의 `<receiver>` 한 블록**이고 Gradle 파일은 (폰트 복사 과제를 빼면) 건드리지 않는다.

---

## 2. 데이터 모델 — 기기 캐시 하나 (서버 스키마 변경 없음)

### 2.1 저장 위치와 키

| 항목 | 값 |
|---|---|
| 저장소 | `home_widget`의 prefs 파일(`HomeWidgetPreferences`). 앱 전용 저장소다 |
| 키 | `todo_widget_payload` — **JSON 문자열 한 개**. 여러 키로 쪼개지 않는다(여러 키를 쓰면 네이티브가 반쯤 갱신된 상태를 읽을 수 있다) |
| 쓰는 쪽 | **Dart만** 쓴다. Kotlin은 읽기만 한다 |
| 읽는 쪽 | Kotlin(그리기), Dart(중복 탭 판단) |
| 지우는 쪽 | 로그아웃·탈퇴 때 Dart가 "로그인하지 않음" 상태로 **덮어쓴다**(8장). 키를 지우는 것보다 덮어쓰는 것이 낫다 — 키가 없으면 네이티브가 "아직 아무것도 모른다" 화면을 띄우는데, 그건 로그아웃 상태와 다른 뜻이다 |

사진·대결·상대 정보는 캐시에 **들어가지 않는다**(원칙 1). 들어가는 개인 정보는 **내 미완료 할 일 제목**뿐이고, 그것이 홈 화면에 보이는 것은 오너가 결정한 사항이다(spec 결정 기록 3).

### 2.2 JSON 스키마

```json
{
  "v": 1,
  "items": [ { "id": "<uuid>", "title": "장보기" } ],
  "totalCount": 12,
  "centerText": null,
  "note": "할 일 · 오전 9:14 기준",
  "noteTone": "muted",
  "moreFormat": "그 외 %d개",
  "pendingId": "<uuid|null>",
  "pendingAtMs": 1730000000000,
  "pendingLabel": "쓰는 중",
  "tapTarget": "todo",
  "updatedAtMs": 1730000000000
}
```

| 키 | 뜻 | 비고 |
|---|---|---|
| `v` | 스키마 판 번호 | 네이티브가 모르는 판이면 "앱을 열어 주세요" 대체 화면으로 떨어진다(앱만 업데이트되고 위젯 코드가 옛 것일 수는 없지만, 반대로 캐시가 새 앱 → 구 위젯인 순간은 업데이트 직후 존재할 수 있다) |
| `items` | 그릴 줄. **미완료만**, 앱과 같은 순서(2026-11-09 `todo-due-date` → 2026-11-10 `todo-reorder`: 앱과 같은 순서 = **사용자가 끌어 정한 순서**. 서버의 `order by position`이 그 순서를 만들고 페이로드는 보존만 한다. `docs/specs/todo-reorder/design.md` 2장) | 최대 **8개**만 담는다(6줄 + 여유). 제목은 80자에서 자른다 |
| `totalCount` | 미완료 **전체** 개수 | "그 외 N개" 계산용(`totalCount - 그린 줄 수`) |
| `centerText` | 목록 대신 가운데에 띄울 안내 문구 | `items`가 빈 상태에서만 채운다 |
| `note` | 아래 한 줄. 상태 문구·기준 시각·실패 안내가 모두 여기로 모인다 | Dart가 완성된 문장을 넣는다 |
| `noteTone` | `muted`(보조색) / `danger`(실패) | 네이티브는 색만 고른다 |
| `moreFormat` | `그 외 %d개` | **네이티브가 하는 유일한 문자열 조립**. 숫자 하나를 끼운다 |
| `pendingId`·`pendingAtMs`·`pendingLabel` | 지금 체크를 쓰고 있는 할 일 | 네이티브는 `now - pendingAtMs < 60초`일 때만 그 줄을 `pendingLabel`로 바꿔 그린다(4.3) |
| `tapTarget` | `todo`(할 일 화면) / `login`(로그인) | 지금은 둘 다 "앱 열기"로 같다. 미로그인 상태면 앱이 알아서 로그인 화면을 띄우므로 네이티브 분기는 없다. 값은 남겨 두되 **대결용으로 확장하지 않는다** |
| `updatedAtMs` | 발행 시각 | `note`의 기준 시각은 Dart가 이미 문장으로 만들어 두므로, 이 값은 디버깅·중복 발행 판단용이다 |

### 2.3 상태 7가지 → 캐시가 어떻게 채워지나

spec "P1" 표의 여섯 상태에 **로그인 직후 첫 조회 중**을 하나 더했다. 이유: 로그아웃 캐시를 그대로 두면 로그인한 사용자에게 "로그인하면 할 일이 여기에 보여요"가 1초쯤 보이고, 그 사이 조회가 실패하면 그 거짓말이 그대로 남는다. spec이 금지한 것은 빈 사각형·오류 코드이고, 이 줄을 더하는 것은 그 금지와 어긋나지 않는다.

| # | 상태 | `items` | `centerText` | `note` (제안 문구, `AppStrings`에 확정) | `noteTone` |
|---|---|---|---|---|---|
| 1 | 로그인하지 않음 | **비움** | `로그인하면 할 일이 여기에 보여요` | (비움) | muted |
| 2 | 로그인 직후 조회 중 | 비움 | `할 일을 불러오는 중이에요` | (비움) | muted |
| 3 | 정상 | 미완료 목록 | null | `할 일 · 오전 9:14 기준` | muted |
| 4 | 조회 실패(이전 목록 있음) | **직전 목록 유지** | null | `지금은 못 불러왔어요 · 오전 9:14 기준` | muted |
| 5 | 조회 실패(이전 목록 없음) | 비움 | `할 일을 불러오지 못했어요. 눌러서 다시 시도해요` | (비움) | muted |
| 6 | 할 일이 하나도 없음 | 비움 | `할 일이 없어요. 눌러서 추가해요` | (비움) | muted |
| 7 | 미완료가 없음(전부 완료) | 비움 | `할 일을 모두 끝냈어요` | (비움) | muted |
| 8 | 체크가 반영되지 않음 | **직전 목록 유지**(지운 적이 없으므로 자동으로 되살아난다) | null | `체크하지 못했어요. 눌러서 앱에서 확인해요` | **danger** |

- 6과 7을 가르는 값은 "전체 할 일 개수"다. 그래서 캐시를 만들 때 **완료까지 포함한 전체 길이**를 함께 본다(서버에서는 이미 둘 다 받아온다 — `fetchTodos`는 완료 여부로 필터하지 않는다).
- 8은 **상태가 아니라 note의 덮어쓰기**다. 실패 직전 목록 그대로에 note만 danger로 바꾼다. 그래서 "그 할 일이 위젯 목록에 다시 나타난다"는 spec 조건이 **별도 로직 없이** 성립한다 — 애초에 목록에서 지우지 않았다(4.3).
- 8의 note는 **다음 발행 때 사라진다**(앱이 목록을 다시 받아오거나, 다른 체크가 성공하면). 따로 지우는 타이머를 두지 않는다.
- 실패 문구에 서버 오류 메시지·코드·영문을 넣지 않는다(spec). 캐시에 `error` 원문을 담는 키 자체가 없다.

### 2.4 문구·색·폰트가 네이티브로 가는 길

| 무엇 | 어디서 오나 | 근거 |
|---|---|---|
| 위젯에 보이는 거의 모든 문구 | **캐시 JSON**(위 표의 `centerText`·`note`·`pendingLabel`·`moreFormat`). 원본은 `lib/core/strings.dart` | 두 곳에 적지 않는다. 문구를 고치면 다음 발행에서 위젯까지 따라온다 |
| 네이티브가 가져야 하는 문자열 **딱 3개** | `res/values/widget_resources.xml`에 **생성기가 써 준다**: 위젯 선택기에 뜨는 이름(`android:label`), 위젯 설명(`android:description`), 캐시가 아예 없을 때의 한 줄(`앱을 한 번 열어 주세요`) | 이 셋은 "캐시가 없을 때"와 "위젯 선택기"라서 캐시로 전달할 수 없다. 손으로 중복 정의하면 어긋나므로 **`AppStrings`에서 뽑아 생성**한다 |
| 색 | 같은 생성기가 `RetroPalette`에서 뽑아 같은 XML에 쓴다 | `tool/generate_launcher_icons.dart`가 이미 `res/values/colors.xml`을 `RetroPalette`에서 생성하는 선례가 있다. 그 파일을 덮지 않도록 **다른 파일**(`widget_resources.xml`)에 쓴다 |
| 폰트 | ~~`res/font/galmuri11.ttf`~~ → **미적용**(시스템 폰트) | 2.5의 각주 참고(2026-11-04 구현에서 용량 한도 초과로 넣지 않았다) |

- 생성기: **새 파일 `tool/generate_widget_resources.dart`**(기존 아이콘 생성기를 고치지 않는다 — 아이콘 생성이 깨지면 스토어 자산까지 영향을 받는다). 실행법은 기존과 같은 모양(`flutter test tool/generate_widget_resources.dart`)이고 CLAUDE.md 개발 명령어에 한 줄 더한다(13장 7단계).
- 생성 파일 머리에 "생성기가 만든다. 직접 고치지 말 것" 주석을 넣는다(colors.xml 선례와 같은 문장).

### 2.5 레트로 테마를 어디까지 맞추나 — 색은 전부, 폰트는 **미적용**(용량 한도 초과)

> **2026-11-04 구현 결과(각주).** 아래 "폰트" 항목은 **적용되지 않았다.** 이 절이 미리 못 박은
> 숫자 기준("TTF가 2.5MB를 넘으면 폰트를 넣지 않고 시스템 폰트 + 색만 맞춘다")에 따른 분기다 —
> `assets/fonts/galmuri/Galmuri11.ttf` 실측 **5,376,428바이트(5.37MB)** > 2.5MB.
> 그래서 `res/font/`도, `android/app/build.gradle.kts`의 복사 과제도 만들지 않았고(**Gradle 파일을
> 한 줄도 건드리지 않았다**), 위젯은 **색·테두리만 레트로이고 글꼴은 시스템 폰트(Roboto)** 다.
> 홈 화면의 위젯과 앱 화면의 글꼴이 달라 보이는 것은 **의도된 차이**이고 버그가 아니다
> (장식이 기능을 막지 않는다). 2.4 표의 폰트 행과 9장의 `res/font/`·`build.gradle.kts` 행도 이
> 각주를 따른다. 서브셋 폰트(수백 KB)로 다시 시도하는 것은 배포 후 재검토감이다.

- **색: 전부 맞춘다.** 비용이 사실상 0이다(2.4의 생성기가 `RetroPalette`에서 뽑는다). 쓰는 색은 `paper`(위젯 배경), `surface`(줄 면), `ink`(테두리·글자), `inkMuted`(note), `sunken`(체크 칸 면), `danger`(실패 note), `primary`(강조가 필요하면). 테두리·그림자는 `res/drawable/`의 `<layer-list>`/`<shape>`로 2dp 선 + 2dp 바닥 두께를 흉내 낸다 — 앱의 `PixelFrame.raised`와 같은 모양을 노린다. 픽셀 아이콘(`PixelIcons`)은 Flutter에서 직접 그리는 것이라 RemoteViews에 재사용할 수 없으므로, 체크 칸은 `<shape>` 사각형으로 대신한다.
- **폰트: 갈무리11 regular만 `res/font/`에 둔다** — **미적용으로 끝났다(위 각주). 아래는 그 판단의 기록이다.** 근거:
  - 위젯 레이아웃 XML에서 `android:fontFamily="@font/galmuri11"`은 런처가 **우리 APK의 리소스**를 읽어 적용하므로 동작한다(실기기 확인 항목으로 둔다. 안 되면 시스템 폰트로 떨어뜨리고 색만 맞춘다 — 장식 실패가 기능을 막지 않는다).
  - 비트맵 폰트는 이 앱의 인상 그 자체다. 홈 화면에 시스템 폰트로 뜨면 "다른 앱 위젯"처럼 보인다.
  - **bold는 넣지 않는다.** 한글 TTF 한 벌의 용량이 작지 않고(두 벌이면 두 배다) 위젯에서 굵기로 구분할 정보 위계가 없다 — 줄과 note의 구분은 색과 크기로 충분하다.
  - **git에는 TTF를 한 벌만 둔다.** `android/app/build.gradle.kts`에 복사 과제를 하나 두어 `assets/fonts/galmuri/Galmuri11.ttf`를 빌드 중 생성 리소스 디렉터리의 `font/galmuri11.ttf`로 복사하고 그 디렉터리를 `sourceSets["main"].res`에 더한다(리소스 이름 규칙상 소문자·숫자·`_`만 쓸 수 있어 이름을 바꿔 복사한다). APK 안에는 결과적으로 두 벌이 들어가는데(Flutter asset + 안드로이드 리소스) 그 용량 증가는 받아들인다.
  - **판단 기준을 숫자로 둔다**: 구현 때 TTF가 2.5MB를 넘으면 폰트를 넣지 않고 시스템 폰트 + 색만 맞춘다. 배포 직전에 AAB 용량을 몇 MB씩 늘리는 결정을 설계가 미리 못 박지 않는다.
  - **라이선스**: 갈무리는 OFL 1.1이고 이미 `assets/fonts/galmuri/LICENSE.txt`를 번들해 앱 안 라이선스 화면에 고지한다(`main.dart`). 같은 APK 안에서 쓰는 자리가 하나 늘어나는 것은 OFL이 허용한다(예약 이름 규칙상 **파일 이름만 소문자로 바꾸고 글꼴 이름·내용은 바꾸지 않는다** — 서브셋·개명 금지를 지킨다). 고지는 기존 한 곳으로 충분하다.

---

## 3. 갱신 경로

### 3.1 먼저 결정: 위젯은 **캐시만** 읽는다 (서버를 부르는 주기 갱신을 만들지 않는다)

| 안 | 내용 | 평가 |
|---|---|---|
| A | 주기 갱신 때 백그라운드에서 Supabase를 읽어 캐시를 새로 만든다(WorkManager 또는 `home_widget` 백그라운드 콜백) | 기각 |
| B | **앱이 받아온 목록만 캐시해 두고, 위젯은 그 캐시만 읽는다. 주기 갱신은 "캐시로 다시 그리기"다** | **채택(권고)** |

B를 고르는 근거:

1. **개인 투두는 이 기기에서만 바뀐다.** 투두를 바꾸는 경로는 앱의 할 일 화면뿐이다 — 웹 클라이언트도, 서버 cron도, 상대 사용자도 내 투두를 건드리지 않는다(`todos`를 만지는 서버 코드는 `delete_account` 하나뿐이고 그건 그 기기에서 일으킨 일이다). 즉 **A가 더 가져오는 정보는 "같은 계정을 두 기기에서 쓰는 사용자의 다른 기기 변경"뿐이다.**
2. **A의 대가는 이 설계에서 가장 비싼 것들이다.** 백그라운드 Dart에서 `Supabase.instance`는 초기화되어 있지 않으므로 isolate마다 `Supabase.initialize`를 다시 해야 하고, 그러면 **세션 복구와 토큰 갱신이 백그라운드에서 일어난다.** 4.2에서 소스로 확인한 대로 그것은 **앱이 로그아웃되는 경로**를 만든다. 30분마다 그 위험을 감수할 이유가 "다른 기기" 하나뿐이다.
3. **주기적 백그라운드 Dart 실행 자체에 패키지가 또 필요하다.** `home_widget`의 백그라운드 콜백은 **위젯 탭**에만 걸린다. 주기 실행을 하려면 `workmanager` 류를 더 넣어야 한다. 패키지 하나를 더 넣어 배터리·도즈 예외를 다루는 비용은 spec이 인정한 가치("30분 전 할 일 목록은 지금도 쓸모가 있다")에 비해 과하다.
4. **spec의 보장 지점은 B로 전부 지켜진다.** spec이 "금방 반영되는 것"으로 보장하라고 한 것은 **앱에서 한 일**이고(아래 3.2), 서버에서 일어난 일은 "다음 주기까지 늦을 수 있다"고 이미 양보해 두었다. B는 그 양보를 "앱을 다시 열 때까지"로 한 칸 더 늘린다.
5. **덤**: 체크를 위해 백그라운드가 어차피 한 번 깨어날 때는 그 기회에 서버 목록을 다시 받아 캐시를 새로 만든다(4.3). 즉 위젯을 **쓰는** 사람은 자연히 최신 캐시를 갖게 된다.

**대가(명시)**: 앱을 전혀 열지 않으면 위젯은 영원히 낡는다. 두 기기 사용자는 다른 기기의 변경을 앱을 열 때까지 못 본다. 이 한 칸의 양보를 오너가 확인해 주길 바란다 → **결정 필요 1**.

### 3.2 발행 지점 — 어느 코드가 무엇을 호출하나

새 계층 둘을 둔다(둘 다 `lib/features/todo/` 안이다 — 위젯이 보여 주는 것은 투두뿐이고 `core`에 둘 이유가 없다. push가 `core/push/`에 간 것은 여러 feature가 함께 썼기 때문이다).

| 파일 | 역할 |
|---|---|
| `lib/features/todo/data/todo_widget_payload.dart` | 캐시 JSON의 **순수 함수**. `TodoWidgetPayload.fromTodos(...)`, `loggedOut()`, `loading()`, `fetchFailed(previous)`, `checkFailed(previous)`, `pending(previous, id, now)`, `toJson()/fromJson()`, 기준 시각 문자열(`오전 9:14`) 만들기. **유닛 테스트 대상** |
| `lib/features/todo/data/todo_widget_host.dart` | `home_widget` 호출을 감싼 얇은 계층(`save(json)`, `read()`, `update()`, `registerCallback()`, `launchUri()`). provider로 노출해 위젯 테스트에서 가짜로 바꾼다(선례: `PushMessaging`, `VsIntroSeenStore`, `EvidenceCamera`) |
| `lib/features/todo/domain/todo_widget_service.dart` | 발행 로직. `publish(payload)` = `host.save` + `host.update`, 실패는 `debugPrint`만 |

provider는 `lib/features/todo/domain/todo_providers.dart`에 함께 둔다(`todoWidgetHostProvider`, `todoWidgetServiceProvider`).

| spec이 보장하라고 한 지점 | 무엇이 일으키나 | 호출되는 것 |
|---|---|---|
| **앱에서 할 일이 바뀐 뒤 앱을 나갈 때** | `MainShell.build`의 `ref.listen(todosProvider, ...)` — 데이터가 오면(추가·수정·삭제·체크 뒤 `invalidate` 포함) 그 자리에서 발행한다. **나갈 때를 기다리지 않는다** | `todoWidgetService.publish(TodoWidgetPayload.fromTodos(...))` |
| 같은 지점의 **실패** | 같은 `ref.listen`의 error 분기 | `publish(fetchFailed(이전 캐시))` — 이전 목록을 유지한 채 note만 바꾼다(상태 4·5) |
| **로그인 직후** | `MainShell.initState`(세션이 있을 때만 떠 있는 화면이다 — push가 토큰 등록을 여기서 시작한 것과 같은 자리) | `publish(loading())` → 곧 위 `ref.listen`이 실제 목록으로 덮는다 |
| **로그아웃·탈퇴 직후** | `AuthRepository.signOut()` / `deleteAccount()` + `AuthGate`의 방어 발행 | `publish(loggedOut())` (8장) |
| **위젯에서 체크한 직후** | 쓰기를 수행한 쪽(앱의 main isolate 또는 백그라운드 isolate)이 직접 | `publish(...)` (4.3) |
| **주기 갱신** | 네이티브 `updatePeriodMillis = 1800000`(30분) → `TodoWidgetProvider.onUpdate` | **Dart를 깨우지 않고** 캐시를 다시 읽어 그린다. 네트워크·세션·배터리 비용이 0이다 |

- `todosProvider`는 `MainShell`의 `IndexedStack`이 `TodoListScreen`을 처음부터 만들기 때문에 로그인 직후부터 살아 있다. 따라서 "할 일 탭에 들어간 적이 없어서 발행이 안 된다"는 구멍은 없다.
- `ref.listen`을 `MainShell`에 두는 이유: 화면(`TodoListScreen`)에 두면 탭을 떠난 뒤의 변경을 놓칠 수 있고, `MainShell`은 이미 탭 전환마다 `invalidate`를 지휘하는 자리다.
- 같은 페이로드를 두 번 발행하지 않도록 `TodoWidgetService`가 직전에 보낸 JSON을 메모리에 들고 비교한다(브로드캐스트를 아끼는 것 이상의 의미는 없다).

### 3.3 `updatePeriodMillis` vs WorkManager

**`updatePeriodMillis = 1800000`만 쓴다.** 하는 일이 "캐시를 다시 읽어 그리기"뿐이라 Dart·네트워크·세션이 필요 없고, 시스템이 30분보다 늦게 깨워도 손해가 없다(spec: 1단계에서 지연의 대가는 거의 없다). 주기 갱신이 실제로 하는 일은 셋이다: (1) note의 기준 시각 문장이 그대로 남아 있게 유지(문장 자체는 Dart가 만든 고정 문자열이므로 다시 그려도 바뀌지 않는다 — 즉 주기 갱신은 **시각을 갱신하지 않는다**), (2) 런처 프로세스가 재시작돼 위젯이 빈 채로 남은 경우의 복구, (3) 60초가 지난 `pending` 표시의 해제. WorkManager·`workmanager` 패키지·`AlarmManager`는 쓰지 않는다.

---

## 4. 체크(쓰기) 경로

### 4.1 전제

- 허용하는 쓰기는 **`todos.is_done = true` 하나**다. 추가·수정·삭제·완료 해제·대결 관련 쓰기는 없다(spec, 원칙 1).
- 기본 경우는 **앱이 떠 있지 않은 상태의 탭**이다.
- 오프라인 대기열을 만들지 않는다. 그 자리에서 실패로 끝내고 위젯 안 한 줄로 말한다(spec).
- **push에는 재사용할 백그라운드 선례가 없다**("참고" 참고). 그래서 아래를 처음부터 설계했다.

### 4.2 핵심 문제: 백그라운드 isolate의 Supabase 세션

백그라운드 isolate에는 `Supabase.instance`가 없다. 쓰려면 `Supabase.initialize`를 그 isolate에서 다시 불러야 하고, 그러면 `SharedPreferencesLocalStorage`에서 세션을 복구하며 **필요하면 토큰을 갱신(refresh)** 한다. 여기서 소스로 확인한 사실이 설계를 정했다.

- 앱(main isolate)은 **resume될 때 로컬 저장소를 다시 읽지 않는다**(`supabase_auth.dart:170-186`).
- 백그라운드에서 refresh가 일어나면 refresh 토큰이 **회전**하고, 메모리에 옛 토큰을 든 앱은 다음 refresh에서 `refresh_token_already_used`를 받는다. gotrue는 그때 **메모리 세션이 아직 만료 전이면 버티지만, 만료된 뒤에는 세션을 지우고 `signedOut`을 쏜다**(`gotrue_client.dart:1611-1633`).
- 앱은 백그라운드로 가면 `stopAutoRefresh()`가 걸려 refresh를 하지 않다가 **resume 때 몰아서** 한다. 즉 "앱을 내려 두고 위젯으로 체크하다가 앱을 다시 열면 로그아웃" 이라는 재현 가능한 경로가 생긴다. 원칙 5에 정면으로 어긋난다.

| 안 | 내용 | 판단 |
|---|---|---|
| W1 | 백그라운드 isolate에서 항상 `Supabase.initialize`(세션 복구·refresh 허용) + 앱이 resume될 때 저장소를 다시 읽어 세션을 고치는 보정 코드를 추가 | 기각. **인증에 손을 댄다.** 배포 직전에 가장 건드리고 싶지 않은 부분이고, 보정이 어긋나면 증상이 "가끔 로그아웃"이라 추적이 어렵다 |
| W2 | 백그라운드에서 refresh를 아예 하지 않고 저장된 액세스 토큰만 써서 쓰기(`Supabase.initialize(accessToken: ...)` — 이 모드는 `SupabaseAuth`와 세션 복구를 건너뛴다. `supabase.dart:151`) | 부분 채택(후퇴 경로). 안전하지만 액세스 토큰 수명(기본 1시간)이 지나면 **거의 항상 실패**한다. 하루에 한 번 앱을 여는 사용자의 체크가 대부분 "체크하지 못했어요"가 된다 |
| W3 | 서버에 기기용 쓰기 토큰 테이블 + Edge Function을 만들어 백그라운드가 그것으로만 쓰기 | 기각. 마이그레이션·Edge·오너 배포 절차가 늘고, 무엇보다 **기기 단위 자격증명이 서버에 남는다** — spec이 "위젯은 새 데이터를 수집하지 않으므로 개인정보처리방침·데이터 보안 양식을 건드리지 않는다"고 적은 전제를 깬다(push는 알림 토큰 때문에 그 서류 작업을 실제로 감수했다). 다른 세션이 `supabase/migrations/`·`supabase/functions/`를 만지고 있는 지금 `delete_account` 재정의가 겹치는 문제도 있다 |
| W4 | 읽기 전용으로 후퇴(체크 없음) | 보류. spec이 남겨 둔 유효한 후퇴 경로이고, 아래 검증이 실패하면 이쪽으로 간다(4.4) |
| **W5** | **백그라운드 콜백이 먼저 "앱의 main isolate가 살아 있는가"를 보고, 살아 있으면 그쪽에 쓰기를 맡기고(앱의 살아 있는 Supabase 클라이언트가 쓴다), 죽어 있으면 그때만 `Supabase.initialize`로 직접 쓴다** | **채택** |

**W5가 성립하는 이유**: 토큰 회전이 해로운 것은 **같은 프로세스에 옛 세션을 든 클라이언트가 살아 있을 때**뿐이다. 위젯 탭으로 깨어나는 백그라운드 engine은 **앱과 같은 OS 프로세스**에서 돈다. 그래서 "main isolate가 살아 있는지"는 그 프로세스 안에서 정확히 알 수 있고, 살아 있으면 클라이언트를 두 개 만들 필요가 없으며(그쪽이 제대로 refresh한다), 죽어 있으면 회전으로 깨뜨릴 상대가 애초에 없다.

- 아는 방법: `dart:ui`의 `IsolateNameServer`. 앱이 시작할 때 main isolate가 `ReceivePort`를 이름(`todododo/todo_widget_write`)으로 등록한다. 백그라운드 콜백은 `lookupPortByName`으로 찾는다. **프로세스가 죽으면 그 등록도 사라지므로** 별도 정리 코드가 필요 없다 — 이것이 플래그 파일보다 나은 점이다. 패키지도 필요 없다(Flutter 코어).
- 등록 자리: `AuthGate`(로그인 여부와 무관하게 늘 떠 있고, `main.dart`가 아니라서 다른 세션과 겹치지 않는다. 10장). 중복 등록을 막으려고 `removePortNameMapping`을 먼저 부른다(핫 리스타트 대비).

### 4.3 흐름

```
위젯의 체크 칸 탭
  └ Kotlin: setOnClickPendingIntent로 걸어 둔
      HomeWidgetBackgroundIntent.getBroadcast(context, "todododo://widget/check?id=<uuid>")
        └ home_widget이 백그라운드 FlutterEngine에서
            @pragma('vm:entry-point') onTodoWidgetAction(Uri?) 를 실행
```

`onTodoWidgetAction`(새 파일 `lib/features/todo/data/todo_widget_callback.dart`, **`main.dart`가 아니다**)이 하는 일, 순서대로:

1. Uri를 순수 함수로 해석한다(`todoWidgetActionOf(Uri?)` → `TodoWidgetAction.check(id)` / `none`). uuid 모양이 아니면 아무 일도 하지 않는다(선례: `notification_payload.dart`의 `battleIdOf`).
2. 캐시를 **다시 읽어**(`host.read()`) 중복 탭을 가른다. `pendingId == id`이고 60초가 안 지났으면 **두 번째 탭은 무시한다.** 이미 사라진(= 성공한) 할 일 id면 역시 무시한다.
3. `publish(pending(이전, id, now))` — 그 줄을 `쓰는 중`으로 바꿔 즉시 다시 그린다. 백그라운드 engine이 뜨는 데 1초 안쪽이 걸릴 수 있어 탭과 표시 사이에 짧은 공백이 있다. 받아들인다(위젯에 진행 표시를 더 그릴 자리가 없다).
4. `IsolateNameServer.lookupPortByName(...)`:
   - **포트가 있다(앱 프로세스 살아 있음)**: `[id, replyPort.sendPort]`를 보내고 **8초** 기다린다. 앱의 main isolate가 `todoRepository.setDone(id, true)` → `invalidate(todosProvider)`를 하고, 그 결과로 3.2의 `ref.listen`이 **새 목록으로 발행**한다. 백그라운드는 답(`ok`/`fail`/`loggedOut`)만 받고 끝낸다. **Supabase 클라이언트를 만들지 않는다.**
   - **포트가 없다(프로세스가 새로 떴다)**: `initSupabase()`(세션 복구·refresh 허용. 이 프로세스에 다른 클라이언트가 없으므로 안전하다) → 세션이 없으면 `publish(loggedOut())`로 끝 → 있으면 `setDone(id, true)` → `fetchTodos`로 목록을 다시 받아 `publish(fromTodos(...))`.
   - **포트는 있는데 8초 안에 답이 없다**(프로세스가 얼어 있거나 바쁜 경우): **직접 쓰지 않고 실패로 끝낸다.** `publish(checkFailed(이전))`. 안전(원칙 5)을 UX보다 앞에 둔다.
5. 어떤 예외든 `publish(checkFailed(이전))`로 끝낸다. 네트워크가 없으면 여기로 온다 → 위젯에 `체크하지 못했어요. 눌러서 앱에서 확인해요`가 뜨고 그 할 일은 목록에 그대로 있다. **"조용히 성공한 것처럼 보이는" 경로가 없다**: 성공 발행은 서버 쓰기가 끝난 뒤에만 일어난다.
6. 프로세스가 쓰기 중에 죽어 아무 발행도 못 한 경우: 캐시에는 `pending`만 남는다. 네이티브가 **60초가 지난 `pending`을 무시하고 그 줄을 평소대로 그리므로** 위젯은 "체크되지 않은 할 일"로 돌아간다. 거짓 성공은 여기서도 없다.

앱이 떠 있는 동안 위젯에서 체크했을 때 화면도 함께 갱신되는 것은 4번의 `invalidate` 덕이다(사용자가 앱으로 돌아갔을 때 어긋나 보이지 않는다).

### 4.4 후퇴 경로 (spec이 남겨 둔 길)

구현 6단계의 실기기 검증에서 아래 중 하나라도 재현되면 **체크를 내리고 1단계를 읽기 전용으로 낸다**(위젯은 그대로, 체크 칸만 없애고 줄 전체가 앱을 열게 한다). 그 경우에도 1~5단계는 그대로 쓸 수 있다.

| 검증 항목 | 통과 기준 |
|---|---|
| 앱 종료 상태에서 체크 | 5초 안에 줄이 사라지고, 앱을 열면 완료로 보인다 |
| 앱을 홈으로 내린 뒤(프로세스 살아 있음) 체크를 여러 번 | 매번 반영되고, **앱으로 돌아갔을 때 로그인 화면이 뜨지 않는다** |
| 비행기 모드에서 체크 | 줄이 되살아나고 실패 한 줄이 보인다 |
| 같은 줄을 연속 두 번 탭 | 서버 쓰기가 한 번만 일어난다 |
| 1시간 이상 앱을 열지 않은 뒤 체크 | 반영된다(= 백그라운드 세션 복구가 동작한다) |

중간 후퇴도 있다: 포트 핸드오프가 동작하지 않으면 **W2**(저장된 액세스 토큰만 쓰고 refresh 없음)로 내려 "앱을 최근에 쓴 사용자만 체크가 된다"로 축소할 수 있다. 읽기 전용보다는 낫지만 실패가 흔해지므로 두 번째 선택지다.

---

## 5. 탭 딥링크

| 누른 곳 | 결과 |
|---|---|
| 위젯의 빈 곳, 할 일 **제목** 영역, `centerText` 영역, note 줄 | 앱의 **할 일 화면** |
| 할 일 줄의 **체크 칸** | 4장의 쓰기(앱을 열지 않는다) |
| 미로그인 상태에서 어디든 | 앱이 열리고 `AuthGate`가 **로그인 화면**을 띄운다(위젯이 분기하지 않는다) |

- 수단: Kotlin에서 `HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse("todododo://widget/todo"))`. MainActivity를 **명시적으로** 지목하는 Intent이므로 manifest에 새 `intent-filter`를 **더하지 않는다**.
- 기존 OAuth 딥링크(`com.todododo.todododo://login-callback`)와 스킴이 다르고, `supabase_flutter`의 딥링크 관찰자는 `access_token`·`code`·`error` 류 파라미터가 없는 Uri를 **무시한다**(소스 확인: `supabase_auth.dart:222-233`). 그러므로 이 Uri가 인증 흐름을 건드릴 일이 없다.
- Dart 수신:
  - **앱이 꺼져 있었을 때**: `AuthGate.initState`에서 `host.initiallyLaunchedFromHomeWidget()`.
  - **앱이 이미 떠 있을 때**: `host.widgetClicked` 스트림 구독(같은 자리에서 시작, `dispose`에서 해제).
  - 둘 다 순수 함수 `widgetTargetOf(Uri?)`로 해석한 뒤 `selectedTabProvider`를 `AppTab.todo`로 바꾼다. `MainShell`이 아직 없으면(미로그인) 값만 바뀐 채 로그인 화면이 보이고, 로그인하면 할 일 탭에서 시작한다 — 따로 보관 상태(`pendingBattleOpenProvider` 같은 것)를 만들지 않아도 `selectedTabProvider`가 그 역할을 한다.
  - 해석할 수 없는 Uri면 아무것도 하지 않는다. **오류 화면을 보이지 않는다**(spec, push의 알림 탭 규칙과 같은 태도).

---

## 6. 위젯 렌더링 (화면)

### 6.1 레이아웃

머리글(앱 이름)을 두지 않는다. 좁은 자리에서 한 줄이라도 할 일에 쓰는 것이 낫고, 앱 이름은 note가 `할 일 · 오전 9:14 기준`으로 이미 말한다.

```
┌─────────────────────────────┐  ← 전체 배경 paper, 2dp ink 테두리
│ [□] 장보기                  │  ← row1 (surface 면 + ink 선)
│ [□] 운동하기                │  ← row2
│ [쓰는 중] 책 반납            │  ← row3 (pending)
│ 그 외 4개                   │  ← row6를 "더 있음" 줄로 쓴다
│ 할 일 · 오전 9:14 기준       │  ← note (inkMuted / danger)
└─────────────────────────────┘
```

- `res/layout/todo_widget.xml`: 세로 LinearLayout + **줄 6개를 미리 선언**(각 줄은 체크 칸 ImageView/Button + 제목 TextView, `maxLines=1`, `ellipsize=end`) + "더 있음" TextView + note TextView + 가운데 안내 TextView(`centerText` 전용). 안 쓰는 것은 `GONE`.
- 전체 배경·빈 곳·note·`centerText`에 **앱 열기 PendingIntent**를 건다. 줄의 제목 TextView에도 같은 것을 건다. 체크 칸에만 4장의 PendingIntent를 건다.
- 자리가 아주 좁을 때(1줄)도 note는 남긴다 — "기준 시각"은 spec이 요구한 장치다.

### 6.2 크기별 줄 수

`AppWidgetManager.getAppWidgetOptions()`의 `OPTION_APPWIDGET_MIN_HEIGHT`(dp)로 **Kotlin이** 정한다(이 계산이 네이티브의 두 번째이자 마지막 판단이다). 줄 높이 36dp, note 20dp를 기준으로:

| 높이(dp) | 대략 크기 | 줄 수 |
|---|---|---|
| < 80 | 4x1 | 1 |
| 80~119 | 2x2, 4x2 | 2 |
| 120~179 | 4x3 | 3 |
| 180~249 | 4x4 | 5 |
| ≥ 250 | 4x5 이상 | 6 (상한) |

- `res/xml/todo_widget_info.xml`: `minWidth=180dp`, `minHeight=110dp`(= 가로 넉넉히, 2행), `minResizeWidth=140dp`, `minResizeHeight=70dp`, `targetCellWidth=4`, `targetCellHeight=2`, `resizeMode="horizontal|vertical"`, `updatePeriodMillis=1800000`, `widgetCategory="home_screen"`, `previewLayout`(API 31+) = 같은 레이아웃, `previewImage=@mipmap/ic_launcher`, `description=@string/...`(2.4의 생성 문자열). 설정 화면(`configure`)은 두지 않는다(spec: 위젯 설정 화면은 범위 밖).
- `onAppWidgetOptionsChanged`에서도 다시 그린다(크기를 바꾼 직후 줄 수가 따라오게).
- **"그 외 N개"를 쓰는 때**: `totalCount`가 그린 줄 수보다 많을 때. 이때 마지막 줄 **하나를 "더 있음" 줄로 바꿔** 쓴다(그러지 않으면 "3개 보이고 그 외 0개"처럼 어긋난다). 예: 줄 수 3, 미완료 7개 → 할 일 2줄 + `그 외 5개`.
- 캐시의 `items`는 8개까지만 담으므로, 줄 수 6을 넘게 그릴 일은 없다.

### 6.3 상태별로 무엇이 보이나

| 캐시 상태(2.3) | 줄 | 가운데 | note |
|---|---|---|---|
| 1 로그인하지 않음 | 없음 | `로그인하면 할 일이 여기에 보여요` | 없음 |
| 2 조회 중 | 없음 | `할 일을 불러오는 중이에요` | 없음 |
| 3 정상 | 할 일 + 필요하면 "그 외 N개" | 없음 | `할 일 · 오전 9:14 기준` |
| 4 조회 실패(목록 있음) | 직전 할 일 | 없음 | `지금은 못 불러왔어요 · 오전 9:14 기준` |
| 5 조회 실패(목록 없음) | 없음 | `할 일을 불러오지 못했어요. 눌러서 다시 시도해요` | 없음 |
| 6 할 일 없음 | 없음 | `할 일이 없어요. 눌러서 추가해요` | 없음 |
| 7 전부 완료 | 없음 | `할 일을 모두 끝냈어요` | 없음 |
| 8 체크 실패 | 직전 할 일(되살아난 줄 포함) | 없음 | `체크하지 못했어요. 눌러서 앱에서 확인해요`(danger) |
| 캐시 자체가 없음/판 번호 모름 | 없음 | `@string/...`(생성 문자열, 예: `앱을 한 번 열어 주세요`) | 없음 |

어떤 상태에서도 빈 사각형·오류 코드·영문이 보이지 않는다(spec). 네이티브가 그릴 것이 없으면 **반드시** 마지막 줄의 대체 문구로 떨어진다.

---

## 7. 앱 안 변경

새 화면은 없다. 기존 화면에 붙는 것만 있다.

| 화면/파일 | 변경 | 상태 |
|---|---|---|
| `lib/core/navigation/main_shell.dart` | `ref.listen(todosProvider)`로 발행(3.2), `initState`에서 `publish(loading())` | 발행 실패는 화면에 영향 없음 |
| `lib/features/auth/presentation/auth_gate.dart` | `ConsumerStatefulWidget`으로 바꿔 `initState`에서 ① `host.registerCallback(onTodoWidgetAction)`(앱 업데이트로 콜백 핸들이 낡을 수 있어 **매 실행마다** 다시 등록한다) ② `IsolateNameServer` 포트 등록 ③ 위젯 런치 Uri 처리(5장). `dispose`에서 포트·구독 해제. 세션이 없어지는 것을 보면 `publish(loggedOut())`(8장) | 어느 단계가 실패해도 `debugPrint`만 남기고 로그인·본 화면은 그대로 뜬다 |
| `lib/features/todo/presentation/todo_list_screen.dart` | 목록 맨 위에 **한 번만 뜨는 안내 블록**(7.1) | 닫으면 다시 뜨지 않음. 기록 읽기·쓰기 실패 시 안내를 띄우지 않고 로그만(연출성 기록의 선례와 같은 태도) |
| `lib/features/auth/data/auth_repository.dart` | `signOut()`·`deleteAccount()`에 위젯 캐시 비우기 추가(8장) | 실패해도 로그아웃·탈퇴를 막지 않는다 |
| `lib/core/strings.dart` | 위젯 문구 일괄 추가(2.3·6.3의 문구 + 안내 블록 문구) | — |

### 7.1 홈 화면 노출 안내 — 자리와 방식 (spec이 design에 맡긴 것)

- **자리: 할 일 화면 목록 맨 위의 안내 블록**(`PixelFrame` + `primaryPale` 면, 오른쪽에 닫기). 위젯이 보여 주는 것이 이 화면의 내용이므로 같은 화면에서 말하는 것이 가장 맥락에 맞다. 프로필에 두면(알림 안내 선례) 위젯과 상관없는 사용자가 더 많이 보게 되고, 위젯을 올리는 사람은 프로필을 안 볼 수 있다.
- **방식: 처음 한 번만.** `shared_preferences`에 기기·계정별 플래그(선례: `VsIntroSeenStore`). 닫으면 끝이고 다시 꺼내는 설정을 만들지 않는다.
- **문구(제안)**: `홈 화면 위젯을 올리면 할 일 제목이 홈 화면에 그대로 보여요. 런처 설정에 따라 잠금화면에도 보일 수 있어요.` — 위젯을 올렸는지 **몰라도 사실인 문장**으로 적는다. "위젯이 올라갔는지"를 알아내는 네이티브 조회에 의존하지 않기 위함이다(의존하면 플러그인 API 유무에 설계가 걸린다).
- 가리기 설정·개수만 보기 같은 선택지는 만들지 않는다(spec 결정 기록 3).

---

## 8. 로그아웃·탈퇴 때 기기 캐시 삭제

| 경로 | 어느 코드가 | 무엇을 |
|---|---|---|
| 로그아웃 | `AuthRepository.signOut()` — 지금 `_push.forgetCurrentToken()`을 먼저 부르는 그 자리에 한 줄 더한다 | `todoWidgetService.publish(loggedOut())`(캐시를 "로그인하지 않음"으로 덮고 위젯 다시 그리기) → 그 뒤 `auth.signOut()` |
| 탈퇴 | `AuthRepository.deleteAccount()` — `delete_account` RPC와 `auth.signOut()` **뒤** | 같은 호출. 이 경로는 `signOut()`을 거치지 않고 `_client.auth.signOut()`을 직접 부르므로 **따로 넣어야 한다** |
| 세션이 그냥 끊긴 경우(만료·서버에서 무효화) | `AuthGate`에서 `ref.listen(authStateProvider)` → 세션이 `null`이 되면 | 같은 호출. 사용자가 "로그아웃"을 누르지 않아도 홈 화면에 남지 않게 하는 방어선 |

- 둘 다 **세션이 살아 있을 때 호출할 필요가 없다**(캐시는 기기 로컬이라 서버 권한이 필요 없다). 그래서 push 토큰 정리처럼 순서에 민감하지 않다.
- 실패하면 `debugPrint`만 남긴다. 다만 이 실패는 프라이버시 사고가 될 수 있으므로(홈 화면에 남는다) **방어선이 셋**이다: 로그아웃 경로, 탈퇴 경로, 세션 소멸 감지. 세 번 모두 실패하면 30분 뒤 주기 갱신이 와도 캐시가 그대로이므로 내용이 남는다 — 그 잔존 가능성은 spec 트레이드오프가 이미 인정했다("앱이 비정상 종료된 뒤처럼 삭제가 늦어질 여지는 남는다").
- 개인정보처리방침과의 관계: 캐시는 **앱 전용 저장소의 기기 로컬 사본**이고 새 수집 항목이 아니다. 방침의 "탈퇴 시 삭제" 서술과 어긋나지 않는 것만 확인한다(spec P1, 13장 7단계).

---

## 9. 안드로이드 파일·배선

| 파일 | 변경 | 함정 |
|---|---|---|
| `android/app/src/main/AndroidManifest.xml` | `<receiver android:name=".TodoWidgetProvider" android:exported="false">` + `android.appwidget.action.APPWIDGET_UPDATE` intent-filter + `<meta-data android:name="android.appwidget.provider" android:resource="@xml/todo_widget_info"/>` | `exported="false"`로 둔다(우리 PendingIntent만 깨우면 된다). 새 권한은 필요 없다 |
| `.../kotlin/com/todododo/todododo/TodoWidgetProvider.kt` (신규) | `AppWidgetProvider` 상속. `onUpdate`·`onAppWidgetOptionsChanged`에서 캐시를 읽어 그린다. 줄 수 계산(6.2), `%d` 끼우기, PendingIntent 걸기 | RemoteViews는 **우리 코드가 아닌 런처 프로세스**에서 그려진다. 커스텀 View·데이터 바인딩을 쓸 수 없고 `setTextViewText`/`setViewVisibility`/`setTextColor`/`setOnClickPendingIntent` 류만 쓴다 |
| `res/layout/todo_widget.xml` (신규) | 6.1의 고정 레이아웃 | RemoteViews가 허용하는 View만 쓴다(LinearLayout/TextView/ImageView/FrameLayout) |
| `res/xml/todo_widget_info.xml` (신규) | 6.2의 메타데이터 | `updatePeriodMillis`는 30분 미만을 적어도 무시된다 |
| `res/drawable/widget_*.xml` (신규 몇 개) | 테두리·줄 면·체크 칸 모양 | `<layer-list>`로 2dp 바닥 두께를 흉내 낸다 |
| `res/values/widget_resources.xml` (**생성**) | 2.4의 색·문자열 3개 | 손으로 고치지 않는다. `res/values/colors.xml`(아이콘 생성기 소유)과 **다른 파일**이다 |
| ~~`res/font/galmuri11.ttf`~~ | **만들지 않았다** — 2.5의 각주(5.37MB > 2.5MB) | 시스템 폰트로 간다 |
| `android/app/build.gradle.kts` | **변경 없음** — 폰트를 포기했으므로 복사 과제가 없다(2.5의 각주) | 원래 서술: 폰트 복사 과제 + 생성 리소스 디렉터리 등록 |
| `android/settings.gradle.kts` | **변경 없음**(Glance를 쓰지 않으므로 새 Gradle 플러그인이 없다) | — |

---

## 10. `main.dart`·`pubspec.yaml`을 건드리는 지점 (다른 세션과의 충돌 회피)

다른 세션이 `push-notification` 4단계를 같은 체크아웃에서 작업 중이다(그쪽이 만지는 것: `lib/core/push/`, `supabase/functions/`, `supabase/migrations/`, `pubspec.yaml`, `main.dart`).

| 파일 | 이 설계가 필요한 변경 | 회피 방법 |
|---|---|---|
| `pubspec.yaml` | **한 줄만**: `home_widget: ^x.y.z`(+ 이유 주석 2줄, 기존 패키지들의 서술 방식과 같게) | 13장 2단계에서 한 번만 고친다. 같은 시점에 다른 세션이 pubspec을 만지면 충돌 해결이 한 줄짜리라 쉽다. `pubspec.lock`은 둘 다 바뀌므로 **머지 후 `flutter pub get`을 다시 돌린다** |
| `lib/main.dart` | **변경 없음.** 백그라운드 콜백 진입점은 `lib/features/todo/data/todo_widget_callback.dart`의 최상위 함수로 두고, 콜백 등록·포트 등록·런치 Uri 처리는 모두 `AuthGate`에서 한다 | `main.dart`를 열 필요가 없게 설계를 맞췄다(원래 자연스러운 자리는 `main()`이지만, 거기 두면 충돌한다) |
| `supabase/migrations/`, `supabase/functions/` | **변경 없음**(11장) | 겹칠 일이 없다 |
| `lib/core/navigation/main_shell.dart` | 발행 `ref.listen` 2~3줄 | push 5단계가 이 파일을 만질 예정이다. 변경이 작고 서로 다른 블록이라 충돌해도 해결이 쉽다 |
| `lib/core/strings.dart` | 위젯 문구 추가 | 양쪽이 끝에 덧붙이는 식이라 충돌 가능. 추가 위치를 파일 끝의 새 구역(`// 홈 화면 위젯`)으로 모은다 |

---

## 11. API 계약

### 11.1 스키마 변경: 없음

- 위젯이 읽는 것은 `todos`이고, 쓰는 것은 `todos.is_done`이다. 둘 다 **이미 있는** 테이블·RLS로 충분하다(`20260818220000_profiles_and_todos.sql`: 본인 행만 select/insert/update/delete).
- 새 테이블·새 RPC·새 Edge Function을 만들지 않는다. 새 열도 없다. 그래서 **마이그레이션 파일이 없고, 원격 적용 승인 절차도 필요 없다**(오너의 손 작업이 그만큼 줄어든다).
- 만약 구현 중 스키마가 필요해 보이면 그때는 반드시 마이그레이션 파일로만 하고 RLS를 같은 파일에 쓴다(CLAUDE.md). 지금 설계에는 그런 지점이 없다.

### 11.2 쓰는 호출 (전부 기존 것)

| 부르는 곳 | 호출 | 비고 |
|---|---|---|
| 앱(main isolate), 백그라운드 isolate | `TodoRepository.fetchTodos(userId)` = `todos.select().eq('user_id', …).order('position', ascending: true).order('id', ascending: true)` | 그대로 쓴다. 위젯용 변형을 만들지 않는다. (2026-11-10 `todo-reorder`: 쿼리의 `order`만 `position`으로 바뀌었다. 레포지토리를 그대로 쓰므로 **이 백그라운드 경로도 앱과 같은 순서를 본다** — Dart 정렬이 없어져 정렬 함수를 따로 부를 일이 없다) |
| 같음 | `TodoRepository.setDone(id, true)` = `todos.update({'is_done': true}).eq('id', id)` | **`true`만 넘긴다**(완료 해제 없음). RLS가 남의 행을 막는다 |

- 백그라운드 isolate에서 `userId`는 복구된 세션의 `supabase.auth.currentUser!.id`다. 세션이 없으면 쓰기를 하지 않는다.
- `setDone`은 멱등이다(이미 `true`인 행을 다시 `true`로 해도 무해). 중복 탭 방어가 한 겹 뚫려도 손해가 없다.

---

## 12. 테스트 전략

| 무엇 | 어디서 | 수단 |
|---|---|---|
| 캐시 페이로드: 미완료만 담기·**받은 순서 보존**(2026-11-10 `todo-reorder` 기준: 순서는 서버의 `order by position`이 만들고 페이로드는 보존만 한다. 그 전에는 `todo-due-date`의 `sortedForList`, 더 전에는 "생성순 유지"였다)·8개 상한·제목 자르기·`totalCount`, 상태 8가지의 문구 선택(빈 목록/전부 완료/조회 실패 두 종/체크 실패/로그아웃/조회 중), 기준 시각 문장(`오전/오후 h:mm`), `pending` 설정·만료, JSON 직렬화 왕복 | Dart 순수 함수 | `flutter test` 유닛 — `test/features/todo/todo_widget_payload_test.dart` |
| 위젯 Uri 해석(`todoWidgetActionOf`, `widgetTargetOf`): 정상·uuid 아님·키 없음·엉뚱한 스킴 | Dart 순수 함수 | 같은 곳 |
| "줄 수 → 몇 개 그리고 '그 외 N개'는 몇인가" | Dart 순수 함수로 **떼어 둔다**(`visibleRows(items, totalCount, rowCount)`) 네이티브는 이 규칙을 그대로 옮긴 20줄이다 | 유닛. 규칙을 Dart에 두는 것이 원칙 2다 |
| 할 일을 바꾸면 발행이 일어나는가 / 조회 실패 때 이전 목록을 유지하는가 / 로그아웃·탈퇴 때 비우는가 | Dart 위젯 테스트 | 가짜 `todoWidgetHostProvider`로 `save`·`update` 호출을 기록해 확인(선례: 가짜 `pushMessagingProvider`) |
| 중복 탭 무시, 포트가 없을 때의 분기 | Dart 유닛 | 콜백의 결정 부분을 `TodoWidgetCheckDecision`(순수 함수)으로 떼어 캐시 상태 + 포트 유무를 입력으로 받게 한다. **실제 isolate·네트워크는 테스트하지 않는다** |
| RemoteViews 그리기, 줄 수 계산, PendingIntent, 폰트·색, 백그라운드 engine 기동 | **테스트하지 않는다** | 네이티브 단위 테스트를 도입하지 않는다(CLAUDE.md는 화면 테스트를 강제하지 않고, 위젯은 화면보다 더 테스트하기 어렵다). 대신 4.4의 실기기 체크리스트로 본다 |

실기기 확인 목록(= `DEPLOY.md`에 들어갈 줄): 설치 직후 위젯 올리기 / 로그아웃 상태 / 네트워크 없는 상태 / 2x2·4x2·4x4 크기 / 체크 성공·실패 / 위젯 탭 → 할 일 화면 / 미로그인 탭 → 로그인 화면 / 탈퇴 후 홈 화면에 할 일이 남지 않음.

---

## 13. 구현 단계 분할 (커밋 단위)

각 단계 끝에 `flutter analyze` 이슈 0 + `flutter test` 통과를 확인한다. **스키마 변경이 없으므로 원격 적용 승인 지점이 없다.**

| 단계 | 커밋 제안 | 내용 | 끝나면 무엇이 되나 |
|---|---|---|---|
| 1 | `feat: 투두 위젯 캐시 페이로드` | `todo_widget_payload.dart`(+`visibleRows`·Uri 해석 순수 함수), `strings.dart`에 위젯 문구, 유닛 테스트 | 앱 동작은 그대로. 테스트만 늘어난다 |
| 2 | `feat: 홈 화면 투두 위젯 추가` | `pubspec.yaml`(`home_widget`), `TodoWidgetProvider.kt`, `res/layout|xml|drawable`, `tool/generate_widget_resources.dart` + 생성 결과, manifest `<receiver>`, 폰트 복사(`build.gradle.kts`), `todo_widget_host.dart` | 위젯을 홈 화면에 올릴 수 있다. 캐시가 없으니 대체 한 줄만 보인다. **AGP/Kotlin 호환과 minSdk를 여기서 확인한다**(1.1) |
| 3 | `feat: 앱의 할 일 변경을 위젯에 반영` | `todo_widget_service.dart`, provider, `main_shell.dart`의 `ref.listen`, 상태 8종 발행 | 읽기 전용 위젯이 완성된다. **여기까지가 spec의 "읽기 전용 후퇴" 지점**이다 |
| 4 | `feat: 로그아웃·탈퇴 시 위젯 캐시 비우기` | `auth_repository.dart`, `auth_gate.dart`(세션 소멸 감지) | 프라이버시 요구 충족 |
| 5 | `feat: 위젯 탭으로 할 일 화면 열기` | `auth_gate.dart`(런치 Uri·구독), 5장 | 탭 경로 완성 |
| 6 | `feat: 위젯에서 할 일 완료 처리` | `todo_widget_callback.dart`, 포트 등록(`auth_gate.dart`), 체크 PendingIntent(Kotlin), `pending`·실패 한 줄 | 체크 완성. **4.4의 검증을 통과하지 못하면 이 단계를 되돌리고 3단계 상태로 낸다** |
| 7 | `feat: 위젯 홈 화면 노출 안내` + `docs: 위젯 배포 준비` | 7.1의 안내 블록(화면이라 커밋 분리) / `DEPLOY.md` 한 줄, CLAUDE.md(범위 서술·개발 명령어에 생성기·코딩 규칙 예외 한 줄), `TODO_BACKLOG.md`에서 이 항목 빼기, 개인정보처리방침 보유·삭제 서술 확인 | 배포 준비 완료 |

단계 2·6이 위험이 몰린 곳이고, 3단계에서 멈춰도 쓸 수 있는 위젯이 남는다는 점이 이 분할의 핵심이다.

---

## 14. 오너가 손수 해야 할 일

1. 없음(시크릿·Firebase 콘솔·Supabase 설정 변경이 **하나도 없다**). 스키마 변경도 없어 원격 적용 승인이 필요 없다.
2. 실기기 확인(12장 목록). 에뮬레이터로도 위젯을 올려 볼 수 있지만, 체크의 백그라운드 경로와 절전 동작은 실기기(Galaxy S20)로 본다.
3. 개인정보처리방침(별도 저장소)의 보유·삭제 서술이 "기기에 남는 위젯 캐시는 로그아웃·탈퇴 때 지운다"와 어긋나지 않는지 한 번 읽어 확인(새 수집 항목은 아니므로 표를 바꾸지 않는다).

---

## 결정 필요

1. **주기 갱신이 서버를 보지 않는 것(캐시 전용)을 받아들이는가?** (3.1)
   - 권고: **받아들인다.** 개인 투두를 바꾸는 경로는 이 기기의 앱뿐이라 서버를 폴링해서 더 얻는 것은 "같은 계정을 두 기기에서 쓸 때 다른 기기의 변경"뿐이다. 그 대가로 백그라운드 인증·네트워크·배터리와 **앱이 로그아웃될 위험**(4.2에서 소스로 확인한 토큰 회전 문제)이 읽기 경로에서 전부 사라지고, 주기 실행용 패키지(`workmanager` 류)를 더 넣지 않아도 된다.
   - 대가: **앱을 전혀 열지 않으면 위젯은 영원히 낡는다.** spec "P0. 갱신 주기"가 "서버에서 일어난 일은 다음 주기까지 늦을 수 있다"고 적은 것보다 한 칸 더 양보하는 것이므로 확인을 받고 싶다.
2. **검증에서 체크가 성립하지 않으면 읽기 전용으로 내리는 것을 미리 승인해 두겠는가?** (4.4)
   - 권고: **미리 승인해 둔다.** spec 결정 기록 2가 그 후퇴를 유효한 채로 남겨 두었고, 설계상 3단계까지만 가도 쓸 수 있는 위젯이 남는다. 검증 항목 중 **"앱을 내려 둔 상태에서 위젯으로 체크한 뒤 앱을 열었을 때 로그인 화면이 뜨지 않는다"**가 가장 중요한 한 줄이다 — 이것이 깨지면 체크 때문에 앱의 로그인이 끊기는 것이라 체크를 내리는 것이 맞다.
   - 미리 승인해 두면 구현 중 판단이 막히지 않는다. 승인하지 않겠다면 6단계 검증 결과를 받아 그때 정한다.

---

## 결정 기록 (2026-11-04 오너 확정)

위 "## 결정 필요" 2건에 대한 오너의 답이다. 둘 다 권고안 그대로다.

1. **주기 갱신은 서버를 보지 않는다(캐시 전용, 3.1의 안 B) — 받아들인다.** 앱을 전혀 열지 않으면
   위젯이 영원히 낡는다는 대가, 그리고 두 기기 사용자가 다른 기기의 변경을 앱을 열 때까지 못 본다는
   대가를 오너가 확인했다. 그 대신 읽기 경로에서 백그라운드 인증·네트워크·배터리와 4.2의 로그아웃
   위험이 전부 사라지고 `workmanager` 류를 더 넣지 않는다. **서버를 폴링하는 설계를 나중에 몰래
   되살리지 말 것** — 되살리려면 4.2를 다시 풀어야 한다.
2. **검증에서 체크가 깨지면 읽기 전용으로 내리는 것을 미리 승인한다(4.4).** 구현 6단계에서 4.4 표의
   항목 중 하나라도 재현되면 **다시 물을 필요 없이** 6단계를 되돌리고 3단계 상태(읽기 전용 위젯)로
   낸다. 특히 **"앱을 내려 둔 상태에서 위젯으로 체크한 뒤 앱을 열었을 때 로그인 화면이 뜨지 않는다"**가
   깨지면 체크 때문에 앱의 로그인이 끊기는 것이므로 즉시 내린다. 중간 후퇴(W2, 저장된 액세스 토큰만
   쓰기)를 택할 때는 "앱을 최근에 쓴 사용자만 체크가 된다"는 축소를 보고에 명시한다.

이 둘이 확정됐으므로 **구현 단계에서 오너에게 다시 물을 승인 지점은 없다**(스키마 변경도 없다).
남은 오너 몫은 14장의 실기기 확인뿐이다.
