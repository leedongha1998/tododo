// 판정 기준 캐시(criteria-cache)의 순수 함수들.
//
// 근거: docs/specs/criteria-cache/{spec,design,plan}.md.
//
// **이 파일은 전부 순수하다** - Gemini를 부르지 않고 DB를 보지 않으며 Deno.env도 읽지 않는다
// (환경에서 오는 값은 전부 인자로 받는다). 그래서 `deno test supabase/functions/_shared/`가
// 그대로 돈다. 캐시 적중 판단에서 자동 테스트가 닿을 수 있는 자리를 전부 여기로 모았다.
//
// 여기에 없는 것: 벡터 검색 그 자체(SQL의 `<=>`와 order by), RLS·권한, 원장 불간섭.
// 로컬 Docker가 없어 SQL은 자동 테스트 밖이고, supabase/tests/criteria_cache_smoke.sql과
// docs/manual-test-plan.md 3-8~3-15가 그 자리를 본다(design 9.3).

import { BattleType, TITLE_MAX, ValidationError } from './schemas.ts';

/// 정규화된 제목의 상한. DB 제약(criteria_cache.title_norm 1~60자)과 같은 값이어야 한다 -
/// 한쪽만 바뀌면 적재가 insert에서 깨진다. 요청 제목의 상한(TITLE_MAX)과 같은 수를 쓴다.
const TITLE_NORM_MAX = TITLE_MAX;

/// 유사도 임계값. **이 값이 사는 자리는 여기 하나다**(DB 컬럼도, 시크릿도, 사용자 설정도 아니다 -
/// design 원칙 7). 판정의 근거가 되는 품질 손잡이라 버전 관리되는 자리에 둔다.
///
/// 지금 값은 **측정하지 않은 보수값**이다. design 8장의 측정(tool/criteria_cache_threshold.ts)은
/// GEMINI_API_KEY가 필요해 구현 환경에서 돌리지 못했다(plan.md "## 임계값 결과표"). 측정하지 않은
/// 값은 높은 쪽으로 틀려야 한다 - 높아서 틀리면 손해가 AI 호출 1회이고, 낮아서 틀리면 **판정의
/// 근거가 틀어진다**(spec "의심스러우면 AI를 부른다"). 측정 뒤 권장값(= 그룹 B 최고 + 0.02)으로
/// 고치고 plan.md의 결과표를 함께 갱신한다.
export const CRITERIA_CACHE_MIN_SIMILARITY = 0.95;

/// 차단 판단(provable = false)을 캐시에서 쓰는가. P0는 false(통과 기준만), P1에서 true.
/// **이 상수 하나가 P1의 스위치다** - false로 되돌리면 차단 캐시는 적재만 되고 조회되지 않는다.
export const CACHE_BLOCKED_DECISIONS = true;

/// 캐시 조회에 쓰는 제목 정규화.
///
/// **증서·프롬프트에 들어가는 제목은 정규화하지 않는다** - 증서의 제목은 "내가 쓴 제목"이어야
/// 한다(spec 수용 기준). 이 값이 쓰이는 곳은 조회 키와 캐시 행의 title_norm뿐이다.
export function normalizeTitle(raw: string): string {
  return raw
    .normalize('NFC')
    // 전각 공백(U+3000)·탭·개행을 포함한 모든 공백류를 하나로 접는다.
    .replace(/\s+/gu, ' ')
    .trim()
    .toLowerCase()
    // **소문자화가 길이를 늘리는 문자가 있다**('İ' 한 자 -> 두 자). 입력은 60자까지인데
    // criteria_cache.title_norm은 60자까지라, 자르지 않으면 그 제목만 적재가 insert에서 깨진다
    // (피해는 "캐시에 안 들어감 + 로그 한 줄"이지만 막는 비용이 한 줄이다).
    // 조회 키로서도 안전하다 - 같은 입력은 언제나 같은 값으로 잘린다.
    .slice(0, TITLE_NORM_MAX);
}

/// 'gemini-2.5-flash/p1'. criteria_checks.ai_model과 같은 표기다.
export function aiModelKey(model: string, promptVersion: string): string {
  return `${model}/${promptVersion}`;
}

/// 'gemini-embedding-001/SEMANTIC_SIMILARITY/768'. 셋 중 하나만 달라도 벡터 공간이 다르다 -
/// 다른 공간의 벡터를 비교한 유사도는 아무 뜻이 없으므로 한 키로 묶는다.
export function embeddingModelKey(model: string, taskType: string, dim: number): string {
  return `${model}/${taskType}/${dim}`;
}

/// 벡터를 길이 1로 만든다. gemini-embedding-001은 3072가 아닌 차원을 정규화해 주지 않는다.
/// 이미 정규화된 벡터를 다시 정규화해도 결과가 같으므로 어느 쪽이든 안전한 쪽을 고정한다.
export function l2Normalize(values: number[]): number[] {
  if (values.length === 0) {
    throw new ValidationError('빈 벡터는 정규화할 수 없습니다.');
  }
  let sum = 0;
  for (const value of values) {
    if (!Number.isFinite(value)) {
      throw new ValidationError('벡터에 유한수가 아닌 값이 있습니다.');
    }
    sum += value * value;
  }
  const norm = Math.sqrt(sum);
  if (norm === 0) {
    throw new ValidationError('길이가 0인 벡터는 정규화할 수 없습니다.');
  }
  return values.map((value) => value / norm);
}

/// pgvector가 받는 '[0.1,-0.2,...]' 문자열. PostgREST가 JSON 배열을 vector로 바꿔 주는 동작에
/// 의존하지 않고 Edge가 직접 만든다(SQL이 한 번 캐스팅한다).
///
/// 길이를 **먼저** 검사하는 이유: 코드 상수(EMBEDDING_DIM)와 DB 컬럼(vector(768))이 어긋나면
/// 적재가 insert에서 깨지는데, 그 실패는 로그만 남는 자리라 조용히 사라진다.
export function toVectorLiteral(values: number[], dim: number): string {
  if (values.length !== dim) {
    throw new ValidationError(`벡터 차원이 ${dim}이 아닙니다(${values.length}).`);
  }
  for (const value of values) {
    if (!Number.isFinite(value)) {
      throw new ValidationError('벡터에 유한수가 아닌 값이 있습니다.');
    }
  }
  return `[${values.join(',')}]`;
}

/// 코사인 유사도. 임계값 측정 스크립트(tool/criteria_cache_threshold.ts)와 테스트가 쓴다.
/// 운영 조회의 유사도는 Postgres의 `<=>`가 계산한다 - 같은 정의다(정규화된 벡터의 내적).
export function cosineSimilarity(a: number[], b: number[]): number {
  if (a.length !== b.length) {
    throw new ValidationError('길이가 다른 벡터는 비교할 수 없습니다.');
  }
  if (a.length === 0) {
    throw new ValidationError('빈 벡터는 비교할 수 없습니다.');
  }
  let dot = 0;
  let normA = 0;
  let normB = 0;
  for (let i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  if (normA === 0 || normB === 0) {
    throw new ValidationError('길이가 0인 벡터는 비교할 수 없습니다.');
  }
  return dot / (Math.sqrt(normA) * Math.sqrt(normB));
}

export interface CacheHit {
  cacheId: string;
  type: BattleType;
  provable: boolean;
  minCriteria: string[];
  superiorityCriteria: string[] | null;
  aiModel: string;
  embeddingModel: string;
  similarity: number;
  matchedBy: 'title' | 'vector';
}

export interface CacheHitExpectation {
  type: BattleType;
  aiModel: string;
  embeddingModel: string;
  minSimilarity: number;
  includeBlocked: boolean;
}

function criteriaListOf(value: unknown, label: string): string[] {
  if (!Array.isArray(value)) {
    throw new ValidationError(`캐시 행의 ${label}이(가) 배열이 아닙니다.`);
  }
  return value.map((item) => {
    if (typeof item !== 'string' || item.trim().length === 0) {
      throw new ValidationError(`캐시 행의 ${label} 항목이 올바르지 않습니다.`);
    }
    return item;
  });
}

/// 조회 결과를 **Edge에서 한 번 더** 검증한다. SQL이 이미 걸렀지만 믿지 않는다
/// (schemas.ts가 Gemini의 responseSchema를 믿지 않는 것과 같은 태도).
///
/// 어긋나면 ValidationError를 던지고, 호출부는 그것을 **미적중**으로 처리한다(= 지금처럼 AI를
/// 부른다. 사용자에게는 아무 차이가 없다). spec 수용 기준의 "유형이 다르면 재사용되지 않는다",
/// "프롬프트·모델 버전이 다르면 재사용되지 않는다"를 유닛 테스트로 고정할 수 있는 자리가 여기다
/// (벡터 검색 자체는 자동 테스트가 닿지 않는다).
export function parseCacheHit(row: unknown, expected: CacheHitExpectation): CacheHit {
  if (typeof row !== 'object' || row === null) {
    throw new ValidationError('캐시 조회 결과가 객체가 아닙니다.');
  }
  const raw = row as Record<string, unknown>;

  const cacheId = typeof raw.cache_id === 'string' ? raw.cache_id : '';
  if (cacheId.length === 0) {
    throw new ValidationError('캐시 id가 없습니다.');
  }

  if (raw.type !== expected.type) {
    throw new ValidationError('캐시 행의 유형이 요청과 다릅니다.');
  }
  if (raw.ai_model !== expected.aiModel) {
    throw new ValidationError('캐시 행의 생성 모델·프롬프트 버전이 지금 것과 다릅니다.');
  }
  if (raw.embedding_model !== expected.embeddingModel) {
    throw new ValidationError('캐시 행의 임베딩 모델 키가 지금 것과 다릅니다.');
  }

  if (typeof raw.provable !== 'boolean') {
    throw new ValidationError('캐시 행에 provable이 없습니다.');
  }
  if (!raw.provable && !expected.includeBlocked) {
    throw new ValidationError('차단 판단은 지금 재사용하지 않습니다.');
  }

  const matchedBy = raw.matched_by;
  if (matchedBy !== 'title' && matchedBy !== 'vector') {
    throw new ValidationError('캐시 행의 matched_by가 올바르지 않습니다.');
  }

  const similarity = typeof raw.similarity === 'number' ? raw.similarity : Number.NaN;
  if (!Number.isFinite(similarity)) {
    throw new ValidationError('캐시 행에 유사도가 없습니다.');
  }
  if (similarity < expected.minSimilarity) {
    throw new ValidationError('유사도가 임계값보다 낮습니다.');
  }

  // 차단 행은 두 목록이 비어 있다(DB 제약도 그 모양이다). 통과 행만 모양을 강제한다.
  let minCriteria: string[] = [];
  let superiorityCriteria: string[] | null = null;
  if (raw.provable) {
    minCriteria = criteriaListOf(raw.min_criteria, '최소 기준');
    if (minCriteria.length === 0) {
      throw new ValidationError('캐시 행의 최소 기준이 비어 있습니다.');
    }
    if (expected.type === 'quality') {
      superiorityCriteria = criteriaListOf(raw.superiority_criteria, '우열 기준');
      if (superiorityCriteria.length === 0) {
        throw new ValidationError('품질전 캐시 행에 우열 기준이 없습니다.');
      }
    } else if (raw.superiority_criteria !== null && raw.superiority_criteria !== undefined) {
      throw new ValidationError('속도전 캐시 행에 우열 기준이 들어 있습니다.');
    }
  }

  return {
    cacheId,
    type: expected.type,
    provable: raw.provable,
    minCriteria,
    superiorityCriteria,
    aiModel: expected.aiModel,
    embeddingModel: expected.embeddingModel,
    similarity,
    matchedBy,
  };
}

/// 기준을 어디서 얻는가. 흐름의 분기를 값으로 만든 것이다.
export type CriteriaSource = 'cache' | 'generate';

export function decideCriteriaSource(
  input: { skipCache: boolean; hit: CacheHit | null },
): CriteriaSource {
  // `기준 다시 만들기`는 적중 후보가 있어도 AI에게 새로 묻는다 - 그래야 캐시가 기존 탈출구를
  // 무효화하지 않는다(spec P0 탈출구 절).
  if (input.skipCache) return 'generate';
  return input.hit === null ? 'generate' : 'cache';
}

/// 그 결정이 하루 10회 한도를 몇 번 쓰는가. 수용 기준의 숫자를 코드로 적은 것이다.
///   적중 0 / 미적중 1 / 다시 만들기 1 / 재검사 1(= generate가 아니라 check 경로, 지금과 같다)
///
/// 실제 소모는 `begin_criteria_call`을 부르는가와 1:1이다(design 원칙 3). 이 함수는 그 사실을
/// 테스트가 읽을 수 있는 자리에 적어 둔 것이고, 원장에 새 상태를 만들지 않는다.
export function limitCostOf(source: CriteriaSource): 0 | 1 {
  return source === 'cache' ? 0 : 1;
}
