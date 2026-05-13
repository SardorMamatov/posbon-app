import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/security_models.dart';

class HistoryService {
  HistoryService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _kKey = 'posbon.history_v1';
  static const int _maxEntries = 200;

  Future<List<ScanFinding>> load() async {
    try {
      final raw = await _storage.read(key: _kKey);
      if (raw == null || raw.isEmpty) return [];
      return ScanFinding.decodeList(raw);
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<ScanFinding> findings) async {
    try {
      final capped = findings.length > _maxEntries
          ? findings.sublist(0, _maxEntries)
          : findings;
      await _storage.write(key: _kKey, value: ScanFinding.encodeList(capped));
    } catch (_) {}
  }

  Future<void> clear() async {
    try {
      await _storage.delete(key: _kKey);
    } catch (_) {}
  }
}
