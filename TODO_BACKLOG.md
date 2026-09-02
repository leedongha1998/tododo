# TODO Backlog

- 탈퇴 시 증거 사진 정리 실패 대비 — 사진 삭제는 앱이 Storage API로만 할 수 있고(SQL 직접 삭제는 `storage.protect_delete()`가 막는다), 이 정리가 실패해도 탈퇴는 진행된다. 참조가 끊긴 사진이 버킷에 남을 수 있으므로 주기적 정리 수단이 필요하다(배포 후)
- 웹 계정 삭제 요청 URL — Google 계정 로그인 앱의 Play 정책 필수 요건. 앱 내 삭제 경로는 구현 완료, 웹 URL만 남음. 배포 전 해결 필요, `DEPLOY.md` 0번 참고
