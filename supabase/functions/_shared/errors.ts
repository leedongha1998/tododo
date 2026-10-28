// 오류 코드와 HTTP 상태 매핑.
//
// 서버 메시지를 그대로 사용자에게 보여 주지 않는다. 앱은 코드로 분기해 자기 문구를 고른다.

export const ERROR_CODES = [
  'CONSENT_REQUIRED',
  'PENDING_EXISTS',
  'MY_DAILY_LIMIT',
  'CRITERIA_CALL_LIMIT',
  'CHECK_INVALID',
  'NOT_PENDING',
  // 증거 제출 거부(행을 만들지 않으므로 어떤 횟수에도 들어가지 않는다).
  'CAPTURED_BEFORE_START',
  'CAPTURE_TIME_MISMATCH',
  'DEADLINE_PASSED',
  'SUBMISSION_LOCKED',
  'BAD_REQUEST',
  'UNAUTHORIZED',
  'AI_FAILED',
  'SERVER_ERROR',
] as const;

export type ErrorCode = (typeof ERROR_CODES)[number];

const STATUS: Record<ErrorCode, number> = {
  CONSENT_REQUIRED: 403,
  PENDING_EXISTS: 409,
  MY_DAILY_LIMIT: 429,
  CRITERIA_CALL_LIMIT: 429,
  CHECK_INVALID: 409,
  NOT_PENDING: 409,
  // 거부는 요청 형식이 아니라 내용(촬영 시각·상태·횟수) 문제라 422다.
  CAPTURED_BEFORE_START: 422,
  CAPTURE_TIME_MISMATCH: 422,
  DEADLINE_PASSED: 422,
  SUBMISSION_LOCKED: 422,
  BAD_REQUEST: 400,
  UNAUTHORIZED: 401,
  // AI 실패는 우리 잘못도 사용자 잘못도 아니다. 앱은 "다시 시도" 버튼을 보여 준다.
  AI_FAILED: 502,
  SERVER_ERROR: 500,
};

export function statusFor(code: ErrorCode): number {
  return STATUS[code] ?? 500;
}

/// DB 함수가 `raise ... using hint = '<CODE>'`로 알려 준 코드를 그대로 받는다.
export function codeFromHint(hint: unknown): ErrorCode | null {
  if (typeof hint !== 'string') return null;
  return (ERROR_CODES as readonly string[]).includes(hint) ? (hint as ErrorCode) : null;
}

export function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}

export function errorResponse(code: ErrorCode, extra: Record<string, unknown> = {}): Response {
  return jsonResponse({ error: code, ...extra }, statusFor(code));
}
