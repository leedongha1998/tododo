import '../../../core/strings.dart';

/// 모집 목록을 좁히는 조건과, 그 조건이 만든 빈 상태를 읽는 순수 함수들.
///
/// 걸러내기는 전부 서버가 한다. 이 파일이 가진 것은 **서버에 보낼 키**와 **사용자에게 보일 라벨**뿐이고,
/// 유형 비교나 분 단위 경계 같은 판단은 들어 있지 않다 — 그 판단을 Dart에 복제하면 서버와 어긋날 수 있고,
/// 클라이언트가 받은 묶음을 다시 걸러내는 길이 열린다.

/// 유형 축. 기본값은 전체다.
enum RecruitTypeFilter {
  all(null, AppStrings.battleFilterAll),
  speed('speed', AppStrings.battleTypeSpeed),
  quality('quality', AppStrings.battleTypeQuality);

  const RecruitTypeFilter(this.serverValue, this.label);

  /// 서버 인자 `p_type`. 전체는 null(조건 없음)이다.
  final String? serverValue;
  final String label;
}

/// 기간대 축. **분 경계는 담지 않는다** — 경계는 서버 함수만 안다.
/// 라벨이 경계를 숫자로 말하는 이유: "짧은 대결"은 얼마가 짧은지 사용자가 다시 추측해야 한다.
enum RecruitDurationBand {
  all(null, AppStrings.battleFilterAll),
  quick('quick', AppStrings.battleDurationBandQuick),
  day('day', AppStrings.battleDurationBandDay),
  multi('multi', AppStrings.battleDurationBandMulti);

  const RecruitDurationBand(this.serverValue, this.label);

  /// 서버 인자 `p_duration_band`. 전체는 null(조건 없음)이다.
  final String? serverValue;
  final String label;
}

/// 지금 **적용된** 조건 한 벌. 입력 중인 글자가 아니라 서버에 보낸(보낼) 값이다.
class RecruitQuery {
  const RecruitQuery({
    this.query = '',
    this.type = RecruitTypeFilter.all,
    this.band = RecruitDurationBand.all,
  });

  /// 앞뒤 공백을 떼고 보관한다. 서버도 `btrim`하므로 공백만 다른 입력은 같은 조건이다.
  final String query;
  final RecruitTypeFilter type;
  final RecruitDurationBand band;

  /// 서버 인자 `p_query`. 비었으면 null(조건 없음)로 보낸다.
  String? get serverQuery => query.isEmpty ? null : query;

  /// 조건이 하나라도 걸려 있는지. 빈 상태 문구와 `조건 지우기` 표시를 가른다.
  bool get hasAnyCondition =>
      query.isNotEmpty ||
      type != RecruitTypeFilter.all ||
      band != RecruitDurationBand.all;

  RecruitQuery copyWith({
    String? query,
    RecruitTypeFilter? type,
    RecruitDurationBand? band,
  }) {
    return RecruitQuery(
      query: query ?? this.query,
      type: type ?? this.type,
      band: band ?? this.band,
    );
  }

  // 같은 조건으로 다시 읽지 않기 위한 비교다(한글 IME는 자모 조합 중에도 입력 이벤트를 쏜다).
  @override
  bool operator ==(Object other) {
    return other is RecruitQuery &&
        other.query == query &&
        other.type == type &&
        other.band == band;
  }

  @override
  int get hashCode => Object.hash(query, type, band);
}

/// 목록이 비었을 때의 성격. 사용자가 다음에 할 일이 다르기 때문에 나눈다.
/// 세 번째 빈 상태(불러오기 실패)는 `AsyncValue.error`가 고르므로 여기 없다.
enum RecruitEmptyKind {
  /// 빈 상태가 아니다(그릴 카드가 있다).
  none,

  /// 올라온 모집이 하나도 없다 → 내가 먼저 걸어 보라고 권한다.
  noRecruits,

  /// 조건이 좁아서 비었다 → 조건을 되돌리라고 권한다(여기서 대결 만들기를 권하지 않는다).
  noMatches,
}

RecruitEmptyKind recruitEmptyKind({
  required bool hasItems,
  required bool hasAnyCondition,
}) {
  if (hasItems) return RecruitEmptyKind.none;
  return hasAnyCondition
      ? RecruitEmptyKind.noMatches
      : RecruitEmptyKind.noRecruits;
}
