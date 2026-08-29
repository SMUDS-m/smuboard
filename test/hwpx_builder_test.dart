import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smuboard/services/hwpx_builder.dart';

/// 템플릿을 실제로 열어 값을 채우고, 결과가 다시 열리는지까지 확인한다.
/// 결과 파일은 스킬의 check 게이트로도 검사할 수 있도록 남긴다.
void main() {
  final templateFile = File('assets/templates/현황조사표.hwpx');

  late Uint8List template;

  setUpAll(() {
    template = templateFile.readAsBytesSync();
  });

  test('템플릿에 사진칸이 6개 있다', () async {
    const builder = HwpxBuilder();
    expect(await builder.photoSlotCount(templateBytes: template), 6);
  });

  test('치환 표시가 값으로 바뀌고 사진 바이트가 교체된다', () async {
    const builder = HwpxBuilder();
    final photos = <Uint8List>[
      for (var i = 0; i < 3; i++)
        Uint8List.fromList(List<int>.filled(64, 0x40 + i)),
    ];

    final out = await builder.build(
      templateBytes: template,
      values: <String, String>{
        'survey_no': 'SMU-20260829-1403',
        'site_name': '○○천 좌안 제방 유실',
        'disaster_type': '호우',
        'damage_desc': '제방 <상단> 30m 구간 유실 & 세굴 확인',
        'photo_count': '3',
        'photo_caption_1': '제방 유실부 전경',
      },
      photos: photos,
    );

    File('build/hwpx_roundtrip.hwpx').createSync(recursive: true);
    File('build/hwpx_roundtrip.hwpx').writeAsBytesSync(out);

    final archive = ZipDecoder().decodeBytes(out);
    final section = utf8.decode(
      archive.files.firstWhere((f) => f.name == 'Contents/section0.xml').content,
    );

    // 값이 들어갔다.
    expect(section, contains('SMU-20260829-1403'));
    expect(section, contains('○○천 좌안 제방 유실'));
    expect(section, contains('제방 유실부 전경'));

    // XML 특수문자는 이스케이프된다.
    expect(section, contains('&lt;상단&gt;'));
    expect(section, contains('&amp;'));
    expect(section, isNot(contains('<상단>')));

    // 값을 안 준 키는 그대로 남아 템플릿의 실수를 감추지 않는다.
    expect(section, contains('{{opinion}}'));

    // 사진 3장만 교체되고 나머지 자리표시는 유지된다.
    final images = archive.files
        .where((f) => f.name.startsWith('BinData/'))
        .toList();
    expect(images.length, 6);
    expect(images.take(3).every((f) => f.content.length == 64), isTrue);
    expect(images.skip(3).every((f) => f.content.length > 1000), isTrue);

    // mimetype은 첫 엔트리이면서 무압축이어야 한글이 연다.
    expect(archive.files.first.name, 'mimetype');
    expect(utf8.decode(archive.files.first.content), 'application/hwp+zip');
  });
}
