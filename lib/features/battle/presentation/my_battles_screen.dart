import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/app_tab.dart';
import '../../../core/strings.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/app_button_styles.dart';
import '../../../core/widgets/app_panel.dart';
import '../../../core/widgets/app_tag.dart';
import '../../../core/widgets/keep_words_text.dart';
import '../../../core/widgets/status_message.dart';
import '../data/battle.dart';
import '../domain/battle_providers.dart';
import '../domain/battle_summary.dart';
import 'battle_chips.dart';
import 'battle_summary_list.dart';
import 'edit_recruit_criteria_screen.dart';

/// `내 대결` 탭. "내가 지금 걸어 둔 것 전부"가 모이는 자리다.
///
/// 두 구역을 **섞지 않는다.** 모집 중은 "기다린다 / 고친다 / 취소한다"이고 상대도 마감도 없으며,
/// 진행 중은 "사진을 낸다 / 상대 증거를 판정한다"이고 마감이 흐른다. 같은 카드 모양으로 끼워 넣으면
/// 상대·상태 줄이 빈칸이 되어 목록이 말하려는 것이 흐려진다.
/// 끝난 대결은 지금처럼 프로필 전적으로 간다.
class MyBattlesScreen extends ConsumerWidget {
  const MyBattlesScreen({super.key});

  /// 모집 취소. **한 번 확인받는다**(2026-11-12 오너 확정).
  ///
  /// 카드의 두 동작이 아이콘만 남으면서 "모집 취소"라는 글자가 사라졌다. 글자가 있을 때는 누른
  /// 자각이 있었지만 아이콘만으로는 오탭 한 번에 모집이 없어지고, 그 모집의 AI 판정 기준도 함께
  /// 사라진다(다시 올리려면 기준을 새로 만들어야 한다). 포기(`_forfeit`)와 같은 급으로 다룬다.
  Future<void> _cancel(
    BuildContext context,
    WidgetRef ref,
    String battleId,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const KeepWordsText(AppStrings.battleRecruitCancelConfirmTitle),
        content: const KeepWordsText(AppStrings.battleRecruitCancelConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const KeepWordsText(AppStrings.cancel),
          ),
          FilledButton(
            style: AppButtonStyles.danger,
            onPressed: () => Navigator.of(context).pop(true),
            child: const KeepWordsText(AppStrings.battleRecruitCancel),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(battleRepositoryProvider).cancelBattle(battleId);
      ref.invalidate(myRecruitsProvider);
      ref.invalidate(myLimitsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: KeepWordsText(AppStrings.battleRecruitCancelled)),
        );
      }
    } catch (e) {
      debugPrint('cancelBattle failed: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: KeepWordsText(AppStrings.battleRecruitCancelFailed)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final battlesAsync = ref.watch(myBattlesProvider);
    final recruitsAsync = ref.watch(myRecruitsProvider);
    final recruits = recruitsAsync.value ?? const <Battle>[];

    return Scaffold(
      appBar: AppBar(title: const KeepWordsText(AppStrings.battleMyBattles)),
      // 빈 상태와 에러까지 감싸야 한다. 목록이 비었을 때야말로 새로고침이 필요하다.
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(myRecruitsProvider);
          ref.invalidate(myLimitsProvider);
          final refreshed = ref.refresh(myBattlesProvider.future);
          try {
            await refreshed;
          } catch (error) {
            debugPrint('myBattlesProvider refresh failed: $error');
          }
        },
        child: ListView(
          // 목록이 비었을 때도 당겨지게 한다.
          physics: const AlwaysScrollableScrollPhysics(),
          // 화면 가장자리 20, 구역 사이 24(redesign design 4.1).
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            ..._buildRecruitSection(context, ref, recruitsAsync),
            ..._buildBattleSection(context, ref, battlesAsync, recruits),
          ],
        ),
      ),
    );
  }

  /// 구역 A — 내가 등록한 모집. 0건이면 구역 자체가 보이지 않고, 한 구역의 실패가 다른 구역을
  /// 가리지 않는다.
  ///
  /// **머리글은 박스 밖에 하나만 둔다**(2026-11-12 오너 확정). 전에는 `AppPanel.flat(title:)`로
  /// 카드 안 첫 줄에 있었는데, 모집 수 제한이 2026-11-06에 없어져 모집이 여러 건일 수 있게 되자
  /// 카드마다 같은 제목이 반복됐다. 밖으로 빼면 머리글 하나 + 카드 N장이다.
  List<Widget> _buildRecruitSection(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<Battle>> recruitsAsync,
  ) {
    // 이전 값이 남아 있어도 실패를 숨기지 않는다(riverpod은 실패해도 직전 값을 들고 있다).
    // 모집은 취소·매칭으로 사라지는 것이라, 낡은 값을 그대로 두면 없는 모집에 기준 수정을 시도하게 된다.
    if (recruitsAsync.hasError) {
      debugPrint('myRecruitsProvider error: ${recruitsAsync.error}');
      // 실패에는 머리글을 함께 둔다 — 무엇을 못 불러왔는지 말해 주는 것이 머리글이다.
      // (불러오는 중에는 두지 않는다. 모집이 0건이면 구역이 사라지므로 머리글만 한 번 번쩍인다.)
      return [
        _sectionHeader(context, AppStrings.battleMyRecruits),
        StatusMessage.error(
          message: AppStrings.battleLoadRecruitsFailed,
          action: TextButton(
            onPressed: () => ref.invalidate(myRecruitsProvider),
            child: const KeepWordsText(AppStrings.retry),
          ),
        ),
        const SizedBox(height: 24),
      ];
    }

    final recruits = recruitsAsync.value;
    if (recruits == null) {
      return const [StatusMessage.loading(), SizedBox(height: 24)];
    }
    if (recruits.isEmpty) return const [];

    return [
      // 머리글이 "여기부터 다른 성격"을 말하므로 구분선을 따로 긋지 않는다.
      _sectionHeader(context, AppStrings.battleMyRecruits),
      for (var i = 0; i < recruits.length; i++) ...[
        // 카드 사이 12, 구역 사이 24(redesign design 4.1).
        if (i > 0) const SizedBox(height: 12),
        AppPanel.flat(
          // 위아래 8(좌우는 기본 16). 윗줄을 카드 위쪽에 더 붙이려고 줄였다 — 48dp 버튼은 그
          // 안에 아이콘을 가운데 두므로 이미 위쪽에 12dp 남짓의 여백을 갖고 있다.
          // 위아래가 같아야 제목이 정확히 가운데에 선다(`_MyRecruitBody` 주석의 산수).
          // 진행 중 카드와 **같은 값**을 쓴다(`myBattleCardPadding`).
          padding: myBattleCardPadding,
          child: _MyRecruitBody(
            battle: recruits[i],
            onCancel: () => _cancel(context, ref, recruits[i].id),
          ),
        ),
      ],
      const SizedBox(height: 24),
    ];
  }

  /// 구역 B — 진행 중인 대결. 카드와 상세 진입은 그대로다.
  ///
  /// **머리글을 둔다**(2026-11-12 오너 확정 — 전에는 "탭 이름이 이미 `내 대결`"이라고 두지
  /// 않았다). 모집 구역에만 이름이 있으면 나머지가 "그 밖의 것"으로 읽힌다. 다만 대결도 모집도
  /// 없는 첫 화면에는 두지 않는다 — 그 자리는 소개 블록과 "찾기로 가기"가 말하는 자리이고,
  /// 빈 목록에 이름을 붙이면 없는 것을 가리키는 머리글이 된다.
  List<Widget> _buildBattleSection(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<BattleSummary>> battlesAsync,
    List<Battle> recruits,
  ) {
    return [
      battlesAsync.when(
        data: (summaries) {
          if (summaries.isNotEmpty) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionHeader(context, AppStrings.battleMyActiveBattles),
                ...battleSummaryCards(summaries),
              ],
            );
          }
          // 모집 1건이 있으면 "비었다"가 아니다. 그 구역이 이미 "기다리는 중"을 말하고 있으므로
          // 찾기 탭으로 보내는 버튼을 두 번 권하지 않는다. 머리글은 둔다 — 한 줄짜리 안내가
          // 무엇에 대한 말인지를 머리글이 말한다.
          if (recruits.isNotEmpty) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionHeader(context, AppStrings.battleMyActiveBattles),
                KeepWordsText(
                  AppStrings.battleNoActiveBattlesYet,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            );
          }
          // 대결도 모집도 없을 때 할 일은 하나뿐이다 — 상대를 찾으러 가는 것.
          // 그 전에 이 앱이 무엇인지 세 줄로 말한다. 로그인 직후 첫 탭이 여기이고,
          // 새 계정이 설명을 만나는 자리가 어디에도 없다(동의 화면은 만들기·참가를 누른 뒤에야 뜬다).
          // 온보딩 화면·투어는 만들지 않는다 — 블록 한 장이면 되고 뒤로가기 경로가 늘지 않는다.
          return Column(
            children: [
              const AppPanel.tone(
                tone: AppTone.info,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    KeepWordsText(AppStrings.battleIntroMatching),
                    SizedBox(height: 8),
                    KeepWordsText(AppStrings.battleIntroEvidence),
                    SizedBox(height: 8),
                    KeepWordsText(AppStrings.battleIntroJudging),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              StatusMessage.empty(
                message: AppStrings.battleMyBattlesEmpty,
                detail: AppStrings.battleFinishedInProfile,
                action: FilledButton(
                  onPressed: () =>
                      ref.read(selectedTabProvider.notifier).select(AppTab.find),
                  child: const KeepWordsText(AppStrings.battleFind),
                ),
              ),
            ],
          );
        },
        loading: () => const StatusMessage.loading(),
        error: (error, stackTrace) {
          debugPrint('myBattlesProvider error: $error');
          return StatusMessage.error(
            message: AppStrings.battleLoadListFailed,
            action: TextButton(
              onPressed: () => ref.invalidate(myBattlesProvider),
              child: const KeepWordsText(AppStrings.retry),
            ),
          );
        },
      ),
    ];
  }
}

/// 구역 머리글. **박스 밖**에 둔다 — 카드 안에 두면 카드마다 같은 제목이 반복된다.
///
/// 글꼴은 `titleSmall`이다(선례: `create_battle_screen`의 `기간` 라벨). 아래 간격 8은
/// 머리글과 그 묶음을 한 덩어리로 묶는 거리이고, 구역 사이는 24다(redesign design 4.1).
Widget _sectionHeader(BuildContext context, String label) => Padding(
  padding: const EdgeInsets.only(bottom: 8),
  child: KeepWordsText(label, style: Theme.of(context).textTheme.titleSmall),
);

/// 모집 구역의 안쪽. 할 수 있는 일은 지금과 같다(기준 수정, 모집 취소) — 새 기능을 더하지 않는다.
class _MyRecruitBody extends StatelessWidget {
  const _MyRecruitBody({required this.battle, required this.onCancel});

  final Battle battle;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 맨 윗줄은 **곁들이는 정보와 두 동작**이다(2026-11-12 오너 확정 — 칩을 제목 위로,
        // 글자는 한 단계 작게). 제목은 그 아래 가운데로 내려온다.
        //
        // 칩이 작아진 이유: 제목보다 먼저 읽히는 자리에 제목과 같은 무게로 서 있으면 무엇이
        // 이 카드의 이름인지 흐려진다. readability.md 방안 2가 칩을 12 → 14로 키운 것은 칩이
        // 주 정보인 자리(진행 중 카드·찾기 목록)를 두고 한 결정이고 그쪽은 그대로다.
        //
        // 세로 정렬은 center다. start로 두면 버튼의 아이콘 중심이 24dp 칩의 중심보다
        // 아래에 놓여 어긋나 보인다.
        Row(
          children: [
            Expanded(
              // 칩 세 개가 좁은 화면·큰 글자에서 한 줄에 다 못 들어가면 빼지 않고 다음 줄로
              // 내린다(readability.md 3-1). 두 버튼이 가져가는 80dp만큼 그 여지가 줄었다.
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  BattleTypeBadge(type: battle.type, compact: true),
                  // 점선 = 빈 자리(아직 상대가 없다).
                  AppTag(
                    label: battleStatusLabel('pending'),
                    style: battleStatusTagStyle('pending'),
                    size: AppTagSize.compact,
                  ),
                  AppTag(
                    label: battleDurationLabel(battle.durationMinutes),
                    style: battleStatusTagStyle('draw'),
                    size: AppTagSize.compact,
                  ),
                ],
              ),
            ),
            // 매칭 전까지는 기준을 고칠 수 있다. 매칭된 뒤에는 서버가 거부한다.
            _CardIconAction(
              icon: AppIcons.edit,
              label: AppStrings.battleCriteriaEditRecruit,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => EditRecruitCriteriaScreen(battle: battle),
                ),
              ),
            ),
            // 없애기는 danger. 아이콘은 X가 아니라 휴지통이다 — X는 "카드를 닫는다"로도 읽히는데
            // 실제로 일어나는 일은 모집이 없어지는 것이다.
            _CardIconAction(
              icon: AppIcons.delete,
              label: AppStrings.battleRecruitCancel,
              color: AppPalette.danger,
              onPressed: onCancel,
            ),
          ],
        ),
        const SizedBox(height: 8),
        // 제목은 **카드의 정확한 가운데**다(2026-11-12 오너 확정). 그러려면 제목 위아래가 같은
        // 높이여야 한다 — 윗줄 높이는 아이콘 버튼이 정하므로 아랫줄도 같은 높이
        // (`myBattleCardBlockHeight`)를 차지하게 두고, 카드 위아래 여백과 제목 양쪽 간격(8)을
        // 맞춘다. 고정 숫자로 "28을 띄운다" 식으로 맞추면 글자 배율이 커질 때 아랫줄만 자라
        // 대칭이 깨진다.
        //
        // 크기는 titleMedium(18/700)이다. 목록 본문(bodyLarge 16)보다 한 단계 위인데, 이 카드에서
        // 제목은 본문이 아니라 **유일한 주인공**이다(칩은 곁들이는 정보로 내려갔다).
        KeepWordsText(
          battle.title,
          style: textTheme.titleMedium,
          // 줄 수를 막지 않는다(진행 중 카드와 같다) — 큰 글자 배율에서 뒷말이 잘리면
          // 무슨 모집인지 알 수 없다.
          // 역할이 카드 제목이라 줄 길이를 고르게 한다(redesign 후속 2 W2).
          wrap: KeepWordsWrap.balanced,
        ),
        const SizedBox(height: 8),
        // "아직 아무도 안 들어왔다"는 사실 자체가 이 구역의 의미다.
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: myBattleCardBlockHeight),
          child: Align(
            alignment: Alignment.centerLeft,
            child: KeepWordsText(
              AppStrings.battleMyRecruitWaiting,
              style: textTheme.bodySmall,
            ),
          ),
        ),
      ],
    );
  }
}

/// 카드 우측 상단의 동작 하나. 글자 없이 아이콘만이라 **[label]을 툴팁으로 단다** — 길게 누르면
/// 뜨고, 스크린 리더가 읽는 이름도 그것이다(글자 버튼일 때는 라벨이 그 두 가지를 겸했다).
///
/// 크기를 `SizedBox`로 못 박는다 — `IconButton`의 기본 여백에 맡기면 테마·`visualDensity`에 따라
/// 달라지고, 이 버튼이 카드 윗줄의 높이를 정하므로 제목의 가운데까지 함께 흔들린다.
///
/// 48이 아니라 40이다(2026-11-12 오너 — "속도전 있는 행 padding이 너무 크다"). 48이면 24dp 칩
/// 위아래로 12dp씩 빈 공간이 생겨 윗줄만 떠 보였다. 40은 Material 권장(48)보다 작지만
/// 카드 전체가 누를 수 있는 면이고, 이 두 버튼은 그 위에 얹힌 **곁다리 동작**이다.
class _CardIconAction extends StatelessWidget {
  const _CardIconAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: myBattleCardBlockHeight,
      height: myBattleCardBlockHeight,
      child: IconButton(
        padding: EdgeInsets.zero,
        tooltip: label,
        color: color,
        onPressed: onPressed,
        icon: Icon(icon),
      ),
    );
  }
}
