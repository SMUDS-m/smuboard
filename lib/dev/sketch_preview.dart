// 약도 렌더링 확인용 개발 진입점. 배포 번들에는 들어가지 않는다.
//
//   flutter run -t lib/dev/sketch_preview.dart -d chrome \
//     --dart-define=VWORLD_KEY=...
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../models/board_data.dart';
import '../models/sketch_map_options.dart';
import '../services/vworld_service.dart';
import '../widgets/board_painter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ko_KR');
  runApp(const _SketchPreviewApp());
}

class _SketchPreviewApp extends StatelessWidget {
  const _SketchPreviewApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const _Preview(),
    );
  }
}

class _Preview extends StatefulWidget {
  const _Preview();

  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  final VWorldService _vworld = VWorldService();

  final Map<VWorldLayer, ui.Image> _sketches = <VWorldLayer, ui.Image>{};
  String _status = '불러오는 중…';
  String _address = '';

  // 세명대학교 제천캠퍼스.
  static const double _lat = 37.1447;
  static const double _lng = 128.2013;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!_vworld.isConfigured) {
      setState(() => _status = 'VWORLD_KEY가 주입되지 않았습니다.');
      return;
    }
    try {
      for (final layer in VWorldLayer.values) {
        _sketches[layer] = await _vworld.renderSketchMap(
          latitude: _lat,
          longitude: _lng,
          size: const Size(520, 390),
          zoom: 17,
          layer: layer,
        );
      }
      final address = await _vworld.reverseGeocode(_lat, _lng);
      setState(() {
        _address = address?.preferred ?? '(주소 변환 실패)';
        _status = '레이어 ${_sketches.length}종 · $_address';
      });
    } catch (e) {
      setState(() => _status = '실패: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final board = BoardData(
      siteName: '세명대학교 제천캠퍼스 사면 점검',
      workType: '호우 · 사면/옹벽',
      location: _address,
      contractor: '세명대학교 재난안전학과 / 홍길동',
      capturedAt: DateTime(2026, 8, 29, 14, 3),
      latitude: _lat,
      longitude: _lng,
      sketchMap: const SketchMapOptions(zoom: 17),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('약도 렌더 확인')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(_status),
          const SizedBox(height: 12),
          for (final entry in _sketches.entries) ...<Widget>[
            Text('${entry.key.label} (${entry.key.id}'
                '${entry.key.overlayId == null ? '' : ' + ${entry.key.overlayId}'})'),
            const SizedBox(height: 6),
            SizedBox(
              height: 240,
              child: CustomPaint(painter: _RawImagePainter(entry.value)),
            ),
            const SizedBox(height: 16),
          ],
          const SizedBox(height: 20),
          const Text('2) 사진 위 합성 결과(보드 + 약도)'),
          const SizedBox(height: 6),
          AspectRatio(
            aspectRatio: 4 / 3,
            child: ColoredBox(
              color: const Color(0xFF7C8A94),
              child: CustomPaint(
                painter: BoardPainter(
                  board,
                  sketchMap: _sketches[VWorldLayer.satellite],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RawImagePainter extends CustomPainter {
  const _RawImagePainter(this.image);

  final ui.Image image;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_RawImagePainter oldDelegate) =>
      oldDelegate.image != image;
}
