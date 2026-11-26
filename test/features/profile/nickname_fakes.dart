import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/features/battle/data/profile.dart';
import 'package:todododo/features/profile/data/nickname_state.dart';
import 'package:todododo/features/profile/data/profile_repository.dart';

/// 별명 관문·바꾸기 화면 테스트가 함께 쓰는 가짜들.

NicknameState unconfirmedNickname({bool wasReset = false}) =>
    NicknameState(nickname: '부지런한 수달', confirmed: false, wasReset: wasReset);

NicknameState confirmedNickname() =>
    const NicknameState(nickname: '부지런한 수달', confirmed: true, wasReset: false);

String nicknameFieldText(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;

/// 프로필 레포지토리 가짜. mocking 프레임워크 없이 `implements`로 만든다(기존 관례). 별명과 무관한
/// 메서드는 `noSuchMethod`가 받는다 — 레포지토리에 메서드가 늘어도 이 파일이 깨지지 않게 한다.
class FakeNicknameProfileRepository implements ProfileRepository {
  FakeNicknameProfileRepository({
    required this.states,
    this.setError,
    this.suggestion = '느긋한 펭귄',
    this.suggestError,
    this.currentName = '부지런한 수달',
    this.profileError,
  });

  /// 상태 조회가 차례로 돌려줄 값(NicknameState 또는 던질 오류). 끝에 닿으면 마지막 것을 되풀이한다.
  final List<Object> states;
  final Object? setError;
  final String suggestion;
  final Object? suggestError;
  final Object? profileError;
  String currentName;

  final List<String> setCalls = [];
  int _fetchCount = 0;

  @override
  Future<NicknameState> fetchMyNicknameState() async {
    final index = _fetchCount < states.length ? _fetchCount : states.length - 1;
    _fetchCount++;
    final next = states[index];
    if (next is NicknameState) return next;
    throw next;
  }

  @override
  Future<String> setNickname(String raw) async {
    setCalls.add(raw);
    final error = setError;
    if (error != null) throw error;
    // 서버처럼 공백을 정리한 값을 저장하고 돌려준다.
    currentName = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    return currentName;
  }

  @override
  Future<String> suggestNickname() async {
    final error = suggestError;
    if (error != null) throw error;
    return suggestion;
  }

  @override
  Future<Profile> fetchMyProfile() async {
    final error = profileError;
    if (error != null) throw error;
    return Profile(id: 'me', displayName: currentName);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
