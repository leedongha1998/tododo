// deno test supabase/functions/_shared/
// FCM 요청 조립·응답 해석·자격 증명 파싱. **FCM도 Google OAuth도 부르지 않는다**
// (Gemini를 부르지 않는 기존 테스트와 같은 선).

import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  buildFcmMessage,
  classifyFcmResponse,
  errorStatusOf,
  parseServiceAccount,
  pemToDer,
} from './fcm.ts';

Deno.test('메시지는 notification + high 우선순위 + data 두 키로 조립된다', () => {
  const message = buildFcmMessage('device-token', '이겼어요!', '「방 청소」 · +3점', {
    battle_id: '3f2504e0-4f89-11d3-9a0c-0305e82c3301',
    kind: 'finished',
  });

  assertEquals(message, {
    message: {
      token: 'device-token',
      // notification이라야 앱이 종료돼 있어도 시스템이 그린다.
      notification: { title: '이겼어요!', body: '「방 청소」 · +3점' },
      // Doze에서 임박·종결 알림이 늦지 않게 한다.
      android: { priority: 'high' },
      data: { battle_id: '3f2504e0-4f89-11d3-9a0c-0305e82c3301', kind: 'finished' },
    },
  });
});

Deno.test('죽은 토큰만 지운다', () => {
  assertEquals(classifyFcmResponse(404, 'NOT_FOUND').status, 'dead');
  assertEquals(classifyFcmResponse(404, null).status, 'dead');
  assertEquals(classifyFcmResponse(400, 'UNREGISTERED').status, 'dead');
  assertEquals(classifyFcmResponse(400, 'INVALID_ARGUMENT').status, 'dead');
});

Deno.test('자격 증명 문제는 토큰을 지우지 않는다 - 값만 고치면 다음부터 정상이다', () => {
  assertEquals(classifyFcmResponse(401, 'UNAUTHENTICATED').status, 'failed');
  assertEquals(classifyFcmResponse(403, 'PERMISSION_DENIED').status, 'failed');
});

Deno.test('일시적인 실패는 실패로만 둔다(재시도하지 않는다)', () => {
  assertEquals(classifyFcmResponse(429, 'RESOURCE_EXHAUSTED').status, 'failed');
  assertEquals(classifyFcmResponse(500, 'INTERNAL').status, 'failed');
  assertEquals(classifyFcmResponse(503, 'UNAVAILABLE').status, 'failed');
  // 400이라도 토큰 형식 문제가 아니면 토큰을 지우지 않는다.
  assertEquals(classifyFcmResponse(400, 'FAILED_PRECONDITION').status, 'failed');
});

Deno.test('성공은 2xx 전부', () => {
  assertEquals(classifyFcmResponse(200, null), { status: 'sent' });
  assertEquals(classifyFcmResponse(204, null), { status: 'sent' });
});

Deno.test('실패 설명에는 상태 코드와 FCM 오류 코드만 남는다', () => {
  const outcome = classifyFcmResponse(500, 'INTERNAL');
  assertEquals(outcome.status === 'failed' ? outcome.detail : '', 'FCM 500 INTERNAL');
});

Deno.test('응답 본문에서 오류 코드만 꺼낸다', () => {
  assertEquals(errorStatusOf({ error: { status: 'UNREGISTERED', message: '기기 토큰 ...' } }), 'UNREGISTERED');
  assertEquals(errorStatusOf({ error: {} }), null);
  assertEquals(errorStatusOf(null), null);
  assertEquals(errorStatusOf('nope'), null);
});

Deno.test('서비스 계정은 base64 JSON에서 세 값만 읽는다', () => {
  const account = {
    type: 'service_account',
    project_id: 'tododo-f81f0',
    private_key: '-----BEGIN PRIVATE KEY-----\nAAAA\n-----END PRIVATE KEY-----\n',
    client_email: 'fcm@tododo-f81f0.iam.gserviceaccount.com',
  };
  const parsed = parseServiceAccount(btoa(JSON.stringify(account)));

  assertEquals(parsed?.projectId, 'tododo-f81f0');
  assertEquals(parsed?.clientEmail, 'fcm@tododo-f81f0.iam.gserviceaccount.com');
});

Deno.test('값이 없거나 모양이 틀리면 null이다 - 발송을 시도하지 않는다', () => {
  assertEquals(parseServiceAccount(undefined), null);
  assertEquals(parseServiceAccount(''), null);
  assertEquals(parseServiceAccount('   '), null);
  assertEquals(parseServiceAccount('base64가 아님!!'), null);
  assertEquals(parseServiceAccount(btoa('{}')), null);
  // 세 키 중 하나라도 빠지면 쓰지 않는다.
  assertEquals(parseServiceAccount(btoa(JSON.stringify({ project_id: 'p', private_key: 'k' }))), null);
});

Deno.test('PEM은 머리말·꼬리말·줄바꿈을 떼고 DER로 바뀐다', () => {
  const der = new Uint8Array([1, 2, 3, 4, 5]);
  let binary = '';
  for (const byte of der) binary += String.fromCharCode(byte);
  const body = btoa(binary);

  assertEquals(pemToDer(`-----BEGIN PRIVATE KEY-----\n${body}\n-----END PRIVATE KEY-----\n`), der);
  // 줄바꿈이 \n 문자열 그대로 들어온 경우도 받는다.
  assertEquals(pemToDer(`-----BEGIN PRIVATE KEY-----\\n${body}\\n-----END PRIVATE KEY-----`), der);
});
