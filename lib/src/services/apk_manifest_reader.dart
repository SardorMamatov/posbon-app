import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';

/// Top-level function passed to [compute] — reads only AndroidManifest.xml
/// from the APK (which is a ZIP file) and returns its raw bytes.
///
/// Keeping archive imports isolated here prevents IDE "organize imports"
/// from stripping the dependency in permission_analyzer.dart.
Uint8List readManifestBytesFromApk(String filePath) {
  final bytes = File(filePath).readAsBytesSync();
  final archive = ZipDecoder().decodeBytes(bytes);
  final entry = archive.findFile('AndroidManifest.xml');
  if (entry == null) {
    throw Exception('APK ichida AndroidManifest.xml topilmadi');
  }
  return Uint8List.fromList(entry.content as List<int>);
}
