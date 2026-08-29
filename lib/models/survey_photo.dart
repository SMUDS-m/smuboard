import 'package:flutter/foundation.dart';

import 'survey_enums.dart';

/// 현장사진 한 장.
///
/// 합성 원본은 IndexedDB에 보관했다가 업로드가 확인되면 지운다(UploadQueue).
/// 메모리에는 [thumbnail]만 들고 있으며, 이것도 보관소에 복사본이 있어 탭을
/// 새로고침해도 복구된다. 업로드가 끝난 뒤의 정본은 드라이브의 [driveFileId]다.
class SurveyPhoto {
  SurveyPhoto({
    required this.id,
    required this.capturedAt,
    this.caption = '',
    this.latitude,
    this.longitude,
    this.thumbnail,
    this.driveFileId,
    this.driveLink,
    this.state = UploadState.pending,
    this.error,
  });

  final String id;
  final DateTime capturedAt;

  /// 사진 설명 한 줄(촬영 부위·공종).
  String caption;

  final double? latitude;
  final double? longitude;

  /// 목록 표시용 축소 이미지. 메모리 캐시이며, 원본은 보관소에 있다.
  Uint8List? thumbnail;

  String? driveFileId;
  String? driveLink;
  UploadState state;
  String? error;

  /// HWPX 사진 설명과 파일명에 쓰는 순번 붙은 이름.
  String fileName(int index) {
    final label = caption.trim().isEmpty ? '현장사진' : caption.trim();
    return '사진_${index.toString().padLeft(2, '0')}_$label.jpg';
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'capturedAt': capturedAt.toIso8601String(),
    'caption': caption,
    'latitude': latitude,
    'longitude': longitude,
    'driveFileId': driveFileId,
    'driveLink': driveLink,
    'state': state.name,
  };

  factory SurveyPhoto.fromJson(Map<String, dynamic> json) {
    return SurveyPhoto(
      id: json['id'] as String,
      capturedAt:
          DateTime.tryParse(json['capturedAt'] as String? ?? '') ??
          DateTime.now(),
      caption: json['caption'] as String? ?? '',
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      driveFileId: json['driveFileId'] as String?,
      driveLink: json['driveLink'] as String?,
      state: UploadState.values.firstWhere(
        (e) => e.name == json['state'],
        orElse: () => UploadState.pending,
      ),
    );
  }
}
