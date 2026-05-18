import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/app_locale.dart';
import '../models/security_models.dart';
import 'apk_scan_engine.dart';
import 'native_package_service.dart';
import 'permission_analyzer.dart';
import 'permissions_service.dart';
import 'virus_total_service.dart';

class ScanProgress {
  const ScanProgress({
    required this.current,
    required this.total,
    required this.currentFileName,
    required this.percentage,
    required this.completedResults,
    required this.threatsFound,
    this.statusText,
  });

  final int current;
  final int total;
  final String currentFileName;
  final double percentage;
  final List<ApkScanResult> completedResults;
  final int threatsFound;
  final String? statusText;
}

class ScanProgressUpdate {
  const ScanProgressUpdate({
    required this.filePath,
    required this.fileName,
    this.permissionResult,
    this.vtResult,
    this.completedResult,
    required this.isCompleted,
  });

  final String filePath;
  final String fileName;
  final PermissionResult? permissionResult;
  final VirusTotalResult? vtResult;
  final ApkScanResult? completedResult;
  final bool isCompleted;
}

class FileScanProgress {
  const FileScanProgress({
    required this.current,
    required this.total,
    required this.label,
  });

  final int current;
  final int total;
  final String label;
}

class PosbonScanService {
  PosbonScanService({
    required VirusTotalService virusTotalService,
    required NativePackageService nativePackageService,
    PermissionsService? permissionsService,
    PermissionAnalyzer? permissionAnalyzer,
    ApkScanEngine? apkScanEngine,
  }) : _nativePackageService = nativePackageService,
       _permissionsService =
           permissionsService ??
           PermissionsService(nativePackageService: nativePackageService),
       _permissionAnalyzer = permissionAnalyzer ?? PermissionAnalyzer(),
       _apkScanEngine =
           apkScanEngine ??
           ApkScanEngine(
             permissionAnalyzer: permissionAnalyzer ?? PermissionAnalyzer(),
             virusTotalService: virusTotalService,
           );

  final NativePackageService _nativePackageService;
  final PermissionsService _permissionsService;
  final PermissionAnalyzer _permissionAnalyzer;
  final ApkScanEngine _apkScanEngine;
  final StreamController<ScanProgressUpdate> _updatesController =
      StreamController<ScanProgressUpdate>.broadcast();
  bool _cancelRequested = false;

  Stream<ScanProgressUpdate> get updates => _updatesController.stream;

  void cancelCurrentScan() {
    _cancelRequested = true;
    _apkScanEngine.cancelFileScanIo();
  }

  static const Set<String> _scanExtensions = {
    '.apk',
    '.xapk',
    '.zip',
    '.dex',
    '.jar',
  };

  Future<List<File>> collectDownloadFiles() async {
    final matchedFiles = <File>[];
    final seenPaths = <String>{};

    // Bosqich 1: Downloads papkasini skanerlash.
    // Native path Android'dan olinadi — hardcoded pathlar fallback sifatida.
    final nativePath = await _nativePackageService
        .getDeviceInfo()
        .then((info) => info.downloadsPath)
        .catchError((_) => null as String?);

    final downloadPaths = <String>{
      if (nativePath != null && nativePath.isNotEmpty) nativePath,
      '/storage/emulated/0/Download',
      '/storage/emulated/0/Downloads',
      '/sdcard/Download',
      '/sdcard/Downloads',
    };

    for (final path in downloadPaths) {
      final dir = Directory(path);
      bool exists = false;
      try {
        exists = await dir.exists();
      } on FileSystemException catch (e) {
        debugPrint('[FileScan] exists() xatolik: $path | $e');
        continue;
      }
      if (!exists) continue;
      try {
        await for (final entity in dir.list(followLinks: false)) {
          if (entity is! File) continue;
          if (!_scanExtensions.contains(_extensionOf(entity.path))) continue;
          if (!seenPaths.add(entity.path)) continue;
          matchedFiles.add(entity);
        }
      } on FileSystemException catch (e) {
        debugPrint('[FileScan] list() xatolik: $path | $e');
        continue;
      }
    }

    debugPrint(
      '[FileScan] Bosqich 1 yakunlandi: ${matchedFiles.length} ta fayl topildi',
    );

    // Bosqich 2: MANAGE_EXTERNAL_STORAGE berilgan bo'lsa butun telefonni skanerlash.
    // recursive: true ishlatilmaydi — /Android/data kabi cheklangan papkalar
    // stream-level exception beradi va butun iterationni to'xtatadi.
    // O'rniga: har bir papka uchun alohida try/catch bilan manual recursion.
    final hasFullAccess = await Permission.manageExternalStorage.isGranted;
    debugPrint('[FileScan] MANAGE_EXTERNAL_STORAGE: $hasFullAccess');
    if (hasFullAccess) {
      final root = Directory('/storage/emulated/0/');
      if (await root.exists()) {
        await _collectRecursive(
          dir: root,
          seenPaths: seenPaths,
          matchedFiles: matchedFiles,
        );
      }
    }

    debugPrint('[FileScan] Jami topildi: ${matchedFiles.length} ta fayl');

    matchedFiles.sort(
      (a, b) => _safeLastModified(b).compareTo(_safeLastModified(a)),
    );
    return matchedFiles;
  }

  // Har bir papka uchun alohida exception handling bilan recursive scan.
  // recursive: true ishlatilmaydi chunki cheklangan papka (masalan /Android/data)
  // stream-level exception berib, butun iterationni to'xtatadi.
  Future<void> _collectRecursive({
    required Directory dir,
    required Set<String> seenPaths,
    required List<File> matchedFiles,
  }) async {
    List<FileSystemEntity> entries;
    try {
      entries = await dir.list(followLinks: false).toList();
    } on FileSystemException {
      return;
    }

    for (final entity in entries) {
      final p = entity.path;
      if (entity is File) {
        if (!_scanExtensions.contains(_extensionOf(p))) continue;
        if (!seenPaths.add(p)) continue;
        matchedFiles.add(entity);
      } else if (entity is Directory) {
        // /Android/data va /Android/obb — cheklangan, o'tkazib yuboriladi.
        if (p.endsWith('/Android/data') ||
            p.endsWith('/Android/obb') ||
            p.contains('/Android/data/') ||
            p.contains('/Android/obb/')) {
          continue;
        }
        await _collectRecursive(
          dir: entity,
          seenPaths: seenPaths,
          matchedFiles: matchedFiles,
        );
      }
    }
  }

  Future<List<File>> pickFiles() async {
    final result = await FilePicker.pickFiles(
      allowMultiple: true,
      withData: false,
      lockParentWindow: true,
    );

    if (result == null) return [];
    return result.files
        .map((file) => file.path)
        .whereType<String>()
        .map(File.new)
        .where((file) => _scanExtensions.contains(_extensionOf(file.path)))
        .where((file) => file.existsSync())
        .toList();
  }

  Stream<ScanProgress> scanAllFiles() async* {
    await _permissionsService.request(
      PermissionCardId.fileManager,
      AppStrings.of(AppLocale.uz),
    );
    final status = await Permission.manageExternalStorage.status;
    final legacyStatus = await Permission.storage.status;
    if (!status.isGranted && !legacyStatus.isGranted) {
      throw Exception('MANAGE_EXTERNAL_STORAGE ruxsati berilmagan');
    }

    final root = Directory('/storage/emulated/0/');
    if (!await root.exists()) {
      throw Exception('/storage/emulated/0/ katalogi topilmadi');
    }

    final seenPaths = <String>{};
    final rawFiles = <File>[];
    await _collectRecursive(
      dir: root,
      seenPaths: seenPaths,
      matchedFiles: rawFiles,
    );

    yield* _scanFiles(rawFiles);
  }

  Future<ApkScanResult> scanSingleFile(String path) async {
    final extension = _extensionOf(path);
    if (extension == '.apk') {
      return _apkScanEngine.scanApk(filePath: path);
    }
    return _apkScanEngine.scanNonApkFile(path);
  }

  /// Fast local-only scan: parses just the AndroidManifest.xml inside the APK
  /// (no full APK read, no SHA256, no VirusTotal). Suitable for live monitoring
  /// and the new-APK alert flow where latency matters.
  Future<ApkScanResult> scanSingleFileLocally(String path) async {
    final extension = _extensionOf(path);
    debugPrint('[PosbonWatcher] Tezkor skan boshlandi | yo\'l: $path');
    if (extension != '.apk') {
      return _apkScanEngine.scanNonApkFile(path);
    }
    return _apkScanEngine.scanApkLocally(filePath: path);
  }

  Future<ApkScanResult> scanSingleFileDeep(String path) async {
    final extension = _extensionOf(path);
    debugPrint('[PosbonWatcher] Chuqur skan boshlandi | yo\'l: $path');
    if (extension != '.apk') {
      return _apkScanEngine.scanNonApkFile(path);
    }
    return _apkScanEngine.scanApk(filePath: path);
  }

  Future<List<ScanFinding>> scanFiles(
    List<File> files, {
    required void Function(FileScanProgress progress) onProgress,
  }) async {
    final results = <ApkScanResult>[];
    await for (final progress in _scanFiles(files)) {
      onProgress(
        FileScanProgress(
          current: progress.current,
          total: progress.total,
          label: progress.statusText ?? progress.currentFileName,
        ),
      );
      if (progress.completedResults.length > results.length) {
        results
          ..clear()
          ..addAll(progress.completedResults);
      }
    }

    return results.map(_findingFromResult).toList();
  }

  Stream<ScanProgress> _scanFiles(List<File> files) async* {
    final safeFiles = files.where((file) => file.existsSync()).toList();
    final results = <ApkScanResult>[];
    var threats = 0;

    _cancelRequested = false;
    for (var index = 0; index < safeFiles.length; index++) {
      if (_cancelRequested) break;
      final file = safeFiles[index];
      final fileName = file.uri.pathSegments.last;
      final extension = _extensionOf(file.path);

      if (extension == '.apk') {
        PermissionResult permissionResult;
        try {
          permissionResult = await _permissionAnalyzer.analyze(file.path);
        } catch (_) {
          permissionResult = const PermissionResult(
            allPermissions: [],
            dangerousPermissions: [],
            detectedCombos: [],
            permissionScore: 0,
          );
        }
        _updatesController.add(
          ScanProgressUpdate(
            filePath: file.path,
            fileName: fileName,
            permissionResult: permissionResult,
            isCompleted: false,
          ),
        );

        final completed = await _apkScanEngine.scanApk(filePath: file.path);
        if (completed.riskLevel.isRisky) {
          threats++;
        }
        results.add(completed);
        _updatesController.add(
          ScanProgressUpdate(
            filePath: file.path,
            fileName: fileName,
            permissionResult: permissionResult,
            vtResult: completed.vtResult,
            completedResult: completed,
            isCompleted: true,
          ),
        );
      } else {
        final result = await scanSingleFile(file.path);
        if (result.riskLevel.isRisky) {
          threats++;
        }
        results.add(result);
        _updatesController.add(
          ScanProgressUpdate(
            filePath: file.path,
            fileName: fileName,
            vtResult: result.vtResult,
            completedResult: result,
            isCompleted: true,
          ),
        );
      }

      yield ScanProgress(
        current: index + 1,
        total: safeFiles.length,
        currentFileName: fileName,
        percentage: safeFiles.isEmpty ? 0 : (index + 1) / safeFiles.length,
        completedResults: List<ApkScanResult>.unmodifiable(results),
        threatsFound: threats,
        statusText:
            'Tekshirilmoqda: $fileName\n${file.parent.path.replaceAll("\\\\", "/")}',
      );
    }
  }

  ScanFinding findingFromResult(ApkScanResult result) =>
      _findingFromResult(result);

  ScanFinding _findingFromResult(ApkScanResult result) {
    return ScanFinding(
      name: result.fileName,
      type: ScanTargetType.file,
      risk: result.riskLevel,
      details: result.riskSummary,
      reasons: _findingReasons(result),
      location: result.filePath,
    );
  }

  List<String> _findingReasons(ApkScanResult result) {
    final reasons = <String>[];

    reasons.addAll(
      result.permissionResult.dangerousPermissions.map(
        (permission) => permission.reason,
      ),
    );
    reasons.addAll(result.permissionResult.detectedCombos);

    if (result.vtResult.detectedCount > 0) {
      final threatLabel = result.vtResult.detectedAs;
      reasons.add(
        threatLabel != null && threatLabel.isNotEmpty
            ? 'VirusTotal bazasida "$threatLabel" sifatida aniqlandi'
            : 'VirusTotal ${result.vtResult.detectedCount} ta engine orqali xavfli deb topdi',
      );
    } else if (result.vtResult.note != null &&
        result.vtResult.note!.isNotEmpty) {
      reasons.add(result.vtResult.note!);
    }

    if (reasons.isEmpty) {
      reasons.add(
        'Shubhali belgi topilmadi. Fayl hozircha xavfsiz ko\'rinmoqda.',
      );
    }

    return reasons.toSet().toList();
  }

  String _extensionOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot == -1) return '';
    return path.substring(dot).toLowerCase();
  }

  DateTime _safeLastModified(File file) {
    try {
      return file.lastModifiedSync();
    } on FileSystemException {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  void dispose() {
    _updatesController.close();
  }
}

class FileScanService extends PosbonScanService {
  FileScanService({
    required super.virusTotalService,
    required super.nativePackageService,
    super.permissionsService,
    super.permissionAnalyzer,
    super.apkScanEngine,
  });
}
