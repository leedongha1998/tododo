// 탈퇴한 카카오 가입자의 "이 앱과 카카오 계정의 연결" 끊기 (kakao-login design §4).
//
// 왜 Admin 키 + 회원번호인가
//   사용자 액세스 토큰으로 끊는 길도 있지만 Supabase는 카카오가 준 공급자 토큰을 서버에 보관하지
//   않는다. 탈퇴 시점에 그 토큰을 가진 곳이 없으므로 서버가 앱 Admin 키와 회원번호로 끊는다.
//
// 시크릿 규칙
//   Admin 키는 이 앱의 모든 사용자에 대해 관리 API를 부를 수 있는 강한 키다. 부르는 쪽이
//   `Deno.env.get('KAKAO_ADMIN_KEY')`로만 읽어 넘기고, 이 파일은 **어떤 로그에도 키·요청 헤더를
//   찍지 않는다.** 요청 주소는 아래 상수 하나뿐이다(입력에서 주소를 받지 않는다).
//
// 관문이 아니다
//   탈퇴(delete_account)가 끝난 **뒤에** 한 번 시도하고, 실패해도 탈퇴를 되돌리지 않는다. 재시도·
//   대기열은 두지 않는다. 실패하면 운영자가 손으로 다시 끊을 수 있게 회원번호를 로그에 남기고
//   (오너 확정 3번 — 계정이 이미 지워져 다른 곳에 그 값이 없다), 앱은 사용자에게 직접 끊는 곳을 알린다.
//
// [확인 필요 — 2차분] 주소·헤더·본문·성공 모양은 카카오 REST API 문서의 "연결 끊기"로, 회원번호가
// identity의 어느 필드에 있는지는 검증 게이트 V5로 확정한다. "이미 연결이 끊긴 사용자" 오류 코드는
// 확인하지 못해 아래 목록을 비워 두었다(추측한 코드를 넣으면 실제 실패를 성공으로 읽을 수 있다).

export const KAKAO_UNLINK_URL = 'https://kapi.kakao.com/v1/user/unlink';

/// 연결 끊기 요청의 시간 제한. 탈퇴 응답을 이것보다 오래 붙잡지 않는다.
export const KAKAO_UNLINK_TIMEOUT_MS = 5000;

/// "이미 이 앱과 연결되지 않은 사용자" 오류 코드 — 끊으려던 상태가 이미 이뤄져 있으므로 성공으로 본다.
/// 카카오 문서로 확인한 뒤 채운다(2차분). 비어 있는 동안은 그 경우도 `failed`로 읽힌다(안전한 쪽).
export const ALREADY_UNLINKED_CODES: readonly number[] = [];

export type KakaoUnlinkResult = 'done' | 'failed';

/// 앱 응답의 `kakaoUnlink` 값. 카카오 가입자가 아니면 `notKakao`.
export type KakaoUnlinkStatus = KakaoUnlinkResult | 'notKakao';

export type Fetcher = (url: string, init: RequestInit) => Promise<Response>;

/// `auth.getUser()`가 주는 사용자 레코드 중 이 파일이 보는 부분만.
export interface UserLike {
  identities?: ReadonlyArray<IdentityLike> | null;
  app_metadata?: Record<string, unknown> | null;
}

export interface IdentityLike {
  provider?: unknown;
  id?: unknown;
  identity_data?: Record<string, unknown> | null;
}

/// 카카오 회원번호 꼴: 숫자만, 1~20자.
const MEMBER_ID = /^[0-9]{1,20}$/;

function kakaoIdentity(user: UserLike): IdentityLike | null {
  return (user.identities ?? []).find((identity) => identity?.provider === 'kakao') ?? null;
}

/// 이 사용자가 카카오로 가입했는가. identity가 정답이고, identity 목록이 비어 오는 경우를 위해
/// 서버가 쓴 `app_metadata.provider`도 본다 — 카카오인데 `notKakao`로 넘어가면 끊기를 조용히 건너뛴다.
export function isKakaoUser(user: UserLike): boolean {
  if (kakaoIdentity(user) !== null) return true;
  const meta = user.app_metadata ?? {};
  if (meta.provider === 'kakao') return true;
  const providers = meta.providers;
  return Array.isArray(providers) && providers.includes('kakao');
}

function asMemberId(value: unknown): string | null {
  let text: string;
  if (typeof value === 'string') {
    text = value;
  } else if (typeof value === 'number' && Number.isSafeInteger(value) && value >= 0) {
    text = String(value);
  } else {
    return null;
  }
  return MEMBER_ID.test(text) ? text : null;
}

/// 끊을 대상의 카카오 회원번호. 카카오 identity의 `identity_data.sub` → `identity_data.provider_id`
/// → 행의 `id` 순으로 **첫 값**을 본다(게이트 V5로 순서 확정). 그 값이 회원번호 꼴이 아니면 null —
/// 다음 후보로 넘어가지 않는다(첫 값이 엉뚱하면 레코드 모양이 예상과 다른 것이므로 추측하지 않는다).
/// 카카오 identity가 없으면 null.
export function kakaoTargetId(user: UserLike): string | null {
  const identity = kakaoIdentity(user);
  if (identity === null) return null;
  const data = identity.identity_data ?? {};
  const first = [data.sub, data.provider_id, identity.id].find(
    (value) => value !== undefined && value !== null && value !== '',
  );
  return asMemberId(first);
}

/// 연결 끊기 요청. 본문은 `URLSearchParams`로 인코딩한다.
export function buildUnlinkRequest(
  adminKey: string,
  targetId: string,
): { url: string; init: RequestInit } {
  return {
    url: KAKAO_UNLINK_URL,
    init: {
      method: 'POST',
      headers: {
        Authorization: `KakaoAK ${adminKey}`,
        'Content-Type': 'application/x-www-form-urlencoded;charset=utf-8',
      },
      body: new URLSearchParams({ target_id_type: 'user_id', target_id: targetId }).toString(),
    },
  };
}

/// 카카오 응답 해석. 200이고 돌려준 `id`가 끊으려던 회원번호와 같으면 `done`, 이미 끊긴 사용자
/// 코드면 `done`, 그 밖은 전부 `failed`.
export function interpretUnlinkResponse(
  status: number,
  body: unknown,
  targetId: string,
): KakaoUnlinkResult {
  if (body === null || typeof body !== 'object') return 'failed';
  const record = body as Record<string, unknown>;
  if (status === 200) {
    return asMemberId(record.id) === targetId ? 'done' : 'failed';
  }
  const code = record.code;
  if (typeof code === 'number' && ALREADY_UNLINKED_CODES.includes(code)) return 'done';
  return 'failed';
}

function logFailure(reason: string, targetId: string): void {
  // 키·요청 헤더·응답 본문은 남기지 않는다. 회원번호는 운영자가 손으로 다시 끊는 데 필요하다.
  console.error(`delete-account: 카카오 연결 끊기 실패 - ${reason}, target_id=${targetId}`);
}

/// 연결 끊기 1회. 재시도하지 않는다. 키가 비면 요청 없이 `failed`(조용히 건너뛰지 않는다).
/// `fetcher`가 던지거나(네트워크·시간 초과) 본문이 JSON이 아니면 `failed`.
export async function unlinkKakaoUser(
  fetcher: Fetcher,
  adminKey: string,
  targetId: string,
  timeoutMs: number = KAKAO_UNLINK_TIMEOUT_MS,
): Promise<KakaoUnlinkResult> {
  if (adminKey.trim() === '') {
    logFailure('KAKAO_ADMIN_KEY 미설정', targetId);
    return 'failed';
  }

  const { url, init } = buildUnlinkRequest(adminKey, targetId);
  let response: Response;
  try {
    response = await fetcher(url, { ...init, signal: AbortSignal.timeout(timeoutMs) });
  } catch (error) {
    // 오류 메시지 전체가 아니라 이름만 남긴다(메시지에 요청 정보가 섞일 수 있다).
    const name = error instanceof Error ? error.name : typeof error;
    logFailure(`요청 실패(${name})`, targetId);
    return 'failed';
  }

  let body: unknown;
  try {
    body = JSON.parse(await response.text());
  } catch (_) {
    logFailure(`HTTP ${response.status}, 응답이 JSON이 아님`, targetId);
    return 'failed';
  }

  const result = interpretUnlinkResponse(response.status, body, targetId);
  if (result === 'failed') {
    const code = body !== null && typeof body === 'object'
      ? (body as Record<string, unknown>).code
      : undefined;
    const codeText = typeof code === 'number' || typeof code === 'string' ? ` code=${code}` : '';
    logFailure(`HTTP ${response.status}${codeText}`, targetId);
  }
  return result;
}

/// 탈퇴가 끝난 뒤 부르는 자리의 전체 판단. 카카오 가입자가 아니면 요청 없이 `notKakao`,
/// 카카오인데 회원번호를 뽑지 못했으면(레코드 모양이 예상과 다름) 요청 없이 `failed` + 로그.
///
/// 회원번호는 **`delete_account` 전에** 받은 사용자 레코드에서 뽑아야 한다 — 그 RPC가 `auth.users`를
/// 지우면 `auth.identities`도 함께 사라진다. 그래서 이 함수는 레코드를 인자로 받는다.
export async function unlinkAfterDeletion(
  user: UserLike,
  fetcher: Fetcher,
  adminKey: string,
  timeoutMs: number = KAKAO_UNLINK_TIMEOUT_MS,
): Promise<KakaoUnlinkStatus> {
  if (!isKakaoUser(user)) return 'notKakao';
  const targetId = kakaoTargetId(user);
  if (targetId === null) {
    console.error('delete-account: 카카오 연결 끊기 실패 - 회원번호를 찾지 못함');
    return 'failed';
  }
  return await unlinkKakaoUser(fetcher, adminKey, targetId, timeoutMs);
}
