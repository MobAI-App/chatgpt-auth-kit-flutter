import 'dart:async';
import 'dart:io';

/// Minimal HTTP/1.1 server bound to `localhost:<port>` (IPv4 + IPv6) that
/// resolves the first inbound `GET /auth/callback` with its query parameters.
/// Only handles a single request; call [stop] to release the port early.
class LoopbackServer {
  final int port;
  final List<HttpServer> _servers = [];
  final Completer<Map<String, String>> _completer = Completer();
  bool _finished = false;

  LoopbackServer(this.port);

  /// Binds the listener(s). Resolves once at least one of IPv4/IPv6 is
  /// listening. After this future completes it's safe to direct the browser
  /// at `http://localhost:<port>/auth/callback`.
  Future<void> start() async {
    Object? lastError;
    try {
      final v4 = await HttpServer.bind(InternetAddress.loopbackIPv4, port, shared: true);
      _servers.add(v4);
      _serve(v4);
    } catch (e) {
      lastError = e;
    }
    try {
      final v6 = await HttpServer.bind(InternetAddress.loopbackIPv6, port, shared: true);
      _servers.add(v6);
      _serve(v6);
    } catch (_) {
      // IPv6 bind may fail on some networks; IPv4 alone is enough on most setups.
    }
    if (_servers.isEmpty) {
      throw StateError('Loopback listen failed: $lastError');
    }
  }

  /// Suspends until the loopback receives an `/auth/callback` request, [stop]
  /// is called, or a listener fails. Throws on stop or error.
  Future<Map<String, String>> waitForCallback() => _completer.future;

  void stop() {
    if (!_finished && !_completer.isCompleted) {
      _finished = true;
      _completer.completeError(StateError('Loopback server stopped.'));
    }
    for (final s in _servers) {
      s.close(force: true);
    }
    _servers.clear();
  }

  void _serve(HttpServer server) {
    server.listen((HttpRequest req) async {
      try {
        if (req.method != 'GET') {
          req.response
            ..statusCode = 405
            ..write('Method not allowed');
          await req.response.close();
          return;
        }
        if (req.uri.path != '/auth/callback') {
          req.response
            ..statusCode = 404
            ..write('Not found');
          await req.response.close();
          return;
        }
        final query = Map<String, String>.from(req.uri.queryParameters);
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType.html
          ..write(_successHtml);
        await req.response.close();
        _finish(query: query);
      } catch (e) {
        _finish(error: 'Handler failed: $e');
      }
    }, onError: (e) => _finish(error: 'Listen error: $e'));
  }

  void _finish({Map<String, String>? query, String? error}) {
    if (_finished) return;
    _finished = true;
    for (final s in _servers) {
      s.close(force: true);
    }
    _servers.clear();
    if (error != null) {
      if (!_completer.isCompleted) _completer.completeError(StateError(error));
    } else if (query != null) {
      if (!_completer.isCompleted) _completer.complete(query);
    }
  }

  static const _successHtml = '''
<!doctype html><html><head><meta charset="utf-8"><title>Done</title>
<style>body{font-family:-apple-system,sans-serif;text-align:center;padding:40px;color:#222}h2{color:#10a37f}</style>
</head><body>
<h2>Authentication successful</h2>
<p>You can close this tab and return to the app.</p>
</body></html>
''';
}
