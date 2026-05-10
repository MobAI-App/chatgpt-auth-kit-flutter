import 'dart:convert';
import 'package:http/http.dart' as http;

import 'credentials.dart';
import 'credentials_provider.dart';

class Window {
  final double usedPercent;
  final int windowSeconds;
  final int resetAt;
  const Window({required this.usedPercent, required this.windowSeconds, required this.resetAt});
}

class CreditsInfo {
  final bool hasCredits;
  final bool unlimited;
  final String? balance;
  const CreditsInfo({required this.hasCredits, required this.unlimited, this.balance});
}

class UsageStatus {
  final String? planType;
  final Window? primary;
  final Window? secondary;
  final CreditsInfo? credits;
  final String? limitReachedKind;
  const UsageStatus({this.planType, this.primary, this.secondary, this.credits, this.limitReachedKind});
}

class UsageClient {
  final CredentialsProvider provider;
  final Uri endpoint;
  final String originator;

  UsageClient({
    required this.provider,
    Uri? endpoint,
    this.originator = 'codex_cli_rs',
  }) : endpoint = endpoint ?? Uri.parse('https://chatgpt.com/backend-api/wham/usage');

  UsageClient.fromCredentials(
    Credentials credentials, {
    Uri? endpoint,
    String originator = 'codex_cli_rs',
  }) : this(
          provider: StaticCredentialsProvider(credentials),
          endpoint: endpoint,
          originator: originator,
        );

  Future<UsageStatus> fetch() async {
    final credentials = await provider.currentCredentials();
    final resp = await http.get(endpoint, headers: {
      'Authorization': 'Bearer ${credentials.accessToken}',
      'Accept': 'application/json',
      'originator': originator,
      if (credentials.accountID.isNotEmpty) 'ChatGPT-Account-ID': credentials.accountID,
    });
    if (resp.statusCode == 401) throw const FormatException('Token rejected - sign in again.');
    if (resp.statusCode != 200) {
      throw FormatException('Usage endpoint returned ${resp.statusCode}: ${resp.body}');
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    return parse(json);
  }

  static UsageStatus parse(Map<String, dynamic> json) {
    final rl = json['rate_limit'] as Map<String, dynamic>?;
    final primary = _window(rl?['primary_window'] as Map<String, dynamic>?);
    final secondary = _window(rl?['secondary_window'] as Map<String, dynamic>?);
    final credits = (json['credits'] as Map<String, dynamic>?);
    final reached = (json['rate_limit_reached_type'] as Map<String, dynamic>?)?['kind'] as String?;
    return UsageStatus(
      planType: json['plan_type'] as String?,
      primary: primary,
      secondary: secondary,
      credits: credits == null
          ? null
          : CreditsInfo(
              hasCredits: credits['has_credits'] as bool? ?? false,
              unlimited: credits['unlimited'] as bool? ?? false,
              balance: credits['balance'] as String?,
            ),
      limitReachedKind: reached,
    );
  }

  static Window? _window(Map<String, dynamic>? d) {
    if (d == null) return null;
    final usedRaw = d['used_percent'];
    final used = usedRaw is num ? usedRaw.toDouble() : -1.0;
    final win = d['limit_window_seconds'] as int? ?? -1;
    if (used < 0 || win < 0) return null;
    return Window(
      usedPercent: used,
      windowSeconds: win,
      resetAt: d['reset_at'] as int? ?? 0,
    );
  }
}
