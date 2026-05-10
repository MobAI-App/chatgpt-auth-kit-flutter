import 'dart:async';
import 'package:url_launcher/url_launcher.dart';

import 'credentials.dart';
import 'loopback_server.dart';
import 'oauth_client.dart';

/// High-level orchestrator for the full OAuth login flow.
///
/// Handles: URL construction → loopback listener bind → URL presentation
/// (via the caller's hook or `url_launcher`) → callback parsing → token
/// exchange. The caller only needs to: provide an optional `present(Uri)`
/// closure that opens the URL in an in-app browser, and `await` the returned
/// credentials.
class OAuthFlow {
  final String originator;
  final Duration timeout;

  OAuthFlow({
    this.originator = 'codex_cli_rs',
    this.timeout = const Duration(minutes: 5),
  });

  /// Runs the full flow. If [present] is provided it's invoked once with the
  /// authorization URL — wire it to your in-app browser. If omitted, opens
  /// the system browser via `url_launcher`.
  Future<Credentials> run({
    Future<void> Function(Uri url)? present,
    Future<void> Function()? onComplete,
  }) async {
    final request = OAuthClient.buildAuthorizationURL(originator: originator);

    final server = LoopbackServer(OAuthClient.callbackPort);
    await server.start();

    if (present != null) {
      await present(request.url);
    } else {
      await launchUrl(request.url, mode: LaunchMode.externalApplication);
    }

    Map<String, String> query;
    try {
      query = await server.waitForCallback().timeout(timeout, onTimeout: () {
        server.stop();
        throw OAuthException.timedOut();
      });
    } finally {
      server.stop();
      if (onComplete != null) await onComplete();
    }

    if (query.containsKey('error')) {
      throw OAuthException.providerError(query['error']!, query['error_description']);
    }
    if (query['state'] != request.state) throw OAuthException.stateMismatch();
    final code = query['code'];
    if (code == null || code.isEmpty) throw OAuthException.noCode();

    return OAuthClient.exchangeCode(code: code, verifier: request.verifier);
  }
}
