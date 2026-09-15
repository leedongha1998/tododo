-- ai-judge 1단계: 상호 승인 모델 시절의 테스트 대결 데이터 정리.
--
-- 근거: docs/specs/ai-judge/decisions.md 57번, design.md "마이그레이션 계획" 1.
-- 배포 전이라 실사용자 데이터가 없다. 기존 대결은 전부 새 규칙과 맞지 않으므로(텍스트 증거,
-- 승자 없는 품질전, 참가자 이의제기로 끝난 disputed) 선별하지 않고 모두 지운다.
--
-- 되돌릴 수 없다. battle_participants는 on delete cascade로 함께 지워진다.
-- profiles, todos, auth.users는 건드리지 않는다.
--
-- Storage의 증거 사진은 SQL로 지울 수 없다(storage.protect_delete() 트리거 —
-- 20260903090000_delete_account_storage_fix.sql 참고). 적용 직후 Storage API로 비운다:
--   supabase storage rm -r ss:///battle_evidence/ --linked --experimental

delete from public.battles;
