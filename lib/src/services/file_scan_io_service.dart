import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

class FileScanIoResult {
  const FileScanIoResult({
    required this.verdict,
    required this.threatLevel,
    required this.wasFound,
    required this.fsioScore,
    this.malwareName,
    this.iocs = const [],
    this.note,
  });

  /// MALICIOUS | NO_THREAT | BENIGN | UNKNOWN
  final String verdict;

  /// 0.0 – 1.0
  final double threatLevel;
  final bool wasFound;
  final int fsioScore;
  final String? malwareName;
  final List<String> iocs;
  final String? note;

  bool get hasThreat => verdict == 'MALICIOUS';

  static const FileScanIoResult empty = FileScanIoResult(
    verdict: 'UNKNOWN',
    threatLevel: 0,
    wasFound: false,
    fsioScore: 0,
    note: 'FileScan.io tekshiruvi bajarilmadi.',
  );
}

class FileScanIoService {
  FileScanIoService({required this.apiKey, Dio? dio})
    : _dio = dio ??
          Dio(
            BaseOptions(
              baseUrl: 'https://www.filescan.io',
              connectTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(seconds: 30),
            ),
          );

  final String apiKey;
  final Dio _dio;

  static const int _maxPollAttempts = 8;
  // Progressively longer delays: 3s, 5s, 8s, then 10s for remaining attempts.
  static const List<Duration> _pollDelays = [
    Duration(seconds: 3),
    Duration(seconds: 5),
    Duration(seconds: 8),
    Duration(seconds: 10),
  ];

  Map<String, String> get _headers =>
      apiKey.isNotEmpty ? {'X-Api-Key': apiKey} : {};

  /// Hash orqali tezkor tekshiruv — fayl yuklanmaydi.
  Future<FileScanIoResult?> checkReputation(String sha256) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/reputation/hash',
        queryParameters: {'sha256': sha256},
        options: Options(headers: _headers),
      );
      final data = response.data;
      if (data == null) return null;

      final verdict = data['verdict']?.toString() ?? 'UNKNOWN';
      if (verdict == 'UNKNOWN') return null;

      final threatLevel = (data['threatLevel'] as num?)?.toDouble() ?? 0.0;
      final detections = data['detections'] as Map<String, dynamic>? ?? {};
      final malwareName = _topDetection(detections);
      final score = _scoreFromVerdict(verdict, threatLevel);

      return FileScanIoResult(
        verdict: verdict,
        threatLevel: threatLevel,
        wasFound: true,
        fsioScore: score,
        malwareName: malwareName,
        note: _noteFromVerdict(verdict, malwareName),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404 || e.response?.statusCode == 404) {
        return null;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Faylni yuklab, to'liq tahlil qiladi. flow_id qaytaradi.
  Future<String> uploadFile(String filePath) async {
    final file = File(filePath);
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        filePath,
        filename: file.uri.pathSegments.last,
      ),
      'rapid_mode': 'true',
    });

    final response = await _dio.post<Map<String, dynamic>>(
      '/api/scan/file',
      data: formData,
      options: Options(headers: _headers),
    );

    final flowId = response.data?['flow_id']?.toString();
    if (flowId == null || flowId.isEmpty) {
      throw Exception('FileScan.io flow_id qaytmadi');
    }
    return flowId;
  }

  /// flow_id bo'yicha natijani kutib oladi (polling).
  Future<FileScanIoResult> pollReport(String flowId) async {
    for (var attempt = 0; attempt < _maxPollAttempts; attempt++) {
      final delay = attempt < _pollDelays.length
          ? _pollDelays[attempt]
          : _pollDelays.last;
      await Future<void>.delayed(delay);

      try {
        final response = await _dio.get<Map<String, dynamic>>(
          '/api/scan/$flowId/report',
          queryParameters: {'filter': 'general,allSignalGroups'},
          options: Options(headers: _headers),
        );

        final data = response.data;
        if (data == null) continue;

        final verdictBlock =
            data['finalVerdict'] as Map<String, dynamic>? ?? {};
        final verdict = verdictBlock['verdict']?.toString() ?? '';

        if (verdict.isEmpty) continue;

        final threatLevel =
            (verdictBlock['threatLevel'] as num?)?.toDouble() ?? 0.0;

        final iocs = _extractIocs(data);
        final malwareName = _extractMalwareName(data);
        final score = _scoreFromVerdict(verdict, threatLevel);

        return FileScanIoResult(
          verdict: verdict,
          threatLevel: threatLevel,
          wasFound: true,
          fsioScore: score,
          malwareName: malwareName,
          iocs: iocs,
          note: _noteFromVerdict(verdict, malwareName),
        );
      } on DioException {
        continue;
      }
    }

    return const FileScanIoResult(
      verdict: 'UNKNOWN',
      threatLevel: 0,
      wasFound: false,
      fsioScore: 0,
      note: 'FileScan.io tahlili vaqtida tugamadi.',
    );
  }

  /// Hash tekshiruvi → topilmasa fayl yuklab tahlil qiladi.
  Future<FileScanIoResult> scanFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return FileScanIoResult.empty;

      final sha256Hash = await _sha256Of(filePath);

      final reputation = await checkReputation(sha256Hash);
      if (reputation != null) return reputation;

      final flowId = await uploadFile(filePath);
      return await pollReport(flowId);
    } catch (e) {
      return FileScanIoResult(
        verdict: 'UNKNOWN',
        threatLevel: 0,
        wasFound: false,
        fsioScore: 0,
        note: 'FileScan.io xatosi: $e',
      );
    }
  }

  Future<String> _sha256Of(String path) async {
    Digest? result;
    final sink = sha256.startChunkedConversion(
      _DigestSink((d) => result = d),
    );
    await for (final chunk in File(path).openRead()) {
      sink.add(chunk);
    }
    sink.close();
    return result!.toString();
  }

  int _scoreFromVerdict(String verdict, double threatLevel) {
    return switch (verdict) {
      'MALICIOUS' => (30 + (threatLevel * 20).round()).clamp(30, 50),
      'NO_THREAT' => 0,
      'BENIGN' => 0,
      _ => 0,
    };
  }

  String? _noteFromVerdict(String verdict, String? malwareName) {
    return switch (verdict) {
      'MALICIOUS' => malwareName != null
          ? 'FileScan.io "$malwareName" zararli dasturini aniqladi'
          : 'FileScan.io faylni zararli deb baholadi',
      'NO_THREAT' => 'FileScan.io xavf topilmadi',
      'BENIGN' => 'FileScan.io faylni xavfsiz deb baholadi',
      _ => null,
    };
  }

  String? _topDetection(Map<String, dynamic> detections) {
    if (detections.isEmpty) return null;
    final labels = detections.values
        .whereType<String>()
        .where((v) => v.isNotEmpty)
        .toList();
    if (labels.isEmpty) return null;
    final freq = <String, int>{};
    for (final l in labels) {
      freq[l] = (freq[l] ?? 0) + 1;
    }
    return (freq.entries.toList()..sort((a, b) => b.value - a.value))
        .first
        .key;
  }

  List<String> _extractIocs(Map<String, dynamic> data) {
    final iocs = <String>[];
    final reports = data['reports'] as Map<String, dynamic>? ?? {};
    for (final report in reports.values) {
      if (report is! Map<String, dynamic>) continue;
      final iocBlock = report['iocs'] as Map<String, dynamic>? ?? {};
      for (final key in ['domains', 'urls', 'ips']) {
        final list = iocBlock[key];
        if (list is List) {
          iocs.addAll(list.whereType<String>().take(5));
        }
      }
    }
    return iocs.toSet().take(10).toList();
  }

  String? _extractMalwareName(Map<String, dynamic> data) {
    final reports = data['reports'] as Map<String, dynamic>? ?? {};
    for (final report in reports.values) {
      if (report is! Map<String, dynamic>) continue;
      final signals =
          report['allSignalGroups'] as Map<String, dynamic>? ?? {};
      for (final group in signals.values) {
        if (group is! Map<String, dynamic>) continue;
        final name = group['malwareName']?.toString() ??
            group['name']?.toString();
        if (name != null && name.isNotEmpty) return name;
      }
    }
    return null;
  }

  void dispose() => _dio.close();
}

class _DigestSink implements Sink<Digest> {
  _DigestSink(this._onDigest);
  final void Function(Digest) _onDigest;
  @override
  void add(Digest data) => _onDigest(data);
  @override
  void close() {}
}
