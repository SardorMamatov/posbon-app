import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class VirusTotalResult {
  const VirusTotalResult({
    required this.wasFound,
    required this.maliciousCount,
    required this.suspiciousCount,
    required this.totalEngines,
    this.detectedAs,
    this.note,
    required this.vtScore,
  });

  final bool wasFound;
  final int maliciousCount;
  final int suspiciousCount;
  final int totalEngines;
  final String? detectedAs;
  final String? note;
  final int vtScore;

  int get detectedCount => maliciousCount + suspiciousCount;

  bool get hasThreat => detectedCount > 0;
}

class VirusTotalLookupResult {
  const VirusTotalLookupResult({
    required this.found,
    required this.totalDetections,
    this.detectedAs,
    this.note,
  });

  final bool found;
  final int totalDetections;
  final String? detectedAs;
  final String? note;
}

class VirusTotalRateLimitException implements Exception {
  const VirusTotalRateLimitException({required this.retryAfterSeconds});

  final int retryAfterSeconds;

  @override
  String toString() =>
      'VirusTotal so\'rov limiti sababli $retryAfterSeconds soniya kutish kerak.';
}

class VirusTotalService {
  VirusTotalService({
    required this.apiKey,
    Dio? dio,
  }) : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: 'https://www.virustotal.com/api/v3',
                headers: <String, String>{'x-apikey': apiKey},
              ),
            );

  final String apiKey;
  final Dio _dio;
  final Queue<_QueuedRequest<dynamic>> _queue =
      Queue<_QueuedRequest<dynamic>>();
  final ValueNotifier<int> waitSecondsNotifier = ValueNotifier<int>(0);
  bool _processing = false;
  DateTime? _lastRequestAt;
  Timer? _waitTimer;

  static const Duration requestInterval = Duration(seconds: 15);
  static const int maxInlineUploadBytes = 32 * 1024 * 1024;

  int get remainingWaitSeconds => waitSecondsNotifier.value;

  Future<VirusTotalResult> checkByHash(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('Fayl topilmadi: $filePath');
    }

    final hash = sha256.convert(await file.readAsBytes()).toString();

    try {
      final response = await _enqueue(
        () => _dio.get<Map<String, dynamic>>('/files/$hash'),
      );
      return _parseFileResult(
        response.data ?? const <String, dynamic>{},
        wasFound: true,
      );
    } on DioException catch (error) {
      if (error.response?.statusCode != 404) {
        rethrow;
      }
    }

    final fileSize = await file.length();
    if (fileSize > maxInlineUploadBytes) {
      return const VirusTotalResult(
        wasFound: false,
        maliciousCount: 0,
        suspiciousCount: 0,
        totalEngines: 0,
        note:
            'VirusTotal bepul limitidan katta fayl. Lokal tahlil natijasi korsatildi.',
        vtScore: 0,
      );
    }

    try {
      final analysisId = await uploadFile(filePath);
      final uploaded = await pollAnalysis(analysisId);

      return VirusTotalResult(
        wasFound: false,
        maliciousCount: uploaded.maliciousCount,
        suspiciousCount: uploaded.suspiciousCount,
        totalEngines: uploaded.totalEngines,
        detectedAs: uploaded.detectedAs,
        note: uploaded.note,
        vtScore: uploaded.vtScore,
      );
    } on DioException catch (error) {
      if (error.response?.statusCode == 413) {
        return const VirusTotalResult(
          wasFound: false,
          maliciousCount: 0,
          suspiciousCount: 0,
          totalEngines: 0,
          note:
              'Fayl hajmi katta bolgani uchun VirusTotal uni qabul qilmadi. Lokal tahlil natijasi ishlatildi.',
          vtScore: 0,
        );
      }
      rethrow;
    }
  }

  Future<String> uploadFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('Fayl topilmadi: $filePath');
    }

    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        filePath,
        filename: file.uri.pathSegments.last,
      ),
    });

    final response = await _enqueue(
      () => _dio.post<Map<String, dynamic>>('/files', data: formData),
    );

    final data = response.data?['data'] as Map<String, dynamic>? ?? {};
    final analysisId = data['id']?.toString();
    if (analysisId == null || analysisId.isEmpty) {
      throw Exception('VirusTotal analysis id qaytmadi');
    }

    return analysisId;
  }

  Future<VirusTotalResult> pollAnalysis(String analysisId) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      final response = await _enqueue(
        () => _dio.get<Map<String, dynamic>>('/analyses/$analysisId'),
      );

      final payload = response.data ?? const <String, dynamic>{};
      final data = payload['data'] as Map<String, dynamic>? ?? {};
      final attributes = data['attributes'] as Map<String, dynamic>? ?? {};
      final status = attributes['status']?.toString();

      if (status == 'completed') {
        return _parseAnalysisResult(payload);
      }
    }

    throw Exception('VirusTotal javobi kutilgan vaqt ichida tugamadi');
  }

  Future<VirusTotalLookupResult> fetchFileReport(String hash) async {
    try {
      final response = await _enqueue(
        () => _dio.get<Map<String, dynamic>>('/files/$hash'),
      );
      final parsed = _parseFileResult(
        response.data ?? const <String, dynamic>{},
        wasFound: true,
      );
      return VirusTotalLookupResult(
        found: true,
        totalDetections: parsed.detectedCount,
        detectedAs: parsed.detectedAs,
        note: parsed.note,
      );
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) {
        return const VirusTotalLookupResult(
          found: false,
          totalDetections: 0,
        );
      }
      rethrow;
    }
  }

  Future<VirusTotalLookupResult> uploadAndScanLegacy(String filePath) async {
    final result = await checkByHash(filePath);
    return VirusTotalLookupResult(
      found: result.wasFound,
      totalDetections: result.detectedCount,
      detectedAs: result.detectedAs,
      note: result.note,
    );
  }

  Future<T> _enqueue<T>(Future<T> Function() request) {
    final completer = Completer<T>();
    _queue.add(_QueuedRequest<T>(request: request, completer: completer));
    if (!_processing) {
      unawaited(_processQueue());
    }
    return completer.future;
  }

  Future<void> _processQueue() async {
    _processing = true;
    while (_queue.isNotEmpty) {
      final wait = _remainingWait();
      if (wait > Duration.zero) {
        _startCountdown(wait);
        await Future<void>.delayed(wait);
      }

      _waitTimer?.cancel();
      waitSecondsNotifier.value = 0;

      final queued = _queue.removeFirst();
      try {
        final result = await queued.request();
        _lastRequestAt = DateTime.now();
        queued.completer.complete(result);
      } on DioException catch (error, stackTrace) {
        _lastRequestAt = DateTime.now();
        if (error.response?.statusCode == 429) {
          final retryHeader = error.response?.headers.value('Retry-After');
          final retryAfterSeconds = int.tryParse(retryHeader ?? '') ??
              remainingWaitSeconds.clamp(1, requestInterval.inSeconds).toInt();
          queued.completer.completeError(
            VirusTotalRateLimitException(
              retryAfterSeconds: retryAfterSeconds,
            ),
            stackTrace,
          );
          continue;
        }
        queued.completer.completeError(error, stackTrace);
      } catch (error, stackTrace) {
        _lastRequestAt = DateTime.now();
        queued.completer.completeError(error, stackTrace);
      }
    }

    _processing = false;
  }

  Duration _remainingWait() {
    final lastRequestAt = _lastRequestAt;
    if (lastRequestAt == null) return Duration.zero;
    final elapsed = DateTime.now().difference(lastRequestAt);
    final remaining = requestInterval - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  void _startCountdown(Duration duration) {
    _waitTimer?.cancel();
    waitSecondsNotifier.value = duration.inSeconds.ceil();
    _waitTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final next = waitSecondsNotifier.value - 1;
      if (next <= 0) {
        waitSecondsNotifier.value = 0;
        timer.cancel();
      } else {
        waitSecondsNotifier.value = next;
      }
    });
  }

  VirusTotalResult _parseFileResult(
    Map<String, dynamic> payload, {
    required bool wasFound,
  }) {
    final data = payload['data'] as Map<String, dynamic>? ?? {};
    final attributes = data['attributes'] as Map<String, dynamic>? ?? {};
    final stats = attributes['last_analysis_stats'] as Map<String, dynamic>? ??
        const <String, dynamic>{};
    final analysisResults =
        attributes['last_analysis_results'] as Map<String, dynamic>? ??
            const <String, dynamic>{};

    final malicious = (stats['malicious'] as num?)?.toInt() ?? 0;
    final suspicious = (stats['suspicious'] as num?)?.toInt() ?? 0;
    final totalEngines = _totalEngines(stats);
    final threatLabel = _extractThreatLabel(analysisResults);

    return VirusTotalResult(
      wasFound: wasFound,
      maliciousCount: malicious,
      suspiciousCount: suspicious,
      totalEngines: totalEngines,
      detectedAs: threatLabel ?? attributes['meaningful_name']?.toString(),
      note: _noteForDetectionState(
        detectedCount: malicious + suspicious,
        totalEngines: totalEngines,
      ),
      vtScore: ((malicious * 10) + (suspicious * 3)).clamp(0, 60),
    );
  }

  VirusTotalResult _parseAnalysisResult(Map<String, dynamic> payload) {
    final data = payload['data'] as Map<String, dynamic>? ?? {};
    final attributes = data['attributes'] as Map<String, dynamic>? ?? {};
    final stats = attributes['stats'] as Map<String, dynamic>? ??
        const <String, dynamic>{};
    final results = attributes['results'] as Map<String, dynamic>? ??
        const <String, dynamic>{};

    final malicious = (stats['malicious'] as num?)?.toInt() ?? 0;
    final suspicious = (stats['suspicious'] as num?)?.toInt() ?? 0;
    final totalEngines = _totalEngines(stats);
    final threatLabel = _extractThreatLabel(results);

    return VirusTotalResult(
      wasFound: true,
      maliciousCount: malicious,
      suspiciousCount: suspicious,
      totalEngines: totalEngines,
      detectedAs: threatLabel,
      note: _noteForDetectionState(
        detectedCount: malicious + suspicious,
        totalEngines: totalEngines,
      ),
      vtScore: ((malicious * 10) + (suspicious * 3)).clamp(0, 60),
    );
  }

  int _totalEngines(Map<String, dynamic> stats) {
    return stats.values
        .whereType<num>()
        .fold<int>(0, (sum, value) => sum + value.toInt());
  }

  String? _extractThreatLabel(Map<String, dynamic> results) {
    final labels = <String, int>{};

    for (final value in results.values) {
      if (value is! Map) continue;
      final category = value['category']?.toString().toLowerCase();
      if (category != 'malicious' && category != 'suspicious') {
        continue;
      }

      final label = value['result']?.toString().trim();
      if (label == null || label.isEmpty) continue;
      labels.update(label, (count) => count + 1, ifAbsent: () => 1);
    }

    if (labels.isEmpty) return null;
    final sorted = labels.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.first.key;
  }

  String? _noteForDetectionState({
    required int detectedCount,
    required int totalEngines,
  }) {
    if (detectedCount > 0) {
      return null;
    }
    if (totalEngines > 0) {
      return 'VirusTotal zararli belgi topmadi.';
    }
    return null;
  }

  void dispose() {
    _waitTimer?.cancel();
    waitSecondsNotifier.dispose();
    _dio.close();
  }
}

class _QueuedRequest<T> {
  const _QueuedRequest({
    required this.request,
    required this.completer,
  });

  final Future<T> Function() request;
  final Completer<T> completer;
}
