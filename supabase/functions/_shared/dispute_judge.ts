// AI 재판정 한 번 실행하기(judge-dispute).
//
// 실행 단위는 언제나 "임대 → 판정 → 기록" 하나이고, 임대에 실패하면 아무 일도 하지 않는다
// (cron이 같은 잡을 여러 번 불러도 한 번만 판정된다). 잡의 종류(kind)로 질문이 갈라진다.
//   - min_criteria: 불복당한 사진 한 장이 최소 기준을 충족하는가(두 유형 공통).
//   - superiority: 두 사진이 모두 통과로 확정된 품질전에서 우열 기준으로 누가 더 잘했는가.
//
// 승패는 여기서 정하지 않는다. AI 응답은 사실로만 DB에 들어가고, 상태·승자·점수는 DB의
// resolve_battle·finalize_battle이 정한다. AI에게는 사람의 판정 결과를 보내지 않는다.

import { encodeBase64 } from 'https://deno.land/std@0.224.0/encoding/base64.ts';
import { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';

import { generateJson, GeminiError, geminiModel } from './gemini.ts';
import {
  MIN_CRITERIA_JUDGE_SYSTEM_INSTRUCTION,
  PROMPT_VERSION,
  SUPERIORITY_JUDGE_SYSTEM_INSTRUCTION,
  buildMinCriteriaJudgeUserText,
  buildSuperiorityJudgeUserText,
} from './prompts.ts';
import {
  ValidationError,
  mapSuperiorityWinnerToParticipant,
  minCriteriaVerdictResponseSchema,
  parseMinCriteriaVerdictResponse,
  parseSuperiorityVerdictResponse,
  superiorityVerdictResponseSchema,
} from './schemas.ts';

const EVIDENCE_BUCKET = 'battle_evidence';
const MIN_CRITERIA_TIMEOUT_MS = 30_000;
/// 사진 두 장을 함께 보내므로 넉넉하게 둔다. 임대는 3분이라 여유가 있다.
const SUPERIORITY_TIMEOUT_MS = 60_000;

export type DisputeJudgeResult =
  /// 결론이 나서 대결이 종결됐다.
  | 'finished'
  | 'draw'
  /// 이 결론으로는 아직 끝나지 않았다(다른 판정이나 재판정이 남았다).
  | 'judging'
  /// 이번 시도는 실패했고 다음 시도가 예약됐다.
  | 'retry_scheduled'
  /// 시도를 모두 써서 대결이 무효가 됐다.
  | 'voided'
  /// 임대하지 못했다(다른 실행이 진행 중이거나, 시각이 안 됐거나, 이미 끝난 대결).
  | 'skipped';

interface MinCriteriaClaim {
  kind: 'min_criteria';
  token: string;
  attempt: number;
  title: string;
  min_criteria: string[];
  target_path: string;
}

interface SuperiorityClaim {
  kind: 'superiority';
  token: string;
  attempt: number;
  title: string;
  superiority_criteria: string[];
  creator_id: string;
  opponent_id: string;
  a_path: string;
  b_path: string;
}

type Claim = MinCriteriaClaim | SuperiorityClaim;

export async function runDisputeJudgment(
  supabase: SupabaseClient,
  jobId: number,
): Promise<DisputeJudgeResult> {
  const { data: claimed, error: claimError } = await supabase.rpc('claim_ai_judgment', {
    p_job_id: jobId,
  });

  if (claimError) {
    console.error(`claim_ai_judgment 실패(${jobId}): ${claimError.message}`);
    return 'skipped';
  }
  if (!claimed) {
    return 'skipped';
  }

  const claim = claimed as Claim;

  try {
    return claim.kind === 'min_criteria'
      ? await judgeMinCriteria(supabase, jobId, claim)
      : await judgeSuperiority(supabase, jobId, claim);
  } catch (error) {
    // 호출 실패·타임아웃·안전 차단·형식 오류(승자 누락 포함)·사진 다운로드 실패는 모두 이번 시도의
    // 실패다. 시도가 남아 있으면 서버가 알아서 다시 하고, 다 쓰면 대결이 무효로 끝난다.
    const message = error instanceof GeminiError || error instanceof ValidationError ||
        error instanceof Error
      ? error.message
      : '알 수 없는 오류';
    console.error(`AI 재판정 실패(잡 ${jobId}, ${claim.kind}, 시도 ${claim.attempt}): ${message}`);

    const { data: failed, error: failError } = await supabase.rpc('record_ai_judgment_failure', {
      p_job_id: jobId,
      p_token: claim.token,
      p_error: message,
    });

    if (failError) {
      console.error(`record_ai_judgment_failure 실패(${jobId}): ${failError.message}`);
      return 'skipped';
    }

    return (failed?.result ?? 'skipped') as DisputeJudgeResult;
  }
}

async function judgeMinCriteria(
  supabase: SupabaseClient,
  jobId: number,
  claim: MinCriteriaClaim,
): Promise<DisputeJudgeResult> {
  const photo = await downloadPhoto(supabase, claim.target_path);

  const raw = await generateJson({
    systemInstruction: MIN_CRITERIA_JUDGE_SYSTEM_INSTRUCTION,
    userText: buildMinCriteriaJudgeUserText({ title: claim.title, minCriteria: claim.min_criteria }),
    responseSchema: minCriteriaVerdictResponseSchema,
    images: [{ mimeType: 'image/jpeg', dataBase64: photo }],
    timeoutMs: MIN_CRITERIA_TIMEOUT_MS,
  });

  const verdict = parseMinCriteriaVerdictResponse(raw);

  const { data: recorded, error: recordError } = await supabase.rpc('record_min_criteria_verdict', {
    p_job_id: jobId,
    p_token: claim.token,
    p_meets: verdict.passed,
    p_reason: verdict.reason,
    p_model: `${geminiModel}/${PROMPT_VERSION}`,
  });

  if (recordError) {
    // 기록에 실패하면 임대가 만료될 때까지 잡이 묶여 있다가 cron이 실패 1회로 정리한다.
    console.error(`record_min_criteria_verdict 실패(${jobId}): ${recordError.message}`);
    return 'skipped';
  }

  return (recorded?.result ?? 'skipped') as DisputeJudgeResult;
}

async function judgeSuperiority(
  supabase: SupabaseClient,
  jobId: number,
  claim: SuperiorityClaim,
): Promise<DisputeJudgeResult> {
  // 위치 편향(앞에 온 사진을 더 좋게 보는 경향)을 줄이려고 매 시도마다 순서를 섞는다.
  // 되돌리기는 mapSuperiorityWinnerToParticipant가 한다.
  const flipped = Math.random() < 0.5;

  const [creatorPhoto, opponentPhoto] = await Promise.all([
    downloadPhoto(supabase, claim.a_path),
    downloadPhoto(supabase, claim.b_path),
  ]);

  const raw = await generateJson({
    systemInstruction: SUPERIORITY_JUDGE_SYSTEM_INSTRUCTION,
    userText: buildSuperiorityJudgeUserText({
      title: claim.title,
      superiorityCriteria: claim.superiority_criteria,
    }),
    responseSchema: superiorityVerdictResponseSchema,
    images: [
      { mimeType: 'image/jpeg', dataBase64: flipped ? opponentPhoto : creatorPhoto },
      { mimeType: 'image/jpeg', dataBase64: flipped ? creatorPhoto : opponentPhoto },
    ],
    timeoutMs: SUPERIORITY_TIMEOUT_MS,
  });

  const verdict = parseSuperiorityVerdictResponse(raw);
  const winner = mapSuperiorityWinnerToParticipant(verdict.winner, flipped);

  const { data: recorded, error: recordError } = await supabase.rpc('record_superiority_verdict', {
    p_job_id: jobId,
    p_token: claim.token,
    p_winner_user_id: winner === 'creator' ? claim.creator_id : claim.opponent_id,
    p_reason: verdict.winnerReason,
    p_model: `${geminiModel}/${PROMPT_VERSION}`,
  });

  if (recordError) {
    console.error(`record_superiority_verdict 실패(${jobId}): ${recordError.message}`);
    return 'skipped';
  }

  return (recorded?.result ?? 'skipped') as DisputeJudgeResult;
}

async function downloadPhoto(supabase: SupabaseClient, objectPath: string): Promise<string> {
  const { data, error } = await supabase.storage.from(EVIDENCE_BUCKET).download(objectPath);
  if (error || !data) {
    throw new Error(`증거 사진을 내려받지 못했습니다: ${error?.message ?? '내용 없음'}`);
  }
  return encodeBase64(await data.arrayBuffer());
}
