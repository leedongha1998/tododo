// 증거 사진 제출과 속도전 판정.
//
// 흐름(design.md 흐름 5)
//   1. JWT로 호출자를 확인한다(클라이언트가 보낸 id는 믿지 않는다).
//   2. accept_submission: 참가자·동의·상태·마감·경로·촬영 시각(매칭 전/10분)·통과 여부·판정 중·5회
//      상한을 보고 제출 행을 만든다. 거부되면 행이 남지 않으므로 어떤 횟수에도 들어가지 않는다 —
//      이때 업로드된 사진은 여기서 service 롤로 지운다.
//   3. 속도전이면 사진을 내려받아 Gemini에 최소 기준 판정을 맡긴다(재시도 없음. 실패는 그 제출만
//      무효이고 5회 상한에 세지 않으므로 사용자가 다시 내면 된다).
//   4. record_speed_verdict가 판정 사실을 기록하고, 승패·점수는 DB의 resolve_battle이 정한다.
//
// 품질전은 제출 행만 만들고 끝낸다. 두 사진을 비교하는 판정 잡은 6단계(judge-quality)에서 붙는다.
//
// 보내지 않는 것: 사용자 id·이름, 상대 정보, 촬영 시각, 점수(결정 69).

import { encodeBase64 } from 'https://deno.land/std@0.224.0/encoding/base64.ts';

import { getUserId, serviceClient } from '../_shared/auth.ts';
import { codeFromHint, errorResponse, jsonResponse } from '../_shared/errors.ts';
import { generateJson, GeminiError, geminiModel } from '../_shared/gemini.ts';
import {
  PROMPT_VERSION,
  SPEED_JUDGE_SYSTEM_INSTRUCTION,
  buildSpeedJudgeUserText,
} from '../_shared/prompts.ts';
import {
  ValidationError,
  parseSpeedVerdictResponse,
  parseSubmitEvidenceRequest,
  speedVerdictResponseSchema,
} from '../_shared/schemas.ts';

const EVIDENCE_BUCKET = 'battle_evidence';
const SPEED_JUDGE_TIMEOUT_MS = 30_000;

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

  // 2. 제출 수락 여부 판단. 거부되면 사진을 지워 버킷에 쓰레기가 남지 않게 한다.
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

  const submissionId = accepted.submission_id as number;

  if (accepted.type !== 'speed') {
    // 품질전: 두 사진이 모두 올라온 뒤 대결 단위로 판정한다(6단계).
    const { data: battle } = await supabase
      .from('battles')
      .select('status')
      .eq('id', request.battleId)
      .single();
    return jsonResponse({ submission_id: submissionId, battle_status: battle?.status ?? null });
  }

  // 3. 사진과 기준을 모아 판정을 맡긴다.
  let verdict: 'passed' | 'failed' | 'error';
  let reason: string | null;

  try {
    const [photo, criteria] = await Promise.all([
      downloadPhoto(supabase, request.objectPath),
      loadCriteria(supabase, request.battleId),
    ]);

    const raw = await generateJson({
      systemInstruction: SPEED_JUDGE_SYSTEM_INSTRUCTION,
      userText: buildSpeedJudgeUserText({ title: criteria.title, minCriteria: criteria.minCriteria }),
      responseSchema: speedVerdictResponseSchema,
      images: [{ mimeType: 'image/jpeg', dataBase64: photo }],
      timeoutMs: SPEED_JUDGE_TIMEOUT_MS,
    });

    const result = parseSpeedVerdictResponse(raw);
    verdict = result.passed ? 'passed' : 'failed';
    reason = result.reason;
  } catch (error) {
    // 호출 실패·타임아웃·안전 차단·형식 오류·사진 다운로드 실패는 모두 "그 제출만 무효"다.
    // 5회 상한에 세지 않으므로 사용자는 손해 없이 다시 낼 수 있다(결정 60).
    if (error instanceof GeminiError || error instanceof ValidationError || error instanceof Error) {
      console.error(`속도전 판정 실패(submission ${submissionId}): ${error.message}`);
      verdict = 'error';
      reason = null;
    } else {
      throw error;
    }
  }

  // 4. 판정 사실만 기록한다. 종결·승자·점수는 DB 규칙이 정한다.
  const { data: recorded, error: recordError } = await supabase.rpc('record_speed_verdict', {
    p_submission_id: submissionId,
    p_verdict: verdict,
    p_reason: reason,
    p_model: `${geminiModel}/${PROMPT_VERSION}`,
  });

  if (recordError) {
    console.error(`record_speed_verdict 실패: ${recordError.message}`);
    return errorResponse('SERVER_ERROR');
  }

  return jsonResponse({
    submission_id: submissionId,
    verdict,
    reason,
    battle_status: recorded?.battle_status ?? null,
  });
});

async function removeObject(
  supabase: ReturnType<typeof serviceClient>,
  objectPath: string,
): Promise<void> {
  const { error } = await supabase.storage.from(EVIDENCE_BUCKET).remove([objectPath]);
  if (error) {
    // 사진이 남아도 제출은 거부된 채다. 지우지 못한 파일은 알려진 한계(주기 정리)로 둔다.
    console.error(`거부된 사진 삭제 실패: ${error.message}`);
  }
}

async function downloadPhoto(
  supabase: ReturnType<typeof serviceClient>,
  objectPath: string,
): Promise<string> {
  const { data, error } = await supabase.storage.from(EVIDENCE_BUCKET).download(objectPath);
  if (error || !data) {
    throw new Error(`증거 사진을 내려받지 못했습니다: ${error?.message ?? '내용 없음'}`);
  }
  return encodeBase64(await data.arrayBuffer());
}

/// 판정에 쓰는 기준은 클라이언트가 보낸 값이 아니라 DB에 확정된 값이다.
async function loadCriteria(
  supabase: ReturnType<typeof serviceClient>,
  battleId: string,
): Promise<{ title: string; minCriteria: string[] }> {
  const { data, error } = await supabase
    .from('battles')
    .select('title, min_criteria')
    .eq('id', battleId)
    .single();

  if (error || !data) {
    throw new Error(`대결 기준을 읽지 못했습니다: ${error?.message ?? '내용 없음'}`);
  }
  return { title: data.title as string, minCriteria: data.min_criteria as string[] };
}
