import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/survey.dart';
import '../models/survey_enums.dart';
import '../models/survey_photo.dart';
import 'board_composer.dart';
import 'drive_service.dart';
import 'location_service.dart';

/// 촬영 한 장이 거치는 전 과정: 합성 → 축소 → 드라이브 업로드.
///
/// 업로드를 조사 제출까지 미루지 않는 이유는 모바일 웹 때문이다. 탭이
/// 백그라운드에서 정리되면 메모리의 사진은 그대로 사라진다. 가장 잃기 쉬운
/// 것을 가장 오래 들고 있지 않도록, 합성이 끝나는 즉시 올린다.
class PhotoPipeline {
  const PhotoPipeline({
    required BoardComposer composer,
    required DriveService drive,
    required LocationService location,
  }) : _composer = composer,
       _drive = drive,
       _location = location;

  final BoardComposer _composer;
  final DriveService _drive;
  final LocationService _location;

  static const Uuid _uuid = Uuid();

  /// 사진을 합성해 조사에 추가하고, 곧바로 업로드를 시작한다.
  ///
  /// 업로드 결과를 기다리지 않고 [SurveyPhoto]를 먼저 돌려주므로 화면은 바로
  /// 다음 촬영으로 넘어갈 수 있다. 진행 상황은 [onUploaded]로 알린다.
  Future<SurveyPhoto> process({
    required Survey survey,
    required Uint8List photoBytes,
    required String caption,
    required VoidCallback onUploaded,
  }) async {
    final capturedAt = DateTime.now();

    // 촬영 지점은 장마다 다를 수 있다. 조사 대표 좌표와 별개로 남긴다.
    double? latitude = survey.latitude;
    double? longitude = survey.longitude;
    try {
      final here = await _location.current();
      latitude = here.latitude;
      longitude = here.longitude;
    } catch (_) {
      // 위치를 못 잡아도 촬영은 유효하다.
    }

    final composed = await _composer.compose(
      photoBytes,
      survey.toBoardData(capturedAt: capturedAt, caption: caption),
    );

    final photo = SurveyPhoto(
      id: _uuid.v4(),
      capturedAt: capturedAt,
      caption: caption,
      latitude: latitude,
      longitude: longitude,
      thumbnail: composed.thumbnail,
      state: UploadState.uploading,
    );
    survey.photos.add(photo);

    unawaited(_upload(survey, photo, composed.full, onUploaded));
    return photo;
  }

  /// 실패한 사진을 다시 올린다. 원본 바이트가 이미 없으므로 축소본을 올린다.
  ///
  /// 탭이 살아 있는 동안에는 축소본이 남아 있어 최소한 기록은 지킬 수 있다.
  Future<void> retry(
    Survey survey,
    SurveyPhoto photo,
    VoidCallback onUploaded,
  ) async {
    final bytes = photo.thumbnail;
    if (bytes == null) {
      photo.state = UploadState.failed;
      photo.error = '원본이 남아 있지 않습니다. 다시 촬영해 주세요.';
      onUploaded();
      return;
    }
    photo.state = UploadState.uploading;
    onUploaded();
    await _upload(survey, photo, bytes, onUploaded);
  }

  Future<void> _upload(
    Survey survey,
    SurveyPhoto photo,
    Uint8List bytes,
    VoidCallback onUploaded,
  ) async {
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
    } catch (e) {
      photo
        ..state = UploadState.failed
        ..error = '$e';
    }
    onUploaded();
  }
}

void unawaited(Future<void> future) {
  future.catchError((Object error) => debugPrint('업로드 처리 중 오류: $error'));
}
