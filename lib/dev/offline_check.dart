// IndexedDB 보관소 동작 확인용 개발 진입점. 배포 번들에는 들어가지 않는다.
//
//   flutter run -t lib/dev/offline_check.dart -d chrome
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/offline/connectivity.dart';
import '../services/offline/photo_blob_store.dart';

void main() => runApp(const _App());

class _App extends StatelessWidget {
  const _App();

  @override
  Widget build(BuildContext context) =>
      const MaterialApp(debugShowCheckedModeBanner: false, home: _Check());
}

class _Check extends StatefulWidget {
  const _Check();

  @override
  State<_Check> createState() => _CheckState();
}

class _CheckState extends State<_Check> {
  final List<({String name, bool ok, String detail})> _results = [];
  final Connectivity _connectivity = Connectivity();
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _connectivity.dispose();
    super.dispose();
  }

  Future<void> _check(String name, Future<String> Function() body) async {
    try {
      final detail = await body();
      _results.add((name: name, ok: true, detail: detail));
    } catch (e) {
      _results.add((name: name, ok: false, detail: '$e'));
    }
    if (mounted) setState(() {});
  }

  Future<void> _run() async {
    final store = PhotoBlobStore();

    await _check('저장소가 내구성 있는가', () async {
      if (!store.isDurable) throw StateError('메모리 폴백이 잡혔습니다.');
      return 'IndexedDB';
    });

    // 실제 합성 사진에 가까운 크기로 넣어 본다(2MB).
    final big = Uint8List(2 * 1024 * 1024);
    for (var i = 0; i < big.length; i += 997) {
      big[i] = i % 251;
    }

    await _check('2MB 사진 저장', () async {
      await store.put('full:dev-1', big);
      return '${(big.length / 1024).round()}KB 기록';
    });

    await _check('읽어서 바이트가 같은가', () async {
      final back = await store.get('full:dev-1');
      if (back == null) throw StateError('읽지 못했습니다.');
      if (back.length != big.length) {
        throw StateError('길이 불일치 ${back.length} != ${big.length}');
      }
      for (var i = 0; i < big.length; i += 9973) {
        if (back[i] != big[i]) throw StateError('$i 바이트 불일치');
      }
      return '${back.length} 바이트, 표본 대조 일치';
    });

    await _check('여러 건 저장 후 키 목록', () async {
      await store.put('thumb:dev-1', Uint8List.fromList(<int>[1, 2, 3]));
      await store.put('full:dev-2', Uint8List.fromList(<int>[4, 5]));
      final keys = await store.keys()..sort();
      return keys.join(', ');
    });

    await _check('없는 키는 null', () async {
      final missing = await store.get('full:없음');
      if (missing != null) throw StateError('null이 아닙니다.');
      return 'null';
    });

    await _check('총 보관량', () async {
      return '${(await store.totalBytes() / 1024).round()}KB';
    });

    await _check('한 건 삭제', () async {
      await store.remove('full:dev-2');
      if (await store.get('full:dev-2') != null) throw StateError('남아 있습니다.');
      return '삭제됨';
    });

    await _check('여러 건 삭제', () async {
      await store.removeAll(<String>['full:dev-1', 'thumb:dev-1']);
      final keys = await store.keys();
      if (keys.isNotEmpty) throw StateError('남은 키: $keys');
      return '보관소 비움';
    });

    await _check('새 인스턴스에서도 이어서 읽히는가', () async {
      await store.put('full:dev-persist', Uint8List.fromList(<int>[9, 9, 9]));
      final reopened = PhotoBlobStore();
      final back = await reopened.get('full:dev-persist');
      if (back == null || back.length != 3) throw StateError('복구 실패');
      await reopened.removeAll(await reopened.keys());
      return '같은 DB를 다시 열어 읽음';
    });

    await _check('연결 상태를 읽는가', () async {
      return _connectivity.isOnline ? '온라인' : '오프라인';
    });

    if (mounted) setState(() => _done = true);
  }

  @override
  Widget build(BuildContext context) {
    final failed = _results.where((r) => !r.ok).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('오프라인 보관소 점검'),
        backgroundColor: !_done
            ? null
            : failed == 0
            ? Colors.green.shade100
            : Colors.red.shade100,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(
            _done ? '완료 · 실패 $failed건' : '실행 중…',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          for (final r in _results)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                r.ok ? Icons.check_circle : Icons.error,
                color: r.ok ? Colors.green : Colors.red,
                size: 20,
              ),
              title: Text(r.name),
              subtitle: Text(r.detail),
            ),
        ],
      ),
    );
  }
}
