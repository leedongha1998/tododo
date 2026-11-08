import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:todododo/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Material Icons 고지는 Flutter SDK 원문(CC BY 4.0) 그대로 자산에 있다', () {
    final bytes = File(materialIconsLicenseAsset).readAsBytesSync();
    final text = String.fromCharCodes(bytes);
    expect(text, startsWith('Attribution 4.0 International'));
    expect(text, contains('Creative Commons Attribution 4.0 International Public License'));
    // Flutter SDK가 아이콘 글꼴과 함께 두는 원문과 바이트까지 같다(SDK 캐시가 있으면 대조한다).
    final flutterRoot = Platform.environment['FLUTTER_ROOT'];
    final sdkCopy = File('$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons_LICENSE.txt');
    if (flutterRoot != null && sdkCopy.existsSync()) {
      expect(bytes, sdkCopy.readAsBytesSync());
    }
    expect(File('pubspec.yaml').readAsStringSync(), contains('- $materialIconsLicenseAsset'));
  });

  test('오픈소스 라이선스 화면에 Pretendard(OFL)와 Material Icons(CC BY 4.0)가 올라간다', () async {
    LicenseRegistry.reset();
    addTearDown(LicenseRegistry.reset);
    registerFontLicenses();

    final entries = await LicenseRegistry.licenses.toList();
    String textOf(String package) => entries
        .where((entry) => entry.packages.contains(package))
        .expand((entry) => entry.paragraphs)
        .map((paragraph) => paragraph.text)
        .join('\n');

    expect(textOf('Pretendard'), contains('SIL OPEN FONT LICENSE'));
    expect(textOf('Material Icons'), contains('Attribution 4.0 International'));
  });
}
