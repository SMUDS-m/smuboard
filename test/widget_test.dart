import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:smuboard/models/board_data.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ko_KR'));

  test('빈 항목은 보드 행에서 빠진다', () {
    const data = BoardData(siteName: '○○지구 정비사업', workType: '토공');
    expect(data.rows.map((r) => r.label), <String>['현장명', '공　종']);
  });

  test('일시에 요일이 붙는다', () {
    final data = BoardData(
      siteName: '현장',
      capturedAt: DateTime(2026, 8, 29, 14, 3),
    );
    expect(data.formattedDateTime, '2026-08-29 (토) 14:03');
  });

  test('좌표는 반구 기호와 함께 6자리로 표기된다', () {
    const data = BoardData(
      siteName: '현장',
      latitude: 37.566535,
      longitude: 126.977969,
    );
    expect(data.formattedCoordinates, 'N 37.566535  E 126.977969');
  });

  test('좌표 표시를 끄면 좌표 행이 사라진다', () {
    const data = BoardData(
      siteName: '현장',
      latitude: 37.5,
      longitude: 127.0,
      showCoordinates: false,
    );
    expect(data.rows.any((r) => r.label == '좌　표'), isFalse);
  });
}
