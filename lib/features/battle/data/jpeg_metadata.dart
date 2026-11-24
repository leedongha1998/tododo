import 'dart:typed_data';

/// 증거 사진에서 메타데이터를 걷어낸다(2026-11-24 보안 점검 높음 3).
///
/// 증거 사진은 **모르는 상대**에게 그대로 내려간다. 그런데 `image_picker`(Android)는 크기를 줄여
/// 다시 인코딩하면서 원본의 EXIF를 골라 복사하고, 그 목록에 GPS 태그 32개가 들어 있다
/// (`ExifDataCopier.java`). 기기 카메라의 위치 저장이 켜져 있으면 사진 파일에 촬영 장소 — 대개
/// 집이다 — 가 남는다. `requestFullMetadata: false`는 Android에서 이 복사를 끄지 않는다.
///
/// 그래서 올리기 직전에 메타데이터 구역을 통째로 지운다.
/// - **지우는 것**: APP1(EXIF·XMP — GPS, 기기 모델, 촬영 시각, 소프트웨어), APP13(IPTC),
///   COM(주석).
/// - **남기는 것**: 그림을 그리는 데 필요한 나머지 전부(APP0 JFIF, APP2 ICC 색 프로필, APP14 Adobe
///   색 변환, 양자화·허프만 표, 프레임, 스캔 데이터) — 바이트 그대로다.
/// - **회전 하나만 되살린다.** Android가 다시 인코딩한 픽셀은 회전되지 않은 채이고 "몇 도 돌려
///   보라"는 EXIF Orientation이 그 보정을 맡는다. 통째로 지우면 세로 사진이 눕는다 — 그래서
///   원래 값이 1(그대로)이 아니면 Orientation **하나만** 담은 최소 EXIF를 새로 쓴다.
///
/// 촬영 시각은 이 파일과 상관없다 — 앱이 따로 보내고 서버가 수신 시각과 대조한다.
///
/// JPEG가 아니거나 구조가 깨져 있으면 **받은 바이트를 그대로** 돌려준다. `image_picker`가
/// 방금 인코딩한 파일에서는 일어나지 않고, 그때 제출 자체를 막으면 속도전에서 사용자가 진다.
Uint8List stripJpegMetadata(Uint8List bytes) {
  final header = _readHeader(bytes);
  if (header == null) return bytes;

  var orientation = 1;
  final out = BytesBuilder(copy: false)..add(const [0xFF, 0xD8]);
  final kept = BytesBuilder(copy: false);
  for (final segment in header.segments) {
    if (segment.marker == 0xE1) {
      final value = _exifOrientation(bytes, segment);
      if (value != null) orientation = value;
      continue;
    }
    if (segment.marker == 0xED || segment.marker == 0xFE) continue;
    kept.add(Uint8List.sublistView(bytes, segment.start, segment.end));
  }

  // JFIF(APP0)가 있으면 그 뒤에, 없으면 SOI 바로 뒤에 둔다 — 두 자리 모두 표준 판독기가 읽는다.
  final keptBytes = kept.takeBytes();
  final hasApp0 = keptBytes.length >= 2 && keptBytes[0] == 0xFF && keptBytes[1] == 0xE0;
  if (hasApp0) {
    final app0End = 2 + ((keptBytes[2] << 8) | keptBytes[3]);
    out.add(Uint8List.sublistView(keptBytes, 0, app0End));
    if (orientation != 1) out.add(_orientationOnlyExif(orientation));
    out.add(Uint8List.sublistView(keptBytes, app0End));
  } else {
    if (orientation != 1) out.add(_orientationOnlyExif(orientation));
    out.add(keptBytes);
  }

  // 스캔(SOS) 이후는 손대지 않는다.
  out.add(Uint8List.sublistView(bytes, header.scanStart));
  return out.takeBytes();
}

/// EXIF Orientation(1~8). JPEG가 아니거나 값이 없으면 null. 테스트와 진단용.
int? jpegOrientation(Uint8List bytes) {
  final header = _readHeader(bytes);
  if (header == null) return null;
  for (final segment in header.segments) {
    if (segment.marker != 0xE1) continue;
    final value = _exifOrientation(bytes, segment);
    if (value != null) return value;
  }
  return null;
}

class _Segment {
  const _Segment(this.marker, this.start, this.end);

  /// 0xFF 다음 바이트.
  final int marker;

  /// 0xFF부터 이 구역 끝(다음 구역 시작)까지.
  final int start;
  final int end;
}

/// SOI 뒤부터 SOS **직전**까지의 구역들과 SOS가 시작하는 자리. SOS부터는 엔트로피 데이터라
/// 길이로 걸을 수 없으므로 바이트 그대로 옮긴다. 구조가 어긋나면 null.
({List<_Segment> segments, int scanStart})? _readHeader(Uint8List bytes) {
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) return null;
  final segments = <_Segment>[];
  var i = 2;
  while (i + 1 < bytes.length) {
    if (bytes[i] != 0xFF) return null;
    // 채움 바이트(0xFF 연속)를 건너뛴다.
    var markerAt = i + 1;
    while (markerAt < bytes.length && bytes[markerAt] == 0xFF) {
      markerAt += 1;
    }
    if (markerAt >= bytes.length) return null;
    final marker = bytes[markerAt];
    // 스캔 시작. 여기까지가 헤더다(채움 바이트가 있었다면 그것도 스캔 쪽에 그대로 남는다).
    if (marker == 0xDA) return (segments: segments, scanStart: i);
    if (marker == 0xD9) return null; // 스캔 없이 끝났다.
    if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
      segments.add(_Segment(marker, i, markerAt + 1));
      i = markerAt + 1;
      continue;
    }
    if (markerAt + 2 >= bytes.length) return null;
    final length = (bytes[markerAt + 1] << 8) | bytes[markerAt + 2];
    if (length < 2) return null;
    final end = markerAt + 1 + length;
    if (end > bytes.length) return null;
    segments.add(_Segment(marker, i, end));
    i = end;
  }
  return null;
}

const _exifHeader = [0x45, 0x78, 0x69, 0x66, 0x00, 0x00]; // "Exif\0\0"

/// APP1 구역이 EXIF면 IFD0의 Orientation을 읽는다. EXIF가 아니거나(XMP 등) 읽을 수 없으면 null.
int? _exifOrientation(Uint8List bytes, _Segment segment) {
  // 0xFF, 마커, 길이 2바이트 뒤가 내용이다.
  final payload = segment.start + 4;
  if (payload + _exifHeader.length + 8 > segment.end) return null;
  for (var k = 0; k < _exifHeader.length; k++) {
    if (bytes[payload + k] != _exifHeader[k]) return null;
  }
  final tiff = payload + _exifHeader.length;
  final bool little;
  if (bytes[tiff] == 0x49 && bytes[tiff + 1] == 0x49) {
    little = true;
  } else if (bytes[tiff] == 0x4D && bytes[tiff + 1] == 0x4D) {
    little = false;
  } else {
    return null;
  }

  int u16(int at) => little ? bytes[at] | (bytes[at + 1] << 8) : (bytes[at] << 8) | bytes[at + 1];
  int u32(int at) => little
      ? bytes[at] | (bytes[at + 1] << 8) | (bytes[at + 2] << 16) | (bytes[at + 3] << 24)
      : (bytes[at] << 24) | (bytes[at + 1] << 16) | (bytes[at + 2] << 8) | bytes[at + 3];

  final ifd0 = tiff + u32(tiff + 4);
  if (ifd0 + 2 > segment.end) return null;
  final count = u16(ifd0);
  for (var n = 0; n < count; n++) {
    final entry = ifd0 + 2 + n * 12;
    if (entry + 12 > segment.end) return null;
    if (u16(entry) != 0x0112) continue;
    final value = u16(entry + 8);
    return value >= 1 && value <= 8 ? value : null;
  }
  return null;
}

/// Orientation 하나만 담은 APP1(EXIF) 구역. 빅 엔디언, IFD0 한 항목, 다음 IFD 없음.
Uint8List _orientationOnlyExif(int orientation) {
  return Uint8List.fromList([
    0xFF, 0xE1, 0x00, 0x22, // APP1, 길이 34(길이 2바이트 포함)
    ..._exifHeader,
    0x4D, 0x4D, 0x00, 0x2A, 0x00, 0x00, 0x00, 0x08, // "MM", 42, IFD0는 TIFF 시작 + 8
    0x00, 0x01, // 항목 1개
    0x01, 0x12, 0x00, 0x03, 0x00, 0x00, 0x00, 0x01, // Orientation, SHORT, 1개
    0x00, orientation, 0x00, 0x00, // 값
    0x00, 0x00, 0x00, 0x00, // 다음 IFD 없음
  ]);
}
