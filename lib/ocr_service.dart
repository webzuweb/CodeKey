import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'models.dart';

class OcrService {
  Future<String> recognize(String imagePath, InterfaceLanguage language) async {
    final script = language == InterfaceLanguage.zh
        ? TextRecognitionScript.chinese
        : TextRecognitionScript.latin;
    final recognizer = TextRecognizer(script: script);
    try {
      final image = InputImage.fromFilePath(imagePath);
      final result = await recognizer.processImage(image);
      return _normalizeCode(result.text);
    } finally {
      await recognizer.close();
    }
  }

  String _normalizeCode(String value) {
    final normalized = value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    return normalized
        .split('\n')
        .map((line) => line.replaceFirst(RegExp(r'^\s*\d{1,5}\s+[│|]?\s*'), ''))
        .join('\n')
        .trim();
  }
}
