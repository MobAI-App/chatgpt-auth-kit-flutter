import 'dart:convert';

/// Internal JWT helpers for extracting OpenAI-specific claims.
class Jwt {
  static String? extractAccountID(String token) {
    final json = _decodePayload(token);
    if (json == null) return null;

    final auth = json['https://api.openai.com/auth'];
    if (auth is Map) {
      final id = auth['chatgpt_account_id'];
      if (id is String && id.isNotEmpty) return id;
    }
    final flat = json['chatgpt_account_id'];
    if (flat is String && flat.isNotEmpty) return flat;

    final orgs = json['organizations'];
    if (orgs is List && orgs.isNotEmpty) {
      final first = orgs.first;
      if (first is Map) {
        final id = first['id'];
        if (id is String) return id;
      }
    }
    return null;
  }

  static String? extractPlanType(String token) {
    final json = _decodePayload(token);
    if (json == null) return null;
    final auth = json['https://api.openai.com/auth'];
    if (auth is Map) {
      final plan = auth['chatgpt_plan_type'];
      if (plan is String && plan.isNotEmpty) return plan;
    }
    final flat = json['chatgpt_plan_type'];
    if (flat is String && flat.isNotEmpty) return flat;
    return null;
  }

  static Map<String, dynamic>? _decodePayload(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    var payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
    final pad = payload.length % 4;
    if (pad > 0) payload += '=' * (4 - pad);
    try {
      final bytes = base64.decode(payload);
      final decoded = utf8.decode(bytes);
      final map = jsonDecode(decoded);
      return map is Map<String, dynamic> ? map : null;
    } catch (_) {
      return null;
    }
  }
}
