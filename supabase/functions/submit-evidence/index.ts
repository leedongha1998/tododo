// 증거 사진 제출(또는 교체) 접수.
//
// 흐름(mutual-judge design.md 흐름 1)
//   1. JWT로 호출자를 확인한다(클라이언트가 보낸 id는 믿지 않는다).
//   2. accept_submission: 참가자·동의·상태·마감·경로·촬영 시각(매칭 전/10분)·교체 가능 여부를
//      보고 제출 행을 만들거나(속도전이면 교체로 덮어쓴다) 거부한다. 거부되면 행이 남지 않는다 —
//      이때 업로드된 사진은 여기서 service 롤로 지운다.
//   3. 교체로 밀려난 옛 사진이 있으면 같은 방식으로 지운다.
//
// 제출 즉시 판정하지 않는다. 판정은 마감(또는 양쪽 제출) 뒤 상호 판정 창에서 일어나고,
// 그 창을 여닫는 cron과 AI 재판정은 2·3단계의 DB 함수·judge-dispute Edge Function이 맡는다.
//
// 보내지 않는 것: 사용자 id·이름, 상대 정보, 점수.

import { getUserId, serviceClient } from '../_shared/auth.ts';
import { codeFromHint, errorResponse, jsonResponse } from '../_shared/errors.ts';
import { ValidationError, parseSubmitEvidenceRequest } from '../_shared/schemas.ts';

const EVIDENCE_BUCKET = 'battle_evidence';

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== 'POST') {
    return errorResponse('BAD_REQUEST');
  }

  const userId = await getUserId(req);
  if (!userId) {
    return errorResponse('UNAUTHORIZED');
  }

  let request;
  try {
    request = parseSubmitEvidenceRequest(await req.json().catch(() => null), userId);
  } catch (error) {
    if (error instanceof ValidationError) {
      console.error(`submit-evidence 입력 오류: ${error.message}`);
      return errorResponse('BAD_REQUEST');
    }
    throw error;
  }

  const supabase = serviceClient();

  // 제출 수락 여부 판단. 거부되면 사진을 지워 버킷에 쓰레기가 남지 않게 한다.
  const { data: accepted, error: acceptError } = await supabase.rpc('accept_submission', {
    p_user_id: userId,
    p_battle_id: request.battleId,
    p_object_path: request.objectPath,
    p_captured_at: request.capturedAt,
  });

  if (acceptError) {
    await removeObject(supabase, request.objectPath);
    const code = codeFromHint(acceptError.hint);
    if (code) {
      return errorResponse(code);
    }
    console.error(`accept_submission 실패: ${acceptError.message}`);
    return errorResponse('SERVER_ERROR');
  }

  // 교체로 밀려난 옛 사진. 더는 어디에서도 참조하지 않으므로 지운다.
  const replacedObjectPath = accepted.replaced_object_path as string | null;
  if (replacedObjectPath) {
    await removeObject(supabase, replacedObjectPath);
  }

  return jsonResponse({
    submission_id: accepted.submission_id as number,
    replaced_object_path: replacedObjectPath,
    judging_opened: Boolean(accepted.judging_opened),
    battle_status: accepted.battle_status as string | null,
  });
});

async function removeObject(
  supabase: ReturnType<typeof serviceClient>,
  objectPath: string,
): Promise<void> {
  const { error } = await supabase.storage.from(EVIDENCE_BUCKET).remove([objectPath]);
  if (error) {
    // 사진이 남아도 판정에는 영향이 없다. 지우지 못한 파일은 알려진 한계(주기 정리)로 둔다.
    console.error(`사진 삭제 실패: ${error.message}`);
  }
}
