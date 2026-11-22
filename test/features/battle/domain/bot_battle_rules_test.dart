import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:todododo/core/strings.dart';
import 'package:todododo/features/battle/domain/bot_battle_rules.dart';
import 'package:todododo/features/battle/domain/submission_rules.dart';

PostgrestException _rpcError(String hint) =>
    PostgrestException(message: '서버 메시지', hint: hint);

void main() {
  group('결과 부제는 서버가 기록한 outcome에서 고른다', () {
    test('승·완료한 패배·완료 못 한 패배가 각각 다른 문장이다', () {
      // 봇전은 세 결과의 점수가 +1 / -1 / -1이라 **완료한 패배와 미착수가 점수로 구분되지
      // 않는다**(오너 결정 5). 그 차이를 말하는 것은 이 문장뿐이다.
      expect(botResultSubtitle('win'), AppStrings.botBattleWon);
      expect(botResultSubtitle('completed_loss'), AppStrings.botBattleCompletedLoss);
      expect(botResultSubtitle('loss'), AppStrings.botBattleLossNoSubmission);
    });

    test('포기와 진행 중에는 봇전 전용 문장을 주지 않는다', () {
      // 포기는 사람 대결과 같은 문구를 쓰고(화면이 먼저 고른다), 진행 중에는 결과가 없다.
      expect(botResultSubtitle('forfeit'), isNull);
      expect(botResultSubtitle(null), isNull);
    });
  });

  group('시작 실패 문구', () {
    test('하루 3회 소진과 쓸 수 없는 주제를 구분해 말한다', () {
      expect(
        botBattleStartErrorMessage(_rpcError('BOT_DAILY_LIMIT')),
        AppStrings.botBattleErrorDailyLimit,
      );
      expect(
        botBattleStartErrorMessage(_rpcError('BOT_TOPIC_INVALID')),
        AppStrings.botBattleErrorTopicInvalid,
      );
    });

    test('모르는 실패는 서버 메시지를 보여 주지 않고 공통 문구로 말한다', () {
      expect(botBattleStartErrorMessage(Exception('네트워크')), AppStrings.botBattleStartFailed);
      expect(botBattleStartErrorMessage(_rpcError('WHAT')), AppStrings.botBattleStartFailed);
    });
  });

  group('교체 잠김의 이유가 대결 종류에 따라 갈린다', () {
    test('봇전은 "봇이 완료해서", 사람 대결은 기존 문구', () {
      final locked = _rpcError('SUBMISSION_LOCKED');
      expect(
        submissionErrorMessage(locked, isBot: true),
        AppStrings.botBattleErrorSubmissionLocked,
      );
      expect(submissionErrorMessage(locked), AppStrings.battleErrorSubmissionLocked);
    });

    test('마감·촬영 시각 거부는 봇전에서도 같은 문구다', () {
      // 사용자 쪽 증거 규칙은 봇전에서 한 글자도 바뀌지 않는다.
      for (final code in const ['DEADLINE_PASSED', 'CAPTURED_BEFORE_START', 'CAPTURE_TIME_MISMATCH']) {
        expect(
          submissionErrorMessage(_rpcError(code), isBot: true),
          submissionErrorMessage(_rpcError(code)),
          reason: code,
        );
      }
    });
  });
}
