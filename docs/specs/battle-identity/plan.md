# battle-identity 구현 계획

## 참고
- spec.md: `docs/specs/battle-identity/spec.md`
- design.md: `docs/specs/battle-identity/design.md`

## 작업 순서

### 1. 마이그레이션 (`supabase/migrations/20260827120000_battle_evidence_identity.sql`)
- `complete_speed_task(uuid)` / `submit_quality_evidence` / `decide_quality_evidence` 삭제
- `battle_participants.completed_at` 컬럼 삭제
- `submit_evidence(uuid, text, text)` / `decide_evidence(uuid, uuid, text)` 생성
- Storage 버킷 `battle_evidence`(비공개) + insert/update/select 정책
- 컬럼 주석 정정(`decision` = "이 참가자의 완료가 유효한가")

### 2. 패키지
- `image_picker` 추가 (사진 증거 필수화로 이번 스코프 승격). 카메라/갤러리 모두 사용.

### 3. 데이터 계층
- `BattleParticipant`: `completedAt` 제거
- `BattleRepository`: `completeSpeedTask` 제거, `submitEvidence` / `decideEvidence`로 일반화,
  `uploadEvidencePhoto`(Storage 업로드 → 경로 반환), `createEvidenceSignedUrl` 추가

### 4. 도메인 (`BattleDetail`)
- 제거: `canCompleteSpeedTask`, `isWaitingForOpponentSpeed`
- 유지/확장: `canSubmitEvidence`(유형 공통), `canReviewOpponentEvidence`(judging에서만)
- 신규: `requiresPhotoEvidence`, `wasMyEvidenceDisputed`, `wasOpponentEvidenceDisputed`,
  `isAwaitingBothDecisions`, `isSpeedDisputed`, `didILoseSpeedBattle`

### 5. 화면
- `_SpeedSection` / `_QualitySection` → 공용 `_EvidenceSection` 통합
- 사진 선택(카메라/갤러리 바텀시트) + 업로드 + 제출, 속도전은 텍스트도 허용
- 상대 증거 썸네일(서명 URL) + 승인/이의제기, 이의제기는 확인 다이얼로그
- 결과 배너를 유형/사유별로 분기

### 6. 목록/전적
- `BattleRecord.fromBattle`: 속도전도 `disputed`면 미결로 표시(현재는 무조건 승/패)

### 7. 문자열
- 신규: `battleSpeedEvidenceNotice`, `battleMyEvidenceDisputed`, `battleAwaitingBothDecisions`,
  `battleDisputeConfirmSpeed`, `battleDisputeConfirmQuality`, `battleWonByOpponentDisputed`,
  `battleWonBySpeed`, `battleLostByDisputed`, `battleLostBySpeed`, `battleSpeedDisputedMessage`,
  사진 선택 관련 문자열
- 제거: `battleComplete`, `battleCompleted`, `battleCompleteFailed`, `battleSpeedDone`,
  `battleSpeedWaiting`, `battleSpeedWaitingOpponent`

### 8. 테스트
- `battle_detail_test.dart`: `completedAt` 기반 케이스 제거, 신규 getter 케이스 추가
- `battle_record_test.dart`: 속도전 disputed → 미결 케이스 추가
- `widget_test.dart`: 속도전 화면이 완료 버튼이 아니라 증거 제출 폼을 보이도록 갱신

### 9. 문서
- CLAUDE.md 도메인 규칙 4줄 갱신(design.md에 대체 문구 명시됨)
- TODO_BACKLOG.md의 "품질전 증거 사진 업로드" 줄 제거

## 커밋 분할
1. `feat: 대결 증거/상호 승인 구조로 판정 RPC 일반화` (마이그레이션)
2. `feat: 속도전에도 증거 제출과 상호 승인 적용` (Dart 전체 + 테스트)
3. `docs: 대결 판정 규칙 변경을 CLAUDE.md에 반영`

## 검증 한계 (중요)
로컬에 Docker가 없어 `supabase start`/`db reset`으로 마이그레이션을 적용해볼 수 없다.
따라서 SQL은 **문법/로직 리뷰만 거친 미검증 상태**로 커밋되며, 실제 적용은 클라우드
프로젝트에 `supabase db push`로 사용자가 직접 수행해야 한다. Dart 쪽 판정 표시 로직은
유닛 테스트로 검증한다.
