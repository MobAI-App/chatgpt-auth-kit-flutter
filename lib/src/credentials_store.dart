import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'credentials.dart';

/// Persists [Credentials] in the platform-secure store
/// (iOS Keychain / Android Keystore-backed shared preferences).
class CredentialsStore {
  final String key;
  final FlutterSecureStorage _storage;

  CredentialsStore({this.key = 'chatgpt_auth_credentials'})
      : _storage = const FlutterSecureStorage(
          iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
          aOptions: AndroidOptions(encryptedSharedPreferences: true),
        );

  Future<void> save(Credentials creds) async {
    await _storage.write(key: key, value: jsonEncode(creds.toJson()));
  }

  Future<Credentials?> load() async {
    final raw = await _storage.read(key: key);
    if (raw == null) return null;
    try {
      return Credentials.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    await _storage.delete(key: key);
  }
}
