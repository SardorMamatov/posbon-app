import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_device_apps/flutter_device_apps.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/app_constants.dart';
import 'core/app_locale.dart';
import 'core/app_theme.dart';
import 'core/settings_controller.dart';
import 'data/sample_data.dart';
import 'models/posbon_safe_models.dart';
import 'models/security_models.dart';
import 'screens/agreement_screen.dart';
import 'screens/settings_screen.dart';
import 'services/app_scan_service.dart';
import 'services/file_scan_service.dart';
import 'services/native_package_service.dart';
import 'services/posbon_safe_service.dart';
import 'services/permissions_service.dart';
import 'services/virus_total_service.dart' as vt;
import 'widgets/animated_background.dart';

final GlobalKey<ScaffoldMessengerState> _rootMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

const String kPosbonAppVersion = '0.1.0';

class PosbonApp extends StatefulWidget {
  const PosbonApp({super.key});

  @override
  State<PosbonApp> createState() => _PosbonAppState();
}

class _PosbonAppState extends State<PosbonApp> {
  final SettingsController _settings = SettingsController();
  late final LocaleController _localeController = LocaleController();

  @override
  void initState() {
    super.initState();
    _settings.addListener(_syncLocale);
    _settings.load();
  }

  void _syncLocale() {
    _localeController.set(_settings.locale);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _settings.removeListener(_syncLocale);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LocaleScope(
      notifier: _localeController,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'POSBON',
        theme: buildPosbonTheme(),
        scaffoldMessengerKey: _rootMessengerKey,
        builder: (context, child) {
          return LocaleScope(
            notifier: _localeController,
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: PosbonRoot(settings: _settings),
      ),
    );
  }
}

enum AppStage {
  splash,
  agreement,
  onboarding,
  permissions,
  dashboard,
  files,
  scanning,
  results,
  apps,
  appDetail,
  safe,
  settings,
}

enum DashboardTab { home, files, apps, safe, history, settings }

class PosbonRoot extends StatefulWidget {
  const PosbonRoot({required this.settings, super.key});

  final SettingsController settings;

  @override
  State<PosbonRoot> createState() => _PosbonRootState();
}

class _PosbonRootState extends State<PosbonRoot> with WidgetsBindingObserver {
  late final vt.VirusTotalService _virusTotalService;
  late final NativePackageService _nativePackageService;
  late final AppScanService _appScanService;
  late final FileScanService _fileScanService;
  late final PermissionsService _permissionsService;
  late final PosbonSafeService _posbonSafeService;

  AppStage _stage = AppStage.splash;
  DashboardTab _tab = DashboardTab.home;
  int _onboardingIndex = 0;
  int _scannedCount = 0;
  int _scanTotalCount = 0;
  String _currentTargetName = '...';
  bool _appsLoading = false;
  bool _filesLoading = false;
  bool _detailLoading = false;
  bool _safeLoading = false;
  bool _safeUnlocked = false;
  bool _safeHasPin = false;
  bool _safeDeviceAuthAvailable = false;
  List<PermissionStatusCard> _permissions = [];
  List<ScanFinding> _history = [];
  List<ProtectedApp> _apps = [];
  List<File> _downloadFiles = [];
  List<SafeCredential> _safeItems = [];
  ProtectedApp? _selectedApp;
  RiskFilter _resultsFilter = RiskFilter.all;
  final PageStorageBucket _pageStorageBucket = PageStorageBucket();
  StreamSubscription<String>? _incomingFileSubscription;
  StreamSubscription<String>? _incomingDestinationSubscription;
  String? _pendingIncomingFilePath;
  final Set<String> _knownDownloadPaths = <String>{};
  DateTime? _scanStartedAt;
  bool _scanWentToBackground = false;
  bool _scanInProgress = false;
  bool _scanBackgroundMode = false;
  bool _pendingResultsNavigation = false;
  Timer? _downloadWatcherTimer;

  SettingsController get _settings => widget.settings;
  AppStrings get _tr => AppStrings.of(_settings.locale);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _nativePackageService = NativePackageService();
    _virusTotalService = vt.VirusTotalService(
      apiKey: AppConstants.virusTotalApiKey,
    );
    _appScanService = AppScanService(
      virusTotalService: _virusTotalService,
      nativePackageService: _nativePackageService,
    );
    _fileScanService = FileScanService(
      virusTotalService: _virusTotalService,
      nativePackageService: _nativePackageService,
    );
    _permissionsService = PermissionsService(
      nativePackageService: _nativePackageService,
    );
    _posbonSafeService = PosbonSafeService();
    _incomingFileSubscription = _nativePackageService.incomingFiles.listen(
      _handleIncomingFile,
    );
    _incomingDestinationSubscription = _nativePackageService
        .incomingDestinations
        .listen(_handleIncomingDestination);
    _settings.addListener(_onSettingsChanged);
    // Defer heavy bootstrap to post-first-frame so the UI appears instantly.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bootstrap();
    });
  }

  AppLocale _lastLocale = AppLocale.uz;

  void _onSettingsChanged() {
    if (!mounted) return;
    if (_settings.liveMonitoring) {
      if (_downloadWatcherTimer == null || !_downloadWatcherTimer!.isActive) {
        _startDownloadWatcher();
      }
    } else {
      _downloadWatcherTimer?.cancel();
      _downloadWatcherTimer = null;
    }
    if (_settings.locale != _lastLocale) {
      _lastLocale = _settings.locale;
      unawaited(_reloadPermissionsForLocale());
    }
    setState(() {});
  }

  Future<void> _reloadPermissionsForLocale() async {
    final refreshed = await _permissionsService.loadStatuses(_tr);
    if (!mounted) return;
    setState(() => _permissions = refreshed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _incomingFileSubscription?.cancel();
    _incomingDestinationSubscription?.cancel();
    _downloadWatcherTimer?.cancel();
    _settings.removeListener(_onSettingsChanged);
    unawaited(_nativePackageService.dispose());
    _virusTotalService.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    // Phase 1: load settings & permissions (fast, blocking for routing).
    await _settings.load();
    _permissions = await _permissionsService.loadStatuses(_tr);
    if (!mounted) return;

    // Route based on agreement and permissions. Heavy work continues after.
    final AppStage next;
    if (!_settings.agreementAccepted) {
      next = AppStage.agreement;
    } else if (!_hasAllRequiredPermissions) {
      next = AppStage.permissions;
    } else {
      next = AppStage.dashboard;
    }

    setState(() {
      _stage = next;
    });

    // Phase 2: heavy data loading in background.
    unawaited(() async {
      await _loadSafeState();
      await _loadFiles(force: true, silent: true, seedKnownPaths: true);
      if (_settings.liveMonitoring) {
        _startDownloadWatcher();
      }
      await _restorePendingOpenFile();
    }());
  }

  void _acceptAgreement() {
    unawaited(_settings.acceptAgreement());
    setState(() {
      _stage = _hasAllRequiredPermissions
          ? AppStage.dashboard
          : AppStage.permissions;
    });
  }

  Future<void> _restorePendingOpenFile() async {
    final destination = await _nativePackageService.consumePendingDestination();
    if (destination == 'results') {
      _openResultsIfAvailable();
    } else if (destination == 'files') {
      unawaited(_openTab(DashboardTab.files));
    }

    final path = await _nativePackageService.consumePendingOpenFile();
    if (path == null || path.isEmpty) return;
    _handleIncomingFile(path);
  }

  void _handleIncomingFile(String path) {
    unawaited(_nativePackageService.consumePendingOpenFile());
    _pendingIncomingFilePath = path;
    if (!_hasAllRequiredPermissions) {
      if (mounted) {
        setState(() => _stage = AppStage.permissions);
      }
      _showMessage(_tr.t('scan.external_queued'));
      return;
    }

    unawaited(_scanIncomingFile(path));
  }

  void _handleIncomingDestination(String destination) {
    if (destination == 'results') {
      _openResultsIfAvailable();
    } else if (destination == 'files') {
      unawaited(_openTab(DashboardTab.files));
    }
  }

  void _startScanSession() {
    _scanStartedAt = DateTime.now();
    _scanWentToBackground = false;
    _scanInProgress = true;
    _scanBackgroundMode = false;
    _pendingResultsNavigation = false;
  }

  Future<void> _notifyIfNeeded(List<ScanFinding> findings) async {
    final startedAt = _scanStartedAt;
    _scanStartedAt = null;
    _scanInProgress = false;
    final shouldNotify = _scanBackgroundMode || _scanWentToBackground;
    _scanBackgroundMode = false;

    if (startedAt == null) return;
    final tookLong =
        DateTime.now().difference(startedAt) >= const Duration(seconds: 10);
    if (!shouldNotify && !tookLong) return;

    final dangerousCount =
        findings.where((item) => item.risk.isDangerous).length;
    final suspiciousCount =
        findings.where((item) => item.risk.isSuspicious).length;
    final tr = mounted ? context.tr : AppStrings.of(_settings.locale);
    final body = dangerousCount > 0
        ? '$dangerousCount ${tr.t('status.dangerous').toLowerCase()}.'
        : suspiciousCount > 0
            ? '$suspiciousCount ${tr.t('status.suspicious').toLowerCase()}.'
            : tr.t('results.empty_desc');
    await _nativePackageService.showNotification(
      title: tr.t('scan.notification_title'),
      body: body,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_stage == AppStage.scanning && state != AppLifecycleState.resumed) {
      _scanWentToBackground = true;
    }

    if (state == AppLifecycleState.resumed) {
      if (_pendingResultsNavigation && !_scanInProgress) {
        _openResultsIfAvailable();
      }
      if (_stage == AppStage.apps || _stage == AppStage.appDetail) {
        unawaited(_loadApps(force: true));
      }
      unawaited(_loadFiles(force: true, silent: true, seedKnownPaths: true));
      unawaited(_restorePendingOpenFile());
    }
  }

  void _continueScanInBackground() {
    if (!_scanInProgress) return;
    setState(() {
      _scanBackgroundMode = true;
      _scanWentToBackground = true;
      _tab = DashboardTab.home;
      _stage = AppStage.dashboard;
    });
    final tr = context.tr;
    _showMessage(tr.t('scan.background_on'));
    // Fire-and-forget: tell the OS a scan is running so the user gets a head-up.
    if (_hasNotificationPermission) {
      unawaited(
        _nativePackageService.showNotification(
          title: tr.t('scan.bg_start_title'),
          body: tr.t('scan.bg_start_body'),
        ),
      );
    }
  }

  void _openResultsIfAvailable() {
    if (_history.isEmpty) return;
    if (!mounted) return;
    setState(() {
      _pendingResultsNavigation = false;
      _tab = DashboardTab.history;
      _stage = AppStage.results;
    });
  }

  bool get _hasAllRequiredPermissions =>
      _permissions.every((item) => !item.actionable || item.granted);

  bool get _hasFileManagerPermission =>
      _isPermissionGranted(PermissionCardId.fileManager);

  bool get _hasNotificationPermission =>
      _isPermissionGranted(PermissionCardId.notifications);

  bool _isPermissionGranted(PermissionCardId id) {
    for (final item in _permissions) {
      if (item.id == id) {
        return item.granted;
      }
    }
    return false;
  }

  void _setOnboardingPage(int index) {
    setState(() => _onboardingIndex = index);
  }

  void _completeOnboarding() {
    setState(() => _stage = AppStage.permissions);
  }

  Future<void> _togglePermission(PermissionCardId id) async {
    final feedback = await _permissionsService.request(id, _tr);
    final permissions = await _permissionsService.loadStatuses(_tr);
    if (!mounted) return;
    setState(() => _permissions = permissions);
    _showMessage(
      feedback.message,
      isError: !feedback.changed && id != PermissionCardId.appScanning,
    );
  }

  void _continueFromPermissions() {
    if (!_hasAllRequiredPermissions) {
      _showMessage(
        context.tr.t('permissions.body'),
        isError: true,
      );
      return;
    }
    final pendingPath = _pendingIncomingFilePath;
    setState(() => _stage = AppStage.dashboard);
    if (_settings.liveMonitoring) {
      _startDownloadWatcher();
    }
    unawaited(_loadFiles(force: true, silent: true, seedKnownPaths: true));
    if (pendingPath != null && pendingPath.isNotEmpty) {
      unawaited(_scanIncomingFile(pendingPath));
    }
  }

  Future<void> _openTab(DashboardTab tab) async {
    // Immediate UI switch; fetch data after so navigation is snappy.
    if (!mounted) return;
    setState(() {
      _tab = tab;
      if (tab == DashboardTab.files) {
        _stage = AppStage.files;
      } else if (tab == DashboardTab.apps) {
        _stage = AppStage.apps;
      } else if (tab == DashboardTab.history) {
        _stage = AppStage.results;
        _resultsFilter = RiskFilter.all;
      } else if (tab == DashboardTab.settings) {
        _stage = AppStage.settings;
      } else {
        _stage = AppStage.dashboard;
      }
    });

    if (tab == DashboardTab.files) {
      unawaited(_loadFiles(force: _downloadFiles.isEmpty));
    } else if (tab == DashboardTab.apps) {
      unawaited(_loadApps());
    }
  }

  void _openResultsFiltered(RiskFilter filter) {
    if (!mounted) return;
    setState(() {
      _tab = DashboardTab.history;
      _stage = AppStage.results;
      _resultsFilter = filter;
    });
  }

  Future<void> _openSafeScreen() async {
    await _loadSafeState();
    if (!mounted) return;

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => PosbonSafeScreen(
          isLoading: _safeLoading,
          unlocked: _safeUnlocked,
          hasPin: _safeHasPin,
          deviceAuthAvailable: _safeDeviceAuthAvailable,
          items: _safeItems,
          onUnlockWithDevice: _unlockSafeWithDeviceAuth,
          onUnlockWithPin: _unlockSafeWithPin,
          onSetPin: _setupSafePin,
          onLock: _lockSafe,
          onAddItem: _addSafeItem,
          onDeleteItem: _deleteSafeItem,
          onCopyValue: _copyValue,
          onShowAbout: _showAboutPosbon,
        ),
      ),
    );

    if (!mounted) return;
    await _loadSafeState();
  }

  Future<void> _loadFiles({
    bool force = false,
    bool silent = false,
    bool seedKnownPaths = false,
  }) async {
    if (_filesLoading || (_downloadFiles.isNotEmpty && !force)) return;
    if (mounted) {
      setState(() => _filesLoading = true);
    }
    try {
      final files = await _fileScanService.collectDownloadFiles();
      if (!mounted) return;
      setState(() => _downloadFiles = files);
      if (seedKnownPaths) {
        _knownDownloadPaths
          ..clear()
          ..addAll(files.map((file) => file.path));
      }
    } catch (error) {
      if (!silent) {
        _showMessage(
          formatTemplate(_tr.t('scan.error_downloads'), {'e': error}),
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _filesLoading = false);
      }
    }
  }

  void _startDownloadWatcher() {
    _downloadWatcherTimer?.cancel();
    unawaited(_checkDownloadsForThreats());
    _downloadWatcherTimer = Timer.periodic(
      const Duration(seconds: 45),
      (_) => unawaited(_checkDownloadsForThreats()),
    );
  }

  Future<void> _checkDownloadsForThreats() async {
    if (!_settings.liveMonitoring) return;
    if (!_hasFileManagerPermission || _scanInProgress || _filesLoading) {
      return;
    }

    try {
      final files = await _fileScanService.collectDownloadFiles();
      if (mounted) {
        setState(() => _downloadFiles = files);
      }

      final newFiles = files
          .where((file) => !_knownDownloadPaths.contains(file.path))
          .toList();

      _knownDownloadPaths
        ..clear()
        ..addAll(files.map((file) => file.path));

      for (final file in newFiles) {
        final result = await _fileScanService.scanSingleFile(file.path);
        if (!result.riskLevel.isRisky) {
          continue;
        }

        final finding = _fileScanService.findingFromResult(result);
        _rememberFinding(finding);
        if (_hasNotificationPermission) {
          await _nativePackageService.showNotification(
            title: result.riskLevel.isDangerous
                ? _tr.t('scan.found_dangerous')
                : _tr.t('scan.found_suspicious'),
            body: '${finding.name} Download.',
          );
        }
      }
    } catch (_) {}
  }

  Future<void> _loadApps({bool force = false}) async {
    if (_appsLoading || (_apps.isNotEmpty && !force)) return;
    setState(() => _appsLoading = true);
    try {
      final apps = await _appScanService.loadInstalledApps();
      if (!mounted) return;
      setState(() => _apps = apps);
    } catch (error) {
      _showMessage(
        formatTemplate(_tr.t('scan.error_downloads'), {'e': error}),
      );
    } finally {
      if (mounted) {
        setState(() => _appsLoading = false);
      }
    }
  }

  Future<void> _startScan() async {
    if (_scanInProgress) {
      _showMessage(_tr.t('files.prev_in_progress'));
      return;
    }
    await _loadApps();
    if (_apps.isEmpty) {
      _showMessage(_tr.t('scan.no_apps'));
      return;
    }

    final targets = List<ProtectedApp>.from(_apps);
    _startScanSession();
    setState(() {
      _stage = AppStage.scanning;
      _scannedCount = 0;
      _scanTotalCount = targets.length;
      _currentTargetName = targets.first.name;
    });

    try {
      final findings = <ScanFinding>[];
      for (var index = 0; index < targets.length; index++) {
        final scanned = await _appScanService.scanInstalledApp(
          targets[index],
          allowVirusTotalLookup: false,
        );
        _replaceApp(scanned);
        findings.add(_findingFromApp(scanned));
        if (!mounted) return;
        setState(() {
          _scannedCount = index + 1;
          _currentTargetName = scanned.name;
        });
      }

      if (!mounted) return;
      setState(() {
        _history = findings;
        if (_scanBackgroundMode) {
          _pendingResultsNavigation = true;
        } else {
          _tab = DashboardTab.history;
          _stage = AppStage.results;
        }
      });
      await _notifyIfNeeded(findings);
    } catch (error) {
      _scanStartedAt = null;
      _scanInProgress = false;
      _scanBackgroundMode = false;
      _showMessage(
        formatTemplate(_tr.t('scan.error_downloads'), {'e': error}),
        isError: true,
      );
      if (mounted) {
        setState(() {
          _tab = DashboardTab.home;
          _stage = AppStage.dashboard;
        });
      }
    }
  }

  void _cancelScan() {
    _scanStartedAt = null;
    _scanInProgress = false;
    _scanBackgroundMode = false;
    setState(() {
      _tab = DashboardTab.home;
      _stage = AppStage.dashboard;
    });
  }

  Future<void> _pickAndScanFiles() async {
    if (_scanInProgress) {
      _showMessage(_tr.t('files.prev_in_progress'));
      return;
    }
    final files = await _fileScanService.pickFiles();
    if (files.isEmpty) {
      _showMessage(_tr.t('files.empty_download'), isError: true);
      return;
    }

    await _scanFiles(files);
  }

  Future<void> _scanAllDownloadFiles() async {
    if (_scanInProgress) {
      _showMessage(_tr.t('files.prev_in_progress'));
      return;
    }
    var files = _downloadFiles;
    if (files.isEmpty) {
      await _loadFiles(force: true);
      files = _downloadFiles;
    }
    if (files.isEmpty) {
      _showMessage(_tr.t('files.empty_download'), isError: true);
      return;
    }

    await _scanFiles(files);
  }

  Future<void> _scanFiles(List<File> files) async {
    _startScanSession();
    setState(() {
      _stage = AppStage.scanning;
      _scannedCount = 0;
      _scanTotalCount = files.length;
      _currentTargetName = files.first.path.split('\\').last;
    });

    try {
      final findings = await _fileScanService.scanFiles(
        files,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _scannedCount = progress.current;
            _scanTotalCount = progress.total;
            _currentTargetName = progress.label;
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _history = findings;
        if (_scanBackgroundMode) {
          _pendingResultsNavigation = true;
        } else {
          _tab = DashboardTab.history;
          _stage = AppStage.results;
        }
      });
      await _notifyIfNeeded(findings);
      await _loadFiles(force: true, silent: true, seedKnownPaths: true);
    } catch (error) {
      _scanStartedAt = null;
      _scanInProgress = false;
      _scanBackgroundMode = false;
      _showMessage(
        formatTemplate(_tr.t('scan.error_downloads'), {'e': error}),
        isError: true,
      );
      if (mounted) {
        setState(() => _stage = AppStage.dashboard);
      }
    }
  }

  Future<void> _scanSingleDownloadFile(File file) async {
    await _scanIncomingFile(file.path);
  }

  void _rememberFinding(ScanFinding finding) {
    final updated = List<ScanFinding>.from(_history);
    final index = updated.indexWhere(
      (item) => item.location == finding.location && item.name == finding.name,
    );
    if (index == -1) {
      updated.insert(0, finding);
    } else {
      updated[index] = finding;
    }

    if (!mounted) {
      _history = updated;
      return;
    }

    setState(() => _history = updated);
  }

  void _openAppDetail(ProtectedApp app) {
    setState(() {
      _selectedApp = app;
      _stage = AppStage.appDetail;
    });
    unawaited(_loadSelectedAppDetails(app));
  }

  Future<void> _loadSelectedAppDetails(ProtectedApp app) async {
    setState(() => _detailLoading = true);
    try {
      final detailed = await _appScanService.enrichAppDetails(app);
      _replaceApp(detailed);
      if (!mounted) return;
      setState(() => _selectedApp = detailed);
    } catch (error) {
      _showMessage(
        formatTemplate(_tr.t('scan.error_downloads'), {'e': error}),
      );
    } finally {
      if (mounted) {
        setState(() => _detailLoading = false);
      }
    }
  }

  Future<void> _scanSelectedApp() async {
    final app = _selectedApp;
    if (app == null) return;
    setState(() => _detailLoading = true);
    try {
      final scanned = await _appScanService.scanInstalledApp(app);
      _replaceApp(scanned);
      if (!mounted) return;
      setState(() => _selectedApp = scanned);
    } on vt.VirusTotalRateLimitException catch (error) {
      _showMessage(
        'VirusTotal limiti sabab $error',
        isError: true,
      );
    } catch (error) {
      _showMessage(
        formatTemplate(_tr.t('scan.error_downloads'), {'e': error}),
      );
    } finally {
      if (mounted) {
        setState(() => _detailLoading = false);
      }
    }
  }

  Future<void> _uninstallSelectedApp() async {
    final app = _selectedApp;
    if (app == null) return;
    try {
      // Prefer native package uninstaller on Android (opens system dialog).
      var opened = await _nativePackageService.openUninstallScreen(
        app.packageName,
      );
      if (!opened) {
        // Try flutter_device_apps plugin which fires a real uninstall intent.
        try {
          final pluginResult = await FlutterDeviceApps.uninstallApp(
            app.packageName,
          );
          opened = pluginResult == true;
        } catch (_) {
          opened = false;
        }
      }
      if (!opened) {
        // Last resort: open the app details page (user can tap Uninstall).
        opened = await _nativePackageService.openAppSettings(app.packageName);
      }
      if (!opened && mounted) {
        _showMessage(context.tr.t('uninstall.failed'), isError: true);
      }
      // No success toast — the system already shows its own dialog / UI.
    } catch (_) {
      if (mounted) {
        _showMessage(context.tr.t('uninstall.failed'), isError: true);
      }
    }
  }

  Future<void> _scanIncomingFile(String path) async {
    if (_scanInProgress) {
      _showMessage(_tr.t('files.prev_in_progress'));
      return;
    }
    _pendingIncomingFilePath = null;
    final fileName = path.split(RegExp(r'[\\/]')).last;

    _startScanSession();
    if (mounted) {
      setState(() {
        _stage = AppStage.scanning;
        _scannedCount = 0;
        _scanTotalCount = 1;
        _currentTargetName = fileName;
      });
    }

    try {
      final result = await _fileScanService.scanSingleFile(path);
      final finding = _fileScanService.findingFromResult(result);
      if (!mounted) return;
      setState(() {
        _history = [
          finding,
          ..._history.where((item) => item.location != finding.location)
        ];
        _scannedCount = 1;
        if (_scanBackgroundMode) {
          _pendingResultsNavigation = true;
        } else {
          _tab = DashboardTab.history;
          _stage = AppStage.results;
        }
      });
      await _notifyIfNeeded([finding]);
      await _loadFiles(force: true, silent: true, seedKnownPaths: true);
    } on vt.VirusTotalRateLimitException catch (error) {
      _scanStartedAt = null;
      _scanInProgress = false;
      _scanBackgroundMode = false;
      _showMessage(
        'VirusTotal limiti sabab $error',
        isError: true,
      );
      if (mounted) {
        setState(() => _stage = AppStage.files);
      }
    } catch (error) {
      _scanStartedAt = null;
      _scanInProgress = false;
      _scanBackgroundMode = false;
      _showMessage(
        formatTemplate(_tr.t('scan.error_downloads'), {'e': error}),
        isError: true,
      );
      if (mounted) {
        setState(() => _stage = AppStage.files);
      }
    }
  }

  Future<void> _deleteFindingFile(ScanFinding finding) async {
    final location = finding.location;
    if (location == null || location.isEmpty) {
      _showMessage(_tr.t('files.delete_missing'), isError: true);
      return;
    }

    final file = File(location);
    if (!await file.exists()) {
      _showMessage(_tr.t('files.delete_missing'));
      setState(() {
        _history = _history.where((item) => item.location != location).toList();
      });
      return;
    }

    try {
      await file.delete();
      if (!mounted) return;
      setState(() {
        _history = _history.where((item) => item.location != location).toList();
        _downloadFiles =
            _downloadFiles.where((item) => item.path != location).toList();
        _knownDownloadPaths.remove(location);
      });
      _showMessage(_tr.t('files.delete_done'));
    } catch (error) {
      _showMessage(
        formatTemplate(_tr.t('files.delete_failed'), {'e': error}),
        isError: true,
      );
    }
  }

  Future<void> _loadSafeState() async {
    if (_safeLoading) return;
    if (mounted) {
      setState(() => _safeLoading = true);
    }
    try {
      final hasPin = await _posbonSafeService.hasPin();
      final items = await _posbonSafeService.loadItems();
      bool deviceAuthAvailable = false;
      try {
        deviceAuthAvailable =
            await _nativePackageService.canAuthenticateDevice();
      } catch (_) {
        deviceAuthAvailable = false;
      }

      if (!mounted) {
        _safeHasPin = hasPin;
        _safeItems = items;
        _safeDeviceAuthAvailable = deviceAuthAvailable;
        return;
      }

      setState(() {
        _safeHasPin = hasPin;
        _safeItems = items;
        _safeDeviceAuthAvailable = deviceAuthAvailable;
      });
    } finally {
      if (mounted) {
        setState(() => _safeLoading = false);
      }
    }
  }

  Future<void> _setupSafePin(String pin) async {
    await _posbonSafeService.savePin(pin);
    if (!mounted) return;
    setState(() {
      _safeHasPin = true;
      _safeUnlocked = true;
    });
  }

  Future<bool> _unlockSafeWithPin(String pin) async {
    final verified = await _posbonSafeService.verifyPin(pin);
    if (!mounted) return verified;
    if (verified) {
      setState(() => _safeUnlocked = true);
      return true;
    }
    return false;
  }

  Future<bool> _unlockSafeWithDeviceAuth() async {
    try {
      final unlocked = await _nativePackageService.authenticateDevice(
        reason: 'Posbon Safe ma\'lumotlarini ochish uchun tasdiqlang',
      );
      if (!mounted) return unlocked;
      if (unlocked) {
        setState(() => _safeUnlocked = true);
      }
      return unlocked;
    } catch (error) {
      return false;
    }
  }

  void _lockSafe() {
    if (!mounted) {
      _safeUnlocked = false;
      return;
    }
    setState(() => _safeUnlocked = false);
  }

  Future<void> _saveSafeItems(List<SafeCredential> items) async {
    await _posbonSafeService.saveItems(items);
    if (!mounted) {
      _safeItems = items;
      return;
    }
    setState(() => _safeItems = items);
  }

  Future<void> _addSafeItem(SafeCredential item) async {
    final updated = [item, ..._safeItems];
    await _saveSafeItems(updated);
  }

  Future<void> _deleteSafeItem(SafeCredential item) async {
    final updated = _safeItems.where((value) => value.id != item.id).toList();
    await _saveSafeItems(updated);
  }

  Future<void> _copyValue(String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    _showMessage(
      formatTemplate(_tr.t('files.copied'), {'label': label}),
    );
  }

  void _showAboutPosbon() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.secondarySurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        final tr = context.tr;
        final maxHeight = MediaQuery.sizeOf(context).height * 0.82;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Center(child: PosbonLogo(size: 58)),
                  const SizedBox(height: 18),
                  Text(
                    tr.t('about.title'),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _AboutLine(
                    icon: Icons.apps_rounded,
                    title: tr.t('about.apps_title'),
                    description: tr.t('about.apps_desc'),
                  ),
                  _AboutLine(
                    icon: Icons.folder_open_rounded,
                    title: tr.t('about.files_title'),
                    description: tr.t('about.files_desc'),
                  ),
                  _AboutLine(
                    icon: Icons.lock_outline_rounded,
                    title: tr.t('about.safe_title'),
                    description: tr.t('about.safe_desc'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  ScanFinding _findingFromApp(ProtectedApp app) {
    final reasons = {
      ...app.permissions
          .where((permission) => permission.isDangerous)
          .map((permission) => permission.explanation ?? permission.name),
      if (app.virusTotalDetections > 0)
        app.virusTotalThreatLabel != null &&
                app.virusTotalThreatLabel!.isNotEmpty
            ? 'VirusTotal: "${app.virusTotalThreatLabel}"'
            : 'VirusTotal: ${app.virusTotalDetections}',
      if (app.virusTotalDetections == 0 &&
          app.virusTotalNote != null &&
          app.virusTotalNote!.isNotEmpty)
        app.virusTotalNote!,
      '${_tr.t('app_detail.source')}: ${app.source}',
      if (app.isTrusted) _tr.t('about.app_trusted_hint'),
    }.toList();

    return ScanFinding(
      name: app.name,
      type: ScanTargetType.app,
      risk: app.risk,
      details: app.lastScanSummary ?? '${app.riskScore}%',
      reasons: reasons,
      location: app.packageName,
    );
  }

  void _replaceApp(ProtectedApp app) {
    final updatedApps = List<ProtectedApp>.from(_apps);
    final index = updatedApps.indexWhere(
      (item) => item.packageName == app.packageName,
    );
    if (index == -1) {
      updatedApps.add(app);
      _apps = updatedApps;
      return;
    }
    updatedApps[index] = app;
    _apps = updatedApps;
  }

  Future<bool> _handleSystemBack() async {
    switch (_stage) {
      case AppStage.appDetail:
        setState(() => _stage = AppStage.apps);
        return false;
      case AppStage.files:
      case AppStage.apps:
      case AppStage.safe:
      case AppStage.results:
      case AppStage.settings:
        setState(() {
          _tab = DashboardTab.home;
          _stage = AppStage.dashboard;
        });
        return false;
      case AppStage.scanning:
        _cancelScan();
        return false;
      case AppStage.splash:
      case AppStage.agreement:
      case AppStage.onboarding:
      case AppStage.permissions:
      case AppStage.dashboard:
        return true;
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final messenger = _rootMessengerKey.currentState;
      if (messenger == null || !messenger.mounted) {
        return;
      }

      try {
        messenger
          ..hideCurrentSnackBar()
          ..hideCurrentMaterialBanner()
          ..showSnackBar(
            _buildPosbonSnackBar(
              messenger.context,
              message,
              isError: isError,
            ),
          );
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    late final Widget screen;
    switch (_stage) {
      case AppStage.splash:
        screen = const SplashScreen();
        break;
      case AppStage.agreement:
        screen = AgreementScreen(onAccepted: _acceptAgreement);
        break;
      case AppStage.onboarding:
        screen = OnboardingScreen(
          currentIndex: _onboardingIndex,
          onPageChanged: _setOnboardingPage,
          onContinue: _completeOnboarding,
        );
        break;
      case AppStage.permissions:
        screen = PermissionsScreen(
          items: _permissions,
          canContinue: _hasAllRequiredPermissions,
          onGrant: (id) {
            _togglePermission(id);
          },
          onContinue: _continueFromPermissions,
        );
        break;
      case AppStage.dashboard:
        screen = HomeDashboardScreen(
          findings: _history,
          scanInProgress: _scanInProgress,
          scanBackgroundMode: _scanBackgroundMode,
          scannedCount: _scannedCount,
          scanTotalCount: _scanTotalCount,
          currentScanTarget: _currentTargetName,
          liveMonitoring: _settings.liveMonitoring,
          onStartScan: () {
            _startScan();
          },
          onOpenFiles: () {
            _openTab(DashboardTab.files);
          },
          onOpenApps: () {
            _openTab(DashboardTab.apps);
          },
          onOpenSafe: () {
            _openSafeScreen();
          },
          onOpenAbout: _showAboutPosbon,
          onSelectTab: (tab) {
            _openTab(tab);
          },
          onOpenResultsFiltered: _openResultsFiltered,
          currentTab: _tab,
        );
        break;
      case AppStage.files:
        screen = FilesScreen(
          files: _downloadFiles,
          isLoading: _filesLoading,
          hasFilePermission: _permissions
              .firstWhere(
                (item) => item.id == PermissionCardId.fileManager,
                orElse: () => const PermissionStatusCard(
                  id: PermissionCardId.fileManager,
                  icon: Icons.folder_open_rounded,
                  title: '',
                  description: '',
                  granted: false,
                ),
              )
              .granted,
          onRefresh: () => _loadFiles(force: true, seedKnownPaths: true),
          onScanAll: _scanAllDownloadFiles,
          onPickFiles: _pickAndScanFiles,
          onOpenFile: _scanSingleDownloadFile,
          onOpenPermissions: () =>
              _togglePermission(PermissionCardId.fileManager),
          onSelectTab: (tab) {
            _openTab(tab);
          },
          currentTab: DashboardTab.files,
        );
        break;
      case AppStage.scanning:
        screen = ScanningScreen(
          currentName: _currentTargetName,
          scannedCount: _scannedCount,
          totalCount: _scanTotalCount == 0 ? 1 : _scanTotalCount,
          onBackground: _continueScanInBackground,
          onCancel: _cancelScan,
        );
        break;
      case AppStage.results:
        screen = ResultsScreen(
          findings: _history,
          initialFilter: _resultsFilter,
          onDeleteFinding: _deleteFindingFile,
          onSelectTab: (tab) {
            _openTab(tab);
          },
          currentTab: DashboardTab.history,
        );
        break;
      case AppStage.apps:
        screen = InstalledAppsScreen(
          apps: _apps,
          isLoading: _appsLoading,
          onRefresh: () => _loadApps(force: true),
          onOpenApp: _openAppDetail,
          onSelectTab: (tab) {
            _openTab(tab);
          },
          currentTab: DashboardTab.apps,
        );
        break;
      case AppStage.appDetail:
        screen = AppDetailScreen(
          app: _selectedApp ?? _apps.first,
          isLoading: _detailLoading,
          onScan: () {
            _scanSelectedApp();
          },
          onUninstall: () {
            _uninstallSelectedApp();
          },
          onBack: () {
            _openTab(DashboardTab.apps);
          },
        );
        break;
      case AppStage.settings:
        screen = Scaffold(
          backgroundColor: Colors.transparent,
          body: SettingsScreen(
            controller: _settings,
            onChanged: () {
              if (mounted) setState(() {});
            },
            appVersion: kPosbonAppVersion,
          ),
          bottomNavigationBar: PosbonBottomNav(
            currentTab: DashboardTab.settings,
            onSelected: _openTab,
          ),
        );
        break;
      case AppStage.safe:
        screen = HomeDashboardScreen(
          findings: _history,
          scanInProgress: _scanInProgress,
          scanBackgroundMode: _scanBackgroundMode,
          scannedCount: _scannedCount,
          scanTotalCount: _scanTotalCount,
          currentScanTarget: _currentTargetName,
          liveMonitoring: _settings.liveMonitoring,
          onStartScan: () {
            _startScan();
          },
          onOpenFiles: () {
            _openTab(DashboardTab.files);
          },
          onOpenApps: () {
            _openTab(DashboardTab.apps);
          },
          onOpenSafe: () {
            _openSafeScreen();
          },
          onOpenAbout: _showAboutPosbon,
          onSelectTab: (tab) {
            _openTab(tab);
          },
          onOpenResultsFiltered: _openResultsFiltered,
          currentTab: _tab,
        );
        break;
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        final shouldPop = await _handleSystemBack();
        if (shouldPop) {
          navigator.pop();
        }
      },
      child: PageStorage(bucket: _pageStorageBucket, child: screen),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    return AnimatedAuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final scale = 1 + (_controller.value * 0.08);
              return Transform.scale(scale: scale, child: child);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    PulseRings(size: 180, color: AppColors.accent, ringCount: 3),
                    const PosbonLogo(size: 96),
                  ],
                ),
                const SizedBox(height: 22),
                Text(
                  tr.t('app.name_short'),
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.6,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  tr.t('app.slogan'),
                  style: const TextStyle(
                    color: AppColors.description,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    required this.currentIndex,
    required this.onPageChanged,
    required this.onContinue,
    super.key,
  });

  final int currentIndex;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onContinue;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late final PageController _controller;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: onboardingItems.length,
                  onPageChanged: widget.onPageChanged,
                  itemBuilder: (context, index) {
                    final item = onboardingItems[index];
                    final tr = context.tr;
                    final titleKey = 'onboarding.${index + 1}.title';
                    final descKey = 'onboarding.${index + 1}.desc';
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 116,
                          height: 116,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(color: AppColors.accent),
                          ),
                          child: Icon(
                            item.icon,
                            size: 54,
                            color: AppColors.accent,
                          ),
                        ),
                        const SizedBox(height: 28),
                        Text(
                          tr.t(titleKey),
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          tr.t(descKey),
                          style: const TextStyle(
                            color: AppColors.description,
                            fontSize: 14,
                            height: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    );
                  },
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  onboardingItems.length,
                  (index) => AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    width: widget.currentIndex == index ? 28 : 10,
                    height: 10,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: widget.currentIndex == index
                          ? AppColors.accent
                          : AppColors.mutedSurface,
                      borderRadius: BorderRadius.circular(100),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              PrimaryButton(
                label: context.tr.t('common.continue'),
                onPressed: () {
                  if (widget.currentIndex == onboardingItems.length - 1) {
                    widget.onContinue();
                    return;
                  }
                  _controller.nextPage(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOut,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PermissionsScreen extends StatelessWidget {
  const PermissionsScreen({
    required this.items,
    required this.canContinue,
    required this.onGrant,
    required this.onContinue,
    super.key,
  });

  final List<PermissionStatusCard> items;
  final bool canContinue;
  final ValueChanged<PermissionCardId> onGrant;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const PosbonLogo(size: 48),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      tr.t('permissions.title'),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                tr.t('permissions.body'),
                style: const TextStyle(
                  color: AppColors.description,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 28),
              Expanded(
                child: ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return PermissionTile(
                      item: item,
                      onGrant: () => onGrant(item.id),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.secondarySurface,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: canContinue ? onContinue : null,
                  child: Text(tr.t('common.continue')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HomeDashboardScreen extends StatelessWidget {
  const HomeDashboardScreen({
    required this.findings,
    required this.onStartScan,
    required this.onOpenFiles,
    required this.onOpenApps,
    required this.onOpenSafe,
    required this.onOpenAbout,
    required this.onSelectTab,
    required this.currentTab,
    required this.onOpenResultsFiltered,
    required this.scanInProgress,
    required this.scanBackgroundMode,
    required this.scannedCount,
    required this.scanTotalCount,
    required this.currentScanTarget,
    required this.liveMonitoring,
    super.key,
  });

  final List<ScanFinding> findings;
  final VoidCallback onStartScan;
  final VoidCallback onOpenFiles;
  final VoidCallback onOpenApps;
  final VoidCallback onOpenSafe;
  final VoidCallback onOpenAbout;
  final ValueChanged<DashboardTab> onSelectTab;
  final DashboardTab currentTab;
  final ValueChanged<RiskFilter> onOpenResultsFiltered;
  final bool scanInProgress;
  final bool scanBackgroundMode;
  final int scannedCount;
  final int scanTotalCount;
  final String currentScanTarget;
  final bool liveMonitoring;

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final dangerous = findings.where((item) => item.risk.isDangerous).length;
    final suspicious = findings.where((item) => item.risk.isSuspicious).length;
    final safe = findings.where((item) => item.risk.isSafe).length;

    return AnimatedAuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: OverflowSafeScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const PosbonLogo(size: 44),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tr.t('app.title'),
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            tr.t('app.subtitle'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.description,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _GlassIconButton(
                      icon: Icons.info_outline_rounded,
                      onTap: onOpenAbout,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (scanInProgress || scanBackgroundMode)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _ScanningBanner(
                      scannedCount: scannedCount,
                      totalCount: scanTotalCount,
                      currentTarget: currentScanTarget,
                      background: scanBackgroundMode,
                    ),
                  ),
                _HomeHeroCard(
                  findings: findings,
                  onStartScan: onStartScan,
                  scanning: scanInProgress,
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: StatCard(
                        label: tr.t('status.dangerous'),
                        value: '$dangerous',
                        color: AppColors.danger,
                        onTap: () =>
                            onOpenResultsFiltered(RiskFilter.dangerous),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: StatCard(
                        label: tr.t('status.suspicious'),
                        value: '$suspicious',
                        color: AppColors.warning,
                        onTap: () =>
                            onOpenResultsFiltered(RiskFilter.suspicious),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: StatCard(
                        label: tr.t('status.safe'),
                        value: '$safe',
                        color: AppColors.accent,
                        onTap: () => onOpenResultsFiltered(RiskFilter.safe),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _LiveMonitorRow(enabled: liveMonitoring),
                const SizedBox(height: 16),
                Text(
                  findings.isEmpty
                      ? tr.t('home.hint_no_scan')
                      : tr.t('home.hint_done'),
                  style: const TextStyle(
                    color: AppColors.description,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  tr.t('home.quick_access'),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: QuickActionCard(
                        title: tr.t('home.files_title'),
                        subtitle: tr.t('home.files_sub'),
                        icon: Icons.folder_open_rounded,
                        onTap: onOpenFiles,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: QuickActionCard(
                        title: tr.t('home.apps_title'),
                        subtitle: tr.t('home.apps_sub'),
                        icon: Icons.apps_rounded,
                        onTap: onOpenApps,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                QuickActionCard(
                  title: tr.t('home.safe_title'),
                  subtitle: tr.t('home.safe_sub'),
                  icon: Icons.lock_outline_rounded,
                  onTap: onOpenSafe,
                ),
              ],
            ),
          ),
        ),
        bottomNavigationBar: PosbonBottomNav(
          currentTab: currentTab,
          onSelected: onSelectTab,
        ),
      ),
    );
  }
}

class _LiveMonitorRow extends StatelessWidget {
  const _LiveMonitorRow({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: enabled
              ? AppColors.accent.withValues(alpha: 0.3)
              : AppColors.outline,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: enabled ? AppColors.accent : AppColors.description,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              enabled
                  ? tr.t('home.live_monitor')
                  : tr.t('home.live_monitor_off'),
              style: const TextStyle(fontSize: 12),
            ),
          ),
          Icon(
            enabled ? Icons.wifi_tethering_rounded : Icons.power_off_rounded,
            color: enabled ? AppColors.accent : AppColors.description,
            size: 18,
          ),
        ],
      ),
    );
  }
}

class _ScanningBanner extends StatelessWidget {
  const _ScanningBanner({
    required this.scannedCount,
    required this.totalCount,
    required this.currentTarget,
    required this.background,
  });

  final int scannedCount;
  final int totalCount;
  final String currentTarget;
  final bool background;

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final total = totalCount == 0 ? 1 : totalCount;
    final progress = (scannedCount / total).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF153A33), Color(0xFF0B1F1C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              RadarSweep(size: 28, color: AppColors.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      background
                          ? tr.t('home.scanning_bg')
                          : tr.t('home.scanning_now'),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      currentTarget,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.description,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '$scannedCount/$total',
                style: const TextStyle(
                  color: AppColors.accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              color: AppColors.accent,
              backgroundColor: AppColors.mutedSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class ScanningScreen extends StatelessWidget {
  const ScanningScreen({
    required this.currentName,
    required this.scannedCount,
    required this.totalCount,
    required this.onBackground,
    required this.onCancel,
    super.key,
  });

  final String currentName;
  final int scannedCount;
  final int totalCount;
  final VoidCallback onBackground;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final progress = scannedCount / totalCount;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final radarSize = min(screenWidth - 96, 220.0).clamp(170.0, 220.0);
    final innerRadarSize = (radarSize * 0.54).clamp(92.0, 118.0);

    return Scaffold(
      body: SafeArea(
        child: OverflowSafeScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.88, end: 1.08),
                duration: const Duration(milliseconds: 1100),
                curve: Curves.easeInOut,
                builder: (context, value, child) {
                  return Transform.scale(scale: value, child: child);
                },
                child: Container(
                  width: radarSize,
                  height: radarSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.accent, width: 2),
                  ),
                  child: Center(
                    child: Container(
                      width: innerRadarSize,
                      height: innerRadarSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.accent.withValues(alpha: 0.10),
                      ),
                      child: const Icon(
                        Icons.radar_rounded,
                        color: AppColors.accent,
                        size: 56,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 30),
              Text(
                tr.t('scan.title'),
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                currentName,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.description,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 24),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: progress.clamp(0, 1),
                  minHeight: 10,
                  color: AppColors.accent,
                  backgroundColor: AppColors.mutedSurface,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                formatTemplate(tr.t('scan.progress'), {
                  'n': scannedCount,
                  't': totalCount,
                }),
                style: const TextStyle(
                  color: AppColors.description,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                tr.t('scan.hint_background'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.description,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlineActionButton(
                      label: tr.t('scan.background_btn'),
                      onPressed: onBackground,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlineActionButton(
                      label: tr.t('common.cancel'),
                      borderColor: AppColors.warning,
                      foregroundColor: AppColors.warning,
                      onPressed: onCancel,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FilesScreen extends StatelessWidget {
  const FilesScreen({
    required this.files,
    required this.isLoading,
    required this.hasFilePermission,
    required this.onRefresh,
    required this.onScanAll,
    required this.onPickFiles,
    required this.onOpenFile,
    required this.onOpenPermissions,
    required this.onSelectTab,
    required this.currentTab,
    super.key,
  });

  final List<File> files;
  final bool isLoading;
  final bool hasFilePermission;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onScanAll;
  final Future<void> Function() onPickFiles;
  final Future<void> Function(File file) onOpenFile;
  final VoidCallback onOpenPermissions;
  final ValueChanged<DashboardTab> onSelectTab;
  final DashboardTab currentTab;

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr.t('files.title'),
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                hasFilePermission
                    ? tr.t('files.subtitle_ok_long')
                    : tr.t('files.subtitle_no_perm_long'),
                style: const TextStyle(
                  color: AppColors.description,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.outline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.download_rounded,
                          color: AppColors.accent,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            formatTemplate(tr.t('files.count_found'), {
                              'n': files.length,
                            }),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (!hasFilePermission)
                          TextButton(
                            onPressed: onOpenPermissions,
                            child: Text(tr.t('files.permission')),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      tr.t('files.bg_hint'),
                      style: const TextStyle(
                        color: AppColors.description,
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlineActionButton(
                            label: tr.t('files.scan_all'),
                            onPressed: onScanAll,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlineActionButton(
                            label: tr.t('files.pick'),
                            onPressed: onPickFiles,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : RefreshIndicator(
                        onRefresh: onRefresh,
                        child: files.isEmpty
                            ? ListView(
                                children: const [
                                  SizedBox(height: 56),
                                  EmptyFilesState(),
                                ],
                              )
                            : ListView.builder(
                                itemCount: files.length,
                                itemBuilder: (context, index) {
                                  final file = files[index];
                                  return DownloadFileTile(
                                    file: file,
                                    onTap: () => onOpenFile(file),
                                  );
                                },
                              ),
                      ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: PosbonBottomNav(
        currentTab: currentTab,
        onSelected: onSelectTab,
      ),
    );
  }
}

class ResultsScreen extends StatefulWidget {
  const ResultsScreen({
    required this.findings,
    required this.onDeleteFinding,
    required this.onSelectTab,
    required this.currentTab,
    this.initialFilter = RiskFilter.all,
    super.key,
  });

  final List<ScanFinding> findings;
  final Future<void> Function(ScanFinding finding) onDeleteFinding;
  final ValueChanged<DashboardTab> onSelectTab;
  final DashboardTab currentTab;
  final RiskFilter initialFilter;

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  late RiskFilter _filter;

  @override
  void initState() {
    super.initState();
    _filter = widget.initialFilter;
  }

  @override
  void didUpdateWidget(covariant ResultsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialFilter != widget.initialFilter) {
      _filter = widget.initialFilter;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final findings = widget.findings;
    final dangerous = findings.where((item) => item.risk.isDangerous).length;
    final suspicious = findings.where((item) => item.risk.isSuspicious).length;
    final safe = findings.where((item) => item.risk == RiskLevel.safe).length;

    final filtered = findings.where((item) {
      return switch (_filter) {
        RiskFilter.all => true,
        RiskFilter.dangerous => item.risk.isDangerous,
        RiskFilter.suspicious => item.risk.isSuspicious,
        RiskFilter.safe => item.risk == RiskLevel.safe,
      };
    }).toList();

    return AnimatedAuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr.t('results.title'),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  tr.t('results.subtitle'),
                  style: const TextStyle(
                    color: AppColors.description,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _FilterChipCount(
                        label: tr.t('status.dangerous'),
                        value: dangerous,
                        color: AppColors.danger,
                        selected: _filter == RiskFilter.dangerous,
                        onTap: () => setState(() {
                          _filter = _filter == RiskFilter.dangerous
                              ? RiskFilter.all
                              : RiskFilter.dangerous;
                        }),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _FilterChipCount(
                        label: tr.t('status.suspicious'),
                        value: suspicious,
                        color: AppColors.warning,
                        selected: _filter == RiskFilter.suspicious,
                        onTap: () => setState(() {
                          _filter = _filter == RiskFilter.suspicious
                              ? RiskFilter.all
                              : RiskFilter.suspicious;
                        }),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _FilterChipCount(
                        label: tr.t('status.safe'),
                        value: safe,
                        color: AppColors.accent,
                        selected: _filter == RiskFilter.safe,
                        onTap: () => setState(() {
                          _filter = _filter == RiskFilter.safe
                              ? RiskFilter.all
                              : RiskFilter.safe;
                        }),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: filtered.isEmpty
                      ? const EmptySafeState()
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 16),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final finding = filtered[index];
                            return FindingTile(
                              finding: finding,
                              onDeleteFinding: widget.onDeleteFinding,
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
        bottomNavigationBar: PosbonBottomNav(
          currentTab: widget.currentTab,
          onSelected: widget.onSelectTab,
        ),
      ),
    );
  }
}

class _FilterChipCount extends StatelessWidget {
  const _FilterChipCount({
    required this.label,
    required this.value,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int value;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? color.withValues(alpha: 0.18)
                : AppColors.surface.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? color.withValues(alpha: 0.6)
                  : AppColors.outline,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$value',
                style: TextStyle(
                  color: color,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.description,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class InstalledAppsScreen extends StatefulWidget {
  const InstalledAppsScreen({
    required this.apps,
    required this.isLoading,
    required this.onRefresh,
    required this.onOpenApp,
    required this.onSelectTab,
    required this.currentTab,
    super.key,
  });

  final List<ProtectedApp> apps;
  final bool isLoading;
  final Future<void> Function() onRefresh;
  final ValueChanged<ProtectedApp> onOpenApp;
  final ValueChanged<DashboardTab> onSelectTab;
  final DashboardTab currentTab;

  @override
  State<InstalledAppsScreen> createState() => _InstalledAppsScreenState();
}

class _InstalledAppsScreenState extends State<InstalledAppsScreen> {
  String _query = '';
  RiskFilter _filter = RiskFilter.all;

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final filteredApps = widget.apps.where((app) {
      final queryMatch = app.name.toLowerCase().contains(
            _query.toLowerCase(),
          );
      if (!queryMatch) return false;
      return switch (_filter) {
        RiskFilter.all => true,
        RiskFilter.dangerous => app.risk.isDangerous,
        RiskFilter.suspicious => app.risk.isSuspicious,
        RiskFilter.safe => app.risk == RiskLevel.safe,
      };
    }).toList();

    String filterLabel(RiskFilter f) => switch (f) {
          RiskFilter.all => tr.t('status.all'),
          RiskFilter.dangerous => tr.t('status.dangerous'),
          RiskFilter.suspicious => tr.t('status.suspicious'),
          RiskFilter.safe => tr.t('status.safe'),
        };

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr.t('apps.title'),
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 18),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.outline),
                ),
                child: TextField(
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: tr.t('apps.search_hint'),
                    hintStyle: const TextStyle(color: AppColors.description),
                    prefixIcon: const Icon(
                      Icons.search,
                      color: AppColors.description,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              const SizedBox(height: 16),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: RiskFilter.values.map((filter) {
                    final selected = _filter == filter;
                    return Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: GestureDetector(
                        onTap: () => setState(() => _filter = filter),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: selected
                                ? AppColors.accent
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: AppColors.outline),
                          ),
                          child: Text(
                            filterLabel(filter),
                            style: TextStyle(
                              color: selected ? Colors.black : Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: widget.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : RefreshIndicator(
                        onRefresh: widget.onRefresh,
                        child: ListView.builder(
                          key: const PageStorageKey<String>(
                            'installed_apps_list',
                          ),
                          itemCount: filteredApps.length,
                          itemBuilder: (context, index) {
                            final app = filteredApps[index];
                            return AppListTile(
                              app: app,
                              onTap: () => widget.onOpenApp(app),
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: PosbonBottomNav(
        currentTab: widget.currentTab,
        onSelected: widget.onSelectTab,
      ),
    );
  }
}

class AppDetailScreen extends StatefulWidget {
  const AppDetailScreen({
    required this.app,
    required this.isLoading,
    required this.onScan,
    required this.onUninstall,
    required this.onBack,
    super.key,
  });

  final ProtectedApp app;
  final bool isLoading;
  final VoidCallback onScan;
  final VoidCallback onUninstall;
  final VoidCallback onBack;

  @override
  State<AppDetailScreen> createState() => _AppDetailScreenState();
}

class _AppDetailScreenState extends State<AppDetailScreen> {
  bool _showAllPermissions = false;

  @override
  void didUpdateWidget(covariant AppDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.app.packageName != widget.app.packageName) {
      _showAllPermissions = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final permissions = _showAllPermissions || app.permissions.length <= 4
        ? app.permissions
        : app.permissions.take(4).toList();

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: widget.onBack,
                child: const Icon(Icons.arrow_back_ios_new_rounded),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Container(
                    width: 66,
                    height: 66,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.outline),
                    ),
                    child: app.iconBytes != null
                        ? ClipOval(
                            child: Image.memory(
                              app.iconBytes!,
                              fit: BoxFit.cover,
                            ),
                          )
                        : Icon(
                            app.icon ?? Icons.android_rounded,
                            color: AppColors.accent,
                            size: 34,
                          ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          app.name,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        RiskBadge(level: app.risk),
                        if (app.isTrusted) ...[
                          const SizedBox(height: 8),
                          Text(
                            context.tr.t('app_detail.trusted_badge'),
                            style: const TextStyle(
                              color: AppColors.accent,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: InfoCard(
                      label: context.tr.t('app_detail.source'),
                      value: app.source,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InfoCard(
                      label: context.tr.t('app_detail.version'),
                      value: app.version,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              InfoCard(
                label: context.tr.t('app_detail.installed_date'),
                value: app.installedDate,
              ),
              if (app.lastUpdatedDate != null) ...[
                const SizedBox(height: 12),
                InfoCard(
                  label: context.tr.t('app_detail.updated_date'),
                  value: app.lastUpdatedDate!,
                ),
              ],
              const SizedBox(height: 22),
              Text(
                context.tr.t('app_detail.risk_level'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: app.riskScore / 100,
                  minHeight: 12,
                  color: app.risk.color,
                  backgroundColor: AppColors.mutedSurface,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '${app.riskScore}%',
                style: const TextStyle(
                  color: AppColors.description,
                  fontSize: 14,
                ),
              ),
              if (app.isTrusted) ...[
                const SizedBox(height: 16),
                _FindingMetaCard(
                  label: context.tr.t('app_detail.posbon_note'),
                  value: context.tr.t('app_detail.posbon_note_body'),
                ),
              ],
              if (app.lastScanSummary != null) ...[
                const SizedBox(height: 16),
                _FindingMetaCard(
                  label: context.tr.t('app_detail.summary_title'),
                  value: app.lastScanSummary!,
                ),
              ],
              if (app.apkPath != null && app.apkPath!.isNotEmpty) ...[
                const SizedBox(height: 12),
                InfoCard(label: 'APK', value: app.apkPath!),
              ],
              const SizedBox(height: 22),
              Text(
                context.tr.t('app_detail.permissions'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              if (app.permissions.isEmpty)
                Text(
                  context.tr.t('app_detail.permissions_none'),
                  style: const TextStyle(
                    color: AppColors.description,
                    fontSize: 14,
                  ),
                )
              else
                ...permissions.map(
                  (permission) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Icon(
                            permission.isDangerous
                                ? Icons.warning_rounded
                                : Icons.check_circle_outline_rounded,
                            color: permission.isDangerous
                                ? AppColors.danger
                                : AppColors.accent,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                permission.explanation ?? permission.name,
                                style: const TextStyle(fontSize: 14),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                permission.name,
                                style: const TextStyle(
                                  color: AppColors.description,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (app.permissions.length > 4)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () {
                      setState(
                          () => _showAllPermissions = !_showAllPermissions);
                    },
                    child: Text(
                      _showAllPermissions
                          ? context.tr.t('app_detail.show_less')
                          : context.tr.t('app_detail.show_more'),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              _VirusTotalStatusCard(app: app),
              const SizedBox(height: 8),
              if (app.virusTotalDetections > 0)
                Text(
                  context.tr.t('app_detail.vt_dangerous_note'),
                  style: const TextStyle(
                    color: AppColors.description,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlineActionButton(
                  label: widget.isLoading
                      ? context.tr.t('app_detail.scanning')
                      : context.tr.t('app_detail.deep_scan'),
                  onPressed: widget.isLoading ? () {} : widget.onScan,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: OutlineActionButton(
                  label: context.tr.t('app_detail.uninstall'),
                  borderColor: AppColors.danger,
                  foregroundColor: AppColors.danger,
                  onPressed: widget.onUninstall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PosbonSafeScreen extends StatefulWidget {
  const PosbonSafeScreen({
    required this.isLoading,
    required this.unlocked,
    required this.hasPin,
    required this.deviceAuthAvailable,
    required this.items,
    required this.onUnlockWithDevice,
    required this.onUnlockWithPin,
    required this.onSetPin,
    required this.onLock,
    required this.onAddItem,
    required this.onDeleteItem,
    required this.onCopyValue,
    required this.onShowAbout,
    super.key,
  });

  final bool isLoading;
  final bool unlocked;
  final bool hasPin;
  final bool deviceAuthAvailable;
  final List<SafeCredential> items;
  final Future<bool> Function() onUnlockWithDevice;
  final Future<bool> Function(String pin) onUnlockWithPin;
  final Future<void> Function(String pin) onSetPin;
  final VoidCallback onLock;
  final Future<void> Function(SafeCredential item) onAddItem;
  final Future<void> Function(SafeCredential item) onDeleteItem;
  final Future<void> Function(String label, String value) onCopyValue;
  final VoidCallback onShowAbout;

  @override
  State<PosbonSafeScreen> createState() => _PosbonSafeScreenState();
}

class _PosbonSafeScreenState extends State<PosbonSafeScreen> {
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _setupPinController = TextEditingController();
  final TextEditingController _setupConfirmController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  late final bool _isLoading = widget.isLoading;
  late bool _isUnlocked = widget.unlocked;
  late bool _hasPin = widget.hasPin;
  late final bool _deviceAuthAvailable = widget.deviceAuthAvailable;
  late List<SafeCredential> _items = List<SafeCredential>.from(widget.items);

  String _searchQuery = '';
  String? _setupHint;
  String? _unlockHint;

  @override
  void dispose() {
    _pinController.dispose();
    _setupPinController.dispose();
    _setupConfirmController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchQuery.trim().toLowerCase();
    final filteredItems = query.isEmpty
        ? _items
        : _items
            .where(
              (item) => _safeItemMatchesQuery(item, query),
            )
            .toList();

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : !_hasPin
                ? OverflowSafeScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                    child: _buildSetupState(),
                  )
                : !_isUnlocked
                    ? OverflowSafeScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                        child: _buildLockedState(),
                      )
                    : Padding(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                        child: _buildVaultState(filteredItems),
                      ),
      ),
      floatingActionButton:
          _isUnlocked && _hasPin && MediaQuery.viewInsetsOf(context).bottom == 0
              ? FloatingActionButton.extended(
                  onPressed: _showAddCredentialSheet,
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.black,
                  icon: const Icon(Icons.add),
                  label: Text(context.tr.t('safe.add_password')),
                )
              : null,
    );
  }

  Widget _buildSetupState() {
    final tr = context.tr;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SafeTopBar(
          title: tr.t('home.safe_title'),
          onBack: () => Navigator.of(context).maybePop(),
          onInfo: widget.onShowAbout,
        ),
        const SizedBox(height: 14),
        _SafeHeroCard(
          title: tr.t('safe.setup_title'),
          description: tr.t('safe.setup_body'),
        ),
        const SizedBox(height: 24),
        _SafeField(
          controller: _setupPinController,
          hintText: tr.t('safe.pin_enter'),
          obscureText: true,
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 14),
        _SafeField(
          controller: _setupConfirmController,
          hintText: tr.t('safe.pin_confirm'),
          obscureText: true,
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 18),
        PrimaryButton(
          label: tr.t('safe.enable'),
          onPressed: _handleSetupPin,
        ),
        if (_setupHint != null) ...[
          const SizedBox(height: 12),
          _SafeInlineNote(
            message: _setupHint!,
            isError: true,
          ),
        ],
      ],
    );
  }

  Widget _buildLockedState() {
    final tr = context.tr;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SafeTopBar(
          title: tr.t('home.safe_title'),
          onBack: () => Navigator.of(context).maybePop(),
          onInfo: widget.onShowAbout,
        ),
        const SizedBox(height: 14),
        _SafeHeroCard(
          title: tr.t('safe.locked_title'),
          description: tr.t('safe.locked_body'),
        ),
        const SizedBox(height: 24),
        if (_deviceAuthAvailable) ...[
          PrimaryButton(
            label: tr.t('safe.unlock_device'),
            onPressed: _handleUnlockWithDevice,
          ),
          const SizedBox(height: 14),
        ],
        _SafeField(
          controller: _pinController,
          hintText: tr.t('safe.pin_unlock'),
          obscureText: true,
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 14),
        OutlineActionButton(
          label: tr.t('safe.pin_unlock_btn'),
          onPressed: _handleUnlockWithPin,
        ),
        if (_unlockHint != null) ...[
          const SizedBox(height: 12),
          _SafeInlineNote(
            message: _unlockHint!,
            isError: true,
          ),
        ],
      ],
    );
  }

  Widget _buildVaultState(List<SafeCredential> filteredItems) {
    final tr = context.tr;
    final reviewCount = _countCredentialsNeedingReview(_items);
    final isSearching = _searchQuery.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SafeTopBar(
          title: tr.t('safe.title_vault'),
          subtitle: formatTemplate(tr.t('safe.count_label'), {
            'n': isSearching ? filteredItems.length : _items.length,
          }),
          onBack: () => Navigator.of(context).maybePop(),
          onInfo: widget.onShowAbout,
          trailing: _GlassIconButton(
            icon: Icons.lock_outline_rounded,
            onTap: () {
              widget.onLock();
              setState(() {
                _isUnlocked = false;
                _unlockHint = null;
              });
            },
          ),
        ),
        const SizedBox(height: 12),
        _SafeSearchField(
          controller: _searchController,
          onChanged: (value) {
            setState(() => _searchQuery = value);
          },
          onClear: () {
            _searchController.clear();
            setState(() => _searchQuery = '');
          },
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _SafeMetaPill(
              icon: Icons.key_rounded,
              label: formatTemplate(tr.t('safe.count_label'), {
                'n': _items.length,
              }),
            ),
            if (reviewCount > 0)
              _SafeMetaPill(
                icon: Icons.priority_high_rounded,
                label: '$reviewCount',
                color: AppColors.warning,
              ),
          ],
        ),
        if (isSearching && filteredItems.isEmpty) ...[
          const SizedBox(height: 10),
          Text(
            tr.t('safe.search_no_results'),
            style: const TextStyle(
              color: AppColors.description,
              fontSize: 13,
            ),
          ),
        ],
        const SizedBox(height: 12),
        Expanded(
          child: filteredItems.isEmpty
              ? EmptyVaultState(
                  icon: isSearching
                      ? Icons.search_off_rounded
                      : Icons.lock_outline_rounded,
                  title: isSearching
                      ? tr.t('safe.search_no_results')
                      : tr.t('safe.empty_title'),
                  description: tr.t('safe.empty_desc'),
                )
              : ListView.builder(
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  itemCount: filteredItems.length,
                  itemBuilder: (context, index) {
                    final item = filteredItems[index];
                    return SafeCredentialTile(
                      item: item,
                      needsAttention: _isCredentialNeedingReview(
                        item,
                        allItems: _items,
                      ),
                      onTap: () => _showCredentialDetails(item),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _showAddCredentialSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.secondarySurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (context) {
        return _AddCredentialSheet(
          onAddItem: (item) async {
            await widget.onAddItem(item);
            if (!mounted) return;
            setState(() => _items = [item, ..._items]);
          },
          onCopyValue: widget.onCopyValue,
        );
      },
    );
  }

  void _showCredentialDetails(SafeCredential item) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.secondarySurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return _SafeCredentialSheet(
          item: item,
          onCopyValue: widget.onCopyValue,
          onDelete: () async {
            Navigator.of(context).pop();
            await widget.onDeleteItem(item);
            if (!mounted) return;
            setState(() {
              _items = _items.where((value) => value.id != item.id).toList();
            });
          },
        );
      },
    );
  }

  Future<void> _handleSetupPin() async {
    final pin = _setupPinController.text.trim();
    final confirmation = _setupConfirmController.text.trim();

    if (pin.length < 4 || pin != confirmation) {
      setState(() {
        _setupHint =
            'PIN kamida 4 xonali bo\'lsin va ikkalasi bir xil kiritilsin.';
      });
      return;
    }

    await widget.onSetPin(pin);
    if (!mounted) return;
    setState(() {
      _hasPin = true;
      _isUnlocked = true;
      _setupHint = null;
    });
    _setupPinController.clear();
    _setupConfirmController.clear();
  }

  Future<void> _handleUnlockWithPin() async {
    final unlocked = await widget.onUnlockWithPin(_pinController.text);
    if (!mounted) return;

    if (unlocked) {
      setState(() {
        _isUnlocked = true;
        _unlockHint = null;
      });
      _pinController.clear();
      return;
    }

    setState(() {
      _unlockHint = 'PIN noto\'g\'ri kiritildi. Qayta urinib ko\'ring.';
    });
  }

  Future<void> _handleUnlockWithDevice() async {
    final unlocked = await widget.onUnlockWithDevice();
    if (!mounted) return;

    if (unlocked) {
      setState(() {
        _isUnlocked = true;
        _unlockHint = null;
      });
      _pinController.clear();
      return;
    }

    setState(() {
      _unlockHint = context.tr.t('safe.device_unlock_failed');
    });
  }
}

enum _PasswordStrengthLevel { weak, okay, strong }

bool _safeItemMatchesQuery(SafeCredential item, String query) {
  final buffer = StringBuffer()
    ..write(item.site)
    ..write(' ')
    ..write(item.username)
    ..write(' ')
    ..write(item.category.label)
    ..write(' ')
    ..write(item.website ?? '')
    ..write(' ')
    ..write(item.note ?? '');

  return buffer.toString().toLowerCase().contains(query);
}

int _passwordStrengthScore(String value) {
  final password = value.trim();
  if (password.isEmpty) return 0;

  var score = 0;
  if (password.length >= 12) score++;
  if (password.length >= 16) score++;
  if (RegExp(r'[A-Z]').hasMatch(password)) score++;
  if (RegExp(r'[a-z]').hasMatch(password)) score++;
  if (RegExp(r'[0-9]').hasMatch(password)) score++;
  if (RegExp(r'[^A-Za-z0-9]').hasMatch(password)) score++;

  final lower = password.toLowerCase();
  const riskyPatterns = <String>[
    'password',
    'parol',
    'qwerty',
    '123456',
    'asdf',
    'admin',
  ];
  final hasRiskyPattern = riskyPatterns.any(lower.contains) ||
      RegExp(r'(.)\1{2,}').hasMatch(password) ||
      RegExp(r'0123|1234|2345|3456|abcd|bcde|cdef').hasMatch(lower);

  if (hasRiskyPattern) {
    score -= 2;
  }

  return score.clamp(0, 6);
}

_PasswordStrengthLevel _passwordStrengthLevel(String value) {
  final score = _passwordStrengthScore(value);
  if (score <= 2) return _PasswordStrengthLevel.weak;
  if (score <= 4) return _PasswordStrengthLevel.okay;
  return _PasswordStrengthLevel.strong;
}

String _passwordStrengthLabel(BuildContext context, String value) {
  final tr = context.tr;
  return switch (_passwordStrengthLevel(value)) {
    _PasswordStrengthLevel.weak => tr.t('safe.strength_weak'),
    _PasswordStrengthLevel.okay => tr.t('safe.strength_okay'),
    _PasswordStrengthLevel.strong => tr.t('safe.strength_strong'),
  };
}

Color _passwordStrengthColor(String value) {
  return switch (_passwordStrengthLevel(value)) {
    _PasswordStrengthLevel.weak => AppColors.danger,
    _PasswordStrengthLevel.okay => AppColors.warning,
    _PasswordStrengthLevel.strong => AppColors.accent,
  };
}

double _passwordStrengthProgress(String value) {
  return (_passwordStrengthScore(value) / 6).clamp(0, 1);
}

bool _isCredentialNeedingReview(
  SafeCredential item, {
  required List<SafeCredential> allItems,
}) {
  final password = item.password.trim();
  if (password.isEmpty) return true;

  final reusedCount =
      allItems.where((other) => other.password.trim() == password).length;
  return reusedCount > 1 ||
      _passwordStrengthLevel(password) != _PasswordStrengthLevel.strong;
}

int _countCredentialsNeedingReview(List<SafeCredential> items) {
  return items
      .where(
        (item) => _isCredentialNeedingReview(item, allItems: items),
      )
      .length;
}

SafeCategory _suggestSafeCategory({
  required String site,
  String? website,
}) {
  final source = '${site.toLowerCase()} ${website?.toLowerCase() ?? ''}';
  if (RegExp(
    r'bank|click|payme|visa|master|kapital|uzum|card|wallet',
  ).hasMatch(source)) {
    return SafeCategory.banking;
  }
  if (RegExp(
    r'mail|gmail|outlook|yahoo|proton|icloud',
  ).hasMatch(source)) {
    return SafeCategory.email;
  }
  if (RegExp(
    r'telegram|instagram|facebook|tiktok|twitter|x\.com|whatsapp|snapchat',
  ).hasMatch(source)) {
    return SafeCategory.social;
  }
  if (RegExp(
    r'jira|slack|github|gitlab|notion|asana|office|workspace|company|work',
  ).hasMatch(source)) {
    return SafeCategory.work;
  }
  return SafeCategory.other;
}

String _generateSafePassword(
  int length, {
  required bool useUppercase,
  required bool useNumbers,
  required bool useSymbols,
}) {
  const lowercase = 'abcdefghijkmnopqrstuvwxyz';
  const uppercase = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  const numbers = '23456789';
  const symbols = '@#%!?=+-_';

  final buffer = StringBuffer(lowercase);
  if (useUppercase) {
    buffer.write(uppercase);
  }
  if (useNumbers) {
    buffer.write(numbers);
  }
  if (useSymbols) {
    buffer.write(symbols);
  }

  final characters = buffer.toString();
  final random = Random.secure();
  return List.generate(
    length,
    (_) => characters[random.nextInt(characters.length)],
  ).join();
}

class _AddCredentialSheet extends StatefulWidget {
  const _AddCredentialSheet({
    required this.onAddItem,
    required this.onCopyValue,
  });

  final Future<void> Function(SafeCredential item) onAddItem;
  final Future<void> Function(String label, String value) onCopyValue;

  @override
  State<_AddCredentialSheet> createState() => _AddCredentialSheetState();
}

class _AddCredentialSheetState extends State<_AddCredentialSheet> {
  final TextEditingController _siteController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();

  double _length = 16;
  bool _useUppercase = true;
  bool _useNumbers = true;
  bool _useSymbols = true;
  bool _showAdvanced = false;
  bool _categoryLockedByUser = false;
  bool _isSaving = false;
  SafeCategory _category = SafeCategory.other;

  @override
  void initState() {
    super.initState();
    _siteController.addListener(_handleCategorySuggestion);
    _passwordController.addListener(_refresh);
    _generatePassword();
  }

  @override
  void dispose() {
    _siteController
      ..removeListener(_handleCategorySuggestion)
      ..dispose();
    _usernameController.dispose();
    _passwordController
      ..removeListener(_refresh)
      ..dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  void _handleCategorySuggestion() {
    if (_categoryLockedByUser) return;
    final suggested = _suggestSafeCategory(
      site: _siteController.text,
      website: null,
    );
    if (_category != suggested && mounted) {
      setState(() => _category = suggested);
    }
  }

  void _generatePassword() {
    final value = _generateSafePassword(
      _length.round(),
      useUppercase: _useUppercase,
      useNumbers: _useNumbers,
      useSymbols: _useSymbols,
    );
    _passwordController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  void _showMessage(String message, {bool isError = true}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..hideCurrentMaterialBanner()
      ..showSnackBar(
        _buildPosbonSnackBar(context, message, isError: isError),
      );
  }

  Future<void> _submit() async {
    if (_isSaving) return;

    final site = _siteController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();
    final note = _noteController.text.trim();

    if (site.isEmpty || password.isEmpty) {
      _showMessage(context.tr.t('safe.required_missing'));
      return;
    }

    setState(() => _isSaving = true);
    final item = SafeCredential(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      site: site,
      username: username,
      password: password,
      category: _category,
      website: null,
      note: note.isEmpty ? null : note,
      createdAt: DateTime.now(),
    );

    try {
      await widget.onAddItem(item);
      if (!mounted) return;
      Navigator.of(context).pop();
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final password = _passwordController.text.trim();
    final strengthLabel = _passwordStrengthLabel(context, password);
    final strengthColor = _passwordStrengthColor(password);
    final strengthValue = _passwordStrengthProgress(password);

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.description.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1A3A35), Color(0xFF102520)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: AppColors.outline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.10),
                            ),
                          ),
                          child: const Icon(
                            Icons.password_rounded,
                            color: AppColors.accent,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tr.t('safe.new_login'),
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                tr.t('safe.new_credential_hint'),
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.72),
                                  fontSize: 13,
                                  height: 1.45,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _SheetInfoPill(
                          icon: Icons.auto_awesome_rounded,
                          label: tr.t('safe.has_generator'),
                        ),
                        _SheetInfoPill(
                          icon: Icons.info_outline_rounded,
                          label: tr.t('safe.extra_fields_opt'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _SafeSectionTitle(
                title: tr.t('safe.main_info'),
                description: tr.t('safe.main_info_hint'),
              ),
              const SizedBox(height: 14),
              _FieldLabel(
                title: tr.t('safe.field_name'),
                isRequired: true,
                helper: tr.t('safe.field_name_helper'),
              ),
              const SizedBox(height: 8),
              _SafeField(
                controller: _siteController,
                hintText: tr.t('safe.field_name'),
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),
              _FieldLabel(
                title: tr.t('safe.field_login'),
                helper: tr.t('safe.field_login_helper'),
              ),
              const SizedBox(height: 8),
              _SafeField(
                controller: _usernameController,
                hintText: 'username@gmail.com',
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.username],
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: AppColors.outline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _FieldLabel(
                            title: tr.t('safe.field_password'),
                            isRequired: true,
                            helper: tr.t('safe.field_password_helper'),
                          ),
                        ),
                        Text(
                          strengthLabel,
                          style: TextStyle(
                            color: strengthColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _SafeField(
                      controller: _passwordController,
                      hintText: tr.t('safe.field_password'),
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: strengthValue,
                        minHeight: 8,
                        backgroundColor: AppColors.mutedSurface,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          strengthColor,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      formatTemplate(tr.t('safe.generator_length'), {
                        'n': _length.round(),
                      }),
                      style: const TextStyle(fontSize: 13),
                    ),
                    Slider(
                      value: _length,
                      min: 10,
                      max: 28,
                      divisions: 18,
                      activeColor: AppColors.accent,
                      onChanged: (value) {
                        setState(() => _length = value);
                      },
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: _GeneratorToggle(
                            label: 'A-Z',
                            selected: _useUppercase,
                            onTap: () {
                              setState(() => _useUppercase = !_useUppercase);
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _GeneratorToggle(
                            label: '0-9',
                            selected: _useNumbers,
                            onTap: () {
                              setState(() => _useNumbers = !_useNumbers);
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _GeneratorToggle(
                            label: '@#%',
                            selected: _useSymbols,
                            onTap: () {
                              setState(() => _useSymbols = !_useSymbols);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlineActionButton(
                            label: tr.t('safe.copy'),
                            onPressed: () async {
                              final value = _passwordController.text.trim();
                              if (value.isEmpty) return;
                              await widget.onCopyValue(
                                tr.t('safe.password'),
                                value,
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(54),
                              backgroundColor: AppColors.accent,
                              foregroundColor: Colors.black,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: _generatePassword,
                            child: Text(
                              tr.t('safe.new_password_btn'),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              InkWell(
                onTap: () {
                  setState(() => _showAdvanced = !_showAdvanced);
                },
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.outline),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tr.t('safe.extra_fields'),
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              tr.t('safe.extra_fields_hint'),
                              style: const TextStyle(
                                color: AppColors.description,
                                fontSize: 13,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        _showAdvanced
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: AppColors.description,
                      ),
                    ],
                  ),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                child: _showAdvanced
                    ? Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _FieldLabel(
                              title: tr.t('safe.category'),
                              helper: tr.t('safe.category_helper'),
                            ),
                            const SizedBox(height: 8),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              child: Row(
                                children: SafeCategory.values
                                    .map(
                                      (value) => _CategoryChip(
                                        label: value.label,
                                        selected: _category == value,
                                        onTap: () {
                                          setState(() {
                                            _categoryLockedByUser = true;
                                            _category = value;
                                          });
                                        },
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                            const SizedBox(height: 16),
                            _FieldLabel(
                              title: tr.t('safe.field_note'),
                              helper: tr.t('safe.field_note_helper'),
                            ),
                            const SizedBox(height: 8),
                            _SafeField(
                              controller: _noteController,
                              hintText: tr.t('safe.note'),
                              maxLines: 3,
                              textCapitalization: TextCapitalization.sentences,
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(height: 20),
              PrimaryButton(
                label: _isSaving
                    ? tr.t('safe.saving')
                    : tr.t('safe.save'),
                onPressed: _isSaving ? () {} : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({
    required this.title,
    this.helper,
    this.isRequired = false,
  });

  final String title;
  final String? helper;
  final bool isRequired;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (isRequired) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  context.tr.t('safe.required_badge'),
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
        if (helper != null) ...[
          const SizedBox(height: 4),
          Text(
            helper!,
            style: const TextStyle(
              color: AppColors.description,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ],
    );
  }
}

class _SafeSectionTitle extends StatelessWidget {
  const _SafeSectionTitle({
    required this.title,
    required this.description,
  });

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: const TextStyle(
            color: AppColors.description,
            fontSize: 13,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

class _SheetInfoPill extends StatelessWidget {
  const _SheetInfoPill({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.accent),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SafeTopBar extends StatelessWidget {
  const _SafeTopBar({
    required this.title,
    required this.onBack,
    required this.onInfo,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final VoidCallback onBack;
  final VoidCallback onInfo;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _GlassIconButton(
          icon: Icons.arrow_back_ios_new_rounded,
          onTap: onBack,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      color: AppColors.description,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (trailing != null) ...[
          trailing!,
          const SizedBox(width: 8),
        ],
        _GlassIconButton(
          icon: Icons.info_outline_rounded,
          onTap: onInfo,
        ),
      ],
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.outline),
          ),
          child: Icon(icon, color: Colors.white),
        ),
      ),
    );
  }
}

class _SafeMetaPill extends StatelessWidget {
  const _SafeMetaPill({
    required this.icon,
    required this.label,
    this.color = AppColors.accent,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SafeInlineNote extends StatelessWidget {
  const _SafeInlineNote({
    required this.message,
    this.isError = false,
  });

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError ? AppColors.danger : AppColors.accent;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error_outline_rounded : Icons.info_outline_rounded,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: color,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SafeSearchField extends StatelessWidget {
  const _SafeSearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: const TextStyle(color: Colors.white),
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: context.tr.t('safe.search_placeholder'),
        hintStyle: const TextStyle(color: AppColors.description),
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        prefixIcon: const Icon(
          Icons.search_rounded,
          color: AppColors.description,
        ),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                onPressed: onClear,
                icon: const Icon(
                  Icons.close_rounded,
                  color: AppColors.description,
                ),
              ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.accent),
        ),
      ),
    );
  }
}

class OverflowSafeScrollView extends StatelessWidget {
  const OverflowSafeScrollView({
    required this.child,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: padding,
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: constraints.maxWidth,
              minHeight: constraints.maxHeight,
            ),
            child: child,
          ),
        );
      },
    );
  }
}

class PosbonBottomNav extends StatelessWidget {
  const PosbonBottomNav({
    required this.currentTab,
    required this.onSelected,
    super.key,
  });

  final DashboardTab currentTab;
  final ValueChanged<DashboardTab> onSelected;

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final selectedTab =
        currentTab == DashboardTab.files ? DashboardTab.home : currentTab;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.secondarySurface.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.06),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: _NavItem(
                    icon: Icons.home_rounded,
                    label: tr.t('nav.home'),
                    selected: selectedTab == DashboardTab.home,
                    onTap: () => onSelected(DashboardTab.home),
                  ),
                ),
                Expanded(
                  child: _NavItem(
                    icon: Icons.apps_rounded,
                    label: tr.t('nav.apps'),
                    selected: selectedTab == DashboardTab.apps,
                    onTap: () => onSelected(DashboardTab.apps),
                  ),
                ),
                Expanded(
                  child: _NavItem(
                    icon: Icons.history_rounded,
                    label: tr.t('nav.results'),
                    selected: selectedTab == DashboardTab.history,
                    onTap: () => onSelected(DashboardTab.history),
                  ),
                ),
                Expanded(
                  child: _NavItem(
                    icon: Icons.settings_rounded,
                    label: tr.t('nav.settings'),
                    selected: selectedTab == DashboardTab.settings,
                    onTap: () => onSelected(DashboardTab.settings),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.accent : AppColors.description;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.accent.withValues(alpha: 0.16)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PosbonLogo extends StatelessWidget {
  const PosbonLogo({required this.size, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(color: AppColors.accent, width: 1.8),
      ),
      child: Center(
        child: Image.asset('assets/png/posbon.png', fit: BoxFit.contain),
      ),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    required this.label,
    required this.onPressed,
    super.key,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onPressed: onPressed,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class OutlineActionButton extends StatelessWidget {
  const OutlineActionButton({
    required this.label,
    required this.onPressed,
    this.borderColor = AppColors.accent,
    this.foregroundColor = Colors.white,
    super.key,
  });

  final String label;
  final VoidCallback onPressed;
  final Color borderColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minHeight: 54),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: foregroundColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class PermissionTile extends StatelessWidget {
  const PermissionTile({required this.item, required this.onGrant, super.key});

  final PermissionStatusCard item;
  final VoidCallback onGrant;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: Colors.black,
              border: Border.all(color: AppColors.outline),
            ),
            child: Icon(item.icon, color: AppColors.accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  item.description,
                  style: const TextStyle(
                    color: AppColors.description,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                if (item.statusNote != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    item.statusNote!,
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          item.granted
              ? Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.check, color: Colors.black),
                )
                  : item.actionable
                      ? SizedBox(
                          width: 110,
                          child: OutlineActionButton(
                            label: context.tr.t('permissions.grant'),
                            onPressed: onGrant,
                          ),
                        )
                  : const SizedBox.shrink(),
        ],
      ),
    );
  }
}

class StatCard extends StatelessWidget {
  const StatCard({
    required this.label,
    required this.value,
    this.color,
    this.onTap,
    super.key,
  });

  final String label;
  final String value;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? AppColors.accent;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                accent.withValues(alpha: 0.18),
                const Color(0xFF0E1E1A),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: accent.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  color: accent,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.description,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeHeroCard extends StatelessWidget {
  const _HomeHeroCard({
    required this.findings,
    required this.onStartScan,
    required this.scanning,
  });

  final List<ScanFinding> findings;
  final VoidCallback onStartScan;
  final bool scanning;

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final findingLabel = findings.isEmpty
        ? tr.t('home.no_results')
        : formatTemplate(tr.t('home.results_count'), {'n': findings.length});

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A3A35), Color(0xFF0C1D1A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _SafeMetaPill(
                icon: Icons.shield_outlined,
                label: tr.t('home.pill_main_scan'),
              ),
              _SafeMetaPill(
                icon: Icons.analytics_outlined,
                label: findingLabel,
                color: AppColors.description,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            tr.t('home.scan_cta_title'),
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            findings.isEmpty
                ? tr.t('home.scan_cta_body_empty')
                : tr.t('home.scan_cta_body_done'),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.74),
              fontSize: 13,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          _ScanLaunchButton(onTap: onStartScan, scanning: scanning),
        ],
      ),
    );
  }
}

class _ScanLaunchButton extends StatelessWidget {
  const _ScanLaunchButton({required this.onTap, required this.scanning});

  final VoidCallback onTap;
  final bool scanning;

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 64,
                height: 64,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (scanning)
                      RadarSweep(size: 64, color: AppColors.accent),
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.accent.withValues(alpha: 0.12),
                        border: Border.all(
                          color: AppColors.accent.withValues(alpha: 0.5),
                          width: 1.4,
                        ),
                      ),
                      child: const Center(child: PosbonLogo(size: 30)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      scanning
                          ? tr.t('home.scanning_now')
                          : tr.t('home.scan_launch'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      scanning
                          ? tr.t('scan.background_on')
                          : tr.t('home.scan_launch_sub'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.description,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  scanning
                      ? Icons.stop_rounded
                      : Icons.arrow_forward_rounded,
                  color: Colors.black,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class QuickActionCard extends StatelessWidget {
  const QuickActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    super.key,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF132723), Color(0xFF0D1C19)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.outline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(icon, color: AppColors.accent, size: 24),
                  ),
                  const Spacer(),
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.arrow_forward_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppColors.description,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SummaryCard extends StatelessWidget {
  const SummaryCard({
    required this.title,
    required this.value,
    required this.color,
    super.key,
  });

  final String title;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 92),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.description, fontSize: 12),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class FindingTile extends StatelessWidget {
  const FindingTile({
    required this.finding,
    required this.onDeleteFinding,
    super.key,
  });

  final ScanFinding finding;
  final Future<void> Function(ScanFinding finding) onDeleteFinding;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _showFindingDetails(context),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.outline),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Row(
            children: [
              Container(width: 4, color: finding.risk.color),
              Expanded(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  leading: Icon(
                    finding.type == ScanTargetType.app
                        ? Icons.apps_rounded
                        : Icons.insert_drive_file_rounded,
                    color: AppColors.accent,
                  ),
                  title: Text(
                    finding.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    finding.details,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.description),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RiskBadge(level: finding.risk),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.description,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFindingDetails(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.secondarySurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => FindingDetailsSheet(
        finding: finding,
        onDeleteFinding: onDeleteFinding,
      ),
    );
  }
}

class FindingDetailsSheet extends StatelessWidget {
  const FindingDetailsSheet({
    required this.finding,
    required this.onDeleteFinding,
    super.key,
  });

  final ScanFinding finding;
  final Future<void> Function(ScanFinding finding) onDeleteFinding;

  @override
  Widget build(BuildContext context) {
    final reasons =
        finding.reasons.isEmpty ? <String>[finding.details] : finding.reasons;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.description.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      finding.name,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  RiskBadge(level: finding.risk),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                finding.details,
                style: const TextStyle(
                  color: AppColors.description,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              if (finding.location != null) ...[
                const SizedBox(height: 18),
                _FindingMetaCard(
                  label: context.tr.t('results.location'),
                  value: finding.location!,
                ),
              ],
              const SizedBox(height: 18),
              Text(
                context.tr.t('results.reasons'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              ...reasons.map(
                (reason) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(top: 7),
                        decoration: BoxDecoration(
                          color: finding.risk.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          reason,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (finding.type == ScanTargetType.file &&
                  finding.location != null) ...[
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: OutlineActionButton(
                    label: context.tr.t('results.delete_file'),
                    borderColor: AppColors.danger,
                    foregroundColor: AppColors.danger,
                    onPressed: () async {
                      Navigator.of(context).pop();
                      await onDeleteFinding(finding);
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FindingMetaCard extends StatelessWidget {
  const _FindingMetaCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppColors.description, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 14, height: 1.4)),
        ],
      ),
    );
  }
}

class _VirusTotalStatusCard extends StatelessWidget {
  const _VirusTotalStatusCard({required this.app});

  final ProtectedApp app;

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final isDanger = app.virusTotalDetections > 0;
    final borderColor = isDanger ? AppColors.danger : AppColors.outline;
    final backgroundColor =
        isDanger ? AppColors.danger.withValues(alpha: 0.10) : AppColors.surface;
    final title = isDanger
        ? tr.t('results.vt_dangerous')
        : app.vtScanned
            ? tr.t('results.vt_clean')
            : tr.t('results.vt_not_scanned');

    final subtitle = isDanger
        ? app.virusTotalThreatLabel != null &&
                app.virusTotalThreatLabel!.isNotEmpty
            ? app.virusTotalThreatLabel!
            : '${app.virusTotalDetections}'
        : app.virusTotalNote ?? '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: isDanger ? AppColors.danger : Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(
              color: AppColors.description,
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class EmptyFilesState extends StatelessWidget {
  const EmptyFilesState({super.key});

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.download_for_offline_outlined,
            color: AppColors.accent,
            size: 54,
          ),
          const SizedBox(height: 16),
          Text(
            tr.t('files.empty_download'),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            tr.t('files.subtitle_no_perm_long'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.description,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class DownloadFileTile extends StatelessWidget {
  const DownloadFileTile({required this.file, required this.onTap, super.key});

  final File file;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final exists = _fileExists(file);
    final lastModified = exists
        ? (_tryLastModified(file) ?? DateTime.fromMillisecondsSinceEpoch(0))
        : DateTime.fromMillisecondsSinceEpoch(0);
    final fileSize = exists ? _tryFileLength(file) : null;
    final tr = context.tr;
    final sizeLabel = exists
        ? fileSize == null
            ? tr.t('files.size_unknown')
            : _formatFileSize(fileSize)
        : tr.t('files.moved');

    return InkWell(
      onTap: exists ? onTap : null,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.outline),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.outline),
              ),
              child: const Icon(
                Icons.android_rounded,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.uri.pathSegments.last,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${_formatShortDate(lastModified)}  •  $sizeLabel',
                    style: const TextStyle(
                      color: AppColors.description,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    file.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.description,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              exists ? Icons.chevron_right_rounded : Icons.info_outline_rounded,
              color: exists ? AppColors.description : AppColors.warning,
            ),
          ],
        ),
      ),
    );
  }
}

class _SafeHeroCard extends StatelessWidget {
  const _SafeHeroCard({
    required this.title,
    required this.description,
  });

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF173730), Color(0xFF0F221E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const PosbonLogo(size: 44),
              const SizedBox(width: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.lock_outline_rounded,
                      color: AppColors.accent,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      context.tr.t('safe.protected_badge'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.76),
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _SafeField extends StatefulWidget {
  const _SafeField({
    required this.controller,
    required this.hintText,
    this.obscureText = false,
    this.keyboardType,
    this.maxLines = 1,
    this.autofillHints,
    this.textCapitalization = TextCapitalization.none,
    this.textInputAction,
  });

  final TextEditingController controller;
  final String hintText;
  final bool obscureText;
  final TextInputType? keyboardType;
  final int maxLines;
  final Iterable<String>? autofillHints;
  final TextCapitalization textCapitalization;
  final TextInputAction? textInputAction;

  @override
  State<_SafeField> createState() => _SafeFieldState();
}

class _SafeFieldState extends State<_SafeField> {
  late bool _obscureText = widget.obscureText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: _obscureText,
      keyboardType: widget.keyboardType,
      maxLines: widget.obscureText ? 1 : widget.maxLines,
      autofillHints: widget.autofillHints,
      textCapitalization: widget.textCapitalization,
      textInputAction: widget.textInputAction,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: widget.hintText,
        hintStyle: const TextStyle(color: AppColors.description),
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.accent),
        ),
        suffixIcon: widget.obscureText
            ? IconButton(
                onPressed: () {
                  setState(() => _obscureText = !_obscureText);
                },
                icon: Icon(
                  _obscureText
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: AppColors.description,
                ),
              )
            : null,
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.accent
                : AppColors.mutedSurface.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.outline,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.black : Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _GeneratorToggle extends StatelessWidget {
  const _GeneratorToggle({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accent.withValues(alpha: 0.14)
              : AppColors.mutedSurface.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.outline,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              selected ? Icons.check_box : Icons.check_box_outline_blank,
              color: selected ? AppColors.accent : AppColors.description,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class EmptyVaultState extends StatelessWidget {
  const EmptyVaultState({
    this.icon = Icons.lock_outline_rounded,
    this.title = 'Posbon Safe bo\'sh',
    this.description =
        'Gmail, bank yoki boshqa muhim loginlarni shu yerda saqlashingiz mumkin.',
    super.key,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.accent, size: 52),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.description, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class SafeCredentialTile extends StatelessWidget {
  const SafeCredentialTile(
      {required this.item,
      required this.onTap,
      this.needsAttention = false,
      super.key});

  final SafeCredential item;
  final VoidCallback onTap;
  final bool needsAttention;

  @override
  Widget build(BuildContext context) {
    final subtitle = item.username.isNotEmpty
        ? item.username
        : (item.website?.isNotEmpty ?? false)
            ? item.website!
            : context.tr.t('safe.login_none');

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF132723), Color(0xFF0D1C19)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: needsAttention ? AppColors.warning : AppColors.outline,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.outline),
              ),
              child: Icon(item.category.icon, color: AppColors.accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.site,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (needsAttention)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.warning.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            context.tr.t('app_detail.checking'),
                            style: const TextStyle(
                              color: AppColors.warning,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.description,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _SafeMetaPill(
                        icon: item.category.icon,
                        label: item.category.label,
                        color: AppColors.description,
                      ),
                      if (item.website != null && item.website!.isNotEmpty)
                        _SafeMetaPill(
                          icon: Icons.language_rounded,
                          label: item.website!,
                          color: AppColors.accent,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.description,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SafeCredentialSheet extends StatefulWidget {
  const _SafeCredentialSheet({
    required this.item,
    required this.onCopyValue,
    required this.onDelete,
  });

  final SafeCredential item;
  final Future<void> Function(String label, String value) onCopyValue;
  final Future<void> Function() onDelete;

  @override
  State<_SafeCredentialSheet> createState() => _SafeCredentialSheetState();
}

class _SafeCredentialSheetState extends State<_SafeCredentialSheet> {
  bool _showPassword = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.description.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.site,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      item.category.label,
                      style: const TextStyle(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _DetailRow(
                label: context.tr.t('safe.login'),
                value: item.username.isEmpty
                    ? context.tr.t('safe.login_not_set')
                    : item.username,
                onCopy: item.username.isEmpty
                    ? null
                    : () => widget.onCopyValue(
                          context.tr.t('safe.login'),
                          item.username,
                        ),
              ),
              const SizedBox(height: 12),
              _DetailRow(
                label: context.tr.t('safe.password'),
                value:
                    _showPassword ? item.password : '•' * item.password.length,
                trailing: IconButton(
                  onPressed: () {
                    setState(() => _showPassword = !_showPassword);
                  },
                  icon: Icon(
                    _showPassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: AppColors.description,
                  ),
                ),
                onCopy: () => widget.onCopyValue(
                  context.tr.t('safe.password'),
                  item.password,
                ),
              ),
              if (item.note != null && item.note!.isNotEmpty) ...[
                const SizedBox(height: 12),
                _FindingMetaCard(
                  label: context.tr.t('safe.note'),
                  value: item.note!,
                ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: OutlineActionButton(
                  label: context.tr.t('safe.delete_entry'),
                  borderColor: AppColors.danger,
                  foregroundColor: AppColors.danger,
                  onPressed: widget.onDelete,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.onCopy,
    this.trailing,
  });

  final String label;
  final String value;
  final Future<void> Function()? onCopy;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.description,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                Text(value, style: const TextStyle(fontSize: 14)),
              ],
            ),
          ),
          if (onCopy != null)
            IconButton(
              onPressed: onCopy,
              icon: const Icon(Icons.copy_rounded, color: AppColors.accent),
            ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _AboutLine extends StatelessWidget {
  const _AboutLine({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.outline),
            ),
            child: Icon(icon, color: AppColors.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    color: AppColors.description,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class EmptySafeState extends StatelessWidget {
  const EmptySafeState({super.key});

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const PosbonLogo(size: 74),
          const SizedBox(height: 18),
          Text(
            tr.t('results.empty_title'),
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            tr.t('results.empty_desc'),
            style: const TextStyle(
              color: AppColors.description,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class AppListTile extends StatelessWidget {
  const AppListTile({required this.app, required this.onTap, super.key});

  final ProtectedApp app;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.outline),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.black,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.outline),
              ),
              child: app.iconBytes != null
                  ? ClipOval(
                      child: Image.memory(app.iconBytes!, fit: BoxFit.cover),
                    )
                  : Icon(
                      app.icon ?? Icons.android_rounded,
                      color: AppColors.accent,
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    app.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    app.version,
                    style: const TextStyle(
                      color: AppColors.description,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            RiskBadge(level: app.risk),
          ],
        ),
      ),
    );
  }
}

class InfoCard extends StatelessWidget {
  const InfoCard({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppColors.description, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

SnackBar _buildPosbonSnackBar(
  BuildContext context,
  String message, {
  bool isError = false,
}) {
  final bottomPadding = MediaQuery.maybeOf(context)?.padding.bottom ?? 0;

  return SnackBar(
    behavior: SnackBarBehavior.floating,
    backgroundColor: Colors.white,
    elevation: 10,
    dismissDirection: DismissDirection.horizontal,
    duration: const Duration(seconds: 4),
    margin: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomPadding),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    content: Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: (isError ? AppColors.danger : AppColors.accent)
                .withValues(alpha: 0.14),
            shape: BoxShape.circle,
          ),
          child: Icon(
            isError ? Icons.error_outline_rounded : Icons.check_circle_rounded,
            color: isError ? AppColors.danger : AppColors.accent,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(
              color: Colors.black87,
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ),
      ],
    ),
  );
}

bool _fileExists(File file) {
  try {
    return file.existsSync();
  } on FileSystemException {
    return false;
  }
}

DateTime? _tryLastModified(File file) {
  try {
    return file.lastModifiedSync();
  } on FileSystemException {
    return null;
  }
}

int? _tryFileLength(File file) {
  try {
    return file.lengthSync();
  } on FileSystemException {
    return null;
  }
}

String _formatShortDate(DateTime value) {
  if (value.year <= 1970) {
    return '—';
  }
  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  return '$day.$month.${value.year}';
}

String _formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
  final mb = kb / 1024;
  return '${mb.toStringAsFixed(1)} MB';
}

class RiskBadge extends StatelessWidget {
  const RiskBadge({required this.level, super.key});

  final RiskLevel level;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: level.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: level.color),
      ),
      child: Text(
        level.label,
        style: TextStyle(
          color: level.color,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}
