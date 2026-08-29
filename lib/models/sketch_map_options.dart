/// 약도에 쓸 브이월드 배경지도 종류.
enum VWorldLayer {
  base('Base', 'png', '일반'),
  satellite('Satellite', 'jpeg', '위성'),
  gray('gray', 'png', '회색');

  const VWorldLayer(this.id, this.extension, this.label);

  /// WMTS 경로에 들어가는 레이어 이름.
  final String id;

  /// 타일 확장자. 위성만 jpeg다.
  final String extension;

  /// UI에 보여줄 이름.
  final String label;

  static VWorldLayer fromId(String? id) => values.firstWhere(
    (layer) => layer.id == id,
    orElse: () => VWorldLayer.base,
  );
}

/// 약도를 사진의 어느 모서리에 붙일지.
///
/// 하단은 보드가 차지하므로 상단 두 곳만 고를 수 있다.
enum SketchMapCorner {
  topLeft('좌측 상단'),
  topRight('우측 상단');

  const SketchMapCorner(this.label);

  final String label;
}

/// 약도 표시 설정.
class SketchMapOptions {
  const SketchMapOptions({
    this.enabled = true,
    this.zoom = 17,
    this.layer = VWorldLayer.base,
    this.corner = SketchMapCorner.topRight,
    this.widthRatio = 0.30,
  });

  /// 약도를 합성할지 여부.
  final bool enabled;

  /// 브이월드 줌 레벨. 클수록 확대된다.
  final int zoom;

  final VWorldLayer layer;
  final SketchMapCorner corner;

  /// 사진 가로 대비 약도 폭 비율.
  final double widthRatio;

  SketchMapOptions copyWith({
    bool? enabled,
    int? zoom,
    VWorldLayer? layer,
    SketchMapCorner? corner,
    double? widthRatio,
  }) {
    return SketchMapOptions(
      enabled: enabled ?? this.enabled,
      zoom: zoom ?? this.zoom,
      layer: layer ?? this.layer,
      corner: corner ?? this.corner,
      widthRatio: widthRatio ?? this.widthRatio,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'enabled': enabled,
    'zoom': zoom,
    'layer': layer.id,
    'corner': corner.name,
    'widthRatio': widthRatio,
  };

  factory SketchMapOptions.fromJson(Map<String, dynamic> json) {
    return SketchMapOptions(
      enabled: json['enabled'] as bool? ?? true,
      zoom: (json['zoom'] as num?)?.toInt() ?? 17,
      layer: VWorldLayer.fromId(json['layer'] as String?),
      corner: SketchMapCorner.values.firstWhere(
        (c) => c.name == json['corner'],
        orElse: () => SketchMapCorner.topRight,
      ),
      widthRatio: (json['widthRatio'] as num?)?.toDouble() ?? 0.30,
    );
  }
}
