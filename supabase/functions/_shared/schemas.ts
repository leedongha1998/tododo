// 요청 입력 검증과 Gemini 응답 재검증.
//
// Gemini의 responseSchema 강제를 믿지 않고 서버에서 한 번 더 본다. 검증에 실패하면 AI 실패로 취급한다
// (스키마 밖 필드·초과 길이를 잘라 쓰지 않는다 — 잘린 기준·사유가 오해를 부른다).

export const BATTLE_TYPES = ['speed', 'quality'] as const;
export type BattleType = (typeof BATTLE_TYPES)[number];

export const DURATION_HOURS = [24, 72, 168] as const;

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
  durationHours: number;
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

  const durationHours = raw.duration_hours;
  if (typeof durationHours !== 'number' || !DURATION_HOURS.includes(durationHours as 24)) {
    throw new ValidationError('duration_hours는 24, 72, 168 중 하나여야 합니다.');
  }

  const battleId = typeof raw.battle_id === 'string' ? raw.battle_id : null;

  if (action === 'generate') {
    return { action, title, type, durationHours, battleId };
  }

  // 재검사: 사용자가 고친 목록을 그대로 받아 검사한다.
  const minCriteria = validateCriteriaList(raw.min_criteria, '최소 기준');
  let superiorityCriteria: string[] | null = null;
  if (type === 'quality') {
    superiorityCriteria = validateCriteriaList(raw.superiority_criteria, '우열 기준');
  } else if (raw.superiority_criteria !== undefined && raw.superiority_criteria !== null) {
    throw new ValidationError('속도전에는 우열 기준이 없습니다.');
  }

  return { action, title, type, durationHours, minCriteria, superiorityCriteria, battleId };
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
