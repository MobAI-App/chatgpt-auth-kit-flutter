import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'credentials.dart';
import 'jwt.dart';

/// PKCE OAuth client for ChatGPT/Codex sign-in. Mirrors the Swift
/// implementation. You typically use [OAuthFlow] instead of these
/// methods directly.
class OAuthClient {
  static const authEndpoint = 'https://auth.openai.com/oauth/authorize';
  static const tokenEndpoint = 'https://auth.openai.com/oauth/token';
  static const clientID = 'app_EMoamEEZ73f0CkXaXp7hrann';
  static const redirectURI = 'http://localhost:1455/auth/callback';
  static const scopes = 'openid profile email offline_access';
  static const callbackPort = 1455;

  /// Builds the authorization URL the user must open in a browser.
  /// Caller must keep `verifier` and `state` for the exchange.
  static AuthorizationRequest buildAuthorizationURL({
    String originator = 'codex_cli_rs',
  }) {
    final verifier = _PKCE.generateVerifier();
    final challenge = _PKCE.challenge(verifier);
    final state = _PKCE.randomState();

    final uri = Uri.parse(authEndpoint).replace(queryParameters: {
      'client_id': clientID,
      'redirect_uri': redirectURI,
      'response_type': 'code',
      'scope': scopes,
      'state': state,
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
      'codex_cli_simplified_flow': 'true',
      'originator': originator,
    });
    return AuthorizationRequest(url: uri, verifier: verifier, state: state);
  }

  /// Exchanges an authorization code for access + refresh tokens.
  static Future<Credentials> exchangeCode({
    required String code,
    required String verifier,
  }) async {
    final response = await http.post(
      Uri.parse(tokenEndpoint),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'authorization_code',
        'client_id': clientID,
        'code': code,
        'redirect_uri': redirectURI,
        'code_verifier': verifier,
      },
    );
    if (response.statusCode != 200) {
      throw OAuthException.tokenExchangeFailed(response.statusCode, response.body);
    }
    return _credentialsFromBody(response.body);
  }

  /// Refreshes an expired access token. Returns updated credentials.
  static Future<Credentials> refresh(Credentials creds) async {
    final response = await http.post(
      Uri.parse(tokenEndpoint),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'refresh_token',
        'client_id': clientID,
        'refresh_token': creds.refreshToken,
      },
    );
    if (response.statusCode != 200) {
      throw OAuthException.tokenExchangeFailed(response.statusCode, response.body);
    }
    final fresh = _credentialsFromBody(response.body);
    return Credentials(
      accessToken: fresh.accessToken,
      refreshToken: fresh.refreshToken.isEmpty ? creds.refreshToken : fresh.refreshToken,
      expiresAt: fresh.expiresAt,
      accountID: fresh.accountID.isEmpty ? creds.accountID : fresh.accountID,
    );
  }

  static Credentials _credentialsFromBody(String body) {
    final json = jsonDecode(body) as Map<String, dynamic>;
    final accessToken = json['access_token'] as String;
    final refreshToken = (json['refresh_token'] as String?) ?? '';
    final expiresIn = json['expires_in'] as int;
    final accountID = Jwt.extractAccountID(accessToken) ?? '';
    return Credentials(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
      accountID: accountID,
    );
  }
}

class AuthorizationRequest {
  final Uri url;
  final String verifier;
  final String state;
  const AuthorizationRequest({required this.url, required this.verifier, required this.state});
}

class OAuthException implements Exception {
  final String message;
  const OAuthException(this.message);
  factory OAuthException.tokenExchangeFailed(int status, String body) =>
      OAuthException('Token endpoint returned $status: $body');
  factory OAuthException.stateMismatch() => const OAuthException('OAuth state mismatch');
  factory OAuthException.noCode() => const OAuthException('Authorization code missing from callback');
  factory OAuthException.providerError(String code, String? desc) =>
      OAuthException('Provider rejected: $code${desc == null ? '' : ' — $desc'}');
  factory OAuthException.timedOut() => const OAuthException('Login timed out');
  @override
  String toString() => message;
}

class _PKCE {
  static String generateVerifier() => _randomBase64Url(32);

  static String challenge(String verifier) {
    final hash = sha256.convert(utf8.encode(verifier));
    return _base64UrlEncode(hash.bytes);
  }

  static String randomState({int byteCount = 32}) => _randomBase64Url(byteCount);

  static String _randomBase64Url(int byteCount) {
    final rng = Random.secure();
    final bytes = List<int>.generate(byteCount, (_) => rng.nextInt(256));
    return _base64UrlEncode(bytes);
  }

  static String _base64UrlEncode(List<int> bytes) {
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}
