import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'app_services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 조사표와 보드에 요일을 한국어로 찍으려면 로케일 데이터가 먼저 필요하다.
  await initializeDateFormatting('ko_KR');

  final services = AppServices();

  // 첫 화면을 막지 않도록 백그라운드로 돌린다. 드라이브를 부르려면 로그인
  // 복구가 먼저 끝나야 하므로, 지난 세션에서 못 올린 사진은 그 뒤에 잇는다.
  services.auth
      .initialize()
      .then((_) => services.queue.resume())
      .catchError((Object e, StackTrace s) {
        debugPrint('시작 복구 실패: $e\n$s');
      });

  runApp(SmuBoardApp(services: services));
}
