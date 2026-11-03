# TODO Backlog

- 탈퇴 시 증거 사진 정리 실패 대비 — 사진 삭제는 앱이 Storage API로만 할 수 있고(SQL 직접 삭제는 `storage.protect_delete()`가 막는다), 이 정리가 실패해도 탈퇴는 진행된다. 참조가 끊긴 사진이 버킷에 남을 수 있으므로 주기적 정리 수단이 필요하다(배포 후)
- 정책 문서 게시 — `C:\workspaces\todododo-legal`을 GitHub 공개 저장소로 올리고 Pages를 켠 뒤, 개인정보처리방침·계정 삭제 URL을 Play Console에 등록. 배포 전 필수, `DEPLOY.md` 0번·5번 참고
- 증거 신고/차단 (UGC 정책) — Play는 사용자끼리 콘텐츠를 주고받는 앱에 신고·차단 수단을 요구한다. 모집 방식이라 모르는 사람의 사진을 보게 되는데 지금은 둘 다 없다. 심사에서 지적될 수 있음, `store/listing-ko.md` 하단 참고
- 스토어 스크린샷 재촬영·스토어 배너 이미지 제작 — retro-theme·ai-judge 구현이 모두 끝났으므로 이제 찍을 수 있다. 현재 스크린샷은 대결 진행·프로필 장면이 새 규칙(AI 판정, 점수·전적)과 어긋난다. `DEPLOY.md` 4번, `docs/specs/retro-theme/spec.md` 범위 밖 참고
- 탈퇴한 상대의 지난 대결에서 사진 자리 안내 — 탈퇴하면 `battle_submissions.object_path`가 null이 되어 종결 뒤 공개되는 이력에 판정 사유만 남고 사진 자리는 비어 보인다. "사진 없음(탈퇴한 사용자)" 같은 안내가 있으면 좋다(design.md "탈퇴와의 상호작용"). 기능이 막히지는 않아 배포 후로 미룸
- 글자 배율 상한 1.5 재검증 — `main.dart`의 `maxTextScale = 1.3`을 올릴 여지가 생겼다(짧은 라벨이 본문 글꼴이 되어 줄바꿈이 가능해졌고 칩 줄은 `Wrap`이 됐다). 전 화면을 1.5배로 다시 봐야 해서 MVP 직전에는 하지 않았다. `docs/specs/retro-theme/readability.md` 3-2 참고
- 레트로 테마 가독성 2차(방안 4·5) — 칩 테두리 2dp→1dp, 구분선 `line`→`inkMuted`, 프레임 중첩 평면화. 레이아웃 변동이 커서 배포 후로 미뤘다. `docs/specs/retro-theme/readability.md` 4장 참고
- 찾기 탭 고정 조작 영역 축소(M14 / recruit-list-scan S5) — 검색줄에 `필터` 버튼을 합치고 두 세그먼트는 하단 시트로 옮긴다(안 B). 고정 영역 174dp(세로 22%)와 "조작 요소가 전부 엄지 밖"이 남아 있다. 실기기 관측이 "카드 수가 부족하다"는 근거를 무효화해 배포 전 필수는 아니다(2026-11-02 오너 결정 4). `docs/specs/mobile-ux/recruit-list-scan.md` S5 참고
- 대결 상세의 당겨서 새로고침 예외 처리 — `battle_detail_screen.dart:78`의 `onRefresh`는 `ref.refresh(...future)`를 그대로 돌려줘서 새로고침이 실패하면 예외가 제스처 밖으로 터진다(사용자에게는 아무 안내가 없다). `my_battles_screen.dart:59`·`battle_recruits_screen.dart:390`처럼 `try/catch`로 받아 로그만 남기고 화면의 `error` 갈래에 맡기는 쪽이 맞다. mobile-ux M2 이전부터 있던 문제라 그 변경 범위 밖으로 두었다(reviewer N5, 2026-11-02)
- 홈 화면 위젯 — 배포 후 첫 업데이트의 첫 작업으로 투두 위젯 하나를 낸다(위젯에서 할 일 체크까지 허용). 대결 위젯은 `push-notification` 2~7단계 완료 + "알림을 받고도 판정을 놓친다"는 확인 뒤로 미뤘다. 기획·결정은 `docs/specs/home-widget/spec.md`에 끝나 있고 design.md부터 시작하면 된다(2026-11-03 오너 결정, 안 C)
