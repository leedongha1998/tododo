import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:todododo/features/battle/data/jpeg_metadata.dart';

/// 마커 하나와 내용으로 길이 있는 구역을 만든다.
List<int> _segment(int marker, List<int> payload) {
  final length = payload.length + 2;
  return [0xFF, marker, length >> 8, length & 0xFF, ...payload];
}

/// Orientation과 GPS IFD(그 안에 [gpsText])를 담은 EXIF 내용("Exif\0\0" + TIFF).
List<int> _exifPayload({required bool little, int? orientation, String gpsText = 'GPSMARK37.5'}) {
  List<int> u16(int v) => little ? [v & 0xFF, v >> 8] : [v >> 8, v & 0xFF];
  List<int> u32(int v) => little
      ? [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, v >> 24]
      : [v >> 24, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];

  final entries = <List<int>>[
    if (orientation != null) [...u16(0x0112), ...u16(3), ...u32(1), ...u16(orientation), 0, 0],
  ];
  final ifd0Size = 2 + (entries.length + 1) * 12 + 4;
  final gpsIfd = 8 + ifd0Size;
  entries.add([...u16(0x8825), ...u16(4), ...u32(1), ...u32(gpsIfd)]);
  final gpsData = gpsIfd + 2 + 12 + 4;
  final gpsBytes = [...ascii.encode(gpsText), 0];

  return [
    ...ascii.encode('Exif'), 0, 0,
    ...(little ? [0x49, 0x49] : [0x4D, 0x4D]), ...u16(42), ...u32(8),
    ...u16(entries.length), for (final e in entries) ...e, ...u32(0),
    ...u16(1), ...u16(0x0002), ...u16(2), ...u32(gpsBytes.length), ...u32(gpsData), ...u32(0),
    ...gpsBytes,
  ];
}

final _app0 = _segment(0xE0, [...ascii.encode('JFIF'), 0, 1, 1, 0, 0, 1, 0, 1, 0, 0]);
final _app2Icc = _segment(0xE2, [...ascii.encode('ICC_PROFILE'), 0, 1, 1, 9, 9]);
final _dqt = _segment(0xDB, [0x00, 1, 2, 3, 4]);
final _xmp = _segment(0xE1, [
  ...ascii.encode('http://ns.adobe.com/xap/1.0/'),
  0,
  ...ascii.encode('<exif:GPSLatitude>XMPGPS</exif:GPSLatitude>'),
]);
final _iptc = _segment(0xED, ascii.encode('Photoshop 3.0 IPTCMARK'));
final _comment = _segment(0xFE, ascii.encode('COMMENTMARK'));

/// SOS 헤더 + 엔트로피 데이터(0xFF 00 스터핑, 리스타트 마커 포함) + EOI.
final _scan = [
  0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F, 0x00,
  0x12, 0xFF, 0x00, 0x34, 0xFF, 0xD0, 0x56,
  0xFF, 0xD9,
];

Uint8List _jpeg(List<List<int>> header) =>
    Uint8List.fromList([0xFF, 0xD8, for (final s in header) ...s, ..._scan]);

bool _contains(Uint8List haystack, String needle) =>
    latin1.decode(haystack, allowInvalid: true).contains(needle);

void main() {
  group('stripJpegMetadata', () {
    for (final little in [true, false]) {
      test('GPS·XMP·IPTC·주석을 지우고 회전은 남긴다 (${little ? 'II' : 'MM'})', () {
        final input = _jpeg([
          _app0,
          _segment(0xE1, _exifPayload(little: little, orientation: 6)),
          _xmp,
          _app2Icc,
          _iptc,
          _comment,
          _dqt,
        ]);
        expect(_contains(input, 'GPSMARK'), isTrue, reason: '테스트 입력에 GPS가 들어 있어야 한다');

        final output = stripJpegMetadata(input);

        expect(_contains(output, 'GPSMARK'), isFalse);
        expect(_contains(output, 'XMPGPS'), isFalse);
        expect(_contains(output, 'IPTCMARK'), isFalse);
        expect(_contains(output, 'COMMENTMARK'), isFalse);
        expect(jpegOrientation(output), 6);
      });
    }

    test('그림에 필요한 구역과 스캔 데이터는 바이트 그대로 남는다', () {
      final input = _jpeg([
        _app0,
        _segment(0xE1, _exifPayload(little: true, orientation: 3)),
        _app2Icc,
        _dqt,
      ]);
      final output = stripJpegMetadata(input);

      // SOI → APP0 → (새 EXIF) → ICC → DQT → 스캔
      expect(output.sublist(0, 2), [0xFF, 0xD8]);
      expect(output.sublist(2, 2 + _app0.length), _app0);
      final exifStart = 2 + _app0.length;
      expect(output.sublist(exifStart, exifStart + 2), [0xFF, 0xE1]);
      final exifLength = (output[exifStart + 2] << 8) | output[exifStart + 3];
      final rest = output.sublist(exifStart + 2 + exifLength);
      expect(rest, [..._app2Icc, ..._dqt, ..._scan]);
    });

    test('회전이 1이거나 없으면 EXIF를 아예 쓰지 않는다', () {
      for (final orientation in [1, null]) {
        final output = stripJpegMetadata(_jpeg([
          _app0,
          _segment(0xE1, _exifPayload(little: true, orientation: orientation)),
          _dqt,
        ]));
        expect(output, [0xFF, 0xD8, ..._app0, ..._dqt, ..._scan]);
        expect(jpegOrientation(output), isNull);
      }
    });

    test('APP0이 없으면 새 EXIF는 SOI 바로 뒤에 온다', () {
      final output = stripJpegMetadata(_jpeg([
        _segment(0xE1, _exifPayload(little: false, orientation: 8)),
        _dqt,
      ]));
      expect(output.sublist(0, 4), [0xFF, 0xD8, 0xFF, 0xE1]);
      expect(jpegOrientation(output), 8);
      expect(output.sublist(output.length - _dqt.length - _scan.length), [..._dqt, ..._scan]);
    });

    test('두 번 걸러도 같다', () {
      final once = stripJpegMetadata(_jpeg([
        _app0,
        _segment(0xE1, _exifPayload(little: true, orientation: 6)),
        _xmp,
        _dqt,
      ]));
      expect(stripJpegMetadata(once), once);
    });

    test('메타데이터가 없으면 바뀌지 않는다', () {
      final input = _jpeg([_app0, _dqt]);
      expect(stripJpegMetadata(input), input);
    });

    test('JPEG가 아니거나 구조가 깨졌으면 받은 그대로 돌려준다', () {
      final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0, 0, 0, 0]);
      expect(stripJpegMetadata(png), same(png));

      // 길이가 파일 끝을 넘는 구역.
      final truncated = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE1, 0x10, 0x00, 1, 2, 3]);
      expect(stripJpegMetadata(truncated), same(truncated));

      // 스캔 없이 끝난 파일.
      final noScan = Uint8List.fromList([0xFF, 0xD8, ..._dqt, 0xFF, 0xD9]);
      expect(stripJpegMetadata(noScan), same(noScan));
    });
  });
}
