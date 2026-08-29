import 'package:flutter/foundation.dart';

import 'survey_enums.dart';

/// 현장사진 한 장.
///
/// 합성이 끝난 바이트는 업로드 직후 버린다. 모바일 웹 탭 메모리에 수십 장을
/// 들고 있을 수 없기 때문이다. 화면에는 [thumbnail]만 남기고, 원본은 드라이브의
/// [driveFileId]가 정본이 된다.
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

  /// 목록 표시용 축소 이미지. 세션이 끝나면 사라진다.
  final Uint8List? thumbnail;

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
