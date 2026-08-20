# TODO Backlog

- 대결 초대 취소/거절(decline) 기능 — 현재 스키마는 `pending -> active`(수락)만 지원. 잘못 보낸 초대를 취소하거나 거절하는 경로가 없음.
- 품질전 증거 사진 업로드 — 현재 대결 진행 화면은 텍스트 증거만 지원. 사진 증거를 넣으려면 Supabase Storage 버킷/RLS + `image_picker` 패키지 추가 필요.
