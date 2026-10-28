import 'open_recruit.dart';

/// 한 번에 받는 모집 묶음의 크기. 서버 상한은 50이다.
const openRecruitPageSize = 20;

/// 다음 묶음을 어디서부터 받을지. 서버가 준 문자열을 **그대로** 보관한다.
///
/// `DateTime`으로 파싱하지 않는 이유: 파싱·재직렬화를 거치며 정밀도가 깎이거나 포맷이 바뀌면
/// 서버의 `(created_at, id) < (커서)` 비교의 경계가 흔들려 그 사이 행이 조용히 빠지거나 두 번 나온다.
/// 이 기능에서 가장 조용하게 깨지는 지점이라 날 것 그대로 들고 되돌려 보낸다
/// (`Battle.createdAt`은 화면 표시용으로 파싱해 쓰고, 커서로는 쓰지 않는다).
class RecruitCursor {
  const RecruitCursor({required this.createdAt, required this.id});

  final String createdAt;
  final String id;

  @override
  bool operator ==(Object other) =>
      other is RecruitCursor &&
      other.createdAt == createdAt &&
      other.id == id;

  @override
  int get hashCode => Object.hash(createdAt, id);
}

/// 서버가 돌려준 한 묶음. 커서로 쓸 값이 행 안에 이미 있으므로 포장 객체를 따로 받지 않고
/// 묶음을 받은 자리에서 뽑아낸다.
class OpenRecruitPage {
  const OpenRecruitPage({
    required this.items,
    required this.nextCursor,
    required this.hasMore,
  });

  const OpenRecruitPage.empty()
      : items = const [],
        nextCursor = null,
        hasMore = false;

  final List<OpenRecruit> items;
  final RecruitCursor? nextCursor;

  /// 받은 건수가 요청한 묶음 크기와 같으면 "더 있을 수 있다"로 둔다. 마지막 묶음이 정확히
  /// 꽉 찼으면 다음 호출이 0건을 받고 그때 false가 된다 — 빈 요청 한 번이 드는 대신 서버가
  /// count를 세거나 한 건을 더 읽는 일을 하지 않는다. 중복·누락과는 무관하다.
  final bool hasMore;

  /// RPC가 돌려준 행 목록 → 묶음. 행 순서(서버의 최신순)를 바꾸지 않는다.
  factory OpenRecruitPage.fromRows(List<dynamic> rows, int limit) {
    final items = rows
        .map((row) => OpenRecruit.fromMap(Map<String, dynamic>.from(row as Map)))
        .toList();
    RecruitCursor? cursor;
    if (rows.isNotEmpty) {
      final last = Map<String, dynamic>.from(rows.last as Map);
      final battle = Map<String, dynamic>.from(last['battle'] as Map);
      cursor = RecruitCursor(
        createdAt: battle['created_at'] as String,
        id: battle['id'] as String,
      );
    }
    return OpenRecruitPage(
      items: items,
      nextCursor: cursor,
      hasMore: rows.length == limit,
    );
  }
}
