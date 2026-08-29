import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

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
      final file = File(imagePath);
      try {
        // Prefer the file constructor. It avoids the path-only conversion path
        // that has produced native InputImage/ML Kit crashes on some Android ROMs.
        final result = await recognizer.processImage(InputImage.fromFile(file));
        return result.text;
      } on Object catch (error, stackTrace) {
        if (!Platform.isAndroid) rethrow;
        _logger.warning('ocr.file_input_failed_using_bitmap_fallback', {
          'script': script.name,
          'errorType': error.runtimeType.toString(),
        });
        _logger.error(
          'ocr.file_input_exception',
          error,
          stackTrace: stackTrace,
          data: {'script': script.name},
        );
        final bitmapInput = await _bitmapInput(file);
        final result = await recognizer.processImage(bitmapInput);
        return result.text;
      }
    } finally {
      await recognizer.close();
    }
  }

  Future<InputImage> _bitmapInput(File file) async {
    final encoded = await file.readAsBytes();
    if (encoded.isEmpty) throw const OcrException('image_file_empty');
    final codec = await ui.instantiateImageCodec(encoded);
    try {
      final frame = await codec.getNextFrame();
      try {
        final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (data == null) throw const OcrException('image_bitmap_conversion_failed');
        final Uint8List rgba = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        return InputImage.fromBitmap(
          bitmap: rgba,
          width: frame.image.width,
          height: frame.image.height,
          rotation: 0,
        );
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
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
