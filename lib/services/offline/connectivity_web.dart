import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// 브라우저의 온라인 상태를 관찰한다.
///
/// `navigator.onLine`은 "랜선이 꽂혀 있다" 수준의 신호라 실제 통신 가능 여부를
/// 보장하지 않는다. 그래서 이 값은 재시도를 *앞당기는* 힌트로만 쓰고, 성공
/// 여부는 업로드 결과로 판단한다.
class Connectivity {
  Connectivity() {
    _onOnline = ((web.Event _) => _controller.add(true)).toJS;
    _onOffline = ((web.Event _) => _controller.add(false)).toJS;
    web.window.addEventListener('online', _onOnline);
    web.window.addEventListener('offline', _onOffline);
  }

  final StreamController<bool> _controller = StreamController<bool>.broadcast();

  late final JSFunction _onOnline;
  late final JSFunction _onOffline;

  bool get isOnline => web.window.navigator.onLine;

  Stream<bool> get changes => _controller.stream;

  void dispose() {
    web.window.removeEventListener('online', _onOnline);
    web.window.removeEventListener('offline', _onOffline);
    _controller.close();
  }
}
