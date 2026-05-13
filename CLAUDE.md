# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
flutter run                      # Run on connected device
flutter build apk                # Release APK
flutter build appbundle          # Release AAB
flutter analyze                  # Lint
flutter test                     # All tests
flutter test test/path/to_test.dart  # Single test
```

## What the App Does

POSBON is an Android security scanner with three core features:
1. **Installed app scanner** — queries manifest permissions, scores risk, and checks file hashes against VirusTotal
2. **APK file scanner** — scans files from Downloads or a file picker
3. **Posbon Safe** — a PIN-protected credential vault (banking, email, social, etc.)

Real-time monitoring is handled by a foreground service (`DownloadWatcherService.kt`) that watches the Downloads folder and alerts users when a new APK appears.

## Architecture

### State Management — Riverpod

All providers are centralized in [lib/src/providers/scan_providers.dart](lib/src/providers/scan_providers.dart). Service instances are singletons managed by providers. The main state holders are:

- `ScanResultsNotifier` (StateNotifier) — scan results list + progress
- `scanProgressProvider` / `scanUpdatesProvider` — StreamProviders fed by service streams
- `vtRateLimitProvider` — countdown stream for VirusTotal's 4-req/min free tier limit

### Services Layer (`lib/src/services/`)

| Service | Role |
|---|---|
| `NativePackageService` | All MethodChannel calls to Android (`uz.posbon/native_packages`) |
| `PermissionAnalyzer` | Scores APK manifest permissions; flags dangerous combos |
| `VirusTotalService` | Hash lookups via Dio (rate-limited to 4/min) |
| `ApkScanEngine` | Orchestrates PermissionAnalyzer + VirusTotalService |
| `AppScanService` | Scans installed apps; maintains a trusted-package allowlist |
| `FileScanService` | Scans APK files from Downloads or file picker |
| `PosbonSafeService` | PIN vault via FlutterSecureStorage (SHA-256 PIN hash) |
| `PermissionsService` | Runtime permission requests |

### Android Native Bridge

`MainActivity.kt` exposes these MethodChannel methods to Flutter:

- `getPackageInfo` / `getRequestedPermissions` — APK introspection
- `getDeviceInfo` — SDK version, Downloads path
- `consumePendingOpenFile` / `consumePendingDestination` — deep link payloads (APK/ZIP SEND/VIEW intents cache the file to app cache dir)
- `showNotification` — high-priority notification posting
- `startDownloadWatcher` / `stopDownloadWatcher` / `isDownloadWatcherRunning` — controls `DownloadWatcherService`
- `canAuthenticateDevice` / `authenticateDevice` — BiometricPrompt

`DownloadWatcherService.kt` is a foreground `dataSync` service using `FileObserver`. It debounces (600 ms) new APK detections, avoids duplicate notifications via SharedPreferences, and sends the file path back to `MainActivity` via a PendingIntent with extras `INCOMING_FILE_PATH` and `destination="incoming_scan"`.

### Core Utilities (`lib/src/core/`)

- **`app_locale.dart`** — localization via `LocaleScope` + `InheritedNotifier`. Access strings with `context.tr`. Supports Uzbek, Russian, English.
- **`settings_controller.dart`** — persists locale, agreement acceptance, and live-monitoring toggle to `FlutterSecureStorage`.
- **`app_constants.dart`** — holds the VirusTotal API key.

### Navigation

App state is driven by an `AppStage` enum (splash → agreement → onboarding → permissions → dashboard → ...) and a `DashboardTab` enum. Deep link destinations (`incoming_scan`, etc.) are consumed from the native side and trigger stage transitions.

### Storage

All persistence (settings, PIN hash, credentials) goes through `FlutterSecureStorage`. There is no local database.

## Key Constraints

- **VirusTotal free tier**: 4 requests/minute — `vtRateLimitProvider` manages the countdown; respect it when adding scan flows.
- **MANAGE_EXTERNAL_STORAGE**: Required for broad file access on Android 11+; granted at runtime via `PermissionsService`.
- **Foreground service**: `DownloadWatcherService` must remain a foreground service (with a persistent notification) to survive background kill on modern Android.
