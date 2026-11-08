import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 번들 글꼴 목록(redesign design 3.1). pubspec에 적은 자산이 실제 파일로 있어야 빌드가 산다.
/// `flutter test`는 패키지 루트에서 돌므로 상대 경로로 읽는다.
void main() {
  const pretendardFiles = [
    'assets/fonts/pretendard/Pretendard-Regular.otf',
    'assets/fonts/pretendard/Pretendard-Bold.otf',
    'assets/fonts/pretendard/Pretendard-ExtraBold.otf',
  ];
  const pretendardLicense = 'assets/fonts/pretendard/LICENSE.txt';

  final pubspec = File('pubspec.yaml').readAsStringSync();

  test('pubspec에 Pretendard 패밀리와 세 굵기(400/700/800)가 적혀 있다', () {
    expect(pubspec, contains('- family: Pretendard'));
    for (final path in pretendardFiles) {
      expect(pubspec, contains('- asset: $path'), reason: path);
    }
    expect(pubspec, contains('weight: 400'));
    expect(pubspec, contains('weight: 700'));
    expect(pubspec, contains('weight: 800'));
  });

  test('Pretendard 라이선스 원문이 자산으로 등록돼 있다', () {
    expect(pubspec, contains('- $pretendardLicense'));
  });

  test('pubspec이 가리키는 Pretendard 파일과 라이선스가 실제로 있다', () {
    for (final path in [...pretendardFiles, pretendardLicense]) {
      expect(File(path).existsSync(), isTrue, reason: path);
    }
  });

  // 옛 픽셀 글꼴은 C26에서 지웠다. 이름을 직접 적지 않고 "Pretendard 말고는 없다"로 고정한다
  // (redesign plan의 최종 잔존 참조 grep이 test/까지 본다).
  // 주석(`#   - family: ...`, Flutter 템플릿 예시)은 세지 않는다.
  test('번들 글꼴 패밀리는 Pretendard 하나뿐이다', () {
    final families = RegExp(r'^\s*- family: (\S+)', multiLine: true).allMatches(pubspec).map((m) => m.group(1)).toList();
    expect(families, ['Pretendard']);
    final fontAssets = RegExp(r'^\s*- (?:asset: )?(assets/fonts/\S+)', multiLine: true).allMatches(pubspec).map((m) => m.group(1)!);
    expect(fontAssets.where((path) => !path.startsWith('assets/fonts/pretendard/')), isEmpty);
  });

  test('assets/fonts 아래에는 pretendard 폴더 하나뿐이다(옛 글꼴 파일이 남지 않는다)', () {
    final entries = Directory('assets/fonts').listSync().map((e) => e.uri.pathSegments.where((s) => s.isNotEmpty).last);
    expect(entries.toList(), ['pretendard']);
  });
}
