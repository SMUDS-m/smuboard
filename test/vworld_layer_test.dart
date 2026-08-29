import 'package:flutter_test/flutter_test.dart';
import 'package:smuboard/models/sketch_map_options.dart';

/// 레이어 이름은 브이월드 WMTS가 실제로 받는 것만 써야 한다. 없는 이름을 보내면
/// 이미지 대신 `InvalidParameterValue` XML이 돌아오고, 약도가 조용히 빈칸이 된다
/// (앱은 content-type을 보고 타일을 버린다). 아래 목록은 배포 도메인에서 직접
/// 호출해 이미지가 오는 것을 확인한 값이다.
void main() {
  const verified = <String>{'Base', 'Satellite', 'Hybrid', 'midnight', 'white'};

  test('모든 레이어 이름이 확인된 값이다', () {
    for (final layer in VWorldLayer.values) {
      expect(
        verified,
        contains(layer.id),
        reason: '${layer.id}는 브이월드에서 확인되지 않은 레이어 이름입니다.',
      );
      final overlay = layer.overlayId;
      if (overlay != null) expect(verified, contains(overlay));
    }
  });

  test('위성은 지명·도로가 담긴 Hybrid를 겹친다', () {
    expect(VWorldLayer.satellite.overlayId, 'Hybrid');
    // 위성 타일만 jpeg이고, 겹침 레이어는 투명이 필요해 png다.
    expect(VWorldLayer.satellite.extension, 'jpeg');
  });

  test('모르는 이름은 일반 지도로 되돌린다', () {
    // 예전 설정에 저장된 'gray'가 그대로 남아 있어도 빈 약도가 되지 않아야 한다.
    expect(VWorldLayer.fromId('gray'), VWorldLayer.base);
    expect(VWorldLayer.fromId(null), VWorldLayer.base);
  });
}
