import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/app_theme.dart';

enum RiskLevel { danger, dangerous, suspicious, safe }

extension RiskLevelX on RiskLevel {
  bool get isSafe => this == RiskLevel.safe;

  bool get isDangerous =>
      this == RiskLevel.danger || this == RiskLevel.dangerous;

  bool get isSuspicious => this == RiskLevel.suspicious;

  bool get isRisky => !isSafe;

  String get label => switch (this) {
        RiskLevel.danger => 'Xavfli',
        RiskLevel.dangerous => 'Xavfli',
        RiskLevel.suspicious => 'Shubhali',
        RiskLevel.safe => 'Xavfsiz',
      };

  Color get color => switch (this) {
        RiskLevel.danger => AppColors.danger,
        RiskLevel.dangerous => AppColors.danger,
        RiskLevel.suspicious => AppColors.warning,
        RiskLevel.safe => AppColors.accent,
      };
}

enum RiskFilter { all, dangerous, suspicious, safe }

extension RiskFilterX on RiskFilter {
  String get label => switch (this) {
        RiskFilter.all => 'Barchasi',
        RiskFilter.dangerous => 'Xavfli',
        RiskFilter.suspicious => 'Shubhali',
        RiskFilter.safe => 'Xavfsiz',
      };
}

enum ScanTargetType { app, file }

enum PermissionCardId {
  notifications,
  fileManager,
  mediaFiles,
  monitoring,
  appScanning,
  safeInstall,
}

class OnboardingItem {
  const OnboardingItem({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;
}

class PermissionStatusCard {
  const PermissionStatusCard({
    required this.id,
    required this.icon,
    required this.title,
    required this.description,
    required this.granted,
    this.actionable = true,
    this.statusNote,
  });

  final PermissionCardId id;
  final IconData icon;
  final String title;
  final String description;
  final bool granted;
  final bool actionable;
  final String? statusNote;

  PermissionStatusCard copyWith({
    PermissionCardId? id,
    IconData? icon,
    String? title,
    String? description,
    bool? granted,
    bool? actionable,
    String? statusNote,
  }) {
    return PermissionStatusCard(
      id: id ?? this.id,
      icon: icon ?? this.icon,
      title: title ?? this.title,
      description: description ?? this.description,
      granted: granted ?? this.granted,
      actionable: actionable ?? this.actionable,
      statusNote: statusNote ?? this.statusNote,
    );
  }
}

class ScanTarget {
  const ScanTarget({
    required this.name,
    required this.type,
  });

  final String name;
  final ScanTargetType type;
}

class ScanFinding {
  const ScanFinding({
    required this.name,
    required this.type,
    required this.risk,
    required this.details,
    this.reasons = const <String>[],
    this.location,
  });

  final String name;
  final ScanTargetType type;
  final RiskLevel risk;
  final String details;
  final List<String> reasons;
  final String? location;
}

class AppPermission {
  const AppPermission({
    required this.name,
    required this.isDangerous,
    this.explanation,
    this.riskScore = 0,
  });

  final String name;
  final bool isDangerous;
  final String? explanation;
  final int riskScore;
}

class ProtectedApp {
  const ProtectedApp({
    required this.packageName,
    required this.name,
    required this.version,
    required this.risk,
    required this.riskScore,
    required this.source,
    required this.installedDate,
    required this.permissions,
    required this.virusTotalDetections,
    this.virusTotalTotalEngines = 0,
    this.virusTotalThreatLabel,
    this.virusTotalNote,
    this.icon,
    this.iconBytes,
    this.apkPath,
    this.installerStore,
    this.lastScanSummary,
    this.vtScanned = false,
    this.lastUpdatedDate,
    this.isTrusted = false,
  });

  final String packageName;
  final String name;
  final String version;
  final IconData? icon;
  final Uint8List? iconBytes;
  final RiskLevel risk;
  final int riskScore;
  final String source;
  final String installedDate;
  final List<AppPermission> permissions;
  final int virusTotalDetections;
  final int virusTotalTotalEngines;
  final String? virusTotalThreatLabel;
  final String? virusTotalNote;
  final String? apkPath;
  final String? installerStore;
  final String? lastScanSummary;
  final bool vtScanned;
  final String? lastUpdatedDate;
  final bool isTrusted;

  bool get hasVirusTotalThreat => virusTotalDetections > 0;

  ProtectedApp copyWith({
    String? packageName,
    String? name,
    String? version,
    IconData? icon,
    Uint8List? iconBytes,
    RiskLevel? risk,
    int? riskScore,
    String? source,
    String? installedDate,
    List<AppPermission>? permissions,
    int? virusTotalDetections,
    int? virusTotalTotalEngines,
    String? virusTotalThreatLabel,
    String? virusTotalNote,
    String? apkPath,
    String? installerStore,
    String? lastScanSummary,
    bool? vtScanned,
    String? lastUpdatedDate,
    bool? isTrusted,
  }) {
    return ProtectedApp(
      packageName: packageName ?? this.packageName,
      name: name ?? this.name,
      version: version ?? this.version,
      icon: icon ?? this.icon,
      iconBytes: iconBytes ?? this.iconBytes,
      risk: risk ?? this.risk,
      riskScore: riskScore ?? this.riskScore,
      source: source ?? this.source,
      installedDate: installedDate ?? this.installedDate,
      permissions: permissions ?? this.permissions,
      virusTotalDetections: virusTotalDetections ?? this.virusTotalDetections,
      virusTotalTotalEngines:
          virusTotalTotalEngines ?? this.virusTotalTotalEngines,
      virusTotalThreatLabel:
          virusTotalThreatLabel ?? this.virusTotalThreatLabel,
      virusTotalNote: virusTotalNote ?? this.virusTotalNote,
      apkPath: apkPath ?? this.apkPath,
      installerStore: installerStore ?? this.installerStore,
      lastScanSummary: lastScanSummary ?? this.lastScanSummary,
      vtScanned: vtScanned ?? this.vtScanned,
      lastUpdatedDate: lastUpdatedDate ?? this.lastUpdatedDate,
      isTrusted: isTrusted ?? this.isTrusted,
    );
  }
}
