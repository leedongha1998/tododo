// 알림 발송기: 원장(notification_outbox)을 비운다.
//
// 부르는 쪽은 사용자가 아니라 서버다: cron notify-tick의 dispatch_notifications가 pg_net으로
// 부른다. 그래서 verify_jwt = false로 배포하고 **헤더 x-notify-secret을 상수 시간으로 비교하는
// 것이 유일한 관문**이다(불일치는 401). 입력은 없다 - 큐를 비우는 것이 일이다.
//
// 이 함수는 DB를 다시 읽지 않는다. claim_notifications가 내준 payload 스냅샷만으로 문구를
// 만들므로, 대결·제출 테이블에 접근할 이유가 없어 비공개 정보(판정 사유·사진)가 새는 경로 자체가
// 없다. 승패·점수도 계산하지 않는다 - 이미 확정된 사실의 사본을 배달할 뿐이다.
//
// 어떤 실패도 예외로 올리지 않고 console.error로만 남긴다(spec: 사용자에게 알리지 않고 서버
// 로그에만). 한 통이 실패해도 나머지는 계속 보낸다.

import { serviceClient } from '../_shared/auth.ts';
import { errorResponse, jsonResponse } from '../_shared/errors.ts';
import { parseServiceAccount, sendToToken } from '../_shared/fcm.ts';
import { notificationText } from '../_shared/notification_text.ts';
import { constantTimeEquals } from '../_shared/secret.ts';

/// 한 번에 집어 오는 행 수. 1분마다 돌므로 밀려도 다음 tick이 이어서 비운다.
const CLAIM_LIMIT = 50;

interface ClaimedRow {
  id: number;
  kind: string;
  battle_id: string;
  payload: Record<string, unknown>;
  tokens: string[];
}

function parseRows(data: unknown): ClaimedRow[] {
  if (!Array.isArray(data)) return [];
  return data.flatMap((row) => {
    const item = row as Partial<ClaimedRow>;
    if (typeof item?.id !== 'number' || typeof item?.kind !== 'string') return [];
    if (typeof item?.battle_id !== 'string') return [];
    const tokens = Array.isArray(item.tokens)
      ? item.tokens.filter((token): token is string => typeof token === 'string')
      : [];
    const payload = (item.payload ?? {}) as Record<string, unknown>;
    return [{ id: item.id, kind: item.kind, battle_id: item.battle_id, payload, tokens }];
  });
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== 'POST') {
    return errorResponse('BAD_REQUEST');
  }

  const secret = Deno.env.get('NOTIFY_CRON_SECRET') ?? '';
  const provided = req.headers.get('x-notify-secret') ?? '';
  // 시크릿이 설정되지 않았으면(빈 문자열) 어떤 요청도 통과하지 못한다.
  if (!constantTimeEquals(provided, secret)) {
    return errorResponse('UNAUTHORIZED');
  }

  const account = parseServiceAccount(Deno.env.get('FCM_SERVICE_ACCOUNT'));
  if (account === null) {
    // 자격 증명이 아직 들어오지 않았다. **원장을 집어 오지 않는다** - 집어 오면 그 행들이
    // sending으로 바뀌었다가 임대 만료로 failed가 되어 영영 전달되지 않는다. 값이 들어오는
    // 순간부터 쌓여 있던 알림이 그대로 나간다.
    console.error('send-notifications: FCM_SERVICE_ACCOUNT가 없어 발송을 건너뜁니다.');
    return jsonResponse({ claimed: 0, sent: 0, failed: 0, skipped: true });
  }

  const client = serviceClient();
  const { data, error } = await client.rpc('claim_notifications', { p_limit: CLAIM_LIMIT });
  if (error) {
    console.error(`send-notifications: claim 실패 - ${error.message}`);
    return errorResponse('SERVER_ERROR');
  }

  const rows = parseRows(data);
  let sent = 0;
  let failed = 0;

  for (const row of rows) {
    const text = notificationText(row.kind, row.payload);
    if (text === null) {
      // 뜻을 모르는 kind다. 글자를 지어내지 않고 실패로 기록하고 넘어간다(재시도 없음).
      console.error(`send-notifications: 모르는 kind (id=${row.id}, kind=${row.kind})`);
      await record(client, row.id, 'failed', '알 수 없는 알림 종류입니다.', []);
      failed += 1;
      continue;
    }

    const dead: string[] = [];
    let delivered = false;
    let lastError = '';

    for (const token of row.tokens) {
      const outcome = await sendToToken(account, token, text.title, text.body, {
        battle_id: row.battle_id,
        kind: row.kind,
      });
      if (outcome.status === 'sent') {
        delivered = true;
      } else if (outcome.status === 'dead') {
        dead.push(token);
        lastError = outcome.detail;
      } else {
        lastError = outcome.detail;
      }
    }

    // 한 기기라도 전달되면 그 행은 보낸 것으로 본다(같은 사건을 다시 보내지 않는다).
    if (delivered) {
      sent += 1;
      await record(client, row.id, 'sent', null, dead);
    } else {
      failed += 1;
      await record(client, row.id, 'failed', lastError || '보낼 기기가 없습니다.', dead);
    }
  }

  return jsonResponse({ claimed: rows.length, sent, failed });
});

/// 결과 기록과 죽은 토큰 정리. 여기서 실패해도 예외를 올리지 않는다 - 다음 claim이 임대 만료로
/// 그 행을 failed로 내린다(중복 발송보다 누락을 택한다는 spec 그대로다).
async function record(
  client: ReturnType<typeof serviceClient>,
  id: number,
  status: 'sent' | 'failed',
  detail: string | null,
  deadTokens: string[],
): Promise<void> {
  const { error } = await client.rpc('record_notification_result', {
    p_id: id,
    p_status: status,
    p_error: detail,
    p_dead_tokens: deadTokens.length > 0 ? deadTokens : null,
  });
  if (error) {
    console.error(`send-notifications: 결과 기록 실패 (id=${id}) - ${error.message}`);
  }
}
