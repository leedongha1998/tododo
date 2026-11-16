import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/core/strings.dart';
import 'package:todododo/core/theme/app_icons.dart';
import 'package:todododo/features/notification/domain/notification_line.dart';

/// 알림함 줄 문구(notification-inbox design 4장의 매핑 표 = 정답).
///
/// 이 표가 서버 푸시 문구(`supabase/functions/_shared/notification_text.ts`)와 **같은 사실**을
/// 말하는지가 spec의 요구다. 그래서 여기서 고정하는 것은 세 가지다 —
/// (1) 7종 kind가 모두 뜻대로 매핑된다, (2) 아는 키만 읽는다(금지 값이 줄에 닿지 않는다),
/// (3) 지금 기준으로 계산되는 값(남은 시간)을 말하지 않는다.
void main() {
  group('kind 7종 매핑', () {
    test('matched', () {
      final line = notificationLine('matched', {'title': '아침 달리기', 'battle_type': 'speed'});
      expect(line!.text, AppStrings.notificationMatched);
      expect(line.title, '아침 달리기');
      expect(line.icon, AppIcons.battle);
    });

    test('submitted', () {
      final line = notificationLine('submitted', {'title': '방 청소', 'battle_type': 'quality'});
      expect(line!.text, AppStrings.notificationSubmitted);
      expect(line.icon, AppIcons.camera);
    });

    test('judge_turn', () {
      final line = notificationLine('judge_turn', {'title': '방 청소'});
      expect(line!.text, AppStrings.notificationJudgeTurn);
      expect(line.icon, AppIcons.judge);
    });

    test('deadline_soon', () {
      final line = notificationLine('deadline_soon', {'title': '방 청소'});
      expect(line!.text, AppStrings.notificationDeadlineSoon);
      expect(line.icon, AppIcons.clock);
    });

    test('voided', () {
      final line = notificationLine('voided', {'title': '설거지'});
      expect(line!.text, AppStrings.notificationVoided);
      expect(line.icon, AppIcons.warning);
    });

    test('cancelled', () {
      final line = notificationLine('cancelled', {'title': '설거지'});
      expect(line!.text, AppStrings.notificationCancelled);
      expect(line.icon, AppIcons.close);
    });

    test('모르는 kind는 줄을 그리지 않는다', () {
      expect(notificationLine('friend_request', {'title': '무엇'}), isNull);
      expect(notificationLine('', const {}), isNull);
    });
  });

  group('finished — outcome 5종 x 점수 변화', () {
    NotificationLine lineOf(String outcome, int delta) =>
        notificationLine('finished', {
          'title': '아침 달리기',
          'outcome': outcome,
          'score_delta': delta,
        })!;

    test('win은 이겼어요 + 트로피', () {
      final line = lineOf('win', 3);
      expect(line.text, '${AppStrings.notificationFinishedWin} · +3점');
      expect(line.icon, AppIcons.trophy);
    });

    test('draw는 무승부예요 + 모래시계', () {
      final line = lineOf('draw', -1);
      expect(line.text, '${AppStrings.notificationFinishedDraw} · -1점');
      expect(line.icon, AppIcons.hourglass);
    });

    test('completed_loss·loss·forfeit은 모두 졌어요 + 하향 화살표', () {
      for (final outcome in ['completed_loss', 'loss', 'forfeit']) {
        final line = lineOf(outcome, -1);
        expect(line.text, '${AppStrings.notificationFinishedLoss} · -1점', reason: outcome);
        expect(line.icon, AppIcons.lose, reason: outcome);
      }
    });

    test('completed_loss에 감면 설명을 붙이지 않는다(상세가 말한다)', () {
      expect(lineOf('completed_loss', -1).text, isNot(contains('감점')));
    });

    test('점수 변화가 0이면 "0점"이 아니라 "점수 변화 없음"이다(하한에 걸린 경우)', () {
      final line = lineOf('loss', 0);
      expect(line.text, '${AppStrings.notificationFinishedLoss} · ${AppStrings.notificationScoreUnchanged}');
      expect(line.text, isNot(contains('0점')));
    });

    test('score_delta가 없거나 숫자가 아니면 0으로 읽는다', () {
      expect(
        notificationLine('finished', {'title': '달리기', 'outcome': 'win'})!.text,
        '${AppStrings.notificationFinishedWin} · ${AppStrings.notificationScoreUnchanged}',
      );
      expect(
        notificationLine('finished', {'title': '달리기', 'outcome': 'win', 'score_delta': '3'})!.text,
        '${AppStrings.notificationFinishedWin} · ${AppStrings.notificationScoreUnchanged}',
      );
    });

    test('outcome이 없거나 모르는 값이면 패로 읽는다(서버 문구와 같은 갈래)', () {
      expect(notificationLine('finished', {'title': '달리기'})!.text, contains(AppStrings.notificationFinishedLoss));
      expect(
        notificationLine('finished', {'title': '달리기', 'outcome': 'unknown'})!.text,
        contains(AppStrings.notificationFinishedLoss),
      );
    });

    test('하한 설명 문장을 줄에 붙이지 않는다', () {
      expect(lineOf('loss', 0).text, isNot(contains('0점 아래')));
    });
  });

  group('대결 제목', () {
    test('없음·빈 문자열·공백만이면 "대결"로 대체된다', () {
      for (final payload in <Map<String, dynamic>>[
        {},
        {'title': ''},
        {'title': '   '},
        {'title': null},
        {'title': 42},
      ]) {
        expect(
          notificationLine('matched', payload)!.title,
          AppStrings.notificationFallbackTitle,
          reason: '$payload',
        );
      }
    });

    test('앞뒤 공백은 다듬는다', () {
      expect(notificationLine('matched', {'title': '  아침 달리기 '})!.title, '아침 달리기');
    });
  });

  group('아는 키만 읽는다 — 금지 값이 줄에 닿지 않는다', () {
    // 서버 `notification_text_test.ts`의 같은 검사와 짝이다. payload에 들어 있어도
    // 줄에 나타날 길이 자체가 없어야 한다(걸러내는 목록을 두지 않고 구조로 막는다).
    const forbidden = {
      'reason': '사진이 흐려서 기준을 통과하지 못했습니다',
      'verdict_reason': '우열 기준에서 더 깔끔했습니다',
      'object_path': 'battle_evidence/abc/def.jpg',
      'display_name': '김상대',
      'winner_id': 'c0ffee00-0000-0000-0000-000000000000',
    };

    test('7종 어느 줄에도 금지 값이 나타나지 않는다', () {
      for (final kind in [
        'matched',
        'submitted',
        'judge_turn',
        'deadline_soon',
        'finished',
        'voided',
        'cancelled',
      ]) {
        final line = notificationLine(kind, {
          'title': '아침 달리기',
          'battle_type': 'speed',
          'outcome': 'win',
          'score_delta': 3,
          ...forbidden,
        })!;
        for (final value in forbidden.values) {
          expect(line.text, isNot(contains(value)), reason: kind);
          expect(line.title, isNot(contains(value)), reason: kind);
        }
      }
    });
  });

  group('지금 기준으로 계산되는 값을 말하지 않는다 (design 원칙 4)', () {
    test('deadline_at·judge_deadline_at이 있어도 줄에 숫자가 없다', () {
      for (final kind in ['matched', 'judge_turn', 'deadline_soon', 'submitted']) {
        final line = notificationLine(kind, {
          'title': '아침 달리기',
          'battle_type': 'speed',
          'deadline_at': '2026-11-14T03:00:00+00:00',
          'judge_deadline_at': '2026-11-15T03:00:00+00:00',
        })!;
        expect(line.text, isNot(matches(RegExp(r'\d'))), reason: kind);
        expect(line.text, isNot(contains('남았')), reason: kind);
        expect(line.text, isNot(contains('자동 승인')), reason: kind);
      }
    });
  });

  group('시각 표기', () {
    test("'11월 8일 오후 3:04' 꼴이다", () {
      expect(notificationTimeLabel(DateTime(2026, 11, 8, 15, 4)), '11월 8일 오후 3:04');
    });

    test('분이 한 자리면 0을 채운다', () {
      expect(notificationTimeLabel(DateTime(2026, 11, 8, 15, 4)), endsWith('3:04'));
      expect(notificationTimeLabel(DateTime(2026, 11, 8, 9, 0)), '11월 8일 오전 9:00');
    });

    test('자정은 오전 12시, 정오는 오후 12시다', () {
      expect(notificationTimeLabel(DateTime(2026, 1, 1, 0, 30)), '1월 1일 오전 12:30');
      expect(notificationTimeLabel(DateTime(2026, 1, 1, 12, 0)), '1월 1일 오후 12:00');
      expect(notificationTimeLabel(DateTime(2026, 1, 1, 23, 59)), '1월 1일 오후 11:59');
    });

    test('연도를 적지 않는다', () {
      expect(notificationTimeLabel(DateTime(2025, 3, 2, 8, 5)), '3월 2일 오전 8:05');
    });

    test('UTC로 받은 시각은 기기 시간대로 바꿔 말한다', () {
      final utc = DateTime.utc(2026, 11, 8, 6, 4);
      expect(notificationTimeLabel(utc), notificationTimeLabel(utc.toLocal()));
    });
  });
}
