import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/posbon_safe_models.dart';

class PosbonSafeService {
  PosbonSafeService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const String _itemsKey = 'posbon_safe_items';
  static const String _pinHashKey = 'posbon_safe_pin_hash';

  Future<List<SafeCredential>> loadItems() async {
    final raw = await _storage.read(key: _itemsKey);
    if (raw == null || raw.isEmpty) {
      return const <SafeCredential>[];
    }

    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return const <SafeCredential>[];
    }

    return decoded
        .whereType<Map>()
        .map(
          (item) => SafeCredential.fromJson(
            item.map(
              (key, value) => MapEntry(key.toString(), value),
            ),
          ),
        )
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> saveItems(List<SafeCredential> items) {
    final payload = jsonEncode(items.map((item) => item.toJson()).toList());
    return _storage.write(key: _itemsKey, value: payload);
  }

  Future<bool> hasPin() async {
    final hash = await _storage.read(key: _pinHashKey);
    return hash != null && hash.isNotEmpty;
  }

  Future<void> savePin(String pin) async {
    final normalized = pin.trim();
    final hash = sha256.convert(utf8.encode(normalized)).toString();
    await _storage.write(key: _pinHashKey, value: hash);
  }

  Future<bool> verifyPin(String pin) async {
    final currentHash = await _storage.read(key: _pinHashKey);
    if (currentHash == null || currentHash.isEmpty) {
      return false;
    }
    final candidateHash = sha256.convert(utf8.encode(pin.trim())).toString();
    return currentHash == candidateHash;
  }
}
