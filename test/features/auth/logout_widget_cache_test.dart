import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:todododo/core/push/push_service.dart';
import 'package:todododo/core/strings.dart';
import 'package:todododo/features/auth/data/auth_repository.dart';
import 'package:todododo/features/todo/data/todo_widget_payload.dart';
import 'package:todododo/features/todo/domain/todo_widget_service.dart';

import '../todo/todo_widget_fakes.dart';

/// 로그아웃·탈퇴·세션 소멸 **셋 모두**에서 홈 화면 위젯이 그 자리에서 비워지는지 본다
/// (design 8장의 세 방어선). 비워지지 않으면 기기를 넘겨받은 사람이 내 할 일 제목을 본다 —
/// spec은 "다음 주기 갱신(최대 30분)을 기다려야 비워지는 것"을 받지 않는다.
void main() {
  group('AuthRepository', () {
    test('로그아웃이 위젯 캐시를 비운다', () async {
      final calls = <String>[];
      final repository = _repository(calls);

      // auth.signOut()은 세션이 없어 던진다(네트워크를 타지 않는다). 비우기를 그 **앞**에 두는
      // 이유가 이것이다 — 뒤에 두면 앞 단계가 던질 때 건너뛰어진다.
      await _ignoreFailure(repository.signOut);

      expect(calls, contains('clearWidgetCache'));
      // 알림 토큰 정리가 먼저다(내 세션으로만 통하므로). 위젯 캐시는 기기 로컬이라 순서에 민감하지
      // 않지만, 로그아웃 자체보다는 앞이어야 한다.
      expect(calls.indexOf('clearWidgetCache'), greaterThan(calls.indexOf('forgetToken')));
    });

    test('로그인 상태가 아닌 탈퇴는 아무것도 비우지 않는다', () async {
      final calls = <String>[];
      final repository = _repository(calls);

      // 탈퇴는 `signOut()`을 거치지 않고 `auth.signOut()`을 직접 부르므로 비우기를 **따로** 적어야
      // 한다(design 8.1). 그 줄은 `delete_account` RPC 뒤에 있어 **서버가 있어야 도달한다** —
      // 오프라인 유닛에서는 세션 가드에서 끝나므로 여기서는 "실패한 탈퇴가 캐시를 건드리지
      // 않는다"만 고정한다(그 줄 자체는 실기기 확인이 본다 — design 12.2의 10번).
      await _ignoreFailure(repository.deleteAccount);

      expect(calls, isEmpty);
    });
  });

  group('TodoWidgetService', () {
    test('publishLoggedOut은 캐시를 로그인 안내로 덮는다', () async {
      final host = FakeTodoWidgetHost();
      final service = TodoWidgetService(host);
      await service.publish(TodoWidgetPayload.loading(now: DateTime(2026, 11, 18)));

      await service.publishLoggedOut(now: DateTime(2026, 11, 18, 9, 14));

      // 키를 지우지 않고 **덮는다** — 키가 없으면 위젯이 "앱을 한 번 열어 주세요"를 띄우는데
      // 그건 로그아웃 상태와 다른 뜻이다.
      expect(host.saved.last.items, isEmpty);
      expect(host.saved.last.centerText, AppStrings.widgetLoggedOut);
      expect(host.saved.last.tapTarget, TodoWidgetTapTarget.login);
      expect(host.updateCount, 2);
    });

    test('비우기가 실패해도 예외가 호출부로 나가지 않는다', () async {
      final host = FakeTodoWidgetHost(saveError: StateError('no plugin'));
      final service = TodoWidgetService(host);

      // 위젯 캐시 때문에 로그아웃·탈퇴가 막히면 안 된다. 그래서 호출부에 try가 없다.
      await service.publishLoggedOut(now: DateTime(2026, 11, 18));

      expect(host.saved, hasLength(1));
    });
  });
}

/// 세션이 없는 상태에서 로그아웃·탈퇴를 부르면 마지막 단계가 던진다. 그 예외는 이 테스트의
/// 관심사가 아니다(관심사는 "그 전에 위젯 캐시를 비웠는가").
Future<void> _ignoreFailure(Future<void> Function() action) async {
  try {
    await action();
  } catch (error) {
    // 기대한 실패다.
  }
}

AuthRepository _repository(List<String> calls) {
  return AuthRepository(
    SupabaseClient('http://localhost:54321', 'test-anon-key'),
    _FakePushService(calls),
    () async => calls.add('cancelAlarms'),
    () async => calls.add('clearWidgetCache'),
  );
}

class _FakePushService implements PushService {
  _FakePushService(this.calls);

  final List<String> calls;

  @override
  Future<void> forgetCurrentToken() async => calls.add('forgetToken');

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
