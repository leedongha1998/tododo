// 알림 문구는 전부 여기서 만든다.
//
// **왜 서버인가**: 앱이 종료돼 있어도 잠금화면에 보여야 하므로 FCM `notification` 페이로드로
// 보내고, 그 텍스트는 안드로이드 시스템이 앱 코드 없이 그린다. 클라이언트가 문구를 만들려면
// data-only 메시지 + 백그라운드 isolate + 로컬 알림 패키지가 필요해 패키지와 실패 지점만 늘어난다.
// 그래서 CLAUDE.md "사용자에게 보이는 문자열은 lib/core/strings.dart"의 예외다
// (앱 화면에 보이는 문자열은 종전대로 strings.dart다).
//
// **담지 않는 것**(spec "알림 문구가 담는 것과 담지 않는 것"): 판정 사유, 증거 사진, 상대의 표시
// 이름, 내부 코드·서버 오류 메시지, 누적 점수·승패 카운터. 이 함수는 **아는 키만 읽는다** —
// payload에 무엇이 들어 있든 아래에 적힌 키 말고는 문구에 닿을 길이 자체가 없다. 금지 항목을
// 걸러내는 목록을 두지 않고 구조로 막는 쪽을 택했다.
//
// 남은 시간은 원장에 담지 않는다(deadline_at만 담는다). 발송 시각 기준으로 여기서 계산한다.

export interface NotificationText {
  title: string;
  body: string;
}

/// 원장 한 행에서 문구를 만들 때 읽는 것. payload의 나머지 키는 쳐다보지 않는다.
export type NotificationPayload = Record<string, unknown>;

/// 대결 제목은 「」로 감싼다. 사용자가 직접 쓰거나 공개 모집에서 보고 참가한 문장이라 담는다(결정 3).
function quoted(title: unknown): string {
  const text = typeof title === 'string' ? title.trim() : '';
  return text.length > 0 ? `「${text}」` : '「대결」';
}

function textOf(value: unknown): string | null {
  return typeof value === 'string' && value.trim().length > 0 ? value.trim() : null;
}

/// 남은 시간을 "3시간" / "25분"으로. 값이 없거나 이미 지났으면 null이고, 그때는 부르는 쪽이
/// 시간 문장을 통째로 뺀다 - 틀린 시간을 말하느니 말하지 않는다.
export function remainingAmount(deadlineIso: unknown, now: Date): string | null {
  const iso = textOf(deadlineIso);
  if (iso === null) return null;

  const deadline = Date.parse(iso);
  if (Number.isNaN(deadline)) return null;

  const minutes = Math.floor((deadline - now.getTime()) / 60_000);
  if (minutes < 1) return null;
  if (minutes < 60) return `${minutes}분`;
  return `${Math.floor(minutes / 60)}시간`;
}

/// 점수 변화 한 조각. 0점은 하한(0점 아래로 내려가지 않는다)에 걸린 경우라 사실과 어긋나지 않게
/// 문장을 바꾼다 - "-3점"이라고 해 놓고 점수가 그대로이면 규칙을 잘못 배우게 된다.
function scorePhrase(delta: unknown): string {
  const value = typeof delta === 'number' && Number.isFinite(delta) ? Math.trunc(delta) : 0;
  if (value > 0) return `+${value}점`;
  if (value < 0) return `${value}점`;
  return '점수 변화 없음 · 점수는 0점 아래로 내려가지 않아요';
}

function finishedText(payload: NotificationPayload): NotificationText {
  const outcome = textOf(payload.outcome);
  const delta = payload.score_delta;
  const score = scorePhrase(delta);

  const title = outcome === 'win' ? '이겼어요!' : outcome === 'draw' ? '무승부예요' : '졌어요';

  // "완료한 패배"는 속도전에서 기준을 통과하고도 늦은 경우다. 점수가 실제로 덜 깎였을 때만
  // 그렇게 말한다 - 하한에 걸려 변화가 0이면 "감점이 줄었다"가 사실과 어긋난다.
  const softened =
    outcome === 'completed_loss' && typeof delta === 'number' && delta < 0
      ? ' · 기준을 통과해서 감점이 줄었어요.'
      : '';

  return { title, body: `${quoted(payload.title)} · ${score}${softened}` };
}

function submittedText(payload: NotificationPayload): NotificationText {
  const type = textOf(payload.battle_type);
  // 두 유형이 잃는 것이 다르다. 품질전은 안 내면 상대가 판정 없이 이기고, 속도전은 그 순간
  // 내 사진 교체가 잠긴다. 제출 시각·사진·교체 횟수는 담지 않는다(마감 전 공개 범위 그대로).
  const tail =
    type === 'quality'
      ? ' 아직 내 사진을 내지 않았어요.'
      : type === 'speed'
        ? ' 이제 내 사진은 바꿀 수 없어요.'
        : '';
  return { title: '상대가 사진을 냈어요', body: `${quoted(payload.title)}${tail}` };
}

function judgeTurnText(payload: NotificationPayload, now: Date): NotificationText {
  const left = remainingAmount(payload.judge_deadline_at, now);
  // 미판정은 승인으로 간주된다(도메인 규칙). 그래서 "안 하면 어떻게 되는지"가 이 알림의 핵심이다.
  const body =
    left === null
      ? `${quoted(payload.title)} 판정하지 않으면 자동 승인돼요.`
      : `${quoted(payload.title)} ${left} 안에 판정하지 않으면 자동 승인돼요.`;
  return { title: '판정할 차례예요', body };
}

function matchedText(payload: NotificationPayload, now: Date): NotificationText {
  const left = remainingAmount(payload.deadline_at, now);
  const tail = left === null ? '' : ` 마감까지 ${left} 남았어요.`;
  // 참가자의 표시 이름을 담지 않는다. 소셜 로그인에서 온 실명일 수 있어 "상대"로만 부른다.
  return {
    title: '대결이 시작됐어요',
    body: `${quoted(payload.title)}에 상대가 참가했어요.${tail}`,
  };
}

function deadlineSoonText(payload: NotificationPayload, now: Date): NotificationText {
  const left = remainingAmount(payload.deadline_at, now);
  // 재촉하지 않는다(spec "N6의 제약"). 사실과 남은 시간만 전한다.
  const body =
    left === null ? quoted(payload.title) : `${quoted(payload.title)} 마감까지 ${left} 남았어요.`;
  return { title: '마감이 다가와요', body };
}

function cancelledText(payload: NotificationPayload): NotificationText {
  // 탈퇴한 사람의 이름은 담지 않는다. 한도가 돌아온 것은 오늘 매칭된 대결일 때만이다.
  const tail = payload.slot_returned === true ? ' 오늘 대결 한도가 돌아왔어요.' : '';
  return {
    title: '대결이 취소됐어요',
    body: `${quoted(payload.title)} 상대가 탈퇴해서 취소됐어요.${tail}`,
  };
}

/// 원장의 kind와 payload로 알림 문구를 만든다. 모르는 kind는 null이고, 부르는 쪽은 그 행을
/// 보내지 않는다 - 뜻을 모르는 채로 사용자에게 글자를 띄우지 않는다.
export function notificationText(
  kind: string,
  payload: NotificationPayload,
  now: Date = new Date(),
): NotificationText | null {
  switch (kind) {
    case 'matched':
      return matchedText(payload, now);
    case 'finished':
      return finishedText(payload);
    case 'voided':
      // 실패 원인·사유는 담지 않는다. 결과와 그것이 전적에 미치는 영향까지만.
      return {
        title: '판정이 무효가 됐어요',
        body: `${quoted(payload.title)} 점수와 전적에 반영되지 않아요.`,
      };
    case 'submitted':
      return submittedText(payload);
    case 'judge_turn':
      return judgeTurnText(payload, now);
    case 'cancelled':
      return cancelledText(payload);
    case 'deadline_soon':
      return deadlineSoonText(payload, now);
    default:
      return null;
  }
}
