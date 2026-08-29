import 'package:flutter/foundation.dart';

/// 네이티브용 폴백. 프로세스가 사는 동안만 유지된다.
///
/// 이 앱은 모바일 웹이 주 대상이라 실제 내구성은 IndexedDB 구현이 담당한다.
/// 여기서는 같은 인터페이스만 맞춰 테스트와 네이티브 빌드가 돌아가게 한다.
class PhotoBlobStore {
  final Map<String, Uint8List> _memory = <String, Uint8List>{};

  /// 저장소가 탭 종료 후에도 살아남는지. UI 문구를 가르는 데 쓴다.
  bool get isDurable => false;

  Future<void> put(String key, Uint8List bytes) async {
    _memory[key] = bytes;
  }

  Future<Uint8List?> get(String key) async => _memory[key];

  Future<void> remove(String key) async {
    _memory.remove(key);
  }

  Future<void> removeAll(Iterable<String> keys) async {
    for (final key in keys) {
      _memory.remove(key);
    }
  }

  Future<List<String>> keys() async => _memory.keys.toList();

  /// 보관 중인 총 바이트. 저장 용량 안내에 쓴다.
  Future<int> totalBytes() async =>
      _memory.values.fold<int>(0, (sum, bytes) => sum + bytes.length);
}
