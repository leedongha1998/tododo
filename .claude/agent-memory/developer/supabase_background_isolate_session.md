---
name: supabase-background-isolate-session
description: 백그라운드 isolate에서 Supabase.initialize를 부르면 refresh 토큰이 회전해 앱(main isolate)이 다음 resume에 조용히 로그아웃될 수 있다
metadata:
  type: reference
---

백그라운드 Dart(위젯 탭 콜백, 알림 콜백, WorkManager 등)에서 Supabase를 쓰려 할 때 걸리는 함정이다.
`home-widget` 설계(2026-11-04) 때 `pub-cache`의 `supabase_flutter`·`gotrue` 소스를 직접 읽어 확인했다.

1. **백그라운드 isolate에는 `Supabase.instance`가 없다.** 쓰려면 그 isolate에서
   `Supabase.initialize`를 다시 불러야 하고, 그러면 로컬 저장소에서 세션을 복구하며 필요하면
   **토큰을 갱신(refresh)** 한다.
2. **앱(main isolate)은 resume될 때 로컬 저장소를 다시 읽지 않는다**(`supabase_auth.dart`의
   resume 처리). 즉 메모리에 옛 refresh 토큰을 그대로 들고 있다.
3. refresh 토큰은 **회전**하므로, 앱이 다음에 refresh를 시도하면 `refresh_token_already_used`를
   받는다. gotrue는 메모리 세션이 **아직 만료 전이면 버티지만, 만료된 뒤에는 세션을 지우고
   `signedOut`을 쏜다**(`gotrue_client.dart`의 refresh 실패 처리).
4. 앱은 백그라운드로 가면 `stopAutoRefresh()`가 걸려 refresh를 멈추고 **resume 때 몰아서** 한다.
   그래서 "앱을 내려 두고 백그라운드 경로를 몇 번 쓰다가 앱을 다시 열면 로그인 화면" 이라는
   **재현 가능한** 경로가 된다.

**Why:** 증상이 "가끔 로그아웃"이라 추적이 매우 어렵고, 원인이 기능 코드가 아니라 인증이라 배포
직전에 손대기 가장 나쁜 곳이다. 백그라운드에서 Supabase를 부르는 설계는 이 비용을 먼저 계산해야 한다.

**How to apply:** 백그라운드에서 Supabase 쓰기가 필요하면 (a) `dart:ui`의 `IsolateNameServer`로
앱 main isolate의 포트를 찾아 **살아 있으면 그쪽에 쓰기를 맡기고**(한 프로세스에 클라이언트를 두 개
만들지 않는다), 죽어 있을 때만 직접 `initialize`한다 — 프로세스가 죽으면 포트 등록도 사라지므로
정리 코드가 필요 없다. (b) 더 안전하게 가려면 `Supabase.initialize(accessToken: ...)`로 저장된
액세스 토큰만 쓰고 refresh를 아예 하지 않는다(세션 복구를 건너뛴다). 다만 액세스 토큰 수명이
기본 1시간이라 실패가 흔해진다. **읽기 전용으로 할 수 있는 일이면 백그라운드에서 서버를 아예
부르지 않는 쪽이 가장 싸다** — `home-widget`은 그래서 위젯 갱신을 기기 캐시만 읽는 것으로 정했다
(`docs/specs/home-widget/design.md` 3.1·4.2).
