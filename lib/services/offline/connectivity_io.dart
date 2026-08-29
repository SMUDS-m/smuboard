import 'dart:async';

/// 네이티브 폴백. 브라우저의 online/offline 이벤트에 해당하는 것이 없으므로
/// 항상 연결된 것으로 보고, 실패는 업로드 시도에서 판단한다.
class Connectivity {
  bool get isOnline => true;

  Stream<bool> get changes => const Stream<bool>.empty();

  void dispose() {}
}
