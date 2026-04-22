import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/app_locale.dart';
import '../models/security_models.dart';
import 'native_package_service.dart';

class PermissionRequestFeedback {
  const PermissionRequestFeedback({
    required this.changed,
    required this.message,
  });

  final bool changed;
  final String message;
}

class PermissionsService {
  PermissionsService({required NativePackageService nativePackageService})
      : _nativePackageService = nativePackageService;

  final NativePackageService _nativePackageService;

  Future<List<PermissionStatusCard>> loadStatuses(AppStrings tr) async {
    final device = await _nativePackageService.getDeviceInfo();
    final notifications = await Permission.notification.status;
    final fileManager = await _storagePermission(device.sdkInt).status;
    final mediaPermission = await _mediaPermission(device.sdkInt).status;
    final battery = await Permission.ignoreBatteryOptimizations.status;
    final installPackages = await Permission.requestInstallPackages.status;

    return [
      PermissionStatusCard(
        id: PermissionCardId.notifications,
        icon: Icons.notifications_none_rounded,
        title: tr.t('perm.notifications.title'),
        description: tr.t('perm.notifications.desc'),
        granted: notifications.isGranted,
      ),
      PermissionStatusCard(
        id: PermissionCardId.fileManager,
        icon: Icons.folder_open_rounded,
        title: tr.t('perm.files.title'),
        description: tr.t('perm.files.desc'),
        granted: fileManager.isGranted,
        statusNote: device.sdkInt >= 30
            ? formatTemplate(
                tr.t('perm.files.note_wide'),
                {'sdk': device.sdkInt},
              )
            : formatTemplate(
                tr.t('perm.files.note_std'),
                {'sdk': device.sdkInt},
              ),
      ),
      PermissionStatusCard(
        id: PermissionCardId.mediaFiles,
        icon: Icons.photo_library_outlined,
        title: tr.t('perm.media.title'),
        description: tr.t('perm.media.desc'),
        granted: mediaPermission.isGranted,
        statusNote: device.sdkInt >= 33
            ? tr.t('perm.media.note_new')
            : tr.t('perm.media.note_old'),
      ),
      PermissionStatusCard(
        id: PermissionCardId.monitoring,
        icon: Icons.settings_outlined,
        title: tr.t('perm.monitoring.title'),
        description: tr.t('perm.monitoring.desc'),
        granted: battery.isGranted,
      ),
      PermissionStatusCard(
        id: PermissionCardId.appScanning,
        icon: Icons.security_rounded,
        title: tr.t('perm.apps.title'),
        description: tr.t('perm.apps.desc'),
        granted: Platform.isAndroid,
        actionable: false,
        statusNote: tr.t('perm.apps.note'),
      ),
      PermissionStatusCard(
        id: PermissionCardId.safeInstall,
        icon: Icons.download_done_rounded,
        title: tr.t('perm.install.title'),
        description: tr.t('perm.install.desc'),
        granted: installPackages.isGranted,
      ),
    ];
  }

  Future<PermissionRequestFeedback> request(
    PermissionCardId id,
    AppStrings tr,
  ) async {
    final device = await _nativePackageService.getDeviceInfo();

    switch (id) {
      case PermissionCardId.notifications:
        final status = await Permission.notification.request();
        return PermissionRequestFeedback(
          changed: status.isGranted,
          message: status.isGranted
              ? tr.t('perm.notifications.granted')
              : tr.t('perm.notifications.denied'),
        );
      case PermissionCardId.fileManager:
        final permission = _storagePermission(device.sdkInt);
        final status = await permission.request();
        return PermissionRequestFeedback(
          changed: status.isGranted,
          message: status.isGranted
              ? tr.t('perm.files.granted')
              : tr.t('perm.files.denied'),
        );
      case PermissionCardId.mediaFiles:
        final permission = _mediaPermission(device.sdkInt);
        final status = await permission.request();
        return PermissionRequestFeedback(
          changed: status.isGranted,
          message: status.isGranted
              ? tr.t('perm.media.granted')
              : device.sdkInt >= 33
                  ? tr.t('perm.media.denied_new')
                  : tr.t('perm.media.denied_old'),
        );
      case PermissionCardId.monitoring:
        final status = await Permission.ignoreBatteryOptimizations.request();
        return PermissionRequestFeedback(
          changed: status.isGranted,
          message: status.isGranted
              ? tr.t('perm.monitoring.granted')
              : tr.t('perm.monitoring.denied'),
        );
      case PermissionCardId.appScanning:
        return PermissionRequestFeedback(
          changed: false,
          message: tr.t('perm.apps.already'),
        );
      case PermissionCardId.safeInstall:
        final status = await Permission.requestInstallPackages.request();
        return PermissionRequestFeedback(
          changed: status.isGranted,
          message: status.isGranted
              ? tr.t('perm.install.granted')
              : tr.t('perm.install.denied'),
        );
    }
  }

  Permission _storagePermission(int sdkInt) {
    if (sdkInt >= 30) return Permission.manageExternalStorage;
    return Permission.storage;
  }

  Permission _mediaPermission(int sdkInt) {
    if (sdkInt >= 33) return Permission.photos;
    return Permission.storage;
  }
}
