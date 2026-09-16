// deno test supabase/functions/_shared/
// Gemini를 부르지 않는 순수 검증 함수 테스트.

import { assertEquals, assertThrows } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  ValidationError,
  mapQualityVerdictToParticipants,
  parseCheckResponse,
  parseCriteriaRequest,
  parseGenerationResponse,
  parseJudgeQualityRequest,
  parseQualityVerdictResponse,
  parseSpeedVerdictResponse,
  parseSubmitEvidenceRequest,
  validateCriteriaList,
} from './schemas.ts';

const battleId = '11111111-2222-3333-4444-555555555555';
const userId = '66666666-7777-8888-9999-000000000000';

Deno.test('증거 제출 요청은 본인 폴더 경로만 받는다', () => {
  const request = parseSubmitEvidenceRequest(
    {
      battle_id: battleId,
      object_path: `${battleId}/${userId}/photo.jpg`,
      captured_at: '2026-09-16T01:02:03.000Z',
    },
    userId,
  );
  assertEquals(request.battleId, battleId);
  assertEquals(request.capturedAt, '2026-09-16T01:02:03.000Z');

  // 남의 폴더, 다른 대결 폴더, 폴더만 있고 파일이 없는 경로는 모두 거부한다.
  const otherUser = '99999999-7777-8888-9999-000000000000';
  assertThrows(
    () =>
      parseSubmitEvidenceRequest(
        { battle_id: battleId, object_path: `${battleId}/${otherUser}/p.jpg`, captured_at: '2026-09-16T01:02:03Z' },
        userId,
      ),
    ValidationError,
  );
  assertThrows(
    () =>
      parseSubmitEvidenceRequest(
        { battle_id: battleId, object_path: `${battleId}/${userId}/`, captured_at: '2026-09-16T01:02:03Z' },
        userId,
      ),
    ValidationError,
  );
  assertThrows(
    () =>
      parseSubmitEvidenceRequest(
        { battle_id: 'not-a-uuid', object_path: `not-a-uuid/${userId}/p.jpg`, captured_at: '2026-09-16T01:02:03Z' },
        userId,
      ),
    ValidationError,
  );
  assertThrows(
    () =>
      parseSubmitEvidenceRequest(
        { battle_id: battleId, object_path: `${battleId}/${userId}/p.jpg`, captured_at: '어제' },
        userId,
      ),
    ValidationError,
  );
});

Deno.test('속도전 판정 응답은 합격 여부와 60자 이내 사유를 요구한다', () => {
  assertEquals(parseSpeedVerdictResponse({ passed: true, reason: ' 상판이 모두 보인다 ' }), {
    passed: true,
    reason: '상판이 모두 보인다',
  });

  assertThrows(() => parseSpeedVerdictResponse({ passed: 'yes', reason: '사유' }), ValidationError);
  assertThrows(() => parseSpeedVerdictResponse({ passed: false }), ValidationError);
  assertThrows(() => parseSpeedVerdictResponse({ passed: false, reason: '   ' }), ValidationError);
  assertThrows(
    () => parseSpeedVerdictResponse({ passed: false, reason: '가'.repeat(61) }),
    ValidationError,
  );
});

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

const bothPass = {
  a: { meets_criteria: true, reason: '상판이 모두 보인다' },
  b: { meets_criteria: true, reason: '상판이 보인다' },
  winner: 'a',
  winner_reason: '얼룩이 남지 않아 더 깨끗하다',
};

Deno.test('품질전 판정 응답은 사진별 1단계 결과와 2단계 승자를 함께 본다', () => {
  const result = parseQualityVerdictResponse(bothPass);
  assertEquals(result.a.meetsCriteria, true);
  assertEquals(result.b.reason, '상판이 보인다');
  assertEquals(result.winner, 'a');
  assertEquals(result.winnerReason, '얼룩이 남지 않아 더 깨끗하다');

  // 사진별 사유는 비거나 60자를 넘으면 실패로 본다(잘라 쓰지 않는다).
  assertThrows(
    () => parseQualityVerdictResponse({ ...bothPass, a: { meets_criteria: true, reason: '  ' } }),
    ValidationError,
  );
  assertThrows(
    () =>
      parseQualityVerdictResponse({
        ...bothPass,
        b: { meets_criteria: true, reason: '가'.repeat(61) },
      }),
    ValidationError,
  );
  assertThrows(() => parseQualityVerdictResponse({ a: bothPass.a }), ValidationError);
});

Deno.test('둘 다 기준을 충족했는데 승자가 없으면 실패로 처리한다', () => {
  // 동점이 없다는 규칙은 서버가 강제한다. 실패로 보면 자동 재시도가 걸린다.
  assertThrows(
    () => parseQualityVerdictResponse({ ...bothPass, winner: null, winner_reason: null }),
    ValidationError,
  );
  assertThrows(() => parseQualityVerdictResponse({ ...bothPass, winner: 'c' }), ValidationError);
  // 승자만 있고 근거가 없어도 실패다(사유 없이 -3점을 줄 수 없다).
  assertThrows(
    () => parseQualityVerdictResponse({ ...bothPass, winner_reason: '   ' }),
    ValidationError,
  );
});

Deno.test('한쪽이라도 미달이면 승자 값은 무시한다', () => {
  // 이때의 승패는 DB의 quality_outcome이 정한다(충족한 쪽 승, 둘 다 미달이면 무승부).
  const oneFails = parseQualityVerdictResponse({
    a: { meets_criteria: true, reason: '상판이 보인다' },
    b: { meets_criteria: false, reason: '물건이 그대로 있다' },
    winner: 'b',
    winner_reason: '엉뚱한 근거',
  });
  assertEquals(oneFails.winner, null);
  assertEquals(oneFails.winnerReason, null);

  const bothFail = parseQualityVerdictResponse({
    a: { meets_criteria: false, reason: '물건이 그대로 있다' },
    b: { meets_criteria: false, reason: '사진이 흐리다' },
  });
  assertEquals(bothFail.winner, null);
});

Deno.test('A/B 순서를 섞어 보내도 판정을 참가자로 되돌린다', () => {
  const result = parseQualityVerdictResponse(bothPass);

  // 섞지 않은 시도: A = 생성자.
  const straight = mapQualityVerdictToParticipants(result, false);
  assertEquals(straight.creator.reason, '상판이 모두 보인다');
  assertEquals(straight.opponent.reason, '상판이 보인다');
  assertEquals(straight.winner, 'creator');

  // 섞은 시도: A = 참가자. 되돌리기가 틀리면 승패가 통째로 뒤집힌다.
  const flipped = mapQualityVerdictToParticipants(result, true);
  assertEquals(flipped.creator.reason, '상판이 보인다');
  assertEquals(flipped.opponent.reason, '상판이 모두 보인다');
  assertEquals(flipped.winner, 'opponent');
  assertEquals(flipped.winnerReason, '얼룩이 남지 않아 더 깨끗하다');

  // 승자가 없으면 어느 순서로 보냈든 없다.
  const noWinner = mapQualityVerdictToParticipants(
    parseQualityVerdictResponse({
      a: { meets_criteria: false, reason: '물건이 그대로 있다' },
      b: { meets_criteria: false, reason: '사진이 흐리다' },
    }),
    true,
  );
  assertEquals(noWinner.winner, null);
});

Deno.test('판정 요청은 대결 id만 받는다', () => {
  assertEquals(parseJudgeQualityRequest({ battle_id: ` ${battleId} ` }).battleId, battleId);

  assertThrows(() => parseJudgeQualityRequest({ battle_id: 'b1' }), ValidationError);
  assertThrows(() => parseJudgeQualityRequest({}), ValidationError);
  assertThrows(() => parseJudgeQualityRequest(null), ValidationError);
});
