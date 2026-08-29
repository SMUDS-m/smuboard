import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

/// 촬영한 사진 바이트를 IndexedDB에 보관한다.
///
/// localStorage는 보통 5MB 남짓이라 합성 사진 한 장에도 넘친다. IndexedDB는
/// 용량이 훨씬 크고 바이너리를 그대로 담을 수 있어, 통신이 끊긴 현장에서
/// 업로드를 기다리는 동안 탭이 정리돼도 사진이 남는다.
class PhotoBlobStore {
  static const String _dbName = 'smuboard';
  static const String _storeName = 'photo_blobs';
  static const int _version = 1;

  Future<web.IDBDatabase>? _opening;

  bool get isDurable => true;

  Future<web.IDBDatabase> _database() {
    return _opening ??= _open().catchError((Object e) {
      // 다음 호출에서 다시 시도할 수 있게 실패한 연결은 버린다.
      _opening = null;
      throw e;
    });
  }

  Future<web.IDBDatabase> _open() {
    final completer = Completer<web.IDBDatabase>();
    final request = web.window.indexedDB.open(_dbName, _version);

    request.onupgradeneeded = (web.Event _) {
      final db = request.result as web.IDBDatabase;
      if (!db.objectStoreNames.contains(_storeName)) {
        db.createObjectStore(_storeName);
      }
    }.toJS;

    request.onsuccess = (web.Event _) {
      completer.complete(request.result as web.IDBDatabase);
    }.toJS;

    request.onerror = (web.Event _) {
      completer.completeError(
        // 시크릿 모드나 사이트 데이터 차단 설정에서는 열리지 않는다.
        StateError('IndexedDB를 열지 못했습니다: ${request.error?.message ?? ''}'),
      );
    }.toJS;

    return completer.future;
  }

  /// 쓰기 트랜잭션. 트랜잭션이 완료돼야 디스크에 남은 것으로 본다.
  Future<void> _write(void Function(web.IDBObjectStore store) body) async {
    final db = await _database();
    final transaction = db.transaction(_storeName.toJS, 'readwrite');
    final completer = Completer<void>();

    transaction.oncomplete = (web.Event _) {
      if (!completer.isCompleted) completer.complete();
    }.toJS;
    transaction.onerror = (web.Event _) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError('IndexedDB 쓰기 실패: ${transaction.error?.message ?? ''}'),
        );
      }
    }.toJS;
    // abort는 대부분 저장 용량 초과다.
    transaction.onabort = (web.Event _) {
      if (!completer.isCompleted) completer.completeError(const _QuotaExceeded());
    }.toJS;

    body(transaction.objectStore(_storeName));
    return completer.future;
  }

  /// 읽기 트랜잭션. 요청 결과를 그대로 돌려준다.
  Future<JSAny?> _read(
    web.IDBRequest Function(web.IDBObjectStore store) body,
  ) async {
    final db = await _database();
    final transaction = db.transaction(_storeName.toJS, 'readonly');
    final request = body(transaction.objectStore(_storeName));
    final completer = Completer<JSAny?>();

    request.onsuccess = (web.Event _) {
      if (!completer.isCompleted) completer.complete(request.result);
    }.toJS;
    request.onerror = (web.Event _) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError('IndexedDB 읽기 실패: ${request.error?.message ?? ''}'),
        );
      }
    }.toJS;

    return completer.future;
  }

  Future<void> put(String key, Uint8List bytes) async {
    try {
      await _write((store) => store.put(bytes.toJS, key.toJS));
    } on _QuotaExceeded {
      throw StateError(
        '기기 저장 공간이 부족해 사진을 보관하지 못했습니다. '
        '업로드가 끝난 조사를 정리한 뒤 다시 시도해 주세요.',
      );
    }
  }

  Future<Uint8List?> get(String key) async {
    final result = await _read((store) => store.get(key.toJS));
    return result == null ? null : (result as JSUint8Array).toDart;
  }

  Future<void> remove(String key) async {
    await _write((store) => store.delete(key.toJS));
  }

  Future<void> removeAll(Iterable<String> keys) async {
    if (keys.isEmpty) return;
    await _write((store) {
      for (final key in keys) {
        store.delete(key.toJS);
      }
    });
  }

  Future<List<String>> keys() async {
    final result = await _read((store) => store.getAllKeys());
    if (result == null) return <String>[];
    return (result as JSArray<JSString>).toDart
        .map((key) => key.toDart)
        .toList();
  }

  Future<int> totalBytes() async {
    var total = 0;
    for (final key in await keys()) {
      total += (await get(key))?.length ?? 0;
    }
    return total;
  }
}

/// 저장 용량 초과. 트랜잭션이 abort될 때 나온다.
class _QuotaExceeded implements Exception {
  const _QuotaExceeded();
}
