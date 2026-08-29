import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

/// 합성 결과를 브라우저 다운로드로 내려 준다.
///
/// 모바일 웹에서는 이것이 "갤러리에 저장"에 가장 가까운 동작이다. 안드로이드
/// 크롬은 다운로드 폴더로 받고, iOS 사파리는 "파일" 앱 저장을 묻는다.
Future<void> downloadBytes(
  Uint8List bytes,
  String fileName, {
  String mimeType = 'application/octet-stream',
}) async {
  final blob = web.Blob(
    <JSUint8Array>[bytes.toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = fileName
    ..style.display = 'none';

  web.document.body!.append(anchor);
  anchor.click();
  anchor.remove();

  // 즉시 해제하면 일부 브라우저에서 저장이 취소된다. 한 프레임 뒤에 정리한다.
  await Future<void>.delayed(const Duration(seconds: 1));
  web.URL.revokeObjectURL(url);
}

bool get supportsDownload => true;
