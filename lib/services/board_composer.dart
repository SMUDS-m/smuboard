import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;

import '../models/board_data.dart';
import '../widgets/board_painter.dart';
import 'vworld_service.dart';

/// 합성 결과. 원본은 드라이브로 올리고, 축소본은 목록과 조사표에 쓴다.
class ComposedPhoto {
  const ComposedPhoto({
    required this.full,
    required this.thumbnail,
    required this.width,
    required this.height,
  });

  final Uint8List full;
  final Uint8List thumbnail;
  final int width;
  final int height;
}

/// 촬영 원본에 약도와 보드를 구워 JPEG 바이트를 만든다.
///
/// 화면 위젯을 캡처하지 않고 원본 해상도 캔버스에 직접 그리기 때문에,
/// 휴대폰 화면이 작아도 제출용 해상도가 그대로 유지된다.
class BoardComposer {
  const BoardComposer(
    this._vworld, {
    this.maxEdge = 2600,
    this.quality = 88,
    this.thumbnailEdge = 640,
  });

  final VWorldService _vworld;

  /// 결과물 긴 변의 최대 픽셀. 원본이 더 작으면 확대하지 않는다.
  ///
  /// 모바일 웹은 브라우저 탭 메모리가 넉넉하지 않다. 12MP 원본을 그대로 쓰면
  /// RGBA 중간 버퍼만 48MB가 되어 저사양 기기에서 탭이 죽는다.
  final int maxEdge;

  /// JPEG 인코딩 품질(0~100).
  final int quality;

  /// 목록·조사표용 축소본의 긴 변 픽셀.
  final int thumbnailEdge;

  Future<ComposedPhoto> compose(Uint8List photoBytes, BoardData data) async {
    // 플랫폼 코덱으로 디코딩한다. Dart 디코더보다 빠르고, EXIF orientation도
    // 이 단계에서 함께 적용된다.
    final source = await decodeImageFromList(photoBytes);
    ui.Image? sketch;
    try {
      final scale = _scaleFor(source.width, source.height);
      final width = (source.width * scale).round();
      final height = (source.height * scale).round();

      sketch = await _renderSketch(data, width);

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImageRect(
        source,
        Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
        Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        Paint()..filterQuality = FilterQuality.medium,
      );
      BoardPainter(
        data,
        sketchMap: sketch,
      ).paintOn(canvas, Size(width.toDouble(), height.toDouble()));

      final picture = recorder.endRecording();
      final ui.Image composed;
      try {
        composed = await picture.toImage(width, height);
      } finally {
        picture.dispose();
      }

      try {
        // 축소본은 같은 합성 결과에서 뽑는다. 다시 합성하지 않는다.
        final thumbScale = _scaleTo(width, height, thumbnailEdge);
        final thumbWidth = (width * thumbScale).round();
        final thumbHeight = (height * thumbScale).round();

        // JPEG 인코딩은 순수 Dart라 무겁다. UI 프레임을 막지 않도록 분리한다.
        // 웹에서는 compute가 웹 워커 대신 같은 이벤트 루프에서 도는 점에 유의.
        final full = await compute(
          _encodeJpeg,
          _EncodeRequest(
            rgba: await _rgbaOf(composed),
            width: width,
            height: height,
            quality: quality,
          ),
        );

        final thumbnail = thumbScale == 1
            ? full
            : await _encodeScaled(composed, thumbWidth, thumbHeight);

        return ComposedPhoto(
          full: full,
          thumbnail: thumbnail,
          width: width,
          height: height,
        );
      } finally {
        composed.dispose();
      }
    } finally {
      sketch?.dispose();
      source.dispose();
    }
  }

  /// 최종 해상도에 맞춰 약도를 렌더한다.
  ///
  /// 화면 크기가 아니라 합성 결과 기준으로 뽑아야 인쇄했을 때 글자가 깨지지
  /// 않는다. 실패하면 약도 없이 진행한다 - 지도 때문에 촬영분을 잃을 수는 없다.
  Future<ui.Image?> _renderSketch(BoardData data, int outputWidth) async {
    if (!data.wantsSketchMap || !_vworld.isConfigured) return null;
    try {
      final width = outputWidth * data.sketchMap.widthRatio;
      return await _vworld.renderSketchMap(
        latitude: data.latitude!,
        longitude: data.longitude!,
        size: Size(width, width * 0.75),
        zoom: data.sketchMap.zoom,
        layer: data.sketchMap.layer,
      );
    } catch (e) {
      debugPrint('약도 렌더 실패(약도 없이 진행): $e');
      return null;
    }
  }

  double _scaleFor(int width, int height) => _scaleTo(width, height, maxEdge);

  static double _scaleTo(int width, int height, int edge) {
    final longest = width > height ? width : height;
    if (longest <= edge) return 1;
    return edge / longest;
  }

  static Future<Uint8List> _rgbaOf(ui.Image image) async {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) {
      throw StateError('합성 이미지를 픽셀 데이터로 변환하지 못했습니다.');
    }
    return byteData.buffer.asUint8List();
  }

  Future<Uint8List> _encodeScaled(ui.Image source, int width, int height) async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawImageRect(
      source,
      Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..filterQuality = FilterQuality.medium,
    );
    final picture = recorder.endRecording();
    final ui.Image scaled;
    try {
      scaled = await picture.toImage(width, height);
    } finally {
      picture.dispose();
    }
    try {
      return await compute(
        _encodeJpeg,
        _EncodeRequest(
          rgba: await _rgbaOf(scaled),
          width: width,
          height: height,
          quality: 78,
        ),
      );
    } finally {
      scaled.dispose();
    }
  }
}

class _EncodeRequest {
  const _EncodeRequest({
    required this.rgba,
    required this.width,
    required this.height,
    required this.quality,
  });

  final Uint8List rgba;
  final int width;
  final int height;
  final int quality;
}

Uint8List _encodeJpeg(_EncodeRequest request) {
  final image = img.Image.fromBytes(
    width: request.width,
    height: request.height,
    bytes: request.rgba.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return img.encodeJpg(image, quality: request.quality);
}
