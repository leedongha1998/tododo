# TODO Backlog

- 탈퇴 시 증거 사진 정리 실패 대비 — 사진 삭제는 앱이 Storage API로만 할 수 있고(SQL 직접 삭제는 `storage.protect_delete()`가 막는다), 이 정리가 실패해도 탈퇴는 진행된다. 참조가 끊긴 사진이 버킷에 남을 수 있으므로 주기적 정리 수단이 필요하다(배포 후)
- 정책 문서 게시 — `C:\workspaces\todododo-legal`을 GitHub 공개 저장소로 올리고 Pages를 켠 뒤, 개인정보처리방침·계정 삭제 URL을 Play Console에 등록. 배포 전 필수, `DEPLOY.md` 0번·5번 참고
