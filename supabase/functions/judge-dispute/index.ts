// AI 재판정 잡 실행기(불복 재판정 / 우열 재판정).
//
// 부르는 쪽은 사용자가 아니라 서버다: cron의 dispatch_ai_judgments가 pg_net으로 부른다.
// 그래서 verify_jwt = false로 배포하고 **헤더 x-judge-secret을 상수 시간으로 비교하는 것이
// 유일한 관문**이다(불일치는 401).
//
// 실제 판정은 _shared/dispute_judge.ts가 한다. 승패는 DB가 정한다 - 이 함수는 AI 응답을 사실로
// 옮기기만 한다. 옛 judge-quality를 대체한다(잡 단위가 대결에서 건으로 바뀌어 입력도 job_id다).

import { serviceClient } from '../_shared/auth.ts';
import { errorResponse, jsonResponse } from '../_shared/errors.ts';
import { runDisputeJudgment } from '../_shared/dispute_judge.ts';
import { ValidationError, parseJudgeDisputeRequest } from '../_shared/schemas.ts';
import { constantTimeEquals } from '../_shared/secret.ts';

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== 'POST') {
    return errorResponse('BAD_REQUEST');
  }

  const secret = Deno.env.get('JUDGE_CRON_SECRET') ?? '';
  const provided = req.headers.get('x-judge-secret') ?? '';
  // 시크릿이 설정되지 않았으면(빈 문자열) 어떤 요청도 통과하지 못한다.
  if (!constantTimeEquals(provided, secret)) {
    return errorResponse('UNAUTHORIZED');
  }

  let request;
  try {
    request = parseJudgeDisputeRequest(await req.json().catch(() => null));
  } catch (error) {
    if (error instanceof ValidationError) {
      console.error(`judge-dispute 입력 오류: ${error.message}`);
      return errorResponse('BAD_REQUEST');
    }
    throw error;
  }

  const result = await runDisputeJudgment(serviceClient(), request.jobId);

  return jsonResponse({ result });
});
