import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/app_tab.dart';
import '../../../core/push/push_messaging.dart';
import '../../../core/push/push_providers.dart';
import '../../../core/strings.dart';
import '../data/due_alarm_host.dart';
import '../data/todo.dart';
import 'due_alarm_plan.dart';

/// 기한 알림의 배선. 계획은 순수 함수가 세우고(`due_alarm_plan.dart`) 이 클래스는 그 계획을
/// 플랫폼에 옮기는 일만 한다.
///
/// **이 클래스의 모든 실패는 `debugPrint`로만 남고 밖으로 나가지 않는다.** 알림은 관문이
/// 아니므로(spec "알림이 관문이 아니다") 예약·취소·초기화·권한이 어떻게 실패해도 할 일 저장·
/// 수정·완료·삭제가 막히지 않는다. 호출 자리(`MainShell`의 `ref.listen`, 대화상자)에는 토스트를
/// 띄울 맥락도 없고 사용자가 할 수 있는 일도 없다 — 다음 보정에서 저절로 맞춰진다.
/// 이 예외는 `CLAUDE.md` 코딩 규칙의 예외 목록에 적혀 있다(위젯 캐시 발행과 같은 성격).
///
/// 직전에 맞춘 "원하는 집합"을 기억하므로 앱 수명 동안 하나만 둔다(`dueAlarmServiceProvider`).
class DueAlarmService {
  DueAlarmService(this._ref, this._host, this._messaging);

  /// 알림을 탭했을 때 할 일 탭으로 보내려고 들고 있다(`PushService`와 같은 이유).
  final Ref _ref;
  final DueAlarmHost _host;

  /// 알림 권한은 **이미 있는 firebase_messaging 하나로 묻는다.** 같은 OS 권한을 두 패키지가
  /// 각자 묻게 하면 상태를 읽는 자리가 둘이 되고, 프로필의 "알림이 꺼져 있어요"와 어긋난다.
  final PushMessaging _messaging;

  bool _initialized = false;

  /// 진행 중인 초기화. 셸이 뜨는 순간 `start()`와 첫 `sync()`가 **거의 동시에** 들어오므로,
  /// 이것이 없으면 플러그인 초기화와 채널 생성이 두 번 돌고 탭 콜백도 두 번 등록된다.
  Future<void>? _initializing;

  /// 직전에 맞춘 집합의 서명. 같으면 플랫폼을 건드리지 않는다 — 탭을 오갈 때마다 목록이 다시
  /// 와도 내용이 같으면 조용하다.
  ///
  /// **`TodoWidgetService._lastJson`을 그대로 베끼면 안 된다.** 위젯 발행은 키 하나에 JSON
  /// 하나를 덮어쓰는 **멱등한 쓰기**라 마지막 writer가 이기면 그걸로 끝이다. 예약은 그렇지
  /// 않다 — 조회해서(`pending`) 고쳐 쓰는(`cancel`/`schedule`) **집합**이라, 두 보정이 겹치면
  /// 뒤에 온 쪽이 앞의 중간 상태를 읽고 "이미 지웠어야 하는 예약"을 남긴다. 그 상태에서 서명만
  /// 기록되면 다음 보정이 조회조차 건너뛰어 **일시적 경합이 영구 오상태로 굳는다.**
  /// 그래서 이 서명은 [_queue]로 직렬화된 구간 **안에서만** 읽고 쓴다.
  String? _lastSignature;

  /// 예약을 건드리는 일(보정·전체 취소)을 한 줄로 세운다.
  ///
  /// `MainShell`은 리스너에서 `unawaited`로 쏘고, 로그아웃은 `cancelAll()`을 기다린다 — 둘이
  /// 겹치면 ① 완료·삭제한 할 일의 예약이 남고 ② 로그아웃이 기다린 취소 **뒤에** 예약이 되살아난다.
  /// 둘 다 spec 수용 기준을 바로 깨므로 같은 사슬에 세운다.
  Future<void> _queue = Future<void>.value();

  /// 셸이 떠날 때(= 로그인 직후) 한 번. 초기화와 "종료 상태에서 알림을 탭해 시작됐는지"를 집는다.
  Future<void> start() async {
    try {
      await _ensureInitialized();
      if (await _host.launchedByNotification()) _openTodoTab();
    } catch (error) {
      debugPrint('dueAlarm start failed: $error');
    }
  }

  /// 목록을 받아올 때마다 **지금 있어야 하는 예약으로 맞춘다**(없으면 만들고, 어긋나면 고치고,
  /// 필요 없어진 것은 버린다).
  ///
  /// spec이 요구하는 취소·갱신 여섯 가지(기한 변경·기한 삭제·할 일 삭제·완료·완료 해제·다른
  /// 기기에서의 수정)와 기기 성질 보정(기기 교체·재설치)이 **전부 이 한 경로**로 해결된다 —
  /// 모두 "원하는 집합이 달라졌다"로 같게 표현되기 때문이다(design 8.5·8.7).
  Future<void> sync(List<Todo> todos, {required DateTime now}) =>
      _enqueue(() => _syncNow(todos, now: now));

  Future<void> _syncNow(List<Todo> todos, {required DateTime now}) async {
    try {
      final desired = planDueAlarms(todos, now: now);
      final signature = desired
          .map((alarm) => '${alarm.id}:${alarm.payload}')
          .join(',');
      // 서명 비교가 사슬 **안**에 있어야 한다 — 밖에서 걸러내면 앞선 보정이 아직 끝나지 않아
      // 서명이 비어 있고, 두 보정이 같은 중간 상태를 읽는다.
      if (signature == _lastSignature) return;

      await _ensureInitialized();
      final pending = [
        for (final alarm in await _host.pending())
          PendingDueAlarm(id: alarm.id, payload: alarm.payload),
      ];
      final plan = reconcileDueAlarms(desired: desired, pending: pending);
      // **취소를 전부 돌린 뒤에 예약한다.** 이 순서가 해시 충돌(design 8.4)의 안전장치다 —
      // 밀려 앉은 자리나 payload가 바뀐 옛 예약이 먼저 지워지므로, 새로 거는 예약이 아직
      // 남아 있는 남의 자리를 덮어써 그 알림을 조용히 없애는 일이 생기지 않는다.
      // 순서를 뒤집지 말 것(`cancelFor` 같은 payload 검색 취소를 만들지 않은 근거이기도 하다).
      for (final id in plan.cancel) {
        await _host.cancel(id);
      }
      for (final alarm in plan.schedule) {
        await _host.schedule(
          id: alarm.id,
          at: alarm.at,
          title: alarm.title,
          body: alarm.body,
          payload: alarm.payload,
          channelName: AppStrings.todoDueAlarmChannel,
        );
      }
      // 끝까지 성공한 집합만 기억한다. 중간에 실패했으면 다음 목록에서 다시 맞춘다.
      _lastSignature = signature;
    } catch (error) {
      debugPrint('dueAlarm sync failed: $error');
    }
  }

  /// 로그아웃·탈퇴. **기기를 넘겨받은 사람에게 내 할 일 제목이 알림으로 뜨면 안 된다**
  /// (위젯 캐시를 로그아웃 때 지우는 것과 같은 이유). 걸려 있는 알림이 전부 기한 알림이라
  /// 전부 버린다. 실패해도 로그아웃을 막지 않는다.
  Future<void> cancelAll() => _enqueue(_cancelAllNow);

  Future<void> _cancelAllNow() async {
    try {
      await _ensureInitialized();
      await _host.cancelAll();
    } catch (error) {
      debugPrint('dueAlarm cancelAll failed: $error');
    }
    // 다음 로그인에서 처음부터 다시 맞추게 한다(실패했더라도 기억을 비우는 쪽이 안전하다).
    _lastSignature = null;
  }

  /// 예약을 건드리는 일을 [_queue] 뒤에 붙인다. 앞의 일이 실패해도 사슬이 끊기지 않게
  /// 사슬 쪽 오류는 흘려보낸다 — 호출자에게는 [work]의 결과를 그대로 돌려준다
  /// (지금은 [_syncNow]·[_cancelAllNow]가 스스로 삼키므로 실패가 올라오지 않는다).
  Future<void> _enqueue(Future<void> Function() work) {
    final next = _queue.then((_) => work());
    _queue = next.catchError((Object _) {});
    return next;
  }

  /// **기한을 처음 정하는 순간** 알림 권한을 묻는다. 앱 첫 실행·투두 화면 진입에서 묻지
  /// 않는다 — 권한을 쓸 이유가 생긴 자리에서 물어야 사용자가 왜 묻는지 안다(spec).
  ///
  /// "이미 물어봤다"는 기록을 앱이 따로 두지 않는다. `notDetermined`가 그 기록이고, 그래서
  /// 거부한 사용자에게 **반복해 묻지 않는다**(`PushService`의 같은 자리 선례).
  /// 사전 안내 문구는 두지 않는다 — OS 다이얼로그에 우리 문장을 끼울 자리가 없고, 앞에 우리
  /// 대화상자를 하나 더 띄우면 허용을 두 번 묻는 모양이 된다(오너 확정, design 결정 기록 3번).
  Future<void> ensurePermissionWhenSettingDue() async {
    try {
      if (await _messaging.permissionStatus() !=
          NotificationPermission.notDetermined) {
        return;
      }
      await _messaging.requestPermission();
      // 프로필의 "알림이 꺼져 있어요" 칸과 대화상자의 꺼짐 안내가 같은 값을 보게 다시 읽힌다.
      _ref.invalidate(notificationPermissionProvider);
    } catch (error) {
      debugPrint('dueAlarm permission request failed: $error');
    }
  }

  /// 어떤 경로로 들어오든 늦게 초기화되는 일이 없게 모든 메서드가 이것을 먼저 지난다.
  /// 실패하면 다시 시도할 수 있게 기억을 비우고, 예외는 호출자의 `try/catch`로 올려 보낸다.
  Future<void> _ensureInitialized() {
    if (_initialized) return Future<void>.value();
    final started = _initializing;
    if (started != null) return started;

    // **대입을 먼저 하고 비우는 일은 그 뒤로 미룬다.** `_host.initialize`가 첫 await 전에
    // 던지면 `_initializeOnce()`는 **이미 실패로 끝난 Future**를 돌려주는데, 그 안에서 기억을
    // 비우면 비우기가 대입보다 먼저 일어나 실패한 Future가 `_initializing`에 영구히 남는다
    // (그 뒤의 모든 호출이 같은 실패를 되돌려받아 다시 시도하지 못한다).
    final attempt = _initializeOnce();
    _initializing = attempt;
    return attempt.whenComplete(() {
      if (_initializing == attempt) _initializing = null;
    });
  }

  Future<void> _initializeOnce() async {
    await _host.initialize(
      channelName: AppStrings.todoDueAlarmChannel,
      onTap: _openTodoTab,
    );
    _initialized = true;
  }

  /// 알림을 탭하면 **할 일 화면**을 연다. 특정 할 일로 스크롤·강조하지 않으므로 payload를
  /// 해석하지 않는다(위젯 탭 선례). 미로그인이면 이 서비스가 시작되지도 않아 아무 일도
  /// 일어나지 않고 `AuthGate`가 로그인 화면을 띄운다 — 오류 화면이 보이지 않는다.
  void _openTodoTab() {
    try {
      _ref.read(selectedTabProvider.notifier).select(AppTab.todo);
    } catch (error) {
      debugPrint('dueAlarm tap handling failed: $error');
    }
  }
}
