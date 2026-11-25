import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/features/auth/data/account_deletion_result.dart';

/// 탈퇴 응답 해석(kakao-login design 흐름 5·8.3). `kakaoUnlink`가 정확히 `failed`일 때만 다른 토스트가
/// 뜨고, 그 밖은 전부 기존 완료 토스트다 — 구버전 Edge(필드 없음)와도 맞아야 배포 순서에 묶이지 않는다.
void main() {
  test('카카오 연결 끊기가 실패했다고 오면 완료의 다른 판이다', () {
    expect(
      accountDeletionResultFrom({'deleted': true, 'kakaoUnlink': 'failed'}),
      AccountDeletionResult.doneKakaoUnlinkFailed,
    );
  });

  test('끊었거나 카카오가 아니면 그냥 완료다', () {
    expect(
      accountDeletionResultFrom({'deleted': true, 'kakaoUnlink': 'done'}),
      AccountDeletionResult.done,
    );
    expect(
      accountDeletionResultFrom({'deleted': true, 'kakaoUnlink': 'notKakao'}),
      AccountDeletionResult.done,
    );
  });

  test('필드가 없거나 모양이 다르면 완료로 읽는다', () {
    expect(accountDeletionResultFrom({'deleted': true}), AccountDeletionResult.done);
    expect(accountDeletionResultFrom(null), AccountDeletionResult.done);
    expect(accountDeletionResultFrom('{"kakaoUnlink":"failed"}'), AccountDeletionResult.done);
    expect(accountDeletionResultFrom({'kakaoUnlink': true}), AccountDeletionResult.done);
    expect(accountDeletionResultFrom(const ['failed']), AccountDeletionResult.done);
  });
}
