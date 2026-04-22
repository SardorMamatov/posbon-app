import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_device_apps/flutter_device_apps.dart';

import '../models/security_models.dart';
import 'apk_scan_engine.dart';
import 'file_scan_service.dart';
import 'native_package_service.dart';
import 'permission_analyzer.dart';
import 'virus_total_service.dart';

class AppScanProgress {
  const AppScanProgress({
    required this.current,
    required this.total,
    required this.label,
  });

  final int current;
  final int total;
  final String label;
}

class AppScanService {
  AppScanService({
    required VirusTotalService virusTotalService,
    required NativePackageService nativePackageService,
    ApkScanEngine? apkScanEngine,
  })  : _nativePackageService = nativePackageService,
        _apkScanEngine = apkScanEngine ??
            ApkScanEngine(
              permissionAnalyzer: PermissionAnalyzer(),
              virusTotalService: virusTotalService,
            );

  final NativePackageService _nativePackageService;
  final ApkScanEngine _apkScanEngine;
  static const Set<String> _trustedPackageNames = {
    'com.example.posbon_app',
    'com.google.android.apps.meetings',
    'org.telegram.messenger',
    'com.telegram.messenger',
    'com.whatsapp',
    'com.instagram.android',
    'com.facebook.katana',
    'com.google.android.gm',
    'com.android.chrome',
    'com.google.android.apps.maps',
    'com.google.android.youtube',
    'com.google.android.apps.messaging',
    'com.google.android.dialer',
    'com.google.android.contacts',
    'com.smartbanking.clickuz',
    'uz.dida.payme',
    'uz.paynet.mobile',
    'uz.uzum.mobile',
    'uz.uzumbank.mobile',
    'uz.uzum.market',
    'uz.soliq.mobile',
  };
  static const Set<String> _trustedAppNames = {
    'posbon',
    'telegram',
    'telegram x',
    'google meet',
    'click',
    'click superapp',
    'payme',
    'paynet',
    'uzum',
    'uzum bank',
    'uzum market',
    'soliq',
    'mygov',
    'gmail',
    'chrome',
    'google maps',
    'youtube',
    'whatsapp',
    'instagram',
    'facebook',
    'zoom',
    'microsoft teams',
    'kapitalbank',
    'apelsin',
    'humans',
  };
  static const Map<String, int> _installedPermissionScores = {
    'android.permission.BIND_ACCESSIBILITY_SERVICE': 35,
    'android.permission.READ_SMS': 18,
    'android.permission.SEND_SMS': 18,
    'android.permission.RECEIVE_SMS': 12,
    'android.permission.READ_CALL_LOG': 12,
    'android.permission.PROCESS_OUTGOING_CALLS': 12,
    'android.permission.REQUEST_INSTALL_PACKAGES': 12,
    'android.permission.RECEIVE_BOOT_COMPLETED': 6,
    'android.permission.RECORD_AUDIO': 3,
    'android.permission.READ_CONTACTS': 2,
    'android.permission.ACCESS_FINE_LOCATION': 2,
    'android.permission.FOREGROUND_SERVICE': 1,
    'android.permission.CAMERA': 0,
  };

  Future<List<ProtectedApp>> loadInstalledApps() async {
    final apps = await FlutterDeviceApps.listApps(
      includeIcons: true,
      includeSystem: false,
      onlyLaunchable: true,
    );

    final results = await Future.wait(
      apps.map((app) async {
        final installerStore = await FlutterDeviceApps.getInstallerStore(
          app.packageName ?? '',
        );
        return _applyTrustOverride(
          ProtectedApp(
            packageName: app.packageName ?? '',
            name: app.appName ?? app.packageName ?? 'Noma\'lum ilova',
            version: app.versionName ?? 'unknown',
            iconBytes: app.iconBytes,
            icon: Icons.android_rounded,
            risk: _sourceRisk(installerStore),
            riskScore: _sourceScore(installerStore),
            source: _sourceLabel(installerStore),
            installedDate: _formatDate(app.firstInstallTime),
            lastUpdatedDate: _formatDate(app.lastUpdateTime),
            permissions: const [],
            virusTotalDetections: 0,
            virusTotalTotalEngines: 0,
            installerStore: installerStore,
          ),
        );
      }),
    );

    results.sort((a, b) => b.riskScore.compareTo(a.riskScore));
    return results;
  }

  Future<ProtectedApp> enrichAppDetails(ProtectedApp app) async {
    final results = await Future.wait<Object?>([
      _nativePackageService.getRequestedPermissions(app.packageName),
      _nativePackageService.getPackageInfo(app.packageName),
    ]);
    final permissions = (results[0] as List<String>?) ?? const <String>[];
    final nativeInfo = results[1] as NativePackageInfo;

    final permissionModels = permissions.map(
      (permission) {
        final permissionScore = _installedPermissionScores[permission] ?? 0;
        return AppPermission(
          name: permission,
          isDangerous: permissionScore >= 8,
          explanation: _permissionExplanation(permission),
          riskScore: permissionScore,
        );
      },
    ).toList()
      ..sort((a, b) => b.riskScore.compareTo(a.riskScore));

    final riskScore = (_sourceScore(app.installerStore) +
            _installedPermissionRisk(permissionModels))
        .clamp(0, 100);

    final enriched = app.copyWith(
      apkPath: nativeInfo.apkPath,
      permissions: permissionModels,
      riskScore: riskScore,
      risk: _riskFromScore(riskScore),
      lastScanSummary: _summaryFromPermissions(permissionModels),
    );

    return _applyTrustOverride(enriched);
  }

  Future<ProtectedApp> scanInstalledApp(
    ProtectedApp app, {
    bool allowVirusTotalLookup = true,
  }) async {
    final enriched = await enrichAppDetails(app);
    final apkPath = enriched.apkPath;
    if (!allowVirusTotalLookup || apkPath == null || apkPath.isEmpty) {
      return enriched.copyWith(vtScanned: false);
    }

    final apkFile = File(apkPath);
    if (!await apkFile.exists()) {
      return enriched.copyWith(
        vtScanned: false,
        lastScanSummary: 'APK fayli topilmadi',
      );
    }

    final result = await _apkScanEngine.scanApk(
      filePath: apkPath,
      installerPackage: enriched.installerStore,
    );

    final scanned = enriched.copyWith(
      riskScore: result.finalScore,
      risk: result.riskLevel,
      virusTotalDetections: result.vtResult.detectedCount,
      virusTotalTotalEngines: result.vtResult.totalEngines,
      virusTotalThreatLabel: result.vtResult.detectedAs,
      virusTotalNote: result.vtResult.note,
      vtScanned: true,
      lastScanSummary: result.riskSummary,
    );

    return _applyTrustOverride(scanned);
  }

  Stream<ScanProgress> scanInstalledApps() async* {
    final apps = await loadInstalledApps();
    final results = <ApkScanResult>[];
    var threats = 0;

    for (var index = 0; index < apps.length; index++) {
      final app = apps[index];
      final apkPath =
          (await _nativePackageService.getPackageInfo(app.packageName)).apkPath;
      if (apkPath == null || apkPath.isEmpty || !File(apkPath).existsSync()) {
        continue;
      }

      final result = await _apkScanEngine.scanApkLocally(
        filePath: apkPath,
        installerPackage: app.installerStore,
        includeInstallerBonus: true,
      );
      results.add(result);
      if (result.riskLevel.isRisky) {
        threats++;
      }

      yield ScanProgress(
        current: index + 1,
        total: apps.length,
        currentFileName: app.name,
        percentage: apps.isEmpty ? 0 : (index + 1) / apps.length,
        completedResults: List<ApkScanResult>.unmodifiable(results),
        threatsFound: threats,
        statusText: 'Tekshirilmoqda: ${app.name}',
      );
    }
  }

  Future<List<ScanFinding>> quickScanApps(
    List<ProtectedApp> apps, {
    required void Function(AppScanProgress progress) onProgress,
  }) async {
    final findings = <ScanFinding>[];
    for (var index = 0; index < apps.length; index++) {
      final scanned = await scanInstalledApp(
        apps[index],
        allowVirusTotalLookup: false,
      );
      onProgress(
        AppScanProgress(
          current: index + 1,
          total: apps.length,
          label: scanned.name,
        ),
      );
      findings.add(
        ScanFinding(
          name: scanned.name,
          type: ScanTargetType.app,
          risk: scanned.risk,
          details: scanned.lastScanSummary ?? scanned.source,
          reasons: _findingReasons(scanned),
          location: scanned.packageName,
        ),
      );
    }
    return findings;
  }

  RiskLevel _sourceRisk(String? installerStore) =>
      _riskFromScore(_sourceScore(installerStore));

  int _sourceScore(String? installerStore) {
    if (installerStore == 'com.android.vending') return 0;
    if (installerStore == 'com.telegram.messenger' ||
        installerStore == 'org.telegram.messenger') {
      return 12;
    }
    if (installerStore == null || installerStore.isEmpty) return 18;
    return 10;
  }

  int _installedPermissionRisk(List<AppPermission> permissions) {
    final permissionNames = permissions.map((item) => item.name).toSet();
    var score = permissions.fold<int>(
      0,
      (sum, item) => sum + item.riskScore,
    );

    if (_hasAll(permissionNames, const [
      'android.permission.READ_SMS',
      'android.permission.SEND_SMS',
    ])) {
      score += 18;
    }

    if (_hasAll(permissionNames, const [
      'android.permission.BIND_ACCESSIBILITY_SERVICE',
      'android.permission.READ_SMS',
    ])) {
      score += 24;
    }

    if (_hasAll(permissionNames, const [
      'android.permission.REQUEST_INSTALL_PACKAGES',
      'android.permission.RECEIVE_BOOT_COMPLETED',
    ])) {
      score += 10;
    }

    return score;
  }

  bool _hasAll(Set<String> source, List<String> required) =>
      required.every(source.contains);

  RiskLevel _riskFromScore(int score, {int vtDetections = 0}) {
    if (vtDetections > 0) return RiskLevel.dangerous;
    if (score >= 28) return RiskLevel.suspicious;
    return RiskLevel.safe;
  }

  String _sourceLabel(String? installerStore) {
    if (installerStore == 'com.android.vending') return 'Play Store';
    if (installerStore == 'com.telegram.messenger' ||
        installerStore == 'org.telegram.messenger') {
      return 'Telegram';
    }
    return 'Noma\'lum manba';
  }

  String _summaryFromPermissions(List<AppPermission> permissions) {
    final dangerous = permissions.where((item) => item.isDangerous).toList();
    if (dangerous.isEmpty) {
      return 'Shubhali permission topilmadi';
    }

    final preview = dangerous
        .take(2)
        .map((item) => item.explanation ?? item.name)
        .join(', ');
    return '${dangerous.length} ta sezgir permission topildi: $preview';
  }

  String _permissionExplanation(String permission) {
    return PermissionAnalyzer.describePermission(permission);
  }

  ProtectedApp _applyTrustOverride(ProtectedApp app) {
    if (app.virusTotalDetections > 0) {
      return app.copyWith(
        risk: RiskLevel.dangerous,
        isTrusted: false,
      );
    }

    final normalizedName = _normalizeAppName(app.name);
    final isTrusted = _trustedPackageNames.contains(app.packageName) ||
        _trustedAppNames.contains(normalizedName);
    if (!isTrusted) {
      return app.copyWith(isTrusted: false);
    }

    return app.copyWith(
      risk: RiskLevel.safe,
      riskScore: 0,
      isTrusted: true,
      lastScanSummary: app.lastScanSummary ??
          'Mashhur va ishonchli ilova ro\'yxatida. Standart permissionlar sababli shubhali deb belgilanmadi.',
    );
  }

  String _normalizeAppName(String value) {
    final lowered = value.toLowerCase();
    return lowered.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  }

  List<String> _findingReasons(ProtectedApp app) {
    final reasons = <String>[];

    reasons.addAll(
      app.permissions
          .where((permission) => permission.isDangerous)
          .map((permission) => permission.explanation ?? permission.name),
    );

    if (app.virusTotalDetections > 0) {
      final threatLabel = app.virusTotalThreatLabel;
      reasons.add(
        threatLabel != null && threatLabel.isNotEmpty
            ? 'VirusTotal bazasida "$threatLabel" sifatida aniqlandi'
            : 'VirusTotal ${app.virusTotalDetections} ta engine orqali xavfli deb topdi',
      );
    } else if (app.virusTotalNote != null && app.virusTotalNote!.isNotEmpty) {
      reasons.add(app.virusTotalNote!);
    }

    reasons.add('Manba: ${app.source}');

    if (app.isTrusted) {
      reasons.add('Mashhur ilovalar ro\'yxatida mavjud');
    }

    if (reasons.isEmpty) {
      reasons.add(
          'Shubhali belgi topilmadi. Ilova hozircha xavfsiz ko\'rinmoqda.');
    }

    return reasons.toSet().toList();
  }

  String _formatDate(DateTime? value) {
    if (value == null) return 'Noma\'lum';
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    return '$day.$month.${value.year}';
  }
}
