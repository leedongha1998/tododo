// 계정 삭제(탈퇴) — 증거 사진 정리까지.
//
// 왜 Edge인가(2026-11-24 보안 점검 높음 1·2)
//   예전에는 앱이 탈퇴 직전에 내 증거 사진을 직접 지웠다. 그러려면 "내 폴더의 사진은 언제든 지울
//   수 있다"는 Storage 정책이 필요했는데, 그 정책이 판정 중 사진 삭제(→ AI 재판정 실패 → 대결 무효)와
//   제출 시각을 지킨 채 사진 바꿔치기를 함께 열어 두었다. 그 정책을 없앴으므로(20261124130000)
//   사진 정리는 service 롤로 여기서 한다. storage.objects를 SQL로 지우면 실제 파일이 남으므로
//   (protect_objects_delete 트리거도 막는다) Storage API로 지운다.
//
// 흐름
//   1. JWT로 호출자를 확인한다.
//   2. 내가 참가한 대결 id를 먼저 모은다(사진 폴더가 `battleId/userId/`다).
//   3. **delete_account를 먼저** 호출자의 JWT로 부른다 — 끝나지 않은 대결이 cancelled가 된 뒤에
//      사진을 지워야, "사진은 사라졌는데 대결은 아직 판정 중"인 틈이 생기지 않는다.
//      실패하면 아무것도 지우지 않고 오류를 돌려준다(앱이 토스트로 알린다).
//   4. 사진을 지운다. 실패해도 탈퇴는 이미 끝났으므로 로그만 남긴다(예전 앱 쪽 처리와 같은 태도).

import { getUserId, serviceClient, userClient } from '../_shared/auth.ts';
import { errorResponse, jsonResponse } from '../_shared/errors.ts';
import { removeUserEvidence, supabaseEvidenceStore } from '../_shared/evidence_storage.ts';

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== 'POST') {
    return errorResponse('BAD_REQUEST');
  }

  const authorization = req.headers.get('Authorization');
  const userId = await getUserId(req);
  if (!userId || !authorization) {
    return errorResponse('UNAUTHORIZED');
  }

  const supabase = serviceClient();

  const { data: rows, error: listError } = await supabase
    .from('battle_participants')
    .select('battle_id')
    .eq('user_id', userId);
  if (listError) {
    console.error(`delete-account: 참가 대결 조회 실패 - ${listError.message}`);
    return errorResponse('SERVER_ERROR');
  }
  const battleIds = (rows ?? []).map((row) => row.battle_id as string);

  const { error: deleteError } = await userClient(authorization).rpc('delete_account');
  if (deleteError) {
    console.error(`delete-account: delete_account 실패 - ${deleteError.message}`);
    return errorResponse('SERVER_ERROR');
  }

  const failedFolders = await removeUserEvidence(
    supabaseEvidenceStore(supabase),
    userId,
    battleIds,
  );
  if (failedFolders > 0) {
    console.error(`delete-account: 사진 폴더 ${failedFolders}개를 지우지 못했습니다.`);
  }

  return jsonResponse({ deleted: true });
});
