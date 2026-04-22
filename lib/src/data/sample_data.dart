import 'package:flutter/material.dart';

import '../models/security_models.dart';

const onboardingItems = [
  OnboardingItem(
    icon: Icons.shield_outlined,
    title: 'Xavfsizlik skaneri',
    description:
        'Qurilmangizdagi fayl va ilovalarni bir joyda nazorat qilib, tahdidlarni tez aniqlang.',
  ),
  OnboardingItem(
    icon: Icons.apps_rounded,
    title: 'Ilovalarni tekshirish',
    description:
        'O\'rnatilgan dasturlarni permission, manba va risk darajasi bo\'yicha kuzating.',
  ),
  OnboardingItem(
    icon: Icons.insert_drive_file_outlined,
    title: 'Fayllarni himoya qilish',
    description:
        'Shubhali fayllarni ajrating va xavfsizlik holatini vizual ko\'rinishda baholang.',
  ),
];

const samplePermissions = [
  PermissionStatusCard(
    id: PermissionCardId.notifications,
    icon: Icons.notifications_none_rounded,
    title: 'Bildirishnomalar',
    description: 'Muhim xavfsizlik ogohlantirishlarini ko\'rsatadi.',
    granted: true,
  ),
  PermissionStatusCard(
    id: PermissionCardId.fileManager,
    icon: Icons.folder_open_rounded,
    title: 'Fayl Manager',
    description: 'Qurilmadagi fayllarni tekshirishga kirish beradi.',
    granted: false,
  ),
  PermissionStatusCard(
    id: PermissionCardId.mediaFiles,
    icon: Icons.photo_library_outlined,
    title: 'Media fayllar',
    description: 'Rasm va video fayllarni kuzatish imkonini beradi.',
    granted: true,
  ),
  PermissionStatusCard(
    id: PermissionCardId.monitoring,
    icon: Icons.settings_outlined,
    title: 'Monitoringlash',
    description: 'Orqa fonda doimiy xavfsizlik nazoratini yoqadi.',
    granted: false,
  ),
  PermissionStatusCard(
    id: PermissionCardId.appScanning,
    icon: Icons.security_rounded,
    title: 'Dasturlarni tekshirish',
    description:
        'O\'rnatilgan ilovalar haqida xavfsizlik ma\'lumotlarini oladi.',
    granted: false,
  ),
  PermissionStatusCard(
    id: PermissionCardId.safeInstall,
    icon: Icons.download_done_rounded,
    title: 'Dasturlarni xavfsiz o\'rnatish',
    description: 'Yangi APK fayllarni o\'rnatishdan oldin tekshiradi.',
    granted: false,
  ),
];

final sampleScanTargets = List.generate(
  340,
  (index) => ScanTarget(
    name: index.isEven
        ? 'storage/emulated/0/Download/file_$index.apk'
        : 'com.posbon.sample.app$index',
    type: index.isEven ? ScanTargetType.file : ScanTargetType.app,
  ),
);

const sampleFindings = [
  ScanFinding(
    name: 'Telegram_mod.apk',
    type: ScanTargetType.file,
    risk: RiskLevel.dangerous,
    details: '12/70 engine tomonidan zararli deb topildi',
  ),
  ScanFinding(
    name: 'QuickCleaner Pro',
    type: ScanTargetType.app,
    risk: RiskLevel.dangerous,
    details: 'Noma\'lum manba va ortiqcha permission aniqlandi',
  ),
  ScanFinding(
    name: 'Screen Recorder Plus',
    type: ScanTargetType.app,
    risk: RiskLevel.suspicious,
    details: 'Accessibility va SMS permission talab qilmoqda',
  ),
  ScanFinding(
    name: 'family_photo_2026.zip',
    type: ScanTargetType.file,
    risk: RiskLevel.suspicious,
    details: 'Arxiv ichida imzosiz APK mavjud',
  ),
  ScanFinding(
    name: 'Banking App',
    type: ScanTargetType.app,
    risk: RiskLevel.safe,
    details: 'Play Store orqali o\'rnatilgan va toza',
  ),
];

const sampleApps = [
  ProtectedApp(
    packageName: 'com.quickcleaner.pro',
    name: 'QuickCleaner Pro',
    version: 'v3.1.2',
    icon: Icons.cleaning_services_rounded,
    risk: RiskLevel.dangerous,
    riskScore: 82,
    source: 'APK fayl',
    installedDate: '10-aprel 2026',
    virusTotalDetections: 3,
    permissions: [
      AppPermission(name: 'READ_SMS', isDangerous: true),
      AppPermission(name: 'SYSTEM_ALERT_WINDOW', isDangerous: true),
      AppPermission(name: 'INTERNET', isDangerous: false),
    ],
  ),
  ProtectedApp(
    packageName: 'com.screen.recorder.plus',
    name: 'Screen Recorder Plus',
    version: 'v5.0.1',
    icon: Icons.video_call_rounded,
    risk: RiskLevel.suspicious,
    riskScore: 47,
    source: 'Play Store',
    installedDate: '04-aprel 2026',
    virusTotalDetections: 1,
    permissions: [
      AppPermission(name: 'RECORD_AUDIO', isDangerous: false),
      AppPermission(name: 'READ_CONTACTS', isDangerous: true),
      AppPermission(name: 'ACCESSIBILITY_SERVICE', isDangerous: true),
    ],
  ),
  ProtectedApp(
    packageName: 'com.banking.app',
    name: 'Banking App',
    version: 'v12.4.0',
    icon: Icons.account_balance_wallet_rounded,
    risk: RiskLevel.safe,
    riskScore: 11,
    source: 'Play Store',
    installedDate: '02-aprel 2026',
    virusTotalDetections: 0,
    permissions: [
      AppPermission(name: 'USE_BIOMETRIC', isDangerous: false),
      AppPermission(name: 'INTERNET', isDangerous: false),
    ],
  ),
];
