import 'package:flutter/widgets.dart';

import '../../../core/strings.dart';
import '../../../core/theme/app_icons.dart';

/// 알림함 한 줄이 말하는 것 — 사건 문구(주) + 대결 제목(부) + 아이콘.
///
/// 시각은 줄마다 다른 축이라 여기 담지 않는다(화면이 `AppStrings.notificationTime`으로 그린다).
///
/// **`domain`인데 `IconData`를 든다** — 이 저장소에서 아이콘 선택은 보통 presentation의 몫이다
/// (2026-11-13 리뷰 지적). 그럼에도 여기 둔 이유: `finished`의 아이콘이 `outcome`(승/무/패)으로
/// 갈리므로 presentation으로 내리면 **같은 outcome switch가 두 곳에 생기거나**, 아이콘을 가리키는
/// 열거형을 하나 더 만들어 그것을 다시 아이콘으로 옮겨야 한다 — 둘 다 이 매핑을 한 곳에 모아 둔
/// 지금보다 틀리기 쉽다. `IconData`는 위젯이 아니라 순수 데이터이고 테스트가 7종 전부를 고정한다.
/// **이 예외를 다른 domain 파일로 넓히지 말 것.**
class NotificationLine {
  const NotificationLine({required this.text, required this.title, required this.icon});

  /// 사건 문구. `finished`에서는 점수 조각이 ` · `로 붙는다.
  final String text;

  /// 대결 제목. payload에 없거나 빈 문자열이면 `대결`로 대체된다.
  final String title;

  final IconData icon;
}

/// payload에서 대결 제목을 꺼낸다. 서버 문구가 `'「대결」'`로 대체하는 것과 같은 방어다.
String _titleOf(Map<String, dynamic> payload) {
  final value = payload['title'];
  final text = value is String ? value.trim() : '';
  return text.isEmpty ? AppStrings.notificationFallbackTitle : text;
}

/// 점수 변화 한 조각. **0은 `0점`이라고 적지 않는다** — 하한(점수는 0점 아래로 내려가지 않는다)에
/// 걸린 경우라 `-3점`이라고 해 놓고 점수가 그대로이면 규칙을 잘못 배우게 된다. 서버 문구가
/// 같은 이유로 문장을 바꾸는 것과 같은 처리다.
///
/// 하한 설명("점수는 0점 아래로 내려가지 않아요")은 줄에 붙이지 않는다 — 상세가 말한다.
String _scorePhrase(Object? delta) {
  final value = delta is num ? delta.toInt() : 0;
  if (value == 0) return AppStrings.notificationScoreUnchanged;
  return AppStrings.battleScoreDelta(value);
}

/// 종결 줄. 승/무/그 외(패)로 셋만 가른다 — 서버 푸시 문구와 같은 갈래라 두 자리가 어긋나지 않는다.
///
/// `forfeit`은 실제로는 오지 않는다(포기한 본인에게는 적재하지 않는다). 방어적으로 패로 둔다.
/// `completed_loss`의 감면 설명("기준을 통과해서 감점이 줄었어요")은 **일부러 빼고** 상세에 맡긴다.
NotificationLine _finishedLine(Map<String, dynamic> payload) {
  final outcome = payload['outcome'];
  final score = _scorePhrase(payload['score_delta']);
  final (String base, IconData icon) = switch (outcome) {
    'win' => (AppStrings.notificationFinishedWin, AppIcons.trophy),
    'draw' => (AppStrings.notificationFinishedDraw, AppIcons.hourglass),
    _ => (AppStrings.notificationFinishedLoss, AppIcons.lose),
  };
  return NotificationLine(text: '$base · $score', title: _titleOf(payload), icon: icon);
}

/// 원장의 kind와 payload로 알림함 줄을 만든다. **모르는 kind는 null**이고 부르는 쪽은 그 줄을
/// 그리지 않는다 — 뜻을 모르는 채로 글자를 띄우지 않는다(서버 `notification_text.ts`의
/// `default: return null`과 같은 태도). 체크 제약이 7종을 보장하므로 실제로는 오지 않는다.
///
/// **아는 키만 읽는다.** payload에 무엇이 들어 있든 아래에 적힌 키(`title`·`outcome`·`score_delta`)
/// 말고는 줄에 닿을 길이 자체가 없다 — 금지 항목(판정 사유·사진 경로·상대 표시 이름)을 걸러내는
/// 목록을 두지 않고 구조로 막는다.
///
/// **지금 기준으로 계산되는 값을 말하지 않는다.** `deadline_at`·`judge_deadline_at`이 payload에
/// 있어도 읽지 않는다. 알림함은 과거 사건의 기록이고, 그 마감은 이미 지났을 수 있어서 남은 시간을
/// 적으면 틀린 말이 된다. 현재 상태의 정답은 언제나 대결 상세다(design 원칙 4).
NotificationLine? notificationLine(String kind, Map<String, dynamic> payload) {
  return switch (kind) {
    'matched' => NotificationLine(
      text: AppStrings.notificationMatched,
      title: _titleOf(payload),
      icon: AppIcons.battle,
    ),
    'submitted' => NotificationLine(
      text: AppStrings.notificationSubmitted,
      title: _titleOf(payload),
      icon: AppIcons.camera,
    ),
    'judge_turn' => NotificationLine(
      text: AppStrings.notificationJudgeTurn,
      title: _titleOf(payload),
      icon: AppIcons.judge,
    ),
    'deadline_soon' => NotificationLine(
      text: AppStrings.notificationDeadlineSoon,
      title: _titleOf(payload),
      icon: AppIcons.clock,
    ),
    'finished' => _finishedLine(payload),
    'voided' => NotificationLine(
      text: AppStrings.notificationVoided,
      title: _titleOf(payload),
      icon: AppIcons.warning,
    ),
    'cancelled' => NotificationLine(
      text: AppStrings.notificationCancelled,
      title: _titleOf(payload),
      icon: AppIcons.close,
    ),
    _ => null,
  };
}

/// 사건이 일어난 시각 한 줄. 서버가 준 UTC를 기기 시간대로 바꿔 `11월 8일 오후 3:04`로.
///
/// `todo-due-date`의 `남음`/`지남` 표와 **섞지 않는다** — 그 표는 **기한**을 말하고, 이것은
/// 사건이 **언제 일어났는지**를 말한다(spec). `formatRemaining`·`formatDueLabel`을 쓰지 않는다.
String notificationTimeLabel(DateTime createdAt) {
  final local = createdAt.toLocal();
  final isAm = local.hour < 12;
  // 0시는 오전 12시, 12시는 오후 12시다.
  final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
  return AppStrings.notificationTime(
    month: local.month,
    day: local.day,
    isAm: isAm,
    hour12: hour12,
    minute: local.minute,
  );
}
