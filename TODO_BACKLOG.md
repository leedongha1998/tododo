# TODO Backlog

- 탈퇴 시 증거 사진 정리 실패 대비 — 사진 삭제는 앱이 Storage API로만 할 수 있고(SQL 직접 삭제는 `storage.protect_delete()`가 막는다), 이 정리가 실패해도 탈퇴는 진행된다. 참조가 끊긴 사진이 버킷에 남을 수 있으므로 주기적 정리 수단이 필요하다(배포 후)
- 정책 문서 게시 — `C:\workspaces\todododo-legal`을 GitHub 공개 저장소로 올리고 Pages를 켠 뒤, 개인정보처리방침·계정 삭제 URL을 Play Console에 등록. 배포 전 필수, `DEPLOY.md` 0번·5번 참고
- 증거 신고/차단 (UGC 정책) — Play는 사용자끼리 콘텐츠를 주고받는 앱에 신고·차단 수단을 요구한다. 모집 방식이라 모르는 사람의 사진을 보게 되는데 지금은 둘 다 없다. 심사에서 지적될 수 있음, `store/listing-ko.md` 하단 참고
- 스토어 스크린샷 재촬영·스토어 배너 이미지 제작 — retro-theme·ai-judge 구현이 모두 끝났으므로 이제 찍을 수 있다. 현재 스크린샷은 대결 진행·프로필 장면이 새 규칙(AI 판정, 점수·전적)과 어긋난다. `DEPLOY.md` 4번, `docs/specs/retro-theme/spec.md` 범위 밖 참고
- 탈퇴한 상대의 지난 대결에서 사진 자리 안내 — 탈퇴하면 `battle_submissions.object_path`가 null이 되어 종결 뒤 공개되는 이력에 판정 사유만 남고 사진 자리는 비어 보인다. "사진 없음(탈퇴한 사용자)" 같은 안내가 있으면 좋다(design.md "탈퇴와의 상호작용"). 기능이 막히지는 않아 배포 후로 미룸
