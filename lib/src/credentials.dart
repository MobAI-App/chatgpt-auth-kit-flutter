import 'jwt.dart';

/// OAuth credentials returned by [OAuthClient] / [OAuthFlow].
class Credentials {
  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final String accountID;

  const Credentials({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.accountID,
  });

  /// True if the access token is expired or will expire within [buffer].
  bool isExpired({Duration buffer = const Duration(minutes: 5)}) {
    return expiresAt.difference(DateTime.now()) <= buffer;
  }

  /// Plan tier (`free`/`plus`/`pro`/...) extracted from the JWT.
  String? get planType => Jwt.extractPlanType(accessToken);

  Map<String, dynamic> toJson() => {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'expiresAt': expiresAt.millisecondsSinceEpoch,
        'accountID': accountID,
      };

  factory Credentials.fromJson(Map<String, dynamic> json) => Credentials(
        accessToken: json['accessToken'] as String,
        refreshToken: json['refreshToken'] as String,
        expiresAt: DateTime.fromMillisecondsSinceEpoch(json['expiresAt'] as int),
        accountID: json['accountID'] as String,
      );
}
