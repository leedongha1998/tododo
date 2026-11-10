import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/push/push_messaging.dart';
import '../../../core/push/push_providers.dart';
import '../../../core/strings.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_panel.dart';
import '../../../core/widgets/keep_words_text.dart';
import '../../../core/widgets/status_message.dart';
import '../../auth/domain/auth_providers.dart';
import '../data/todo.dart';
import '../domain/due_date_rules.dart';
import '../domain/todo_order.dart';
import '../domain/todo_providers.dart';

/// 손잡이 칸·체크박스 칸. 터치 영역과 겹침을 재는 기준은 **그려지는 상자가 아니라 이 칸**이다
/// (`Transform.scale`은 그림만 키운다 — 히트 테스트는 칸이 결정한다).
const todoDragHandleKey = Key('todoDragHandle');
const todoCheckCellKey = Key('todoCheckCell');

/// 줄의 고정 칸 폭. 손잡이·체크박스·삭제가 같은 48dp를 쓰고 남은 폭 전부가 제목 칸이다
/// (360dp 화면·1.5배 글자에서 제목 칸 200dp — todo-reorder design 4.2의 폭 산수).
const _cellWidth = 48.0;

class TodoListScreen extends ConsumerStatefulWidget {
  const TodoListScreen({super.key});

  @override
  ConsumerState<TodoListScreen> createState() => _TodoListScreenState();
}

class _TodoListScreenState extends ConsumerState<TodoListScreen> {
  /// 끌어 놓은 순서를 **서버가 답할 때까지만** 들고 있는 복사본(design 4.4).
  ///
  /// 순서의 진실은 여전히 `todosProvider`(서버의 `order by position`) 하나이고 이 값은 낙관적
  /// 적용이다. null이면 "끌기 결과를 기다리는 중이 아니다"이고, 되돌리는 방법은 null로 두는
  /// 것이다 — `todosProvider`를 건드리지 않았으므로 그 값이 곧 끌기 전 순서다.
  List<Todo>? _dragged;

  /// 서버에 보낸 끌기를 **한 줄로 세우는 사슬**. 보낸 순서 = 사용자가 끈 순서다.
  ///
  /// 겹친 끌기를 동시에 보내면 두 가지가 어긋난다: ① 뒤 끌기의 기준(`afterId`)은 앞 끌기가
  /// 서버에 적용된 뒤에 뜻을 갖고, ② 앞 끌기의 재조회가 **뒤 끌기의 낙관적 순서를 지워** 목록이
  /// 한 번 옛 순서로 튄다. 위젯 캐시 발행처럼 "키 하나를 덮어쓰는 멱등한 쓰기"가 아니라 순서를
  /// 이어 고치는 경로이므로 직렬화한다. `_sendMove`가 예외를 밖으로 내지 않아 사슬이 끊기지 않는다.
  Future<void> _moveQueue = Future<void>.value();

  /// 아직 결말이 나지 않은 끌기 수. 0이 아니면 **들어온 데이터로 낙관적 순서를 지우지 않는다**.
  int _pendingMoves = 0;

  /// 새 할 일이 맨 아래에 생기므로 추가 직후 거기를 보여 준다(design 4.5).
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _openAddDialog() async {
    final draft = await _showTodoInputDialog(context, dialogTitle: AppStrings.addTodo);
    if (draft == null || draft.title.isEmpty) return;

    try {
      final userId = ref.read(authRepositoryProvider).currentUser!.id;
      await ref
          .read(todoRepositoryProvider)
          .addTodo(userId, draft.title, dueAt: draft.dueAt);
      ref.invalidate(todosProvider);
      unawaited(_showNewTodo());
    } catch (e) {
      debugPrint('addTodo failed: $e');
      if (mounted) _showErrorSnackBar(context, AppStrings.saveTodoFailed);
    }
  }

  /// 새 할 일은 언제나 **맨 아래**에 생긴다(서버가 컬럼 기본값으로 정한다 — design 1.5). 목록이
  /// 길면 그 자리가 화면 밖이고, 저장은 됐는데 아무 변화가 안 보이면 사용자는 실패로 읽는다.
  /// 그래서 추가 직후 맨 아래를 보여 준다(design 4.5). 목록이 화면에 다 들어가면
  /// `maxScrollExtent`가 0이라 아무 일도 일어나지 않는다.
  ///
  /// 새 목록을 받고 **그 목록으로 한 프레임이 그려진 뒤에** 움직인다 — 그 전에는 늘어난 길이를
  /// 모른다. 실패는 `debugPrint`만 남긴다: 스크롤은 관문이 아니고 저장은 이미 끝났으며 사용자가
  /// 직접 내릴 수 있다(위젯 캐시 발행과 같은 성격이다. **추가 자체의 실패는 토스트**다).
  Future<void> _showNewTodo() async {
    try {
      await ref.read(todosProvider.future);
      if (!mounted) return;
      // 새 목록으로 한 프레임이 그려진 뒤에 길이를 읽는다.
      await WidgetsBinding.instance.endOfFrame;
      // **목록 길이는 추정값이다.** 줄을 게으르게 만들기 때문에(ListView.builder) 끝까지
      // 내려가는 동안 값이 정확해진다 — 한 번만 내려가면 추정이 짧았던 만큼(한 줄 남짓) 모자란
      // 자리에서 멈춘다. 그래서 더 내려갈 곳이 없을 때까지 몇 번만 더 내려간다.
      for (var i = 0; i < 5; i++) {
        if (!mounted || !_scrollController.hasClients) return;
        final target = _scrollController.position.maxScrollExtent;
        if (_scrollController.offset >= target) return;
        await _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    } catch (e) {
      debugPrint('scrollToNewTodo failed: $e');
    }
  }

  Future<void> _openEditDialog(Todo todo) async {
    final draft = await _showTodoInputDialog(
      context,
      dialogTitle: AppStrings.editTodo,
      initialTitle: todo.title,
      initialDueAt: todo.dueAt?.toLocal(),
    );
    if (draft == null || draft.title.isEmpty) return;
    // 제목이 그대로여도 기한이 바뀌면 저장한다. **둘 다** 그대로일 때만 건너뛴다 —
    // 기한만 고친 경우가 조용히 버려지면 안 된다(spec).
    final sameTitle = draft.title == todo.title;
    final sameDue = _sameInstant(draft.dueAt, todo.dueAt);
    if (sameTitle && sameDue) return;

    try {
      await ref
          .read(todoRepositoryProvider)
          .updateTodo(todo.id, title: draft.title, dueAt: draft.dueAt);
      ref.invalidate(todosProvider);
    } catch (e) {
      debugPrint('updateTodo failed: $e');
      if (mounted) _showErrorSnackBar(context, AppStrings.saveTodoFailed);
    }
  }

  Future<void> _toggleDone(Todo todo) async {
    try {
      await ref.read(todoRepositoryProvider).setDone(todo.id, !todo.isDone);
      ref.invalidate(todosProvider);
    } catch (e) {
      debugPrint('setDone failed: $e');
      if (mounted) _showErrorSnackBar(context, AppStrings.saveTodoFailed);
    }
  }

  Future<void> _deleteTodo(Todo todo) async {
    try {
      await ref.read(todoRepositoryProvider).deleteTodo(todo.id);
      ref.invalidate(todosProvider);
    } catch (e) {
      debugPrint('deleteTodo failed: $e');
      if (mounted) _showErrorSnackBar(context, AppStrings.deleteTodoFailed);
    }
  }

  /// 끌어 놓은 한 번. 좌표 변환은 순수 함수가 하고(`planTodoMove`), 자리 값은 서버가 만든다
  /// (design 원칙 2) — 화면이 보내는 것은 "이 할 일을 저 할 일 바로 아래에 둔다"는 기준 하나다.
  ///
  /// 네 줄로 끝난다(design 4.4): ① 화면에 먼저 적용하고 ② 서버에 보내고 ③ 성공하면 다시 받고
  /// ④ 실패하면 **끌기 전 순서로 되돌리고 토스트**를 띄운다. 순서 저장 실패는 삼키지 않는다 —
  /// 위젯 캐시 발행·기한 알림 예약과 달리 사용자가 방금 한 조작 그 자체다.
  Future<void> _onReorder(List<Todo> current, int oldIndex, int newIndex) async {
    final plan = planTodoMove(current, oldIndex: oldIndex, newIndex: newIndex);
    // 제자리면 아무것도 하지 않는다(끌었다가 같은 자리에 놓는 일은 흔하다).
    if (!plan.changed) return;
    final movedId = current[oldIndex].id;
    // 화면은 **곧바로** 바뀐다(손을 따라와야 한다). 서버에 보내는 일만 줄을 세운다.
    setState(() => _dragged = plan.todos);
    _pendingMoves++;
    final queued = _moveQueue.then((_) => _sendMove(movedId, plan));
    _moveQueue = queued;
    await queued;
  }

  /// 끌기 하나를 서버에 보내고 결말을 낸다. **예외를 밖으로 내지 않는다**(사슬이 끊기면 그 뒤에
  /// 끈 것들이 영원히 안 나간다).
  Future<void> _sendMove(
    String movedId,
    ({List<Todo> todos, String? afterId, bool changed}) plan,
  ) async {
    try {
      await ref
          .read(todoRepositoryProvider)
          .moveTodo(movedId, afterId: plan.afterId);
      // _dragged는 **새 데이터가 도착할 때까지 그대로 둔다**(바로 지우면 재조회 동안 끌기 전
      // 순서가 한 번 보였다가 다시 바뀌어, 저장에 성공했는데도 화면이 두 번 튄다). 새 데이터가
      // 오면 build의 리스너가 지우고, 그 값은 방금 저장한 순서와 같으므로 화면은 꿈쩍하지 않는다.
      // 그 재조회가 MainShell의 ref.listen을 지나며 홈 위젯 캐시도 같은 순서로 발행된다.
      ref.invalidate(todosProvider);
    } catch (e) {
      debugPrint('moveTodo failed: $e');
      if (!mounted) return;
      // 그 사이 사용자가 또 끌었으면 그 조작을 내 실패로 덮지 않는다(나중 끌기가 자기 결말을
      // 낸다). 되돌리는 방법은 _dragged를 비우는 것이다 — todosProvider를 건드리지 않았으므로
      // 그 값이 곧 끌기 전 순서다(실패한 끌기 때문에 목록이 에러 화면으로 사라지지 않는다).
      if (_sameOrder(_dragged, plan.todos)) setState(() => _dragged = null);
      _showErrorSnackBar(context, AppStrings.todoReorderFailed);
    } finally {
      _pendingMoves--;
    }
  }

  /// 두 목록이 같은 할 일을 같은 차례로 들고 있는지. 되돌릴지 말지를 가르는 데만 쓴다.
  bool _sameOrder(List<Todo>? a, List<Todo> b) {
    if (a == null || a.length != b.length) return false;
    for (var i = 0; i < b.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  /// 기한이 그대로인지. 둘 다 null도 "같다"다. 저장된 값은 UTC, 대화상자의 값은 local이라
  /// 절대 시각으로 비교한다.
  bool _sameInstant(DateTime? a, DateTime? b) {
    if (a == null || b == null) return a == null && b == null;
    return a.toUtc().isAtSameMomentAs(b.toUtc());
  }

  void _showErrorSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: KeepWordsText(message)));
  }

  /// 들린 줄은 카드가 책상에서 떠오른 모습이다 — 면·테두리·내용은 그대로 두고 그림자만 더한다
  /// (`AppPanel`의 두께는 그 아래에 그대로 있다). 기본 데코레이터는 모서리를 모르는 직사각형
  /// 그림자를 그리므로 카드의 16 반경을 알려 준다.
  Widget _liftedCard(Widget child, int index, Animation<double> animation) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) => Material(
        color: Colors.transparent,
        elevation: 6 * Curves.easeOut.transform(animation.value),
        shadowColor: AppPalette.edge,
        borderRadius: BorderRadius.circular(16),
        child: child,
      ),
    );
  }

  /// 줄 하나. `ListTile`을 쓰지 않고 네 칸을 직접 쓰는 이유는 하나다: `ListTile`은 칸 폭을 자기
  /// 규칙으로 정하므로 손잡이 48dp를 넣고도 제목 칸이 198dp 이상임을 **산수로 보일 수 없다**
  /// (design 4.2). 칸을 직접 쓰면 폭이 더하기 한 줄이다.
  ///
  /// 손잡이를 **왼쪽 끝**에 두고 삭제를 오른쪽 끝에 둔다 — 손잡이를 겨냥해 미끄러져도 닿는
  /// 것은 체크박스이고, 잘못 눌렀을 때 가장 비싼 삭제 옆에 손잡이를 두는 배치를 피한다.
  Widget _todoRow(Todo todo, int index, DateTime now) {
    // 완료한 할 일에는 남은 시간을 표시하지 않는다(기한이 있어도, 넘겼어도) —
    // 끝낸 일에 붙는 빨간 "지남"은 아무 행동도 유도하지 않는다(spec).
    // 문구와 색은 formatDueLabel이 **함께** 판정한다. 여기서 "지났는지"를 다시 따지면
    // 경계(기한까지 1초 미만)에서 둘이 어긋난다.
    final dueAt = todo.isDone ? null : todo.dueAt?.toLocal();
    final due = dueAt == null ? null : formatDueLabel(dueAt, now);
    // IntrinsicHeight가 있어야 stretch가 성립한다(목록 줄의 높이 제약이 무한이라
    // 그대로 stretch를 쓰면 무한 높이를 강제한다 — plan.md "설계와 다른 점" 2번).
    final row = ConstrainedBox(
      // 지금까지의 minTileHeight 60을 그대로 가져온다.
      constraints: const BoxConstraints(minHeight: 60),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ① 손잡이 48dp. 줄 높이 전체를 차지해 터치 영역은 48 x (60 이상)이다.
            // ColoredBox(투명)로 칸 전체를 히트 테스트 대상으로 만든다 — 아이콘만 두면
            // 칸의 빈 자리를 잡아도 끌리지 않는다(plan.md "설계와 다른 점" 3번).
            ReorderableDragStartListener(
              index: index,
              child: Semantics(
                // container: true가 없으면 라벨이 바깥 노드(줄 전체 탭)에 **병합돼** 손잡이가
                // 자기 노드를 갖지 못한다(기본값이 false다). 접근성 끌기 액션은 범위 밖이다.
                container: true,
                label: AppStrings.todoReorderHandle,
                child: const SizedBox(
                  key: todoDragHandleKey,
                  width: _cellWidth,
                  child: ColoredBox(
                    color: Colors.transparent,
                    child: Center(
                      child: Icon(
                        AppIcons.dragHandle,
                        size: 24,
                        color: AppPalette.inkMuted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // ② 체크박스 48dp. 그림은 지금처럼 24dp(Flutter Checkbox가 18dp 고정이라 키운다)이고
            //    **히트 영역은 이 칸 48dp**다(부모가 자기 크기 밖의 좌표를 먼저 거른다).
            SizedBox(
              key: todoCheckCellKey,
              width: _cellWidth,
              child: Center(
                child: Transform.scale(
                  scale: 24 / 18,
                  child: Checkbox(
                    value: todo.isDone,
                    onChanged: (_) => _toggleDone(todo),
                  ),
                ),
              ),
            ),
            // ③ 제목(+남은 시간). 남은 폭 전부.
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    KeepWordsText(
                      todo.title,
                      style: todo.isDone
                          ? const TextStyle(
                              decoration: TextDecoration.lineThrough,
                              color: AppPalette.inkMuted,
                              decorationColor: AppPalette.inkMuted,
                            )
                          : null,
                    ),
                    // 남은 시간은 제목 아래 둘째 줄이다 — 제목 칸을 1dp도 깎지 않는다.
                    if (due != null) ...[
                      const SizedBox(height: 2),
                      KeepWordsText(
                        due.label,
                        style: Theme.of(context).textTheme.bodySmall!
                            .merge(AppText.tabular)
                            .copyWith(
                              color: due.overdue
                                  ? AppPalette.danger
                                  : AppPalette.inkMuted,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // ④ 삭제 48dp. 상자를 48x48로 두어 지금과 같은 크기를 유지한다(줄 높이로 늘리지
            //    않는다 — 잘못 눌렸을 때 가장 비싼 동작이라 영역을 키우지 않는다).
            SizedBox(
              width: _cellWidth,
              child: Center(
                child: IconButton(
                  icon: const Icon(AppIcons.delete, color: AppPalette.inkMuted),
                  tooltip: AppStrings.delete,
                  onPressed: () => _deleteTodo(todo),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    void openEdit() => _openEditDialog(todo);
    // 안 한 일은 떠 있고, 끝낸 일은 가라앉는다. 면색·높낮이·체크·취소선으로 한눈에 갈린다.
    // 누르기(수정)는 묶음이 받아 떠 있는 카드는 누르는 동안 두께가 꺼진다. 손잡이·체크박스·삭제
    // 버튼은 안쪽이라 제스처 경쟁에서 먼저 이긴다.
    // 간격 12를 **모든 줄**이 쓴다(지금은 마지막 줄만 0이었다) — 끌고 있는 동안 "마지막 줄"이
    // 바뀌어 12dp가 튀기 때문이다. 늘어난 12dp는 fabClearance 아래에 묻힌다.
    return Padding(
      key: ValueKey(todo.id),
      padding: const EdgeInsets.only(bottom: 12),
      child: todo.isDone
          ? AppPanel.inset(padding: EdgeInsets.zero, onTap: openEdit, child: row)
          : AppPanel.raised(padding: EdgeInsets.zero, onTap: openEdit, child: row),
    );
  }

  @override
  Widget build(BuildContext context) {
    final todosAsync = ref.watch(todosProvider);

    // 서버가 답하면 낙관적 복사본을 놓는다(design 4.4의 규칙 3). **데이터일 때만** 지운다 —
    // 로딩·에러에서 지우면 재조회 동안 끌기 전 순서가 한 번 보였다가 다시 바뀐다.
    ref.listen(todosProvider, (previous, next) {
      if (next.isLoading || next.hasError) return;
      // 아직 결말이 나지 않은 끌기가 남아 있으면 그대로 둔다 — 앞 끌기의 재조회가 **뒤 끌기의
      // 낙관적 순서를 지워** 목록이 한 번 옛 순서로 튀는 것을 막는다(끌기를 직렬화해도 재조회는
      // 앞 끌기 쪽이 먼저 돌아온다).
      if (_pendingMoves > 0) return;
      if (_dragged != null) setState(() => _dragged = null);
    });

    return Scaffold(
      appBar: AppBar(title: const KeepWordsText(AppStrings.todoTitle)),
      body: todosAsync.when(
        data: (data) {
          // 끌어 놓은 결과가 있으면 그것을 그린다(서버가 답하면 리스너가 지운다).
          final todos = _dragged ?? data;
          if (todos.isEmpty) {
            return const StatusMessage.empty(
              icon: AppIcons.todoOutlined,
              message: AppStrings.emptyTodos,
              fill: true,
            );
          }
          // 모든 줄이 같은 "지금"을 쓰도록 한 번만 읽는다. 분 단위 타이머로 다시 그리지 않으므로
          // 화면을 켜 둔 채 두면 낡지만, 다시 들어오면 맞는다(spec "표시 갱신").
          final now = DateTime.now();
          return ReorderableListView.builder(
            // 좌우는 8로 줄여 손잡이 48dp의 자리를 만든다(제목 칸은 198 → 200dp로 오히려 는다 —
            // design 4.2, 오너 확정). 위 16·아래 fabClearance는 그대로다.
            padding: const EdgeInsets.fromLTRB(8, 16, 8, AppTheme.fabClearance),
            scrollController: _scrollController,
            itemCount: todos.length,
            // **길게 누르기를 쓰지 않는다**(오너 확정). 기본값(true)이면 모바일에서 줄 전체가
            // 길게 눌러 집히는 손잡이가 되어 "줄 전체 누르기 = 수정"과 싸운다.
            buildDefaultDragHandles: false,
            proxyDecorator: _liftedCard,
            // onReorder가 아니라 onReorderItem이다 — 전자는 Flutter 3.47에서 폐기됐고(analyze
            // 이슈가 된다), 후자는 "옮길 줄을 뺀 뒤의 자리"를 준다(plan.md "설계와 다른 점" 1번).
            onReorderItem: (oldIndex, newIndex) =>
                unawaited(_onReorder(todos, oldIndex, newIndex)),
            itemBuilder: (context, index) => _todoRow(todos[index], index, now),
          );
        },
        loading: () => const StatusMessage.loading(fill: true),
        error: (error, stackTrace) {
          debugPrint('todosProvider error: $error');
          return const StatusMessage.error(message: AppStrings.loadTodosFailed, fill: true);
        },
      ),
      floatingActionButton: FloatingActionButton(
        // 찾기 탭 FAB와 같은 이유로 고유 태그를 준다(기본값이면 Hero 태그가 겹친다).
        heroTag: 'addTodoFab',
        onPressed: _openAddDialog,
        child: const Icon(AppIcons.add),
      ),
    );
  }
}

/// 추가·수정 대화상자가 돌려주는 값. null은 취소다.
class TodoDraft {
  const TodoDraft({required this.title, required this.dueAt});

  final String title;

  /// **기기 시간대의 local DateTime**(분 단위, 초·밀리초는 0). null이면 기한 없음.
  /// UTC 변환은 레포지토리가 저장 직전에 한다.
  final DateTime? dueAt;
}

Future<TodoDraft?> _showTodoInputDialog(
  BuildContext context, {
  required String dialogTitle,
  String initialTitle = '',
  DateTime? initialDueAt,
}) {
  return showDialog<TodoDraft>(
    context: context,
    builder: (context) => _TodoInputDialog(
      dialogTitle: dialogTitle,
      initialTitle: initialTitle,
      initialDueAt: initialDueAt,
    ),
  );
}

/// 추가와 수정이 공유하는 대화상자. 기한은 사용자가 고르는 동안 화면에 남아야 하므로
/// 상태가 필요하다(지금까지는 무상태 `AlertDialog`였다).
///
/// **기한을 쓰지 않는 사용자의 타수가 늘지 않는다**(design 원칙 5): 입력 칸이 여전히
/// `autofocus`이고 `onSubmitted`가 그대로 저장으로 간다 — 제목 적고 엔터면 끝이다. 기한 줄은
/// 입력 칸 아래에 있고 날짜를 고르라고 막는 단계가 없다.
///
/// `ConsumerStatefulWidget`인 이유는 하나다 — 기한을 처음 정할 때 알림 권한을 묻고(P1),
/// 거부 상태면 한 줄로 알리려고 `ref`가 필요하다.
class _TodoInputDialog extends ConsumerStatefulWidget {
  const _TodoInputDialog({
    required this.dialogTitle,
    required this.initialTitle,
    this.initialDueAt,
  });

  final String dialogTitle;
  final String initialTitle;
  final DateTime? initialDueAt;

  @override
  ConsumerState<_TodoInputDialog> createState() => _TodoInputDialogState();
}

class _TodoInputDialogState extends ConsumerState<_TodoInputDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialTitle);
  DateTime? _dueAt;

  @override
  void initState() {
    super.initState();
    _dueAt = widget.initialDueAt;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(
      TodoDraft(title: _controller.text.trim(), dueAt: _dueAt),
    );
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final base = _dueAt ?? now;
    // 규칙상의 한도가 아니라 달력 위젯이 요구하는 범위다(spec "기한의 하한·상한을 두지 않는다").
    // 지난 시각도 기한으로 넣을 수 있어야 하므로 firstDate를 오늘로 두지 않고, 이미 가진 기한이
    // 범위를 벗어나면 그쪽으로 넓혀 수정이 막히지 않게 한다.
    var firstDate = DateTime(now.year - 1);
    var lastDate = DateTime(now.year + 5, 12, 31);
    final baseDay = DateTime(base.year, base.month, base.day);
    if (baseDay.isBefore(firstDate)) firstDate = baseDay;
    if (baseDay.isAfter(lastDate)) lastDate = baseDay;

    final date = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: firstDate,
      lastDate: lastDate,
    );
    // 날짜를 취소하면 아무것도 바뀌지 않는다(취소는 취소다).
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      // 날짜만 생각하고 들어온 사용자를 위해 23:59. 확인만 눌러도 "그 날 안에"가 된다(spec).
      initialTime: _dueAt == null
          ? const TimeOfDay(hour: 23, minute: 59)
          : TimeOfDay.fromDateTime(_dueAt!),
    );
    if (time == null || !mounted) return;

    // 초·밀리초는 0이다(분 단위). 수정 시 "안 바뀌었는지" 비교가 흔들리지 않는다.
    setState(() {
      _dueAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });

    // 기한을 **정한 그 자리**에서 알림 권한을 묻는다(앱 첫 실행·화면 진입이 아니다 — spec).
    // 아직 묻지 않았을 때만 OS 다이얼로그가 뜨고, 거부한 사용자에게 다시 묻지 않는다.
    // 저장 전에 묻는 이유: 권한을 쓸 이유가 생긴 순간이 여기이고, 저장 성공을 기다리면
    // 왜 묻는지가 흐려진다. 실패는 서비스가 로그만 남긴다(알림은 관문이 아니다).
    await ref.read(dueAlarmServiceProvider).ensurePermissionWhenSettingDue();
  }

  @override
  Widget build(BuildContext context) {
    final dueAt = _dueAt;
    // 권한 상태는 프로필의 "알림이 꺼져 있어요" 칸과 **같은 provider**를 읽는다 — 한 값을 두
    // 곳에서 각자 판정하면 두 자리가 어긋난다. 아직 못 읽었거나 읽기에 실패했으면 아무 줄도
    // 그리지 않는다(없는 안내보다 틀린 안내가 나쁘다).
    final notificationsOff =
        ref.watch(notificationPermissionProvider).value ==
        NotificationPermission.denied;
    return AlertDialog(
      title: KeepWordsText(widget.dialogTitle),
      // 1.5배 글자 + 키보드에서 내용이 잘리지 않게 감싼다(기한 줄만큼 높이가 늘었다).
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(hintText: AppStrings.todoInputHint),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 8),
            if (dueAt == null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _pickDue,
                  icon: const Icon(AppIcons.clock),
                  label: const KeepWordsText(AppStrings.todoDueAdd),
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: _pickDue,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: KeepWordsText(
                          '${AppStrings.todoDueLabel} · ${formatDueValue(dueAt)}',
                        ),
                      ),
                    ),
                  ),
                  // 기한 없음으로 되돌리는 길. 없으면 잘못 고른 기한을 지우는 유일한 방법이
                  // "할 일을 삭제하고 다시 적기"가 된다(spec).
                  IconButton(
                    icon: const Icon(AppIcons.close, color: AppPalette.inkMuted),
                    tooltip: AppStrings.todoDueClear,
                    onPressed: () => setState(() => _dueAt = null),
                  ),
                ],
              ),
            // 알림이 꺼져 있다는 사실은 **기한을 정한 사람에게만** 뜻이 있다. 기한을 정하는
            // 길은 막지 않고(입력·표시·정렬은 그대로 동작한다) 한 줄로만 알린다.
            // `알림 설정 열기` 버튼은 두지 않는다 — 프로필 안내가 이미 길을 알려 준다(spec·설계).
            if (dueAt != null && notificationsOff)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: KeepWordsText(
                  AppStrings.todoDueNotificationsOff,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppPalette.inkMuted,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const KeepWordsText(AppStrings.cancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: const KeepWordsText(AppStrings.save),
        ),
      ],
    );
  }
}
