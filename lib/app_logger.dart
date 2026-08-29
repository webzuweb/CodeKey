import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class AppLogger {
  AppLogger._();

  static final AppLogger instance = AppLogger._();

  static const _maxFileBytes = 1024 * 1024;
  static const _maxArchives = 3;
  static const _fileName = 'codekey.log.jsonl';

  Directory? _directory;
  File? _file;
  Future<void> _queue = Future<void>.value();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    final support = await getApplicationSupportDirectory();
    _directory = Directory('${support.path}${Platform.pathSeparator}diagnostics');
    await _directory!.create(recursive: true);
    _file = File('${_directory!.path}${Platform.pathSeparator}$_fileName');
    _initialized = true;
    info('app.logger_initialized', {
      'platform': Platform.operatingSystem,
      'platformVersion': Platform.operatingSystemVersion,
      'appVersion': '0.3.0+3',
    });
  }

  void debug(String event, [Map<String, Object?> data = const {}]) =>
      _enqueue('debug', event, data);

  void info(String event, [Map<String, Object?> data = const {}]) =>
      _enqueue('info', event, data);

  void warning(String event, [Map<String, Object?> data = const {}]) =>
      _enqueue('warning', event, data);

  void error(
    String event,
    Object error, {
    StackTrace? stackTrace,
    Map<String, Object?> data = const {},
  }) {
    _enqueue('error', event, {
      ...data,
      'errorType': error.runtimeType.toString(),
      'error': _sanitizeString(error.toString()),
      if (stackTrace != null) 'stackTrace': _sanitizeString(stackTrace.toString()),
    });
  }

  void _enqueue(String level, String event, Map<String, Object?> data) {
    _queue = _queue.then((_) async {
      try {
        if (!_initialized) await initialize();
        await _rotateIfNeeded();
        final entry = <String, Object?>{
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'level': level,
          'event': event,
          'data': _sanitizeMap(data),
        };
        await _file!.writeAsString(
          '${jsonEncode(entry)}\n',
          mode: FileMode.append,
          flush: level == 'error',
        );
      } on Object {
        // Diagnostics must never crash the application.
      }
    });
  }

  Future<void> flush() => _queue;

  Future<void> clear() async {
    await flush();
    if (!_initialized) await initialize();
    final directory = _directory!;
    if (await directory.exists()) {
      await for (final entity in directory.list()) {
        if (entity is File && entity.path.contains('codekey')) {
          try {
            await entity.delete();
          } on FileSystemException {
            // Ignore files already removed by the operating system.
          }
        }
      }
    }
    _file = File('${directory.path}${Platform.pathSeparator}$_fileName');
    info('app.logs_cleared');
  }

  Future<File> exportDiagnostics({
    Map<String, Object?> metadata = const {},
  }) async {
    await flush();
    if (!_initialized) await initialize();
    final temp = await getTemporaryDirectory();
    final stamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final export = File(
      '${temp.path}${Platform.pathSeparator}CodeKey-diagnostics-$stamp.jsonl',
    );
    final sink = export.openWrite();
    sink.writeln(jsonEncode({
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'level': 'info',
      'event': 'diagnostics.export_header',
      'data': _sanitizeMap({
        'appVersion': '0.3.0+3',
        'platform': Platform.operatingSystem,
        'platformVersion': Platform.operatingSystemVersion,
        ...metadata,
      }),
    }));

    final files = await _logFilesOldestFirst();
    for (final file in files) {
      if (!await file.exists()) continue;
      await sink.addStream(file.openRead());
    }
    await sink.flush();
    await sink.close();
    info('diagnostics.exported', {'bytes': await export.length()});
    return export;
  }

  Future<List<File>> _logFilesOldestFirst() async {
    final directory = _directory!;
    final files = <File>[];
    if (!await directory.exists()) return files;
    await for (final entity in directory.list()) {
      if (entity is File && entity.path.contains('codekey.log')) files.add(entity);
    }
    int generation(File file) {
      final name = file.uri.pathSegments.last;
      if (name == _fileName) return 0;
      final match = RegExp(r'\.(\d+)$').firstMatch(name);
      return int.tryParse(match?.group(1) ?? '') ?? 0;
    }

    // Rotation uses .3 as the oldest and the base file as the newest.
    files.sort((a, b) => generation(b).compareTo(generation(a)));
    return files;
  }

  Future<void> _rotateIfNeeded() async {
    final file = _file!;
    if (!await file.exists()) return;
    if (await file.length() < _maxFileBytes) return;

    for (var index = _maxArchives; index >= 1; index--) {
      final source = index == 1
          ? file
          : File('${_directory!.path}${Platform.pathSeparator}$_fileName.${index - 1}');
      final destination = File(
        '${_directory!.path}${Platform.pathSeparator}$_fileName.$index',
      );
      if (index == _maxArchives && await destination.exists()) {
        await destination.delete();
      }
      if (await source.exists()) {
        await source.rename(destination.path);
      }
    }
    _file = File('${_directory!.path}${Platform.pathSeparator}$_fileName');
  }

  Map<String, Object?> _sanitizeMap(Map<String, Object?> data) {
    final output = <String, Object?>{};
    for (final entry in data.entries) {
      output[entry.key] = _sanitizeValue(entry.key, entry.value);
    }
    return output;
  }

  Object? _sanitizeValue(String key, Object? value) {
    final normalizedKey = key.toLowerCase();
    const sensitiveFragments = <String>[
      'apikey',
      'api_key',
      'authorization',
      'bearer',
      'password',
      'secret',
      'setupkey',
      'setup_key',
      'proof',
      'token',
      'privatekey',
      'private_key',
      'requesttext',
      'codetext',
      'ocrtext',
    ];
    if (sensitiveFragments.any(normalizedKey.contains)) return '<redacted>';
    if (value is String) return _sanitizeString(value);
    if (value is num || value is bool || value == null) return value;
    if (value is Enum) return value.name;
    if (value is Map) {
      return _sanitizeMap(
        value.map((key, value) => MapEntry(key.toString(), value)),
      );
    }
    if (value is Iterable) {
      return value.map((item) => _sanitizeValue(key, item)).toList(growable: false);
    }
    return _sanitizeString(value.toString());
  }

  String _sanitizeString(String value) {
    var sanitized = value;
    sanitized = sanitized.replaceAll(
      RegExp(r'-----BEGIN[\s\S]*?PRIVATE KEY-----[\s\S]*?-----END[\s\S]*?PRIVATE KEY-----', caseSensitive: false),
      '<private-key-redacted>',
    );
    sanitized = sanitized.replaceAll(
      RegExp(r'\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b'),
      '<jwt-redacted>',
    );
    sanitized = sanitized.replaceAll(
      RegExp(r'(authorization\s*[:=]\s*bearer\s+)[^\s,;]+', caseSensitive: false),
      r'$1<redacted>',
    );
    sanitized = sanitized.replaceAll(
      RegExp(r'''(api[_-]?key|token|secret|password|setup[_-]?key)\s*[:=]\s*["']?[^\s,"']+''', caseSensitive: false),
      '<credential-redacted>',
    );
    const maxLength = 4000;
    return sanitized.length <= maxLength
        ? sanitized
        : '${sanitized.substring(0, maxLength)}…<truncated>';
  }
}
