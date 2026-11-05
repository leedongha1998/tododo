// deno test supabase/functions/_shared/
// 알림 문구 7종과 프라이버시 제약(FCM·Google OAuth는 부르지 않는다).

import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { notificationText, remainingAmount } from './notification_text.ts';

const now = new Date('2026-11-04T12:00:00Z');
const inHours = (h: number) => new Date(now.getTime() + h * 3_600_000).toISOString();
const inMinutes = (m: number) => new Date(now.getTime() + m * 60_000).toISOString();

Deno.test('남은 시간은 1시간을 경계로 시간·분으로 적고, 지났으면 말하지 않는다', () => {
  assertEquals(remainingAmount(inHours(3), now), '3시간');
  // 3시간 59분은 아직 3시간이다(올리지 않는다 - 남은 시간을 실제보다 길게 말하지 않는다).
  assertEquals(remainingAmount(inMinutes(239), now), '3시간');
  assertEquals(remainingAmount(inMinutes(60), now), '1시간');
  assertEquals(remainingAmount(inMinutes(59), now), '59분');
  assertEquals(remainingAmount(inMinutes(1), now), '1분');
  // 1분 미만·이미 지남·값 없음·형식 오류는 전부 null이고, 부르는 쪽이 시간 문장을 뺀다.
  assertEquals(remainingAmount(inMinutes(0), now), null);
  assertEquals(remainingAmount(inHours(-1), now), null);
  assertEquals(remainingAmount(undefined, now), null);
  assertEquals(remainingAmount('어제', now), null);
});

Deno.test('N1 매칭: 마감까지 남은 시간을 담고 참가자 이름은 담지 않는다', () => {
  const text = notificationText(
    'matched',
    { title: '아침 달리기', battle_type: 'speed', deadline_at: inHours(3) },
    now,
  );
  assertEquals(text, {
    title: '대결이 시작됐어요',
    body: '「아침 달리기」에 상대가 참가했어요. 마감까지 3시간 남았어요.',
  });
});

Deno.test('N1 매칭: 마감이 이미 지났으면 시간 문장을 뺀다', () => {
  const text = notificationText('matched', { title: '아침 달리기', deadline_at: inHours(-1) }, now);
  assertEquals(text?.body, '「아침 달리기」에 상대가 참가했어요.');
});

Deno.test('N2 종결: 결과별 제목과 점수 변화', () => {
  assertEquals(notificationText('finished', { title: '방 청소', outcome: 'win', score_delta: 3 }, now), {
    title: '이겼어요!',
    body: '「방 청소」 · +3점',
  });
  assertEquals(notificationText('finished', { title: '방 청소', outcome: 'loss', score_delta: -3 }, now), {
    title: '졌어요',
    body: '「방 청소」 · -3점',
  });
  assertEquals(notificationText('finished', { title: '방 청소', outcome: 'draw', score_delta: -1 }, now), {
    title: '무승부예요',
    body: '「방 청소」 · -1점',
  });
  // 포기한 본인에게는 보내지 않지만, 혹시 들어와도 패배로 읽히게 둔다.
  assertEquals(
    notificationText('finished', { title: '방 청소', outcome: 'forfeit', score_delta: -3 }, now)?.title,
    '졌어요',
  );
});

Deno.test('N2 종결: 완료한 패배는 감점이 실제로 줄었을 때만 그렇게 말한다', () => {
  assertEquals(
    notificationText('finished', { title: '방 청소', outcome: 'completed_loss', score_delta: -1 }, now)?.body,
    '「방 청소」 · -1점 · 기준을 통과해서 감점이 줄었어요.',
  );
  // 점수 하한 0에 걸려 변화가 없으면 "감점이 줄었다"가 사실과 어긋난다.
  assertEquals(
    notificationText('finished', { title: '방 청소', outcome: 'completed_loss', score_delta: 0 }, now)?.body,
    '「방 청소」 · 점수 변화 없음 · 점수는 0점 아래로 내려가지 않아요',
  );
});

Deno.test('N2 종결: 점수 변화 0은 하한을 함께 말한다', () => {
  assertEquals(
    notificationText('finished', { title: '방 청소', outcome: 'loss', score_delta: 0 }, now)?.body,
    '「방 청소」 · 점수 변화 없음 · 점수는 0점 아래로 내려가지 않아요',
  );
});

Deno.test("N2' 무효: 실패 원인을 말하지 않고 전적에 미치는 영향만 말한다", () => {
  assertEquals(notificationText('voided', { title: '설거지', battle_type: 'quality' }, now), {
    title: '판정이 무효가 됐어요',
    body: '「설거지」 점수와 전적에 반영되지 않아요.',
  });
});

Deno.test('N3 제출: 유형마다 잃는 것이 달라 뒷문장이 갈린다', () => {
  assertEquals(notificationText('submitted', { title: '방 청소', battle_type: 'quality' }, now), {
    title: '상대가 사진을 냈어요',
    body: '「방 청소」 아직 내 사진을 내지 않았어요.',
  });
  assertEquals(notificationText('submitted', { title: '아침 달리기', battle_type: 'speed' }, now), {
    title: '상대가 사진을 냈어요',
    body: '「아침 달리기」 이제 내 사진은 바꿀 수 없어요.',
  });
});

Deno.test("N4' 판정 차례: 안 하면 자동 승인된다는 사실을 남은 기한과 함께 말한다", () => {
  assertEquals(
    notificationText(
      'judge_turn',
      { title: '아침 달리기', battle_type: 'speed', judge_deadline_at: inHours(24) },
      now,
    ),
    { title: '판정할 차례예요', body: '「아침 달리기」 24시간 안에 판정하지 않으면 자동 승인돼요.' },
  );
  // 기한을 못 읽어도 "안 하면 승인된다"는 사실은 남긴다.
  assertEquals(
    notificationText('judge_turn', { title: '아침 달리기' }, now)?.body,
    '「아침 달리기」 판정하지 않으면 자동 승인돼요.',
  );
});

Deno.test('N5 취소: 사실만 말하고 탈퇴한 사람의 이름은 담지 않는다', () => {
  assertEquals(notificationText('cancelled', { title: '우산 챙기기' }, now), {
    title: '대결이 취소됐어요',
    body: '「우산 챙기기」 상대가 탈퇴해서 취소됐어요.',
  });
  // 한도가 없어졌으므로(daily-limit-removal) 옛 payload가 남아 있어도 그 문장을 붙이지 않는다.
  assertEquals(
    notificationText('cancelled', { title: '우산 챙기기', slot_returned: true }, now)?.body,
    '「우산 챙기기」 상대가 탈퇴해서 취소됐어요.',
  );
});

Deno.test('N6 마감 임박: 사실과 남은 시간만 말한다(재촉 없음)', () => {
  assertEquals(
    notificationText('deadline_soon', { title: '책상 정리', deadline_at: inHours(6) }, now),
    { title: '마감이 다가와요', body: '「책상 정리」 마감까지 6시간 남았어요.' },
  );
});

Deno.test('모르는 kind는 문구를 만들지 않는다', () => {
  assertEquals(notificationText('nope', { title: '방 청소' }, now), null);
  assertEquals(notificationText('', {}, now), null);
});

Deno.test('payload에 금지 항목이 섞여 들어와도 문구에 닿지 않는다', () => {
  // 원장에는 애초에 담기지 않지만(3단계 스모크가 확인한다), 문구 쪽에서도 구조로 막혀 있는지 본다.
  const dirty = {
    title: '방 청소',
    battle_type: 'quality',
    outcome: 'loss',
    score_delta: -3,
    reason: '사진에 바닥이 보이지 않습니다',
    object_path: 'b1/u1/photo.jpg',
    display_name: '김철수',
    winner_id: '00000000-0000-0000-0000-000000000000',
    ai_model: 'gemini-2.5-flash',
  };
  const forbidden = ['사진에 바닥', 'photo.jpg', '김철수', '00000000', 'gemini'];

  for (const kind of ['matched', 'finished', 'voided', 'submitted', 'judge_turn', 'cancelled', 'deadline_soon']) {
    const text = notificationText(kind, dirty, now);
    if (text === null) throw new Error(`${kind} 문구가 없다`);
    for (const needle of forbidden) {
      assertEquals(text.title.includes(needle), false, `${kind} 제목에 ${needle}`);
      assertEquals(text.body.includes(needle), false, `${kind} 본문에 ${needle}`);
    }
  }
});

Deno.test('제목이 비어 있어도 문구가 깨지지 않는다', () => {
  assertEquals(notificationText('voided', {}, now)?.body, '「대결」 점수와 전적에 반영되지 않아요.');
});
