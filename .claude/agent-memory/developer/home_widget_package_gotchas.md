---
name: home-widget-package-gotchas
description: home_widget 0.10.0의 배관 함정 — 백그라운드 리시버를 패키지가 선언해 주지 않고, getBroadcast의 요청 코드가 0으로 고정돼 Uri data로만 줄을 구분할 수 있다
metadata:
  type: reference
---

`home_widget` 0.10.0(이 저장소가 쓰는 판)의 소스를 직접 읽어 확인한 사실들이다. 전부 **실기기에서
"아무 일도 안 일어난다"로만 드러나는** 종류라 코드를 다시 읽기 전에 여기를 먼저 볼 것.

1. **패키지의 `AndroidManifest.xml`은 비어 있다**(`<manifest package="es.antonborri.home_widget" />`).
   즉 **`HomeWidgetBackgroundReceiver`를 앱 매니페스트에 직접 선언해야 한다** —
   `<receiver android:name="es.antonborri.home_widget.HomeWidgetBackgroundReceiver">` +
   `<action android:name="es.antonborri.home_widget.action.BACKGROUND"/>`. 없으면 위젯 버튼을 눌러도
   Dart 콜백이 **전혀** 실행되지 않는다(예제 앱이 앱 쪽에 적어 두는 구조다). `exported="false"`로
   충분하다 — 그 PendingIntent는 우리 앱이 만들어 런처에 넘긴 것이고 우리 자격으로 발송된다.
2. **`HomeWidgetBackgroundIntent.getBroadcast(context, uri)`는 요청 코드를 0으로 고정한다**(인자가
   없다). 그래서 목록의 줄마다 다른 동작을 걸려면 **Uri data를 줄마다 다르게** 하는 것이 유일한
   수단이다(`PendingIntent`의 동일성은 `Intent.filterEquals` = action·data·type·component·categories).
   **extras에 id를 싣지 말 것** — `filterEquals`가 extras를 보지 않아 모든 줄이 한 PendingIntent로
   합쳐지고 아무 줄을 눌러도 같은 항목이 처리되는 사고가 난다.
3. 백그라운드 콜백의 디스패처가 `WidgetsFlutterBinding.ensureInitialized()`를 **이미 부르고**,
   engine을 `FlutterEngine(context)`로 만들어 **플러그인이 자동 등록**된다. 그래서 콜백 안에서
   `shared_preferences`·`home_widget` 같은 채널이 그대로 동작한다(별도 등록 코드가 필요 없다).
   실행은 WorkManager를 거친다.
4. `registerInteractivityCallback`이 등록하는 것은 **Dart 콜백의 핸들**이다. 앱을 업데이트하면 그
   값이 낡으므로 **앱 실행마다 다시 등록**한다.
5. 이 패키지는 `androidx.glance:glance-appwidget`을 `api` 의존성으로 끌고 온다(쓰지 않아도 APK에
   들어온다). 그리고 자기 `build.gradle`이 buildscript classpath에 `kotlin-gradle-plugin:1.9.0`을
   박아 두어 **릴리스 빌드만 깨지는** 문제를 만든다 — 해결은 `android.builtInKotlin=true`
   (`CLAUDE.md` "개발 환경"에 적혀 있다).
