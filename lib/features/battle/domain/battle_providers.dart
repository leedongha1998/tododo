import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_init.dart';
import '../data/battle.dart';
import '../data/battle_criteria_repository.dart';
import '../data/battle_participant.dart';
import '../data/battle_repository.dart';
import '../data/criteria_check_result.dart';
import '../data/evidence_camera.dart';
import '../data/open_recruit.dart';
import '../data/player_card.dart';
import '../data/vs_intro_seen_store.dart';
import 'battle_detail.dart';
import 'battle_summary.dart';

final battleRepositoryProvider = Provider<BattleRepository>((ref) {
  return BattleRepository(supabase);
});

final battleCriteriaRepositoryProvider = Provider<BattleCriteriaRepository>((ref) {
  return BattleCriteriaRepository(supabase);
});

/// 오늘 남은 기준 생성 횟수와 모집·대결 한도. 대결 만들기 화면의 사전 안내용.
final myLimitsProvider = FutureProvider.autoDispose<MyLimits>((ref) {
  return ref.watch(battleRepositoryProvider).fetchMyLimits();
});

// 대결 목록류 provider는 화면을 떠나면 캐시를 비우는 autoDispose를 쓴다.
// 그래야 상대가 참가/제출하는 등 서버 쪽 변화가 있어도 화면에 다시 들어올 때 최신 상태를 가져온다.
final openRecruitsProvider = FutureProvider.autoDispose<List<OpenRecruit>>((ref) {
  return ref.watch(battleRepositoryProvider).fetchOpenRecruits();
});

/// 상대·모집 생성자의 전적 카드. 서버가 공개 범위를 막으므로 임의 사용자로는 실패한다.
final playerCardProvider = FutureProvider.autoDispose.family<PlayerCard, String>((ref, userId) {
  return ref.watch(battleRepositoryProvider).fetchPlayerCard(userId);
});

final myRecruitsProvider = FutureProvider.autoDispose<List<Battle>>((ref) async {
  return ref.watch(battleRepositoryProvider).fetchMyRecruits();
});

final myBattlesProvider = FutureProvider.autoDispose<List<BattleSummary>>((ref) async {
  final repo = ref.watch(battleRepositoryProvider);
  final myId = supabase.auth.currentUser!.id;
  final battles = await repo.fetchMyBattles();
  final otherIds = battles.map((b) => b.creatorId == myId ? b.opponentId! : b.creatorId);
  final names = await repo.fetchDisplayNames(otherIds);
  // 카드의 상태 줄이 "상대가 제출했다 / 판정할 차례다"를 말하려면 양쪽 요약 행이 필요하다.
  final participants = await repo.fetchParticipantsOf(battles.map((b) => b.id));

  BattleParticipant? participantOf(String battleId, String userId) {
    for (final participant in participants) {
      if (participant.battleId == battleId && participant.userId == userId) return participant;
    }
    return null;
  }

  return battles.map((b) {
    final otherId = b.creatorId == myId ? b.opponentId! : b.creatorId;
    return BattleSummary(
      battle: b,
      otherPartyName: names[otherId] ?? '알 수 없음',
      me: participantOf(b.id, myId),
      opponent: participantOf(b.id, otherId),
    );
  }).toList();
});

final battleDetailProvider = FutureProvider.autoDispose.family<BattleDetail, String>((ref, battleId) async {
  final repo = ref.watch(battleRepositoryProvider);
  final myId = supabase.auth.currentUser!.id;
  final battle = await repo.fetchBattle(battleId);
  final participants = await repo.fetchParticipants(battleId);
  final me = participants.firstWhere((p) => p.userId == myId);
  final opponent = participants.firstWhere((p) => p.userId != myId);
  final names = await repo.fetchDisplayNames([me.userId, opponent.userId]);
  // 판정 창 전에는 내 제출만 돌아온다. 상대 것을 가리는 일은 서버(RLS)가 한다.
  final submissions = await repo.fetchSubmissions(battleId);
  return BattleDetail(
    battle: battle,
    me: me,
    opponent: opponent,
    myName: names[me.userId] ?? '나',
    opponentName: names[opponent.userId] ?? '알 수 없음',
    submissions: submissions,
  );
});

/// 증거 사진 촬영(카메라 전용). 위젯 테스트에서 가짜로 바꿀 수 있게 provider로 둔다.
final evidenceCameraProvider = Provider<EvidenceCamera>((ref) => const EvidenceCamera());

/// 증거 사진의 짧은 수명 서명 URL. 발급도 Storage 조회 정책을 거치므로,
/// 진행 중 상대 사진은 여기서 실패한다(서버가 가린다).
final evidencePhotoUrlProvider = FutureProvider.autoDispose.family<String, String>((ref, path) {
  return ref.watch(battleRepositoryProvider).createEvidencePhotoUrl(path);
});

/// VS 인트로 "봤음" 기록. 위젯 테스트에서 가짜로 바꿀 수 있게 provider로 둔다.
final vsIntroSeenStoreProvider = Provider<VsIntroSeenStore>((ref) => const VsIntroSeenStore());
