import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';

class PermissionResult {
  const PermissionResult({
    required this.allPermissions,
    required this.dangerousPermissions,
    required this.detectedCombos,
    required this.permissionScore,
  });

  final List<String> allPermissions;
  final List<DangerousPermission> dangerousPermissions;
  final List<String> detectedCombos;
  final int permissionScore;
}

class DangerousPermission {
  const DangerousPermission({
    required this.name,
    required this.score,
    required this.reason,
  });

  final String name;
  final int score;
  final String reason;
}

class PermissionAnalyzer {
  static const Map<String, int> permissionScores = {
    'android.permission.BIND_ACCESSIBILITY_SERVICE': 30,
    'android.permission.READ_SMS': 15,
    'android.permission.SEND_SMS': 15,
    'android.permission.RECEIVE_SMS': 10,
    'android.permission.READ_CALL_LOG': 10,
    'android.permission.PROCESS_OUTGOING_CALLS': 10,
    'android.permission.RECORD_AUDIO': 8,
    'android.permission.CAMERA': 5,
    'android.permission.READ_CONTACTS': 5,
    'android.permission.ACCESS_FINE_LOCATION': 5,
    'android.permission.RECEIVE_BOOT_COMPLETED': 5,
    'android.permission.FOREGROUND_SERVICE': 3,
    'android.permission.REQUEST_INSTALL_PACKAGES': 8,
  };

  static const Map<String, String> _permissionReasons = {
    'android.permission.BIND_ACCESSIBILITY_SERVICE':
        'Accessibility orqali foydalanuvchi harakatlarini boshqarishi mumkin',
    'android.permission.READ_SMS': 'SMS xabarlarni oqishi mumkin',
    'android.permission.SEND_SMS': 'SMS yuborishi mumkin',
    'android.permission.RECEIVE_SMS': 'Kelgan SMSlarni kuzatishi mumkin',
    'android.permission.READ_CALL_LOG': 'Qongiroq tarixini oqishi mumkin',
    'android.permission.PROCESS_OUTGOING_CALLS':
        'Chiquvchi qongiroqlarni boshqarishi mumkin',
    'android.permission.RECORD_AUDIO': 'Mikrofondan yozib olishi mumkin',
    'android.permission.CAMERA': 'Kameradan foydalanishi mumkin',
    'android.permission.READ_CONTACTS': 'Kontaktlarga kira oladi',
    'android.permission.ACCESS_FINE_LOCATION':
        'Aniq joylashuvni bilishi mumkin',
    'android.permission.RECEIVE_BOOT_COMPLETED':
        'Telefon yoqilganda avtomatik ishga tushishi mumkin',
    'android.permission.FOREGROUND_SERVICE':
        'Fon jarayonini uzoq vaqt faol ushlab turishi mumkin',
    'android.permission.REQUEST_INSTALL_PACKAGES':
        'Boshqa APKlarni ornatishga urinishi mumkin',
  };

  static String describePermission(String permission) {
    return _permissionReasons[permission] ?? 'Oddiy ruxsat';
  }

  Future<PermissionResult> analyze(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('APK topilmadi: $filePath');
    }

    final apkBytes = await file.readAsBytes();
    final payload = await compute(_analyzePermissionPayload, apkBytes);
    return _permissionResultFromPayload(payload);
  }

  PermissionResult _permissionResultFromPayload(Map<String, Object?> payload) {
    final dangerousPayload =
        (payload['dangerousPermissions'] as List<Object?>? ?? const [])
            .whereType<Map<Object?, Object?>>()
            .toList();

    return PermissionResult(
      allPermissions: (payload['allPermissions'] as List<Object?>? ?? const [])
          .whereType<String>()
          .toList(),
      dangerousPermissions: dangerousPayload
          .map(
            (item) => DangerousPermission(
              name: item['name']?.toString() ?? '',
              score: (item['score'] as num?)?.toInt() ?? 0,
              reason: item['reason']?.toString() ?? 'Xavfli ruxsat aniqlandi',
            ),
          )
          .toList(),
      detectedCombos: (payload['detectedCombos'] as List<Object?>? ?? const [])
          .whereType<String>()
          .toList(),
      permissionScore: (payload['permissionScore'] as num?)?.toInt() ?? 0,
    );
  }

  PermissionResult _analyzeBytes(Uint8List apkBytes) {
    final permissions = _extractPermissionsFromApk(apkBytes);
    final permissionSet = permissions.toSet();
    final dangerousPermissions = <DangerousPermission>[];
    var score = 0;
    final combos = <String>[];

    for (final permission in permissions) {
      final permissionScore = permissionScores[permission];
      if (permissionScore == null) continue;

      dangerousPermissions.add(
        DangerousPermission(
          name: permission,
          score: permissionScore,
          reason: describePermission(permission),
        ),
      );
      score += permissionScore;
    }

    if (_hasAll(permissionSet, const [
      'android.permission.READ_SMS',
      'android.permission.SEND_SMS',
    ])) {
      combos.add('Banking trojan pattern');
      score += 20;
    }

    if (_hasAll(permissionSet, const [
      'android.permission.BIND_ACCESSIBILITY_SERVICE',
      'android.permission.READ_SMS',
    ])) {
      combos.add('Spyware pattern');
      score += 25;
    }

    if (_hasAll(permissionSet, const [
      'android.permission.CAMERA',
      'android.permission.RECORD_AUDIO',
      'android.permission.ACCESS_FINE_LOCATION',
    ])) {
      combos.add('Surveillance pattern');
      score += 15;
    }

    if (_hasAll(permissionSet, const [
      'android.permission.REQUEST_INSTALL_PACKAGES',
      'android.permission.RECEIVE_BOOT_COMPLETED',
    ])) {
      combos.add('Dropper pattern');
      score += 10;
    }

    return PermissionResult(
      allPermissions: permissions,
      dangerousPermissions: dangerousPermissions,
      detectedCombos: combos,
      permissionScore: score,
    );
  }

  Future<PermissionResult> analyzeApk(String filePath) => analyze(filePath);

  bool _hasAll(Set<String> source, List<String> values) =>
      values.every(source.contains);

  List<String> _extractPermissionsFromApk(List<int> apkBytes) {
    final archive = ZipDecoder().decodeBytes(apkBytes);
    final manifest =
        archive.files.where((file) => !file.isDirectory).firstWhere(
              (file) => file.name == 'AndroidManifest.xml',
              orElse: () =>
                  throw Exception('APK ichida AndroidManifest.xml topilmadi'),
            );

    final manifestBytes = Uint8List.fromList(manifest.content);

    return _parseBinaryXml(manifestBytes);
  }

  List<String> _parseBinaryXml(Uint8List bytes) {
    if (bytes.length < 8) {
      throw Exception('AXML juda qisqa');
    }

    const magic = [0x03, 0x00, 0x08, 0x00];
    for (var index = 0; index < magic.length; index++) {
      if (bytes[index] != magic[index]) {
        throw Exception('AndroidManifest.xml binary AXML emas');
      }
    }

    final stringPoolOffset = 8;
    final chunkType = _readUint16(bytes, stringPoolOffset);
    if (chunkType != 0x0001) {
      throw Exception('AXML string pool chunk topilmadi');
    }

    final strings = _parseStringPool(bytes, stringPoolOffset);
    const prefix = 'android.permission.';
    return strings.where((value) => value.startsWith(prefix)).toSet().toList()
      ..sort();
  }

  List<String> _parseStringPool(Uint8List bytes, int offset) {
    final flags = _readUint32(bytes, offset + 16);
    final stringCount = _readUint32(bytes, offset + 8);
    final stringsStart = _readUint32(bytes, offset + 20);
    final isUtf8 = (flags & 0x00000100) != 0;
    final stringDataBase = offset + stringsStart;
    final strings = <String>[];

    for (var index = 0; index < stringCount; index++) {
      final stringOffset = _readUint32(bytes, offset + 28 + (index * 4));
      final absoluteOffset = stringDataBase + stringOffset;
      strings.add(
        isUtf8
            ? _readUtf8String(bytes, absoluteOffset)
            : _readUtf16String(bytes, absoluteOffset),
      );
    }

    return strings;
  }

  String _readUtf8String(Uint8List bytes, int offset) {
    final first = _readLength8(bytes, offset);
    var cursor = offset + first.bytesUsed;
    final second = _readLength8(bytes, cursor);
    cursor += second.bytesUsed;
    final length = second.value;
    final raw = bytes.sublist(cursor, cursor + length);
    return utf8.decode(raw, allowMalformed: true);
  }

  String _readUtf16String(Uint8List bytes, int offset) {
    final lengthInfo = _readLength16(bytes, offset);
    final cursor = offset + lengthInfo.bytesUsed;
    final byteLength = lengthInfo.value * 2;
    final raw = bytes.sublist(cursor, cursor + byteLength);
    final codeUnits = <int>[];

    for (var index = 0; index < raw.length; index += 2) {
      codeUnits.add(raw[index] | (raw[index + 1] << 8));
    }

    return String.fromCharCodes(codeUnits);
  }

  _LengthInfo _readLength8(Uint8List bytes, int offset) {
    final first = bytes[offset];
    if ((first & 0x80) == 0) {
      return _LengthInfo(first, 1);
    }

    final second = bytes[offset + 1];
    return _LengthInfo(((first & 0x7F) << 8) | second, 2);
  }

  _LengthInfo _readLength16(Uint8List bytes, int offset) {
    final first = _readUint16(bytes, offset);
    if ((first & 0x8000) == 0) {
      return _LengthInfo(first, 2);
    }

    final second = _readUint16(bytes, offset + 2);
    return _LengthInfo(((first & 0x7FFF) << 16) | second, 4);
  }

  int _readUint16(Uint8List bytes, int offset) {
    final data = ByteData.sublistView(bytes, offset, offset + 2);
    return data.getUint16(0, Endian.little);
  }

  int _readUint32(Uint8List bytes, int offset) {
    final data = ByteData.sublistView(bytes, offset, offset + 4);
    return data.getUint32(0, Endian.little);
  }
}

class _LengthInfo {
  const _LengthInfo(this.value, this.bytesUsed);

  final int value;
  final int bytesUsed;
}

Map<String, Object?> _analyzePermissionPayload(Uint8List apkBytes) {
  final analyzer = PermissionAnalyzer();
  final result = analyzer._analyzeBytes(apkBytes);

  return <String, Object?>{
    'allPermissions': result.allPermissions,
    'dangerousPermissions': result.dangerousPermissions
        .map(
          (permission) => <String, Object?>{
            'name': permission.name,
            'score': permission.score,
            'reason': permission.reason,
          },
        )
        .toList(),
    'detectedCombos': result.detectedCombos,
    'permissionScore': result.permissionScore,
  };
}
