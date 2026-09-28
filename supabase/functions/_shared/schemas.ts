// 요청 입력 검증과 Gemini 응답 재검증.
//
// Gemini의 responseSchema 강제를 믿지 않고 서버에서 한 번 더 본다. 검증에 실패하면 AI 실패로 취급한다
// (스키마 밖 필드·초과 길이를 잘라 쓰지 않는다 — 잘린 기준·사유가 오해를 부른다).

export const BATTLE_TYPES = ['speed', 'quality'] as const;
export type BattleType = (typeof BATTLE_TYPES)[number];

// 대결 기간은 분 단위 커스텀이다(mutual-judge spec "P0. 커스텀 마감"). 하한 1분, 상한 10080분(7일).
// DB 제약(battles_duration_minutes_check)과 같은 범위를 쓴다 — 한쪽만 바뀌면 통과한 요청이 insert에서 깨진다.
export const DURATION_MINUTES_MIN = 1;
export const DURATION_MINUTES_MAX = 10080;

export const TITLE_MAX = 60;
export const CRITERION_MAX = 100;
export const CRITERIA_MIN_COUNT = 1;
export const CRITERIA_MAX_COUNT = 5;
export const BLOCK_REASON_MAX = 60;

export class ValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'ValidationError';
  }
}

/// 기준 목록 한 개. 1~5개, 각 항목은 공백을 뺀 1~100자 문자열이어야 한다.
export function validateCriteriaList(value: unknown, label: string): string[] {
  if (!Array.isArray(value)) {
    throw new ValidationError(`${label}이(가) 배열이 아닙니다.`);
  }
  if (value.length < CRITERIA_MIN_COUNT || value.length > CRITERIA_MAX_COUNT) {
    throw new ValidationError(`${label}은(는) ${CRITERIA_MIN_COUNT}~${CRITERIA_MAX_COUNT}개여야 합니다.`);
  }
  return value.map((item) => {
    if (typeof item !== 'string') {
      throw new ValidationError(`${label} 항목이 문자열이 아닙니다.`);
    }
    const trimmed = item.trim();
    if (trimmed.length === 0) {
      throw new ValidationError(`${label}에 빈 항목이 있습니다.`);
    }
    if (trimmed.length > CRITERION_MAX) {
      throw new ValidationError(`${label} 항목이 ${CRITERION_MAX}자를 넘습니다.`);
    }
    return trimmed;
  });
}

export interface CriteriaRequest {
  action: 'generate' | 'check';
  title: string;
  type: BattleType;
  durationMinutes: number;
  minCriteria?: string[];
  superiorityCriteria?: string[] | null;
  battleId?: string | null;
}

/// 클라이언트 요청 검증. 여기서 걸리면 Gemini를 부르지 않는다(한도도 쓰지 않는다).
export function parseCriteriaRequest(body: unknown): CriteriaRequest {
  if (typeof body !== 'object' || body === null) {
    throw new ValidationError('요청 본문이 올바르지 않습니다.');
  }
  const raw = body as Record<string, unknown>;

  const action = raw.action;
  if (action !== 'generate' && action !== 'check') {
    throw new ValidationError('action은 generate 또는 check여야 합니다.');
  }

  const title = typeof raw.title === 'string' ? raw.title.trim() : '';
  if (title.length === 0 || title.length > TITLE_MAX) {
    throw new ValidationError(`제목은 1~${TITLE_MAX}자여야 합니다.`);
  }

  const type = raw.type;
  if (type !== 'speed' && type !== 'quality') {
    throw new ValidationError('type은 speed 또는 quality여야 합니다.');
  }

  const durationMinutes = raw.duration_minutes;
  if (
    typeof durationMinutes !== 'number' ||
    !Number.isInteger(durationMinutes) ||
    durationMinutes < DURATION_MINUTES_MIN ||
    durationMinutes > DURATION_MINUTES_MAX
  ) {
    throw new ValidationError(
      `duration_minutes는 ${DURATION_MINUTES_MIN}~${DURATION_MINUTES_MAX} 사이의 정수여야 합니다.`,
    );
  }

  const battleId = typeof raw.battle_id === 'string' ? raw.battle_id : null;

  if (action === 'generate') {
    return { action, title, type, durationMinutes, battleId };
  }

  // 재검사: 사용자가 고친 목록을 그대로 받아 검사한다.
  const minCriteria = validateCriteriaList(raw.min_criteria, '최소 기준');
  let superiorityCriteria: string[] | null = null;
  if (type === 'quality') {
    superiorityCriteria = validateCriteriaList(raw.superiority_criteria, '우열 기준');
  } else if (raw.superiority_criteria !== undefined && raw.superiority_criteria !== null) {
    throw new ValidationError('속도전에는 우열 기준이 없습니다.');
  }

  return { action, title, type, durationMinutes, minCriteria, superiorityCriteria, battleId };
}

/// ① 기준 생성 응답 스키마.
export const generationResponseSchema = {
  type: 'object',
  properties: {
    provable: { type: 'boolean' },
    block_reason: { type: 'string', nullable: true },
    min_criteria: { type: 'array', items: { type: 'string' } },
    superiority_criteria: { type: 'array', items: { type: 'string' }, nullable: true },
  },
  required: ['provable', 'min_criteria'],
};

/// ② 증명 가능성 검사 응답 스키마.
export const checkResponseSchema = {
  type: 'object',
  properties: {
    provable: { type: 'boolean' },
    block_reason: { type: 'string', nullable: true },
  },
  required: ['provable'],
};

export interface GenerationResult {
  provable: boolean;
  blockReason: string | null;
  minCriteria: string[];
  superiorityCriteria: string[] | null;
}

function parseBlockReason(value: unknown): string {
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new ValidationError('차단 사유가 없습니다.');
  }
  const trimmed = value.trim();
  if (trimmed.length > BLOCK_REASON_MAX) {
    throw new ValidationError(`차단 사유가 ${BLOCK_REASON_MAX}자를 넘습니다.`);
  }
  return trimmed;
}

/// 기준 생성 응답 재검증. 유형과 우열 기준 유무가 어긋나면 AI 실패로 처리한다.
export function parseGenerationResponse(value: unknown, type: BattleType): GenerationResult {
  if (typeof value !== 'object' || value === null) {
    throw new ValidationError('응답이 객체가 아닙니다.');
  }
  const raw = value as Record<string, unknown>;
  if (typeof raw.provable !== 'boolean') {
    throw new ValidationError('provable이 없습니다.');
  }

  if (!raw.provable) {
    // 차단이면 두 목록은 비어 있고 사유만 온다.
    return {
      provable: false,
      blockReason: parseBlockReason(raw.block_reason),
      minCriteria: [],
      superiorityCriteria: null,
    };
  }

  const minCriteria = validateCriteriaList(raw.min_criteria, '최소 기준');
  let superiorityCriteria: string[] | null = null;
  if (type === 'quality') {
    superiorityCriteria = validateCriteriaList(raw.superiority_criteria, '우열 기준');
  } else if (raw.superiority_criteria !== undefined && raw.superiority_criteria !== null) {
    throw new ValidationError('속도전 응답에 우열 기준이 들어 있습니다.');
  }

  return { provable: true, blockReason: null, minCriteria, superiorityCriteria };
}

export interface CheckResult {
  provable: boolean;
  blockReason: string | null;
}

export const REASON_MAX = 60;

const UUID_PATTERN = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

export interface SubmitEvidenceRequest {
  battleId: string;
  objectPath: string;
  /// 앱이 보낸 촬영 시각. 서버 대조에만 쓰고 AI로는 보내지 않는다(결정 69).
  capturedAt: string;
}

/// 증거 제출 요청 검증. 경로는 JWT로 확인한 호출자의 폴더여야 한다
/// (클라이언트가 보낸 user id를 믿지 않으므로 [userId]는 호출부가 JWT에서 꺼내 넘긴다).
export function parseSubmitEvidenceRequest(body: unknown, userId: string): SubmitEvidenceRequest {
  if (typeof body !== 'object' || body === null) {
    throw new ValidationError('요청 본문이 올바르지 않습니다.');
  }
  const raw = body as Record<string, unknown>;

  const battleId = typeof raw.battle_id === 'string' ? raw.battle_id.trim() : '';
  if (!UUID_PATTERN.test(battleId)) {
    throw new ValidationError('battle_id가 올바르지 않습니다.');
  }

  const objectPath = typeof raw.object_path === 'string' ? raw.object_path.trim() : '';
  if (!objectPath.startsWith(`${battleId}/${userId}/`) || objectPath.length <= `${battleId}/${userId}/`.length) {
    throw new ValidationError('사진 경로가 본인 폴더가 아닙니다.');
  }

  const capturedAt = typeof raw.captured_at === 'string' ? raw.captured_at.trim() : '';
  if (capturedAt.length === 0 || Number.isNaN(Date.parse(capturedAt))) {
    throw new ValidationError('촬영 시각이 올바르지 않습니다.');
  }

  return { battleId, objectPath, capturedAt };
}

/// ③ 최소 기준 재판정 응답 스키마(두 유형 공통).
export const minCriteriaVerdictResponseSchema = {
  type: 'object',
  properties: {
    passed: { type: 'boolean' },
    reason: { type: 'string' },
  },
  required: ['passed', 'reason'],
};

export interface MinCriteriaVerdictResult {
  passed: boolean;
  reason: string;
}

/// 최소 기준 재판정 응답 재검증. 사유가 없거나 60자를 넘으면 AI 실패로 처리한다
/// (잘라 쓰지 않는다 — 잘린 사유가 오해를 부른다).
export function parseMinCriteriaVerdictResponse(value: unknown): MinCriteriaVerdictResult {
  if (typeof value !== 'object' || value === null) {
    throw new ValidationError('응답이 객체가 아닙니다.');
  }
  const raw = value as Record<string, unknown>;
  if (typeof raw.passed !== 'boolean') {
    throw new ValidationError('passed가 없습니다.');
  }
  if (typeof raw.reason !== 'string' || raw.reason.trim().length === 0) {
    throw new ValidationError('판정 사유가 없습니다.');
  }
  const reason = raw.reason.trim();
  if (reason.length > REASON_MAX) {
    throw new ValidationError(`판정 사유가 ${REASON_MAX}자를 넘습니다.`);
  }
  return { passed: raw.passed, reason };
}

/// ④ 품질전 우열 재판정 응답 스키마.
///
/// a/b는 **보낸 사진의 순서**일 뿐 참가자가 아니다. 순서는 매 시도마다 섞이고,
/// 응답을 참가자로 되돌리는 일은 [mapSuperiorityWinnerToParticipant]가 한다.
export const superiorityVerdictResponseSchema = {
  type: 'object',
  properties: {
    winner: { type: 'string', enum: ['a', 'b'] },
    winner_reason: { type: 'string' },
  },
  required: ['winner', 'winner_reason'],
};

export interface SuperiorityVerdictResult {
  /// 사진 순서 기준의 승자.
  winner: 'a' | 'b';
  /// 우열 기준에 근거한 한 줄 사유.
  winnerReason: string;
}

/// 우열 재판정 응답 재검증.
///
/// **승자가 없거나 a/b가 아니면 실패로 본다**(동점이 없다는 규칙을 서버가 강제한다). 실패는 재시도 대상이며,
/// 마지막 시도까지 실패하면 대결이 무효가 된다. 승자만 있고 근거가 없어도 실패다(사유 없이 -3점을 줄 수 없다).
export function parseSuperiorityVerdictResponse(value: unknown): SuperiorityVerdictResult {
  if (typeof value !== 'object' || value === null) {
    throw new ValidationError('응답이 객체가 아닙니다.');
  }
  const raw = value as Record<string, unknown>;
  if (raw.winner !== 'a' && raw.winner !== 'b') {
    throw new ValidationError('승자가 없습니다.');
  }
  if (typeof raw.winner_reason !== 'string' || raw.winner_reason.trim().length === 0) {
    throw new ValidationError('승패 사유가 없습니다.');
  }
  const winnerReason = raw.winner_reason.trim();
  if (winnerReason.length > REASON_MAX) {
    throw new ValidationError(`승패 사유가 ${REASON_MAX}자를 넘습니다.`);
  }
  return { winner: raw.winner, winnerReason };
}

/// 사진 순서(a/b)로 온 승자를 참가자(생성자/참가자)로 되돌린다.
///
/// [flipped]가 true이면 A 자리에 참가자 사진을, B 자리에 생성자 사진을 보낸 것이다.
/// 위치 편향(앞에 온 사진을 더 좋게 보는 경향)을 줄이려고 매 시도마다 순서를 섞기 때문에,
/// 이 되돌리기가 틀리면 승패가 통째로 뒤집힌다.
export function mapSuperiorityWinnerToParticipant(
  winner: 'a' | 'b',
  flipped: boolean,
): 'creator' | 'opponent' {
  if (winner === 'a') return flipped ? 'opponent' : 'creator';
  return flipped ? 'creator' : 'opponent';
}

export interface JudgeDisputeRequest {
  jobId: number;
}

/// cron(pg_net)이 보내는 재판정 요청. 잡 id 하나뿐이다
/// (기준·사진 경로는 요청 값이 아니라 DB에서 읽는다).
export function parseJudgeDisputeRequest(body: unknown): JudgeDisputeRequest {
  if (typeof body !== 'object' || body === null) {
    throw new ValidationError('요청 본문이 올바르지 않습니다.');
  }
  const raw = body as Record<string, unknown>;
  const jobId = raw.job_id;
  if (typeof jobId !== 'number' || !Number.isSafeInteger(jobId) || jobId <= 0) {
    throw new ValidationError('job_id가 올바르지 않습니다.');
  }
  return { jobId };
}

/// 증명 가능성 검사 응답 재검증.
export function parseCheckResponse(value: unknown): CheckResult {
  if (typeof value !== 'object' || value === null) {
    throw new ValidationError('응답이 객체가 아닙니다.');
  }
  const raw = value as Record<string, unknown>;
  if (typeof raw.provable !== 'boolean') {
    throw new ValidationError('provable이 없습니다.');
  }
  if (raw.provable) {
    return { provable: true, blockReason: null };
  }
  return { provable: false, blockReason: parseBlockReason(raw.block_reason) };
}
