// 증거 사진 제출(또는 교체) 접수.
//
// 흐름(mutual-judge design.md 흐름 1)
//   1. JWT로 호출자를 확인한다(클라이언트가 보낸 id는 믿지 않는다).
//   2. 사진이 버킷에 **실제로 있는지** 본다(없으면 BAD_REQUEST). 앱 사용자는 증거 사진을 지울 수도
//      바꿀 수도 없으므로(20261124130000) 이 확인을 지난 경로의 사진은 끝까지 그대로다 — 빈 경로로
//      먼저 접수해 시각을 잡고 나중에 사진을 올리는 길이 여기서 막힌다(2026-11-24 보안 점검 높음 1).
//   3. accept_submission: 참가자·동의·상태·마감·경로·촬영 시각(매칭 전/10분)·교체 가능 여부를
//      보고 제출 행을 만들거나(속도전이면 교체로 덮어쓴다) 거부한다. 거부되면 행이 남지 않는다 —
//      이때 업로드된 사진은 여기서 service 롤로 지운다 — **단 어떤 제출도 가리키지 않을 때만**.
//      그러지 않으면 판정 중에 내 제출 경로를 다시 보내 거부당하는 것만으로 서버가 그 사진을
//      대신 지워 주고, AI 재판정이 사진을 못 받아 대결이 무효가 된다(같은 점검 높음 2).
//   4. 교체로 밀려난 옛 사진이 있으면 같은 방식으로 지운다.
//
// 제출 즉시 판정하지 않는다. 판정은 마감(또는 양쪽 제출) 뒤 상호 판정 창에서 일어나고,
// 그 창을 여닫는 cron과 AI 재판정은 2·3단계의 DB 함수·judge-dispute Edge Function이 맡는다.
//
// 보내지 않는 것: 사용자 id·이름, 상대 정보, 점수.

import { getUserId, serviceClient } from '../_shared/auth.ts';
import { codeFromHint, errorResponse, jsonResponse } from '../_shared/errors.ts';
import { ValidationError, parseSubmitEvidenceRequest } from '../_shared/schemas.ts';
import {
  evidenceExists,
  removeIfUnreferenced,
  supabaseEvidenceStore,
} from '../_shared/evidence_storage.ts';

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
  const store = supabaseEvidenceStore(supabase);

  // 앱은 언제나 올린 뒤에 접수하므로 정상 흐름에서는 걸리지 않는다. 걸리면 API를 직접 부른 것이다.
  if (!(await evidenceExists(store, request.objectPath))) {
    console.error('submit-evidence: 올라가 있지 않은 사진 경로로 접수를 시도했습니다.');
    return errorResponse('BAD_REQUEST');
  }

  // 제출 수락 여부 판단. 거부되면 사진을 지워 버킷에 쓰레기가 남지 않게 한다.
  const { data: accepted, error: acceptError } = await supabase.rpc('accept_submission', {
    p_user_id: userId,
    p_battle_id: request.battleId,
    p_object_path: request.objectPath,
    p_captured_at: request.capturedAt,
  });

  if (acceptError) {
    if ((await removeIfUnreferenced(store, request.objectPath)) === 'kept') {
      console.error('submit-evidence: 거부된 경로가 제출이 가리키는 사진이라 지우지 않았습니다.');
    }
    const code = codeFromHint(acceptError.hint);
    if (code) {
      return errorResponse(code);
    }
    console.error(`accept_submission 실패: ${acceptError.message}`);
    return errorResponse('SERVER_ERROR');
  }

  // 교체로 밀려난 옛 사진. 경로는 서버(accept_submission)가 정한 값이고 더는 어디에서도
  // 참조하지 않는다. 같은 규칙(참조 없을 때만)을 지나게 해 삭제 경로를 하나로 둔다.
  const replacedObjectPath = accepted.replaced_object_path as string | null;
  if (replacedObjectPath) {
    await removeIfUnreferenced(store, replacedObjectPath);
  }

  return jsonResponse({
    submission_id: accepted.submission_id as number,
    replaced_object_path: replacedObjectPath,
    judging_opened: Boolean(accepted.judging_opened),
    battle_status: accepted.battle_status as string | null,
  });
});

