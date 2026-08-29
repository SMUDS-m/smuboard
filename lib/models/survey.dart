import 'package:intl/intl.dart';

import 'board_data.dart';
import 'sketch_map_options.dart';
import 'survey_enums.dart';
import 'survey_photo.dart';

/// 재난현장 조사 한 건.
///
/// 조사 개요(A~C)와 현황조사표(D~G), 현장사진(H)을 함께 들고 있으며,
/// 사진 보드·HWPX·시트 행이 모두 이 객체 하나에서 파생된다.
class Survey {
  Survey({
    required this.id,
    required this.createdAt,
    // A 조사개요
    this.surveyedAt,
    this.organization = '세명대학교 재난안전학과',
    this.inspectorName = '',
    this.inspectorContact = '',
    // B 재난개요
    this.disasterType = DisasterType.heavyRain,
    this.occurredAt,
    this.weather = '',
    // C 위치
    this.siteName = '',
    this.addressParcel = '',
    this.addressRoad = '',
    this.latitude,
    this.longitude,
    // D 피해시설
    this.facilityType = FacilityType.river,
    this.facilityName = '',
    this.manager = '',
    this.scaleLength = '',
    this.scaleWidth = '',
    this.scaleHeight = '',
    this.scaleArea = '',
    // E 피해현황
    this.damageLevel = DamageLevel.partial,
    this.casualtyDead = 0,
    this.casualtyInjured = 0,
    this.casualtyMissing = 0,
    this.casualtyEvacuated = 0,
    this.damageDescription = '',
    // F 원인·위험
    this.cause = '',
    this.riskLevel = RiskLevel.medium,
    this.riskFactor = '',
    // G 조치
    this.emergencyAction = '',
    this.opinion = '',
    // 부가
    this.sketchMap = const SketchMapOptions(),
    this.driveFolderId,
    this.driveFolderLink,
    this.submittedAt,
    List<SurveyPhoto>? photos,
  }) : photos = photos ?? <SurveyPhoto>[];

  final String id;
  final DateTime createdAt;

  DateTime? surveyedAt;
  String organization;
  String inspectorName;
  String inspectorContact;

  DisasterType disasterType;
  DateTime? occurredAt;
  String weather;

  /// 현장명. 폴더명과 파일명의 근간이 된다.
  String siteName;
  String addressParcel;
  String addressRoad;
  double? latitude;
  double? longitude;

  FacilityType facilityType;
  String facilityName;
  String manager;
  String scaleLength;
  String scaleWidth;
  String scaleHeight;
  String scaleArea;

  DamageLevel damageLevel;
  int casualtyDead;
  int casualtyInjured;
  int casualtyMissing;
  int casualtyEvacuated;
  String damageDescription;

  String cause;
  RiskLevel riskLevel;
  String riskFactor;

  String emergencyAction;
  String opinion;

  SketchMapOptions sketchMap;
  final List<SurveyPhoto> photos;

  String? driveFolderId;
  String? driveFolderLink;
  DateTime? submittedAt;

  bool get hasCoordinates => latitude != null && longitude != null;

  bool get isSubmitted => submittedAt != null;

  /// 조사번호. 생성 시각 기준이라 조사건마다 유일하다.
  String get surveyNumber =>
      'SMU-${DateFormat('yyyyMMdd-HHmm').format(createdAt)}';

  String get displayName =>
      siteName.trim().isEmpty ? '(현장명 미입력)' : siteName.trim();

  /// 드라이브 하위 폴더 이름. 파일명에 못 쓰는 문자는 걸러낸다.
  String get folderName {
    final date = DateFormat('yyyy-MM-dd').format(surveyedAt ?? createdAt);
    final safe = displayName.replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ').trim();
    return '${date}_$safe';
  }

  /// 사진 보드에 찍을 내용. 화면 미리보기와 최종 합성이 같은 값을 쓴다.
  BoardData toBoardData({DateTime? capturedAt, String? caption}) {
    return BoardData(
      siteName: displayName,
      workType: <String>[
        disasterType.label,
        facilityType.label,
        if (caption != null && caption.trim().isNotEmpty) caption.trim(),
      ].join(' · '),
      location: addressParcel.isNotEmpty ? addressParcel : addressRoad,
      contractor: <String>[
        organization,
        inspectorName,
      ].where((e) => e.trim().isNotEmpty).join(' / '),
      note: '',
      capturedAt: capturedAt,
      latitude: latitude,
      longitude: longitude,
      sketchMap: sketchMap,
    );
  }

  /// 아직 못 채운 필수 항목. 제출 화면에서 경고로 보여 준다.
  List<String> get missingFields {
    return <String>[
      if (siteName.trim().isEmpty) '현장명',
      if (inspectorName.trim().isEmpty) '조사자 성명',
      if (!hasCoordinates) '위치 좌표',
      if (occurredAt == null) '재난 발생일시',
      if (damageDescription.trim().isEmpty) '피해내용',
      if (photos.isEmpty) '현장사진',
    ];
  }

  String _fmt(DateTime? at) =>
      at == null ? '' : DateFormat('yyyy-MM-dd (E) HH:mm', 'ko_KR').format(at);

  String get coordinateText {
    if (!hasCoordinates) return '';
    return 'N ${latitude!.toStringAsFixed(6)}  E ${longitude!.toStringAsFixed(6)}';
  }

  /// HWPX 템플릿의 `{{키}}`를 채울 값. 설계 문서의 치환 키와 1:1로 맞춘다.
  Map<String, String> toTemplateValues() {
    return <String, String>{
      'survey_no': surveyNumber,
      'survey_at': _fmt(surveyedAt ?? createdAt),
      'organization': organization,
      'inspector_name': inspectorName,
      'inspector_contact': inspectorContact,
      'disaster_type': disasterType.label,
      'occurred_at': _fmt(occurredAt),
      'weather': weather,
      'site_name': displayName,
      'addr_parcel': addressParcel,
      'addr_road': addressRoad,
      'coordinates': coordinateText,
      'lat': latitude?.toStringAsFixed(6) ?? '',
      'lng': longitude?.toStringAsFixed(6) ?? '',
      'facility_type': facilityType.label,
      'facility_name': facilityName,
      'manager': manager,
      'scale_length': scaleLength,
      'scale_width': scaleWidth,
      'scale_height': scaleHeight,
      'scale_area': scaleArea,
      'damage_level': damageLevel.label,
      'casualty_dead': '$casualtyDead',
      'casualty_injured': '$casualtyInjured',
      'casualty_missing': '$casualtyMissing',
      'casualty_evacuated': '$casualtyEvacuated',
      'damage_desc': damageDescription,
      'cause': cause,
      'risk_level': riskLevel.label,
      'risk_factor': riskFactor,
      'emergency_action': emergencyAction,
      'opinion': opinion,
      'photo_count': '${photos.length}',
      for (var i = 0; i < 6; i++)
        'photo_caption_${i + 1}': i < photos.length ? photos[i].caption : '',
    };
  }

  /// 구글 시트 집계표에 한 줄로 들어갈 값.
  List<Object?> toSheetRow() {
    return <Object?>[
      surveyNumber,
      _fmt(surveyedAt ?? createdAt),
      disasterType.label,
      displayName,
      addressParcel.isNotEmpty ? addressParcel : addressRoad,
      latitude,
      longitude,
      facilityType.label,
      facilityName,
      damageLevel.label,
      casualtyDead,
      casualtyInjured,
      casualtyMissing,
      casualtyEvacuated,
      riskLevel.label,
      damageDescription,
      emergencyAction,
      opinion,
      inspectorName,
      photos.length,
      driveFolderLink ?? '',
    ];
  }

  /// 집계표 첫 줄. [toSheetRow]와 순서가 같아야 한다.
  static const List<String> sheetHeader = <String>[
    '조사번호',
    '조사일시',
    '재난유형',
    '현장명',
    '주소',
    '위도',
    '경도',
    '시설유형',
    '시설명',
    '피해정도',
    '사망',
    '부상',
    '실종',
    '대피',
    '2차위험도',
    '피해내용',
    '응급조치',
    '조치의견',
    '조사자',
    '사진수',
    '폴더링크',
  ];

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'surveyedAt': surveyedAt?.toIso8601String(),
    'organization': organization,
    'inspectorName': inspectorName,
    'inspectorContact': inspectorContact,
    'disasterType': disasterType.name,
    'occurredAt': occurredAt?.toIso8601String(),
    'weather': weather,
    'siteName': siteName,
    'addressParcel': addressParcel,
    'addressRoad': addressRoad,
    'latitude': latitude,
    'longitude': longitude,
    'facilityType': facilityType.name,
    'facilityName': facilityName,
    'manager': manager,
    'scaleLength': scaleLength,
    'scaleWidth': scaleWidth,
    'scaleHeight': scaleHeight,
    'scaleArea': scaleArea,
    'damageLevel': damageLevel.name,
    'casualtyDead': casualtyDead,
    'casualtyInjured': casualtyInjured,
    'casualtyMissing': casualtyMissing,
    'casualtyEvacuated': casualtyEvacuated,
    'damageDescription': damageDescription,
    'cause': cause,
    'riskLevel': riskLevel.name,
    'riskFactor': riskFactor,
    'emergencyAction': emergencyAction,
    'opinion': opinion,
    'sketchMap': sketchMap.toJson(),
    'driveFolderId': driveFolderId,
    'driveFolderLink': driveFolderLink,
    'submittedAt': submittedAt?.toIso8601String(),
    'photos': photos.map((p) => p.toJson()).toList(),
  };

  factory Survey.fromJson(Map<String, dynamic> json) {
    DateTime? parse(String? value) =>
        value == null ? null : DateTime.tryParse(value);

    return Survey(
      id: json['id'] as String,
      createdAt: parse(json['createdAt'] as String?) ?? DateTime.now(),
      surveyedAt: parse(json['surveyedAt'] as String?),
      organization: json['organization'] as String? ?? '세명대학교 재난안전학과',
      inspectorName: json['inspectorName'] as String? ?? '',
      inspectorContact: json['inspectorContact'] as String? ?? '',
      disasterType: DisasterType.fromName(json['disasterType'] as String?),
      occurredAt: parse(json['occurredAt'] as String?),
      weather: json['weather'] as String? ?? '',
      siteName: json['siteName'] as String? ?? '',
      addressParcel: json['addressParcel'] as String? ?? '',
      addressRoad: json['addressRoad'] as String? ?? '',
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      facilityType: FacilityType.fromName(json['facilityType'] as String?),
      facilityName: json['facilityName'] as String? ?? '',
      manager: json['manager'] as String? ?? '',
      scaleLength: json['scaleLength'] as String? ?? '',
      scaleWidth: json['scaleWidth'] as String? ?? '',
      scaleHeight: json['scaleHeight'] as String? ?? '',
      scaleArea: json['scaleArea'] as String? ?? '',
      damageLevel: DamageLevel.fromName(json['damageLevel'] as String?),
      casualtyDead: (json['casualtyDead'] as num?)?.toInt() ?? 0,
      casualtyInjured: (json['casualtyInjured'] as num?)?.toInt() ?? 0,
      casualtyMissing: (json['casualtyMissing'] as num?)?.toInt() ?? 0,
      casualtyEvacuated: (json['casualtyEvacuated'] as num?)?.toInt() ?? 0,
      damageDescription: json['damageDescription'] as String? ?? '',
      cause: json['cause'] as String? ?? '',
      riskLevel: RiskLevel.fromName(json['riskLevel'] as String?),
      riskFactor: json['riskFactor'] as String? ?? '',
      emergencyAction: json['emergencyAction'] as String? ?? '',
      opinion: json['opinion'] as String? ?? '',
      sketchMap: SketchMapOptions.fromJson(
        (json['sketchMap'] as Map<String, dynamic>?) ?? const <String, dynamic>{},
      ),
      driveFolderId: json['driveFolderId'] as String?,
      driveFolderLink: json['driveFolderLink'] as String?,
      submittedAt: parse(json['submittedAt'] as String?),
      photos: (json['photos'] as List<dynamic>? ?? const <dynamic>[])
          .cast<Map<String, dynamic>>()
          .map(SurveyPhoto.fromJson)
          .toList(),
    );
  }
}
