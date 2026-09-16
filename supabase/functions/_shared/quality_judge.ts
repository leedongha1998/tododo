// 품질전 판정 한 번 실행하기.
//
// judge-quality(HTTP)와 submit-evidence(두 번째 제출 직후 즉시 실행)가 같은 코드를 쓴다.
// 실행 단위는 언제나 "임대 → 판정 → 기록" 하나이고, 임대에 실패하면 아무 일도 하지 않는다
// (cron과 즉시 실행이 겹쳐도 한 번만 판정된다).
//
// 승패는 여기서 정하지 않는다. AI 응답은 "각 사진이 최소 기준을 충족했는가 / 우열 기준으로 어느 쪽이
// 더 나은가"라는 사실로만 DB에 들어가고, 상태·승자·점수는 DB의 quality_outcome·finalize_battle이 정한다.

import { encodeBase64 } from 'https://deno.land/std@0.224.0/encoding/base64.ts';
import { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';

import { generateJson, GeminiError, geminiModel } from './gemini.ts';
import {
  PROMPT_VERSION,
  QUALITY_JUDGE_SYSTEM_INSTRUCTION,
  buildQualityJudgeUserText,
} from './prompts.ts';
import {
  ValidationError,
  mapQualityVerdictToParticipants,
  parseQualityVerdictResponse,
  qualityVerdictResponseSchema,
} from './schemas.ts';

const EVIDENCE_BUCKET = 'battle_evidence';
/// 사진 두 장을 함께 보내므로 속도전(30초)보다 넉넉하게 둔다. 임대는 3분이라 여유가 있다.
const QUALITY_JUDGE_TIMEOUT_MS = 60_000;

export type QualityJudgeResult =
  /// 판정이 끝나 대결이 종결됐다.
  | 'finished'
  | 'draw'
  /// 이번 시도는 실패했고 다음 시도가 예약됐다.
  | 'retry_scheduled'
  /// 시도를 모두 써서 대결이 무효가 됐다.
  | 'voided'
  /// 임대하지 못했다(다른 실행이 진행 중이거나 이미 끝난 대결).
  | 'skipped';

interface ClaimedJudgment {
  token: string;
  attempt: number;
  creator_id: string;
  opponent_id: string;
  title: string;
  min_criteria: string[];
  superiority_criteria: string[];
  a_path: string;
  b_path: string;
}

export async function runQualityJudgment(
  supabase: SupabaseClient,
  battleId: string,
): Promise<QualityJudgeResult> {
  const { data: claimed, error: claimError } = await supabase.rpc('claim_quality_judgment', {
    p_battle_id: battleId,
  });

  if (claimError) {
    console.error(`claim_quality_judgment 실패(${battleId}): ${claimError.message}`);
    return 'skipped';
  }
  if (!claimed) {
    // 다른 실행이 임대 중이거나, 아직 다음 시도 시각이 되지 않았거나, 대결이 이미 끝났다.
    return 'skipped';
  }

  const claim = claimed as ClaimedJudgment;

  // 위치 편향(앞에 온 사진을 더 좋게 보는 경향)을 줄이려고 매 시도마다 순서를 섞는다.
  // 되돌리기는 mapQualityVerdictToParticipants가 한다.
  const flipped = Math.random() < 0.5;

  try {
    const [creatorPhoto, opponentPhoto] = await Promise.all([
      downloadPhoto(supabase, claim.a_path),
      downloadPhoto(supabase, claim.b_path),
    ]);

    const first = flipped ? opponentPhoto : creatorPhoto;
    const second = flipped ? creatorPhoto : opponentPhoto;

    const raw = await generateJson({
      systemInstruction: QUALITY_JUDGE_SYSTEM_INSTRUCTION,
      userText: buildQualityJudgeUserText({
        title: claim.title,
        minCriteria: claim.min_criteria,
        superiorityCriteria: claim.superiority_criteria,
      }),
      responseSchema: qualityVerdictResponseSchema,
      images: [
        { mimeType: 'image/jpeg', dataBase64: first },
        { mimeType: 'image/jpeg', dataBase64: second },
      ],
      timeoutMs: QUALITY_JUDGE_TIMEOUT_MS,
    });

    const verdict = mapQualityVerdictToParticipants(parseQualityVerdictResponse(raw), flipped);

    const winnerUserId = verdict.winner === 'creator'
      ? claim.creator_id
      : verdict.winner === 'opponent'
      ? claim.opponent_id
      : null;

    const { data: recorded, error: recordError } = await supabase.rpc('record_quality_verdict', {
      p_battle_id: battleId,
      p_token: claim.token,
      p_a_meets: verdict.creator.meetsCriteria,
      p_a_reason: verdict.creator.reason,
      p_b_meets: verdict.opponent.meetsCriteria,
      p_b_reason: verdict.opponent.reason,
      p_winner_user_id: winnerUserId,
      p_reason: verdict.winnerReason,
      p_model: `${geminiModel}/${PROMPT_VERSION}`,
    });

    if (recordError) {
      // 기록에 실패하면 임대가 만료될 때까지 잡이 묶여 있다가 cron이 실패 1회로 정리한다.
      console.error(`record_quality_verdict 실패(${battleId}): ${recordError.message}`);
      return 'skipped';
    }

    return (recorded?.result ?? 'skipped') as QualityJudgeResult;
  } catch (error) {
    // 호출 실패·타임아웃·안전 차단·형식 오류(승자 누락 포함)·사진 다운로드 실패는 모두 이번 시도의
    // 실패다. 시도가 남아 있으면 서버가 알아서 다시 하고, 다 쓰면 대결이 무효로 끝난다(결정 19).
    const message = error instanceof GeminiError || error instanceof ValidationError ||
        error instanceof Error
      ? error.message
      : '알 수 없는 오류';
    console.error(`품질전 판정 실패(${battleId}, 시도 ${claim.attempt}): ${message}`);

    const { data: failed, error: failError } = await supabase.rpc('record_quality_failure', {
      p_battle_id: battleId,
      p_token: claim.token,
      p_error: message,
    });

    if (failError) {
      console.error(`record_quality_failure 실패(${battleId}): ${failError.message}`);
      return 'skipped';
    }

    return (failed?.result ?? 'skipped') as QualityJudgeResult;
  }
}

async function downloadPhoto(supabase: SupabaseClient, objectPath: string): Promise<string> {
  const { data, error } = await supabase.storage.from(EVIDENCE_BUCKET).download(objectPath);
  if (error || !data) {
    throw new Error(`증거 사진을 내려받지 못했습니다: ${error?.message ?? '내용 없음'}`);
  }
  return encodeBase64(await data.arrayBuffer());
}
