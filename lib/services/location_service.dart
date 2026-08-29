import 'package:geolocator/geolocator.dart';

import 'vworld_service.dart';

/// 위치 조회 결과. 주소 변환은 실패할 수 있으므로 좌표와 분리해 둔다.
class LocationResult {
  const LocationResult({
    required this.latitude,
    required this.longitude,
    this.address,
  });

  final double latitude;
  final double longitude;

  /// 브이월드 역지오코딩 결과. 실패하면 null.
  final VWorldAddress? address;
}

/// 위치 권한이 없거나 서비스가 꺼져 있을 때 던진다.
class LocationUnavailable implements Exception {
  const LocationUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}

class LocationService {
  const LocationService(this._vworld);

  final VWorldService _vworld;

  /// 현재 좌표와 주소를 가져온다.
  ///
  /// 주소 변환은 네트워크가 필요하지만, 실패해도 좌표는 그대로 돌려준다.
  /// 현장에서 통신이 끊겨도 촬영은 계속돼야 하기 때문이다.
  Future<LocationResult> current() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationUnavailable(
        '위치 서비스가 꺼져 있습니다. 브라우저와 기기의 위치 설정을 확인해 주세요.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const LocationUnavailable('위치 권한이 거부되었습니다.');
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationUnavailable(
        '위치 권한이 영구 거부되었습니다. 브라우저 사이트 설정에서 위치를 허용해 주세요.',
      );
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      ),
    );

    return LocationResult(
      latitude: position.latitude,
      longitude: position.longitude,
      address: await _vworld.reverseGeocode(
        position.latitude,
        position.longitude,
      ),
    );
  }
}
