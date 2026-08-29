import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/board_data.dart';
import '../models/sketch_map_options.dart';

/// 사진 위에 사진대지 보드를 그리는 단일 진입점.
///
/// 미리보기(화면 크기)와 최종 합성(원본 해상도)이 같은 코드를 쓰기 때문에
/// "보이는 대로 저장된다"가 보장된다. 모든 치수는 캔버스 너비에 비례하므로
/// 어떤 해상도로 그려도 결과 비율이 동일하다.
class BoardPainter extends CustomPainter {
  const BoardPainter(this.data, {this.opacity = 0.92, this.sketchMap});

  final BoardData data;

  /// 보드 배경 불투명도. 1.0이면 사진을 완전히 가린다.
  final double opacity;

  /// 미리 렌더한 약도 이미지. null이면 약도를 그리지 않는다.
  final ui.Image? sketchMap;

  static const Color _boardColor = Color(0xFFFFFFFF);
  static const Color _labelColor = Color(0xFFE8EDF2);
  static const Color _lineColor = Color(0xFF1A1A1A);
  static const Color _textColor = Color(0xFF111111);

  @override
  void paint(Canvas canvas, Size size) => paintOn(canvas, size);

  /// [CustomPaint] 밖에서도(원본 해상도 합성) 호출할 수 있는 실제 구현.
  void paintOn(Canvas canvas, Size size) {
    _paintSketchMap(canvas, size);

    final rows = data.rows;
    if (rows.isEmpty) return;

    final w = size.width;
    final h = size.height;

    final margin = w * 0.018;
    final boardWidth = w - margin * 2;
    final fontSize = w * 0.023;
    final cellPadX = fontSize * 0.6;
    final cellPadY = fontSize * 0.38;
    final labelWidth = boardWidth * 0.20;
    final valueWidth = boardWidth - labelWidth - cellPadX * 2;
    final stroke = (w * 0.0022).clamp(1.0, 6.0);
    final minRowHeight = fontSize * 1.9;

    // 1단계: 값이 여러 줄로 접힐 수 있으므로 행 높이를 먼저 잰다.
    final valuePainters = <TextPainter>[];
    final labelPainters = <TextPainter>[];
    final rowHeights = <double>[];
    for (final row in rows) {
      final value = _painter(row.value, fontSize, FontWeight.w500)
        ..layout(maxWidth: valueWidth);
      final label = _painter(row.label, fontSize, FontWeight.w700)
        ..layout(maxWidth: labelWidth - cellPadX * 2);
      valuePainters.add(value);
      labelPainters.add(label);
      rowHeights.add(
        (value.height + cellPadY * 2).clamp(minRowHeight, double.infinity),
      );
    }

    final boardHeight = rowHeights.reduce((a, b) => a + b);
    final board = Rect.fromLTWH(
      margin,
      h - margin - boardHeight,
      boardWidth,
      boardHeight,
    );
    final radius = RRect.fromRectAndRadius(
      board,
      Radius.circular(fontSize * 0.35),
    );

    canvas.save();
    canvas.clipRRect(radius);

    // 2단계: 배경(본문 흰색 + 라벨 열 음영).
    canvas.drawRect(board, Paint()..color = _boardColor.withValues(alpha: opacity));
    canvas.drawRect(
      Rect.fromLTWH(board.left, board.top, labelWidth, boardHeight),
      Paint()..color = _labelColor.withValues(alpha: opacity),
    );

    // 3단계: 텍스트와 행 구분선.
    final linePaint = Paint()
      ..color = _lineColor.withValues(alpha: 0.55)
      ..strokeWidth = stroke * 0.7;
    var y = board.top;
    for (var i = 0; i < rows.length; i++) {
      final rowHeight = rowHeights[i];
      if (i > 0) {
        canvas.drawLine(
          Offset(board.left, y),
          Offset(board.right, y),
          linePaint,
        );
      }
      labelPainters[i].paint(
        canvas,
        Offset(
          board.left + cellPadX,
          y + (rowHeight - labelPainters[i].height) / 2,
        ),
      );
      valuePainters[i].paint(
        canvas,
        Offset(
          board.left + labelWidth + cellPadX,
          y + (rowHeight - valuePainters[i].height) / 2,
        ),
      );
      y += rowHeight;
    }

    canvas.restore();

    // 4단계: 바깥 테두리와 라벨 열 경계.
    canvas.drawLine(
      Offset(board.left + labelWidth, board.top),
      Offset(board.left + labelWidth, board.bottom),
      linePaint,
    );
    canvas.drawRRect(
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = _lineColor,
    );
  }

  /// 약도를 지정한 모서리에 액자처럼 얹는다.
  void _paintSketchMap(Canvas canvas, Size size) {
    final map = sketchMap;
    if (map == null || !data.sketchMap.enabled) return;

    final margin = size.width * 0.018;
    final width = size.width * data.sketchMap.widthRatio;
    final height = width * 0.75;

    final Offset origin = switch (data.sketchMap.corner) {
      SketchMapCorner.topLeft => Offset(margin, margin),
      SketchMapCorner.topRight => Offset(size.width - margin - width, margin),
    };
    final frame = Rect.fromLTWH(origin.dx, origin.dy, width, height);
    final radius = RRect.fromRectAndRadius(
      frame,
      Radius.circular(size.width * 0.008),
    );

    canvas.save();
    canvas.clipRRect(radius);
    canvas.drawImageRect(
      map,
      Rect.fromLTWH(0, 0, map.width.toDouble(), map.height.toDouble()),
      frame,
      Paint()..filterQuality = FilterQuality.medium,
    );
    canvas.restore();

    final stroke = (size.width * 0.0022).clamp(1.0, 6.0);
    canvas.drawRRect(
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = _lineColor,
    );

    // 좌표만 있는 지도는 무엇인지 알기 어려우므로 제목을 붙인다.
    final caption = _painter('약　도', size.width * 0.016, FontWeight.w700)
      ..layout(maxWidth: width);
    final captionBox = Rect.fromLTWH(
      frame.left,
      frame.top,
      caption.width + size.width * 0.014,
      caption.height + size.width * 0.008,
    );
    canvas.drawRect(captionBox, Paint()..color = _boardColor.withValues(alpha: opacity));
    canvas.drawRect(
      captionBox,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * 0.7
        ..color = _lineColor,
    );
    caption.paint(
      canvas,
      Offset(captionBox.left + size.width * 0.007, captionBox.top + size.width * 0.004),
    );
  }

  TextPainter _painter(String text, double fontSize, FontWeight weight) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: _textColor,
          fontSize: fontSize,
          fontWeight: weight,
          height: 1.25,
          // 사진 배경이 밝을 때도 글자가 뭉개지지 않도록 살짝 대비를 준다.
          shadows: const <Shadow>[],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 3,
      ellipsis: '…',
      textScaler: TextScaler.noScaling,
    );
  }

  @override
  bool shouldRepaint(BoardPainter oldDelegate) =>
      oldDelegate.data != data ||
      oldDelegate.opacity != opacity ||
      oldDelegate.sketchMap != sketchMap;
}

/// 원본 해상도 이미지 위에 보드를 굽기 위한 헬퍼.
///
/// 화면 캡처(RepaintBoundary)와 달리 기기 화면 해상도에 종속되지 않는다.
Future<ui.Image> renderBoardOnImage(
  ui.Image source,
  BoardData data, {
  ui.Image? sketchMap,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final size = Size(source.width.toDouble(), source.height.toDouble());

  canvas.drawImage(source, Offset.zero, Paint());
  BoardPainter(data, sketchMap: sketchMap).paintOn(canvas, size);

  final picture = recorder.endRecording();
  try {
    return await picture.toImage(source.width, source.height);
  } finally {
    picture.dispose();
  }
}
