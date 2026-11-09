# TODO Backlog

- 탈퇴 시 증거 사진 정리 실패 대비 — 사진 삭제는 앱이 Storage API로만 할 수 있고(SQL 직접 삭제는 `storage.protect_delete()`가 막는다), 이 정리가 실패해도 탈퇴는 진행된다. 참조가 끊긴 사진이 버킷에 남을 수 있으므로 주기적 정리 수단이 필요하다(배포 후)
- 정책 문서 게시 — `C:\workspaces\todododo-legal`을 GitHub 공개 저장소로 올리고 Pages를 켠 뒤, 개인정보처리방침·계정 삭제 URL을 Play Console에 등록. 배포 전 필수, `DEPLOY.md` 0번·5번 참고
- 증거 신고/차단 (UGC 정책) — Play는 사용자끼리 콘텐츠를 주고받는 앱에 신고·차단 수단을 요구한다. 모집 방식이라 모르는 사람의 사진을 보게 되는데 지금은 둘 다 없다. 심사에서 지적될 수 있음, `store/listing-ko.md` 하단 참고
- 스토어 스크린샷 재촬영·스토어 배너 이미지 제작 — redesign(2026-11-08)까지 끝났으므로 이제 찍을 수 있다. 현재 스크린샷은 옛 레트로 화면이고, 대결 진행·프로필 장면이 새 규칙(상호 판정, 점수·전적)과도 어긋난다. `DEPLOY.md` 4번, `docs/specs/redesign/plan.md` 0단계(`store/screenshots/`는 redesign 범위 밖) 참고
- 탈퇴한 상대의 지난 대결에서 사진 자리 안내 — 탈퇴하면 `battle_submissions.object_path`가 null이 되어 종결 뒤 공개되는 이력에 판정 사유만 남고 사진 자리는 비어 보인다. "사진 없음(탈퇴한 사용자)" 같은 안내가 있으면 좋다(design.md "탈퇴와의 상호작용"). 기능이 막히지는 않아 배포 후로 미룸
- 찾기 탭 고정 조작 영역 축소(M14 / recruit-list-scan S5) — 검색줄에 `필터` 버튼을 합치고 두 세그먼트는 하단 시트로 옮긴다(안 B). 고정 영역 174dp(세로 22%)와 "조작 요소가 전부 엄지 밖"이 남아 있다. 실기기 관측이 "카드 수가 부족하다"는 근거를 무효화해 배포 전 필수는 아니다(2026-11-02 오너 결정 4). `docs/specs/mobile-ux/recruit-list-scan.md` S5 참고
- 대결 상세의 당겨서 새로고침 예외 처리 — `battle_detail_screen.dart:78`의 `onRefresh`는 `ref.refresh(...future)`를 그대로 돌려줘서 새로고침이 실패하면 예외가 제스처 밖으로 터진다(사용자에게는 아무 안내가 없다). `my_battles_screen.dart:59`·`battle_recruits_screen.dart:390`처럼 `try/catch`로 받아 로그만 남기고 화면의 `error` 갈래에 맡기는 쪽이 맞다. mobile-ux M2 이전부터 있던 문제라 그 변경 범위 밖으로 두었다(reviewer N5, 2026-11-02)
- firebase_messaging 토큰 API deprecation 전환 — 17.0.1이 `getToken`/`onTokenRefresh`/`deleteToken`을 deprecated로 두고 `register()`+`onRegistered`(FID)를 권한다. 새 API는 등록 토큰이 아니라 FID를 스트림으로만 내주므로 전송 대상 의미와 "앱 실행 시 즉시 등록" 흐름이 둘 다 바뀐다 — 서버 발송 경로(`push-notification` 4단계)가 실제로 돌아 FCM v1 전송이 검증된 뒤에 다룬다. 지금은 `lib/core/push/push_messaging.dart`에서 `// ignore: deprecated_member_use`로 등록 토큰을 쓴다(2026-11-03)
- **[배포 전 필수]** AI 동의 화면 첫 문장 "대결 결과는 AI 심판이 판정해요"(`AppStrings.aiConsentIntro`)가 현행 판정 구조(1차 참가자 상호 판정 + 2차 AI 재판정)와 다르다. 동의 고지 문구라 오너 확인 후 수정(2026-11-08 redesign 후속 검토)
- 승리/결과 화면의 증거 제출 시각이 "01:16"처럼 라벨·날짜 없이 표시된다 — 무엇의 시각인지("제출 시각")와 날짜를 붙일 것(2026-11-08 redesign 후속 검토)
- 속도전 진행 중 화면에서 촬영하는 동안(미리보기) 최소 기준이 보이지 않는다 — 찍으면서 기준을 확인할 수 없음(2026-11-08 redesign 후속 검토)
- 프로필 전적 카드에 날짜가 없고, 포기로 진 대결이 일반 패와 구분되지 않는다(2026-11-08 redesign 후속 검토)
- 반복되는 할 일(매일·매주·N일마다) — 하나의 할 일이 여러 번 생기는 구조라 완료·수정·삭제가 "이번 것만/전부"로 갈라진다. 투두 기한과 별개의 기능으로 다룰 것(2026-11-09 `todo-due-date` 기획에서 범위 밖으로 확정)
- 지난 기한 일괄 정리·접어 두기 — 기한이 지난 할 일을 자동으로 지우지 않기로 했으므로(오너 확정) 지난 기한이 목록 맨 위에 계속 쌓인다. 배포 후로 미룸(2026-11-09 오너 결정). `docs/specs/todo-due-date/spec.md` 참고
- 홈 위젯 줄에 기한 임박 표시 — 위젯 캐시는 최소 30분(절전이면 그 이상) 낡아서 남은 시간 숫자가 틀린다. 위젯이 그리는 시점에 시간을 다시 계산할 방법이 생기면 재검토. `docs/specs/todo-due-date/spec.md` "P1. 홈 화면 위젯" 참고
- 개인정보처리방침에 알림(FCM 토큰) 항목이 없다 — `privacy.html`에 알림·토큰 이야기가 한 줄도 없는데, 대결 알림(`push-notification`)은 FCM 등록 토큰을 서버(`push_tokens`)에 저장한다. 그 기능을 배포할 때 방침에 한 줄이 필요하다. 투두 기한 알림은 기기 로컬이라 무관하다(2026-11-10 `todo-due-date` 11단계 서류 확인에서 발견)
- 로그인·로그아웃 때 `todosProvider`를 무효화하지 않는다 — 같은 프로세스에서 다른 사용자가 로그인하면 `todosProvider`가 비워지지 않아 **이전 사용자의 할 일 목록 캐시가 그대로 보인다**(autoDispose가 아니고, 무효화하는 자리가 어디에도 없다). 같은 이유로 `MainShell`이 셸 시작에 거는 기한 알림 보정도 그 캐시를 쓴다. auth 상태 변화에 맞춘 `invalidate(todosProvider)` 하나로 둘이 함께 해결된다(2026-11-10 `todo-due-date` P1 리뷰에서 발견, 그 기능의 범위 밖)
