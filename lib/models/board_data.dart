import 'package:intl/intl.dart';

import 'sketch_map_options.dart';

/// 사진대지 보드에 찍히는 한 장 분량의 정보.
///
/// [BoardPainter]가 이 값을 그대로 그리므로, 화면 미리보기와 최종 합성본이
/// 항상 같은 내용을 보여준다.
class BoardData {
  const BoardData({
    this.siteName = '',
    this.workType = '',
    this.location = '',
    this.contractor = '',
    this.note = '',
    this.capturedAt,
    this.latitude,
    this.longitude,
    this.showCoordinates = true,
    this.sketchMap = const SketchMapOptions(),
  });

  /// 현장명(공사명).
  final String siteName;

  /// 공종.
  final String workType;

  /// 위치 - 역지오코딩 주소 또는 직접 입력한 위치.
  final String location;

  /// 시공사/작업자.
  final String contractor;

  /// 비고.
  final String note;

  /// 촬영 일시. 비어 있으면 보드에서 일시 행을 그리지 않는다.
  final DateTime? capturedAt;

  final double? latitude;
  final double? longitude;

  /// 좌표를 보드에 함께 표시할지 여부.
  final bool showCoordinates;

  /// 약도(브이월드 배경지도) 표시 설정.
  final SketchMapOptions sketchMap;

  bool get hasCoordinates => latitude != null && longitude != null;

  /// 약도를 실제로 그릴 수 있는 상태인지. 좌표가 없으면 그릴 것이 없다.
  bool get wantsSketchMap => sketchMap.enabled && hasCoordinates;

  /// `2026-08-29 (토) 14:03` 형태. 요일을 포함한다.
  String get formattedDateTime {
    final at = capturedAt;
    if (at == null) return '';
    return DateFormat('yyyy-MM-dd (E) HH:mm', 'ko_KR').format(at);
  }

  /// `N 37.566535  E 126.977969` 형태.
  String get formattedCoordinates {
    if (!hasCoordinates) return '';
    final lat = latitude!;
    final lng = longitude!;
    final ns = lat >= 0 ? 'N' : 'S';
    final ew = lng >= 0 ? 'E' : 'W';
    return '$ns ${lat.abs().toStringAsFixed(6)}  '
        '$ew ${lng.abs().toStringAsFixed(6)}';
  }

  /// 보드에 실제로 그릴 행 목록. 값이 빈 항목은 제외한다.
  List<({String label, String value})> get rows {
    final entries = <({String label, String value})>[
      (label: '현장명', value: siteName),
      (label: '공　종', value: workType),
      (label: '위　치', value: location),
      (label: '일　시', value: formattedDateTime),
      if (showCoordinates) (label: '좌　표', value: formattedCoordinates),
      (label: '시공자', value: contractor),
      (label: '비　고', value: note),
    ];
    return entries.where((e) => e.value.trim().isNotEmpty).toList();
  }

  BoardData copyWith({
    String? siteName,
    String? workType,
    String? location,
    String? contractor,
    String? note,
    DateTime? capturedAt,
    double? latitude,
    double? longitude,
    bool? showCoordinates,
    SketchMapOptions? sketchMap,
  }) {
    return BoardData(
      siteName: siteName ?? this.siteName,
      workType: workType ?? this.workType,
      location: location ?? this.location,
      contractor: contractor ?? this.contractor,
      note: note ?? this.note,
      capturedAt: capturedAt ?? this.capturedAt,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      showCoordinates: showCoordinates ?? this.showCoordinates,
      sketchMap: sketchMap ?? this.sketchMap,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'siteName': siteName,
    'workType': workType,
    'location': location,
    'contractor': contractor,
    'note': note,
    'capturedAt': capturedAt?.toIso8601String(),
    'latitude': latitude,
    'longitude': longitude,
    'showCoordinates': showCoordinates,
    'sketchMap': sketchMap.toJson(),
  };

  factory BoardData.fromJson(Map<String, dynamic> json) {
    final capturedAt = json['capturedAt'] as String?;
    return BoardData(
      siteName: json['siteName'] as String? ?? '',
      workType: json['workType'] as String? ?? '',
      location: json['location'] as String? ?? '',
      contractor: json['contractor'] as String? ?? '',
      note: json['note'] as String? ?? '',
      capturedAt: capturedAt == null ? null : DateTime.tryParse(capturedAt),
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      showCoordinates: json['showCoordinates'] as bool? ?? true,
      sketchMap: SketchMapOptions.fromJson(
        (json['sketchMap'] as Map<String, dynamic>?) ?? const <String, dynamic>{},
      ),
    );
  }
}
