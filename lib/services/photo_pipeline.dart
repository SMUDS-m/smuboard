import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/survey.dart';
import '../models/survey_enums.dart';
import '../models/survey_photo.dart';
import 'board_composer.dart';
import 'location_service.dart';
import 'upload_queue.dart';

/// 촬영 한 장이 거치는 전 과정: 위치 기록 → 합성 → 보관 → 업로드 큐.
///
/// 업로드를 조사 제출까지 미루지 않는다. 모바일 웹은 탭이 백그라운드에서
/// 정리되면 메모리의 사진이 사라지므로, 합성이 끝나는 즉시 기기에 보관하고
/// 통신이 되는 대로 올린다.
class PhotoPipeline {
  const PhotoPipeline({
    required BoardComposer composer,
    required LocationService location,
    required UploadQueue queue,
  }) : _composer = composer,
       _location = location,
       _queue = queue;

  final BoardComposer _composer;
  final LocationService _location;
  final UploadQueue _queue;

  static const Uuid _uuid = Uuid();

  /// 사진을 합성해 조사에 추가하고 업로드 큐에 넣는다.
  ///
  /// 통신이 없어도 여기까지는 성공한다. 보관에 실패한 경우에만 예외가 난다.
  Future<SurveyPhoto> process({
    required Survey survey,
    required Uint8List photoBytes,
    required String caption,
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
      state: UploadState.pending,
    );
    survey.photos.add(photo);

    await _queue.enqueue(
      survey: survey,
      photo: photo,
      full: composed.full,
      thumbnail: composed.thumbnail,
    );
    return photo;
  }
}
