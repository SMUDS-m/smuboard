import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

class HwpxException implements Exception {
  const HwpxException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 템플릿 HWPX를 열어 값을 채워 넣는다.
///
/// HWPX는 확장자만 다를 뿐 ZIP 컨테이너이고 본문은 `Contents/section*.xml`의
/// OWPML XML이다. 한컴오피스도 서버도 없이 브라우저에서 처리할 수 있는 이유다.
///
/// 사진은 새로 삽입하지 않고 템플릿에 이미 들어 있는 그림의 바이트만 갈아
/// 끼운다. 그림의 크기·위치·XML이 템플릿에 잡혀 있어 까다로운 OWPML 도형
/// 마크업을 직접 쓰지 않아도 된다.
class HwpxBuilder {
  const HwpxBuilder({this.templateAsset = 'assets/templates/현황조사표.hwpx'});

  final String templateAsset;

  /// `{{키}}`를 찾되, 한컴이 글자를 여러 런으로 쪼개 놓아 중간에 XML 태그가
  /// 끼어든 경우까지 잡는다. 캡처한 부분에서 태그를 걷어내면 키만 남는다.
  static final RegExp _placeholder = RegExp(r'\{\{((?:[^<>{}]|<[^>]*>)*?)\}\}');
  static final RegExp _tag = RegExp(r'<[^>]*>');

  Future<Uint8List> build({
    required Map<String, String> values,
    List<Uint8List> photos = const <Uint8List>[],
    Uint8List? templateBytes,
  }) async {
    final bytes = templateBytes ?? await _loadTemplate();

    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      throw HwpxException('HWPX 템플릿을 열지 못했습니다: $e');
    }

    final output = Archive();
    var photoSlot = 0;

    // mimetype은 ZIP의 첫 항목이면서 무압축이어야 한다. 순서를 지키려고
    // 원본 순서를 그대로 따라가되, 혹시 몰라 맨 앞으로 한 번 더 끌어올린다.
    final entries = archive.files.where((f) => f.isFile).toList()
      ..sort((a, b) {
        if (a.name == 'mimetype') return -1;
        if (b.name == 'mimetype') return 1;
        return 0;
      });

    for (final file in entries) {
      final name = file.name;
      final content = file.readBytes();
      if (content == null) continue;

      if (name == 'mimetype') {
        output.add(
          ArchiveFile.bytes(name, content)..compression = CompressionType.none,
        );
        continue;
      }

      if (_isBodyXml(name)) {
        final filled = _substitute(utf8.decode(content), values);
        output.add(ArchiveFile.string(name, filled));
        continue;
      }

      if (_isBinImage(name) && photoSlot < photos.length) {
        output.add(ArchiveFile.bytes(name, photos[photoSlot++]));
        continue;
      }

      output.add(ArchiveFile.bytes(name, content));
    }

    if (photos.length > photoSlot) {
      // 템플릿의 사진칸보다 많이 찍은 경우. 조사표에는 앞의 것만 들어간다.
      debugPrint(
        '템플릿 사진칸 $photoSlot개, 촬영 ${photos.length}장 - 나머지는 조사표에 들어가지 않습니다.',
      );
    }

    final encoded = ZipEncoder().encodeBytes(output);
    return Uint8List.fromList(encoded);
  }

  /// 템플릿이 사진을 몇 칸까지 받는지. 제출 화면 안내에 쓴다.
  Future<int> photoSlotCount({Uint8List? templateBytes}) async {
    final bytes = templateBytes ?? await _loadTemplate();
    final archive = ZipDecoder().decodeBytes(bytes);
    return archive.files.where((f) => f.isFile && _isBinImage(f.name)).length;
  }

  Future<Uint8List> _loadTemplate() async {
    try {
      final data = await rootBundle.load(templateAsset);
      return data.buffer.asUint8List();
    } catch (e) {
      throw HwpxException('HWPX 템플릿을 찾을 수 없습니다 ($templateAsset): $e');
    }
  }

  static bool _isBodyXml(String name) =>
      name.startsWith('Contents/') && name.endsWith('.xml');

  static bool _isBinImage(String name) => name.startsWith('BinData/');

  /// XML 본문의 치환 표시를 값으로 바꾼다. 값은 XML로 이스케이프한다.
  static String _substitute(String xml, Map<String, String> values) {
    return xml.replaceAllMapped(_placeholder, (match) {
      final key = match.group(1)!.replaceAll(_tag, '').trim();
      final value = values[key];
      // 모르는 키는 손대지 않는다. 템플릿의 실수를 조용히 지우지 않기 위해서다.
      if (value == null) return match.group(0)!;
      return _escape(value);
    });
  }

  static String _escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
