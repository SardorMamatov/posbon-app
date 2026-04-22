import 'dart:io';

import 'package:crypto/crypto.dart';

import '../models/security_models.dart';
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
  });

  final String filePath;
  final String fileName;
  final String sha256Hash;
  final RiskLevel riskLevel;
  final int finalScore;
  final PermissionResult permissionResult;
  final VirusTotalResult vtResult;
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
      parts.add(
        '${dangerousPermissions.length} ta xavfli ruxsat: $topReasons',
      );
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

    return parts.join('. ');
  }
}

class ApkScanEngine {
  ApkScanEngine({
    required PermissionAnalyzer permissionAnalyzer,
    required VirusTotalService virusTotalService,
  })  : _permissionAnalyzer = permissionAnalyzer,
        _virusTotalService = virusTotalService;

  final PermissionAnalyzer _permissionAnalyzer;
  final VirusTotalService _virusTotalService;

  Future<ApkScanResult> scanApk({
    required String filePath,
    String? installerPackage,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('APK topilmadi: $filePath');
    }

    final bytes = await file.readAsBytes();
    final sha256Hash = sha256.convert(bytes).toString();

    final results = await Future.wait<dynamic>([
      _permissionAnalyzer.analyze(filePath),
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

  Future<ApkScanResult> scanApkLocally({
    required String filePath,
    String? installerPackage,
    bool includeInstallerBonus = false,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('APK topilmadi: $filePath');
    }

    final bytes = await file.readAsBytes();
    final sha256Hash = sha256.convert(bytes).toString();
    final permissionResult = await _permissionAnalyzer.analyze(filePath);

    var finalScore = permissionResult.permissionScore;
    if (includeInstallerBonus) {
      finalScore += _installerBonus(installerPackage);
    }
    finalScore = finalScore.clamp(0, 100);

    return ApkScanResult(
      filePath: filePath,
      fileName: file.uri.pathSegments.last,
      sha256Hash: sha256Hash,
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
  }) {
    if (vtResult.detectedCount > 0) {
      return RiskLevel.dangerous;
    }
    if (score >= 28) return RiskLevel.suspicious;
    return RiskLevel.safe;
  }
}
