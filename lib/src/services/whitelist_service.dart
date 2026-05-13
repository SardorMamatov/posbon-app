import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class WhitelistService {
  WhitelistService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _kKey = 'posbon.whitelist_v1';

  Set<String> _packages = {};

  Set<String> get packages => Set.unmodifiable(_packages);

  Future<void> load() async {
    try {
      final raw = await _storage.read(key: _kKey);
      if (raw != null && raw.isNotEmpty) {
        final list = (jsonDecode(raw) as List<dynamic>)
            .map((e) => e.toString())
            .toSet();
        _packages = list;
      }
    } catch (_) {}
  }

  bool contains(String packageName) => _packages.contains(packageName);

  Future<void> add(String packageName) async {
    if (_packages.add(packageName)) await _save();
  }

  Future<void> remove(String packageName) async {
    if (_packages.remove(packageName)) await _save();
  }

  Future<void> _save() async {
    try {
      await _storage.write(
        key: _kKey,
        value: jsonEncode(_packages.toList()),
      );
    } catch (_) {}
  }
}
