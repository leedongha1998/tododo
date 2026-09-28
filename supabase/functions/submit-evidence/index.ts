// 증거 사진 제출과 교체.
//
// 흐름(mutual-judge design.md 흐름 1)
//   1. JWT로 호출자를 확인한다(클라이언트가 보낸 id는 믿지 않는다).
//   2. accept_submission: 참가자·동의·상태·마감·경로·촬영 시각(매칭 전/10분)·교체 가능 여부를 보고
//      제출 행을 만들거나(첫 제출) 덮어쓴다(속도전 교체, 상대 미제출일 때만). 양쪽이 제출했으면
//      같은 트랜잭션에서 판정 창이 열린다.
//   3. 거부되면 방금 올린 사진을, 교체되면 밀려난 옛 사진을 service 롤로 지운다. 업로드는 DB 잠금 밖에서
//      일어나므로 버킷 정리는 이 함수의 몫이다.
//
// 제출 즉시 AI 판정은 없다. 판정은 판정 창에서 참가자끼리 하고, 결론이 나지 않은 것만 AI가 다시 본다
// (3단계 judge-dispute). 그래서 이 함수는 Gemini를 부르지 않는다.

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

  const { data: accepted, error: acceptError } = await supabase.rpc('accept_submission', {
    p_user_id: userId,
    p_battle_id: request.battleId,
    p_object_path: request.objectPath,
    p_captured_at: request.capturedAt,
  });

  if (acceptError) {
    // 거부된 사진은 제출로 치지 않는다. 버킷에 쓰레기가 남지 않게 지운다.
    await removeObject(supabase, request.objectPath, '거부된 사진');
    const code = codeFromHint(acceptError.hint);
    if (code) {
      return errorResponse(code);
    }
    console.error(`accept_submission 실패: ${acceptError.message}`);
    return errorResponse('SERVER_ERROR');
  }

  const replacedPath = accepted.replaced_object_path as string | null;
  if (replacedPath) {
    // 교체로 밀려난 옛 사진. 행을 덮어썼으므로 이 파일을 가리키는 곳이 없다.
    await removeObject(supabase, replacedPath, '교체된 사진');
  }

  return jsonResponse({
    submission_id: accepted.submission_id as number,
    replaced: replacedPath != null,
    judging_opened: accepted.judging_opened === true,
    battle_status: (accepted.battle_status as string | null) ?? null,
  });
});

async function removeObject(
  supabase: ReturnType<typeof serviceClient>,
  objectPath: string,
  label: string,
): Promise<void> {
  const { error } = await supabase.storage.from(EVIDENCE_BUCKET).remove([objectPath]);
  if (error) {
    // 사진이 남아도 제출 결과는 그대로다. 지우지 못한 파일은 알려진 한계(주기 정리, TODO_BACKLOG)로 둔다.
    console.error(`${label} 삭제 실패: ${error.message}`);
  }
}
