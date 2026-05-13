import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'app_locale.dart';

class SettingsController extends ChangeNotifier {
  SettingsController({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _kLocale = 'posbon.locale';
  static const _kAgreementAccepted = 'posbon.terms_accepted_v1';
  static const _kLiveMonitoring = 'posbon.live_monitoring';
  static const _kFullScanMode = 'posbon.full_scan_mode';
  static const _kScreenProtection = 'posbon.screen_protection';

  AppLocale _locale = AppLocale.uz;
  bool _agreementAccepted = false;
  bool _liveMonitoring = true;
  bool _fullScanMode = false;
  bool _screenProtection = false;
  bool _initialized = false;
  Future<void>? _loadFuture;

  AppLocale get locale => _locale;
  bool get agreementAccepted => _agreementAccepted;
  bool get liveMonitoring => _liveMonitoring;

  /// true = Full Scan (VT + FileScanIo), false = Smart Scan (local only).
  bool get fullScanMode => _fullScanMode;

  /// true = FLAG_SECURE active, prevents screenshots/screen recording.
  bool get screenProtection => _screenProtection;

  bool get initialized => _initialized;

  Future<void> load() {
    final existing = _loadFuture;
    if (existing != null) return existing;
    final future = _doLoad();
    _loadFuture = future;
    return future;
  }

  Future<void> _doLoad() async {
    try {
      final values = await Future.wait<String?>([
        _storage.read(key: _kLocale),
        _storage.read(key: _kAgreementAccepted),
        _storage.read(key: _kLiveMonitoring),
        _storage.read(key: _kFullScanMode),
        _storage.read(key: _kScreenProtection),
      ]);
      _locale = AppLocale.fromCode(values[0]);
      _agreementAccepted = values[1] == '1';
      _liveMonitoring = values[2] == null ? true : values[2] == '1';
      _fullScanMode = values[3] == '1';
      _screenProtection = values[4] == '1';
    } catch (_) {
    } finally {
      _initialized = true;
      notifyListeners();
    }
  }

  Future<void> setLocale(AppLocale locale) async {
    if (_locale == locale) return;
    _locale = locale;
    notifyListeners();
    try {
      await _storage.write(key: _kLocale, value: locale.code);
    } catch (_) {}
  }

  Future<void> acceptAgreement() async {
    if (_agreementAccepted) return;
    _agreementAccepted = true;
    notifyListeners();
    try {
      await _storage.write(key: _kAgreementAccepted, value: '1');
    } catch (_) {}
  }

  Future<void> setLiveMonitoring(bool value) async {
    if (_liveMonitoring == value) return;
    _liveMonitoring = value;
    notifyListeners();
    try {
      await _storage.write(key: _kLiveMonitoring, value: value ? '1' : '0');
    } catch (_) {}
  }

  Future<void> setFullScanMode(bool value) async {
    if (_fullScanMode == value) return;
    _fullScanMode = value;
    notifyListeners();
    try {
      await _storage.write(key: _kFullScanMode, value: value ? '1' : '0');
    } catch (_) {}
  }

  Future<void> setScreenProtection(bool value) async {
    if (_screenProtection == value) return;
    _screenProtection = value;
    notifyListeners();
    try {
      await _storage.write(key: _kScreenProtection, value: value ? '1' : '0');
    } catch (_) {}
  }
}
