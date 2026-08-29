import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'app_services.dart';
import 'screens/login_screen.dart';
import 'screens/survey_list_screen.dart';

class SmuBoardApp extends StatelessWidget {
  const SmuBoardApp({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      services: services,
      child: MaterialApp(
        title: 'SMUBoard 재난현장 조사',
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        home: const _AuthGate(),
      ),
    );
  }

  ThemeData _theme(Brightness brightness) {
    // 로고의 학교 블루를 시드로 삼는다.
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0B57A4),
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: scheme,
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        isDense: true,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
    );
  }
}

/// 로그인 여부에 따라 첫 화면을 가른다.
class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  @override
  Widget build(BuildContext context) {
    final auth = AppScope.of(context).auth;
    return StreamBuilder<GoogleSignInAccount?>(
      stream: auth.accountChanges,
      initialData: auth.account,
      builder: (context, snapshot) {
        return snapshot.data == null
            ? const LoginScreen()
            : const SurveyListScreen();
      },
    );
  }
}
