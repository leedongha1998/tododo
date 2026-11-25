/// 탈퇴가 끝난 뒤 사용자에게 무엇을 말할지(kakao-login design 흐름 5).
///
/// 두 값 모두 **탈퇴는 성공**이다. 카카오 연결 끊기는 탈퇴 뒤에 한 번 시도하는 일이라(관문이 아니다)
/// 실패해도 실패 토스트가 아니라 완료 토스트의 다른 판으로 말한다 — 사용자가 할 수 있는 일(카카오
/// 설정에서 직접 끊기)이 있으므로 알린다.
enum AccountDeletionResult { done, doneKakaoUnlinkFailed }

/// Edge `delete-account`의 성공 응답(`{deleted: true, kakaoUnlink: 'done' | 'failed' | 'notKakao'}`)을
/// 읽는다. `kakaoUnlink`가 정확히 `'failed'`일 때만 [AccountDeletionResult.doneKakaoUnlinkFailed]이고,
/// 필드가 없거나 모양이 다르면 [AccountDeletionResult.done] — 구버전 Edge와도 맞아서 앱과 Edge의 배포
/// 순서에 묶이지 않는다.
AccountDeletionResult accountDeletionResultFrom(Object? data) {
  if (data is Map && data['kakaoUnlink'] == 'failed') {
    return AccountDeletionResult.doneKakaoUnlinkFailed;
  }
  return AccountDeletionResult.done;
}
