import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'app_logger.dart';
import 'models.dart';

class OcrService {
  OcrService({AppLogger? logger}) : _logger = logger ?? AppLogger.instance;

  final AppLogger _logger;

  Future<String> recognize(
    String imagePath,
    InterfaceLanguage interfaceLanguage,
  ) async {
    final file = File(imagePath);
    if (!await file.exists()) throw const OcrException('image_file_missing');
    final length = await file.length();
    if (length == 0) throw const OcrException('image_file_empty');

    // Source code is usually Latin/ASCII, but comments and identifiers can be
    // Chinese regardless of the application's interface language. Try the
    // likely script first, then use the bundled second recognizer as fallback.
    final scripts = interfaceLanguage == InterfaceLanguage.zh
        ? const [TextRecognitionScript.chinese, TextRecognitionScript.latin]
        : const [TextRecognitionScript.latin, TextRecognitionScript.chinese];
    final errors = <String>[];

    for (final script in scripts) {
      final stopwatch = Stopwatch()..start();
      try {
        final result = _normalizeCode(
          await _recognizeWithScript(imagePath, script),
        );
        _logger.info('ocr.script_completed', {
          'script': script.name,
          'durationMs': stopwatch.elapsedMilliseconds,
          'imageBytes': length,
          'recognizedCharacters': result.length,
        });
        if (result.isNotEmpty) return result;
      } on Object catch (error, stackTrace) {
        errors.add('${script.name}:${error.runtimeType}');
        _logger.error(
          'ocr.script_failed',
          error,
          stackTrace: stackTrace,
          data: {
            'script': script.name,
            'durationMs': stopwatch.elapsedMilliseconds,
            'imageBytes': length,
          },
        );
      }
    }

    if (errors.isNotEmpty) {
      throw OcrException('mlkit_recognition_failed: ${errors.join(',')}');
    }
    throw const OcrException('ocr_no_text_detected');
  }

  Future<String> _recognizeWithScript(
    String imagePath,
    TextRecognitionScript script,
  ) async {
    final recognizer = TextRecognizer(script: script);
    try {
      final image = InputImage.fromFilePath(imagePath);
      final result = await recognizer.processImage(image);
      return result.text;
    } finally {
      await recognizer.close();
    }
  }

  String _normalizeCode(String value) {
    final normalized = value
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll('\u00A0', ' ');
    return normalized
        .split('\n')
        .map(
          (line) => line.replaceFirst(
            RegExp(r'^\s*\d{1,5}\s+[│|]?\s*'),
            '',
          ),
        )
        .join('\n')
        .trim();
  }
}

class OcrException implements Exception {
  const OcrException(this.message);
  final String message;
  @override
  String toString() => message;
}
