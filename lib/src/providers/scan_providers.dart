import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_constants.dart';
import '../services/apk_scan_engine.dart';
import '../services/app_scan_service.dart';
import '../services/file_scan_service.dart';
import '../services/native_package_service.dart';
import '../services/permission_analyzer.dart';
import '../services/virus_total_service.dart';

final nativePackageServiceProvider = Provider<NativePackageService>((ref) {
  return NativePackageService();
});

final permissionAnalyzerProvider = Provider<PermissionAnalyzer>((ref) {
  return PermissionAnalyzer();
});

final virusTotalServiceProvider = Provider<VirusTotalService>((ref) {
  final service = VirusTotalService(apiKey: AppConstants.virusTotalApiKey);
  ref.onDispose(service.dispose);
  return service;
});

final apkScanEngineProvider = Provider<ApkScanEngine>((ref) {
  return ApkScanEngine(
    permissionAnalyzer: ref.watch(permissionAnalyzerProvider),
    virusTotalService: ref.watch(virusTotalServiceProvider),
  );
});

final posbonScanServiceProvider = Provider<PosbonScanService>((ref) {
  final service = PosbonScanService(
    virusTotalService: ref.watch(virusTotalServiceProvider),
    nativePackageService: ref.watch(nativePackageServiceProvider),
    permissionAnalyzer: ref.watch(permissionAnalyzerProvider),
    apkScanEngine: ref.watch(apkScanEngineProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

class ScanResultsNotifier extends StateNotifier<List<ApkScanResult>> {
  ScanResultsNotifier(this._ref) : super(const <ApkScanResult>[]);

  final Ref _ref;
  final StreamController<ScanProgress> _progressController =
      StreamController<ScanProgress>.broadcast();

  Stream<ScanProgress> get progressStream => _progressController.stream;

  Future<void> startScanAllFiles() async {
    await _runProgress(_ref.read(posbonScanServiceProvider).scanAllFiles());
  }

  Future<void> startScanInstalledApps() async {
    final appService = AppScanService(
      virusTotalService: _ref.read(virusTotalServiceProvider),
      nativePackageService: _ref.read(nativePackageServiceProvider),
      apkScanEngine: _ref.read(apkScanEngineProvider),
    );
    await _runProgress(appService.scanInstalledApps());
  }

  Future<ApkScanResult> scanSingleFile(String path) async {
    final result =
        await _ref.read(posbonScanServiceProvider).scanSingleFile(path);
    state = <ApkScanResult>[...state, result];
    return result;
  }

  Future<void> _runProgress(Stream<ScanProgress> stream) async {
    state = const <ApkScanResult>[];
    await for (final progress in stream) {
      state = progress.completedResults;
      _progressController.add(progress);
    }
  }

  @override
  void dispose() {
    _progressController.close();
    super.dispose();
  }
}

final scanResultsProvider =
    StateNotifierProvider<ScanResultsNotifier, List<ApkScanResult>>((ref) {
  return ScanResultsNotifier(ref);
});

final scanProgressProvider = StreamProvider<ScanProgress>((ref) {
  return ref.watch(scanResultsProvider.notifier).progressStream;
});

final scanUpdatesProvider = StreamProvider<ScanProgressUpdate>((ref) {
  return ref.watch(posbonScanServiceProvider).updates;
});

final vtRateLimitProvider = StreamProvider<int>((ref) {
  final service = ref.watch(virusTotalServiceProvider);
  final controller = StreamController<int>.broadcast();

  void listener() {
    controller.add(service.waitSecondsNotifier.value);
  }

  service.waitSecondsNotifier.addListener(listener);
  controller.add(service.waitSecondsNotifier.value);

  ref.onDispose(() {
    service.waitSecondsNotifier.removeListener(listener);
    controller.close();
  });

  return controller.stream;
});
