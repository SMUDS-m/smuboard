import 'dart:async';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/googleapis_auth.dart' as gapis;

import '../config/app_config.dart';

class GoogleAuthException implements Exception {
  const GoogleAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 구글 로그인과 API 클라이언트 발급만 담당한다.
///
/// 스코프는 `drive.file` 하나뿐이다. 앱이 만든 파일에만 접근하는 스코프라
/// 사용자의 기존 드라이브를 볼 수 없고, 구글 시트 API도 이 스코프를 받아들여
/// 별도의 `spreadsheets` 승인을 요구하지 않는다.
class GoogleAuthService {
  static const List<String> scopes = <String>[drive.DriveApi.driveFileScope];

  final StreamController<GoogleSignInAccount?> _controller =
      StreamController<GoogleSignInAccount?>.broadcast();

  GoogleSignInAccount? _account;
  bool _initialized = false;

  GoogleSignInAccount? get account => _account;

  bool get isSignedIn => _account != null;

  Stream<GoogleSignInAccount?> get accountChanges => _controller.stream;

  /// 앱 시작 시 한 번 호출한다. 이전 로그인이 남아 있으면 조용히 복구한다.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    await GoogleSignIn.instance.initialize(
      clientId: AppConfig.googleClientId,
      serverClientId: AppConfig.googleServerClientId,
    );

    GoogleSignIn.instance.authenticationEvents.listen(
      (event) => _set(switch (event) {
        GoogleSignInAuthenticationEventSignIn() => event.user,
        GoogleSignInAuthenticationEventSignOut() => null,
      }),
      onError: (Object _) => _set(null),
    );

    await GoogleSignIn.instance.attemptLightweightAuthentication();
  }

  /// 대화형 로그인. 버튼 탭에서만 호출해야 한다.
  Future<GoogleSignInAccount> signIn() async {
    await initialize();
    if (!AppConfig.hasGoogleConfig) {
      throw const GoogleAuthException(
        'OAuth 클라이언트 ID가 설정되지 않았습니다. README의 구글 설정 항목을 확인하세요.',
      );
    }
    if (!GoogleSignIn.instance.supportsAuthenticate()) {
      throw const GoogleAuthException('이 브라우저에서는 앱 내 로그인을 지원하지 않습니다.');
    }

    try {
      final account = await GoogleSignIn.instance.authenticate(
        scopeHint: scopes,
      );
      _set(account);
      return account;
    } on GoogleSignInException catch (e) {
      throw GoogleAuthException(_describe(e));
    }
  }

  Future<void> signOut() async {
    await GoogleSignIn.instance.disconnect();
    _set(null);
  }

  /// googleapis 호출에 쓸 인증 클라이언트.
  ///
  /// 승인이 아직 없으면 그 자리에서 요청한다. 웹에서는 팝업이 뜨므로 사용자
  /// 조작 흐름 안에서 불러야 차단되지 않는다.
  Future<gapis.AuthClient> authClient() async {
    final account = _account;
    if (account == null) {
      throw const GoogleAuthException('먼저 구글 계정으로 로그인해 주세요.');
    }
    try {
      final authorization =
          await account.authorizationClient.authorizationForScopes(scopes) ??
          await account.authorizationClient.authorizeScopes(scopes);
      return authorization.authClient(scopes: scopes);
    } on GoogleSignInException catch (e) {
      throw GoogleAuthException(_describe(e));
    }
  }

  void _set(GoogleSignInAccount? account) {
    _account = account;
    _controller.add(account);
  }

  String _describe(GoogleSignInException e) => switch (e.code) {
    GoogleSignInExceptionCode.canceled => '로그인을 취소했습니다.',
    GoogleSignInExceptionCode.interrupted => '로그인이 중단되었습니다. 다시 시도해 주세요.',
    GoogleSignInExceptionCode.clientConfigurationError =>
      'OAuth 클라이언트 설정이 잘못되었습니다. 승인된 자바스크립트 원본에 이 사이트 주소가 등록됐는지 확인하세요.',
    GoogleSignInExceptionCode.providerConfigurationError =>
      '구글 로그인 제공자 설정을 확인해 주세요.',
    GoogleSignInExceptionCode.uiUnavailable => '지금은 로그인 창을 띄울 수 없습니다.',
    _ => '로그인 실패: ${e.description ?? e.code.name}',
  };

  void dispose() => _controller.close();
}
