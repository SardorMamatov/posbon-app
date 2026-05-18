import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:crypto/crypto.dart';

import '../models/security_models.dart';
import 'file_scan_io_service.dart';
import 'permission_analyzer.dart';
import 'virus_total_service.dart';

class ApkScanResult {
  const ApkScanResult({
    required this.filePath,
    required this.fileName,
    required this.sha256Hash,
    required this.riskLevel,
    required this.finalScore,
    required this.permissionResult,
    required this.vtResult,
    required this.installSource,
    required this.scannedAt,
    this.fsioResult,
  });

  final String filePath;
  final String fileName;
  final String sha256Hash;
  final RiskLevel riskLevel;
  final int finalScore;
  final PermissionResult permissionResult;
  final VirusTotalResult vtResult;
  final FileScanIoResult? fsioResult;
  final String installSource;
  final DateTime scannedAt;

  String get riskSummary {
    final parts = <String>[];
    final dangerousPermissions = permissionResult.dangerousPermissions;

    if (dangerousPermissions.isNotEmpty) {
      final topReasons = dangerousPermissions
          .take(2)
          .map((permission) => permission.reason)
          .join(', ');
      parts.add('${dangerousPermissions.length} ta xavfli ruxsat: $topReasons');
    }

    if (permissionResult.detectedCombos.isNotEmpty) {
      parts.add(permissionResult.detectedCombos.join(', '));
    }

    if (vtResult.detectedCount > 0) {
      final threatLabel = vtResult.detectedAs;
      parts.add(
        threatLabel != null && threatLabel.isNotEmpty
            ? 'VirusTotal ${vtResult.detectedCount} ta engine orqali "$threatLabel" deb topdi'
            : 'VirusTotal ${vtResult.detectedCount} ta engine orqali zararli deb topdi',
      );
    } else if (vtResult.totalEngines > 0) {
      parts.add('VirusTotal zararli belgi topmadi');
    } else if (vtResult.note != null && vtResult.note!.isNotEmpty) {
      parts.add(vtResult.note!);
    } else {
      parts.add('VirusTotal hali ma\'lumot bermadi');
    }

    final fsio = fsioResult;
    if (fsio != null && fsio.note != null && fsio.note!.isNotEmpty) {
      parts.add(fsio.note!);
    }

    return parts.join('. ');
  }
}

class ApkScanEngine {
  ApkScanEngine({
    required PermissionAnalyzer permissionAnalyzer,
    required VirusTotalService virusTotalService,
    FileScanIoService? fileScanIoService,
  }) : _permissionAnalyzer = permissionAnalyzer,
       _virusTotalService = virusTotalService,
       _fileScanIoService = fileScanIoService;

  final PermissionAnalyzer _permissionAnalyzer;
  final VirusTotalService _virusTotalService;
  final FileScanIoService? _fileScanIoService;

  void cancelFileScanIo() => _fileScanIoService?.cancel();

  Future<ApkScanResult> scanApk({
    required String filePath,
    String? installerPackage,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('APK topilmadi: $filePath');
    }

    final sha256Hash = await _sha256OfFile(filePath);

    // APK: permission tahlili + VirusTotal. FileScan.io ishlatilmaydi —
    // VT APK ma'lumotlar bazasi ancha katta va aniqroq.
    final permResultFuture = _permissionAnalyzer.analyze(filePath).onError<
      Object
    >((e, st) {
      debugPrint(
        '[ApkEngine] scanApk - manifest o\'qib bo\'lmadi, VT davom etadi | $filePath\n$e\n$st',
      );
      return const PermissionResult(
        allPermissions: [],
        dangerousPermissions: [],
        detectedCombos: [],
        permissionScore: 0,
      );
    });

    final results = await Future.wait<dynamic>([
      permResultFuture,
      _virusTotalService.checkByHash(filePath),
    ]);

    final permissionResult = results[0] as PermissionResult;
    final vtResult = results[1] as VirusTotalResult;

    var finalScore = permissionResult.permissionScore + vtResult.vtScore;
    finalScore += _installerBonus(installerPackage);
    finalScore = finalScore.clamp(0, 100);

    return ApkScanResult(
      filePath: filePath,
      fileName: file.uri.pathSegments.last,
      sha256Hash: sha256Hash,
      riskLevel: _riskFromScore(finalScore, vtResult: vtResult),
      finalScore: finalScore,
      permissionResult: permissionResult,
      vtResult: vtResult,
      installSource: _installerLabel(installerPackage),
      scannedAt: DateTime.now(),
    );
  }

  Future<ApkScanResult> scanNonApkFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('Fayl topilmadi: $filePath');
    }

    // ZIP/DEX/JAR/XAPK: FileScan.io primary (dinamik tahlil).
    // FileScan.io sozlanmagan bo'lsa, VT hash tekshiruvi fallback sifatida.
    final fsio = _fileScanIoService;

    FileScanIoResult fsioResult;
    VirusTotalResult vtResult;

    if (fsio != null) {
      fsioResult = await fsio.scanFile(filePath);
      vtResult = const VirusTotalResult(
        wasFound: false,
        maliciousCount: 0,
        suspiciousCount: 0,
        totalEngines: 0,
        vtScore: 0,
      );
    } else {
      vtResult = await _virusTotalService.checkByHash(filePath);
      fsioResult = FileScanIoResult.empty;
    }

    final finalScore = (vtResult.vtScore + fsioResult.fsioScore).clamp(0, 100);

    const emptyPermissions = PermissionResult(
      allPermissions: [],
      dangerousPermissions: [],
      detectedCombos: [],
      permissionScore: 0,
    );

    return ApkScanResult(
      filePath: filePath,
      fileName: file.uri.pathSegments.last,
      sha256Hash: '',
      riskLevel: _riskFromScore(
        finalScore,
        vtResult: vtResult,
        fsioResult: fsioResult,
      ),
      finalScore: finalScore,
      permissionResult: emptyPermissions,
      vtResult: vtResult,
      fsioResult: fsioResult,
      installSource: 'Fayl',
      scannedAt: DateTime.now(),
    );
  }

  Future<ApkScanResult> scanApkLocally({
    required String filePath,
    String? installerPackage,
    bool includeInstallerBonus = false,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('APK topilmadi: $filePath');
    }

    try {
      final permissionResult = await _permissionAnalyzer.analyze(filePath);

      var finalScore = permissionResult.permissionScore;
      if (includeInstallerBonus) {
        finalScore += _installerBonus(installerPackage);
      }
      finalScore = finalScore.clamp(0, 100);

      return ApkScanResult(
        filePath: filePath,
        fileName: file.uri.pathSegments.last,
        sha256Hash: '',
        riskLevel: _riskFromScore(
          finalScore,
          vtResult: const VirusTotalResult(
            wasFound: false,
            maliciousCount: 0,
            suspiciousCount: 0,
            totalEngines: 0,
            vtScore: 0,
          ),
        ),
        finalScore: finalScore,
        permissionResult: permissionResult,
        vtResult: const VirusTotalResult(
          wasFound: false,
          maliciousCount: 0,
          suspiciousCount: 0,
          totalEngines: 0,
          note: 'Faqat lokal permission tahlili bajarildi.',
          vtScore: 0,
        ),
        installSource: _installerLabel(installerPackage),
        scannedAt: DateTime.now(),
      );
    } catch (e, st) {
      debugPrint(
        '[ApkEngine] scanApkLocally - manifest o\'qib bo\'lmadi | $filePath\n$e\n$st',
      );
      return ApkScanResult(
        filePath: filePath,
        fileName: file.uri.pathSegments.last,
        sha256Hash: '',
        riskLevel: RiskLevel.safe,
        finalScore: 0,
        permissionResult: const PermissionResult(
          allPermissions: [],
          dangerousPermissions: [],
          detectedCombos: [],
          permissionScore: 0,
        ),
        vtResult: const VirusTotalResult(
          wasFound: false,
          maliciousCount: 0,
          suspiciousCount: 0,
          totalEngines: 0,
          note:
              'Manifest o\'qib bo\'lmadi — APK noto\'g\'ri ZIP strukturasida.',
          vtScore: 0,
        ),
        installSource: _installerLabel(installerPackage),
        scannedAt: DateTime.now(),
      );
    }
  }

  Future<String> _sha256OfFile(String path) async {
    Digest? result;
    final inputSink = sha256.startChunkedConversion(
      _DigestSink((d) => result = d),
    );
    await for (final chunk in File(path).openRead()) {
      inputSink.add(chunk);
    }
    inputSink.close();
    return result!.toString();
  }

  int _installerBonus(String? installerPackage) {
    if (installerPackage == 'com.android.vending') return -10;
    if (installerPackage == 'com.telegram.messenger' ||
        installerPackage == 'org.telegram.messenger') {
      return 8;
    }
    if (installerPackage == null) return 18;
    if (installerPackage.trim().isEmpty) return 16;
    return 14;
  }

  String _installerLabel(String? installerPackage) {
    if (installerPackage == 'com.android.vending') return 'Play Store';
    if (installerPackage == 'com.telegram.messenger' ||
        installerPackage == 'org.telegram.messenger') {
      return 'Telegram';
    }
    return 'Noma\'lum';
  }

  RiskLevel _riskFromScore(
    int score, {
    required VirusTotalResult vtResult,
    FileScanIoResult? fsioResult,
  }) {
    if (vtResult.detectedCount > 0 || (fsioResult?.hasThreat ?? false)) {
      return RiskLevel.dangerous;
    }
    if (score >= 28) return RiskLevel.suspicious;
    return RiskLevel.safe;
  }
}

class _DigestSink implements Sink<Digest> {
  _DigestSink(this._onDigest);
  final void Function(Digest) _onDigest;
  @override
  void add(Digest data) => _onDigest(data);
  @override
  void close() {}
}

