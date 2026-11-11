// deno test supabase/functions/_shared/
// 판정 기준 캐시(criteria-cache)의 순수 함수 테스트. Gemini도 DB도 부르지 않는다.
//
// 여기서 고정하는 수용 기준(spec "## 수용 기준"):
//   - 유형이 다른 기준은 재사용되지 않는다
//   - 지금의 프롬프트 버전·모델이 아닌 기준은 재사용되지 않는다
//   - 임베딩 모델이 바뀌기 전의 벡터와 비교하지 않는다(키 차원에서)
//   - 캐시 적중은 하루 10회를 소모하지 않고, 미적중·다시 만들기는 1회만 쓴다
//   - 제목 정규화(공백·대소문자)가 유닛 테스트된다
//   - 임계값이 서버가 가진 값 하나다

import { assertAlmostEquals, assertEquals, assertThrows } from 'https://deno.land/std@0.224.0/assert/mod.ts';

import {
  CACHE_BLOCKED_DECISIONS,
  CRITERIA_CACHE_MIN_SIMILARITY,
  aiModelKey,
  cosineSimilarity,
  decideCriteriaSource,
  embeddingModelKey,
  l2Normalize,
  limitCostOf,
  normalizeTitle,
  parseCacheHit,
  toVectorLiteral,
} from './criteria_cache.ts';
import { ValidationError } from './schemas.ts';

const expectation = {
  type: 'speed' as const,
  aiModel: 'gemini-2.5-flash/p1',
  embeddingModel: 'gemini-embedding-001/SEMANTIC_SIMILARITY/768',
  minSimilarity: 0.9,
  includeBlocked: false,
};

function speedRow(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    cache_id: '11111111-2222-3333-4444-555555555555',
    type: 'speed',
    provable: true,
    min_criteria: ['운동화를 신은 발이 실외 바닥에 보인다'],
    superiority_criteria: null,
    ai_model: expectation.aiModel,
    embedding_model: expectation.embeddingModel,
    similarity: 0.97,
    matched_by: 'vector',
    ...overrides,
  };
}

Deno.test('제목 정규화는 공백류를 접고 소문자로 만든다', () => {
  assertEquals(normalizeTitle('  아침   운동  '), '아침 운동');
  assertEquals(normalizeTitle('아침\t운동\n하기'), '아침 운동 하기');
  // 전각 공백(U+3000)도 같은 한 칸으로 접는다.
  assertEquals(normalizeTitle('아침　운동'), '아침 운동');
  assertEquals(normalizeTitle('Morning Run'), 'morning run');
  assertEquals(normalizeTitle('MORNING   RUN '), 'morning run');
  // NFD로 쓴 한글(조합형)과 NFC로 쓴 한글이 같은 키가 된다.
  assertEquals(normalizeTitle('가'), '가');
  // 60자 경계는 그대로 지난다(길이 제한은 parseCriteriaRequest가 본다).
  assertEquals(normalizeTitle('가'.repeat(60)).length, 60);
  // **소문자화로 길이가 늘어나는 문자**('İ' 한 자 -> 'i̇' 두 자)가 있다. 60자로 잘라서
  // criteria_cache.title_norm(1~60자) 제약을 넘지 않게 한다 - 넘으면 그 제목만 적재가 깨진다.
  const growing = 'İ'.repeat(60);
  assertEquals(growing.toLowerCase().length > 60, true);
  assertEquals(normalizeTitle(growing).length, 60);
  // 같은 입력은 언제나 같은 키로 잘린다(조회와 적재가 같은 값을 본다).
  assertEquals(normalizeTitle(growing), normalizeTitle(growing));
});

Deno.test('모델 키는 한 조각만 달라도 달라진다', () => {
  assertEquals(aiModelKey('gemini-2.5-flash', 'p1'), 'gemini-2.5-flash/p1');
  // 프롬프트를 고치면(p1 -> p2) 옛 캐시가 조회 대상에서 빠진다.
  assertEquals(aiModelKey('gemini-2.5-flash', 'p1') === aiModelKey('gemini-2.5-flash', 'p2'), false);
  assertEquals(aiModelKey('gemini-2.5-flash', 'p1') === aiModelKey('gemini-3-flash', 'p1'), false);

  const key = embeddingModelKey('gemini-embedding-001', 'SEMANTIC_SIMILARITY', 768);
  assertEquals(key, 'gemini-embedding-001/SEMANTIC_SIMILARITY/768');
  // 모델·작업유형·차원이 모두 벡터 공간을 바꾸므로 셋 중 하나만 달라도 다른 키다.
  assertEquals(key === embeddingModelKey('gemini-embedding-2', 'SEMANTIC_SIMILARITY', 768), false);
  assertEquals(key === embeddingModelKey('gemini-embedding-001', 'RETRIEVAL_QUERY', 768), false);
  assertEquals(key === embeddingModelKey('gemini-embedding-001', 'SEMANTIC_SIMILARITY', 1536), false);
});

Deno.test('L2 정규화는 길이를 1로 만들고 0 벡터를 거부한다', () => {
  const unit = l2Normalize([3, 4]);
  assertAlmostEquals(unit[0], 0.6, 1e-12);
  assertAlmostEquals(unit[1], 0.8, 1e-12);
  // 이미 정규화된 벡터를 다시 정규화해도 같다(어느 쪽이든 안전한 쪽을 고정한 근거).
  const again = l2Normalize(unit);
  assertAlmostEquals(again[0], unit[0], 1e-12);
  assertAlmostEquals(again[1], unit[1], 1e-12);

  assertThrows(() => l2Normalize([]), ValidationError);
  assertThrows(() => l2Normalize([0, 0, 0]), ValidationError);
  assertThrows(() => l2Normalize([1, Number.NaN]), ValidationError);
});

Deno.test('벡터 리터럴은 차원이 맞을 때만 만들어진다', () => {
  const values = new Array(768).fill(0);
  values[0] = 1;
  const literal = toVectorLiteral(values, 768);
  assertEquals(literal.startsWith('[1,0,0'), true);
  assertEquals(literal.endsWith('0]'), true);

  // 코드 상수와 DB 컬럼 vector(768)이 어긋나면 적재가 조용히 깨진다. 여기서 먼저 막는다.
  assertThrows(() => toVectorLiteral(values, 1536), ValidationError);
  assertThrows(() => toVectorLiteral([1, 2, Number.POSITIVE_INFINITY], 3), ValidationError);
  assertThrows(() => toVectorLiteral([1, Number.NaN, 3], 3), ValidationError);
});

Deno.test('코사인 유사도는 같은 벡터 1, 직교 0, 반대 -1', () => {
  assertAlmostEquals(cosineSimilarity([1, 0], [1, 0]), 1, 1e-12);
  assertAlmostEquals(cosineSimilarity([1, 0], [0, 1]), 0, 1e-12);
  assertAlmostEquals(cosineSimilarity([1, 0], [-1, 0]), -1, 1e-12);
  // 길이가 달라도 방향이 같으면 1이다(정규화 전 벡터로도 측정할 수 있다).
  assertAlmostEquals(cosineSimilarity([2, 0], [5, 0]), 1, 1e-12);
  assertThrows(() => cosineSimilarity([1, 0], [1, 0, 0]), ValidationError);
  assertThrows(() => cosineSimilarity([], []), ValidationError);
});

Deno.test('정상 행은 통과하고 원 제목·원 사유는 들어오지 않는다', () => {
  const hit = parseCacheHit(speedRow(), expectation);
  assertEquals(hit.cacheId, '11111111-2222-3333-4444-555555555555');
  assertEquals(hit.provable, true);
  assertEquals(hit.minCriteria.length, 1);
  assertEquals(hit.superiorityCriteria, null);
  assertEquals(hit.matchedBy, 'vector');
  // CacheHit에는 제목·차단 사유를 담는 칸이 없다(조회 함수도 돌려주지 않는다).
  assertEquals(Object.keys(hit).includes('titleNorm'), false);
  assertEquals(Object.keys(hit).includes('blockReason'), false);
});

Deno.test('유형이 다른 캐시 행은 재사용되지 않는다', () => {
  assertThrows(() => parseCacheHit(speedRow({ type: 'quality' }), expectation), ValidationError);
  // 품질전 요청에 우열 기준이 없는 행도 거부한다(증서 제약에서 깨지기 전에 막는다).
  assertThrows(
    () =>
      parseCacheHit(
        speedRow({ type: 'quality', superiority_criteria: null }),
        { ...expectation, type: 'quality' },
      ),
    ValidationError,
  );
  // 속도전 요청에 우열 기준이 딸려 오는 행도 거부한다.
  assertThrows(
    () => parseCacheHit(speedRow({ superiority_criteria: ['더 깨끗하다'] }), expectation),
    ValidationError,
  );

  const quality = parseCacheHit(
    speedRow({ type: 'quality', superiority_criteria: ['먼지가 없다'] }),
    { ...expectation, type: 'quality' },
  );
  assertEquals(quality.superiorityCriteria, ['먼지가 없다']);
});

Deno.test('프롬프트·모델 버전이 다른 캐시 행은 재사용되지 않는다', () => {
  assertThrows(
    () => parseCacheHit(speedRow({ ai_model: 'gemini-2.5-flash/p2' }), expectation),
    ValidationError,
  );
  assertThrows(
    () => parseCacheHit(speedRow({ ai_model: 'gemini-3-flash/p1' }), expectation),
    ValidationError,
  );
  // 임베딩 모델이 바뀌기 전의 벡터와는 비교하지 않는다.
  assertThrows(
    () =>
      parseCacheHit(
        speedRow({ embedding_model: 'gemini-embedding-2/SEMANTIC_SIMILARITY/768' }),
        expectation,
      ),
    ValidationError,
  );
});

Deno.test('임계값보다 낮은 유사도와 모양이 깨진 행은 거부한다', () => {
  assertThrows(() => parseCacheHit(speedRow({ similarity: 0.89 }), expectation), ValidationError);
  // 임계값과 같으면 통과한다(경계는 포함).
  assertEquals(parseCacheHit(speedRow({ similarity: 0.9 }), expectation).similarity, 0.9);

  assertThrows(() => parseCacheHit(null, expectation), ValidationError);
  assertThrows(() => parseCacheHit(speedRow({ cache_id: null }), expectation), ValidationError);
  assertThrows(() => parseCacheHit(speedRow({ provable: 'yes' }), expectation), ValidationError);
  assertThrows(() => parseCacheHit(speedRow({ matched_by: 'guess' }), expectation), ValidationError);
  assertThrows(() => parseCacheHit(speedRow({ similarity: null }), expectation), ValidationError);
  assertThrows(() => parseCacheHit(speedRow({ min_criteria: [] }), expectation), ValidationError);
  assertThrows(() => parseCacheHit(speedRow({ min_criteria: [''] }), expectation), ValidationError);
  assertThrows(() => parseCacheHit(speedRow({ min_criteria: 'bad' }), expectation), ValidationError);
});

Deno.test('차단 판단은 허용했을 때만 재사용된다(P1 스위치)', () => {
  const blocked = speedRow({ provable: false, min_criteria: [], superiority_criteria: null });

  // P0 상태(CACHE_BLOCKED_DECISIONS = false로 되돌린 경우)에서는 차단 행이 거부된다.
  assertThrows(
    () => parseCacheHit(blocked, { ...expectation, includeBlocked: false }),
    ValidationError,
  );

  const hit = parseCacheHit(blocked, { ...expectation, includeBlocked: true });
  assertEquals(hit.provable, false);
  // 차단 행은 두 목록이 비어 있다(사유는 애초에 전달되지 않는다 - 고정 문장을 서버가 쓴다).
  assertEquals(hit.minCriteria, []);
  assertEquals(hit.superiorityCriteria, null);
  // 차단 적중도 한도를 쓰지 않는다.
  assertEquals(limitCostOf(decideCriteriaSource({ skipCache: false, hit })), 0);
});

Deno.test('적중은 한도 0회, 미적중과 다시 만들기는 1회', () => {
  const hit = parseCacheHit(speedRow(), expectation);

  assertEquals(decideCriteriaSource({ skipCache: false, hit }), 'cache');
  assertEquals(limitCostOf('cache'), 0);

  assertEquals(decideCriteriaSource({ skipCache: false, hit: null }), 'generate');
  assertEquals(limitCostOf('generate'), 1);

  // `기준 다시 만들기`는 적중 후보가 있어도 AI에게 새로 묻고 1회를 쓴다(캐시의 탈출구).
  assertEquals(decideCriteriaSource({ skipCache: true, hit }), 'generate');
  assertEquals(limitCostOf(decideCriteriaSource({ skipCache: true, hit })), 1);
  assertEquals(decideCriteriaSource({ skipCache: true, hit: null }), 'generate');
});

Deno.test('임계값과 P1 스위치는 서버가 가진 값 하나다', () => {
  // 사용자가 조절하지 않고 화면에도 나오지 않는다. 값이 0과 1 사이여야 뜻이 있다.
  assertEquals(CRITERIA_CACHE_MIN_SIMILARITY > 0 && CRITERIA_CACHE_MIN_SIMILARITY < 1, true);
  // 측정 전 보수값. 측정 뒤 권장값으로 고치면 이 단정은 그대로 통과한다(범위만 본다).
  assertEquals(CRITERIA_CACHE_MIN_SIMILARITY >= 0.85, true);
  assertEquals(typeof CACHE_BLOCKED_DECISIONS, 'boolean');
});
