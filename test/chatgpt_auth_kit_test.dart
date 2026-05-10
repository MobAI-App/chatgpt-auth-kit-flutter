import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:chatgpt_auth_kit/chatgpt_auth_kit.dart';

String _b64UrlNoPad(String s) =>
    base64Url.encode(utf8.encode(s)).replaceAll('=', '');

String _makeJwt(Map<String, dynamic> payload) {
  final body = _b64UrlNoPad(jsonEncode(payload));
  return 'header.$body.sig';
}

void main() {
  group('PKCE / authorization URL', () {
    test('authorization URL contains required PKCE params', () {
      final req = OAuthClient.buildAuthorizationURL();
      expect(req.url.queryParameters['client_id'], OAuthClient.clientID);
      expect(req.url.queryParameters['redirect_uri'], OAuthClient.redirectURI);
      expect(req.url.queryParameters['response_type'], 'code');
      expect(req.url.queryParameters['code_challenge_method'], 'S256');
      expect(req.url.queryParameters['state'], req.state);
      expect(req.verifier.isNotEmpty, true);
      expect(req.verifier.contains('='), false);
    });
  });

  group('Credentials', () {
    test('expiry boundary respects buffer', () {
      final c = Credentials(
        accessToken: 'x',
        refreshToken: 'y',
        expiresAt: DateTime.now().add(const Duration(seconds: 60)),
        accountID: 'z',
      );
      expect(c.isExpired(buffer: const Duration(seconds: 120)), true);
      expect(c.isExpired(buffer: const Duration(seconds: 30)), false);
    });

    test('round-trips through JSON', () {
      final c = Credentials(
        accessToken: 'a',
        refreshToken: 'b',
        expiresAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        accountID: 'acc_x',
      );
      final back = Credentials.fromJson(jsonDecode(jsonEncode(c.toJson())) as Map<String, dynamic>);
      expect(back.accessToken, 'a');
      expect(back.accountID, 'acc_x');
      expect(back.expiresAt.millisecondsSinceEpoch, 1700000000000);
    });
  });

  group('JWT', () {
    test('extracts account id from auth claim', () {
      final token = _makeJwt({
        'https://api.openai.com/auth': {
          'chatgpt_account_id': 'acc_111',
          'chatgpt_plan_type': 'plus',
        },
      });
      expect(Jwt.extractAccountID(token), 'acc_111');
      expect(Jwt.extractPlanType(token), 'plus');
    });

    test('falls back to top-level claim', () {
      final token = _makeJwt({
        'chatgpt_account_id': 'acc_222',
        'chatgpt_plan_type': 'pro',
      });
      expect(Jwt.extractAccountID(token), 'acc_222');
      expect(Jwt.extractPlanType(token), 'pro');
    });

    test('falls back to organizations[0].id', () {
      final token = _makeJwt({
        'organizations': [
          {'id': 'org_333'},
        ],
      });
      expect(Jwt.extractAccountID(token), 'org_333');
      expect(Jwt.extractPlanType(token), null);
    });

    test('returns null for malformed tokens', () {
      expect(Jwt.extractAccountID('not.a.jwt'), null);
      expect(Jwt.extractAccountID('two.parts'), null);
      expect(Jwt.extractAccountID(''), null);
    });
  });

  group('UsageClient.parse', () {
    test('decodes a full payload', () {
      final json = {
        'plan_type': 'plus',
        'rate_limit': {
          'primary_window': {'used_percent': 12.5, 'limit_window_seconds': 18000, 'reset_at': 9999},
          'secondary_window': {'used_percent': 4, 'limit_window_seconds': 604800, 'reset_at': 11111},
        },
        'credits': {'has_credits': true, 'unlimited': false, 'balance': '9.99'},
        'rate_limit_reached_type': {'kind': 'credit_depleted'},
      };
      final s = UsageClient.parse(json);
      expect(s.planType, 'plus');
      expect(s.primary?.usedPercent, 12.5);
      expect(s.primary?.windowSeconds, 18000);
      expect(s.secondary?.usedPercent, 4);
      expect(s.credits?.balance, '9.99');
      expect(s.limitReachedKind, 'credit_depleted');
    });

    test('tolerates missing fields', () {
      final s = UsageClient.parse({'plan_type': 'free'});
      expect(s.planType, 'free');
      expect(s.primary, null);
      expect(s.secondary, null);
      expect(s.credits, null);
      expect(s.limitReachedKind, null);
    });
  });

  group('RefreshingCredentialsProvider', () {
    final fresh = Credentials(
      accessToken: 'ok',
      refreshToken: 'r',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
      accountID: 'a',
    );
    final stale = Credentials(
      accessToken: 'old',
      refreshToken: 'r',
      expiresAt: DateTime.now().subtract(const Duration(seconds: 60)),
      accountID: 'a',
    );
    final refreshed = Credentials(
      accessToken: 'new',
      refreshToken: 'r2',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
      accountID: 'a',
    );

    test('returns cached credentials when fresh', () async {
      final provider = RefreshingCredentialsProvider(
        fresh,
        refresh: (_) async {
          fail('refresh should not be called when token is fresh');
        },
      );
      final c = await provider.currentCredentials();
      expect(c.accessToken, 'ok');
    });

    test('refreshes when expired', () async {
      final provider = RefreshingCredentialsProvider(
        stale,
        refresh: (_) async => refreshed,
      );
      final c = await provider.currentCredentials();
      expect(c.accessToken, 'new');
      expect(c.refreshToken, 'r2');
    });

    test('coalesces concurrent refreshes', () async {
      var calls = 0;
      final provider = RefreshingCredentialsProvider(
        stale,
        refresh: (_) async {
          calls += 1;
          await Future.delayed(const Duration(milliseconds: 50));
          return refreshed;
        },
      );
      final results = await Future.wait([
        provider.currentCredentials(),
        provider.currentCredentials(),
        provider.currentCredentials(),
      ]);
      expect(results.map((c) => c.accessToken), ['new', 'new', 'new']);
      expect(calls, 1);
    });

    test('propagates refresh failure', () async {
      final provider = RefreshingCredentialsProvider(
        stale,
        refresh: (_) async => throw StateError('boom'),
      );
      await expectLater(provider.currentCredentials(), throwsA(isA<StateError>()));
    });
  });
}
