import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

@JS('JSON.stringify')
external String _stringify(JSAny? value);

int _sequence = 0;

/// 브라우저에서 CORS 헤더가 없는 API를 호출한다.
///
/// 브이월드 지오코더는 `Access-Control-Allow-Origin`을 주지 않아 fetch/XHR로는
/// 막히지만 `callback=` 파라미터를 붙이면 JSONP로 응답한다. 정적 호스팅(GitHub
/// Pages)에는 프록시를 둘 수 없으므로 이 경로가 사실상 유일한 방법이다.
Future<String> fetchJsonp(Uri uri, {String callbackParam = 'callback'}) {
  final name = '__smuboardJsonp${_sequence++}';
  final completer = Completer<String>();

  late final web.HTMLScriptElement script;
  var settled = false;

  void cleanUp() {
    globalContext.delete(name.toJS);
    script.remove();
  }

  void finish(void Function() action) {
    if (settled) return;
    settled = true;
    cleanUp();
    action();
  }

  globalContext.setProperty(
    name.toJS,
    (JSAny? data) {
      finish(() => completer.complete(_stringify(data)));
    }.toJS,
  );

  final target = uri.replace(
    queryParameters: <String, String>{
      ...uri.queryParameters,
      callbackParam: name,
    },
  );

  script = web.document.createElement('script') as web.HTMLScriptElement
    ..src = target.toString()
    ..async = true;
  script.onerror = (JSAny? _) {
    finish(
      () => completer.completeError(Exception('JSONP 요청 실패: ${uri.host}')),
    );
  }.toJS;

  web.document.head!.append(script);

  return completer.future.timeout(
    const Duration(seconds: 10),
    onTimeout: () {
      finish(() {});
      throw TimeoutException('응답이 없습니다: ${uri.host}');
    },
  );
}
