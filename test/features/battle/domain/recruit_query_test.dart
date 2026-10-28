import 'package:flutter_test/flutter_test.dart';

import 'package:todododo/core/strings.dart';
import 'package:todododo/features/battle/domain/recruit_query.dart';

void main() {
  group('조건 → 서버 인자', () {
    test('전체는 조건 없음(null)으로 보낸다', () {
      expect(RecruitTypeFilter.all.serverValue, isNull);
      expect(RecruitDurationBand.all.serverValue, isNull);
    });

    test('유형·기간대 키는 서버가 받는 값 그대로다', () {
      expect(RecruitTypeFilter.speed.serverValue, 'speed');
      expect(RecruitTypeFilter.quality.serverValue, 'quality');
      expect(RecruitDurationBand.quick.serverValue, 'quick');
      expect(RecruitDurationBand.day.serverValue, 'day');
      expect(RecruitDurationBand.multi.serverValue, 'multi');
    });

    test('검색어가 비었으면 null로 보낸다(조건 없음과 같다)', () {
      expect(const RecruitQuery().serverQuery, isNull);
      expect(const RecruitQuery(query: '설거지').serverQuery, '설거지');
    });

    // 분 경계는 서버만 안다. 라벨은 환산 없이 경계를 그대로 말한다.
    test('기간대 라벨은 사용자가 분을 환산하지 않아도 되는 구간 이름이다', () {
      expect(RecruitDurationBand.all.label, AppStrings.battleFilterAll);
      expect(RecruitDurationBand.quick.label, '1시간 안');
      expect(RecruitDurationBand.day.label, '하루 안');
      expect(RecruitDurationBand.multi.label, '며칠');
    });

    test('유형 라벨은 앱의 다른 화면과 같은 문자열을 쓴다', () {
      expect(RecruitTypeFilter.speed.label, AppStrings.battleTypeSpeed);
      expect(RecruitTypeFilter.quality.label, AppStrings.battleTypeQuality);
    });
  });

  group('조건이 걸려 있는지', () {
    test('기본값은 아무 조건도 아니다', () {
      expect(const RecruitQuery().hasAnyCondition, isFalse);
    });

    test('검색어·유형·기간대 중 하나라도 있으면 조건이 걸린 것이다', () {
      expect(const RecruitQuery(query: '설거지').hasAnyCondition, isTrue);
      expect(
        const RecruitQuery(type: RecruitTypeFilter.speed).hasAnyCondition,
        isTrue,
      );
      expect(
        const RecruitQuery(band: RecruitDurationBand.day).hasAnyCondition,
        isTrue,
      );
    });

    // 같은 조건으로 다시 읽지 않기 위한 비교다(한글 IME는 조합 중에도 입력 이벤트를 쏜다).
    test('같은 조건은 같다고 본다', () {
      const a = RecruitQuery(query: '설거지', type: RecruitTypeFilter.speed);
      const b = RecruitQuery(query: '설거지', type: RecruitTypeFilter.speed);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == a.copyWith(band: RecruitDurationBand.quick), isFalse);
    });
  });

  group('빈 상태 성격', () {
    test('카드가 있으면 빈 상태가 아니다', () {
      expect(
        recruitEmptyKind(hasItems: true, hasAnyCondition: true),
        RecruitEmptyKind.none,
      );
    });

    test('조건이 없는데 비었으면 "아직 모집이 없다"다', () {
      expect(
        recruitEmptyKind(hasItems: false, hasAnyCondition: false),
        RecruitEmptyKind.noRecruits,
      );
    });

    test('조건이 걸린 채 비었으면 "조건에 맞는 모집이 없다"다', () {
      expect(
        recruitEmptyKind(hasItems: false, hasAnyCondition: true),
        RecruitEmptyKind.noMatches,
      );
    });
  });
}
