import 'package:flutter/widgets.dart';

import 'services/board_composer.dart';
import 'services/capture_service.dart';
import 'services/drive_service.dart';
import 'services/google_auth_service.dart';
import 'services/location_service.dart';
import 'services/offline/connectivity.dart';
import 'services/offline/photo_blob_store.dart';
import 'services/photo_pipeline.dart';
import 'services/submit_service.dart';
import 'services/survey_store.dart';
import 'services/upload_queue.dart';
import 'services/vworld_service.dart';

/// 앱 전역 서비스 묶음.
///
/// 화면마다 서비스를 생성자로 줄줄이 넘기지 않도록 한곳에 모아 두고,
/// [AppScope]로 트리 아래에 내려 준다.
class AppServices {
  AppServices()
    : vworld = VWorldService(),
      auth = GoogleAuthService(),
      capture = CaptureService(),
      store = SurveyStore(),
      blobs = PhotoBlobStore(),
      connectivity = Connectivity() {
    location = LocationService(vworld);
    drive = DriveService(auth);
    queue = UploadQueue(
      blobs: blobs,
      drive: drive,
      store: store,
      connectivity: connectivity,
    );
    photos = PhotoPipeline(
      composer: BoardComposer(vworld),
      location: location,
      queue: queue,
    );
    submit = SubmitService(drive, queue);
  }

  final VWorldService vworld;
  final GoogleAuthService auth;
  final CaptureService capture;
  final SurveyStore store;

  /// 업로드 대기 사진의 기기 보관소.
  final PhotoBlobStore blobs;
  final Connectivity connectivity;

  late final LocationService location;
  late final DriveService drive;
  late final UploadQueue queue;
  late final PhotoPipeline photos;
  late final SubmitService submit;

  void dispose() {
    queue.dispose();
    connectivity.dispose();
    auth.dispose();
    vworld.dispose();
  }
}

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope가 트리에 없습니다.');
    return scope!.services;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      oldWidget.services != services;
}
