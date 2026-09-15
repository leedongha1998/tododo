// deno test supabase/functions/_shared/
// Gemini를 부르지 않는 순수 검증 함수 테스트.

import { assertEquals, assertThrows } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  ValidationError,
  parseCheckResponse,
  parseCriteriaRequest,
  parseGenerationResponse,
  validateCriteriaList,
} from './schemas.ts';

Deno.test('기준 목록은 1~5개, 각 항목 1~100자여야 한다', () => {
  assertEquals(validateCriteriaList([' 책상이 비어 있다 '], '최소 기준'), ['책상이 비어 있다']);

  assertThrows(() => validateCriteriaList([], '최소 기준'), ValidationError);
  assertThrows(() => validateCriteriaList(['a', 'b', 'c', 'd', 'e', 'f'], '최소 기준'), ValidationError);
  assertThrows(() => validateCriteriaList(['   '], '최소 기준'), ValidationError);
  assertThrows(() => validateCriteriaList(['가'.repeat(101)], '최소 기준'), ValidationError);
  assertThrows(() => validateCriteriaList([1], '최소 기준'), ValidationError);
  assertThrows(() => validateCriteriaList('목록', '최소 기준'), ValidationError);
});

Deno.test('생성 요청은 제목·유형·기간을 검증한다', () => {
  const request = parseCriteriaRequest({
    action: 'generate',
    title: ' 방 청소하기 ',
    type: 'quality',
    duration_hours: 72,
  });
  assertEquals(request.title, '방 청소하기');
  assertEquals(request.type, 'quality');
  assertEquals(request.durationHours, 72);

  assertThrows(() => parseCriteriaRequest({ action: 'nope', title: 'a', type: 'speed', duration_hours: 24 }));
  assertThrows(() => parseCriteriaRequest({ action: 'generate', title: '', type: 'speed', duration_hours: 24 }));
  assertThrows(
    () => parseCriteriaRequest({ action: 'generate', title: '가'.repeat(61), type: 'speed', duration_hours: 24 }),
  );
  assertThrows(() => parseCriteriaRequest({ action: 'generate', title: 'a', type: 'both', duration_hours: 24 }));
  assertThrows(() => parseCriteriaRequest({ action: 'generate', title: 'a', type: 'speed', duration_hours: 5 }));
});

Deno.test('재검사 요청은 품질전에서만 우열 기준을 받는다', () => {
  const quality = parseCriteriaRequest({
    action: 'check',
    title: '방 청소하기',
    type: 'quality',
    duration_hours: 24,
    min_criteria: ['바닥이 보인다'],
    superiority_criteria: ['먼지가 없다'],
  });
  assertEquals(quality.minCriteria, ['바닥이 보인다']);
  assertEquals(quality.superiorityCriteria, ['먼지가 없다']);

  const speed = parseCriteriaRequest({
    action: 'check',
    title: '방 청소하기',
    type: 'speed',
    duration_hours: 24,
    min_criteria: ['바닥이 보인다'],
  });
  assertEquals(speed.superiorityCriteria, null);

  // 품질전인데 우열 기준이 없으면 거부한다.
  assertThrows(() =>
    parseCriteriaRequest({
      action: 'check',
      title: '방 청소하기',
      type: 'quality',
      duration_hours: 24,
      min_criteria: ['바닥이 보인다'],
    })
  );
  // 속도전에는 우열 기준이 없다.
  assertThrows(() =>
    parseCriteriaRequest({
      action: 'check',
      title: '방 청소하기',
      type: 'speed',
      duration_hours: 24,
      min_criteria: ['바닥이 보인다'],
      superiority_criteria: ['먼지가 없다'],
    })
  );
});

Deno.test('생성 응답: 품질전은 두 목록, 속도전은 최소 기준만', () => {
  const quality = parseGenerationResponse({
    provable: true,
    min_criteria: ['바닥이 보인다'],
    superiority_criteria: ['먼지가 없다', '물건이 각 잡혀 있다'],
  }, 'quality');
  assertEquals(quality.minCriteria.length, 1);
  assertEquals(quality.superiorityCriteria?.length, 2);

  const speed = parseGenerationResponse({
    provable: true,
    min_criteria: ['바닥이 보인다'],
    superiority_criteria: null,
  }, 'speed');
  assertEquals(speed.superiorityCriteria, null);

  // 유형과 우열 기준 유무가 어긋나면 AI 실패로 본다.
  assertThrows(
    () => parseGenerationResponse({ provable: true, min_criteria: ['a'] }, 'quality'),
    ValidationError,
  );
  assertThrows(
    () => parseGenerationResponse({ provable: true, min_criteria: ['a'], superiority_criteria: ['b'] }, 'speed'),
    ValidationError,
  );
});

Deno.test('차단 응답은 사유가 있어야 하고 기준 목록은 비워 둔다', () => {
  const blocked = parseGenerationResponse({
    provable: false,
    block_reason: '사진으로 확인할 수 없는 미션이에요',
    min_criteria: [],
  }, 'quality');
  assertEquals(blocked.provable, false);
  assertEquals(blocked.minCriteria, []);
  assertEquals(blocked.superiorityCriteria, null);

  // 사유가 없거나 너무 길면 실패로 본다.
  assertThrows(() => parseGenerationResponse({ provable: false, min_criteria: [] }, 'speed'), ValidationError);
  assertThrows(
    () => parseGenerationResponse({ provable: false, block_reason: '가'.repeat(61), min_criteria: [] }, 'speed'),
    ValidationError,
  );
});

Deno.test('검사 응답은 provable과 사유만 본다', () => {
  assertEquals(parseCheckResponse({ provable: true, block_reason: null }), {
    provable: true,
    blockReason: null,
  });
  assertEquals(parseCheckResponse({ provable: false, block_reason: '시간 경과는 사진으로 못 봐요' }), {
    provable: false,
    blockReason: '시간 경과는 사진으로 못 봐요',
  });

  assertThrows(() => parseCheckResponse({ provable: false }), ValidationError);
  assertThrows(() => parseCheckResponse({}), ValidationError);
  assertThrows(() => parseCheckResponse(null), ValidationError);
});
