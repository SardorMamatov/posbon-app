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

  AppLocale _locale = AppLocale.uz;
  bool _agreementAccepted = false;
  bool _liveMonitoring = true;
  bool _initialized = false;

  AppLocale get locale => _locale;
  bool get agreementAccepted => _agreementAccepted;
  bool get liveMonitoring => _liveMonitoring;
  bool get initialized => _initialized;

  Future<void> load() async {
    try {
      final localeCode = await _storage.read(key: _kLocale);
      final accepted = await _storage.read(key: _kAgreementAccepted);
      final monitoring = await _storage.read(key: _kLiveMonitoring);

      _locale = AppLocale.fromCode(localeCode);
      _agreementAccepted = accepted == '1';
      _liveMonitoring = monitoring == null ? true : monitoring == '1';
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
}
