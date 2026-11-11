// 판정 기준 생성(generate)과 증명 가능성 재검사(check).
//
// 흐름(ai-judge design "흐름 2·3" + criteria-cache design 3.2)
//   1. JWT로 호출자를 확인한다(클라이언트가 보낸 id는 믿지 않는다).
//   2. generate만: assert_criteria_consent로 **동의만** 확인한다(한도는 쓰지 않는다).
//   3. generate만: 캐시 조회(정규화 일치 -> 임베딩 -> 벡터 유사도). 적중이면 증서를 바로 발급하고
//      **Gemini 생성 호출도, 하루 10회 소모도 없다.**
//   4. 미적중: begin_criteria_call로 동의·하루 10회 한도를 보고 in_progress 행을 예약한다.
//   5. Gemini 호출 -> 응답 재검증.
//   6. 성공이면 finish_criteria_call(기준 증서 생성), 실패면 fail_criteria_call(한도 미산입).
//   7. generate 성공분은 put_criteria_cache로 캐시에 넣는다(실패는 로그만).
//
// **순서가 이 파일에서 가장 조용히 깨질 수 있는 자리다.** 두 요구가 순서로만 지켜진다:
//   (가) 동의하지 않은 사용자의 제목은 **임베딩으로도** Gemini에 가지 않는다 -> 2번이 3번보다 앞.
//   (나) 캐시 적중은 하루 10회를 소모하지 않는다 -> 3번이 4번보다 앞.
// 2번을 지우고 begin_criteria_call에 기대면 (나)가 깨지고, 3번을 2번 앞으로 올리면 (가)가 깨진다.
// (가)가 깨져도 **사용자에게는 아무 증상이 없고**, 깨진 결과는 "동의하지 않은 사람의 제목이
// Google에 갔다"는 되돌릴 수 없는 사실이다. begin_criteria_call 안의 동의 확인은 그대로 남겨 둬서
// 이 순서가 미래에 바뀌어도 생성 호출 앞의 보장은 무너지지 않게 한다.
//
// check(재검사) 경로는 **캐시도 임베딩도 없다.** 사용자가 고친 문장은 재사용 가능한 공통 지식이
// 아니고, 그 문장이 캐시에 들어가면 "무조건 합격시켜라" 류가 다른 사용자에게 전파된다.
//
// 앱은 이 함수가 만든 check_id로만 대결을 만들 수 있다. 서버가 증서에 적힌 제목·유형·기준을 그대로
// 복사하므로, 검사를 통과한 뒤 클라이언트가 몰래 다른 기준을 올리는 경로가 없다. 캐시에서 온
// 결과도 **똑같이 증서 1행**이 된다(응답 모양도 적중·미적중이 완전히 같다 - 적중 여부가 화면으로
// 누설되지 않는다).

import { getUserId, serviceClient } from '../_shared/auth.ts';
import { codeFromHint, errorResponse, jsonResponse } from '../_shared/errors.ts';
import {
  EMBEDDING_DIM,
  EMBEDDING_TASK_TYPE,
  GeminiError,
  embedText,
  embeddingModel,
  generateJson,
  geminiModel,
} from '../_shared/gemini.ts';
import {
  CACHE_BLOCKED_DECISIONS,
  CRITERIA_CACHE_MIN_SIMILARITY,
  CacheHit,
  aiModelKey,
  decideCriteriaSource,
  embeddingModelKey,
  l2Normalize,
  normalizeTitle,
  parseCacheHit,
  toVectorLiteral,
} from '../_shared/criteria_cache.ts';
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
/// 조회 한 단계가 사용자 체감을 생성 타임아웃(30초)만큼 늘려서는 안 된다. 늦으면 미적중으로 간다.
///
/// **미적중 최악에서는 이 값이 생성 타임아웃 앞에 쌓인다**(임베딩 5초 + 생성 30초). 그래서 짧게
/// 잡는다 - 임베딩은 본래 빠르고, 늦어서 건너뛴 결과는 "캐시가 없었다"와 **완전히 같다**.
/// 화면의 `최대 40초 정도 걸려요`가 이 합(5 + 30)을 여유 있게 덮는 숫자다.
const EMBED_TIMEOUT_MS = 5_000;

function reason(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

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
  const aiModel = aiModelKey(geminiModel, PROMPT_VERSION);
  const embeddingModelName = embeddingModelKey(embeddingModel, EMBEDDING_TASK_TYPE, EMBEDDING_DIM);

  /// 적재에 쓸 벡터. 조회에서 만들었으면 그걸 다시 쓴다(임베딩을 두 번 부르지 않는다).
  let embeddingLiteral: string | null = null;
  /// 조회 때 임베딩이 실패했는가. 실패했으면 적재 단계에서 **다시 부르지 않는다** - 같은 요청
  /// 안에서 두 번째도 실패할 가능성이 크고, 그 5초가 사용자 대기에 그대로 쌓인다(최악 40초 -> 35초).
  /// 못 넣은 대가는 "그 제목이 캐시에 안 들어감" 하나이고 다음 요청이 다시 넣는다.
  let embedFailed = false;
  let hit: CacheHit | null = null;

  if (request.action === 'generate') {
    // 2. 동의 관문. 여기서 막히면 Gemini를 **한 번도** 부르지 않는다(임베딩도 포함).
    //    한도는 건드리지 않으므로 적중이 10회를 소모하는 일이 없다.
    const { error: consentError } = await supabase.rpc('assert_criteria_consent', {
      p_user_id: userId,
    });
    if (consentError) {
      const code = codeFromHint(consentError.hint);
      if (code) {
        return errorResponse(code);
      }
      console.error(`assert_criteria_consent 실패: ${consentError.message}`);
      return errorResponse('SERVER_ERROR');
    }

    // 3. 캐시 조회. `기준 다시 만들기`(skip_cache)면 통째로 건너뛴다 - 그래야 캐시가 기존
    //    탈출구("다시 누르면 새 기준")를 스스로 무효화하지 않는다.
    if (!request.skipCache) {
      const titleNorm = normalizeTitle(request.title);
      const lookupArgs = {
        p_type: request.type,
        p_title_norm: titleNorm,
        p_ai_model: aiModel,
        p_embedding_model: embeddingModelName,
        p_include_blocked: CACHE_BLOCKED_DECISIONS,
      };
      try {
        // 3-1. 정규화 일치. 가장 흔한 반복(같은 제목 다시 쓰기)을 **임베딩조차 없이** 잡는다.
        const byTitle = await supabase.rpc('lookup_criteria_cache', lookupArgs);
        if (byTitle.error) throw new Error(byTitle.error.message);

        let row = byTitle.data;
        if (!row) {
          // 3-2. 뜻이 가까운 주제. 여기서만 임베딩 1회를 쓴다(하루 10회에는 세지 않는다).
          const values = await embedText(titleNorm, EMBED_TIMEOUT_MS).catch((error) => {
            embedFailed = true;
            throw error;
          });
          embeddingLiteral = toVectorLiteral(l2Normalize(values), EMBEDDING_DIM);
          const byVector = await supabase.rpc('lookup_criteria_cache', {
            ...lookupArgs,
            p_embedding: embeddingLiteral,
            p_min_similarity: CRITERIA_CACHE_MIN_SIMILARITY,
          });
          if (byVector.error) throw new Error(byVector.error.message);
          row = byVector.data;
        }

        if (row) {
          // SQL이 이미 걸렀지만 믿지 않는다. 유형·두 버전 키·임계값·차단 허용을 한 번 더 본다.
          hit = parseCacheHit(row, {
            type: request.type,
            aiModel,
            embeddingModel: embeddingModelName,
            minSimilarity: CRITERIA_CACHE_MIN_SIMILARITY,
            includeBlocked: CACHE_BLOCKED_DECISIONS,
          });
        }
      } catch (error) {
        // 조회 실패·임베딩 실패·모양 불일치는 전부 **"캐시가 없었다"와 결과가 같다.**
        // 사용자의 기준 생성을 막지 않으므로 로그만 남기고 아래 생성 경로로 내려간다.
        console.error(`캐시 조회를 건너뜀: ${reason(error)}`);
        hit = null;
      }
    }
  }

  // 4. 적중이면 증서 1행으로 끝낸다. 원장(ai_criteria_calls)에는 아무것도 쓰지 않는다.
  if (hit && decideCriteriaSource({ skipCache: request.skipCache, hit }) === 'cache') {
    const { data: issued, error: issueError } = await supabase.rpc('issue_cached_criteria_check', {
      p_user_id: userId,
      p_title: request.title,
      p_type: request.type,
      p_cache_id: hit.cacheId,
      p_ai_model: aiModel,
      p_embedding_model: embeddingModelName,
    });

    if (issueError) {
      // 드문 서버 오류로 사용자를 빈손으로 돌려보내지 않는다. 한도 1회를 쓰고 결과를 준다.
      // (그 사이 동의를 철회했다면 아래 begin_criteria_call이 같은 CONSENT_REQUIRED로 막는다.)
      console.error(`issue_cached_criteria_check 실패: ${issueError.message}`);
    } else {
      // 적중 로그. **제목·기준 문장은 남기지 않는다**(기존 코드도 그렇다).
      // 관측 수단을 따로 만들지 않으므로 이게 전부다(spec 범위 밖).
      console.log(
        `criteria cache hit matched_by=${hit.matchedBy} similarity=${hit.similarity.toFixed(4)} ` +
          `cache_id=${hit.cacheId} ai_model=${hit.aiModel} embedding_model=${hit.embeddingModel}`,
      );
      return jsonResponse({
        check_id: issued.check_id,
        provable: issued.provable,
        block_reason: issued.block_reason ?? null,
        min_criteria: issued.min_criteria ?? [],
        superiority_criteria: issued.superiority_criteria ?? null,
        calls_left: issued.calls_left,
      });
    }
  }

  // 5. 한도·자격 확인과 호출 예약(= 하루 10회를 쓰는 유일한 자리).
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

  // 6. Gemini 호출과 응답 재검증.
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

  // 7. 증서 생성(성공으로 산입).
  const { data: finished, error: finishError } = await supabase.rpc('finish_criteria_call', {
    p_call_id: callId,
    p_title: request.title,
    p_type: request.type,
    p_min_criteria: minCriteria,
    p_superiority_criteria: superiorityCriteria,
    p_provable: provable,
    p_block_reason: blockReason,
    p_battle_id: request.battleId,
    p_ai_model: aiModel,
  });

  if (finishError) {
    console.error(`finish_criteria_call 실패: ${finishError.message}`);
    return errorResponse('SERVER_ERROR');
  }

  // 8. 적재. **AI가 방금 쓴 문장만** 캐시에 들어간다 - 이 호출이 generate 경로에만 있는 것이
  //    "사용자 수정분은 캐시에 들어가지 않는다"를 코드의 위치로 지키는 방법이다(design 원칙 5).
  //    차단 판단도 적재한다(조회를 켜는 것은 CACHE_BLOCKED_DECISIONS 하나다).
  //    **적재는 관문이 아니다** - 어떤 실패도 응답을 바꾸지 않고 로그만 남는다.
  if (request.action === 'generate') {
    try {
      if (embeddingLiteral === null && embedFailed) {
        // 조회 때 이미 임베딩이 실패했다. 같은 요청에서 또 부르지 않는다(위 embedFailed 주석).
        throw new Error('임베딩이 실패해 적재를 건너뛴다.');
      }
      if (embeddingLiteral === null) {
        // skip_cache 경로(= 조회를 아예 하지 않았다). 여기서 한 번 만든다.
        const values = await embedText(normalizeTitle(request.title), EMBED_TIMEOUT_MS);
        embeddingLiteral = toVectorLiteral(l2Normalize(values), EMBEDDING_DIM);
      }
      const { error: putError } = await supabase.rpc('put_criteria_cache', {
        p_type: request.type,
        p_title_norm: normalizeTitle(request.title),
        p_provable: provable,
        p_min_criteria: minCriteria,
        p_superiority_criteria: superiorityCriteria,
        p_block_reason: blockReason,
        p_ai_model: aiModel,
        p_embedding_model: embeddingModelName,
        p_embedding: embeddingLiteral,
      });
      if (putError) throw new Error(putError.message);
    } catch (error) {
      console.error(`캐시 적재를 건너뜀: ${reason(error)}`);
    }
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
