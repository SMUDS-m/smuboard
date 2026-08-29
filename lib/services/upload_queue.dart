import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/survey.dart';
import '../models/survey_enums.dart';
import '../models/survey_photo.dart';
import 'drive_service.dart';
import 'offline/connectivity.dart';
import 'offline/photo_blob_store.dart';
import 'survey_store.dart';

/// 업로드를 기다리는 사진을 기기에 보관했다가 통신이 되면 올린다.
///
/// 통신이 끊긴 현장에서도 촬영을 계속할 수 있어야 하고, 그 사이 브라우저 탭이
/// 정리돼도 사진이 남아야 한다. 그래서 합성 결과를 먼저 IndexedDB에 넣고,
/// 업로드가 확인된 뒤에야 지운다 - 순서가 반대면 실패한 사진이 사라진다.
class UploadQueue extends ChangeNotifier {
  UploadQueue({
    required PhotoBlobStore blobs,
    required DriveService drive,
    required SurveyStore store,
    required Connectivity connectivity,
  }) : _blobs = blobs,
       _drive = drive,
       _store = store,
       _connectivity = connectivity {
    _subscription = _connectivity.changes.listen((online) {
      if (online) {
        // 연결이 돌아오면 물러난 대기 시간을 접고 바로 시도한다.
        _backoff = _minBackoff;
        unawaited(drain());
      }
      notifyListeners();
    });
  }

  final PhotoBlobStore _blobs;
  final DriveService _drive;
  final SurveyStore _store;
  final Connectivity _connectivity;

  StreamSubscription<bool>? _subscription;
  Timer? _retryTimer;

  /// 진행 중인 업로드 한 바퀴. 겹쳐 돌지 않게 하면서도, 이미 돌고 있을 때
  /// [drain]을 부른 쪽이 그 결과를 기다릴 수 있게 한다.
  Future<void>? _drainTask;

  /// 화면이 들고 있는 조사 객체들.
  ///
  /// [SurveyStore]에서 다시 읽으면 같은 내용의 *다른* 객체가 나온다. 그것에
  /// 업로드 결과를 써 봐야 화면이 쥔 객체는 그대로여서 상태가 갱신되지 않는다.
  /// 그래서 살아 있는 인스턴스를 우선해 갱신한다.
  final Map<String, Survey> _live = <String, Survey>{};

  static const Duration _minBackoff = Duration(seconds: 20);
  static const Duration _maxBackoff = Duration(minutes: 10);
  Duration _backoff = _minBackoff;

  int _pending = 0;
  String? _lastError;

  /// 업로드를 기다리는 사진 수.
  int get pendingCount => _pending;

  bool get isOnline => _connectivity.isOnline;

  bool get isDraining => _drainTask != null;

  /// 마지막 실패 사유. 사용자에게 "왜 아직 안 올라갔는지"를 알려 준다.
  String? get lastError => _lastError;

  /// 다음 자동 재시도까지 남은 대기. 예약이 없으면 null.
  Duration? get retryIn => _retryTimer == null ? null : _backoff;

  /// 화면이 연 조사를 큐에 알린다. 업로드 결과가 그 객체에 반영된다.
  void track(Survey survey) {
    _live[survey.id] = survey;
  }

  static String fullKey(String photoId) => 'full:$photoId';

  static String thumbKey(String photoId) => 'thumb:$photoId';

  /// 촬영 직후 호출한다. 보관에 성공하면 바로 업로드를 시도한다.
  ///
  /// 보관이 실패하면(저장 공간 부족 등) 그 사실을 사진에 남기고 예외를 올린다.
  /// 조용히 메모리에만 두면 탭이 정리될 때 사진이 사라진다.
  Future<void> enqueue({
    required Survey survey,
    required SurveyPhoto photo,
    required Uint8List full,
    required Uint8List thumbnail,
  }) async {
    try {
      await _blobs.put(fullKey(photo.id), full);
      // 축소본은 업로드가 끝나도 남긴다. 목록 표시와 HWPX 조사표에 쓰이고,
      // 탭을 새로고침해도 사진이 사라지지 않아야 하기 때문이다.
      await _blobs.put(thumbKey(photo.id), thumbnail);
    } catch (e) {
      photo
        ..state = UploadState.failed
        ..error = '$e';
      _lastError = '$e';
      notifyListeners();
      rethrow;
    }

    photo.state = UploadState.pending;
    track(survey);
    await _store.save(survey);
    await drain();
  }

  /// 대기 중인 사진을 모두 올린다. 실패하면 물러났다가 다시 시도한다.
  ///
  /// 이미 돌고 있으면 그 작업을 돌려준다. 기다린 쪽이 "끝났겠지" 하고 결과를
  /// 보는 일이 없도록, 반환된 future는 항상 실제 완료를 가리킨다.
  Future<void> drain() {
    return _drainTask ??= _drainOnce().whenComplete(() => _drainTask = null);
  }

  Future<void> _drainOnce() async {
    _retryTimer?.cancel();
    _retryTimer = null;
    notifyListeners();

    var failed = false;
    try {
      final stored = await _store.loadAll();
      // 화면이 쥔 객체가 있으면 그것을 갱신 대상으로 삼는다.
      final surveys = stored
          .map((s) => _live[s.id] ?? s)
          .toList();
      var pending = 0;

      for (final survey in surveys) {
        final waiting = survey.photos
            .where((p) => p.state != UploadState.done)
            .toList();
        if (waiting.isEmpty) continue;

        var changed = false;
        for (final photo in waiting) {
          if (!_connectivity.isOnline) {
            pending += 1;
            failed = true;
            continue;
          }
          final uploaded = await _upload(survey, photo);
          changed = true;
          if (!uploaded) {
            pending += 1;
            failed = true;
          }
        }
        if (changed) await _store.save(survey);
      }

      _pending = pending;
      if (pending == 0) {
        _lastError = null;
        _backoff = _minBackoff;
      }
    } catch (e) {
      failed = true;
      _lastError = '$e';
    } finally {
      if (failed && _pending > 0) _scheduleRetry();
      notifyListeners();
    }
  }

  Future<bool> _upload(Survey survey, SurveyPhoto photo) async {
    final bytes = await _blobs.get(fullKey(photo.id));
    if (bytes == null) {
      // 보관본이 사라졌다(브라우저 데이터 삭제 등). 다시 찍는 수밖에 없다.
      photo
        ..state = UploadState.failed
        ..error = '보관된 원본이 없습니다. 다시 촬영해 주세요.';
      return false;
    }

    photo.state = UploadState.uploading;
    notifyListeners();

    try {
      final index = survey.photos.indexOf(photo) + 1;
      final file = await _drive.uploadBytes(
        survey: survey,
        bytes: bytes,
        fileName: photo.fileName(index),
        mimeType: 'image/jpeg',
      );
      photo
        ..driveFileId = file.id
        ..driveLink = file.link
        ..state = UploadState.done
        ..error = null;
      // 올라간 것을 확인한 뒤에 지운다.
      await _blobs.remove(fullKey(photo.id));
      return true;
    } catch (e) {
      photo
        ..state = UploadState.pending
        ..error = '$e';
      _lastError = '$e';
      return false;
    }
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer(_backoff, () {
      _retryTimer = null;
      unawaited(drain());
    });
    // 계속 실패하면 간격을 늘려 배터리와 통신을 아낀다.
    final next = _backoff * 2;
    _backoff = next > _maxBackoff ? _maxBackoff : next;
    notifyListeners();
  }

  /// 목록·조사표에 쓸 축소본. 메모리에 없으면 보관소에서 읽어 채운다.
  Future<Uint8List?> thumbnailOf(SurveyPhoto photo) async {
    final cached = photo.thumbnail;
    if (cached != null) return cached;
    final bytes = await _blobs.get(thumbKey(photo.id));
    if (bytes != null) photo.thumbnail = bytes;
    return bytes;
  }

  /// 제출이 끝난 조사의 보관본을 정리한다. 정본은 드라이브에 있다.
  Future<void> releaseSurvey(Survey survey) async {
    _live.remove(survey.id);
    await _blobs.removeAll(<String>[
      for (final photo in survey.photos) ...<String>[
        fullKey(photo.id),
        thumbKey(photo.id),
      ],
    ]);
  }

  /// 앱 시작 시 한 번. 지난 세션에서 못 올린 사진을 이어서 처리한다.
  Future<void> resume() async {
    final surveys = await _store.loadAll();
    _pending = surveys
        .expand((s) => s.photos)
        .where((p) => p.state != UploadState.done)
        .length;
    notifyListeners();
    if (_pending > 0) await drain();
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }
}
