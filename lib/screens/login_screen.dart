import 'package:flutter/material.dart';

import '../app_services.dart';
import '../config/app_config.dart';
import '../services/google_auth_service.dart';
import '../widgets/smuds_logo.dart';

/// 첫 화면. 로그인하지 않으면 다른 화면으로 갈 수 없다.
///
/// 촬영한 사진을 즉시 드라이브에 올리는 구조라 로그인이 조사 시작의 전제다.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AppScope.of(context).auth.signIn();
    } on GoogleAuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '로그인 실패: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const SmudsLogo(height: 52),
                  const SizedBox(height: 36),
                  Text(
                    '재난현장 조사',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '현장사진과 현황조사표를 구글 드라이브에 바로 저장합니다.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 40),
                  FilledButton.icon(
                    onPressed: _busy ? null : _signIn,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.login),
                    label: const Text('구글 계정으로 로그인'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                  if (_error != null) ...<Widget>[
                    const SizedBox(height: 18),
                    _Notice(text: _error!, tone: theme.colorScheme.error),
                  ],
                  if (!AppConfig.hasGoogleConfig) ...<Widget>[
                    const SizedBox(height: 18),
                    _Notice(
                      text:
                          'OAuth 클라이언트 ID가 빌드에 주입되지 않았습니다. '
                          'GOOGLE_WEB_CLIENT_ID를 --dart-define으로 넣어야 로그인이 됩니다.',
                      tone: theme.colorScheme.tertiary,
                    ),
                  ],
                  const SizedBox(height: 28),
                  Text(
                    '드라이브 권한은 이 앱이 만든 파일에만 적용됩니다.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.tone});

  final String text;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.10),
        border: Border(left: BorderSide(color: tone, width: 3)),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.5),
      ),
    );
  }
}
