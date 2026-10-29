// deno test supabase/functions/_shared/
// judge-dispute의 유일한 관문인 비밀값 비교(Gemini 호출 없음).

import { assert, assertFalse } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { constantTimeEquals } from './secret.ts';

Deno.test('같은 값만 통과한다', () => {
  assert(constantTimeEquals('s3cr3t-value', 's3cr3t-value'));
  assertFalse(constantTimeEquals('s3cr3t-value', 's3cr3t-valuE'));
  // 앞부분이 같아도, 길이만 달라도 통과하지 않는다.
  assertFalse(constantTimeEquals('s3cr3t-value', 's3cr3t'));
  assertFalse(constantTimeEquals('s3cr3t', 's3cr3t-value'));
});

Deno.test('빈 값은 어떤 경우에도 통과하지 않는다', () => {
  // 시크릿이 설정되지 않은 상태에서 빈 헤더가 통과하면 함수가 통째로 열린다.
  assertFalse(constantTimeEquals('', ''));
  assertFalse(constantTimeEquals('s3cr3t', ''));
  assertFalse(constantTimeEquals('', 's3cr3t'));
});
