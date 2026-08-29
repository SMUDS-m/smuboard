import 'package:flutter/foundation.dart';

/// 네이티브에는 브라우저식 "다운로드"가 없다. 저장은 공유 시트로 처리한다.
Future<void> downloadBytes(
  Uint8List bytes,
  String fileName, {
  String mimeType = 'application/octet-stream',
}) async {
  throw UnsupportedError('이 플랫폼에서는 다운로드 대신 공유를 사용하세요.');
}

/// 이 플랫폼에서 직접 다운로드가 가능한지.
bool get supportsDownload => false;
