import 'package:flutter/foundation.dart';

/// 빌드 시 주입되는 외부 서비스 설정.
///
/// 키를 소스에 넣지 않는다. 로컬 실행:
/// ```
/// flutter run -d chrome \
///   --dart-define=VWORLD_KEY=... \
///   --dart-define=GOOGLE_WEB_CLIENT_ID=...apps.googleusercontent.com
/// ```
/// 배포는 GitHub Actions가 저장소 Secret에서 같은 값을 넣어 준다.
///
/// 클라이언트 웹앱이므로 두 값 모두 최종 번들에 남는다. 실제 보호는
/// 브이월드 콘솔의 서비스 도메인 등록과 OAuth 승인 도메인 설정으로 한다.
class AppConfig {
  const AppConfig._();

  /// 브이월드 오픈API 인증키.
  static const String vworldKey = String.fromEnvironment('VWORLD_KEY');

  static const String _webClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
  );
  static const String _iosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
  );

  static bool get hasVWorldKey => vworldKey.isNotEmpty;

  /// 로그인 없이 메인 화면까지 들어가는 개발용 우회.
  ///
  /// `--dart-define=ALLOW_GUEST=true`로 빌드할 때만 켜진다. 배포 워크플로는 이
  /// 값을 넘기지 않으므로 배포본은 로그인 게이트를 그대로 유지한다.
  /// 게스트 상태에서도 촬영과 조사표 작성은 되지만, 드라이브 업로드는
  /// 로그인해야 시작된다.
  static const bool allowGuest = bool.fromEnvironment('ALLOW_GUEST');

  /// `GoogleSignIn.initialize`에 넘길 클라이언트 ID.
  static String? get googleClientId {
    if (kIsWeb) return _orNull(_webClientId);
    return _isApple ? _orNull(_iosClientId) : null;
  }

  /// 서버(웹) 클라이언트 ID. Android 네이티브 빌드에서 ID 토큰을 받을 때 쓴다.
  static String? get googleServerClientId =>
      kIsWeb ? null : _orNull(_webClientId);

  static bool get hasGoogleConfig {
    if (kIsWeb) return _webClientId.isNotEmpty;
    if (_isApple) return _iosClientId.isNotEmpty;
    return true; // Android는 패키지명 + SHA-1로 매칭된다.
  }

  static bool get _isApple =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  static String? _orNull(String value) => value.isEmpty ? null : value;
}
