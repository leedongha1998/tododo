# TODO Backlog

- 탈퇴 시 증거 사진 정리 실패 대비 — 사진 삭제는 앱이 Storage API로만 할 수 있고(SQL 직접 삭제는 `storage.protect_delete()`가 막는다), 이 정리가 실패해도 탈퇴는 진행된다. 참조가 끊긴 사진이 버킷에 남을 수 있으므로 주기적 정리 수단이 필요하다(배포 후)
- 정책 문서 게시 — `C:\workspaces\todododo-legal`을 GitHub 공개 저장소로 올리고 Pages를 켠 뒤, 개인정보처리방침·계정 삭제 URL을 Play Console에 등록. 배포 전 필수, `DEPLOY.md` 0번·5번 참고
- 증거 신고/차단 (UGC 정책) — Play는 사용자끼리 콘텐츠를 주고받는 앱에 신고·차단 수단을 요구한다. 모집 방식이라 모르는 사람의 사진을 보게 되는데 지금은 둘 다 없다. 심사에서 지적될 수 있음, `store/listing-ko.md` 하단 참고
- 스토어 스크린샷 재촬영·스토어 배너 이미지 제작 — redesign(2026-11-08)까지 끝났으므로 이제 찍을 수 있다. 현재 스크린샷은 옛 레트로 화면이고, 대결 진행·프로필 장면이 새 규칙(상호 판정, 점수·전적)과도 어긋난다. `DEPLOY.md` 4번, `docs/specs/redesign/plan.md` 0단계(`store/screenshots/`는 redesign 범위 밖) 참고
- 탈퇴한 상대의 지난 대결에서 사진 자리 안내 — 탈퇴하면 `battle_submissions.object_path`가 null이 되어 종결 뒤 공개되는 이력에 판정 사유만 남고 사진 자리는 비어 보인다. "사진 없음(탈퇴한 사용자)" 같은 안내가 있으면 좋다(design.md "탈퇴와의 상호작용"). 기능이 막히지는 않아 배포 후로 미룸
- 찾기 탭 고정 조작 영역 축소(M14 / recruit-list-scan S5) — 검색줄에 `필터` 버튼을 합치고 두 세그먼트는 하단 시트로 옮긴다(안 B). 고정 영역 174dp(세로 22%)와 "조작 요소가 전부 엄지 밖"이 남아 있다. 실기기 관측이 "카드 수가 부족하다"는 근거를 무효화해 배포 전 필수는 아니다(2026-11-02 오너 결정 4). `docs/specs/mobile-ux/recruit-list-scan.md` S5 참고
- 대결 상세의 당겨서 새로고침 예외 처리 — `battle_detail_screen.dart:78`의 `onRefresh`는 `ref.refresh(...future)`를 그대로 돌려줘서 새로고침이 실패하면 예외가 제스처 밖으로 터진다(사용자에게는 아무 안내가 없다). `my_battles_screen.dart:59`·`battle_recruits_screen.dart:390`처럼 `try/catch`로 받아 로그만 남기고 화면의 `error` 갈래에 맡기는 쪽이 맞다. mobile-ux M2 이전부터 있던 문제라 그 변경 범위 밖으로 두었다(reviewer N5, 2026-11-02)
- firebase_messaging 토큰 API deprecation 전환 — 17.0.1이 `getToken`/`onTokenRefresh`/`deleteToken`을 deprecated로 두고 `register()`+`onRegistered`(FID)를 권한다. 새 API는 등록 토큰이 아니라 FID를 스트림으로만 내주므로 전송 대상 의미와 "앱 실행 시 즉시 등록" 흐름이 둘 다 바뀐다 — 서버 발송 경로(`push-notification` 4단계)가 실제로 돌아 FCM v1 전송이 검증된 뒤에 다룬다. 지금은 `lib/core/push/push_messaging.dart`에서 `// ignore: deprecated_member_use`로 등록 토큰을 쓴다(2026-11-03)
