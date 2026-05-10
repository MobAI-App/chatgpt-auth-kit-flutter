import 'dart:convert';
import 'package:http/http.dart' as http;

import 'credentials.dart';
import 'credentials_provider.dart';

class CodexModel {
  final String slug;
  final String? displayName;
  final bool isDefault;
  const CodexModel({required this.slug, this.displayName, this.isDefault = false});
}

class ModelsClient {
  final CredentialsProvider provider;
  final Uri endpoint;
  final String originator;

  ModelsClient({
    required this.provider,
    String clientVersion = 'chatgpt-auth-kit-flutter-0.1',
    this.originator = 'codex_cli_rs',
  }) : endpoint = Uri.parse(
            'https://chatgpt.com/backend-api/codex/models?client_version=$clientVersion');

  /// Convenience: wraps a single [Credentials] value. Prefer the provider-based
  /// constructor with a [RefreshingCredentialsProvider] for long-lived callers.
  ModelsClient.fromCredentials(
    Credentials credentials, {
    String clientVersion = 'chatgpt-auth-kit-flutter-0.1',
    String originator = 'codex_cli_rs',
  }) : this(
          provider: StaticCredentialsProvider(credentials),
          clientVersion: clientVersion,
          originator: originator,
        );

  Future<List<CodexModel>> fetch() async {
    final credentials = await provider.currentCredentials();
    final resp = await http.get(endpoint, headers: {
      'Authorization': 'Bearer ${credentials.accessToken}',
      'Accept': 'application/json',
      'originator': originator,
      if (credentials.accountID.isNotEmpty) 'ChatGPT-Account-ID': credentials.accountID,
    });
    if (resp.statusCode == 401) throw const FormatException('Token rejected - sign in again.');
    if (resp.statusCode != 200) {
      throw FormatException('Models endpoint returned ${resp.statusCode}: ${resp.body}');
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final raw = (json['models'] as List?) ?? const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(_parse)
        .whereType<CodexModel>()
        .toList(growable: false);
  }

  static CodexModel? _parse(Map<String, dynamic> d) {
    final slug = (d['slug'] as String?) ?? (d['model'] as String?);
    if (slug == null || slug.isEmpty) return null;
    return CodexModel(
      slug: slug,
      displayName: (d['display_name'] as String?) ?? (d['name'] as String?),
      isDefault: (d['is_default'] as bool?) ?? false,
    );
  }
}
