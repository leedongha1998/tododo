// FCM HTTP v1 발송은 여기 한 곳에서만 한다.
//
// 자격 증명(FCM_SERVICE_ACCOUNT)은 Edge Function 시크릿으로만 읽는다. 여러 줄 PEM이 환경변수에서
// 깨지는 것을 피하려고 서비스 계정 JSON 전체를 base64 한 줄로 넣는다. 값은 코드·로그·응답
// 어디에도 남기지 않는다(남기는 것은 상태 코드와 FCM 오류 코드뿐이다).
//
// 새 의존성을 넣지 않는다 - REST와 WebCrypto만으로 OAuth2 액세스 토큰을 만든다
// (gemini.ts가 REST를 직접 부르는 선례와 같은 선).

const TOKEN_ENDPOINT = 'https://oauth2.googleapis.com/token';
const SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';
const SEND_TIMEOUT_MS = 10_000;

/// 한 기기로 보낸 결과. 예외는 올리지 않는다 - 발송 실패가 판정·대결을 막아서는 안 된다.
export type FcmOutcome =
  /// 전달됨.
  | { status: 'sent' }
  /// 이 토큰은 더 이상 유효하지 않다. 호출자가 device_push_tokens에서 지운다.
  | { status: 'dead'; detail: string }
  /// 이번에는 실패. 토큰은 그대로 둔다(자격 증명 설정 문제이거나 일시적인 문제다).
  | { status: 'failed'; detail: string };

export interface ServiceAccount {
  clientEmail: string;
  privateKeyPem: string;
  projectId: string;
}

/// base64 한 줄로 넣은 서비스 계정 JSON을 읽는다. 값이 없거나 모양이 틀리면 null이고,
/// 그때는 발송을 시도하지 않는다(시크릿이 들어오는 순간부터 이어서 나간다).
export function parseServiceAccount(encoded: string | undefined): ServiceAccount | null {
  if (!encoded || encoded.trim().length === 0) return null;

  let json: unknown;
  try {
    json = JSON.parse(new TextDecoder().decode(decodeBase64(encoded.trim())));
  } catch {
    return null;
  }

  const account = json as Record<string, unknown>;
  const clientEmail = account.client_email;
  const privateKeyPem = account.private_key;
  const projectId = account.project_id;
  if (
    typeof clientEmail !== 'string' || typeof privateKeyPem !== 'string' ||
    typeof projectId !== 'string'
  ) {
    return null;
  }
  return { clientEmail, privateKeyPem, projectId };
}

/// PEM 본문만 떼어 DER 바이트로. 줄바꿈이 \n 문자열로 들어온 경우도 받는다
/// (JSON을 base64로 감쌌으므로 보통은 진짜 줄바꿈이다).
export function pemToDer(pem: string): Uint8Array<ArrayBuffer> {
  const body = pem
    .replace(/\\n/g, '\n')
    .replace(/-----BEGIN [^-]+-----/, '')
    .replace(/-----END [^-]+-----/, '')
    .replace(/\s+/g, '');
  return decodeBase64(body);
}

function decodeBase64(value: string): Uint8Array<ArrayBuffer> {
  const binary = atob(value);
  const bytes = new Uint8Array(new ArrayBuffer(binary.length));
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function base64Url(bytes: Uint8Array): string {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

/// 보낼 메시지 한 통. `notification`을 쓰는 이유는 앱이 종료돼 있어도 시스템이 그려 주기
/// 때문이다. `android.priority = high`는 Doze 상태에서 임박·종결 알림이 늦는 것을 막는다.
/// 알림 채널은 따로 만들지 않고 FCM 기본 채널을 쓴다(여러 채널·중요도 체계는 spec 범위 밖).
export function buildFcmMessage(
  token: string,
  title: string,
  body: string,
  data: Record<string, string>,
): Record<string, unknown> {
  return {
    message: {
      token,
      notification: { title, body },
      android: { priority: 'high' },
      data,
    },
  };
}

/// FCM 응답을 세 가지 결론으로 옮긴다.
///   404 / UNREGISTERED, 400 + INVALID_ARGUMENT  -> 죽은 토큰(지운다)
///   401 / 403                                   -> 자격 증명 설정 문제. 토큰은 그대로 두고 실패로만 둔다
///                                                  (값만 고치면 다음 사건부터 정상이 된다)
///   그 밖(429·5xx 등)                            -> 실패. 재시도하지 않는다(spec: 누락은 허용, 중복은 금지)
export function classifyFcmResponse(status: number, errorStatus: string | null): FcmOutcome {
  if (status >= 200 && status < 300) return { status: 'sent' };

  const code = errorStatus ?? '';
  if (status === 404 || code === 'UNREGISTERED' || code === 'NOT_FOUND') {
    return { status: 'dead', detail: `FCM ${status} ${code || 'UNREGISTERED'}` };
  }
  if (status === 400 && code === 'INVALID_ARGUMENT') {
    return { status: 'dead', detail: 'FCM 400 INVALID_ARGUMENT' };
  }
  return { status: 'failed', detail: `FCM ${status}${code ? ` ${code}` : ''}` };
}

/// 응답 본문에서 FCM이 준 오류 코드만 꺼낸다. 본문을 통째로 로그에 남기지 않기 위한 것이다.
export function errorStatusOf(body: unknown): string | null {
  const error = (body as { error?: { status?: unknown } } | null)?.error;
  const status = error?.status;
  return typeof status === 'string' ? status : null;
}

// 액세스 토큰은 만료 1분 전까지 모듈 스코프에 들고 있는다. 한 tick에서 여러 통을 보내므로
// 매번 교환하면 OAuth 호출만 늘어난다.
let cachedToken: { value: string; expiresAt: number } | null = null;

/// 테스트와 시크릿 교체 뒤를 위해 캐시를 비운다.
export function clearAccessTokenCache(): void {
  cachedToken = null;
}

async function accessToken(account: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.expiresAt - 60 > now) return cachedToken.value;

  const header = base64Url(new TextEncoder().encode(JSON.stringify({ alg: 'RS256', typ: 'JWT' })));
  const claims = base64Url(
    new TextEncoder().encode(
      JSON.stringify({
        iss: account.clientEmail,
        scope: SCOPE,
        aud: TOKEN_ENDPOINT,
        iat: now,
        exp: now + 3600,
      }),
    ),
  );

  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToDer(account.privateKeyPem),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(`${header}.${claims}`),
  );
  const assertion = `${header}.${claims}.${base64Url(new Uint8Array(signature))}`;

  const response = await fetch(TOKEN_ENDPOINT, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  });

  if (!response.ok) {
    // 상태 코드만 남긴다. 본문에 자격 증명이 섞여 돌아올 이유는 없지만 통째로 로그하지 않는다.
    throw new Error(`OAuth 토큰 교환 실패 (${response.status})`);
  }

  const body = await response.json().catch(() => null) as
    | { access_token?: string; expires_in?: number }
    | null;
  const value = body?.access_token;
  if (typeof value !== 'string' || value.length === 0) {
    throw new Error('OAuth 응답에 액세스 토큰이 없습니다.');
  }

  cachedToken = { value, expiresAt: now + (body?.expires_in ?? 3600) };
  return value;
}

/// 기기 하나로 한 통. 어떤 실패도 예외로 올리지 않는다.
export async function sendToToken(
  account: ServiceAccount,
  token: string,
  title: string,
  body: string,
  data: Record<string, string>,
): Promise<FcmOutcome> {
  let bearer: string;
  try {
    bearer = await accessToken(account);
  } catch (error) {
    // 자격 증명 문제다. 토큰을 지우지 않는다 - 값만 고치면 다음 사건부터 정상이 된다.
    return { status: 'failed', detail: error instanceof Error ? error.message : 'OAuth 실패' };
  }

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), SEND_TIMEOUT_MS);

  try {
    const response = await fetch(
      `https://fcm.googleapis.com/v1/projects/${account.projectId}/messages:send`,
      {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          authorization: `Bearer ${bearer}`,
        },
        body: JSON.stringify(buildFcmMessage(token, title, body, data)),
        signal: controller.signal,
      },
    );

    if (response.ok) {
      // 본문을 읽어 연결을 정리한다(값은 쓰지 않는다).
      await response.body?.cancel();
      return { status: 'sent' };
    }

    const payload = await response.json().catch(() => null);
    return classifyFcmResponse(response.status, errorStatusOf(payload));
  } catch (error) {
    if (error instanceof Error && error.name === 'AbortError') {
      return { status: 'failed', detail: 'FCM 호출이 시간 안에 끝나지 않았습니다.' };
    }
    return { status: 'failed', detail: 'FCM에 연결하지 못했습니다.' };
  } finally {
    clearTimeout(timer);
  }
}
