import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smuboard/models/survey.dart';
import 'package:smuboard/models/survey_enums.dart';
import 'package:smuboard/models/survey_photo.dart';
import 'package:smuboard/services/drive_service.dart';
import 'package:smuboard/services/google_auth_service.dart';
import 'package:smuboard/services/offline/connectivity.dart';
import 'package:smuboard/services/offline/photo_blob_store.dart';
import 'package:smuboard/services/survey_store.dart';
import 'package:smuboard/services/upload_queue.dart';

/// 업로드를 흉내 내는 드라이브. 온/오프와 실패를 조종한다.
class _FakeDrive extends DriveService {
  _FakeDrive() : super(GoogleAuthService());

  bool failing = false;
  final List<String> uploaded = <String>[];

  @override
  Future<DriveFile> ensureSurveyFolder(Survey survey) async {
    survey.driveFolderId ??= 'folder-1';
    return const DriveFile(id: 'folder-1', name: '폴더');
  }

  @override
  Future<DriveFile> uploadBytes({
    required Survey survey,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    if (failing) throw const DriveException('네트워크 없음');
    uploaded.add(fileName);
    return DriveFile(id: 'file-${uploaded.length}', name: fileName);
  }
}

class _FakeConnectivity implements Connectivity {
  bool online = true;
  final StreamController<bool> _controller = StreamController<bool>.broadcast();

  @override
  bool get isOnline => online;

  @override
  Stream<bool> get changes => _controller.stream;

  void goOffline() {
    online = false;
    _controller.add(false);
  }

  void goOnline() {
    online = true;
    _controller.add(true);
  }

  @override
  void dispose() => _controller.close();
}

void main() {
  late PhotoBlobStore blobs;
  late _FakeDrive drive;
  late _FakeConnectivity connectivity;
  late SurveyStore store;
  late UploadQueue queue;
  var sharedQueueDisposed = false;
  var signedIn = true;

  /// 공용 큐도 연결 이벤트를 듣는다. 재시작 시나리오처럼 큐가 하나뿐이어야
  /// 하는 테스트에서는 먼저 이것을 닫는다.
  void disposeSharedQueue() {
    if (sharedQueueDisposed) return;
    sharedQueueDisposed = true;
    queue.dispose();
  }

  Uint8List bytesOf(int length, int fill) =>
      Uint8List.fromList(List<int>.filled(length, fill));

  Survey newSurvey() =>
      Survey(id: 'survey-1', createdAt: DateTime(2026, 8, 29), siteName: '○○천');

  SurveyPhoto newPhoto(String id) =>
      SurveyPhoto(id: id, capturedAt: DateTime(2026, 8, 29));

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    blobs = PhotoBlobStore();
    drive = _FakeDrive();
    connectivity = _FakeConnectivity();
    store = SurveyStore();
    sharedQueueDisposed = false;
    signedIn = true;
    queue = UploadQueue(
      blobs: blobs,
      drive: drive,
      store: store,
      connectivity: connectivity,
      canUpload: () => signedIn,
    );
  });

  tearDown(() {
    disposeSharedQueue();
    connectivity.dispose();
  });

  test('온라인이면 촬영 즉시 올라가고 원본 보관본은 지워진다', () async {
    final survey = newSurvey();
    final photo = newPhoto('p1');
    survey.photos.add(photo);

    await queue.enqueue(
      survey: survey,
      photo: photo,
      full: bytesOf(120, 1),
      thumbnail: bytesOf(20, 2),
    );

    expect(photo.state, UploadState.done);
    expect(drive.uploaded, hasLength(1));
    expect(queue.pendingCount, 0);
    // 원본은 정리하고, 축소본은 조사표와 목록에 필요하니 남긴다.
    expect(await blobs.get(UploadQueue.fullKey('p1')), isNull);
    expect(await blobs.get(UploadQueue.thumbKey('p1')), isNotNull);
  });

  test('오프라인이면 대기 상태로 기기에 보관된다', () async {
    connectivity.goOffline();
    final survey = newSurvey();
    final photo = newPhoto('p1');
    survey.photos.add(photo);

    await queue.enqueue(
      survey: survey,
      photo: photo,
      full: bytesOf(120, 1),
      thumbnail: bytesOf(20, 2),
    );

    expect(photo.state, UploadState.pending);
    expect(drive.uploaded, isEmpty);
    expect(queue.pendingCount, 1);
    // 통신이 없어도 원본은 남아 있어야 다시 찍지 않는다.
    expect(await blobs.get(UploadQueue.fullKey('p1')), hasLength(120));
  });

  test('연결이 돌아오면 대기분이 자동으로 올라간다', () async {
    connectivity.goOffline();
    final survey = newSurvey();
    for (final id in <String>['p1', 'p2']) {
      final photo = newPhoto(id);
      survey.photos.add(photo);
      await queue.enqueue(
        survey: survey,
        photo: photo,
        full: bytesOf(50, 1),
        thumbnail: bytesOf(10, 2),
      );
    }
    expect(queue.pendingCount, 2);

    connectivity.goOnline();
    // online 이벤트 구독이 drain을 부를 때까지 이벤트 루프를 돌린다.
    await Future<void>.delayed(Duration.zero);
    await queue.drain();

    expect(drive.uploaded, hasLength(2));
    expect(queue.pendingCount, 0);
    expect(survey.photos.every((p) => p.state == UploadState.done), isTrue);
  });

  test('업로드가 실패해도 대기로 남고 보관본을 지우지 않는다', () async {
    drive.failing = true;
    final survey = newSurvey();
    final photo = newPhoto('p1');
    survey.photos.add(photo);

    await queue.enqueue(
      survey: survey,
      photo: photo,
      full: bytesOf(80, 1),
      thumbnail: bytesOf(10, 2),
    );

    expect(photo.state, UploadState.pending);
    expect(photo.error, contains('네트워크 없음'));
    expect(await blobs.get(UploadQueue.fullKey('p1')), hasLength(80));
    expect(queue.retryIn, isNotNull);

    drive.failing = false;
    await queue.drain();
    expect(photo.state, UploadState.done);
    expect(queue.retryIn, isNull);
  });

  test('보관본이 사라지면 다시 촬영하라고 알린다', () async {
    connectivity.goOffline();
    final survey = newSurvey();
    final photo = newPhoto('p1');
    survey.photos.add(photo);
    await queue.enqueue(
      survey: survey,
      photo: photo,
      full: bytesOf(80, 1),
      thumbnail: bytesOf(10, 2),
    );

    // 브라우저 사이트 데이터 삭제 등으로 보관본이 없어진 상황.
    await blobs.remove(UploadQueue.fullKey('p1'));
    connectivity.goOnline();
    await queue.drain();

    expect(photo.state, UploadState.failed);
    expect(photo.error, contains('다시 촬영'));
  });

  test('새로고침 뒤에도 축소본이 보관소에서 복구된다', () async {
    final survey = newSurvey();
    final photo = newPhoto('p1');
    survey.photos.add(photo);
    await queue.enqueue(
      survey: survey,
      photo: photo,
      full: bytesOf(80, 1),
      thumbnail: bytesOf(24, 7),
    );

    // 탭이 새로 뜨면 메모리 캐시는 비어 있다.
    photo.thumbnail = null;
    expect(await queue.thumbnailOf(photo), hasLength(24));
    expect(photo.thumbnail, isNotNull);
  });

  test('제출이 끝나면 기기 보관본을 비운다', () async {
    final survey = newSurvey();
    final photo = newPhoto('p1');
    survey.photos.add(photo);
    await queue.enqueue(
      survey: survey,
      photo: photo,
      full: bytesOf(80, 1),
      thumbnail: bytesOf(24, 7),
    );

    await queue.releaseSurvey(survey);
    expect(await blobs.keys(), isEmpty);
  });

  test('로그인 전에는 올리지 않고 기기에 보관만 한다', () async {
    // 게스트로 둘러보는 개발 빌드에서 업로드 실패가 쌓이지 않아야 한다.
    signedIn = false;
    final survey = newSurvey();
    final photo = newPhoto('p1');
    survey.photos.add(photo);

    await queue.enqueue(
      survey: survey,
      photo: photo,
      full: bytesOf(90, 1),
      thumbnail: bytesOf(12, 2),
    );

    expect(queue.canUpload, isFalse);
    expect(drive.uploaded, isEmpty);
    expect(photo.state, UploadState.pending);
    expect(photo.error, isNull, reason: '로그인 전 대기는 실패가 아니다');
    expect(await blobs.get(UploadQueue.fullKey('p1')), hasLength(90));

    // 로그인하면 그대로 올라간다.
    signedIn = true;
    await queue.drain();
    expect(drive.uploaded, hasLength(1));
    expect(photo.state, UploadState.done);
  });

  test('지난 세션의 대기분을 시작 시 이어서 올린다', () async {
    // 이 시나리오는 큐를 두 번(닫히기 전/후) 만들어야 해서 공용 큐를 쓰지 않는다.
    UploadQueue build() => UploadQueue(
      blobs: blobs,
      drive: drive,
      store: store,
      connectivity: connectivity,
      canUpload: () => signedIn,
    );

    disposeSharedQueue();
    connectivity.goOffline();
    final before = build();
    final survey = newSurvey();
    final photo = newPhoto('p1');
    survey.photos.add(photo);
    await before.enqueue(
      survey: survey,
      photo: photo,
      full: bytesOf(80, 1),
      thumbnail: bytesOf(10, 2),
    );
    expect(before.pendingCount, 1);
    expect(drive.uploaded, isEmpty);

    // 탭이 닫힌다. 보관소와 조사 기록만 남는다.
    before.dispose();

    final after = build();
    addTearDown(after.dispose);
    connectivity.goOnline();
    await after.resume();

    expect(drive.uploaded, hasLength(1));
    expect(after.pendingCount, 0);
    // 올라간 뒤에는 원본 보관본이 정리된다.
    expect(await blobs.get(UploadQueue.fullKey('p1')), isNull);
  });
}
