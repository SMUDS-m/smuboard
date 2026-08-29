import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/sketch_map_options.dart';
import 'jsonp/jsonp.dart';

/// 역지오코딩 결과. 지번과 도로명을 모두 받아 둔다.
class VWorldAddress {
  const VWorldAddress({this.parcel, this.road, this.zipcode});

  /// 지번 주소.
  final String? parcel;

  /// 도로명 주소.
  final String? road;

  final String? zipcode;

  /// 사진대지에는 지번이 관행이라 지번을 우선한다.
  String? get preferred => parcel ?? road;
}

/// 브이월드 오픈API 클라이언트 - 배경지도 타일과 주소 변환.
class VWorldService {
  VWorldService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// 같은 타일을 반복해서 내려받지 않도록 세션 동안 들고 있는다.
  /// 약도는 촬영 장소가 비슷해 적중률이 높다.
  final Map<String, ui.Image> _tileCache = <String, ui.Image>{};

  static const int tileSize = 256;

  /// 적도 기준 픽셀당 미터. 축척 막대 계산에 쓴다.
  static const double _equatorMetersPerPixel = 156543.03392804097;

  bool get isConfigured => AppConfig.hasVWorldKey;

  /// 좌표를 지번/도로명 주소로 바꾼다. 실패하면 null.
  ///
  /// 브이월드 지오코더는 CORS 헤더를 주지 않으므로 웹에서는 JSONP로 부른다.
  Future<VWorldAddress?> reverseGeocode(double latitude, double longitude) async {
    if (!isConfigured) return null;
    try {
      final uri = Uri.https('api.vworld.kr', '/req/address', <String, String>{
        'service': 'address',
        'request': 'getAddress',
        'version': '2.0',
        'crs': 'epsg:4326',
        'point': '$longitude,$latitude',
        'format': 'json',
        'type': 'both',
        'key': AppConfig.vworldKey,
      });

      final body = await fetchJsonp(uri);
      final json = jsonDecode(body) as Map<String, dynamic>;
      final response = json['response'] as Map<String, dynamic>?;
      if (response == null || response['status'] != 'OK') return null;

      final results = response['result'] as List<dynamic>? ?? const <dynamic>[];
      String? parcel;
      String? road;
      String? zipcode;
      for (final entry in results.cast<Map<String, dynamic>>()) {
        final text = (entry['text'] as String?)?.trim();
        if (text == null || text.isEmpty) continue;
        zipcode ??= entry['zipcode'] as String?;
        if (entry['type'] == 'parcel') {
          parcel ??= text;
        } else if (entry['type'] == 'road') {
          road ??= text;
        }
      }
      if (parcel == null && road == null) return null;
      return VWorldAddress(parcel: parcel, road: road, zipcode: zipcode);
    } catch (e) {
      debugPrint('역지오코딩 실패: $e');
      return null;
    }
  }

  /// 지정한 좌표를 중심으로 [size] 크기의 약도 이미지를 만든다.
  ///
  /// 필요한 타일만 골라 이어 붙이고, 중심에 마커와 축척 막대를 얹는다.
  /// 지도 SDK를 띄우지 않으므로 최종 합성 캔버스에 그대로 그릴 수 있다.
  Future<ui.Image> renderSketchMap({
    required double latitude,
    required double longitude,
    required Size size,
    int zoom = 17,
    VWorldLayer layer = VWorldLayer.base,
  }) async {
    if (!isConfigured) {
      throw StateError('브이월드 인증키가 설정되지 않았습니다.');
    }

    final clampedZoom = zoom.clamp(6, 19);
    final center = _project(latitude, longitude, clampedZoom);
    final left = center.dx - size.width / 2;
    final top = center.dy - size.height / 2;

    final maxTile = (1 << clampedZoom) - 1;
    final firstX = (left / tileSize).floor();
    final lastX = ((left + size.width) / tileSize).ceil() - 1;
    final firstY = math.max(0, (top / tileSize).floor());
    final lastY = math.min(maxTile, ((top + size.height) / tileSize).ceil() - 1);

    // 타일은 병렬로 받는다. 실패한 타일은 빈칸으로 두고 나머지를 그린다.
    List<({int x, int y, Future<ui.Image?> image})> requestsFor(
      String layerId,
      String extension,
    ) {
      final requests = <({int x, int y, Future<ui.Image?> image})>[];
      for (var ty = firstY; ty <= lastY; ty++) {
        for (var tx = firstX; tx <= lastX; tx++) {
          final wrapped = tx % (maxTile + 1);
          requests.add((
            x: tx,
            y: ty,
            image: _tile(
              layerId,
              extension,
              clampedZoom,
              wrapped < 0 ? wrapped + maxTile + 1 : wrapped,
              ty,
            ),
          ));
        }
      }
      return requests;
    }

    final base = requestsFor(layer.id, layer.extension);
    final overlayId = layer.overlayId;
    final overlay = overlayId == null
        ? const <({int x, int y, Future<ui.Image?> image})>[]
        : requestsFor(overlayId, 'png');

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final bounds = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.clipRect(bounds);
    canvas.drawRect(bounds, Paint()..color = const Color(0xFFE9E6DF));

    // 배경을 먼저 깔고 겹침 레이어(도로·지명)를 위에 올린다.
    for (final group in <List<({int x, int y, Future<ui.Image?> image})>>[
      base,
      overlay,
    ]) {
      for (final request in group) {
        final tile = await request.image;
        if (tile == null) continue;
        canvas.drawImage(
          tile,
          Offset(request.x * tileSize - left, request.y * tileSize - top),
          Paint()..filterQuality = FilterQuality.medium,
        );
      }
    }

    _drawMarker(canvas, Offset(size.width / 2, size.height / 2), size);
    _drawScaleBar(canvas, size, latitude, clampedZoom);

    final picture = recorder.endRecording();
    try {
      return await picture.toImage(size.width.round(), size.height.round());
    } finally {
      picture.dispose();
    }
  }

  Future<ui.Image?> _tile(
    String layerId,
    String extension,
    int z,
    int x,
    int y,
  ) async {
    final key = '$layerId/$z/$y/$x';
    final cached = _tileCache[key];
    if (cached != null) return cached;

    try {
      final uri = Uri.https(
        'api.vworld.kr',
        '/req/wmts/1.0.0/${AppConfig.vworldKey}/$layerId/$z/$y/$x.$extension',
      );
      final response = await _client.get(uri);
      if (response.statusCode != 200) return null;
      // 인증 실패나 범위 밖 요청은 이미지 대신 XML 오류를 돌려준다.
      final contentType = response.headers['content-type'] ?? '';
      if (!contentType.startsWith('image/')) return null;

      final image = await decodeImageFromList(response.bodyBytes);
      _tileCache[key] = image;
      return image;
    } catch (e) {
      debugPrint('타일 로드 실패 ($key): $e');
      return null;
    }
  }

  /// 위경도 → 지정 줌의 전역 픽셀 좌표 (웹 메르카토르).
  static Offset _project(double latitude, double longitude, int zoom) {
    final worldPixels = tileSize * math.pow(2, zoom).toDouble();
    final x = (longitude + 180) / 360 * worldPixels;
    final clampedLat = latitude.clamp(-85.05112878, 85.05112878);
    final sin = math.sin(clampedLat * math.pi / 180);
    final y =
        (0.5 - math.log((1 + sin) / (1 - sin)) / (4 * math.pi)) * worldPixels;
    return Offset(x, y);
  }

  void _drawMarker(Canvas canvas, Offset center, Size size) {
    final scale = size.shortestSide / 200;
    final radius = 7.0 * scale;
    final tip = center + Offset(0, 16 * scale);

    final pin = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(center.dx - radius * 0.8, center.dy + radius * 0.6)
      ..lineTo(center.dx + radius * 0.8, center.dy + radius * 0.6)
      ..close();

    canvas.drawPath(pin, Paint()..color = const Color(0xFFD32F2F));
    canvas.drawCircle(center, radius, Paint()..color = const Color(0xFFD32F2F));
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * scale
        ..color = const Color(0xFFFFFFFF),
    );
    canvas.drawCircle(
      center,
      radius * 0.35,
      Paint()..color = const Color(0xFFFFFFFF),
    );
  }

  /// 좌하단 축척 막대. 약도만 보고도 거리 감을 잡을 수 있어야 한다.
  void _drawScaleBar(Canvas canvas, Size size, double latitude, int zoom) {
    final metersPerPixel =
        _equatorMetersPerPixel *
        math.cos(latitude * math.pi / 180) /
        math.pow(2, zoom);

    // 25~40% 폭에 들어오는 가장 큰 "깔끔한" 거리를 고른다.
    const candidates = <int>[10, 20, 50, 100, 200, 500, 1000, 2000];
    final maxPixels = size.width * 0.4;
    var meters = candidates.first;
    for (final candidate in candidates) {
      if (candidate / metersPerPixel <= maxPixels) meters = candidate;
    }
    final barWidth = meters / metersPerPixel;
    if (barWidth < 20) return;

    final scale = size.shortestSide / 200;
    final bottom = size.height - 8 * scale;
    final left = 8 * scale;
    final barHeight = 3.0 * scale;

    canvas.drawRect(
      Rect.fromLTWH(left - 2, bottom - barHeight - 12 * scale, barWidth + 4, barHeight + 14 * scale),
      Paint()..color = const Color(0xCCFFFFFF),
    );
    canvas.drawRect(
      Rect.fromLTWH(left, bottom - barHeight, barWidth, barHeight),
      Paint()..color = const Color(0xFF222222),
    );

    final label = meters >= 1000 ? '${meters ~/ 1000}km' : '${meters}m';
    TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: const Color(0xFF222222),
          fontSize: 9 * scale,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )
      ..layout()
      ..paint(canvas, Offset(left, bottom - barHeight - 11 * scale));
  }

  void dispose() {
    for (final image in _tileCache.values) {
      image.dispose();
    }
    _tileCache.clear();
    _client.close();
  }
}
