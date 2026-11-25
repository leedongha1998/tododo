import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  buildUnlinkRequest,
  type Fetcher,
  interpretUnlinkResponse,
  isKakaoUser,
  KAKAO_UNLINK_URL,
  kakaoTargetId,
  unlinkAfterDeletion,
  unlinkKakaoUser,
} from './kakao_unlink.ts';

const KEY = 'test-admin-key-should-never-be-logged';

function kakaoUser(identityData: Record<string, unknown>, id?: unknown) {
  return { identities: [{ provider: 'kakao', id, identity_data: identityData }] };
}

/// 요청을 기록하고 정해 둔 응답을 돌려주는 가짜 fetch.
function fakeFetch(respond: () => Response | Promise<Response>) {
  const calls: { url: string; init: RequestInit }[] = [];
  const fetcher: Fetcher = (url, init) => {
    calls.push({ url, init });
    return Promise.resolve(respond());
  };
  return { fetcher, calls };
}

function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), { status });
}

/// console.error로 찍힌 문자열을 모은다. **키가 로그에 남지 않는지**를 보는 데 쓴다.
async function captureErrors<T>(run: () => Promise<T>): Promise<{ result: T; logs: string[] }> {
  const logs: string[] = [];
  const original = console.error;
  console.error = (...args: unknown[]) => logs.push(args.map(String).join(' '));
  try {
    return { result: await run(), logs };
  } finally {
    console.error = original;
  }
}

Deno.test('회원번호: identity_data.sub가 첫 자리다', () => {
  assertEquals(kakaoTargetId(kakaoUser({ sub: '4411', provider_id: '9999' }, '8888')), '4411');
});

Deno.test('회원번호: sub가 없으면 provider_id, 그것도 없으면 행의 id', () => {
  assertEquals(kakaoTargetId(kakaoUser({ provider_id: '4411' })), '4411');
  assertEquals(kakaoTargetId(kakaoUser({}, '4411')), '4411');
  // 숫자로 와도 회원번호로 읽는다.
  assertEquals(kakaoTargetId(kakaoUser({ sub: 4411 })), '4411');
});

Deno.test('회원번호: 카카오 identity가 없으면 null', () => {
  assertEquals(kakaoTargetId({ identities: [{ provider: 'google', identity_data: { sub: '1' } }] }), null);
  assertEquals(kakaoTargetId({ identities: [] }), null);
  assertEquals(kakaoTargetId({}), null);
  assertEquals(kakaoTargetId({ identities: null }), null);
});

Deno.test('회원번호: 숫자만 1~20자가 아니면 null', () => {
  assertEquals(kakaoTargetId(kakaoUser({ sub: 'abc' })), null);
  assertEquals(kakaoTargetId(kakaoUser({ sub: '' })), null);
  assertEquals(kakaoTargetId(kakaoUser({ sub: '1'.repeat(21) })), null);
  assertEquals(kakaoTargetId(kakaoUser({ sub: '1'.repeat(20) })), '1'.repeat(20));
  assertEquals(kakaoTargetId(kakaoUser({ sub: '-1' })), null);
  assertEquals(kakaoTargetId(kakaoUser({ sub: 1.5 })), null);
  // 첫 값이 엉뚱하면 다음 후보로 넘어가지 않는다(레코드 모양이 예상과 다르다는 뜻이다).
  assertEquals(kakaoTargetId(kakaoUser({ sub: 'abc', provider_id: '4411' })), null);
});

Deno.test('회원번호: Google·카카오가 함께 있으면(일어나지 않지만) 카카오 값', () => {
  const user = {
    identities: [
      { provider: 'google', identity_data: { sub: '1111' } },
      { provider: 'kakao', identity_data: { sub: '4411' } },
    ],
  };
  assertEquals(kakaoTargetId(user), '4411');
});

Deno.test('카카오 가입자 판별: identity 또는 app_metadata', () => {
  assert(isKakaoUser(kakaoUser({ sub: '1' })));
  assert(isKakaoUser({ identities: [], app_metadata: { provider: 'kakao' } }));
  assert(isKakaoUser({ app_metadata: { providers: ['kakao'] } }));
  assert(!isKakaoUser({ identities: [{ provider: 'google' }], app_metadata: { provider: 'google' } }));
  assert(!isKakaoUser({}));
});

Deno.test('요청: 주소·메서드·헤더·본문', () => {
  const { url, init } = buildUnlinkRequest(KEY, '4411');
  assertEquals(url, 'https://kapi.kakao.com/v1/user/unlink');
  assertEquals(url, KAKAO_UNLINK_URL);
  assertEquals(init.method, 'POST');
  const headers = init.headers as Record<string, string>;
  assertEquals(headers.Authorization, `KakaoAK ${KEY}`);
  assertEquals(headers['Content-Type'], 'application/x-www-form-urlencoded;charset=utf-8');
  assertEquals(init.body, 'target_id_type=user_id&target_id=4411');
});

Deno.test('응답: 200 + 같은 id면 done, 그 밖은 failed', () => {
  assertEquals(interpretUnlinkResponse(200, { id: 4411 }, '4411'), 'done');
  assertEquals(interpretUnlinkResponse(200, { id: '4411' }, '4411'), 'done');
  assertEquals(interpretUnlinkResponse(200, { id: 9999 }, '4411'), 'failed');
  assertEquals(interpretUnlinkResponse(200, {}, '4411'), 'failed');
  assertEquals(interpretUnlinkResponse(200, null, '4411'), 'failed');
  assertEquals(interpretUnlinkResponse(400, { code: -101, msg: 'x' }, '4411'), 'failed');
  assertEquals(interpretUnlinkResponse(401, { code: -401 }, '4411'), 'failed');
  assertEquals(interpretUnlinkResponse(500, { id: 4411 }, '4411'), 'failed');
});

Deno.test('끊기: 정상이면 요청 한 번에 done', async () => {
  const { fetcher, calls } = fakeFetch(() => jsonResponse(200, { id: 4411 }));
  const { result, logs } = await captureErrors(() => unlinkKakaoUser(fetcher, KEY, '4411'));
  assertEquals(result, 'done');
  assertEquals(calls.length, 1);
  assertEquals(calls[0].url, KAKAO_UNLINK_URL);
  // 시간 제한 신호가 붙어 있다(5초).
  assert(calls[0].init.signal instanceof AbortSignal);
  assertEquals(logs, []);
});

Deno.test('끊기: 키가 비면 요청하지 않고 failed', async () => {
  const { fetcher, calls } = fakeFetch(() => jsonResponse(200, { id: 4411 }));
  const { result, logs } = await captureErrors(() => unlinkKakaoUser(fetcher, '', '4411'));
  assertEquals(result, 'failed');
  assertEquals(calls.length, 0);
  assertEquals(logs.length, 1);
  assert(logs[0].includes('KAKAO_ADMIN_KEY 미설정'));
  assert(logs[0].includes('target_id=4411'));

  const blank = await captureErrors(() => unlinkKakaoUser(fetcher, '   ', '4411'));
  assertEquals(blank.result, 'failed');
  assertEquals(calls.length, 0);
});

Deno.test('끊기: fetch가 던지면(네트워크·시간 초과) failed', async () => {
  const network: Fetcher = () => Promise.reject(new TypeError(`connect failed KakaoAK ${KEY}`));
  const timeout: Fetcher = () => Promise.reject(new DOMException('signal timed out', 'TimeoutError'));
  const a = await captureErrors(() => unlinkKakaoUser(network, KEY, '4411'));
  const b = await captureErrors(() => unlinkKakaoUser(timeout, KEY, '4411'));
  assertEquals(a.result, 'failed');
  assertEquals(b.result, 'failed');
  assert(b.logs[0].includes('TimeoutError'));
  // 오류 메시지에 키가 섞여 있어도 로그에는 오류 이름만 남는다.
  for (const line of [...a.logs, ...b.logs]) assert(!line.includes(KEY), line);
});

Deno.test('끊기: 실제로 시간이 넘으면 failed', async () => {
  const hang: Fetcher = (_url, init) =>
    new Promise((_resolve, reject) => {
      init.signal?.addEventListener('abort', () => reject(init.signal?.reason));
    });
  const { result } = await captureErrors(() => unlinkKakaoUser(hang, KEY, '4411', 10));
  assertEquals(result, 'failed');
});

Deno.test('끊기: 본문이 JSON이 아니면 failed', async () => {
  const { fetcher } = fakeFetch(() => new Response('<html>bad gateway</html>', { status: 200 }));
  const { result, logs } = await captureErrors(() => unlinkKakaoUser(fetcher, KEY, '4411'));
  assertEquals(result, 'failed');
  assert(logs[0].includes('JSON'));
});

Deno.test('끊기: 오류 응답은 상태·코드와 회원번호만 남기고 키는 남기지 않는다', async () => {
  const { fetcher } = fakeFetch(() => jsonResponse(401, { code: -401, msg: `bad key ${KEY}` }));
  const { result, logs } = await captureErrors(() => unlinkKakaoUser(fetcher, KEY, '4411'));
  assertEquals(result, 'failed');
  assertEquals(logs.length, 1);
  assert(logs[0].includes('HTTP 401'));
  assert(logs[0].includes('code=-401'));
  assert(logs[0].includes('target_id=4411'));
  assert(!logs[0].includes(KEY));
  assert(!logs[0].includes('bad key'));
});

Deno.test('탈퇴 뒤 판단: 카카오가 아니면 요청 없이 notKakao', async () => {
  const { fetcher, calls } = fakeFetch(() => jsonResponse(200, { id: 1 }));
  const google = { identities: [{ provider: 'google', identity_data: { sub: '1111' } }] };
  assertEquals(await unlinkAfterDeletion(google, fetcher, KEY), 'notKakao');
  assertEquals(calls.length, 0);
});

Deno.test('탈퇴 뒤 판단: 카카오인데 회원번호를 못 뽑으면 요청 없이 failed', async () => {
  const { fetcher, calls } = fakeFetch(() => jsonResponse(200, { id: 1 }));
  const odd = { identities: [], app_metadata: { provider: 'kakao' } };
  const { result, logs } = await captureErrors(() => unlinkAfterDeletion(odd, fetcher, KEY));
  assertEquals(result, 'failed');
  assertEquals(calls.length, 0);
  assert(logs[0].includes('회원번호를 찾지 못함'));
});

Deno.test('탈퇴 뒤 판단: 카카오면 그 회원번호로 끊는다', async () => {
  const { fetcher, calls } = fakeFetch(() => jsonResponse(200, { id: 4411 }));
  assertEquals(await unlinkAfterDeletion(kakaoUser({ sub: '4411' }), fetcher, KEY), 'done');
  assertEquals(calls[0].init.body, 'target_id_type=user_id&target_id=4411');
});
