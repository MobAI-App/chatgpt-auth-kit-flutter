## 0.1.0

Initial release.

- `OAuthFlow` + `LoopbackServer`: PKCE flow with a localhost:1455 callback,
  binds IPv4+IPv6 before the browser is launched.
- `CredentialsStore`: `flutter_secure_storage`-backed persistence
  (iOS Keychain / Android Keystore).
- `RefreshingCredentialsProvider`: caches credentials, refreshes via
  `OAuthClient.refresh` when near-expiry, coalesces concurrent refreshes,
  persists to the store.
- `ResponsesClient` / `ModelsClient` / `UsageClient`: minimal hand-rolled
  REST/SSE clients pointed at `chatgpt.com/backend-api/codex`.
- 13 tests covering PKCE, JWT decode, Usage parse, the refreshing
  provider's caching / refresh / coalesce / failure paths.
