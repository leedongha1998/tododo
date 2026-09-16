import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

/// 촬영한 증거 사진과 촬영 시각.
class EvidenceShot {
  const EvidenceShot({required this.bytes, required this.capturedAt});

  final Uint8List bytes;

  /// 촬영 직후 기록한 시각(UTC). 서버가 수신 시각과 대조하는 데만 쓰고 승부에는 쓰지 않는다.
  final DateTime capturedAt;
}

/// 증거 사진 촬영. **카메라만** 연다 — 갤러리에서 고르는 경로는 만들지 않는다(결정 5).
///
/// 앱 자체 뷰파인더(`camera` 패키지)를 쓰지 않는 이유: 조작된 기기에 대한 방어력이 다르지 않고
/// 권한·생명주기 코드만 늘어난다. 시스템 카메라 인텐트라 CAMERA 권한 선언도 필요 없다.
class EvidenceCamera {
  const EvidenceCamera();

  /// 사용자가 촬영을 취소하면 null.
  Future<EvidenceShot?> capture() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: 1600,
      imageQuality: 80,
    );
    if (file == null) return null;

    final bytes = await file.readAsBytes();
    // 시스템 카메라가 확인 화면을 거쳐 돌아오는 시간은 수 초~수십 초라 10분 규칙에 영향이 없다.
    return EvidenceShot(bytes: bytes, capturedAt: DateTime.now().toUtc());
  }
}
