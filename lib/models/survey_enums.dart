// 조사표에서 고르는 값들. 라벨은 HWPX와 시트에 그대로 들어간다.

enum DisasterType {
  heavyRain('호우'),
  typhoon('태풍'),
  heavySnow('대설'),
  earthquake('지진'),
  landslide('산사태'),
  flood('하천범람'),
  fire('화재'),
  collapse('붕괴'),
  other('기타');

  const DisasterType(this.label);

  final String label;

  static DisasterType fromName(String? name) =>
      values.firstWhere((e) => e.name == name, orElse: () => DisasterType.other);
}

enum FacilityType {
  road('도로'),
  bridge('교량'),
  river('하천/제방'),
  slope('사면/옹벽'),
  building('건축물'),
  utility('상하수도'),
  farmland('농경지'),
  other('기타');

  const FacilityType(this.label);

  final String label;

  static FacilityType fromName(String? name) =>
      values.firstWhere((e) => e.name == name, orElse: () => FacilityType.other);
}

enum DamageLevel {
  total('전파'),
  half('반파'),
  partial('부분파손'),
  minor('경미');

  const DamageLevel(this.label);

  final String label;

  static DamageLevel fromName(String? name) =>
      values.firstWhere((e) => e.name == name, orElse: () => DamageLevel.partial);
}

enum RiskLevel {
  high('높음'),
  medium('보통'),
  low('낮음');

  const RiskLevel(this.label);

  final String label;

  static RiskLevel fromName(String? name) =>
      values.firstWhere((e) => e.name == name, orElse: () => RiskLevel.medium);
}

/// 산출물 업로드 진행 상태.
enum UploadState { pending, uploading, done, failed }
