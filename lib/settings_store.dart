import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class SettingsStore {
  SettingsStore({
    FlutterSecureStorage? secureStorage,
  }) : _secure = secureStorage ?? const FlutterSecureStorage();

  static const _settingsKey = 'codekey.settings.v1';
  static const _apiKeyKey = 'codekey.api_key';
  static const _setupKeyKey = 'codekey.setup_key';
  static const _clientIdKey = 'codekey.client_id';

  final FlutterSecureStorage _secure;

  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_settingsKey);
    final apiKey = await _secure.read(key: _apiKeyKey) ?? '';
    final setupKey = await _secure.read(key: _setupKeyKey) ?? '';
    if (raw == null || raw.isEmpty) {
      return AppSettings(apiKey: apiKey, setupKey: setupKey);
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return AppSettings.fromPersistedJson(
          decoded,
          apiKey: apiKey,
          setupKey: setupKey,
        );
      }
    } on FormatException {
      // Fall through to safe defaults.
    }
    return AppSettings(apiKey: apiKey, setupKey: setupKey);
  }

  Future<void> save(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_settingsKey, settings.encodePersisted());
    await _secure.write(key: _apiKeyKey, value: settings.apiKey);
    await _secure.write(key: _setupKeyKey, value: settings.setupKey);
  }

  Future<String> clientId() async {
    final stored = await _secure.read(key: _clientIdKey);
    if (stored != null && stored.length >= 16) return stored;
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    final value = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    await _secure.write(key: _clientIdKey, value: value);
    return value;
  }
}
