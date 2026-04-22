import 'dart:async';

import 'package:flutter/services.dart';

class NativePackageInfo {
  const NativePackageInfo({required this.packageName, required this.apkPath});

  final String packageName;
  final String? apkPath;
}

class NativeDeviceInfo {
  const NativeDeviceInfo({required this.sdkInt, required this.downloadsPath});

  final int sdkInt;
  final String? downloadsPath;
}

class NativePackageService {
  NativePackageService() {
    _channel.setMethodCallHandler(_handleNativeCalls);
  }

  static const MethodChannel _channel = MethodChannel(
    'uz.posbon/native_packages',
  );

  final StreamController<String> _incomingFilesController =
      StreamController<String>.broadcast();
  final StreamController<String> _incomingDestinationsController =
      StreamController<String>.broadcast();

  Stream<String> get incomingFiles => _incomingFilesController.stream;
  Stream<String> get incomingDestinations =>
      _incomingDestinationsController.stream;

  Future<NativePackageInfo> getPackageInfo(String packageName) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'getPackageInfo',
      <String, dynamic>{'packageName': packageName},
    );

    return NativePackageInfo(
      packageName: packageName,
      apkPath: result?['apkPath']?.toString(),
    );
  }

  Future<List<String>> getRequestedPermissions(String packageName) async {
    final result = await _channel.invokeListMethod<dynamic>(
      'getRequestedPermissions',
      <String, dynamic>{'packageName': packageName},
    );
    return (result ?? const <dynamic>[])
        .map((item) => item?.toString() ?? '')
        .where((item) => item.isNotEmpty)
        .toList();
  }

  Future<NativeDeviceInfo> getDeviceInfo() async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'getDeviceInfo',
    );
    return NativeDeviceInfo(
      sdkInt: (result?['sdkInt'] as num?)?.toInt() ?? 0,
      downloadsPath: result?['downloadsPath']?.toString(),
    );
  }

  Future<String?> consumePendingOpenFile() async {
    final result = await _channel.invokeMethod<String>(
      'consumePendingOpenFile',
    );
    if (result == null || result.isEmpty) {
      return null;
    }
    return result;
  }

  Future<String?> consumePendingDestination() async {
    final result = await _channel.invokeMethod<String>(
      'consumePendingDestination',
    );
    if (result == null || result.isEmpty) {
      return null;
    }
    return result;
  }

  Future<bool> openUninstallScreen(String packageName) async {
    final result = await _channel.invokeMethod<bool>(
      'openUninstallScreen',
      <String, dynamic>{'packageName': packageName},
    );
    return result ?? false;
  }

  Future<bool> openAppSettings(String packageName) async {
    final result = await _channel.invokeMethod<bool>(
      'openAppSettings',
      <String, dynamic>{'packageName': packageName},
    );
    return result ?? false;
  }

  Future<bool> canAuthenticateDevice() async {
    final result = await _channel.invokeMethod<bool>('canAuthenticateDevice');
    return result ?? false;
  }

  Future<bool> authenticateDevice({required String reason}) async {
    final result = await _channel.invokeMethod<bool>(
      'authenticateDevice',
      <String, dynamic>{'reason': reason},
    );
    return result ?? false;
  }

  Future<bool> showNotification({
    required String title,
    required String body,
  }) async {
    final result = await _channel.invokeMethod<bool>(
      'showNotification',
      <String, dynamic>{'title': title, 'body': body},
    );
    return result ?? false;
  }

  Future<void> _handleNativeCalls(MethodCall call) async {
    switch (call.method) {
      case 'incomingFileReady':
        final arguments = call.arguments;
        final path = switch (arguments) {
          Map<Object?, Object?> map => map['path']?.toString(),
          _ => null,
        };
        if (path != null &&
            path.isNotEmpty &&
            !_incomingFilesController.isClosed) {
          _incomingFilesController.add(path);
        }
        break;
      case 'destinationReady':
        final arguments = call.arguments;
        final destination = switch (arguments) {
          Map<Object?, Object?> map => map['destination']?.toString(),
          _ => null,
        };
        if (destination != null &&
            destination.isNotEmpty &&
            !_incomingDestinationsController.isClosed) {
          _incomingDestinationsController.add(destination);
        }
        break;
      default:
        break;
    }
  }

  Future<void> dispose() async {
    await _incomingFilesController.close();
    await _incomingDestinationsController.close();
    _channel.setMethodCallHandler(null);
  }
}
