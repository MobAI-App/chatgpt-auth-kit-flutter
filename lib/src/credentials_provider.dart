import 'dart:async';

import 'credentials.dart';
import 'credentials_store.dart';
import 'oauth_client.dart';

/// Source-of-truth for the access token used by the API clients
/// ([ResponsesClient], [ModelsClient], [UsageClient]).
///
/// The default implementation, [RefreshingCredentialsProvider], swaps in fresh
/// credentials from [OAuthClient.refresh] when the access token is about to
/// expire, and persists the result via [CredentialsStore]. Build one of those
/// at app start and hand it to every client; never store a bare [Credentials]
/// in long-lived state.
abstract class CredentialsProvider {
  /// Returns valid credentials, refreshing them first if they're stale.
  Future<Credentials> currentCredentials();
}

/// Wraps a single [Credentials] value as a non-refreshing provider. Useful
/// for one-shot calls or tests; production callers should use
/// [RefreshingCredentialsProvider].
class StaticCredentialsProvider implements CredentialsProvider {
  final Credentials credentials;
  StaticCredentialsProvider(this.credentials);

  @override
  Future<Credentials> currentCredentials() async => credentials;
}

/// Caches credentials and refreshes them via [OAuthClient.refresh] when
/// [Credentials.isExpired] is true. Concurrent callers during a refresh share
/// a single in-flight refresh future. Optionally writes the new credentials
/// back to a [CredentialsStore] so they survive app launches.
class RefreshingCredentialsProvider implements CredentialsProvider {
  Credentials _credentials;
  final CredentialsStore? _store;
  final Duration _buffer;
  final Future<Credentials> Function(Credentials) _refresh;
  Future<Credentials>? _refreshFuture;

  RefreshingCredentialsProvider(
    Credentials credentials, {
    CredentialsStore? store,
    Duration buffer = const Duration(minutes: 5),
    Future<Credentials> Function(Credentials)? refresh,
  })  : _credentials = credentials,
        _store = store,
        _buffer = buffer,
        _refresh = refresh ?? OAuthClient.refresh;

  @override
  Future<Credentials> currentCredentials() async {
    if (!_credentials.isExpired(buffer: _buffer)) return _credentials;

    final pending = _refreshFuture;
    if (pending != null) return pending;

    final current = _credentials;
    final future = () async {
      try {
        final fresh = await _refresh(current);
        _credentials = fresh;
        try {
          await _store?.save(fresh);
        } catch (_) {
          // best-effort persist; the in-memory copy is still updated.
        }
        return fresh;
      } finally {
        _refreshFuture = null;
      }
    }();
    _refreshFuture = future;
    return future;
  }

  /// Replace the cached credentials (e.g. after a fresh sign-in) and persist.
  Future<void> update(Credentials credentials) async {
    _credentials = credentials;
    try {
      await _store?.save(credentials);
    } catch (_) {}
  }
}
