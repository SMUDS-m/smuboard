import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'app_services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 조사표와 보드에 요일을 한국어로 찍으려면 로케일 데이터가 먼저 필요하다.
  await initializeDateFormatting('ko_KR');

  final services = AppServices();
  // 이전 로그인 복구는 첫 화면을 막지 않도록 백그라운드로 돌린다.
  services.auth.initialize().catchError(
    (Object e) => debugPrint('로그인 복구 실패: $e'),
  );

  runApp(SmuBoardApp(services: services));
}
