// 판정 기준 생성(generate)과 증명 가능성 재검사(check).
//
// 흐름(design.md 흐름 2·3)
//   1. JWT로 호출자를 확인한다(클라이언트가 보낸 id는 믿지 않는다).
//   2. begin_criteria_call: 동의·모집 1개·오늘 슬롯·하루 10회 한도를 보고 in_progress 행을 예약한다.
//      여기서 막히면 Gemini를 부르지 않는다 — 동의 전에는 어떤 대결 데이터도 AI로 나가지 않는다.
//   3. Gemini 호출 → 응답 재검증.
//   4. 성공이면 finish_criteria_call(기준 증서 생성), 실패면 fail_criteria_call(한도 미산입).
//
// 앱은 이 함수가 만든 check_id로만 대결을 만들 수 있다. 서버가 증서에 적힌 제목·유형·기준을 그대로
// 복사하므로, 검사를 통과한 뒤 클라이언트가 몰래 다른 기준을 올리는 경로가 없다.

import { getUserId, serviceClient } from '../_shared/auth.ts';
import { codeFromHint, errorResponse, jsonResponse } from '../_shared/errors.ts';
import { generateJson, GeminiError, geminiModel } from '../_shared/gemini.ts';
import {
  CHECK_SYSTEM_INSTRUCTION,
  GENERATE_SYSTEM_INSTRUCTION,
  PROMPT_VERSION,
  buildCheckUserText,
  buildGenerateUserText,
} from '../_shared/prompts.ts';
import {
  ValidationError,
  checkResponseSchema,
  generationResponseSchema,
  parseCheckResponse,
  parseCriteriaRequest,
  parseGenerationResponse,
} from '../_shared/schemas.ts';

const CRITERIA_TIMEOUT_MS = 30_000;

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
    request = parseCriteriaRequest(await req.json().catch(() => null));
  } catch (error) {
    if (error instanceof ValidationError) {
      console.error(`battle-criteria 입력 오류: ${error.message}`);
      return errorResponse('BAD_REQUEST');
    }
    throw error;
  }

  const supabase = serviceClient();

  // 2. 한도·자격 확인과 호출 예약.
  const { data: callId, error: beginError } = await supabase.rpc('begin_criteria_call', {
    p_user_id: userId,
    p_action: request.action,
    p_battle_id: request.battleId,
  });

  if (beginError) {
    const code = codeFromHint(beginError.hint);
    if (code) {
      return errorResponse(code, code === 'CRITERIA_CALL_LIMIT' ? { calls_left: 0 } : {});
    }
    console.error(`begin_criteria_call 실패: ${beginError.message}`);
    return errorResponse('SERVER_ERROR');
  }

  // 3. Gemini 호출과 응답 재검증.
  let provable: boolean;
  let blockReason: string | null;
  let minCriteria: string[];
  let superiorityCriteria: string[] | null;

  try {
    if (request.action === 'generate') {
      const raw = await generateJson({
        systemInstruction: GENERATE_SYSTEM_INSTRUCTION,
        userText: buildGenerateUserText(request),
        responseSchema: generationResponseSchema,
        timeoutMs: CRITERIA_TIMEOUT_MS,
      });
      const result = parseGenerationResponse(raw, request.type);
      provable = result.provable;
      blockReason = result.blockReason;
      minCriteria = result.minCriteria;
      superiorityCriteria = result.superiorityCriteria;
    } else {
      const raw = await generateJson({
        systemInstruction: CHECK_SYSTEM_INSTRUCTION,
        userText: buildCheckUserText(request),
        responseSchema: checkResponseSchema,
        timeoutMs: CRITERIA_TIMEOUT_MS,
      });
      const result = parseCheckResponse(raw);
      provable = result.provable;
      blockReason = result.blockReason;
      // 재검사에서는 AI가 기준을 다시 쓰지 않는다. 사용자가 고친 목록을 그대로 증서에 담는다.
      minCriteria = provable ? request.minCriteria ?? [] : [];
      superiorityCriteria = provable ? request.superiorityCriteria ?? null : null;
    }
  } catch (error) {
    // 호출 실패·타임아웃·안전 차단·형식 오류는 모두 AI 실패다. 하루 10회에 세지 않는다(결정 61).
    if (error instanceof GeminiError || error instanceof ValidationError) {
      console.error(`기준 AI 호출 실패(${request.action}): ${error.message}`);
      const { data: failed } = await supabase.rpc('fail_criteria_call', { p_call_id: callId });
      return errorResponse('AI_FAILED', { calls_left: failed?.calls_left ?? null });
    }
    throw error;
  }

  // 4. 증서 생성(성공으로 산입).
  const { data: finished, error: finishError } = await supabase.rpc('finish_criteria_call', {
    p_call_id: callId,
    p_title: request.title,
    p_type: request.type,
    p_min_criteria: minCriteria,
    p_superiority_criteria: superiorityCriteria,
    p_provable: provable,
    p_block_reason: blockReason,
    p_battle_id: request.battleId,
    p_ai_model: `${geminiModel}/${PROMPT_VERSION}`,
  });

  if (finishError) {
    console.error(`finish_criteria_call 실패: ${finishError.message}`);
    return errorResponse('SERVER_ERROR');
  }

  return jsonResponse({
    check_id: finished.check_id,
    provable,
    block_reason: blockReason,
    min_criteria: minCriteria,
    superiority_criteria: superiorityCriteria,
    calls_left: finished.calls_left,
  });
});
