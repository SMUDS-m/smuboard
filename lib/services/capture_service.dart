import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

/// 사진 한 장을 바이트로 가져온다.
///
/// 웹에서는 `capture` 속성이 붙은 파일 입력으로 이어져 기기의 기본 카메라 앱이
/// 열린다. 브라우저 안에서 getUserMedia 프리뷰를 띄우는 것보다 해상도가 훨씬
/// 높고, 초점·노출·플래시도 OS 카메라의 것을 그대로 쓴다.
class CaptureService {
  CaptureService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  Future<Uint8List?> takePhoto() => _pick(ImageSource.camera);

  Future<Uint8List?> pickFromGallery() => _pick(ImageSource.gallery);

  Future<Uint8List?> _pick(ImageSource source) async {
    final file = await _picker.pickImage(
      source: source,
      // 원본을 그대로 받는다. 축소는 합성 단계에서 한 번만 한다.
      imageQuality: 100,
      requestFullMetadata: false,
    );
    if (file == null) return null;
    return file.readAsBytes();
  }
}
